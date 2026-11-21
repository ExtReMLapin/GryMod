-- Tests of the HUD settings (GryMod.HUDOptions): one saved switch per element of the interface, GLuaTest format,
-- client realm. The original game has no such switches (its menu only has the colour sets and the crosshair
-- style, see research-ui2/options.md), so these are GryMod's own and every element can be turned off.

local NAMES = {"status", "radar", "crosshair", "damage", "hit", "grenade", "binoculars", "quickmenu", "boot", "damagefx"}

local saved = {}

return {
	groupName = "GryMod HUD options",
	beforeAll = function(state)
		for _, name in ipairs(NAMES) do
			local convar = GetConVar("gry_hud_" .. name)
			saved[name] = convar and convar:GetString()
		end
	end,
	afterAll = function(state)
		for name, value in pairs(saved) do
			GetConVar("gry_hud_" .. name):SetString(value)
		end
	end,
	cases = {
		{
			name = "every element has its own switch, on by default",
			func = function(state)
				for _, name in ipairs(NAMES) do
					local convar = GetConVar("gry_hud_" .. name)
					expect(convar ~= nil).to.beTrue()
					expect(convar:GetDefault()).to.equal("1")
					expect(GryMod.HUDOptions.Find(name)).to.exist()
				end
			end
		},
		{
			name = "Enabled follows the switch, and an unknown element counts as on",
			func = function(state)
				local O = GryMod.HUDOptions
				GetConVar("gry_hud_radar"):SetString("0")
				expect(O.Enabled("radar")).to.beFalse()
				GetConVar("gry_hud_radar"):SetString("1")
				expect(O.Enabled("radar")).to.beTrue()
				expect(O.Enabled("something else")).to.beTrue()
			end
		},
		{
			name = "the list gives each element a name and a label for the menu, in the order of the menu",
			func = function(state)
				local list = GryMod.HUDOptions.List

				for i, name in ipairs(NAMES) do
					expect(list[i].name).to.equal(name)
					expect(isstring(list[i].label) and #list[i].label > 0).to.beTrue()
				end
			end
		},
		{
			name = "Reset puts every switch back on",
			func = function(state)
				for _, name in ipairs(NAMES) do
					GetConVar("gry_hud_" .. name):SetString("0")
				end

				GryMod.HUDOptions.Reset()

				for _, name in ipairs(NAMES) do
					expect(GetConVar("gry_hud_" .. name):GetBool()).to.beTrue()
				end
			end
		},
		{
			name = "the grenade warning, the binoculars and the quick menu each follow their own switch",
			func = function(state)
				local hud = GetConVar("gry_hud"):GetString()
				GetConVar("gry_hud"):SetString("1")

				for name, module in pairs({grenade = GryMod.FlashGrenade, binoculars = GryMod.FlashBinoculars, quickmenu = GryMod.FlashMenu}) do
					GetConVar("gry_hud_" .. name):SetString("1")
					expect(module.Enabled()).to.beTrue()
					GetConVar("gry_hud_" .. name):SetString("0")
					expect(module.Enabled()).to.beFalse()
					GetConVar("gry_hud_" .. name):SetString("1")
				end

				GetConVar("gry_hud"):SetString(hud)
			end
		},
		{
			name = "the options panel has a check box and a colour mixer for each setting, and opening it writes nothing",
			func = function(state)
				local writes = {}
				local realRun = RunConsoleCommand
				RunConsoleCommand = function(name, value)
					writes[#writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
				end

				local ok, err = pcall(function()
					local panel = vgui.Create("ControlPanel")
					GryMod.GryOptionschute(panel)

					local boxes, mixers = 0, 0
					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" then boxes = boxes + 1 end
							if child.ClassName == "DColorMixer" then mixers = mixers + 1 end
							walk(child)
						end
					end

					walk(panel)
					panel:Remove()
					expect(boxes >= #GryMod.HUDOptions.List).to.beTrue()
					expect(mixers).to.equal(3)
				end)

				RunConsoleCommand = realRun
				expect(ok).to.beTrue()
				expect(#writes).to.equal(0)
				expect(concommand.GetTable().gry_hud_reset ~= nil).to.beTrue()
			end
		},
		{
			name = "dragging in a colour mixer writes the colour once, after a short pause, not at every step",
			func = function(state)
				local writes = {}
				local realRun = RunConsoleCommand
				RunConsoleCommand = function(name, value)
					writes[#writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
				end

				local panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(panel)
				local mixer

				local function walk(p)
					for _, child in ipairs(p:GetChildren()) do
						if not mixer and child.ClassName == "DColorMixer" then mixer = child end
						walk(child)
					end
				end

				walk(panel)
				mixer:ValueChanged(Color(11, 22, 33))
				mixer:ValueChanged(Color(12, 23, 34))
				local immediate = #writes
				local pending = timer.Exists("GryHUDColourApply")
				panel:Remove()
				RunConsoleCommand = realRun
				timer.Remove("GryHUDColourApply")
				expect(immediate).to.equal(0)
				expect(pending).to.beTrue()
			end
		},
		{
			name = "the status panel and the radar panel are each drawn or not by their own switch",
			func = function(state)
				local Flash = GryMod.Flash
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local real, drawn = Flash.Draw, 0
				Flash.Draw = function() drawn = drawn + 1 end

				local function count()
					GryMod.FlashHUD.Reset()
					drawn = 0
					GryMod.FlashHUD.Paint()

					return drawn
				end

				GetConVar("gry_hud_status"):SetString("1")
				GetConVar("gry_hud_radar"):SetString("1")
				local both = count()
				GetConVar("gry_hud_status"):SetString("0")
				local radarOnly = count()
				GetConVar("gry_hud_status"):SetString("1")
				GetConVar("gry_hud_radar"):SetString("0")
				local statusOnly = count()
				GetConVar("gry_hud_status"):SetString("0")
				local none = count()
				Flash.Draw = real
				GryMod.FlashHUD.Reset()

				expect(both).to.equal(2)
				expect(radarOnly).to.equal(1)
				expect(statusOnly).to.equal(1)
				expect(none).to.equal(0)
			end
		}
	}
}
