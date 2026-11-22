-- GryMod minimap: module preload (the pure part). The list of the tiles to prepare in advance, so that the radar does not wait for the player to get somewhere
-- before making the tiles of the place.
--   * Definitions(k, ranges, start): the definitions (pixels per metre, a level of the automatic pyramid) the radar can reach from the zoom ranges: the level in use
--     plus the level of each range (shared ranges count once). The rule keeps the level in use while the density stays within 0.6 to 1.6 times it, so a range
--     may show the level in use instead of its own, but never a level that is not in that list. k is the radar's pixels per metre times the screen's
--     pixels per radar pixel: the density at a range r (metres) is k / r.
--   * NewJob(boxes, opts): the tiles that cover the OUTDOOR boxes of the in/out map, at those definitions, for the open level of each place. It is a job, done in
--     steps of a few boxes (the up ray of each place is the cost, and a map has thousands of boxes: a step is made in one frame, never all at once).
-- Nothing here touches the engine: the up ray (Floors.OpenAt), the tile size (Cache.TileUnits) and the cache's Has are given in `opts`, so the tests give their own.
-- The driver that runs the job and hands its tiles to the generator is another file part (see the end of this file once it exists).

GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}

local Preload = GryMod.Minimap.Preload or {}
GryMod.Minimap.Preload = Preload

local CELL = 128 -- units: the cells of the in/out map
local HALF_BAND = 64 -- a layer is a band of 128 units around layer * 128
local SUBDIV = 3 -- a box is cut in at most SUBDIV x SUBDIV areas, each asks its own up ray
local OUTDOOR = 1
local INDOOR = 2

Preload.MAX_TILES = 4000 -- a plan keeps the nearest tiles when there are more

local mathFloor = math.floor
local mathMin = math.min

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- Definitions

-- The levels of the pyramid reachable from the zoom ranges `ranges` (metres) at the screen constant `k`, sorted. `start` is the level in use (kept in the list
-- when it is a level of the pyramid: the radar draws it under the new one while that is made). No constant or no range gives {}.
function Preload.Definitions(k, ranges, start)
	local Settings = GryMod.Minimap and GryMod.Minimap.Settings
	local list = {}

	if type(k) ~= "number" or k ~= k or k <= 0 or type(ranges) ~= "table" or #ranges == 0 or not Settings or not Settings.AutoDefinitionFor then
		return list
	end

	local isLevel = {}

	for _, level in ipairs(Settings.AUTO_LEVELS or {}) do
		isLevel[level] = true
	end

	local seen = {}

	local function add(level)
		if isLevel[level] and not seen[level] then
			seen[level] = true
			list[#list + 1] = level

			return true
		end

		return false
	end

	add(start)

	for _, range in ipairs(ranges) do
		if type(range) == "number" and range > 0 then
			add(Settings.AutoDefinitionFor(k / range, nil))
		end
	end

	-- No closure over the rule's hysteresis is needed: from a level in use the rule answers that level (already in the list) or the fresh level of the range
	-- (also in the list), so the levels the radar can ever use are the level in use plus one fresh level per range (checked by trying every triple of ranges
	-- from 5 to 100 m at three starting levels: the closure never found one more).
	table.sort(list)

	return list
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- The job

-- a box as the in/out map gives it, in a list or with names
local function field(box, name, at)
	local value = box[name]

	if value == nil then
		value = box[at]
	end

	return type(value) == "number" and value or 0
end

local function byDistance(a, b)
	return a.d < b.d
end

-- NewJob(boxes, opts) -> job. boxes = the boxes of the in/out map ({layer, x1, y1, x2, y2, state, ceil}, cells of 128 units); opts = {
--   definitions = {ppm, ...}, res = tile size in pixels, tileUnits = function(res, ppm) -> edge of a tile in units,
--   levelAt = function(x, y, z) -> level table | nil (Floors.OpenAt), has = function(tile) -> bool (Cache.Has: tiles already there are left out),
--   origin = {x, y} (the nearest tiles first), maxTiles = the cap (Preload.MAX_TILES), maxTop = the top of the map's open level (Floors.MapOpenTop): a place whose
--   level is higher makes no tile (a cell at the fringe of a box, where the in/out map's spread is wider than the ground, can see its ray go through the sky of the
--   playable area into the skybox),
--   indoorLevelAt = function(x, y, top) -> level | nil (the floors of an INDOOR box: the ground is found under `top`, the top of the box's layer, then the level of a player there;
--   without it indoor boxes make no tile), places = {{x, y, z}, ...} (the ground places of the node graph: the floors), placeLevelAt = function(x, y, z) -> level | nil (Floors.PeekAt), definitionsAt =
--   function(x, y, z) -> {ppm, ...} (the definitions of the place's mode; without it the job's `definitions`), placeRadius = units around a place that get tiles (256) }.
-- The job: Step(count) does at most `count` boxes and answers how many it did; Done(); Entries() = the tiles to make, nearest first, each {tile = {level, tx, ty,
-- res, ppm}, level = the level table (the generator needs its heights), d = squared distance to the origin}; Total() = how many tiles the plan has before the
-- cap; Truncated() = true when the cap cut it. The entries are final once Done() is true.
function Preload.NewJob(boxes, opts)
	local job = {}
	local definitions = opts.definitions or {}
	local res = opts.res
	local origin = opts.origin or {0, 0}
	local maxTiles = opts.maxTiles or Preload.MAX_TILES
	local levelAt, has, tileUnits = opts.levelAt, opts.has, opts.tileUnits
	local indoorLevelAt = opts.indoorLevelAt
	local maxTop = opts.maxTop

	-- the edge of a tile for each definition, asked once per definition
	local edges = {}

	local function edgeFor(ppm)
		local edge = edges[ppm]

		if edge == nil then
			edge = tileUnits(res, ppm) or false
			edges[ppm] = edge
		end

		return edge
	end

	local places = opts.places or {}
	local placeLevelAt, definitionsAt = opts.placeLevelAt, opts.definitionsAt
	local radius = opts.placeRadius or 256
	local nextBox = 1
	local nextPlace = 1
	local seen = {} -- "level:tx,ty@ppm" of the tiles already listed
	local entries = {}
	local total = 0
	local finished = false
	local sorted = false

	-- the tiles of one area (world units) at the given definitions, for one level
	local function addArea(level, x1, y1, x2, y2, defs)
		for i = 1, #defs do
			local ppm = defs[i]
			local edge = edgeFor(ppm)

			if type(edge) == "number" and edge > 0 then
				local tx0, tx1 = mathFloor(x1 / edge), mathFloor((x2 - 1e-6) / edge)
				local ty0, ty1 = mathFloor(y1 / edge), mathFloor((y2 - 1e-6) / edge)

				for tx = tx0, tx1 do
					for ty = ty0, ty1 do
						local key = level.id .. ":" .. tx .. "," .. ty .. "@" .. ppm

						if not seen[key] then
							seen[key] = true

							local tile = {level = level.id, tx = tx, ty = ty, res = res, ppm = ppm}

							if not (has and has(tile)) then
								local dx, dy = (tx + 0.5) * edge - origin[1], (ty + 0.5) * edge - origin[2]

								total = total + 1
								entries[#entries + 1] = {tile = tile, level = level, d = dx * dx + dy * dy}
							end
						end
					end
				end
			end
		end
	end

	local function doBox(box)
		local state = field(box, "state", 6)
		local outdoor = state == OUTDOOR

		-- an indoor box makes tiles only when the floors are asked for (indoorLevelAt)
		if not outdoor and not (state == INDOOR and indoorLevelAt) then
			return
		end

		local layer = field(box, "layer", 1)
		local cx1, cy1, cx2, cy2 = field(box, "x1", 2), field(box, "y1", 3), field(box, "x2", 4), field(box, "y2", 5)
		local w, h = cx2 - cx1 + 1, cy2 - cy1 + 1

		if w < 1 or h < 1 then
			return
		end

		-- the ray starts at the top of the layer's band: the ground is somewhere in the band, so the start is over it
		local z = layer * CELL + HALF_BAND - 1
		local gx, gy = mathMin(SUBDIV, w), mathMin(SUBDIV, h)

		for ix = 0, gx - 1 do
			local ax1, ax2 = cx1 + mathFloor(ix * w / gx), cx1 + mathFloor((ix + 1) * w / gx) -- cells [ax1, ax2)

			for iy = 0, gy - 1 do
				local ay1, ay2 = cy1 + mathFloor(iy * h / gy), cy1 + mathFloor((iy + 1) * h / gy)
				local x1, y1, x2, y2 = ax1 * CELL, ay1 * CELL, ax2 * CELL, ay2 * CELL
				local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
				local level = (outdoor and levelAt or indoorLevelAt)(mx, my, z)

				if type(level) == "table" and type(level.id) == "string" and not (maxTop and type(level.zhi) == "number" and level.zhi > maxTop) then
					local defs = definitions

					if not outdoor and definitionsAt then
						defs = definitionsAt(mx, my, z) or definitions
					end

					addArea(level, x1, y1, x2, y2, defs)
				end
			end
		end
	end

	local function doPlace(place)
		local level = placeLevelAt(place.x, place.y, place.z)

		if type(level) == "table" and type(level.id) == "string" and not (maxTop and type(level.zhi) == "number" and level.zhi > maxTop) then
			local defs = definitionsAt and definitionsAt(place.x, place.y, place.z) or definitions

			addArea(level, place.x - radius, place.y - radius, place.x + radius, place.y + radius, defs)
		end
	end

	-- the boxes first, then the places, in the same steps
	function job.Step(count)
		local done = 0

		while done < count and nextBox <= #boxes do
			local box = boxes[nextBox]

			nextBox = nextBox + 1
			done = done + 1

			if type(box) == "table" then
				doBox(box)
			end
		end

		while done < count and placeLevelAt and nextPlace <= #places do
			local place = places[nextPlace]

			nextPlace = nextPlace + 1
			done = done + 1

			if type(place) == "table" and type(place.x) == "number" and type(place.y) == "number" and type(place.z) == "number" then
				doPlace(place)
			end
		end

		if nextBox > #boxes and (not placeLevelAt or nextPlace > #places) then
			finished = true
		end

		return done
	end

	function job.Done()
		return finished or (nextBox > #boxes and (not placeLevelAt or nextPlace > #places))
	end

	function job.Entries()
		if not sorted and job.Done() then
			table.sort(entries, byDistance)

			-- the cap keeps the nearest tiles
			for i = #entries, maxTiles + 1, -1 do
				entries[i] = nil
			end

			sorted = true
		end

		return entries
	end

	function job.Total()
		return total
	end

	function job.Truncated()
		return total > maxTiles
	end

	return job
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- The driver: reads the settings and the in/out map, plans in small steps (one frame never does all the rays of a map), and hands the tiles to the generator, which
-- makes them after everything the radar asks for, within a small budget and not in a slow frame (see Gen.SetPreload). Cost rules: no hook stays: the frame hook exists only
-- while a plan is being made; a timer waits a moment after an event or a change of setting so that several changes make one plan; nothing is done when the preload is off.
-- The engine's parts are fields (Preload._hookAdd, ...) so that the tests give their own.

local NAME = "GryMod minimap preload"
local STEP_BOXES = 4 -- boxes planned between two readings of the clock
local FRAME_SHARE = 0.001 -- seconds of planning in a frame, at most (one step is always done)

Preload.SCHEDULE_DELAY = 2 -- seconds waited after an event or a change before planning
Preload.RETRY_MAX = 30 -- how many times a plan waits (a second each) for the radar to give the screen constant

CreateClientConVar("gry_minimap_preload", "1", true, false, "Make the map tiles of the outdoor places in advance, from the in/out map (1), or only as you play (0)", 0, 1)

Preload._hookAdd = hook.Add
Preload._hookRemove = hook.Remove
Preload._timerCreate = timer.Create
Preload._timerRemove = timer.Remove
Preload._frameTime = FrameTime
Preload._clock = SysTime

Preload._convar = function(name)
	local convar = GetConVar(name)

	return convar and convar:GetFloat() or nil
end

Preload._origin = function()
	local ply = LocalPlayer()

	if IsValid(ply) then
		local pos = ply:GetPos()

		return {pos.x, pos.y}
	end

	return {0, 0}
end

local job = nil -- the plan being made
local retries = 0

local function removeFrameHook()
	Preload._hookRemove("Think", NAME)
end

-- one frame of planning (the Think hook)
local function frame()
	if not job then
		removeFrameHook()

		return
	end

	local Gen = GryMod.Minimap.Gen
	local limit = Gen and Gen.PRELOAD_MAX_FRAME or 0.025

	if Preload._frameTime() > limit then
		return -- the last frame was slow: later
	end

	local started = Preload._clock()

	repeat
		job.Step(STEP_BOXES)
	until job.Done() or Preload._clock() - started >= FRAME_SHARE

	if job.Done() then
		local entries = job.Entries()

		job = nil
		removeFrameHook()

		if Gen and Gen.SetPreload then
			Gen.SetPreload(entries)
		end
	end
end

-- Stop(): the plan in progress is dropped, the frame hook and the timer go, and the generator forgets the preload tiles that wait.
function Preload.Stop()
	job = nil
	removeFrameHook()
	Preload._timerRemove(NAME)

	local Gen = GryMod.Minimap.Gen

	if Gen and Gen.SetPreload then
		Gen.SetPreload({})
	end
end

-- Start() -> true | false, reason. Plans the preload now: the outdoor boxes of the in/out map, at the definitions the radar will use (the slider's with a manual definition;
-- with the automatic one, the levels the three zoom ranges give, or the one range of the radar when the automatic zoom is off). Reasons: "off" (the switch or the
-- minimap), "no map" (the in/out map is not there), "no screen constant" (the radar has not drawn yet), "no definition".
function Preload.Start()
	local M = GryMod.Minimap

	job = nil
	removeFrameHook()

	local Settings, Cache, Floors, Gen = M.Settings, M.Cache, M.Floors, M.Gen

	if (Preload._convar("gry_minimap_preload") or 1) == 0 or not Settings or not (Settings.Enabled and Settings.Enabled()) then
		if Gen and Gen.SetPreload then
			Gen.SetPreload({})
		end

		return false, "off"
	end

	local zone = GryMod.ZoneMapClient
	local boxes = zone and zone.Boxes and zone.Boxes()

	if type(boxes) ~= "table" then
		return false, "no map"
	end

	local definitions
	local footDefs, indoorDefs -- the definitions of the two modes, for the floors (a place is indoors or not by the in/out map)

	if Settings.DefinitionAuto() then
		local k = Settings.ScreenConstant and Settings.ScreenConstant()

		if not k then
			return false, "no screen constant"
		end

		local ranges

		if (Preload._convar("gry_radar_autozoom") or 0) == 1 then
			ranges = {Preload._convar("gry_radar_zoom_vehicle"), Preload._convar("gry_radar_zoom_foot"), Preload._convar("gry_radar_zoom_indoor")}
		else
			ranges = {Preload._convar("gry_radar_range")}
		end

		definitions = Preload.Definitions(k, ranges, Settings.Definition())

		-- the floors: indoors the indoor range's level, else the foot range's (the vehicle drives outdoors); with one range both are that range's
		local autozoom = (Preload._convar("gry_radar_autozoom") or 0) == 1
		local footRange = autozoom and Preload._convar("gry_radar_zoom_foot") or Preload._convar("gry_radar_range")
		local indoorRange = autozoom and Preload._convar("gry_radar_zoom_indoor") or footRange

		if type(footRange) == "number" and footRange > 0 and type(indoorRange) == "number" and indoorRange > 0 then
			footDefs = {Settings.AutoDefinitionFor(k / footRange, nil)}
			indoorDefs = {Settings.AutoDefinitionFor(k / indoorRange, nil)}
		end
	else
		definitions = {Settings.Definition()}
		footDefs = definitions
		indoorDefs = definitions
	end

	if #definitions == 0 or not Cache or not Floors or not Floors.OpenAt then
		return false, "no definition"
	end

	-- the ground places of the node graph (the floors): none without a graph, a reader or Floors.PeekAt
	local places = {}
	local AIN = GryMod.AIN
	local ok, graph = pcall(function() return AIN and AIN.Load and AIN.Load(game.GetMap()) end)

	if ok and type(graph) == "table" and type(graph.nodes) == "table" and Floors.PeekAt and footDefs then
		for _, node in ipairs(graph.nodes) do
			if type(node) == "table" and node.type == 2 then
				places[#places + 1] = {x = node.x, y = node.y, z = node.z}
			end
		end
	end

	job = Preload.NewJob(boxes, {
		definitions = definitions,
		res = Settings.TileRes(),
		tileUnits = Cache.TileUnits,
		levelAt = Floors.OpenAt,
		maxTop = Floors.MapOpenTop and Floors.MapOpenTop() or nil,
		has = Cache.Has,
		origin = Preload._origin(),
		indoorLevelAt = (Floors.GroundAt and Floors.PeekAt and footDefs) and function(x, y, top)
			local ground = Floors.GroundAt(x, y, top)

			return ground and Floors.PeekAt(x, y, ground) or nil
		end or nil,
		places = places,
		placeLevelAt = Floors.PeekAt,
		definitionsAt = function(x, y, z)
			local indoors = zone.Indoor and zone.Indoor({x = x, y = y, z = z}) == true

			return indoors and indoorDefs or footDefs
		end
	})

	Preload._hookAdd("Think", NAME, frame)

	return true
end

-- Schedule(): plan after a short wait (an event or a change of setting: several make one plan). Off: nothing waits and nothing is kept.
function Preload.Schedule()
	if (Preload._convar("gry_minimap_preload") or 1) == 0 then
		Preload.Stop()

		return
	end

	Preload._timerCreate(NAME, Preload.SCHEDULE_DELAY, 1, function()
		local started, why = Preload.Start()

		-- the radar gives the screen constant at its first draws: wait for it (a second at a time) instead of giving up
		if not started and why == "no screen constant" and retries < Preload.RETRY_MAX then
			retries = retries + 1
			Preload._timerCreate(NAME, 1, 1, function()
				Preload.Schedule()
			end)
		else
			retries = 0
		end
	end)
end

-- the in/out map arrived, and the settings that change what is to be made
hook.Add("GryMod_InOutMapReady", NAME, function()
	Preload.Schedule()
end)

for _, name in ipairs({"gry_minimap_preload", "gry_minimap_definition_auto", "gry_minimap_definition", "gry_radar_autozoom", "gry_radar_zoom_vehicle", "gry_radar_zoom_foot", "gry_radar_zoom_indoor", "gry_radar_range"}) do
	cvars.AddChangeCallback(name, function()
		Preload.Schedule()
	end, NAME)
end
