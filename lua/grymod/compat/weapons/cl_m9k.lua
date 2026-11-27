-- M9K: the fire mode icon of the weapon slot, read from the base's own fields (read from its source code). Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and
-- does nothing when the base is not installed. A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- M9K: GetAutomatic(); its shotguns have their own base.
local M9K_BASES = {bobs_gun_base = true, bobs_scoped_base = true, bobs_shotty_base = true}

HUD.AddFireModeResolver(function(weapon)
	if not M9K_BASES[weapon.Base] or not weapon.GetAutomatic then
		return nil
	end

	if weapon.Base == "bobs_shotty_base" then
		return "Shotgun"
	end

	return weapon:GetAutomatic() and "Auto" or "Single"
end, "compat.m9k")
