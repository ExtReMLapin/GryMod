-- Tests of the client side of the in/out map (lua/grymod/client/cl_zonemap.lua, GryMod.ZoneMapClient), GLuaTest format, client realm:
-- the receivers (state and chunks of the file), the answer of Indoor, the status line, the notice for an incomplete map, the debug drawing (a hook
-- that exists only while gry_zonemap_debug is on) and the options panel. The pure module GryMod.ZoneMap is another file: the cases of the receivers
-- run on a stand-in of it (so that they test only this file), the cases of the section "real module" run on the real one.
-- Every stand-in (net, render, notification, Confirm, the module, the clock, the convars) is put back in afterEach inside a pcall, also when a case failed.

-- the real pure module, loaded here when the autorun does not do it yet
local realModule = GryMod.ZoneMap

if not realModule then
	pcall(include, "grymod/sh_zonemap.lua")
	realModule = GryMod.ZoneMap
end

local HOOK = "GryMod zonemap debug"
local HUD_HOOK = "GryMod zonemap debug hud"
local DEBUG = "gry_zonemap_debug"
local RANGE = "gry_zonemap_debug_range"
local SHOW_IN = "gry_zonemap_debug_in"
local SHOW_OUT = "gry_zonemap_debug_out"
local FACES = "gry_zonemap_debug_faces"
local EDGES = "gry_zonemap_debug_edges"
local METRES_PER_UNIT = 0.01905

-- a convar that must exist (a missing one is a failed case, not a crash in the middle of it)
local function needConVar(name)
	local convar = GetConVar(name)

	expect(convar ~= nil).to.beTrue()

	return convar
end

-- Runs fn with the test runner's step hook (a count hook that checks the time of a step) taken off, and puts it back, also when fn raises. The hook allocates a
-- few KB each time it fires, and how often it fires depends on whether the JIT compiled the loop being measured (a compiled loop never fires it): a memory
-- measure under it says more about the JIT than about the code. Without it the measure is what the code allocates.
local function withoutRunnerHook(fn)
	local hookFn, mask, count = debug.gethook()

	debug.sethook()

	local ok, result = pcall(fn)

	if hookFn then
		debug.sethook(hookFn, mask, count)
	end

	if not ok then
		error(result, 0)
	end

	return result
end

-- three indoor boxes (cells x 0 to 2, ceiling class 3 = 120 units) then two outdoor ones (cells x 3 and 4, ceiling class 5 = 224 units), all on row 0, layer 0.
-- The cyan line of a box tells its kind by its height. A position at y = 500 is over no box.
local function mixedBoxes()
	return {boxes = {
		{0, 0, 0, 0, 0, 2, 3},
		{0, 1, 0, 1, 0, 2, 3},
		{0, 2, 0, 2, 0, 2, 3},
		{0, 3, 0, 3, 0, 1, 5},
		{0, 4, 0, 4, 0, 1, 5}
	}}
end

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

local function hasLabel(panel, text)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DLabel" and p:GetText() == text then
			return true
		end
	end

	return false
end

-- the section is a folding category (cl_options.lua): its title is the header of the category
local function hasCategory(panel, title)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "ControlPanel" and p.Header and p.Header:GetText() == title then
			return true
		end
	end

	return false
end

local function checkBoxOn(panel, convarName)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == convarName then
			return p
		end
	end
end

-- the button of the radar menu that deletes the in/out map and makes it again (flagged by cl_options_radar.lua)
local function resetButton(panel)
	for _, p in ipairs(walk(panel)) do
		if p.GryZoneMapReset then
			return p
		end
	end
end

-- Cuts `bytes` in pieces of the given sizes (the last piece takes what is left) and delivers them as the server would.
local function deliver(Z, bytes, sizes)
	local pieces, at = {}, 1

	for i = 1, #sizes do
		pieces[#pieces + 1] = string.sub(bytes, at, at + sizes[i] - 1)
		at = at + sizes[i]
	end

	if at <= #bytes then
		pieces[#pieces + 1] = string.sub(bytes, at)
	end

	for i, piece in ipairs(pieces) do
		Z.OnData(i - 1, #pieces, #piece, piece)
	end

	return #pieces
end

local function hookFunction()
	return (hook.GetTable()["PostDrawTranslucentRenderables"] or {})[HOOK]
end

local function hudHookFunction()
	return (hook.GetTable()["HUDPaint"] or {})[HUD_HOOK]
end

-- The drawing stand-ins: every call is recorded with copies of the numbers (the module reuses its Vectors and Colors, so a record must not keep them).
-- Returns the record: boxes (DrawBox), wires (DrawWireframeBox), lines (DrawLine), materials (the number of SetColorMaterial calls).
local function recordRender()
	local rec = {boxes = {}, wires = {}, lines = {}, materials = 0}

	render.SetColorMaterial = function()
		rec.materials = rec.materials + 1
	end
	render.DrawBox = function(origin, angle, mins, maxs, colour, writeZ)
		rec.boxes[#rec.boxes + 1] = {
			ox = origin.x, oy = origin.y, oz = origin.z, ap = angle.p, ay = angle.y, ar = angle.r,
			x1 = mins.x, y1 = mins.y, z1 = mins.z, x2 = maxs.x, y2 = maxs.y, z2 = maxs.z,
			r = colour.r, g = colour.g, b = colour.b, a = colour.a, writeZ = writeZ
		}
	end
	render.DrawWireframeBox = function(origin, angle, mins, maxs, colour, writeZ)
		rec.wires[#rec.wires + 1] = {
			ox = origin.x, oy = origin.y, oz = origin.z,
			x1 = mins.x, y1 = mins.y, z1 = mins.z, x2 = maxs.x, y2 = maxs.y, z2 = maxs.z,
			r = colour.r, g = colour.g, b = colour.b, a = colour.a, writeZ = writeZ
		}
	end
	render.DrawLine = function(from, to, colour)
		rec.lines[#rec.lines + 1] = {z1 = from.z, z2 = to.z, r = colour.r, g = colour.g, b = colour.b, a = colour.a}
	end

	return rec
end

-- render stand-ins that do nothing (for the allocation cases)
local function silentRender()
	render.SetColorMaterial = function() end
	render.DrawBox = function() end
	render.DrawWireframeBox = function() end
	render.DrawLine = function() end
end

-- draw.SimpleText stand-in: records text, font, x, y, the colour and the alignments
local function recordText()
	local calls = {}

	draw.SimpleText = function(text, font, x, y, colour, xalign, yalign)
		calls[#calls + 1] = {
			text = text, font = font, x = x, y = y, r = colour and colour.r, g = colour and colour.g, b = colour and colour.b, a = colour and colour.a,
			xalign = xalign, yalign = yalign
		}

		return 0, 0
	end

	return calls
end

-- the lines of the HUD block: the calls whose colour is not the dark shadow, in order
local function textLines(calls)
	local lines = {}

	for _, call in ipairs(calls) do
		if call.r + call.g + call.b > 200 then
			lines[#lines + 1] = call
		end
	end

	return lines
end

-- the distance from a point to a drawn box (the box's own world bounds, 0 along an axis the point is inside)
local function distanceTo(box, px, py, pz)
	local function axis(p, lo, hi)
		return p < lo and lo - p or (p > hi and p - hi or 0)
	end

	local dx, dy, dz = axis(px, box.x1, box.x2), axis(py, box.y1, box.y2), axis(pz, box.z1, box.z2)

	return dx * dx + dy * dy + dz * dz
end

-- the stand-in of the pure module: only what the receivers use
local function standInModule(state)
	return {
		Decode = function(bytes)
			if string.sub(bytes, 1, 3) ~= "MAP" then
				return nil, "bad magic"
			end

			return state.decoded or {boxes = {{0, 0, 0, 0, 0, 2, 0}}}, {complete = true, sampleCount = 1}
		end,
		Index = function(map)
			return {map = map}
		end,
		Lookup = function()
			return state.lookupState or 0, 0
		end,
		Count = function()
			return 1
		end
	}
end

-- boxes in a grid of cells (layer 0), each one cell: `columns` by `rows`
local function gridBoxes(columns, rows, ceil, named)
	local boxes = {}

	for cy = 0, rows - 1 do
		for cx = 0, columns - 1 do
			if named then
				boxes[#boxes + 1] = {layer = 0, x1 = cx, y1 = cy, x2 = cx, y2 = cy, state = 2, ceil = ceil}
			else
				boxes[#boxes + 1] = {0, cx, cy, cx, cy, 2, ceil}
			end
		end
	end

	return {boxes = boxes}
end

-- the player's position stand-in: a plain table with x, y, z (Draw reads only those)
local function at(x, y, z)
	return {x = x, y = y, z = z}
end

return {
	groupName = "GryMod zone map (client)",
	beforeEach = function(state)
		local Z = GryMod.ZoneMapClient

		state.saved = Z and Z.Save and Z.Save()
		state.module = GryMod.ZoneMap
		state.clock = Z and Z.Clock
		state.realStart, state.realSend = net.Start, net.SendToServer
		state.realReadUInt, state.realReadData = net.ReadUInt, net.ReadData
		state.realBox, state.realLine, state.realMat = render.DrawWireframeBox, render.DrawLine, render.SetColorMaterial
		state.realDrawBox = render.DrawBox
		state.realErrorNoHalt = ErrorNoHaltWithStack
		state.realDraw = GryMod.ZoneMapClient and GryMod.ZoneMapClient.Draw
		state.realDrawHud = GryMod.ZoneMapClient and GryMod.ZoneMapClient.DrawHud
		state.realText = draw.SimpleText
		state.range = GetConVar(RANGE) and GetConVar(RANGE):GetString()
		state.realAdd = notification and notification.AddLegacy
		state.realMap = game.GetMap
		state.realConfirm = GryMod.Confirm
		state.realIsAdmin = GryMod.AdminUI and GryMod.AdminUI.IsAdmin
		state.debug = GetConVar(DEBUG) and GetConVar(DEBUG):GetString()
		state.showIn = GetConVar(SHOW_IN) and GetConVar(SHOW_IN):GetString()
		state.showOut = GetConVar(SHOW_OUT) and GetConVar(SHOW_OUT):GetString()

		state.faces = GetConVar(FACES) and GetConVar(FACES):GetString()
		state.edges = GetConVar(EDGES) and GetConVar(EDGES):GetString()

		-- every case starts with both kinds shown, faces and edges drawn (the owner may have switched one off)
		for _, name in ipairs({SHOW_IN, SHOW_OUT, FACES, EDGES}) do
			if GetConVar(name) then
				GetConVar(name):SetString("1")
			end
		end

		state.sent = {}
		state.notices = {}
		state.asked = {}
		state.confirmAnswer = true
		state.now = 1000
		state.panel = nil
		state.decoded = nil
		state.lookupState = nil

		GryMod.ZoneMap = standInModule(state)

		if Z then
			if Z.Reset then
				Z.Reset()
			end

			Z.Clock = function()
				return state.now
			end
		end

		-- nothing leaves the game: the net messages are only recorded
		net.Start = function(name)
			state.sent[#state.sent + 1] = tostring(name)

			return true
		end
		net.SendToServer = function()
			state.sent[#state.sent + 1] = "send"
		end

		if notification then
			notification.AddLegacy = function(text)
				state.notices[#state.notices + 1] = tostring(text)
			end
		end

		GryMod.Confirm = function(text, onYes)
			state.asked[#state.asked + 1] = tostring(text)

			if state.confirmAnswer then
				onYes()
			end
		end
	end,
	afterEach = function(state)
		pcall(function()
			net.Start, net.SendToServer = state.realStart, state.realSend
			net.ReadUInt, net.ReadData = state.realReadUInt, state.realReadData
			render.DrawWireframeBox, render.DrawLine, render.SetColorMaterial = state.realBox, state.realLine, state.realMat
			render.DrawBox = state.realDrawBox
			draw.SimpleText = state.realText
			ErrorNoHaltWithStack = state.realErrorNoHalt

			if GryMod.ZoneMapClient then
				GryMod.ZoneMapClient.Draw = state.realDraw
				GryMod.ZoneMapClient.DrawHud = state.realDrawHud
			end
			notification.AddLegacy = state.realAdd
			game.GetMap = state.realMap
			GryMod.Confirm = state.realConfirm
			GryMod.ZoneMap = state.module

			if GryMod.AdminUI then
				GryMod.AdminUI.IsAdmin = state.realIsAdmin
			end

			if state.panel and IsValid(state.panel) then
				state.panel:Remove()
			end

			-- the range goes back, then the switch (its callback puts the hooks back in line), then the module's own state
			if state.range and GetConVar(RANGE) then
				GetConVar(RANGE):SetString(state.range)
			end

			if state.showIn and GetConVar(SHOW_IN) then
				GetConVar(SHOW_IN):SetString(state.showIn)
			end

			if state.showOut and GetConVar(SHOW_OUT) then
				GetConVar(SHOW_OUT):SetString(state.showOut)
			end

			if state.faces and GetConVar(FACES) then
				GetConVar(FACES):SetString(state.faces)
			end

			if state.edges and GetConVar(EDGES) then
				GetConVar(EDGES):SetString(state.edges)
			end

			if state.debug and GetConVar(DEBUG) then
				GetConVar(DEBUG):SetString(state.debug)
			end

			local Z = GryMod.ZoneMapClient

			if Z then
				Z.Clock = state.clock

				if state.saved and Z.Restore then
					Z.Restore(state.saved)
				end
			end
		end)
	end,
	cases = {
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the table and the receivers
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: the file is still the stub
			name = "GryMod.ZoneMapClient has Indoor, Status, StatusText, Reset, OnState, OnData and Want, and the two net messages are received",
			func = function()
				local Z = GryMod.ZoneMapClient

				expect(istable(Z)).to.beTrue()

				for _, name in ipairs({"Indoor", "Status", "StatusText", "Reset", "OnState", "OnData", "Want", "Draw", "BoxAt", "DrawHud", "DebugRangeUnits", "SelectionRuns"}) do
					expect(isfunction(Z[name])).to.beTrue()
				end

				expect(isfunction(net.Receivers["gry_zonemap_state"])).to.beTrue()
				expect(isfunction(net.Receivers["gry_zonemap_data"])).to.beTrue()
			end
		},
		{
			-- breaks if: a bit width or the order of the fields of gry_zonemap_state changes
			name = "the state message is read as UInt 3, UInt 24, UInt 24 in that order",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local widths, values = {}, {3, 42, 100}

				net.ReadUInt = function(bits)
					widths[#widths + 1] = bits

					return values[#widths]
				end

				net.Receivers["gry_zonemap_state"](0)
				net.ReadUInt = state.realReadUInt

				expect(widths[1]).to.equal(3)
				expect(widths[2]).to.equal(24)
				expect(widths[3]).to.equal(24)

				local s, done, total = Z.Status()

				expect(s).to.equal(3)
				expect(done).to.equal(42)
				expect(total).to.equal(100)
			end
		},
		{
			-- breaks if: the data message is read with other widths, or the data is not read with the length
			name = "the data message is read as UInt 16 index, UInt 16 count, UInt 16 length, then Data(length)",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local widths, values = {}, {0, 1, 7}
				local dataLength

				net.ReadUInt = function(bits)
					widths[#widths + 1] = bits

					return values[#widths]
				end
				net.ReadData = function(length)
					dataLength = length

					return "MAP1234"
				end

				net.Receivers["gry_zonemap_data"](0)
				net.ReadUInt, net.ReadData = state.realReadUInt, state.realReadData

				expect(#widths).to.equal(3)
				expect(widths[1]).to.equal(16)
				expect(widths[2]).to.equal(16)
				expect(widths[3]).to.equal(16)
				expect(dataLength).to.equal(7)

				-- the one chunk is a whole file: the map is there
				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(1)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the reassembly of the file
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "one chunk is a whole file: decoded, indexed, the box count is known, no reason",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}}}
				Z.OnState(4, 2, 2)
				Z.OnData(0, 1, 10, "MAP1234567")

				local s, _, _, boxes, reason = Z.Status()

				expect(s).to.equal(4)
				expect(boxes).to.equal(2)
				expect(reason).to.beNil()
				expect(Z.Indoor(at(0, 0, 0))).to.beNil()
			end
		},
		{
			-- the tile preload starts from this event and reads the boxes (it must not start from a map that is not there, or a refused file)
			-- breaks if: the event is not fired when a file is accepted, is fired for a refused one, or Boxes() gives boxes of a map that was dropped
			name = "an accepted file fires GryMod_InOutMapReady once with the number of boxes, and Boxes() gives them; a refused file or a state that drops the map does neither",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local fired = {}

				hook.Add("GryMod_InOutMapReady", "gry_zonemap_test_ready", function(count)
					fired[#fired + 1] = count
				end)

				local ok, err = pcall(function()
					expect(isfunction(Z.Boxes)).to.beTrue()
					expect(Z.Boxes()).to.beNil()

					state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}}}
					Z.OnState(4, 2, 2)
					Z.OnData(0, 1, 10, "MAP1234567")

					expect(#fired).to.equal(1)
					expect(fired[1]).to.equal(2)
					expect(#Z.Boxes()).to.equal(2)

					-- a state that says the map is being made again drops it
					Z.OnState(3, 1, 2)
					expect(Z.Boxes()).to.beNil()

					-- a file that is refused (the stand-in decoder refuses what does not start with "MAP")
					Z.OnState(4, 2, 2)
					Z.OnData(0, 1, 10, "XXX1234567")
					expect(#fired).to.equal(1)
					expect(Z.Boxes()).to.beNil()
				end)

				hook.Remove("GryMod_InOutMapReady", "gry_zonemap_test_ready")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "three chunks in order make the file",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}, {0, 2, 0, 2, 0, 1, 0}}}
				state.lookupState = 2

				expect(deliver(Z, "MAP" .. string.rep("x", 27), {10, 10})).to.equal(3)

				local _, _, _, boxes, reason = Z.Status()

				expect(boxes).to.equal(3)
				expect(reason).to.beNil()
				expect(Z.Indoor(at(5, 5, 5))).to.beTrue()
				expect(#state.sent).to.equal(0)
			end
		},
		{
			-- breaks if: a missing chunk is skipped over, so that a file with a hole is decoded
			name = "a gap (chunk 1 missing) drops the set, asks again with gry_zonemap_want, and no map comes of it",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnData(0, 3, 10, "MAP1234567")
				Z.OnData(2, 3, 10, "7654321000")

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(0)
				expect(Z.Indoor(at(0, 0, 0))).to.beNil()
				expect(state.sent[1]).to.equal("gry_zonemap_want")
				expect(state.sent[2]).to.equal("send")

				-- the dropped set does not come back to life with the chunk that followed the gap
				Z.OnData(1, 3, 10, "xxxxxxxxxx")
				local _, _, _, again = Z.Status()

				expect(again).to.equal(0)
			end
		},
		{
			name = "a set that does not start at index 0 is dropped and asked again",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnData(1, 2, 10, "MAP1234567")

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(0)
				expect(state.sent[1]).to.equal("gry_zonemap_want")
			end
		},
		{
			name = "an out of order chunk (index 2 before index 1) drops the set",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnData(0, 3, 10, "MAP1234567")
				Z.OnData(2, 3, 10, "xxxxxxxxxx")
				Z.OnData(1, 3, 10, "yyyyyyyyyy")

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(0)
				expect(state.sent[1]).to.equal("gry_zonemap_want")
			end
		},
		{
			name = "a chunk whose length is not the length written is dropped, like a gap",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnData(0, 2, 10, "MAP1234567")
				Z.OnData(1, 2, 10, "short")

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(0)
				expect(state.sent[1]).to.equal("gry_zonemap_want")
			end
		},
		{
			-- breaks if: index 0 does not start a new set, so that the old chunks stay
			name = "a new set starts at index 0 and forgets the half of the old one; the new one makes the map",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}}}
				Z.OnData(0, 3, 10, "MAP1234567")
				Z.OnData(1, 3, 10, "xxxxxxxxxx")

				-- a new set of two chunks
				Z.OnData(0, 2, 10, "MAPabcdefg")
				Z.OnData(1, 2, 4, "hijk")

				local _, _, _, boxes, reason = Z.Status()

				expect(boxes).to.equal(2)
				expect(reason).to.beNil()
				expect(#state.sent).to.equal(0)
			end
		},
		{
			name = "a map that was received is replaced by the next one",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}}}
				Z.OnData(0, 1, 4, "MAP1")
				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}, {0, 2, 0, 2, 0, 1, 0}}}
				Z.OnData(0, 1, 4, "MAP2")

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(3)
			end
		},
		{
			-- breaks if: a bad file raises, or is kept as a map, or the reason is lost
			name = "a corrupt file is refused with a reason, raises nothing, and leaves no map",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnState(4, 1, 1)
				expect(function()
					Z.OnData(0, 1, 7, "garbage")
				end).to.succeed()

				local s, _, _, boxes, reason = Z.Status()

				expect(s).to.equal(4)
				expect(boxes).to.equal(0)
				expect(isstring(reason)).to.beTrue()
				expect(string.find(reason, "bad magic", 1, true) ~= nil).to.beTrue()
				expect(Z.Indoor(at(0, 0, 0))).to.beNil()

				-- the panel's line tells it
				expect(string.find(Z.StatusText(), "bad magic", 1, true) ~= nil).to.beTrue()

				-- no endless loop of requests: a refused file is not asked again
				expect(#state.sent).to.equal(0)

				-- a good file after it clears the reason
				Z.OnData(0, 1, 4, "MAP1")
				local _, _, _, good, noReason = Z.Status()

				expect(good).to.equal(1)
				expect(noReason).to.beNil()
			end
		},
		{
			name = "a module that raises while decoding is a refusal with a reason, not an error",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GryMod.ZoneMap.Decode = function()
					error("boom")
				end

				expect(function()
					Z.OnData(0, 1, 4, "MAP1")
				end).to.succeed()

				local _, _, _, boxes, reason = Z.Status()

				expect(boxes).to.equal(0)
				expect(isstring(reason)).to.beTrue()
			end
		},
		{
			name = "the module missing is a refusal with a reason, not an error",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GryMod.ZoneMap = nil

				expect(function()
					Z.OnData(0, 1, 4, "MAP1")
				end).to.succeed()

				local _, _, _, boxes, reason = Z.Status()

				expect(boxes).to.equal(0)
				expect(isstring(reason)).to.beTrue()
				expect(Z.Indoor(at(0, 0, 0))).to.beNil()
			end
		},
		{
			-- breaks if: the gap asks again at every chunk (a flood), or never asks again after 5 seconds
			name = "the repeated want is limited to one every 5 seconds",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				local function gapOnce()
					Z.OnData(0, 3, 10, "MAP1234567")
					Z.OnData(2, 3, 10, "xxxxxxxxxx")
				end

				local function wants()
					local n = 0

					for _, entry in ipairs(state.sent) do
						if entry == "gry_zonemap_want" then
							n = n + 1
						end
					end

					return n
				end

				gapOnce()
				expect(wants()).to.equal(1)

				state.now = state.now + 4.9
				gapOnce()
				expect(wants()).to.equal(1)

				state.now = state.now + 0.2
				gapOnce()
				expect(wants()).to.equal(2)

				state.now = state.now + 1
				gapOnce()
				expect(wants()).to.equal(2)
			end
		},
		{
			-- breaks if: the first want, sent when the game starts, is the only one (measured on the owner's game: the server has no player yet at that moment and
			-- drops it, so the client never got the map), or if it goes on asking after the server has answered, or without an end
			name = "the want at the start is repeated every 3 seconds until the server answers, at most 10 times, stops as soon as a state has come, and a new start replaces the old chain",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local realTimer, realWant = Z.Timer, Z.Want
				local wants, pending = 0, {}

				local ok, err = pcall(function()
					Z.Want = function() wants = wants + 1 end
					Z.Timer = function(delay, fn) pending[#pending + 1] = {delay = delay, fn = fn} end

					expect(isfunction(Z.AskUntilAnswered)).to.beTrue()
					Z.AskUntilAnswered()
					expect(wants).to.equal(1)
					expect(#pending).to.equal(1)
					expect(pending[1].delay).to.equal(3)

					-- no answer yet: asked again, up to 10 times in all
					for i = 2, 10 do
						local step = table.remove(pending, 1)

						step.fn()
						expect(wants).to.equal(i)
					end

					expect(#pending).to.equal(0)

					-- an answer stops it
					wants, pending = 0, {}
					Z.AskUntilAnswered()
					expect(wants).to.equal(1)
					Z.OnState(3, 10, 100)
					pending[1].fn()
					expect(wants).to.equal(1)
					expect(#pending).to.equal(1)

					-- a new start replaces the chain of the old one: its timer, when it runs, asks nothing
					Z.Reset()
					wants, pending = 0, {}
					Z.AskUntilAnswered()
					local old = pending[1]

					Z.AskUntilAnswered()
					expect(wants).to.equal(2)
					old.fn()
					expect(wants).to.equal(2)
					pending[2].fn()
					expect(wants).to.equal(3)
				end)

				Z.Timer, Z.Want = realTimer, realWant

				if not ok then error(err, 0) end
			end
		},
		{
			-- the radar shows its veil while the in/out map is not there: from the moment the client asks (before any answer), while the server waits or computes (with its
			-- percentage), and while the file is on its way; not when it is off, has no graph or failed (there is nothing to wait for)
			name = "Loading: the veil is wanted from the ask until the map is there, with the server's percentage while it computes, and not for states 0, 1 and 6",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local realTimer, realWant = Z.Timer, Z.Want

				local ok, err = pcall(function()
					Z.Timer, Z.Want = function() end, function() end

					expect(isfunction(Z.Loading)).to.beTrue()
					-- nothing asked yet (a module that was just reset): nothing to wait for
					expect(Z.Loading()).to.beFalse()

					Z.AskUntilAnswered()
					-- the grace of a quarter of a second: no flicker for a map that is made in a few frames
					expect(Z.Loading()).to.beFalse()
					state.now = state.now + 0.3
					expect(Z.Loading()).to.beTrue()

					-- the server waits: still the veil, 0 %
					Z.OnState(2, 0, 0)
					local loading, percent = Z.Loading()
					expect(loading).to.beTrue()
					expect(percent).to.equal(0)

					-- computing: its percentage (whole, no division by 0)
					Z.OnState(3, 41, 100)
					loading, percent = Z.Loading()
					expect(loading).to.beTrue()
					expect(percent).to.equal(41)
					Z.OnState(3, 0, 0)
					loading, percent = Z.Loading()
					expect(percent).to.equal(0)

					-- ready but the file has not come: still the veil
					Z.OnState(4, 10, 10)
					expect((Z.Loading())).to.beTrue()

					-- the file came: no more veil
					Z.OnData(0, 1, 4, "ABCD")
					expect(Z.Loading()).to.beFalse()
				end)

				if ok then
					ok, err = pcall(function()
						-- off, no graph, failed: nothing to wait for
						for _, s in ipairs({0, 1, 6}) do
							Z.Reset()
							Z.AskUntilAnswered()
							state.now = state.now + 0.3
							Z.OnState(s, 0, 0)
							expect(Z.Loading()).to.beFalse()
						end

						-- a server that never answers: the veil ends with the ask (10 wants, 3 seconds apart)
						Z.Reset()
						Z.AskUntilAnswered()
						Z.Loading() -- the grace starts at the first look
						state.now = state.now + 0.3
						expect(Z.Loading()).to.beTrue()
						state.now = state.now + 31
						expect(Z.Loading()).to.beFalse()
					end)
				end

				Z.Timer, Z.Want = realTimer, realWant

				if not ok then error(err, 0) end
			end
		},
		{
			-- the owner's decision (2026-11-22): while the server waits for the navigation mesh (state 2) the engine gives no progress, so the radar must not show a
			-- percentage: Loading's third answer is the phase, "wait" for the state 2 and "percent" for everything else (asking, computing, the file on its way).
			-- Breaks if the state 2 gives "percent" (the veil would show "In/out 0%" again), if the phase is missing, if state 3 is "wait", or if the grace changes
			name = "Loading: the third answer is the phase: 'wait' for the state 2 (no percentage to show), 'percent' for the asking, the state 3 and the file on its way; the grace is the same and 2 to 3 keeps it",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local realTimer, realWant = Z.Timer, Z.Want

				local ok, err = pcall(function()
					Z.Timer, Z.Want = function() end, function() end

					-- the first answer is awaited: a percentage (0), as before
					Z.Reset()
					Z.AskUntilAnswered()
					Z.Loading() -- the grace starts at the first look
					state.now = state.now + 0.3
					local loading, percent, phase = Z.Loading()
					expect(loading).to.beTrue()
					expect(percent).to.equal(0)
					expect(phase).to.equal("percent")

					-- the server waits for the navigation mesh: the veil, the phase "wait"
					Z.OnState(2, 0, 0)
					loading, percent, phase = Z.Loading()
					expect(loading).to.beTrue()
					expect(phase).to.equal("wait")

					-- it computes: the percentage again; the grace was counted once (no new quarter of a second)
					Z.OnState(3, 41, 100)
					loading, percent, phase = Z.Loading()
					expect(loading).to.beTrue()
					expect(percent).to.equal(41)
					expect(phase).to.equal("percent")

					-- the file is on its way: a percentage
					Z.OnState(4, 10, 10)
					loading, percent, phase = Z.Loading()
					expect(loading).to.beTrue()
					expect(phase).to.equal("percent")

					-- a state 2 on a fresh start still has the grace of a quarter of a second (a map found in a few frames does not flash the veil)
					Z.Reset()
					Z.OnState(2, 0, 0)
					expect(Z.Loading()).to.beFalse()
					state.now = state.now + 0.2
					expect(Z.Loading()).to.beFalse()
					state.now = state.now + 0.1
					loading, percent, phase = Z.Loading()
					expect(loading).to.beTrue()
					expect(phase).to.equal("wait")
				end)

				Z.Timer, Z.Want = realTimer, realWant

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if the front (the HUD, another addon) is not told of the changes of the in/out map, or if a hook that raises stops the receiver
			name = "every state message runs the hook GryMod_InOutMapState with the state, done and total, and a hook that raises changes nothing",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local seen = {}
				local id = "GryMod test inout"

				local ok, err = pcall(function()
					hook.Add("GryMod_InOutMapState", id, function(s, d, t)
						seen[#seen + 1] = {s, d, t}
					end)

					Z.OnState(3, 5, 50)
					Z.OnState(4, 50, 50)
					expect(#seen).to.equal(2)
					expect(seen[1][1]).to.equal(3)
					expect(seen[1][2]).to.equal(5)
					expect(seen[1][3]).to.equal(50)
					expect(seen[2][1]).to.equal(4)

					-- a state that is refused (out of range) runs nothing
					Z.OnState(9, 0, 0)
					expect(#seen).to.equal(2)

					-- a hook that raises
					hook.Add("GryMod_InOutMapState", id .. " bad", function() error("boom") end)
					expect(function() Z.OnState(2, 0, 0) end).to.succeed()
					expect((Z.Status())).to.equal(2)
				end)

				hook.Remove("GryMod_InOutMapState", id)
				hook.Remove("GryMod_InOutMapState", id .. " bad")

				if not ok then error(err, 0) end
			end
		},
		{
			name = "bad chunk numbers (count 0, index not under count, length 0, not numbers) are dropped without an error",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				expect(function()
					Z.OnData(0, 0, 4, "MAP1")
					Z.OnData(5, 2, 4, "MAP1")
					Z.OnData(0, 1, 0, "")
					Z.OnData(nil, nil, nil, nil)
					Z.OnData(0, 1, 4, nil)
				end).to.succeed()

				local _, _, _, boxes = Z.Status()

				expect(boxes).to.equal(0)
			end
		},
		{
			-- breaks if: a state that says the map is being made again leaves the old map in use
			name = "a state 0, 1, 2, 3 or 6 drops the map and the half set (a stale map must not answer); 4 and 5 keep it",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.lookupState = 2

				for _, s in ipairs({0, 1, 2, 3, 6}) do
					Z.OnData(0, 1, 4, "MAP1")
					expect(Z.Indoor(at(0, 0, 0))).to.beTrue()
					Z.OnState(s, 1, 2)
					expect(Z.Indoor(at(0, 0, 0))).to.beNil()

					local _, _, _, boxes = Z.Status()

					expect(boxes).to.equal(0)
				end

				Z.OnData(0, 1, 4, "MAP1")
				Z.OnState(4, 1, 1)
				expect(Z.Indoor(at(0, 0, 0))).to.beTrue()
				Z.OnState(5, 1, 1)
				expect(Z.Indoor(at(0, 0, 0))).to.beTrue()
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- Indoor
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "Indoor is nil with no map",
			func = function()
				expect(GryMod.ZoneMapClient.Indoor(at(0, 0, 0))).to.beNil()
			end
		},
		{
			-- breaks if: the answers 2 / 1 / 0 of the lookup are not true / false / nil
			name = "Indoor: lookup state 2 is true, 1 is false, 0 is nil (the module's lookup, read once per call)",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				Z.OnData(0, 1, 4, "MAP1")

				state.lookupState = 2
				expect(Z.Indoor(at(1, 2, 3))).to.equal(true)
				state.lookupState = 1
				expect(Z.Indoor(at(1, 2, 3))).to.equal(false)
				state.lookupState = 0
				expect(Z.Indoor(at(1, 2, 3))).to.beNil()
			end
		},
		{
			name = "Indoor reads pos.x, pos.y, pos.z and gives them to the lookup, and takes a real Vector",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local seen

				Z.OnData(0, 1, 4, "MAP1")
				GryMod.ZoneMap.Lookup = function(index, x, y, z)
					seen = {index ~= nil, x, y, z}

					return 2, 0
				end

				expect(Z.Indoor(Vector(10, 20, 30))).to.beTrue()
				expect(seen[1]).to.beTrue()
				expect(seen[2]).to.equal(10)
				expect(seen[3]).to.equal(20)
				expect(seen[4]).to.equal(30)
			end
		},
		{
			name = "Indoor with a missing position, missing numbers or NaN is nil and raises nothing",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.lookupState = 2
				Z.OnData(0, 1, 4, "MAP1")

				expect(function()
					expect(Z.Indoor(nil)).to.beNil()
					expect(Z.Indoor(12)).to.beNil()
					expect(Z.Indoor({})).to.beNil()
					expect(Z.Indoor({x = 1, y = 2})).to.beNil()
					expect(Z.Indoor({x = 0 / 0, y = 0, z = 0})).to.beNil()
					expect(Z.Indoor({x = 1, y = math.huge, z = 0})).to.beNil()
				end).to.succeed()
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the status and its line
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "before any message the state is unknown and the line says not received yet",
			func = function()
				local Z = GryMod.ZoneMapClient
				local s = Z.Status()

				expect(s).to.beNil()
				expect(Z.StatusText()).to.equal("In/out map: not received yet")
			end
		},
		{
			name = "Status gives state, done, total for each state 0 to 6, and StatusText tells each one",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local PREFIX = "In/out map: "

				local wanted = {
					[0] = "off on this server",
					[1] = "no graph on this map",
					[2] = "waiting",
					[3] = "computing 42 %",
					[6] = "failed (see the server log)"
				}

				for s = 0, 6 do
					if wanted[s] then
						Z.OnState(s, s == 3 and 42 or 0, s == 3 and 100 or 0)

						local got, done, total = Z.Status()

						expect(got).to.equal(s)
						expect(done).to.equal(s == 3 and 42 or 0)
						expect(total).to.equal(s == 3 and 100 or 0)
						expect(Z.StatusText()).to.equal(PREFIX .. wanted[s])
					end
				end

				-- ready, with the map: the box count
				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}, {0, 2, 0, 2, 0, 1, 0}}}
				Z.OnState(4, 5, 5)
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.StatusText()).to.equal(PREFIX .. "ready, 3 boxes")

				-- incomplete
				Z.OnState(5, 4, 5)
				expect(string.find(Z.StatusText(), "incomplete", 1, true) ~= nil).to.beTrue()
				expect(string.find(Z.StatusText(), "not every node was used", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			name = "the percentage while computing is whole, and 0 % when the total is 0 (no division by 0)",
			func = function()
				local Z = GryMod.ZoneMapClient

				Z.OnState(3, 1, 3)
				expect(Z.StatusText()).to.equal("In/out map: computing 33 %")
				Z.OnState(3, 0, 0)
				expect(Z.StatusText()).to.equal("In/out map: computing 0 %")
				Z.OnState(3, 7, 7)
				expect(Z.StatusText()).to.equal("In/out map: computing 100 %")
			end
		},
		{
			name = "ready before the data came says so (the map is on its way), and a state 7 or beyond is ignored",
			func = function()
				local Z = GryMod.ZoneMapClient

				Z.OnState(4, 3, 3)
				expect(string.find(Z.StatusText(), "ready", 1, true) ~= nil).to.beTrue()
				expect(string.find(Z.StatusText(), "0 boxes", 1, true) == nil).to.beTrue()

				Z.OnState(7, 0, 0)
				Z.OnState(-1, 0, 0)
				Z.OnState(nil, 0, 0)
				expect((Z.Status())).to.equal(4)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the notice for an incomplete map
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: the notice is sent at every state 5, or never, or for another state
			name = "a state 5 tells the player once per map, not for the other states, again for another map",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				game.GetMap = function() return "gm_test_a" end

				Z.OnState(4, 1, 1)
				Z.OnState(3, 1, 2)
				expect(#state.notices).to.equal(0)

				Z.OnState(5, 1, 1)
				expect(#state.notices).to.equal(1)
				expect(string.find(state.notices[1], "was not made from every node", 1, true) ~= nil).to.beTrue()
				expect(string.find(state.notices[1], "in/out map", 1, true) ~= nil).to.beTrue()

				Z.OnState(5, 1, 1)
				Z.OnData(0, 1, 4, "MAP1")
				Z.OnState(4, 1, 1)
				Z.OnState(5, 1, 1)
				expect(#state.notices).to.equal(1)

				game.GetMap = function() return "gm_test_b" end
				Z.OnState(5, 1, 1)
				expect(#state.notices).to.equal(2)
			end
		},
		{
			name = "the notice does not fail when notification is missing",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				notification.AddLegacy = nil

				expect(function()
					Z.OnState(5, 1, 1)
				end).to.succeed()
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- asking for the map
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "Want sends gry_zonemap_want with no payload",
			func = function(state)
				GryMod.ZoneMapClient.Want()

				expect(state.sent[1]).to.equal("gry_zonemap_want")
				expect(state.sent[2]).to.equal("send")
				expect(#state.sent).to.equal(2)
			end
		},
		{
			name = "Want does not raise when the net string is not known (net.Start raises)",
			func = function(state)
				net.Start = function() error("unpooled message name") end

				expect(function()
					GryMod.ZoneMapClient.Want()
				end).to.succeed()
			end
		},
		{
			-- breaks if: the switch going on does not ask the server
			name = "the switch gry_zonemap going on asks for the map; going off does not",
			func = function(state)
				cvars.OnConVarChanged("gry_zonemap", "0", "0")
				expect(#state.sent).to.equal(0)

				cvars.OnConVarChanged("gry_zonemap", "0", "1")
				expect(state.sent[1]).to.equal("gry_zonemap_want")
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the debug drawing
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "gry_zonemap_debug is a client convar, 0 by default, saved with the settings",
			func = function()
				local convar = GetConVar(DEBUG)

				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("0")

				-- the engine does not show the archive bit in GetFlags (measured: 268763144 for every archived client convar of GryMod): the flags are those of
				-- another setting made the same way
				expect(convar:GetFlags()).to.equal(GetConVar("gry_minimap"):GetFlags())
			end
		},
		{
			-- breaks if: the hook is added at load whatever the convar says, or stays after the convar goes to 0
			name = "the debug hook is added when the convar becomes 1, removed when it becomes 0, and absent while it is 0",
			func = function(state)
				local convar = GetConVar(DEBUG)

				convar:SetString("0")
				expect(hookFunction()).to.beNil()
				expect(hudHookFunction()).to.beNil()

				convar:SetString("1")
				expect(isfunction(hookFunction())).to.beTrue()
				expect(isfunction(hudHookFunction())).to.beTrue()

				convar:SetString("0")
				expect(hookFunction()).to.beNil()
				expect(hudHookFunction()).to.beNil()

				-- again, and twice on in a row: one hook of each, not a pile
				convar:SetString("1")
				convar:SetString("1")
				expect(isfunction(hookFunction())).to.beTrue()
				expect(isfunction(hudHookFunction())).to.beTrue()
				convar:SetString("0")
				expect(hookFunction()).to.beNil()
				expect(hudHookFunction()).to.beNil()
			end
		},
		{
			-- breaks if: the HUD function does not draw the block of the player's place (the hook must reach DrawHud with the local player's position)
			name = "the HUD hook draws the block (the status line when no map is there) and the 3D hook draws nothing when there is no map, nor in the skybox passes",
			func = function(state)
				local convar = GetConVar(DEBUG)

				GryMod.ZoneMapClient.Reset()
				convar:SetString("1")

				local calls = recordText()
				local rec = recordRender()

				hudHookFunction()()
				expect(#textLines(calls)).to.equal(1)
				expect(textLines(calls)[1].text).to.equal("In/out map: not received yet")

				hookFunction()(false, false, false)
				hookFunction()(false, true, false)
				hookFunction()(false, false, true)
				expect(#rec.boxes + #rec.wires + #rec.lines).to.equal(0)
			end
		},
		{
			-- breaks if: a hook runs its drawing without a guard (an error every frame: thousands of lines in a minute), the error is printed more than once, a hook stays,
			-- the switch stays at 1, the player is not told, or the next activation is not reported again
			name = "a drawing that raises (3D or HUD) is reported once with its stack, the switch goes to 0, both hooks are gone and the player is told once; the next activation reports again",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(DEBUG)
				local printed = {}

				ErrorNoHaltWithStack = function(text)
					printed[#printed + 1] = tostring(text)
				end

				for _, which in ipairs({"3D", "HUD"}) do
					printed, state.notices = {}, {}

					Z.Draw = function() error("boom in the 3D drawing") end
					Z.DrawHud = function() error("boom in the HUD drawing") end
					convar:SetString("1")

					local run = which == "3D" and hookFunction() or hudHookFunction()
					local wanted = which == "3D" and "boom in the 3D drawing" or "boom in the HUD drawing"

					-- the first frame: the error does not escape the hook
					expect(function() run(false, false, false) end).to.succeed()
					expect(#printed).to.equal(1)
					expect(string.find(printed[1], wanted, 1, true) ~= nil).to.beTrue()
					expect(hookFunction()).to.beNil()
					expect(hudHookFunction()).to.beNil()
					expect(convar:GetString()).to.equal("0")
					expect(#state.notices).to.equal(1)
					expect(string.find(state.notices[1], "The in/out map debug drawing stopped: ", 1, true) == 1).to.beTrue()
					expect(string.find(state.notices[1], wanted, 1, true) ~= nil).to.beTrue()

					-- a frame that still gets through (a function kept by the engine for the frame): nothing more is said
					expect(function() run(false, false, false) end).to.succeed()
					expect(#printed).to.equal(1)
					expect(#state.notices).to.equal(1)

					-- the switch on again: the hooks come back and the next error is reported
					convar:SetString("1")
					expect(isfunction(hookFunction())).to.beTrue()
					expect(isfunction(hudHookFunction())).to.beTrue()
					run = which == "3D" and hookFunction() or hudHookFunction()
					run(false, false, false)
					expect(#printed).to.equal(2)
					expect(#state.notices).to.equal(2)
					expect(convar:GetString()).to.equal("0")
				end
			end
		},
		{
			-- breaks if: the debug hook draws while a minimap tile capture runs (the boxes would be baked into the cached tiles), or stops drawing for the player
			name = "the debug boxes are not drawn during a minimap tile capture, and are drawn the rest of the time",
			func = function()
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(DEBUG)
				local Capture = GryMod.Minimap.Capture
				local wasDraw, wasCapturing, wasValue = Z.Draw, Capture.IsCapturing, convar:GetString()
				local calls = 0

				local ok, err = pcall(function()
					convar:SetString("1")
					Z.SyncDebugHook()
					Z.Draw = function() calls = calls + 1 end

					Capture.IsCapturing = function() return true end
					hookFunction()(nil, false, false)
					expect(calls).to.equal(0)

					Capture.IsCapturing = function() return false end
					hookFunction()(nil, false, false)
					expect(calls).to.equal(1)
				end)

				Z.Draw, Capture.IsCapturing = wasDraw, wasCapturing
				convar:SetString(wasValue)
				Z.SyncDebugHook()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "SyncDebugHook (what runs at load) puts the hook in line with the convar's current value",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(DEBUG)

				convar:SetString("1")
				hook.Remove("PostDrawTranslucentRenderables", HOOK)
				hook.Remove("HUDPaint", HUD_HOOK)
				expect(hookFunction()).to.beNil()
				expect(hudHookFunction()).to.beNil()
				Z.SyncDebugHook()
				expect(isfunction(hookFunction())).to.beTrue()
				expect(isfunction(hudHookFunction())).to.beTrue()

				convar:SetString("0")
				hook.Add("PostDrawTranslucentRenderables", HOOK, function() end)
				hook.Add("HUDPaint", HUD_HOOK, function() end)
				Z.SyncDebugHook()
				expect(hookFunction()).to.beNil()
				expect(hudHookFunction()).to.beNil()
			end
		},
		{
			-- breaks if: the range convar is missing, has another default, or has no limits (a slider could then send it anywhere)
			name = "gry_zonemap_debug_range is a client convar in metres: 120 by default, 20 to 300, saved with the settings",
			func = function()
				local convar = GetConVar(RANGE)

				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("120")
				expect(convar:GetMin()).to.equal(20)
				expect(convar:GetMax()).to.equal(300)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_minimap"):GetFlags())
			end
		},
		{
			-- breaks if: the conversion to units is not 0.01905 metres a unit (the same as the radar), or the convar is not read at all
			name = "DebugRangeUnits turns the convar's metres into units with 0.01905 metres per unit",
			func = function()
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(RANGE)

				convar:SetString("120")
				expect(Z.DebugRangeUnits()).to.aboutEqual(120 / METRES_PER_UNIT, 0.01)
				convar:SetString("20")
				expect(Z.DebugRangeUnits()).to.aboutEqual(20 / METRES_PER_UNIT, 0.01)
				convar:SetString("300")
				expect(Z.DebugRangeUnits()).to.aboutEqual(300 / METRES_PER_UNIT, 0.01)
			end
		},
		{
			-- breaks if: the cap of 800 boxes a frame is raised, lowered or removed
			name = "at most 800 boxes are drawn a frame (a filled box and a wire each), and 700 are all drawn",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GetConVar(RANGE):SetString("300")
				state.decoded = gridBoxes(30, 30, 0)
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				-- in the middle of the grid: all 900 are within 300 metres
				local drawn = Z.Draw(at(15 * 128 + 64, 15 * 128 + 64, 0))

				expect(drawn).to.equal(800)
				expect(#rec.boxes).to.equal(800)
				expect(#rec.wires).to.equal(800)
				expect(#rec.lines).to.equal(0)

				-- a map of 700 boxes: all of them
				state.decoded = gridBoxes(28, 25, 0)
				Z.OnData(0, 1, 4, "MAP1")
				rec = recordRender()
				expect(Z.Draw(at(14 * 128 + 64, 12 * 128 + 64, 0))).to.equal(700)
				expect(#rec.boxes).to.equal(700)
				expect(#rec.wires).to.equal(700)
			end
		},
		{
			-- breaks if: the boxes drawn are the first 800 found (rows of the grid) and not the nearest, or the sort is by the wrong key
			name = "with more boxes than the cap, the NEAREST ones are the ones drawn (no drawn box is farther than a box left out), the corners are left out",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local px, py, pz = 15 * 128 + 64, 15 * 128 + 64, 0

				GetConVar(RANGE):SetString("300")
				state.decoded = gridBoxes(30, 30, 0)
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				expect(Z.Draw(at(px, py, pz))).to.equal(800)

				local drawn = {}
				local farthestDrawn = 0

				for _, box in ipairs(rec.boxes) do
					drawn[box.x1 .. "," .. box.y1] = true
					farthestDrawn = math.max(farthestDrawn, distanceTo(box, px, py, pz))
				end

				local nearestLeftOut = math.huge
				local leftOut = 0

				for cy = 0, 29 do
					for cx = 0, 29 do
						if not drawn[(cx * 128) .. "," .. (cy * 128)] then
							leftOut = leftOut + 1
							nearestLeftOut = math.min(nearestLeftOut, distanceTo({x1 = cx * 128, y1 = cy * 128, z1 = -64, x2 = cx * 128 + 128, y2 = cy * 128 + 128, z2 = 64}, px, py, pz))
						end
					end
				end

				expect(leftOut).to.equal(100)
				expect(farthestDrawn <= nearestLeftOut).to.beTrue()

				-- the box under the player is drawn, the four corners of the grid are not
				expect(drawn[(15 * 128) .. "," .. (15 * 128)]).to.beTrue()

				for _, corner in ipairs({{0, 0}, {29, 0}, {0, 29}, {29, 29}}) do
					expect(drawn[(corner[1] * 128) .. "," .. (corner[2] * 128)]).to.beNil()
				end
			end
		},
		{
			-- breaks if: the selection is made at every frame (the cost of the sort and of the scan is paid 60 times a second), or never made again
			name = "the selection of the boxes is made at most four times a second, or when the player moved more than 64 units, or when the range changed: not every frame",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GetConVar(RANGE):SetString("300")
				state.decoded = gridBoxes(30, 30, 0)
				Z.OnData(0, 1, 4, "MAP1")
				silentRender()

				local x, y = 15 * 128 + 64, 15 * 128 + 64

				expect(Z.SelectionRuns()).to.equal(0)
				Z.Draw(at(x, y, 0))
				expect(Z.SelectionRuns()).to.equal(1)

				-- sixty frames at the same place and the same time: the selection of the first
				for _ = 1, 60 do
					Z.Draw(at(x, y, 0))
				end

				expect(Z.SelectionRuns()).to.equal(1)

				-- 60 units away from where it was made: still the same
				Z.Draw(at(x + 60, y, 0))
				expect(Z.SelectionRuns()).to.equal(1)

				-- 70 units away: made again (here, at 70)
				Z.Draw(at(x + 70, y, 0))
				expect(Z.SelectionRuns()).to.equal(2)

				-- a fifth of a second later at the same place: not yet
				state.now = state.now + 0.2
				Z.Draw(at(x + 70, y, 0))
				expect(Z.SelectionRuns()).to.equal(2)

				-- more than a quarter of a second after the last one: made again
				state.now = state.now + 0.06
				Z.Draw(at(x + 70, y, 0))
				expect(Z.SelectionRuns()).to.equal(3)

				-- the range changed (the slider): at once
				GetConVar(RANGE):SetString("200")
				Z.Draw(at(x + 70, y, 0))
				expect(Z.SelectionRuns()).to.equal(4)

				-- a new map: the selection is the new map's
				state.decoded = gridBoxes(3, 3, 0)
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				expect(Z.Draw(at(x + 70, y, 0))).to.equal(9)
				expect(#rec.boxes).to.equal(9)
				expect(Z.SelectionRuns()).to.equal(1)
			end
		},
		{
			-- breaks if: the range test is dropped (everything is drawn), the range is a fixed number, or the convar's metres are not turned into units
			name = "only the boxes within the convar's range of the player are drawn: 20, 50 and 120 metres give three different sets",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(RANGE)

				-- 20 metres = 1049.9 units, 50 metres = 2624.7 units, 120 metres = 6299.2 units
				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 0},     -- the cell at the player: in at any range
					{0, 20, 0, 20, 0, 1, 0},   -- from x = 2560: nearest edge 2560 away: in at 50 and 120
					{0, 21, 0, 21, 0, 1, 0},   -- from x = 2688: in at 120 only
					{20, 0, 0, 0, 0, 1, 0},    -- layer 20: z = 2496 to 2624, 2496 above: in at 50 and 120 (3D distance)
					{22, 0, 0, 0, 0, 1, 0},    -- layer 22: z from 2752: in at 120 only
					{0, 60, 0, 60, 0, 1, 0}    -- from x = 7680: out at any range
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local function count(metres)
					convar:SetString(tostring(metres))

					local rec = recordRender()
					local drawn = Z.Draw(at(0, 0, 0))

					expect(#rec.boxes).to.equal(drawn)

					return drawn
				end

				expect(count(20)).to.equal(1)
				expect(count(50)).to.equal(3)
				expect(count(120)).to.equal(5)
			end
		},
		{
			-- breaks if: the box is drawn from other corners, with an origin, an angle, or with writes to the depth buffer (the translucent boxes would hide each other)
			name = "a box is drawn filled and as a wire from x1 * 128 to (x2 + 1) * 128, likewise y, z from layer * 128 - 64 to + 64, origin 0, angle 0, no depth write, with the colour material set",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{2, -3, 4, -1, 6, 2, 0}}}
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				expect(Z.Draw(at(-200, 700, 256))).to.equal(1)
				expect(rec.materials >= 1).to.beTrue()
				expect(#rec.boxes).to.equal(1)
				expect(#rec.wires).to.equal(1)

				for _, drawn in ipairs({rec.boxes[1], rec.wires[1]}) do
					-- the box is drawn with an origin of 0 and the corners given in the world (so that nothing is built per box)
					expect(drawn.ox).to.equal(0)
					expect(drawn.oy).to.equal(0)
					expect(drawn.oz).to.equal(0)
					expect(drawn.x1).to.equal(-3 * 128)
					expect(drawn.y1).to.equal(4 * 128)
					expect(drawn.z1).to.equal(2 * 128 - 64)
					expect(drawn.x2).to.equal(0)
					expect(drawn.y2).to.equal(7 * 128)
					expect(drawn.z2).to.equal(2 * 128 + 64)
					expect(drawn.writeZ).to.equal(false)
				end

				expect(rec.boxes[1].ap).to.equal(0)
				expect(rec.boxes[1].ay).to.equal(0)
				expect(rec.boxes[1].ar).to.equal(0)
			end
		},
		{
			name = "the boxes may be named fields (layer, x1...) as well as positional",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = gridBoxes(5, 5, 3, true)
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				expect(Z.Draw(at(300, 300, 0))).to.equal(25)
				expect(#rec.boxes).to.equal(25)
				expect(#rec.wires).to.equal(25)
			end
		},
		{
			-- breaks if: the faces are opaque (alpha 255) or the colours are swapped, or the wire is as faint as the faces
			name = "faces: red for indoor, green for outdoor, translucent (alpha 38); the wire of every box at alpha 90",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 3},   -- indoor, class 3
					{0, 1, 0, 1, 0, 1, 0},   -- outdoor, no ceiling
					{0, 2, 0, 2, 0, 1, 5}    -- outdoor with a ceiling class 5
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				-- the player is over no box (y = 500 is the row 3): nothing is highlighted
				expect(Z.Draw(at(0, 500, 0))).to.equal(3)

				local face, wire = {}, {}

				for _, box in ipairs(rec.boxes) do
					face[box.x1 / 128] = box
				end

				for _, box in ipairs(rec.wires) do
					wire[box.x1 / 128] = box
				end

				expect(face[0].r > face[0].g).to.beTrue()
				expect(face[1].g > face[1].r).to.beTrue()
				expect(face[2].g > face[2].r).to.beTrue()

				for cx = 0, 2 do
					expect(face[cx].a).to.equal(38)
					expect(wire[cx].a).to.equal(90)
					-- the wire is the colour of its faces
					expect(wire[cx].r).to.equal(face[cx].r)
					expect(wire[cx].g).to.equal(face[cx].g)
				end
			end
		},
		{
			-- breaks if: the box the player stands in is not told from the others, or both of its alphas are not raised
			name = "the box the player is in is highlighted: faces at double the alpha (76), wire at full alpha; the others stay at 38 and 90",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 0},
					{0, 1, 0, 1, 0, 1, 0},
					{0, 2, 0, 2, 0, 1, 0}
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				-- inside the middle box
				Z.Draw(at(128 + 64, 64, 0))

				for _, box in ipairs(rec.boxes) do
					expect(box.a).to.equal(box.x1 == 128 and 76 or 38)
				end

				for _, box in ipairs(rec.wires) do
					expect(box.a).to.equal(box.x1 == 128 and 255 or 90)
				end
			end
		},
		{
			name = "a cyan line only where the ceiling class is not 0, going up by the class height",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 3},   -- indoor, class 3 (120)
					{0, 1, 0, 1, 0, 1, 0},   -- outdoor, no ceiling
					{0, 2, 0, 2, 0, 1, 5}    -- outdoor with a ceiling class 5 (224)
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local rec = recordRender()

				expect(Z.Draw(at(0, 0, 0))).to.equal(3)

				-- two lines (classes 3 and 5), cyan (no red, green and blue high), going up by the class height
				expect(#rec.lines).to.equal(2)
				expect(rec.lines[1].r).to.equal(0)
				expect(rec.lines[1].g > 100 and rec.lines[1].b > 100).to.beTrue()
				expect(rec.lines[1].z2 - rec.lines[1].z1).to.equal(120)
				expect(rec.lines[2].z2 - rec.lines[2].z1).to.equal(224)
			end
		},
		{
			-- breaks if: a convar is missing, is not saved with the settings, has another default (a hidden kind by default would surprise the player) or has no limits
			name = "gry_zonemap_debug_in and gry_zonemap_debug_out are client convars, 1 by default, 0 or 1, saved with the settings",
			func = function(state)
				for _, name in ipairs({SHOW_IN, SHOW_OUT}) do
					local convar = needConVar(name)

					expect(convar:GetDefault()).to.equal("1")
					expect(convar:GetMin()).to.equal(0)
					expect(convar:GetMax()).to.equal(1)
					-- the engine does not show the archive bit (see the test of gry_zonemap_debug): the flags are those of another saved setting
					expect(convar:GetFlags()).to.equal(GetConVar("gry_minimap"):GetFlags())
				end
			end
		},
		{
			-- breaks if: the filter is inverted, only one of the two convars is read, or the cyan line of a hidden box is still drawn
			name = "each filter hides its own kind and only that kind: the faces, the wires and the ceiling line of the hidden boxes are not drawn",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local away = at(0, 500, 0)

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")

				-- both on: the five boxes, five lines (three of 120, two of 224)
				local rec = recordRender()

				expect(Z.Draw(away)).to.equal(5)
				expect(#rec.boxes).to.equal(5)
				expect(#rec.wires).to.equal(5)
				expect(#rec.lines).to.equal(5)

				-- the indoor ones hidden: the two outdoor boxes (green), their two lines (224)
				needConVar(SHOW_IN):SetString("0")
				rec = recordRender()
				expect(Z.Draw(away)).to.equal(2)
				expect(#rec.boxes).to.equal(2)
				expect(#rec.wires).to.equal(2)
				expect(#rec.lines).to.equal(2)

				for _, box in ipairs(rec.boxes) do
					expect(box.g > box.r).to.beTrue()
					expect(box.x1 == 3 * 128 or box.x1 == 4 * 128).to.beTrue()
				end

				for _, wire in ipairs(rec.wires) do
					expect(wire.g > wire.r).to.beTrue()
				end

				for _, line in ipairs(rec.lines) do
					expect(line.z2 - line.z1).to.equal(224)
				end

				-- the outdoor ones hidden: the three indoor boxes (red), their three lines (120)
				needConVar(SHOW_IN):SetString("1")
				needConVar(SHOW_OUT):SetString("0")
				rec = recordRender()
				expect(Z.Draw(away)).to.equal(3)
				expect(#rec.boxes).to.equal(3)
				expect(#rec.wires).to.equal(3)
				expect(#rec.lines).to.equal(3)

				for _, box in ipairs(rec.boxes) do
					expect(box.r > box.g).to.beTrue()
					expect(box.x1 <= 2 * 128).to.beTrue()
				end

				for _, wire in ipairs(rec.wires) do
					expect(wire.r > wire.g).to.beTrue()
				end

				for _, line in ipairs(rec.lines) do
					expect(line.z2 - line.z1).to.equal(120)
				end
			end
		},
		{
			-- breaks if: the filter is applied after the selection of the nearest boxes and the cap (the hidden boxes then use up places of the cap)
			name = "the cap of 800 counts only the boxes of the shown kind: 1200 indoor and 400 outdoor boxes, each kind alone fills (or does not exceed) what it should",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local boxes = {}

				-- a grid of 40 by 40 cells: the outdoor ones on the cells where both numbers are even (400), the others indoor (1200)
				for cy = 0, 39 do
					for cx = 0, 39 do
						local outdoor = cx % 2 == 0 and cy % 2 == 0

						boxes[#boxes + 1] = {0, cx, cy, cx, cy, outdoor and 1 or 2, 0}
					end
				end

				GetConVar(RANGE):SetString("300")
				state.decoded = {boxes = boxes}
				Z.OnData(0, 1, 4, "MAP1")

				local middle = at(20 * 128 + 64, 20 * 128 + 64, 0)

				-- both: capped at 800, of both kinds
				local rec = recordRender()

				expect(Z.Draw(middle)).to.equal(800)

				-- the outdoor ones hidden: 800 of the 1200 indoor ones, and every drawn box is indoor (with the filter after the cap, about 600)
				needConVar(SHOW_OUT):SetString("0")
				rec = recordRender()
				expect(Z.Draw(middle)).to.equal(800)
				expect(#rec.boxes).to.equal(800)

				for _, box in ipairs(rec.boxes) do
					expect(box.r > box.g).to.beTrue()
				end

				-- the indoor ones hidden: all 400 outdoor boxes (with the filter after the cap, about 200)
				needConVar(SHOW_OUT):SetString("1")
				needConVar(SHOW_IN):SetString("0")
				rec = recordRender()
				expect(Z.Draw(middle)).to.equal(400)
				expect(#rec.boxes).to.equal(400)

				for _, box in ipairs(rec.boxes) do
					expect(box.g > box.r).to.beTrue()
				end
			end
		},
		{
			-- breaks if: the cached selection is not made again when a convar changes (the drawing waits a quarter of a second, or until the player moves)
			name = "a change of either convar changes the drawn set at the next frame (the clock and the player do not move), and the selection is made again once for each change",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local away = at(0, 500, 0)

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")
				recordRender()

				expect(Z.Draw(away)).to.equal(5)
				expect(Z.SelectionRuns()).to.equal(1)

				-- the same frame again: the selection is kept
				expect(Z.Draw(away)).to.equal(5)
				expect(Z.SelectionRuns()).to.equal(1)

				needConVar(SHOW_IN):SetString("0")
				expect(Z.Draw(away)).to.equal(2)
				expect(Z.SelectionRuns()).to.equal(2)
				expect(Z.Draw(away)).to.equal(2)
				expect(Z.SelectionRuns()).to.equal(2)

				needConVar(SHOW_OUT):SetString("0")
				expect(Z.Draw(away)).to.equal(0)

				needConVar(SHOW_IN):SetString("1")
				expect(Z.Draw(away)).to.equal(3)

				needConVar(SHOW_OUT):SetString("1")
				expect(Z.Draw(away)).to.equal(5)
			end
		},
		{
			-- breaks if: both off still scans, sorts and draws (a switch on with nothing to show would still cost)
			name = "both kinds hidden draw nothing in 3D and do no work: no draw call, no material, the selection is not made",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")
				needConVar(SHOW_IN):SetString("0")
				needConVar(SHOW_OUT):SetString("0")

				local rec = recordRender()

				for _ = 1, 3 do
					expect(Z.Draw(at(0, 0, 0))).to.equal(0)
				end

				expect(#rec.boxes + #rec.wires + #rec.lines).to.equal(0)
				expect(rec.materials).to.equal(0)
				expect(Z.SelectionRuns()).to.equal(0)

				-- one of them back on: drawn again, the selection made
				needConVar(SHOW_OUT):SetString("1")
				expect(Z.Draw(at(0, 0, 0))).to.equal(2)
				expect(Z.SelectionRuns()).to.equal(1)
			end
		},
		{
			-- breaks if: the highlight is chosen before the filter (a hidden box still lit), or the filter hides the highlight of a shown box
			name = "the box the player is in follows the filter: not drawn and not lit when its kind is hidden, lit as before when it is shown, the other boxes stay at the normal alphas",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 0},   -- indoor, the player is in it
					{0, 1, 0, 1, 0, 1, 0},   -- outdoor
					{0, 2, 0, 2, 0, 1, 0}    -- outdoor
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local indoorHere = at(64, 64, 0)

				-- the player's own kind hidden: its box is not drawn, and nothing is lit
				needConVar(SHOW_IN):SetString("0")

				local rec = recordRender()

				expect(Z.Draw(indoorHere)).to.equal(2)

				for _, box in ipairs(rec.boxes) do
					expect(box.x1 ~= 0).to.beTrue()
					expect(box.a).to.equal(38)
				end

				for _, wire in ipairs(rec.wires) do
					expect(wire.x1 ~= 0).to.beTrue()
					expect(wire.a).to.equal(90)
				end

				-- the other kind hidden: the player's box is drawn and lit, the outdoor ones are not drawn
				needConVar(SHOW_IN):SetString("1")
				needConVar(SHOW_OUT):SetString("0")
				rec = recordRender()
				expect(Z.Draw(indoorHere)).to.equal(1)
				expect(rec.boxes[1].x1).to.equal(0)
				expect(rec.boxes[1].a).to.equal(76)
				expect(rec.wires[1].a).to.equal(255)

				-- the player in an outdoor box, the outdoor kind hidden: no box is lit
				needConVar(SHOW_OUT):SetString("0")
				rec = recordRender()
				expect(Z.Draw(at(128 + 64, 64, 0))).to.equal(1)
				expect(rec.boxes[1].x1).to.equal(0)
				expect(rec.boxes[1].a).to.equal(38)
				expect(rec.wires[1].a).to.equal(90)

				-- both shown: the outdoor box the player is in is lit
				needConVar(SHOW_OUT):SetString("1")
				rec = recordRender()
				expect(Z.Draw(at(128 + 64, 64, 0))).to.equal(3)

				for _, box in ipairs(rec.boxes) do
					expect(box.a).to.equal(box.x1 == 128 and 76 or 38)
				end
			end
		},
		{
			-- breaks if: the filter reaches the HUD block (the block would then stop naming the box the player stands in)
			name = "the HUD block still names the box the player is in when its kind is hidden, also with both kinds hidden",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")

				local function linesAt(pos)
					local calls = recordText()

					Z.DrawHud(pos)

					return textLines(calls)
				end

				needConVar(SHOW_IN):SetString("0")

				local lines = linesAt(at(64, 64, 0))

				expect(#lines).to.equal(3)
				expect(lines[1].text).to.equal("In/out map: box 1 / 5")
				expect(lines[2].text).to.equal("indoor, ceiling 120 units (class 3)")

				needConVar(SHOW_IN):SetString("1")
				needConVar(SHOW_OUT):SetString("0")
				lines = linesAt(at(3 * 128 + 64, 64, 0))
				expect(#lines).to.equal(3)
				expect(lines[1].text).to.equal("In/out map: box 4 / 5")
				expect(lines[2].text).to.equal("outdoor, ceiling 224 units (class 5)")

				needConVar(SHOW_IN):SetString("0")
				lines = linesAt(at(64, 64, 0))
				expect(#lines).to.equal(3)
				expect(lines[2].text).to.equal("indoor, ceiling 120 units (class 3)")
			end
		},
		{
			-- breaks if: a convar is missing, is not saved with the settings, has another default or has no limits
			name = "gry_zonemap_debug_faces and gry_zonemap_debug_edges are client convars, 1 by default, 0 or 1, saved with the settings",
			func = function(state)
				for _, name in ipairs({FACES, EDGES}) do
					local convar = needConVar(name)

					expect(convar:GetDefault()).to.equal("1")
					expect(convar:GetMin()).to.equal(0)
					expect(convar:GetMax()).to.equal(1)
					expect(convar:GetFlags()).to.equal(GetConVar("gry_minimap"):GetFlags())
				end
			end
		},
		{
			-- breaks if: the two switches are swapped, one of them is ignored, or the ceiling line follows the faces instead of the edges
			name = "faces off draws no filled box and keeps the wires and the ceiling lines; edges off draws no wire and no ceiling line and keeps the filled boxes",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local away = at(0, 500, 0)

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")

				-- both on: five of each, five lines
				local rec = recordRender()

				expect(Z.Draw(away)).to.equal(5)
				expect(#rec.boxes).to.equal(5)
				expect(#rec.wires).to.equal(5)
				expect(#rec.lines).to.equal(5)

				needConVar(FACES):SetString("0")
				rec = recordRender()
				expect(Z.Draw(away)).to.equal(5)
				expect(#rec.boxes).to.equal(0)
				expect(#rec.wires).to.equal(5)
				expect(#rec.lines).to.equal(5)

				needConVar(FACES):SetString("1")
				needConVar(EDGES):SetString("0")
				rec = recordRender()
				expect(Z.Draw(away)).to.equal(5)
				expect(#rec.boxes).to.equal(5)
				expect(#rec.wires).to.equal(0)
				expect(#rec.lines).to.equal(0)
			end
		},
		{
			-- breaks if: both off still scans and draws (the material is set, a selection is made)
			name = "faces and edges both off draw nothing in 3D and do no work: no draw call, no material, the selection is not made; one back on draws again",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")
				needConVar(FACES):SetString("0")
				needConVar(EDGES):SetString("0")

				local rec = recordRender()

				for _ = 1, 3 do
					expect(Z.Draw(at(0, 0, 0))).to.equal(0)
				end

				expect(#rec.boxes + #rec.wires + #rec.lines).to.equal(0)
				expect(rec.materials).to.equal(0)
				expect(Z.SelectionRuns()).to.equal(0)

				needConVar(EDGES):SetString("1")
				expect(Z.Draw(at(0, 0, 0))).to.equal(5)
				expect(#rec.wires).to.equal(5)
				expect(#rec.boxes).to.equal(0)
			end
		},
		{
			-- breaks if: the highlight is drawn whatever the switches say (a lit face with faces off, a lit wire with edges off)
			name = "the box the player is in follows faces and edges: the double-alpha faces only with faces on, the full-alpha wire only with edges on",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 0},
					{0, 1, 0, 1, 0, 1, 0},
					{0, 2, 0, 2, 0, 1, 0}
				}}
				Z.OnData(0, 1, 4, "MAP1")

				local here = at(128 + 64, 64, 0)

				-- faces off: only the wires, the player's box at full alpha, the others at 90
				needConVar(FACES):SetString("0")

				local rec = recordRender()

				expect(Z.Draw(here)).to.equal(3)
				expect(#rec.boxes).to.equal(0)
				expect(#rec.wires).to.equal(3)

				for _, wire in ipairs(rec.wires) do
					expect(wire.a).to.equal(wire.x1 == 128 and 255 or 90)
				end

				-- edges off: only the faces, the player's box at 76, the others at 38
				needConVar(FACES):SetString("1")
				needConVar(EDGES):SetString("0")
				rec = recordRender()
				expect(Z.Draw(here)).to.equal(3)
				expect(#rec.wires).to.equal(0)
				expect(#rec.boxes).to.equal(3)

				for _, box in ipairs(rec.boxes) do
					expect(box.a).to.equal(box.x1 == 128 and 76 or 38)
				end
			end
		},
		{
			-- breaks if: a switch of the render changes the selection (a new scan for a change of the drawing), the IN / OUT filter or the cap
			name = "faces and edges change only the drawing: no new selection when one changes, the IN / OUT filters and the cap of 800 work as before, the HUD block is the same",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local away = at(0, 500, 0)

				state.decoded = mixedBoxes()
				Z.OnData(0, 1, 4, "MAP1")
				recordRender()

				Z.Draw(away)
				expect(Z.SelectionRuns()).to.equal(1)
				needConVar(FACES):SetString("0")
				Z.Draw(away)
				needConVar(EDGES):SetString("0")
				Z.Draw(away)
				needConVar(EDGES):SetString("1")
				Z.Draw(away)
				expect(Z.SelectionRuns()).to.equal(1)

				-- faces off, the IN zones hidden: the two outdoor boxes as wires
				needConVar(SHOW_IN):SetString("0")

				local rec = recordRender()

				expect(Z.Draw(away)).to.equal(2)
				expect(#rec.boxes).to.equal(0)
				expect(#rec.wires).to.equal(2)
				needConVar(SHOW_IN):SetString("1")

				-- the HUD block names the box with both switches off
				needConVar(EDGES):SetString("0")

				local calls = recordText()

				Z.DrawHud(at(64, 64, 0))

				local lines = textLines(calls)

				expect(#lines).to.equal(3)
				expect(lines[1].text).to.equal("In/out map: box 1 / 5")
				expect(lines[2].text).to.equal("indoor, ceiling 120 units (class 3)")

				-- the cap: 900 boxes, faces off: 800 wires
				needConVar(EDGES):SetString("1")
				GetConVar(RANGE):SetString("300")
				state.decoded = gridBoxes(30, 30, 0)
				Z.OnData(0, 1, 4, "MAP1")
				rec = recordRender()
				expect(Z.Draw(at(15 * 128 + 64, 15 * 128 + 64, 0))).to.equal(800)
				expect(#rec.boxes).to.equal(0)
				expect(#rec.wires).to.equal(800)
			end
		},
		{
			name = "Draw with no map draws nothing, and with a position that is not a position too",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local rec = recordRender()

				expect(Z.Draw(at(0, 0, 0))).to.equal(0)

				state.decoded = gridBoxes(3, 3, 2)
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.Draw(nil)).to.equal(0)
				expect(Z.Draw(at(0 / 0, 0, 0))).to.equal(0)
				expect(#rec.boxes + #rec.wires + #rec.lines).to.equal(0)
			end
		},
		{
			-- breaks if: the drawing builds a table, a Vector or a Color per box per frame, or the selection builds a table per candidate
			name = "drawing 400 boxes allocates no table, Vector or Color per box, also when the selection is made again at every frame, also with the sort of more boxes than the cap",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GetConVar(RANGE):SetString("300")
				silentRender()

				local function measure(pos, advance)
					-- warm up (the JIT compiles the loop meanwhile, and its own objects are not the drawing's)
					for _ = 1, 300 do
						if advance then
							state.now = state.now + 1
						end

						Z.Draw(pos)
					end

					-- the smallest of three rounds: the game may allocate a little of its own between two measures (a test must not depend on that)
					local grown = math.huge

					for _ = 1, 5 do
						collectgarbage("collect")
						collectgarbage("stop")

						local before = collectgarbage("count")

						for _ = 1, 20 do
							if advance then
								state.now = state.now + 1
							end

							Z.Draw(pos)
						end

						grown = math.min(grown, collectgarbage("count") - before)
						collectgarbage("restart")
					end

					return grown
				end

				-- the runner's step hook is off while the memory is measured (see withoutRunnerHook)
				local function grownOver(pos, advance)
					return withoutRunnerHook(function()
						return measure(pos, advance)
					end)
				end

				-- 20 frames of 400 boxes: a Vector per box would be 8000 * 40 bytes = 320 KB, a table per box more; the test runner's own step-budget hook allocates about 10 KB over the same instructions
				state.decoded = gridBoxes(20, 20, 4)
				Z.OnData(0, 1, 4, "MAP1")
				expect(grownOver(at(1280, 1280, 0), false)).to.beLessThan(64)
				expect(grownOver(at(1280, 1280, 0), true)).to.beLessThan(64)

				-- 900 boxes: the selection sorts them at every frame
				state.decoded = gridBoxes(30, 30, 4)
				Z.OnData(0, 1, 4, "MAP1")
				expect(grownOver(at(1984, 1984, 0), true)).to.beLessThan(64)
			end
		},
		{
			-- breaks if: the filter makes a table or a closure per selection or per box
			name = "with one kind hidden the drawing allocates nothing either, also when the selection is made again at every frame",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				GetConVar(RANGE):SetString("300")
				silentRender()

				local function measure(pos)
					for _ = 1, 300 do
						state.now = state.now + 1
						Z.Draw(pos)
					end

					local grown = math.huge

					for _ = 1, 5 do
						collectgarbage("collect")
						collectgarbage("stop")

						local before = collectgarbage("count")

						for _ = 1, 20 do
							state.now = state.now + 1
							Z.Draw(pos)
						end

						grown = math.min(grown, collectgarbage("count") - before)
						collectgarbage("restart")
					end

					return grown
				end

				local function grownOver(pos)
					return withoutRunnerHook(function()
						return measure(pos)
					end)
				end

				-- half indoor, half outdoor, one kind hidden: the filter reads the convars and the states at every selection
				local mixed = {}

				for cy = 0, 29 do
					for cx = 0, 29 do
						mixed[#mixed + 1] = {0, cx, cy, cx, cy, (cx + cy) % 2 == 0 and 1 or 2, 4}
					end
				end

				state.decoded = {boxes = mixed}
				Z.OnData(0, 1, 4, "MAP1")
				needConVar(SHOW_IN):SetString("0")
				expect(grownOver(at(1984, 1984, 0), true)).to.beLessThan(64)
				needConVar(SHOW_IN):SetString("1")
				needConVar(SHOW_OUT):SetString("0")
				expect(grownOver(at(1984, 1984, 0), true)).to.beLessThan(64)

				-- more shown boxes than the cap (1200 indoor of 1600): the sort runs at every selection, with one kind hidden
				local many = {}

				for cy = 0, 39 do
					for cx = 0, 39 do
						many[#many + 1] = {0, cx, cy, cx, cy, (cx % 2 == 0 and cy % 2 == 0) and 1 or 2, 4}
					end
				end

				state.decoded = {boxes = many}
				Z.OnData(0, 1, 4, "MAP1")
				expect(grownOver(at(20 * 128, 20 * 128, 0), true)).to.beLessThan(64)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- BoxAt: the box the player is in
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "BoxAt is nil with no map, and for a position that is not a position, and raises nothing",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				expect(Z.BoxAt(at(0, 0, 0))).to.beNil()

				state.decoded = gridBoxes(3, 3, 2)
				Z.OnData(0, 1, 4, "MAP1")

				expect(function()
					expect(Z.BoxAt(nil)).to.beNil()
					expect(Z.BoxAt(12)).to.beNil()
					expect(Z.BoxAt({})).to.beNil()
					expect(Z.BoxAt({x = 1, y = 2})).to.beNil()
					expect(Z.BoxAt({x = 0 / 0, y = 0, z = 0})).to.beNil()
					expect(Z.BoxAt({x = 1, y = math.huge, z = 0})).to.beNil()
				end).to.succeed()

				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1)
			end
		},
		{
			-- breaks if: the index or a field comes back in another order than (index, layer, x1, y1, x2, y2, state, ceil)
			name = "BoxAt returns the index and the fields of the box that contains the position (the module's order: layer, x1, y1, x2, y2, state, ceil)",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}, {0, 10, -2, 12, 4, 1, 0}, {2, 3, -2, 9, 4, 1, 6}}}
				Z.OnData(0, 1, 4, "MAP1")

				local index, layer, x1, y1, x2, y2, st, ceil = Z.BoxAt(at(5 * 128 + 10, 128, 0))

				expect(index).to.equal(1)
				expect(layer).to.equal(0)
				expect(x1).to.equal(3)
				expect(y1).to.equal(-2)
				expect(x2).to.equal(9)
				expect(y2).to.equal(4)
				expect(st).to.equal(2)
				expect(ceil).to.equal(4)

				index, layer, x1, y1, x2, y2, st, ceil = Z.BoxAt(at(11 * 128, 0, 0))

				expect(index).to.equal(2)
				expect(x1).to.equal(10)
				expect(st).to.equal(1)
				expect(ceil).to.equal(0)

				-- the box of layer 2, over the first one
				index, layer, _, _, _, _, st, ceil = Z.BoxAt(at(5 * 128, 128, 2 * 128))

				expect(index).to.equal(3)
				expect(layer).to.equal(2)
				expect(ceil).to.equal(6)
			end
		},
		{
			-- breaks if: the edge is off by a cell: the cell x2 + 1 is outside, the cell x1 is inside (floor of the coordinate over the cell)
			name = "BoxAt: a box contains from x1 * 128 up to just under (x2 + 1) * 128, likewise y; the next cell is outside",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 0}}}
				Z.OnData(0, 1, 4, "MAP1")

				expect(Z.BoxAt(at(3 * 128, 0, 0))).to.equal(1)
				expect(Z.BoxAt(at(3 * 128 - 0.01, 0, 0))).to.beNil()
				expect(Z.BoxAt(at(10 * 128 - 0.01, 0, 0))).to.equal(1)
				expect(Z.BoxAt(at(10 * 128, 0, 0))).to.beNil()
				expect(Z.BoxAt(at(5 * 128, -2 * 128, 0))).to.equal(1)
				expect(Z.BoxAt(at(5 * 128, -2 * 128 - 0.01, 0))).to.beNil()
				expect(Z.BoxAt(at(5 * 128, 5 * 128 - 0.01, 0))).to.equal(1)
				expect(Z.BoxAt(at(5 * 128, 5 * 128, 0))).to.beNil()
			end
		},
		{
			-- breaks if: the layer above and the one below are not looked at (stairs), or are looked at before the player's own layer, or a layer farther away is taken
			name = "BoxAt looks at the player's own layer first, then the layer above, then the one below (like Lookup), and no farther",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				-- only the layer 1 (z = 64 to 192 ... the band of a layer is 128 high around layer * 128)
				state.decoded = {boxes = {{1, 0, 0, 2, 2, 1, 0}}}
				Z.OnData(0, 1, 4, "MAP1")

				expect(Z.BoxAt(at(64, 64, 128))).to.equal(1) -- its own layer
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1) -- layer 0: the layer above is layer 1
				expect(Z.BoxAt(at(64, 64, 256))).to.equal(1) -- layer 2: the layer below is layer 1
				expect(Z.BoxAt(at(64, 64, 512))).to.beNil() -- layer 4: two layers away
				expect(Z.BoxAt(at(64, 64, -200))).to.beNil() -- layer -2

				-- the player's own layer is chosen first when both exist
				state.decoded = {boxes = {{0, 0, 0, 2, 2, 1, 0}, {1, 0, 0, 2, 2, 2, 3}}}
				Z.OnData(0, 1, 4, "MAP1")

				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1)
				expect(Z.BoxAt(at(64, 64, 63))).to.equal(1)
				expect(Z.BoxAt(at(64, 64, 64))).to.equal(2)
				expect(Z.BoxAt(at(64, 64, 128))).to.equal(2)

				-- the layer above before the one below: z = 64 is the layer 1 (own), z = 0 with layers -1 and 1 only gives the one above
				state.decoded = {boxes = {{-1, 0, 0, 2, 2, 1, 0}, {1, 0, 0, 2, 2, 2, 3}}}
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(2)
			end
		},
		{
			-- breaks if: the answer is kept from the old map or the old place
			name = "BoxAt follows the player from a box to the next at once, and a new map or a state that drops the map gives a new answer",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {0, 1, 0, 1, 0, 1, 0}}}
				Z.OnData(0, 1, 4, "MAP1")

				-- the clock does not move: the answer still changes with the cell
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1)
				expect(Z.BoxAt(at(128 + 64, 64, 0))).to.equal(2)
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1)
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(1)

				-- another map at the same place
				state.decoded = {boxes = {{0, 5, 5, 5, 5, 1, 0}, {0, 0, 0, 0, 0, 1, 0}}}
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.BoxAt(at(64, 64, 0))).to.equal(2)

				-- the map dropped
				Z.OnState(2, 0, 0)
				expect(Z.BoxAt(at(64, 64, 0))).to.beNil()
			end
		},
		{
			-- breaks if: the scan makes a table, a Vector or a string at each call
			name = "BoxAt allocates nothing, also when the cell changes at every call (the scan itself)",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = gridBoxes(20, 20, 4)
				Z.OnData(0, 1, 4, "MAP1")

				local a, b = at(64, 64, 0), at(1500, 1500, 0)

				for _ = 1, 1000 do
					Z.BoxAt(a)
					Z.BoxAt(b)
				end

				local grown = math.huge

				for _ = 1, 5 do
					collectgarbage("collect")
					collectgarbage("stop")

					local before = collectgarbage("count")

					for _ = 1, 2000 do
						Z.BoxAt(a)
						Z.BoxAt(b)
					end

					grown = math.min(grown, collectgarbage("count") - before)
					collectgarbage("restart")
				end

				expect(grown).to.beLessThan(128)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the HUD block of the debug mode
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: a line says something else, or the box number or the total is wrong, or the ceiling of a class is wrong
			name = "the HUD block in an indoor box: box number / total, indoor with the ceiling height and class, the layer and the cells with their size",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}, {0, 10, -2, 12, 2, 1, 0}, {0, 20, 0, 20, 0, 1, 3}}}
				Z.OnData(0, 1, 4, "MAP1")

				local calls = recordText()

				Z.DrawHud(at(5 * 128 + 10, 128, 0))

				local lines = textLines(calls)

				expect(#lines).to.equal(3)
				expect(lines[1].text).to.equal("In/out map: box 1 / 3")
				expect(lines[2].text).to.equal("indoor, ceiling 160 units (class 4)")
				expect(lines[3].text).to.equal("layer 0, cells x 3..9, y -2..4 (7 x 7)")
			end
		},
		{
			name = "the HUD block in an outdoor box with no ceiling, with a box that is not square",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}, {0, 10, -2, 12, 2, 1, 0}, {1, 20, 0, 20, 0, 1, 3}}}
				Z.OnData(0, 1, 4, "MAP1")

				local calls = recordText()

				Z.DrawHud(at(11 * 128, 0, 0))

				local lines = textLines(calls)

				expect(#lines).to.equal(3)
				expect(lines[1].text).to.equal("In/out map: box 2 / 3")
				expect(lines[2].text).to.equal("outdoor, open sky / ceiling over 512")
				expect(lines[3].text).to.equal("layer 0, cells x 10..12, y -2..2 (3 x 5)")

				-- the next frame in another box: the text follows (nothing is kept from the first)
				calls = recordText()
				Z.DrawHud(at(20 * 128 + 5, 5, 128))
				lines = textLines(calls)
				expect(lines[1].text).to.equal("In/out map: box 3 / 3")
				expect(lines[2].text).to.equal("outdoor, ceiling 120 units (class 3)")
				expect(lines[3].text).to.equal("layer 1, cells x 20..20, y 0..0 (1 x 1)")
			end
		},
		{
			-- breaks if: the block is not placed under the crosshair, not centred, the lines overlap, or the shadow is missing or is drawn after the text
			name = "the HUD block is centred under the crosshair (ScrW() / 2, ScrH() / 2 + 80), one line under the other, each with a dark shadow drawn first, with a font",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}}}
				Z.OnData(0, 1, 4, "MAP1")

				local calls = recordText()

				Z.DrawHud(at(5 * 128, 128, 0))

				-- three lines, each drawn twice: 6 calls
				expect(#calls).to.equal(6)

				local lines = textLines(calls)

				expect(#lines).to.equal(3)
				expect(lines[1].x).to.equal(ScrW() / 2)
				expect(lines[1].y).to.equal(ScrH() / 2 + 80)
				expect(lines[2].y > lines[1].y).to.beTrue()
				expect(lines[3].y > lines[2].y).to.beTrue()

				for i, call in ipairs(calls) do
					expect(isstring(call.font) and #call.font > 0).to.beTrue()
					expect(call.xalign).to.equal(TEXT_ALIGN_CENTER)

					if call.r + call.g + call.b > 200 then
						-- the text: the call before it is its shadow, the same text one pixel right and down, dark
						local shadow = calls[i - 1]

						expect(shadow ~= nil).to.beTrue()
						expect(shadow.text).to.equal(call.text)
						expect(shadow.r + shadow.g + shadow.b <= 200).to.beTrue()
						expect(shadow.a > 0).to.beTrue()
						expect(shadow.x).to.equal(call.x + 1)
						expect(shadow.y).to.equal(call.y + 1)
					end
				end
			end
		},
		{
			name = "the HUD block with a map but no box at the player's feet says so, in one line",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}}}
				Z.OnData(0, 1, 4, "MAP1")

				local calls = recordText()

				Z.DrawHud(at(100000, 0, 0))

				local lines = textLines(calls)

				expect(#lines).to.equal(1)
				expect(lines[1].text).to.equal("In/out map: unknown here (no box): the automatic zoom uses its own rays")
				expect(lines[1].x).to.equal(ScrW() / 2)
				expect(lines[1].y).to.equal(ScrH() / 2 + 80)
			end
		},
		{
			-- breaks if: with no map the block is empty or says "no box" (it is not the same thing: the map has not come)
			name = "the HUD block with no map is the state's own line: not received yet, computing, off on this server",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				local function lineFor(pos)
					local calls = recordText()

					Z.DrawHud(pos)

					local lines = textLines(calls)

					expect(#lines).to.equal(1)

					return lines[1].text
				end

				expect(lineFor(at(0, 0, 0))).to.equal("In/out map: not received yet")

				Z.OnState(3, 42, 100)
				expect(lineFor(at(0, 0, 0))).to.equal("In/out map: computing 42 %")

				Z.OnState(0, 0, 0)
				expect(lineFor(at(0, 0, 0))).to.equal("In/out map: off on this server")
			end
		},
		{
			-- breaks if: the block builds its strings at every frame (the cache of the lines by box), or never builds them again when the box changes
			name = "the HUD lines are made when the player goes into another box, not at every frame in the same box",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = {boxes = {{0, 3, -2, 9, 4, 2, 4}, {0, 10, -2, 12, 2, 1, 0}}}
				Z.OnData(0, 1, 4, "MAP1")
				draw.SimpleText = function() return 0, 0 end

				local first = Z.HudBuilds()

				for _ = 1, 100 do
					Z.DrawHud(at(5 * 128, 128, 0))
				end

				-- 100 frames in box 1, and a few steps inside it: one build
				Z.DrawHud(at(5 * 128 + 40, 128 + 10, 0))
				expect(Z.HudBuilds()).to.equal(first + 1)

				-- into box 2: one more, then no more
				for _ = 1, 100 do
					Z.DrawHud(at(11 * 128, 0, 0))
				end

				expect(Z.HudBuilds()).to.equal(first + 2)

				-- out of every box: one more
				for _ = 1, 100 do
					Z.DrawHud(at(100000, 0, 0))
				end

				expect(Z.HudBuilds()).to.equal(first + 3)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the options panel
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			name = "ZoneMapOptions builds a header, the status line (a snapshot), and the debug check box bound to gry_zonemap_debug; building it writes nothing",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				expect(isfunction(GryMod.ZoneMapOptions)).to.beTrue()

				Z.OnState(3, 42, 100)

				state.panel = vgui.Create("ControlPanel")
				GryMod.ZoneMapOptions(state.panel)

				expect(hasCategory(state.panel, "In/out map")).to.beTrue()
				expect(hasLabel(state.panel, "In/out map: computing 42 %")).to.beTrue()

				local box = checkBoxOn(state.panel, DEBUG)

				expect(box ~= nil).to.beTrue()
				expect(string.find(box:GetText(), "Draw the map in the world", 1, true) == 1).to.beTrue()
				expect(GetConVar(DEBUG):GetString()).to.equal(state.debug)
			end
		},
		{
			-- breaks if: the slider is missing, is bound to another convar, has other limits, or is above the check box
			name = "ZoneMapOptions has the display distance slider (metres, 20 to 300, whole numbers) bound to gry_zonemap_debug_range right under the debug check box; building it writes nothing",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.ZoneMapOptions(state.panel)

				local boxAt, sliderAt, slider

				for i, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == DEBUG then
						boxAt = i
					elseif p.ClassName == "DNumSlider" and p.Scratch and p.Scratch:GetTable().m_strConVar == RANGE then
						sliderAt, slider = i, p
					end
				end

				expect(boxAt ~= nil).to.beTrue()
				expect(slider ~= nil).to.beTrue()
				expect(sliderAt > boxAt).to.beTrue()
				expect(slider:GetText()).to.equal("Display distance (m)")
				expect(slider:GetMin()).to.equal(20)
				expect(slider:GetMax()).to.equal(300)
				expect(slider:GetDecimals()).to.equal(0)
				expect(GetConVar(RANGE):GetString()).to.equal(state.range)
			end
		},
		{
			-- breaks if: the section is not called from the radar menu, or comes before the automatic zoom, or is still in the Config menu
			name = "the Radar and map menu has the zone map section once, right after the automatic zoom section, and the Config menu has none",
			func = function(state)
				local function order(panel)
					local found = {}

					for _, p in ipairs(walk(panel)) do
						if p.ClassName == "DNumSlider" and p.Scratch and p.Scratch:GetTable().m_strConVar == "gry_radar_zoom_delay" then
							found[#found + 1] = "delay"
						elseif p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == DEBUG then
							found[#found + 1] = "debug"
						end
					end

					return found
				end

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local found = order(state.panel)

				expect(#found).to.equal(2)
				expect(found[1]).to.equal("delay")
				expect(found[2]).to.equal("debug")
				state.panel:Remove()

				state.panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(state.panel)
				expect(#order(state.panel)).to.equal(0)
			end
		},
		{
			name = "the Radar and map menu's server section has the gry_zonemap switch (asked through the server, not a convar) and the button that makes the map again; the Config menu's has neither",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local control = state.panel.GryAdminControls["gry_zonemap"]

				expect(control ~= nil).to.beTrue()
				expect(control.ClassName).to.equal("DCheckBoxLabel")
				expect(control:GetText()).to.equal("The server makes the in/out map")
				expect(control.Button:GetTable().m_strConVar).to.beNil()

				local box = resetButton(state.panel)

				expect(box ~= nil).to.beTrue()
				expect(box.ClassName).to.equal("DButton")
				expect(box:GetText()).to.equal("Delete and remake the in/out map")
				state.panel:Remove()

				-- the administrators' section of the Config menu
				state.panel = vgui.Create("ControlPanel")
				GryMod.AdminOptions(state.panel)
				expect(state.panel.GryAdminControls["gry_zonemap"]).to.beNil()
				expect(resetButton(state.panel)).to.beNil()
			end
		},
		{
			-- breaks if: the switch is not in the white list, the server refuses the administrator's request and the box does nothing
			name = "the server's white list knows gry_zonemap as a bool (without it the administrators' box would do nothing)",
			func = function()
				local setting = GryMod.ServerSettings and GryMod.ServerSettings.Find("gry_zonemap")

				expect(setting ~= nil).to.beTrue()
				expect(setting.kind).to.equal("bool")
			end
		},
		{
			-- breaks if: the button sends without asking, or asks and sends on "no"
			name = "the reset button asks first; on no nothing is sent, on yes gry_zonemap_reset goes to the server with no payload",
			func = function(state)
				GryMod.AdminUI.IsAdmin = function() return true end

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local box = resetButton(state.panel)

				state.confirmAnswer = false
				box:DoClick()
				expect(#state.asked).to.equal(1)
				expect(string.find(state.asked[1], "Delete the in/out map of this map and make it again?", 1, true) == 1).to.beTrue()
				expect(#state.sent).to.equal(0)

				state.confirmAnswer = true
				box:DoClick()
				expect(#state.asked).to.equal(2)
				expect(state.sent[1]).to.equal("gry_zonemap_reset")
				expect(state.sent[2]).to.equal("send")
				expect(#state.sent).to.equal(2)
			end
		},
		{
			name = "for a player who is not an administrator the reset button is disabled, and a click that gets through asks nothing and sends nothing",
			func = function(state)
				GryMod.AdminUI.IsAdmin = function() return false end

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local box = resetButton(state.panel)

				expect(box:IsEnabled()).to.beFalse()
				box:DoClick()
				expect(#state.asked).to.equal(0)
				expect(#state.sent).to.equal(0)
			end
		},
		-- ----------------------------------------------------------------------------------------------------------------------
		-- the real pure module
		-- ----------------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: the receivers and the real module disagree (the format, the index, the lookup)
			name = "real module: a map built, encoded, cut in 3 chunks and received answers Indoor true, false and nil",
			skip = realModule == nil,
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local M = realModule

				GryMod.ZoneMap = M

				local samples = {}

				for i = 0, 4 do
					samples[#samples + 1] = {x = 64 + 128 * i, y = 64, z = 0, indoor = true, ceil = 3}
				end

				for i = 6, 10 do
					samples[#samples + 1] = {x = 64 + 128 * i, y = 64, z = 0, indoor = false, ceil = 0}
				end

				local map = M.Build(samples)
				local bytes = M.Encode(map, {bspSize = 1234, nodeCount = 10, complete = true})

				expect(isstring(bytes)).to.beTrue()

				local cut = math.max(1, math.floor(#bytes / 3))

				Z.OnState(4, 10, 10)
				expect(deliver(Z, bytes, {cut, cut})).to.equal(3)

				local s, _, _, boxes, reason = Z.Status()

				expect(reason).to.beNil()
				expect(s).to.equal(4)
				expect(boxes).to.equal(#map.boxes)
				expect(boxes > 0).to.beTrue()

				expect(Z.Indoor(Vector(64 + 128 * 2, 64, 0))).to.equal(true)
				expect(Z.Indoor(Vector(64 + 128 * 8, 64, 0))).to.equal(false)
				expect(Z.Indoor(Vector(100000, 0, 0))).to.beNil()
				-- the next layer up is looked at when the player's own layer is unknown (stairs), far above it is unknown
				expect(Z.Indoor(Vector(64 + 128 * 2, 64, 700))).to.beNil()
				expect(Z.Indoor(Vector(0 / 0, 0, 0))).to.beNil()
			end
		},
		{
			-- breaks if: the drawing reads other names than the module's boxes (layer, x1, y1, x2, y2, state, ceil)
			name = "real module: the boxes of a received map are drawn, one wireframe box each, with the ceiling line where the class is not 0",
			skip = realModule == nil,
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local M = realModule
				local boxes, lines = 0, 0

				GryMod.ZoneMap = M

				local samples = {}

				for i = 0, 3 do
					samples[#samples + 1] = {x = 64 + 128 * i, y = 64, z = 0, indoor = true, ceil = 4}
				end

				for i = 5, 8 do
					samples[#samples + 1] = {x = 64 + 128 * i, y = 64, z = 0, indoor = false, ceil = 0}
				end

				local map = M.Build(samples)
				local bytes = M.Encode(map, {bspSize = 1, nodeCount = 8, complete = true})

				Z.OnState(4, 8, 8)
				Z.OnData(0, 1, #bytes, bytes)
				expect((select(4, Z.Status()))).to.equal(#map.boxes)

				local rec = recordRender()

				expect(Z.Draw(Vector(500, 64, 0))).to.equal(#map.boxes)
				boxes, lines = #rec.boxes, #rec.lines
				expect(boxes).to.equal(#map.boxes)
				expect(#rec.wires).to.equal(#map.boxes)

				-- the indoor boxes have ceiling class 4, the outdoor ones none: some lines, not one a box
				expect(lines > 0 and lines < boxes).to.beTrue()
			end
		},
		{
			-- breaks if: the HUD and the zoom disagree (BoxAt and Indoor must answer the same, the stairs layers included)
			name = "real module: BoxAt and Indoor agree on a grid of positions, on three layers (the HUD names the box the automatic zoom reads)",
			skip = realModule == nil,
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local M = realModule

				GryMod.ZoneMap = M

				local samples = {}

				-- layer 0 and layer 1 over a part of the area, outdoor cells beside
				for i = 0, 5 do
					for j = 0, 3 do
						samples[#samples + 1] = {x = 64 + 128 * i, y = 64 + 128 * j, z = 0, indoor = i < 3, ceil = i < 3 and 3 or 0}
					end
				end

				for i = 1, 4 do
					samples[#samples + 1] = {x = 64 + 128 * i, y = 64, z = 128, indoor = true, ceil = 5}
				end

				local map = M.Build(samples)
				local bytes = M.Encode(map, {bspSize = 1, nodeCount = #samples, complete = true})

				Z.OnState(4, 1, 1)
				Z.OnData(0, 1, #bytes, bytes)
				expect(#map.boxes > 1).to.beTrue()

				local checked, found = 0, 0

				for x = -100, 900, 61 do
					for y = -100, 600, 53 do
						for z = -140, 300, 37 do
							local pos = Vector(x, y, z)
							local indoor = Z.Indoor(pos)
							local index, _, _, _, _, _, boxState = Z.BoxAt(pos)

							checked = checked + 1

							if index then
								found = found + 1
								expect(indoor).to.equal(boxState == 2)
							else
								expect(indoor).to.beNil()
							end
						end
					end
				end

				expect(checked > 500).to.beTrue()
				expect(found > 50).to.beTrue()
			end
		},
		{
			name = "real module: a corrupt copy of a real file is refused with a reason from the module",
			skip = realModule == nil,
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local M = realModule

				GryMod.ZoneMap = M

				local map = M.Build({{x = 64, y = 64, z = 0, indoor = true, ceil = 2}})
				local bytes = M.Encode(map, {bspSize = 1, nodeCount = 1, complete = true})
				local broken = string.sub(bytes, 1, 8) .. string.char((string.byte(bytes, 9) + 1) % 256) .. string.sub(bytes, 10)

				Z.OnState(4, 1, 1)
				expect(function()
					Z.OnData(0, 1, #broken, broken)
				end).to.succeed()

				local _, _, _, boxes, reason = Z.Status()

				expect(boxes).to.equal(0)
				expect(isstring(reason) and #reason > 0).to.beTrue()
				expect(Z.Indoor(Vector(64, 64, 0))).to.beNil()
			end
		}
	}
}
