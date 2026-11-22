-- Tests of the window the radar shows (GryMod.FlashRadar.FRAME), GLuaTest format, client realm. The contacts disappear at the edge of this polygon and the minimap is
-- clipped against it (View.MapFrame), so it has to be the glass the movie really draws (its NoiseMask outline, the clip that masks the units), in radar pixels,
-- converted with the same numbers as the contacts. The original game's polygon (Radar.ORIGINAL_FRAME) is smaller than its own glass: a contact vanished
-- while still over the map and the map stopped short of the glass.

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

-- the outline of the glass in radar pixels, from the movie's data: the shape of the NoiseMask clip, the matrix of that clip in Root, then the point of the Units clip
-- the radar pixels are converted to (its centre, 110 / 94 movie pixels for a radar pixel) and the matrix of Units
local function glassOutline()
	local R = GryMod.FlashRadar
	local movie = GryMod.Flash.Load("hud_radarcompassstealth")
	local panel = R.New(movie)
	local outline = movie.chars[84].p
	local mask = panel.main.names.NoiseMask.m
	local units = panel.main:Child("Units").entry.m
	local poly = {}

	for i = 1, #outline, 2 do
		local x = outline[i] * mask[1] + outline[i + 1] * mask[3] + mask[5]
		local y = outline[i] * mask[2] + outline[i + 1] * mask[4] + mask[6]
		poly[#poly + 1] = {(x - units[5] - R.UNITS_CENTRE_X) / R.UNITS_PIXEL, (y - units[6] - R.UNITS_CENTRE_Y) / R.UNITS_PIXEL}
	end

	return poly
end

local function inside(poly, x, y)
	local result = false
	local j = #poly

	for i = 1, #poly do
		local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]

		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
			result = not result
		end

		j = i
	end

	return result
end

local function bounds(poly)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge

	for _, p in ipairs(poly) do
		x0, x1 = math.min(x0, p[1]), math.max(x1, p[1])
		y0, y1 = math.min(y0, p[2]), math.max(y1, p[2])
	end

	return x0, y0, x1, y1
end

-- the area of `a` that is not in `b`, in square radar pixels, by sampling every half pixel
local function outside(a, b)
	local x0, y0, x1, y1 = bounds(a)
	local count = 0

	for x = x0, x1, 0.5 do
		for y = y0, y1, 0.5 do
			if inside(a, x, y) and not inside(b, x, y) then
				count = count + 1
			end
		end
	end

	return count * 0.25
end

local function area(poly)
	local x0, y0, x1, y1 = bounds(poly)
	local count = 0

	for x = x0, x1, 0.5 do
		for y = y0, y1, 0.5 do
			if inside(poly, x, y) then
				count = count + 1
			end
		end
	end

	return count * 0.25
end

-- how far from the player, in radar pixels, a contact in the direction (ux, uy) of the radar (x right, y down) is still drawn: the real Radar.Contacts
local function threshold(ux, uy, range)
	local R, S = GryMod.FlashRadar, GryMod.RadarShared
	local pixels = S.METRES_PER_UNIT * S.PIXELS / range
	local low, high = 0, 300

	for _ = 1, 40 do
		local d = (low + high) / 2
		-- yaw 0: a radar point (x, y) is the world offset (dx, dy) = (-y, -x) / pixels
		local contact = {id = 1, x = -uy * d / pixels, y = -ux * d / pixels, z = 0, yaw = 0, type = 1, sub = 2, marker = false, big = false}
		local list = R.Contacts({x = 0, y = 0, z = 0}, 0, {contact}, 0, range)

		if #list > 0 then
			low = d
		else
			high = d
		end
	end

	return low
end

-- where a ray from the player in the direction (ux, uy) leaves a polygon
local function leaves(poly, ux, uy)
	local low, high = 0, 300

	for _ = 1, 40 do
		local d = (low + high) / 2

		if inside(poly, ux * d, uy * d) then
			low = d
		else
			high = d
		end
	end

	return low
end

return {
	groupName = "GryMod radar window (FRAME)",
	cases = {
		{
			name = "FRAME is the glass of the movie: it differs from the NoiseMask outline in radar pixels by less than 2 % of its area (FRAME is the original game's smaller polygon)",
			func = function(state)
				local glass = glassOutline()
				local frame = GryMod.FlashRadar.FRAME
				local total = area(glass)
				expect(total).to.beGreaterThan(10000)
				expect(outside(glass, frame)).to.beLessThan(total * 0.02)
				expect(outside(frame, glass)).to.beLessThan(total * 0.02)
			end
		},
		{
			name = "the original game's polygon is kept apart as ORIGINAL_FRAME, a heptagon smaller than the glass",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.ORIGINAL_FRAME).toNot.beNil()
				expect(#R.ORIGINAL_FRAME).to.equal(7)
				expect(R.ORIGINAL_FRAME[1][1]).to.equal(-58)
				expect(R.ORIGINAL_FRAME[3][1]).to.equal(62)
				expect(outside(R.ORIGINAL_FRAME, glassOutline())).to.beLessThan(5)
				expect(area(glassOutline())).to.beGreaterThan(area(R.ORIGINAL_FRAME) * 1.1)
			end
		},
		{
			name = "a contact disappears at the edge of the glass in the four directions, not before (ahead, behind, left, right; at 75 m and at 38 m)",
			func = function(state)
				local glass = glassOutline()

				for _, range in ipairs({75, 38}) do
					for name, dir in pairs({ahead = {0, -1}, behind = {0, 1}, left = {-1, 0}, right = {1, 0}}) do
						local measured = threshold(dir[1], dir[2], range)
						local edge = leaves(glass, dir[1], dir[2])
						-- in radar pixels the edge is the same whatever the range (the range only says what a pixel is worth in metres)
						expect(math.abs(measured - edge) < 0.4).to.beTrue()
						expect(name ~= nil).to.beTrue()
					end
				end
			end
		},
		{
			name = "the edge of the glass in metres for the range of 38 m: the numbers the report quotes (ahead, behind, left, right)",
			func = function(state)
				local S = GryMod.RadarShared
				local metres = S.PIXELS / 38 -- radar pixels per metre
				local ahead, behind = threshold(0, -1, 38) / metres, threshold(0, 1, 38) / metres
				local left, right = threshold(-1, 0, 38) / metres, threshold(1, 0, 38) / metres
				-- 38 m is 43 radar pixels: the glass reaches 45.9 / 49.5 / 77.4 / 70.8 of them
				expect(ahead).to.aboutEqual(45.9 * 38 / 43, 0.5)
				expect(behind).to.aboutEqual(49.5 * 38 / 43, 0.5)
				expect(left).to.aboutEqual(77.4 * 38 / 43, 0.7)
				expect(right).to.aboutEqual(70.8 * 38 / 43, 0.5)
			end
		},
		{
			name = "the map frame (View.MapFrame) is inside the glass and fills it right of MAP_LEFT (the danger bar's strip is the only part left out)",
			func = function(state)
				local View = GryMod.Minimap and GryMod.Minimap.View
				expect(View ~= nil and View.MapFrame ~= nil).to.beTrue()
				local map = View.MapFrame()
				expect(#map >= 4).to.beTrue()
				local glass = glassOutline()
				-- the map is inside the glass
				expect(outside(map, glass)).to.beLessThan(area(map) * 0.02)
				-- and it is the glass right of MAP_LEFT: what is missing is only the strip of the bar
				local x0 = bounds(map)
				local left = GryMod.FlashRadar.MAP_LEFT
				local rest = 0

				for x = left, 80, 0.5 do
					for y = -60, 60, 0.5 do
						if inside(glass, x, y) and not inside(map, x, y) then
							rest = rest + 0.25
						end
					end
				end

				expect(rest).to.beLessThan(area(map) * 0.02)
				-- the map starts at MAP_LEFT, not at the notch of the frame (x = -51.23: that left a hole 14.6 pixels wide beside the bar)
				expect(math.abs(x0 - left) < 0.05).to.beTrue()
				expect(x0 < -60).to.beTrue()
			end
		},
		{
			name = "MAP_LEFT is the left edge of the map: just right of the danger bar the movie draws (its StealthBar) and the left edge of the movie's own map window",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(type(R.MAP_LEFT)).to.equal("number")
				local movie = GryMod.Flash.Load("hud_radarcompassstealth")
				local panel = R.New(movie)
				local units = panel.main:Child("Units").entry.m
				local bar = panel.view:Child("StealthBar")
				expect(bar).toNot.beNil()
				local view = panel.view.entry.m
				local barM = bar.entry.m
				local barRight = -math.huge

				local function apply(m, x, y)
					return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
				end

				-- the shapes of the bar (its two layers; the clip is turned a quarter): the corners through the shape's matrix, the bar's and the radar clip's, in the Root clip's
				-- coordinates, then in radar pixels; the right edge is the farthest right of them
				for _, entry in ipairs(bar:Entries()) do
					local shape = movie.chars[entry.id]

					if shape and shape.dw then
						for _, c in ipairs({{shape.ox, shape.oy}, {shape.ox + shape.dw, shape.oy}, {shape.ox, shape.oy + shape.dh}, {shape.ox + shape.dw, shape.oy + shape.dh}}) do
							local x, y = apply(entry.m, c[1], c[2])
							x, y = apply(barM, x, y)
							x, y = apply(view, x, y)
							barRight = math.max(barRight, (x - units[5] - R.UNITS_CENTRE_X) / R.UNITS_PIXEL)
						end
					end
				end

				expect(barRight > -80 and barRight < -60).to.beTrue()
				-- 0.9 to 2 pixels of margin right of the bar
				expect(R.MAP_LEFT >= barRight + 0.5).to.beTrue()
				expect(R.MAP_LEFT <= barRight + 2.5).to.beTrue()
				-- the movie's map window (the mask of the MapArea, shape 9 at depth 3 of Root): its left edge
				local outline = movie.chars[9].p
				local mask = panel.main:Child("MapArea") and panel.main.list[3].m
				expect(mask).toNot.beNil()
				local left = math.huge

				for i = 1, #outline, 2 do
					local x = outline[i] * mask[1] + outline[i + 1] * mask[3] + mask[5]
					left = math.min(left, (x - units[5] - R.UNITS_CENTRE_X) / R.UNITS_PIXEL)
				end

				expect(R.MAP_LEFT).to.aboutEqual(left, 0.35)
			end
		},
		{
			name = "the map frame starts at MAP_LEFT: no hole between the danger bar and the map, and nothing of the map over the bar",
			func = function(state)
				local R, View = GryMod.FlashRadar, GryMod.Minimap.View
				local map = View.MapFrame()
				local left = math.huge

				for _, p in ipairs(map) do
					left = math.min(left, p[1])
				end

				expect(left).to.aboutEqual(R.MAP_LEFT, 0.01)
			end
		},
		{
			name = "the tiles asked for reach the farthest corner of the map frame: ExtentFactor() times the range, the player's circle of the frame's reach",
			func = function(state)
				local View, S = GryMod.Minimap.View, GryMod.RadarShared
				expect(type(View.ExtentFactor)).to.equal("function")
				local factor = View.ExtentFactor()
				local reach = 0

				for _, p in ipairs(View.MapFrame()) do
					reach = math.max(reach, math.sqrt(p[1] * p[1] + p[2] * p[2]))
				end

				expect(factor * S.PIXELS >= reach - 1e-6).to.beTrue()
				expect(factor * S.PIXELS < reach * 1.1).to.beTrue()
				expect(GryMod.FlashRadar.MAP_EXTENT >= factor - 1e-6).to.beTrue()
			end
		},
		{
			name = "the server looks for contacts as far as the glass reaches: SCAN_FACTOR times the radius covers the farthest corner of FRAME, and not much more",
			func = function(state)
				local S = GryMod.RadarShared
				local reach = 0

				for _, p in ipairs(GryMod.FlashRadar.FRAME) do
					reach = math.max(reach, math.sqrt(p[1] * p[1] + p[2] * p[2]))
				end

				expect(S.SCAN_FACTOR * S.PIXELS >= reach).to.beTrue()
				expect(S.SCAN_FACTOR * S.PIXELS < reach * 1.1).to.beTrue()
			end
		}
	}
}
