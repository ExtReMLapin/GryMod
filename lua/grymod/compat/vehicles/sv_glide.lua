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
-- scripted_ents.IsBasedOn(class, base) is false for the base class itself (found with the real Glide), so the plain glide_missile and glide_projectile are named.

local projectileClasses = {}
local vehicleClasses = {}

-- Forgets what was learned about the classes (the tests, which replace scripted_ents.IsBasedOn).
function Compat.ForgetClasses()
	projectileClasses, vehicleClasses = {}, {}
end

local function isGlideProjectile(class)
	local known = projectileClasses[class]

	if known == nil then
		known = class == "glide_missile" or class == "glide_projectile" or scripted_ents.IsBasedOn(class, "glide_missile") == true or scripted_ents.IsBasedOn(class, "glide_projectile") == true
		projectileClasses[class] = known
	end

	return known
end

local function isGlideVehicle(class)
	local known = vehicleClasses[class]

	if known == nil then
		known = scripted_ents.IsBasedOn(class, "base_glide") == true
		vehicleClasses[class] = known
	end

	return known
end

-- A shot that leaves no bullet for the engine's hook is told with its noise (GryMod.API.ReportShot, the core's) when the core has it, silently otherwise.
local function tell(ply)
	return (API.ReportShot or API.ReportAttack)(ply, false)
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
		tell(attacker)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The explosive cannon
-- ---------------------------------------------------------------------------------------------------------
-- The explosive cannon of the aircraft (VSWEP explosive_cannon: gtav_lazer, gtav_strikeforce...) fires through ENT:FireBullet with isExplosive: Glide.FireBullet then only blasts the
-- place it hits and calls no FireBullets, so the engine's hook never sees that shot (the machine guns' bullets go through FireBullets and are seen). Glide.FireBullet is kept in a local by
-- the vehicles' files when they load, after GryMod: it cannot be replaced. ENT:FireBullet of each vehicle can: it is wrapped on the vehicle, once, a tick after it is made.
-- It counts when the attacker (the driver of the first seat) sits in the vehicle that fires.

local SHOT_INTERVAL = 0.25 -- the cannon fires twelve shots a second; the first one ends the camouflage

-- A field: the tests call it.
function Compat.ReportCannon(vehicle, attacker)
	if not isPlayer(attacker) or not Compat.VehicleOf or Compat.VehicleOf(attacker) ~= vehicle then
		return false
	end

	local now = CurTime()

	if (attacker.gryGlideShotAt or -1000) + SHOT_INTERVAL > now then
		return false
	end

	attacker.gryGlideShotAt = now

	return tell(attacker) == true
end

local wrapped = setmetatable({}, {__mode = "k"}) -- the wrappers we made

local function wrapFireBullet(vehicle)
	local original = vehicle.FireBullet

	if not isfunction(original) or wrapped[original] then
		return
	end

	local function wrapper(self, params, ...)
		if istable(params) and params.isExplosive then
			pcall(Compat.ReportCannon, self, params.attacker)
		end

		return original(self, params, ...)
	end

	wrapped[wrapper] = true
	vehicle.FireBullet = wrapper
end

hook.Add("OnEntityCreated", "GryModGlideAttack", function(ent)
	if not IsValid(ent) then
		return
	end

	local class = ent:GetClass()

	if isGlideProjectile(class) then
		-- the shooter is given right after the entity is made (SetupMissile), in the same tick
		timer.Simple(0, function()
			Compat.ReportShot(ent)
		end)
	elseif isGlideVehicle(class) then
		timer.Simple(0, function()
			if IsValid(ent) then
				wrapFireBullet(ent)
			end
		end)
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The hits on a player who sits in a Glide vehicle
-- ---------------------------------------------------------------------------------------------------------
-- Glide cancels every blast on a player in one of its vehicles (events.lua, Glide.OverrideDamage): the suit must not pay a hit that never lands (its energy went down for nothing):
-- "ignore". A vehicle that explodes kills its occupants with ply:TakeDamage(999) once hasExploded is set (base_glide/sv_damage.lua, Explode), and removes itself: that hit goes to the
-- health whatever the bar holds ("bypass"), or an infinite armor would let the occupant live in the explosion of his vehicle.

function Compat.HitVerdict(ply, dmginfo)
	local vehicle = Compat.VehicleOf and Compat.VehicleOf(ply)

	if not IsValid(vehicle) then
		return nil
	end

	if dmginfo:IsDamageType(DMG_BLAST) then
		return "ignore"
	end

	if vehicle.hasExploded == true then
		return "bypass"
	end

	return nil
end

if API.AddHitFilter then
	API.AddHitFilter("glide", Compat.HitVerdict, 5)
end
