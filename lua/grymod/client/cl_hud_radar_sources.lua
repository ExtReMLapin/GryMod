-- The marker sources of the radar: anything (the objectives, the explosion rings, an addon's own points of interest) can put icons on the radar of the HUD
-- by giving the radar a function that returns the markers of the moment: GryMod.Radar.AddSource(key, fn) / GryMod.Radar.RemoveSource(key). The radar places
-- the markers with the rules of the original's icon types, which are not the same for every type (the evidence is in the radar notes of the project):
--   * type 5, the objective arrow: beyond the radar it STICKS TO THE BORDER of the radar (the edge variant of the icon, an arrow that points away from the
--     player); inside it is a glow. Primary is green (subtype 0), secondary is yellow (subtype 2); the original draws it at 75 percent size and alpha;
--   * type 7, the team mate: beyond the range it sticks to the CIRCLE of the range (the original clamps it by length, not to the frame);
--   * the other types (1 to 4 the units, 6 the explosion ring) are not clamped: they vanish when they leave the radar's frame, as the contacts do.
-- Loaded after cl_hud_radar_units.lua, whose Feed asks for the markers once per frame (Radar.FeedMarkers); with no source nothing is done at all.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared

-- The public table. (On the server GryMod.Radar is the radar's rules, sv_radar.lua: another realm, another table.)
local API = GryMod.Radar or {}
GryMod.Radar = API

local MarkersConVar = CreateClientConVar("gry_hud_radarmarkers", "1", true, false,
	"Show the markers that the objectives and other addons put on the radar (GryMod.Radar.AddSource); 0 hides them")

-- How many errors in a row a source may throw before the radar removes it.
Radar.SOURCE_MAX_ERRORS = 3

-- The sources: [key] = the function, in the order they were added, and the errors of each in a row. They live through a reload of this file.
local state = API._sources or {fns = {}, order = {}, errors = {}}
API._sources = state

local fns, order, errors = state.fns, state.order, state.errors

-- Adds (or replaces, keeping its place) a source. `fn` is called every frame the radar is drawn, with no argument, and returns an array of markers
-- {pos = Vector, type = 1 to 7, subtype = 0 to 4 (optional), alpha = 0 to 1 (optional), scale = percent of the icon (optional), id = anything (optional),
-- yaw = degrees (optional, the unit icons turn with it)}. Returns true, or false and why.
function API.AddSource(key, fn)
	if key == nil or key ~= key then
		return false, "invalid key"
	end

	if not isfunction(fn) then
		return false, "the source must be a function"
	end

	if fns[key] == nil then
		order[#order + 1] = key
	end

	fns[key] = fn
	errors[key] = nil

	return true
end

-- Takes a source away. Returns whether there was one.
function API.RemoveSource(key)
	if key == nil or fns[key] == nil then
		return false
	end

	fns[key] = nil
	errors[key] = nil

	for i = 1, #order do
		if order[i] == key then
			table.remove(order, i)

			break
		end
	end

	return true
end

function API.HasSource(key)
	return key ~= nil and fns[key] ~= nil
end

-- The keys of the sources, in the order of their markers (a new table).
function API.Sources()
	local list = {}

	for i = 1, #order do
		list[i] = order[i]
	end

	return list
end

local snapshot = {}

-- Asks every source for its markers and puts them in `buffer` (in the order of the sources; the markers are the sources' own tables, not copies), no more than
-- Radar.MAX_MARKERS; what the buffer held past them is cleared. Returns how many. A source runs under pcall: one that throws is skipped this frame and
-- removed, with one message, after Radar.SOURCE_MAX_ERRORS errors in a row (an answer that works starts the count again).
function Radar.CollectMarkers(buffer)
	local count = 0
	local sources = #order

	if sources > 0 then
		-- a snapshot of the keys: a source may add or remove sources (itself included) while it runs
		for i = 1, sources do
			snapshot[i] = order[i]
		end

		for i = 1, sources do
			local key = snapshot[i]
			local fn = fns[key]

			if fn then
				local ok, result = pcall(fn)

				if ok then
					errors[key] = nil

					if istable(result) then
						for j = 1, #result do
							if count >= Radar.MAX_MARKERS then
								break
							end

							count = count + 1
							buffer[count] = result[j]
						end
					end
				else
					local failures = (errors[key] or 0) + 1
					errors[key] = failures

					if failures >= Radar.SOURCE_MAX_ERRORS then
						API.RemoveSource(key)
						ErrorNoHalt("[GryMod] radar marker source '" .. tostring(key) .. "' removed after " .. failures .. " errors in a row: " .. tostring(result) .. "\n")
					end
				end
			end
		end

		for i = sources, 1, -1 do
			snapshot[i] = nil
		end
	end

	for i = #buffer, count + 1, -1 do
		buffer[i] = nil
	end

	return count
end

-- The frame of the icon: the type times 5 plus the subtype. The objective arrow (type 5) has the four pictures of the movie: 25 primary, 26 primary on the
-- edge (the arrow), 27 secondary, 28 secondary on the edge. The radar picks the edge one itself, so a source says only primary (subtype 0 or 1) or
-- secondary (2 or 3); subtype 4 has no picture and is primary.
function Radar.MarkerFrame(kind, subtype, edge)
	subtype = subtype or 0

	if kind == 5 then
		local secondary = subtype == 2 or subtype == 3

		return 25 + (secondary and 2 or 0) + (edge and 1 or 0)
	end

	return kind * 5 + subtype
end

local U = S.METRES_PER_UNIT

-- The original's size and alpha of an icon, when the source gives none: units as the contacts (the height decides), the objective arrow 75 and 75, a ring
-- 100 and 100 (the source sets its size), a team mate 100 times the height factor (4 times a unit's size) and 100.
local DEFAULT_ALPHA = {[5] = 75, [6] = 100, [7] = 100}

-- The entries for the movie, from the player's position and yaw (degrees) and the first `count` markers of a source: {id, x, y, rotation, frame, scale, alpha},
-- the same as Radar.Contacts gives. A marker that is not valid (no position, a type that is not 1 to 7, not a number) is left out, and one more than 500 m
-- above or below the player. `reuse` (optional) is a table to fill instead of a new one, as for Radar.Contacts: it and its entries are kept from one call to
-- the next.
function Radar.MarkerEntries(pos, yaw, markers, count, range, reuse)
	local list = reuse or {}
	local filled = 0

	if markers and pos and yaw == yaw then
		local radians = math.rad(yaw)
		local cos, sin = math.cos(radians), math.sin(radians)
		local pixels = U * S.PIXELS / (range or S.RANGE)
		local px, py, pz = pos.x, pos.y, pos.z

		for i = 1, math.min(count or #markers, Radar.MAX_MARKERS) do
			local m = markers[i]
			local at, kind

			if istable(m) then
				at, kind = m.pos, m.type
			end

			if isvector(at) and isnumber(kind) and kind >= 1 and kind <= 7 and kind == math.floor(kind) then
				local dx, dy, dz = at.x - px, at.y - py, at.z - pz

				if dx == dx and dy == dy and dz == dz and math.abs(dz) * U <= S.HEIGHT_LIMIT then
					-- x right, y down on the radar (up is where the player looks), as for the contacts
					local x = (dx * sin - dy * cos) * pixels
					local y = -(dx * cos + dy * sin) * pixels
					local show, edge = true, false
					local rotation = 180

					if kind == 5 then
						if not Radar.InsideFrame(x, y) then
							-- the arrow points away from the player: the base picture of the icons points down, turned clockwise by this
							rotation = math.deg(math.atan2(-x, y)) % 360
							x, y = Radar.BorderPoint(x, y)
							edge = true
						end
					elseif kind == 7 then
						local length = math.sqrt(x * x + y * y)

						if length > S.PIXELS then
							x, y = x * S.PIXELS / length, y * S.PIXELS / length
						end
					elseif not Radar.InsideFrame(x, y) then
						show = false
					end

					if show then
						if kind ~= 5 and isnumber(m.yaw) then
							rotation = (yaw - m.yaw + 180) % 360
						end

						local scale = m.scale

						if not isnumber(scale) or not (scale > 0) then
							if kind == 5 then
								scale = 75
							elseif kind == 6 then
								scale = 100
							elseif kind == 7 then
								scale = Radar.SizeFor(dz * U, false) * 4
							else
								scale = Radar.SizeFor(dz * U, false)
							end
						end

						local alpha = m.alpha

						if isnumber(alpha) and alpha == alpha then
							alpha = math.Clamp(alpha, 0, 1) * 100
						else
							alpha = DEFAULT_ALPHA[kind] or Radar.ALPHA
						end

						local subtype = isnumber(m.subtype) and m.subtype or 0
						local id = m.id

						if id == nil then
							id = i
						end

						filled = filled + 1
						local entry = reuse and list[filled]

						if not entry then
							entry = {}
							list[filled] = entry
						end

						entry.id = id
						entry.x = Radar.UNITS_CENTRE_X + x * Radar.UNITS_PIXEL
						entry.y = Radar.UNITS_CENTRE_Y + y * Radar.UNITS_PIXEL
						entry.rotation = rotation
						entry.frame = Radar.MarkerFrame(kind, subtype, edge)
						entry.scale = scale
						entry.alpha = alpha
						entry.tint = nil
					end
				end
			end
		end
	end

	if reuse then
		for i = #list, filled + 1, -1 do
			list[i] = nil
		end
	end

	return list
end

local buffer, entries = {}, {}

-- What the HUD's feed asks each frame: the placed markers of all the sources for this player, or nil when there is nothing to draw (no source, or the
-- player's gry_hud_radarmarkers is off). The list is reused: it is good until the next call.
function Radar.FeedMarkers(ply, range)
	if #order == 0 or not MarkersConVar:GetBool() then
		return nil
	end

	local count = Radar.CollectMarkers(buffer)

	if count == 0 then
		return nil
	end

	return Radar.MarkerEntries(ply:GetPos(), Flash.ViewYaw(ply), buffer, count, range, entries)
end

if GryMod.API and GryMod.API.AddFeature then
	GryMod.API.AddFeature("radarmarkers")
end
