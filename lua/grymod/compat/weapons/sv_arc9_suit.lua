-- ARC9 (server): the strength mode's effects that only the server decides, from the rules of lua/grymod/sh_suit_weapons.lua. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): ARC9's own global hooks and GryMod's public API only, nothing for a weapon that is not ARC9's, nothing when ARC9 is not installed.
--   * A melee hit of a strength mode player is multiplied, damage and push, up to x9.2 with a full bar: ARC9's hook "Hook_BashHit" runs for each hit of a bash (the butt stroke
--     of a gun, the swing of a knife, the stab: one code for all) with the damage it is about to apply, before DispatchTraceAttack, so no table of the weapon is touched.
--   * Each shot of a gun takes the energy of the rule: "Hook_PrimaryAttack" runs once for each shot that is going to be fired (after every check that can stop it), the shots of the
--     launcher under the barrel included; a bash is not a shot (the rule gives no cost to a melee hit).

local API = GryMod.API
local SW = GryMod.SuitWeapons

if not API or not SW then
	return -- sv_api.lua and sh_suit_weapons.lua are included first (grymod_shared.lua)
end

local KEY = "GryMod compat arc9 suit"

local function holderOf(weapon)
	if (not istable(weapon) and not isentity(weapon)) or weapon.ARC9 ~= true then
		return nil
	end

	return SW.HolderOf(weapon)
end

hook.Add("ARC9_Hook_BashHit", KEY, function(weapon, data)
	pcall(function()
		local info = istable(data) and data.dmg

		if not info then
			return
		end

		local ply = holderOf(weapon)

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

hook.Add("ARC9_Hook_PrimaryAttack", KEY, function(weapon)
	pcall(function()
		local ply = holderOf(weapon)

		if not ply or GryMod.Config.InfiniteArmor then
			return
		end

		-- the calibre: ARC9 keeps the name of the weapon's ammunition in Primary.Ammo (sh_init.lua)
		local ammo = istable(weapon.Primary) and weapon.Primary.Ammo or nil
		local cost = SW.ShotCost(SW.ModeOf(ply), ammo)

		if cost > 0 then
			API.AddEnergy(ply, -cost)
		end
	end)

	return nil
end)
