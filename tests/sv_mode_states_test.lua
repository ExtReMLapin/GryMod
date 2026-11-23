-- Tests of the answer to the quick menu's question "which modes does a veto refuse right now?" (lua/grymod/server/sv_mode_states.lua and the bits of
-- lua/grymod/sh_mode_states.lua), GLuaTest format, server realm.
-- The veto is GryMod_CanSetMode (docs/api.md). Each case names the production change whose absence makes it fail. The messages are NOT sent: net.Start,
-- net.WriteUInt, net.Send and timer.Simple are replaced by recorders and put back at the end of the case AND in afterEach, whatever happens.

local function ply()
	return player.GetAll()[1]
end

local Modes = GryMod.Modes
local added = {}

-- a hook of the test, removed in afterEach
local function listen(event, fn)
	local id = "gry_mode_states_test_" .. event .. "_" .. #added
	hook.Add(event, id, fn)
	added[#added + 1] = {event, id}
end

-- the fields a test puts on the real player, put back in afterEach
local touched = {}

local function override(p, key, value)
	if touched[key] == nil then
		touched[key] = {had = rawget(p:GetTable(), key)}
	end

	p[key] = value
end

local function restoreFields(p)
	if IsValid(p) then
		for key, saved in pairs(touched) do
			p[key] = saved.had
		end
	end

	touched = {}
end

-- the recorders: what the server would have sent (name, value, bits, who) and the timers it would have set (delay, function)
local real
local sent, timers

local function recordNet()
	real = {start = net.Start, writeUInt = net.WriteUInt, send = net.Send, simple = timer.Simple}
	sent, timers = {}, {}
	local current

	net.Start = function(name)
		current = {name = name}
	end

	net.WriteUInt = function(value, bits)
		current.value, current.bits = value, bits
	end

	net.Send = function(target)
		current.target = target
		sent[#sent + 1] = current
	end

	timer.Simple = function(delay, fn)
		timers[#timers + 1] = {delay = delay, fn = fn}
	end
end

local function restoreNet()
	if real then
		net.Start, net.WriteUInt, net.Send, timer.Simple = real.start, real.writeUInt, real.send, real.simple
		real = nil
	end
end

local function recorded(fn)
	recordNet()

	local ok, err = pcall(fn)
	restoreNet()

	if not ok then
		error(err, 0)
	end
end

local savedErrorNoHalt

return {
	groupName = "GryMod quick menu: refused modes (server)",
	beforeEach = function()
		savedErrorNoHalt = ErrorNoHalt
	end,
	afterEach = function()
		restoreNet()
		ErrorNoHalt = savedErrorNoHalt

		for _, h in ipairs(added) do
			hook.Remove(h[1], h[2])
		end

		added = {}
		restoreFields(ply())
	end,
	cases = {
		{
			-- fails without GryMod.ModeStates.Pack / Unpack (sh_mode_states.lua), or with a bit moved: the bits are the wire format
			name = "the refused modes go through a 3 bit number and come back: speed is bit 0, cloak bit 1, strength bit 2; armor and the weapon drop have no bit",
			func = function()
				local S = GryMod.ModeStates
				expect(S.Bits).to.equal(3)
				expect(S.Pack({})).to.equal(0)
				expect(S.Pack({[Modes.SPEED] = true})).to.equal(1)
				expect(S.Pack({[Modes.CLOAK] = true})).to.equal(2)
				expect(S.Pack({[Modes.STRENGTH] = true})).to.equal(4)
				expect(S.Pack({[Modes.SPEED] = true, [Modes.STRENGTH] = true})).to.equal(5)
				expect(S.Pack({[Modes.ARMOR] = true, [Modes.DROP] = true})).to.equal(0)

				local back = S.Unpack(6)
				expect(back[Modes.CLOAK]).to.beTrue()
				expect(back[Modes.STRENGTH]).to.beTrue()
				expect(back[Modes.SPEED]).to.beNil()

				-- a table given is emptied and filled in place (the menu reads it every frame and makes no garbage)
				local into = {[Modes.SPEED] = true, [Modes.ARMOR] = true}
				expect(S.Unpack(2, into)).to.equal(into)
				expect(into[Modes.SPEED]).to.beNil()
				expect(into[Modes.CLOAK]).to.beTrue()
			end
		},
		{
			-- fails without States.MaskFor
			name = "MaskFor sets the bit of each mode the veto refuses, and nothing when it refuses none",
			func = function()
				local S = GryMod.ModeStates
				expect(S.MaskFor(Modes.ARMOR, false, function() return false end)).to.equal(0)
				expect(S.MaskFor(Modes.ARMOR, false, function(mode) return mode == Modes.CLOAK end)).to.equal(S.Pack({[Modes.CLOAK] = true}))
				expect(S.MaskFor(Modes.ARMOR, false, function() return true end)).to.equal(7)
			end
		},
		{
			-- fails if MaskFor asks about the mode the suit is in (the veto only runs for a change in Player:SetNanosuitMode), or about the armor
			name = "the veto is asked only about the three modes a change can be refused to, never the mode the suit is in, never the armor or the drop",
			func = function()
				local S = GryMod.ModeStates
				local asked = {}
				local mask = S.MaskFor(Modes.CLOAK, false, function(mode)
					asked[#asked + 1] = mode

					return true
				end)

				table.sort(asked)
				expect(table.concat(asked, ",")).to.equal(Modes.SPEED .. "," .. Modes.STRENGTH)
				expect(mask).to.equal(S.Pack({[Modes.SPEED] = true, [Modes.STRENGTH] = true}))
			end
		},
		{
			-- fails if MaskFor asks when the suit is down or off: SetNanosuitMode answers "malfunction" / "disabled" before the veto, so the veto is not asked
			name = "a suit that is down or off asks no veto at all and refuses nothing (the client already knows the state from the networked flags)",
			func = function()
				local S = GryMod.ModeStates
				local calls = 0
				local mask = S.MaskFor(Modes.ARMOR, true, function()
					calls = calls + 1

					return true
				end)

				expect(mask).to.equal(0)
				expect(calls).to.equal(0)
			end
		},
		{
			-- fails without States.Mask reading GryMod_CanSetMode (the hook is run with the player and the mode, as SetNanosuitMode runs it)
			name = "Mask asks the listeners of GryMod_CanSetMode, with the player and the mode, and a false answer refuses; any other answer does not",
			func = function()
				local S = GryMod.ModeStates
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				local seen = {}

				listen("GryMod_CanSetMode", function(who, mode)
					seen[#seen + 1] = {who, mode}

					if mode == Modes.CLOAK then
						return false
					elseif mode == Modes.SPEED then
						return true -- only false is a veto
					end
				end)

				local mask = S.Mask(p)
				local back = S.Unpack(mask)
				expect(back[Modes.CLOAK]).to.beTrue()
				expect(back[Modes.SPEED]).to.beNil()
				expect(back[Modes.STRENGTH]).to.beNil()
				expect(#seen).to.equal(3)
				expect(seen[1][1]).to.equal(p)
			end
		},
		{
			-- fails if a listener that errors stops the answer or counts as a veto
			name = "a listener that fails does not refuse and does not stop the answer",
			func = function()
				local S = GryMod.ModeStates
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)
				local shown = 0
				ErrorNoHalt = function() shown = shown + 1 end

				listen("GryMod_CanSetMode", function(_, mode)
					if mode == Modes.SPEED then
						error("broken listener")
					elseif mode == Modes.STRENGTH then
						return false
					end
				end)

				local back = S.Unpack(S.Mask(p))
				expect(back[Modes.SPEED]).to.beNil()
				expect(back[Modes.STRENGTH]).to.beTrue()
				expect(shown).to.equal(1)
			end
		},
		{
			-- fails if Mask asks the veto for a dead or invalid player
			name = "a player who is not alive, or not valid, gets 0 and no listener is asked",
			func = function()
				local S = GryMod.ModeStates
				local calls = 0

				listen("GryMod_CanSetMode", function()
					calls = calls + 1

					return false
				end)

				local dead = {IsValid = function() return true end, Alive = function() return false end}
				expect(S.Mask(dead)).to.equal(0)
				expect(S.Mask(NULL)).to.equal(0)
				expect(calls).to.equal(0)
			end
		},
		{
			-- fails without Push writing the mask in States.Bits bits to the player
			name = "Push sends gry_modes_refused with the mask, in the width the client reads",
			func = function()
				local S = GryMod.ModeStates
				local p = ply()
				override(p, "Nanosuit_mode", Modes.ARMOR)

				listen("GryMod_CanSetMode", function(_, mode)
					if mode == Modes.STRENGTH then
						return false
					end
				end)

				recorded(function()
					expect(S.Push(p)).to.beTrue()
					expect(#sent).to.equal(1)
					expect(sent[1].name).to.equal("gry_modes_refused")
					expect(sent[1].value).to.equal(S.Pack({[Modes.STRENGTH] = true}))
					expect(sent[1].bits).to.equal(S.Bits)
					expect(sent[1].target).to.equal(p)
					expect(S.Push(NULL)).to.beFalse()
				end)
			end
		},
		{
			-- fails without the per player interval (a client could make the server ask every veto without end), or if the early question is lost
			name = "a question that comes too soon is answered once, later, not many times and not never",
			func = function()
				local S = GryMod.ModeStates
				local p = ply()
				override(p, "gryModesAnswered", nil)
				override(p, "gryModesPending", nil)

				recorded(function()
					local ok = S.Answer(p)
					expect(ok).to.beTrue()
					expect(#sent).to.equal(1)

					-- three questions in the same instant: nothing more now, ONE answer planned
					local again, why = S.Answer(p)
					expect(again).to.beFalse()
					expect(why).to.equal("deferred")
					S.Answer(p)
					S.Answer(p)
					expect(#sent).to.equal(1)
					expect(#timers).to.equal(1)
					expect(timers[1].delay <= S.AskInterval).to.beTrue()
					expect(timers[1].delay > 0).to.beTrue()

					-- the planned answer goes out and the next question is planned again
					timers[1].fn()
					expect(#sent).to.equal(2)
					expect(p.gryModesPending).to.beNil()
				end)
			end
		},
		{
			-- fails if the server stops answering after the first question (the stamp of the last answer must be read, not kept for ever)
			name = "a question after the interval is answered at once",
			func = function()
				local S = GryMod.ModeStates
				local p = ply()
				override(p, "gryModesAnswered", CurTime() - S.AskInterval - 0.01)
				override(p, "gryModesPending", nil)

				recorded(function()
					expect(S.Answer(p)).to.beTrue()
					expect(#sent).to.equal(1)
					expect(#timers).to.equal(0)
				end)
			end
		},
		{
			-- fails without the net.Receive of gry_modes_ask
			name = "the client's question gry_modes_ask is received and answered",
			func = function()
				local p = ply()
				local receiver = net.Receivers["gry_modes_ask"]
				expect(receiver).to.beA("function")
				override(p, "gryModesAnswered", nil)
				override(p, "gryModesPending", nil)

				recorded(function()
					receiver(0, p)
					expect(#sent).to.equal(1)
					expect(sent[1].name).to.equal("gry_modes_refused")
				end)
			end
		},
		{
			-- fails without GryMod.API.RefreshModeStates
			name = "GryMod.API.RefreshModeStates tells the quick menu at once (not held back by the interval), and refuses what is not a player",
			func = function()
				local p = ply()
				override(p, "gryModesAnswered", CurTime())

				recorded(function()
					expect(GryMod.API.RefreshModeStates(p)).to.beTrue()
					expect(#sent).to.equal(1)
					expect(sent[1].name).to.equal("gry_modes_refused")
					local ok, why = GryMod.API.RefreshModeStates(NULL)
					expect(ok).to.beFalse()
					expect(why).to.equal("invalid player")
					ok = GryMod.API.RefreshModeStates("x")
					expect(ok).to.beFalse()
					expect(#sent).to.equal(1)
				end)
			end
		}
	}
}
