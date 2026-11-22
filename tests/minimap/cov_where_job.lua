-- WHERE the veils left after the preload are (lua_job, CLIENT realm; load preload_coverage_job.lua first with lua_exec_file). The same walk as cov_cause_job.lua (forward and
-- backward over the cache the preload made, the real CurrentAt with its display hold), args.points == "nav" for the centres of the navigation mesh (cov_centres_job.lua wrote
-- them). Each veil (the tile under the player missing the first time it is needed) is put in a class:
--   kind:  "open"  the level is an open level (outdoors),
--          "indoor"  the in/out map says indoors,
--          "roofed"  the in/out map says outdoors (or nothing) and the level is a slab (a roof, a porch, a door),
--   box:   the in/out map at the place: "none", "out" (outdoor, ceiling class 0), "out+roof" (outdoor with a ceiling class) or "in",
--   node:  how far the nearest ground node of the graph is (units): "<128", "<256", "<512", ">=512" or "none" (no graph),
--   other: "level differs" when the cache has a tile at the same place and definition under ANOTHER level (the place was prepared, under another level), else "nothing there".
-- Returns the counts, the plan cost and (args.list) the first veils with their position.
-- Usage: lua_exec_file this file once (it defines COV.where(args)), then lua_job {code = "return COV.where(job.args, job)", args = {...}}, or loop over several configurations in one job.

COV = COV or {}

function COV.where(args, job)
	local M = GryMod.Minimap
	local Z = GryMod.ZoneMapClient

	job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)

	local pts = (args and args.points == "nav") and COV.readCentres("grymod_tmp/" .. (args.name or ("cov_centres_" .. game.GetMap())) .. ".txt") or nil
	-- EXPERIMENT (args.ring = distance of 4 points around each ground node; args.grid = spacing in units of a grid over the indoor boxes; args.ogrid = the same over the outdoor boxes, kept
	-- when the place is under a roof): extra places given to the real plan, to see what they remove. Their making is timed apart (COV.extraMs).
	local realNewJob = M.Preload.NewJob

	COV.extraMs, COV.extraPlaces = nil, nil

	if args and (args.ring or args.grid or args.ogrid) then
		M.Preload.NewJob = function(boxes, opts)
			local t0 = SysTime()
			local extra = {}
			local Fl = M.Floors
			local a = args

			for _, p in ipairs(opts.places) do
				extra[#extra + 1] = p
			end

			if a.ring then
				local d = a.ring

				for _, p in ipairs(opts.places) do
					for _, o in ipairs(a.ring8 and {{d, 0}, {-d, 0}, {0, d}, {0, -d}, {d, d}, {-d, d}, {d, -d}, {-d, -d}} or {{d, 0}, {-d, 0}, {0, d}, {0, -d}}) do
						local g = Fl.GroundAt(p.x + o[1], p.y + o[2], p.z + 48)

						if g then
							extra[#extra + 1] = {x = p.x + o[1], y = p.y + o[2], z = g}
						end
					end
				end
			end

			for _, mode in ipairs({{"grid", 2}, {"ogrid", 1}}) do
				local u = a[mode[1]]

				if u then
					for _, box in ipairs(boxes) do
						if box.state == mode[2] then
							local top = box.layer * 128 + 63

							for x = box.x1 * 128 + u / 2, (box.x2 + 1) * 128, u do
								for y = box.y1 * 128 + u / 2, (box.y2 + 1) * 128, u do
									local g = Fl.GroundAt(x, y, top)

									if g and (mode[2] == 2 or not Fl.OpenAt(x, y, g)) then
										extra[#extra + 1] = {x = x, y = y, z = g}
									end
								end
							end
						end
					end
				end
			end

			opts.places = extra
			COV.extraMs = (SysTime() - t0) * 1000
			COV.extraPlaces = #extra

			return realNewJob(boxes, opts)
		end
	end

	COV.around = args and args.around

	local begun = COV.begin({points = pts, snap = args and args.snap, maxPoints = args and args.maxPoints})
	local G = M.Gen

	job:sleep(2)
	job:wait(function()
		local p = G.PreloadProgress()

		return p and p.total and p.total > 0 and G.Pending() == 0 and (p.done or 0) + (p.failed or 0) >= p.total
	end, 1500)

	local F, C, S = M.Floors, M.Cache, M.Settings
	local k = S.ScreenConstant()
	local res = S.TileRes()
	local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
	local indoor = GetConVar("gry_radar_zoom_indoor"):GetFloat()
	local defsList = {2, 4, 8, 16, 32, 64}
	local known = C.KnownLevels()

	local nodes = {}
	local graph = GryMod.AIN.Load(game.GetMap())

	for _, n in ipairs(graph and graph.nodes or {}) do
		if n.type == 2 then
			nodes[#nodes + 1] = n
		end
	end

	-- the box of the in/out map at the place: "none", "out" (outdoor, open sky: ceiling class 0), "out+roof" (outdoor with a ceiling class: a porch, an overhang) or "in"
	local function boxClass(pos)
		local _, _, _, _, _, _, state, ceil = Z.BoxAt(pos)

		if not state then
			return "none"
		end

		return state == 2 and "in" or (ceil or 0) > 0 and "out+roof" or "out"
	end

	local function nodeBin(p)
		if #nodes == 0 then
			return "none"
		end

		local best = math.huge

		for i = 1, #nodes do
			local n = nodes[i]
			local dx, dy, dz = n.x - p.x, n.y - p.y, n.z - p.z
			local d = dx * dx + dy * dy + dz * dz

			if d < best then
				best = d
			end
		end

		best = math.sqrt(best)

		return best < 128 and "<128" or best < 256 and "<256" or best < 512 and "<512" or ">=512"
	end

	local function walk(route)
		local seen = {}
		local out = {}
		local def = S.Definition()
		local clock = 1000
		local realRT = RealTime

		F.Reset()
		RealTime = function() return clock end

		local ok, err = pcall(function()
			for i = 1, #route do
				local p = route[i]

				clock = clock + 0.3

				local pos = Vector(p.x, p.y, p.z)
				local inside = Z.Indoor(pos) == true

				def = S.AutoDefinitionFor(k / (inside and indoor or foot), def)

				local level = F.CurrentAt(pos)
				local ux, uy = C.TileOf(p.x, p.y, res, def)
				local key = level.id .. "|" .. ux .. "," .. uy .. "," .. def

				if not seen[key] then
					seen[key] = true

					if not C.Has({level = level.id, tx = ux, ty = uy, res = res, ppm = def}) then
						local others = 0

						for _, id in ipairs(known) do
							if id ~= level.id and C.Has({level = id, tx = ux, ty = uy, res = res, ppm = def}) then
								others = others + 1
							end
						end

						out[#out + 1] = {
							x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z), level = level.id,
							kind = level.open and "open" or inside and "indoor" or "roofed",
							box = boxClass(pos),
						node = nodeBin(p), other = others > 0 and "level differs" or "nothing there", def = def
						}
					end
				end

				if i % 100 == 0 then
					job:yield()
				end
			end
		end)

		RealTime = realRT
		F.Reset()

		if not ok then
			error(err)
		end

		return out
	end

	local route = COV.nav
	local back = {}

	for i = #route, 1, -1 do
		back[#back + 1] = route[i]
	end

	local result = COV.result()

	result.examples = nil
	result.why = nil

	local function summary(list)
		local s = {total = #list, kind = {}, node = {}, other = {}, levels = {}, box = {}}

		for _, v in ipairs(list) do
			s.kind[v.kind] = (s.kind[v.kind] or 0) + 1
			s.node[v.node] = (s.node[v.node] or 0) + 1
		s.box[v.box] = (s.box[v.box] or 0) + 1
			s.other[v.other] = (s.other[v.other] or 0) + 1
			s.levels[v.level] = (s.levels[v.level] or 0) + 1
		end

		local n = 0

		for _ in pairs(s.levels) do
			n = n + 1
		end

		s.levels = n

		return s
	end

	local fwd = walk(route)
	local bwd = walk(back)
	local out = {begun = begun, result = result, forward = summary(fwd), backward = summary(bwd)}

	if args and args.list then
		out.list = {}

		for i = 1, math.min(#fwd, tonumber(args.list) or 60) do
			out.list[i] = fwd[i]
		end
	end

	COV.finish()
	COV.around = nil
	M.Preload.NewJob = realNewJob
	out.extraMs = COV.extraMs and math.floor(COV.extraMs)
	out.places = COV.extraPlaces

	return out
end
