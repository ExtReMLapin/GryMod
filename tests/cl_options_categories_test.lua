-- Tests of the layout of the options menus (cl_options.lua, cl_options_radar.lua), GLuaTest format, client realm. The Config menu and the Radar and map menu are
-- made of folding categories (one subject each), every control has a SHORT label (a long one is cut by the panel) and its explanation sits under it in a small
-- wrapped text. None of the settings was lost on the way, and opening a menu writes nothing.

-- the controls of a panel as "kind:convar" (sorted): what the menus held before they were put in categories (listed by hand from the game, 2026-11-22),
-- and the movement speeds choice of the server section (a third combo box, 2026-11-22)
local CONFIG = [[binder
binder
box:gry_binoculars_aim
box:gry_binoculars_horizon
box:gry_binoculars_mood
box:gry_binoculars_silhouette
box:gry_binoculars_sounds
box:gry_binoculars_stages
box:gry_binoculars_sway
box:gry_binoculars_tag
box:gry_binoculars_vignette
box:gry_binoculars_vision
box:gry_boot_every_spawn
box:gry_cloak_altfire
box:gry_cloak_fx
box:gry_cloak_lines
box:gry_cloak_refract
box:gry_cloak_selector_guard
box:gry_cloak_shader
box:gry_cloak_transition
box:gry_decloak_glitch
box:gry_grenade_los
box:gry_grenade_own_warn
box:gry_hud
box:gry_hud_binoculars
box:gry_hud_boot
box:gry_hud_crosshair
box:gry_hud_damage
box:gry_hud_damagefx
box:gry_hud_energy_smooth
box:gry_hud_grenade
box:gry_hud_grenade_edge
box:gry_hud_hit
box:gry_hud_quickmenu
box:gry_hud_status
box:gry_icon_reboot
box:gry_malfunction_empty
box:gry_menu_keep_highlight
box:gry_menu_pointer_film
box:gry_menu_ring_film
box:gry_screenfx
box:gry_sound_regen
box:gry_sounds
box:gry_underwater_fx
box:gry_zoom_cancel_weapon
box:gry_zoom_follow_fov
box:gry_zoom_own
button:Open the effects test window
button:Switch every element back on
combo:?
combo:?
combo:?
mixer
mixer
mixer
slider:gry_grenade_range
slider:gry_hud_crosshair_style
slider:gry_sound_volume
slider:gry_xadd
slider:gry_xdist
slider:gry_zoom_tap_ms]]

local RADAR = [[box:gry_hud_radar
box:gry_hud_radarhex
box:gry_hud_radarunits
box:gry_minimap
box:gry_minimap_definition_auto
box:gry_minimap_preload
box:gry_minimap_preload_around
box:gry_minimap_veil_discovery
box:gry_radar_autozoom
box:gry_zonemap_debug
box:gry_zonemap_debug_edges
box:gry_zonemap_debug_faces
box:gry_zonemap_debug_in
box:gry_zonemap_debug_out
button:Clear the minimap cache
button:Delete and remake the in/out map
combo:gry_minimap_tile
slider:gry_minimap_below
slider:gry_minimap_budget_ms
slider:gry_minimap_cache_mb
slider:gry_minimap_definition
slider:gry_minimap_opacity
slider:gry_minimap_outside
slider:gry_radar_range
slider:gry_radar_zoom_delay
slider:gry_radar_zoom_foot
slider:gry_radar_zoom_indoor
slider:gry_radar_zoom_vehicle
slider:gry_zonemap_debug_range]]

local CONFIG_CATEGORIES = {"Keys", "HUD", "HUD colours", "Quick menu and start-up", "Grenade warning", "Binoculars", "Suit and camouflage", "Sounds", "Server (administrators only)", "Development"}
local RADAR_CATEGORIES = {"Radar and compass", "Minimap", "Minimap speed and cache", "Automatic zoom", "In/out map", "Server (administrators only)"}

-- the longest text a panel can show without cutting it, in characters (a check box: its box takes a part of the width; a slider: its label has a third of it)
local MAX_BOX, MAX_SLIDER, MAX_BUTTON = 46, 32, 40

local function walk(panel, found)
	found = found or {}

	for _, child in ipairs(panel:GetChildren()) do
		found[#found + 1] = child
		walk(child, found)
	end

	return found
end

local function signature(panel)
	local out = {}

	for _, c in ipairs(walk(panel)) do
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
		elseif class == "DButton" and c:GetText() ~= "" and not c.Header then
			out[#out + 1] = "button:" .. c:GetText()
		end
	end

	table.sort(out)

	return table.concat(out, "\n")
end

-- the folding categories of a panel, in the order they are shown: their titles
local function categories(panel)
	local out = {}

	for _, c in ipairs(walk(panel)) do
		if c.ClassName == "ControlPanel" and c.Header then
			out[#out + 1] = c.Header:GetText()
		end
	end

	return out
end

local function text(list)
	return table.concat(list, " | ")
end

-- builds `builder` on a panel with RunConsoleCommand recorded, calls fn(panel, writes), always puts everything back
local function with(builder, fn)
	local writes = {}
	local realRun = RunConsoleCommand
	RunConsoleCommand = function(name, value) writes[#writes + 1] = tostring(name) .. "=" .. tostring(value) end

	local panel = vgui.Create("ControlPanel")
	local ok, err = pcall(function()
		builder(panel)
		fn(panel, writes)
	end)

	RunConsoleCommand = realRun
	panel:Remove()

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod options menus: categories and short labels (client)",
	cases = {
		{
			-- breaks if: a setting of the old menus is dropped, bound to another convar, or added without being listed here
			name = "the Config menu still holds every control it held before, bound to the same settings",
			func = function()
				with(GryMod.GryOptionschute, function(panel)
					expect(signature(panel)).to.equal(CONFIG)
				end)
			end
		},
		{
			name = "the Radar and map menu still holds every control it held before, bound to the same settings",
			func = function()
				with(GryMod.RadarOptionsPanel, function(panel)
					expect(signature(panel)).to.equal(RADAR)
				end)
			end
		},
		{
			-- breaks if: the settings are not grouped by subject, a category is renamed or moved, or a menu goes back to one long column
			name = "the Config menu is made of the folding categories, in this order",
			func = function()
				with(GryMod.GryOptionschute, function(panel)
					expect(text(categories(panel))).to.equal(text(CONFIG_CATEGORIES))
				end)
			end
		},
		{
			name = "the Radar and map menu is made of the folding categories, in this order",
			func = function()
				with(GryMod.RadarOptionsPanel, function(panel)
					expect(text(categories(panel))).to.equal(text(RADAR_CATEGORIES))
				end)
			end
		},
		{
			-- breaks if: a control is put on the panel itself, outside every category (it would sit loose between two folds)
			name = "every setting is inside a category: nothing loose on the panel",
			func = function()
				for _, builder in ipairs({GryMod.GryOptionschute, GryMod.RadarOptionsPanel}) do
					with(builder, function(panel)
						for _, c in ipairs(walk(panel)) do
							local class = c.ClassName

							if class == "DCheckBoxLabel" or class == "DNumSlider" or class == "DComboBox" or class == "DBinder" or class == "DColorMixer" then
								local p, inside = c:GetParent(), false

								while p and p ~= panel do
									if p.ClassName == "ControlPanel" then
										inside = true

										break
									end

									p = p:GetParent()
								end

								expect(inside).to.beTrue()
							end
						end
					end)
				end
			end
		},
		{
			-- breaks if: a label is long again: the panel cuts what does not fit (the explanation goes in the help text under the control)
			name = "every check box, slider and button has a short label: the long explanations are in the wrapped text under them",
			func = function()
				local tooLong = {}

				for _, builder in ipairs({GryMod.GryOptionschute, GryMod.RadarOptionsPanel}) do
					with(builder, function(panel)
						for _, c in ipairs(walk(panel)) do
							local class, label, max = c.ClassName, nil, nil

							if class == "DCheckBoxLabel" then
								label, max = c:GetText(), MAX_BOX
							elseif class == "DNumSlider" then
								label, max = c:GetText(), MAX_SLIDER
							elseif class == "DButton" and not c.Header and not c.Button then
								label, max = c:GetText(), MAX_BUTTON
							end

							if label and #label > max then
								tooLong[#tooLong + 1] = #label .. " > " .. max .. ": " .. label
							end
						end
					end)
				end

				expect(#tooLong == 0 and "" or table.concat(tooLong, "\n")).to.equal("")
			end
		},
		{
			-- breaks if: building a menu writes a setting (a category opening, a control created with a value)
			name = "building the menus writes nothing",
			func = function()
				for _, builder in ipairs({GryMod.GryOptionschute, GryMod.RadarOptionsPanel}) do
					with(builder, function(_, writes)
						expect(table.concat(writes, ",")).to.equal("")
					end)
				end
			end
		},
		{
			-- breaks if: a category is built empty (a title with nothing under it)
			name = "no category is empty",
			func = function()
				for _, builder in ipairs({GryMod.GryOptionschute, GryMod.RadarOptionsPanel}) do
					with(builder, function(panel)
						for _, c in ipairs(walk(panel)) do
							if c.ClassName == "ControlPanel" and c.Header then
								local controls = 0

								for _, inner in ipairs(walk(c)) do
									local class = inner.ClassName

									if class == "DCheckBoxLabel" or class == "DNumSlider" or class == "DComboBox" or class == "DBinder" or class == "DColorMixer" or (class == "DButton" and not inner.Header and not inner.Button) then
										controls = controls + 1
									end
								end

								expect(controls > 0).to.beTrue()
							end
						end
					end)
				end
			end
		}
	}
}
