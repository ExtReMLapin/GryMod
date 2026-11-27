-- The settings of GryMod that belong to the SERVER and that an administrator may change from the options panel: the white list, with the
-- kind and the valid values of each. Shared: the server checks every request against it (sv_server_options.lua), the panel builds its
-- Server page (and the suit's weapon effects on the Compatibility page) from the same names (cl_admin_option.lua, cl_options.lua, cl_options_radar.lua, cl_options_compat.lua).
-- A setting that is not here cannot be changed through the net message, whatever the sender.

GryMod = GryMod or {}

local Settings = {}
GryMod.ServerSettings = Settings

-- kind "bool": the text "0" or "1". Kind "choice": one of `values`.
Settings.List = {
	{name = "gry_malfunction", kind = "bool"},
	{name = "gry_grenade_armed_only", kind = "bool"},
	{name = "gry_drown_rules", kind = "bool"},
	{name = "gry_realistic_fall", kind = "bool"},
	{name = "gry_energy_net", kind = "bool"},
	{name = "gry_mechanics", kind = "choice", values = {"crysis", "classic"}},
	{name = "gry_cloak_ai", kind = "bool"},
	-- seconds of the cloak level's fade for the AI (sh_cloak_level.lua); the console takes any value from 0 to 10, the panel these
	{name = "gry_cloak_fade_seconds", kind = "choice", values = {"0", "0.5", "1", "2", "3", "5"}},
	{name = "gry_radar_allies_always", kind = "bool"},
	{name = "gry_movement", kind = "choice", values = {"0", "1", "2"}},
	{name = "gry_jump_speed_cap", kind = "choice", values = {"0", "1", "1.2", "1.5", "2"}},
	{name = "gry_radar_objects", kind = "bool"},
	{name = "gry_radar_pings", kind = "bool"},
	{name = "gry_radar_blast_rings", kind = "bool"},
	{name = "gry_radar_teammates", kind = "bool"},
	{name = "gry_radar_detect", kind = "bool"},
	{name = "gry_zonemap", kind = "bool"},
	{name = "gry_zonemap_navmesh", kind = "bool"},
	{name = "gry_health_regen", kind = "bool"},
	{name = "gry_infinite_armor", kind = "bool"},
	-- what the suit does to a weapon (sh_suit_weapons.lua); the energy of a shot in the strength mode and the speed of a reload in the speed mode are choices
	{name = "gry_suit_handling", kind = "bool"},
	{name = "gry_suit_strength_melee", kind = "bool"},
	{name = "gry_suit_strength_recoil", kind = "bool"},
	{name = "gry_suit_shot_cost", kind = "choice", values = {"0", "3.75", "7.5", "15"}},
	{name = "gry_suit_shot_cost_by_ammo", kind = "bool"},
	{name = "gry_suit_melee_cost", kind = "choice", values = {"0", "0.5", "1", "2"}},
	{name = "gry_suit_reload_rate", kind = "choice", values = {"1", "1.25", "1.5", "2"}},
	{name = "gry_objectives", kind = "bool"},
	{name = "gry_campaign_objectives", kind = "bool"},
	{name = "gry_campaign_secrets", kind = "bool"},
	{name = "gry_sv_nightvision", kind = "bool"}
}

local byName = {}

for _, setting in ipairs(Settings.List) do
	byName[setting.name] = setting
end

-- The setting of this exact name, or nil.
function Settings.Find(name)
	if not isstring(name) then
		return nil
	end

	return byName[name]
end

-- The text to store for the value (the same text), or nil when the name is not in the list or the value is not valid. A value is a string:
-- exactly what the message carries, nothing is converted.
function Settings.Validate(name, value)
	local setting = Settings.Find(name)

	if not setting or not isstring(value) then
		return nil
	end

	if setting.kind == "bool" then
		if value == "0" or value == "1" then
			return value
		end

		return nil
	end

	for _, allowed in ipairs(setting.values) do
		if value == allowed then
			return value
		end
	end

	return nil
end
