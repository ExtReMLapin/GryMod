-- GryMod minimap: module view. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.View = GryMod.Minimap.View or {}

-- The maths from the world to the radar, the tiles around the player, and the drawing of the tiles under the contacts.
--   * View.ToRadar: the formula of Radar.Contacts (cl_hud_radar_units.lua), for one point: radar pixels, x right and y down, (0, 0) is the player.
--   * View.VisibleTiles: the tiles whose bounds touch the square around the player.
--   * View.Draw: each existing tile is drawn as ONE textured quad (surface.DrawPoly) through the transform of the radar: the quad's corners go from
--     the world to radar pixels, are clipped on the CPU against the map frame (still in radar pixels, so the clip does not depend on the
--     transform), then sent through the transform to the screen. It never creates a tile and never raises.
-- The map fills the whole radar window except the strip of the danger bar (the part of the frame to the left of its notch): it is clipped against
-- View.MapFrame(), the frame without that strip, computed from Radar.FRAME at run time. Sutherland-Hodgman is only right against a convex polygon:
-- the map frame is cut into convex pieces (View.ConvexPieces; one piece for the present frame, so one polygon a tile), the quad is clipped against
-- each piece, and a tile that crosses a seam is drawn as polygons that meet along the cut (nothing is drawn twice).
-- Cost: no engine call inside a loop, no closure per tile, the scratch buffers are module level and reused. Drawing allocates the vertices of the
-- polygons it sends (a few dozen small tables a frame).

local View = GryMod.Minimap.View

local floor, sin, cos, rad, huge = math.floor, math.sin, math.cos, math.rad, math.huge

-- The farthest corner of the radar's frame is about this many times the range from the player (the radar's own number, see the design).
local EXTENT_FACTOR = 1.75
-- More tiles than this around the player means a nonsense (a huge range or a tiny tile): nothing is drawn.
local MAX_TILES = 400
-- The coverage samples a regular grid of this many points on a side over the square of the range circle (the ones outside the circle are skipped).
local COVERAGE_GRID = 20
local EPSILON = 1e-9
-- The Source world is within 16384 units of the origin: a coordinate past this is garbage (and its tile indices would lose their precision).
local MAX_COORD = 1e6

View.LastError = nil

local function finite(v)
	return type(v) == "number" and v == v and v > -huge and v < huge
end

-- The radar's pixels for the range, read at call time (never captured at load).
local function radarPixels()
	local S = GryMod.RadarShared

	return S and finite(S.PIXELS) and S.PIXELS or nil
end

-- ToRadar -----------------------------------------------------------------------------------------------------------------------------------------

-- Radar pixels of the world point (x, y) for a player at (px, py) looking at `yawDeg`, the radar showing `rangeUnits` world units in PIXELS pixels.
-- With k = PIXELS / rangeUnits, dx = x - px, dy = y - py: rx = (dx * sin - dy * cos) * k and ry = -(dx * cos + dy * sin) * k, which is the formula of
-- Radar.Contacts (there k = METRES_PER_UNIT * PIXELS / metres). When `rotate` is not true the yaw is 0 (+X is up).
function View.ToRadar(px, py, yawDeg, x, y, rangeUnits, rotate)
	if not (finite(px) and finite(py) and finite(x) and finite(y)) then
		return nil, "bad coordinates"
	end

	if not finite(rangeUnits) or rangeUnits <= 0 then
		return nil, "bad range"
	end

	local yaw = 0

	if rotate then
		if not finite(yawDeg) then
			return nil, "bad yaw"
		end

		yaw = yawDeg
	end

	local pixels = radarPixels()

	if not pixels then
		return nil, "no radar"
	end

	local radians = rad(yaw)
	local s, c = sin(radians), cos(radians)
	local k = pixels / rangeUnits
	local dx, dy = x - px, y - py

	return (dx * s - dy * c) * k, -(dx * c + dy * s) * k
end

-- VisibleTiles ------------------------------------------------------------------------------------------------------------------------------------

-- The range of tile indices whose bounds touch the square of half-side `extent` around (px, py), for tiles T units wide; nil when there are too many.
local function tileRange(px, py, extent, T)
	local tx0, tx1 = floor((px - extent) / T), floor((px + extent) / T)
	local ty0, ty1 = floor((py - extent) / T), floor((py + extent) / T)

	if not (finite(tx0) and finite(tx1) and finite(ty0) and finite(ty1)) or (tx1 - tx0 + 1) * (ty1 - ty0 + 1) > MAX_TILES then
		return nil
	end

	return tx0, tx1, ty0, ty1
end

-- The edge of a tile in units, from the cache (the geometry is its job); nil when it is no usable number.
local function tileUnits(res, ppm)
	local Cache = GryMod.Minimap.Cache

	if type(Cache) ~= "table" or type(Cache.TileUnits) ~= "function" then
		return nil
	end

	local ok, T = pcall(Cache.TileUnits, res, ppm)

	if ok and finite(T) and T > 0 then
		return T
	end

	return nil
end

local function validLevel(level)
	return type(level) == "table" and type(level.id) == "string"
end

-- The tiles of `level` whose bounds touch the square of half-side `extentUnits` around (px, py): {{level = id, tx, ty, res, ppm}, ...}, by tx then ty.
-- Empty on bad input.
function View.VisibleTiles(level, px, py, extentUnits, res, ppm)
	local list = {}

	if not (validLevel(level) and finite(px) and finite(py) and finite(extentUnits) and extentUnits >= 0 and finite(res) and finite(ppm)) then
		return list
	end

	if math.abs(px) > MAX_COORD or math.abs(py) > MAX_COORD or extentUnits > MAX_COORD then
		return list
	end

	local T = tileUnits(res, ppm)

	if not T then
		return list
	end

	local tx0, tx1, ty0, ty1 = tileRange(px, py, extentUnits, T)

	if not tx0 then
		return list
	end

	local id, count = level.id, 0

	for tx = tx0, tx1 do
		for ty = ty0, ty1 do
			count = count + 1
			list[count] = {level = id, tx = tx, ty = ty, res = res, ppm = ppm}
		end
	end

	return list
end

-- The frame in convex pieces ---------------------------------------------------------------------------------------------------------------------

local function dedupe(poly)
	local out = {}

	for i = 1, #poly do
		local p, last = poly[i], out[#out]

		if not last or math.abs(p[1] - last[1]) > EPSILON or math.abs(p[2] - last[2]) > EPSILON then
			out[#out + 1] = p
		end
	end

	local first, last = out[1], out[#out]

	if #out > 1 and math.abs(first[1] - last[1]) <= EPSILON and math.abs(first[2] - last[2]) <= EPSILON then
		out[#out] = nil
	end

	return out
end

local function area2(poly)
	local sum = 0

	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		sum = sum + (a[1] * b[2] - b[1] * a[2])
	end

	return sum
end

-- Cuts `poly` (positive orientation) at its first reflex vertex along the line of the edge that arrives there, until every piece is convex.
local function split(poly, out, depth)
	local n = #poly

	if n < 3 then
		return
	end

	if depth < 24 then
		for i = 1, n do
			local prevIndex = (i - 2) % n + 1
			local prev, cur, nxt = poly[prevIndex], poly[i], poly[i % n + 1]
			local dx, dy = cur[1] - prev[1], cur[2] - prev[2]

			if dx * (nxt[2] - cur[2]) - dy * (nxt[1] - cur[1]) < -EPSILON then
				-- reflex: the extension of prev -> cur goes into the inside; it meets the border at the nearest edge ahead
				local bestT, bestJ, qx, qy = huge

				for j = 1, n do
					if j ~= i and j ~= prevIndex then
						local a, b = poly[j], poly[j % n + 1]
						local ex, ey = b[1] - a[1], b[2] - a[2]
						local denominator = dx * ey - dy * ex

						if math.abs(denominator) > EPSILON then
							local ax, ay = a[1] - cur[1], a[2] - cur[2]
							local t = (ax * ey - ay * ex) / denominator
							local s = (ax * dy - ay * dx) / denominator

							if t > EPSILON and s >= -EPSILON and s <= 1 + EPSILON and t < bestT then
								bestT, bestJ = t, j
								qx, qy = cur[1] + dx * t, cur[2] + dy * t
							end
						end
					end
				end

				if bestJ then
					local q = {qx, qy}
					local first, second = {}, {}
					local k = i

					while true do
						first[#first + 1] = poly[k]

						if k == bestJ then
							break
						end

						k = k % n + 1
					end

					first[#first + 1] = q
					second[1] = q
					k = bestJ % n + 1

					while true do
						second[#second + 1] = poly[k]

						if k == i then
							break
						end

						k = k % n + 1
					end

					split(dedupe(first), out, depth + 1)
					split(dedupe(second), out, depth + 1)

					return
				end
			end
		end
	end

	out[#out + 1] = poly
end

-- The polygon {{x, y}, ...} copied, without repeated points, in the positive orientation (clockwise on a screen with y down); nil when it is not
-- a polygon of numbers.
local function normalise(points)
	if type(points) ~= "table" or #points < 3 then
		return nil
	end

	local poly = {}

	for i = 1, #points do
		local p = points[i]

		if type(p) ~= "table" or not finite(p[1]) or not finite(p[2]) then
			return nil
		end

		poly[i] = {p[1], p[2]}
	end

	poly = dedupe(poly)

	if #poly < 3 then
		return nil
	end

	if area2(poly) < 0 then
		local reversed = {}

		for i = #poly, 1, -1 do
			reversed[#reversed + 1] = poly[i]
		end

		poly = reversed
	end

	return poly
end

-- The convex pieces of a simple polygon {{x, y}, ...} (any orientation): a list of pieces, each a list of {x, y} in the positive orientation (the
-- one of a polygon that goes clockwise on a screen with y down). A convex polygon gives itself.
function View.ConvexPieces(points)
	local out = {}
	local poly = normalise(points)

	if poly then
		split(poly, out, 0)
	end

	return out
end

-- The polygon the map is clipped against: the radar frame without the strip of its danger bar. The strip is the part of the frame to the left of the
-- reflex vertex (the notch), so the map keeps the half plane x >= (the x of that vertex). Nothing is written down here: another frame gives another
-- result. A frame without a reflex vertex has no strip and is returned whole. Positive orientation, no collinear vertices, starting at the lowest
-- (then leftmost) vertex; {} when the points are no polygon.
local function mapPolygon(points)
	local poly = normalise(points)

	if not poly then
		return {}
	end

	local n = #poly
	local limit

	for i = 1, n do
		local prev, cur, nxt = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]

		if (cur[1] - prev[1]) * (nxt[2] - cur[2]) - (cur[2] - prev[2]) * (nxt[1] - cur[1]) < -EPSILON then
			limit = cur[1]

			break
		end
	end

	if limit then
		-- Sutherland-Hodgman against the half plane x >= limit
		local clipped = {}
		local last = poly[n]

		for i = 1, n do
			local cur = poly[i]
			local curIn, lastIn = cur[1] >= limit - EPSILON, last[1] >= limit - EPSILON

			if curIn ~= lastIn then
				local t = (limit - last[1]) / (cur[1] - last[1])
				clipped[#clipped + 1] = {limit, last[2] + (cur[2] - last[2]) * t}
			end

			if curIn then
				clipped[#clipped + 1] = {cur[1], cur[2]}
			end

			last = cur
		end

		poly = dedupe(clipped)
	end

	-- vertices on the straight line between their neighbours (the cut leaves one where the notch was)
	local changed = true

	while changed and #poly >= 3 do
		changed = false
		n = #poly

		for i = 1, n do
			local prev, cur, nxt = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]

			if math.abs((cur[1] - prev[1]) * (nxt[2] - cur[2]) - (cur[2] - prev[2]) * (nxt[1] - cur[1])) <= EPSILON then
				table.remove(poly, i)
				changed = true

				break
			end
		end
	end

	if #poly < 3 then
		return {}
	end

	local first = 1

	for i = 2, #poly do
		local p, f = poly[i], poly[first]

		if p[2] < f[2] or (p[2] == f[2] and p[1] < f[1]) then
			first = i
		end
	end

	local out = {}

	for i = 0, #poly - 1 do
		out[#out + 1] = poly[(first - 1 + i) % #poly + 1]
	end

	return out
end

-- The map frame's pieces in flat arrays for the clipping, rebuilt only when Radar.FRAME changes (its identity, its size or a checksum of its numbers).
local frameCache = {}

local function framePieces()
	local Radar = GryMod.FlashRadar
	local frame = Radar and Radar.FRAME

	if type(frame) ~= "table" or #frame < 3 then
		return nil
	end

	local checksum = 0

	for i = 1, #frame do
		local p = frame[i]

		if type(p) ~= "table" or not finite(p[1]) or not finite(p[2]) then
			return nil
		end

		checksum = checksum + p[1] * (2 * i + 1) + p[2] * (3 * i + 7)
	end

	if frameCache.source ~= frame or frameCache.count ~= #frame or frameCache.checksum ~= checksum then
		local map = mapPolygon(frame)
		local pieces = View.ConvexPieces(map)
		local flat = {}
		local minX, minY, maxX, maxY = huge, huge, -huge, -huge

		for i = 1, #pieces do
			local piece = pieces[i]
			local xs, ys = {}, {}
			local pMinX, pMinY, pMaxX, pMaxY = huge, huge, -huge, -huge

			for j = 1, #piece do
				local x, y = piece[j][1], piece[j][2]
				xs[j], ys[j] = x, y
				pMinX, pMaxX = math.min(pMinX, x), math.max(pMaxX, x)
				pMinY, pMaxY = math.min(pMinY, y), math.max(pMaxY, y)
			end

			flat[i] = {n = #piece, xs = xs, ys = ys, minX = pMinX, minY = pMinY, maxX = pMaxX, maxY = pMaxY}
			minX, maxX = math.min(minX, pMinX), math.max(maxX, pMaxX)
			minY, maxY = math.min(minY, pMinY), math.max(maxY, pMaxY)
		end

		frameCache.source, frameCache.count, frameCache.checksum = frame, #frame, checksum
		frameCache.map = map
		frameCache.pieces, frameCache.minX, frameCache.minY, frameCache.maxX, frameCache.maxY = flat, minX, minY, maxX, maxY
	end

	if #frameCache.pieces == 0 then
		return nil
	end

	return frameCache
end

-- The polygon the map is clipped against (see mapPolygon): {{x, y}, ...} in radar pixels, a copy, {} when there is no usable Radar.FRAME.
function View.MapFrame()
	local cache = framePieces()
	local out = {}

	if cache then
		for i = 1, #cache.map do
			out[i] = {cache.map[i][1], cache.map[i][2]}
		end
	end

	return out
end

-- Clipping ----------------------------------------------------------------------------------------------------------------------------------------

-- Scratch buffers (module level, reused): a polygon is n vertices of 4 numbers each (x, y, u, v) in a flat array.
local bufferA, bufferB = {}, {}
-- the tile's quad, kept apart: every piece of the frame clips it again
local quad = {}

-- Sutherland-Hodgman of the n vertices in `source` against one convex piece (positive orientation: the inside of an edge is where the cross product
-- is not negative). Returns the buffer that holds the result and its vertex count.
local function clipToPiece(piece, source, n, target)
	local xs, ys, m = piece.xs, piece.ys, piece.n

	for e = 1, m do
		local ax, ay = xs[e], ys[e]
		local following = e % m + 1
		local ex, ey = xs[following] - ax, ys[following] - ay
		local count = 0
		local o = (n - 1) * 4
		local sx, sy, su, sv = source[o + 1], source[o + 2], source[o + 3], source[o + 4]
		local sd = ex * (sy - ay) - ey * (sx - ax)

		for i = 0, n - 1 do
			local q = i * 4
			local cx, cy, cu, cv = source[q + 1], source[q + 2], source[q + 3], source[q + 4]
			local cd = ex * (cy - ay) - ey * (cx - ax)

			if (cd >= 0) ~= (sd >= 0) then
				local t = sd / (sd - cd)
				local w = count * 4

				target[w + 1], target[w + 2] = sx + (cx - sx) * t, sy + (cy - sy) * t
				target[w + 3], target[w + 4] = su + (cu - su) * t, sv + (cv - sv) * t
				count = count + 1
			end

			if cd >= 0 then
				local w = count * 4

				target[w + 1], target[w + 2], target[w + 3], target[w + 4] = cx, cy, cu, cv
				count = count + 1
			end

			sx, sy, su, sv, sd = cx, cy, cu, cv, cd
		end

		source, target = target, source
		n = count

		if n == 0 then
			return source, 0
		end
	end

	return source, n
end

-- The scratch state of the drawing of one frame (set by Draw, read by emitTile): the colour is only set when the first polygon is sent.
local colourAlpha, colourSet

-- Clips the quad (in `quad`, radar pixels) against the pieces of the frame and sends every non empty result to surface.DrawPoly through (a, b, c, d,
-- tx, ty). Returns the number of polygons sent.
local function emitTile(material, pieces, a, b, c, d, tx, ty, flip)
	local sent = 0
	local materialSet = false
	local minX, minY, maxX, maxY = huge, huge, -huge, -huge

	for i = 0, 3 do
		local x, y = quad[i * 4 + 1], quad[i * 4 + 2]
		minX, maxX = x < minX and x or minX, x > maxX and x or maxX
		minY, maxY = y < minY and y or minY, y > maxY and y or maxY
	end

	for p = 1, #pieces do
		local piece = pieces[p]

		if maxX >= piece.minX and minX <= piece.maxX and maxY >= piece.minY and minY <= piece.maxY then
			for i = 1, 16 do
				bufferA[i] = quad[i]
			end

			local result, n = clipToPiece(piece, bufferA, 4, bufferB)

			if n >= 3 then
				-- the area in radar pixels: a sliver is not worth a call
				local area = 0

				for i = 0, n - 1 do
					local j = (i + 1) % n
					area = area + result[i * 4 + 1] * result[j * 4 + 2] - result[j * 4 + 1] * result[i * 4 + 2]
				end

				if area > 1e-9 then
					local verts = {}
					local count = 0

					for i = 0, n - 1 do
						local o = (flip and (n - 1 - i) or i) * 4
						local rx, ry = result[o + 1], result[o + 2]
						local x, y = a * rx + c * ry + tx, b * rx + d * ry + ty
						local last = verts[count]

						if not last or math.abs(last.x - x) > 1e-7 or math.abs(last.y - y) > 1e-7 then
							count = count + 1
							verts[count] = {x = x, y = y, u = result[o + 3], v = result[o + 4]}
						end
					end

					if count >= 3 then
						if not colourSet then
							surface.SetDrawColor(255, 255, 255, colourAlpha)
							colourSet = true
						end

						if not materialSet then
							surface.SetMaterial(material)
							materialSet = true
						end

						surface.DrawPoly(verts)
						sent = sent + 1
					end
				end
			end
		end
	end

	return sent
end

-- Draw --------------------------------------------------------------------------------------------------------------------------------------------

-- which tiles of the visible square the cache has, indexed by (tx - tx0) * height + (ty - ty0) + 1 (reused)
local exists = {}

local function drawImpl(xf, px, py, yawDeg, rangeUnits, level, alpha)
	if type(xf) ~= "table" then
		return 0
	end

	local a, b, c, d = xf.a or xf[1], xf.b or xf[2], xf.c or xf[3], xf.d or xf[4]
	local tx, ty = xf.tx or xf[5], xf.ty or xf[6]

	if not (finite(a) and finite(b) and finite(c) and finite(d) and finite(tx) and finite(ty)) then
		return 0
	end

	if not (finite(px) and finite(py) and finite(yawDeg) and finite(rangeUnits) and rangeUnits > 0 and validLevel(level)) then
		return 0
	end

	if math.abs(px) > MAX_COORD or math.abs(py) > MAX_COORD or rangeUnits > MAX_COORD then
		return 0
	end

	if not finite(alpha) then
		alpha = 1
	end

	alpha = alpha < 0 and 0 or (alpha > 1 and 1 or alpha)

	local pixels = radarPixels()
	local M = GryMod.Minimap
	local Settings, Cache = M.Settings, M.Cache
	local frame = framePieces()

	if not (pixels and frame and type(Settings) == "table" and type(Cache) == "table") then
		return 0
	end

	local res, ppm = Settings.TileRes(), Settings.Definition()
	local T = tileUnits(res, ppm)

	if not (T and finite(res) and finite(ppm)) then
		return 0
	end

	local tx0, tx1, ty0, ty1 = tileRange(px, py, rangeUnits * EXTENT_FACTOR, T)

	if not tx0 then
		return 0
	end

	local radians = rad(yawDeg)
	local s, co = sin(radians), cos(radians)
	local k = pixels / rangeUnits
	local pieces = frame.pieces
	local fMinX, fMinY, fMaxX, fMaxY = frame.minX, frame.minY, frame.maxX, frame.maxY
	local flip = a * d - b * c < 0
	local drawing = alpha > 0
	local id = level.id
	local height = ty1 - ty0 + 1
	local width = tx1 - tx0 + 1
	local anyExists = false

	-- the range circle's bounding square, for the tiles the coverage needs
	local diskMinX, diskMaxX, diskMinY, diskMaxY = px - rangeUnits, px + rangeUnits, py - rangeUnits, py + rangeUnits

	colourAlpha, colourSet = floor(alpha * 255 + 0.5), false

	for i = 1, width * height do
		exists[i] = false
	end

	for txi = tx0, tx1 do
		local x0 = txi * T
		local x1 = x0 + T
		local dx0, dx1 = x0 - px, x1 - px

		for tyi = ty0, ty1 do
			local y0 = tyi * T
			local y1 = y0 + T
			local dy0, dy1 = y0 - py, y1 - py

			-- the corners (maxx, maxy), (maxx, miny), (minx, miny), (minx, maxy) in radar pixels, with their texture coordinates
			local r1x, r1y = (dx1 * s - dy1 * co) * k, -(dx1 * co + dy1 * s) * k
			local r2x, r2y = (dx1 * s - dy0 * co) * k, -(dx1 * co + dy0 * s) * k
			local r3x, r3y = (dx0 * s - dy0 * co) * k, -(dx0 * co + dy0 * s) * k
			local r4x, r4y = (dx0 * s - dy1 * co) * k, -(dx0 * co + dy1 * s) * k
			local minX = math.min(r1x, r2x, r3x, r4x)
			local maxX = math.max(r1x, r2x, r3x, r4x)
			local minY = math.min(r1y, r2y, r3y, r4y)
			local maxY = math.max(r1y, r2y, r3y, r4y)
			local visible = drawing and maxX >= fMinX and minX <= fMaxX and maxY >= fMinY and minY <= fMaxY
			local underDisk = x1 > diskMinX and x0 < diskMaxX and y1 > diskMinY and y0 < diskMaxY

			if visible or underDisk then
				local material = Cache.Material({level = id, tx = txi, ty = tyi, res = res, ppm = ppm})

				if material then
					exists[(txi - tx0) * height + (tyi - ty0) + 1] = true
					anyExists = true

					if visible then
						quad[1], quad[2], quad[3], quad[4] = r1x, r1y, 0, 0
						quad[5], quad[6], quad[7], quad[8] = r2x, r2y, 1, 0
						quad[9], quad[10], quad[11], quad[12] = r3x, r3y, 1, 1
						quad[13], quad[14], quad[15], quad[16] = r4x, r4y, 0, 1
						emitTile(material, pieces, a, b, c, d, tx, ty, flip)
					end
				end
			end
		end
	end

	if not anyExists then
		return 0
	end

	-- the share of the range circle that lies on existing tiles: a regular grid over its square, no engine call
	local N = COVERAGE_GRID
	local radius2 = rangeUnits * rangeUnits
	local inside, covered = 0, 0

	for i = 0, N - 1 do
		local ox = ((i + 0.5) * 2 / N - 1) * rangeUnits
		local column = floor((px + ox) / T) - tx0

		for j = 0, N - 1 do
			local oy = ((j + 0.5) * 2 / N - 1) * rangeUnits

			if ox * ox + oy * oy <= radius2 then
				inside = inside + 1

				local row = floor((py + oy) / T) - ty0

				if column >= 0 and column < width and row >= 0 and row < height and exists[column * height + row + 1] then
					covered = covered + 1
				end
			end
		end
	end

	return inside > 0 and covered / inside or 0
end

-- Draws the existing tiles of `level` around (px, py) under the radar: `xf = {a, b, c, d, tx, ty}` (named or numbered) sends a radar pixel (rx, ry) to
-- the screen point (a * rx + c * ry + tx, b * rx + d * ry + ty); `yawDeg` is the angle the map is turned to (0 when it does not turn); `alpha` 0..1
-- (1 when it is no number). Returns the share (0..1) of the range circle that lies on existing tiles. Never creates a tile, never raises (0 and
-- View.LastError when something inside broke).
function View.Draw(xf, px, py, yawDeg, rangeUnits, level, alpha)
	View.LastError = nil

	local ok, coverage = pcall(drawImpl, xf, px, py, yawDeg, rangeUnits, level, alpha)

	if ok and finite(coverage) then
		return coverage
	end

	if not ok then
		View.LastError = tostring(coverage)
	end

	return 0
end
