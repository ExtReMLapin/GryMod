-- FA:S 2 (client): the weapon icon of the quick menu opens FA:S 2's attachment menu. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the public
-- GryMod.API.AddWeaponMenuProvider only, nothing for a weapon that is not FA:S 2's and nothing when FA:S 2 is not installed. READ in a copy of FA:S 2's source (the console
-- command fas2_togglegunpimper, after the weapon's ShowStats is set the way its key sets it: the page of the statistics for a weapon with no attachment) and NOT TRIED in a
-- game: FA:S 2 was not installed when this was written. A weapon that says NoAttachmentMenu has none.

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function open(weapon)
	weapon.ShowStats = weapon.Attachments == nil

	RunConsoleCommand("fas2_togglegunpimper")
end

API.AddWeaponMenuProvider("compat.fas2", function(weapon)
	if not weapon.IsFAS2Weapon or weapon.NoAttachmentMenu then
		return nil
	end

	return open
end)
