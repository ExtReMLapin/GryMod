-- The Radar and map menu of the options: a second entry of the GryMod category (Options tab), next to Config. It holds everything about the radar, the
-- compass and the maps, which was in the Config menu: the two HUD switches of the radar, the minimap, the automatic zoom, the in/out map, and the
-- settings of the server that touch them.
-- No button in it, only check boxes:
--   * a setting of the player is a check box (or a slider) bound to its convar; opening the menu writes nothing;
--   * an action is a momentary check box (GryMod.ActionCheckBox, GryMod.AdminOption kind "action"): ticking it asks "are you sure", on yes it runs the
--     action, and the box un-ticks itself at once whatever the answer (nothing is saved, no convar);
--   * a setting of the server is a check box that never writes a convar: it sends ONE net message and the server decides (cl_admin_option.lua,
--     sv_server_options.lua). The administrators' right is predicted here (the control is disabled with a tooltip for the others) and validated
--     there (GryMod.MayConfigure).
-- Cost: nothing runs by itself; the menu is built when the player opens it.

GryMod = GryMod or {}

-- A check box for an action of the player alone (no server): ticking it asks `question` (GryMod.Confirm; the label followed by a question mark when
-- none is given), on yes it runs onConfirmed(), and the box is un-ticked at once in every case. Returns the box.
function GryMod.ActionCheckBox(Panel, label, onConfirmed, question)
	local box = vgui.Create("DCheckBoxLabel", Panel)

	box:SetText(label)
	box:SetDark(true)
	Panel:AddItem(box)

	GryMod.AdminUI.Momentary(box, question or (label .. "?"), onConfirmed)

	return box
end

-- The HUD switches of the radar: the compass and radar panel, and its contacts. Same list, same labels, same settings as the other elements.
local function radarHUDSwitches(Panel)
	for _, option in ipairs(GryMod.HUDOptions.List) do
		if GryMod.RadarHUDElements[option.name] then
			Panel:CheckBox(option.label, "gry_hud_" .. option.name)
		end
	end
end

-- The settings of the server about the radar and the in/out map, for the administrators only: three check boxes (a request to the server each) and the
-- action that deletes the in/out map and makes it again (the server checks the right again).
local function serverOptions(Panel)
	GryMod.AdminUI.Section(Panel, "Server (administrators only)")

	GryMod.AdminOption(Panel, "Radar: allies (NPCs that like you) show in blue from the start (off: only when alerted, fighting or scanned)", "gry_radar_allies_always", "bool")
	GryMod.AdminOption(Panel, "Radar: vehicles and Combine mines show once the binoculars have scanned them", "gry_radar_objects", "bool")
	GryMod.AdminOption(Panel, "In/out map: the server makes it from the node graph (the automatic zoom and other features use it)", "gry_zonemap", "bool")

	local reset = GryMod.AdminOption(Panel, "Delete the in/out map and make it again", nil, "action", {
		message = "gry_zonemap_reset",
		confirm = "Delete the in/out map of this map and make it again? The server computes it again from the node graph; the automatic zoom uses its own rays meanwhile."
	})

	reset.GryZoneMapReset = true
end

-- The menu, in this order: the title, the HUD switches of the radar, the minimap (and its cache action), the automatic zoom, the in/out map, the server.
function GryMod.RadarOptionsPanel(Panel)
	Panel:AddControl("Label", {
		Text = "GryMod Radar and map"
	})

	radarHUDSwitches(Panel)

	GryMod.MinimapOptions(Panel)

	local clear = GryMod.ActionCheckBox(Panel, "Clear the minimap cache", function()
		GryMod.ClearMinimapCache()
	end, "Clear the minimap cache of this level? The map is made again as you play.")

	clear.GryMinimapClear = true

	GryMod.RadarZoomOptions(Panel)
	GryMod.ZoneMapOptions(Panel)

	serverOptions(Panel)
end
