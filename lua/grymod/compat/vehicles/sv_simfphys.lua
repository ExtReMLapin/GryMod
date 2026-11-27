-- simfphys (the physics vehicle base of Garry's Mod and its armed pack), server half of the compatibility patch (docs/compat.md, sh_simfphys.lua says what GryMod knows about it).
--   * the damage to a player who sits in a car, through a hit filter (GryMod.API.AddHitFilter):
--       - simfphys cancels by itself (its hook "!!!_simfphys_fix_vehicle_explosion_damage", server/damage.lua) every hit that is not DMG_DIRECT on a seated player: the suit must not pay a hit that
--         never comes (the energy, the arrows, a malfunction): "ignore";
--       - a car that blows up kills its occupants on purpose (ExplodeVehicle gives each one Health + Armor, DMG_DIRECT, after setting `car.destroyed`): the armor would absorb it and the occupant
--         would live in the explosion of his car: "bypass".
--     A crash (2 or 5 points, DMG_DIRECT, the car is whole) goes through the armor as any hit.
--   * the shots that are not bullets: a shell of the armed pack (`simfphys_tankprojectile`, made by the player's cannon, it only hurts at its impact) and a mine thrown with weapon_simmines end the
--     camouflage as a thrown grenade does (GryMod.API.ReportAttack). The bullets of the machine guns are told by the engine (EntityFireBullets, `data.Attacker` is the player).
--   * the rings of the radar need nothing: the blast of the shell and of the wreck go through util.BlastDamage, which the core rings (docs/api.md).
-- Nothing runs permanently: the hit filter runs for a hit on a player, and one hook sees the entities as they are made.

local API = GryMod.API
local S = GryMod.CompatSimfphys

if not API or not API.AddHitFilter or not S then
	return -- sv_api.lua and sh_simfphys.lua are included first (grymod_shared.lua)
end

local FIX_HOOK = "!!!_simfphys_fix_vehicle_explosion_damage"
local SHELL = "simfphys_tankprojectile"

S.HitFilterId = "simfphys"

-- Whether simfphys' own hook that cancels the damage to a seated player is there (hook.GetTable makes a copy: only asked for a hit on a seated player).
local function cancelsDamage()
	local events = hook.GetTable()
	local damage = events.EntityTakeDamage

	return damage ~= nil and damage[FIX_HOOK] ~= nil
end

-- What the suit does with a hit on this player: nil (as always), "ignore" or "bypass".
function S.HitVerdict(ply, dmginfo)
	local sits = ply.InVehicle

	if not isfunction(sits) or not sits(ply) then
		return nil
	end

	local car = S.CarOf(ply)

	if not car then
		return nil
	end

	if dmginfo:IsDamageType(DMG_DIRECT) then
		-- the explosion of the car, which wants its occupants dead: everything they have
		if car.destroyed == true and dmginfo:GetDamage() >= ply:Health() then
			return "bypass"
		end

		return nil
	end

	-- simfphys leaves the damage alone when the player's collision group is the player's: it does not cancel it then
	if ply:GetCollisionGroup() ~= COLLISION_GROUP_PLAYER and cancelsDamage() then
		return "ignore"
	end

	return nil
end

API.AddHitFilter(S.HitFilterId, S.HitVerdict, 0)

-- ---------------------------------------------------------------------------------------------------------
-- The shell and the mine
-- ---------------------------------------------------------------------------------------------------------

-- The player attacked: the camouflage ends, and the shot makes its noise when he was camouflaged (what a bullet does, sv_suit_noise.lua).
local function attacked(ply, noisy)
	local level = API.CloakLevel and API.CloakLevel(ply) or 0

	API.ReportAttack(ply, false)

	if noisy and level > 0 and GryMod.EmitSuitNoise then
		GryMod.EmitSuitNoise(ply, "cloak_fire")
	end
end

-- An entity that was just made (a tick after: its fields are set by the code that made it). Never raises an error.
function S.OnCreated(ent)
	pcall(function()
		if not IsValid(ent) then
			return
		end

		local class = ent:GetClass()

		if class == SHELL then
			-- fired by the player's cannon (the shell keeps the shooter and the car it left); a turret's shell belongs to whoever placed the turret: not an attack of his now
			local shooter, base = ent.Attacker, ent.AttackingEnt

			if IsValid(shooter) and shooter:IsPlayer() and IsValid(base) and base:GetClass() == S.Car and (S.CarOf(shooter) == base or base.RemoteDriver == shooter) then
				attacked(shooter, true)
			end
		elseif class == S.Mine then
			local thrower = ent.CreatedBy

			if ent.Thrown == true and IsValid(thrower) and thrower:IsPlayer() then
				attacked(thrower, false)
			end
		end
	end)
end

hook.Add("OnEntityCreated", "GryMod compat simfphys", function(ent)
	if IsValid(ent) then
		local class = ent:GetClass()

		if class == SHELL or class == S.Mine then
			timer.Simple(0, function()
				S.OnCreated(ent)
			end)
		end
	end
end)
