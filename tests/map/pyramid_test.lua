-- Tests of the big map's tile pyramid (lua/grymod/client/map/pyramid.lua), GLuaTest format, client realm: which definition (pixels per metre) a zoom
-- needs, which tiles the window needs, in which order they are asked (the nearest to the mouse first, the coarse level before the fine one), and
-- which picture is drawn for a tile that is not there yet (the same place at a coarser level, scaled). Pure maths: the tiles of the cache and the
-- store are given as a function.

local MPU = 0.01905 -- metres per unit
local RES = 1024

local function P()
	local pyramid = GryMod and GryMod.Map and GryMod.Map.Pyramid

	expect(pyramid ~= nil).to.beTrue()

	return pyramid
end

-- the edge of a tile in units
local function T(ppm)
	return RES / ppm / MPU
end

return {
	groupName = "GryMod big map pyramid",
	cases = {
		-- fails without Pyramid.Levels / LevelIndex
		{
			name = "the levels are the minimap's pyramid 2, 4, 8, 16, 32, 64 pixels per metre, found by their number",
			func = function()
				local levels = P().Levels()

				expect(#levels).to.equal(6)
				expect(levels[1]).to.equal(2)
				expect(levels[6]).to.equal(64)
				expect(P().LevelIndex(16)).to.equal(4)
				expect(P().LevelIndex(3)).to.beNil()
			end
		},
		-- fails when the definition does not follow the density of the screen
		{
			name = "a zoom needs the smallest level that has 0.7 times the screen's density, and keeps its level while the density is within 0.6 to 1.6 of it",
			func = function()
				local pyramid = P()
				-- 20000 units across 800 pixels: 0.04 pixel a unit, 2.1 pixels a metre
				local k = 0.04

				expect(pyramid.Target(k, nil)).to.equal(2)
				-- zoom 8: 16.8 pixels a metre, wanted 11.8: level 16
				expect(pyramid.Target(k * 8, nil)).to.equal(16)
				-- the hysteresis: at level 16 a density of 12 (zoom 5.7) stays at 16
				expect(pyramid.Target(k * 5.7, 16)).to.equal(16)
				-- but without a level in use the rule gives the smallest level with at least 0.7 of the density: 12 * 0.7 = 8.4 -> 16
				expect(pyramid.Target(k * 5.7, nil)).to.equal(16)
				-- a density far under the level in use drops it: 0.04 at level 16 is 2.1 pixels a metre
				expect(pyramid.Target(k, 16)).to.equal(2)
				-- bad numbers keep the level in use
				expect(pyramid.Target(0 / 0, 8)).to.equal(8)
				expect(type(pyramid.Target(nil, nil))).to.equal("number")
			end
		},
		-- fails when Target does not ask the minimap's rule, or touches the radar's own automatic level
		{
			name = "the target level is what the minimap's rule gives for the density of the zoom, and asking never changes the radar's automatic level",
			func = function()
				local M = GryMod.Minimap
				local created = M == nil

				GryMod.Minimap = M or {}
				GryMod.Minimap.Settings = GryMod.Minimap.Settings or {}

				local S = GryMod.Minimap.Settings
				local savedRule, savedSet = S.AutoDefinitionFor, S.SetAutoDefinition
				local asked, set = {}, 0

				S.AutoDefinitionFor = function(density, previous)
					asked[#asked + 1] = {density, previous}

					return 32
				end

				S.SetAutoDefinition = function()
					set = set + 1

					return true
				end

				local ok, err = pcall(function()
					expect(P().Target(0.1, 8)).to.equal(32)
					expect(#asked).to.equal(1)
					expect(asked[1][1]).to.aboutEqual(0.1 / 0.01905, 1e-9)
					expect(asked[1][2]).to.equal(8)
					expect(set).to.equal(0)
				end)

				S.AutoDefinitionFor, S.SetAutoDefinition = savedRule, savedSet

				if created then
					GryMod.Minimap = nil
				end

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when the tile range is not floor of the edges
		{
			name = "the tiles of a rectangle are the indices from floor(min / T) to floor(max / T), with a margin of whole tiles",
			func = function()
				local tx0, tx1, ty0, ty1 = P().Range(-100, 5000, 200, 9000, 4096, 0)

				expect(tx0).to.equal(-1)
				expect(tx1).to.equal(1)
				expect(ty0).to.equal(0)
				expect(ty1).to.equal(2)

				tx0, tx1, ty0, ty1 = P().Range(-100, 5000, 200, 9000, 4096, 1)
				expect(tx0).to.equal(-2)
				expect(tx1).to.equal(2)
				expect(ty0).to.equal(-1)
				expect(ty1).to.equal(3)
			end
		},
		-- fails when two different tiles share a key
		{
			name = "the numeric key of a tile is different for every level, tx and ty (negative ones too) and the same for the same tile",
			func = function()
				local pyramid = P()
				local seen, count = {}, 0

				for level = 1, 6 do
					for tx = -3, 3 do
						for ty = -3, 3 do
							local key = pyramid.Key(level, tx, ty)

							expect(seen[key]).to.beNil()
							seen[key] = true
							count = count + 1
						end
					end
				end

				expect(count).to.equal(6 * 49)
				expect(pyramid.Key(3, -2, 5)).to.equal(pyramid.Key(3, -2, 5))
			end
		},
		-- fails when the coarse tile that holds a fine one is not found by flooring
		{
			name = "the coarse tile that holds a fine tile is found by flooring its index by the ratio of the levels, negative indices too",
			func = function()
				local atx, aty, f = P().Ancestor(3, -2, 4, 2)

				expect(atx).to.equal(1)
				expect(aty).to.equal(-1)
				expect(f).to.equal(2)

				atx, aty, f = P().Ancestor(-1, -5, 16, 2)
				expect(atx).to.equal(-1)
				expect(aty).to.equal(-1)
				expect(f).to.equal(8)

				-- a level that is not coarser, or not a whole ratio: nothing
				expect(P().Ancestor(3, 3, 2, 4)).to.beNil()
				expect(P().Ancestor(3, 3, 6, 4)).to.beNil()
			end
		},
		-- fails when the part of the coarse picture is not the one of the fine tile (the picture has its top at +X and its right at -Y)
		{
			name = "the part of a coarse tile's picture that covers a fine tile: u runs toward -Y, v toward -X (the tile (3, -2) at 4 over (1, -1) at 2)",
			func = function()
				local u0, v0, u1, v1 = P().SubUV(3, -2, 4, 2)

				expect(u0).to.aboutEqual(0.5, 1e-9)
				expect(u1).to.aboutEqual(1, 1e-9)
				expect(v0).to.aboutEqual(0, 1e-9)
				expect(v1).to.aboutEqual(0.5, 1e-9)

				-- the tile is the whole picture when the levels are the same
				u0, v0, u1, v1 = P().SubUV(5, 7, 8, 8)
				expect(u0).to.equal(0)
				expect(v0).to.equal(0)
				expect(u1).to.equal(1)
				expect(v1).to.equal(1)

				-- the four fine tiles of one coarse tile cover its picture exactly once
				local covered = 0

				for lx = 0, 1 do
					for ly = 0, 1 do
						local a, b, c, d = P().SubUV(2 + lx, 4 + ly, 4, 2)

						covered = covered + (c - a) * (d - b)
					end
				end

				expect(covered).to.aboutEqual(1, 1e-9)
			end
		},
		-- fails when a missing tile does not fall back on the nearest coarser level
		{
			name = "a tile that is not there is drawn from the nearest coarser level that has its place, never from a finer or a farther one",
			func = function()
				local has = {["16:5:5"] = "A", ["4:1:1"] = "B", ["2:0:0"] = "C"}
				local function lookup(ppm, tx, ty)
					return has[ppm .. ":" .. tx .. ":" .. ty]
				end

				-- the exact tile
				local handle, ppm = P().Resolve(5, 5, 16, lookup)

				expect(handle).to.equal("A")
				expect(ppm).to.equal(16)

				-- level 16 tile (6, 6) is not there, level 8 (3, 3) neither, level 4 (1, 1) is
				handle, ppm = P().Resolve(6, 6, 16, lookup)
				expect(handle).to.equal("B")
				expect(ppm).to.equal(4)

				-- only the coarsest
				handle, ppm = P().Resolve(0, 0, 16, lookup)
				expect(handle).to.equal("C")
				expect(ppm).to.equal(2)

				-- nothing at all
				handle = P().Resolve(40, 40, 16, lookup)
				expect(handle).to.beNil()

				-- the part of the coarse picture comes with it
				local _, _, u0, v0, u1, v1 = P().Resolve(6, 6, 16, lookup)

				expect(u1 - u0).to.aboutEqual(1 / 4, 1e-9)
				expect(v1 - v0).to.aboutEqual(1 / 4, 1e-9)
			end
		},
		-- fails when the plan is not the coarse level first, then the target, nearest to the mouse first
		{
			name = "the plan asks the coarse level of the window first and the target level after it, each nearest to the mouse first, and leaves out what exists",
			func = function()
				local spec = {
					res = RES, mpu = MPU, target = 8, coarse = 2,
					view = {minx = 0, maxx = T(8) * 3 - 1, miny = 0, maxy = T(8) * 2 - 1},
					bounds = {x0 = -100000, x1 = 100000, y0 = -100000, y1 = 100000},
					mouse = {x = T(8) * 2.5, y = T(8) * 0.5},
					margin = 0
				}
				local function has(ppm, tx, ty)
					return ppm == 8 and tx == 1 and ty == 0
				end

				local plan = P().Plan(spec, has)

				-- the coarse tiles come first
				expect(plan[1].ppm).to.equal(2)

				local firstFine

				for i, entry in ipairs(plan) do
					if entry.ppm == 8 then
						firstFine = firstFine or i
					end
				end

				expect(firstFine ~= nil).to.beTrue()

				for i = 1, firstFine - 1 do
					expect(plan[i].ppm).to.equal(2)
				end

				-- on the fine level the nearest tile to the mouse (2, 0) is first: 6 tiles in view minus the one that exists
				local fine = {}

				for i = firstFine, #plan do
					fine[#fine + 1] = plan[i]
				end

				expect(#fine).to.equal(5)
				expect(fine[1].tx).to.equal(2)
				expect(fine[1].ty).to.equal(0)

				for i = 2, #fine do
					expect(fine[i].d >= fine[i - 1].d).to.beTrue()
				end

				for _, entry in ipairs(fine) do
					expect(entry.tx == 1 and entry.ty == 0).to.beFalse()
				end
			end
		},
		-- fails when the plan asks tiles outside the bounds
		{
			name = "the plan never asks a tile that lies wholly outside the bounds, and is cut at a maximum length",
			func = function()
				local spec = {
					res = RES, mpu = MPU, target = 4, coarse = 4,
					view = {minx = -T(4) * 10, maxx = T(4) * 10, miny = -T(4) * 10, maxy = T(4) * 10},
					bounds = {x0 = 0, x1 = T(4) * 2, y0 = 0, y1 = T(4) * 2},
					mouse = {x = 0, y = 0},
					margin = 1
				}
				local plan = P().Plan(spec, function() return false end)

				for _, entry in ipairs(plan) do
					expect(entry.tx >= 0 and entry.tx <= 1).to.beTrue()
					expect(entry.ty >= 0 and entry.ty <= 1).to.beTrue()
				end

				expect(#plan).to.equal(4)

				spec.bounds = {x0 = -1e7, x1 = 1e7, y0 = -1e7, y1 = 1e7}
				spec.view = {minx = -1e6, maxx = 1e6, miny = -1e6, maxy = 1e6}
				plan = P().Plan(spec, function() return false end)
				expect(#plan <= P().MAX_PLAN).to.beTrue()
			end
		},
		-- fails when the plan contains the same tile twice or lists a coarse tile when coarse == target twice
		{
			name = "when the coarse level is the target level the plan holds each tile once",
			func = function()
				local spec = {
					res = RES, mpu = MPU, target = 2, coarse = 2,
					view = {minx = 0, maxx = T(2) * 2 - 1, miny = 0, maxy = T(2) - 1},
					bounds = {x0 = -1e6, x1 = 1e6, y0 = -1e6, y1 = 1e6},
					mouse = {x = 0, y = 0},
					margin = 0
				}
				local plan = P().Plan(spec, function() return false end)

				expect(#plan).to.equal(2)
			end
		},
		-- fails when the plan signature does not change with the mouse's tile
		{
			name = "the signature of a plan changes when the target, the tiles in view or the tile under the mouse change, and not otherwise",
			func = function()
				local base = {
					res = RES, mpu = MPU, target = 8, coarse = 2, margin = 1,
					view = {minx = 0, maxx = T(8) * 3 - 1, miny = 0, maxy = T(8) * 2 - 1},
					mouse = {x = 10, y = 10}
				}
				local a1, a2, a3, a4, a5, a6, a7 = P().Signature(base)
				local b1, b2, b3, b4, b5, b6, b7 = P().Signature(base)

				expect(a1 == b1 and a2 == b2 and a3 == b3 and a4 == b4 and a5 == b5 and a6 == b6 and a7 == b7).to.beTrue()

				base.mouse = {x = 20, y = 20} -- the same tile
				local c1, c2, c3, c4, c5, c6, c7 = P().Signature(base)

				expect(a1 == c1 and a2 == c2 and a3 == c3 and a4 == c4 and a5 == c5 and a6 == c6 and a7 == c7).to.beTrue()

				base.mouse = {x = T(8) * 1.5, y = 20} -- another tile
				local d1, d2 = P().Signature(base)

				expect(a6 ~= select(6, P().Signature(base)) or a2 ~= d2 or a1 ~= d1).to.beTrue()
			end
		}
	}
}
