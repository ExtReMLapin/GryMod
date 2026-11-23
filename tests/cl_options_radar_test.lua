-- Tests of the Radar and map menu of the options (GryMod.RadarOptionsPanel, cl_options_radar.lua), GLuaTest format, client realm. The menu is a second
-- entry of the GryMod category of the Options tab; it holds everything about the radar, the compass and the maps (taken out of the Config menu).
-- An action is a BUTTON, a toggle (an on/off state) is a check box: the two actions (clear the minimap cache, delete and make the in/out map again) are
-- the only two buttons of the menu, and they ask first (GryMod.Confirm); nothing that acts as a button is a check box.
-- The settings of the server are check boxes that never write a convar: they send ONE net message, and are disabled for a player who is not an
-- administrator (the server validates the right again, tests/sv_server_options_test.lua).
-- Every stand-in (spawnmenu.AddToolMenuOption, RunConsoleCommand, GryMod.Confirm, the admin status, the transports) is put back in afterEach inside a
-- pcall, also when a case failed.

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

local TITLES = {
	["GryMod Radar and map"] = true,
	["Radar and compass"] = true,
	["Minimap"] = true,
	["Minimap speed and cache"] = true,
	["Map tile size (pixels)"] = true,
	["Automatic zoom"] = true,
	["In/out map"] = true,
	["Server (administrators only)"] = true
}

-- every control of the menu in the order it was made: "label:<title>" (the titles of the sections only), "box:<convar>", "slider:<convar>",
-- "combo:<convar>", "button:<text>" (a button that is not the knob of a slider), "admin:<name>" (the controls of GryMod.AdminOption)
local function markers(panel)
	local byControl = {}

	for name, control in pairs(panel.GryAdminControls or {}) do
		byControl[control] = name
	end

	local order = {}

	for _, p in ipairs(walk(panel)) do
		if byControl[p] then
			order[#order + 1] = "admin:" .. byControl[p]
		elseif p.ClassName == "ControlPanel" and p.Header and TITLES[p.Header:GetText()] then
			-- a folding category (cl_options.lua): its title is the header
			order[#order + 1] = "label:" .. p.Header:GetText()
		elseif p.ClassName == "DLabel" and TITLES[p:GetText()] then
			local parent = p:GetParent()

			if parent and parent.ClassName ~= "DCheckBoxLabel" and parent.ClassName ~= "DNumSlider" then
				order[#order + 1] = "label:" .. p:GetText()
			end
		elseif p.ClassName == "DNumSlider" and p.Scratch then
			order[#order + 1] = "slider:" .. tostring(p.Scratch:GetTable().m_strConVar)
		elseif p.ClassName == "DCheckBoxLabel" and p.Button then
			order[#order + 1] = "box:" .. tostring(p.Button:GetTable().m_strConVar)
		elseif p.ClassName == "DButton" and p:GetParent().ClassName ~= "DSlider" then
			-- the knob of a slider is a DButton made by the slider itself: not a control of the menu
			order[#order + 1] = "button:" .. p:GetText()
		elseif p.ClassName == "DComboBox" then
			order[#order + 1] = "combo:" .. tostring(p.GryConVar)
		end
	end

	return order
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

local function actionBox(panel, flag)
	for _, p in ipairs(walk(panel)) do
		if p[flag] then
			return p
		end
	end
end

local function asAdmin(isAdmin, fn)
	local meta = FindMetaTable("Player")
	local real = meta.IsAdmin
	meta.IsAdmin = function() return isAdmin end
	local ok, err = pcall(fn)
	meta.IsAdmin = real

	if not ok then
		error(err, 0)
	end
end

local SERVER_BOXES = {"gry_radar_allies_always", "gry_radar_objects", "gry_radar_pings", "gry_radar_detect", "gry_radar_teammates", "gry_zonemap", "gry_zonemap_navmesh"}

-- what must not be in the Config menu any more: the settings of the radar, the compass and the maps
local RADAR_CONVARS = {
	"gry_hud_radar", "gry_hud_radarunits", "gry_hud_radarhex", "gry_hud_radarmarkers", "gry_hud_radarobjectives", "gry_hud_radarpings", "gry_minimap", "gry_minimap_definition_auto", "gry_minimap_definition", "gry_minimap_opacity",
	"gry_minimap_below", "gry_minimap_outside", "gry_minimap_cache_mb", "gry_minimap_tile", "gry_minimap_budget_ms", "gry_radar_range",
	"gry_radar_autozoom", "gry_radar_zoom_vehicle", "gry_radar_zoom_foot", "gry_radar_zoom_indoor", "gry_radar_zoom_delay", "gry_zonemap_debug",
	"gry_zonemap_debug_range", "gry_zonemap_debug_in", "gry_zonemap_debug_out", "gry_zonemap_debug_faces", "gry_zonemap_debug_edges", "gry_radar_allies_always", "gry_radar_objects", "gry_radar_pings", "gry_radar_detect", "gry_radar_teammates", "gry_zonemap", "gry_zonemap_navmesh"
}

return {
	groupName = "GryMod Radar and map menu",
	beforeEach = function(state)
		state.panel = nil
		state.realRun = RunConsoleCommand
		state.realConfirm = GryMod.Confirm
		state.realAdd = notification and notification.AddLegacy
		state.realCache = GryMod.Minimap and GryMod.Minimap.Cache
		state.realGen = GryMod.Minimap and GryMod.Minimap.Gen
		state.realSendMessage = GryMod.AdminUI.SendMessage
		state.realTransport = GryMod.AdminUI.Transport
		state.realAddOption = spawnmenu.AddToolMenuOption
		state.writes = {}
		state.asked = {}
		state.answer = true
		state.messages = {}
		state.notices = {}

		RunConsoleCommand = function(name, value)
			state.writes[#state.writes + 1] = tostring(name):lower() .. "=" .. tostring(value)
		end

		GryMod.Confirm = function(text, onYes)
			state.asked[#state.asked + 1] = tostring(text)

			if state.answer then
				onYes()
			end
		end

		if notification then
			notification.AddLegacy = function(text)
				state.notices[#state.notices + 1] = tostring(text)
			end
		end

		GryMod.AdminUI.SendMessage = function(name)
			state.messages[#state.messages + 1] = name
		end
		GryMod.AdminUI.Transport = function(name, value)
			state.messages[#state.messages + 1] = name .. "=" .. value
		end
	end,
	afterEach = function(state)
		pcall(function()
			RunConsoleCommand = state.realRun
			GryMod.Confirm = state.realConfirm
			spawnmenu.AddToolMenuOption = state.realAddOption
			GryMod.AdminUI.SendMessage = state.realSendMessage
			GryMod.AdminUI.Transport = state.realTransport

			if notification then
				notification.AddLegacy = state.realAdd
			end

			if GryMod.Minimap then
				GryMod.Minimap.Cache = state.realCache
				GryMod.Minimap.Gen = state.realGen
			end

			if state.panel and IsValid(state.panel) then
				state.panel:Remove()
			end
		end)
	end,
	cases = {
		{
			-- breaks if: the function or the file is missing, or the entry is not added next to Config in the same category
			name = "the menu is a second entry of the GryMod category, 'Radar and map', added when the tool menu is populated, and Config is still there",
			func = function(state)
				expect(isfunction(GryMod.RadarOptionsPanel)).to.beTrue()

				local added = {}

				spawnmenu.AddToolMenuOption = function(tab, category, name, label, command, config, builder)
					added[#added + 1] = {tab = tab, category = category, name = name, label = label, command = command, config = config, builder = builder}
				end

				local ok, err = pcall(GryMod.GryOptionschuteOptionmenu)

				spawnmenu.AddToolMenuOption = state.realAddOption

				if not ok then error(err, 0) end

				expect(#added).to.equal(2)
				expect(added[1].tab).to.equal("Options")
				expect(added[1].category).to.equal("GryMod")
				expect(added[1].name).to.equal("Config")
				expect(added[1].label).to.equal("Config it !")
				expect(added[1].builder).to.equal(GryMod.GryOptionschute)
				expect(added[2].tab).to.equal("Options")
				expect(added[2].category).to.equal("GryMod")
				expect(added[2].name).to.equal("Radar")
				expect(added[2].label).to.equal("Radar and map")
				expect(added[2].builder).to.equal(GryMod.RadarOptionsPanel)

				-- the one hook of the tool menu is the function that makes both
				expect(hook.GetTable().PopulateToolMenu.PopulateToolMenu).to.equal(GryMod.GryOptionschuteOptionmenu)
			end
		},
		{
			-- breaks if: a control is moved, left out or put in another place
			name = "the menu has, in this order: the title, the three HUD switches of the radar, the Minimap section, the cache button, the automatic zoom, the in/out map, then the server section",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local expected = {
					"label:GryMod Radar and map",
					"label:Radar and compass",
					"box:gry_hud_radar",
					"box:gry_hud_radarunits",
					"box:gry_hud_radarhex",
					"box:gry_hud_radarmarkers",
					"box:gry_hud_radarobjectives",
					"box:gry_hud_radarpings",
					"label:Minimap",
					"box:gry_minimap",
					"slider:gry_radar_range",
					"box:gry_minimap_definition_auto",
					"slider:gry_minimap_definition",
					"slider:gry_minimap_opacity",
					"slider:gry_minimap_below",
					"slider:gry_minimap_outside",
					-- the two preload boxes were added to the menu without this list (red since then); the third is the discovery mode's
					"label:Minimap speed and cache",
					"box:gry_minimap_preload",
					"box:gry_minimap_preload_around",
					"box:gry_minimap_veil_discovery",
					"slider:gry_minimap_cache_mb",
					"label:Map tile size (pixels)",
					"combo:gry_minimap_tile",
					"slider:gry_minimap_budget_ms",
					"button:Clear the minimap cache",
					"label:Automatic zoom",
					"box:gry_radar_autozoom",
					"slider:gry_radar_zoom_vehicle",
					"slider:gry_radar_zoom_foot",
					"slider:gry_radar_zoom_indoor",
					"slider:gry_radar_zoom_delay",
					"label:In/out map",
					"box:gry_zonemap_debug",
					"box:gry_zonemap_debug_in",
					"box:gry_zonemap_debug_out",
					"box:gry_zonemap_debug_faces",
					"box:gry_zonemap_debug_edges",
					"slider:gry_zonemap_debug_range",
					"label:Server (administrators only)",
					"admin:gry_radar_allies_always",
					"admin:gry_radar_objects",
					"admin:gry_radar_pings",
					"admin:gry_radar_detect",
					"admin:gry_radar_teammates",
					"admin:gry_zonemap",
					"admin:gry_zonemap_navmesh",
					"admin:action:gry_zonemap_reset"
				}

				expect(table.concat(markers(state.panel), "\n")).to.equal(table.concat(expected, "\n"))
			end
		},
		{
			-- breaks if: the source setting is a slider or a convar control, has another label, or is placed anywhere but right after gry_zonemap (it is asked through the server)
			name = "the in/out map source is a check box asked through the server (no convar written from the client), labelled as agreed, right after the gry_zonemap check box",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local control = state.panel.GryAdminControls["gry_zonemap_navmesh"]

				expect(control ~= nil).to.beTrue()
				expect(control.ClassName).to.equal("DCheckBoxLabel")
				expect(control:GetText()).to.equal("In/out map from the navigation mesh")
				expect(control.Button:GetTable().m_strConVar).to.beNil()

				local order = markers(state.panel)

				expect(indexOf(order, "admin:gry_zonemap_navmesh")).to.equal(indexOf(order, "admin:gry_zonemap") + 1)
			end
		},
		{
			-- breaks if: the three switches are built with another label, or not from the list of the HUD elements
			name = "the three HUD switches of the radar are the ones of the HUD element list, with its labels and the same convars",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				for _, name in ipairs({"radar", "radarunits", "radarhex"}) do
					local option = GryMod.HUDOptions.Find(name)
					local found

					for _, p in ipairs(walk(state.panel)) do
						if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == "gry_hud_" .. name then
							found = p
						end
					end

					expect(found ~= nil).to.beTrue()
					expect(found:GetText()).to.equal(option.label)
				end
			end
		},
		{
			-- breaks if: a box is bound to the wrong convar, has another label, is missing, or is placed after the distance slider or before the debug box
			name = "the four in/out map debug check boxes (IN, OUT, faces, edges) are bound to their convars, labelled as agreed, in this order right after the debug check box and before the distance slider",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local labels = {
					gry_zonemap_debug_in = "Show the IN zones (indoor, red)",
					gry_zonemap_debug_out = "Show the OUT zones (outdoor, green)",
					gry_zonemap_debug_faces = "Draw the faces",
					gry_zonemap_debug_edges = "Draw the edges"
				}

				for name, text in pairs(labels) do
					local found

					for _, p in ipairs(walk(state.panel)) do
						if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == name then
							found = p
						end
					end

					expect(found ~= nil).to.beTrue()
					expect(found:GetText()).to.equal(text)
				end

				local order = markers(state.panel)
				local debug = indexOf(order, "box:gry_zonemap_debug")

				expect(indexOf(order, "box:gry_zonemap_debug_in")).to.equal(debug + 1)
				expect(indexOf(order, "box:gry_zonemap_debug_out")).to.equal(debug + 2)
				expect(indexOf(order, "box:gry_zonemap_debug_faces")).to.equal(debug + 3)
				expect(indexOf(order, "box:gry_zonemap_debug_edges")).to.equal(debug + 4)
				expect(indexOf(order, "slider:gry_zonemap_debug_range")).to.equal(debug + 5)
			end
		},
		{
			-- breaks if: the slider is bound to another convar, has other limits or another label, or is a check box
			name = "the in/out map debug distance is a slider on gry_zonemap_debug_range, 20 to 300 metres, right after the debug check boxes",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local slider

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DNumSlider" and p.Scratch and p.Scratch:GetTable().m_strConVar == "gry_zonemap_debug_range" then
						slider = p
					end
				end

				expect(slider ~= nil).to.beTrue()
				expect(slider:GetText()).to.equal("Display distance (m)")
				expect(slider:GetMin()).to.equal(20)
				expect(slider:GetMax()).to.equal(300)
				expect(slider:GetDecimals()).to.equal(0)

				local order = markers(state.panel)

				expect(indexOf(order, "slider:gry_zonemap_debug_range")).to.equal(indexOf(order, "box:gry_zonemap_debug_edges") + 1)
			end
		},
		{
			-- breaks if: an action is made as a check box again, a button is added that is not one of the two actions, or a toggle is made as a button
			name = "the two actions are the only two buttons of the menu (besides the knobs of the sliders), and nothing that acts as a button is a check box; for an administrator and for the others",
			func = function(state)
				for _, isAdmin in ipairs({true, false}) do
					asAdmin(isAdmin, function()
						local panel = vgui.Create("ControlPanel")
						state.panel = panel
						GryMod.RadarOptionsPanel(panel)

						local buttons, flags = {}, {}

						for _, p in ipairs(walk(panel)) do
							if p.ClassName == "DButton" and p:GetParent().ClassName ~= "DSlider" then
								buttons[#buttons + 1] = p:GetText()
								flags[#flags + 1] = (p.GryMinimapClear and "clear" or "") .. (p.GryZoneMapReset and "reset" or "")
							elseif p.ClassName == "DCheckBoxLabel" then
								-- a check box is a setting: a convar of the player, or one of the four settings of the server
								expect(p.GryMinimapClear).to.beNil()
								expect(p.GryZoneMapReset).to.beNil()

								if not p.Button:GetTable().m_strConVar then
									local isServerBox = false

									for _, name in ipairs(SERVER_BOXES) do
										if panel.GryAdminControls[name] == p then
											isServerBox = true
										end
									end

									expect(isServerBox).to.beTrue()
								end
							end
						end

						expect(table.concat(buttons, "|")).to.equal("Clear the minimap cache|Delete and remake the in/out map")
						expect(table.concat(flags, "|")).to.equal("clear|reset")

						panel:Remove()
						state.panel = nil
					end)
				end
			end
		},
		{
			-- breaks if: the menu writes a convar or sends a message when it is built
			name = "opening the menu writes nothing: no console command, no message, no question, no convar changed (the two action buttons only wait for a click)",
			func = function(state)
				local before = {}

				for _, name in ipairs(RADAR_CONVARS) do
					before[name] = GetConVar(name):GetString()
				end

				asAdmin(true, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)
				end)

				expect(#state.writes).to.equal(0)
				expect(#state.messages).to.equal(0)
				expect(#state.asked).to.equal(0)

				for _, name in ipairs(RADAR_CONVARS) do
					expect(GetConVar(name):GetString()).to.equal(before[name])
				end

				expect(actionBox(state.panel, "GryMinimapClear").ClassName).to.equal("DButton")
				expect(actionBox(state.panel, "GryZoneMapReset").ClassName).to.equal("DButton")
			end
		},
		{
			-- breaks if: a radar control stays in the Config menu
			name = "the Config menu has no radar, compass or map control any more, only the line that says where they went; the HUD switch and the other elements stay",
			func = function(state)
				state.panel = vgui.Create("ControlPanel")
				asAdmin(true, function()
					GryMod.GryOptionschute(state.panel)
				end)

				local convars = {}

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DCheckBoxLabel" and p.Button then
						convars[p.Button:GetTable().m_strConVar or "none"] = true
					elseif p.ClassName == "DNumSlider" and p.Scratch then
						convars[tostring(p.Scratch:GetTable().m_strConVar)] = true
					elseif p.ClassName == "DComboBox" and p.GryConVar then
						convars[p.GryConVar] = true
					end
				end

				for _, name in ipairs(RADAR_CONVARS) do
					expect(convars[name]).to.beNil()
				end

				for name in pairs(state.panel.GryAdminControls or {}) do
					for _, radar in ipairs(SERVER_BOXES) do
						expect(name ~= radar).to.beTrue()
					end

					expect(name ~= "action:gry_zonemap_reset").to.beTrue()
				end

				local lines = {}

				for _, p in ipairs(walk(state.panel)) do
					if p.ClassName == "DLabel" then
						lines[p:GetText()] = true
					end
				end

				expect(lines["Radar, compass and map options are in the Radar and map menu."]).to.beTrue()
				expect(lines["The radar range slider is in the Minimap section."]).to.beNil()
				expect(lines["Minimap"]).to.beNil()
				expect(lines["Automatic zoom"]).to.beNil()
				expect(lines["In/out map"]).to.beNil()

				-- what stays
				expect(convars["gry_hud"]).to.beTrue()
				expect(convars["gry_hud_status"]).to.beTrue()
				expect(convars["gry_hud_crosshair"]).to.beTrue()
				expect(convars["gry_grenade_range"]).to.beTrue()
				expect(convars["gry_malfunction"] == nil).to.beTrue() -- an admin control: no convar in the box
				expect(state.panel.GryAdminControls["gry_malfunction"] ~= nil).to.beTrue()
			end
		},
		{
			-- breaks if: the helper makes a check box, writes a setting, or runs the action without asking
			name = "ActionButton: a button tied to no setting; a click asks, on yes it runs the action, on no it does not; with no question given it asks the label and a question mark",
			func = function(state)
				expect(isfunction(GryMod.ActionButton)).to.beTrue()
				expect(GryMod.ActionCheckBox).to.beNil()

				state.panel = vgui.Create("ControlPanel")

				local ran = 0
				local button = GryMod.ActionButton(state.panel, "Do the thing", function() ran = ran + 1 end, "Really do the thing?")

				expect(button.ClassName).to.equal("DButton")
				expect(button:GetText()).to.equal("Do the thing")
				expect(#state.asked).to.equal(0)
				expect(ran).to.equal(0)

				state.answer = false
				button:DoClick()
				expect(#state.asked).to.equal(1)
				expect(state.asked[1]).to.equal("Really do the thing?")
				expect(ran).to.equal(0)

				state.answer = true
				button:DoClick()
				expect(#state.asked).to.equal(2)
				expect(ran).to.equal(1)

				-- no question given: the label and a question mark
				local plain = GryMod.ActionButton(state.panel, "Plain", function() ran = ran + 1 end)
				plain:DoClick()
				expect(state.asked[3]).to.equal("Plain?")
				expect(ran).to.equal(2)

				expect(#state.writes).to.equal(0)
			end
		},
		{
			-- breaks if: the cache button runs without asking, ignores the answer, or is not exposed as GryMod.ClearMinimapCache
			name = "the 'Clear the minimap cache' button asks first, clears the cache of this level only on yes, and tells the player",
			func = function(state)
				expect(isfunction(GryMod.ClearMinimapCache)).to.beTrue()

				local cleared = {}

				GryMod.Minimap.Cache = {
					Key = function() return "gm_test_key" end,
					Clear = function(key) cleared[#cleared + 1] = key return true end
				}
				GryMod.Minimap.Gen = {Cancel = function() end}

				state.panel = vgui.Create("ControlPanel")
				GryMod.RadarOptionsPanel(state.panel)

				local box = actionBox(state.panel, "GryMinimapClear")

				expect(box ~= nil).to.beTrue()
				expect(box.ClassName).to.equal("DButton")
				expect(box:GetText()).to.equal("Clear the minimap cache")

				state.answer = false
				box:DoClick()
				expect(#state.asked).to.equal(1)
				expect(string.find(state.asked[1], "minimap cache", 1, true) ~= nil).to.beTrue()
				expect(#cleared).to.equal(0)

				state.answer = true
				box:DoClick()
				expect(#state.asked).to.equal(2)
				expect(#cleared).to.equal(1)
				expect(cleared[1]).to.equal("gm_test_key")
				expect(#state.notices).to.equal(1)
				expect(#state.writes).to.equal(0)
				expect(#state.messages).to.equal(0)
			end
		},
		{
			-- breaks if: the button sends without asking, or sends on "no", or sends twice
			name = "the 'Delete the in/out map' button: an administrator clicks it, it asks first, on no nothing is sent, on yes gry_zonemap_reset goes once",
			func = function(state)
				asAdmin(true, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)

					local box = state.panel.GryAdminControls["action:gry_zonemap_reset"]

					expect(box ~= nil).to.beTrue()
					expect(box.ClassName).to.equal("DButton")
					expect(box:GetText()).to.equal("Delete and remake the in/out map")
					expect(box:IsEnabled()).to.beTrue()
					expect(box.GryZoneMapReset).to.beTrue()

					state.answer = false
					box:DoClick()
					expect(#state.asked).to.equal(1)
					expect(string.find(state.asked[1], "Delete the in/out map of this map and make it again?", 1, true) == 1).to.beTrue()
					expect(#state.messages).to.equal(0)

					state.answer = true
					box:DoClick()
					expect(#state.asked).to.equal(2)
					expect(#state.messages).to.equal(1)
					expect(state.messages[1]).to.equal("gry_zonemap_reset")
					expect(#state.writes).to.equal(0)
				end)
			end
		},
		{
			-- breaks if: the front prediction is missing on the reset button (it stays enabled, a click that gets through asks or sends for a player who is not an admin)
			name = "for a player who is not an administrator the 'Delete the in/out map' button is disabled with the tooltip, and a click that gets through asks nothing and sends nothing",
			func = function(state)
				asAdmin(false, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)

					local box = state.panel.GryAdminControls["action:gry_zonemap_reset"]

					expect(box:IsEnabled()).to.beFalse()
					expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")

					box:DoClick() -- a click that got through the mouse
					expect(#state.asked).to.equal(0)
					expect(#state.messages).to.equal(0)
				end)
			end
		},
		{
			-- breaks if: one of the four server boxes is enabled for a player who is not an admin, or sends
			name = "for a player who is not an administrator the four server check boxes are disabled with the tooltip and send nothing; the other controls stay as they are",
			func = function(state)
				asAdmin(false, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)

					for _, name in ipairs(SERVER_BOXES) do
						local box = state.panel.GryAdminControls[name]

						expect(box ~= nil).to.beTrue()
						expect(box.ClassName).to.equal("DCheckBoxLabel")
						expect(box:IsEnabled()).to.beFalse()
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")
						expect(box.Button:GetTable().m_strConVar).to.beNil()

						box:SetValue(not box:GetChecked()) -- a change that got through the mouse
					end

					expect(#state.messages).to.equal(0)
					expect(#state.writes).to.equal(0)

					-- the client controls are not the administrators'
					expect(actionBox(state.panel, "GryMinimapClear"):IsEnabled()).to.beTrue()

					for _, p in ipairs(walk(state.panel)) do
						if p.ClassName == "DCheckBoxLabel" and p.Button and p.Button:GetTable().m_strConVar == "gry_minimap" then
							expect(p:IsEnabled()).to.beTrue()
						end
					end
				end)
			end
		},
		{
			-- breaks if: a server box does not send the white-listed name, or sends a convar write
			name = "for an administrator the four server check boxes are enabled and send the name and the value through the one net message, and no convar is written from the client",
			func = function(state)
				asAdmin(true, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)

					for _, name in ipairs(SERVER_BOXES) do
						local box = state.panel.GryAdminControls[name]
						local before = GetConVar(name):GetString()

						state.messages = {}
						expect(box:IsEnabled()).to.beTrue()
						box:SetValue(not box:GetChecked())
						expect(#state.messages).to.equal(1)
						expect(state.messages[1]).to.equal(name .. "=" .. (before == "1" and "0" or "1"))
						expect(GetConVar(name):GetString()).to.equal(before)

						-- every name is in the server's white list (the server refuses the rest)
						expect(GryMod.ServerSettings.Find(name) ~= nil).to.beTrue()
					end

					expect(#state.writes).to.equal(0)
				end)
			end
		},
		{
			-- breaks if: the status is only read when the panel is built
			name = "the menu follows the player's status live: the poll disables every administrators' control, the reset button included, when he stops being an administrator",
			func = function(state)
				local box

				asAdmin(true, function()
					state.panel = vgui.Create("ControlPanel")
					GryMod.RadarOptionsPanel(state.panel)
					box = state.panel.GryAdminControls["action:gry_zonemap_reset"]
					expect(box:IsEnabled()).to.beTrue()
				end)

				asAdmin(false, function()
					GryMod.AdminUI.Poll(state.panel, state.panel.GryAdminPolled + 1.01)
					expect(box:IsEnabled()).to.beFalse()
					expect(state.panel.GryAdminControls["gry_zonemap"]:IsEnabled()).to.beFalse()
				end)

				asAdmin(true, function()
					GryMod.AdminUI.Poll(state.panel, state.panel.GryAdminPolled + 1.01)
					expect(box:IsEnabled()).to.beTrue()
				end)
			end
		}
	}
}
