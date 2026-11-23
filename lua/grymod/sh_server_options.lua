-- The settings of GryMod that belong to the SERVER and that an administrator may change from the options panel: the white list, with the
-- kind and the valid values of each. Shared: the server checks every request against it (sv_server_options.lua), the panel builds its
-- "Server (administrators only)" section from the same names (cl_admin_option.lua, cl_options.lua).
-- A setting that is not here cannot be changed through the net message, whatever the sender.

GryMod = GryMod or {}

local Settings = {}
GryMod.ServerSettings = Settings

-- kind "bool": the text "0" or "1". Kind "choice": one of `values`.
Settings.List = {
	{name = "gry_malfunction", kind = "bool"},
	{name = "gry_grenade_armed_only", kind = "bool"},
	{name = "gry_drown_rules", kind = "bool"},
	{name = "gry_energy_net", kind = "bool"},
	{name = "gry_mechanics", kind = "choice", values = {"crysis", "classic"}},
	{name = "gry_cloak_ai", kind = "bool"},
	{name = "gry_radar_allies_always", kind = "bool"},
	{name = "gry_movement", kind = "choice", values = {"0", "1", "2"}},
	{name = "gry_radar_objects", kind = "bool"},
	{name = "gry_radar_pings", kind = "bool"},
	{name = "gry_radar_teammates", kind = "bool"},
	{name = "gry_zonemap", kind = "bool"},
	{name = "gry_zonemap_navmesh", kind = "bool"},
	{name = "gry_health_regen", kind = "bool"},
	{name = "gry_infinite_armor", kind = "bool"}
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
