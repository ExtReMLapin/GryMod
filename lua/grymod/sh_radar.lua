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
-- A hostile that is alerted is first noticed within 15 of these pixels (26.2 m).
S.GATE_PIXELS = 15
-- The entities are looked for in a box 1.3 times the radius around the player, so that nothing pops in at the edge.
S.SCAN_FACTOR = 1.3
-- How long the unit that hurt the player stays marked.
S.MARKER_SECONDS = 10
-- A unit more than this many metres above or below the player is not drawn.
S.HEIGHT_LIMIT = 500
-- No more contacts than this in one message (the movie draws as many as it is given; this bounds the work and the traffic).
S.MAX_CONTACTS = 48

-- The message: positions in steps of 8 units (a third of a metre), 13 bits each (the map is within 32768 units), the
-- facing in 512 steps of the circle, 68 bits for a contact.
S.POS_STEP = 8
S.POS_BITS = 13
S.YAW_STEPS = 512

function S.GateMetres()
	return S.GATE_PIXELS * S.RANGE / S.PIXELS
end

function S.GateUnits()
	return S.GateMetres() / S.METRES_PER_UNIT
end

function S.ScanUnits()
	return S.RANGE * S.SCAN_FACTOR / S.METRES_PER_UNIT
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
		net.WriteUInt(c.type, 2)
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
		c.type = net.ReadUInt(2)
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
