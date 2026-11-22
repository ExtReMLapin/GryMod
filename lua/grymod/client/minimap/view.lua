-- GryMod minimap: module view. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.View = GryMod.Minimap.View or {}

-- The maths from the world to the radar, the tiles around the player, and the drawing of the tiles under the contacts.
--   * View.ToRadar: the formula of Radar.Contacts (cl_hud_radar_units.lua), for one point: radar pixels, x right and y down, (0, 0) is the player.
--   * View.VisibleTiles: the tiles whose bounds touch the square around the player.
--   * View.Draw: three passes, the OUTSIDE (the open level of the map, the whole height of the world, tinted and faint), then the floor below (tinted), then the
--     current level (white); each existing tile of a pass is drawn as ONE textured quad (surface.DrawPoly) through the transform of the radar: the quad's corners go from
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

-- How many times the range the tiles asked for reach when there is no usable radar frame to measure (View.ExtentFactor measures it).
local EXTENT_FACTOR = 2
-- More tiles than this around the player means a nonsense (a huge range or a tiny tile): nothing is drawn.
local MAX_TILES = 400
-- Exported: Gen refuses a request that would need more tiles than this around the player (as View does: nothing is drawn).
View.MAX_TILES = MAX_TILES
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
-- reflex vertex (the notch), so the map keeps the half plane x >= (the x of that vertex), or x >= `left` (Radar.MAP_LEFT) when that is a number strictly
-- inside the frame (the drawn bar is narrower than the glass left of the notch; the notch then stays in the polygon, which is cut into convex pieces
-- later). Nothing is written down here: another frame gives another result. A frame without a reflex vertex has no strip and is returned whole. Positive orientation, no collinear vertices, starting at the lowest
-- (then leftmost) vertex; {} when the points are no polygon.
local function mapPolygon(points, left)
	local poly = normalise(points)

	if not poly then
		return {}
	end

	local n = #poly
	local limit

	-- Radar.MAP_LEFT (the right edge of the drawn danger bar, plus a margin) when it is a number inside the frame
	if finite(left) then
		local minX, maxX = huge, -huge

		for i = 1, n do
			minX, maxX = math.min(minX, poly[i][1]), math.max(maxX, poly[i][1])
		end

		if left > minX and left < maxX then
			limit = left
		end
	end

	for i = 1, limit and 0 or n do
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

	local pixels = radarPixels()
	local left = Radar.MAP_LEFT

	if not finite(left) then
		left = nil
	end

	if frameCache.source ~= frame or frameCache.count ~= #frame or frameCache.checksum ~= checksum or frameCache.pixels ~= pixels or frameCache.left ~= left then
		local map = mapPolygon(frame, left)
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

		-- how many times the range the tiles must reach so that the farthest corner of the map frame is covered, in hundredths, rounded up
		local reach = 0

		for i = 1, #map do
			reach = math.max(reach, math.sqrt(map[i][1] * map[i][1] + map[i][2] * map[i][2]))
		end

		frameCache.extent = pixels and reach > 0 and math.ceil(reach / pixels * 100 - 1e-9) / 100 or EXTENT_FACTOR
		frameCache.source, frameCache.count, frameCache.checksum, frameCache.pixels, frameCache.left = frame, #frame, checksum, pixels, left
		frameCache.map = map
		frameCache.pieces, frameCache.minX, frameCache.minY, frameCache.maxX, frameCache.maxY = flat, minX, minY, maxX, maxY
	end

	if #frameCache.pieces == 0 then
		return nil
	end

	return frameCache
end

-- How many times the range (the player's circle of PIXELS radar pixels) the tiles asked for must reach: the farthest vertex of View.MapFrame() from the
-- player, in ranges, rounded up to the hundredth. Another frame gives another number; EXTENT_FACTOR when there is no usable frame.
function View.ExtentFactor()
	local cache = framePieces()

	return cache and cache.extent or EXTENT_FACTOR
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
local colourR, colourG, colourB, colourAlpha, colourSet
-- Reused tables, so that a frame makes no garbage of its own: the vertices of the polygon being sent, and the tile given to the cache (it reads the
-- fields to make a name and keeps nothing of the table; a cache that kept it would break the view's contract).
local polyVerts, vertexPool, polyLength = {}, {}, 0
local scratchTile = {level = false, tx = 0, ty = 0, res = 0, ppm = 0}

-- Whether clipping the quad (in `quad`, radar pixels) against a piece of the frame leaves a polygon with an area; the result stays in the clip buffers
-- (n vertices) for emitTile to use. Returns the buffer and n, or nil.
local function clipQuad(piece, minX, minY, maxX, maxY)
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
				return result, n
			end
		end
	end

	return nil
end

-- The bounding box of the quad's four corners.
local function quadBounds()
	local minX, minY, maxX, maxY = huge, huge, -huge, -huge

	for i = 0, 3 do
		local x, y = quad[i * 4 + 1], quad[i * 4 + 2]
		minX, maxX = x < minX and x or minX, x > maxX and x or maxX
		minY, maxY = y < minY and y or minY, y > maxY and y or maxY
	end

	return minX, minY, maxX, maxY
end

-- Whether any polygon would be sent for the quad: the cache is only asked for a material when this says yes.
local function quadShows(pieces)
	local minX, minY, maxX, maxY = quadBounds()

	for p = 1, #pieces do
		if clipQuad(pieces[p], minX, minY, maxX, maxY) then
			return true
		end
	end

	return false
end

-- Clips the quad against the pieces of the frame and sends every non empty result to surface.DrawPoly through (a, b, c, d, tx, ty), with `material`.
-- Returns the number of polygons sent.
local function emitTile(material, pieces, a, b, c, d, tx, ty, flip)
	local sent = 0
	local materialSet = false
	local minX, minY, maxX, maxY = quadBounds()

	for p = 1, #pieces do
		local result, n = clipQuad(pieces[p], minX, minY, maxX, maxY)

		if result then
			-- the vertex tables and the array that holds them are reused from one polygon to the next (and one frame to the next):
			-- surface.DrawPoly reads them at once and keeps nothing
			local verts = polyVerts
			local count = 0

			for i = 0, n - 1 do
				local o = (flip and (n - 1 - i) or i) * 4
				local rx, ry = result[o + 1], result[o + 2]
				local x, y = a * rx + c * ry + tx, b * rx + d * ry + ty
				local last = vertexPool[count]

				if count == 0 or math.abs(last.x - x) > 1e-7 or math.abs(last.y - y) > 1e-7 then
					count = count + 1

					local vertex = vertexPool[count]

					if not vertex then
						vertex = {x = 0, y = 0, u = 0, v = 0}
						vertexPool[count] = vertex
					end

					vertex.x, vertex.y, vertex.u, vertex.v = x, y, result[o + 3], result[o + 4]
					verts[count] = vertex
				end
			end

			-- the array holds exactly this polygon's vertices (the engine reads its length)
			for i = count + 1, polyLength do
				verts[i] = nil
			end

			polyLength = count

			if count >= 3 then
				if not colourSet then
					surface.SetDrawColor(colourR, colourG, colourB, colourAlpha)
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

	return sent
end

-- Draw --------------------------------------------------------------------------------------------------------------------------------------------

-- The tint of the floor below (a cool blue grey), the share of its alpha is the caller's.
local BELOW_R, BELOW_G, BELOW_B = 150, 165, 190

-- The tint of the outside (the open level, drawn under the floor below): a darker, greyer blue, so that the solid parts of a floor (earth cut by the slice)
-- show a part of what is outside, like the radar of the original game's preview.
local OUTSIDE_R, OUTSIDE_G, OUTSIDE_B = 110, 125, 140

-- Whether the floor below is drawn: a level table of its own (not the main level's id), and an alpha above 0 (clamped to 1).
local function drawingBelow(below, belowAlpha, level)
	if not validLevel(below) or below.id == level.id or not finite(belowAlpha) or belowAlpha <= 0 then
		return false
	end

	return true
end

-- Whether the outside is drawn: a level table of its own (not the main level's id, nor the floor below's id when there is one), and an alpha above 0.
local function drawingOutside(outside, outsideAlpha, level, below)
	if not validLevel(outside) or outside.id == level.id or not finite(outsideAlpha) or outsideAlpha <= 0 then
		return false
	end

	if validLevel(below) and below.id == outside.id then
		return false
	end

	return true
end

-- How many distinct materials one Draw asks of the cache at most (main level first, then the floor below, then the outside): the cache keeps 160, so a frame never
-- pushes out what it has just loaded. The tiles nearest to the player go first. Read at call time (the tests change it).
View.MAX_MATERIALS = 96

-- The tiles of the frame's square, nearest ring first (the ring of a tile is its largest index distance from the player's tile), and what is known of
-- each: its tile indices, the quad in radar pixels (16 numbers: x, y, u, v of four corners), whether it touches the frame's box, whether it is under
-- the range circle, and the materials asked (false: the cache has none). All reused.
local slotTx, slotTy, slotVisible, slotDisk, mainMat, belowMat, outsideMat, slotQuads = {}, {}, {}, {}, {}, {}, {}, {}
local slotCount, ringTx0, ringTx1, ringTy0, ringTy1 = 0, 0, 0, 0, 0

local function ringTile(tx, ty)
	if tx >= ringTx0 and tx <= ringTx1 and ty >= ringTy0 and ty <= ringTy1 then
		slotCount = slotCount + 1
		slotTx[slotCount], slotTy[slotCount] = tx, ty
	end
end

-- which tiles of the visible square the cache has, indexed by (tx - tx0) * height + (ty - ty0) + 1 (reused)
local exists = {}

-- Loads the quad of slot i into `quad`.
local function loadQuad(i)
	local o = (i - 1) * 16

	for j = 1, 16 do
		quad[j] = slotQuads[o + j]
	end
end

-- The previous definition of the automatic definition's pyramid (Settings.PreviousDefinition), or nil: no such function, a function that raises, or an answer
-- that is no definition (a number above 0) are all "none".
local function previousDefinition(Settings)
	if type(Settings.PreviousDefinition) ~= "function" then
		return nil
	end

	local ok, previous = pcall(Settings.PreviousDefinition)

	if ok and finite(previous) and previous > 0 then
		return previous
	end

	return nil
end

-- Whether one of the tiles of the box (tx0..tx1, ty0..ty1) of level `levelId` is missing from the cache (Cache.Has: from memory, no material is loaded).
local function anyMissing(Cache, levelId, tx0, tx1, ty0, ty1, res, ppm)
	scratchTile.level, scratchTile.res, scratchTile.ppm = levelId, res, ppm

	for txi = tx0, tx1 do
		for tyi = ty0, ty1 do
			scratchTile.tx, scratchTile.ty = txi, tyi

			if not Cache.Has(scratchTile) then
				return true
			end
		end
	end

	return false
end

-- `ppmOverride` (the fallback below) draws the three passes with the tiles of another definition and returns 0, then the number of materials it asked for; `budgetCap`
-- is the most it may ask for. The normal call (no override) first draws the fallback when it is needed and gets the budget that is left.
local function drawImpl(xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha, ppmOverride, budgetCap)
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

	if finite(belowAlpha) and belowAlpha > 1 then
		belowAlpha = 1
	end

	if finite(outsideAlpha) and outsideAlpha > 1 then
		outsideAlpha = 1
	end

	local pixels = radarPixels()
	local M = GryMod.Minimap
	local Settings, Cache = M.Settings, M.Cache
	local frame = framePieces()

	if not (pixels and frame and type(Settings) == "table" and type(Cache) == "table") then
		return 0
	end

	local res, ppm = Settings.TileRes(), ppmOverride or Settings.Definition()
	local T = tileUnits(res, ppm)

	if not (T and finite(res) and finite(ppm)) then
		return 0
	end

	local tx0, tx1, ty0, ty1 = tileRange(px, py, rangeUnits * frame.extent, T)

	if not tx0 then
		return 0
	end

	local budget = finite(View.MAX_MATERIALS) and View.MAX_MATERIALS or 96

	-- 0. the previous definition (the automatic definition changed level): while the tiles of the current one are not all there (the main level, and the floor
	-- below and the outside when they are drawn), the tiles of the previous one are drawn first, so the map is never empty after a zoom. The new tiles come over
	-- them. The fallback takes at most half of the budget of materials, the current level the rest.
	if not ppmOverride then
		local previous = previousDefinition(Settings)

		if previous and previous ~= ppm then
			local belowShown = drawingBelow(below, belowAlpha, level)
			local outsideShown = drawingOutside(outside, outsideAlpha, level, below)
			local missing = alpha > 0 and anyMissing(Cache, level.id, tx0, tx1, ty0, ty1, res, ppm)
				or belowShown and anyMissing(Cache, below.id, tx0, tx1, ty0, ty1, res, ppm)
				or outsideShown and anyMissing(Cache, outside.id, tx0, tx1, ty0, ty1, res, ppm)

			if missing then
				local ok, err, spent = pcall(drawImpl, xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha, previous, floor(budget / 2))

				if ok then
					budget = budget - (spent or 0)
				else
					-- told like any other error of the view, and the current level is drawn all the same
					View.LastError = tostring(err)
				end
			end
		end
	elseif budgetCap and budgetCap < budget then
		budget = budgetCap
	end

	local startBudget = budget

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

	-- the range circle's bounding square, for the tiles the coverage needs
	local diskMinX, diskMaxX, diskMinY, diskMaxY = px - rangeUnits, px + rangeUnits, py - rangeUnits, py + rangeUnits

	-- 1. the tiles, nearest ring first
	slotCount = 0
	ringTx0, ringTx1, ringTy0, ringTy1 = tx0, tx1, ty0, ty1

	local ptx, pty = floor(px / T), floor(py / T)
	local maxRing = math.max(ptx - tx0, tx1 - ptx, pty - ty0, ty1 - pty)

	for r = 0, maxRing do
		for txi = ptx - r, ptx + r do
			ringTile(txi, pty - r)

			if r > 0 then
				ringTile(txi, pty + r)
			end
		end

		if r > 0 then
			for tyi = pty - r + 1, pty + r - 1 do
				ringTile(ptx - r, tyi)
				ringTile(ptx + r, tyi)
			end
		end
	end

	-- 2. each tile's quad (the corners (maxx, maxy), (maxx, miny), (minx, miny), (minx, maxy), with their texture coordinates) and where it lies
	for i = 1, slotCount do
		local x0, y0 = slotTx[i] * T, slotTy[i] * T
		local x1, y1 = x0 + T, y0 + T
		local dx0, dx1, dy0, dy1 = x0 - px, x1 - px, y0 - py, y1 - py
		local r1x, r1y = (dx1 * s - dy1 * co) * k, -(dx1 * co + dy1 * s) * k
		local r2x, r2y = (dx1 * s - dy0 * co) * k, -(dx1 * co + dy0 * s) * k
		local r3x, r3y = (dx0 * s - dy0 * co) * k, -(dx0 * co + dy0 * s) * k
		local r4x, r4y = (dx0 * s - dy1 * co) * k, -(dx0 * co + dy1 * s) * k
		local o = (i - 1) * 16

		slotQuads[o + 1], slotQuads[o + 2], slotQuads[o + 3], slotQuads[o + 4] = r1x, r1y, 0, 0
		slotQuads[o + 5], slotQuads[o + 6], slotQuads[o + 7], slotQuads[o + 8] = r2x, r2y, 1, 0
		slotQuads[o + 9], slotQuads[o + 10], slotQuads[o + 11], slotQuads[o + 12] = r3x, r3y, 1, 1
		slotQuads[o + 13], slotQuads[o + 14], slotQuads[o + 15], slotQuads[o + 16] = r4x, r4y, 0, 1

		slotVisible[i] = math.max(r1x, r2x, r3x, r4x) >= fMinX and math.min(r1x, r2x, r3x, r4x) <= fMaxX
			and math.max(r1y, r2y, r3y, r4y) >= fMinY and math.min(r1y, r2y, r3y, r4y) <= fMaxY
		slotDisk[i] = x1 > diskMinX and x0 < diskMaxX and y1 > diskMinY and y0 < diskMaxY
		mainMat[i], belowMat[i], outsideMat[i] = nil, nil, nil
	end

	-- 3. the materials: only for a tile of which a polygon will really be sent, the main level first, then the floor below, then the outside, within the budget
	scratchTile.level, scratchTile.res, scratchTile.ppm = id, res, ppm

	if drawing then
		for i = 1, slotCount do
			if budget > 0 and slotVisible[i] then
				loadQuad(i)

				if quadShows(pieces) then
					budget = budget - 1
					scratchTile.tx, scratchTile.ty = slotTx[i], slotTy[i]
					mainMat[i] = Cache.Material(scratchTile) or false
				end
			end
		end
	end

	local belowOn = drawingBelow(below, belowAlpha, level)

	if belowOn then
		scratchTile.level = below.id

		for i = 1, slotCount do
			if budget > 0 and slotVisible[i] then
				loadQuad(i)

				if quadShows(pieces) then
					budget = budget - 1
					scratchTile.tx, scratchTile.ty = slotTx[i], slotTy[i]
					belowMat[i] = Cache.Material(scratchTile) or false
				end
			end
		end

		scratchTile.level = id
	end

	local outsideOn = drawingOutside(outside, outsideAlpha, level, below)

	if outsideOn then
		scratchTile.level = outside.id

		for i = 1, slotCount do
			if budget > 0 and slotVisible[i] then
				loadQuad(i)

				if quadShows(pieces) then
					budget = budget - 1
					scratchTile.tx, scratchTile.ty = slotTx[i], slotTy[i]
					outsideMat[i] = Cache.Material(scratchTile) or false
				end
			end
		end

		scratchTile.level = id
	end

	-- 3b. the outside first of all (under the floor below and the main level, seen through their voids): the same tiles and clip, tinted, a share of the
	-- main level's alpha
	if outsideOn then
		colourR, colourG, colourB, colourAlpha, colourSet = OUTSIDE_R, OUTSIDE_G, OUTSIDE_B, floor(outsideAlpha * 255 + 0.5), false

		for i = 1, slotCount do
			if outsideMat[i] then
				loadQuad(i)
				emitTile(outsideMat[i], pieces, a, b, c, d, tx, ty, flip)
			end
		end
	end

	-- 4. the floor below (over the outside, under the main level, seen through its voids): the same tiles and clip, tinted, a share of the main level's alpha
	-- (a level of the same id would be the main level twice: it is not drawn)
	if belowOn then
		colourR, colourG, colourB, colourAlpha, colourSet = BELOW_R, BELOW_G, BELOW_B, floor(belowAlpha * 255 + 0.5), false

		for i = 1, slotCount do
			if belowMat[i] then
				loadQuad(i)
				emitTile(belowMat[i], pieces, a, b, c, d, tx, ty, flip)
			end
		end
	end

	-- 5. the main level
	colourR, colourG, colourB, colourAlpha, colourSet = 255, 255, 255, floor(alpha * 255 + 0.5), false

	for i = 1, slotCount do
		if mainMat[i] then
			loadQuad(i)
			emitTile(mainMat[i], pieces, a, b, c, d, tx, ty, flip)
		end
	end

	-- the fallback has no coverage to give: it says how many materials it used
	if ppmOverride then
		return 0, startBudget - budget
	end

	-- 6. which tiles under the range circle exist: what the cache gave for the ones asked, Cache.Has for the others (no material is loaded for this)
	for i = 1, width * height do
		exists[i] = false
	end

	local anyExists = false

	for i = 1, slotCount do
		if slotDisk[i] then
			local found = mainMat[i]

			if found == nil then
				scratchTile.tx, scratchTile.ty = slotTx[i], slotTy[i]
				found = Cache.Has(scratchTile)
			end

			if found then
				exists[(slotTx[i] - tx0) * height + (slotTy[i] - ty0) + 1] = true
				anyExists = true
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
-- (1 when it is no number). Returns the share (0..1) of the range circle that lies on existing tiles of `level` (the floor below does not count).
-- `outside` (a level table, the open level of the map) with `outsideAlpha` > 0 (clamped to 1) draws the outside before everything else: the same visible tiles
-- and the same clip, tinted (110, 125, 140), under the floor below. An outside of the same id as the main level or as the floor below is not drawn. The budget of
-- materials is shared in the order main level, floor below, outside.
-- `below` (a level table) with `belowAlpha` > 0 (clamped to 1) draws the floor below before the main level: the same visible tiles and the same clip, tinted
-- (150, 165, 190) with belowAlpha; the main level comes after, white with `alpha`, and the voids of its tiles (their alpha) show what is under.
-- A `below` of the same id as `level` is not drawn (it would be the same tiles twice). The tiles of `below` are asked from the cache only when
-- one of their polygons is about to be drawn, so the LRU of materials is not loaded with tiles that show nothing. Never creates a tile, never
-- raises (0 and View.LastError when something inside broke).
function View.Draw(xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha)
	View.LastError = nil

	local ok, coverage = pcall(drawImpl, xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha)

	if ok and finite(coverage) then
		return coverage
	end

	if not ok then
		View.LastError = tostring(coverage)
	end

	return 0
end
