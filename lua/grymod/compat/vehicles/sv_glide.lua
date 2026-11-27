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
-- A camouflaged driver is not locked on
-- ---------------------------------------------------------------------------------------------------------
-- Glide asks Glide_CanLockOn(ent, attacker) for each target it could lock a missile on (lua/glide/server/weaponry.lua, CanLockOnEntity): the vehicles, the seats and the players on a
-- seat. A refusal means no lock for that target. The vehicle itself stays visible (the owner's rule: the player is not invisible), it is the lock that does not take on a player whose
-- camouflage is more than half on (the cloak level is the camouflage's fade, API.CloakLevel). The server setting switches it off.

local lockOn = CreateConVar("gry_glide_cloak_lockon", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"1: a missile of Glide does not lock on a vehicle whose driver is camouflaged (more than half); 0: it locks on as it always did", 0, 1)

Compat.LockOnConVar = lockOn

local HIDDEN_FROM = 0.5

local function isPlayer(who)
	return IsValid(who) and isfunction(who.IsPlayer) and who:IsPlayer()
end

hook.Add("Glide_CanLockOn", "GryModGlide", function(ent, attacker)
	if not lockOn:GetBool() or not IsValid(ent) or not API.CloakLevel then
		return
	end

	local driver = isPlayer(ent) and ent or API.GetVehicleDriver(ent)

	if not isPlayer(driver) or driver == attacker then
		return
	end

	if API.CloakLevel(driver) >= HIDDEN_FROM then
		return false
	end
end)

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
