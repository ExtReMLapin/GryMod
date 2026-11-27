-- The explosion pings of the radar (the original's icon type 6: an expanding ring at the place of an explosion, which the HUD draws for two seconds, see
-- cl_hud_radar_pings.lua). The server decides where and how big, and tells the players within the reach of the original's explosion event (250 m).
--   * GryMod.API.ReportRadarPing(pos, kind): an addon reports an explosion, a gunshot, anything that should ping the radar. `kind`: nothing (an explosion),
--     "small" / "explosion" / "big", or a size in metres (0.5 to 8).
--   * automatic pings: every env_explosion that is made pings the radar at its place. The engine makes one for a rocket, a barrel, a mine, a helicopter bomb,
--     a tripmine, a scanner, a roller mine (MEASURED), and an addon's own env_explosion too. Nothing runs by itself: the hook only looks at the class of each
--     new entity, and a ping is made on the tick after the explosion, when its place and its size are set.
--   * the things that explode WITHOUT an env_explosion (the hand grenade, the SMG grenade, the satchel, the AR2 ball, a destroyed manhack: MEASURED, the engine
--     draws their blast as an effect) ping when they are removed (Radar.ExplosiveClasses, below).
--     gry_radar_pings (the administrators' option) turns the automatic ones off; the API call always works.
--   * the blasts of util.BlastDamage (an addon's rocket, a vehicle's shell, a tool's bomb: they make no env_explosion) ring the radar too, from 150 units of radius up. The core wraps
--     util.BlastDamage ONCE (Radar.InstallBlast); the option gry_radar_blast_rings (under gry_radar_pings) turns it off; the hook GryMod_Explosion(pos, radius, inflictor, attacker) is told for
--     every blast, ring or not. A blast and an env_explosion of the same place and moment ring once.
-- The hook GryMod_RadarPing(pos, size, automatic) tells that a ping was accepted (its return value is not read).

util.AddNetworkString("gry_radar_ping")

GryMod = GryMod or {}

local Radar = GryMod.Radar or {}
GryMod.Radar = Radar

local S = GryMod.RadarShared

local automatic = CreateConVar("gry_radar_pings", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The explosions (env_explosion: grenades, rockets, barrels) ping the radar of the players within 250 m with a ring; 0 turns the automatic pings off (the API call still works)")

local blastRings = CreateConVar("gry_radar_blast_rings", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The blasts made by util.BlastDamage (other addons' rockets, shells and bombs) of 150 units or more ping the radar too, like an env_explosion (needs gry_radar_pings); 0 turns them off")

-- No more pings than this a second in all: a chain of explosions must not flood the net (the client keeps 16 rings anyway).
local MAX_PER_SECOND = 20

local window, inWindow = 0, 0

-- Forgets the count of the second (the tests).
function Radar.ResetPingRate()
	window, inWindow = 0, 0
end

local function allowed(now)
	if now - window >= 1 then
		window, inWindow = now, 0
	end

	if inWindow >= MAX_PER_SECOND then
		return false
	end

	inWindow = inWindow + 1

	return true
end

-- The players that can get a ping (a field of Radar so that a test can replace it).
function Radar.PingPlayers()
	return player.GetAll()
end

local REACH2 = (S.PING_RANGE / S.METRES_PER_UNIT) ^ 2

-- The living players within the reach of a ping at `pos`.
function Radar.PingRecipients(pos)
	local list = {}

	for _, ply in ipairs(Radar.PingPlayers()) do
		if IsValid(ply) and ply:Alive() and ply:GetPos():DistToSqr(pos) <= REACH2 then
			list[#list + 1] = ply
		end
	end

	return list
end

-- Makes a ping at `pos` of the size `size` (metres, already valid) and tells the players in reach. Returns true.
local function send(pos, size, auto)
	local to = Radar.PingRecipients(pos)

	if #to > 0 then
		net.Start("gry_radar_ping")
		net.WriteVector(pos)
		net.WriteUInt(S.PingToWire(size), 5)
		net.Send(to)
	end

	hook.Run("GryMod_RadarPing", pos, size, auto)

	return true
end

-- Reports a ping: returns true, or false and why. `kind` as GryMod.RadarShared.PingSize says.
function Radar.ReportPing(pos, kind, auto)
	if not isvector(pos) or pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then
		return false, "invalid position"
	end

	local size = S.PingSize(kind)

	if not size then
		return false, "invalid kind"
	end

	if not allowed(CurTime()) then
		return false, "too many pings this second"
	end

	return send(pos, size, auto == true)
end

function GryMod.API.ReportRadarPing(pos, kind)
	return Radar.ReportPing(pos, kind, false)
end

-- The ping size of an env_explosion: the radius it was given (m_iRadiusOverride) or the one the engine derives from the magnitude (2.5 units for each point,
-- 100 points when nothing is set), held between the smallest and the biggest size.
function Radar.ExplosionSize(ent)
	local override = ent:GetInternalVariable("m_iRadiusOverride")
	local magnitude = ent:GetInternalVariable("m_iMagnitude")
	local radius

	if isnumber(override) and override > 0 then
		radius = override
	else
		radius = (isnumber(magnitude) and magnitude > 0 and magnitude or 100) * 2.5
	end

	return S.PingSizeOfRadius(radius)
end

-- The tick after an env_explosion was made: its place and its keys are set, and the explosion has gone off (the engine's ExplosionCreate fires it at once;
-- one that an addon fires later still pings once, at its place).
-- ---------------------------------------------------------------------------------------------------------
-- The blasts of util.BlastDamage. A blast and an env_explosion at the same place and in the same moment (an addon often does both) are ONE explosion: each kind remembers its rings for a
-- tenth of a second, and the other kind does not ring again near them. Two env_explosions at the same place stay two rings (the engine's chain), as before.
-- ---------------------------------------------------------------------------------------------------------

local SAME_SECONDS, SAME_DISTANCE2 = 0.1, 100 * 100
local BLAST_MIN_RADIUS = 150
local recent = {}

function Radar.ResetBlastMemory()
	recent = {}
end

local function remember(pos, kind, now)
	for i = #recent, 1, -1 do
		if now - recent[i].time > SAME_SECONDS or now < recent[i].time then
			table.remove(recent, i)
		end
	end

	if #recent >= 32 then
		table.remove(recent, 1)
	end

	recent[#recent + 1] = {pos = pos, time = now, kind = kind}
end

-- Whether a ring of this kind was made near `pos` a moment ago
local function ringedNear(pos, kind, now)
	for i = 1, #recent do
		local r = recent[i]

		if r.kind == kind and now >= r.time and now - r.time <= SAME_SECONDS and r.pos:DistToSqr(pos) <= SAME_DISTANCE2 then
			return true
		end
	end

	return false
end

local function explosionPing(ent)
	if not IsValid(ent) or not automatic:GetBool() then
		return
	end

	local pos, now = ent:GetPos(), CurTime()

	-- a blast of util.BlastDamage rang for this explosion already
	if ringedNear(pos, "blast", now) then
		return
	end

	remember(pos, "env", now)
	Radar.ReportPing(pos, Radar.ExplosionSize(ent), true)
end

Radar.ExplosionPing = explosionPing

-- What GryMod does for a blast (called by the wrapper of util.BlastDamage, after the original ran, under pcall: it can never break the blast).
function Radar.OnBlast(pos, radius, inflictor, attacker)
	if not isvector(pos) or not isnumber(radius) or radius ~= radius then
		return
	end

	-- a handler of another addon that fails must not keep the radar from ringing
	local ok, err = pcall(hook.Run, "GryMod_Explosion", pos, radius, inflictor, attacker)

	if not ok then
		ErrorNoHalt("[GryMod] A handler of GryMod_Explosion failed: " .. tostring(err) .. "\n")
	end

	if radius < BLAST_MIN_RADIUS or not blastRings:GetBool() or not automatic:GetBool() then
		return
	end

	local now = CurTime()

	-- an env_explosion rang for this explosion already
	if ringedNear(pos, "env", now) then
		return
	end

	remember(pos, "blast", now)
	Radar.ReportPing(pos, S.PingSizeOfRadius(radius), true)
end

-- Wraps util.BlastDamage once. Installing again does nothing while the wrapper is the function in place; when the wrapper was replaced or wrapped by another addon, this wraps what is
-- there now (the chain may hold an earlier wrapper: the shared flag util.GryBlastBusy makes only the outermost one work, so a blast is never told twice). The wrapper calls the original
-- first and returns what it returns, and any error of it is raised again as it was; only GryMod's own part is under pcall.
function Radar.InstallBlast()
	if util.GryBlastWrapper ~= nil and util.BlastDamage == util.GryBlastWrapper then
		return false
	end

	local original = util.BlastDamage

	if not isfunction(original) then
		return false
	end

	local function wrapper(...)
		if util.GryBlastBusy then
			return original(...)
		end

		util.GryBlastBusy = true

		local ok, a, b, c = pcall(original, ...)

		util.GryBlastBusy = false

		if not ok then
			error(a, 0)
		end

		-- (inflictor, attacker, position, radius, damage)
		local inflictor, attacker, pos, radius = ...
		local told, err = pcall(GryMod.Radar.OnBlast, pos, radius, inflictor, attacker)

		if not told then
			ErrorNoHalt("[GryMod] The radar's blast ring failed: " .. tostring(err) .. "\n")
		end

		return a, b, c
	end

	Radar.BlastOriginal = original
	util.GryBlastWrapper = wrapper
	util.BlastDamage = wrapper

	return true
end

-- Puts the original back (the tests): only when the wrapper is the function in place.
function Radar.UninstallBlast()
	if util.GryBlastWrapper ~= nil and util.BlastDamage == util.GryBlastWrapper then
		util.BlastDamage = Radar.BlastOriginal
		util.GryBlastWrapper = nil

		return true
	end

	return false
end

Radar.InstallBlast()

function Radar.OnEntityCreated(ent)
	if not IsValid(ent) or not automatic:GetBool() or ent:GetClass() ~= "env_explosion" then
		return
	end

	timer.Simple(0, function()
		explosionPing(ent)
	end)
end

hook.Add("OnEntityCreated", "GryMod radar pings", Radar.OnEntityCreated)

-- The things that explode WITHOUT an env_explosion (MEASURED on 2026-11-24: the engine draws their blast as an effect, so the hook above never sees them): the
-- hand grenade, the SMG grenade, the satchel, the AR2 energy ball and the manhack that is destroyed. They ping when they are removed, at the place they were.
--   radius: the blast's radius in units (the same rule as an env_explosion's, held between the smallest and the biggest ring), or kind: a ring size name;
--   dead: the entity only pings when it is destroyed (a manhack removed alive, by a cleanup or an addon, did not explode).
-- A field of Radar: an addon may add the class of its own explosive (Radar.ExplosiveClasses.my_grenade = {radius = 300}).
Radar.ExplosiveClasses = Radar.ExplosiveClasses or {
	npc_grenade_frag = {radius = 250},
	grenade_ar2 = {radius = 250},
	npc_satchel = {radius = 150},
	prop_combine_ball = {radius = 150},
	npc_manhack = {kind = "small", dead = true}
}

-- An explosive that is removed: it went off. `fullUpdate` is the engine's: the removal is part of a cleanup of the map, nothing exploded.
function Radar.OnEntityRemoved(ent, fullUpdate)
	if fullUpdate or not IsValid(ent) then
		return
	end

	local def = Radar.ExplosiveClasses[ent:GetClass()]

	if not def or not automatic:GetBool() then
		return
	end

	if def.dead and ent:Health() > 0 then
		return
	end

	Radar.ReportPing(ent:GetPos(), def.kind or S.PingSizeOfRadius(def.radius), true)
end

hook.Add("EntityRemoved", "GryMod radar pings", Radar.OnEntityRemoved)
