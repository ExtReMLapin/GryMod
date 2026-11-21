
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

	-- what was added to the binoculars, each on its own: the screen itself is the "Binoculars" element above (the zoom key is in the Keys
	-- section at the top of the panel)
	Panel:Help("Binoculars")

	Panel:CheckBox("Binoculars sounds: opening, closing, ambience loop, target locked", "gry_binoculars_sounds")
	Panel:CheckBox("Original aim rules: 4 rays, 300 m, the distance to the entity aimed at", "gry_binoculars_aim")
	Panel:CheckBox("Horizon ladder that follows where you look", "gry_binoculars_horizon")
	Panel:CheckBox("Dark vignette fading out as the binoculars close (off: it goes at once)", "gry_binoculars_vignette")
	Panel:CheckBox("Tag an NPC aimed at for half a second (the radar shows it)", "gry_binoculars_tag")
	Panel:CheckBox("Outline in pale blue the NPCs scanned, from the end of their scan until the binoculars come down (needs the tag option above)", "gry_binoculars_silhouette")
	Panel:CheckBox("Binoculars sound mood: explosions, collisions and vehicles are lowered while they are up", "gry_binoculars_mood")
	Panel:CheckBox("Binoculars zoom stages 2x, 4x, 8x with the mouse wheel, 0.055 s between them, 0.2 s to open and close (off: the Half-Life 2 zoom; always on with the own zoom key above). Changes how the mouse feels", "gry_binoculars_stages")
	Panel:CheckBox("Binoculars sway: the view drifts slowly in a figure of eight, strongest at the start, less when crouching or in strength mode (the original). Moves the view", "gry_binoculars_sway")
	Panel:CheckBox("Own zoom: the player's field of view follows the stage (the server sets it), so that distant windows and fades keep the details of a zoomed view (off: only the picture is zoomed)", "gry_zoom_follow_fov")
	Panel:CheckBox("Opening the binoculars while the crossbow is zoomed (right click) ends the crossbow's zoom (off: it comes back when the binoculars close)", "gry_zoom_cancel_weapon")
	Panel:CheckBox("Binoculars full-screen vision: cool tint, scan lines and darker edges. The original has it in the High quality only, and it doubles the film's vignette", "gry_binoculars_vision")

	Panel:CheckBox("Screen effects: heavy armor hit flash and shake, red tint and blur at low health, colour tint of a suit mode change", "gry_screenfx")
	Panel:NumSlider("Crosshair style (1 to 13)", "gry_hud_crosshair_style", 1, 13, 0)
	Panel:Button("Switch every element back on", "gry_hud_reset")

	-- client setting: the HUD also goes down (Lost, then Reboot) while the energy bar is empty, GryMod's old rule
	Panel:CheckBox("HUD malfunction also when the energy bar is empty (the original: only on an EMP, an electric attack or death)", "gry_malfunction_empty")
	-- client setting: the quick menu icon that was chosen stays lit while the menu fades out
	Panel:CheckBox("Quick menu: the icon you chose stays lit while the menu fades out (the original; off: it goes plain at the release)", "gry_menu_keep_highlight")
	-- client setting: the quick menu ring keeps its colour from an active mode to an inactive one
	Panel:CheckBox("Quick menu: the ring stays green going from an active mode to an inactive one (the original; off: it turns orange)", "gry_menu_ring_film")
	-- client setting: the quick menu pointer runs the game's rule on a fixed clock and the arrow is eased
	Panel:CheckBox("Quick menu: the arrow follows the mouse on a fixed clock and does not flutter at a high frame rate (off: on every frame, as before)", "gry_menu_pointer_film")
	-- client setting: the suit mode icon plays its reboot animation when the HUD comes back
	Panel:CheckBox("Suit mode icon plays its reboot animation when the HUD comes back after a malfunction (the original)", "gry_icon_reboot")
	-- client setting: the start-up log and its sounds belong to the start of the level in the original
	Panel:CheckBox("Start-up log and sounds at every spawn (off: only at the first spawn after the map loads, as in the original)", "gry_boot_every_spawn")

	-- client settings: how far the grenade warning reaches, the old warning for the player's own hand grenade, walls (the original has no range and warns through walls)
	Panel:NumSlider("Grenade warning range (metres)", "gry_grenade_range", 5, 200, 0)
	Panel:CheckBox("Grenade warning also for the hand grenade you threw (only within 15 m). Off: a grenade you threw never warns; your own missiles never do", "gry_grenade_own_warn")
	Panel:CheckBox("Grenade warning only for what you can see (off: also through walls, as in the original game)", "gry_grenade_los")

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

-- The keys, all together at the top of the panel so that nobody has to scroll for them: each key picker with a short description and a line
-- under it (the default, or a warning when the key is already bound in the game), the zoom's behaviour right under its key, and the boxes
-- that go with a key. A `bind <key> <command>` in the console works as well. A picker refuses what its key refuses (Escape, the mouse
-- wheel, the other key) and shows the key that is saved.
function GryMod.KeysOptions(Panel)
	Panel:Help("Keys")

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

		Panel:NumSlider("Short press: shorter than this is a toggle, longer holds (milliseconds, automatic mode)", "gry_zoom_tap_ms", 100, 600, 0)
		Panel:CheckBox("Binoculars own zoom on (off: only the Half-Life 2 zoom key drives the binoculars)", "gry_zoom_own")
	end
end

-- The settings of the server, at the bottom of the panel: for the administrators only (greyed and disabled for the others). They do not write a
-- convar from the client: they ask the server (cl_admin_option.lua).
function GryMod.AdminOptions(Panel)
	GryMod.AdminUI.Section(Panel, "Server (administrators only)")

	GryMod.AdminOption(Panel, "Suit malfunctions: EMP, electric hits and heavy impacts put the suit down", "gry_malfunction", "bool")
	GryMod.AdminOption(Panel, "Drowning: 60 s of breath, then the suit energy, then health (off: the engine's drowning)", "gry_drown_rules", "bool")
	GryMod.AdminOption(Panel, "Send the suit energy at every tick (off: the slower networked value)", "gry_energy_net", "bool")
	GryMod.AdminOption(Panel, "Suit rules", "gry_mechanics", "choice", {
		choices = {
			{"Crysis (the original game's numbers)", "crysis"},
			{"Classic GryMod", "classic"}
		}
	})
	GryMod.AdminOption(Panel, "Camouflage: striders, hunters and manhacks forget you", "gry_cloak_ai", "bool")
	GryMod.AdminOption(Panel, "Radar: allies (NPCs that like you) show in blue from the start (off: only when alerted, fighting or scanned)", "gry_radar_allies_always", "bool")
	GryMod.AdminOption(Panel, "Grenade warning only for armed grenades, mines in the air... (off: also the ones lying around)", "gry_grenade_armed_only", "bool")
	GryMod.AdminOption(Panel, "Toggle health regeneration", nil, "button", {command = "gry_Health"})
	GryMod.AdminOption(Panel, "Toggle infinite armor", nil, "button", {command = "gry_Armor"})
end

-- Every control is bound to its convar: the settings are saved, and opening the panel never changes them.
function GryMod.GryOptionschute(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Config"
	})

	GryMod.KeysOptions(Panel)

	Panel:CheckBox("Draw the HUD (health, energy, ammo, radar)", "gry_hud")
	Panel:CheckBox("Suit sounds", "gry_sounds")
	-- the original game's levels plus this gain (0 dB: as quiet as in the game, +12 dB: the loud ones at full volume)
	Panel:NumSlider("Interface and suit sound level (dB)", "gry_sound_volume", -20, 12, 0)
	Panel:CheckBox("Repair sound when the health comes back", "gry_sound_regen")
	Panel:CheckBox("Underwater sounds: dive in and out, breathing, gasps, ambience", "gry_underwater_fx")
	Panel:CheckBox("Energy bar moves at every frame (predicted between the server's updates)", "gry_hud_energy_smooth")
	Panel:CheckBox("Camouflage: bend the picture behind the player and fade in and out (off: the old material)", "gry_cloak_fx")
	Panel:CheckBox("Camouflage: the sparks are crossed by electric blue scan lines drawn on the screen over the silhouette (off: no lines)", "gry_cloak_lines")
	Panel:CheckBox("Camouflage: the change is progressive, with the sparks, in first and third person (off: it switches at once)", "gry_cloak_transition")
	Panel:CheckBox("Camouflage: a right click that really fires also ends it (shotgun double barrel, SMG grenade, AR2 ball, frag lob; the crossbow zoom does not)", "gry_cloak_altfire")
	Panel:CheckBox("Camouflage: a click just after the weapon selector closed by itself (1.2 s after the wheel) confirms the selection instead of firing and ending the camouflage", "gry_cloak_selector_guard")
	Panel:CheckBox("Camouflage: firing out of it plays the glitch (flash, HUD jump, shake) at any energy, not only above 20 %", "gry_decloak_glitch")

	GryMod.GryHUDOptions(Panel)

	Panel:NumSlider("Mirror Distance", "gry_xadd", -5000, 5000, 0)
	Panel:NumSlider("X Position", "gry_xdist", -5000, 5000, 0)

	GryMod.AdminOptions(Panel)
end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)
