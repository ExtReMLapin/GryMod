-- Tests of GryMod.Minimap.Preload (lua/grymod/client/minimap/preload.lua), GLuaTest format, client realm. The preload makes the list of tiles to prepare in advance from
-- the in/out map's boxes (the outdoor ones, the open level) and from the definitions the automatic rule can reach from the player's zoom ranges.
-- Everything here is pure: the engine's parts (the ray of Floors.OpenAt, the tile size of Cache, the cache's Has) are stand-ins given in `opts`, and the one real
-- part is the rule of Settings.AutoDefinitionFor (the definitions are found with it, the numbers below were worked out by hand from its rule).

local function P()
	return GryMod.Minimap.Preload or {}
end

-- a box as the in/out map gives it: layer, x1, y1, x2, y2 (cells of 128 units, inclusive), state (1 outdoor, 2 indoor), ceiling class
local function box(layer, x1, y1, x2, y2, state)
	return {layer = layer, x1 = x1, y1 = y1, x2 = x2, y2 = y2, state = state or 1, ceil = 0}
end

local function level(id)
	return {id = id, open = true, zlo = -100, zhi = 5000}
end

-- the options of a plan: tiles of 256 units whatever the definition, one level for every place unless `levelAt` is given
local function options(extra)
	local opts = {
		definitions = {2},
		res = 1024,
		tileUnits = function() return 256 end,
		levelAt = function() return level("open_t960") end,
		has = function() return false end,
		origin = {0, 0}
	}

	for k, v in pairs(extra or {}) do
		opts[k] = v
	end

	return opts
end

-- the whole list a job makes, stepped in as many pieces as asked
local function run(boxes, opts, perStep)
	local job = P().NewJob(boxes, opts)

	while not job.Done() do
		job.Step(perStep or 1000)
	end

	return job.Entries(), job
end

-- The stand-ins of the driver's world: the settings (the real rule of the automatic definition, the values of the convars given by the case), the in/out map's boxes,
-- the cache (the real tile size, no tile there), the generator (it keeps what it was handed), Floors.OpenAt (counts its rays), the hook, the timer and the clock.
-- env.set{...} changes values: preload, autozoom, vehicle, foot, indoor, range (convars), k (screen constant, false = unknown), definition, autodef (0 / 1), boxes (true: an
-- outdoor and an indoor box, false: no map), around (the convar of the ring of places around each node: 0 in the plain cases), frame (the last frame's duration). env.restore() puts everything back (a case always calls it, also after a failure).
local function makeEnv()
	local M = GryMod.Minimap
	local P0 = M.Preload
	local env = {hooks = {}, timers = {}, handed = nil, rays = 0, peeks = 0, grounds = 0}
	local saved = {Settings = M.Settings, Cache = M.Cache, Gen = M.Gen, Floors = M.Floors, Zone = GryMod.ZoneMapClient, AIN = GryMod.AIN}
	local savedFields = {}

	for _, k in ipairs({"_hookAdd", "_hookRemove", "_timerCreate", "_timerRemove", "_convar", "_frameTime", "_clock", "_origin"}) do
		savedFields[k] = P0[k]
	end

	local v = {preload = 1, around = 0, autozoom = 0, vehicle = 100, foot = 75, indoor = 25, range = 25, k = 130, definition = 4, autodef = 1, boxes = true, frame = 0.005, nodes = {}}

	local function boxList()
		if v.boxes == "outdoor" then
			return {box(0, 0, 0, 7, 7)} -- the outdoor box alone
		end

		return {box(0, 0, 0, 7, 7), box(0, 20, 20, 22, 22, 2)}
	end

	M.Settings = {
		Enabled = function() return true end,
		DefinitionAuto = function() return v.autodef == 1 end,
		Definition = function() return v.definition end,
		TileRes = function() return 1024 end,
		ScreenConstant = function() return v.k or nil end,
		AUTO_LEVELS = saved.Settings.AUTO_LEVELS,
		AutoDefinitionFor = saved.Settings.AutoDefinitionFor
	}
	M.Cache = {
		TileUnits = function(res, ppm) return res / ppm / 0.01905 end,
		Has = function() return false end
	}
	M.Gen = {
		PRELOAD_MAX_FRAME = 0.025,
		SetPreload = function(entries)
			env.handed = entries

			return true
		end
	}
	M.Floors = {
		MapOpenTop = function() return 5000 end,
		GroundAt = function(_, _, top)
			env.grounds = env.grounds + 1

			return top - 100
		end,
		PeekAt = function(_, _, z)
			env.peeks = env.peeks + 1

			return {id = "f" .. z .. "c120", zlo = z - 56, zhi = z + 120}
		end,
		OpenAt = function()
			env.rays = env.rays + 1

			return level("open_t960")
		end
	}
	GryMod.ZoneMapClient = {
		Boxes = function() return v.boxes and boxList() or nil end,
		Indoor = function(pos) return pos.x >= 1000 end -- the places at x of 1000 and over are indoors
	}
	GryMod.AIN = {
		Load = function() return {nodes = v.nodes} end
	}

	P0._hookAdd = function(_, name, fn) env.hooks[#env.hooks + 1] = {name = name, fn = fn} end
	P0._hookRemove = function(_, name)
		for i = #env.hooks, 1, -1 do
			if env.hooks[i].name == name then
				table.remove(env.hooks, i)
			end
		end
	end
	P0._timerCreate = function(name, _, _, fn)
		for i = #env.timers, 1, -1 do
			if env.timers[i].name == name then
				table.remove(env.timers, i)
			end
		end

		env.timers[#env.timers + 1] = {name = name, fn = fn}
	end
	P0._timerRemove = function(name)
		for i = #env.timers, 1, -1 do
			if env.timers[i].name == name then
				table.remove(env.timers, i)
			end
		end
	end
	P0._convar = function(name)
		return ({
			gry_minimap_preload = v.preload,
			gry_minimap_preload_around = v.around,
			gry_radar_autozoom = v.autozoom,
			gry_radar_zoom_vehicle = v.vehicle,
			gry_radar_zoom_foot = v.foot,
			gry_radar_zoom_indoor = v.indoor,
			gry_radar_range = v.range
		})[name]
	end
	P0._frameTime = function() return v.frame end
	P0._origin = function() return {0, 0} end

	function env.set(values)
		for k, value in pairs(values) do
			v[k] = value
		end
	end

	function env.frame()
		local list = {}

		for i, h in ipairs(env.hooks) do
			list[i] = h.fn
		end

		for _, fn in ipairs(list) do
			fn()
		end
	end

	function env.fireTimer()
		local t = table.remove(env.timers, 1)

		if t then
			t.fn()
		end
	end

	function env.restore()
		pcall(function() P0.Stop() end)
		M.Settings, M.Cache, M.Gen, M.Floors = saved.Settings, saved.Cache, saved.Gen, saved.Floors
		GryMod.ZoneMapClient = saved.Zone
		GryMod.AIN = saved.AIN

		for k, value in pairs(savedFields) do
			P0[k] = value
		end
	end

	return env
end

-- tables are compared by reference by the framework: lists are compared as text
local function text(list)
	local out = {}

	for i, v in ipairs(list) do
		out[i] = tostring(v)
	end

	return table.concat(out, " ")
end

local function ids(entries)
	local out = {}

	for i, e in ipairs(entries) do
		out[i] = e.tile.level .. ":" .. e.tile.tx .. "," .. e.tile.ty .. "@" .. e.tile.ppm
	end

	table.sort(out)

	return out
end

return {
	groupName = "GryMod minimap preload (client)",
	cases = {
		{
			-- a tile of 1024 px costs 1024 * 1024 / 2 (DXT1) + 208 (header) + 600 (the .vmt) = 525096 bytes; the plan may fill 80 % of the cache limit minus what it holds
			-- breaks if: the byte cost of a tile is changed or forgotten, the share of the limit is not 80 %, the used bytes are not taken off, the answer is not a whole number or can be negative, a missing number is not 0
			name = "TilesThatFit: how many tiles of a resolution fit in 80 % of the cache limit once the used bytes are taken off, never negative",
			func = function()
				expect(isfunction(P().TilesThatFit)).to.beTrue()

				local MB = 1048576

				-- 768 MB: 0.8 * 805306368 = 644245094.4 bytes, 1226 tiles of 525096 bytes (1227 would need 644292792)
				expect(P().TilesThatFit(768 * MB, 0, 1024)).to.equal(1226)

				-- a tile of 512 px is 131880 bytes: 4885 of them
				expect(P().TilesThatFit(768 * MB, 0, 512)).to.equal(4885)

				-- the used bytes are taken off: 400 MB held leaves 644245094.4 - 419430400 = 224814694.4 bytes, 428 tiles
				expect(P().TilesThatFit(768 * MB, 400 * MB, 1024)).to.equal(428)

				-- a cache already over 80 % has room for none, not for a negative number
				expect(P().TilesThatFit(256 * MB, 210 * MB, 1024)).to.equal(0)

				-- a missing number is 0 tiles, except the used bytes (nothing held)
				expect(P().TilesThatFit(nil, 0, 1024)).to.equal(0)
				expect(P().TilesThatFit(768 * MB, 0, nil)).to.equal(0)
				expect(P().TilesThatFit(768 * MB, nil, 1024)).to.equal(1226)
				expect(P().TilesThatFit(0, 0, 1024)).to.equal(0)
			end
		},
		{
			-- the loop of the owner's game (2026-11-22): a plan bigger than the cache can hold made the generator make tiles, trim them away and make them again
			-- breaks if: Start does not ask the cache how full it is, the cap is not applied to the plan, or a cache with no limit known stops the preload from being planned
			name = "driver: the plan is capped to the tiles that fit in the cache limit (the nearest are kept); with no limit known it is not capped",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					local M = GryMod.Minimap
					local limit, held = nil, 0

					M.Settings.CacheBytes = function() return limit end
					M.Cache.Trim = function() return {removed = 0, bytes = held} end

					-- a big outdoor box (400 x 400 cells of 128 units): at 4 px per metre a tile is 13438 units wide, so the plan has several tiles
					GryMod.ZoneMapClient.Boxes = function() return {box(0, 0, 0, 399, 399)} end

					local function planned()
						env.handed = nil
						env.set({autozoom = 0, range = 25, k = 130})
						expect(P().Start()).to.beTrue()

						local frames = 0

						while #env.hooks > 0 and frames < 200 do
							env.frame()
							frames = frames + 1
						end

						expect(env.handed ~= nil).to.beTrue()

						return #env.handed
					end

					local all = planned()

					expect(all > 3).to.beTrue()

					-- room for 3 tiles of 525096 bytes: 3.5 tiles' worth at 80 %
					limit = math.floor(3.5 * 525096 / 0.8)
					expect(planned()).to.equal(3)

					-- room for them all and more: the plan is whole
					limit = 4096 * 1048576
					expect(planned()).to.equal(all)

					-- bytes held already fill the share: no tile at all, and the preload says so by an empty plan
					limit = 256 * 1048576
					held = 220 * 1048576
					expect(planned()).to.equal(0)

					-- no limit known: not capped
					limit, held = nil, 0
					expect(planned()).to.equal(all)
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- the numbers come from Settings.AutoDefinitionFor (smallest level of at least 0.7 times the density, the level in use kept between 0.6 and 1.6 times it) with
			-- k = 130 (the radar's pixels per metre times the screen's, for a 4K screen: the density at a range r is k / r).
			-- breaks if: the level in use is forgotten, a level shared by two ranges is listed twice, a range gets a level other than the rule's, or a slider value that is
			-- not a level of the pyramid gets into the list
			name = "Definitions: the level in use plus the level of each zoom range, shared ones once (100 / 75 / 25 m on 4K give 2 and 4; 100 / 40 / 10 m give 2, 4 and 16)",
			func = function()
				expect(isfunction(P().Definitions)).to.beTrue()

				-- the owner's three ranges: the 100 and the 75 give the same level, the 25 another
				expect(text(P().Definitions(130, {100, 75, 25}, 4))).to.equal("2 4")

				-- three ranges, three levels (the 40 m would stay at 2 only up to a density of 3.2, it is 3.25)
				expect(text(P().Definitions(130, {100, 40, 10}, 4))).to.equal("2 4 16")

				-- one range: its own level, and the level in use (the radar draws it under the new one while it is made)
				expect(text(P().Definitions(130, {25}, 4))).to.equal("4")
				expect(text(P().Definitions(130, {25}, 2))).to.equal("2 4")

				-- a level in use that the pyramid does not have (the slider's value) is not a level of the rule: not in the list
				expect(text(P().Definitions(130, {25}, 15))).to.equal("4")

				-- nothing usable: no density constant, or no range
				expect(text(P().Definitions(nil, {25}, 4))).to.equal("")
				expect(text(P().Definitions(130, {}, 4))).to.equal("")
			end
		},
		{
			-- breaks if: an indoor box is asked for an open level, a tile is listed twice (four sub-areas of a box fall in two tiles), or the tile range is off by one
			name = "NewJob: the tiles that cover the outdoor boxes (an indoor box is left out, a tile is listed once), by hand: 4 x 2 cells of 128 units are 2 tiles of 256",
			func = function()
				local asked = 0
				local entries = run({box(0, 0, 0, 3, 1), box(0, 10, 10, 12, 12, 2)}, options({
					levelAt = function()
						asked = asked + 1

						return level("open_t960")
					end
				}))

				-- the box covers x 0..512 and y 0..256: tiles (0,0) and (1,0)
				expect(text(ids(entries))).to.equal("open_t960:0,0@2 open_t960:1,0@2")
				expect(entries[1].level.id).to.equal("open_t960")

				-- 4 x 2 cells are split in 3 x 2 areas (at most 3 along an axis, never more than the cells): six rays, none for the indoor box
				expect(asked).to.equal(6)
			end
		},
		{
			-- breaks if: the list is not the nearest tiles first (the preload would start far from the player), or a tile the cache already has is made again
			name = "NewJob: nearest to the player first; a tile the cache has is left out",
			func = function()
				local boxes = {box(0, 0, 0, 7, 0)} -- x 0..1024, one row: tiles 0, 1, 2, 3 (of 256)
				local entries = run(boxes, options({origin = {900, 50}}))

				-- the tile of x 768..1024 is the nearest to (900, 50), then 512..768, then 256..512, then 0..256
				expect(#entries).to.equal(4)
				expect(entries[1].tile.tx).to.equal(3)
				expect(entries[2].tile.tx).to.equal(2)
				expect(entries[4].tile.tx).to.equal(0)

				local has = function(tile) return tile.tx == 3 end
				local rest = run(boxes, options({origin = {900, 50}, has = has}))

				expect(#rest).to.equal(3)
				expect(rest[1].tile.tx).to.equal(2)
			end
		},
		{
			-- breaks if: a place under a roof (no open level) makes tiles, or two heights in one tile are mixed into a single level (the camera of one of them is wrong)
			name = "NewJob: a place with no open level makes no tile; two levels over one tile make two tiles",
			func = function()
				-- left half of the box under a roof, right half open at 960
				local entries = run({box(0, 0, 0, 1, 0)}, options({
					levelAt = function(x)
						if x < 128 then
							return nil, "roofed"
						end

						return level("open_t960")
					end
				}))

				expect(text(ids(entries))).to.equal("open_t960:0,0@2")

				-- the left half under a piece at 2944, the right half open at 960: the same tile (0,0), two levels
				local mixed = run({box(0, 0, 0, 1, 0)}, options({
					levelAt = function(x)
						return level(x < 128 and "open_t2944" or "open_t960")
					end
				}))

				expect(text(ids(mixed))).to.equal("open_t2944:0,0@2 open_t960:0,0@2")
			end
		},
		{
			-- breaks if: every definition does not get its own tiles (a tile of another size covers another area), or the cap is not on the nearest tiles
			name = "NewJob: every definition has its own tiles, and a plan over the cap keeps the nearest ones and says it was cut",
			func = function()
				-- definition 2 has tiles of 256 units, definition 4 of 128
				local opts = options({
					definitions = {2, 4},
					tileUnits = function(_, ppm) return ppm == 2 and 256 or 128 end
				})
				local entries = run({box(0, 0, 0, 1, 0)}, opts) -- x 0..256, y 0..128

				expect(text(ids(entries))).to.equal("open_t960:0,0@2 open_t960:0,0@4 open_t960:1,0@4")

				local capped, job = run({box(0, 0, 0, 7, 0)}, options({origin = {0, 0}, maxTiles = 2}))

				expect(#capped).to.equal(2)
				expect(capped[1].tile.tx).to.equal(0)
				expect(capped[2].tile.tx).to.equal(1)
				expect(job.Truncated()).to.beTrue()
				expect(job.Total()).to.equal(4)
			end
		},
		{
			-- the cells at the fringe of a box (the spread of the in/out map is wider than the ground) may see a ray that goes through the sky of the playable area into the skybox:
			-- levels over the top of the map's open level are not made (gm_construct made open_t10176 and open_t15168 for them). breaks if: such a place makes tiles
			name = "NewJob: a place whose level is over maxTop (the playable sky) makes no tile; one at or under it does",
			func = function()
				local entries = run({box(0, 0, 0, 1, 0), box(0, 4, 0, 5, 0), box(0, 8, 0, 9, 0)}, options({
					maxTop = 9920,
					levelAt = function(x)
						-- the three boxes are 1024 units apart: x of the first area is in 0..256, the second 512..768, the third 1024..1280
						local top = x < 400 and 9920 or (x < 900 and 15168 or 5000)

						return {id = "open_t" .. top, open = true, zlo = -100, zhi = top}
					end
				}))

				local seen = {}

				for _, e in ipairs(entries) do
					seen[e.level.id] = true
				end

				expect(seen.open_t9920).to.beTrue()
				expect(seen.open_t5000).to.beTrue()
				expect(seen.open_t15168).to.beNil()
			end
		},
		{
			-- the floors: the ground places of the node graph, each with the level a player there would get (Floors.PeekAt) and the definitions of its mode (indoors: the indoor
			-- range's, else the foot range's). breaks if: a place makes tiles of another definition than definitionsAt gives, the tiles around it (its edge cases: a place near a
			-- tile edge needs the next tile too) are not listed, or two places of one tile list it twice
			name = "NewJob: a ground place makes the tiles around it for its own level and the definitions of its place; places in one tile list it once; a place with no level makes none",
			func = function()
				local floorLevel = {id = "f0c120", zlo = -56, zhi = 120}
				local entries = run({}, options({
					places = {{x = 100, y = 100, z = 0}, {x = 110, y = 90, z = 0}, {x = 5000, y = 5000, z = 400}},
					placeLevelAt = function(x, _, z)
						if z > 100 then
							return nil, "roofed"
						end

						return floorLevel
						end,
					definitionsAt = function() return {4} end
				}))

				-- one place of tiles of 256 units: the square of 256 units around (100, 100) is [-156, 356]: tiles -1..1 on both axes, nine tiles; the second place is in the same
				-- tiles (110, 90): nothing more; the third has no level
				expect(#entries).to.equal(9)

				for _, e in ipairs(entries) do
					expect(e.tile.level).to.equal("f0c120")
					expect(e.tile.ppm).to.equal(4)
					expect(e.level).to.equal(floorLevel)
				end

				-- without definitionsAt the job's definitions are used
				local plain = run({}, options({
					definitions = {2, 8},
					places = {{x = 100, y = 100, z = 0}},
					placeLevelAt = function() return floorLevel end
				}))

				expect(#plain).to.equal(18)
			end
		},
		{
			-- the underground and the places the graph does not reach (the navigation mesh does, so the in/out map's indoor boxes do): the floors of an indoor box are asked at its areas,
			-- each with its own ground height. breaks if: an indoor box without indoorLevelAt makes tiles, the definitions of the place are not used, or a place with no ground makes one
			name = "NewJob: an indoor box makes the tiles of its areas for the level indoorLevelAt gives (at the top of its layer), at the definitions of the place; no indoorLevelAt, no tile; no level, no tile",
			func = function()
				local asked = {}
				local floorLevel = {id = "f96c120", zlo = 40, zhi = 216}
				local entries = run({box(1, 0, 0, 1, 0, 2)}, options({
					indoorLevelAt = function(x, y, z)
						asked[#asked + 1] = x .. "," .. y .. "," .. z

						return floorLevel
					end,
					definitionsAt = function() return {4} end
				}))

				-- a box of 2 x 1 cells (x 0..256, y 0..128) of the layer 1 (z 64..192, top 191) is cut in 2 x 1 areas: two asks, at the top of the layer
				expect(#asked).to.equal(2)
				expect(asked[1]).to.equal("64,64,191")
				expect(asked[2]).to.equal("192,64,191")
				expect(#entries >= 1).to.beTrue()

				for _, e in ipairs(entries) do
					expect(e.tile.level).to.equal("f96c120")
					expect(e.tile.ppm).to.equal(4)
				end

				-- no indoorLevelAt: the indoor box makes nothing (it was so before the floors)
				expect(#run({box(1, 0, 0, 1, 0, 2)}, options())).to.equal(0)

				-- a place with no ground
				expect(#run({box(1, 0, 0, 1, 0, 2)}, options({indoorLevelAt = function() return nil end}))).to.equal(0)
			end
		},
		{
			-- breaks if: the indoor boxes of the in/out map are not turned into floor places (the underground of a navigation-mesh map would be left to the player), the ground is not
			-- looked for under the top of the layer, or the indoor definition is not the one used
			name = "driver: the indoor boxes of the in/out map make floor places (the ground found under the top of the layer, then the level of a player there), at the indoor range's definition",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = true, nodes = {}})
					expect(P().Start()).to.beTrue()

					local frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					-- the indoor box is of the layer 0 (top 63): the ground the stand-in finds is 100 under it, -37, and the stand-in level is named after it
					local found = {}

					for _, e in ipairs(env.handed) do
						if e.tile.level == "f-37c120" then
							found[e.tile.ppm] = true
						end
					end

					expect(found[4]).to.beTrue() -- the indoor range (25 m, k = 130) gives 4 px/m
					expect(found[2]).to.beNil()
					expect(env.grounds > 0).to.beTrue()
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- The level of a place is a function of the place only (Floors.LevelFor, rule of 2026-11-22): what PeekAt answers does not depend on what was asked before, so the plan
			-- is made once (it was made twice while the level depended on the registry of anchors known so far). breaks if: the places are asked twice (twice the rays for
			-- nothing), or the tiles of the plan are not handed over
			name = "driver: the plan is made in one pass over the places (the level of a place depends on nothing asked before), each place asked once, its tiles handed over",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					local seenPlaces = 0
					GryMod.Minimap.Floors.PeekAt = function(x, y, z)
						seenPlaces = seenPlaces + 1

						return {id = "c128t192", zlo = z - 64, zhi = z + 128}
					end

					env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = "outdoor", nodes = {
						{x = 100, y = 100, z = 0, type = 2},
						{x = 3100, y = 100, z = 0, type = 2}
					}})
					expect(P().Start()).to.beTrue()

					local frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					local count = 0

					for _, e in ipairs(env.handed) do
						if e.tile.level == "c128t192" then
							count = count + 1
						end
					end

					expect(seenPlaces).to.equal(2) -- two places, one pass
					expect(count > 0).to.beTrue()
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the places are not part of the steps (a step would do all of them at once), or the job is done before them
			name = "NewJob: the boxes come first, then the places, in the same steps; the job is done when both are done",
			func = function()
				local boxes = {box(0, 0, 0, 1, 0), box(0, 8, 0, 9, 0)}
				local places = {}

				for i = 1, 4 do
					places[i] = {x = i * 1000, y = 0, z = 0}
				end

				local job = P().NewJob(boxes, options({
					places = places,
					placeLevelAt = function() return {id = "c128t192", zlo = -64, zhi = 128} end
				}))

				expect(job.Step(3)).to.equal(3) -- two boxes and one place
				expect(job.Done()).to.beFalse()
				expect(job.Step(3)).to.equal(3) -- three places
				expect(job.Done()).to.beTrue()
				expect(job.Step(3)).to.equal(0)
			end
		},
		{
			-- the driver: the nodes of the graph (ground ones), the mode of each place from the in/out map, the definitions of that mode. breaks if: an air node makes a place,
			-- an indoor place gets the foot range's definition (or the other way round), or a map with no graph breaks the plan
			name = "driver: the ground nodes of the graph are the places of the floors, indoors at the indoor range's definition and outdoors at the foot range's; no graph, no floors",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = false == true, nodes = {
						{x = 100, y = 100, z = 0, type = 2},
						{x = 1100, y = 100, z = 0, type = 2},
						{x = 3000, y = 3000, z = 0, type = 3}
					}})
					env.set({boxes = "outdoor"}) -- the outdoor box alone: the peeks counted below are the nodes' (an indoor box would make its own)

					expect(P().Start()).to.beTrue()

					local frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					local seen = {}

					for _, e in ipairs(env.handed) do
						if string.sub(e.tile.level, 1, 1) == "f" then
							seen[e.tile.ppm] = (seen[e.tile.ppm] or 0) + 1
						end
					end

					-- the foot range (75 m, k = 130) gives 2 px/m, the indoor range (25 m) 4 px/m: the place at x 100 only the first, the one at x 1100 only the second
					expect(seen[2] ~= nil and seen[2] > 0).to.beTrue()
					expect(seen[4] ~= nil and seen[4] > 0).to.beTrue()
					expect(seen[8]).to.beNil()
					-- the air node made no place; the plan is made in one pass (see the next case), so each of the two places is asked once
					expect(env.peeks).to.equal(2)

					-- no graph: the boxes alone, nothing raises
					env.set({nodes = {}})
					env.handed = nil
					expect(P().Start()).to.beTrue()
					frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					expect(env.handed ~= nil).to.beTrue()
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- The measure of 2026-11-22 (docs/minimap.md, "Tile preload"): the level of a place changes within a few steps on a ramp or at a door, so a node alone prepares one level and the
			-- player a step away needs another. The four places a step from a ground node (opts.around units on the two axes) are asked too, each with the ground found under it (opts.groundAt,
			-- from 48 over the node's height), and make the tiles of their own level, a little around them (not the node's 256 units). breaks if: the ring is not asked, a ring place gets the
			-- node's height instead of its own ground, a place with no ground makes a tile, the ring makes the node's wide square of tiles, or opts.around nil still makes a ring
			name = "NewJob: with `around`, the four places a step from a ground node make the tiles of their own level (own ground, a small square), none without ground; without it no ring",
			func = function()
				local asked, grounds = {}, {}
				local function placeLevel(x, y, z)
					asked[#asked + 1] = x .. "," .. y .. "," .. z

					return {id = "f" .. z .. "c120", zlo = z - 56, zhi = z + 120}
				end
				local function groundAt(x, y, top)
					grounds[#grounds + 1] = x .. "," .. y .. "," .. top

					if x > 100 then
						return 16 -- only the place at +x has a ground (a stair a step higher)
					elseif y > 100 then
						return 0
					end

					return nil
				end

				local entries = run({}, options({
					places = {{x = 100, y = 100, z = 0}},
					placeLevelAt = placeLevel,
					around = 64,
					groundAt = groundAt
				}))

				-- the node: ground 0, then the four places in a fixed order (+x, -x, +y, -y), the ground searched from 48 over the node
				expect(text(grounds)).to.equal("164,100,48 36,100,48 100,164,48 100,36,48")
				expect(text(asked)).to.equal("100,100,0 164,100,16 100,164,0")

				local byLevel = {}

				for _, e in ipairs(entries) do
					byLevel[e.tile.level] = (byLevel[e.tile.level] or 0) + 1
				end

				expect(byLevel["f0c120"]).to.equal(9) -- the node's square of 256 units around it: nine tiles of 256, as before
				expect(byLevel["f16c120"]).to.equal(1) -- the ring place at (164, 100) +- 32 units is inside the tile (0, 0): one tile, not nine

				-- no `around`: no ring, no ground asked
				asked, grounds = {}, {}
				run({}, options({places = {{x = 100, y = 100, z = 0}}, placeLevelAt = placeLevel, groundAt = groundAt}))
				expect(#asked).to.equal(1)
				expect(#grounds).to.equal(0)
			end
		},
		{
			-- breaks if: the ring places are not steps of the job (the whole ring of a map would be done in one step, a frame that freezes), a node's ring is not made right after the node,
			-- or the ring is made for the places over the cap (the cap keeps the plan's cost bounded on a map with thousands of nodes: nearest nodes first)
			name = "NewJob: each ring place is a step; over Preload.MAX_AROUND_PLACES nodes only the nearest to the player get a ring",
			func = function()
				local places = {}

				for i = 1, 3 do
					places[i] = {x = i * 1000, y = 0, z = 0}
				end

				local job = P().NewJob({}, options({
					places = places,
					placeLevelAt = function() return {id = "c128t192", zlo = -64, zhi = 128} end,
					around = 64,
					groundAt = function() return 0 end
				}))

				expect(job.Step(2)).to.equal(2) -- the node and one ring place
				expect(job.Done()).to.beFalse()
				expect(job.Step(100)).to.equal(13) -- three more of the first ring, then 2 x 5
				expect(job.Done()).to.beTrue()

				-- the cap: three nodes far to near, the cap at two, the origin at 0: the nearest two get a ring
				local saved = P().MAX_AROUND_PLACES

				P().MAX_AROUND_PLACES = 2

				local ok, err = pcall(function()
					local far = {{x = 3000, y = 0, z = 0}, {x = 2000, y = 0, z = 0}, {x = 1000, y = 0, z = 0}}
					local asked = {}
					local capped = P().NewJob({}, options({
						places = far,
						placeLevelAt = function(x)
							asked[#asked + 1] = x

							return {id = "c128t192", zlo = -64, zhi = 128}
						end,
						around = 64,
						groundAt = function() return 0 end
					}))

					while not capped.Done() do
						capped.Step(1000)
					end

					local ringed = {}

					for _, x in ipairs(asked) do
						local node = math.floor(x / 1000 + 0.5) * 1000

						ringed[node] = (ringed[node] or 0) + 1
					end

					expect(ringed[1000]).to.equal(5)
					expect(ringed[2000]).to.equal(5)
					expect(ringed[3000]).to.equal(1) -- the farthest: the node alone
				end)

				P().MAX_AROUND_PLACES = saved

				if not ok then error(err, 0) end
			end
		},
		{
			-- the definitions of a ring place are those of ITS place (the in/out map at that spot), not the node's: a node outdoors a step from a door has a ring place indoors.
			-- breaks if: the ring takes the node's definitions
			name = "NewJob: a ring place gets the definitions of its own place",
			func = function()
				local entries = run({}, options({
					definitions = {2},
					places = {{x = 980, y = 100, z = 0}},
					placeLevelAt = function(_, _, z) return {id = "f" .. z .. "c120", zlo = z - 56, zhi = z + 120} end,
					definitionsAt = function(x) return x >= 1000 and {4} or {2} end,
					around = 64,
					groundAt = function(x, y, top) return x > 980 and 16 or nil end
				}))
				local ppm = {}

				for _, e in ipairs(entries) do
					ppm[e.tile.level .. "@" .. e.tile.ppm] = true
				end

				expect(ppm["f0c120@2"]).to.beTrue() -- the node outdoors
				expect(ppm["f16c120@4"]).to.beTrue() -- the ring place indoors (x 1044)
				expect(ppm["f16c120@2"]).to.beNil()
			end
		},
		{
			-- the driver reads the switch: the convar gry_minimap_preload_around (default on) gives the ring, 0 takes it away. breaks if: the switch is not read, the ring distance or the
			-- ground ray is not given to the plan, or the ring is made with the switch at 0 (the stand-in counts the ground rays and the peeks)
			name = "driver: gry_minimap_preload_around turns the ring of places around each ground node on or off (the node's own place is always made)",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					local function plan(around)
						env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = "outdoor", around = around, nodes = {
							{x = 100, y = 100, z = 0, type = 2},
							{x = 900, y = 100, z = 0, type = 2},
							{x = 3000, y = 3000, z = 0, type = 3}
						}})
						env.peeks, env.grounds = 0, 0
						expect(P().Start()).to.beTrue()

						local frames = 0

						while #env.hooks > 0 and frames < 200 do
							env.frame()
							frames = frames + 1
						end
					end

					plan(0)
					expect(env.peeks).to.equal(2)
					expect(env.grounds).to.equal(0)

					-- the ring: four places for each of the two ground nodes; and the 8 x 8 cells of the outdoor box, each asked from its ground (a roofed cell would peek: the stand-in's
					-- open level answers, so no peek for them)
					plan(1)
					expect(env.peeks).to.equal(2 + 2 * 4)
					expect(env.grounds).to.equal(2 * 4 + 64)
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- The measure of 2026-11-22 (gm_everpine_mall, gm_construct): a roof, a porch or a high structure inside an OUTDOOR box (the in/out map calls the box open, its cells have no ceiling
			-- class) makes levels the three areas of the box never see (and the ray of Floors.OpenAt starts at the top of the layer, over a low roof). With `around` and `groundAt`, each cell of an
			-- outdoor box is asked: the ground under the top of its layer, then the open level a ray up from the ground gives, or, when that ray hits a roof (nil), the level of a player standing
			-- there (placeLevelAt, at the definitions of that place). breaks if: the roofed cell makes no tile, the open cell is asked as a floor, a cell with no ground asks a level, an indoor
			-- box is sampled by cells, or the cells are sampled without `around`
			name = "NewJob: with `around`, each cell of an outdoor box is asked from the ground up: the open level, or the level of a player under the roof; no ground, no tile; indoor boxes and no `around`: none",
			func = function()
				local grounds, opened, peeked = {}, {}, {}

				local function build(extra)
					grounds, opened, peeked = {}, {}, {}

					local opts = options({
						around = 64,
						groundAt = function(x, y, top)
							grounds[#grounds + 1] = x .. "," .. y .. "," .. top

							if x > 400 then
								return nil -- the cell at x 448: no ground
							end

							return top - 100
						end,
						levelAt = function(x, y, z)
							opened[#opened + 1] = x .. "," .. y .. "," .. z

							if x < 300 then
								return level("open_t960")
							end

							return nil, "roofed"
						end,
						placeLevelAt = function(x, y, z)
							peeked[#peeked + 1] = x .. "," .. y .. "," .. z

							return {id = "f" .. z .. "c120", zlo = z - 56, zhi = z + 120}
						end,
						definitionsAt = function() return {4} end
					})

					for k, v in pairs(extra or {}) do
						opts[k] = v
					end

					return opts
				end

				-- 4 x 1 cells of the layer 0 (top 63): the cell centres are at x 64, 192, 320, 448; the ground a cell has is 100 under the top, -37
				local entries = run({box(0, 0, 0, 3, 0)}, build())

				for _, g in ipairs({"64,64,63", "192,64,63", "320,64,63", "448,64,63"}) do
					local found = false

					for _, asked in ipairs(grounds) do
						found = found or asked == g
					end

					expect(found).to.beTrue()
				end

				-- the open level is asked from the ground (the ray of OpenAt starts over the roof when it starts at the top of the layer), the roofed cell gets the level of a player there
				expect(text(peeked)).to.equal("320,64,-37")

				local askedOpen = {}

				for _, o in ipairs(opened) do
					askedOpen[o] = true
				end

				expect(askedOpen["64,64,-37"]).to.beTrue()
				expect(askedOpen["192,64,-37"]).to.beTrue()
				expect(askedOpen["448,64,-37"]).to.beNil() -- no ground: no level asked

				local roofed = 0

				for _, e in ipairs(entries) do
					if e.tile.level == "f-37c120" then
						roofed = roofed + 1
						expect(e.tile.ppm).to.equal(4) -- the definitions of that place, not the box's own
					end
				end

				expect(roofed >= 1).to.beTrue()

				-- an indoor box is not sampled by cells (its floors come from indoorLevelAt)
				run({box(0, 0, 0, 3, 0, 2)}, build())
				expect(#grounds).to.equal(0)

				-- no `around`: the cells are not sampled
				run({box(0, 0, 0, 3, 0)}, build({around = false}))
				expect(#grounds).to.equal(0)
				expect(#peeked).to.equal(0)
			end
		},
		{
			-- the cells are steps of the job (a box of a hundred cells in one step would freeze a frame), after the box's own areas; a plan over Preload.MAX_AROUND_CELLS cells samples every
			-- n-th cell on both axes (n the smallest whole number that brings the count under the cap), at the centres of the cells it keeps. breaks if: a box does all its cells in one
			-- step, the stride is not applied (a big map, 190000 outdoor cells on gm_boreas, would cost seconds), or the sampled cells are not centres
			name = "NewJob: each cell of an outdoor box is a step; over Preload.MAX_AROUND_CELLS cells only every n-th cell on each axis is asked",
			func = function()
				local asked = {}
				local function build()
					asked = {}

					return options({
						around = 64,
						groundAt = function(x, y, top)
							asked[#asked + 1] = x .. "," .. y

							return top - 100
						end,
						levelAt = function() return level("open_t960") end
					})
				end

				local job = P().NewJob({box(0, 0, 0, 3, 0)}, build())

				expect(job.Step(1)).to.equal(1) -- the box's own areas
				expect(#asked).to.equal(0)
				expect(job.Step(2)).to.equal(2) -- two cells
				expect(#asked).to.equal(2)
				expect(job.Done()).to.beFalse()
				expect(job.Step(100)).to.equal(2) -- the last two
				expect(job.Done()).to.beTrue()

				local saved = P().MAX_AROUND_CELLS

				P().MAX_AROUND_CELLS = 4

				local ok, err = pcall(function()
					-- 8 x 8 = 64 cells over a cap of 4: the stride is ceil(sqrt(64 / 4)) = 4: the cells 0 and 4 on each axis, centres at 64 and 576
					run({box(0, 0, 0, 7, 7)}, build())
					table.sort(asked)
					expect(text(asked)).to.equal("576,576 576,64 64,576 64,64")
				end)

				P().MAX_AROUND_CELLS = saved

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: a step does all the work whatever the count asked (a frame would freeze on a map with thousands of boxes), or the job never says it is done
			name = "NewJob: a step does at most the number of boxes asked, the job says when it is done, and the result is the same in any number of steps",
			func = function()
				local boxes = {}

				for i = 0, 9 do
					boxes[#boxes + 1] = box(0, i * 3, 0, i * 3 + 1, 0)
				end

				local job = P().NewJob(boxes, options())

				expect(job.Done()).to.beFalse()
				expect(job.Step(3)).to.equal(3)
				expect(job.Done()).to.beFalse()
				expect(job.Step(3)).to.equal(3)
				expect(job.Step(3)).to.equal(3)
				expect(job.Step(3)).to.equal(1) -- ten boxes in all
				expect(job.Done()).to.beTrue()
				expect(job.Step(3)).to.equal(0)

				local whole = run(boxes, options(), 1000)
				local pieces = run(boxes, options(), 1)

				expect(text(ids(pieces))).to.equal(text(ids(whole)))
			end
		},

		-- ------------------------------------------------------------------------------------------------------------------------------------------------
		-- the driver: it reads the settings and the in/out map, plans in steps of a frame, and hands the tiles to the generator
		-- ------------------------------------------------------------------------------------------------------------------------------------------------
		{
			-- breaks if: the preload starts when it is switched off, from a map that is not there, or without the screen constant it needs to know the definitions
			name = "driver: Start says why it does nothing (switched off, no map, no screen constant with the automatic definition) and makes no hook then",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({preload = 0})
					local started, why = P().Start()

					expect(started).to.beFalse()
					expect(why).to.equal("off")

					env.set({preload = 1, boxes = false})
					started, why = P().Start()
					expect(started).to.beFalse()
					expect(why).to.equal("no map")

					env.set({boxes = true, k = false})
					started, why = P().Start()
					expect(started).to.beFalse()
					expect(why).to.equal("no screen constant")

					expect(#env.hooks).to.equal(0)
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- the owner's three ranges (100 / 75 / 25 m) on a screen whose constant is 130 give the definitions 2 and 4: tiles of both, for the open level of the outdoor boxes
			-- breaks if: the ranges are not read from the convars (the manual one is used with the automatic zoom on), a definition is missing, or the plan is handed over before it is done
			name = "driver: with the automatic zoom the definitions come from the three ranges; the plan is made in steps of the frame hook and handed to the generator when done, then the hook goes",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, definition = 4, boxes = true})

					expect(P().Start()).to.beTrue()
					expect(#env.hooks).to.equal(1)
					expect(env.handed).to.beNil() -- nothing yet: the plan is made frame by frame

					-- drive the frame hook until it removes itself
					local frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					expect(#env.hooks).to.equal(0)
					expect(env.handed ~= nil).to.beTrue()

					local ppms = {}

					for _, e in ipairs(env.handed) do
						expect(e.tile.res).to.equal(1024)

						-- the open level of the outdoor box (the indoor box makes floor tiles of its own, see the floors cases)
						if string.sub(e.tile.level, 1, 4) == "open" then
							ppms[e.tile.ppm] = true
							expect(e.level.id).to.equal("open_t960")
						end
					end

					expect(ppms[2]).to.beTrue()
					expect(ppms[4]).to.beTrue()
					expect(ppms[8]).to.beNil()
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: with the manual definition the preload still waits for the screen constant, or uses another definition than the slider's
			name = "driver: with a manual definition the slider's definition is the only one and no screen constant is needed",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({autodef = 0, definition = 15, k = false, boxes = true})
					expect(P().Start()).to.beTrue()

					local frames = 0

					while #env.hooks > 0 and frames < 100 do
						env.frame()
						frames = frames + 1
					end

					expect(env.handed ~= nil).to.beTrue()

					for _, e in ipairs(env.handed) do
						expect(e.tile.ppm).to.equal(15)
					end
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the frame hook works in a slow frame, or does more than its small share of a frame
			name = "driver: the planning steps do nothing in a frame that follows a slow one, and Stop removes the hook and empties the generator's preload",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = true})
					expect(P().Start()).to.beTrue()

					env.set({frame = 0.08})

					local before = env.rays

					env.frame()
					expect(env.rays).to.equal(before)
					expect(#env.hooks).to.equal(1)

					env.set({frame = 0.005})
					env.frame()
					expect(env.rays > before).to.beTrue()

					P().Stop()
					expect(#env.hooks).to.equal(0)
					expect(#env.handed).to.equal(0)
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		},
		{
			-- the event comes once per accepted file and the owner changes a slider several times: one start, after a short wait. breaks if: every event or change starts a plan
			name = "driver: Schedule waits a moment and starts once however many times it is called; nothing is scheduled when the preload is off",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					env.set({preload = 1, autozoom = 1, vehicle = 100, foot = 75, indoor = 25, k = 130, boxes = true})

					P().Schedule()
					P().Schedule()
					P().Schedule()
					expect(#env.timers).to.equal(1)
					expect(#env.hooks).to.equal(0) -- not yet

					env.fireTimer()
					expect(#env.hooks).to.equal(1)

					env.set({preload = 0})
					P().Stop()
					P().Schedule()
					expect(#env.timers).to.equal(0)
				end)

				env.restore()

				if not ok then error(err, 0) end
			end
		}
	}
}
