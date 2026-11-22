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
