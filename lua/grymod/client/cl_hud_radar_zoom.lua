-- The radar's automatic zoom: an option (gry_radar_autozoom, off by default) that moves the radar's range between three modes, each with its own
-- range chosen by the player (nothing ties one slider to another):
--   * vehicle: the player drives (the vehicle wins over the others: it ignores the ceiling);
--   * indoor: under a ceiling AND in a narrow place;
--   * foot: everything else.
-- A mode has to hold for a delay (gry_radar_zoom_delay, 0.7 s by default) before the radar goes there, in both directions, so a door or a passing
-- ceiling changes nothing. The change of range is an EFFECT: Radar.Range() is the range DISPLAYED, which glides to the TARGET (Radar.TargetRange(),
-- the range of the mode) in 0.8 s, in the logarithm of the range with an ease at both ends. The map's definition (the pyramid) and the request to the
-- server follow the TARGET at once, so a glide never makes tiles on the way: it only scales the ones that are there.
-- Cost: nothing while the option is off (Update returns at once). On: one probe at most every quarter of a second (or each second when the player
-- stands still): the level of Floors.CurrentAt (it asks the engine at most once a second itself) and, only under a ceiling, eight rays at chest height.
-- No hook of its own: Radar.Feed (cl_hud_radar_units.lua) calls Update at each frame the HUD draws; the glide is a pure function of the time.

GryMod = GryMod or {}

local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared

local Zoom = GryMod.RadarZoom or {}
GryMod.RadarZoom = Zoom

local AutoConVar = CreateClientConVar("gry_radar_autozoom", "0", true, false,
	"Automatic radar zoom (0 or 1): the radar's range follows three modes, in a vehicle, on foot outside, and indoors (under a ceiling in a narrow place), each with its own range", 0, 1)
local ModeConVars = {
	vehicle = CreateClientConVar("gry_radar_zoom_vehicle", "100", true, false,
		"Radar range in metres (5 to 100) while the player drives, with the automatic zoom on", 5, 100),
	foot = CreateClientConVar("gry_radar_zoom_foot", "75", true, false,
		"Radar range in metres (5 to 100) on foot outside, with the automatic zoom on", 5, 100),
	indoor = CreateClientConVar("gry_radar_zoom_indoor", "25", true, false,
		"Radar range in metres (5 to 100) indoors (under a ceiling in a narrow place), with the automatic zoom on", 5, 100)
}
local DelayConVar = CreateClientConVar("gry_radar_zoom_delay", "0.7", true, false,
	"Seconds a mode has to hold before the radar goes to its range (0.1 to 5): in a mode for less than that, the radar stays where it is", 0.1, 5)

-- the glide of the displayed range to the target, in seconds
Zoom.TRANSITION = 0.8
-- a narrow place, in metres: the median of the free distances around (each capped at NARROW_CAP) goes in under NARROW_IN and out over NARROW_OUT, and keeps its
-- state between the two
Zoom.NARROW_IN = 12
Zoom.NARROW_OUT = 18
Zoom.NARROW_CAP = 20
-- the probe: not before this many seconds, then again only if the player moved this many units, else once a second
local PROBE_MIN = 0.25
local PROBE_IDLE = 1
local PROBE_MOVE_SQ = 24 * 24
-- the eight rays go out at this height over the feet (the chest of a standing player)
local RAY_HEIGHT = 36

local exp, log = math.exp, math.log

-- the state: the accepted mode (nil before the first observation), the mode that wants in and since when, the glide (from, to, start time; start nil = no glide)
local st = {}

local function clampDelay(value)
	if type(value) ~= "number" or value ~= value then
		return 0.7
	end

	return math.Clamp(value, 0.1, 5)
end

function Zoom.Enabled()
	return AutoConVar:GetBool()
end

-- The mode in use: "vehicle", "foot" or "indoor" ("foot" before the first observation).
function Zoom.Mode()
	return st.mode or "foot"
end

-- The target range, in whole metres: the slider of the mode in use.
function Zoom.TargetRange()
	return S.ClampRange(ModeConVars[Zoom.Mode()]:GetFloat())
end

-- The range DISPLAYED at `now`: the target when there is no glide, else the glide's value (a pure function of the time, nothing is stored).
function Zoom.Displayed(now)
	local to = st.to

	if not to then
		return Zoom.TargetRange()
	end

	local startAt = st.startAt

	if not startAt then
		return to
	end

	local u = (now - startAt) / Zoom.TRANSITION
	local from = st.from

	if u <= 0 then
		return from
	end

	if u >= 1 then
		return to
	end

	-- smoothstep, then a straight line in the logarithm of the range: a zoom looks even in ratio, not in metres
	u = u * u * (3 - 2 * u)

	return exp(math.Remap(u, 0, 1, log(from), log(to)))
end

-- Forgets everything (the option went off, the tests).
function Zoom.Reset()
	st.mode, st.cand, st.candSince = nil, nil, nil
	st.from, st.to, st.startAt = nil, nil, nil
end

-- tells the server the new target now (Radar.RangeChanged does nothing while the client does not want the contacts)
local function tellServer()
	if Radar and Radar.RangeChanged then
		Radar.RangeChanged()
	end
end

-- Observation of the place at `now` (seconds): in a vehicle or not, indoors or not. Accepts a mode after it has held for the delay, and starts the glide when the
-- target changed (a mode change, or the slider of the mode in use moved). The first observation sets the mode at once, with no delay and no glide.
function Zoom.Observe(now, inVehicle, indoor)
	local want = (inVehicle and "vehicle") or (indoor and "indoor") or "foot"
	local first = st.mode == nil

	if first then
		st.mode = want
		st.cand = nil
	elseif want == st.mode then
		st.cand = nil
	else
		if st.cand ~= want then
			st.cand, st.candSince = want, now
		end

		-- the convar holds a 32 bit float (0.1 is 0.10000000149): the comparison leaves a millionth of a second of room
		if now - st.candSince >= clampDelay(DelayConVar:GetFloat()) - 1e-6 then
			st.mode = want
			st.cand = nil
		end
	end

	local target = Zoom.TargetRange()

	if first or not st.to then
		st.from, st.to, st.startAt = target, target, nil

		return
	end

	if target ~= st.to then
		st.from, st.to, st.startAt = Zoom.Displayed(now), target, now
		tellServer()
	end
end

-- The median of the free distances (metres), each capped at NARROW_CAP, is under NARROW_IN: narrow; over NARROW_OUT: not; in between: `was`. No distance: not narrow.
local scratch = {}

function Zoom.Narrow(distances, was)
	local n = #distances

	if n == 0 then
		return false
	end

	local cap = Zoom.NARROW_CAP

	-- a copy, capped and sorted by insertion (a handful of values, no allocation)
	for i = 1, n do
		local d = distances[i]

		if d > cap then
			d = cap
		end

		local j = i - 1

		while j >= 1 and scratch[j] > d do
			scratch[j + 1] = scratch[j]
			j = j - 1
		end

		scratch[j + 1] = d
	end

	local median

	if n % 2 == 1 then
		median = scratch[(n + 1) / 2]
	else
		median = (scratch[n / 2] + scratch[n / 2 + 1]) / 2
	end

	if median < Zoom.NARROW_IN then
		return true
	elseif median > Zoom.NARROW_OUT then
		return false
	end

	return was and true or false
end

-- Indoors is under a ceiling AND narrow.
function Zoom.IsIndoor(roofed, narrow)
	return roofed and narrow and true or false
end

-- the probe's memory and the eight rays' tables (made once: only the two Vectors of a ray are written again)
local probe = {t = -1000, x = 0, y = 0, z = 0, indoor = false, narrow = false}
local rays, dists

local function makeRays()
	rays, dists = {}, {}

	for i = 1, 8 do
		local a = (i - 1) * math.pi / 4

		rays[i] = {
			dx = math.cos(a), dy = math.sin(a),
			params = {start = Vector(0, 0, 0), endpos = Vector(0, 0, 0), mask = MASK_SOLID_BRUSHONLY, output = {}}
		}
	end
end

-- Whether the player is indoors now: asks the engine at most every PROBE_MIN seconds, and only if the player moved PROBE_MOVE units or PROBE_IDLE seconds went by.
-- Replaced by the tests. A failure of the engine call counts as "not indoors".
function Zoom.Probe(ply, now)
	local dt = now - probe.t

	if dt < PROBE_MIN then
		return probe.indoor
	end

	local pos = ply:GetPos()
	local x, y, z = pos.x, pos.y, pos.z

	if dt < PROBE_IDLE then
		local dx, dy, dz = x - probe.x, y - probe.y, z - probe.z

		if dx * dx + dy * dy + dz * dz < PROBE_MOVE_SQ then
			return probe.indoor
		end
	end

	probe.t, probe.x, probe.y, probe.z = now, x, y, z

	local M = GryMod.Minimap
	local Floors = M and M.Floors
	local level = Floors and Floors.CurrentAt and Floors.CurrentAt(pos)
	local roofed = level ~= nil and level ~= false and not level.open

	if roofed then
		if not rays then
			makeRays()
		end

		local capUnits = Zoom.NARROW_CAP / S.METRES_PER_UNIT
		local toMetres = S.METRES_PER_UNIT
		local n = 0

		for i = 1, 8 do
			local ray = rays[i]
			local params = ray.params
			local start, endpos = params.start, params.endpos

			start.x, start.y, start.z = x, y, z + RAY_HEIGHT
			endpos.x, endpos.y, endpos.z = x + ray.dx * capUnits, y + ray.dy * capUnits, z + RAY_HEIGHT

			local ok, tr = pcall(util.TraceLine, params)

			n = n + 1

			if ok and type(tr) == "table" and tr.Hit then
				dists[n] = tr.Fraction * capUnits * toMetres
			else
				dists[n] = Zoom.NARROW_CAP
			end
		end

		probe.narrow = Zoom.Narrow(dists, probe.narrow)
	else
		probe.narrow = false
	end

	probe.indoor = Zoom.IsIndoor(roofed, probe.narrow)

	return probe.indoor
end

-- Called at each frame the radar is fed (Radar.Feed). Does nothing and asks nothing while the option is off (and forgets the state, so that switching it
-- on starts from the place the player is in).
function Zoom.Update(ply, now)
	if not AutoConVar:GetBool() then
		if st.mode then
			Zoom.Reset()
		end

		return
	end

	local inVehicle = ply:InVehicle() and true or false
	local indoor = false

	if not inVehicle then
		indoor = Zoom.Probe(ply, now) and true or false
	end

	Zoom.Observe(now, inVehicle, indoor)
end
