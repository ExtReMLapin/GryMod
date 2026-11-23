-- What the server and the client agree on for the radar contacts: the numbers of the original radar (CHUDRadar::Update,
-- see docs/superpowers/plans/2026-11-21-radar-research.md) and the compact message that carries a list of contacts
-- from the server to a player. Loaded in both realms.

GryMod = GryMod or {}

local S = {}
GryMod.RadarShared = S

-- A Source unit in metres (a 72 unit player is 1.83 m).
S.METRES_PER_UNIT = 0.01905
-- The radar's radius in metres, and the stage pixels it is drawn over (43 pixels for 75 m).
S.RANGE = 75
S.PIXELS = 43
-- The player may choose another radius (the client's gry_radar_range, sent with its request): the original's is the constant 75 m, or the
-- level's `mapRadius`; nothing in the demo changes it while playing. Between these, in metres.
S.MIN_RANGE = 5
S.MAX_RANGE = 100
-- A hostile that is alerted is first noticed within 15 of these pixels (26.2 m).
S.GATE_PIXELS = 15
-- The entities are looked for in a sphere this many times the radius around the player, so that nothing pops in at the edge of the radar window. The window is
-- the glass of the movie (GryMod.FlashRadar.FRAME): its farthest corner is 90 radar pixels from the player, 2.09 radiuses; the original's smaller polygon
-- (74.9 pixels, 1.74 radiuses) was already past the 1.3 used before, so a contact in the corners never came.
S.SCAN_FACTOR = 2.1
-- How long the unit that hurt the player stays marked.
S.MARKER_SECONDS = 10
-- A unit more than this many metres above or below the player is not drawn.
S.HEIGHT_LIMIT = 500
-- No more contacts than this in one message (the movie draws as many as it is given; this bounds the work and the traffic).
S.MAX_CONTACTS = 48

-- The subtype of a contact (the movie's icons have 0 to 4: 0 tagged and not hostile, 1 marker of a non hostile, 2 hostile and
-- calm, 3 alerted, 4 fighting the player). This one is GryMod's own: an ally of the player (the server's Friendly.Relation).
-- It has no icon of its own: the client draws the calm icon of its type, tinted blue.
S.SUB_ALLY = 5

-- The message: positions in steps of 8 units (a third of a metre), 13 bits each (the map is within 32768 units), the
-- facing in 512 steps of the circle, 69 bits for a contact (the icon type has three bits: 1 to 4 are used, see the movie's Units clip).
S.POS_STEP = 8
S.POS_BITS = 13
S.YAW_STEPS = 512

-- A radius that is usable: a number in whole metres between the bounds; anything else (nothing, text, NaN, zero, negative: an older client
-- that sends nothing) is the original's 75.
function S.ClampRange(range)
	if type(range) ~= "number" or range ~= range or range <= 0 then
		return S.RANGE
	end

	return math.Clamp(math.floor(range + 0.5), S.MIN_RANGE, S.MAX_RANGE)
end

-- What follows the radius, which defaults to the original's: the gate of the first notice (15 pixels of the radar) and the search radius.
function S.GateMetres(range)
	return S.GATE_PIXELS * (range or S.RANGE) / S.PIXELS
end

function S.GateUnits(range)
	return S.GateMetres(range) / S.METRES_PER_UNIT
end

function S.ScanUnits(range)
	return (range or S.RANGE) * S.SCAN_FACTOR / S.METRES_PER_UNIT
end

-- The explosion pings (the original's icon type 6, an expanding ring at the place of an explosion; READ in CryGame.dll, CHUDRadar::Update and the explosion
-- handler). A ping lives 2 seconds; its size is held to 8 when it is made and to 4 when it is drawn, and a ring of more than 4 makes one echo; the
-- explosion event reaches the radar when it is within 250 m of the player.
S.PING_LIFETIME = 2
S.PING_MIN_SIZE = 0.5
S.PING_MAX_SIZE = 8
S.PING_DRAW_MAX_SIZE = 4
S.PING_ECHO_ABOVE = 4
S.PING_RANGE = 250
-- The names a kind of ping may have (GryMod.API.ReportRadarPing), and the size each is: about the radius of the blast in metres.
S.PING_KINDS = {small = 2, explosion = 4, big = 8}

-- The size of a ping for a kind: nothing is the explosion, a name is its size, a number is held between the smallest and the biggest. Anything else (an
-- unknown name, NaN, a table) is not a kind: nil.
function S.PingSize(kind)
	if kind == nil then
		return S.PING_KINDS.explosion
	end

	if isstring(kind) then
		return S.PING_KINDS[kind]
	end

	if isnumber(kind) and kind == kind then
		return math.Clamp(kind, S.PING_MIN_SIZE, S.PING_MAX_SIZE)
	end

	return nil
end

-- The size of the ping of a blast of `radius` Source units: the same in metres, held. nil when it is not a number.
function S.PingSizeOfRadius(radius)
	if not isnumber(radius) or radius ~= radius then
		return nil
	end

	return math.Clamp(radius * S.METRES_PER_UNIT, S.PING_MIN_SIZE, S.PING_MAX_SIZE)
end

-- The size on the wire: half metres in 5 bits (1 to 16, never 0).
function S.PingToWire(size)
	return math.Clamp(math.floor(size * 2 + 0.5), 1, 16)
end

function S.PingFromWire(wire)
	return math.Clamp(wire, 1, 16) / 2
end

-- The detection the server adds for the danger bar and the hexagon (server/sv_radar.lua, Radar.Detect): two numbers from 0 to 2, for the hostiles that are soldiers
-- and for the ones that are machines, written in 2 bits each: 0 nothing, 1 a hostile hears the player (or looks for him), 2 one sees him or has him as enemy.
-- The client turns them into the targets of the bar and the hexagon (0, 0.5, 1: the same scale as its contacts).
S.DETECT_TARGETS = {[0] = 0, [1] = 0.5, [2] = 1}
-- The icon types that are machines for the AI (the hexagon's): 2 flying, 3 machines and vehicles. The client's Hex.VEHICLE_TYPES says the same.
S.VEHICLE_TYPES = {[2] = true, [3] = true}

function S.WriteDetect(puppet, vehicle)
	net.WriteUInt(math.Clamp(puppet, 0, 2), 2)
	net.WriteUInt(math.Clamp(vehicle, 0, 2), 2)
end

local POS_LIMIT = 2 ^ (S.POS_BITS - 1)

local function quantisePosition(v)
	local q = math.floor((v or 0) / S.POS_STEP + 0.5)

	if q ~= q then
		return 0
	end

	return math.Clamp(q, -POS_LIMIT, POS_LIMIT - 1)
end

local function quantiseYaw(yaw)
	local q = math.floor(((yaw or 0) % 360) / 360 * S.YAW_STEPS + 0.5) % S.YAW_STEPS

	if q ~= q then
		return 0
	end

	return q
end

-- Writes a list of contacts {id, x, y, z, yaw, type, sub, marker, big} to the message being built (no more than the limit).
function S.Write(contacts)
	local count = math.min(#contacts, S.MAX_CONTACTS)

	net.WriteUInt(count, 7)

	for i = 1, count do
		local c = contacts[i]

		net.WriteUInt(c.id, 13)
		net.WriteUInt(c.type, 3)
		net.WriteUInt(c.sub, 3)
		net.WriteBool(c.marker and true or false)
		net.WriteBool(c.big and true or false)
		net.WriteInt(quantisePosition(c.x), S.POS_BITS)
		net.WriteInt(quantisePosition(c.y), S.POS_BITS)
		net.WriteInt(quantisePosition(c.z), S.POS_BITS)
		net.WriteUInt(quantiseYaw(c.yaw), 9)
	end
end

-- Reads what Write wrote: a list of contacts with the positions and yaws as they were quantised.
function S.Read()
	local contacts = {}
	local count = math.min(net.ReadUInt(7), S.MAX_CONTACTS)

	for i = 1, count do
		local c = {}

		c.id = net.ReadUInt(13)
		c.type = net.ReadUInt(3)
		c.sub = net.ReadUInt(3)
		c.marker = net.ReadBool()
		c.big = net.ReadBool()
		c.x = net.ReadInt(S.POS_BITS) * S.POS_STEP
		c.y = net.ReadInt(S.POS_BITS) * S.POS_STEP
		c.z = net.ReadInt(S.POS_BITS) * S.POS_STEP
		c.yaw = net.ReadUInt(9) * 360 / S.YAW_STEPS
		contacts[i] = c
	end

	return contacts
end

-- Whether two lists would send the same message (so that nothing needs to be sent).
function S.Same(a, b)
	local count = math.min(#a, S.MAX_CONTACTS)

	if count ~= math.min(#b, S.MAX_CONTACTS) then
		return false
	end

	for i = 1, count do
		local x, y = a[i], b[i]

		if x.id ~= y.id or x.type ~= y.type or x.sub ~= y.sub or (x.marker and true or false) ~= (y.marker and true or false)
			or (x.big and true or false) ~= (y.big and true or false) or quantisePosition(x.x) ~= quantisePosition(y.x)
			or quantisePosition(x.y) ~= quantisePosition(y.y) or quantisePosition(x.z) ~= quantisePosition(y.z)
			or quantiseYaw(x.yaw) ~= quantiseYaw(y.yaw) then
			return false
		end
	end

	return true
end
