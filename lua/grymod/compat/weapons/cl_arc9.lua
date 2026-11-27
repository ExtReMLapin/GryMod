-- ARC9: the fire mode icon of the weapon slot, read from the base's own fields. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses the
-- public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and does nothing when the base is not installed. Tried with real ARC9 weapons
-- (arc9_fas_famas with an M203): automatic, burst and single shot modes and the launcher under the barrel read live. A weapon on safety (ARC9 keeps the safety apart from the
-- mode: GetSafe) shows the single shot icon: it cannot fire, and the movie has no safety icon.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- ARC9: GetCurrentFiremode() is the Mode number of the mode in use: below 0 automatic, 1 semi, above 1 a burst of that length (the weapons of the packs installed here use -1,
-- 1, 2 and 3), and the mode of the launcher while it is up (GetUBGL).
HUD.AddFireModeResolver(function(weapon)
	if weapon.ARC9 ~= true or not weapon.GetCurrentFiremode then
		return nil
	end

	if weapon.GetUBGL and weapon:GetUBGL() then
		return "Grenade"
	end

	-- a weapon that only bashes (a knife) is not a gun: no fire mode, as the crowbar. The processed value knows what an attachment changes.
	local bash = weapon.PrimaryBash

	if isfunction(weapon.GetProcessedValue) then
		bash = weapon:GetProcessedValue("PrimaryBash", true)
	end

	if bash == true then
		return "NoGun"
	end

	if weapon.GetSafe and weapon:GetSafe() then
		return "Single"
	end

	local mode = weapon:GetCurrentFiremode()

	if mode < 0 then
		return "Auto"
	end

	return mode > 1 and "Burst" or "Single"
end, "compat.arc9")
