-- The Radar and map page of the options (an entry of the GryMod category, Options tab). It holds everything about the radar, the compass and the maps, in
-- tabs (cl_options_tabs.lua): the HUD switches of the radar, the minimap, the automatic zoom, the minimap cache, the in/out map and the big map. The settings of the
-- server that touch them are in a tab of the Server page.
-- An action is a BUTTON, a toggle (an on/off state) is a check box:
--   * a setting of the player is a check box (or a slider) bound to its convar; opening the menu writes nothing;
--   * an action is a button (GryMod.ActionButton, GryMod.AdminOption kind "action"): a click asks "are you sure", on yes it runs the action, on no
--     nothing happens (nothing is saved, no convar);
--   * a setting of the server is a check box that never writes a convar: it sends ONE net message and the server decides (cl_admin_option.lua,
--     sv_server_options.lua). The administrators' right is predicted here (the control is disabled with a tooltip for the others) and validated
--     there (GryMod.MayConfigure).
-- Cost: nothing runs by itself; the menu is built when the player opens it.

GryMod = GryMod or {}

-- A button for an action of the player alone (no server): a click asks `question` (GryMod.Confirm; the label followed by a question mark when none is
-- given) and on yes runs onConfirmed(). Returns the button.
function GryMod.ActionButton(Panel, label, onConfirmed, question)
	local button = vgui.Create("DButton", Panel)

	button:SetText(label)
	Panel:AddItem(button)

	button.DoClick = function()
		GryMod.Confirm(question or (label .. "?"), onConfirmed)
	end

	return button
end

-- The HUD switches of the radar: the compass and radar panel, and its contacts. Same list, same labels, same settings as the other elements.
local function radarHUDSwitches(Panel)
	local form = GryMod.OptionsCategory(Panel, "Radar and compass", true)

	for _, option in ipairs(GryMod.HUDOptions.List) do
		if GryMod.RadarHUDElements[option.name] then
			if option.helpUnder then
				GryMod.OptionBox(form, option.label, "gry_hud_" .. option.name, option.help)
			else
				form:CheckBox(option.label, "gry_hud_" .. option.name)
			end
		end
	end

	GryMod.OptionBox(form, "Compass: NE, SE, SW, NW", "gry_compass_intercardinals", "On: the compass strip also shows the four letters between N, E, S and W. Off: only N, E, S and W, as in the remaster.")

	-- the markers that the objectives and other addons put on the radar (cl_hud_radar_sources.lua): one switch for all of them
	GryMod.OptionBox(form, "Markers from objectives and addons", "gry_hud_radarmarkers", "Arrows and dots that other parts of the game put on the radar (an objective, a team mate).")
	GryMod.OptionBox(form, "Objectives on the radar", "gry_hud_radarobjectives", "The active objectives on the radar and the minimap: a glow, and an arrow on the border when the objective is beyond the radar (green for a primary one, yellow for a secondary one).")
	GryMod.OptionBox(form, "Explosion rings", "gry_hud_radarpings", "A ring on the radar at each explosion near you (a grenade, a rocket, a barrel).")
end

-- The settings of the server about the radar and the in/out map, for the administrators only: the check boxes (a request to the server each) and the
-- button that deletes the in/out map and makes it again (the server checks the right again). A tab of the Server page. `root` draws them, `Panel` looks after them.
local function serverOptions(root, Panel)
	GryMod.AdminOption(Panel, "Allies in blue from the start", "gry_radar_allies_always", "bool", {into = root, help = "NPCs that like you. Off: they show only when alerted, fighting or scanned."})
	GryMod.AdminOption(Panel, "Vehicles and mines once scanned", "gry_radar_objects", "bool", {into = root, help = "Vehicles and Combine mines show on the radar once the binoculars have scanned them."})
	GryMod.AdminOption(Panel, "Explosion rings on the radar", "gry_radar_pings", "bool", {into = root, help = "Each explosion rings the radar of the players within 250 m. Off: only the ones an addon reports."})
	GryMod.AdminOption(Panel, "Rings for any blast damage", "gry_radar_blast_rings", "bool", {into = root, help = "Explosions made with a plain blast damage (dynamite, explosives, vehicles) ring the radar too, without the addon reporting them."})
	GryMod.AdminOption(Panel, "Danger bar: hostiles that see or hear you", "gry_radar_detect", "bool", {into = root, help = "The danger bar and the hexagon also react to hostiles that have noticed you from far away, not only to the alerted ones that are on the radar."})
	GryMod.AdminOption(Panel, "Team mates on the radar", "gry_radar_teammates", "bool", {into = root, help = "In a team game, the living players of your team show on your radar."})
	GryMod.AdminOption(Panel, "The server makes the in/out map", "gry_zonemap", "bool", {into = root, help = "The automatic zoom and other features use it."})
	GryMod.AdminOption(Panel, "In/out map from the navigation mesh", "gry_zonemap_navmesh", "bool", {into = root, help = "Off: it is made from the AI node graph."})

	local reset = GryMod.AdminOption(Panel, "Delete and remake the in/out map", nil, "action", {
		into = root,
		message = "gry_zonemap_reset",
		confirm = "Delete the in/out map of this map and make it again? The server computes it again from the map's navigation mesh or its node graph (the box above); the automatic zoom uses its own rays meanwhile."
	})

	reset.GryZoneMapReset = true
end

-- The tab "Cache": the minimap's cache settings and the button that clears the cache of this level.
local function cacheOptions(root)
	local speed = GryMod.MinimapCacheOptions(root)

	local clear = GryMod.ActionButton(speed, "Clear the minimap cache", function()
		GryMod.ClearMinimapCache()
	end, "Clear the minimap cache of this level? The map is made again as you play.")

	clear.GryMinimapClear = true
end

-- The tabs of the Radar and map page, in this order (the big map adds its own, map/options.lua); the settings of the server that touch the radar are a tab of the Server page.
GryMod.AddOptionTab("radar", "Radar", radarHUDSwitches, 10)
GryMod.AddOptionTab("radar", "Minimap", function(root) GryMod.MinimapMapOptions(root) end, 20)
GryMod.AddOptionTab("radar", "Auto zoom", function(root) GryMod.RadarZoomOptions(root) end, 30)
GryMod.AddOptionTab("radar", "Cache", cacheOptions, 40)
GryMod.AddOptionTab("radar", "In/out map", function(root) GryMod.ZoneMapOptions(root) end, 50)
GryMod.AddOptionTab("server", "Radar and map", serverOptions, 40)

-- The page: title, filter, tabs.
function GryMod.RadarOptionsPanel(Panel)
	return GryMod.BuildOptionsPage(Panel, "radar")
end
