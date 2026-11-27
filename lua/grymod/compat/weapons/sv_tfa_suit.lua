-- TFA (server): the strength mode's effects that only the server decides, from the rules of lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): TFA's markers and documented hooks and GryMod's public API only, nothing for a weapon that is not TFA's, nothing when TFA is not
-- installed.
--   * A melee hit (a TFA melee weapon, or the quick melee of a gun) of a strength mode player is multiplied, damage and push, up to x9.2 with a full bar. It is read in
--     EntityTakeDamage (the hit's own inflictor is the weapon), so it covers every TFA melee weapon without any of its attack tables being touched.
--   * Each shot of a gun takes the energy of the rule (TFA_PostPrimaryAttack runs once for each shot that was allowed to happen, never for a melee weapon's swing).

local API = GryMod.API
local SW = GryMod.SuitWeapons

if not API or not SW then
	return -- sv_api.lua and sh_suit_weapons.lua are included first (grymod_shared.lua)
end

local KEY = "GryMod compat tfa suit"

local function isMelee(weapon)
	if weapon.IsMelee == true then
		return true
	end

	local strict = weapon.GetBashingStrict

	return isfunction(strict) and strict(weapon) == true
end

hook.Add("EntityTakeDamage", KEY, function(_, info)
	pcall(function()
		local weapon = info:GetInflictor()

		if not IsValid(weapon) or weapon.IsTFAWeapon ~= true or not isMelee(weapon) then
			return
		end

		local ply = SW.HolderOf(weapon)

		if not ply then
			return
		end

		local scale = SW.MeleeScale(SW.ModeOf(ply), SW.EnergyOf(ply))

		if scale > 1 then
			info:ScaleDamage(scale)
			info:SetDamageForce(info:GetDamageForce() * scale)
		end
	end)

	return nil -- the hit goes on as it was (this only changes its numbers)
end)

-- A melee blow takes its price when the swing starts (the original takes it then, and the energy that is left decides how hard the blow hits).
local function payMelee(weapon)
	local ply = SW.HolderOf(weapon)

	if not ply or GryMod.Config.InfiniteArmor then
		return
	end

	local cost = SW.MeleeCost(SW.ModeOf(ply))

	if cost > 0 then
		API.AddEnergy(ply, -cost)
	end
end

-- The right click of a melee weapon is a blow; the right click of a gun is the sights (or its own alt attack, which is not a blow).
hook.Add("TFA_PostSecondaryAttack", KEY, function(weapon)
	pcall(function()
		if weapon.IsMelee == true then
			payMelee(weapon)
		end
	end)
end)

-- The quick melee of a gun (the bash key).
hook.Add("TFA_PostBash", KEY, function(weapon)
	pcall(function()
		payMelee(weapon)
	end)
end)

hook.Add("TFA_PostPrimaryAttack", KEY, function(weapon)
	pcall(function()
		if weapon.IsMelee == true then
			payMelee(weapon)

			return
		end

		if weapon.IsGrenade == true then
			return
		end

		local ply = SW.HolderOf(weapon)

		if not ply or GryMod.Config.InfiniteArmor then
			return
		end

		-- the calibre: TFA names the weapon's kind of ammunition in its Primary.Ammo stat
		local stat = weapon.GetStatL
		local ammo = isfunction(stat) and stat(weapon, "Primary.Ammo") or nil
		local cost = SW.ShotCost(SW.ModeOf(ply), ammo)

		if cost > 0 then
			API.AddEnergy(ply, -cost)
		end
	end)
end)
