-- Tests of the two toggles of the administrators' section of the Config menu (sv_system.lua), GLuaTest format, server realm. "Health regeneration" and
-- "Infinite armor" used to be console commands that flipped a field of GryMod.Config and showed nothing of the state: they are real settings now, two
-- replicated and archived convars (gry_health_regen, gry_infinite_armor) that the options panel shows as check boxes and changes through the one net
-- message of the white list (sh_server_options.lua, sv_server_options.lua). GryMod.Config stays what the rest of the code reads: it follows the convars
-- (read at load, a change callback on each), and the console commands gry_Health and gry_Armor keep working and flip the convar.
-- The real convars and GryMod.Config are put back after every case (the convars are archived: the owner's own settings must survive a test run).

local NAMES = {"gry_health_regen", "gry_infinite_armor"}

-- the convar, the field of GryMod.Config that follows it, the console command that flips it, its default
local TOGGLES = {
	{convar = "gry_health_regen", field = "ShouldRegen", command = "gry_Health", default = "1"},
	{convar = "gry_infinite_armor", field = "InfiniteArmor", command = "gry_Armor", default = "0"}
}

local saved = {}
local savedConfig = {}

local function fakePlayer(admin)
	return {
		IsValid = function() return true end,
		IsAdmin = function() return admin end,
		Nick = function() return admin and "admin" or "player" end,
		ChatPrint = function() end
	}
end

return {
	groupName = "GryMod admin toggles (health regeneration, infinite armor)",
	beforeAll = function()
		for _, name in ipairs(NAMES) do
			local convar = GetConVar(name)

			-- a missing convar must not stop the other cases from reporting: they fail by themselves
			saved[name] = convar and convar:GetString()
		end

		for _, toggle in ipairs(TOGGLES) do
			savedConfig[toggle.field] = GryMod.Config[toggle.field]
		end
	end,
	afterEach = function()
		pcall(function()
			for name, value in pairs(saved) do
				GetConVar(name):SetString(value)
			end

			for field, value in pairs(savedConfig) do
				GryMod.Config[field] = value
			end
		end)
	end,
	afterAll = function()
		pcall(function()
			for name, value in pairs(saved) do
				GetConVar(name):SetString(value)
			end

			for field, value in pairs(savedConfig) do
				GryMod.Config[field] = value
			end
		end)
	end,
	cases = {
		{
			-- breaks if: a convar is not created in sv_system.lua, or it has another default, or it is not replicated (the clients could not show it)
			name = "the two convars exist, with the defaults (regeneration on, infinite armor off), replicated for the check boxes of the clients and notifying",
			func = function()
				for _, toggle in ipairs(TOGGLES) do
					local convar = GetConVar(toggle.convar)

					expect(convar ~= nil).to.beTrue()
					expect(convar:GetDefault()).to.equal(toggle.default)
					expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
					-- FCVAR_ARCHIVE is not readable on a server convar of a running game (gry_malfunction, made the same way, reads false too): the flags
					-- are written in sv_system.lua and checked by reading it
					expect(convar:IsFlagSet(FCVAR_NOTIFY)).to.beTrue()
				end
			end
		},
		{
			-- breaks if: the two names are missing from the white list of sh_server_options.lua (the administrators' check box would do nothing)
			name = "the two convars are in the white list of the server's settings as yes / no settings",
			func = function()
				for _, toggle in ipairs(TOGGLES) do
					local setting = GryMod.ServerSettings.Find(toggle.convar)

					expect(setting ~= nil).to.beTrue()
					expect(setting.kind).to.equal("bool")
					expect(GryMod.ServerSettings.Validate(toggle.convar, "0")).to.equal("0")
					expect(GryMod.ServerSettings.Validate(toggle.convar, "1")).to.equal("1")
					expect(GryMod.ServerSettings.Validate(toggle.convar, "2")).to.beNil()
				end
			end
		},
		{
			-- breaks if: the change callback of a convar is missing or does not set the field (the rest of the code reads GryMod.Config)
			name = "a change of the convar changes GryMod.Config, in both directions, for each toggle",
			func = function()
				for _, toggle in ipairs(TOGGLES) do
					local convar = GetConVar(toggle.convar)

					convar:SetString("1")
					expect(GryMod.Config[toggle.field]).to.beTrue()
					convar:SetString("0")
					expect(GryMod.Config[toggle.field]).to.beFalse()
					convar:SetString("1")
					expect(GryMod.Config[toggle.field]).to.beTrue()
				end
			end
		},
		{
			-- breaks if: the callback writes a table it captured (a test or another file replaces GryMod.Config) instead of looking GryMod.Config up
			name = "the callbacks write the GryMod.Config of the moment, also when the table was replaced (sv_grymod_test.lua does it)",
			func = function()
				local realConfig = GryMod.Config
				local ok, err = pcall(function()
					GryMod.Config = table.Copy(realConfig)
					GetConVar("gry_infinite_armor"):SetString("1")
					expect(GryMod.Config.InfiniteArmor).to.beTrue()
					GetConVar("gry_infinite_armor"):SetString("0")
					expect(GryMod.Config.InfiniteArmor).to.beFalse()
				end)

				GryMod.Config = realConfig

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: GryMod.SyncToggles is missing, or only reads one of the two convars (it is what runs at load)
			name = "the sync that runs at load reads both convars into GryMod.Config, whatever the fields held",
			func = function()
				expect(isfunction(GryMod.SyncToggles)).to.beTrue()

				for _, state in ipairs({{"1", "0"}, {"0", "1"}, {"1", "1"}, {"0", "0"}}) do
					GetConVar("gry_health_regen"):SetString(state[1])
					GetConVar("gry_infinite_armor"):SetString(state[2])

					-- what a test, or the code before the sync, may have left in the fields
					GryMod.Config.ShouldRegen = state[1] ~= "1"
					GryMod.Config.InfiniteArmor = state[2] ~= "1"

					GryMod.SyncToggles()

					expect(GryMod.Config.ShouldRegen).to.equal(state[1] == "1")
					expect(GryMod.Config.InfiniteArmor).to.equal(state[2] == "1")
				end
			end
		},
		{
			-- breaks if: the concommand still flips only the field (the check box would not follow it), or stops working
			name = "gry_Health and gry_Armor keep working from the server console: each flips the convar and GryMod.Config, back and forth",
			func = function()
				for _, toggle in ipairs(TOGGLES) do
					local convar = GetConVar(toggle.convar)

					convar:SetString(toggle.default)

					local before = convar:GetBool()

					expect(concommand.Run(NULL, toggle.command, {}, "")).to.beTrue()
					expect(convar:GetBool()).to.equal(not before)
					expect(GryMod.Config[toggle.field]).to.equal(not before)

					expect(concommand.Run(NULL, toggle.command, {}, "")).to.beTrue()
					expect(convar:GetBool()).to.equal(before)
					expect(GryMod.Config[toggle.field]).to.equal(before)
				end
			end
		},
		{
			-- breaks if: the toggle flips the convar from its own value and leaves the field behind when the two differ (a test that wrote the field, an addon)
			name = "the toggles go by GryMod.Config and bring the convar to the same value, also when the two had drifted apart",
			func = function()
				GetConVar("gry_health_regen"):SetString("0")
				GryMod.Config.ShouldRegen = true -- written by hand, as the other tests do
				GryMod.ToggleHealthRegen(NULL)
				expect(GryMod.Config.ShouldRegen).to.beFalse()
				expect(GetConVar("gry_health_regen"):GetBool()).to.beFalse()

				GetConVar("gry_infinite_armor"):SetString("1")
				GryMod.Config.InfiniteArmor = false
				GryMod.ToggleInfiniteArmor(NULL)
				expect(GryMod.Config.InfiniteArmor).to.beTrue()
				expect(GetConVar("gry_infinite_armor"):GetBool()).to.beTrue()
			end
		},
		{
			-- breaks if: the check was dropped from the toggles (a player who is not an admin could flip the setting from the console)
			name = "a player who is not an admin cannot flip them from the console either: the convar and the field stay",
			func = function()
				for _, toggle in ipairs(TOGGLES) do
					local convar = GetConVar(toggle.convar)
					local before, field = convar:GetString(), GryMod.Config[toggle.field]

					expect(concommand.Run(fakePlayer(false), toggle.command, {}, "")).to.beTrue() -- the command ran and refused
					expect(convar:GetString()).to.equal(before)
					expect(GryMod.Config[toggle.field]).to.equal(field)
				end
			end
		},
		{
			-- breaks if: the handler lets a player who is not an admin through for these two names (the white list is not the only door)
			name = "the message of the options panel: a player who is not an admin is denied for both, an admin changes the convar and GryMod.Config follows",
			func = function()
				local O = GryMod.ServerOptions
				local admin, other = fakePlayer(true), fakePlayer(false)
				local t = 1

				for _, toggle in ipairs(TOGGLES) do
					local convar = GetConVar(toggle.convar)

					convar:SetString(toggle.default)

					local before, field = convar:GetString(), GryMod.Config[toggle.field]
					local flipped = before == "1" and "0" or "1"

					t = t + 10
					expect(O.Handle(other, toggle.convar, flipped, t)).to.equal("denied")
					expect(convar:GetString()).to.equal(before)
					expect(GryMod.Config[toggle.field]).to.equal(field)

					t = t + 10
					expect(O.Handle(admin, toggle.convar, flipped, t)).to.equal("ok")
					expect(convar:GetString()).to.equal(flipped)
					expect(GryMod.Config[toggle.field]).to.equal(flipped == "1")

					t = t + 10
					expect(O.Handle(admin, toggle.convar, before, t)).to.equal("ok")
					expect(GryMod.Config[toggle.field]).to.equal(before == "1")

					-- a value that is not 0 or 1 is invalid, and nothing changes
					t = t + 10
					expect(O.Handle(admin, toggle.convar, "2", t)).to.equal("invalid")
					expect(convar:GetString()).to.equal(before)
				end
			end
		},
		{
			-- breaks if: the two convars are created without FCVAR_ARCHIVE (the engine then forgets an administrator's choice at the next start)
			name = "the two convars are archived, so the choice of the administrator is kept from one session to the next",
			func = function()
				local source = file.Read("grymod/server/sv_system.lua", "LUA")

				expect(source ~= nil).to.beTrue()

				local flags = source:match("local toggleFlags = ([^\n]+)")

				expect(flags ~= nil).to.beTrue()
				expect(flags:find("FCVAR_ARCHIVE", 1, true) ~= nil).to.beTrue()
				expect(flags:find("FCVAR_REPLICATED", 1, true) ~= nil).to.beTrue()
			end
		}
	}
}
