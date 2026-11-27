-- ARC9 (client): the weapon icon of the quick menu opens ARC9's customization menu, and the camouflage leaves the gun plain while that menu is up. Part of the compatibility
-- patches (lua/grymod/compat/, docs/compat.md): the public GryMod.API.AddWeaponMenuProvider and AddPlainViewProvider only, nothing for a weapon that is not ARC9's and nothing
-- when ARC9 is not installed. Tried with a real ARC9 weapon: the weapon's ToggleCustomize(true) (sh_attach.lua) opens it; ARC9 has no console command for it (its key is a bind).
-- While the menu is up (CustomizeDelta goes from 0 to 1 and back, so also while it comes in and goes out) ARC9 turns the gun towards the player over a dark and blurred picture of
-- the world that it draws after the camouflage has copied the screen: the layer there showed an undarkened, unblurred world through the gun, and the player picks parts on it.

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

	-- a knife, a machete or a grenade: the base gives it an empty Attachments table, there is nothing to customize and the menu would open on an empty screen
	if istable(weapon.Attachments) and next(weapon.Attachments) == nil then
		return nil
	end

	return open
end)

if API.AddPlainViewProvider then
	API.AddPlainViewProvider("compat.arc9", function(weapon)
		if weapon.ARC9 ~= true or not isfunction(weapon.GetCustomize) then
			return false
		end

		return weapon:GetCustomize() == true or (weapon.CustomizeDelta or 0) > 0
	end)
end
