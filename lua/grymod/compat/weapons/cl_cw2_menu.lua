-- CW 2.0 (client): the weapon icon of the quick menu opens CW 2.0's customization menu. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the public
-- GryMod.API.AddWeaponMenuProvider only, nothing for a weapon that is not CW 2.0's and nothing when CW 2.0 is not installed. READ in a copy of CW 2.0's source (the weapon's
-- attemptToggleInteractionMenu, or the console command cw_customize) and NOT TRIED in a game: CW 2.0 was not installed when this was written, and no official repository
-- exists, so the names may differ in the Workshop version. The weapon's own canOpenInteractionMenu says whether the menu can open now (no attachment, reloading, running...).

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function open(weapon)
	if isfunction(weapon.attemptToggleInteractionMenu) then
		weapon:attemptToggleInteractionMenu()
	else
		RunConsoleCommand("cw_customize")
	end
end

API.AddWeaponMenuProvider("compat.cw2", function(weapon)
	if not weapon.CW20Weapon then
		return nil
	end

	if isfunction(weapon.canOpenInteractionMenu) and not weapon:canOpenInteractionMenu() then
		return nil
	end

	return open
end)
