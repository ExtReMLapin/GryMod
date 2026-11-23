-- Tests of the HUD settings (GryMod.HUDOptions): one saved switch per element of the interface, GLuaTest format,
-- client realm. The original game has no such switches (its menu only has the colour sets and the crosshair
-- style, see research-ui2/options.md), so these are GryMod's own and every element can be turned off.

local NAMES = {"status", "radar", "radarunits", "radarhex", "crosshair", "damage", "hit", "grenade", "binoculars", "quickmenu", "boot", "damagefx", "overheat"}

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
			-- breaks if: an element has no check box in either menu, the two radar elements stay in the Config menu, or the radar menu does not have them
			name = "every HUD element has a check box in the Config menu or in the Radar and map menu: the three radar ones (radar, radarunits, radarhex) only in the radar menu, all the others only in Config",
			func = function(state)
				local function convarsOf(build)
					local found = {}
					local panel = vgui.Create("ControlPanel")
					local ok, err = pcall(function()
						build(panel)

						local function walk(p)
							for _, child in ipairs(p:GetChildren()) do
								if child.ClassName == "DCheckBoxLabel" and child.Button and child.Button:GetTable().m_strConVar then
									found[child.Button:GetTable().m_strConVar] = true
								end

								walk(child)
							end
						end

						walk(panel)
					end)

					panel:Remove()

					if not ok then error(err, 0) end

					return found
				end

				local config = convarsOf(GryMod.GryOptionschute)
				local radar = convarsOf(GryMod.RadarOptionsPanel)

				for _, option in ipairs(GryMod.HUDOptions.List) do
					local convar = "gry_hud_" .. option.name

					if option.name == "radar" or option.name == "radarunits" or option.name == "radarhex" then
						expect(radar[convar]).to.beTrue()
						expect(config[convar]).to.beNil()
					else
						expect(config[convar]).to.beTrue()
						expect(radar[convar]).to.beNil()
					end
				end
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

				-- the radar's hexagon is a second movie drawn with the radar (counted apart below)
				GetConVar("gry_hud_radarhex"):SetString("0")
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
				-- the hexagon on: the radar draws its icon too (one more); with the radar off the icon goes with it
				GetConVar("gry_hud_radar"):SetString("1")
				GetConVar("gry_hud_radarhex"):SetString("1")
				local withHexagon = count()
				GetConVar("gry_hud_radar"):SetString("0")
				local hexagonOnly = count()
				Flash.Draw = real
				GryMod.FlashHUD.Reset()

				expect(both).to.equal(2)
				expect(radarOnly).to.equal(1)
				expect(statusOnly).to.equal(1)
				expect(none).to.equal(0)
				expect(withHexagon).to.equal(2)
				expect(hexagonOnly).to.equal(0)
			end
		},
		{
			name = "the options panel starts with a Keys section: its title, then the quick menu key picker, the zoom key picker with the behaviour selector and the threshold slider right under it, then the other zoom boxes, all before any other setting",
			func = function(state)
				local realRun = RunConsoleCommand
				local panel
				local order = {}

				local ok, err = pcall(function()
					RunConsoleCommand = function() end
					panel = vgui.Create("ControlPanel")
					GryMod.GryOptionschute(panel)

					-- every control in the order it was made (a label by its text, a picker as "binder", a box by its setting)
					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DBinder" then
								order[#order + 1] = "binder"
							elseif child.ClassName == "ControlPanel" and child.Header then
								-- a folding category (cl_options.lua): its title is its header
								order[#order + 1] = "label:" .. child.Header:GetText()
							elseif child.ClassName == "DCheckBoxLabel" and child.Button then
								order[#order + 1] = "box:" .. tostring(child.Button.m_strConVar)
							elseif child.ClassName == "DLabel" and child.GetText and #child:GetText() > 0 and child:GetParent() ~= nil and child:GetParent().ClassName ~= "DCheckBoxLabel" then
								order[#order + 1] = "label:" .. child:GetText()
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				RunConsoleCommand = realRun

				if IsValid(panel) then
					panel:Remove()
				end

				if not ok then
					error(err, 0)
				end

				local function find(pattern, from)
					for i = from or 1, #order do
						if string.find(order[i], pattern, 1, true) then
							return i
						end
					end
				end

				local keys = find("label:Keys")
				expect(keys).toNot.beNil()
				local firstBinder = find("binder")
				local secondBinder = find("binder", firstBinder + 1)
				expect(firstBinder).toNot.beNil()
				expect(secondBinder).toNot.beNil()
				expect(find("binder", secondBinder + 1)).to.beNil() -- the two keys of the mod, nothing else asks for one
				expect(keys < firstBinder).to.beTrue()

				-- the line under the zoom key picker (the default key, or a warning), then the zoom key behaviour (its label, then the threshold
				-- slider's label: the selector itself has none), the own zoom box is in the section too
				expect(string.find(order[secondBinder + 1], "label:", 1, true)).to.equal(1)
				expect(string.find(order[secondBinder + 2], "label:Zoom key behaviour", 1, true)).toNot.beNil()
				expect(string.find(order[secondBinder + 3], "label:Short press", 1, true)).toNot.beNil()
				local own = find("box:gry_zoom_own")
				expect(own).toNot.beNil()
				expect(own > secondBinder).to.beTrue()

				-- the section comes first: no other setting before the last of its controls
				local lastOfSection = math.max(own, secondBinder + 3)
				local other = find("box:gry_hud")
				expect(other).toNot.beNil()
				expect(other > lastOfSection).to.beTrue()

				for _, convar in ipairs({"gry_sounds", "gry_cloak_fx", "gry_binoculars_sounds", "gry_screenfx"}) do
					local at = find("box:" .. convar)
					expect(at).toNot.beNil()
					expect(at > lastOfSection).to.beTrue()
				end

				-- and the keys are not asked for a second time further down
				local count = 0
				for _, entry in ipairs(order) do
					if entry == "box:gry_zoom_own" then
						count = count + 1
					end
				end
				expect(count).to.equal(1)
			end
		}
	}
}
