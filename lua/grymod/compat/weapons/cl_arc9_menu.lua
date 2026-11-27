-- ARC9 (client): the weapon icon of the quick menu opens ARC9's customization menu. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the public
-- GryMod.API.AddWeaponMenuProvider only, nothing for a weapon that is not ARC9's and nothing when ARC9 is not installed. READ in ARC9's source (the weapon's
-- ToggleCustomize(true), sh_attach.lua) and NOT TRIED in a game: ARC9 was not installed when this was written. ARC9 has no console command for it (its key is a bind).

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function open(weapon)
	weapon:ToggleCustomize(true)
end

API.AddWeaponMenuProvider("compat.arc9", function(weapon)
	if not weapon.ARC9 or not isfunction(weapon.ToggleCustomize) then
		return nil
	end

	return open
end)
