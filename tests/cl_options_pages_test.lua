-- Tests of the pages of the options menu and their tabs (cl_options_tabs.lua and the builders in cl_options.lua, cl_options_radar.lua, cl_options_compat.lua,
-- map/options.lua), GLuaTest format, client realm. The menu has five entries, each a page made of TABS (one property sheet that is as tall as the tab that is shown,
-- so that the page has no scroll bar of its own: the menu's one is the only one), with a filter field above the tabs. Every setting of the player is in exactly ONE place,
-- every setting of the server white list too, and nothing is written when a page is built. The look (nothing cut, nothing on top of something else) is checked on the
-- screenshots, not here. Each case names the change that makes it fail.

local panels

-- the property sheet of a page and the names of its tabs
local function sheetOf(panel)
	if panel.GetItems and panel.AddSheet then
		return panel
	end

	for _, child in ipairs(panel:GetChildren()) do
		local found = sheetOf(child)

		if found then
			return found
		end
	end

	return nil
end

local function tabNames(sheet)
	local names = {}

	for _, item in ipairs(sheet:GetItems()) do
		names[#names + 1] = item.Tab.GryName or item.Tab:GetText()
	end

	return table.concat(names, ",")
end

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

local function adminHolder(panel)
	while panel do
		if panel.GryAdminItem then
			return true
		end

		panel = panel:GetParent()
	end

	return false
end

local CONTROLS = {DCheckBoxLabel = true, DNumSlider = true, DComboBox = true, DBinder = true, DColorMixer = true, DButton = true}

-- the controls of the player (the ones of the server settings are left out) as "kind:convar", sorted
local function signature(panel)
	local out = {}

	for _, c in ipairs(walk(panel)) do
		if not adminHolder(c) then
			local class = c.ClassName

			if class == "DCheckBoxLabel" and c.Button and c.Button:GetTable().m_strConVar then
				out[#out + 1] = "box:" .. c.Button:GetTable().m_strConVar
			elseif class == "DNumSlider" and c.Scratch then
				out[#out + 1] = "slider:" .. tostring(c.Scratch:GetTable().m_strConVar)
			elseif class == "DComboBox" then
				out[#out + 1] = "combo:" .. tostring(c.GryConVar or "?")
			elseif class == "DBinder" then
				out[#out + 1] = "binder"
			elseif class == "DColorMixer" then
				out[#out + 1] = "mixer"
			elseif class == "DButton" and c:GetText() ~= "" and not c.Header and not c.Button and not c.GryTab then
				out[#out + 1] = "button:" .. c:GetText()
			end
		end
	end

	table.sort(out)

	return table.concat(out, "\n")
end

-- what the menus held before the rework (the old Config and Radar and map menus, as listed in cl_options_categories_test.lua of that time) plus the big map page and the
-- ARC9 box, without the server settings (they are in the white list, and checked apart): the sum of the five pages must be exactly this
local EXPECTED = [[binder
binder
binder
binder
box:gry_arc9_hide_hints
box:gry_arc9_hide_hud
box:gry_binoculars_aim
box:gry_binoculars_baseline
box:gry_binoculars_hide_weapon
box:gry_binoculars_hold_zoom
box:gry_binoculars_hologram
box:gry_binoculars_horizon
box:gry_binoculars_malfunction
box:gry_binoculars_mood
box:gry_binoculars_no_fire
box:gry_binoculars_silhouette
box:gry_binoculars_sounds
box:gry_binoculars_stages
box:gry_binoculars_sway
box:gry_binoculars_tag
box:gry_binoculars_thirdperson
box:gry_binoculars_vignette
box:gry_binoculars_vision
box:gry_binoculars_walk
box:gry_boot_every_spawn
box:gry_cloak_altfire
box:gry_cloak_foley_quiet
box:gry_cloak_fx
box:gry_cloak_lines
box:gry_cloak_refract
box:gry_cloak_selector_guard
box:gry_cloak_shader
box:gry_cloak_transition
box:gry_compass_intercardinals
box:gry_decloak_glitch
box:gry_glide_hide_hud
box:gry_glide_nv_key
box:gry_grenade_los
box:gry_grenade_own_warn
box:gry_hit_shake
box:gry_hud
box:gry_hud_bar_smooth
box:gry_hud_binoculars
box:gry_hud_boot
box:gry_hud_corners
box:gry_hud_crosshair
box:gry_hud_crosshair_weapon
box:gry_hud_damage
box:gry_hud_damagefx
box:gry_hud_energy_smooth
box:gry_hud_grenade
box:gry_hud_grenade_edge
box:gry_hud_hit
box:gry_hud_lost_backdrop
box:gry_hud_lost_centered
box:gry_hud_lost_on_death
box:gry_hud_messages
box:gry_hud_nightvision
box:gry_hud_objectives
box:gry_hud_overheat
box:gry_hud_pickups
box:gry_hud_quickmenu
box:gry_hud_radar
box:gry_hud_radarhex
box:gry_hud_radarmarkers
box:gry_hud_radarobjectives
box:gry_hud_radarpings
box:gry_hud_radarunits
box:gry_hud_status
box:gry_hud_usehint
box:gry_hud_weaponlist
box:gry_icon_reboot
box:gry_malfunction_empty
box:gry_map_chrome
box:gry_map_contacts
box:gry_map_enable
box:gry_map_finished
box:gry_map_grid
box:gry_map_waypoints
box:gry_menu_keep_highlight
box:gry_menu_pointer_film
box:gry_menu_ring_film
box:gry_menu_show_refused
box:gry_minimap
box:gry_minimap_definition_auto
box:gry_minimap_preload
box:gry_minimap_preload_around
box:gry_minimap_veil_discovery
box:gry_msg_cloak_disabled
box:gry_msg_cloak_health
box:gry_msg_killed_friend
box:gry_msg_objectives
box:gry_nightvision
box:gry_nightvision_energy
box:gry_nightvision_fx
box:gry_nightvision_hold
box:gry_nightvision_light
box:gry_nightvision_localgain
box:gry_nightvision_star
box:gry_radar_autozoom
box:gry_screenfx
box:gry_sound_cloak_loop
box:gry_sound_malfunction_loop
box:gry_sound_regen
box:gry_sounds
box:gry_underwater_fx
box:gry_usehint_feedback
box:gry_usehint_props
box:gry_zonemap_debug
box:gry_zonemap_debug_edges
box:gry_zonemap_debug_faces
box:gry_zonemap_debug_in
box:gry_zonemap_debug_out
box:gry_zoom_cancel_weapon
box:gry_zoom_follow_fov
box:gry_zoom_hide_crosshair
box:gry_zoom_own
button:Clear the minimap cache
button:Open the effects test window
button:Remove my objective points of this map
button:Switch every element back on
combo:?
combo:gry_binoculars_holo_style
combo:gry_map_loading_fx
combo:gry_minimap_tile
combo:gry_objectives_marker_mode
combo:gry_weapon_selector
mixer
mixer
mixer
slider:gry_grenade_range
slider:gry_hud_crosshair_style
slider:gry_map_zoom_cm
slider:gry_minimap_below
slider:gry_minimap_budget_ms
slider:gry_minimap_cache_mb
slider:gry_minimap_definition
slider:gry_minimap_opacity
slider:gry_minimap_outside
slider:gry_nightvision_drain
slider:gry_nightvision_recharge
slider:gry_radar_range
slider:gry_radar_zoom_delay
slider:gry_radar_zoom_foot
slider:gry_radar_zoom_indoor
slider:gry_radar_zoom_vehicle
slider:gry_sound_volume
slider:gry_usehint_delay
slider:gry_usehint_hold
slider:gry_xadd
slider:gry_xdist
slider:gry_zonemap_debug_range
slider:gry_zoom_tap_ms]]

local PAGES = {
	hud = {name = "HUD and controls", tabs = "Keys,Panels,On screen,Aim and prompts,Colours,Quick menu,Alerts,Advanced", builder = "HUDOptionsPanel"},
	suit = {name = "Suit and vision", tabs = "Suit,Camouflage,Binoculars,Scan,Zoom,Night vision,Sounds", builder = "SuitOptionsPanel"},
	radar = {name = "Radar and map", tabs = "Radar,Minimap,Auto zoom,Cache,In/out map,Big map", builder = "RadarOptionsPanel"},
	compat = {name = "Compatibility", tabs = "Suit effects,TFA,ARC9,Draconic,Other weapon bases,Glide", builder = "CompatOptionsPanel"},
	server = {name = "Server (admins)", tabs = "Suit rules,Camouflage and more,Objectives,Radar and map", builder = "ServerOptionsPanel"}
}

local ORDER = {"hud", "suit", "radar", "compat", "server"}

-- the server settings of the white list that the Compatibility page holds (the suit's effects on weapons): the others are on the Server page
local COMPAT_SETTINGS = {gry_suit_handling = true, gry_suit_reload_rate = true, gry_suit_shot_cost = true, gry_suit_shot_cost_by_ammo = true, gry_suit_melee_cost = true, gry_suit_strength_melee = true, gry_suit_strength_recoil = true}

local MAX_PER_TAB = 12

-- how many controls a tab holds (what is inside a control, the buttons of a colour mixer for one, is not counted again)
local function countControls(panel)
	local count = 0

	for _, child in ipairs(panel:GetChildren()) do
		if CONTROLS[child.ClassName] and not child.Header and not child.GryTab then
			count = count + 1
		else
			count = count + countControls(child)
		end
	end

	return count
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

local function make()
	local panel = vgui.Create("ControlPanel")

	panels[#panels + 1] = panel

	return panel
end

-- a page on a panel, with the writes recorded; returns the panel and the writes
local function build(id, isAdmin)
	local panel, writes = make(), {}
	local realRun = RunConsoleCommand

	RunConsoleCommand = function(name, value) writes[#writes + 1] = tostring(name) .. "=" .. tostring(value) end

	local ok, err = pcall(function()
		asAdmin(isAdmin ~= false, function()
			GryMod[PAGES[id].builder](panel)
		end)
	end)

	RunConsoleCommand = realRun

	if not ok then
		error(err, 0)
	end

	return panel, writes
end

return {
	groupName = "GryMod options: the pages and their tabs",
	beforeEach = function()
		panels = {}
	end,
	afterEach = function()
		for _, panel in ipairs(panels) do
			if IsValid(panel) then
				panel:Remove()
			end
		end
	end,
	cases = {
		{
			-- breaks if: a page is missing, a tab is renamed or moved, or the menu goes back to one long column
			name = "the five pages exist and each is a property sheet with these tabs, in this order",
			func = function()
				for _, id in ipairs(ORDER) do
					local panel = build(id)
					local sheet = sheetOf(panel)

					expect(sheet ~= nil).to.beTrue()
					expect(tabNames(sheet)).to.equal(PAGES[id].tabs)
				end
			end
		},
		{
			-- breaks if: an entry is added or lost, or one is not offered in the Options tab under GryMod
			name = "the menu has these five entries under GryMod, each building its page",
			func = function()
				local added = {}
				local real = spawnmenu.AddToolMenuOption

				spawnmenu.AddToolMenuOption = function(tab, category, class, name, command, config, builder) added[#added + 1] = {tab = tab, category = category, name = name, builder = builder} end

				local ok, err = pcall(GryMod.GryOptionschuteOptionmenu)

				spawnmenu.AddToolMenuOption = real

				if not ok then
					error(err, 0)
				end

				local names = {}

				for _, entry in ipairs(added) do
					expect(entry.tab).to.equal("Options")
					expect(entry.category).to.equal("GryMod")
					names[#names + 1] = entry.name
				end

				local expected = {}

				for _, id in ipairs(ORDER) do
					expected[#expected + 1] = PAGES[id].name
				end

				expect(table.concat(names, "|")).to.equal(table.concat(expected, "|"))

				for i, id in ipairs(ORDER) do
					expect(added[i].builder).to.equal(GryMod[PAGES[id].builder])
				end
			end
		},
		{
			-- breaks if: a setting of the old menus is lost, bound to another convar, shown twice or added without being listed here
			name = "the five pages together hold every control of the player once, bound to the same settings as before",
			func = function()
				local all = {}

				for _, id in ipairs(ORDER) do
					local panel = build(id)

					all[#all + 1] = signature(panel)
				end

				local lines = {}

				for _, text in ipairs(all) do
					for line in string.gmatch(text, "[^\n]+") do
						lines[#lines + 1] = line
					end
				end

				table.sort(lines)
				expect(table.concat(lines, "\n")).to.equal(EXPECTED)
			end
		},
		{
			-- breaks if: a setting of the white list is on no page, on two, or the Compatibility page loses the suit's weapon effects
			name = "every setting of the server white list is on exactly one page: the weapon effects on Compatibility, the others on Server",
			func = function()
				local found = {}

				for _, id in ipairs(ORDER) do
					local panel = build(id)

					for name in pairs(panel.GryAdminControls or {}) do
						found[name] = (found[name] or 0) + 1

						if id == "compat" then
							expect(COMPAT_SETTINGS[name] == true).to.beTrue()
						end

						if id == "server" then
							expect(COMPAT_SETTINGS[name]).to.beNil()
						end

						if id ~= "compat" and id ~= "server" then
							expect("no server setting on the page " .. id .. ": " .. name).to.equal("")
						end
					end
				end

				for _, setting in ipairs(GryMod.ServerSettings.List) do
					expect(found[setting.name]).to.equal(1)
					found[setting.name] = nil
				end

				-- what is left is the actions (a button, no setting)
				for name, count in pairs(found) do
					expect(string.sub(name, 1, 7)).to.equal("action:")
					expect(count).to.equal(1)
				end
			end
		},
		{
			-- breaks if: a server setting stays enabled for a player who is not an admin, or an admin's one is disabled
			name = "the server settings are disabled for a player who is not an admin and enabled for an admin, on both pages that hold them",
			func = function()
				for _, id in ipairs({"server", "compat"}) do
					for _, isAdmin in ipairs({false, true}) do
						local panel = build(id, isAdmin)
						local seen = 0

						for _, c in ipairs(walk(panel)) do
							if CONTROLS[c.ClassName] and adminHolder(c) then
								seen = seen + 1
								expect(c:IsEnabled()).to.equal(isAdmin)
							end
						end

						expect(seen > 0).to.beTrue()
					end
				end
			end
		},
		{
			-- breaks if: a page writes a setting while it is built (a control made with a value, a category opening)
			name = "building a page writes nothing",
			func = function()
				for _, id in ipairs(ORDER) do
					local _, writes = build(id)

					expect(table.concat(writes, ",")).to.equal("")
				end
			end
		},
		{
			-- breaks if: a tab becomes a long list again (the point of the tabs is that a tab fits the screen without a scroll bar)
			name = "no tab holds more than " .. MAX_PER_TAB .. " controls and no tab of the pages of the player is empty",
			func = function()
				for _, id in ipairs(ORDER) do
					local panel = build(id)
					local sheet = sheetOf(panel)

					for _, item in ipairs(sheet:GetItems()) do
						local count = countControls(item.Panel)

						expect(count <= MAX_PER_TAB).to.beTrue()

						if id ~= "compat" then
							expect(count > 0).to.beTrue()
						end
					end
				end
			end
		},
		{
			-- breaks if: a scroll panel is put in a page (two scroll bars, one in the other: the menu has its own) or the sheet keeps a fixed height
			name = "a page has no scroll panel of its own and its sheet is exactly as tall as the tab that is shown",
			func = function()
				for _, id in ipairs(ORDER) do
					local frame = vgui.Create("DFrame")

					panels[#panels + 1] = frame
					frame:SetSize(1000, 900)

					local panel = vgui.Create("ControlPanel", frame)

					panel:Dock(TOP)
					asAdmin(true, function()
						GryMod[PAGES[id].builder](panel)
					end)

					for _, c in ipairs(walk(panel)) do
						expect(c.ClassName ~= "DScrollPanel").to.beTrue()
					end

					local sheet = sheetOf(panel)

					for _, item in ipairs(sheet:GetItems()) do
						sheet:SetActiveTab(item.Tab)
						frame:InvalidateChildren(true)

						-- the shown tab ends under the tab strip (its position slides in when the tab changes)
						local content = item.Panel
						local bottom = item.Tab:GetTall() - 8 + content:GetTall()

						expect(sheet:GetTall() >= bottom).to.beTrue()
						expect(sheet:GetTall() <= bottom + 40).to.beTrue()
					end
				end
			end
		},
		{
			-- breaks if: the filter shows what does not match, hides what matches, does not name where the matches are, or does not bring everything back
			name = "the filter shows only the settings that match (the label or the help), counts them in the tab names and brings everything back when it is cleared",
			func = function()
				local panel = build("suit")
				local sheet = sheetOf(panel)

				expect(isfunction(GryMod.FilterOptions)).to.beTrue()

				local function holderOfBox(convar)
					for _, c in ipairs(walk(panel)) do
						if c.ClassName == "DCheckBoxLabel" and c.Button and c.Button:GetTable().m_strConVar == convar then
							local p = c

							while p:GetParent() and not p:GetParent().GryTabRoot do
								p = p:GetParent()
							end

							return p
						end
					end
				end

				local counts = GryMod.FilterOptions(panel, "scan lines")

				expect(counts["Camouflage"] >= 1).to.beTrue()
				expect(counts["Sounds"]).to.equal(0)
				expect(holderOfBox("gry_cloak_lines"):IsVisible()).to.beTrue()
				expect(holderOfBox("gry_cloak_fx"):IsVisible()).to.beFalse()
				expect(sheet:GetActiveTab().GryName).to.equal("Camouflage")

				local counts2 = GryMod.FilterOptions(panel, "night")

				expect(counts2["Night vision"] >= 1).to.beTrue()
				expect(counts2["Camouflage"]).to.equal(0)
				expect(sheet:GetActiveTab().GryName).to.equal("Night vision")

				GryMod.FilterOptions(panel, "")
				expect(holderOfBox("gry_cloak_fx"):IsVisible()).to.beTrue()
				expect(tabNames(sheet)).to.equal(PAGES.suit.tabs)
			end
		},
		{
			-- breaks if: AddOptionTab does not add a tab at the end of the page, does not replace a tab of the same name, or lets a failing tab break the others
			name = "GryMod.AddOptionTab adds a tab to a page (the way another file adds its settings), replaces one of the same name, and a tab that fails shows its error without breaking the page",
			func = function()
				expect(isfunction(GryMod.AddOptionTab)).to.beTrue()

				local ok, err = pcall(function()
					GryMod.AddOptionTab("compat", "ZZ test", function(root)
						GryMod.OptionBox(root, "A test box", "gry_hud", "Test help")
					end)

					local panel = build("compat")

					expect(tabNames(sheetOf(panel))).to.equal(PAGES.compat.tabs .. ",ZZ test")

					-- the same name again: one tab, the new content
					GryMod.AddOptionTab("compat", "ZZ test", function(root)
						GryMod.OptionBox(root, "Another box", "gry_hud_status", "Test help")
					end)

					expect(tabNames(sheetOf(build("compat")))).to.equal(PAGES.compat.tabs .. ",ZZ test")

					-- a tab that fails
					GryMod.AddOptionTab("compat", "ZZ test", function()
						error("boom")
					end)

					local realError = ErrorNoHalt

					ErrorNoHalt = function() end

					local panel2 = build("compat")

					ErrorNoHalt = realError
					expect(tabNames(sheetOf(panel2))).to.equal(PAGES.compat.tabs .. ",ZZ test")
					expect(#walk(panel2) > 10).to.beTrue()
				end)

				GryMod.RemoveOptionTab("compat", "ZZ test")

				if not ok then
					error(err, 0)
				end

				expect(tabNames(sheetOf(build("compat")))).to.equal(PAGES.compat.tabs)
			end
		},
		{
			-- breaks if: a label is long again: the panel cuts what does not fit (the explanation goes in the help text under the control)
			name = "every check box, slider and button has a short label: the long explanations are in the wrapped text under them",
			func = function()
				local tooLong = {}

				for _, id in ipairs(ORDER) do
					local panel = build(id)

					for _, c in ipairs(walk(panel)) do
						local class, label, max = c.ClassName, nil, nil

						if class == "DCheckBoxLabel" then
							label, max = c:GetText(), 46
						elseif class == "DNumSlider" then
							label, max = c:GetText(), 32
						elseif class == "DButton" and not c.Header and not c.Button and not c.GryTab then
							label, max = c:GetText(), 40
						end

						if label and #label > max then
							tooLong[#tooLong + 1] = #label .. " > " .. max .. ": " .. label
						end
					end
				end

				expect(#tooLong == 0 and "" or table.concat(tooLong, "\n")).to.equal("")
			end
		},
		{
			-- breaks if: the box of the quick menu key reminder is missing from the Keys tab, shows the setting the wrong way round, or writes when the panel opens
			name = "the Keys tab has a box for the reminder of the quick menu key: ticked when the setting is 0 (it asks), a click writes the other value, opening writes nothing",
			func = function()
				local dontAsk = GetConVar("gry_menu_key_dontask") or CreateClientConVar("gry_menu_key_dontask", "0", true, false)
				local before = dontAsk:GetString()
				local ok, err = pcall(function()
					local function find(panel)
						for _, c in ipairs(walk(panel)) do
							if c.ClassName == "DCheckBoxLabel" and c:GetText() == "Ask for the quick menu key at start" then
								return c
							end
						end
					end

					dontAsk:SetString("0")

					local panel, writes = build("hud")

					expect(table.concat(writes, ",")).to.equal("")
					expect(find(panel):GetChecked()).to.beTrue()

					dontAsk:SetString("1")
					expect(find((build("hud"))):GetChecked()).to.beFalse()

					local clicked = {}
					local realRun = RunConsoleCommand

					RunConsoleCommand = function(name, value) clicked[#clicked + 1] = name .. "=" .. tostring(value) end

					local box = find(panel)
					local pcallOk, pcallErr = pcall(function()
						box:SetValue(false)
						box:SetValue(true)
					end)

					RunConsoleCommand = realRun

					if not pcallOk then
						error(pcallErr, 0)
					end

					expect(table.concat(clicked, ",")).to.equal("gry_menu_key_dontask=1,gry_menu_key_dontask=0")
				end)

				dontAsk:SetString(before)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- breaks if: a choice of the server (the energy of a shot) is shown empty because the engine writes its number "7.500000" and the choice is "7.5"
			name = "a choice of the server whose value is a number shows the choice of the same number, whatever way the engine writes it",
			func = function()
				local convar = GetConVar("gry_suit_shot_cost")

				expect(convar ~= nil).to.beTrue()

				if tonumber(convar:GetString()) ~= 7.5 then
					expect.skip("the setting is not at its default in this game")
				end

				local panel = build("compat")

				expect(panel.GryAdminControls["gry_suit_shot_cost"]:GetValue()).to.equal("The original's (7.5)")
			end
		},
		{
			-- breaks if: a page is added with an unknown name without a word (the tab would be lost)
			name = "adding a tab to a page that does not exist is an error that names the page",
			func = function()
				local ok, err = pcall(GryMod.AddOptionTab, "no_such_page", "x", function() end)

				expect(ok).to.beFalse()
				expect(string.find(tostring(err), "no_such_page", 1, true) ~= nil).to.beTrue()
			end
		}
	}
}
