-- The explosion pings of the radar (the original's icon type 6: an expanding ring at the place of an explosion, which the HUD draws for two seconds, see
-- cl_hud_radar_pings.lua). The server decides where and how big, and tells the players within the reach of the original's explosion event (250 m).
--   * GryMod.API.ReportRadarPing(pos, kind): an addon reports an explosion, a gunshot, anything that should ping the radar. `kind`: nothing (an explosion),
--     "small" / "explosion" / "big", or a size in metres (0.5 to 8).
--   * automatic pings: every env_explosion that is made pings the radar at its place. The engine makes one for each Half-Life 2 explosion (a grenade, a rocket,
--     a barrel, a mine, an energy ball), so this one hook covers them all, and an addon's own env_explosion too. Nothing runs by itself: the hook only
--     looks at the class of each new entity, and a ping is made on the tick after the explosion, when its place and its size are set. gry_radar_pings (the
--     administrators' option) turns the automatic ones off; the API call always works.
-- The hook GryMod_RadarPing(pos, size, automatic) tells that a ping was accepted (its return value is not read).

util.AddNetworkString("gry_radar_ping")

GryMod = GryMod or {}

local Radar = GryMod.Radar or {}
GryMod.Radar = Radar

local S = GryMod.RadarShared

local automatic = CreateConVar("gry_radar_pings", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The explosions (env_explosion: grenades, rockets, barrels) ping the radar of the players within 250 m with a ring; 0 turns the automatic pings off (the API call still works)")

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
local function explosionPing(ent)
	if not IsValid(ent) or not automatic:GetBool() then
		return
	end

	Radar.ReportPing(ent:GetPos(), Radar.ExplosionSize(ent), true)
end

function Radar.OnEntityCreated(ent)
	if not IsValid(ent) or not automatic:GetBool() or ent:GetClass() ~= "env_explosion" then
		return
	end

	timer.Simple(0, function()
		explosionPing(ent)
	end)
end

hook.Add("OnEntityCreated", "GryMod radar pings", Radar.OnEntityCreated)
