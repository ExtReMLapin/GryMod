-- CW 2.0 and FA:S 2.0: the fire mode icon of the weapon slot, read from the base's own fields (read from its source code). Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and
-- does nothing when the base is not installed. A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- CW 2.0 and FA:S 2.0: FireMode is a string the server sends when the player changes it (nil until it arrives).
HUD.AddFireModeResolver(function(weapon)
	if weapon.CW20Weapon ~= true and weapon.IsFAS2Weapon ~= true then
		return nil
	end

	return HUD.FireModeFromName(weapon.FireMode)
end, "compat.cw2_fas2")
