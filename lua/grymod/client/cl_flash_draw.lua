-- Draws the display list of a Flash clip (see cl_flash.lua) with the atlas bitmaps converted by tools/flash2lua.
--
-- Shapes are textured quads whose corners go through the accumulated 2D matrix of the clips above them
-- (Flash matrices: x' = a*x + c*y + tx, y' = b*x + d*y + ty), so rotation, skew and scale are exact. Quads
-- sharing a material are batched into one mesh. Colour transforms become the vertex colour (exact for the white
-- shapes the colour-set clips tint). Clip layers (masks) clip each quad against the mask outlines, cut into convex pieces
-- when it is concave (no stencil: it does not exist in every render target). A clip with a blend mode
-- (the HUD uses "add") is drawn as a group, as Flash does: its content is composed normally in a render
-- target, then that image is added to what is below.

local Flash = GryMod.Flash

local BLEND_ADD = 8

-- Debug switch: draw every blend mode as a normal alpha blend (FFDec's renderer does not honour them).
Flash.IgnoreBlendModes = false

-- Where the atlas PNG files are looked up. The addon ships them as materials/grymod/flash/*.png; tests
-- running a branch that is not mounted as an addon can point this at a folder of the game's data directory.
Flash.AtlasMaterialPath = function(path)
	return path
end

local atlasMaterials = {}

local function atlasMaterial(path)
	local material = atlasMaterials[path]

	if not material then
		Flash.Stats.atlasLoads = Flash.Stats.atlasLoads + 1
		material = Material(Flash.AtlasMaterialPath(path), "nocull smooth mips")
		-- Flash blends translucent shapes in gamma space; the engine blends in linear space (washed-out, brighter
		-- translucent panels) unless the shader writes the colour as it is.
		material:SetInt("$linearwrite", 1)
		material:Recompute()
		atlasMaterials[path] = material
	end

	return material
end

function Flash.ClearMaterialCache()
	atlasMaterials = {}
end

-- The material of an atlas picture, made now when it is not (the preloading calls it ahead of the first drawing).
Flash.AtlasMaterial = atlasMaterial

-- Drops the material of one picture (the next drawing makes it again): tests.
function Flash.ForgetAtlas(path)
	atlasMaterials[path] = nil
end

-- Whether the picture has its material already (the next drawing that needs it costs nothing).
function Flash.AtlasLoaded(path)
	return atlasMaterials[path] ~= nil
end

local whitePaths = {}

-- Which atlas file draws shapes of `atlas` under the accumulated colour multipliers (mr, mg, mb). A colour-set
-- clip replaces the colour of its shapes (Flash's Color.setRGB: multiplier 0, colour added), whatever colour
-- the artwork gave them; the engine can only multiply the texture, so those shapes come from the all-white
-- twin of the atlas and the added colour becomes the vertex colour.
function Flash.AtlasPathFor(movie, atlas, mr, mg, mb)
	local path = movie.atlases[atlas]

	if movie.white and movie.white[atlas] and mr + mg + mb < 0.001 then
		local twin = whitePaths[path]

		if not twin then
			twin = path:gsub("%.png$", "_w.png")
			whitePaths[path] = twin
		end

		return twin
	end

	return path
end

-- Triangle batch: 8 numbers (x, y, u, v, r, g, b, a) per vertex, 3 vertices per triangle.
local batch = {}
local batchCount = 0 -- numbers used
local batchMaterial, batchBlend
local position = Vector()

local groupDepth = 0 -- > 0 while drawing the content of a group into its render target
local blendOverridden = false

local function flush()
	if batchCount == 0 then
		return
	end

	local additive = batchBlend == BLEND_ADD

	render.SetMaterial(batchMaterial)

	if additive then
		blendOverridden = true
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	elseif groupDepth > 0 then
		-- keep the alpha of what is drawn in the (initially transparent) group image
		blendOverridden = true
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD, BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
	end

	mesh.Begin(MATERIAL_TRIANGLES, batchCount / 24)

	for i = 1, batchCount, 8 do
		position:SetUnpacked(batch[i], batch[i + 1], 0)
		mesh.Position(position)
		mesh.TexCoord(0, batch[i + 2], batch[i + 3])
		mesh.Color(batch[i + 4], batch[i + 5], batch[i + 6], batch[i + 7])
		mesh.AdvanceVertex()
	end

	mesh.End()

	if additive or groupDepth > 0 then
		blendOverridden = false
		render.OverrideBlend(false)
	end

	batchCount = 0
end

local function vertex(x, y, u, v, r, g, b, a)
	local n = batchCount
	batch[n + 1] = x
	batch[n + 2] = y
	batch[n + 3] = u
	batch[n + 4] = v
	batch[n + 5] = r
	batch[n + 6] = g
	batch[n + 7] = b
	batch[n + 8] = a
	batchCount = n + 8
end

local function clamp255(value)
	if value < 0 then
		return 0
	end

	if value > 1 then
		return 255
	end

	return value * 255
end

-- Measuring pass: drawShape only widens these bounds (screen pixels) instead of drawing.
local measuring = false
local minX, minY, maxX, maxY = 0, 0, 0, 0

-- The active clip layer (mask): an outline cut into convex pieces (a mask may be concave), in screen coordinates.
-- maskPieces[maskFirst] to maskPieces[maskFirst + maskCount - 1] are the pieces of the active mask, each one
-- {n = vertices, sign = winding, x1, y1, x2, y2, ...}; the slots below maskFirst hold the mask of the group
-- being drawn from, whose content has masks of its own.
local maskPieces = {}
local maskFirst = 1
local maskCount = 0 -- convex pieces, 0 = no mask
local polyA, polyB, polySrc = {}, {}, {}

-- Clips the polygon in polyA (n vertices of x, y, u, v) against a convex piece of the mask. Returns the clipped
-- polygon (polyA or polyB, as x, y, u, v groups) and its vertex count.
local function clipToPiece(piece, n)
	local from, to = polyA, polyB
	local pieceCount, maskSign = piece.n, piece.sign

	for edge = 1, pieceCount do
		local ax, ay = piece[edge * 2 - 1], piece[edge * 2]
		local nextEdge = edge % pieceCount + 1
		local bx, by = piece[nextEdge * 2 - 1], piece[nextEdge * 2]
		local ex, ey = bx - ax, by - ay
		local count = 0

		local previous = n
		local px, py = from[previous * 4 - 3], from[previous * 4 - 2]
		local previousSide = maskSign * (ex * (py - ay) - ey * (px - ax))

		for i = 1, n do
			local qx, qy = from[i * 4 - 3], from[i * 4 - 2]
			local side = maskSign * (ex * (qy - ay) - ey * (qx - ax))

			if (side >= 0) ~= (previousSide >= 0) then
				local t = previousSide / (previousSide - side)
				local o = count * 4
				to[o + 1] = px + (qx - px) * t
				to[o + 2] = py + (qy - py) * t
				to[o + 3] = from[previous * 4 - 1] + (from[i * 4 - 1] - from[previous * 4 - 1]) * t
				to[o + 4] = from[previous * 4] + (from[i * 4] - from[previous * 4]) * t
				count = count + 1
			end

			if side >= 0 then
				local o = count * 4
				to[o + 1], to[o + 2], to[o + 3], to[o + 4] = qx, qy, from[i * 4 - 1], from[i * 4]
				count = count + 1
			end

			previous, px, py, previousSide = i, qx, qy, side
		end

		from, to, n = to, from, count

		if n < 3 then
			return from, 0
		end
	end

	return from, n
end

-- Appends the clipped polygon of polyA to the batch as triangles.
local function emitClipped(n, r, g, b, a)
	local last = maskFirst + maskCount - 1

	if maskCount > 1 then
		for i = 1, n * 4 do
			polySrc[i] = polyA[i]
		end
	end

	for index = maskFirst, last do
		if index > maskFirst then
			for i = 1, n * 4 do
				polyA[i] = polySrc[i]
			end
		end

		local from, count = clipToPiece(maskPieces[index], n)

		for i = 2, count - 1 do
			vertex(from[1], from[2], from[3], from[4], r, g, b, a)
			vertex(from[i * 4 - 3], from[i * 4 - 2], from[i * 4 - 1], from[i * 4], r, g, b, a)
			vertex(from[i * 4 + 1], from[i * 4 + 2], from[i * 4 + 3], from[i * 4 + 4], r, g, b, a)
		end
	end
end

-- One textured rectangle: the atlas rectangle (sx, sy, sw, sh) drawn over the local rectangle (x0, y0)-(x1, y1).
local function drawQuad(movie, atlas, sx, sy, sw, sh, x0, y0, x1, y1, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa, blend)
	if measuring then
		for corner = 0, 3 do
			local x = (corner == 1 or corner == 2) and x1 or x0
			local y = corner >= 2 and y1 or y0
			local px, py = a * x + c * y + tx, b * x + d * y + ty

			if px < minX then minX = px end
			if px > maxX then maxX = px end
			if py < minY then minY = py end
			if py > maxY then maxY = py end
		end

		return
	end

	local material = atlasMaterial(Flash.AtlasPathFor(movie, atlas, mr, mg, mb))

	if material ~= batchMaterial or blend ~= batchBlend then
		flush()
		batchMaterial = material
		batchBlend = blend
	end

	local atlasW, atlasH = material:Width(), material:Height()
	local u0, v0 = sx / atlasW, sy / atlasH
	local u1, v1 = (sx + sw) / atlasW, (sy + sh) / atlasH

	-- colour of a white shape under the accumulated colour transform
	local r, g, bl, al = clamp255(mr + ar / 255), clamp255(mg + ag / 255), clamp255(mb + ab / 255), clamp255(ma + aa / 255)

	local ax, ay = a * x0 + c * y0 + tx, b * x0 + d * y0 + ty
	local bx, by = a * x1 + c * y0 + tx, b * x1 + d * y0 + ty
	local cx, cy = a * x1 + c * y1 + tx, b * x1 + d * y1 + ty
	local dx, dy = a * x0 + c * y1 + tx, b * x0 + d * y1 + ty

	if maskCount > 0 then
		polyA[1], polyA[2], polyA[3], polyA[4] = ax, ay, u0, v0
		polyA[5], polyA[6], polyA[7], polyA[8] = bx, by, u1, v0
		polyA[9], polyA[10], polyA[11], polyA[12] = cx, cy, u1, v1
		polyA[13], polyA[14], polyA[15], polyA[16] = dx, dy, u0, v1
		emitClipped(4, r, g, bl, al)

		return
	end

	vertex(ax, ay, u0, v0, r, g, bl, al)
	vertex(bx, by, u1, v0, r, g, bl, al)
	vertex(cx, cy, u1, v1, r, g, bl, al)
	vertex(ax, ay, u0, v0, r, g, bl, al)
	vertex(cx, cy, u1, v1, r, g, bl, al)
	vertex(dx, dy, u0, v1, r, g, bl, al)
end

local function drawShape(movie, shape, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa, blend)
	drawQuad(movie, shape.a, shape.x, shape.y, shape.w, shape.h, shape.ox, shape.oy, shape.ox + shape.dw, shape.oy + shape.dh,
		a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa, blend)
end

-- A text field: one quad per glyph from the font atlas, tinted by the field's own colour.
local function drawText(movie, field, text, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa, blend)
	local font = movie.fonts and movie.fonts[field.f]

	if not font or text == "" then
		return
	end

	local x, baseline, _ = Flash.LayoutText(font, field, text)
	x = field.ox + x
	baseline = field.oy + baseline

	local scale = field.fh / font.em
	local color = field.col
	mr, mg, mb, ma = mr * color[1] / 255, mg * color[2] / 255, mb * color[3] / 255, ma * color[4] / 255
	local glyphs = font.g

	for i = 1, #text do
		local glyph = glyphs[string.byte(text, i)]

		if glyph then
			if glyph.w > 0 then
				local gx, gy = x + glyph.ox * scale, baseline + glyph.oy * scale

				drawQuad(movie, font.a, glyph.x, glyph.y, glyph.w, glyph.h, gx, gy, gx + glyph.w * scale, gy + glyph.h * scale,
					a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa, blend)
			end

			x = x + glyph.adv * scale
		end
	end
end

-- Cutting an outline into convex pieces. The pieces are lists of vertex numbers of the outline (they do not change
-- with the matrix: an affine map keeps convexity), found once per outline: ear clipping into triangles, then
-- neighbouring triangles are joined while the result stays convex (Hertel-Mehlhorn), so an outline with one
-- reflex corner gives two or three pieces. nil when the outline is no simple polygon.
local pieceCache = setmetatable({}, {__mode = "k"})
local EPSILON = 1e-6

local function turn(outline, a, b, c)
	return (outline[b * 2 - 1] - outline[a * 2 - 1]) * (outline[c * 2] - outline[a * 2]) - (outline[b * 2] - outline[a * 2]) * (outline[c * 2 - 1] - outline[a * 2 - 1])
end

local function isConvexRing(outline, ring, sign)
	local n = #ring

	for k = 1, n do
		if sign * turn(outline, ring[k], ring[k % n + 1], ring[(k + 1) % n + 1]) < -EPSILON then
			return false
		end
	end

	return true
end

local function samePoint(outline, a, b)
	return outline[a * 2 - 1] == outline[b * 2 - 1] and outline[a * 2] == outline[b * 2]
end

local function joinedPiece(outline, p, q, sign)
	local np, nq = #p, #q

	for a = 1, np do
		local u, v = p[a], p[a % np + 1]

		for b = 1, nq do
			if q[b] == v and q[b % nq + 1] == u then
				local joined = {}

				for k = 1, np do
					joined[k] = p[(a + k - 1) % np + 1] -- v ... u
				end

				for k = 2, nq - 1 do
					joined[#joined + 1] = q[(b + k - 1) % nq + 1] -- the vertices of q that are not u, v
				end

				if isConvexRing(outline, joined, sign) then
					return joined
				end

				return nil
			end
		end
	end

	return nil
end

local function decompose(outline)
	local ring = {}

	for i = 1, #outline / 2 do
		if #ring == 0 or not samePoint(outline, ring[#ring], i) then
			ring[#ring + 1] = i
		end
	end

	if #ring > 1 and samePoint(outline, ring[1], ring[#ring]) then
		ring[#ring] = nil
	end

	local n = #ring

	if n < 3 then
		return nil
	end

	local area = 0

	for k = 1, n do
		local i, j = ring[k], ring[k % n + 1]
		area = area + outline[i * 2 - 1] * outline[j * 2] - outline[j * 2 - 1] * outline[i * 2]
	end

	if area == 0 then
		return nil
	end

	local sign = area > 0 and 1 or -1

	if isConvexRing(outline, ring, sign) then
		return {ring}
	end

	-- ear clipping
	local pieces = {}

	while #ring > 3 do
		local m = #ring
		local found = false

		for k = 1, m do
			local ia, ib, ic = ring[(k - 2) % m + 1], ring[k], ring[k % m + 1]
			local cross = sign * turn(outline, ia, ib, ic)

			if cross <= EPSILON and cross >= -EPSILON then
				-- a straight run or a spike: no area to give to a piece
				table.remove(ring, k)
				found = true
				break
			end

			if cross > EPSILON then
				local ear = true

				for other = 1, m do
					local io = ring[other]

					if io ~= ia and io ~= ib and io ~= ic and not samePoint(outline, io, ia) and not samePoint(outline, io, ib) and not samePoint(outline, io, ic)
						and sign * turn(outline, ia, ib, io) >= -EPSILON and sign * turn(outline, ib, ic, io) >= -EPSILON and sign * turn(outline, ic, ia, io) >= -EPSILON then
						ear = false
						break
					end
				end

				if ear then
					pieces[#pieces + 1] = {ia, ib, ic}
					table.remove(ring, k)
					found = true
					break
				end
			end
		end

		if not found then
			return nil
		end
	end

	if #ring == 3 and math.abs(turn(outline, ring[1], ring[2], ring[3])) > EPSILON then
		pieces[#pieces + 1] = {ring[1], ring[2], ring[3]}
	end

	-- join neighbours while the result is convex
	local merged = true

	while merged do
		merged = false

		for i = 1, #pieces do
			for j = i + 1, #pieces do
				local joined = joinedPiece(outline, pieces[i], pieces[j], sign)

				if joined then
					pieces[i] = joined
					table.remove(pieces, j)
					merged = true
					break
				end
			end

			if merged then
				break
			end
		end
	end

	if #pieces == 0 then
		return nil
	end

	return pieces
end

local function convexPieces(outline)
	local pieces = pieceCache[outline]

	if pieces == nil then
		pieces = decompose(outline) or false
		pieceCache[outline] = pieces
	end

	return pieces
end

-- The pieces a mask outline is cut into (vertex numbers of the outline), or nil: tests.
function Flash.MaskPieces(outline)
	return convexPieces(outline) or nil
end

-- The contours of a mask shape, each one {outline = {x1, y1, ...}, pieces = ...} (the outline in the shape's own
-- coordinates, its convex pieces as vertex numbers), or false when one of its outlines cannot be cut. A shape has
-- one outline (`p`) or several separate ones (`ps`: the bars of the lost signal, two rectangles...): the mask is
-- their union, which the pieces of all of them make up since the contours do not overlap.
local function cutContours(outlines)
	local contours = {}

	if #outlines == 0 then
		return false
	end

	for i = 1, #outlines do
		local pieces = convexPieces(outlines[i])

		if not pieces then
			return false
		end

		contours[i] = {outline = outlines[i], pieces = pieces}
	end

	return contours
end

-- A morph mask has a new outline at every ratio of its timeline: the contours of each ratio are kept, up to this many
-- ratios per shape (the ratios come from the movie, a few dozen at most), then the shape starts again.
local MORPH_CACHE_LIMIT = 512

-- The contours of one mask shape at the given ratio (a morph only): nil when it has no outline, false when it has
-- one that cannot be cut.
local function shapeContours(definition, ratio)
	if ratio and definition.k == "morph" and (definition.pe or definition.pes) then
		local cache = definition.maskMorph

		if not cache then
			cache = {count = 0}
			definition.maskMorph = cache
		end

		local contours = cache[ratio]

		if contours == nil then
			local starts = definition.ps or {definition.p}
			local ends = definition.pes or {definition.pe}

			if cache.count >= MORPH_CACHE_LIMIT then
				cache = {count = 0}
				definition.maskMorph = cache
			end

			local t = ratio / 65535
			local outlines = {}

			for i = 1, #starts do
				local from, to = starts[i], ends[i]
				local outline = {}

				for k = 1, #from do
					outline[k] = from[k] + (to[k] - from[k]) * t
				end

				outlines[i] = outline
			end

			contours = cutContours(outlines)
			cache[ratio] = contours
			cache.count = cache.count + 1
		end

		return contours
	end

	local contours = definition.maskContours

	if contours == nil then
		if definition.ps then
			contours = cutContours(definition.ps)
		elseif definition.p then
			contours = cutContours({definition.p})
		else
			return nil
		end

		definition.maskContours = contours
	end

	return contours
end

-- How many ratios of a morph mask have their contours kept: tests.
function Flash.MaskMorphCached(definition)
	return definition.maskMorph and definition.maskMorph.count or 0
end

-- The contours of a mask entry (see shapeContours; nil when it has no outline), and the matrix of the shape inside
-- it when the mask is a clip (a clip used as a mask: the first shape with an outline in it counts).
local function maskContours(movie, entry)
	if entry.clip then
		for _, child in ipairs(entry.clip:Entries()) do
			local contours, inner = maskContours(movie, child)

			if contours ~= nil then
				local m = child.m

				if inner then
					-- compose the child's matrix with the one found deeper
					m = {m[1] * inner[1] + m[3] * inner[2], m[2] * inner[1] + m[4] * inner[2],
						m[1] * inner[3] + m[3] * inner[4], m[2] * inner[3] + m[4] * inner[4],
						m[1] * inner[5] + m[3] * inner[6] + m[5], m[2] * inner[5] + m[4] * inner[6] + m[6]}
				end

				return contours, m
			end
		end

		return nil
	end

	local definition = movie.chars[entry.id]

	if not definition then
		return nil
	end

	return shapeContours(definition, entry.ratio)
end

local function beginMask(movie, entry, a, b, c, d, tx, ty)
	local contours, inner = maskContours(movie, entry)

	if not contours then
		return false
	end

	local m = entry.m
	-- the entry matrix under the accumulated one
	local ea = a * m[1] + c * m[2]
	local eb = b * m[1] + d * m[2]
	local ec = a * m[3] + c * m[4]
	local ed = b * m[3] + d * m[4]
	local etx = a * m[5] + c * m[6] + tx
	local ety = b * m[5] + d * m[6] + ty

	if inner then
		-- a clip used as a mask: its shape's own matrix goes on top
		ea, eb, ec, ed, etx, ety =
			ea * inner[1] + ec * inner[2], eb * inner[1] + ed * inner[2],
			ea * inner[3] + ec * inner[4], eb * inner[3] + ed * inner[4],
			ea * inner[5] + ec * inner[6] + etx, eb * inner[5] + ed * inner[6] + ety
	end

	local slot = 0

	for contourIndex = 1, #contours do
		local contour = contours[contourIndex]
		local outline, pieces = contour.outline, contour.pieces

		for k = 1, #pieces do
			local piece = pieces[k]
			slot = slot + 1
			local target = maskPieces[maskFirst + slot - 1]

			if not target then
				target = {}
				maskPieces[maskFirst + slot - 1] = target
			end

			local points = #piece
			local area = 0

			for i = 1, points do
				local o = piece[i]
				local x, y = outline[o * 2 - 1], outline[o * 2]
				target[i * 2 - 1] = ea * x + ec * y + etx
				target[i * 2] = eb * x + ed * y + ety
			end

			for i = 1, points do
				local j = i % points + 1
				area = area + target[i * 2 - 1] * target[j * 2] - target[j * 2 - 1] * target[i * 2]
			end

			target.n = points
			target.sign = area >= 0 and 1 or -1
		end
	end

	maskCount = slot

	return true
end

local function endMask()
	maskCount = 0
end

local drawEntries

-- Render targets for the images of groups, taken from a pool by size and given back when the entry that
-- used one is removed from its display list (cl_flash.lua calls Flash.ReleaseEntry).
local targetPool = {}
local targetCount = 0
local groupMaterials = {}

-- atlasLoads: pictures turned into materials (each one is a freeze of up to a second), targetCreates: render targets made
Flash.Stats = {groupRenders = 0, groupReuses = 0, atlasLoads = 0, targetCreates = 0}

local function powerOfTwo(n)
	local p = 64

	while p < n do
		p = p * 2
	end

	return p
end

local function acquireTarget(width, height)
	local key = width .. "x" .. height
	local pool = targetPool[key]

	if pool and #pool > 0 then
		return table.remove(pool)
	end

	targetCount = targetCount + 1
	Flash.Stats.targetCreates = Flash.Stats.targetCreates + 1

	-- a float format: 8-bit render targets are decoded as sRGB when sampled, which would darken the image
	return GetRenderTargetEx("grymod_flash_p" .. targetCount .. "_" .. key, width, height, RT_SIZE_NO_CHANGE,
		MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA16161616F), key
end

local function releaseTarget(cache)
	if not cache.target or not cache.textureW or not cache.textureH then
		return
	end

	local key = cache.textureW .. "x" .. cache.textureH
	local pool = targetPool[key]

	if not pool then
		pool = {}
		targetPool[key] = pool
	end

	pool[#pool + 1] = cache.target
end

-- Gives the image of a removed entry (and of the groups inside it) back to the pool.
function Flash.ReleaseEntry(entry)
	local cache = entry.cache

	if cache then
		releaseTarget(cache)
		entry.cache = nil
	end

	if entry.clip then
		for _, child in pairs(entry.clip.list) do
			Flash.ReleaseEntry(child)
		end
	end
end

-- Gives back the images of every group in a clip's display list (a HUD that is dropped).
function Flash.ReleaseClip(clip)
	for _, entry in pairs(clip.list) do
		Flash.ReleaseEntry(entry)
	end
end

-- How many render targets wait in the pool (tests).
function Flash.PoolSize()
	local count = 0

	for _, pool in pairs(targetPool) do
		count = count + #pool
	end

	return count
end

local function groupMaterial(target)
	local name = target:GetName()
	local material = groupMaterials[name]

	if not material then
		material = CreateMaterial("grymod_flash_m3_" .. name, "UnlitGeneric", {
			["$basetexture"] = name,
			["$vertexcolor"] = 1,
			["$vertexalpha"] = 1,
			["$linearwrite"] = 1,
			["$nocull"] = 1,
			["$ignorez"] = 1
		})
		groupMaterials[name] = material
	end

	return material
end

local MAX_GROUP = 4096

-- The image of a group on the screen: the colours in it are already multiplied by their alpha, so "add" adds
-- them and any other mode is a normal "over".
local function compositeGroup(cache, blend)
	render.SetMaterial(groupMaterial(cache.target))

	if blend == BLEND_ADD then
		blendOverridden = true
		render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD)
	else
		blendOverridden = true
		render.OverrideBlend(true, BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD)
	end

	local x0, y0, width, height = cache.x0, cache.y0, cache.width, cache.height
	local u1, v1 = width / cache.textureW, height / cache.textureH

	polyA[1], polyA[2], polyA[3], polyA[4] = x0, y0, 0, 0
	polyA[5], polyA[6], polyA[7], polyA[8] = x0 + width, y0, u1, 0
	polyA[9], polyA[10], polyA[11], polyA[12] = x0 + width, y0 + height, u1, v1
	polyA[13], polyA[14], polyA[15], polyA[16] = x0, y0 + height, 0, v1

	local pieces = maskCount > 0 and maskCount or 1

	if pieces > 1 then
		for i = 1, 16 do
			polySrc[i] = polyA[i]
		end
	end

	for piece = 1, pieces do
		local polygon, count = polyA, 4

		if maskCount > 0 then
			if piece > 1 then
				for i = 1, 16 do
					polyA[i] = polySrc[i]
				end
			end

			polygon, count = clipToPiece(maskPieces[maskFirst + piece - 1], 4)
		end

		if count >= 3 then
			mesh.Begin(MATERIAL_TRIANGLES, count - 2)

			for i = 2, count - 1 do
				for corner = 0, 2 do
					local k = corner == 0 and 1 or i + corner - 1
					position:SetUnpacked(polygon[k * 4 - 3], polygon[k * 4 - 2], 0)
					mesh.Position(position)
					mesh.TexCoord(0, polygon[k * 4 - 1], polygon[k * 4])
					mesh.Color(255, 255, 255, 255)
					mesh.AdvanceVertex()
				end
			end

			mesh.End()
		end
	end

	blendOverridden = false
		render.OverrideBlend(false)
end

local function sameKey(cache, blend, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa)
	return cache.blend == blend and cache.a == a and cache.b == b and cache.c == c and cache.d == d
		and cache.tx == tx and cache.ty == ty and cache.mr == mr and cache.mg == mg and cache.mb == mb
		and cache.ma == ma and cache.ar == ar and cache.ag == ag and cache.ab == ab and cache.aa == aa
end

-- Draws the clip of `entry` as one image composed with `blend` (see the header). The image is kept with the
-- entry and drawn again as long as the clip and where it is drawn do not change.
local function drawGroup(entry, blend, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa)
	local clip = entry.clip
	local cache = entry.cache

	if cache and cache.version == clip.version and sameKey(cache, blend, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa) then
		Flash.Stats.groupReuses = Flash.Stats.groupReuses + 1

		if cache.target then
			flush()
			compositeGroup(cache, blend)
		end

		return
	end

	measuring = true
	minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	drawEntries(clip, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa)
	measuring = false

	local x0, y0 = math.floor(minX) - 1, math.floor(minY) - 1
	local width, height = math.ceil(maxX) + 1 - x0, math.ceil(maxY) + 1 - y0
	local textureW, textureH = powerOfTwo(width), powerOfTwo(height)
	local empty = minX > maxX or textureW > MAX_GROUP or textureH > MAX_GROUP

	if cache and (empty or cache.textureW ~= textureW or cache.textureH ~= textureH) then
		if cache.target then
			releaseTarget(cache)
		end

		cache = nil
	end

	if not cache then
		cache = {}
		entry.cache = cache
	end

	cache.version, cache.blend = clip.version, blend
	cache.a, cache.b, cache.c, cache.d, cache.tx, cache.ty = a, b, c, d, tx, ty
	cache.mr, cache.mg, cache.mb, cache.ma, cache.ar, cache.ag, cache.ab, cache.aa = mr, mg, mb, ma, ar, ag, ab, aa

	if empty then
		cache.target = nil

		return
	end

	cache.x0, cache.y0, cache.width, cache.height, cache.textureW, cache.textureH = x0, y0, width, height, textureW, textureH

	if not cache.target then
		cache.target = acquireTarget(textureW, textureH)
	end

	flush()
	Flash.Stats.groupRenders = Flash.Stats.groupRenders + 1

	-- the content has masks of its own: they go in the slots after the ones of this group's mask
	local outerMask, outerFirst = maskCount, maskFirst
	maskFirst = maskFirst + maskCount
	maskCount = 0

	render.PushRenderTarget(cache.target)
	render.Clear(0, 0, 0, 0, true, true, true)
	cam.Start2D()
	groupDepth = groupDepth + 1
	drawEntries(clip, a, b, c, d, tx - x0, ty - y0, mr, mg, mb, ma, ar, ag, ab, aa)
	flush()
	groupDepth = groupDepth - 1
	cam.End2D()
	render.PopRenderTarget()
	maskCount, maskFirst = outerMask, outerFirst

	compositeGroup(cache, blend)
end

function Flash.ClearGroupCache()
	targetPool = {}
	groupMaterials = {}
end

function drawEntries(clip, a, b, c, d, tx, ty, mr, mg, mb, ma, ar, ag, ab, aa)
	local movie = clip.movie
	local entries = clip:Entries()
	local maskUntil

	for i = 1, #entries do
		local entry = entries[i]

		if maskUntil and entry.depth > maskUntil then
			endMask()
			maskUntil = nil
		end

		if entry.clipDepth then
			if maskUntil then
				endMask()
				maskUntil = nil
			end

			if not measuring and beginMask(movie, entry, a, b, c, d, tx, ty) then
				maskUntil = entry.clipDepth
			end
		else
			local m = entry.m
			local ea = a * m[1] + c * m[2]
			local eb = b * m[1] + d * m[2]
			local ec = a * m[3] + c * m[4]
			local ed = b * m[3] + d * m[4]
			local etx = a * m[5] + c * m[6] + tx
			local ety = b * m[5] + d * m[6] + ty

			-- colour transform: the entry's applies first, the accumulated one after it
			local cx = entry.cx
			local nmr, nmg, nmb, nma, nar, nag, nab, naa = mr, mg, mb, ma, ar, ag, ab, aa

			if cx then
				nmr, nmg, nmb, nma = mr * cx[1], mg * cx[2], mb * cx[3], ma * cx[4]
				nar, nag, nab, naa = mr * cx[5] + ar, mg * cx[6] + ag, mb * cx[7] + ab, ma * cx[8] + aa
			end

			local blend = not Flash.IgnoreBlendModes and entry.blend

			if blend == 1 then
				blend = nil
			end

			if entry.clip then
				if entry.clip.visible then
					if blend and not measuring then
						drawGroup(entry, blend, ea, eb, ec, ed, etx, ety, nmr, nmg, nmb, nma, nar, nag, nab, naa)
					else
						drawEntries(entry.clip, ea, eb, ec, ed, etx, ety, nmr, nmg, nmb, nma, nar, nag, nab, naa)
					end
				end
			elseif entry.kind == "shape" then
				drawShape(movie, movie.chars[entry.id], ea, eb, ec, ed, etx, ety, nmr, nmg, nmb, nma, nar, nag, nab, naa, blend or 1)
			elseif entry.kind == "text" then
				drawText(movie, movie.chars[entry.id], entry.text, ea, eb, ec, ed, etx, ety, nmr, nmg, nmb, nma, nar, nag, nab, naa, blend or 1)
			end
		end
	end

	if maskUntil then
		endMask()
	end
end

-- The state the drawing code keeps between calls (tests): measuring, the depth of the groups being drawn, the mask size.
function Flash.DrawState()
	return measuring, groupDepth, maskCount
end

-- After an error in the middle of a drawing: put back what the interrupted code had set (the measuring pass, the
-- stack of group render targets, the blend override, the mask) so that the next frame starts clean.
local function recover()
	while groupDepth > 0 do
		cam.End2D()
		render.PopRenderTarget()
		groupDepth = groupDepth - 1
	end

	if blendOverridden then
		render.OverrideBlend(false)
		blendOverridden = false
	end

	measuring = false
	maskCount, maskFirst = 0, 1
	batchCount = 0
	batchMaterial, batchBlend = nil, nil
end

local lastError

-- Draws `clip` with the stage origin at (x, y) on the screen and `scale` screen pixels per stage pixel. Returns
-- false when something went wrong: the error is printed once (not at every frame) and the state is put back.
function Flash.Draw(clip, x, y, scale)
	batchCount = 0
	batchMaterial = nil
	batchBlend = nil

	local ok, err = pcall(function()
		drawEntries(clip, scale, 0, 0, scale, x, y, 1, 1, 1, 1, 0, 0, 0, 0)
		flush()
	end)

	if ok then
		lastError = nil

		return true
	end

	recover()

	if err ~= lastError then
		lastError = err
		ErrorNoHalt("[GryMod] Flash drawing failed: " .. tostring(err) .. "\n")
	end

	return false
end
