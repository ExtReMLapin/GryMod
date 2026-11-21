
-- The colours picked and not written yet: dragging in a mixer moves them at every step, and every write rebuilds the
-- whole interface, so they are written once, 0.2 s after the last step.
local pendingColours = {}

local function writeColours()
	for convarName, text in pairs(pendingColours) do
		RunConsoleCommand(convarName, text)
	end

	if next(pendingColours) then
		RunConsoleCommand("gry_hud_theme", "custom")
	end

	pendingColours = {}
end

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
			pendingColours[convarName] = text
			timer.Create("GryHUDColourApply", 0.2, 1, writeColours)
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

	-- what was added to the binoculars (the zoom key), each on its own: the screen itself is the "Binoculars" element above
	Panel:Help("Binoculars (hold the zoom key)")
	Panel:CheckBox("Binoculars sounds: opening, closing, ambience loop, target locked", "gry_binoculars_sounds")
	Panel:CheckBox("Original aim rules: 4 rays, 300 m, the distance to the entity aimed at", "gry_binoculars_aim")
	Panel:CheckBox("Horizon ladder that follows where you look", "gry_binoculars_horizon")
	Panel:CheckBox("Dark vignette fading out as the binoculars close (off: it goes at once)", "gry_binoculars_vignette")
	Panel:CheckBox("Tag an NPC aimed at for half a second (the radar shows it)", "gry_binoculars_tag")

	Panel:CheckBox("Screen effects: heavy armor hit flash and shake, red tint and blur at low health, colour tint of a suit mode change", "gry_screenfx")
	Panel:NumSlider("Crosshair style (1 to 13)", "gry_hud_crosshair_style", 1, 13, 0)
	Panel:Button("Switch every element back on", "gry_hud_reset")

	-- server setting (the host or an admin): EMP, electric hits and heavy impacts put the suit down for a few seconds
	Panel:CheckBox("Suit malfunctions: EMP and electric hits (server)", "gry_malfunction")
	-- client setting: the HUD also goes down (Lost, then Reboot) while the energy bar is empty, GryMod's old rule
	Panel:CheckBox("HUD malfunction also when the energy bar is empty (the original: only on an EMP, an electric attack or death)", "gry_malfunction_empty")

	-- server setting: the grenade warning only for a projectile that is active (an armed grenade, a mine in the air...)
	Panel:CheckBox("Grenade warning only for armed grenades, mines in the air... (server; off: also the ones lying around)", "gry_grenade_armed_only")

	-- the pictures of the interface take about a second each to load: ahead of time, or at the first use (a freeze)
	Panel:Help("Preloading of the interface (only the elements above that are on)")
	Panel:AddControl("ComboBox", {
		Label = "Preload",
		MenuButton = 0,
		Options = {
			["At the loading screen (longer loading, no freeze later)"] = {gry_hud_prewarm = "1"},
			["Spread over the first seconds of play (short freezes)"] = {gry_hud_prewarm = "2"},
			["Never (each part freezes the game the first time it is used)"] = {gry_hud_prewarm = "0"}
		}
	})
end

-- Every control is bound to its convar: the settings are saved, and opening the panel never changes them.
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	Panel:CheckBox("Draw the HUD (health, energy, ammo, radar)", "gry_hud")
	Panel:CheckBox("Suit sounds", "gry_sounds")
	-- the original game's levels plus this gain (0 dB: as quiet as in the game, +12 dB: the loud ones at full volume)
	Panel:NumSlider("Interface and suit sound level (dB)", "gry_sound_volume", -20, 12, 0)
	Panel:CheckBox("Repair sound when the health comes back", "gry_sound_regen")
	Panel:CheckBox("Underwater sounds: dive in and out, breathing, gasps, ambience", "gry_underwater_fx")
	Panel:CheckBox("Drowning: 60 s of breath, then the suit energy, then health (server; off: the engine's drowning)", "gry_drown_rules")
	Panel:CheckBox("Energy bar moves at every frame (predicted between the server's updates)", "gry_hud_energy_smooth")
	Panel:CheckBox("Send the suit energy at every tick (server; off: the slower networked value)", "gry_energy_net")
	-- the rules of the suit (server setting, for the host or an admin): the original game's numbers, or GryMod's earlier ones
	Panel:AddControl("ComboBox", {
		Label = "Suit rules (server)",
		MenuButton = 0,
		Options = {
			["Crysis (the original game's numbers)"] = {gry_mechanics = "crysis"},
			["Classic GryMod"] = {gry_mechanics = "classic"}
		}
	})
	Panel:CheckBox("Camouflage: striders, hunters and manhacks forget you (server)", "gry_cloak_ai")
	Panel:CheckBox("Camouflage: bend the picture behind the player and fade in and out (off: the old material)", "gry_cloak_fx")

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
