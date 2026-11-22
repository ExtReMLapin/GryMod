-- The client side of the indoor / outdoor map (see docs/superpowers/specs/2026-11-22-zonemap-design.md): the server makes the map from the node graph
-- (sv_zonemap.lua) and sends it; this file receives it, answers "is this place indoors?" (the automatic zoom asks, cl_hud_radar_zoom.lua), keeps the
-- state for the options panel and draws the boxes in the world while the debug convar is on.
-- GryMod.ZoneMap (sh_zonemap.lua) is the pure module: it decodes the file and looks a position up. It is read at the moment of use, never kept, so that a
-- reload of it (or a test's stand-in) is seen at once.
-- Cost: the two net receivers run only when the server sends something; Indoor allocates nothing; the drawing hook exists only while gry_zonemap_debug is 1.

GryMod = GryMod or {}

local Z = GryMod.ZoneMapClient or {}
GryMod.ZoneMapClient = Z

local DEBUG_CONVAR = "gry_zonemap_debug"
local DEBUG_HOOK = "GryMod zonemap debug"
local DEBUG_RANGE = 3000 -- units: the boxes farther than this from the player are not drawn
local DEBUG_MAX = 300 -- boxes drawn a frame, at most
local ASK_EVERY = 5 -- seconds between two requests made after a failure to receive
local CELL = 128 -- units, as in the pure module
local HALF_BAND = 64
local LAST_STATE = 6

-- the heights of the ceiling classes 1..7 (the same classes as Floors, lua/grymod/client/minimap/floors.lua)
local CLASS_HEIGHT = {56, 88, 120, 160, 224, 320, 448}

CreateClientConVar(DEBUG_CONVAR, "0", true, false, "Draw the indoor / outdoor map of the level in the world (red = indoor, green = outdoor, cyan = ceiling height)", 0, 1)

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
		noticedMap = nil, -- the level for which the incomplete notice was shown
		flat = nil -- the boxes as plain number lists for the drawing (made at the first frame drawn)
	}
end

S = freshState()

local function dropMap()
	S.map, S.index, S.boxes, S.flat = nil, nil, 0, nil
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

	-- made, but not from every node: said once per level
	if state == 5 then
		local map = game.GetMap()

		if S.noticedMap ~= map then
			S.noticedMap = map
			notice("The indoor / outdoor map of this map was not made from every node")
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
	askUntilAnswered(chain, 1)
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

local PREFIX = "Indoor / outdoor map: "

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

local ORIGIN = Vector(0, 0, 0)
local NO_ANGLE = Angle(0, 0, 0)
local boxMins, boxMaxs = Vector(0, 0, 0), Vector(0, 0, 0)
local lineFrom, lineTo = Vector(0, 0, 0), Vector(0, 0, 0)
local RED, GREEN, CYAN = Color(255, 50, 50), Color(50, 255, 80), Color(0, 255, 255)

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
	local flat = {n = 0, minX = {}, maxX = {}, minY = {}, maxY = {}, minZ = {}, maxZ = {}, baseZ = {}, state = {}, ceil = {}}
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
			flat.state[n] = field(box, "state", 6)
			flat.ceil[n] = field(box, "ceil", 7)
		end
	end

	flat.n = n

	return flat
end

-- Draws the boxes within DEBUG_RANGE of `pos` (anything with x, y, z), at most DEBUG_MAX, and returns how many. No table or Vector is made per box.
function Z.Draw(pos)
	local map = S.map

	if not map or not istable(pos) and not isvector(pos) then
		return 0
	end

	local px, py, pz = pos.x, pos.y, pos.z

	if not isnumber(px) or not isnumber(py) or not isnumber(pz) then
		return 0
	end

	local flat = S.flat

	if not flat then
		flat = flatten(map)
		S.flat = flat
	end

	local minX, maxX, minY, maxY, minZ, maxZ = flat.minX, flat.maxX, flat.minY, flat.maxY, flat.minZ, flat.maxZ
	local baseZ, states, ceils = flat.baseZ, flat.state, flat.ceil
	local rangeSquared = DEBUG_RANGE * DEBUG_RANGE
	local drawn = 0

	render.SetColorMaterial()

	for i = 1, flat.n do
		-- the distance from the player to the box (0 along an axis the player is inside)
		local x1, x2 = minX[i], maxX[i]
		local y1, y2 = minY[i], maxY[i]
		local z1, z2 = minZ[i], maxZ[i]
		local dx = px < x1 and x1 - px or (px > x2 and px - x2 or 0)
		local dy = py < y1 and y1 - py or (py > y2 and py - y2 or 0)
		local dz = pz < z1 and z1 - pz or (pz > z2 and pz - z2 or 0)

		if dx * dx + dy * dy + dz * dz <= rangeSquared then
			boxMins.x, boxMins.y, boxMins.z = x1, y1, z1
			boxMaxs.x, boxMaxs.y, boxMaxs.z = x2, y2, z2
			render.DrawWireframeBox(ORIGIN, NO_ANGLE, boxMins, boxMaxs, states[i] == 2 and RED or GREEN, false)

			-- the ceiling class over the box: a cyan line up from the middle of the band by the height of the class (0 = no ceiling)
			local height = CLASS_HEIGHT[ceils[i]]

			if height then
				lineFrom.x, lineFrom.y, lineFrom.z = (x1 + x2) * 0.5, (y1 + y2) * 0.5, baseZ[i]
				lineTo.x, lineTo.y, lineTo.z = lineFrom.x, lineFrom.y, baseZ[i] + height
				render.DrawLine(lineFrom, lineTo, CYAN, false)
			end

			drawn = drawn + 1

			if drawn >= DEBUG_MAX then
				break
			end
		end
	end

	return drawn
end

-- The hook's function: made once, so that Add and Remove name the same one.
local function drawHook(_, drawingSkybox, drawing3DSkybox)
	if drawingSkybox or drawing3DSkybox then
		return
	end

	local ply = LocalPlayer()

	if IsValid(ply) then
		Z.Draw(ply:GetPos())
	end
end

local function setDebugHook(on)
	if on then
		hook.Add("PostDrawTranslucentRenderables", DEBUG_HOOK, drawHook)
	else
		hook.Remove("PostDrawTranslucentRenderables", DEBUG_HOOK)
	end
end

-- Puts the hook in line with the convar: added when it is 1, removed when it is 0 (called at load; the change callback does the same later).
function Z.SyncDebugHook()
	local convar = GetConVar(DEBUG_CONVAR)

	setDebugHook(convar ~= nil and convar:GetBool())
end

cvars.AddChangeCallback(DEBUG_CONVAR, function(_, _, new)
	setDebugHook((tonumber(new) or 0) ~= 0)
end, DEBUG_HOOK)

Z.SyncDebugHook()
