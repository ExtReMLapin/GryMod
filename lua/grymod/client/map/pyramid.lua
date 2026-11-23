-- The big map: the tile pyramid (GryMod.Map.Pyramid). Which definition (pixels per metre) a zoom needs, which tiles the window needs and in which
-- order they are asked, and which picture is drawn for a tile that is not there yet: the same place at a coarser level, scaled up, so the map is never
-- empty. Pure maths: the tiles that exist are given as a function, nothing is read from the engine.
--
-- The levels are the minimap's pyramid (2, 4, 8, 16, 32 and 64 pixels per metre, Settings.AUTO_LEVELS), so a tile the minimap already made at a level
-- is the very tile the big map wants (the same level name, the same grid, the same size). A tile of level L covers res / L / METRES_PER_UNIT units a
-- side, so a tile of a coarser level holds exactly (L / L')^2 tiles of a finer one: the grids are aligned on 0.

GryMod = GryMod or {}
GryMod.Map = GryMod.Map or {}
GryMod.Map.Pyramid = GryMod.Map.Pyramid or {}

local Pyramid = GryMod.Map.Pyramid

local floor = math.floor

Pyramid.DEFAULT_LEVELS = {2, 4, 8, 16, 32, 64}
-- the same rule as the minimap's automatic definition (Settings.AutoDefinitionFor), for when that module is not there
Pyramid.FIT = 0.7
-- the most tiles one plan asks
Pyramid.MAX_PLAN = 96

local function finite(n)
	return type(n) == "number" and n - n == 0
end

-- The levels: the minimap's pyramid when the settings module is loaded, else the default list.
function Pyramid.Levels()
	local M = GryMod.Minimap
	local levels = M and M.Settings and M.Settings.AUTO_LEVELS

	if type(levels) == "table" and #levels > 0 then
		return levels
	end

	return Pyramid.DEFAULT_LEVELS
end

-- The place of a level in the list (1 for the coarsest), or nil when it is not a level.
function Pyramid.LevelIndex(ppm)
	local levels = Pyramid.Levels()

	for i = 1, #levels do
		if levels[i] == ppm then
			return i
		end
	end

	return nil
end

-- The level a zoom needs. `k` is the scale of the map in pixels per world unit, `previous` the level in use (nil at the start). The minimap's own rule
-- decides (the smallest level with at least 0.7 times the screen's density, the level in use kept while the density is within 0.6 to 1.6 times it): it is a
-- pure function of the settings module, and calling it never changes the radar's own state.
function Pyramid.Target(k, previous)
	local mpu = GryMod.RadarShared and GryMod.RadarShared.METRES_PER_UNIT or 0.01905
	local levels = Pyramid.Levels()
	local M = GryMod.Minimap
	local rule = M and M.Settings and M.Settings.AutoDefinitionFor

	if type(rule) == "function" then
		return rule(finite(k) and k > 0 and k / mpu or nil, previous)
	end

	if not finite(k) or k <= 0 then
		return previous or levels[1]
	end

	local density = k / mpu
	local wanted = density * Pyramid.FIT

	for i = 1, #levels do
		if levels[i] >= wanted then
			return levels[i]
		end
	end

	return levels[#levels]
end

-- The edge of a tile in units.
function Pyramid.TileUnits(res, ppm, mpu)
	return res / ppm / mpu
end

-- A number for each tile (the level's place and the two indices): a table key that makes no garbage. Indices go from -1048575 to 1048575.
local OFFSET, SPAN = 1048576, 2097152

function Pyramid.Key(levelIndex, tx, ty)
	return (levelIndex * SPAN + (tx + OFFSET)) * SPAN + (ty + OFFSET)
end

-- The tile indices that touch the rectangle minx..maxx, miny..maxy for tiles T units wide, plus `margin` whole tiles on every side.
function Pyramid.Range(minx, maxx, miny, maxy, T, margin)
	margin = margin or 0

	return floor(minx / T) - margin, floor(maxx / T) + margin, floor(miny / T) - margin, floor(maxy / T) + margin
end

-- The coarser tile that holds the tile (tx, ty) of level `ppm`: its indices and the ratio of the two levels (a whole number). nil when `coarserPpm` is not
-- a coarser level with a whole ratio.
function Pyramid.Ancestor(tx, ty, ppm, coarserPpm)
	if not (finite(ppm) and finite(coarserPpm)) or coarserPpm <= 0 or coarserPpm > ppm then
		return nil
	end

	local f = ppm / coarserPpm

	if f ~= floor(f) then
		return nil
	end

	return floor(tx / f), floor(ty / f), f
end

-- The part of the picture of the coarser tile that covers the tile (tx, ty) of level `ppm`: u0, v0, u1, v1. The picture of a tile has its top at world +X and
-- its right at world -Y, so u runs toward -Y and v toward -X.
function Pyramid.SubUV(tx, ty, ppm, coarserPpm)
	local atx, aty, f = Pyramid.Ancestor(tx, ty, ppm, coarserPpm)

	if not atx then
		return nil
	end

	local lx, ly = tx - atx * f, ty - aty * f

	return 1 - (ly + 1) / f, 1 - (lx + 1) / f, 1 - ly / f, 1 - lx / f
end

-- The picture to draw for the tile (tx, ty) of level `ppm`: lookup(level, tx, ty) gives the handle of a tile that exists (anything but nil and false). The
-- exact tile first, then the same place at each coarser level, nearest first. Returns handle, the level used, u0, v0, u1, v1 (the part of the picture that
-- covers the tile); nil when no level has it.
function Pyramid.Resolve(tx, ty, ppm, lookup)
	local handle = lookup(ppm, tx, ty)

	if handle then
		return handle, ppm, 0, 0, 1, 1
	end

	local levels = Pyramid.Levels()
	local index = Pyramid.LevelIndex(ppm)

	if not index then
		return nil
	end

	for i = index - 1, 1, -1 do
		local atx, aty = Pyramid.Ancestor(tx, ty, ppm, levels[i])

		if atx then
			handle = lookup(levels[i], atx, aty)

			if handle then
				local u0, v0, u1, v1 = Pyramid.SubUV(tx, ty, ppm, levels[i])

				return handle, levels[i], u0, v0, u1, v1
			end
		end
	end

	return nil
end

-- The numbers that tell whether the plan has to be made again: the target level, the tiles in view and the tile under the mouse. A table is not made.
function Pyramid.Signature(spec)
	local T = Pyramid.TileUnits(spec.res, spec.target, spec.mpu)
	local tx0, tx1, ty0, ty1 = Pyramid.Range(spec.view.minx, spec.view.maxx, spec.view.miny, spec.view.maxy, T, spec.margin or 0)
	local mx, my = floor(spec.mouse.x / T), floor(spec.mouse.y / T)

	return spec.target, tx0, tx1, ty0, ty1, mx, my
end

local function byOrder(a, b)
	if a.rank ~= b.rank then
		return a.rank < b.rank
	end

	if a.d ~= b.d then
		return a.d < b.d
	end

	if a.tx ~= b.tx then
		return a.tx < b.tx
	end

	return a.ty < b.ty
end

-- The tiles to make: the coarse level of the window first (so a picture comes at once), then the target level with `margin` tiles around the window; each
-- level nearest to the mouse first. A tile that lies wholly outside the bounds, or that has(level, tx, ty) says exists, is left out. The list is cut at MAX_PLAN.
--   spec = {res, mpu, target, coarse, view = {minx, maxx, miny, maxy}, bounds = {x0, x1, y0, y1}, mouse = {x, y}, margin}
-- Returns {{ppm, tx, ty, d}, ...}, d the squared distance in units of the tile's middle to the mouse.
function Pyramid.Plan(spec, has)
	local plan = {}
	local levels = {}

	if spec.coarse and spec.coarse ~= spec.target then
		levels[#levels + 1] = {ppm = spec.coarse, margin = 0, rank = 1}
	end

	levels[#levels + 1] = {ppm = spec.target, margin = spec.margin or 0, rank = 2}

	local b, view, mouse = spec.bounds, spec.view, spec.mouse

	for _, level in ipairs(levels) do
		local T = Pyramid.TileUnits(spec.res, level.ppm, spec.mpu)
		local tx0, tx1, ty0, ty1 = Pyramid.Range(view.minx, view.maxx, view.miny, view.maxy, T, level.margin)
		local first = #plan + 1

		for tx = tx0, tx1 do
			for ty = ty0, ty1 do
				-- the tile's rectangle must touch the bounds
				if (tx + 1) * T > b.x0 and tx * T < b.x1 and (ty + 1) * T > b.y0 and ty * T < b.y1 and not has(level.ppm, tx, ty) then
					local dx, dy = (tx + 0.5) * T - mouse.x, (ty + 0.5) * T - mouse.y

					plan[#plan + 1] = {ppm = level.ppm, tx = tx, ty = ty, d = dx * dx + dy * dy, rank = level.rank}
				end
			end
		end

		-- nearest first inside the level (the sort is for this level's entries only)
		local part = {}

		for i = first, #plan do
			part[#part + 1] = plan[i]
		end

		table.sort(part, byOrder)

		for i = 1, #part do
			plan[first + i - 1] = part[i]
		end
	end

	-- cut: the end of the list is the farthest tiles of the finest level
	for i = #plan, Pyramid.MAX_PLAN + 1, -1 do
		plan[i] = nil
	end

	return plan
end
