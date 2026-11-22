-- MANUAL MEASUREMENT TOOL (not a GLuaTest): how much of the tile preload helps a walk. Client realm, with gmod-mcp: lua_exec_file this file, then
--   COV.routeData = COV.route(96, 600)          -- a tour over the ground nodes of the graph (96-unit steps, jumps over 600 units)
--   COV.routeData = COV.tour(points, 96, 600)    -- or over any points {x, y, z}, e.g. the centres of the navigation mesh areas (server realm: navmesh.GetAllNavAreas()) so the walk does not use the preload's own places
--   COV.eval(COV.routeData)                      -- the walk against the cache as it is NOW
-- Method used on 2026-11-22 (results in docs/superpowers/plans/2026-11-22-preload-coverage-results.md): point the cache at a scratch folder (replace GryMod.Minimap.Cache.Key by a
-- function returning "zz_coverage_<map>_v4", then Cache.Reset()), make the radar ask for nothing (replace GryMod.Minimap.Gen.Request by a function returning false, so the radar's own
-- tiles do not mix with the preload's), measure with an empty cache (baseline), run GryMod.Minimap.Preload.Start() and wait until Gen.PreloadProgress() is done, measure again; then put
-- everything back (Gen.Cancel, Cache.Clear the scratch key, the original Key and Request, Cache.Reset). The game must run fast (the preload waits after a frame slower than 25 ms:
-- fps_max_nofocus at 35 blocks it). The walk is SIMULATED: nothing moves the player. The number that matters to the player is veilEventsUnderPlayer (the tile under the feet missing);
-- the other misses include the tiles of the radar's window that hold nothing (empty tiles), which are not seen.

-- Coverage measurement of the tile preload (temporary, not part of the addon). A walk is SIMULATED: no player moves. For each position of a route over the ground nodes of
-- the map's node graph it asks the real Floors.CurrentAt for the level and computes, with the real tile geometry of Cache, the tiles the radar would ask for (the window of Gen.Request:
-- the square of the range times the extent factor, plus one tile of margin), at the definition the automatic rule gives for the mode (indoors: the indoor range, else the foot range).
-- A tile that is not in the cache the first time it is needed is a MISS (it would be made lazily, and the tile under the player would show the veil). Nothing is stored.

COV = COV or {}

local M = GryMod.Minimap

-- a tour over `pts` ({x, y, z} each): nearest neighbour first, walking steps of `step` units between places that are at most `hop` apart, a jump otherwise
function COV.tour(pts, step, hop)
	local used, route = {}, {}
	local cur = 1

	used[1] = true
	route[1] = {x = pts[1].x, y = pts[1].y, z = pts[1].z, jump = true}

	for _ = 2, #pts do
		local best, bd = nil, math.huge

		for j = 1, #pts do
			if not used[j] then
				local dx, dy, dz = pts[j].x - pts[cur].x, pts[j].y - pts[cur].y, pts[j].z - pts[cur].z
				local d = dx * dx + dy * dy + dz * dz

				if d < bd then
					best, bd = j, d
				end
			end
		end

		used[best] = true

		local a, b = pts[cur], pts[best]
		local dist = math.sqrt(bd)

		if dist <= hop then
			local n = math.max(1, math.floor(dist / step))

			for k = 1, n do
				local t = k / n

				route[#route + 1] = {x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t}
			end
		else
			route[#route + 1] = {x = b.x, y = b.y, z = b.z, jump = true}
		end

		cur = best
	end

	return route
end

-- a tour over the ground nodes of the node graph
function COV.route(step, hop)
	local graph = GryMod.AIN.Load(game.GetMap())
	local pts = {}

	for _, n in ipairs(graph.nodes) do
		if n.type == 2 then
			pts[#pts + 1] = {x = n.x, y = n.y, z = n.z}
		end
	end

	return COV.tour(pts, step, hop)
end

-- the walk against the cache as it is now
function COV.eval(route)
	local F, C, S, Z = M.Floors, M.Cache, M.Settings, GryMod.ZoneMapClient
	local k = S.ScreenConstant()
	local res = S.TileRes()
	local mpu = GryMod.RadarShared.METRES_PER_UNIT
	local factor = (M.View and M.View.ExtentFactor and M.View.ExtentFactor()) or GryMod.FlashRadar.MAP_EXTENT
	local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
	local indoor = GetConVar("gry_radar_zoom_indoor"):GetFloat()
	local def = S.Definition()
	local seen = {}
	local st = {steps = 0, tiles = 0, hit = {open = 0, floor = 0}, miss = {open = 0, floor = 0}, veil = 0, veilOpen = 0, veilFloor = 0, levels = {}, defs = {}, indoorSteps = 0}
	local clock = 1000
	local realRT = RealTime

	F.Reset()
	RealTime = function() return clock end

	local ok, err = pcall(function()
		for _, p in ipairs(route) do
			clock = clock + 0.3
			st.steps = st.steps + 1

			local pos = Vector(p.x, p.y, p.z)
			local inside = Z.Indoor(pos) == true
			local range = inside and indoor or foot

			if inside then
				st.indoorSteps = st.indoorSteps + 1
			end

			def = S.AutoDefinitionFor(k / range, def)
			st.defs[def] = (st.defs[def] or 0) + 1

			local level = F.CurrentAt(pos)
			local kind = level.open and "open" or "floor"
			local extent = range / mpu * factor
			local tx0, ty0 = C.TileOf(p.x - extent, p.y - extent, res, def)
			local tx1, ty1 = C.TileOf(p.x + extent, p.y + extent, res, def)
			local ux, uy = C.TileOf(p.x, p.y, res, def)

			st.levels[level.id] = true

			for tx = tx0 - 1, tx1 + 1 do
				for ty = ty0 - 1, ty1 + 1 do
					local key = level.id .. "|" .. tx .. "," .. ty .. "," .. def

					if not seen[key] then
						seen[key] = true
						st.tiles = st.tiles + 1

						local has = C.Has({level = level.id, tx = tx, ty = ty, res = res, ppm = def})

						if has then
							st.hit[kind] = st.hit[kind] + 1
						else
							st.miss[kind] = st.miss[kind] + 1

							if tx == ux and ty == uy then
								st.veil = st.veil + 1
								st[kind == "open" and "veilOpen" or "veilFloor"] = st[kind == "open" and "veilOpen" or "veilFloor"] + 1
							end
						end
					end
				end
			end
		end
	end)

	RealTime = realRT
	F.Reset()

	if not ok then
		return {error = tostring(err)}
	end

	local nl = 0

	for _ in pairs(st.levels) do
		nl = nl + 1
	end

	local missTotal = st.miss.open + st.miss.floor

	return {
		steps = st.steps,
		indoorSteps = st.indoorSteps,
		levels = nl,
		definitions = st.defs,
		tilesRequired = st.tiles,
		hitOpen = st.hit.open, hitFloor = st.hit.floor,
		missOpen = st.miss.open, missFloor = st.miss.floor,
		missShare = st.tiles > 0 and math.floor(missTotal * 1000 / st.tiles) / 10 or 0,
		veilEventsUnderPlayer = st.veil, veilOpen = st.veilOpen, veilFloor = st.veilFloor
	}
end

-- WHY each tile under the player was missing after the preload (the owner's question, 2026-11-22). Same walk as COV.eval; for each tile that is under the player the first time and is not in
-- the cache, it says which of these holds, in this order:
--   "level differs": the cache has a tile at the same place and definition for ANOTHER level (the preload prepared the place, but under another level id: the stairs problem);
--   "definition differs": the cache has this level at this place, but at another definition (the mode / range the preload guessed was not the one the walk used);
--   "no node near": nothing at this place, and no ground node of the graph within 300 units (the floors are made around the nodes, 256 units), so nothing could have been asked;
--   "node near, other level": nothing at this place under any level or definition although a node is near (the node's own level is given: why it was not the same);
-- plus, for every case, the box of the in/out map at the place (none, indoor or outdoor) and the nearest node's distance and level.
-- Returns {counts = {...}, examples = {first ones with the ids}}.
function COV.why(route, maxExamples)
	local F, C, S, Z = M.Floors, M.Cache, M.Settings, GryMod.ZoneMapClient
	local k = S.ScreenConstant()
	local res = S.TileRes()
	local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
	local indoorRange = GetConVar("gry_radar_zoom_indoor"):GetFloat()
	local defs = {2, 4, 8, 16, 32, 64}
	local def = S.Definition()
	local graph = GryMod.AIN.Load(game.GetMap())
	local nodes = {}

	for _, n in ipairs(graph.nodes) do
		if n.type == 2 then
			nodes[#nodes + 1] = n
		end
	end

	local seen, counts, examples = {}, {}, {}
	local clock = 1000
	local realRT = RealTime

	F.Reset()
	RealTime = function() return clock end

	local known = C.KnownLevels()

	local ok, err = pcall(function()
		for _, p in ipairs(route) do
			clock = clock + 0.3

			local pos = Vector(p.x, p.y, p.z)
			local inside = Z.Indoor(pos) == true

			def = S.AutoDefinitionFor(k / (inside and indoorRange or foot), def)

			local level = F.CurrentAt(pos)
			local tx, ty = C.TileOf(p.x, p.y, res, def)
			local key = level.id .. "|" .. tx .. "," .. ty .. "," .. def

			if not seen[key] then
				seen[key] = true

				if not C.Has({level = level.id, tx = tx, ty = ty, res = res, ppm = def}) then
					local reason
					local otherLevels, otherDefs = {}, {}

					for _, id in ipairs(known) do
						if id ~= level.id and C.Has({level = id, tx = tx, ty = ty, res = res, ppm = def}) then
							otherLevels[#otherLevels + 1] = id
						end
					end

					for _, d in ipairs(defs) do
						if d ~= def and C.Has({level = level.id, tx = tx, ty = ty, res = res, ppm = d}) then
							otherDefs[#otherDefs + 1] = d
						end
					end

					local near, nd = nil, math.huge

					for _, n in ipairs(nodes) do
						local dx, dy, dz = n.x - p.x, n.y - p.y, n.z - p.z
						local d2 = dx * dx + dy * dy + dz * dz

						if d2 < nd then
							near, nd = n, d2
						end
					end

					nd = math.sqrt(nd)

					if #otherLevels > 0 then
						reason = "level differs"
					elseif #otherDefs > 0 then
						reason = "definition differs"
					elseif nd > 300 then
						reason = "no node near"
					else
						reason = "node near, other level"
					end

					counts[reason] = (counts[reason] or 0) + 1

					if #examples < (maxExamples or 12) then
						local nodeLevel = near and F.PeekAt(near.x, near.y, near.z)

						examples[#examples + 1] = {
							reason = reason,
							level = level.id, open = level.open or false, def = def, indoor = inside,
							pos = math.floor(p.x) .. "," .. math.floor(p.y) .. "," .. math.floor(p.z),
							nearestNode = near and (math.floor(nd) .. " units, level " .. tostring(nodeLevel and nodeLevel.id)) or "none",
							preparedHereUnderOtherLevels = table.concat(otherLevels, " "),
							preparedHereAtOtherDefinitions = table.concat(otherDefs, " ")
						}
					end
				end
			end
		end
	end)

	RealTime = realRT
	F.Reset()

	if not ok then
		return {error = tostring(err)}
	end

	return {counts = counts, examples = examples}
end

-- ---------------------------------------------------------------------------------------------------------------------------------------
-- One map from start to finish (the exploration of 2026-11-22, a test client that is not the owner's game):
--   server:  navmesh centres to a file (see COV.readCentres), or nothing when the map has no navigation mesh;
--   client:  COV.begin{points = COV.readCentres(), k = 141.5}  -- scratch cache, a radar that asks nothing, frame guards off (a test client runs at 20 fps), baseline, then the preload starts
--            (wait until GryMod.Minimap.Gen.Pending() == 0 and PreloadProgress().total > 0, or the plan found nothing)
--            COV.result()                                     -- the same walk after the preload, and the why
--            COV.finish()                                     -- everything back, the scratch folder deleted
function COV.readCentres(path)
	local text = file.Read(path or "grymod_tmp/centres.txt", "DATA")
	local pts = {}

	if text then
		for x, y, z in string.gmatch(text, "(-?%d+),(-?%d+),(-?%d+)") do
			pts[#pts + 1] = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
		end
	end

	return pts
end

function COV.begin(opts)
	opts = opts or {}

	local Mm = GryMod.Minimap

	COV.real = COV.real or {key = Mm.Cache.Key, request = Mm.Gen.Request, pFrame = Mm.Preload._frameTime, gFrame = Mm.Gen._frameTime, screenK = Mm.Settings.ScreenConstant, convar = Mm.Preload._convar}
	COV.scratch = "zz_cov_" .. string.lower(game.GetMap()) .. "_v4"
	Mm.Cache.Key = function() return COV.scratch end
	Mm.Cache.Reset()
	Mm.Gen.Request = function() return false end
	Mm.Gen.Cancel()
	Mm.Preload.Stop()
	Mm.Cache.Clear(COV.scratch)
	Mm.Cache.Reset()
	Mm.Preload._frameTime = function() return 0.005 end
	Mm.Gen._frameTime = function() return 0.005 end

	-- the owner's setup, without writing any saved setting: a screen constant of his 4K screen (the radar of a small test window records another one at every draw), and the
	-- automatic zoom on with his ranges (the convars are read through Preload._convar)
	local k = opts.k or 141.5

	Mm.Settings.ScreenConstant = function() return k end

	local realConvar = COV.real.convar

	Mm.Preload._convar = function(name)
		if name == "gry_radar_autozoom" then
			return 1
		end

		-- COV.around (0 / 1): the ring of places around the nodes forced on or off for a run; nil: the player's own setting
		if name == "gry_minimap_preload_around" and COV.around ~= nil then
			return COV.around
		end

		return realConvar(name)
	end

	local pts = opts.points

	if not pts or #pts == 0 then
		pts = {}

		local graph = GryMod.AIN.Load(game.GetMap())

		for _, n in ipairs(graph and graph.nodes or {}) do
			if n.type == 2 then
				pts[#pts + 1] = {x = n.x, y = n.y, z = n.z}
			end
		end
	end

	if #pts == 0 then
		return {error = "no points (no navigation mesh centres and no graph)"}
	end

	-- the tour is O(n^2): a map with a huge navigation mesh is sampled (every k-th point, in the order of the list, which follows the mesh's own order)
	local maxPoints = opts.maxPoints or 3000

	if #pts > maxPoints then
		local thinned, stride = {}, #pts / maxPoints

		for i = 0, maxPoints - 1 do
			thinned[#thinned + 1] = pts[math.floor(i * stride) + 1]
		end

		pts = thinned
	end

	COV.dropped = nil
	COV.nav = COV.tour(pts, 96, 600)

	-- opts.snap: the feet go on the ground the way a player stands. The steps between two places are interpolated in a straight line, so over a stair or a ramp they are in the air or
	-- in the floor: each step takes the height of the ground found by a ray down from 40 over it (GroundAt), and a step with no ground within 40 units is left out
	if opts.snap then
		local snapped, dropped = {}, 0

		for _, p in ipairs(COV.nav) do
			local g = Mm.Floors.GroundAt(p.x, p.y, p.z + 40)

			if g and math.abs(g - p.z) <= 40 then
				snapped[#snapped + 1] = {x = p.x, y = p.y, z = g, jump = p.jump}
			else
				dropped = dropped + 1
			end
		end

		COV.nav = snapped
		COV.dropped = dropped
	end

	COV.base = COV.eval(COV.nav)

	-- the cost of the plan: the Think hook of the planning is timed (the whole plan, the frames it took, the slowest frame)
	COV.plan = {ms = 0, frames = 0, maxMs = 0, lastMs = 0, maxBeforeLastMs = 0, prevMs = 0}
	COV.realHookAdd = COV.realHookAdd or Mm.Preload._hookAdd

	Mm.Preload._hookAdd = function(event, name, fn)
		if event ~= "Think" then
			return COV.realHookAdd(event, name, fn)
		end

		return COV.realHookAdd(event, name, function(...)
			local t = SysTime()
			local mem = collectgarbage("count")

			fn(...)

			local ms = (SysTime() - t) * 1000

			-- a slow frame during which the memory went DOWN had a garbage collection step in it (the memory is the heap of the whole Lua state)
			if ms > COV.plan.maxMs then
				COV.plan.maxMemDelta = collectgarbage("count") - mem
			end

			COV.plan.ms, COV.plan.frames = COV.plan.ms + ms, COV.plan.frames + 1
			COV.plan.lastMs = ms

			if ms > COV.plan.maxMs then
				COV.plan.maxMs = ms
			end

			-- the frame before this one (the last frame is the one that sorts the tiles and hands them to the generator: it is told apart)
			if COV.plan.prevMs > COV.plan.maxBeforeLastMs then
				COV.plan.maxBeforeLastMs = COV.plan.prevMs
			end

			COV.plan.prevMs = ms
		end)
	end

	local ok, why = Mm.Preload.Start()

	COV.t0 = SysTime()

	return {points = #pts, steps = #COV.nav, dropped = COV.dropped, baseline = {veil = COV.base.veilEventsUnderPlayer, open = COV.base.veilOpen, floor = COV.base.veilFloor, levels = COV.base.levels}, start = {ok, why}}
end

function COV.result()
	local e = COV.eval(COV.nav)
	local w = COV.why(COV.nav, 4)
	local prog = M.Gen.PreloadProgress()

	return {
		planMs = math.floor(COV.plan.ms * 10) / 10, planFrames = COV.plan.frames, planMaxFrameMs = math.floor(COV.plan.maxMs * 100) / 100, planLastFrameMs = math.floor(COV.plan.lastMs * 100) / 100, planSlowestFrameMemDeltaKb = COV.plan.maxMemDelta and math.floor(COV.plan.maxMemDelta), planMaxOtherFrameMs = math.floor(COV.plan.maxBeforeLastMs * 100) / 100,
		preloadTiles = prog.total, preloadFailed = prog.failed, seconds = math.floor((SysTime() - COV.t0) * 10) / 10,
		veilBefore = COV.base.veilEventsUnderPlayer, veilAfter = e.veilEventsUnderPlayer, openAfter = e.veilOpen, floorAfter = e.veilFloor, levels = e.levels,
		why = w.counts, examples = w.examples
	}
end

function COV.finish()
	local Mm = GryMod.Minimap

	Mm.Gen.Cancel()
	Mm.Preload.Stop()

	if COV.real then
		Mm.Gen.Request = COV.real.request
		Mm.Preload._frameTime = COV.real.pFrame
		Mm.Gen._frameTime = COV.real.gFrame
		Mm.Settings.ScreenConstant = COV.real.screenK
		Mm.Preload._convar = COV.real.convar
		-- only when COV.begin wrapped it: the display walk (DW.begin) never does, and an assignment of nil would leave the preload without its hook function (found 2026-11-22)
		Mm.Preload._hookAdd = COV.realHookAdd or Mm.Preload._hookAdd
		Mm.Cache.Clear(COV.scratch)
		Mm.Cache.Key = COV.real.key
		Mm.Cache.Reset()
	end

	Mm.Floors.Reset()
end
