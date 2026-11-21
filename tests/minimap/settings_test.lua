-- Tests of the minimap's settings (lua/grymod/client/minimap/settings.lua), GLuaTest format, client realm. Four saved client convars and
-- four accessors that never return nil and never leave their range, whatever text the convar holds (the player can type anything in the
-- console or in a cfg file). The engine clamps a convar that has bounds (and turns a word into the lowest bound), so the texts that
-- cannot reach an accessor through the real convar are run through the pure Parse* functions the accessors are made of. The tile size is
-- snapped to the nearest of 512, 1024 and 2048: a tie (768 and 1536) goes to the smaller tile, which costs less memory.

local NAMES = {"gry_minimap", "gry_minimap_definition", "gry_minimap_tile", "gry_minimap_budget_ms"}
local SETTINGS_FILE = "grymod/client/minimap/settings.lua"

local function convar(name)
	return GetConVar(name)
end

local function set(name, text)
	convar(name):SetString(text)
end

return {
	groupName = "GryMod minimap settings",
	beforeEach = function(state)
		state.saved = {}

		for _, name in ipairs(NAMES) do
			local c = convar(name)
			state.saved[name] = c and c:GetString()
		end
	end,
	afterEach = function(state)
		-- a case that loaded the file with stand-ins puts the real functions back and loads it again, also when it failed
		if state.realGetConVar then
			pcall(function()
				GetConVar, CreateClientConVar = state.realGetConVar, state.realCreate
				include(SETTINGS_FILE)
			end)
		end

		for name, value in pairs(state.saved or {}) do
			local c = convar(name)

			if c then
				pcall(c.SetString, c, value)
			end
		end
	end,
	cases = {
		{
			name = "the four convars exist, with the defaults of the design",
			func = function()
				local defaults = {
					gry_minimap = "1", gry_minimap_definition = "3", gry_minimap_tile = "1024",
					gry_minimap_budget_ms = "6"
				}

				for name, default in pairs(defaults) do
					local c = convar(name)
					expect(c ~= nil).to.beTrue()
					expect(c:GetDefault()).to.equal(default)
				end
			end
		},
		{
			name = "the convars have the bounds of the design (the engine clamps what is typed)",
			func = function()
				local bounds = {
					gry_minimap = {0, 1}, gry_minimap_definition = {1, 16}, gry_minimap_tile = {512, 2048},
					gry_minimap_budget_ms = {1, 30}
				}

				for name, range in pairs(bounds) do
					local c = convar(name)
					expect(c ~= nil).to.beTrue()
					expect(c:GetMin()).to.equal(range[1])
					expect(c:GetMax()).to.equal(range[2])
				end
			end
		},
		{
			-- FCVAR_ARCHIVE cannot be read from Lua: a convar of CreateClientConVar never has it, saved or not (it is written in client.vdf
			-- instead), so the "saved" argument is checked where it is given: the file is run again with a spy on the creation
			name = "the convars are created saved (CreateClientConVar with shouldsave true), client side, with a help text",
			func = function(state)
				local created = {}
				state.realGetConVar, state.realCreate = GetConVar, CreateClientConVar

				-- the four are hidden from GetConVar so that the file creates them; the real function does the creating (it gives back the
				-- existing convar)
				GetConVar = function(name)
					for _, mine in ipairs(NAMES) do
						if mine == name then
							return nil
						end
					end

					return state.realGetConVar(name)
				end

				CreateClientConVar = function(name, default, shouldsave, userinfo, help, min, max)
					created[name] = {save = shouldsave, userinfo = userinfo, help = help, min = min, max = max}

					return state.realCreate(name, default, shouldsave, userinfo, help, min, max)
				end

				include(SETTINGS_FILE)

				for _, name in ipairs(NAMES) do
					expect(created[name] ~= nil).to.beTrue()
					expect(created[name].save).to.equal(true)
					expect(created[name].userinfo).to.equal(false)
					expect(isstring(created[name].help) and #created[name].help > 10).to.beTrue()
				end
			end
		},
		{
			name = "the namespace has a Settings table with the four accessors and the four parsers",
			func = function()
				local S = GryMod.Minimap.Settings

				expect(S ~= nil).to.beTrue()

				for _, fn in ipairs({"Enabled", "Definition", "TileRes", "BudgetMs", "ParseSwitch", "ParseDefinition", "ParseTileRes", "ParseBudgetMs"}) do
					expect(isfunction(S[fn])).to.beTrue()
				end
			end
		},
		{
			name = "the accessors give the defaults when the convars hold their default",
			func = function()
				local S = GryMod.Minimap.Settings

				for _, name in ipairs(NAMES) do
					set(name, convar(name):GetDefault())
				end

				expect(S.Enabled()).to.equal(true)
				expect(S.Definition()).to.equal(3)
				expect(S.TileRes()).to.equal(1024)
				expect(S.BudgetMs()).to.equal(6)
			end
		},
		{
			name = "Enabled follows its convar: 0 is false, 1 is true",
			func = function()
				local S = GryMod.Minimap.Settings

				for name, fn in pairs({gry_minimap = S.Enabled}) do
					set(name, "0")
					expect(fn()).to.equal(false)
					set(name, "1")
					expect(fn()).to.equal(true)
				end
			end
		},
		{
			name = "ParseSwitch: 0 and 0.4 are false (the engine takes the whole part), 1, 2, -1 are true, a text that is no number is the default (true)",
			func = function()
				local P = GryMod.Minimap.Settings.ParseSwitch

				expect(P("0")).to.equal(false)
				expect(P("0.4")).to.equal(false)
				expect(P("1")).to.equal(true)
				expect(P("2")).to.equal(true)
				expect(P("-1")).to.equal(true)

				for _, text in ipairs({"", "banana", "nan"}) do
					expect(P(text)).to.equal(true)
				end
			end
		},
		{
			name = "Definition follows its convar as a whole number: 3.7 gives 4, 3.2 gives 3, 16 stays 16, 1e9 gives 16 and -5 gives 1",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition", "3.7")
				expect(S.Definition()).to.equal(4)
				set("gry_minimap_definition", "3.2")
				expect(S.Definition()).to.equal(3)
				set("gry_minimap_definition", "16")
				expect(S.Definition()).to.equal(16)
				set("gry_minimap_definition", "1e9")
				expect(S.Definition()).to.equal(16)
				set("gry_minimap_definition", "-5")
				expect(S.Definition()).to.equal(1)
			end
		},
		{
			name = "ParseDefinition: whole numbers from 1 to 16 whatever the text; the default (3) when it is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseDefinition

				expect(P("3.7")).to.equal(4)
				expect(P("3.5")).to.equal(4)
				expect(P("3.2")).to.equal(3)
				expect(P("-5")).to.equal(1)
				expect(P("0")).to.equal(1)
				expect(P("1e9")).to.equal(16)
				expect(P("17")).to.equal(16)
				-- 1e999 is a number (infinity) and is clamped; the word "inf" is no number in LuaJIT
				expect(P("1e999")).to.equal(16)
				expect(P("-1e999")).to.equal(1)

				for _, text in ipairs({"", "banana", "nan", "inf", "-inf", "0x", " "}) do
					expect(P(text)).to.equal(3)
				end
			end
		},
		{
			name = "Definition stays an integer (a float would break the tile names and the cache key)",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition", "5.5")
				local d = S.Definition()
				expect(d).to.equal(math.floor(d))
				expect(d >= 1 and d <= 16).to.beTrue()
				expect(math.floor(GryMod.Minimap.Settings.ParseDefinition("9.5"))).to.equal(GryMod.Minimap.Settings.ParseDefinition("9.5"))
			end
		},
		{
			name = "TileRes keeps 512, 1024 and 2048 as they are",
			func = function()
				local S = GryMod.Minimap.Settings

				for _, res in ipairs({512, 1024, 2048}) do
					set("gry_minimap_tile", tostring(res))
					expect(S.TileRes()).to.equal(res)
				end
			end
		},
		{
			name = "TileRes follows its convar: 700 gives 512, 900 gives 1024, 1500 gives 1024, 1600 gives 2048",
			func = function()
				local S = GryMod.Minimap.Settings

				for text, res in pairs({["700"] = 512, ["900"] = 1024, ["1500"] = 1024, ["1600"] = 2048}) do
					set("gry_minimap_tile", text)
					expect(S.TileRes()).to.equal(res)
				end
			end
		},
		{
			name = "ParseTileRes: the nearest allowed size, 100 and -5 give 512, 99999 and 1e9 give 2048, 1000.4 gives 1024",
			func = function()
				local P = GryMod.Minimap.Settings.ParseTileRes

				for text, res in pairs({
					["700"] = 512, ["900"] = 1024, ["1500"] = 1024, ["1600"] = 2048, ["100"] = 512, ["-5"] = 512,
					["99999"] = 2048, ["1e9"] = 2048, ["1000.4"] = 1024
				}) do
					expect(P(text)).to.equal(res)
				end
			end
		},
		{
			name = "ParseTileRes: a tie (768, 1536) goes to the smaller tile",
			func = function()
				local P = GryMod.Minimap.Settings.ParseTileRes

				expect(P("768")).to.equal(512)
				expect(P("1536")).to.equal(1024)
			end
		},
		{
			name = "ParseTileRes: the default (1024) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseTileRes

				for _, text in ipairs({"", "banana", "nan"}) do
					expect(P(text)).to.equal(1024)
				end
			end
		},
		{
			name = "BudgetMs follows its convar, with decimals: 12.5 stays 12.5, 1e9 gives 30",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_budget_ms", "12.5")
				expect(S.BudgetMs()).to.equal(12.5)
				set("gry_minimap_budget_ms", "1e9")
				expect(S.BudgetMs()).to.equal(30)
				set("gry_minimap_budget_ms", "-5")
				expect(S.BudgetMs()).to.equal(1)
			end
		},
		{
			name = "ParseBudgetMs: from 1 to 30, the default (6) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseBudgetMs

				expect(P("12.5")).to.equal(12.5)
				expect(P("-5")).to.equal(1)
				expect(P("0")).to.equal(1)
				expect(P("1e9")).to.equal(30)
				expect(P("0.5")).to.equal(1)

				for _, text in ipairs({"", "banana", "nan"}) do
					expect(P(text)).to.equal(6)
				end
			end
		},
		{
			name = "the accessors follow the convar at once (nothing is cached)",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition", "2")
				expect(S.Definition()).to.equal(2)
				set("gry_minimap_definition", "9")
				expect(S.Definition()).to.equal(9)
			end
		},
		{
			name = "no accessor and no parser ever returns nil, whatever the text",
			func = function()
				local S = GryMod.Minimap.Settings

				for _, text in ipairs({"", "x", "1e9", "-1e9", "nan", "inf", "-inf", "0", "3.7", "999999999999999999999"}) do
					for _, name in ipairs(NAMES) do
						set(name, text)
					end

					expect(S.Enabled() ~= nil).to.beTrue()
					expect(S.Definition() ~= nil).to.beTrue()
					expect(S.TileRes() ~= nil).to.beTrue()
					expect(S.BudgetMs() ~= nil).to.beTrue()
					expect(S.Definition() >= 1 and S.Definition() <= 16).to.beTrue()
					expect(S.BudgetMs() >= 1 and S.BudgetMs() <= 30).to.beTrue()

					expect(S.ParseSwitch(text) ~= nil).to.beTrue()
					expect(S.ParseDefinition(text) >= 1 and S.ParseDefinition(text) <= 16).to.beTrue()
					expect(S.ParseBudgetMs(text) >= 1 and S.ParseBudgetMs(text) <= 30).to.beTrue()
					expect(S.ParseTileRes(text) >= 512 and S.ParseTileRes(text) <= 2048).to.beTrue()
				end
			end
		}
	}
}
