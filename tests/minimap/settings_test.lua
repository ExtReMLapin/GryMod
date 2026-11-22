-- Tests of the minimap's settings (lua/grymod/client/minimap/settings.lua), GLuaTest format, client realm. Eight saved client convars and
-- eight accessors that never return nil and never leave their range, whatever text the convar holds (the player can type anything in the
-- console or in a cfg file). The engine clamps a convar that has bounds (and turns a word into the lowest bound), so the texts that
-- cannot reach an accessor through the real convar are run through the pure Parse* functions the accessors are made of. The tile size is
-- snapped to the nearest of 512, 1024 and 2048: a tie (768 and 1536) goes to the smaller tile, which costs less memory.

local NAMES = {"gry_minimap", "gry_minimap_definition", "gry_minimap_tile", "gry_minimap_budget_ms", "gry_minimap_below", "gry_minimap_cache_mb", "gry_minimap_opacity", "gry_minimap_outside"}
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
			name = "the eight convars exist, with the defaults of the design",
			func = function()
				local defaults = {
					gry_minimap = "1", gry_minimap_definition = "3", gry_minimap_tile = "1024",
					gry_minimap_budget_ms = "6", gry_minimap_below = "40", gry_minimap_cache_mb = "256", gry_minimap_opacity = "90",
						gry_minimap_outside = "30"
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
					gry_minimap_budget_ms = {1, 30}, gry_minimap_below = {0, 100}, gry_minimap_cache_mb = {16, 4096}, gry_minimap_opacity = {0, 100},
						gry_minimap_outside = {0, 100}
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

				-- the eight are hidden from GetConVar so that the file creates them; the real function does the creating (it gives back the
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
			name = "the namespace has a Settings table with the eight accessors and the eight parsers",
			func = function()
				local S = GryMod.Minimap.Settings

				expect(S ~= nil).to.beTrue()

				for _, fn in ipairs({"Enabled", "Definition", "TileRes", "BudgetMs", "Below", "CacheBytes", "Opacity", "Outside", "ParseSwitch", "ParseDefinition", "ParseTileRes", "ParseBudgetMs", "ParseBelow", "ParseCacheMB", "ParseOpacity", "ParseOutside"}) do
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
				expect(S.Below()).to.equal(0.4)
				expect(S.CacheBytes()).to.equal(256 * 1048576)
				expect(S.Opacity()).to.aboutEqual(0.9, 1e-9)
				expect(S.Outside()).to.aboutEqual(0.3, 1e-9)
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
			name = "Below follows its convar as a fraction from 0 to 1: 0 gives 0, 40 gives 0.4, 100 gives 1, 150 gives 1, -5 gives 0",
			func = function()
				local S = GryMod.Minimap.Settings

				for text, fraction in pairs({["0"] = 0, ["40"] = 0.4, ["100"] = 1, ["150"] = 1, ["-5"] = 0, ["25"] = 0.25}) do
					set("gry_minimap_below", text)
					expect(S.Below()).to.aboutEqual(fraction, 1e-9)
				end
			end
		},
		{
			name = "ParseBelow: a whole percent from 0 to 100 divided by 100 (33.6 gives 0.34), the default (0.4) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseBelow

				expect(P("0")).to.equal(0)
				expect(P("40")).to.aboutEqual(0.4, 1e-9)
				expect(P("100")).to.equal(1)
				expect(P("150")).to.equal(1)
				expect(P("-5")).to.equal(0)
				expect(P("1e9")).to.equal(1)
				expect(P("-1e999")).to.equal(0)
				expect(P("33.6")).to.aboutEqual(0.34, 1e-9)

				for _, text in ipairs({"", "banana", "nan", "inf", " "}) do
					expect(P(text)).to.aboutEqual(0.4, 1e-9)
				end
			end
		},
		{
			name = "Outside follows its convar as a fraction from 0 to 1: 0 gives 0 (off), 30 gives 0.3, 100 gives 1, 150 gives 1, -5 gives 0",
			func = function()
				local S = GryMod.Minimap.Settings

				expect(isfunction(S.Outside)).to.beTrue()

				for text, fraction in pairs({["0"] = 0, ["30"] = 0.3, ["100"] = 1, ["150"] = 1, ["-5"] = 0, ["25"] = 0.25}) do
					set("gry_minimap_outside", text)
					expect(S.Outside()).to.aboutEqual(fraction, 1e-9)
				end
			end
		},
		{
			name = "ParseOutside: a whole percent from 0 to 100 divided by 100 (33.6 gives 0.34), the default (0.3) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseOutside

				expect(isfunction(P)).to.beTrue()
				expect(P("0")).to.equal(0)
				expect(P("30")).to.aboutEqual(0.3, 1e-9)
				expect(P("100")).to.equal(1)
				expect(P("150")).to.equal(1)
				expect(P("-5")).to.equal(0)
				expect(P("1e9")).to.equal(1)
				expect(P("-1e999")).to.equal(0)
				expect(P("33.6")).to.aboutEqual(0.34, 1e-9)

				for _, text in ipairs({"", "banana", "nan", "inf", " "}) do
					expect(P(text)).to.aboutEqual(0.3, 1e-9)
				end
			end
		},
		{
			name = "CacheBytes follows its convar, in bytes: 256 gives 268435456, 16 and 4096 are the ends, 5000 gives 4096 MB, 1 gives 16 MB",
			func = function()
				local S = GryMod.Minimap.Settings

				for text, megabytes in pairs({["256"] = 256, ["16"] = 16, ["4096"] = 4096, ["5000"] = 4096, ["1"] = 16, ["-5"] = 16}) do
					set("gry_minimap_cache_mb", text)
					expect(S.CacheBytes()).to.equal(megabytes * 1048576)
				end

				set("gry_minimap_cache_mb", "256")
				expect(S.CacheBytes()).to.equal(268435456)
			end
		},
		{
			name = "ParseCacheMB: whole megabytes from 16 to 4096 (100.6 gives 101), the default (256) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseCacheMB

				expect(P("256")).to.equal(256)
				expect(P("100.6")).to.equal(101)
				expect(P("0")).to.equal(16)
				expect(P("-5")).to.equal(16)
				expect(P("15")).to.equal(16)
				expect(P("4097")).to.equal(4096)
				expect(P("1e9")).to.equal(4096)
				expect(P("-1e999")).to.equal(16)
				expect(P("1e999")).to.equal(4096)

				for _, text in ipairs({"", "banana", "nan", "inf", " "}) do
					expect(P(text)).to.equal(256)
				end

				expect(P("100.6")).to.equal(math.floor(P("100.6")))
			end
		},
		{
			name = "Opacity follows its convar as a fraction from 0 to 1: 0 gives 0, 90 gives 0.9, 100 gives 1, 150 gives 1, -5 gives 0",
			func = function()
				local S = GryMod.Minimap.Settings

				for text, fraction in pairs({["0"] = 0, ["90"] = 0.9, ["100"] = 1, ["150"] = 1, ["-5"] = 0, ["25"] = 0.25}) do
					set("gry_minimap_opacity", text)
					expect(S.Opacity()).to.aboutEqual(fraction, 1e-9)
				end
			end
		},
		{
			name = "ParseOpacity: a whole percent from 0 to 100 divided by 100 (33.6 gives 0.34), the default (0.9) when the text is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseOpacity

				expect(P("0")).to.equal(0)
				expect(P("90")).to.aboutEqual(0.9, 1e-9)
				expect(P("100")).to.equal(1)
				expect(P("150")).to.equal(1)
				expect(P("-5")).to.equal(0)
				expect(P("1e9")).to.equal(1)
				expect(P("-1e999")).to.equal(0)
				expect(P("33.6")).to.aboutEqual(0.34, 1e-9)

				for _, text in ipairs({"", "banana", "nan", "inf", " "}) do
					expect(P(text)).to.aboutEqual(0.9, 1e-9)
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
					expect(S.Below() ~= nil and S.Below() >= 0 and S.Below() <= 1).to.beTrue()
					expect(S.ParseBelow(text) >= 0 and S.ParseBelow(text) <= 1).to.beTrue()
					expect(S.CacheBytes() >= 16 * 1048576 and S.CacheBytes() <= 4096 * 1048576).to.beTrue()
					expect(S.ParseCacheMB(text) >= 16 and S.ParseCacheMB(text) <= 4096).to.beTrue()
					expect(S.Opacity() ~= nil and S.Opacity() >= 0 and S.Opacity() <= 1).to.beTrue()
					expect(S.ParseOpacity(text) >= 0 and S.ParseOpacity(text) <= 1).to.beTrue()
					expect(S.Outside ~= nil and S.Outside() ~= nil and S.Outside() >= 0 and S.Outside() <= 1).to.beTrue()
					expect(S.ParseOutside ~= nil and S.ParseOutside(text) >= 0 and S.ParseOutside(text) <= 1).to.beTrue()
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
