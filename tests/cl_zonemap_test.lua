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
local DEBUG = "gry_zonemap_debug"

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

local function checkBoxOn(panel, convarName)
	for _, p in ipairs(walk(panel)) do
		if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == convarName then
			return p
		end
	end
end

-- the check box of the radar menu that deletes the in/out map and makes it again (flagged by cl_options_radar.lua)
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
		state.realAdd = notification and notification.AddLegacy
		state.realMap = game.GetMap
		state.realConfirm = GryMod.Confirm
		state.realIsAdmin = GryMod.AdminUI and GryMod.AdminUI.IsAdmin
		state.debug = GetConVar(DEBUG) and GetConVar(DEBUG):GetString()

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

			-- the convar goes back first (its callback puts the hook back in line), then the module's own state
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

				for _, name in ipairs({"Indoor", "Status", "StatusText", "Reset", "OnState", "OnData", "Want", "Draw"}) do
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

				convar:SetString("1")
				expect(isfunction(hookFunction())).to.beTrue()

				convar:SetString("0")
				expect(hookFunction()).to.beNil()

				-- again, and twice on in a row: one hook, not a pile
				convar:SetString("1")
				convar:SetString("1")
				expect(isfunction(hookFunction())).to.beTrue()
				convar:SetString("0")
				expect(hookFunction()).to.beNil()
			end
		},
		{
			name = "SyncDebugHook (what runs at load) puts the hook in line with the convar's current value",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local convar = GetConVar(DEBUG)

				convar:SetString("1")
				hook.Remove("PostDrawTranslucentRenderables", HOOK)
				expect(hookFunction()).to.beNil()
				Z.SyncDebugHook()
				expect(isfunction(hookFunction())).to.beTrue()

				convar:SetString("0")
				hook.Add("PostDrawTranslucentRenderables", HOOK, function() end)
				Z.SyncDebugHook()
				expect(hookFunction()).to.beNil()
			end
		},
		{
			-- breaks if: the cap of 300 boxes a frame is raised, or removed
			name = "at most 300 boxes are drawn a frame, and the wireframe boxes are exactly that many",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local boxes, lines = 0, 0

				state.decoded = gridBoxes(20, 20, 0)
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function() boxes = boxes + 1 end
				render.DrawLine = function() lines = lines + 1 end

				-- in the middle of the grid: all 400 are within 3000 units
				local drawn = Z.Draw(at(1280, 1280, 0))

				expect(drawn).to.equal(300)
				expect(boxes).to.equal(300)
				expect(lines).to.equal(0)

				-- a map of 250 boxes: all of them
				boxes = 0
				state.decoded = gridBoxes(10, 25, 0)
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.Draw(at(640, 1600, 0))).to.equal(250)
				expect(boxes).to.equal(250)
			end
		},
		{
			-- breaks if: the range test is dropped (everything is drawn), or the 3000 units become something else
			name = "only the boxes within 3000 units of the player are drawn",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local calls = {}

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 0},     -- the cell at the player
					{0, 20, 0, 20, 0, 1, 0},   -- from x = 2560 to 2688: nearest edge 2560 away: in
					{0, 24, 0, 24, 0, 1, 0},   -- from x = 3072: out
					{0, 0, 0, 0, 0, 1, 0},     -- again in
					{20, 0, 0, 0, 0, 1, 0}     -- layer 20: z = 2496 to 2624, 2496 above: in (3D distance: 2496 < 3000)
				}}
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function(origin, angle, mins, maxs)
					calls[#calls + 1] = {mins.x, maxs.x, mins.z, maxs.z}
				end
				render.DrawLine = function() end

				expect(Z.Draw(at(0, 0, 0))).to.equal(4)
				expect(#calls).to.equal(4)

				-- a box far in height is out
				calls = {}
				state.decoded = {boxes = {{0, 0, 0, 0, 0, 2, 0}, {40, 0, 0, 0, 0, 2, 0}}}
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.Draw(at(0, 0, 0))).to.equal(1)
			end
		},
		{
			name = "a box is drawn from x1 * 128 to (x2 + 1) * 128, likewise y, and z from layer * 128 - 64 to layer * 128 + 64",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local seen

				state.decoded = {boxes = {{2, -3, 4, -1, 6, 2, 0}}}
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function(origin, angle, mins, maxs)
					seen = {origin.x, origin.y, origin.z, mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z}
				end
				render.DrawLine = function() end

				expect(Z.Draw(at(-200, 700, 256))).to.equal(1)
				-- the box is drawn with an origin of 0 and the corners given in the world (so that nothing is built per box)
				expect(seen[1]).to.equal(0)
				expect(seen[2]).to.equal(0)
				expect(seen[3]).to.equal(0)
				expect(seen[4]).to.equal(-3 * 128)
				expect(seen[5]).to.equal(4 * 128)
				expect(seen[6]).to.equal(2 * 128 - 64)
				expect(seen[7]).to.equal(0)
				expect(seen[8]).to.equal(7 * 128)
				expect(seen[9]).to.equal(2 * 128 + 64)
			end
		},
		{
			name = "the boxes may be named fields (layer, x1...) as well as positional",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local boxes = 0

				state.decoded = gridBoxes(5, 5, 3, true)
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function() boxes = boxes + 1 end
				render.DrawLine = function() end

				expect(Z.Draw(at(300, 300, 0))).to.equal(25)
				expect(boxes).to.equal(25)
			end
		},
		{
			name = "red for indoor, green for outdoor, a cyan line only when the ceiling class is not 0",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local colours, lines = {}, {}

				state.decoded = {boxes = {
					{0, 0, 0, 0, 0, 2, 3},   -- indoor, class 3 (120)
					{0, 1, 0, 1, 0, 1, 0},   -- outdoor, no ceiling
					{0, 2, 0, 2, 0, 1, 5}    -- outdoor with a ceiling class 5 (224)
				}}
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function(origin, angle, mins, maxs, colour)
					colours[#colours + 1] = {colour.r, colour.g, colour.b}
				end
				render.DrawLine = function(from, to, colour)
					lines[#lines + 1] = {from.z, to.z, colour.r, colour.g, colour.b}
				end

				expect(Z.Draw(at(0, 0, 0))).to.equal(3)

				-- indoor is red (more red than green), outdoor is green
				expect(colours[1][1] > colours[1][2]).to.beTrue()
				expect(colours[2][2] > colours[2][1]).to.beTrue()
				expect(colours[3][2] > colours[3][1]).to.beTrue()

				-- two lines (classes 3 and 5), cyan (no red, green and blue high), going up by the class height
				expect(#lines).to.equal(2)
				expect(lines[1][3]).to.equal(0)
				expect(lines[1][4] > 100 and lines[1][5] > 100).to.beTrue()
				expect(lines[1][2] - lines[1][1]).to.equal(120)
				expect(lines[2][2] - lines[2][1]).to.equal(224)
			end
		},
		{
			name = "Draw with no map draws nothing, and with a position that is not a position too",
			func = function(state)
				local Z = GryMod.ZoneMapClient
				local calls = 0

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function() calls = calls + 1 end
				render.DrawLine = function() calls = calls + 1 end

				expect(Z.Draw(at(0, 0, 0))).to.equal(0)

				state.decoded = gridBoxes(3, 3, 2)
				Z.OnData(0, 1, 4, "MAP1")
				expect(Z.Draw(nil)).to.equal(0)
				expect(calls).to.equal(0)
			end
		},
		{
			-- breaks if: the drawing builds a table or a Vector per box per frame
			name = "drawing 300 boxes allocates no table and no Vector per box",
			func = function(state)
				local Z = GryMod.ZoneMapClient

				state.decoded = gridBoxes(20, 20, 4)
				Z.OnData(0, 1, 4, "MAP1")

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function() end
				render.DrawLine = function() end

				-- the first call may build the flat arrays; the next ones must not allocate (a few bytes of the call itself at most)
				local pos = at(1280, 1280, 0)

				-- warm up (the JIT compiles the loop meanwhile, and its own objects are not the drawing's)
				for _ = 1, 300 do
					Z.Draw(pos)
				end

				-- the smallest of three rounds: the game may allocate a little of its own between two measures (a test must not depend on that)
				local grown = math.huge

				for _ = 1, 3 do
					collectgarbage("collect")
					collectgarbage("stop")

					local before = collectgarbage("count")

					for _ = 1, 20 do
						Z.Draw(pos)
					end

					grown = math.min(grown, collectgarbage("count") - before)
					collectgarbage("restart")
				end

				-- 20 frames of 300 boxes: a Vector per box would be 6000 * 40 bytes = 240 KB, a table per box more; the test runner's own step-budget hook allocates about 10 KB over the same instructions
				expect(grown).to.beLessThan(64)
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

				expect(hasLabel(state.panel, "In/out map")).to.beTrue()
				expect(hasLabel(state.panel, "In/out map: computing 42 %")).to.beTrue()

				local box = checkBoxOn(state.panel, DEBUG)

				expect(box ~= nil).to.beTrue()
				expect(string.find(box:GetText(), "Draw the in/out map in the world (debug)", 1, true) == 1).to.beTrue()
				expect(GetConVar(DEBUG):GetString()).to.equal(state.debug)
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
			name = "the Radar and map menu's server section has the gry_zonemap switch (asked through the server, not a convar) and the check box that makes the map again; the Config menu's has neither",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local control = state.panel.GryAdminControls["gry_zonemap"]

				expect(control ~= nil).to.beTrue()
				expect(control.ClassName).to.equal("DCheckBoxLabel")
				expect(control:GetText()).to.equal("In/out map: the server makes it from the node graph (the automatic zoom and other features use it)")
				expect(control.Button:GetTable().m_strConVar).to.beNil()

				local box = resetButton(state.panel)

				expect(box ~= nil).to.beTrue()
				expect(box.ClassName).to.equal("DCheckBoxLabel")
				expect(box:GetText()).to.equal("Delete the in/out map and make it again")
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
			-- breaks if: the box sends without asking, asks and sends on "no", or stays ticked
			name = "the reset check box asks first; on no nothing is sent, on yes gry_zonemap_reset goes to the server with no payload; it is un-ticked each time",
			func = function(state)
				GryMod.AdminUI.IsAdmin = function() return true end

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local box = resetButton(state.panel)

				state.confirmAnswer = false
				box:SetValue(true)
				expect(#state.asked).to.equal(1)
				expect(string.find(state.asked[1], "Delete the in/out map of this map and make it again?", 1, true) == 1).to.beTrue()
				expect(#state.sent).to.equal(0)
				expect(box:GetChecked()).to.beFalse()

				state.confirmAnswer = true
				box:SetValue(true)
				expect(#state.asked).to.equal(2)
				expect(state.sent[1]).to.equal("gry_zonemap_reset")
				expect(state.sent[2]).to.equal("send")
				expect(#state.sent).to.equal(2)
				expect(box:GetChecked()).to.beFalse()
			end
		},
		{
			name = "for a player who is not an administrator the reset check box is disabled, and a tick that gets through asks nothing and sends nothing",
			func = function(state)
				GryMod.AdminUI.IsAdmin = function() return false end

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local box = resetButton(state.panel)

				expect(box:IsEnabled()).to.beFalse()
				box:SetValue(true)
				expect(#state.asked).to.equal(0)
				expect(#state.sent).to.equal(0)
				expect(box:GetChecked()).to.beFalse()
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

				render.SetColorMaterial = function() end
				render.DrawWireframeBox = function() boxes = boxes + 1 end
				render.DrawLine = function() lines = lines + 1 end

				expect(Z.Draw(Vector(500, 64, 0))).to.equal(#map.boxes)
				expect(boxes).to.equal(#map.boxes)

				-- the indoor boxes have ceiling class 4, the outdoor ones none: some lines, not one a box
				expect(lines > 0 and lines < boxes).to.beTrue()
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
