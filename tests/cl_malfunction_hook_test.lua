-- Tests of the client reports GryMod_MalfunctionStart(ply) and GryMod_MalfunctionEnd(ply) (cl_mode_fx.lua), GLuaTest format, client realm.
-- The server has hooks of the same names (with the seconds and the reason, sv_malfunction.lua); the client only knows that the networked flag
-- "GryMalfunction" of a player changed, so it gives the player and nothing else. The game's change hook is called by hand, with a stand-in player:
-- no game state is touched.
--
-- Every case fails without the hook "GryMalfunctionReport" that cl_mode_fx.lua adds to EntityNetworkedVarChanged (the first line of each case
-- looks for it), and each check after that fails if the rule it names is missing in that hook.

local ADDON_HOOKS = {"GryMod_MalfunctionStart", "GryMod_MalfunctionEnd"}
local LISTENER = "GryMalfunctionHookTest"

local events
local realErrorNoHalt

local function reportHook()
	local all = hook.GetTable().EntityNetworkedVarChanged

	return all and all.GryMalfunctionReport
end

local function fakePlayer()
	return {IsValid = function() return true end}
end

return {
	groupName = "GryMod malfunction reports (client)",
	beforeEach = function(state)
		events = {}
		realErrorNoHalt = ErrorNoHalt

		for _, name in ipairs(ADDON_HOOKS) do
			hook.Add(name, LISTENER, function(...)
				events[#events + 1] = {name, ...}
			end)
		end
	end,
	afterEach = function(state)
		for _, name in ipairs(ADDON_HOOKS) do
			hook.Remove(name, LISTENER)
		end

		ErrorNoHalt = realErrorNoHalt
	end,
	cases = {
		{
			name = "Start when the flag of a player goes from false to true, End when it goes from true to false, each with the player and nothing else",
			func = function(state)
				local changed = reportHook()
				expect(changed).to.exist()

				local ply = fakePlayer()

				local ok, err = pcall(function()
					changed(ply, "GryMalfunction", false, true)
					expect(#events).to.equal(1)
					expect(events[1][1]).to.equal("GryMod_MalfunctionStart")
					expect(events[1][2]).to.equal(ply)
					expect(events[1][3]).to.beNil() -- no seconds, no reason: the client does not know them

					changed(ply, "GryMalfunction", true, false)
					expect(#events).to.equal(2)
					expect(events[2][1]).to.equal("GryMod_MalfunctionEnd")
					expect(events[2][2]).to.equal(ply)
					expect(events[2][3]).to.beNil()
				end)

				ErrorNoHalt = realErrorNoHalt

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the reports are for any player, not only the local one, and each hook gets the player whose flag changed",
			func = function(state)
				local changed = reportHook()
				expect(changed).to.exist()

				local first, second = fakePlayer(), fakePlayer()

				local ok, err = pcall(function()
					changed(first, "GryMalfunction", false, true)
					changed(second, "GryMalfunction", false, true)
					changed(first, "GryMalfunction", true, false)
					expect(#events).to.equal(3)
					expect(events[1][2]).to.equal(first)
					expect(events[2][2]).to.equal(second)
					expect(events[3][2]).to.equal(first)
				end)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "an old value of nil (the full update when a player comes into view, not a change) and a value that did not change report nothing",
			func = function(state)
				local changed = reportHook()
				expect(changed).to.exist()

				local ply = fakePlayer()

				local ok, err = pcall(function()
					changed(ply, "GryMalfunction", nil, true)
					changed(ply, "GryMalfunction", nil, false)
					changed(ply, "GryMalfunction", true, true)
					changed(ply, "GryMalfunction", false, false)
					expect(#events).to.equal(0)
				end)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "another variable of the player, or a value that is not a boolean, reports nothing",
			func = function(state)
				local changed = reportHook()
				expect(changed).to.exist()

				local ply = fakePlayer()

				local ok, err = pcall(function()
					changed(ply, "GryCloak", false, true)
					changed(ply, "GryEnergy", 50, 0)
					changed(ply, "GryMalfunction", 0, 1)
					changed(ply, "GryMalfunction", false, nil)
					expect(#events).to.equal(0)
				end)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "a listener that returns a value changes nothing, and a listener that fails does not stop the game's other change hooks (the error is shown once, not thrown)",
			func = function(state)
				local changed = reportHook()
				expect(changed).to.exist()

				local ply = fakePlayer()
				local shown = {}
				ErrorNoHalt = function(text) shown[#shown + 1] = text end

				hook.Add("GryMod_MalfunctionStart", LISTENER .. "Value", function() return false end)
				hook.Add("GryMod_MalfunctionEnd", LISTENER .. "Error", function() error("listener failed") end)

				local ok, err = pcall(function()
					local result = changed(ply, "GryMalfunction", false, true)
					expect(result).to.beNil() -- the hook of ours returns nothing, whatever a listener returned

					local thrown = pcall(changed, ply, "GryMalfunction", true, false)
					expect(thrown).to.beTrue()
					expect(#shown).to.equal(1)
				end)

				hook.Remove("GryMod_MalfunctionStart", LISTENER .. "Value")
				hook.Remove("GryMod_MalfunctionEnd", LISTENER .. "Error")
				ErrorNoHalt = realErrorNoHalt

				if not ok then error(err, 0) end
			end
		},
		{
			name = "no new Think or Tick hook: the reports ride on the game's change hook, which the file already used for the mode tint",
			func = function(state)
				expect(reportHook()).to.exist()
				expect(hook.GetTable().Think and hook.GetTable().Think.GryMalfunctionReport).to.beNil()
				expect(hook.GetTable().Tick and hook.GetTable().Tick.GryMalfunctionReport).to.beNil()
			end
		}
	}
}
