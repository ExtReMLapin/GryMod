-- The big map: its markers (GryMod.Map.Markers). The registry of marker sources for third parties (the same records as the radar's sources, see
-- GryMod.Radar.AddSource), what an objective becomes on the map, the 8 x 8 grid with its letters and numbers, the size of an icon at a zoom and the pin
-- of a marker that is off the window. Pure: a position is anything with x and y; nothing is read from the engine here (the panel draws).

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Markers = GryMod.Map.Markers or {}

local Markers = GryMod.Map.Markers

-- how many markers the map takes from its sources at most
Markers.MAX_MARKERS = 256
-- how many errors in a row a source may throw before it is removed
Markers.SOURCE_MAX_ERRORS = 3
-- how big a finished objective is drawn (alpha), when the player wants them
Markers.FINISHED_ALPHA = 0.45

local floor = math.floor

local function finite(n)
	return type(n) == "number" and n - n == 0
end

-- the sources ---------------------------------------------------------------------------------------------------------------------------------
-- They live through a reload of this file (the registry is kept on the table).
local state = Markers._sources or {fns = {}, order = {}, errors = {}}
Markers._sources = state

local fns, order, errors = state.fns, state.order, state.errors

-- Adds (or replaces, keeping its place) a source. `fn` is called every frame the map is drawn, with no argument, and returns an array of markers
-- {pos = Vector, type = 1 to 7, subtype = 0 to 4 (optional), alpha = 0 to 1 (optional), scale = percent (optional), id = anything (optional),
-- yaw = degrees (optional), label = text (optional), main = true to ring it (optional)}. Returns true, or false and why.
function Markers.AddSource(key, fn)
	if key == nil or key ~= key then
		return false, "invalid key"
	end

	if type(fn) ~= "function" then
		return false, "the source must be a function"
	end

	if fns[key] == nil then
		order[#order + 1] = key
	end

	fns[key] = fn
	errors[key] = nil

	return true
end

function Markers.RemoveSource(key)
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

function Markers.HasSource(key)
	return key ~= nil and fns[key] ~= nil
end

-- The keys of the sources, in the order of their markers (a new table).
function Markers.Sources()
	local list = {}

	for i = 1, #order do
		list[i] = order[i]
	end

	return list
end

local snapshot = {}

-- Asks every source for its markers and puts them in `buffer` (in the order of the sources; the markers are the sources' own tables), at most MAX_MARKERS;
-- what the buffer held past them is cleared. Returns how many. A source runs under pcall: one that throws is skipped this frame and removed, with one
-- message, after SOURCE_MAX_ERRORS errors in a row.
function Markers.Collect(buffer)
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

					if type(result) == "table" then
						for j = 1, #result do
							if count >= Markers.MAX_MARKERS then
								break
							end

							count = count + 1
							buffer[count] = result[j]
						end
					end
				else
					local failures = (errors[key] or 0) + 1

					errors[key] = failures

					if failures >= Markers.SOURCE_MAX_ERRORS then
						Markers.RemoveSource(key)

						if ErrorNoHalt then
							ErrorNoHalt("[GryMod] big map marker source '" .. tostring(key) .. "' removed after " .. failures .. " errors in a row: " .. tostring(result) .. "\n")
						end
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

-- the objectives ------------------------------------------------------------------------------------------------------------------------------

-- The markers of the objectives (GryMod.Objectives.List(): {id, title, primary, main, state, pos, radar, ...}) in `out` (reused, the tail cleared), and how
-- many. An objective that asked not to be on the radar and maps (radar = false), one with no usable position, and (unless `showFinished`) one that is done
-- or failed are left out. A finished one is drawn greyed, with no ring. The records are the objective's own numbers: type 5 (the objective arrow), subtype
-- 0 primary, 2 secondary, the title as the label.
function Markers.FromObjectives(list, showFinished, out)
	local count = 0

	if type(list) == "table" then
		for i = 1, #list do
			local o = list[i]

			if type(o) == "table" and o.radar ~= false and (isvector(o.pos) or type(o.pos) == "table") and finite(o.pos.x) and finite(o.pos.y) then
				local finished = o.state == "done" or o.state == "failed"

				if showFinished or not finished then
					count = count + 1

					local m = out[count]

					if type(m) ~= "table" then
						m = {}
						out[count] = m
					end

					m.pos, m.type, m.subtype = o.pos, 5, o.primary and 0 or 2
					m.id, m.label, m.main = o.id, o.title, o.main == true and not finished
					m.finished, m.alpha = finished, finished and Markers.FINISHED_ALPHA or nil
				end
			end
		end
	end

	for i = #out, count + 1, -1 do
		out[i] = nil
	end

	return count
end

-- the grid -------------------------------------------------------------------------------------------------------------------------------------
-- 8 x 8 over the bounds, as the original's: the numbers 1 to 8 across the screen, the letters A to H down it. The screen's horizontal axis is world -Y and
-- its vertical axis is world -X (the map is not turned), so A1 is the cell at the largest X and the largest Y, the top left of the picture.

local LETTERS = "ABCDEFGH"

-- The letter, the number and the text ("C4") of the grid cell that holds the world point (x, y); a point outside is given the nearest cell. nil for bounds that
-- are not usable.
function Markers.GridRef(b, x, y)
	if type(b) ~= "table" or not (finite(b.x0) and finite(b.x1) and finite(b.y0) and finite(b.y1)) or b.x1 <= b.x0 or b.y1 <= b.y0 or not (finite(x) and finite(y)) then
		return nil
	end

	local row = floor((b.x1 - x) / (b.x1 - b.x0) * 8) + 1
	local column = floor((b.y1 - y) / (b.y1 - b.y0) * 8) + 1

	row = row < 1 and 1 or (row > 8 and 8 or row)
	column = column < 1 and 1 or (column > 8 and 8 or column)

	local letter = string.sub(LETTERS, row, row)

	return letter, column, letter .. column
end

-- The nine world X lines and the nine world Y lines of the grid, in increasing order.
function Markers.GridLines(b)
	local xs, ys = {}, {}

	for i = 0, 8 do
		xs[i + 1] = b.x0 + (b.x1 - b.x0) * i / 8
		ys[i + 1] = b.y0 + (b.y1 - b.y0) * i / 8
	end

	return xs, ys
end

-- icons ----------------------------------------------------------------------------------------------------------------------------------------

-- The size in pixels of an icon whose own size is `base`, at `zoom`: the original's (zoom + 2) * 0.25, so an icon grows slowly while the map grows fast;
-- `scale` is the percent a source asks for (100 when it asks for none).
function Markers.IconSize(zoom, base, scale)
	if not finite(scale) or scale <= 0 then
		scale = 100
	end

	return (zoom + 2) * 0.25 * base * scale / 100
end

-- A marker at the screen point (sx, sy): where to draw it in the window `rect` {x, y, w, h}: the point itself when it is inside, else the nearest point of the
-- window less `margin` pixels. Returns x, y and whether it was pinned.
function Markers.Pin(sx, sy, rect, margin)
	local x0, y0, x1, y1 = rect.x + margin, rect.y + margin, rect.x + rect.w - margin, rect.y + rect.h - margin
	local x, y = sx, sy

	if x < x0 then x = x0 elseif x > x1 then x = x1 end
	if y < y0 then y = y0 elseif y > y1 then y = y1 end

	return x, y, x ~= sx or y ~= sy
end

-- The look of a marker: its shape ("diamond", "dot" or "ring") and its colour. The objective arrow (type 5) is green when primary and yellow when secondary,
-- as the radar's; a finished one is grey.
local PRIMARY_R, PRIMARY_G, PRIMARY_B = 107, 212, 90
local SECOND_R, SECOND_G, SECOND_B = 240, 196, 60

function Markers.Style(m)
	local kind = type(m) == "table" and m.type or nil

	if kind == 5 then
		if m.finished then
			return "diamond", 150, 150, 150
		end

		if m.subtype == 2 or m.subtype == 3 then
			return "diamond", SECOND_R, SECOND_G, SECOND_B
		end

		return "diamond", PRIMARY_R, PRIMARY_G, PRIMARY_B
	end

	if kind == 6 then
		return "ring", 255, 255, 255
	end

	if kind == 7 then
		return "dot", 90, 160, 255
	end

	return "dot", 235, 235, 235
end
