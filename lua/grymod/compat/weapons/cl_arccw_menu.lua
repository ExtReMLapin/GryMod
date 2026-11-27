-- ArcCW (client): the weapon icon of the quick menu opens ArcCW's customization menu. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the public
-- GryMod.API.AddWeaponMenuProvider only, nothing for a weapon that is not ArcCW's and nothing when ArcCW is not installed. READ in ArcCW's source (the console command
-- arccw_toggle_inv, which ArcCW registers for a key bind) and NOT TRIED in a game: ArcCW was not installed when this was written. The command toggles, and ArcCW refuses it
-- when the weapon sprints or has just fired; arccw_enable_customization -1 turns the whole menu off, and then the icon is greyed.

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function open()
	RunConsoleCommand("arccw_toggle_inv")
end

API.AddWeaponMenuProvider("compat.arccw", function(weapon)
	if not weapon.ArcCW then
		return nil
	end

	local setting = GetConVar("arccw_enable_customization")

	if setting and setting:GetInt() < 0 then
		return nil
	end

	return open
end)
