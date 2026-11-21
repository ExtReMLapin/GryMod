
-- One colour of the custom HUD theme: a mixer that writes "r g b" in its setting, and puts the HUD on the custom
-- theme when the player picks a colour. Opening the panel writes nothing.
local function addColourMixer(Panel, label, convarName)
	Panel:Help(label)

	local mixer = vgui.Create("DColorMixer")
	mixer:SetPalette(false)
	mixer:SetAlphaBar(false)
	mixer:SetWangs(true)
	mixer:SetTall(110)

	local current = GryMod.FlashHUD.ParseColour(GetConVar(convarName):GetString()) or {255, 255, 255}
	mixer:SetColor(Color(current[1], current[2], current[3]))

	local ready = true
	mixer.ValueChanged = function(_, color)
		if not ready then
			return
		end

		local text = color.r .. " " .. color.g .. " " .. color.b

		if GetConVar(convarName):GetString() ~= text then
			RunConsoleCommand(convarName, text)
			RunConsoleCommand("gry_hud_theme", "custom")
		end
	end

	Panel:AddItem(mixer)
end

-- The HUD settings: the colours (the four sets of the original game, or your own), and one switch for each
-- element of the interface.
function GryMod.GryHUDOptions(Panel)
	Panel:Help("HUD colours")
	Panel:AddControl("ComboBox", {
		Label = "Colour set",
		MenuButton = 0,
		Options = {
			["Ice blue"] = {gry_hud_theme = "blue"},
			["Military green (Crysis default)"] = {gry_hud_theme = "default"},
			["Amber"] = {gry_hud_theme = "orange"},
			["White"] = {gry_hud_theme = "white"},
			["Custom (the three colours below)"] = {gry_hud_theme = "custom"}
		}
	})
	addColourMixer(Panel, "Custom colour of the outlines and icons", "gry_hud_color_line")
	addColourMixer(Panel, "Custom colour of the active indicators", "gry_hud_color_over")
	addColourMixer(Panel, "Custom colour of the digits and letters", "gry_hud_color_text")

	Panel:Help("HUD elements")

	for _, option in ipairs(GryMod.HUDOptions.List) do
		Panel:CheckBox(option.label, "gry_hud_" .. option.name)
	end

	Panel:NumSlider("Crosshair style (1 to 13)", "gry_hud_crosshair_style", 1, 13, 0)
	Panel:Button("Switch every element back on", "gry_hud_reset")
end

-- Every control is bound to its convar: the settings are saved, and opening the panel never changes them.
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	Panel:CheckBox("Draw the HUD (health, energy, ammo, radar)", "gry_hud")
	Panel:CheckBox("Suit sounds", "gry_sounds")
	-- the rules of the suit (server setting, for the host or an admin): the original game's numbers, or GryMod's earlier ones
	Panel:AddControl("ComboBox", {
		Label = "Suit rules (server)",
		MenuButton = 0,
		Options = {
			["Crysis (the original game's numbers)"] = {gry_mechanics = "crysis"},
			["Classic GryMod"] = {gry_mechanics = "classic"}
		}
	})

	-- the key of the quick menu (a `bind <key> +crysishud` in the console works too)
	if GryMod.MenuKey then
		Panel:AddControl("Label", {
			Text = "Quick menu key (hold it, point with the mouse, release):"
		})

		local binder = vgui.Create("DBinder")
		binder:SetValue(GetConVar("gry_menu_key"):GetInt())
		binder.OnChange = function(_, code)
			GryMod.MenuKey.SetKey(code)
		end
		Panel:AddItem(binder)
	end

	GryMod.GryHUDOptions(Panel)

	Panel:NumSlider("Mirror Distance", "gry_xadd", -5000, 5000, 0)
	Panel:NumSlider("X Position", "gry_xdist", -5000, 5000, 0)

	Panel:Button("[ADMIN] Toggle Health Regen", "gry_Health")
	Panel:Button("[ADMIN] Toggle Infinite Armor", "gry_Armor")
end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)
