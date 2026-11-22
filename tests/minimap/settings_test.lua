-- Tests of the minimap's settings (lua/grymod/client/minimap/settings.lua), GLuaTest format, client realm. Nine saved client convars and
-- nine accessors that never return nil and never leave their range, whatever text the convar holds (the player can type anything in the
-- console or in a cfg file). The engine clamps a convar that has bounds (and turns a word into the lowest bound), so the texts that
-- cannot reach an accessor through the real convar are run through the pure Parse* functions the accessors are made of. The tile size is
-- snapped to the nearest of 512, 1024 and 2048: a tie (768 and 1536) goes to the smaller tile, which costs less memory.

local NAMES = {"gry_minimap", "gry_minimap_definition", "gry_minimap_tile", "gry_minimap_budget_ms", "gry_minimap_below", "gry_minimap_cache_mb", "gry_minimap_opacity", "gry_minimap_outside", "gry_minimap_definition_auto"}
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

		-- the automatic definition keeps its state in the module (Settings.AutoState): it is put back as it was, so that the radar of a running game is not
		-- disturbed by the cases that change it
		local live = GryMod.Minimap.Settings.AutoState
		state.autoState = live and {current = live.current, previous = live.previous}

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

		pcall(function()
			local live = GryMod.Minimap.Settings.AutoState

			if live and state.autoState then
				live.current, live.previous = state.autoState.current, state.autoState.previous
			end
		end)
	end,
	cases = {
		{
			name = "the nine convars exist, with the defaults of the design (the automatic definition is on)",
			func = function()
				local defaults = {
					gry_minimap = "1", gry_minimap_definition = "3", gry_minimap_tile = "1024",
					gry_minimap_budget_ms = "6", gry_minimap_below = "40", gry_minimap_cache_mb = "256", gry_minimap_opacity = "90",
						gry_minimap_outside = "30", gry_minimap_definition_auto = "1"
				}

				for name, default in pairs(defaults) do
					local c = convar(name)
					expect(c ~= nil).to.beTrue()
					expect(c:GetDefault()).to.equal(default)
				end
			end
		},
		{
			-- The bounds are checked where the file gives them (the creation call, spied on in the next case): the engine keeps the bounds a convar had when it
			-- was first created, so in a game that was already running when the definition's upper bound went from 16 to 64 the live convar still says 16 until
			-- the game is restarted. The live convars are checked for what they do not share with that: the minimum of the definition and the other bounds.
			name = "the live convars have the bounds of the design (the engine clamps what is typed), except the upper bound of the definition in a game that started with the old file",
			func = function()
				local bounds = {
					gry_minimap = {0, 1}, gry_minimap_definition = {1, false}, gry_minimap_tile = {512, 2048},
					gry_minimap_budget_ms = {1, 30}, gry_minimap_below = {0, 100}, gry_minimap_cache_mb = {16, 4096}, gry_minimap_opacity = {0, 100},
						gry_minimap_outside = {0, 100}, gry_minimap_definition_auto = {0, 1}
				}

				for name, range in pairs(bounds) do
					local c = convar(name)
					expect(c ~= nil).to.beTrue()
					expect(c:GetMin()).to.equal(range[1])

					if range[2] then
						expect(c:GetMax()).to.equal(range[2])
					end
				end

				-- 16 (the old bound) or 64 (the new one): never another number
				local max = convar("gry_minimap_definition"):GetMax()
				expect(max == 16 or max == 64).to.beTrue()
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

				-- the bounds the file asks for (a convar that exists keeps its first ones, see the case above)
				local bounds = {
					gry_minimap = {0, 1}, gry_minimap_definition = {1, 64}, gry_minimap_tile = {512, 2048},
					gry_minimap_budget_ms = {1, 30}, gry_minimap_below = {0, 100}, gry_minimap_cache_mb = {16, 4096}, gry_minimap_opacity = {0, 100},
						gry_minimap_outside = {0, 100}, gry_minimap_definition_auto = {0, 1}
				}

				for name, range in pairs(bounds) do
					expect(created[name].min).to.equal(range[1])
					expect(created[name].max).to.equal(range[2])
				end
			end
		},
		{
			name = "the namespace has a Settings table with the nine accessors, the nine parsers and the functions of the automatic definition",
			func = function()
				local S = GryMod.Minimap.Settings

				expect(S ~= nil).to.beTrue()

				for _, fn in ipairs({"Enabled", "Definition", "DefinitionAuto", "TileRes", "BudgetMs", "Below", "CacheBytes", "Opacity", "Outside", "ParseSwitch", "ParseDefinition", "ParseDefinitionAuto", "ParseTileRes", "ParseBudgetMs", "ParseBelow", "ParseCacheMB", "ParseOpacity", "ParseOutside", "SetAutoDefinition", "AutoDefinitionFor", "PreviousDefinition"}) do
					expect(isfunction(S[fn])).to.beTrue()
				end
			end
		},
		{
			-- the radar gives the screen constant at every draw (see radar_integration_test); the preload reads it. breaks if a bad value replaces a good one, or is accepted
			name = "the screen constant: SetScreenConstant keeps a positive finite number and refuses anything else (the old value stays); ScreenConstant gives it",
			func = function()
				local S = GryMod.Minimap.Settings
				local live = S.ScreenConstant and S.ScreenConstant()

				expect(isfunction(S.SetScreenConstant)).to.beTrue()
				expect(isfunction(S.ScreenConstant)).to.beTrue()

				local ok, err = pcall(function()
					expect(S.SetScreenConstant(130)).to.equal(true)
					expect(S.ScreenConstant()).to.equal(130)

					for _, bad in ipairs({0, -5, 0 / 0, math.huge, "130", true}) do
						expect(S.SetScreenConstant(bad)).to.equal(false)
						expect(S.ScreenConstant()).to.equal(130)
					end

					expect(S.SetScreenConstant(1.5)).to.equal(true)
					expect(S.ScreenConstant()).to.equal(1.5)
				end)

				-- the running radar's own value is put back
				S.ScreenK = live

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the accessors give the defaults when the convars hold their default",
			func = function()
				local S = GryMod.Minimap.Settings

				for _, name in ipairs(NAMES) do
					set(name, convar(name):GetDefault())
				end

				-- the automatic definition is on by default: the definition in use is then the one the radar calculated (4 until it calculates one)
				expect(S.DefinitionAuto()).to.equal(true)
				S.AutoState.current, S.AutoState.previous = 4, nil
				expect(S.Definition()).to.equal(4)
				-- off: the slider's own default
				set("gry_minimap_definition_auto", "0")
				expect(S.Definition()).to.equal(3)
				expect(S.Enabled()).to.equal(true)
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
			-- the bound is 64 since the automatic definition (the manual slider goes up to the top level of the pyramid); the old bound was 16
			name = "Definition (automatic off) follows its convar as a whole number: 3.7 gives 4, 3.2 gives 3, 16 stays 16, 64 stays 64, 1e9 gives 64 and -5 gives 1",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition_auto", "0")
				set("gry_minimap_definition", "3.7")
				expect(S.Definition()).to.equal(4)
				set("gry_minimap_definition", "3.2")
				expect(S.Definition()).to.equal(3)
				set("gry_minimap_definition", "16")
				expect(S.Definition()).to.equal(16)
				-- the engine's own clamp is the live convar's upper bound: 64 in a game that started with this file, 16 in one that was already running (ParseDefinition,
				-- below, holds the 64 in both)
				local top = convar("gry_minimap_definition"):GetMax()
				set("gry_minimap_definition", "64")
				expect(S.Definition()).to.equal(top)
				set("gry_minimap_definition", "1e9")
				expect(S.Definition()).to.equal(top)
				set("gry_minimap_definition", "-5")
				expect(S.Definition()).to.equal(1)
			end
		},
		{
			name = "ParseDefinition: whole numbers from 1 to 64 whatever the text; the default (3) when it is no number",
			func = function()
				local P = GryMod.Minimap.Settings.ParseDefinition

				expect(P("3.7")).to.equal(4)
				expect(P("3.5")).to.equal(4)
				expect(P("3.2")).to.equal(3)
				expect(P("-5")).to.equal(1)
				expect(P("0")).to.equal(1)
				expect(P("1e9")).to.equal(64)
				expect(P("17")).to.equal(17)
				expect(P("64")).to.equal(64)
				expect(P("65")).to.equal(64)
				-- 1e999 is a number (infinity) and is clamped; the word "inf" is no number in LuaJIT
				expect(P("1e999")).to.equal(64)
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

				set("gry_minimap_definition_auto", "0")
				set("gry_minimap_definition", "5.5")
				local d = S.Definition()
				expect(d).to.equal(math.floor(d))
				expect(d >= 1 and d <= 64).to.beTrue()
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

				set("gry_minimap_definition_auto", "0")
				set("gry_minimap_definition", "2")
				expect(S.Definition()).to.equal(2)
				set("gry_minimap_definition", "9")
				expect(S.Definition()).to.equal(9)
			end
		},
		{
			name = "ParseDefinitionAuto: a switch like the others (0 and 0.4 are false, 1, 2, -1 are true), a text that is no number is the default (true, automatic)",
			func = function()
				local P = GryMod.Minimap.Settings.ParseDefinitionAuto

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
			name = "DefinitionAuto follows its convar at once: 0 is false, 1 is true",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition_auto", "0")
				expect(S.DefinitionAuto()).to.equal(false)
				set("gry_minimap_definition_auto", "1")
				expect(S.DefinitionAuto()).to.equal(true)
			end
		},
		{
			name = "the state of the automatic definition starts at 4 with no previous level (the module's first load)",
			func = function()
				local S = GryMod.Minimap.Settings

				S.AutoState = nil
				include(SETTINGS_FILE)
				set("gry_minimap_definition_auto", "1")
				expect(GryMod.Minimap.Settings.AutoState.current).to.equal(4)
				expect(GryMod.Minimap.Settings.AutoState.previous).to.beNil()
				expect(GryMod.Minimap.Settings.Definition()).to.equal(4)
				expect(GryMod.Minimap.Settings.PreviousDefinition()).to.beNil()
			end
		},
		{
			name = "a hot reload of the file keeps the automatic level the radar calculated (the state is not reset by include)",
			func = function()
				local S = GryMod.Minimap.Settings

				S.AutoState.current, S.AutoState.previous = 32, 8
				include(SETTINGS_FILE)
				expect(GryMod.Minimap.Settings.AutoState.current).to.equal(32)
				expect(GryMod.Minimap.Settings.AutoState.previous).to.equal(8)
			end
		},
		{
			name = "Definition with the automatic on is the level the radar gave (SetAutoDefinition), whatever the slider holds; with it off it is the slider again, the level is kept",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition_auto", "1")
				set("gry_minimap_definition", "7")
				S.AutoState.current, S.AutoState.previous = 4, nil
				expect(S.Definition()).to.equal(4)
				expect(S.SetAutoDefinition(32)).to.equal(true)
				expect(S.Definition()).to.equal(32)
				set("gry_minimap_definition_auto", "0")
				expect(S.Definition()).to.equal(7)
				set("gry_minimap_definition_auto", "1")
				expect(S.Definition()).to.equal(32)
			end
		},
		{
			name = "SetAutoDefinition takes only a whole number of the pyramid (2, 4, 8, 16, 32, 64); anything else is ignored and answers false",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition_auto", "1")

				for _, level in ipairs({2, 4, 8, 16, 32, 64}) do
					expect(S.SetAutoDefinition(level)).to.equal(true)
					expect(S.Definition()).to.equal(level)
				end

				S.SetAutoDefinition(16)

				for _, bad in ipairs({3, 0, 1, -4, 128, 8.5, 15.99999, "8", true, {}, 0 / 0, math.huge, -math.huge}) do
					expect(S.SetAutoDefinition(bad)).to.equal(false)
					expect(S.Definition()).to.equal(16)
				end

				expect(S.SetAutoDefinition(nil)).to.equal(false)
				expect(S.Definition()).to.equal(16)
			end
		},
		{
			name = "PreviousDefinition: the one level before the current one, only when the level changed (the same level again keeps it), nil while the automatic is off",
			func = function()
				local S = GryMod.Minimap.Settings

				set("gry_minimap_definition_auto", "1")
				S.AutoState.current, S.AutoState.previous = 4, nil
				expect(S.PreviousDefinition()).to.beNil()
				S.SetAutoDefinition(4)
				expect(S.PreviousDefinition()).to.beNil()
				S.SetAutoDefinition(32)
				expect(S.PreviousDefinition()).to.equal(4)
				-- the same level asked again does not turn the previous one into the current one
				S.SetAutoDefinition(32)
				expect(S.PreviousDefinition()).to.equal(4)
				-- an invalid level changes nothing
				S.SetAutoDefinition(5)
				expect(S.PreviousDefinition()).to.equal(4)
				-- only one level is remembered
				S.SetAutoDefinition(8)
				expect(S.PreviousDefinition()).to.equal(32)
				set("gry_minimap_definition_auto", "0")
				expect(S.PreviousDefinition()).to.beNil()
				set("gry_minimap_definition_auto", "1")
				expect(S.PreviousDefinition()).to.equal(32)
			end
		},
		{
			name = "AUTO_LEVELS is the pyramid: 2, 4, 8, 16, 32, 64",
			func = function()
				local levels = GryMod.Minimap.Settings.AUTO_LEVELS

				expect(type(levels)).to.equal("table")
				expect(#levels).to.equal(6)

				for i, level in ipairs({2, 4, 8, 16, 32, 64}) do
					expect(levels[i]).to.equal(level)
				end
			end
		},
		{
			-- the smallest level L with L >= 0.7 * density (the texture is stretched at most 1/0.7 = 1.43 times); the numbers are worked out by hand
			name = "AutoDefinitionFor with no previous level: the smallest level of at least 0.7 times the density (50 gives 64, 45 gives 32, 46 gives 64, 6.6 gives 8, 2.8 gives 2, 2.9 gives 4)",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				-- 0.7 * 50 = 35 > 32
				expect(F(50, nil)).to.equal(64)
				-- 0.7 * 45 = 31.5 <= 32; 0.7 * 46 = 32.2 > 32
				expect(F(45, nil)).to.equal(32)
				expect(F(46, nil)).to.equal(64)
				-- 0.7 * 40 = 28, 0.7 * 22.8 = 15.96, 0.7 * 23 = 16.1
				expect(F(40, nil)).to.equal(32)
				expect(F(22.8, nil)).to.equal(16)
				expect(F(23, nil)).to.equal(32)
				-- 0.7 * 14.7 = 10.29
				expect(F(14.7, nil)).to.equal(16)
				-- 0.7 * 6.6 = 4.62, 0.7 * 11 = 7.7, 0.7 * 11.5 = 8.05
				expect(F(6.6, nil)).to.equal(8)
				expect(F(11, nil)).to.equal(8)
				expect(F(11.5, nil)).to.equal(16)
				-- 0.7 * 3.3 = 2.31, 0.7 * 5.7 = 3.99, 0.7 * 5.8 = 4.06
				expect(F(3.3, nil)).to.equal(4)
				expect(F(5.7, nil)).to.equal(4)
				expect(F(5.8, nil)).to.equal(8)
				-- 0.7 * 2.8 = 1.96, 0.7 * 2.9 = 2.03
				expect(F(2.8, nil)).to.equal(2)
				expect(F(2.9, nil)).to.equal(4)
			end
		},
		{
			name = "AutoDefinitionFor is bounded: a density under 1 gives 2, one of 100, 1000 or 1e9 gives 64, never another number than a level",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				expect(F(0.001, nil)).to.equal(2)
				expect(F(1, nil)).to.equal(2)
				expect(F(100, nil)).to.equal(64)
				expect(F(1000, nil)).to.equal(64)
				expect(F(1e9, nil)).to.equal(64)
				expect(F(math.huge, nil)).to.equal(64)

				-- the same from a previous level at the ends
				expect(F(1000, 64)).to.equal(64)
				expect(F(0.001, 2)).to.equal(2)
			end
		},
		{
			name = "AutoDefinitionFor with a density that is no usable number (0, negative, nan, text, nil) keeps the previous level, else 4 (the level the radar starts with)",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				for _, bad in ipairs({0, -5, 0 / 0, "12", true}) do
					expect(F(bad, 16)).to.equal(16)
					expect(F(bad, nil)).to.equal(4)
				end

				expect(F(nil, 8)).to.equal(8)
				expect(F(nil, nil)).to.equal(4)
			end
		},
		{
			-- the level changes only when the density leaves 0.6 to 1.6 times the level in use
			name = "AutoDefinitionFor keeps the previous level while the density stays within 0.6 to 1.6 times it, and changes by the rule outside",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				-- level 16: the band is 9.6 to 25.6
				expect(F(9.7, 16)).to.equal(16)
				expect(F(16, 16)).to.equal(16)
				expect(F(25.5, 16)).to.equal(16)
				-- under it: 0.7 * 9.5 = 6.65 gives 8
				expect(F(9.5, 16)).to.equal(8)
				-- over it: 0.7 * 25.7 = 17.99 gives 32
				expect(F(25.7, 16)).to.equal(32)
				-- a jump of several levels at once: from 4 to a density of 50 gives 64 (the rule), from 64 to a density of 2.5 gives 2
				expect(F(50, 4)).to.equal(64)
				expect(F(2.5, 64)).to.equal(2)
				-- 40 is over the band of level 16 (25.6 is its top): the rule gives 32; 14 is inside it
				expect(F(40, 16)).to.equal(32)
				expect(F(14, 16)).to.equal(16)
				-- a previous value that is not a level of the pyramid is no previous level
				for _, notALevel in ipairs({3, 0, -1, 17, "16", true, 0 / 0}) do
					expect(F(14, notALevel)).to.equal(16)
					expect(F(50, notALevel)).to.equal(64)
				end
			end
		},
		{
			name = "AutoDefinitionFor: the level it gives is stable (asked again with the same density it keeps it) and the density it came from is inside the band of its level",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				for i = 1, 1200 do
					local density = i / 10
					local level = F(density, nil)

					expect(F(density, level)).to.equal(level)

					-- the stretch of the texture is at most 1/0.7 unless the top level is already in use
					if level < 64 then
						expect(level >= 0.7 * density).to.beTrue()
					end

					if level > 2 then
						expect(level / 2 < 0.7 * density).to.beTrue()
					end
				end
			end
		},
		{
			name = "AutoDefinitionFor: a density going back and forth across the edge of a band changes the level at most once (no change at every step of a dragged slider)",
			func = function()
				local F = GryMod.Minimap.Settings.AutoDefinitionFor

				-- the edges of the band of level 8 are 4.8 and 12.8; alternate just inside and just outside each of them
				for _, around in ipairs({{12.7, 12.9}, {4.9, 4.7}}) do
					local level, changes = 8, 0

					for i = 1, 40 do
						local density = around[(i % 2) + 1]
						local nextLevel = F(density, level)

						if nextLevel ~= level then
							changes = changes + 1
						end

						level = nextLevel
					end

					expect(changes <= 1).to.beTrue()
				end

				-- the radar range dragged from 100 m to 5 m and back, one metre at a time, from the level the rule gives at 100 m (density 2.5 at 100 m on a 3840 pixel wide screen, 43 / range * 5.8)
				local level, changes = F(43 / 100 * 5.8, nil), 0

				for pass = 1, 2 do
					for step = 0, 95 do
						local metres = pass == 1 and (100 - step) or (5 + step)
						local nextLevel = F(43 / metres * 5.8, level)

						if nextLevel ~= level then
							changes = changes + 1
						end

						level = nextLevel
					end
				end

				-- 2 to 64 and back: five steps up and five down at most (the band is wider than the step between two levels, so no level is lost or repeated)
				expect(changes <= 10).to.beTrue()
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
					expect(S.Definition() >= 1 and S.Definition() <= 64).to.beTrue()
					expect(S.DefinitionAuto() ~= nil).to.beTrue()
					expect(S.ParseDefinitionAuto(text) ~= nil).to.beTrue()
					expect(S.BudgetMs() >= 1 and S.BudgetMs() <= 30).to.beTrue()

					expect(S.ParseSwitch(text) ~= nil).to.beTrue()
					expect(S.ParseDefinition(text) >= 1 and S.ParseDefinition(text) <= 64).to.beTrue()
					expect(S.ParseBudgetMs(text) >= 1 and S.ParseBudgetMs(text) <= 30).to.beTrue()
					expect(S.ParseTileRes(text) >= 512 and S.ParseTileRes(text) <= 2048).to.beTrue()
				end
			end
		},
		{
			-- the discovery mode of the map is optional (every feature has its switch): archived, 0 by default (no veil while the map is discovered), 1 gives back the old behaviour.
			-- breaks if: the convar is missing, not archived, or its default is 1
			name = "gry_minimap_veil_discovery: an archived convar, 0 by default (no noise veil while the map is discovered); VeilInDiscovery follows it",
			func = function(state)
				local S = GryMod.Minimap.Settings
				local c = convar("gry_minimap_veil_discovery")

				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("0")
				expect(isfunction(S.VeilInDiscovery)).to.beTrue()

				-- created saved (the engine's flag is not readable from Lua for these convars): the file is run again with the convar hidden, and what it asks for is read
				local created
				state.realGetConVar, state.realCreate = GetConVar, CreateClientConVar

				GetConVar = function(name)
					if name == "gry_minimap_veil_discovery" then
						return nil
					end

					return state.realGetConVar(name)
				end

				CreateClientConVar = function(name, default, shouldsave, userinfo, help, min, max)
					if name == "gry_minimap_veil_discovery" then
						created = {default = default, save = shouldsave, userinfo = userinfo, help = help, min = min, max = max}
					end

					return state.realCreate(name, default, shouldsave, userinfo, help, min, max)
				end

				include(SETTINGS_FILE)

				expect(created ~= nil).to.beTrue()
				expect(created.default).to.equal("0")
				expect(created.save).to.equal(true)
				expect(created.userinfo).to.equal(false)
				expect(created.min).to.equal(0)
				expect(created.max).to.equal(1)
				expect(isstring(created.help) and #created.help > 10).to.beTrue()
				S = GryMod.Minimap.Settings

				local before = c:GetString()
				local ok, err = pcall(function()
					c:SetString("0")
					expect(S.VeilInDiscovery()).to.equal(false)
					c:SetString("1")
					expect(S.VeilInDiscovery()).to.equal(true)
				end)

				c:SetString(before)
				if not ok then error(err, 0) end
			end
		},
		{
			-- a text that is no number is the default (no veil): the pure rule the accessor is made of
			name = "ParseVeilDiscovery: 0 and 0.4 are false, 1, 2, -1 are true, a text that is no number is the default (false)",
			func = function()
				local P = GryMod.Minimap.Settings.ParseVeilDiscovery

				expect(isfunction(P)).to.beTrue()
				expect(P("0")).to.equal(false)
				expect(P("0.4")).to.equal(false)
				expect(P("1")).to.equal(true)
				expect(P("2")).to.equal(true)
				expect(P("-1")).to.equal(true)

				for _, text in ipairs({"", "banana", "nan"}) do
					expect(P(text)).to.equal(false)
				end
			end
		}
	}
}
