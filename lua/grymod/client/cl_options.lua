
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

-- A category of an options panel: a folding title with the controls of one subject under it (a ControlPanel nested in the menu's one: it has AddControl, which a plain DForm has not). It starts folded unless `open`. Controls are made on the returned form, as on the panel.
function GryMod.OptionsCategory(Panel, title, open)
	local form = vgui.Create("ControlPanel", Panel)

	form:SetLabel(title)
	form:SetExpanded(open == true, true)
	Panel:AddItem(form)

	return form
end

-- A check box with a SHORT label (a panel cuts what does not fit its width) and, under it, the explanation in a small wrapped text.
function GryMod.OptionBox(form, label, convarName, help)
	local box = form:CheckBox(label, convarName)

	if help then
		form:ControlHelp(help)
	end

	return box
end

-- The same for a slider: a short label, the explanation under it.
function GryMod.OptionSlider(form, label, convarName, min, max, decimals, help)
	local slider = form:NumSlider(label, convarName, min, max, decimals)

	if help then
		form:ControlHelp(help)
	end

	return slider
end

-- The HUD elements whose switches are in the Radar and map menu (cl_options_radar.lua), not in the list of this panel.
GryMod.RadarHUDElements = {radar = true, radarunits = true, radarhex = true}

-- The HUD: one switch for each element of the interface, the crosshair, how the pictures are loaded.
local function hudElements(Panel)
	local form = GryMod.OptionsCategory(Panel, "HUD", true)

	GryMod.OptionBox(form, "Draw the HUD", "gry_hud", "Health, energy, ammo, radar.")
	form:Help("HUD elements")

	for _, option in ipairs(GryMod.HUDOptions.List) do
		if not GryMod.RadarHUDElements[option.name] then
			form:CheckBox(option.label, "gry_hud_" .. option.name)
		end
	end

	form:NumSlider("Crosshair style", "gry_hud_crosshair_style", 1, 13, 0)
	GryMod.OptionBox(form, "Weapons choose their crosshair", "gry_hud_crosshair_weapon", "A weapon of an addon can ask for one of the 13 crosshairs. Off: always the style above.")
	-- how the mouse wheel changes the weapon: the setting is written when the player picks a line, never when the panel opens
	form:Help("Weapon selector (the mouse wheel)")

	local selectorBox = vgui.Create("DComboBox")
	selectorBox.GryConVar = "gry_weapon_selector"
	selectorBox:SetSortItems(false)
	selectorBox:AddChoice("The game's own selector (default)", 0)
	selectorBox:AddChoice("Wheel only: a notch changes the weapon", 1)
	selectorBox:AddChoice("Wheel, then click: the list at the bottom right", 2)
	selectorBox:SetValue((selectorBox:GetOptionText(math.Clamp(GetConVar("gry_weapon_selector"):GetInt(), 0, 2) + 1)))
	selectorBox.OnSelect = function(_, _, _, data)
		RunConsoleCommand("gry_weapon_selector", tostring(data))
	end
	form:AddItem(selectorBox)
	form:ControlHelp("Wheel only: a notch of the wheel changes the weapon at once, no click. Wheel, then click: the wheel walks the weapon list of the HUD (turn the list on above) and the left click confirms; the click then never counts as a shot in the camouflage. The weapon keys keep the game's selector.")
	GryMod.OptionBox(form, "Energy bar at every frame", "gry_hud_energy_smooth", "The energy bar is predicted between the server's updates, so that it moves at every frame.")
	GryMod.OptionBox(form, "Use prompt on props", "gry_usehint_props", "PICK UP also shows on the props, ragdolls and physboxes you can lift (you can pick up almost anything). Off: the prompt is only for what really needs the use key.")
	GryMod.OptionBox(form, "Use prompt feedback", "gry_usehint_feedback", "The prompt pulses with a beep when you press the use key on a door, a button or a charger, then dims for a moment.")
	GryMod.OptionSlider(form, "Use prompt delay (s)", "gry_usehint_delay", 0, 1, 2, "The prompt shows after the crosshair stayed this long on the same thing (0.1 s is the original's; 0: at once).")
	GryMod.OptionSlider(form, "Use prompt hold (s)", "gry_usehint_hold", 0, 1, 2, "The prompt stays this long after the crosshair leaves the thing (0.2 s is the original's; 0: it goes at once). Another usable thing replaces it at once.")
	form:Help("Objective markers on the screen")

	local markerBox = vgui.Create("DComboBox")
	markerBox.GryConVar = "gry_objectives_marker_mode"
	markerBox:SetSortItems(false)
	markerBox:AddChoice("Only through the binoculars (the original)", "binoculars")
	markerBox:AddChoice("Always", "always")
	markerBox:SetValue((markerBox:GetOptionText(GetConVar("gry_objectives_marker_mode"):GetString() == "always" and 2 or 1)))
	markerBox.OnSelect = function(_, _, _, data)
		RunConsoleCommand("gry_objectives_marker_mode", tostring(data))
	end
	form:AddItem(markerBox)
	form:ControlHelp("The radar, the minimap and the map show the objectives in both cases.")
	form:Button("Switch every element back on", "gry_hud_reset")

	-- the pictures of the interface take about a second each to load: ahead of time, or at the first use (a freeze)
	form:Help("Preloading of the interface (only the elements above that are on)")
	form:AddControl("ComboBox", {
		Label = "Preload",
		MenuButton = 0,
		Options = {
			["At the loading screen"] = {gry_hud_prewarm = "1"},
			["Over the first seconds of play"] = {gry_hud_prewarm = "2"},
			["Never"] = {gry_hud_prewarm = "0"}
		}
	})
	form:ControlHelp("At the loading screen: a longer loading and no freeze later. Over the first seconds of play: short freezes. Never: each part freezes the game the first time it is used.")
end

-- The colours: the four sets of the original game, or your own.
local function hudColours(Panel)
	local form = GryMod.OptionsCategory(Panel, "HUD colours")

	form:AddControl("ComboBox", {
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
	addColourMixer(form, "Custom colour of the outlines and icons", "gry_hud_color_line")
	addColourMixer(form, "Custom colour of the active indicators", "gry_hud_color_over")
	addColourMixer(form, "Custom colour of the digits and letters", "gry_hud_color_text")
end

-- The quick menu, the suit mode icon and the start-up sequence: how closely they follow the original.
local function hudBehaviour(Panel)
	local form = GryMod.OptionsCategory(Panel, "Quick menu and start-up")

	-- client setting: the HUD also goes down (Lost, then Reboot) while the energy bar is empty, GryMod's old rule
	GryMod.OptionBox(form, "HUD malfunction on empty energy", "gry_malfunction_empty", "The original: the HUD goes down only on an EMP, an electric attack or death.")
	-- client setting: the HUD goes red with its emergency shutdown screen and sound when the player dies, until the respawn
	GryMod.OptionBox(form, "Red HUD and shutdown screen at death", "gry_hud_lost_on_death", "When you die the HUD goes red with the emergency shutdown animation and sound until you respawn (the original). Off: the HUD just disappears.")
	-- client setting: the shutdown screen of the suit going down (and of a death) in the middle of the screen
	GryMod.OptionBox(form, "Shutdown screen in the middle", "gry_hud_lost_centered", "The DANGER SYSTEM OVERRUN panel (suit down, death) is in the middle of the screen. Off: low, where the original's movie puts it.")
	-- client setting: the quick menu icon that was chosen stays lit while the menu fades out
	GryMod.OptionBox(form, "Quick menu: the chosen icon stays lit", "gry_menu_keep_highlight", "While the menu fades out (the original). Off: it goes plain at the release.")
	-- client setting: the quick menu ring keeps its colour from an active mode to an inactive one
	GryMod.OptionBox(form, "Quick menu: the ring stays green", "gry_menu_ring_film", "Going from an active mode to an inactive one (the original). Off: it turns orange.")
	-- client setting: the quick menu greys a mode that a rule of the server refuses, and shows every icon defective while the suit is down
	GryMod.OptionBox(form, "Quick menu: grey out refused modes", "gry_menu_show_refused", "A mode that the server refuses (an add-on's rule, the suit switched off) is greyed; every icon turns red while the suit is down.")
	-- client setting: the quick menu pointer runs the game's rule on a fixed clock and the arrow is eased
	GryMod.OptionBox(form, "Quick menu: a steady arrow", "gry_menu_pointer_film", "The arrow follows the mouse on a fixed clock and does not flutter at a high frame rate. Off: on every frame, as before.")
	-- client setting: the suit mode icon plays its reboot animation when the HUD comes back
	GryMod.OptionBox(form, "Reboot animation of the mode icon", "gry_icon_reboot", "The suit mode icon plays its reboot animation when the HUD comes back after a malfunction (the original).")
	-- client setting: the start-up log and its sounds belong to the start of the level in the original
	GryMod.OptionBox(form, "Start-up log at every spawn", "gry_boot_every_spawn", "Off: the start-up log and sounds play only at the first spawn after the map loads, as in the original.")
end

-- client settings: how far the grenade warning reaches, the old warning for the player's own hand grenade, walls (the original has no range and warns through walls)
local function grenadeWarning(Panel)
	local form = GryMod.OptionsCategory(Panel, "Grenade warning")

	form:NumSlider("Warning range (metres)", "gry_grenade_range", 5, 200, 0)
	GryMod.OptionBox(form, "Also for a grenade you threw", "gry_grenade_own_warn", "Only within 15 m. Off: a grenade you threw never warns; your own missiles never do.")
	GryMod.OptionBox(form, "Only what you can see", "gry_grenade_los", "Off: also through walls, as in the original game.")
	GryMod.OptionBox(form, "Warning stays at the screen edge", "gry_hud_grenade_edge", "A grenade off the screen to the side, above or below keeps its warning at the edge it is on (the original). Off: the warning goes away.")
end

-- The HUD settings: the colours (the four sets of the original game, or your own), one switch for each element of the interface, the quick menu and the
-- grenade warning, in four categories.
function GryMod.GryHUDOptions(Panel)
	hudElements(Panel)
	hudColours(Panel)
	hudBehaviour(Panel)
	grenadeWarning(Panel)

	-- the radar, the compass and the maps have a menu of their own (cl_options_radar.lua)
	Panel:Help("Radar, compass and map options are in the Radar and map menu.")
end

-- What was added to the binoculars, each on its own: the screen itself is the "Binoculars" element of the HUD (the zoom key is in the Keys category).
function GryMod.BinocularsOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Binoculars")

	GryMod.OptionBox(form, "Binoculars sounds", "gry_binoculars_sounds", "Opening, closing, ambience loop, target locked.")
	GryMod.OptionBox(form, "Original aim rules", "gry_binoculars_aim", "4 rays, 300 m, the distance to the entity aimed at.")
	GryMod.OptionBox(form, "Horizon ladder", "gry_binoculars_horizon", "It follows where you look.")
	GryMod.OptionBox(form, "Vignette fades out when closing", "gry_binoculars_vignette", "Off: the dark vignette goes at once.")
	GryMod.OptionBox(form, "Tag the NPC you aim at", "gry_binoculars_tag", "For half a second; the radar shows it.")
	GryMod.OptionBox(form, "Outline what the binoculars spot", "gry_binoculars_silhouette", "A thin outline round what the scan reaches, from the end of its scan until the binoculars come down. Needs the tag option above.")
	GryMod.OptionBox(form, "Spotted targets as a hologram", "gry_binoculars_hologram", "A thin outline and the whole body filled with scan lines: green for a hostile, white while it is scanned, blue for an ally. Off: the pale blue halo.")
	form:Help("How the hologram is drawn")

	local styleBox = vgui.Create("DComboBox")
	styleBox.GryConVar = "gry_binoculars_holo_style"
	styleBox:SetSortItems(false)
	styleBox:AddChoice("The original's method (a shader)", "crysis")
	styleBox:AddChoice("Simple (additive lines and a halo)", "simple")
	styleBox:SetValue((styleBox:GetOptionText(GetConVar("gry_binoculars_holo_style"):GetString() == "simple" and 2 or 1)))
	styleBox.OnSelect = function(_, _, _, data)
		RunConsoleCommand("gry_binoculars_holo_style", tostring(data))
	end
	form:AddItem(styleBox)
	form:ControlHelp("The shader fills the whole body, brightens its boundary and adds the scan lines and a glow, as the original does. The game falls back to the simple style by itself when it cannot run the shader.")
	GryMod.OptionBox(form, "Hostiles in view drawn at once", "gry_binoculars_baseline", "The hostile NPCs in view are green before they are spotted, as in the original. Off: only what the scan reaches.")
	GryMod.OptionBox(form, "Lower the world's sounds", "gry_binoculars_mood", "Explosions, collisions and vehicles are lowered while the binoculars are up.")
	GryMod.OptionBox(form, "Zoom stages with the mouse wheel", "gry_binoculars_stages", "2x, 4x, 8x, 0.055 s between them, 0.2 s to open and close. Off: the Half-Life 2 zoom (always on with the own zoom key). Changes how the mouse feels.")
	GryMod.OptionBox(form, "Binoculars sway", "gry_binoculars_sway", "The view drifts slowly in a figure of eight, strongest at the start, less when crouching or in strength mode (the original). Moves the view.")
	GryMod.OptionBox(form, "Field of view follows the zoom", "gry_zoom_follow_fov", "The server sets it, so that distant windows and fades keep the details of a zoomed view. Off: only the picture is zoomed.")
	GryMod.OptionBox(form, "Hide the crosshair in a weapon zoom", "gry_zoom_hide_crosshair", "While the crossbow (or any weapon whose right click zooms) is zoomed, the HUD crosshair goes, as it does with the binoculars.")
	GryMod.OptionBox(form, "Cancel the crossbow zoom", "gry_zoom_cancel_weapon", "Opening the binoculars while the crossbow is zoomed (right click) ends the crossbow's zoom. Off: it comes back when the binoculars close.")
	GryMod.OptionBox(form, "Film follows a malfunction", "gry_binoculars_malfunction", "While the suit is down the binoculars fade to white; with the HUD flickering they fade out (the original film's own states).")
	GryMod.OptionBox(form, "No shooting with the binoculars up", "gry_binoculars_no_fire", "The original holds the binoculars in place of the weapon. Off: you can shoot through the Half-Life 2 zoom.")
	GryMod.OptionBox(form, "Walk pace with the binoculars up", "gry_binoculars_walk", "No sprint, and the slow walk instead of the jog, as in the original.")
	GryMod.OptionBox(form, "Hold the zoom key to step the zoom", "gry_binoculars_hold_zoom", "Holding the key goes 2x, 4x, 8x, then back to 2x. Needs the zoom stages.")
	GryMod.OptionBox(form, "No film in third person", "gry_binoculars_thirdperson", "As in the original: the zoom works, the film is not drawn. Off: it is drawn there too.")
	GryMod.OptionBox(form, "Full-screen vision", "gry_binoculars_vision", "Cool tint, scan lines and darker edges. The original has it in the High quality only, and it doubles the film's vignette.")
end

-- The suit: the camouflage and the screen effects of what happens to it.
function GryMod.SuitOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Suit and camouflage")

	GryMod.OptionBox(form, "Screen effects", "gry_screenfx", "Heavy armor hit flash and shake, red tint and blur at low health, colour tint of a suit mode change.")
	GryMod.OptionBox(form, "Small shake on a light hit", "gry_hit_shake", "A hit the armor takes that costs less than a fifth of the bar shakes the screen a little (needs the screen effects above).")
	GryMod.OptionBox(form, "Camouflage: bend the picture", "gry_cloak_fx", "The picture behind the player is bent, and it fades in and out. Off: the old material.")
	GryMod.OptionBox(form, "Camouflage: original refraction", "gry_cloak_refract", "The bent picture is the original game's own pixel shader, blended over the model. Off: the older Refract material.")
	GryMod.OptionBox(form, "Camouflage: original sparks", "gry_cloak_shader", "The sparks are the original game's own pixel shader, when the game can run it. Off: the older approximation.")
	GryMod.OptionBox(form, "Camouflage: scan lines", "gry_cloak_lines", "Electric blue scan lines cross the sparks, drawn on the screen over the silhouette. Off: no lines.")
	GryMod.OptionBox(form, "Camouflage: progressive change", "gry_cloak_transition", "With the sparks, in first and third person. Off: it switches at once.")
	GryMod.OptionBox(form, "Right click that fires ends it", "gry_cloak_altfire", "Shotgun double barrel, SMG grenade, AR2 ball, frag lob; the crossbow zoom does not.")
	GryMod.OptionBox(form, "Selector click keeps the camouflage", "gry_cloak_selector_guard", "A click just after the weapon selector closed by itself (1.2 s after the wheel) confirms the selection instead of firing and ending the camouflage.")
	GryMod.OptionBox(form, "Glitch when firing out of it", "gry_decloak_glitch", "Flash, HUD jump and shake, at any energy and not only above 20 %.")

	-- the suit's own text lines (the HUD element "Text lines" must be on too)
	for _, key in ipairs(GryMod.Messages.LineKeys()) do
		local line = GryMod.Messages.Lines[key]

		GryMod.OptionBox(form, line.label, line.convar, line.help .. ". Shown as \"" .. line.text .. "\".")
	end

	GryMod.OptionBox(form, "Message: objectives", "gry_msg_objectives", "A line and a sound when an objective is added, finished or failed (the list you get when you join is silent).")
end

-- The night vision (cl_nightvision.lua; its key is in the Keys category, the server's switch in the server category). Each part of its screen effect has its own
-- switch (cl_nightvision_fx.lua reads them).
function GryMod.NightVisionOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Night vision")

	GryMod.OptionBox(form, "Night vision", "gry_nightvision", "The suit's light amplifier. Off: it cannot be switched on.")
	GryMod.OptionBox(form, "Hold the key to use it", "gry_nightvision_hold", "On while the key is down. Off: press once to switch it on, again to switch it off.")
	GryMod.OptionBox(form, "Limited energy", "gry_nightvision_energy", "A bar of its own (60 s of use from full, 15 s to refill); it switches off when empty, as in the original. Off: no limit and no bar.")
	GryMod.OptionSlider(form, "Energy used a second", "gry_nightvision_drain", 0.05, 5, 2, "Out of 30: the original's 0.5 gives 60 seconds of use.")
	GryMod.OptionSlider(form, "Energy recovered a second", "gry_nightvision_recharge", 0.1, 20, 1, "While it is off: the original's 2 refills it in 15 seconds.")
	GryMod.OptionBox(form, "Screen effect", "gry_nightvision_fx", "The green amplified picture. Off: only the sounds and the energy bar.")
	GryMod.OptionBox(form, "Light behind you", "gry_nightvision_light", "A soft light behind the player that lights what you look at, with shadows.")
	GryMod.OptionBox(form, "Starlight", "gry_nightvision_star", "A faint light on the darkest parts. It costs a second drawing of the world.")
	GryMod.OptionBox(form, "Local gain", "gry_nightvision_localgain", "Each dark area of the screen is brightened on its own. Off: one gain for the whole screen.")
end

-- The suit's sounds (the binoculars' own are in the Binoculars category).
function GryMod.SoundOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Sounds")

	form:CheckBox("Suit sounds", "gry_sounds")
	-- the original game's levels plus this gain (0 dB: as quiet as in the game, +12 dB: the loud ones at full volume)
	GryMod.OptionSlider(form, "Sound level (dB)", "gry_sound_volume", -20, 12, 0, "The interface and the suit. 0 dB is as quiet as in the game, +12 dB plays the loud ones at full volume.")
	form:CheckBox("Repair sound when health comes back", "gry_sound_regen")
	GryMod.OptionBox(form, "Malfunction sound repeats", "gry_sound_malfunction_loop", "The failure sound goes on while the suit is down, as in the original. Off: it plays once.")
	GryMod.OptionBox(form, "Camouflage sound loop", "gry_sound_cloak_loop", "A soft loop plays while the suit is cloaked (the original's hud cloak feedback).")
	GryMod.OptionBox(form, "Quieter steps in camouflage", "gry_cloak_foley_quiet", "While cloaked, your own footsteps and the suit's sounds are at 70 % over one second, as in the original. Other players' steps and the ambience are not changed.")
	GryMod.OptionBox(form, "Underwater sounds", "gry_underwater_fx", "Dive in and out, breathing, gasps, ambience.")
end

-- What is left for the people who work on the addon.
function GryMod.DevelopmentOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Development")

	form:NumSlider("Mirror Distance", "gry_xadd", -5000, 5000, 0)
	form:NumSlider("X Position", "gry_xdist", -5000, 5000, 0)

	-- the effects test window opens apart from this panel (cl_debug_window.lua)
	local debugButton = form:Button("Open the effects test window")
	debugButton.GryDebugOpen = true

	debugButton.DoClick = function()
		if GryMod.DebugWindow then
			GryMod.DebugWindow.Open()
		end
	end
end

-- The line under a key picker: for a key that is chosen, what the game already does with it (a warning when the key is bound to
-- something: it will do that as well, we cannot tell what another addon's hook does with it); with none chosen, whenNone.
local function keyStatus(code, command, whenNone)
	if code and code > 0 then
		return GryMod.KeyBinder.ConflictText(code, command) or "This key is free in the game."
	end

	return whenNone
end

-- What the zoom does while no key is chosen: the default key (computed, never saved), a bind of +gry_zoom, or nothing free.
local function zoomWhenNone()
	local zoom = GryMod.SuitZoom

	if not GetConVar("gry_zoom_own"):GetBool() then
		return "The binoculars' own zoom is switched off (the box below)."
	end

	if input.LookupBinding("+gry_zoom") ~= nil then
		return "A `bind <key> +gry_zoom` in the console is the zoom key."
	end

	local default = zoom.DefaultKey()

	if default then
		return "Default: " .. string.upper(input.GetKeyName(default) or "?") .. " (free in the game), until you choose another key here."
	end

	return "No default key is free (H, J, K and N are taken): choose a key here."
end

-- What the night vision does while no key is chosen: the default key (N, computed, never saved), a bind of +gry_nightvision, or nothing free.
local function nightVisionWhenNone()
	local NV = GryMod.NightVision

	-- (built once, not at every frame: no cached answer)
	NV.ForgetBinding()

	if not GetConVar("gry_nightvision"):GetBool() then
		return "The night vision is switched off (its box below)."
	end

	if input.LookupBinding("+gry_nightvision") ~= nil then
		return "A `bind <key> +gry_nightvision` in the console is the night vision key."
	end

	if NV.DefaultKey() then
		return "Default: " .. string.upper(input.GetKeyName(NV.DefaultKey()) or "?") .. " (free in the game), until you choose another key here."
	end

	return "No default key is free (N is taken): choose a key here."
end

-- The keys, all together at the top of the panel so that nobody has to scroll for them: each key picker with a short description and a line
-- under it (the default, or a warning when the key is already bound in the game), the zoom's behaviour right under its key, and the boxes
-- that go with a key. A `bind <key> <command>` in the console works as well. A picker refuses what its key refuses (Escape, the mouse
-- wheel, the other key) and shows the key that is saved.
function GryMod.KeysOptions(Parent)
	local Panel = GryMod.OptionsCategory(Parent, "Keys", true)

	-- the key of the quick menu
	if GryMod.MenuKey then
		Panel:AddControl("Label", {
			Text = "Quick menu key: hold it, point with the mouse, release (a `bind <key> +crysishud` in the console works too)"
		})

		local binder = vgui.Create("DBinder")
		binder:SetValue(GetConVar("gry_menu_key"):GetInt())
		Panel:AddItem(binder)

		local status = Panel:Help(keyStatus(GryMod.MenuKey.Chosen(), "+crysishud", "No key is chosen."))
		binder.OnChange = function(self, code)
			if not GryMod.MenuKey.SetKey(code) then
				self:SetValue(GryMod.MenuKey.Chosen())
			end

			status:SetText(keyStatus(GryMod.MenuKey.Chosen(), "+crysishud", "No key is chosen."))
		end
	end

	-- the binoculars' own zoom: a zoom of its own, apart from the Half-Life 2 suit zoom, which is left as it is; the wheel steps the stages
	-- while it is up
	if GryMod.SuitZoom then
		Panel:AddControl("Label", {
			Text = "Binoculars zoom key: the binoculars' own zoom, apart from the Half-Life 2 suit zoom (its key is left as it is). The mouse wheel steps 2x, 4x, 8x. A `bind <key> +gry_zoom` in the console works too"
		})

		local zoomBinder = vgui.Create("DBinder")
		zoomBinder:SetValue(GetConVar("gry_zoom_key"):GetInt())
		Panel:AddItem(zoomBinder)

		local zoomStatus = Panel:Help(keyStatus(GryMod.SuitZoom.Key.Chosen(), "+gry_zoom", zoomWhenNone()))
		zoomBinder.OnChange = function(self, code)
			-- a key that is refused (Escape, the wheel, the quick menu's key) is not shown as chosen
			if not GryMod.SuitZoom.Key.SetKey(code) then
				self:SetValue(GryMod.SuitZoom.Key.Chosen())
			end

			GryMod.SuitZoom.ForgetBinding()
			zoomStatus:SetText(keyStatus(GryMod.SuitZoom.Key.Chosen(), "+gry_zoom", zoomWhenNone()))
		end

		-- how the key works: the setting is written when the player picks a line, never when the panel opens
		Panel:Help("Zoom key behaviour: hold, toggle, or automatic (a short press toggles, a long press holds)")

		local modeBox = vgui.Create("DComboBox")
		modeBox:SetSortItems(false)
		modeBox:AddChoice("Hold: the zoom lasts while the key is down", 0)
		modeBox:AddChoice("Toggle: press once to open, press again to close", 1)
		modeBox:AddChoice("Automatic: a short press toggles, a long press holds", 2)
		modeBox:SetValue((modeBox:GetOptionText(GryMod.SuitZoom.Mode() + 1)))
		modeBox.OnSelect = function(_, _, _, data)
			RunConsoleCommand("gry_zoom_mode", tostring(data))
		end
		Panel:AddItem(modeBox)

		GryMod.OptionSlider(Panel, "Short press (ms)", "gry_zoom_tap_ms", 100, 600, 0, "In the automatic mode a press shorter than this is a toggle, a longer one holds.")
		GryMod.OptionBox(Panel, "Binoculars' own zoom", "gry_zoom_own", "Off: only the Half-Life 2 zoom key drives the binoculars.")
	end

	-- the night vision: its key (how it works, hold or toggle, is in the Night vision category)
	local NV = GryMod.NightVision

	if NV then
		Panel:AddControl("Label", {
			Text = "Night vision key: the suit's light amplifier (a `bind <key> +gry_nightvision` in the console works too)"
		})

		local nvBinder = vgui.Create("DBinder")
		nvBinder:SetValue(GetConVar("gry_nightvision_key"):GetInt())
		Panel:AddItem(nvBinder)

		local nvStatus = Panel:Help(keyStatus(NV.Key.Chosen(), "+gry_nightvision", nightVisionWhenNone()))
		nvBinder.OnChange = function(self, code)
			-- a key that is refused (Escape, the wheel, the quick menu's or the zoom's key) is not shown as chosen
			if not NV.Key.SetKey(code) then
				self:SetValue(NV.Key.Chosen())
			end

			NV.ForgetBinding()
			nvStatus:SetText(keyStatus(NV.Key.Chosen(), "+gry_nightvision", nightVisionWhenNone()))
		end
	end
end

-- The settings of the server: for the administrators only (greyed and disabled for the others). They do not write a convar from the client: they ask the
-- server (cl_admin_option.lua). A category of its own, with the line that says whether you are an administrator.
function GryMod.AdminOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Server (administrators only)")

	GryMod.AdminUI.Section(Panel, "Server (administrators only)", form)

	GryMod.AdminOption(Panel, "Suit malfunctions", "gry_malfunction", "bool", {into = form, help = "EMP, electric hits and heavy impacts put the suit down."})
	GryMod.AdminOption(Panel, "Drowning rules", "gry_drown_rules", "bool", {into = form, help = "60 s of breath, then the suit energy, then health. Off: the engine's drowning."})
	GryMod.AdminOption(Panel, "Realistic fall damage", "gry_realistic_fall", "bool", {into = form, help = "The fall hurts by its speed, not 10 whatever the height. The armor takes it first. Turns the game's own setting on at every launch."})
	GryMod.AdminOption(Panel, "Energy sent at every tick", "gry_energy_net", "bool", {into = form, help = "Off: the slower networked value."})
	GryMod.AdminOption(Panel, "Suit rules", "gry_mechanics", "choice", {
		into = form,
		choices = {
			{"Crysis (the original game's numbers)", "crysis"},
			{"Classic GryMod", "classic"}
		}
	})
	GryMod.AdminOption(Panel, "Camouflage: enemies forget you", "gry_cloak_ai", "bool", {into = form, help = "Striders, hunters and manhacks forget you."})
	GryMod.AdminOption(Panel, "Camouflage fade for the AI", "gry_cloak_fade_seconds", "choice", {
		into = form,
		help = "How long you stay half visible to addon AIs when the camouflage starts or ends.",
		choices = {
			{"Instant", "0"},
			{"0.5 s", "0.5"},
			{"1 s", "1"},
			{"2 s (default)", "2"},
			{"3 s", "3"},
			{"5 s", "5"}
		}
	})
	GryMod.AdminOption(Panel, "Movement speeds", "gry_movement", "choice", {
		into = form,
		choices = {
			{"GMod's own speeds", "0"},
			{"Crysis vanilla speeds", "1"},
			{"Crysis ratios on GMod's speeds", "2"}
		}
	})
	form:ControlHelp("Crysis vanilla: the original game's walk 177 and sprint 266 units a second, the speed mode's sprint climbing to 757 in a second. Ratios: GMod's walk 200 and sprint 400 with the same increases in the speed mode. Both also use the original's energy rules.")
	GryMod.AdminOption(Panel, "Objectives", "gry_objectives", "bool", {into = form, help = "Objectives given by maps and addons are sent to the players. Off: none are sent."})
	GryMod.AdminOption(Panel, "Campaign objectives", "gry_campaign_objectives", "bool", {into = form, help = "The Half-Life 2 and episode maps give objectives (the way out of each map, key steps). Off: none, and nothing is read."})
	GryMod.AdminOption(Panel, "Campaign secrets", "gry_campaign_secrets", "bool", {into = form, help = "Count the hidden items of a campaign map in one objective, \"Secrets 3/7\". Off: they are not mentioned."})
	GryMod.AdminOption(Panel, "Night vision", "gry_sv_nightvision", "bool", {into = form, help = "The players may use the night vision. Off: it is forbidden for everybody and goes off at once."})
	GryMod.AdminOption(Panel, "Grenade warning: armed ones only", "gry_grenade_armed_only", "bool", {into = form, help = "Only armed grenades, mines in the air... Off: also the ones lying around."})
	-- the two toggles of the console (gry_Health, gry_Armor) are settings of the server too: check boxes that show the state (sv_system.lua)
	GryMod.AdminOption(Panel, "Health regeneration", "gry_health_regen", "bool", {into = form, help = "The suit repairs the health over time. Off: no regeneration."})
	GryMod.AdminOption(Panel, "Infinite armor", "gry_infinite_armor", "bool", {into = form, help = "The suit never loses energy and no malfunction happens. Off: the normal rules."})
end

-- Tells the player what the cache button did (a notice on the screen).
local function minimapNotice(text, kind)
	if notification and notification.AddLegacy then
		notification.AddLegacy(text, kind, 4)
	end
end

-- Asks "are you sure" before an action that cannot be undone: the text, and what to run on "yes". A function of GryMod so that a test can answer it.
function GryMod.Confirm(text, onYes)
	Derma_Query(text, "GryMod", "Yes", onYes, "Cancel")
end

-- What the "Clear the minimap cache" button of the Radar and map menu does: the files of the current level, made again the next time the radar needs them. It asks the
-- Cache module (another file, which may be missing or fail): nothing here may raise.
local function clearMinimapCache()
	local cache = GryMod.Minimap and GryMod.Minimap.Cache

	if not cache or not isfunction(cache.Clear) or not isfunction(cache.Key) then
		minimapNotice("The minimap cache is not available.", NOTIFY_ERROR)

		return
	end

	local ok, result, reason = pcall(function()
		return cache.Clear(cache.Key())
	end)

	-- the generator remembers the last request it made: without this, asking for the same tiles again would find the request already done
	-- and make nothing (the files are gone)
	local gen = GryMod.Minimap.Gen

	if gen and isfunction(gen.Cancel) then
		pcall(gen.Cancel)
	end

	if ok and result ~= false then
		minimapNotice("The minimap cache of this level was cleared; the map is made again as you play.", NOTIFY_GENERIC)
	else
		minimapNotice("The minimap cache could not be cleared: " .. tostring(ok and reason or result), NOTIFY_ERROR)
	end
end

-- the button of the Radar and map menu (cl_options_radar.lua) runs it, after asking
GryMod.ClearMinimapCache = clearMinimapCache

-- Numbers the panels of the definition slider, so that each one has its own change callback (a name that no other panel uses, also across a reload of this file).
GryMod.MinimapDefinitionPanels = GryMod.MinimapDefinitionPanels or 0

-- The definition slider is greyed (disabled, it keeps its value) while the automatic definition is on, and wakes when it is off, also when the convar is
-- changed from the console. The convar's change callback lives only as long as the panel: it takes itself off when the panel is removed (OnRemove) or
-- finds it dead; no hook, no Think.
-- The same for any control and any switch: `control` is greyed while the convar `name` is on (`isOn` reads its text), and wakes when it is off.
local function greyWhileOn(control, name, isOn)
	local convar = GetConVar(name)

	control:SetEnabled(not (convar and isOn(convar:GetString())))

	GryMod.MinimapDefinitionPanels = GryMod.MinimapDefinitionPanels + 1

	local id = "GryMod_MinimapGrey_" .. GryMod.MinimapDefinitionPanels

	-- a callback does not take itself off here: cvars.OnConVarChanged walks the list by index, and removing an entry during the walk would call a nil. The engine
	-- calls OnRemove when it deletes the panel (at the end of the frame of its Remove), which is outside any walk.
	cvars.AddChangeCallback(name, function(_, _, new)
		if IsValid(control) then
			control:SetEnabled(not isOn(new))
		end
	end, id)

	local removed = control.OnRemove

	control.OnRemove = function(self)
		cvars.RemoveChangeCallback(name, id)

		if removed then
			removed(self)
		end
	end
end

local function followDefinitionAuto(slider)
	local Settings = GryMod.Minimap and GryMod.Minimap.Settings

	greyWhileOn(slider, "gry_minimap_definition_auto", function(text)
		if Settings and isfunction(Settings.ParseDefinitionAuto) then
			return Settings.ParseDefinitionAuto(text)
		end

		return (tonumber(text) or 1) ~= 0
	end)
end

-- The radar range slider is greyed while the automatic zoom is on: the three ranges of the zoom's modes take its place.
local function followAutoZoom(slider)
	greyWhileOn(slider, "gry_radar_autozoom", function(text)
		return (tonumber(text) or 0) ~= 0
	end)
end

-- The map behind the radar, in two categories. "Minimap": the switch, the distance the radar shows (the radar range), how sharp the map is (pixels per metre
-- of the tiles: chosen by itself from the range and the screen, or by the slider, which the check box greys), how opaque the map is, how visible the floor
-- below is through the empty parts of the current one and how visible the outside (the whole height of the map) is behind both. "Minimap speed and cache":
-- making the tiles in advance, the veil, how much disk the cache of a map may take, the size of one tile, how much time the generator may take in a frame.
-- The settings are written when the player changes a control, never when the panel opens.
function GryMod.MinimapOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Minimap", true)

	GryMod.OptionBox(form, "Map behind the radar", "gry_minimap", "Draw the map of the level behind the radar.")
	-- the range sits right before the automatic definition, which follows it (and the screen)
	local range = GryMod.OptionSlider(form, "Radar range (m)", "gry_radar_range", 5, 100, 0, "75 is the original's, 40 to 75 are good values; down to 5 it zooms the map right in (raise the map definition for a sharp picture).")

	if IsValid(range) then
		followAutoZoom(range)
	end

	GryMod.OptionBox(form, "Automatic definition", "gry_minimap_definition_auto", "Follows the radar range and the screen.")

	local definition = GryMod.OptionSlider(form, "Map definition", "gry_minimap_definition", 1, 64, 0, "Pixels per metre of the map tiles: more is sharper and takes longer to make.")

	if IsValid(definition) then
		followDefinitionAuto(definition)
	end

	form:NumSlider("Map opacity (%)", "gry_minimap_opacity", 0, 100, 0)
	form:NumSlider("Floor below (opacity %)", "gry_minimap_below", 0, 100, 0)
	GryMod.OptionSlider(form, "Outside behind floors (%)", "gry_minimap_outside", 0, 100, 0, "The whole height of the map seen through the solid parts; 0 = off.")

	local speed = GryMod.OptionsCategory(Panel, "Minimap speed and cache")

	GryMod.OptionBox(speed, "Make outdoor tiles in advance", "gry_minimap_preload", "From the in/out map, at the definitions the zoom ranges need. Off: only as you play.")
	GryMod.OptionBox(speed, "Also the places around the nodes", "gry_minimap_preload_around", "A step from each ground node of the map: fewer veils on ramps and at doors, a longer plan and more tiles.")
	GryMod.OptionBox(speed, "Noise veil on missing tiles", "gry_minimap_veil_discovery", "A noise veil and a percentage whenever the map tile under you is missing. Off: while you discover the map the last picture stays and the new one appears when ready; the veil only comes when there is nothing to show.")
	speed:NumSlider("Cache size limit (MB)", "gry_minimap_cache_mb", 16, 4096, 0)

	speed:Help("Map tile size (pixels)")

	local tileBox = vgui.Create("DComboBox")
	tileBox.GryConVar = "gry_minimap_tile"
	tileBox:SetSortItems(false)
	tileBox:AddChoice("512 (small, quick to make)", "512")
	tileBox:AddChoice("1024 (the default)", "1024")
	tileBox:AddChoice("2048 (big, slower to make)", "2048")

	-- show the size that is saved without writing it: the text and the choice are set by hand, OnSelect is put on after
	local current = GryMod.Minimap.Settings and GryMod.Minimap.Settings.TileRes() or 1024

	for id = 1, 3 do
		if tileBox:GetOptionData(id) == tostring(current) then
			tileBox:SetValue((tileBox:GetOptionText(id)))
			tileBox.selected = id
		end
	end

	tileBox.OnSelect = function(_, _, _, data)
		RunConsoleCommand("gry_minimap_tile", tostring(data))
	end
	speed:AddItem(tileBox)

	GryMod.OptionSlider(speed, "Generator time (ms)", "gry_minimap_budget_ms", 1, 30, 0, "How much time the map generator may take in a frame.")

	return speed
end

-- The radar's automatic zoom (cl_hud_radar_zoom.lua): the switch, the range of each of the three modes (nothing ties one to another: the player puts what he
-- wants) and how long a mode has to hold before the radar goes there. The radar range slider of the Minimap category is greyed while the switch is on.
function GryMod.RadarZoomOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Automatic zoom")

	GryMod.OptionBox(form, "Automatic zoom", "gry_radar_autozoom", "The radar's range follows where you are: in a vehicle, on foot outside, indoors under a ceiling in a narrow place.")
	form:NumSlider("Range in a vehicle (m)", "gry_radar_zoom_vehicle", 5, 100, 0)
	form:NumSlider("Range on foot outside (m)", "gry_radar_zoom_foot", 5, 100, 0)
	form:NumSlider("Range indoors (m)", "gry_radar_zoom_indoor", 5, 100, 0)
	GryMod.OptionSlider(form, "Delay before a change (s)", "gry_radar_zoom_delay", 0.1, 5, 1, "A mode must hold that long before the radar goes there; in a mode for less than that, nothing changes.")
end

-- The in/out map the server makes (cl_zonemap.lua): the line with its state (as it is when the panel is built: nothing runs while the panel is
-- open), the check box of the debug drawing and how far it draws (metres). The switch and the button that makes the map again are the administrators' (the server category of the Radar and map menu).
function GryMod.ZoneMapOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "In/out map")

	local Zone = GryMod.ZoneMapClient

	form:Help(Zone and Zone.StatusText() or "In/out map: not available")
	GryMod.OptionBox(form, "Draw the map in the world", "gry_zonemap_debug", "A debug drawing of the in/out map, as boxes in the world.")
	form:CheckBox("Show the IN zones (indoor, red)", "gry_zonemap_debug_in")
	form:CheckBox("Show the OUT zones (outdoor, green)", "gry_zonemap_debug_out")
	GryMod.OptionBox(form, "Draw the faces", "gry_zonemap_debug_faces", "The filled translucent volumes.")
	GryMod.OptionBox(form, "Draw the edges", "gry_zonemap_debug_edges", "The lines around each box and the ceiling height line.")
	form:NumSlider("Display distance (m)", "gry_zonemap_debug_range", 20, 300, 0)
end

-- The Config menu: the title, then one folding category for each subject (the keys, the HUD, the binoculars, the suit, the sounds, the server, the
-- development tools). Every control is bound to its convar: the settings are saved, and opening the panel never changes them.
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	GryMod.KeysOptions(Panel)
	GryMod.GryHUDOptions(Panel)
	GryMod.BinocularsOptions(Panel)
	GryMod.SuitOptions(Panel)
	GryMod.NightVisionOptions(Panel)
	GryMod.SoundOptions(Panel)
	GryMod.AdminOptions(Panel)
	GryMod.DevelopmentOptions(Panel)
end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Radar", "Radar and map", "", "", GryMod.RadarOptionsPanel)
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Compat", "Compatibility", "", "", GryMod.CompatOptionsPanel)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)
