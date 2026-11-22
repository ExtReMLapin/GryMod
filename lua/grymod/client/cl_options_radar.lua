-- The Radar and map menu of the options: a second entry of the GryMod category (Options tab), next to Config. It holds everything about the radar, the
-- compass and the maps, which was in the Config menu: the two HUD switches of the radar, the minimap, the automatic zoom, the in/out map, and the
-- settings of the server that touch them.
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
			form:CheckBox(option.label, "gry_hud_" .. option.name)
		end
	end
end

-- The settings of the server about the radar and the in/out map, for the administrators only: four check boxes (a request to the server each) and the
-- button that deletes the in/out map and makes it again (the server checks the right again).
local function serverOptions(Panel)
	local form = GryMod.OptionsCategory(Panel, "Server (administrators only)")

	GryMod.AdminUI.Section(Panel, "Server (administrators only)", form)

	GryMod.AdminOption(Panel, "Allies in blue from the start", "gry_radar_allies_always", "bool", {into = form, help = "NPCs that like you. Off: they show only when alerted, fighting or scanned."})
	GryMod.AdminOption(Panel, "Vehicles and mines once scanned", "gry_radar_objects", "bool", {into = form, help = "Vehicles and Combine mines show on the radar once the binoculars have scanned them."})
	GryMod.AdminOption(Panel, "The server makes the in/out map", "gry_zonemap", "bool", {into = form, help = "The automatic zoom and other features use it."})
	GryMod.AdminOption(Panel, "In/out map from the navigation mesh", "gry_zonemap_navmesh", "bool", {into = form, help = "Off: it is made from the AI node graph."})

	local reset = GryMod.AdminOption(Panel, "Delete and remake the in/out map", nil, "action", {
		into = form,
		message = "gry_zonemap_reset",
		confirm = "Delete the in/out map of this map and make it again? The server computes it again from the map's navigation mesh or its node graph (the box above); the automatic zoom uses its own rays meanwhile."
	})

	reset.GryZoneMapReset = true
end

-- The menu, in this order: the title, then the categories: the HUD switches of the radar, the minimap and its speed and cache (with the cache button), the
-- automatic zoom, the in/out map, the server.
function GryMod.RadarOptionsPanel(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Radar and map"
	})

	radarHUDSwitches(Panel)

	local speed = GryMod.MinimapOptions(Panel)

	local clear = GryMod.ActionButton(speed, "Clear the minimap cache", function()
		GryMod.ClearMinimapCache()
	end, "Clear the minimap cache of this level? The map is made again as you play.")

	clear.GryMinimapClear = true

	GryMod.RadarZoomOptions(Panel)
	GryMod.ZoneMapOptions(Panel)

	serverOptions(Panel)
end
