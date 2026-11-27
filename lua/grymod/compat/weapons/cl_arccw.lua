-- ArcCW: the fire mode icon of the weapon slot, read from the base's own fields (read from its source code). Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and
-- does nothing when the base is not installed. A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- ArcCW: GetCurrentFiremode() is a table whose Mode is the other way round: 2 or more automatic, 1 semi,
-- 0 safety, negative a burst.
HUD.AddFireModeResolver(function(weapon)
	if weapon.ArcCW ~= true or not weapon.GetCurrentFiremode then
		return nil
	end

	if weapon.GetInUBGL and weapon:GetInUBGL() then
		return "Grenade"
	end

	local current = weapon:GetCurrentFiremode()
	local mode = current and current.Mode or 1

	if mode >= 2 then
		return "Auto"
	end

	return mode < 0 and "Burst" or "Single"
end, "compat.arccw")
