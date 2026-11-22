-- Tests of what the client does when it has finished loading (cl_hud.lua), GLuaTest format, client realm. The mode of the suit is told to
-- a player by the server once, at the spawn, and the engine does not deliver net messages reliably before the client's InitPostEntity: a player who
-- joins a game in progress could keep a suit without a mode. The client now says "gry_client_ready" when it is ready (at InitPostEntity, and when the
-- file is loaded again in a running game), the server answers with the real mode (sv_system.lua, tested in sv_join_sync_test.lua), and until
-- something is received the mode is armor.
--
-- The real player's mode is his own: the cases use fake players (LocalPlayer is replaced for the length of a call) and recorders in place of the network
-- and the sounds; the real functions are put back right after each call, whatever happens inside.

local meta = FindMetaTable("Player")

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
	-- what the tint of a mode change reads of the player (cl_mode_fx.lua, FX.TintNow): alive, and no malfunction
	function me:Alive() return true end
	function me:GetNW2Bool(_, default) return default end

	return me
end

-- runs fn with `me` as the local player and the network, the sounds and the timers as recorders; returns what was done
local function recorded(me, fn)
	local log = {net = {}, sounds = {}, timers = 0}

	with({
		{_G, "LocalPlayer", function() return me end},
		{net, "Start", function(name) log.net[#log.net + 1] = {name = name} return true end},
		{net, "WriteUInt", function(value) log.net[#log.net].mode = value end},
		{net, "SendToServer", function() log.net[#log.net].sent = true end},
		{GryMod, "PlaySound", function(path) log.sounds[#log.sounds + 1] = path return true end},
		{timer, "Create", function() log.timers = log.timers + 1 end},
		{timer, "Remove", function() end}
	}, function()
		fn(log)
	end)

	return log
end

return {
	groupName = "GryMod client ready message and default mode (client)",
	cases = {
		{
			-- would fail if: GryMod.SendReady was removed, or sent another message
			name = "SendReady tells the server the client is ready (gry_client_ready, to the server), and says so",
			func = function()
				local me = fakeMe(nil)
				local result

				local log = recorded(me, function()
					result = GryMod.SendReady()
				end)

				expect(result).to.beTrue()
				expect(#log.net).to.equal(1)
				expect(log.net[1].name).to.equal("gry_client_ready")
				expect(log.net[1].sent).to.beTrue()
			end
		},
		{
			-- would fail if: SendReady did not check the local player (before InitPostEntity LocalPlayer() is a null entity)
			name = "SendReady does nothing without a local player (the game is not loaded yet)",
			func = function()
				local result
				local log = recorded(NULL, function()
					result = GryMod.SendReady()
				end)

				expect(result).to.beFalse()
				expect(#log.net).to.equal(0)
			end
		},
		{
			-- would fail if: the net message failed (the server did not pool its name: an old server, a reload of one side only) and the error went out of SendReady
			name = "SendReady does not raise an error when the server does not know the message",
			func = function()
				local me = fakeMe(nil)

				with({
					{_G, "LocalPlayer", function() return me end},
					{net, "Start", function() error("Calling net.Start with unpooled message name!") end}
				}, function()
					expect(function() GryMod.SendReady() end).to.succeed()
				end)
			end
		},
		{
			-- would fail if: the hook was removed (the message is then never sent when the game loads, which is the whole point)
			name = "the message is sent when the level is loaded: InitPostEntity has a hook for it",
			func = function()
				local hookFn = hook.GetTable().InitPostEntity and hook.GetTable().InitPostEntity.GryModClientReady
				expect(hookFn).to.beA("function")

				local log = recorded(fakeMe(nil), function()
					hookFn()
				end)

				expect(#log.net).to.equal(1)
				expect(log.net[1].name).to.equal("gry_client_ready")
			end
		},
		{
			-- would fail if: nothing set the default (the mode stayed nil: the quick menu has no pointer and the icons no mode until a message comes)
			name = "until the server says otherwise the mode is armor; a mode the player already has is left alone",
			func = function()
				local me = fakeMe(nil)
				expect(GryMod.AssumeDefaultMode(me)).to.beTrue()
				expect(me.NanosuitMode).to.equal(GryMod.Modes.ARMOR)

				local other = fakeMe(GryMod.Modes.CLOAK)
				expect(GryMod.AssumeDefaultMode(other)).to.beFalse()
				expect(other.NanosuitMode).to.equal(GryMod.Modes.CLOAK)
			end
		},
		{
			-- would fail if: the default were a plain assignment that the equality test of SetNanosuitMode then took for the mode the server told: the first real
			-- message ("armor") would find nothing to do, and the suit's armor sound and voice, heard at every first spawn before, would be lost
			name = "the default is a guess: the first mode the server tells, even armor, goes through the whole change (sound and voice), and only the second is the same mode again",
			func = function()
				local me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)

				local log = recorded(me, function()
					meta.SetNanosuitMode(me, GryMod.Modes.ARMOR, false)
				end)

				expect(#log.sounds).to.equal(1)
				expect(log.timers).to.equal(1) -- the voice
				expect(me.NanosuitMode).to.equal(GryMod.Modes.ARMOR)

				log = recorded(me, function()
					meta.SetNanosuitMode(me, GryMod.Modes.ARMOR, false)
				end)

				expect(#log.sounds).to.equal(0)
			end
		},
		{
			-- would fail if: the guess swallowed the player's own choice of armor (he asks for it from the quick menu before the server told anything: the server
			-- must hear it, as it did when the mode was nil)
			name = "the default does not swallow the player's own choice: armor asked from the menu while the mode is only a guess is sent to the server",
			func = function()
				local me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)

				local log = recorded(me, function()
					meta.SetNanosuitMode(me, GryMod.Modes.ARMOR, true)
				end)

				expect(#log.net).to.equal(1)
				expect(log.net[1].name).to.equal("gry_nanosuit_mode_change")
				expect(log.net[1].mode).to.equal(GryMod.Modes.ARMOR)
			end
		},
		{
			-- would fail if: the guess stayed marked after a real mode was set (the next request for the same mode would be done twice)
			name = "once a real mode is set the guess is gone: the same mode asked again does nothing",
			func = function()
				local me = fakeMe(nil)
				GryMod.AssumeDefaultMode(me)

				local log = recorded(me, function()
					meta.SetNanosuitMode(me, GryMod.Modes.SPEED, false)
					meta.SetNanosuitMode(me, GryMod.Modes.SPEED, false)
				end)

				expect(#log.sounds).to.equal(1)
				expect(me.NanosuitModeAssumed).to.beNil()
			end
		}
	}
}
