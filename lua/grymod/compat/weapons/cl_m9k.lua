-- M9K: the fire mode icon of the weapon slot, read from the base's own fields (read from its source code). Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.AddFireModeResolver, answers nil for a weapon that is not this base's, and
-- does nothing when the base is not installed. A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

-- M9K: GetAutomatic(); its shotguns have their own base. M9K sets no marker on its weapons (the other bases do), so the weapon is known by its BASE. No weapon class is named:
-- a weapon is M9K's when one of the three M9K bases is the base it was built on, however many bases of a weapon pack there are between them (weapons.IsBasedOn follows the chain).
local GUN_BASES = {"bobs_gun_base", "bobs_scoped_base"}
local SHOTGUN_BASE = "bobs_shotty_base"

local kinds = {} -- [class][base] = "gun", "shotgun" or false: the chain of a class does not change while the game runs, and the HUD asks at every frame

local function basedOn(class, base)
	return class == base or weapons.IsBasedOn(class, base)
end

local function kindOf(weapon)
	local class = weapon.GetClass and weapon:GetClass()
	local base = weapon.Base or ""
	local known = isstring(class) and kinds[class]
	local kind = known and known[base]

	if kind ~= nil then
		return kind
	end

	kind = false

	-- the direct base is enough for a stand-in with no class; a real weapon is looked up through its whole chain
	if weapon.Base == SHOTGUN_BASE or (isstring(class) and basedOn(class, SHOTGUN_BASE)) then
		kind = "shotgun"
	else
		for _, base in ipairs(GUN_BASES) do
			if weapon.Base == base or (isstring(class) and basedOn(class, base)) then
				kind = "gun"

				break
			end
		end
	end

	if isstring(class) then
		known = known or {}
		known[base] = kind
		kinds[class] = known
	end

	return kind
end

HUD.AddFireModeResolver(function(weapon)
	if not weapon.GetAutomatic then
		return nil
	end

	local kind = kindOf(weapon)

	if kind == "shotgun" then
		return "Shotgun"
	elseif kind == "gun" then
		return weapon:GetAutomatic() and "Auto" or "Single"
	end

	return nil
end, "compat.m9k")
