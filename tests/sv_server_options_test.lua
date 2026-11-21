-- Tests of the administrators' settings (GryMod.ServerOptions, sv_server_options.lua; the list of the settings is shared, sh_server_options.lua),
-- GLuaTest format, server realm. A client cannot change a server convar by itself (on a dedicated server a replicated convar refuses the
-- console of a client, and a convar that is not replicated does not exist for it), so the options panel sends ONE net message,
-- gry_set_server_option (the name of the setting, its value) and the SERVER decides: the sender is an admin (the host of a listen server and the
-- single player count, the server console is no sender), the name is in a white list of the settings of GryMod and nothing else, the value is
-- valid, and no more than 5 messages a second per player. A refusal is silent. Fake players (IsValid, IsAdmin) are used: the engine's real
-- players are not needed to check who is allowed, and the real convars are put back after each case.

local WHITELIST = {
	"gry_cloak_ai", "gry_drown_rules", "gry_energy_net", "gry_grenade_armed_only", "gry_malfunction", "gry_mechanics",
	"gry_movement", "gry_radar_allies_always", "gry_radar_objects"
}

local saved = {}

local function fakePlayer(admin)
	return {
		IsValid = function() return true end,
		IsAdmin = function() return admin end,
		Nick = function() return admin and "admin" or "player" end
	}
end

return {
	groupName = "GryMod administrators' settings (server)",
	beforeAll = function()
		for _, name in ipairs(WHITELIST) do
			saved[name] = GetConVar(name):GetString()
		end
	end,
	afterEach = function()
		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end
	end,
	afterAll = function()
		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end
	end,
	cases = {
		{
			name = "the module, its net message and its receiver exist",
			func = function()
				expect(GryMod.ServerOptions ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_set_server_option") ~= 0).to.beTrue()
				expect(net.Receivers["gry_set_server_option"] ~= nil).to.beTrue()
			end
		},
		{
			name = "the white list is exactly the settings of the options panel that are the server's, each one a real replicated convar the clients can read",
			func = function()
				local names = {}

				for _, setting in ipairs(GryMod.ServerSettings.List) do
					names[#names + 1] = setting.name
					local convar = GetConVar(setting.name)
					expect(convar ~= nil).to.beTrue()
					expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				end

				table.sort(names)
				expect(table.concat(names, ",")).to.equal(table.concat(WHITELIST, ","))
			end
		},
		{
			name = "an admin changes a yes / no setting, in both directions, and the convar of the server really changes",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)

				expect(O.Handle(admin, "gry_malfunction", "0", 1)).to.equal("ok")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal("0")
				expect(O.Handle(admin, "gry_malfunction", "1", 2)).to.equal("ok")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal("1")
			end
		},
		{
			name = "an admin changes the suit rules to crysis or classic, and only to those",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)

				expect(O.Handle(admin, "gry_mechanics", "classic", 1)).to.equal("ok")
				expect(GetConVar("gry_mechanics"):GetString()).to.equal("classic")
				expect(O.Handle(admin, "gry_mechanics", "crysis", 2)).to.equal("ok")
				expect(GetConVar("gry_mechanics"):GetString()).to.equal("crysis")

				for i, bad in ipairs({"Classic", "CRYSIS", "other", "", "1", "classic ", "classic;quit", " crysis"}) do
					expect(O.Handle(admin, "gry_mechanics", bad, 10 + i * 2)).to.equal("invalid")
					expect(GetConVar("gry_mechanics"):GetString()).to.equal("crysis")
				end
			end
		},
		{
			name = "a player who is not an admin changes nothing, with no error, for every setting of the list",
			func = function()
				local O = GryMod.ServerOptions
				local player = fakePlayer(false)

				for i, setting in ipairs(GryMod.ServerSettings.List) do
					local before = GetConVar(setting.name):GetString()
					local other = setting.kind == "choice" and (before == "crysis" and "classic" or "crysis") or (before == "1" and "0" or "1")
					local result
					expect(function() result = O.Handle(player, setting.name, other, i * 2) end).to.succeed()
					expect(result).to.equal("denied")
					expect(GetConVar(setting.name):GetString()).to.equal(before)
				end
			end
		},
		{
			name = "no sender (the server console, a player who left) is never allowed through a message",
			func = function()
				local O = GryMod.ServerOptions

				expect(O.Handle(nil, "gry_malfunction", "0", 1)).to.equal("denied")
				expect(O.Handle(NULL, "gry_malfunction", "0", 2)).to.equal("denied")
				expect(O.Handle({IsValid = function() return false end, IsAdmin = function() return true end}, "gry_malfunction", "0", 3)).to.equal("denied")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal(saved["gry_malfunction"])
			end
		},
		{
			name = "the authorisation is the one of the admin toggles (sv_system.lua): console and admins yes, others no",
			func = function()
				expect(GryMod.MayConfigure(NULL)).to.beTrue()
				expect(GryMod.MayConfigure(fakePlayer(true))).to.beTrue()
				expect(GryMod.MayConfigure(fakePlayer(false))).to.beFalse()
				expect(GryMod.MayConfigure(player.GetAll()[1])).to.equal(player.GetAll()[1]:IsAdmin())
			end
		},
		{
			name = "a name that is not in the list is refused, even a real convar, a cheat convar or another convar of GryMod",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)
				local gravity = GetConVar("sv_gravity"):GetString()
				local cheats = GetConVar("sv_cheats"):GetString()
				local contacts = GetConVar("gry_radar_contacts"):GetString()

				for i, name in ipairs({"sv_gravity", "sv_cheats", "gry_radar_contacts", "gry_hud", "gry_malfunction_shock", "rcon_password", "", "gry_malfunction ", "GRY_MALFUNCTION"}) do
					expect(O.Handle(admin, name, "0", i * 2)).to.equal("unknown")
				end

				expect(O.Handle(admin, nil, "0", 100)).to.equal("unknown")
				expect(O.Handle(admin, 5, "0", 102)).to.equal("unknown")
				expect(GetConVar("sv_gravity"):GetString()).to.equal(gravity)
				expect(GetConVar("sv_cheats"):GetString()).to.equal(cheats)
				expect(GetConVar("gry_radar_contacts"):GetString()).to.equal(contacts)
			end
		},
		{
			name = "a value that is not valid is refused for a yes / no setting: only 0 and 1",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)
				GetConVar("gry_cloak_ai"):SetString("1")

				for i, bad in ipairs({"2", "-1", "0.5", "abc", "", "1 ; quit", "true", "01", " 1", "1e0", "9999999999"}) do
					expect(O.Handle(admin, "gry_cloak_ai", bad, i * 2)).to.equal("invalid")
					expect(GetConVar("gry_cloak_ai"):GetString()).to.equal("1")
				end

				expect(O.Handle(admin, "gry_cloak_ai", nil, 100)).to.equal("invalid")
				expect(O.Handle(admin, "gry_cloak_ai", 0, 102)).to.equal("invalid") -- a number is not what the message carries: a string
				expect(O.Handle(admin, "gry_cloak_ai", {}, 104)).to.equal("invalid")
				expect(GetConVar("gry_cloak_ai"):GetString()).to.equal("1")
			end
		},
		{
			name = "the validation is a function of its own: the value that is stored, or nothing",
			func = function()
				local S = GryMod.ServerSettings

				expect(S.Validate("gry_malfunction", "1")).to.equal("1")
				expect(S.Validate("gry_malfunction", "0")).to.equal("0")
				expect(S.Validate("gry_malfunction", "2")).to.beNil()
				expect(S.Validate("gry_mechanics", "classic")).to.equal("classic")
				expect(S.Validate("gry_mechanics", "1")).to.beNil()
				expect(S.Validate("sv_cheats", "1")).to.beNil()
				expect(S.Find("gry_mechanics").kind).to.equal("choice")
				expect(S.Find("gry_malfunction").kind).to.equal("bool")
				expect(S.Find("sv_cheats")).to.beNil()
			end
		},
		{
			name = "five messages a second per player at most: the sixth and the ones after are ignored (even from an admin), the next second they count again",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)
				O.Forget(admin)

				for i = 1, 5 do
					expect(O.Handle(admin, "gry_malfunction", tostring(i % 2), 10 + i * 0.1)).to.equal("ok")
				end

				local afterFive = GetConVar("gry_malfunction"):GetString()
				expect(O.Handle(admin, "gry_malfunction", afterFive == "1" and "0" or "1", 10.7)).to.equal("rate")
				expect(O.Handle(admin, "gry_malfunction", afterFive == "1" and "0" or "1", 10.9)).to.equal("rate")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal(afterFive)

				-- a window of one second from the first message of the window
				expect(O.Handle(admin, "gry_malfunction", afterFive == "1" and "0" or "1", 11.2)).to.equal("ok")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal(afterFive == "1" and "0" or "1")
			end
		},
		{
			name = "the limit is per player, and a refused message of a player who is not an admin counts for him, not for the admin",
			func = function()
				local O = GryMod.ServerOptions
				local admin, player = fakePlayer(true), fakePlayer(false)
				O.Forget(admin)
				O.Forget(player)

				for i = 1, 5 do
					expect(O.Handle(player, "gry_malfunction", "0", 20 + i * 0.01)).to.equal("denied")
				end

				expect(O.Handle(player, "gry_malfunction", "0", 20.1)).to.equal("rate")
				expect(O.Handle(admin, "gry_malfunction", "0", 20.1)).to.equal("ok")
			end
		},
		{
			name = "a player who left is forgotten (no table that grows), and the hook is there",
			func = function()
				local O = GryMod.ServerOptions
				local admin = fakePlayer(true)
				O.Handle(admin, "gry_malfunction", "1", 1)
				expect(O.Tracked(admin)).to.beTrue()
				O.Forget(admin)
				expect(O.Tracked(admin)).to.beFalse()
				expect(hook.GetTable().PlayerDisconnected["GryMod server options"] ~= nil).to.beTrue()
			end
		},
		{
			name = "the host of a listen server and the single player are admins of the real engine player (the test game's player)",
			func = function()
				local p = player.GetAll()[1]
				expect(IsValid(p)).to.beTrue()
				expect(GryMod.MayConfigure(p)).to.beTrue()

				local O = GryMod.ServerOptions
				O.Forget(p)
				expect(O.Handle(p, "gry_malfunction", "0", 1)).to.equal("ok")
				expect(GetConVar("gry_malfunction"):GetString()).to.equal("0")
			end
		},
		{
			name = "the admin toggles of the panel (gry_Health, gry_Armor) keep refusing a player who is not an admin",
			func = function()
				local health, armor = GryMod.Config.ShouldRegen, GryMod.Config.InfiniteArmor

				expect(GryMod.ToggleHealthRegen(fakePlayer(false))).to.beFalse()
				expect(GryMod.ToggleInfiniteArmor(fakePlayer(false))).to.beFalse()
				expect(GryMod.Config.ShouldRegen).to.equal(health)
				expect(GryMod.Config.InfiniteArmor).to.equal(armor)
			end
		},
	}
}
