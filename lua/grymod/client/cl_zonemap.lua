-- The client side of the in/out map (see docs/superpowers/specs/2026-11-22-zonemap-design.md): the server makes the map from the node graph
-- (sv_zonemap.lua) and sends it; this file receives it, answers "is this place indoors?" (the automatic zoom asks, cl_hud_radar_zoom.lua), keeps the
-- state for the options panel and, while the debug convar is on, draws the boxes in the world (translucent volumes, the nearest ones, within the range the
-- player chose) and a block of text under the crosshair that names the box the player is in.
-- GryMod.ZoneMap (sh_zonemap.lua) is the pure module: it decodes the file and looks a position up. It is read at the moment of use, never kept, so that a
-- reload of it (or a test's stand-in) is seen at once.
-- Cost: the two net receivers run only when the server sends something; Indoor allocates nothing; the two drawing hooks (3D and HUD) exist only while
-- gry_zonemap_debug is 1.

GryMod = GryMod or {}

local Z = GryMod.ZoneMapClient or {}
GryMod.ZoneMapClient = Z

local DEBUG_CONVAR = "gry_zonemap_debug"
local DEBUG_HOOK = "GryMod zonemap debug"
local HUD_HOOK = "GryMod zonemap debug hud"
local RANGE_CONVAR = "gry_zonemap_debug_range"
local RANGE_MIN, RANGE_MAX = 20, 300 -- metres, the limits of the convar
local DEBUG_MAX = 800 -- boxes drawn a frame, at most (the nearest ones)
local REFRESH_EVERY = 0.25 -- seconds: the selection of the boxes to draw is made again after that
local MOVE_LIMIT = 64 -- units: or when the player moved farther than that from where it was made
local FALLBACK_METRES_PER_UNIT = 0.01905 -- GryMod.RadarShared.METRES_PER_UNIT, when that file is not loaded
local ASK_EVERY = 5 -- seconds between two requests made after a failure to receive
local CELL = 128 -- units, as in the pure module
local HALF_BAND = 64
local LAST_STATE = 6

-- the heights of the ceiling classes 1..7 (the same classes as Floors, lua/grymod/client/minimap/floors.lua)
local CLASS_HEIGHT = {56, 88, 120, 160, 224, 320, 448}

CreateClientConVar(DEBUG_CONVAR, "0", true, false, "Draw the in/out map of the level in the world (red = indoor, green = outdoor, cyan = ceiling height) and name the box you are in", 0, 1)

local rangeConVar = CreateClientConVar(RANGE_CONVAR, "120", true, false, "In/out map debug: how far, in metres, the boxes are drawn around you (20 to 300)", RANGE_MIN, RANGE_MAX)

-- ---------------------------------------------------------------------------------------------------------
-- The state: one table, so that a test can save it and put it back
-- ---------------------------------------------------------------------------------------------------------

local S

local function freshState()
	return {
		state = nil, -- 0..6 as the server sent it, nil before the first message
		done = 0,
		total = 0,
		map = nil, -- the decoded map (GryMod.ZoneMap.Decode)
		index = nil, -- GryMod.ZoneMap.Index(map)
		boxes = 0,
		reason = nil, -- why the last file was refused
		pieces = nil, -- the chunks of the file being received (1-based list)
		setCount = nil, -- how many chunks that file has
		lastAsk = -math.huge, -- the clock of the last request made after a failure
		askedAt = nil, -- the clock when the client started to ask for the map (Z.AskUntilAnswered)
		loadingSince = nil, -- the clock since when Z.Loading wants the veil (its grace is counted from there)
		noticedMap = nil, -- the level for which the incomplete notice was shown
		flat = nil, -- the boxes as plain number lists for the drawing (made at the first frame drawn)
		sel = nil, -- the boxes to draw (the nearest ones), made again now and then (see refreshSelection)
		boxCache = nil, -- the box the player was last found in (see findBox)
		hud = nil, -- the lines of the HUD block for the box the player is in
		hudBuilds = 0 -- how many times those lines were made (see Z.HudBuilds)
	}
end

S = freshState()

local function dropMap()
	S.map, S.index, S.boxes, S.flat = nil, nil, 0, nil
	-- everything that was made from the old boxes goes with them
	S.sel, S.boxCache, S.hud = nil, nil, nil
end

local function dropSet()
	S.pieces, S.setCount = nil, nil
end

-- A test's clock (the real one is RealTime).
function Z.Clock()
	return RealTime()
end

-- Everything back to the start (tests, and nothing else).
function Z.Reset()
	S = freshState()
end

-- The state as a copy a test can give back to Restore (so that a test does not wipe the map the owner's game really received).
function Z.Save()
	local copy = {}

	for key, value in pairs(S) do
		copy[key] = value
	end

	return copy
end

function Z.Restore(saved)
	S = freshState()

	for key, value in pairs(saved) do
		S[key] = value
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Asking
-- ---------------------------------------------------------------------------------------------------------

-- "Tell me the state and send me the map" (no payload). Never raises: the message may not be known yet.
function Z.Want()
	if pcall(net.Start, "gry_zonemap_want") then
		pcall(net.SendToServer)
	end
end

-- After a file that did not arrive whole: ask again, at most once every 5 seconds (the server answers to everybody with the state, and only to
-- the asker with the file).
local function askAgain()
	local now = Z.Clock()

	if now - S.lastAsk < ASK_EVERY then
		return
	end

	S.lastAsk = now
	Z.Want()
end

-- ---------------------------------------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------------------------------------

local function notice(text)
	if notification and notification.AddLegacy then
		pcall(notification.AddLegacy, text, NOTIFY_GENERIC, 6)
	end
end

-- Decodes a whole file and keeps the map, or keeps the reason it was refused. Never raises.
local function accept(bytes)
	local M = GryMod.ZoneMap

	dropMap()

	if not M or not isfunction(M.Decode) or not isfunction(M.Index) then
		S.reason = "the zone map module is not loaded"

		return
	end

	local ok, map, header = pcall(M.Decode, bytes)

	if not ok then
		S.reason = "the file could not be read (" .. tostring(map) .. ")"

		return
	end

	if not map or not istable(map.boxes) then
		S.reason = tostring(header or "the file is not a map")

		return
	end

	local indexed, index = pcall(M.Index, map)

	if not indexed or index == nil then
		S.reason = "the map could not be indexed (" .. tostring(index) .. ")"

		return
	end

	S.map, S.index, S.boxes, S.reason = map, index, #map.boxes, nil
end

-- The state of the server's work (gry_zonemap_state). A state that says the map is not there (or is being made again) drops the one held: a stale
-- map would answer for a place the new one may see differently.
function Z.OnState(state, done, total)
	if not isnumber(state) or state < 0 or state > LAST_STATE or state ~= math.floor(state) then
		return
	end

	S.state = state
	S.done = isnumber(done) and done or 0
	S.total = isnumber(total) and total or 0

	if state < 4 or state == 6 then
		dropMap()
		dropSet()
		S.reason = nil
	end

	-- the front (the radar's veil asks Z.Loading; the HUD or another addon may listen): the state, how many nodes are done, how many there are. A hook that raises
	-- does not stop the receiver.
	local ran, hookErr = pcall(hook.Run, "GryMod_InOutMapState", state, S.done, S.total)

	if not ran then
		ErrorNoHalt("[GryMod] GryMod_InOutMapState: " .. tostring(hookErr) .. "\n")
	end

	-- made, but not from every node: said once per level
	if state == 5 then
		local map = game.GetMap()

		if S.noticedMap ~= map then
			S.noticedMap = map
			notice("The in/out map of this map was not made from every node")
		end
	end
end

-- One chunk of the file (gry_zonemap_data). A set starts at index 0; a chunk that is not the next one of the set, or that is not what it says it is, drops the set
-- and asks again.
function Z.OnData(index, count, length, data)
	if not isnumber(index) or not isnumber(count) or not isnumber(length) or not isstring(data) or count < 1 or index < 0 or index >= count or length < 1 or #data ~= length then
		dropSet()
		askAgain()

		return
	end

	if index == 0 then
		S.pieces, S.setCount = {data}, count
	elseif not S.pieces or S.setCount ~= count or index ~= #S.pieces then
		dropSet()
		askAgain()

		return
	else
		S.pieces[#S.pieces + 1] = data
	end

	if #S.pieces == S.setCount then
		local bytes = table.concat(S.pieces)

		dropSet()
		accept(bytes)
	end
end

net.Receive("gry_zonemap_state", function()
	local state = net.ReadUInt(3)
	local done = net.ReadUInt(24)
	local total = net.ReadUInt(24)

	Z.OnState(state, done, total)
end)

net.Receive("gry_zonemap_data", function()
	local index = net.ReadUInt(16)
	local count = net.ReadUInt(16)
	local length = net.ReadUInt(16)
	local data = net.ReadData(length)

	Z.OnData(index, count, length, data)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Asking for the map: once when the client is ready, and when the switch goes on
-- ---------------------------------------------------------------------------------------------------------

-- The first want of a map is lost: when this file loads the server has no player for this client yet (measured on a listen server: the state stayed "not received
-- yet"), and InitPostEntity of the client does not fire reliably on a map change made from the console (it had not fired 18 seconds after the load), so nothing
-- waits for it. The want is sent when the file loads and repeated every few seconds until the server has answered with any state, at most RETRY_MAX times in
-- all: a chain of timers that ends by itself, no hook that stays. A new start replaces the chain of the old one.
local RETRY_EVERY = 3 -- seconds
local RETRY_MAX = 10 -- wants in all (30 seconds: a heavy map may take that long to be in the game)

-- the timer, a field so that a test can replace it
Z.Timer = timer.Simple

local chain = 0

local function askUntilAnswered(mine, attempt)
	Z.Want()

	if attempt >= RETRY_MAX then
		return
	end

	Z.Timer(RETRY_EVERY, function()
		if chain == mine and S.state == nil then
			askUntilAnswered(mine, attempt + 1)
		end
	end)
end

function Z.AskUntilAnswered()
	chain = chain + 1
	S.askedAt = Z.Clock()
	askUntilAnswered(chain, 1)
end

-- Whether the radar should be veiled because the in/out map is not there yet, and the percentage to show: the client is waiting for the server's first answer (from
-- the moment it asks, for as long as the asks go on: RETRY_EVERY * RETRY_MAX seconds), the server waits or computes (state 2, 3: its percentage), or the server says the
-- map is ready and the file is on its way (state 4, 5 with no map yet and no refusal). Nothing to wait for when it is off, there is no graph or it failed (0, 1, 6), or
-- when the map is held. A grace of a quarter of a second: a map made in a few frames does not flash the veil. Returns false, or true and a whole percentage.
local GRACE = 0.25

function Z.Loading()
	local now = Z.Clock()
	local state = S.state
	local wanted, percent = false, 0

	if state == nil then
		wanted = S.askedAt ~= nil and now - S.askedAt < RETRY_EVERY * RETRY_MAX
	elseif state == 2 then
		wanted = true
	elseif state == 3 then
		wanted = true

		if S.total > 0 then
			percent = math.Clamp(math.floor(S.done * 100 / S.total), 0, 100)
		end
	elseif (state == 4 or state == 5) and S.index == nil and S.reason == nil then
		wanted, percent = true, 100
	end

	if not wanted then
		S.loadingSince = nil

		return false
	end

	S.loadingSince = S.loadingSince or now

	if now - S.loadingSince < GRACE then
		return false
	end

	return true, percent
end

-- when the file loads (a new map, or a reload in the game)
Z.AskUntilAnswered()

cvars.AddChangeCallback("gry_zonemap", function(_, _, new)
	if (tonumber(new) or 0) ~= 0 then
		Z.Want()
	end
end, "GryMod zonemap want")

-- ---------------------------------------------------------------------------------------------------------
-- The answers
-- ---------------------------------------------------------------------------------------------------------

-- true (indoor), false (outdoor) or nil (no map, or a place the map does not know). Allocation free.
function Z.Indoor(pos)
	local index = S.index

	if not index then
		return nil
	end

	if not istable(pos) and not isvector(pos) then
		return nil
	end

	local x, y, z = pos.x, pos.y, pos.z

	if not isnumber(x) or not isnumber(y) or not isnumber(z) then
		return nil
	end

	-- NaN and infinity: their difference with themselves is not 0
	if x - x ~= 0 or y - y ~= 0 or z - z ~= 0 then
		return nil
	end

	local M = GryMod.ZoneMap

	if not M then
		return nil
	end

	local state = M.Lookup(index, x, y, z)

	if state == 2 then
		return true
	elseif state == 1 then
		return false
	end

	return nil
end

-- state, done, total, boxes, reason. The state is nil before the server said anything.
function Z.Status()
	return S.state, S.done, S.total, S.boxes, S.reason
end

local PREFIX = "In/out map: "

-- The line the options panel shows.
function Z.StatusText()
	local state = S.state

	if state == nil then
		return PREFIX .. "not received yet"
	elseif state == 0 then
		return PREFIX .. "off on this server"
	elseif state == 1 then
		return PREFIX .. "no graph on this map"
	elseif state == 2 then
		return PREFIX .. "waiting"
	elseif state == 3 then
		local percent = S.total > 0 and math.floor(S.done * 100 / S.total) or 0

		return PREFIX .. "computing " .. percent .. " %"
	elseif state == 6 then
		return PREFIX .. "failed (see the server log)"
	end

	local text

	if state == 4 then
		if S.boxes > 0 then
			text = "ready, " .. S.boxes .. " boxes"
		else
			text = "ready, the map is on its way"
		end
	else
		text = "incomplete, not every node was used"
	end

	if S.reason then
		text = text .. " (the file was refused: " .. S.reason .. ")"
	end

	return PREFIX .. text
end

-- ---------------------------------------------------------------------------------------------------------
-- The debug drawing
-- ---------------------------------------------------------------------------------------------------------
-- The boxes are drawn as translucent volumes (a filled box and, over it, its edges as a thin wire at a higher alpha so that two neighbours stay readable), red for
-- indoor and green for outdoor, plus a cyan line for the ceiling. At most DEBUG_MAX boxes a frame, the NEAREST ones within the range of the convar
-- gry_zonemap_debug_range (metres). Which boxes those are is worked out at most four times a second, or when the player moved more than 64 units (the frame
-- draws the selection kept). The box the player is in is drawn brighter. Everything the frame uses is made once: no table, Vector or Color per box per frame.

local floor = math.floor
local INV_CELL = 1 / CELL -- exact: a power of two
local INV_BAND = 1 / (2 * HALF_BAND)

local ORIGIN = Vector(0, 0, 0)
local NO_ANGLE = Angle(0, 0, 0)
local boxMins, boxMaxs = Vector(0, 0, 0), Vector(0, 0, 0)
local lineFrom, lineTo = Vector(0, 0, 0), Vector(0, 0, 0)
local CYAN = Color(0, 255, 255)

-- the colours by state (1 outdoor, 2 indoor): the faces (alpha 38, 76 for the box the player is in) and the wire (alpha 90, 255 for that box)
local FACE = {Color(50, 255, 80, 38), Color(255, 50, 50, 38)}
local FACE_HERE = {Color(50, 255, 80, 76), Color(255, 50, 50, 76)}
local WIRE = {Color(50, 255, 80, 90), Color(255, 50, 50, 90)}
local WIRE_HERE = {Color(50, 255, 80, 255), Color(255, 50, 50, 255)}

-- A box as the module gives it: {layer, x1, y1, x2, y2, state, ceil}, in a list or with those names.
local function field(box, name, at)
	local value = box[name]

	if value == nil then
		value = box[at]
	end

	return isnumber(value) and value or 0
end

-- The boxes of the map as plain lists of numbers (the world bounds of each box), made once for a map, at the first frame that draws it.
local function flatten(map)
	local flat = {n = 0, minX = {}, maxX = {}, minY = {}, maxY = {}, minZ = {}, maxZ = {}, baseZ = {}, layer = {}, state = {}, ceil = {}, dist = {}}
	local n = 0

	for _, box in ipairs(map.boxes) do
		if istable(box) then
			n = n + 1

			local layer = field(box, "layer", 1)

			flat.minX[n] = field(box, "x1", 2) * CELL
			flat.minY[n] = field(box, "y1", 3) * CELL
			flat.maxX[n] = (field(box, "x2", 4) + 1) * CELL
			flat.maxY[n] = (field(box, "y2", 5) + 1) * CELL
			flat.minZ[n] = layer * CELL - HALF_BAND
			flat.maxZ[n] = layer * CELL + HALF_BAND
			flat.baseZ[n] = layer * CELL
			flat.layer[n] = layer
			flat.state[n] = field(box, "state", 6)
			flat.ceil[n] = field(box, "ceil", 7)
			flat.dist[n] = 0 -- the distance of the box to the player, filled by the selection (the array is full from the start)
		end
	end

	flat.n = n

	return flat
end

-- the flat boxes of the map held (made when they are first needed), or nil when there is no map
local function flatBoxes()
	local flat = S.flat

	if not flat and S.map then
		flat = flatten(S.map)
		S.flat = flat
	end

	return flat
end

-- x, y, z of a position (a Vector or anything with those numbers), or nil when it is not one (or not a finite one)
local function position(pos)
	if not istable(pos) and not isvector(pos) then
		return nil
	end

	local x, y, z = pos.x, pos.y, pos.z

	if not isnumber(x) or not isnumber(y) or not isnumber(z) then
		return nil
	end

	-- NaN and infinity: their difference with themselves is not 0
	if x - x ~= 0 or y - y ~= 0 or z - z ~= 0 then
		return nil
	end

	return x, y, z
end

-- The range of the debug drawing in units (the convar is in metres).
function Z.DebugRangeUnits()
	local shared = GryMod.RadarShared
	local metresPerUnit = shared and shared.METRES_PER_UNIT or FALLBACK_METRES_PER_UNIT

	return math.Clamp(rangeConVar:GetFloat(), RANGE_MIN, RANGE_MAX) / metresPerUnit
end

-- ---------------------------------------------------------------------------------------------------------
-- The box the player is in
-- ---------------------------------------------------------------------------------------------------------

-- The index of the box that contains the position, or 0. The player's own layer first, then the layer above, then the one below (like GryMod.ZoneMap.Lookup, so that
-- the HUD and Indoor agree). The answer is kept for the cell and the layer it was found in: a scan of the boxes only when the player changes cell or layer.
local function findBox(flat, x, y, z)
	local cx, cy, layer = floor(x * INV_CELL), floor(y * INV_CELL), floor((z + HALF_BAND) * INV_BAND)
	local cache = S.boxCache

	if cache then
		if cache.cx == cx and cache.cy == cy and cache.layer == layer then
			return cache.index
		end
	else
		cache = {cx = 0, cy = 0, layer = 0, index = 0}
		S.boxCache = cache
	end

	local minX, maxX, minY, maxY, layers = flat.minX, flat.maxX, flat.minY, flat.maxY, flat.layer
	local best, bestRank = 0, 4

	for i = 1, flat.n do
		-- the cells x1 to x2 are the coordinates from x1 * CELL up to (x2 + 1) * CELL, not including it
		if x >= minX[i] and x < maxX[i] and y >= minY[i] and y < maxY[i] then
			local apart = layers[i] - layer
			local rank = apart == 0 and 1 or (apart == 1 and 2 or (apart == -1 and 3 or 4))

			if rank < 4 and rank <= bestRank then
				best, bestRank = i, rank
			end
		end
	end

	cache.cx, cache.cy, cache.layer, cache.index = cx, cy, layer, best

	return best
end

-- The fields of the box i of the flat boxes, in the module's order: layer, x1, y1, x2, y2, state, ceil (the cells are whole numbers: the world bounds over CELL, exact)
local function boxFields(flat, i)
	return flat.layer[i], flat.minX[i] * INV_CELL, flat.minY[i] * INV_CELL, flat.maxX[i] * INV_CELL - 1, flat.maxY[i] * INV_CELL - 1, flat.state[i], flat.ceil[i]
end

-- BoxAt(pos) -> index, layer, x1, y1, x2, y2, state, ceil of the box the position is in (the index is the box's place in the map), or nil. No table made.
function Z.BoxAt(pos)
	local x, y, z = position(pos)

	if not x then
		return nil
	end

	local flat = flatBoxes()

	if not flat then
		return nil
	end

	local index = findBox(flat, x, y, z)

	if index == 0 then
		return nil
	end

	return index, boxFields(flat, index)
end

-- ---------------------------------------------------------------------------------------------------------
-- The boxes to draw: the nearest ones within the range
-- ---------------------------------------------------------------------------------------------------------

-- the sort puts the nearest first (a tie goes to the lower index, so the order is the same every time); the distances it reads are those of the selection being made
local sortDist

local function nearer(a, b)
	local da, db = sortDist[a], sortDist[b]

	return da < db or (da == db and a < b)
end

-- The selection kept (S.sel): the indices of the boxes within the range, the nearest DEBUG_MAX of them when there are more, in the table `idx` that is reused. It is made
-- again when it is older than REFRESH_EVERY, when the player is more than MOVE_LIMIT units from where it was made, or when the range changed.
local function refreshSelection(flat, x, y, z, range, now)
	local sel = S.sel

	if not sel then
		sel = {n = 0, idx = {}, runs = 0, at = -math.huge, x = 0, y = 0, z = 0, range = -1}
		S.sel = sel
	end

	local dx, dy, dz = x - sel.x, y - sel.y, z - sel.z
	local age = now - sel.at

	if sel.range == range and age >= 0 and age < REFRESH_EVERY and dx * dx + dy * dy + dz * dz <= MOVE_LIMIT * MOVE_LIMIT then
		return sel
	end

	sel.at, sel.x, sel.y, sel.z, sel.range = now, x, y, z, range
	sel.runs = sel.runs + 1

	local minX, maxX, minY, maxY, minZ, maxZ, dist = flat.minX, flat.maxX, flat.minY, flat.maxY, flat.minZ, flat.maxZ, flat.dist
	local rangeSquared = range * range
	local idx, n = sel.idx, 0

	for i = 1, flat.n do
		-- the distance from the player to the box (0 along an axis the player is inside)
		local x1, x2, y1, y2, z1, z2 = minX[i], maxX[i], minY[i], maxY[i], minZ[i], maxZ[i]
		local bx = x < x1 and x1 - x or (x > x2 and x - x2 or 0)
		local by = y < y1 and y1 - y or (y > y2 and y - y2 or 0)
		local bz = z < z1 and z1 - z or (z > z2 and z - z2 or 0)
		local d = bx * bx + by * by + bz * bz

		if d <= rangeSquared then
			n = n + 1
			idx[n] = i
			dist[i] = d
		end
	end

	-- the tail of the last selection that is not part of this one
	for i = n + 1, sel.n do
		idx[i] = nil
	end

	if n > DEBUG_MAX then
		sortDist = dist
		table.sort(idx, nearer)

		for i = DEBUG_MAX + 1, n do
			idx[i] = nil
		end

		n = DEBUG_MAX
	end

	sel.n = n

	return sel
end

-- how many times the selection was made for the map held (a test reads it to see that it is not made at every frame)
function Z.SelectionRuns()
	local sel = S.sel

	return sel and sel.runs or 0
end

-- Draws the boxes of the selection (the nearest within the range of the convar, DEBUG_MAX at most) around `pos` (anything with x, y, z) and returns how many. The box
-- `pos` is in is drawn brighter. No table, Vector or Color is made per box.
function Z.Draw(pos)
	local x, y, z = position(pos)

	if not x then
		return 0
	end

	local flat = flatBoxes()

	if not flat then
		return 0
	end

	local sel = refreshSelection(flat, x, y, z, Z.DebugRangeUnits(), Z.Clock())
	local here = findBox(flat, x, y, z)
	local minX, maxX, minY, maxY, minZ, maxZ = flat.minX, flat.maxX, flat.minY, flat.maxY, flat.minZ, flat.maxZ
	local baseZ, states, ceils = flat.baseZ, flat.state, flat.ceil
	local idx = sel.idx

	render.SetColorMaterial()

	for k = 1, sel.n do
		local i = idx[k]
		local x1, x2, y1, y2 = minX[i], maxX[i], minY[i], maxY[i]
		local state = states[i] == 2 and 2 or 1

		boxMins.x, boxMins.y, boxMins.z = x1, y1, minZ[i]
		boxMaxs.x, boxMaxs.y, boxMaxs.z = x2, y2, maxZ[i]

		-- the volume (no write to the depth buffer: two translucent boxes never hide each other), then its edges
		if i == here then
			render.DrawBox(ORIGIN, NO_ANGLE, boxMins, boxMaxs, FACE_HERE[state], false)
			render.DrawWireframeBox(ORIGIN, NO_ANGLE, boxMins, boxMaxs, WIRE_HERE[state], false)
		else
			render.DrawBox(ORIGIN, NO_ANGLE, boxMins, boxMaxs, FACE[state], false)
			render.DrawWireframeBox(ORIGIN, NO_ANGLE, boxMins, boxMaxs, WIRE[state], false)
		end

		-- the ceiling class over the box: a cyan line up from the middle of the band by the height of the class (0 = no ceiling)
		local height = CLASS_HEIGHT[ceils[i]]

		if height then
			lineFrom.x, lineFrom.y, lineFrom.z = (x1 + x2) * 0.5, (y1 + y2) * 0.5, baseZ[i]
			lineTo.x, lineTo.y, lineTo.z = lineFrom.x, lineFrom.y, baseZ[i] + height
			render.DrawLine(lineFrom, lineTo, CYAN, false)
		end
	end

	return sel.n
end

-- ---------------------------------------------------------------------------------------------------------
-- The HUD block: the box the player is in
-- ---------------------------------------------------------------------------------------------------------

local FONT = "GryModZoneMapDebug"
local BLOCK_DOWN = 80 -- pixels under the crosshair

-- the font follows the height of the screen as it is when the file loads (20 pixels at 1080, 40 at a 4K screen)
local FONT_SIZE = math.max(18, math.floor(ScrH() / 54))
local LINE_HEIGHT = math.floor(FONT_SIZE * 1.2) -- pixels between two lines of the block

surface.CreateFont(FONT, {font = "Tahoma", size = FONT_SIZE, weight = 600, antialias = true})

local TEXT, TEXT_INDOOR, TEXT_OUTDOOR, SHADOW = Color(235, 235, 235), Color(255, 225, 130), Color(150, 255, 175), Color(0, 0, 0, 200)

local NO_BOX = PREFIX .. "unknown here (no box): the automatic zoom uses its own rays"

-- The lines of the block for a position: line 1, line 2 (nil when there is none), line 3, and the colour of line 2. With no map, the state's own line. The lines are kept
-- for the box the player is in: the strings are made when he goes from one box to another, not at every frame.
local function hudLines(pos)
	local flat = flatBoxes()

	if not flat then
		return Z.StatusText()
	end

	local x, y, z = position(pos)
	local index = x and findBox(flat, x, y, z) or 0
	local hud = S.hud

	if hud and hud.index == index then
		return hud.line1, hud.line2, hud.line3, hud.colour
	end

	hud = hud or {}
	S.hud = hud
	hud.index = index
	S.hudBuilds = S.hudBuilds + 1

	if index == 0 then
		hud.line1, hud.line2, hud.line3, hud.colour = NO_BOX, nil, nil, TEXT

		return hud.line1, nil, nil, TEXT
	end

	local layer, x1, y1, x2, y2, state, ceil = boxFields(flat, index)
	local height = CLASS_HEIGHT[ceil]
	local indoor = state == 2

	hud.line1 = PREFIX .. "box " .. index .. " / " .. flat.n
	hud.line2 = (indoor and "indoor, " or "outdoor, ") .. (height and ("ceiling " .. height .. " units (class " .. ceil .. ")") or "open sky / ceiling over 512")
	hud.line3 = "layer " .. layer .. ", cells x " .. x1 .. ".." .. x2 .. ", y " .. y1 .. ".." .. y2 .. " (" .. (x2 - x1 + 1) .. " x " .. (y2 - y1 + 1) .. ")"
	hud.colour = indoor and TEXT_INDOOR or TEXT_OUTDOOR

	return hud.line1, hud.line2, hud.line3, hud.colour
end

-- how many times the lines of the block were made (a test reads it to see that they are made when the box changes, not at every frame)
function Z.HudBuilds()
	return S.hudBuilds
end

-- a line with its shadow (one pixel right and down) under it
local function shadowed(text, x, y, colour)
	draw.SimpleText(text, FONT, x + 1, y + 1, SHADOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	draw.SimpleText(text, FONT, x, y, colour, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end

-- Draws the block under the crosshair for the position `pos`.
function Z.DrawHud(pos)
	local line1, line2, line3, colour = hudLines(pos)
	local x, y = ScrW() * 0.5, ScrH() * 0.5 + BLOCK_DOWN

	shadowed(line1, x, y, TEXT)

	if line2 then
		shadowed(line2, x, y + LINE_HEIGHT, colour)
	end

	if line3 then
		shadowed(line3, x, y + 2 * LINE_HEIGHT, TEXT)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The hooks: there while the debug convar is 1, not otherwise
-- ---------------------------------------------------------------------------------------------------------

-- A debug hook must never spam: both hooks run their drawing under pcall. The first error is printed ONCE (with its stack), the switch is put to 0 (its callback takes
-- both hooks off) and the player is told once. `stopped` is reset when the switch goes on again, so that the next error is reported again.
local setDebugHook
local stopped = false

local function stopDebug(err)
	if stopped then
		return
	end

	stopped = true

	local text = tostring(err)

	ErrorNoHaltWithStack("[GryMod] In/out map debug drawing: " .. text .. "\n")

	-- the hooks go at once (the callback of the switch would take them off too, but a stopped drawing must not wait for it)
	setDebugHook(false)

	local convar = GetConVar(DEBUG_CONVAR)

	if convar then
		convar:SetString("0")
	end

	-- the first line of the error, without the path of the file, cut short
	local short = string.gsub(string.match(text, "[^\r\n]*") or text, "^[%w_%.%-/\\:]*[/\\]", "")

	notice("The in/out map debug drawing stopped: " .. string.sub(short, 1, 100))
end

-- The hooks' functions: made once, so that Add and Remove name the same one.
local function drawHook(_, drawingSkybox, drawing3DSkybox)
	if drawingSkybox or drawing3DSkybox then
		return
	end

	local ply = LocalPlayer()

	if IsValid(ply) then
		local ok, err = pcall(Z.Draw, ply:GetPos())

		if not ok then
			stopDebug(err)
		end
	end
end

local function hudHook()
	local ply = LocalPlayer()

	if IsValid(ply) then
		local ok, err = pcall(Z.DrawHud, ply:GetPos())

		if not ok then
			stopDebug(err)
		end
	end
end

function setDebugHook(on)
	if on then
		stopped = false
		hook.Add("PostDrawTranslucentRenderables", DEBUG_HOOK, drawHook)
		hook.Add("HUDPaint", HUD_HOOK, hudHook)
	else
		hook.Remove("PostDrawTranslucentRenderables", DEBUG_HOOK)
		hook.Remove("HUDPaint", HUD_HOOK)
	end
end

-- Puts the hooks in line with the convar: added when it is 1, removed when it is 0 (called at load; the change callback does the same later).
function Z.SyncDebugHook()
	local convar = GetConVar(DEBUG_CONVAR)

	setDebugHook(convar ~= nil and convar:GetBool())
end

cvars.AddChangeCallback(DEBUG_CONVAR, function(_, _, new)
	setDebugHook((tonumber(new) or 0) ~= 0)
end, DEBUG_HOOK)

Z.SyncDebugHook()
