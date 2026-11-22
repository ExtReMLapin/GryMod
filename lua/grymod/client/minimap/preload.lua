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
--   origin = {x, y} (the nearest tiles first), maxTiles = the cap (Preload.MAX_TILES) }.
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

	-- the edge of a tile for each definition, asked once
	local edges = {}

	for i = 1, #definitions do
		edges[i] = tileUnits(res, definitions[i])
	end

	local nextBox = 1
	local seen = {} -- "level:tx,ty@ppm" of the tiles already listed
	local entries = {}
	local total = 0
	local finished = false
	local sorted = false

	-- the tiles of one area (world units) at every definition, for one level
	local function addArea(level, x1, y1, x2, y2)
		for i = 1, #definitions do
			local edge = edges[i]
			local ppm = definitions[i]

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
		if field(box, "state", 6) ~= OUTDOOR then
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
				local level = levelAt((x1 + x2) / 2, (y1 + y2) / 2, z)

				if type(level) == "table" and type(level.id) == "string" then
					addArea(level, x1, y1, x2, y2)
				end
			end
		end
	end

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

		if nextBox > #boxes then
			finished = true
		end

		return done
	end

	function job.Done()
		return finished or nextBox > #boxes
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
