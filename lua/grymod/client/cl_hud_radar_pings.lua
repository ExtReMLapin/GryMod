-- The explosion rings of the radar: the original's icon type 6, an expanding ring at the place of an explosion. The server says where and how big
-- (server/sv_radar_pings.lua); here a ring is kept for two seconds and handed to the radar as a marker through the marker sources
-- (cl_hud_radar_sources.lua), so it has the radar's range, zoom and frame like the rest. The numbers are the original's (CryGame.dll, the explosion list of
-- CHUDRadar::Update; the research notes of the project have the addresses):
--   * a ring lives 2 seconds and fades straight from full to nothing;
--   * its radius, in radar pixels, is (age + 1) * 4 * min(size, 4); the icon is drawn at 10 times that in percent;
--   * it is not drawn once it is wider than 43 pixels (the radar's radius), nor when its centre is farther than 62.9 pixels (0.7 * distance^2 above 1.5 * 43^2);
--   * a ring of more than 4 makes ONE echo of about half its size (0.3 to 0.7), about 0.05 s after it (between 0 and 0.15 s): a big blast shows two or three rings.
-- Nothing runs while there is no ring: the marker source is added with the first one and removed with the last. Loaded after cl_hud_radar_sources.lua.

GryMod = GryMod or {}

local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared
local API = GryMod.Radar

local Switch = CreateClientConVar("gry_hud_radarpings", "1", true, false,
	"Show the explosions as rings on the radar (the server's gry_radar_pings sends them); 0 hides them")

local Pings = {}
Radar.Pings = Pings

-- How many rings are kept at once (the oldest goes first).
Pings.MAX = 16

-- The key of the marker source.
Pings.KEY = "gry_pings"

-- The clock, the place of the player, the radar's range and the dice, as fields so that the tests can replace them.
Pings.Time = RealTime

function Pings.Origin()
	local ply = LocalPlayer()

	if IsValid(ply) then
		return ply:GetPos()
	end

	return nil
end

Pings.Range = function()
	return Radar.Range()
end

-- A number from 0 to 1.
Pings.Random = math.random

-- [i] = {pos, size, born, echo = the age at which it makes its echo (nil: it makes none, or already did)}
local list = {}

-- The markers handed to the radar, kept from one frame to the next (the HUD asks every frame).
local markers = {}

function Pings.Count()
	return #list
end

function Pings.Size(i)
	return list[i] and list[i].size
end

function Pings.Born(i)
	return list[i] and list[i].born
end

-- The radius of a ring of `size` at `age` seconds, in radar pixels.
function Pings.Radius(size, age)
	return (age + 1) * 4 * math.min(size, S.PING_DRAW_MAX_SIZE)
end

-- How much of the ring is left: 1 at its birth, 0 at the end of its life.
function Pings.Alpha(age)
	return math.Clamp(1 - age / S.PING_LIFETIME, 0, 1)
end

local source

-- Forgets every ring (and takes the source away).
function Pings.Clear()
	for i = #list, 1, -1 do
		list[i] = nil
	end

	API.RemoveSource(Pings.KEY)
end

-- Adds a ring at `pos` (a Vector) of `size` metres at the time `born` (the clock when not given). Returns whether it was kept: not when the player switched the
-- rings off or the position is not valid.
function Pings.Add(pos, size, born)
	if not Switch:GetBool() or not isvector(pos) or pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then
		return false
	end

	size = math.Clamp(isnumber(size) and size == size and size or S.PING_KINDS.explosion, S.PING_MIN_SIZE, S.PING_MAX_SIZE)
	born = born or Pings.Time()

	if #list >= Pings.MAX then
		table.remove(list, 1)
	end

	-- only a ring above 4 has an echo; its moment is between 0 and 0.15 s
	local echo = size > S.PING_ECHO_ABOVE and ((Pings.Random() * 2 - 1) * 0.1 + 0.05) or nil

	list[#list + 1] = {pos = pos, size = size, born = born, echo = echo}

	if not API.HasSource(Pings.KEY) then
		API.AddSource(Pings.KEY, source)
	end

	return true
end

-- The message of the server (sv_radar_pings.lua): the place and the size in half metres.
function Pings.ReadMessage()
	local pos = net.ReadVector()
	local size = S.PingFromWire(net.ReadUInt(5))

	Pings.Add(pos, size)
end

net.Receive("gry_radar_ping", Pings.ReadMessage)

-- Removes the rings whose two seconds are over and makes the echoes that are due.
function Pings.Update(now)
	for i = #list, 1, -1 do
		local ping = list[i]
		local age = now - ping.born

		if age > S.PING_LIFETIME then
			table.remove(list, i)
		elseif ping.echo and age > ping.echo then
			ping.echo = nil
			-- an echo is half the size, a little more or less (0.3 to 0.7), and starts now; made at the end of the list so that this loop does not meet it
			local size = ping.size * (0.5 + 0.2 * (Pings.Random() * 2 - 1))

			if #list < Pings.MAX then
				local echo = size > S.PING_ECHO_ABOVE and ((Pings.Random() * 2 - 1) * 0.1 + 0.05) or nil

				list[#list + 1] = {pos = ping.pos, size = size, born = now, echo = echo}
			end
		end
	end
end

-- The 0.7 * distance^2 limit of the original, in radar pixels: 1.5 * 43^2.
local REACH2 = 1.5 * S.PIXELS * S.PIXELS

-- The marker source: the rings as markers of type 6 {pos, alpha, scale (percent), id}. Takes itself away when there is no ring left.
source = function()
	local now = Pings.Time()
	Pings.Update(now)

	local origin = Pings.Origin()
	local range = Pings.Range()
	local pixels = S.PIXELS / range
	local count = 0

	for i = 1, #list do
		local ping = list[i]
		local radius = Pings.Radius(ping.size, now - ping.born)
		local near = true

		if origin then
			local dx, dy = (ping.pos.x - origin.x) * S.METRES_PER_UNIT * pixels, (ping.pos.y - origin.y) * S.METRES_PER_UNIT * pixels
			near = 0.7 * (dx * dx + dy * dy) <= REACH2
		end

		if radius <= S.PIXELS and near then
			count = count + 1
			local marker = markers[count]

			if not marker then
				marker = {type = 6, subtype = 0}
				markers[count] = marker
			end

			marker.pos = ping.pos
			marker.scale = radius * 10
			marker.alpha = Pings.Alpha(now - ping.born)
			marker.id = ping.born
		end
	end

	for i = #markers, count + 1, -1 do
		markers[i] = nil
	end

	if #list == 0 then
		API.RemoveSource(Pings.KEY)
	end

	return markers
end
