-- LVS (server): what the suit does with the hits an occupant takes, the shots that LVS fires without telling the engine, and the relation of two players by LVS team. Part of the
-- compatibility patches (lua/grymod/compat/, docs/compat.md): nothing when LVS is not installed. The shared half is sh_lvs.lua (read its header for what was read in LVS's code).
--
-- The hits. LVS has its own damage rules for the people in a vehicle (lvs_framework/autorun/lvs_hookers.lua and lvs_base/sv_damagesystem.lua):
--   * every hit on an occupant that is not DMG_DIRECT is set to 0 by LVS (the vehicle takes it instead): the suit must do NOTHING for it, or the bar is paid, the arrows and the
--     malfunction rules answer for a hit that never lands (the order of two addons' EntityTakeDamage hooks is not chosen). Verdict "ignore".
--   * when a vehicle explodes LVS kills its occupants with a DMG_DIRECT hit of exactly Health() + Armor() (a 1000 for a car): the addon wants them dead, and a full bar would
--     swallow it. Verdict "bypass" (the damage goes to the health, the bar is not touched). A DMG_DIRECT hit that is not lethal (a bullet through the driver's window, an ammunition
--     rack) is the suit's business as any hit.
--
-- The shots. LVS's weapons do not fire engine bullets (`LVS:FireBullet` simulates them in Lua), so EntityFireBullets, which ends the camouflage, never runs for them. The function is
-- wrapped once and tells the suit with GryMod.API.ReportAttack; the missiles and the bombs (entities) are told one frame after they are made, when their attacker is set.

GryMod = GryMod or {}

local API = GryMod.API
local L = GryMod.CompatLVS

if not API or not L or not API.AddHitFilter or not API.ReportAttack then
	return -- sh_lvs.lua and sv_api.lua are included first (grymod_shared.lua)
end

-- ---------------------------------------------------------------------------------------------------------
-- The hits
-- ---------------------------------------------------------------------------------------------------------

-- "ignore", "bypass" or nil, for one hit on a player.
function L.HitVerdict(ply, dmginfo)
	if not L.VehicleOf(ply) then
		return nil
	end

	if dmginfo:IsDamageType(DMG_DIRECT) then
		-- the explosion's kill: LVS asks for exactly what the player has
		if dmginfo:GetDamage() >= ply:Health() + ply:Armor() then
			return "bypass"
		end

		return nil
	end

	-- LVS sets the damage to 0 unless the player's collision group is the normal one (lvs_hookers.lua)
	if ply:GetCollisionGroup() == COLLISION_GROUP_PLAYER then
		return nil
	end

	return "ignore"
end

-- ---------------------------------------------------------------------------------------------------------
-- The shots
-- ---------------------------------------------------------------------------------------------------------

-- A player is told at most once in this time: a machine gun fires ten bullets a second, and the first one ends the camouflage.
L.SHOT_INTERVAL = 0.25

-- The player who fired: an LVS shot or missile has a player as its attacker, or the vehicle (an AI) or nothing.
local function playerOf(attacker)
	if IsValid(attacker) and isfunction(attacker.IsPlayer) and attacker:IsPlayer() then
		return attacker
	end

	return nil
end

-- Tells the suit that this player attacked (not a bullet of the engine, not the right click). Returns whether the suit was told.
function L.ReportShot(ply)
	ply = playerOf(ply)

	if not ply then
		return false
	end

	local now = CurTime()

	if (ply.gryLvsShotAt or -1000) + L.SHOT_INTERVAL > now then
		return false
	end

	ply.gryLvsShotAt = now

	-- a gun of a vehicle leaves no bullet for the engine's hook: the shot is told with its noise (ReportShot, the core's) when the core has it
	return (API.ReportShot or API.ReportAttack)(ply, false) == true
end

-- LVS:FireBullet(data) is the one place its machine guns, cannons and lasers go through: data.Attacker is the driver or the gunner.
function L.WrapFireBullet()
	if not L.Present() then
		return false
	end

	if not isfunction(LVS.FireBullet) then
		-- LVS is there but the function the patch replaces is not (LVS changed): the patch is off, and the owner is told once the game is up (LVS may define it late)
		if API.WarnPatchMissing then
			API.WarnPatchMissing("LVS", "LVS.FireBullet", function() return istable(LVS) and not isfunction(LVS.FireBullet) end)
		end

		return false
	end

	local current = LVS.FireBullet

	if L.wrappers and L.wrappers[current] then
		return true
	end

	L.wrappers = L.wrappers or setmetatable({}, {__mode = "k"})

	local function wrapper(self, data, ...)
		if istable(data) then
			pcall(L.ReportShot, data.Attacker)
		end

		return current(self, data, ...)
	end

	L.wrappers[wrapper] = current
	LVS.FireBullet = wrapper

	return true
end

-- A missile or a bomb of LVS: the class, or a class built on lvs_missile / lvs_bomb (a pack's own).
local projectileClasses = {}

function L.IsProjectileClass(class)
	if not isstring(class) then
		return false
	end

	local known = projectileClasses[class]

	if known == nil then
		known = scripted_ents.IsBasedOn(class, "lvs_missile") or scripted_ents.IsBasedOn(class, "lvs_bomb") or false
		projectileClasses[class] = known
	end

	return known
end

local function launched(ent)
	if not IsValid(ent) or not isfunction(ent.GetAttacker) then
		return
	end

	L.ReportShot(ent:GetAttacker())
end

-- Every projectile is looked at once, one frame after it exists: LVS sets its attacker right after Spawn. Nothing runs at any other time.
function L.OnEntityCreated(ent)
	if IsValid(ent) and L.IsProjectileClass(ent:GetClass()) then
		timer.Simple(0, function()
			launched(ent)
		end)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Players of two LVS teams
-- ---------------------------------------------------------------------------------------------------------

-- Two players on different LVS teams are enemies for LVS's AI whatever their team of the game; on the same LVS team they are friends. A team 0 (the default: friendly to everyone)
-- has no opinion, and the game's own rule decides.
function L.PlayerRelation(ply, other)
	if not IsValid(other) or not isfunction(other.IsPlayer) or not other:IsPlayer() then
		return nil
	end

	return L.TeamRelation(L.TeamOfPlayer(ply), L.TeamOfPlayer(other))
end

-- ---------------------------------------------------------------------------------------------------------
-- The registrations
-- ---------------------------------------------------------------------------------------------------------

-- Idempotent; false when LVS is not installed.
function L.InstallServer()
	if not L.Present() then
		return false
	end

	API.AddHitFilter("lvs", L.HitVerdict, 10)
	API.AddRelationProvider("lvs", L.PlayerRelation)
	L.WrapFireBullet()
	hook.Add("OnEntityCreated", "GryMod compat LVS projectiles", L.OnEntityCreated)

	return true
end

-- Takes the registrations away and gives LVS back its own FireBullet (when nobody wrapped it since).
function L.UninstallServer()
	API.RemoveHitFilter("lvs")
	API.RemoveRelationProvider("lvs")
	hook.Remove("OnEntityCreated", "GryMod compat LVS projectiles")

	if L.Present() and L.wrappers and L.wrappers[LVS.FireBullet] then
		LVS.FireBullet = L.wrappers[LVS.FireBullet]
	end
end

if L.Present() then
	L.InstallServer()
end

hook.Add("LVS:Initialize", "GryMod compat LVS server", function()
	L.InstallServer()
end)

hook.Add("InitPostEntity", "GryMod compat LVS server", function()
	L.InstallServer()
end)
