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
-- outdoor and an indoor box, false: no map), frame (the last frame's duration). env.restore() puts everything back (a case always calls it, also after a failure).
local function makeEnv()
	local M = GryMod.Minimap
	local P0 = M.Preload
	local env = {hooks = {}, timers = {}, handed = nil, rays = 0, peeks = 0, grounds = 0}
	local saved = {Settings = M.Settings, Cache = M.Cache, Gen = M.Gen, Floors = M.Floors, Zone = GryMod.ZoneMapClient, AIN = GryMod.AIN}
	local savedFields = {}

	for _, k in ipairs({"_hookAdd", "_hookRemove", "_timerCreate", "_timerRemove", "_convar", "_frameTime", "_clock", "_origin"}) do
		savedFields[k] = P0[k]
	end

	local v = {preload = 1, autozoom = 0, vehicle = 100, foot = 75, indoor = 25, range = 25, k = 130, definition = 4, autodef = 1, boxes = true, frame = 0.005, nodes = {}}

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
			-- The level of a place is "the usable anchor of the biggest class among those known": it depends on which anchors the registry holds when the place is asked. At the start of
			-- a plan it holds few, at the end all of them, and a player arriving later gets the choice of the complete registry. Measured on gm_everpine_mall: the floors left missing were
			-- places prepared under a level chosen early. breaks if: the plan is made once (the early places are named with an incomplete registry), or the tiles of the first pass are handed over too
			name = "driver: the plan is made in two passes over the same places (the first fills the registry of levels, the second asks again with the complete one) and only the second pass's tiles are handed over",
			func = function()
				local env = makeEnv()

				local ok, err = pcall(function()
					-- a PeekAt whose answer depends on how many places it has seen: the first pass answers "early", the second "late" (as the registry fills)
					local seenPlaces = 0
					GryMod.Minimap.Floors.PeekAt = function(x, y, z)
						seenPlaces = seenPlaces + 1

						return {id = seenPlaces <= 2 and "early" or "late", zlo = z - 56, zhi = z + 120}
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

					local seen = {}

					for _, e in ipairs(env.handed) do
						seen[e.tile.level] = true
					end

					expect(seenPlaces).to.equal(4) -- two places, two passes
					expect(seen.late).to.beTrue() -- what the complete registry says
					expect(seen.early).to.beNil() -- what the first pass said is not handed over
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
					placeLevelAt = function() return {id = "f0c120", zlo = -56, zhi = 120} end
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
					-- the air node made no place; the plan is made in two passes (see the next case), so each of the two places is asked twice
					expect(env.peeks).to.equal(4)

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
