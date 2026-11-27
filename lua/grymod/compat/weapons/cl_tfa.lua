-- TFA: the fire mode icon of the weapon slot, read from the base's own fields (read from its source code). Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and
-- does nothing when the base is not installed. A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- TFA: GetFireMode() is an index into FireModes, a list of names.
HUD.AddFireModeResolver(function(weapon)
	if weapon.IsTFAWeapon ~= true or not weapon.GetFireMode or not weapon.FireModes then
		return nil
	end

	-- a weapon that only strikes (a knife, a sword) is not a gun: no fire mode, as the crowbar and the ARC9 knives
	if weapon.IsMelee == true or weapon.IsKnife == true then
		return "NoGun"
	end

	return HUD.FireModeFromName(weapon.FireModes[weapon:GetFireMode()])
end, "compat.tfa")
