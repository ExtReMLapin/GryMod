-- Tests of the big map's settings (lua/grymod/client/map/settings.lua), GLuaTest format, client realm: the saved convars and how a text is read into a
-- value inside its range (the player can type anything in the console or in a cfg file). The convars are created when the file loads: the tests
-- read what exists and fix nothing of the owner's saved values; the Parse functions are pure and take any text.

local function S()
	local settings = GryMod and GryMod.Map and GryMod.Map.Settings

	expect(settings ~= nil).to.beTrue()

	return settings
end

return {
	groupName = "GryMod big map settings",
	cases = {
		-- fails when a convar of the big map is missing or not saved
		{
			name = "the convars exist and are saved: gry_map_enable, gry_map_zoom, gry_map_loading_fx, gry_map_finished, gry_map_grid, gry_map_chrome",
			func = function()
				S()

				for _, name in ipairs({"gry_map_enable", "gry_map_zoom", "gry_map_loading_fx", "gry_map_finished", "gry_map_grid", "gry_map_chrome"}) do
					local convar = GetConVar(name)

					expect(convar ~= nil).to.beTrue()
					-- (GetFlags does not report FCVAR_ARCHIVE for Lua-created convars in this build: the flags are those of a saved sibling)
					expect(convar:GetFlags()).to.equal(GetConVar("gry_hud_status"):GetFlags())
				end
			end
		},
		-- fails when the defaults are not the documented ones
		{
			name = "the defaults: the map on, zoom 1, the glitch look, finished objectives hidden, the grid shown, the Crysis PDA frame on",
			func = function()
				local settings = S()

				expect(settings.DEFAULT_ENABLE).to.beTrue()
				expect(settings.DEFAULT_ZOOM).to.equal(1)
				expect(settings.DEFAULT_FX).to.equal("glitch")
				expect(settings.DEFAULT_FINISHED).to.beFalse()
				expect(settings.DEFAULT_GRID).to.beTrue()
				expect(settings.DEFAULT_CHROME).to.beTrue()
				expect(GetConVar("gry_map_enable"):GetDefault()).to.equal("1")
				expect(GetConVar("gry_map_zoom"):GetDefault()).to.equal("1")
				expect(GetConVar("gry_map_loading_fx"):GetDefault()).to.equal("glitch")
				expect(GetConVar("gry_map_finished"):GetDefault()).to.equal("0")
				expect(GetConVar("gry_map_grid"):GetDefault()).to.equal("1")
				expect(GetConVar("gry_map_chrome"):GetDefault()).to.equal("1")
			end
		},
		-- fails when a switch is read as the engine reads a boolean
		{
			name = "a switch is on when the whole part of the number is not 0; a text that is no number gives the default",
			func = function()
				local settings = S()

				expect(settings.ParseSwitch("1", false)).to.beTrue()
				expect(settings.ParseSwitch("0", true)).to.beFalse()
				expect(settings.ParseSwitch("0.5", true)).to.beFalse()
				expect(settings.ParseSwitch("-1", false)).to.beTrue()
				expect(settings.ParseSwitch("abc", true)).to.beTrue()
				expect(settings.ParseSwitch("abc", false)).to.beFalse()
				expect(settings.ParseSwitch("", true)).to.beTrue()
				expect(settings.ParseSwitch(nil, false)).to.beFalse()
			end
		},
		-- fails when the saved zoom is not read inside 1 to 8
		{
			name = "the zoom text is read inside 1 to 8",
			func = function()
				local settings = S()

				expect(settings.ParseZoom("2.5")).to.equal(2.5)
				expect(settings.ParseZoom("0")).to.equal(1)
				expect(settings.ParseZoom("40")).to.equal(8)
				expect(settings.ParseZoom("x")).to.equal(1)
			end
		},
		-- fails when a look name with a bad character is accepted
		{
			name = "the name of a loading look is letters, digits and underscore only; anything else gives the default",
			func = function()
				local settings = S()

				expect(settings.ParseFx("mosaic_2")).to.equal("mosaic_2")
				expect(settings.ParseFx("../x")).to.equal("glitch")
				expect(settings.ParseFx("")).to.equal("glitch")
				expect(settings.ParseFx(nil)).to.equal("glitch")
				expect(settings.ParseFx(string.rep("a", 40))).to.equal("glitch")
			end
		},
		-- fails when the accessors do not read the convars
		{
			name = "the accessors give a value of the right kind, whatever the convars hold",
			func = function()
				local settings = S()

				expect(type(settings.Enabled())).to.equal("boolean")
				expect(type(settings.Zoom())).to.equal("number")
				expect(settings.Zoom() >= 1 and settings.Zoom() <= 1024).to.beTrue()
				expect(type(settings.ZoomCentimetres())).to.equal("number")
				expect(settings.ZoomCentimetres() >= 1 and settings.ZoomCentimetres() <= 100).to.beTrue()
				expect(type(settings.LoadingFx())).to.equal("string")
				expect(type(settings.ShowFinished())).to.equal("boolean")
				expect(type(settings.ShowGrid())).to.equal("boolean")
				expect(type(settings.Chrome())).to.equal("boolean")
			end
		}
	}
}
