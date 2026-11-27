-- Glide, the server part (see sh_glide.lua): a spawn that is only a player getting up from a ragdoll, the lock-on of a missile that must not see a camouflaged driver, and the
-- missiles and shells that end the camouflage of the player who fired them. Public API and hooks only: the veto GryMod_CanResetOnSpawn, GryMod.API.GetVehicleOf,
-- GetVehicleDriver, CloakLevel and ReportAttack; the hooks of Glide named below (READ in its code: Glide documents its functions in the wiki, not its hooks).
-- Nothing runs without Glide: its hooks are never called, and the creation of an entity costs one lookup in a table of classes.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.ReportAttack then
	return -- sh_api.lua and sv_api.lua are included first (grymod_shared.lua)
end

local Compat = GryMod.GlideCompat or {}
GryMod.GlideCompat = Compat

-- ---------------------------------------------------------------------------------------------------------
-- A player who gets up from a ragdoll keeps his suit
-- ---------------------------------------------------------------------------------------------------------
-- Glide.RagdollPlayer takes the player out of the vehicle (a fall from a motorcycle, an ejection) and Glide.UnRagdollPlayer gets him back with Player:Spawn()
-- (lua/glide/server/ragdoll.lua, RestoreSpawnInfo), then gives back the health, the armor and the weapons it stored in ply.GlideSpawnData. The spawn would reset the suit (the energy
-- full, the armor mode, the start-up of the HUD): the veto of GryMod keeps it. The hook Glide_PrePlayerUnRagdoll runs at the start of that call, so the spawn that follows in the
-- same tick is the getting up. ply.GlideSpawnData alone is not enough: a player killed while ragdolled keeps it (UnRagdollPlayer returns at once for a dead player) and his real
-- respawn, much later, must reset the suit as usual.

hook.Add("Glide_PrePlayerUnRagdoll", "GryModGlide", function(ply)
	if IsValid(ply) then
		ply.GryGlideUnragdollAt = CurTime()
	end
end)

hook.Add("GryMod_CanResetOnSpawn", "GryModGlide", function(ply)
	if ply.GlideSpawnData ~= nil and ply.GryGlideUnragdollAt == CurTime() then
		return false
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- No lock-on veto
-- ---------------------------------------------------------------------------------------------------------
-- Glide asks Glide_CanLockOn(ent, attacker) before a missile locks on a target. GryMod does not answer: the lock-on is not an eye, and the camouflage hides from the visible light only
-- (and a player in a vehicle is never invisible anyway).

local function isPlayer(who)
	return IsValid(who) and isfunction(who.IsPlayer) and who:IsPlayer()
end

-- ---------------------------------------------------------------------------------------------------------
-- A missile or a shell ends the camouflage of the player who fired it
-- ---------------------------------------------------------------------------------------------------------
-- The bullets of a vehicle's guns are fired with the player as the attacker, and GryMod sees them (EntityFireBullets). A missile (glide_missile, the homing launcher SWEP and the
-- vehicles' launchers) or a shell (glide_projectile, the cannons) fires no bullet. Glide has no hook for it, so the adapter looks at the entity at its creation: the shooter is in
-- its field `attacker`, set by SetupMissile / SetupProjectile in the same tick. It counts when the player's own hands fired it (the engine owner is the player: the homing launcher) or
-- the vehicle he sits in did (its owner is his vehicle). A launcher a player only placed has himself as the attacker (its creator) and the launcher as the owner: no report.

local projectileClasses = {}

local function isGlideProjectile(class)
	local known = projectileClasses[class]

	if known == nil then
		known = scripted_ents.IsBasedOn(class, "glide_missile") == true or scripted_ents.IsBasedOn(class, "glide_projectile") == true
		projectileClasses[class] = known
	end

	return known
end

-- Reports the shot of one missile or shell (a field: the tests call it).
function Compat.ReportShot(ent)
	if not IsValid(ent) then
		return
	end

	local attacker = ent.attacker

	if not isPlayer(attacker) then
		return
	end

	local owner = isfunction(ent.GetOwner) and ent:GetOwner() or nil
	local fired = owner == attacker

	if not fired and IsValid(owner) then
		fired = API.GetVehicleOf(attacker) == owner
	end

	if fired then
		API.ReportAttack(attacker, false)
	end
end

hook.Add("OnEntityCreated", "GryModGlideAttack", function(ent)
	if IsValid(ent) and isGlideProjectile(ent:GetClass()) then
		-- the shooter is given right after the entity is made (SetupMissile), in the same tick
		timer.Simple(0, function()
			Compat.ReportShot(ent)
		end)
	end
end)
