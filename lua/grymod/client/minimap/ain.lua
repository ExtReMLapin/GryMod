-- GryMod minimap: module ain. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.AIN = GryMod.Minimap.AIN or {}

-- Strict reader of the engine's node graph (maps/graphs/<map>.ain, version 37). The minimap uses the ground nodes to find the levels (floors)
-- of a map (module floors). Layout, all little-endian, no padding, size = 16 + 65 * N + 14 * L:
--   header      int32 version (37), int32 map version, int32 N (0 to 1500)
--   N nodes     61 bytes: float32 x, y, z, yaw; 10 float32 vertical offsets (one per hull, not read); int8 type; uint16 info; int16 zone
--   links       int32 L, then L records of 14 bytes: int16 src, int16 dest (0-based), 10 uint8 move capabilities (not read)
--   lookup      N int32
-- The whole file is read with one file.Read and decoded from the string with string.byte ranges and arithmetic: no ffi in this build, no
-- engine call and no table or closure created per value besides the result itself.

local AIN = GryMod.Minimap.AIN

local VERSION = 37
local MAX_NODES = 1500
local HEADER_SIZE = 16 -- version, map version, N, L
local NODE_SIZE = 61
local LINK_SIZE = 14
local LOOKUP_SIZE = 4
local NODE_STRIDE = NODE_SIZE + LOOKUP_SIZE -- 65: the node and its lookup entry

AIN.NODE_TYPE = {ANY = 0, DELETED = 1, GROUND = 2, AIR = 3, CLIMB = 4, WATER = 5}

-- 2^(e - 127) for the exponent field e of a normal float32 (1 to 254); e = 0 (zero, denormals) gives 0 and e = 255 (infinity, NaN) is refused
local POW2 = {}

for e = 1, 254 do
	POW2[e] = 2 ^ (e - 127)
end

local floor = math.floor
local byte = string.byte
local type = type

-- int32 / int16 signed and uint16 from the string at byte position i
local function int32(s, i)
	local a, b, c, d = byte(s, i, i + 3)
	local n = a + b * 256 + c * 65536 + d * 16777216

	if n >= 2147483648 then
		n = n - 4294967296
	end

	return n
end

local function int16(s, i)
	local a, b = byte(s, i, i + 1)
	local n = a + b * 256

	if n >= 32768 then
		n = n - 65536
	end

	return n
end

-- float32 at byte position i: sign, 8-bit exponent, 23-bit mantissa. Zero and denormals give 0 (never -0); infinity and NaN give nil
local function float32(s, i)
	local b1, b2, b3, b4 = byte(s, i, i + 3)
	local e = (b4 % 128) * 2 + floor(b3 / 128)

	if e == 0 then
		return 0
	elseif e == 255 then
		return nil
	end

	local mant = (b3 % 128) * 65536 + b2 * 256 + b1
	local v = (1 + mant / 8388608) * POW2[e]

	if b4 >= 128 then
		return -v
	end

	return v
end

-- Parse(bytes) -> {version, mapVersion, nodes = {{x, y, z, yaw, type, info, zone}...}, links = {{src, dest}...}, lookup = {int...}} | nil, reason
-- Node and link indices of the result are 1-based. Every call builds new tables.
function AIN.Parse(bytes)
	if type(bytes) ~= "string" then
		return nil, "not a string"
	end

	local size = #bytes

	if size < HEADER_SIZE then
		return nil, "too short"
	end

	local version = int32(bytes, 1)

	if version ~= VERSION then
		return nil, "bad version"
	end

	local count = int32(bytes, 9)

	if count < 0 or count > MAX_NODES then
		return nil, "bad node count"
	end

	-- the link count sits after the nodes: its 4 bytes must be there before they are read
	local linkAt = 13 + NODE_SIZE * count

	if size < linkAt + 3 then
		return nil, "truncated"
	end

	local linkCount = int32(bytes, linkAt)

	if linkCount < 0 then
		return nil, "bad link count"
	end

	-- the size is exact: the header (16), a node and a lookup entry per node (65), a record per link (14). The test is made before any loop, so an
	-- absurd count costs nothing
	local expected = HEADER_SIZE + NODE_STRIDE * count + LINK_SIZE * linkCount

	if size < expected then
		return nil, "truncated (link count exceeds the data)"
	elseif size > expected then
		return nil, "trailing bytes"
	end

	local nodes = {}
	local o = 13

	for i = 1, count do
		local x, y, z, yaw = float32(bytes, o), float32(bytes, o + 4), float32(bytes, o + 8), float32(bytes, o + 12)

		if not (x and y and z and yaw) then
			return nil, "non-finite float in node " .. i
		end

		local t = byte(bytes, o + 56)

		if t >= 128 then
			t = t - 256
		end

		local info = byte(bytes, o + 57) + byte(bytes, o + 58) * 256

		nodes[i] = {x = x, y = y, z = z, yaw = yaw, type = t, info = info, zone = int16(bytes, o + 59)}
		o = o + NODE_SIZE
	end

	local links = {}

	o = linkAt + 4

	for i = 1, linkCount do
		local src, dest = int16(bytes, o), int16(bytes, o + 2)

		if src < 0 or src >= count or dest < 0 or dest >= count then
			return nil, "link out of range"
		end

		links[i] = {src = src + 1, dest = dest + 1}
		o = o + LINK_SIZE
	end

	local lookup = {}

	for i = 1, count do
		lookup[i] = int32(bytes, o)
		o = o + LOOKUP_SIZE
	end

	return {version = version, mapVersion = int32(bytes, 5), nodes = nodes, links = links, lookup = lookup}
end

-- Load(mapName) -> graph | nil, reason. One file.Read of maps/graphs/<mapName>.ain; "no graph" when the file is missing
function AIN.Load(mapName)
	if type(mapName) ~= "string" or mapName == "" then
		return nil, "bad map name"
	end

	-- the name goes into a path: no directory part, no parent reference
	if string.find(mapName, "[/\\]") or string.find(mapName, "..", 1, true) then
		return nil, "bad map name"
	end

	local bytes = file.Read("maps/graphs/" .. mapName .. ".ain", "GAME")

	if not bytes then
		return nil, "no graph"
	end

	return AIN.Parse(bytes)
end
