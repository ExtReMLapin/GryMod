-- Tests of the hook GryMod_ModeChanged(ply, mode, oldMode, reason) on the CLIENT (cl_hud.lua), GLuaTest format, client realm. The same hook, with the same
-- arguments, runs on the server (sv_api_suit_test.lua); the client runs it only for the local player, the one whose mode it knows. The cause comes from the
-- server as an id in the message gry_nanosuit_mode_change (the mode, then the cause) and is a string again in the hook.
--
-- The real player's mode is his own: the cases use a fake local player (LocalPlayer is replaced for the length of a call) and recorders in place of the
-- network, the sounds and the timers; the real functions are put back right after each call, whatever happens inside. The hooks of the cases are removed
-- in afterEach.

local meta = FindMetaTable("Player")
local Modes, Why = GryMod.Modes, GryMod.ModeReasons

-- the real functions are put back right after fn, in any case
local function with(stubs, fn)
	local saved = {}

	for _, entry in ipairs(stubs) do
		saved[#saved + 1] = {entry[1], entry[2], entry[1][entry[2]]}
		entry[1][entry[2]] = entry[3]
	end

	local ok, err = pcall(fn)

	for i = #saved, 1, -1 do
		saved[i][1][saved[i][2]] = saved[i][3]
	end

	if not ok then
		error(err, 0)
	end
end

-- the local player, as far as the mode code goes
local function fakeMe(mode)
	local me = {NanosuitMode = mode}

	function me:IsValid() return true end
	function me:GetViewModel() return NULL end
	function me:GetHands() return NULL end
	function me:Alive() return true end
	function me:GetNW2Bool(_, default) return default end

	return me
end

-- the hook calls of a case: {ply, mode, oldMode, reason, modeSeen (the player's mode at the moment of the call)}
local calls = {}
local hookId = "gry_cl_mode_changed_hook_test"

local function listen()
	calls = {}

	hook.Add("GryMod_ModeChanged", hookId, function(ply, mode, old, why)
		calls[#calls + 1] = {ply, mode, old, why, ply.NanosuitMode}
	end)
end

-- runs fn with `me` as the local player and the network, the sounds and the timers as recorders; returns what was done
local function recorded(me, fn)
	local log = {net = {}, sounds = {}, timers = 0}

	with({
		{_G, "LocalPlayer", function() return me end},
		{net, "Start", function(name) log.net[#log.net + 1] = {name = name, writes = {}} return true end},
		{net, "WriteUInt", function(value, bits)
			local writes = log.net[#log.net].writes
			writes[#writes + 1] = {value, bits}
		end},
		{net, "SendToServer", function() log.net[#log.net].sent = true end},
		{GryMod, "PlaySound", function(path) log.sounds[#log.sounds + 1] = path return true end},
		{timer, "Create", function() log.timers = log.timers + 1 end},
		{timer, "Remove", function() end}
	}, function()
		fn(log)
	end)

	return log
end

-- the message of the server as the client reads it: the mode, then the id of the cause (a queue in place of net.ReadUInt); the widths asked are kept
local function receive(me, mode, id)
	local queue, widths = {mode, id}, {}
	local receiver = net.Receivers["gry_nanosuit_mode_change"]

	expect(receiver).to.beA("function")

	local log = recorded(me, function()
		with({
			{net, "ReadUInt", function(bits)
				widths[#widths + 1] = bits

				return table.remove(queue, 1)
			end}
		}, function()
			receiver(0)
		end)
	end)

	log.widths = widths

	return log
end

local function idOf(reason)
	return GryMod.ModeReasonIds[reason]
end

return {
	groupName = "GryMod_ModeChanged on the client (local player)",
	afterEach = function()
		hook.Remove("GryMod_ModeChanged", hookId)
		calls = {}
	end,
	cases = {
		{
			-- would fail if: the receiver still read only the mode (no cause: the hook would not know why), or the hook was not run on the client
			name = "a change sent by the server runs the hook once with (local player, mode, old mode, cause as a string), and the cause is read in ModeReasonBits",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				local log = receive(me, Modes.SPEED, idOf(Why.ENERGY))

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(me)
				expect(calls[1][2]).to.equal(Modes.SPEED)
				expect(calls[1][3]).to.equal(Modes.ARMOR)
				expect(calls[1][4]).to.equal(Why.ENERGY)
				expect(log.widths[1]).to.equal(3)
				expect(log.widths[2]).to.equal(GryMod.ModeReasonBits)
			end
		},
		{
			-- would fail if: the id was not turned back with the list (a wrong or shifted string) for some cause
			name = "every cause comes out of the wire as its own string",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				for key, reason in pairs(Why) do
					calls = {}
					me.NanosuitMode = Modes.ARMOR
					receive(me, Modes.CLOAK, idOf(reason))

					expect(#calls).to.equal(1)
					expect(calls[1][4]).to.equal(reason)
				end
			end
		},
		{
			-- would fail if: an id the list does not know raised an error or went through as nil (an addon would get a nil cause)
			name = "an id that no cause has (a newer server) goes through as OTHER",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				receive(me, Modes.SPEED, 15)

				expect(#calls).to.equal(1)
				expect(calls[1][4]).to.equal(Why.OTHER)
			end
		},
		{
			-- would fail if: the hook ran BEFORE the assignment (a handler reading the player's mode would still see the old one)
			name = "the hook runs after the mode is set: the player's mode is the new one inside the handler",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				receive(me, Modes.STRENGTH, idOf(Why.API))

				expect(calls[1][5]).to.equal(Modes.STRENGTH)
			end
		},
		{
			-- would fail if: DROP (not a mode, only the weapon is dropped) ran the hook, or changed the player's mode
			name = "dropping the suit's item (DROP) is not a mode: no hook, the mode stays",
			func = function()
				listen()
				local me = fakeMe(Modes.SPEED)

				local log = recorded(me, function()
					meta.SetNanosuitMode(me, Modes.DROP, true, Why.PLAYER)
				end)

				expect(#calls).to.equal(0)
				expect(me.NanosuitMode).to.equal(Modes.SPEED)
				expect(log.net[1].name).to.equal("gry_drop")
			end
		},
		{
			-- would fail if: both the early path and the end of SetNanosuitMode ran the hook, or ApplyServerMode ran it again
			name = "one hook per change, and none for the same mode again with another cause (sync, vetoed, api, other)",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				receive(me, Modes.SPEED, idOf(Why.API))
				expect(#calls).to.equal(1)

				for _, reason in ipairs({Why.API, Why.SYNC, Why.VETOED, Why.PLAYER, Why.OTHER, Why.ENERGY}) do
					receive(me, Modes.SPEED, idOf(reason))
				end

				expect(#calls).to.equal(1)
			end
		},
		{
			-- would fail if: the early return of SetNanosuitMode ("same mode: nothing") came before the hook (a respawn from armor to armor would be silent)
			name = "a respawn from armor to armor is announced (cause SPAWN, mode = old mode = armor) without the HUD event, the sound or the voice",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				local log = receive(me, Modes.ARMOR, idOf(Why.SPAWN))

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(me)
				expect(calls[1][2]).to.equal(Modes.ARMOR)
				expect(calls[1][3]).to.equal(Modes.ARMOR)
				expect(calls[1][4]).to.equal(Why.SPAWN)
				expect(#log.sounds).to.equal(0)
				expect(log.timers).to.equal(0)
			end
		},
		{
			-- would fail if: a respawn from another mode ran the hook twice (the early path and the end), or lost the old mode
			name = "a respawn from the camouflage is one hook (armor, old mode camouflage, SPAWN) and plays the change as before",
			func = function()
				listen()
				local me = fakeMe(Modes.CLOAK)

				local log = receive(me, Modes.ARMOR, idOf(Why.SPAWN))

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(Modes.ARMOR)
				expect(calls[1][3]).to.equal(Modes.CLOAK)
				expect(calls[1][4]).to.equal(Why.SPAWN)
				expect(#log.sounds).to.equal(1)
			end
		},
		{
			-- would fail if: the guessed armor of the loading (AssumeDefaultMode) was not the old mode: the first real mode would have no old mode (nil)
			name = "the assumed armor of the loading is the old mode: the first mode the server tells (sync) runs the hook with old = armor",
			func = function()
				listen()
				local me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)

				receive(me, Modes.CLOAK, idOf(Why.SYNC))

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(Modes.CLOAK)
				expect(calls[1][3]).to.equal(Modes.ARMOR)
				expect(calls[1][4]).to.equal(Why.SYNC)
			end
		},
		{
			-- would fail if: the guess made the first "armor" of the server a change for the hook (the suit was in armor all along: a new player is not a change)
			name = "the assumed armor then armor from the server (sync): the change plays as before, but no hook (the mode did not change); with the cause SPAWN it is announced",
			func = function()
				listen()
				local me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)

				local log = receive(me, Modes.ARMOR, idOf(Why.SYNC))

				expect(#calls).to.equal(0)
				expect(#log.sounds).to.equal(1) -- the armor sound of the first spawn is still heard
				expect(me.NanosuitModeAssumed).to.beNil()

				me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)
				receive(me, Modes.ARMOR, idOf(Why.SPAWN))

				expect(#calls).to.equal(1)
				expect(calls[1][3]).to.equal(Modes.ARMOR)
				expect(calls[1][4]).to.equal(Why.SPAWN)
			end
		},
		{
			-- would fail if: the quick menu's request had no cause (OTHER), or the client wrote the cause in its message to the server (it sends the mode only)
			name = "the player's own change is applied at once with the cause PLAYER, and the message to the server is the mode alone",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				local log = recorded(me, function()
					meta.SetNanosuitMode(me, Modes.SPEED, true, Why.PLAYER)
				end)

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(Modes.SPEED)
				expect(calls[1][3]).to.equal(Modes.ARMOR)
				expect(calls[1][4]).to.equal(Why.PLAYER)

				expect(log.net[1].name).to.equal("gry_nanosuit_mode_change")
				expect(#log.net[1].writes).to.equal(1)
				expect(log.net[1].writes[1][1]).to.equal(Modes.SPEED)
				expect(log.net[1].writes[1][2]).to.equal(3)
			end
		},
		{
			-- would fail if: the refusal's answer did not reach the hook (the addon would think the change stayed) or came with another cause
			name = "when the server refuses the player's change, a second hook comes with the real mode and the cause VETOED",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				recorded(me, function()
					meta.SetNanosuitMode(me, Modes.CLOAK, true, Why.PLAYER)
				end)

				receive(me, Modes.ARMOR, idOf(Why.VETOED))

				expect(#calls).to.equal(2)
				expect(calls[2][2]).to.equal(Modes.ARMOR)
				expect(calls[2][3]).to.equal(Modes.CLOAK)
				expect(calls[2][4]).to.equal(Why.VETOED)
			end
		},
		{
			-- would fail if: a call without a cause got nil (or the old default) instead of OTHER
			name = "a call without a cause gives OTHER",
			func = function()
				listen()
				local me = fakeMe(Modes.ARMOR)

				recorded(me, function()
					meta.SetNanosuitMode(me, Modes.STRENGTH, false)
				end)

				expect(calls[1][4]).to.equal(Why.OTHER)
			end
		},
		{
			-- would fail if: ApplyServerMode ran the hook for a player that is not there yet (the game is loading: LocalPlayer() is a null entity)
			name = "no local player yet (the game is loading): nothing is done, no hook, no error",
			func = function()
				listen()

				expect(function()
					receive(NULL, Modes.SPEED, idOf(Why.SYNC))
				end).to.succeed()

				expect(#calls).to.equal(0)
			end
		}
	}
}
