
-- Every control is bound to its convar: the settings are saved, and opening the panel never changes them.
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	Panel:CheckBox("Draw the HUD (health, energy, ammo, radar)", "gry_hud")
	Panel:AddControl("ComboBox", {
		Label = "HUD style",
		MenuButton = 0,
		Options = {
			["Classic"] = {gry_hud_style = "classic"},
			["Crysis (original Scaleform movie)"] = {gry_hud_style = "crysis"}
		}
	})
	Panel:CheckBox("Suit sounds", "gry_sounds")
	Panel:AddControl("ComboBox", {
		Label = "Crysis HUD colours",
		MenuButton = 0,
		Options = {
			["Blue"] = {gry_hud_theme = "blue"},
			["Crysis default (green)"] = {gry_hud_theme = "default"},
			["White"] = {gry_hud_theme = "white"},
			["Orange"] = {gry_hud_theme = "orange"}
		}
	})
	Panel:NumSlider("Mirror Distance", "gry_xadd", -5000, 5000, 0)
	Panel:NumSlider("X Position", "gry_xdist", -5000, 5000, 0)

	Panel:Button("[ADMIN] Toggle Health Regen", "gry_Health")
	Panel:Button("[ADMIN] Toggle Infinite Armor", "gry_Armor")
end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)
