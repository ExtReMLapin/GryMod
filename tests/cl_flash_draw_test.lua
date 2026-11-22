-- Tests of the parts of the Flash drawing code that do not need a render context (cl_flash_draw.lua): the pool of
-- render targets and what happens after an error while drawing. The pictures themselves are checked with
-- tests/flash_pixels_job.lua.

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Shape"}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Group", bl = 8}}}}
		},
		root = {{{d = 1, c = 3, n = "Holder"}}}
	}
end

-- Draws `root` with the mesh and material calls replaced by recorders (the drawing needs no render context for
-- that) and returns the triangles it emitted, as {x1, y1, x2, y2, x3, y3}. The real functions are put back
-- whatever happens.
local function drawnTriangles(root, x, y, scale)
	local originals = {mesh = {}, render = {}}
	local names = {mesh = {"Begin", "Position", "TexCoord", "Color", "AdvanceVertex", "End"}, render = {"SetMaterial", "OverrideBlend"}}
	local triangles, corner, current = {}, 0, nil
	local fakes = {
		mesh = {
			Begin = function() end,
			Position = function(position) current = {position.x, position.y} end,
			TexCoord = function() end,
			Color = function() end,
			AdvanceVertex = function()
				corner = corner + 1
				triangles[#triangles + 1] = current

				if corner == 3 then
					corner = 0
				end
			end,
			End = function() end
		},
		render = {SetMaterial = function() end, OverrideBlend = function() end}
	}

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			originals[library][name] = _G[library][name]
			_G[library][name] = fakes[library][name]
		end
	end

	local ignored = GryMod.Flash.IgnoreBlendModes
	GryMod.Flash.IgnoreBlendModes = true
	local ok, err = pcall(GryMod.Flash.Draw, root, x or 0, y or 0, scale or 1)
	GryMod.Flash.IgnoreBlendModes = ignored

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			_G[library][name] = originals[library][name]
		end
	end

	assert(ok and err ~= false, "the drawing failed")
	local grouped = {}

	for i = 1, #triangles, 3 do
		local a, b, c = triangles[i], triangles[i + 1], triangles[i + 2]
		grouped[#grouped + 1] = {a[1], a[2], b[1], b[2], c[1], c[2]}
	end

	return grouped
end

-- A clip with two shapes, one at depth 1 and one at depth 5 (100 pixels to the right), to see what is drawn before and after a hook.
local function hookMovie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "A"}, {d = 5, c = 1, n = "B", m = {1, 0, 0, 1, 100, 0}}}}}
		},
		root = {{{d = 1, c = 2, n = "Holder"}}}
	}
end

-- Draws `root` with the mesh calls replaced by recorders and returns the events in order: "A" for a triangle of the shape at depth 1, "B" for
-- one of the shape at depth 5 (told apart by their x), and whatever `record` is asked to add: the hook calls it. The real functions are put back.
local function drawEvents(root, x, y, scale, setup)
	local events = {}
	local names = {mesh = {"Begin", "Position", "TexCoord", "Color", "AdvanceVertex", "End"}, render = {"SetMaterial", "OverrideBlend"}}
	local originals = {mesh = {}, render = {}}
	local current
	local last

	local fakes = {
		mesh = {
			Begin = function() end,
			Position = function(position) current = position.x end,
			TexCoord = function() end,
			Color = function() end,
			AdvanceVertex = function()
				local name = current >= 50 and "B" or "A"

				if name ~= last then
					events[#events + 1] = name
					last = name
				end
			end,
			End = function() end
		},
		render = {SetMaterial = function() end, OverrideBlend = function() end}
	}

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			originals[library][name] = _G[library][name]
			_G[library][name] = fakes[library][name]
		end
	end

	if setup then
		setup(function(label) events[#events + 1] = label last = nil end)
	end

	local ok, err = pcall(GryMod.Flash.Draw, root, x or 0, y or 0, scale or 1)

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			_G[library][name] = originals[library][name]
		end
	end

	assert(ok, tostring(err))

	return events
end

local function area(triangles)
	local total = 0

	for _, t in ipairs(triangles) do
		total = total + math.abs((t[3] - t[1]) * (t[6] - t[2]) - (t[5] - t[1]) * (t[4] - t[2])) / 2
	end

	return total
end

-- The area of a polygon given as {x1, y1, x2, y2, ...}
local function polygonArea(p)
	local total, n = 0, #p / 2

	for i = 1, n do
		local j = i % n + 1
		total = total + p[i * 2 - 1] * p[j * 2] - p[j * 2 - 1] * p[i * 2]
	end

	return math.abs(total) / 2
end

local function distanceToSegment(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local t = math.Clamp(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)

	return math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
end

-- Whether a point is inside the polygon {x1, y1, ...} or within `tolerance` of its outline (even-odd rule).
local function insideOrOn(px, py, p, tolerance)
	local n, inside = #p / 2, false

	for i = 1, n do
		local j = i % n + 1
		local ax, ay, bx, by = p[i * 2 - 1], p[i * 2], p[j * 2 - 1], p[j * 2]

		if distanceToSegment(px, py, ax, ay, bx, by) <= tolerance then
			return true
		end

		if (ay > py) ~= (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax then
			inside = not inside
		end
	end

	return inside
end

-- every corner and the centre of every triangle lies in the polygon
local function allInside(triangles, polygon)
	for _, t in ipairs(triangles) do
		for corner = 1, 3 do
			if not insideOrOn(t[corner * 2 - 1], t[corner * 2], polygon, 0.01) then
				return false, t
			end
		end

		if not insideOrOn((t[1] + t[3] + t[5]) / 3, (t[2] + t[4] + t[6]) / 3, polygon, 0.01) then
			return false, t
		end
	end

	return true
end

-- A square of 100 x 100 stage pixels (atlas rect 4 x 4) masked by the shape `outline` placed at (ox, oy)
local function maskedMovie(outline)
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 100, dh = 100},
			[2] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 100, dh = 100, p = outline}
		},
		root = {{{d = 1, c = 2, cd = 2, m = {1, 0, 0, 1, 10, 20}}, {d = 2, c = 1, m = {1, 0, 0, 1, 10, 20}}}}
	}
end

local function moved(outline, dx, dy)
	local moved = {}

	for i = 1, #outline, 2 do
		moved[i], moved[i + 1] = outline[i] + dx, outline[i + 1] + dy
	end

	return moved
end

local L_SHAPE = {0, 0, 100, 0, 100, 40, 40, 40, 40, 100, 0, 100}

-- The same square masked by a shape of several contours (`ps`, a list of outlines).
local function maskedMovieOf(contours)
	local m = maskedMovie(nil)
	m.chars[2].p = nil
	m.chars[2].ps = contours

	return m
end

-- Two rectangles of 30 x 100 with a gap of 40 between them, and the same drawn as a morph that narrows them to 20.
local TWO_BARS = {{0, 0, 30, 0, 30, 100, 0, 100}, {70, 0, 100, 0, 100, 100, 70, 100}}
local TWO_BARS_END = {{0, 0, 20, 0, 20, 100, 0, 100}, {80, 0, 100, 0, 100, 100, 80, 100}}

local function morphingMovie(ratio)
	local m = maskedMovie(nil)
	m.chars[2] = {k = "morph", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 100, dh = 100, ex = 0, ey = 0, ew = 100, eh = 100,
		ps = TWO_BARS, pes = TWO_BARS_END}
	m.root[1][1].r = ratio

	return m
end

-- A shape of 30 x 20 pixels in a clip that is drawn as a group (blend mode "add"), inside a holder.
local function groupMovie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 30, dh = 20},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Shape"}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Group", bl = 8}}}}
		},
		root = {{{d = 1, c = 3, n = "Holder"}}}
	}
end

-- The same inside another group: the holder's group holds a group.
local function nestedGroupMovie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 30, dh = 20},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Shape"}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Inner", bl = 8, m = {1, 0, 0, 1, 4, 3}}, {d = 2, c = 1, m = {1, 0, 0, 1, 50, 0}}}}},
			[4] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 3, n = "Outer", bl = 8}}}}
		},
		root = {{{d = 1, c = 4, n = "Holder"}}}
	}
end

-- Draws `root` with groups made for real as far as the drawing code goes, but with the engine calls replaced by recorders (no render
-- context needed). Returns how many group images were made and the triangles drawn on the screen itself (not into an image), as a list of
-- numbers (x, y of each vertex). The real functions are put back whatever happens.
local function drawGroups(root, x, y, scale)
	local replaced = {}
	local function replace(library, name, fake)
		replaced[#replaced + 1] = {library, name, library[name]}
		library[name] = fake
	end

	local F = GryMod.Flash
	local renders = F.Stats.groupRenders
	local inside, screen, targets = 0, {}, 0
	local current

	replace(_G, "GetRenderTargetEx", function()
		targets = targets + 1

		return {GetName = function() return "fake_target_" .. targets end}
	end)
	replace(_G, "CreateMaterial", function() return {} end)
	replace(render, "PushRenderTarget", function() inside = inside + 1 end)
	replace(render, "PopRenderTarget", function() inside = inside - 1 end)
	replace(render, "Clear", function() end)
	replace(render, "SetMaterial", function() end)
	replace(render, "OverrideBlend", function() end)
	replace(cam, "Start2D", function() end)
	replace(cam, "End2D", function() end)
	replace(mesh, "Begin", function() end)
	replace(mesh, "Position", function(position) current = position end)
	replace(mesh, "TexCoord", function() end)
	replace(mesh, "Color", function() end)
	replace(mesh, "End", function() end)
	replace(mesh, "AdvanceVertex", function()
		if inside == 0 then
			screen[#screen + 1] = current.x
			screen[#screen + 1] = current.y
		end
	end)

	local ok, err = pcall(F.Draw, root, x or 0, y or 0, scale or 1)

	for i = #replaced, 1, -1 do
		local r = replaced[i]
		r[1][r[2]] = r[3]
	end

	F.ClearGroupCache() -- the pool and the group materials hold fakes

	assert(ok and err ~= false, "the drawing failed: " .. tostring(err))

	return {renders = F.Stats.groupRenders - renders, screen = screen}
end

return {
	groupName = "GryMod Flash drawing (no render context)",
	cases = {
		-- the cached image of a group follows the clip when it is drawn a whole number of pixels away (the HUD's jolt after a hit)
		{
			name = "a cached group image is drawn again, not made again, when the clip is a whole number of pixels away; a fraction of a pixel makes it again",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(groupMovie())
				local first = drawGroups(root, 10.25, 20.5)
				expect(first.renders).to.equal(1)
				local again = drawGroups(root, 10.25, 20.5)
				expect(again.renders).to.equal(0)
				-- a whole number of pixels, either way and both axes: no new image, and the picture is where a new image would put it
				for _, shift in ipairs({{3, -5}, {-7, 0}, {0, 12}, {40, 30}}) do
					local x, y = 10.25 + shift[1], 20.5 + shift[2]
					local moved = drawGroups(root, x, y)
					expect(moved.renders).to.equal(0)
					local fresh = drawGroups(F.NewRoot(groupMovie()), x, y)
					expect(fresh.renders).to.equal(1)
					expect(#moved.screen).to.equal(#fresh.screen)

					for i = 1, #fresh.screen do
						expect(moved.screen[i]).to.aboutEqual(fresh.screen[i], 1e-6)
					end
				end

				-- a fraction of a pixel (in either axis) changes what the image holds
				expect(drawGroups(root, 10.5, 20.5).renders).to.equal(1)
				expect(drawGroups(root, 10.5, 20.75).renders).to.equal(1)
				expect(drawGroups(root, 10.5, 20.75).renders).to.equal(0)
				F.ClearGroupCache()
			end
		},
		{
			name = "a shift of a whole number of pixels with a rounding error of the matrix additions is still a whole shift, and a different scale is not",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(groupMovie())
				drawGroups(root, 100.1, 200.3)
				expect(drawGroups(root, 100.1 + 17, 200.3 - 9).renders).to.equal(0) -- the addition rounds: 117.1 is not exactly 100.1 + 17
				expect(drawGroups(root, 100.1 + 17, 200.3 - 9, 1.0000001).renders).to.equal(1)
				F.ClearGroupCache()
			end
		},
		{
			name = "a group inside a group is not made again either when the whole clip moves by whole pixels, and both are when it moves by a fraction",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(nestedGroupMovie())
				expect(drawGroups(root, 5.5, 6.5).renders).to.equal(2)
				expect(drawGroups(root, 5.5 + 9, 6.5 - 4).renders).to.equal(0)
				local fresh = drawGroups(F.NewRoot(nestedGroupMovie()), 5.5 + 9, 6.5 - 4)
				local moved = drawGroups(root, 5.5 + 9, 6.5 - 4)

				for i = 1, #fresh.screen do
					expect(moved.screen[i]).to.aboutEqual(fresh.screen[i], 1e-6)
				end

				expect(drawGroups(root, 5.75 + 9, 6.5 - 4).renders).to.equal(2)
				F.ClearGroupCache()
			end
		},
		{
			name = "a changed clip makes its group image again even when the clip also moved by whole pixels",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(groupMovie())
				drawGroups(root, 10, 10)
				root:Child("Holder"):Child("Group"):_touch() -- what it holds changed
				expect(drawGroups(root, 12, 11).renders).to.equal(1)
				F.ClearGroupCache()
			end
		},
		{
			-- the radar's view cone is a morph shape (a triangle that opens from p at ratio 0 to pe at ratio 65535); the converter only keeps its outline, so it was never drawn
			name = "a morph marked as a fill is drawn as a flat triangle between its start and end outlines at the ratio of its entry, one not marked is not drawn",
			func = function(state)
				local F = GryMod.Flash
				local function coneMovie(ratio, fill)
					return {
						w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
						chars = {
							[1] = {k = "morph", ox = 0, oy = 0, w = 10, h = 10, ex = -10, ey = 0, ew = 30, eh = 10, fill = fill, p = {0, 0, 10, 0, 5, 10}, pe = {-10, 0, 20, 0, 5, 10}},
							[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Cone", r = ratio}}}}
						},
						root = {{{d = 1, c = 2, n = "Holder"}}}
					}
				end

				local function points(ratio, fill)
					local triangles = drawnTriangles(F.NewRoot(coneMovie(ratio, fill)), 0, 0, 1)

					return triangles
				end

				local function hasPoint(triangle, x, y)
					for i = 1, 5, 2 do
						if math.abs(triangle[i] - x) < 1e-3 and math.abs(triangle[i + 1] - y) < 1e-3 then
							return true
						end
					end

					return false
				end

				expect(#points(0, nil)).to.equal(0)

				local start = points(0, true)
				expect(#start).to.equal(1)
				expect(hasPoint(start[1], 0, 0) and hasPoint(start[1], 10, 0) and hasPoint(start[1], 5, 10)).to.beTrue()

				local finish = points(65535, true)
				expect(#finish).to.equal(1)
				expect(hasPoint(finish[1], -10, 0) and hasPoint(finish[1], 20, 0) and hasPoint(finish[1], 5, 10)).to.beTrue()

				local middle = points(32767.5, true)
				expect(#middle).to.equal(1)
				expect(hasPoint(middle[1], -5, 0) and hasPoint(middle[1], 15, 0) and hasPoint(middle[1], 5, 10)).to.beTrue()
			end
		},
		{
			name = "an outline is cut into few convex pieces, a convex one stays whole, a bow tie (no simple polygon) is refused",
			func = function(state)
				local F = GryMod.Flash
				expect(#F.MaskPieces({0, 0, 10, 0, 10, 10, 0, 10})).to.equal(1)
				expect(#F.MaskPieces(L_SHAPE)).to.equal(2)
				-- the outline of the radar's noise mask: one reflex corner
				local radar = F.Load("hud_radarcompassstealth").chars[84].p
				expect(#F.MaskPieces(radar)).to.beLessThan(4)
				expect(F.MaskPieces({0, 0, 10, 10, 10, 0, 0, 10})).to.beNil()
			end
		},
		{
			name = "a mask shaped like an L lets through the L and nothing of its notch",
			func = function(state)
				local root = GryMod.Flash.NewRoot(maskedMovie(L_SHAPE))
				local triangles = drawnTriangles(root)
				expect(#triangles).to.beGreaterThan(0)
				expect(area(triangles)).to.aboutEqual(polygonArea(L_SHAPE), 0.5)
				expect(allInside(triangles, moved(L_SHAPE, 10, 20))).to.beTrue()
				local _, _, masks = GryMod.Flash.DrawState()
				expect(masks).to.equal(0)
			end
		},
		{
			name = "a mask that is concave the other way (a U), wound either way, lets through the U only",
			func = function(state)
				local u = {0, 0, 30, 0, 30, 60, 70, 60, 70, 0, 100, 0, 100, 100, 0, 100}
				local reversed = {}

				for i = #u / 2, 1, -1 do
					reversed[#reversed + 1], reversed[#reversed + 2] = u[i * 2 - 1], u[i * 2]
				end

				for _, outline in ipairs({u, reversed}) do
					local triangles = drawnTriangles(GryMod.Flash.NewRoot(maskedMovie(outline)))
					expect(area(triangles)).to.aboutEqual(polygonArea(u), 0.5)
					expect(allInside(triangles, moved(u, 10, 20))).to.beTrue()
				end
			end
		},
		{
			name = "a quad that lies in the notch of a concave mask draws nothing",
			func = function(state)
				local m = maskedMovie(L_SHAPE)
				-- the quad is 20 x 20 at (60, 60) from the mask's origin: in the notch of the L
				m.chars[1].dw, m.chars[1].dh = 20, 20
				m.root[1][2].m = {1, 0, 0, 1, 70, 80}
				expect(#drawnTriangles(GryMod.Flash.NewRoot(m))).to.equal(0)
			end
		},
		{
			name = "a convex mask still clips to exactly its polygon",
			func = function(state)
				local diamond = {50, 0, 100, 50, 50, 100, 0, 50}
				local triangles = drawnTriangles(GryMod.Flash.NewRoot(maskedMovie(diamond)))
				expect(area(triangles)).to.aboutEqual(polygonArea(diamond), 0.5)
				expect(allInside(triangles, moved(diamond, 10, 20))).to.beTrue()
			end
		},
		{
			name = "a mask of two separate rectangles lets through the two of them and nothing of the gap",
			func = function(state)
				local triangles = drawnTriangles(GryMod.Flash.NewRoot(maskedMovieOf(TWO_BARS)))
				expect(#triangles).to.beGreaterThan(0)
				expect(area(triangles)).to.aboutEqual(2 * 30 * 100, 0.5)

				-- every triangle lies in one of the two rectangles
				local moved1, moved2 = moved(TWO_BARS[1], 10, 20), moved(TWO_BARS[2], 10, 20)

				for _, t in ipairs(triangles) do
					local cx, cy = (t[1] + t[3] + t[5]) / 3, (t[2] + t[4] + t[6]) / 3
					expect(insideOrOn(cx, cy, moved1, 0.01) or insideOrOn(cx, cy, moved2, 0.01)).to.beTrue()
				end

				local _, _, masks = GryMod.Flash.DrawState()
				expect(masks).to.equal(0)
			end
		},
		{
			name = "a quad in the gap between the rectangles of a mask draws nothing",
			func = function(state)
				local m = maskedMovieOf(TWO_BARS)
				-- 30 x 100 from 35 to 65 of the mask's origin: between the rectangles (30 and 70)
				m.chars[1].ox, m.chars[1].dw = 35, 30
				expect(#drawnTriangles(GryMod.Flash.NewRoot(m))).to.equal(0)
			end
		},
		{
			name = "a quad across the contours of a mask is cut once: the area is the one of the mask, never twice",
			func = function(state)
				-- two rectangles that touch, one concave contour (two pieces) and an island: the quad covers all of them
				local touching = {{0, 0, 50, 0, 50, 100, 0, 100}, {50, 0, 100, 0, 100, 100, 50, 100}}
				expect(area(drawnTriangles(GryMod.Flash.NewRoot(maskedMovieOf(touching))))).to.aboutEqual(100 * 100, 0.5)

				local island = {0, 0, 100, 0, 100, 40, 40, 40, 40, 100, 0, 100}
				local m = maskedMovieOf({island, {60, 60, 90, 60, 90, 90, 60, 90}})
				expect(area(drawnTriangles(GryMod.Flash.NewRoot(m)))).to.aboutEqual(polygonArea(island) + 30 * 30, 0.5)
			end
		},
		{
			name = "a mask of several contours whose outline the drawing code cannot cut is drawn without a mask, like a single one",
			func = function(state)
				local bowTie = {0, 0, 10, 10, 10, 0, 0, 10}
				local m = maskedMovieOf({TWO_BARS[1], bowTie})
				expect(area(drawnTriangles(GryMod.Flash.NewRoot(m)))).to.aboutEqual(100 * 100, 0.5)
			end
		},
		{
			name = "a morph mask of several contours follows its ratio: the start at 0, the end at 65535, between them in between",
			func = function(state)
				local function drawnArea(ratio)
					return area(drawnTriangles(GryMod.Flash.NewRoot(morphingMovie(ratio))))
				end

				expect(drawnArea(0)).to.aboutEqual(2 * 30 * 100, 0.5)
				expect(drawnArea(65535)).to.aboutEqual(2 * 20 * 100, 0.5)
				expect(drawnArea(32767.5)).to.aboutEqual(2 * 25 * 100, 0.5)
				expect(drawnArea(0)).to.aboutEqual(2 * 30 * 100, 0.5) -- back to the start after the others
			end
		},
		{
			name = "the pieces of a morph mask are kept per ratio, in a bounded number",
			func = function(state)
				local F = GryMod.Flash
				local m = morphingMovie(100)
				local root = F.NewRoot(m)
				drawnTriangles(root)
				expect(F.MaskMorphCached(m.chars[2])).to.equal(1)
				drawnTriangles(root)
				expect(F.MaskMorphCached(m.chars[2])).to.equal(1) -- the same ratio again: nothing new

				for ratio = 1, 700 do
					root:EntryAt(1).ratio = ratio
					drawnTriangles(root)
				end

				expect(F.MaskMorphCached(m.chars[2])).to.beBetween(1, 600)
				-- and what is drawn is right once the cache has been emptied and filled again
				expect(area(drawnTriangles(F.NewRoot(morphingMovie(65535))))).to.aboutEqual(2 * 20 * 100, 0.5)
			end
		},
		{
			name = "a morph mask with one outline (p, pe) still follows its ratio",
			func = function(state)
				local m = morphingMovie(65535)
				m.chars[2].ps, m.chars[2].pes = nil, nil
				m.chars[2].p, m.chars[2].pe = {0, 0, 100, 0, 100, 100, 0, 100}, {0, 0, 50, 0, 50, 100, 0, 100}
				expect(area(drawnTriangles(GryMod.Flash.NewRoot(m)))).to.aboutEqual(50 * 100, 0.5)
				m.root[1][1].r = 0
				expect(area(drawnTriangles(GryMod.Flash.NewRoot(m)))).to.aboutEqual(100 * 100, 0.5)
			end
		},
		{
			name = "the noise of a malfunctioning radar stays inside the outline of the radar",
			func = function(state)
				local movie = GryMod.Flash.Load("hud_radarcompassstealth")
				local outline = movie.chars[84].p -- the shape of the NoiseMask clip
				expect(outline).toNot.beNil()
				local panel = GryMod.FlashRadar.New(movie)
				panel:Destroy(1)

				for _ = 1, 5 do panel:Update(1 / 30) end

				local noise = panel.main:Child("Noise")
				expect(noise.visible).to.beTrue()

				-- only the noise is drawn: the rest of the panel is hidden
				for _, entry in ipairs(panel.main:Entries()) do
					if entry.clip and entry.clip ~= noise then
						entry.clip.visible = false
					end
				end

				local triangles = drawnTriangles(panel.root, 0, 0, 1)
				expect(#triangles).to.beGreaterThan(0)
				-- the outline on the stage: the NoiseMask entry's matrix, then the one of the panel's main clip
				local mask = panel.main.names.NoiseMask.m
				local main = panel.main.entry.m
				local onStage = {}

				for i = 1, #outline, 2 do
					local x, y = outline[i] * mask[1] + outline[i + 1] * mask[3] + mask[5], outline[i] * mask[2] + outline[i + 1] * mask[4] + mask[6]
					onStage[i] = x * main[1] + y * main[3] + main[5]
					onStage[i + 1] = x * main[2] + y * main[4] + main[6]
				end

				expect(allInside(triangles, onStage)).to.beTrue()
				-- the noise picture is bigger than the outline: all of the outline is covered
				expect(area(triangles)).to.aboutEqual(polygonArea(onStage), polygonArea(onStage) * 0.01)
			end
		},
		{
			name = "a group image is a power of two up to 1024 pixels, then a multiple of 512 (a full-screen one is not rounded up to twice its size)",
			func = function(state)
				local F = GryMod.Flash
				expect(F.TargetSide(1)).to.equal(64)
				expect(F.TargetSide(65)).to.equal(128)
				expect(F.TargetSide(1024)).to.equal(1024)
				expect(F.TargetSide(1025)).to.equal(1536)
				expect(F.TargetSide(2151)).to.equal(2560)
				expect(F.TargetSide(2816)).to.equal(3072)
				expect(F.TargetSide(2944)).to.equal(3072) -- two big groups a little apart share an image
				expect(F.TargetSide(3825)).to.equal(4096)
			end
		},
		{
			name = "releasing a group that never had an image (empty or too big) does not error",
			func = function(state)
				local F = GryMod.Flash
				F.ReleaseEntry({cache = {}})
				F.ReleaseEntry({cache = {target = nil, textureW = nil}, clip = {list = {}}})
			end
		},
		{
			name = "releasing a clip gives the images of its groups back to the pool, once",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(movie())
				local group = root:Child("Holder"):Child("Group")
				local entry = root:Child("Holder"):EntryAt(1)
				entry.cache = {target = {}, textureW = 64, textureH = 128}
				local before = F.PoolSize()
				F.ReleaseClip(root)
				expect(F.PoolSize()).to.equal(before + 1)
				expect(entry.cache).to.beNil()
				F.ReleaseClip(root) -- nothing left to give back
				expect(F.PoolSize()).to.equal(before + 1)
				F.ClearGroupCache() -- the pool holds a fake target: do not let a real drawing take it
			end
		},
		{
			name = "an error while drawing is reported once, leaves the drawing state clean and does not stop the next frame",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				m.chars[1] = nil -- the shape disappears: drawing it raises an error, inside the measuring pass of the group
				local ok = F.Draw(root, 0, 0, 1)
				expect(ok).to.beFalse()
				local measuring, depth, masks = F.DrawState()
				expect(measuring).to.beFalse()
				expect(depth).to.equal(0)
				expect(masks).to.equal(0)
				m.chars[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1}
				expect(F.DrawState()).to.beFalse() -- still clean for the next call
			end
		},
		-- a hook on a clip: the radar draws its map between the glass of its panel and the rest (cl_hud_radar_flash.lua)
		{
			name = "drawBefore runs between the entries below its depth and the ones from it on, with the clip's matrix (no hook support in the drawing)",
			func = function(state)
				local root = GryMod.Flash.NewRoot(hookMovie())
				local holder = root:Child("Holder")
				local got
				holder.drawBeforeDepth = 3

				local events = drawEvents(root, 10, 20, 2, function(record)
					holder.drawBefore = function(a, b, c, d, tx, ty)
						got = {a, b, c, d, tx, ty}
						record("hook")
					end
				end)

				expect(events[1]).to.equal("A")
				expect(events[2]).to.equal("hook")
				expect(events[3]).to.equal("B")
				expect(#events).to.equal(3)
				expect(got[1]).to.equal(2)
				expect(got[2]).to.equal(0)
				expect(got[3]).to.equal(0)
				expect(got[4]).to.equal(2)
				expect(got[5]).to.equal(10)
				expect(got[6]).to.equal(20)
			end
		},
		{
			name = "drawBefore runs once a frame and after everything when no entry is at or above its depth (the map is not lost)",
			func = function(state)
				local root = GryMod.Flash.NewRoot(hookMovie())
				local holder = root:Child("Holder")
				local calls = 0
				holder.drawBeforeDepth = 99

				local events = drawEvents(root, 0, 0, 1, function(record)
					holder.drawBefore = function() calls = calls + 1 record("hook") end
				end)

				expect(calls).to.equal(1)
				expect(events[#events]).to.equal("hook")
				expect(events[1]).to.equal("A")
			end
		},
		{
			name = "a clip without drawBefore draws as before, and a hook that raises an error does not stop the picture",
			func = function(state)
				local root = GryMod.Flash.NewRoot(hookMovie())
				local plain = drawEvents(root, 0, 0, 1)
				expect(plain[1]).to.equal("A")
				expect(plain[2]).to.equal("B")
				expect(#plain).to.equal(2)

				local holder = root:Child("Holder")
				holder.drawBeforeDepth = 3
				holder.drawBefore = function() error("hook failed", 0) end
				local original = ErrorNoHalt
				local told = {}
				ErrorNoHalt = function(message) told[#told + 1] = message end
				local ok, events = pcall(drawEvents, root, 0, 0, 1)
				-- twice: the message is told once
				local again = ok and drawEvents(root, 0, 0, 1)
				ErrorNoHalt = original

				expect(ok).to.beTrue()
				expect(events[1]).to.equal("A")
				expect(events[2]).to.equal("B")
				expect(again[2]).to.equal("B")
				expect(#told).to.equal(1)
				expect(string.find(told[1], "hook failed", 1, true) ~= nil).to.beTrue()
				local measuring, depth, masks = GryMod.Flash.DrawState()
				expect(measuring).to.beFalse()
				expect(depth).to.equal(0)
				expect(masks).to.equal(0)
			end
		}
	}
}
