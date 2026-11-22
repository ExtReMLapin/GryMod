
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
	-- client setting: the radius of the radar's map (the original's is 75 m; a smaller one makes the icons of big things nearer their real size)
	-- the range slider is in the Minimap section now, next to the automatic definition that follows it
	Panel:Help("The radar range slider is in the Minimap section.")
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

-- The button that deletes the map of the level and makes it again: it asks first, then asks the server (which checks the administrator itself).
local function zoneMapResetButton(Panel)
	-- the usual administrators' button (dimmed with a tooltip for the others, looked at every second), with its own click
	local button = GryMod.AdminOption(Panel, "Delete the indoor / outdoor map and make it again", nil, "button", {command = "gry_zonemap_reset"})

	button.GryZoneMapReset = true
	button.DoClick = function()
		if not GryMod.AdminUI.IsAdmin() then
			return
		end

		GryMod.Confirm("Delete the indoor / outdoor map of this map and make it again? The server computes it again from the node graph; the automatic zoom uses its own rays meanwhile.", function()
			net.Start("gry_zonemap_reset")
			net.SendToServer()
		end)
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
	GryMod.AdminOption(Panel, "Movement: the original game's walk and run speeds (177 and 266 units a second, the speed mode's sprint 757) instead of GryMod's own; the energy is not touched", "gry_movement", "bool")
	GryMod.AdminOption(Panel, "Radar: vehicles and Combine mines show once the binoculars have scanned them", "gry_radar_objects", "bool")
	GryMod.AdminOption(Panel, "Grenade warning only for armed grenades, mines in the air... (off: also the ones lying around)", "gry_grenade_armed_only", "bool")
	GryMod.AdminOption(Panel, "Indoor / outdoor map: the server makes it from the node graph (the automatic zoom and other features use it)", "gry_zonemap", "bool")
	zoneMapResetButton(Panel)
	GryMod.AdminOption(Panel, "Toggle health regeneration", nil, "button", {command = "gry_Health"})
	GryMod.AdminOption(Panel, "Toggle infinite armor", nil, "button", {command = "gry_Armor"})
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

-- The button that clears the minimap's cache: the files of the current level, made again the next time the radar needs them. It asks the
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

-- The map behind the radar: the switch, the distance the radar shows (the radar range) and how sharp the map is (pixels per metre of the tiles: chosen by
-- itself from the range and the screen, or by the slider, which the check box greys), the size of
-- one tile, how opaque the map is, how much disk the cache of a map may take, how visible the floor below is through the empty parts of the current one, how visible the outside (the whole height of the map) is behind both, how much time the generator may take in a frame, and the button that clears the cache. The
-- settings are written when the player changes a control, never when the panel opens.
function GryMod.MinimapOptions(Panel)
	Panel:Help("Minimap")

	Panel:CheckBox("Draw the map of the level behind the radar", "gry_minimap")
	-- the range sits right before the automatic definition, which follows it (and the screen)
	local range = Panel:NumSlider("Radar range (metres; 75 is the original's, 40 to 75 are good values, down to 5 zooms the map right in; raise the map definition for a sharp picture)", "gry_radar_range", 5, 100, 0)

	if IsValid(range) then
		followAutoZoom(range)
	end
	Panel:CheckBox("Automatic definition (follows the radar range and the screen)", "gry_minimap_definition_auto")

	local definition = Panel:NumSlider("Map definition (pixels per metre of the map tiles; more is sharper and takes longer to make)", "gry_minimap_definition", 1, 64, 0)

	if IsValid(definition) then
		followDefinitionAuto(definition)
	end
	Panel:NumSlider("Map opacity (%)", "gry_minimap_opacity", 0, 100, 0)
	Panel:NumSlider("Floor below (opacity %)", "gry_minimap_below", 0, 100, 0)
	Panel:NumSlider("Outside behind the floors (opacity %; the whole height of the map seen through the solid parts, 0 = off)", "gry_minimap_outside", 0, 100, 0)
	Panel:NumSlider("Cache size limit (MB)", "gry_minimap_cache_mb", 16, 4096, 0)

	Panel:Help("Map tile size (pixels)")

	local tileBox = vgui.Create("DComboBox")
	tileBox.GryConVar = "gry_minimap_tile"
	tileBox:SetSortItems(false)
	tileBox:AddChoice("512 (small tiles, quick to make)", "512")
	tileBox:AddChoice("1024 (the default)", "1024")
	tileBox:AddChoice("2048 (big tiles, fewer but each takes longer)", "2048")

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
	Panel:AddItem(tileBox)

	Panel:NumSlider("Map generator time per frame (milliseconds)", "gry_minimap_budget_ms", 1, 30, 0)

	local clearButton = Panel:Button("Clear the minimap cache")
	clearButton.GryMinimapClear = true
	clearButton.DoClick = function()
		GryMod.Confirm("Clear the minimap cache of this level? The map is made again as you play.", clearMinimapCache)
	end
end

-- The radar's automatic zoom (cl_hud_radar_zoom.lua): the switch, the range of each of the three modes (nothing ties one to another: the player puts what he
-- wants) and how long a mode has to hold before the radar goes there. The radar range slider of the Minimap section is greyed while the switch is on.
function GryMod.RadarZoomOptions(Panel)
	Panel:Help("Automatic zoom")

	Panel:CheckBox("Automatic zoom: the radar's range follows where you are (in a vehicle, on foot outside, indoors under a ceiling in a narrow place)", "gry_radar_autozoom")
	Panel:NumSlider("Range in a vehicle (metres)", "gry_radar_zoom_vehicle", 5, 100, 0)
	Panel:NumSlider("Range on foot outside (metres)", "gry_radar_zoom_foot", 5, 100, 0)
	Panel:NumSlider("Range indoors (metres)", "gry_radar_zoom_indoor", 5, 100, 0)
	Panel:NumSlider("Time a mode must hold before the radar goes there (seconds; in a mode for less than that, nothing changes)", "gry_radar_zoom_delay", 0.1, 5, 1)
end

-- The indoor / outdoor map the server makes (cl_zonemap.lua): the line with its state (as it is when the panel is built: nothing runs while the panel is
-- open) and the check box of the debug drawing. The switch and the button that makes the map again are the administrators' (GryMod.AdminOptions).
function GryMod.ZoneMapOptions(Panel)
	Panel:Help("Indoor / outdoor map")

	local Zone = GryMod.ZoneMapClient

	Panel:Help(Zone and Zone.StatusText() or "Indoor / outdoor map: not available")
	Panel:CheckBox("Draw the indoor / outdoor map in the world (debug)", "gry_zonemap_debug")
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
	Panel:CheckBox("Camouflage: the refraction (the bent picture behind) is the original game's own pixel shader, blended over the model (off: the older Refract material)", "gry_cloak_refract")
	Panel:CheckBox("Camouflage: the sparks are the original game's own pixel shader, when the game can run it (off: the older approximation)", "gry_cloak_shader")
	Panel:CheckBox("Camouflage: the sparks are crossed by electric blue scan lines drawn on the screen over the silhouette (off: no lines)", "gry_cloak_lines")
	Panel:CheckBox("Camouflage: the change is progressive, with the sparks, in first and third person (off: it switches at once)", "gry_cloak_transition")
	Panel:CheckBox("Camouflage: a right click that really fires also ends it (shotgun double barrel, SMG grenade, AR2 ball, frag lob; the crossbow zoom does not)", "gry_cloak_altfire")
	Panel:CheckBox("Camouflage: a click just after the weapon selector closed by itself (1.2 s after the wheel) confirms the selection instead of firing and ending the camouflage", "gry_cloak_selector_guard")
	Panel:CheckBox("Camouflage: firing out of it plays the glitch (flash, HUD jump, shake) at any energy, not only above 20 %", "gry_decloak_glitch")

	GryMod.GryHUDOptions(Panel)
	GryMod.MinimapOptions(Panel)
	GryMod.RadarZoomOptions(Panel)
	GryMod.ZoneMapOptions(Panel)

	Panel:NumSlider("Mirror Distance", "gry_xadd", -5000, 5000, 0)
	Panel:NumSlider("X Position", "gry_xdist", -5000, 5000, 0)

	GryMod.AdminOptions(Panel)

	-- the effects test window opens apart from this panel (cl_debug_window.lua); last, after the administrators' section
	local debugButton = Panel:Button("Open the effects test window")
	debugButton.GryDebugOpen = true

	debugButton.DoClick = function()
		if GryMod.DebugWindow then
			GryMod.DebugWindow.Open()
		end
	end
end

function GryMod.GryOptionschuteOptionmenu()
	spawnmenu.AddToolMenuOption("Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute)
end

hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)
