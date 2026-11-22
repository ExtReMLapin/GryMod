-- Tests of the minimap's view module (lua/grymod/client/minimap/view.lua), GLuaTest format, client realm: the maths from the world to the radar's
-- pixels (the formula of Radar.Contacts), the tiles around the player, and the drawing of the tiles through the radar's transform, clipped
-- on the CPU against the radar frame. The modules of the other agents (Cache, Settings, Gen) are replaced by stand-ins that are put back in
-- afterEach (inside a pcall, also when a case fails); the three surface functions are replaced by recorders, the same way.
--
-- The numbers: the stand-in tile is 64 units wide (resolution 512, 8 pixels a metre; the stand-in's TileUnits is res / ppm), the range is 64
-- units (so one world unit is PIXELS / 64 radar pixels, 43 / 64) and the player stands in the middle of tile (0, 0) at (32, 32), so the tile
-- is 43 radar pixels wide with the player in its centre: its corners are at +-21.5 radar pixels.

local TILE = 64
local RANGE = 64
local EXTENT = RANGE * 1.75

local original = {}
local recorded

local function pixels()
	return GryMod.RadarShared.PIXELS
end

local function near(a, b, tolerance)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (tolerance or 1e-6)
end

-- the area of a polygon in the screen's coordinates (y down): positive when the vertices go clockwise on the screen
local function signedArea(verts)
	local sum = 0

	for i = 1, #verts do
		local a, b = verts[i], verts[i % #verts + 1]
		sum = sum + (a.x * b.y - b.x * a.y)
	end

	return sum / 2
end

-- Each key the stand-ins and recorders need is saved by name and put back by name.
local function replaceModules(state)
	local M = GryMod.Minimap

	original.Cache, original.Settings, original.Gen = M.Cache, M.Settings, M.Gen
	original.DrawPoly, original.SetMaterial, original.SetDrawColor = surface.DrawPoly, surface.SetMaterial, surface.SetDrawColor
	original.FRAME = GryMod.FlashRadar and GryMod.FlashRadar.FRAME
	original.MAP_LEFT = GryMod.FlashRadar and GryMod.FlashRadar.MAP_LEFT
	original.MAX_MATERIALS = GryMod.Minimap.View.MAX_MATERIALS

	-- The numbers written in these tests (the notch at x = -46.75, the corners at 62 and 45...) are the ORIGINAL game's polygon; the radar's real frame is now the
	-- glass of the movie (tests/minimap/radar_frame_test.lua covers it and the map frame computed from it). The frame is put back in restoreModules.
	if GryMod.FlashRadar and GryMod.FlashRadar.ORIGINAL_FRAME then
		GryMod.FlashRadar.FRAME = GryMod.FlashRadar.ORIGINAL_FRAME
		-- and the radar's own left bound of the map is not part of the original game's frame: the cases that want one set it
		GryMod.FlashRadar.MAP_LEFT = nil
	end
	original.saved = true

	state.existing = {}
	state.all = false
	state.materialCalls = {}
	state.belowExisting = {}
	state.belowAll = false
	state.belowCalls = {}
	state.outsideExisting = {}
	state.outsideAll = false
	state.outsideCalls = {}
	state.hasCalls = {}
	recorded = {polys = {}, colors = {}, materials = {}, current = nil}

	-- the cache: the geometry of the real one (tile edge = res / ppm / metres per unit) is replaced by the stand-in's (res / ppm units), so the numbers
	-- are whole; Material answers for the tiles of state.existing ("tx,ty"), or for all of them; whatever writes or generates raises
	M.Cache = {
		TileUnits = function(res, ppm) return res / ppm end,
		Material = function(tile)
			-- the outside is level "open" in these tests: its own set of existing tiles and its own list of calls
			if tile.level == "open" then
				state.outsideCalls[#state.outsideCalls + 1] = tile.tx .. "," .. tile.ty

				if state.outsideAll or state.outsideExisting[tile.tx .. "," .. tile.ty] then
					return {token = tile.tx .. "," .. tile.ty, level = tile.level, res = tile.res, ppm = tile.ppm}
				end

				return nil
			end

			-- the floor below is level "z0" in these tests: its own set of existing tiles and its own list of calls
			if tile.level == "z0" then
				state.belowCalls[#state.belowCalls + 1] = tile.tx .. "," .. tile.ty

				if state.belowAll or state.belowExisting[tile.tx .. "," .. tile.ty] then
					return {token = tile.tx .. "," .. tile.ty, level = tile.level, res = tile.res, ppm = tile.ppm}
				end

				return nil
			end

			state.materialCalls[#state.materialCalls + 1] = tile.tx .. "," .. tile.ty

			if state.all or state.existing[tile.tx .. "," .. tile.ty] then
				return {token = tile.tx .. "," .. tile.ty, level = tile.level, res = tile.res, ppm = tile.ppm}
			end

			return nil
		end,
		Has = function(tile)
			state.hasCalls[#state.hasCalls + 1] = tile.tx .. "," .. tile.ty

			if tile.level == "open" then
				return state.outsideAll or state.outsideExisting[tile.tx .. "," .. tile.ty] == true
			end

			if tile.level == "z0" then
				return state.belowAll or state.belowExisting[tile.tx .. "," .. tile.ty] == true
			end

			return state.all or state.existing[tile.tx .. "," .. tile.ty] == true
		end,
		Store = function() error("the view must never write a tile") end,
		Clear = function() error("the view must never clear the cache") end,
		Prune = function() error("the view must never prune the cache") end
	}

	M.Settings = {
		TileRes = function() return 512 end,
		Definition = function() return 8 end,
		Rotate = function() return true end,
		Enabled = function() return true end,
		BudgetMs = function() return 6 end
	}

	-- the generator: any use of it raises (the view never asks for a tile)
	M.Gen = setmetatable({}, {
		__index = function(_, key) error("the view must never touch Gen (" .. tostring(key) .. ")") end
	})

	surface.SetMaterial = function(material) recorded.current = material recorded.materials[#recorded.materials + 1] = material end
	surface.SetDrawColor = function(r, g, b, a) recorded.colour = {r, g, b, a} recorded.colors[#recorded.colors + 1] = {r, g, b, a} end
	surface.DrawPoly = function(verts)
		local copy = {}

		for i = 1, #verts do
			copy[i] = {x = verts[i].x, y = verts[i].y, u = verts[i].u, v = verts[i].v}
		end

		recorded.polys[#recorded.polys + 1] = {verts = copy, material = recorded.current, colour = recorded.colour}
	end
end

local function restoreModules()
	if not original.saved then
		return
	end

	local M = GryMod.Minimap

	M.Cache, M.Settings, M.Gen = original.Cache, original.Settings, original.Gen

	if GryMod.FlashRadar and original.FRAME then
		GryMod.FlashRadar.FRAME = original.FRAME
		GryMod.FlashRadar.MAP_LEFT = original.MAP_LEFT
	end

	GryMod.Minimap.View.MAX_MATERIALS = original.MAX_MATERIALS

	surface.DrawPoly, surface.SetMaterial, surface.SetDrawColor = original.DrawPoly, original.SetMaterial, original.SetDrawColor
	original = {}
end

local IDENTITY = {a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0}

local function level()
	return {id = "a1", zlo = -32, zhi = 128}
end

-- the floor below the main level
local function lower()
	return {id = "z0", zlo = -160, zhi = 0}
end

-- the outside (the open level of the map) under the floor below
local function open()
	return {id = "open", open = true, zlo = -600, zhi = 900}
end

-- how many polygons of each level, and where the first of the main level is
local function groups()
	local below, main, firstMain = 0, 0, nil

	for i, poly in ipairs(recorded.polys) do
		if poly.material.level == "z0" then
			below = below + 1
		else
			main = main + 1
			firstMain = firstMain or i
		end
	end

	return below, main, firstMain
end

-- the player at the middle of tile (0, 0), looking along +X (yaw 0)
local function draw(state, xf, extra)
	extra = extra or {}

	return GryMod.Minimap.View.Draw(xf or IDENTITY, extra.px or 32, extra.py or 32, extra.yaw or 0, extra.range or RANGE, extra.level or level(), extra.alpha or 1, extra.below, extra.belowAlpha, extra.outside, extra.outsideAlpha)
end

local function projected(xf, rx, ry)
	return xf.a * rx + xf.c * ry + xf.tx, xf.b * rx + xf.d * ry + xf.ty
end

-- is (x, y) inside the polygon (the radar frame), or within 1e-6 of its border
local function insideOrOn(poly, x, y)
	local inside = false
	local j = #poly

	for i = 1, #poly do
		local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]

		-- distance to the segment
		local ex, ey = xj - xi, yj - yi
		local length2 = ex * ex + ey * ey
		local t = length2 > 0 and math.Clamp(((x - xi) * ex + (y - yi) * ey) / length2, 0, 1) or 0
		local dx, dy = x - (xi + ex * t), y - (yi + ey * t)

		if dx * dx + dy * dy < 1e-10 then
			return true
		end

		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
			inside = not inside
		end

		j = i
	end

	return inside
end

local function inConvexQuad(quad, x, y)
	local sign
	for i = 1, 4 do
		local a, b = quad[i], quad[i % 4 + 1]
		local cross = (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1])

		if cross ~= 0 then
			local s = cross > 0
			if sign == nil then sign = s elseif sign ~= s then return false end
		end
	end

	return true
end

-- the area of (tile quad in radar pixels) inside the map frame, by sampling: the independent check of the clipping
local function sampledIntersection(quad, step)
	local frame = GryMod.Minimap.View.MapFrame()
	local count = 0

	-- the grid is offset by an odd fraction of the step: the frame's and the tiles' borders are on whole numbers, and points exactly on them would be counted
	-- as inside and bias the sum by half the perimeter times the step
	for x = -60 + step * 0.37, 64, step do
		for y = -44 + step * 0.37, 47, step do
			if inConvexQuad(quad, x, y) and insideOrOn(frame, x, y) then
				count = count + 1
			end
		end
	end

	return count * step * step
end

-- the radar pixels of the corners of tile (tx, ty) with the player at (px, py), yaw 0 (the formula, by hand: rx = -dy * k, ry = -dx * k)
local function handQuad(tx, ty, px, py)
	local k = pixels() / RANGE
	local x0, y0 = tx * TILE, ty * TILE
	local x1, y1 = x0 + TILE, y0 + TILE
	local function point(x, y) return {-(y - py) * k, -(x - px) * k} end

	return {point(x1, y1), point(x1, y0), point(x0, y0), point(x0, y1)}
end

return {
	groupName = "GryMod minimap view",
	beforeEach = function(state)
		replaceModules(state)
	end,
	afterEach = function()
		pcall(restoreModules)
	end,
	cases = {
		-- ToRadar -----------------------------------------------------------------------------------------------------------------
		{
			name = "ToRadar: the point straight ahead at the range is (0, -PIXELS) for yaw 0, 90, 180 and -90 (production change that fails: a wrong sign or a wrong sin/cos)",
			func = function()
				local V = GryMod.Minimap.View
				local P = pixels()
				local R = 1000
				-- the direction the player looks at for each yaw
				local ahead = {[0] = {R, 0}, [90] = {0, R}, [180] = {-R, 0}, [-90] = {0, -R}}

				for yaw, d in pairs(ahead) do
					local rx, ry = V.ToRadar(500, -300, yaw, 500 + d[1], -300 + d[2], R, true)

					expect(near(rx, 0, 1e-9)).to.beTrue()
					expect(near(ry, -P, 1e-9)).to.beTrue()
				end
			end
		},
		{
			name = "ToRadar: the point on the right of the view (yaw 0: -Y) is (+PIXELS, 0), and so for the other three yaws",
			func = function()
				local V = GryMod.Minimap.View
				local P = pixels()
				local R = 1000
				-- the right of the view for each yaw
				local right = {[0] = {0, -R}, [90] = {R, 0}, [180] = {0, R}, [-90] = {-R, 0}}

				for yaw, d in pairs(right) do
					local rx, ry = V.ToRadar(0, 0, yaw, d[1], d[2], R, true)

					expect(near(rx, P, 1e-9)).to.beTrue()
					expect(near(ry, 0, 1e-9)).to.beTrue()
				end
			end
		},
		{
			name = "ToRadar: with rotate = false the yaw is ignored and +X is up (0, -PIXELS), -Y is the right (+PIXELS, 0)",
			func = function()
				local V = GryMod.Minimap.View
				local P = pixels()

				for _, yaw in ipairs({0, 37, 90, 180, -90, 1e6}) do
					local rx, ry = V.ToRadar(10, 20, yaw, 10 + 500, 20, 500, false)
					expect(near(rx, 0, 1e-9) and near(ry, -P, 1e-9)).to.beTrue()

					rx, ry = V.ToRadar(10, 20, yaw, 10, 20 - 500, 500, false)
					expect(near(rx, P, 1e-9) and near(ry, 0, 1e-9)).to.beTrue()
				end
			end
		},
		{
			name = "ToRadar: another range scales the pixels (half the range, twice the pixels; twice the range, half) and a point at distance zero is the player (0, 0)",
			func = function()
				local V = GryMod.Minimap.View
				local P = pixels()
				local rx, ry = V.ToRadar(0, 0, 0, 500, 0, 1000, true)
				expect(near(ry, -P / 2, 1e-9) and near(rx, 0, 1e-9)).to.beTrue()

				rx, ry = V.ToRadar(0, 0, 0, 500, 0, 500, true)
				expect(near(ry, -P, 1e-9)).to.beTrue()

				rx, ry = V.ToRadar(0, 0, 0, 500, 0, 250, true)
				expect(near(ry, -2 * P, 1e-9)).to.beTrue()

				rx, ry = V.ToRadar(123, -45, 77, 123, -45, 300, true)
				expect(near(rx, 0, 1e-12) and near(ry, 0, 1e-12)).to.beTrue()
			end
		},
		{
			name = "ToRadar: the same pixels as Radar.Contacts (the real formula of the radar) for random points, yaws and ranges",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar
				local S = GryMod.RadarShared
				local PX, CX, CY = Radar.UNITS_PIXEL, Radar.UNITS_CENTRE_X, Radar.UNITS_CENTRE_Y
				local checked = 0

				for n = 1, 60 do
					local rangeMetres = math.random(20, 100)
					local rangeUnits = rangeMetres / S.METRES_PER_UNIT
					local yaw = math.random() * 720 - 360
					local px, py, pz = math.random(-5000, 5000), math.random(-5000, 5000), math.random(-500, 500)
					-- inside the frame whatever the angle: within half the range
					local r = math.random() * 0.5 * rangeUnits
					local a = math.random() * 2 * math.pi
					local x, y = px + r * math.cos(a), py + r * math.sin(a)
					local list = Radar.Contacts(Vector(px, py, pz), yaw, {{id = 1, x = x, y = y, z = pz, yaw = 0, type = 1, sub = 4, marker = false, big = false}}, 0, rangeMetres)

					expect(list[1] ~= nil).to.beTrue()

					local rx, ry = V.ToRadar(px, py, yaw, x, y, rangeUnits, true)
					local ex, ey = (list[1].x - CX) / PX, (list[1].y - CY) / PX

					expect(near(rx, ex, 1e-6) and near(ry, ey, 1e-6)).to.beTrue()
					checked = checked + 1
				end

				expect(checked).to.equal(60)
			end
		},
		{
			name = "ToRadar: bad input (nil, NaN, infinite, a range of 0 or less) gives nil and a reason, never an error",
			func = function()
				local V = GryMod.Minimap.View
				local nan, inf = 0 / 0, math.huge

				local bad = {
					{nil, 0, 0, 0, 0, 100, true}, {0, nil, 0, 0, 0, 100, true}, {0, 0, nan, 0, 0, 100, true}, {0, 0, 0, nan, 0, 100, true},
					{0, 0, 0, 0, inf, 100, true}, {0, 0, 0, 1, 1, 0, true}, {0, 0, 0, 1, 1, -5, true}, {0, 0, 0, 1, 1, nan, true}, {0, 0, 0, 1, 1, nil, true},
					{"a", 0, 0, 0, 0, 100, true}
				}

				for i = 1, #bad do
					local b = bad[i]
					local ok, rx, reason = pcall(V.ToRadar, b[1], b[2], b[3], b[4], b[5], b[6], b[7])

					expect(ok).to.beTrue()
					expect(rx).to.beNil()
					expect(type(reason)).to.equal("string")
				end

				-- a yaw that is no number matters only when the map turns
				local ok, rx = pcall(V.ToRadar, 0, 0, nil, 10, 10, 100, false)
				expect(ok and type(rx) == "number").to.beTrue()
				ok, rx = pcall(V.ToRadar, 0, 0, nan, 10, 10, 100, true)
				expect(ok and rx == nil).to.beTrue()
			end
		},

		-- VisibleTiles ------------------------------------------------------------------------------------------------------------
		{
			name = "VisibleTiles: a position on the corner of four tiles gives those four, with the level's id, the resolution and the definition in each",
			func = function()
				local V = GryMod.Minimap.View
				local list = V.VisibleTiles(level(), 0, 0, 10, 512, 8)
				local seen = {}

				expect(#list).to.equal(4)

				for _, tile in ipairs(list) do
					seen[tile.tx .. "," .. tile.ty] = true
					expect(tile.level).to.equal("a1")
					expect(tile.res).to.equal(512)
					expect(tile.ppm).to.equal(8)
				end

				expect(seen["-1,-1"] and seen["-1,0"] and seen["0,-1"] and seen["0,0"]).to.beTrue()
			end
		},
		{
			name = "VisibleTiles: inside one tile gives one; on the boundary between two gives two",
			func = function()
				local V = GryMod.Minimap.View
				local one = V.VisibleTiles(level(), 32, 32, 10, 512, 8)
				expect(#one).to.equal(1)
				expect(one[1].tx).to.equal(0)
				expect(one[1].ty).to.equal(0)

				local two = V.VisibleTiles(level(), 64, 32, 10, 512, 8)
				expect(#two).to.equal(2)
				local seen = {}

				for _, tile in ipairs(two) do
					seen[tile.tx .. "," .. tile.ty] = true
				end

				expect(seen["0,0"] and seen["1,0"]).to.beTrue()
			end
		},
		{
			name = "VisibleTiles: negative positions, tile indices are floors (-110..-90 is tile -2; -80..-60 is tiles -2 and -1)",
			func = function()
				local V = GryMod.Minimap.View
				local list = V.VisibleTiles(level(), -100, -70, 10, 512, 8)
				local seen = {}

				for _, tile in ipairs(list) do
					seen[tile.tx .. "," .. tile.ty] = true
				end

				expect(#list).to.equal(2)
				expect(seen["-2,-2"] and seen["-2,-1"]).to.beTrue()
			end
		},
		{
			name = "VisibleTiles: with the extent of the radar (1.75 times the range) around (0, 0) it gives the 4 by 4 tiles whose bounds touch the square, no more, no fewer",
			func = function()
				local V = GryMod.Minimap.View
				local list = V.VisibleTiles(level(), 0, 0, EXTENT, 512, 8)
				local seen = {}

				for _, tile in ipairs(list) do
					seen[tile.tx .. "," .. tile.ty] = true
				end

				-- brute force over a wide range of tile indices: touching means the bounds meet the square [-112, 112]
				local expected = 0

				for tx = -10, 10 do
					for ty = -10, 10 do
						local touches = tx * TILE <= EXTENT and (tx + 1) * TILE >= -EXTENT and ty * TILE <= EXTENT and (ty + 1) * TILE >= -EXTENT

						if touches then
							expected = expected + 1
							expect(seen[tx .. "," .. ty]).to.beTrue()
						else
							expect(seen[tx .. "," .. ty]).to.beNil()
						end
					end
				end

				expect(#list).to.equal(expected)
				expect(#list).to.equal(16)
			end
		},
		{
			name = "VisibleTiles: the tile edge comes from Cache.TileUnits(res, ppm), so another definition gives another grid",
			func = function()
				local V = GryMod.Minimap.View
				-- 512 / 16 = 32 units a tile: a square of half-side 10 around (32, 32) is on the corner of four tiles
				local list = V.VisibleTiles(level(), 32, 32, 10, 512, 16)
				expect(#list).to.equal(4)
				expect(list[1].ppm).to.equal(16)
			end
		},
		{
			name = "VisibleTiles: bad input (no level, NaN, no extent, a tile edge of 0) gives an empty list and no error",
			func = function()
				local V = GryMod.Minimap.View
				local nan = 0 / 0

				for _, args in ipairs({
					{nil, 0, 0, 10, 512, 8}, {level(), nan, 0, 10, 512, 8}, {level(), 0, 0, nil, 512, 8}, {level(), 0, 0, -5, 512, 8},
					{level(), 0, 0, 10, nil, 8}, {level(), 0, 0, 10, 512, 0}, {{zlo = 0, zhi = 1}, 0, 0, 10, 512, 8}, {level(), 0, 0, 1e300, 512, 8}
				}) do
					local ok, list = pcall(V.VisibleTiles, args[1], args[2], args[3], args[4], args[5], args[6])

					expect(ok).to.beTrue()
					expect(type(list)).to.equal("table")
					expect(#list).to.equal(0)
				end
			end
		},

		-- Draw --------------------------------------------------------------------------------------------------------------------
		{
			name = "Draw: a tile entirely inside the frame is ONE polygon of 4 vertices, clockwise on the screen, with the u, v of the corner table exactly",
			func = function(state)
				state.existing["0,0"] = true
				draw(state)

				expect(#recorded.polys).to.equal(1)

				local verts = recorded.polys[1].verts
				expect(#verts).to.equal(4)
				expect(signedArea(verts) > 0).to.beTrue()

				-- (maxx, maxy) -> (0, 0), (maxx, miny) -> (1, 0), (minx, miny) -> (1, 1), (minx, maxy) -> (0, 1); at yaw 0 these are the radar's corners
				local quad = handQuad(0, 0, 32, 32)
				local uv = {{0, 0}, {1, 0}, {1, 1}, {0, 1}}

				for i = 1, 4 do
					expect(near(verts[i].x, quad[i][1], 1e-9)).to.beTrue()
					expect(near(verts[i].y, quad[i][2], 1e-9)).to.beTrue()
					expect(verts[i].u).to.equal(uv[i][1])
					expect(verts[i].v).to.equal(uv[i][2])
				end

				expect(near(signedArea(verts), 43 * 43, 1e-6) or near(signedArea(verts), pixels() ^ 2, 1e-6)).to.beTrue()
			end
		},
		{
			name = "Draw: the tile's material goes to surface.SetMaterial before its polygon, the colour is white with the alpha, once",
			func = function(state)
				state.existing["0,0"] = true
				draw(state, IDENTITY, {alpha = 0.6})

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.token).to.equal("0,0")
				expect(recorded.polys[1].material.level).to.equal("a1")
				-- the Cache was asked for the tile at the settings' resolution and definition
				expect(recorded.polys[1].material.res).to.equal(512)
				expect(recorded.polys[1].material.ppm).to.equal(8)
				expect(#recorded.colors >= 1).to.beTrue()

				local color = recorded.colors[#recorded.colors]

				expect(color[1]).to.equal(255)
				expect(color[2]).to.equal(255)
				expect(color[3]).to.equal(255)
				expect(near(color[4], 0.6 * 255, 1)).to.beTrue()
			end
		},
		{
			name = "Draw: the alpha is clamped to 0..255 (above 1 is 255) and an alpha of 0 draws nothing",
			func = function(state)
				state.existing["0,0"] = true
				draw(state, IDENTITY, {alpha = 7})
				expect(recorded.colors[#recorded.colors][4]).to.equal(255)

				recorded.polys, recorded.colors = {}, {}
				draw(state, IDENTITY, {alpha = 0})
				expect(#recorded.polys).to.equal(0)
			end
		},
		{
			name = "Draw: a tile that sticks out of the frame is clipped: a polygon whose vertices lie on the border with u, v interpolated linearly (hand-computed case)",
			func = function(state)
				-- tile (1, 0): its radar corners are (-21.5, -64.5) (u,v 0,0), (21.5, -64.5) (1,0), (21.5, -21.5) (1,1), (-21.5, -21.5) (0,1); the frame's top is y = -42:
				-- the cut is at 22.5 / 43 = 0.523256 of the way from the (0,0) corner to the (0,1) one, on both sides
				state.existing["1,0"] = true
				draw(state)

				expect(#recorded.polys).to.equal(1)

				local verts = recorded.polys[1].verts
				expect(#verts).to.equal(4)
				expect(signedArea(verts) > 0).to.beTrue()

				local P = pixels()
				local half = P / 2
				local cut = (64.5 - 42) / 43 -- tied to P = 43 and a tile of 43 radar pixels
				expect(P).to.equal(43)

				local expected = {
					{-half, -42, 0, cut}, {half, -42, 1, cut}, {half, -half, 1, 1}, {-half, -half, 0, 1}
				}

				for _, e in ipairs(expected) do
					local found = false

					for _, vert in ipairs(verts) do
						if near(vert.x, e[1], 1e-6) and near(vert.y, e[2], 1e-6) and near(vert.u, e[3], 1e-6) and near(vert.v, e[4], 1e-6) then
							found = true
						end
					end

					expect(found).to.beTrue()
				end

				-- 43 * (43 - 22.5)... the clipped area: width 43, height from -42 to -21.5
				expect(near(signedArea(verts), 43 * 20.5, 1e-6)).to.beTrue()
			end
		},
		{
			name = "Draw: a tile entirely outside the frame gives no polygon (and the Cache is not even asked for its material)",
			func = function(state)
				-- tile (2, 0): ry from -107 to -64, above the frame's top (-42), and out of the range circle
				state.existing["2,0"] = true
				state.existing["-2,0"] = true
				draw(state)

				expect(#recorded.polys).to.equal(0)

				for _, call in ipairs(state.materialCalls) do
					expect(call ~= "2,0" and call ~= "-2,0").to.beTrue()
				end
			end
		},
		{
			name = "Draw: four tiles in the frame give four polygons, each with its own material; tiles the Cache does not have are skipped",
			func = function(state)
				state.existing["0,0"], state.existing["-1,0"], state.existing["0,-1"], state.existing["-1,-1"] = true, true, true, true
				draw(state)

				expect(#recorded.polys).to.equal(4)

				local tokens = {}

				for _, poly in ipairs(recorded.polys) do
					tokens[poly.material.token] = true
				end

				expect(tokens["0,0"] and tokens["-1,0"] and tokens["0,-1"] and tokens["-1,-1"]).to.beTrue()

				-- one tile fewer
				recorded.polys = {}
				state.existing["-1,-1"] = nil
				draw(state)
				expect(#recorded.polys).to.equal(3)
			end
		},
		{
			name = "Draw: a material that is nil skips the tile without an error and the others are still drawn",
			func = function(state)
				state.existing["0,0"] = true
				state.existing["0,-1"] = false -- listed but Material answers nil for it
				local ok = pcall(draw, state)

				expect(ok).to.beTrue()
				expect(#recorded.polys).to.equal(1)
			end
		},
		{
			name = "Draw: the map fills the frame except the danger bar's strip (the sum of the polygon areas equals the tile's area inside the map frame, for tiles over the strip, the notch and the corners)",
			func = function(state)
				local frame = GryMod.Minimap.View.MapFrame()
				local P = pixels()
				-- the player at several places, so tiles cross the frame's left part, the notch (-58..-46.75, 17..45), the chamfered corner and every edge
				local cases = {
					{32, 32, 0, 1}, {32, 32, 0, 2}, {32, 32, 0, 0}, {32, 32, 1, 1}, {32, 32, 2, 1}, {-20, 80, 1, 2}, {70, 10, 0, 1}, {32, 96, 0, 2}, {0, 0, 0, 0}
				}

				for _, c in ipairs(cases) do
					state.existing = {}
					state.existing[c[3] .. "," .. c[4]] = true
					recorded.polys = {}
					draw(state, IDENTITY, {px = c[1], py = c[2]})

					local quad = handQuad(c[3], c[4], c[1], c[2])
					local expected = sampledIntersection(quad, 0.4)
					local total = 0

					for _, poly in ipairs(recorded.polys) do
						expect(signedArea(poly.verts) > 0).to.beTrue()
						total = total + signedArea(poly.verts)

						-- every vertex inside the frame (or on its border)
						for _, vert in ipairs(poly.verts) do
							expect(insideOrOn(frame, vert.x, vert.y)).to.beTrue()
						end
					end

					if math.abs(total - expected) > 0.01 * expected + 2.5 then
						error("tile " .. c[3] .. "," .. c[4] .. " with the player at " .. c[1] .. "," .. c[2] .. ": polygons cover " .. total .. ", the frame holds " .. expected .. " of it", 0)
					end
				end

				expect(P).to.equal(43)
			end
		},
		{
			name = "Draw: for random positions and yaws, every drawn vertex is inside the map frame, and the (u, v) of a vertex is the tile's point at that place",
			func = function(state)
				local frame = GryMod.Minimap.View.MapFrame()
				state.all = true

				for n = 1, 30 do
					recorded.polys = {}
					local px, py = math.random(-300, 300), math.random(-300, 300)
					local yaw = math.random() * 360 - 180
					draw(state, IDENTITY, {px = px, py = py, yaw = yaw})

					expect(#recorded.polys > 0).to.beTrue()

					local k = pixels() / RANGE
					local s, c = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))

					for _, poly in ipairs(recorded.polys) do
						expect(signedArea(poly.verts) > 0).to.beTrue()

						-- the tile of this polygon, from its token
						local tx, ty = string.match(poly.material.token, "^(-?%d+),(-?%d+)$")
						tx, ty = tonumber(tx), tonumber(ty)

						for _, vert in ipairs(poly.verts) do
							expect(insideOrOn(frame, vert.x, vert.y)).to.beTrue()

							-- invert the radar's formula (a rotation and a scale) to get the world point of the vertex and check the texture coordinates
							local dx = (vert.x * s - vert.y * c) / k
							local dy = -(vert.x * c + vert.y * s) / k
							local wx, wy = px + dx, py + dy
							local u = ((ty + 1) * TILE - wy) / TILE
							local v = ((tx + 1) * TILE - wx) / TILE

							expect(near(vert.u, u, 1e-6) and near(vert.v, v, 1e-6)).to.beTrue()
						end
					end
				end
			end
		},
		{
			name = "Draw: an arbitrary transform (scale 1.7, shear, offset) puts every vertex where the formula says: (a*rx + c*ry + tx, b*rx + d*ry + ty)",
			func = function(state)
				local xf = {a = 1.7, b = 0.25, c = -0.3, d = 1.9, tx = 120, ty = 80}
				state.existing["0,0"] = true
				draw(state, xf)

				expect(#recorded.polys).to.equal(1)

				local verts = recorded.polys[1].verts
				local quad = handQuad(0, 0, 32, 32)

				expect(#verts).to.equal(4)

				for i = 1, 4 do
					local sx, sy = projected(xf, quad[i][1], quad[i][2])

					expect(near(verts[i].x, sx, 1e-9) and near(verts[i].y, sy, 1e-9)).to.beTrue()
				end

				-- the array form {a, b, c, d, tx, ty} of the contract is read the same way
				recorded.polys = {}
				draw(state, {xf.a, xf.b, xf.c, xf.d, xf.tx, xf.ty})
				expect(#recorded.polys).to.equal(1)
				expect(near(recorded.polys[1].verts[1].x, (projected(xf, quad[1][1], quad[1][2])), 1e-9)).to.beTrue()
			end
		},
		{
			name = "Draw: a transform that mirrors (negative determinant) still gives clockwise polygons on the screen",
			func = function(state)
				state.existing["0,0"] = true
				state.existing["1,0"] = true
				draw(state, {a = -1, b = 0, c = 0, d = 1, tx = 500, ty = 0})

				expect(#recorded.polys).to.equal(2)

				for _, poly in ipairs(recorded.polys) do
					expect(signedArea(poly.verts) > 0).to.beTrue()
				end
			end
		},
		{
			name = "Draw: a tile clipped by the transformed frame with a shear still shows the same visible shape (the clip is done in radar space, then transformed)",
			func = function(state)
				local xf = {a = 1.7, b = 0.3, c = -0.2, d = 1.7, tx = 300, ty = 200}
				state.existing["1,0"] = true
				draw(state, xf)

				expect(#recorded.polys).to.equal(1)
				-- the same vertices as in the identity case, transformed
				local plain = recorded.polys[1].verts
				local inverse = {}

				-- invert the transform for each vertex, back to radar pixels, and check it lies on the frame's top y = -42 or inside it
				local det = xf.a * xf.d - xf.b * xf.c

				for i, vert in ipairs(plain) do
					local x, y = vert.x - xf.tx, vert.y - xf.ty
					local rx = (xf.d * x - xf.c * y) / det
					local ry = (-xf.b * x + xf.a * y) / det

					expect(ry >= -42 - 1e-9).to.beTrue()
					inverse[i] = {rx, ry}
				end
			end
		},

		-- coverage ----------------------------------------------------------------------------------------------------------------
		{
			name = "Draw: the coverage is 0 when no tile exists (and nothing is drawn)",
			func = function(state)
				local coverage = draw(state)

				expect(coverage).to.equal(0)
				expect(#recorded.polys).to.equal(0)
			end
		},
		{
			name = "Draw: the coverage is 1 when the tiles cover the range circle (a tile outside the circle does not count)",
			func = function(state)
				state.all = true
				local coverage = draw(state)

				expect(near(coverage, 1, 1e-9)).to.beTrue()
			end
		},
		{
			name = "Draw: the coverage is about a half when the tiles of the right half exist, about a quarter for one quadrant",
			func = function(state)
				-- the player on the corner of four tiles: (64, 64); the tiles with tx >= 1 are the half x >= 64
				state.existing = {["1,-1"] = true, ["1,0"] = true, ["1,1"] = true, ["1,2"] = true}
				local half = draw(state, IDENTITY, {px = 64, py = 64})
				expect(near(half, 0.5, 0.03)).to.beTrue()

				state.existing = {["1,1"] = true}
				local quarter = draw(state, IDENTITY, {px = 64, py = 64})
				expect(near(quarter, 0.25, 0.03)).to.beTrue()

				-- the coverage does not depend on the angle (the disk turns into itself)
				local turned = draw(state, IDENTITY, {px = 64, py = 64, yaw = 33})
				expect(near(turned, quarter, 1e-9)).to.beTrue()
			end
		},
		{
			name = "Draw: the coverage counts the tiles under the range circle even when they are outside the frame or the Cache has them but they are not drawn (alpha 0)",
			func = function(state)
				state.all = true
				local coverage = draw(state, IDENTITY, {alpha = 0})

				expect(near(coverage, 1, 1e-9)).to.beTrue()
				expect(#recorded.polys).to.equal(0)
			end
		},
		{
			name = "Draw: the coverage stays cheap: no more than 20 by 20 sample points (no Cache call per sample), so a bigger world does not change the number of Material calls beyond the tiles",
			func = function(state)
				state.all = true
				draw(state, IDENTITY, {range = 64})

				-- one Material call per tile of the range square or the frame, at most the 16 tiles of the visible square
				expect(#state.materialCalls <= 16).to.beTrue()
			end
		},

		-- absurd input and the Gen stand-in ---------------------------------------------------------------------------------------
		{
			name = "Draw: never raises and answers 0 for absurd input (nil, NaN, infinite, range 0 or negative, no level, bad xf, alpha NaN)",
			func = function(state)
				local V = GryMod.Minimap.View
				local nan, inf = 0 / 0, math.huge
				state.all = true
				V.LastError = nil

				local calls = {
					{nil, 0, 0, 0, 100, level(), 1}, {IDENTITY, nil, 0, 0, 100, level(), 1}, {IDENTITY, 0, nan, 0, 100, level(), 1},
					{IDENTITY, 0, 0, nan, 100, level(), 1}, {IDENTITY, 0, 0, 0, 0, level(), 1}, {IDENTITY, 0, 0, 0, -3, level(), 1},
					{IDENTITY, 0, 0, 0, nan, level(), 1}, {IDENTITY, 0, 0, 0, inf, level(), 1}, {IDENTITY, 0, 0, 0, 100, nil, 1},
					{IDENTITY, 0, 0, 0, 100, {zlo = 0, zhi = 1}, 1}, {IDENTITY, 0, 0, 0, 100, "a1", 1}, {{a = nan, b = 0, c = 0, d = 1, tx = 0, ty = 0}, 0, 0, 0, 100, level(), 1},
					{{}, 0, 0, 0, 100, level(), 1}, {"x", 0, 0, 0, 100, level(), 1}, {IDENTITY, 1e300, 0, 0, 100, level(), 1}, {IDENTITY, inf, 0, 0, 100, level(), 1},
					{IDENTITY, "a", 0, 0, 100, level(), 1}
				}

				for i = 1, #calls do
					local c = calls[i]
					local ok, coverage = pcall(V.Draw, c[1], c[2], c[3], c[4], c[5], c[6], c[7])

					expect(ok).to.beTrue()
					expect(coverage).to.equal(0)
				end

				-- a bad alpha is no reason to fail: the default of 1 applies (the tile is drawn) or nothing is drawn, but no error
				for _, alpha in ipairs({nan, "x", nil, -2, inf}) do
					local ok, coverage = pcall(V.Draw, IDENTITY, 32, 32, 0, 64, level(), alpha)
					expect(ok and type(coverage) == "number").to.beTrue()
				end

				-- the validation catches all of these: the safety net of the module was not needed
				expect(V.LastError).to.beNil()
			end
		},
		{
			name = "Draw: an error inside a dependency (Cache.Material raises) is swallowed and answers 0, nothing is drawn half way",
			func = function(state)
				local V = GryMod.Minimap.View
				GryMod.Minimap.Cache.Material = function() error("boom") end
				local ok, coverage = pcall(V.Draw, IDENTITY, 32, 32, 0, 64, level(), 1)

				expect(ok).to.beTrue()
				expect(coverage).to.equal(0)
				expect(type(V.LastError)).to.equal("string")
			end
		},
		{
			name = "Draw and VisibleTiles never touch Gen and never write the Cache (the stand-ins raise if they do)",
			func = function(state)
				local V = GryMod.Minimap.View
				state.all = true
				local list = V.VisibleTiles(level(), 0, 0, EXTENT, 512, 8)

				expect(#list > 0).to.beTrue()
				draw(state)
				draw(state, IDENTITY, {px = -500, py = 900, yaw = 200})

				-- a use of Gen or of Cache.Store would have raised inside Draw and been swallowed: the safety net's message says so
				expect(V.LastError).to.beNil()
				expect(#recorded.polys > 0).to.beTrue()
			end
		},
		-- the map frame: the radar frame without the danger bar's strip --------------------------------------------------------------
		{
			name = "MapFrame: with the original game's polygon as Radar.FRAME it is the convex polygon (-46.75,-42) (62,-42) (62,32.15) (46.25,45) (-46.75,45), clockwise, no vertex on the old notch",
			func = function()
				local V = GryMod.Minimap.View
				local map = V.MapFrame()
				local expected = {{-46.75, -42}, {62, -42}, {62, 32.15}, {46.25, 45}, {-46.75, 45}}

				-- this test is about the real frame: it is not one of a stand-in
				expect(GryMod.FlashRadar.FRAME[7][1]).to.equal(-46.75)
				expect(#map).to.equal(#expected)

				for i = 1, #expected do
					expect(near(map[i][1], expected[i][1], 1e-9) and near(map[i][2], expected[i][2], 1e-9)).to.beTrue()
				end

				expect(signedArea({{x = map[1][1], y = map[1][2]}, {x = map[2][1], y = map[2][2]}, {x = map[3][1], y = map[3][2]}, {x = map[4][1], y = map[4][2]}, {x = map[5][1], y = map[5][2]}}) > 0).to.beTrue()

				-- a copy: writing in it changes nothing for the next call
				map[1][1] = 1e9
				expect(V.MapFrame()[1][1]).to.equal(-46.75)
			end
		},
		{
			name = "MapFrame: computed from Radar.FRAME at run time: a simulated frame with its notch elsewhere gives the part right of ITS notch, and the real one comes back after",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				-- the same shape as the real frame, other numbers: the strip is x < -20, the notch's vertex is (-20, 5)
				Radar.FRAME = {{-30, 10}, {-30, -20}, {40, -20}, {40, 20}, {-20, 20}, {-20, 5}}

				local map = V.MapFrame()
				local expected = {{-20, -20}, {40, -20}, {40, 20}, {-20, 20}}

				expect(#map).to.equal(4)

				for i = 1, 4 do
					expect(near(map[i][1], expected[i][1], 1e-9) and near(map[i][2], expected[i][2], 1e-9)).to.beTrue()
				end

				-- a convex frame has no strip: it is returned whole (the same polygon, clockwise, from its lowest vertex)
				Radar.FRAME = {{0, 0}, {10, 0}, {10, 5}, {0, 5}}
				map = V.MapFrame()
				expect(#map).to.equal(4)
				expect(map[1][1] == 0 and map[1][2] == 0 and map[3][1] == 10 and map[3][2] == 5).to.beTrue()

				-- the other direction round gives the same polygon
				Radar.FRAME = {{0, 5}, {10, 5}, {10, 0}, {0, 0}}
				map = V.MapFrame()
				expect(#map).to.equal(4)
				expect(map[1][1] == 0 and map[1][2] == 0 and map[2][1] == 10 and map[2][2] == 0).to.beTrue()

				-- not a frame: an empty polygon, no error
				Radar.FRAME = {{0, 0}}
				expect(#V.MapFrame()).to.equal(0)

				Radar.FRAME = original.FRAME
				expect(#V.MapFrame()).to.equal(5)
			end
		},
		{
			name = "Draw: a tile that sticks out over the danger bar's strip draws nothing at x < -46.75 (one polygon, cut at the strip's edge)",
			func = function(state)
				-- tile (0, 1) with the player at (32, 32): radar x from -64.5 to -21.5, y from -21.5 to 21.5; the strip is x from -58 to -46.75
				state.existing["0,1"] = true
				draw(state)

				expect(#recorded.polys).to.equal(1)

				local limit = GryMod.Minimap.View.MapFrame()[1][1]

				expect(limit).to.equal(-46.75)

				for _, vert in ipairs(recorded.polys[1].verts) do
					expect(vert.x >= limit - 1e-9).to.beTrue()
				end

				-- the visible part: from -46.75 to -21.5 wide (25.25), 43 high
				expect(near(signedArea(recorded.polys[1].verts), 25.25 * 43, 1e-6)).to.beTrue()
			end
		},
		{
			name = "Draw: a tile that covers the whole frame gives one polygon whose area is the map frame's (nothing missing in the corners, nothing over)",
			func = function(state)
				-- a tile of 512 units (definition 1) around the player at its middle: 344 radar pixels wide, much more than the frame
				GryMod.Minimap.Settings.Definition = function() return 1 end
				state.existing["0,0"] = true
				draw(state, IDENTITY, {px = 256, py = 256})

				expect(#recorded.polys).to.equal(1)

				local map = GryMod.Minimap.View.MapFrame()
				local verts = recorded.polys[1].verts
				local expected = 0

				for i = 1, #map do
					local a, b = map[i], map[i % #map + 1]
					expected = expected + (a[1] * b[2] - b[1] * a[2]) / 2
				end

				expect(#verts).to.equal(#map)
				expect(near(signedArea(verts), expected, 1e-6)).to.beTrue()
				-- the window's corners are in: the farthest corner of the map frame is a vertex of the polygon
				local found = false

				for _, vert in ipairs(verts) do
					if near(vert.x, 62, 1e-6) and near(vert.y, 32.15, 1e-6) then
						found = true
					end
				end

				expect(found).to.beTrue()
			end
		},
		-- the floor below -----------------------------------------------------------------------------------------------------------
		{
			name = "Below: its tiles are drawn first (all of them before any tile of the main level), tinted (150,165,190) with belowAlpha, then the main level white with alpha",
			func = function(state)
				state.existing["0,0"], state.existing["0,-1"] = true, true
				state.belowExisting["0,0"], state.belowExisting["-1,0"], state.belowExisting["-1,-1"] = true, true, true
				draw(state, IDENTITY, {alpha = 0.6, below = lower(), belowAlpha = 0.4})

				local belowCount, mainCount, firstMain = groups()

				expect(belowCount).to.equal(3)
				expect(mainCount).to.equal(2)
				expect(firstMain).to.equal(4)

				for i, poly in ipairs(recorded.polys) do
					local c = poly.colour

					if i < firstMain then
						expect(poly.material.level).to.equal("z0")
						expect(c[1] == 150 and c[2] == 165 and c[3] == 190 and near(c[4], 0.4 * 255, 1)).to.beTrue()
					else
						expect(poly.material.level).to.equal("a1")
						expect(c[1] == 255 and c[2] == 255 and c[3] == 255 and near(c[4], 0.6 * 255, 1)).to.beTrue()
					end
				end

				-- one colour call a group, in that order
				expect(#recorded.colors).to.equal(2)
				expect(recorded.colors[1][1]).to.equal(150)
				expect(recorded.colors[2][1]).to.equal(255)
			end
		},
		{
			name = "Below: the tiles of the floor below are asked from the Cache with the level's id, the resolution and the definition",
			func = function(state)
				state.belowExisting["0,0"] = true
				draw(state, IDENTITY, {below = lower(), belowAlpha = 0.4})

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.level).to.equal("z0")
				expect(recorded.polys[1].material.res).to.equal(512)
				expect(recorded.polys[1].material.ppm).to.equal(8)
			end
		},
		{
			name = "Below: nothing is drawn or asked for the floor below when belowAlpha is 0, nil, negative or no number (and nothing changes for the main level)",
			func = function(state)
				state.existing["0,0"] = true
				state.belowAll = true

				for _, belowAlpha in ipairs({0, -1, 0 / 0, "x", false}) do
					recorded.polys, recorded.colors = {}, {}
					draw(state, IDENTITY, {below = lower(), belowAlpha = belowAlpha})

					expect(#recorded.polys).to.equal(1)
					expect(recorded.polys[1].material.level).to.equal("a1")
					expect(#recorded.colors).to.equal(1)
				end

				recorded.polys, recorded.colors = {}, {}
				draw(state, IDENTITY, {below = lower()})
				expect(#recorded.polys).to.equal(1)
				expect(#state.belowCalls).to.equal(0)
			end
		},
		{
			name = "Below: a belowAlpha above 1 is clamped to 255",
			func = function(state)
				state.belowExisting["0,0"] = true
				draw(state, IDENTITY, {below = lower(), belowAlpha = 5})

				expect(recorded.polys[1].colour[4]).to.equal(255)
			end
		},
		{
			name = "Below: the coverage counts the main level only, the same with or without a floor below",
			func = function(state)
				state.existing = {["1,-1"] = true, ["1,0"] = true, ["1,1"] = true, ["1,2"] = true}
				state.belowAll = true

				local without = draw(state, IDENTITY, {px = 64, py = 64})
				local with = draw(state, IDENTITY, {px = 64, py = 64, below = lower(), belowAlpha = 0.4})

				expect(near(without, 0.5, 0.03)).to.beTrue()
				expect(with).to.equal(without)

				-- no main tile at all: the coverage is 0 even when the floor below is everywhere (and it is drawn)
				state.existing = {}
				recorded.polys = {}
				expect(draw(state, IDENTITY, {below = lower(), belowAlpha = 0.4})).to.equal(0)
				expect(#recorded.polys > 0).to.beTrue()
			end
		},
		{
			name = "Below: a floor below with no tile in the cache draws nothing for itself, adds no colour call and no error",
			func = function(state)
				state.existing["0,0"] = true
				draw(state)

				local polys, colors, calls = #recorded.polys, #recorded.colors, #state.materialCalls
				recorded.polys, recorded.colors = {}, {}
				state.materialCalls = {}

				local ok = pcall(draw, state, IDENTITY, {below = lower(), belowAlpha = 0.4})

				expect(ok).to.beTrue()
				expect(#recorded.polys).to.equal(polys)
				expect(#recorded.colors).to.equal(colors)
				expect(#state.materialCalls).to.equal(calls)
				-- the main level costs what it cost: the floor below was asked about the tiles of the window only, never more than the main level was
				expect(#state.belowCalls >= 1 and #state.belowCalls <= 16).to.beTrue()
			end
		},
		{
			name = "Below: tiles outside the map frame are not asked for (the LRU of materials), the others are clipped by the same frame (nothing at x < -46.75)",
			func = function(state)
				state.all = true
				state.belowAll = true
				draw(state, IDENTITY, {below = lower(), belowAlpha = 0.4})

				local belowCount, mainCount = groups()

				expect(belowCount > 0).to.beTrue()
				-- the same tiles, the same polygons
				expect(belowCount).to.equal(mainCount)

				for _, call in ipairs(state.belowCalls) do
					-- the tiles at two tiles from the player lie above or below the window (their radar y is out of -42..45)
					expect(call ~= "2,0" and call ~= "-2,0").to.beTrue()
				end

				local limit = GryMod.Minimap.View.MapFrame()[1][1]

				for _, poly in ipairs(recorded.polys) do
					for _, vert in ipairs(poly.verts) do
						expect(vert.x >= limit - 1e-9).to.beTrue()
					end
				end
			end
		},
		{
			name = "Below: the floor below's polygons are the main level's for the same tile: the same vertices and u, v",
			func = function(state)
				state.existing["0,1"] = true
				state.belowExisting["0,1"] = true
				draw(state, IDENTITY, {below = lower(), belowAlpha = 0.4})

				expect(#recorded.polys).to.equal(2)

				local a, b = recorded.polys[1].verts, recorded.polys[2].verts

				expect(#a).to.equal(#b)

				for i = 1, #a do
					expect(a[i].x == b[i].x and a[i].y == b[i].y and a[i].u == b[i].u and a[i].v == b[i].v).to.beTrue()
				end
			end
		},
		{
			name = "Below: a floor below with the SAME id as the main level is not drawn (it would be the same tiles twice): the main level is drawn once",
			func = function(state)
				state.existing["0,0"] = true
				state.belowAll = true
				draw(state, IDENTITY, {below = level(), belowAlpha = 0.4})

				expect(#recorded.polys).to.equal(1)
				expect(#recorded.colors).to.equal(1)
				expect(#state.belowCalls).to.equal(0)
			end
		},
		{
			name = "Below: with the main level's alpha at 0 the floor below is still drawn (the main level is not); bad below tables are ignored without error",
			func = function(state)
				state.existing["0,0"] = true
				state.belowExisting["0,0"] = true
				draw(state, IDENTITY, {alpha = 0, below = lower(), belowAlpha = 0.4})

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.level).to.equal("z0")

				for _, bad in ipairs({"z0", {zlo = 0, zhi = 1}, {id = 5}, 7, true}) do
					recorded.polys = {}
					local ok = pcall(draw, state, IDENTITY, {below = bad, belowAlpha = 0.4})

					expect(ok).to.beTrue()
					expect(#recorded.polys).to.equal(1)
					expect(recorded.polys[1].material.level).to.equal("a1")
				end

				expect(GryMod.Minimap.View.LastError).to.beNil()
			end
		},
		{
			name = "Below: an error in the Cache while the floor below is drawn is swallowed (Draw answers 0, LastError says why)",
			func = function(state)
				state.existing["0,0"] = true
				local material = GryMod.Minimap.Cache.Material

				GryMod.Minimap.Cache.Material = function(tile)
					if tile.level == "z0" then error("boom") end

					return material(tile)
				end

				local ok, coverage = pcall(draw, state, IDENTITY, {below = lower(), belowAlpha = 0.4})

				expect(ok).to.beTrue()
				expect(coverage).to.equal(0)
				expect(type(GryMod.Minimap.View.LastError)).to.equal("string")
			end
		},
		-- the outside ---------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: the outside is drawn after the floor below or the main level, or with another tint than (110,125,140), or with the alpha of the main level
			name = "Outside: its tiles are drawn first (all of them before any tile of the floor below, and of the main level), tinted (110,125,140) with outsideAlpha",
			func = function(state)
				state.existing["0,0"], state.existing["0,-1"] = true, true
				state.belowExisting["0,0"], state.belowExisting["-1,0"] = true, true
				state.outsideExisting["0,0"], state.outsideExisting["-1,0"], state.outsideExisting["-1,-1"], state.outsideExisting["0,-1"] = true, true, true, true
				draw(state, IDENTITY, {alpha = 0.6, below = lower(), belowAlpha = 0.4, outside = open(), outsideAlpha = 0.25})

				local levels = {}

				for i, poly in ipairs(recorded.polys) do
					levels[i] = poly.material.level
				end

				expect(table.concat(levels, " ")).to.equal("open open open open z0 z0 a1 a1")

				for i, poly in ipairs(recorded.polys) do
					local c = poly.colour

					if i <= 4 then
						expect(c[1] == 110 and c[2] == 125 and c[3] == 140 and near(c[4], 0.25 * 255, 1)).to.beTrue()
					elseif i <= 6 then
						expect(c[1] == 150 and c[2] == 165 and c[3] == 190 and near(c[4], 0.4 * 255, 1)).to.beTrue()
					else
						expect(c[1] == 255 and c[2] == 255 and c[3] == 255 and near(c[4], 0.6 * 255, 1)).to.beTrue()
					end
				end

				-- one colour call a group, in that order
				expect(#recorded.colors).to.equal(3)
				expect(recorded.colors[1][1]).to.equal(110)
				expect(recorded.colors[2][1]).to.equal(150)
				expect(recorded.colors[3][1]).to.equal(255)
			end
		},
		{
			-- breaks if: the outside needs a floor below to be drawn
			name = "Outside: without a floor below the outside is drawn right under the main level",
			func = function(state)
				state.existing["0,0"] = true
				state.outsideExisting["0,0"], state.outsideExisting["0,-1"] = true, true
				draw(state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				expect(#recorded.polys).to.equal(3)
				expect(recorded.polys[1].material.level).to.equal("open")
				expect(recorded.polys[2].material.level).to.equal("open")
				expect(recorded.polys[3].material.level).to.equal("a1")
				expect(#state.belowCalls).to.equal(0)
			end
		},
		{
			-- breaks if: the Cache is asked for the outside with another id, resolution or definition
			name = "Outside: the tiles of the outside are asked from the Cache with the level's id, the resolution and the definition",
			func = function(state)
				state.outsideExisting["0,0"] = true
				draw(state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.level).to.equal("open")
				expect(recorded.polys[1].material.res).to.equal(512)
				expect(recorded.polys[1].material.ppm).to.equal(8)
			end
		},
		{
			-- breaks if: an alpha that is 0, negative, nil or no number still draws or asks for the outside
			name = "Outside: nothing is drawn or asked for the outside when outsideAlpha is 0, nil, negative or no number (and nothing changes for the main level)",
			func = function(state)
				state.existing["0,0"] = true
				state.outsideAll = true

				for _, outsideAlpha in ipairs({0, -1, 0 / 0, "x", false}) do
					recorded.polys, recorded.colors = {}, {}
					draw(state, IDENTITY, {outside = open(), outsideAlpha = outsideAlpha})

					expect(#recorded.polys).to.equal(1)
					expect(recorded.polys[1].material.level).to.equal("a1")
					expect(#recorded.colors).to.equal(1)
				end

				recorded.polys, recorded.colors = {}, {}
				draw(state, IDENTITY, {outside = open()})
				expect(#recorded.polys).to.equal(1)
				expect(#state.outsideCalls).to.equal(0)
			end
		},
		{
			-- breaks if: outsideAlpha above 1 is not clamped
			name = "Outside: an outsideAlpha above 1 is clamped to 255",
			func = function(state)
				state.outsideExisting["0,0"] = true
				draw(state, IDENTITY, {outside = open(), outsideAlpha = 5})

				expect(recorded.polys[1].colour[4]).to.equal(255)
			end
		},
		{
			-- breaks if: the coverage counts the tiles of the outside
			name = "Outside: the coverage counts the main level only, the same with or without an outside",
			func = function(state)
				state.existing = {["1,-1"] = true, ["1,0"] = true, ["1,1"] = true, ["1,2"] = true}
				state.outsideAll = true
				state.belowAll = true

				local without = draw(state, IDENTITY, {px = 64, py = 64})
				local with = draw(state, IDENTITY, {px = 64, py = 64, below = lower(), belowAlpha = 0.4, outside = open(), outsideAlpha = 0.3})

				expect(near(without, 0.5, 0.03)).to.beTrue()
				expect(with).to.equal(without)

				-- no main tile at all: the coverage is 0 even when the outside is everywhere (and it is drawn)
				state.existing = {}
				recorded.polys = {}
				expect(draw(state, IDENTITY, {outside = open(), outsideAlpha = 0.3})).to.equal(0)
				expect(#recorded.polys > 0).to.beTrue()
			end
		},
		{
			-- breaks if: a missing tile of the outside sends a polygon, a colour call, or an error
			name = "Outside: an outside with no tile in the cache (or only empty ones: the Cache gives no material) draws nothing for itself, adds no colour call and no error",
			func = function(state)
				state.existing["0,0"] = true
				draw(state)

				local polys, colors = #recorded.polys, #recorded.colors
				recorded.polys, recorded.colors = {}, {}

				local ok = pcall(draw, state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				expect(ok).to.beTrue()
				expect(#recorded.polys).to.equal(polys)
				expect(#recorded.colors).to.equal(colors)
				expect(#state.outsideCalls >= 1 and #state.outsideCalls <= 16).to.beTrue()
			end
		},
		{
			-- breaks if: the tiles of the outside are asked for when no polygon of them would be sent
			name = "Outside: tiles outside the map frame are not asked for, the others are clipped by the same frame (nothing at x < -46.75)",
			func = function(state)
				state.all = true
				state.outsideAll = true
				draw(state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				local mainCount, outsideCount = 0, 0

				for _, poly in ipairs(recorded.polys) do
					if poly.material.level == "open" then outsideCount = outsideCount + 1 else mainCount = mainCount + 1 end
				end

				expect(outsideCount > 0).to.beTrue()
				expect(outsideCount).to.equal(mainCount)

				for _, call in ipairs(state.outsideCalls) do
					expect(call ~= "2,0" and call ~= "-2,0").to.beTrue()
				end

				local limit = GryMod.Minimap.View.MapFrame()[1][1]

				for _, poly in ipairs(recorded.polys) do
					for _, vert in ipairs(poly.verts) do
						expect(vert.x >= limit - 1e-9).to.beTrue()
					end
				end
			end
		},
		{
			-- breaks if: the outside is drawn with other vertices than the main level's for the same tile
			name = "Outside: the outside's polygons are the main level's for the same tile: the same vertices and u, v",
			func = function(state)
				state.existing["0,1"] = true
				state.outsideExisting["0,1"] = true
				draw(state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				expect(#recorded.polys).to.equal(2)

				local a, b = recorded.polys[1].verts, recorded.polys[2].verts

				expect(#a).to.equal(#b)

				for i = 1, #a do
					expect(a[i].x == b[i].x and a[i].y == b[i].y and a[i].u == b[i].u and a[i].v == b[i].v).to.beTrue()
				end
			end
		},
		{
			-- breaks if: an outside of the same id as the main level or the floor below is drawn (the same tiles twice)
			name = "Outside: an outside with the SAME id as the main level or as the floor below is not drawn",
			func = function(state)
				state.existing["0,0"] = true
				state.outsideAll = true
				state.belowExisting["0,0"] = true

				draw(state, IDENTITY, {outside = level(), outsideAlpha = 0.3})
				expect(#recorded.polys).to.equal(1)
				expect(#recorded.colors).to.equal(1)

				recorded.polys, recorded.colors = {}, {}
				draw(state, IDENTITY, {below = lower(), belowAlpha = 0.4, outside = lower(), outsideAlpha = 0.3})
				expect(#recorded.polys).to.equal(2)
				expect(#recorded.colors).to.equal(2)
				expect(#state.outsideCalls).to.equal(0)
			end
		},
		{
			-- breaks if: the outside depends on the main level's alpha, or a bad outside table raises
			name = "Outside: with the main level's alpha at 0 the outside is still drawn; bad outside tables are ignored without error",
			func = function(state)
				state.existing["0,0"] = true
				state.outsideExisting["0,0"] = true
				draw(state, IDENTITY, {alpha = 0, outside = open(), outsideAlpha = 0.3})

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.level).to.equal("open")

				for _, bad in ipairs({"open", {zlo = 0, zhi = 1}, {id = 5}, 7, true}) do
					recorded.polys = {}
					local ok = pcall(draw, state, IDENTITY, {outside = bad, outsideAlpha = 0.3})

					expect(ok).to.beTrue()
					expect(#recorded.polys).to.equal(1)
					expect(recorded.polys[1].material.level).to.equal("a1")
				end

				expect(GryMod.Minimap.View.LastError).to.beNil()
			end
		},
		{
			-- breaks if: an error of the Cache while the outside is drawn escapes Draw
			name = "Outside: an error in the Cache while the outside is drawn is swallowed (Draw answers 0, LastError says why)",
			func = function(state)
				state.existing["0,0"] = true
				local material = GryMod.Minimap.Cache.Material

				GryMod.Minimap.Cache.Material = function(tile)
					if tile.level == "open" then error("boom") end

					return material(tile)
				end

				local ok, coverage = pcall(draw, state, IDENTITY, {outside = open(), outsideAlpha = 0.3})

				expect(ok).to.beTrue()
				expect(coverage).to.equal(0)
				expect(type(GryMod.Minimap.View.LastError)).to.equal("string")
			end
		},
		{
			-- breaks if: the budget is not shared in the order main, below, outside
			name = "Outside: the materials budget is shared main level, floor below, outside: the outside only gets what the other two left",
			func = function(state)
				local V = GryMod.Minimap.View
				GryMod.Minimap.Settings.Definition = function() return 40 end
				state.all = true
				state.belowAll = true
				state.outsideAll = true

				V.MAX_MATERIALS = 100000
				draw(state, IDENTITY, {px = 40, py = 40})

				local count = #state.materialCalls

				expect(count >= 130).to.beTrue()

				-- the main level and the floor below take the whole budget: the outside asks for nothing
				V.MAX_MATERIALS = 2 * count
				state.materialCalls, state.belowCalls, state.outsideCalls = {}, {}, {}
				draw(state, IDENTITY, {px = 40, py = 40, below = lower(), belowAlpha = 0.4, outside = open(), outsideAlpha = 0.3})
				expect(#state.materialCalls).to.equal(count)
				expect(#state.belowCalls).to.equal(count)
				expect(#state.outsideCalls).to.equal(0)

				-- with room left it asks for exactly 5
				V.MAX_MATERIALS = 2 * count + 5
				state.materialCalls, state.belowCalls, state.outsideCalls = {}, {}, {}
				draw(state, IDENTITY, {px = 40, py = 40, below = lower(), belowAlpha = 0.4, outside = open(), outsideAlpha = 0.3})
				expect(#state.outsideCalls).to.equal(5)

				-- the floor below is off: the outside gets what the main level left
				V.MAX_MATERIALS = count + 3
				state.materialCalls, state.outsideCalls = {}, {}
				draw(state, IDENTITY, {px = 40, py = 40, outside = open(), outsideAlpha = 0.3})
				expect(#state.materialCalls).to.equal(count)
				expect(#state.outsideCalls).to.equal(3)
			end
		},
		-- the extent of the tiles asked for -------------------------------------------------------------------------------------------
		{
			name = "ExtentFactor: the farthest vertex of the map frame from the player in ranges, rounded UP to the hundredth (original polygon: 1.75; the real glass: its own value)",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar
				local P = pixels()

				local function expectedFactor()
					local reach = 0

					for _, p in ipairs(V.MapFrame()) do
						reach = math.max(reach, math.sqrt(p[1] * p[1] + p[2] * p[2]))
					end

					return reach, math.ceil(reach / P * 100 - 1e-9) / 100
				end

				-- the original polygon: the farthest vertex is (62, -42), 74.9 pixels, 1.742 ranges
				local reach, factor = expectedFactor()
				expect(factor).to.equal(1.75)
				expect(V.ExtentFactor()).to.equal(1.75)
				expect(V.ExtentFactor() * P >= reach).to.beTrue()

				-- the real glass of the movie (the frame the tests found before their montage)
				Radar.FRAME = original.FRAME
				reach, factor = expectedFactor()
				expect(V.ExtentFactor()).to.equal(factor)
				expect(V.ExtentFactor() * P >= reach - 1e-9).to.beTrue()
				expect(V.ExtentFactor() * P < reach + 0.01 * P + 1e-9).to.beTrue()
				expect(V.ExtentFactor() >= 1 and V.ExtentFactor() <= Radar.MAP_EXTENT + 1e-9).to.beTrue()
			end
		},
		{
			name = "ExtentFactor: a simulated frame gives its own number (reach 44.72 pixels = 1.04 ranges, rounded up to 1.05); a frame of exactly 2 ranges gives 2, not 2.01",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				Radar.FRAME = {{-30, 10}, {-30, -20}, {40, -20}, {40, 20}, {-20, 20}, {-20, 5}}
				expect(V.ExtentFactor()).to.equal(1.05)

				-- a square whose farthest corner is exactly 2 * PIXELS away: (0.6, 0.8) * 2 * PIXELS
				local P = pixels()
				Radar.FRAME = {{0, 0}, {1.2 * P, 0}, {1.2 * P, 1.6 * P}, {0, 1.6 * P}}
				expect(V.ExtentFactor()).to.equal(2)
			end
		},
		{
			name = "ExtentFactor: with no usable frame it is the fallback, 2",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				for _, frame in ipairs({false, "x", {}, {{0, 0}}, {{0, 0}, {1, 1}}, {{0, 0}, {1, 0}, {0 / 0, 1}}, {{0, 0}, {1, 0}, "p"}}) do
					Radar.FRAME = frame or nil
					expect(V.ExtentFactor()).to.equal(2)
				end
			end
		},
		{
			name = "Draw: the tiles asked for reach the frame's farthest corner: a big frame draws a tile 160 units away that the old 1.75 ranges would not reach",
			func = function(state)
				local Radar = GryMod.FlashRadar

				Radar.FRAME = {{-150, -150}, {150, -150}, {150, 150}, {-150, 150}}
				-- tile (3, 0): world x from 192 to 256, 160 to 224 units ahead of the player, 107 to 150 radar pixels up: inside this frame, past 1.75 * 64 = 112 units
				state.existing["3,0"] = true
				draw(state)

				expect(#recorded.polys).to.equal(1)
				expect(recorded.polys[1].material.token).to.equal("3,0")
			end
		},
		{
			name = "Draw: the vertex tables are reused but every polygon reaches DrawPoly with exactly its own vertices (a clipped tile of 5 or more, then a whole one of 4)",
			func = function(state)
				state.all = true

				-- the player at the right corner of the window: some tiles are cut at the chamfered corner (5 vertices or more), some are whole
				local sizes = {}

				for _, position in ipairs({{32, 32}, {-20, 80}, {70, 10}, {32, 32}}) do
					recorded.polys = {}
					draw(state, IDENTITY, {px = position[1], py = position[2]})

					for _, poly in ipairs(recorded.polys) do
						local verts = poly.verts

						expect(#verts >= 3).to.beTrue()
						sizes[#verts] = true

						-- no vertex is repeated (a stale tail or a shared table would show here), and the polygon is a proper clockwise one
						for i = 1, #verts do
							for j = i + 1, #verts do
								expect(verts[i].x ~= verts[j].x or verts[i].y ~= verts[j].y).to.beTrue()
							end
						end

						expect(signedArea(verts) > 0).to.beTrue()
					end
				end

				expect(sizes[4]).to.beTrue()
				expect(sizes[5] or sizes[6] or sizes[7]).to.beTrue()
			end
		},
		-- Radar.MAP_LEFT: where the map starts on the left ----------------------------------------------------------------------------
		{
			name = "MapFrame: with Radar.MAP_LEFT = -70 on the real glass the polygon starts at x = -70 (and keeps the notch, which is right of it)",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				Radar.FRAME = original.FRAME
				Radar.MAP_LEFT = nil
				local before = V.MapFrame()
				Radar.MAP_LEFT = -70

				local map = V.MapFrame()
				local minX = math.huge
				local onCut = 0
				local notch = false

				for _, p in ipairs(map) do
					minX = math.min(minX, p[1])

					if near(p[1], -70, 1e-9) then
						onCut = onCut + 1
					end

					if near(p[1], -51.23, 1e-9) and near(p[2], 28.37, 1e-9) then
						notch = true
					end
				end

				expect(near(minX, -70, 1e-9)).to.beTrue()
				expect(onCut).to.equal(2)
				expect(notch).to.beTrue()
				-- a wider polygon than the one cut at the notch (the cache took the new bound into account: it was built before)
				expect(#map > #before).to.beTrue()
			end
		},
		{
			name = "MapFrame: Radar.MAP_LEFT absent, NaN, no number, past the right edge or outside the frame gives the rule of the notch (x of the first reflex vertex)",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				Radar.FRAME = original.FRAME
				Radar.MAP_LEFT = nil
				local default = V.MapFrame()

				expect(#default > 0).to.beTrue()
				expect(near(default[1][1], -51.23, 1e-9) or near(default[#default][1], -51.23, 1e-9) or near(default[2][1], -51.23, 1e-9)).to.beTrue()

				-- the frame spans x from -77.38 to 70.8: the bounds themselves and everything beyond are not inside it
				for _, bad in ipairs({0 / 0, "x", true, 1e9, -1e9, math.huge, -math.huge, -77.38, 70.8, 100, -100}) do
					Radar.MAP_LEFT = bad

					local map = V.MapFrame()

					expect(#map).to.equal(#default)

					for i = 1, #map do
						expect(map[i][1] == default[i][1] and map[i][2] == default[i][2]).to.beTrue()
					end
				end
			end
		},
		{
			name = "MapFrame: a change of Radar.MAP_LEFT is picked up at the next call (the cache is keyed on it), and so is its removal",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				Radar.FRAME = original.FRAME
				Radar.MAP_LEFT = -70
				expect(near(V.MapFrame()[1][1], -70, 1e-9) or near(V.MapFrame()[#V.MapFrame()][1], -70, 1e-9) or true).to.beTrue()

				local function leftmost()
					local minX = math.huge

					for _, p in ipairs(V.MapFrame()) do
						minX = math.min(minX, p[1])
					end

					return minX
				end

				expect(near(leftmost(), -70, 1e-9)).to.beTrue()
				Radar.MAP_LEFT = -60
				expect(near(leftmost(), -60, 1e-9)).to.beTrue()
				Radar.MAP_LEFT = nil
				expect(near(leftmost(), -51.23, 1e-9)).to.beTrue()
			end
		},
		{
			name = "ExtentFactor: recomputed with the polygon MAP_LEFT gives (a frame whose farthest vertex is in the strip: 0.33 ranges without it, 2.11 with it)",
			func = function()
				local V = GryMod.Minimap.View
				local Radar = GryMod.FlashRadar

				-- the shape of the real frame, a long left part: the strip is x < -5, the notch vertex is (-5, 3)
				Radar.FRAME = {{-100, 0}, {-100, -10}, {10, -10}, {10, 10}, {-5, 10}, {-5, 3}}
				Radar.MAP_LEFT = nil
				expect(V.ExtentFactor()).to.equal(0.33)

				-- cut at -90: the farthest vertex is (-90, -10), 90.55 pixels = 2.106 ranges
				Radar.MAP_LEFT = -90
				expect(V.ExtentFactor()).to.equal(2.11)
			end
		},
		{
			name = "Draw: a tile that straddles the left cut is clipped against the polygon MAP_LEFT gives (nothing at x < MAP_LEFT, area of the part inside)",
			func = function(state)
				-- the original polygon, the map starting at -30 (the notch at -46.75 is then outside the map): tile (0, 1) is x from -64.5 to -21.5, y from -21.5 to 21.5
				GryMod.FlashRadar.MAP_LEFT = -30
				state.existing["0,1"] = true
				draw(state)

				expect(#recorded.polys).to.equal(1)

				for _, vert in ipairs(recorded.polys[1].verts) do
					expect(vert.x >= -30 - 1e-9).to.beTrue()
				end

				expect(near(signedArea(recorded.polys[1].verts), 8.5 * 43, 1e-6)).to.beTrue()
			end
		},
		{
			name = "Draw: with a MAP_LEFT that keeps the notch (the polygon is not convex) the polygons of a tile over the notch still add up to the tile's area inside the map frame",
			func = function(state)
				GryMod.FlashRadar.MAP_LEFT = -52

				for _, c in ipairs({{32, 32, 0, 1}, {32, 32, 0, 2}, {32, 32, 1, 2}, {-20, 80, 1, 2}}) do
					state.existing = {}
					state.existing[c[3] .. "," .. c[4]] = true
					recorded.polys = {}
					draw(state, IDENTITY, {px = c[1], py = c[2]})

					local expected = sampledIntersection(handQuad(c[3], c[4], c[1], c[2]), 0.4)
					local total = 0

					for _, poly in ipairs(recorded.polys) do
						expect(signedArea(poly.verts) > 0).to.beTrue()
						total = total + signedArea(poly.verts)
					end

					if math.abs(total - expected) > 0.01 * expected + 2.5 then
						error("tile " .. c[3] .. "," .. c[4] .. " with the player at " .. c[1] .. "," .. c[2] .. ": polygons cover " .. total .. ", the map frame holds " .. expected, 0)
					end
				end
			end
		},

		-- what is asked of the cache -----------------------------------------------------------------------------------------------------
		{
			name = "Cache: Material is only asked for a tile of which a polygon is really sent: not with an alpha of 0, not for a tile whose box touches the frame's but whose quad does not",
			func = function(state)
				state.all = true
				draw(state, IDENTITY, {alpha = 0})
				expect(#state.materialCalls).to.equal(0)
				expect(#recorded.polys).to.equal(0)

				-- a quad turned 45 degrees: the tiles in the corners of the frame's box have a box that touches it and a quad that does not
				state.materialCalls, recorded.polys = {}, {}
				draw(state, IDENTITY, {yaw = 45})

				local asked = #state.materialCalls
				expect(asked == #recorded.polys).to.beTrue()
				expect(asked > 0).to.beTrue()
			end
		},
		{
			name = "Cache: the coverage uses Cache.Has, not Material (a tile under the range circle that is not drawn costs a Has, never a material)",
			func = function(state)
				state.all = true
				draw(state, IDENTITY, {alpha = 0})

				expect(#state.materialCalls).to.equal(0)
				expect(#state.hasCalls > 0).to.beTrue()
				-- only the tiles under the circle, once each
				expect(#state.hasCalls <= 9).to.beTrue()

				-- a tile that was asked for is not asked about again with Has
				state.hasCalls, state.materialCalls = {}, {}
				state.existing["0,0"] = true
				state.all = false
				draw(state, IDENTITY, {})

				for _, call in ipairs(state.hasCalls) do
					expect(call ~= "0,0").to.beTrue()
				end
			end
		},
		{
			name = "Cache: no more than View.MAX_MATERIALS (96) distinct materials asked in one Draw, the nearest tiles first; the floor below only gets what the main level left",
			func = function(state)
				local V = GryMod.Minimap.View
				-- 12.8 units a tile: some 130 and more tiles on the window
				GryMod.Minimap.Settings.Definition = function() return 40 end
				state.all = true
				state.belowAll = true
				expect(V.MAX_MATERIALS).to.equal(96)

				V.MAX_MATERIALS = 100000
				draw(state, IDENTITY, {px = 40, py = 40})

				local everything = {}

				for _, call in ipairs(state.materialCalls) do
					everything[#everything + 1] = call
				end

				expect(#everything >= 130).to.beTrue()

				V.MAX_MATERIALS = original.MAX_MATERIALS
				state.materialCalls, recorded.polys = {}, {}
				draw(state, IDENTITY, {px = 40, py = 40})

				expect(#state.materialCalls).to.equal(96)
				expect(#recorded.polys).to.equal(96)

				-- the tile under the player is among them, and no tile that was left out is nearer (by ring) than one that was asked
				local T = 512 / 40
				local ptx, pty = math.floor(40 / T), math.floor(40 / T)
				local asked = {}
				local worstAsked = -1
				local bestLeft = math.huge

				local function ring(call)
					local tx, ty = string.match(call, "^(-?%d+),(-?%d+)$")

					return math.max(math.abs(tonumber(tx) - ptx), math.abs(tonumber(ty) - pty))
				end

				for _, call in ipairs(state.materialCalls) do
					asked[call] = true
					worstAsked = math.max(worstAsked, ring(call))
				end

				for _, call in ipairs(everything) do
					if not asked[call] then
						bestLeft = math.min(bestLeft, ring(call))
					end
				end

				expect(asked[ptx .. "," .. pty]).to.beTrue()
				expect(worstAsked <= bestLeft).to.beTrue()

				-- the floor below: the main level took the whole budget, so it asks for nothing
				state.materialCalls, state.belowCalls = {}, {}
				draw(state, IDENTITY, {px = 40, py = 40, below = lower(), belowAlpha = 0.4})
				expect(#state.materialCalls).to.equal(96)
				expect(#state.belowCalls).to.equal(0)

				-- with room left (the main level's count + 5) it asks for exactly 5
				V.MAX_MATERIALS = #everything + 5
				state.materialCalls, state.belowCalls = {}, {}
				draw(state, IDENTITY, {px = 40, py = 40, below = lower(), belowAlpha = 0.4})
				expect(#state.materialCalls).to.equal(#everything)
				expect(#state.belowCalls).to.equal(5)
			end
		},
		{
			name = "Radar.FRAME is cut into convex pieces that cover it exactly (ConvexPieces)",
			func = function()
				local V = GryMod.Minimap.View
				local frame = GryMod.FlashRadar.FRAME

				expect(type(V.ConvexPieces)).to.equal("function")

				local pieces = V.ConvexPieces(frame)
				local total = 0

				for _, piece in ipairs(pieces) do
					local n = #piece
					expect(n >= 3).to.beTrue()

					local area = 0

					for i = 1, n do
						local a, b, c = piece[i], piece[i % n + 1], piece[(i + 1) % n + 1]
						-- convex: every turn goes the same way
						expect((b[1] - a[1]) * (c[2] - b[2]) - (b[2] - a[2]) * (c[1] - b[1]) >= -1e-9).to.beTrue()
						area = area + (a[1] * b[2] - b[1] * a[2]) / 2
					end

					expect(area > 0).to.beTrue()
					total = total + area
				end

				local whole = 0

				for i = 1, #frame do
					local a, b = frame[i], frame[i % #frame + 1]
					whole = whole + (a[1] * b[2] - b[1] * a[2]) / 2
				end

				expect(near(total, math.abs(whole), 1e-6)).to.beTrue()
				expect(#pieces).to.equal(2)
			end
		},
		{
			name = "ConvexPieces: an L shape (one reflex corner) gives two convex pieces that cover it; a convex polygon gives itself",
			func = function()
				local V = GryMod.Minimap.View
				local pieces = V.ConvexPieces({{0, 0}, {10, 0}, {10, 4}, {4, 4}, {4, 10}, {0, 10}})

				expect(#pieces).to.equal(2)

				local total = 0

				for _, piece in ipairs(pieces) do
					local n = #piece

					for i = 1, n do
						local a, b = piece[i], piece[i % n + 1]
						total = total + (a[1] * b[2] - b[1] * a[2]) / 2
					end
				end

				expect(near(total, 10 * 4 + 4 * 6, 1e-9)).to.beTrue()

				local square = V.ConvexPieces({{0, 0}, {1, 0}, {1, 1}, {0, 1}})
				expect(#square).to.equal(1)
				expect(#square[1]).to.equal(4)

				-- the other orientation is the same polygon
				local reversed = V.ConvexPieces({{0, 1}, {1, 1}, {1, 0}, {0, 0}})
				expect(#reversed).to.equal(1)
			end
		}
	}
}
