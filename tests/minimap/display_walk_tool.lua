-- MANUAL MEASUREMENT TOOL (not a GLuaTest): what the radar MAKES and what it SHOWS while a player walks (client realm, gmod-mcp). Load preload_coverage_job.lua first
-- (COV.tour, COV.readCentres), then this file with lua_exec_file; run display_walk_job.lua as a lua_job.
--
-- A walk is SIMULATED (nothing moves the player), over the same route as the preload coverage tool (the centres of the navigation mesh, or the ground nodes of the graph) in both
-- directions. The cache is a scratch one ("zz_dl_<map>_v5": never the real folder) filled by the real preload. At each step the walk asks the real Floors.CurrentAt for the level
-- SHOWN (with the hold) and for the level of the PLACE (the second answer, or PeekAt when CurrentAt gives only one), then plays the radar:
--   * what it asks the generator for: the SHOWN level (mode "old": what the radar did before) or the level of the PLACE (mode "new"); the floor below and the outside as the radar's
--     settings say. The tiles of the window (the square of the range times the extent factor, one tile of margin) that the cache lacks are counted as MADE BY THE RADAR (they were
--     not prepared) and are then in the cache (every step is a few frames of work: the generator is supposed to be fast enough), also for the hold (TileReady reads Cache.Has);
--   * what it draws under the player: the shown level's tile if the cache has it, else (mode "new") the tile of the place's level. When neither is there the player sees the
--     VEIL (counted once per tile and level);
--   * a CHANGE OF PICTURE: the level drawn under the player differs from the previous step's (a jump between two distant places is not a change).
-- Result per direction: steps, walked units, changes (and per 1000 units), veils, tiles made by the radar by set (main, below, outside) and, for the main set, how many of
-- them lay under the player.

DW = DW or {}

local M = GryMod.Minimap

-- the scratch cache, a radar that asks nothing, the owner's screen constant and zoom (no saved setting is written); COV.finish puts everything back
function DW.scratch(opts)
	opts = opts or {}

	local Mm = GryMod.Minimap

	COV.real = COV.real or {key = Mm.Cache.Key, request = Mm.Gen.Request, pFrame = Mm.Preload._frameTime, gFrame = Mm.Gen._frameTime, screenK = Mm.Settings.ScreenConstant, convar = Mm.Preload._convar}
	COV.scratch = "zz_dl_" .. string.lower(game.GetMap()) .. "_v5"
	Mm.Cache.Key = function() return COV.scratch end
	Mm.Cache.Reset()
	Mm.Gen.Request = function() return false end
	Mm.Gen.Cancel()
	Mm.Preload.Stop()
	Mm.Cache.Clear(COV.scratch)
	Mm.Cache.Reset()
	Mm.Preload._frameTime = function() return 0.005 end
	Mm.Gen._frameTime = function() return 0.005 end

	local k = opts.k or 141.5

	Mm.Settings.ScreenConstant = function() return k end

	local realConvar = COV.real.convar

	Mm.Preload._convar = function(name)
		if name == "gry_radar_autozoom" then
			return 1
		end

		return realConvar(name)
	end
end

function DW.begin(opts)
	opts = opts or {}

	DW.scratch(opts)

	local Mm = GryMod.Minimap
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

	local maxPoints = opts.maxPoints or 3000

	if #pts > maxPoints then
		local thinned, stride = {}, #pts / maxPoints

		for i = 0, maxPoints - 1 do
			thinned[#thinned + 1] = pts[math.floor(i * stride) + 1]
		end

		pts = thinned
	end

	COV.nav = COV.tour(pts, 96, 600)

	-- the feet on the ground the way a player stands (the steps between two places are interpolated in a straight line: over a stair or a ramp they are in the air or in the floor,
	-- which makes veils that no player sees, found by the preload coverage agent on 2026-11-22): the height of the ground found by a ray down from 40 over each step (GroundAt),
	-- a step with no ground within 40 units is left out. opts.snap = false keeps the straight line.
	COV.dropped = nil

	if opts.snap ~= false then
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

	COV.t0 = SysTime()

	local ok, why = Mm.Preload.Start()

	return {points = #pts, steps = #COV.nav, dropped = COV.dropped, start = {ok, why}}
end

-- the real shot of CurrentAt and the level of the place
local function levels(F, pos)
	local shown, own = F.CurrentAt(pos)

	if not own then
		own = F.PeekAt(pos.x, pos.y, pos.z) or shown
	end

	return shown, own
end

-- DW.walk(route, mode) with mode "old", "new" or "skip" (an experiment: not what the radar does); returns the numbers described above
function DW.walk(route, mode, job, made0)
	local F, C, S, Z = M.Floors, M.Cache, M.Settings, GryMod.ZoneMapClient
	local k = S.ScreenConstant()
	local res = S.TileRes()
	local mpu = GryMod.RadarShared.METRES_PER_UNIT
	local factor = (M.View and M.View.ExtentFactor and M.View.ExtentFactor()) or GryMod.FlashRadar.MAP_EXTENT
	local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
	local indoor = GetConVar("gry_radar_zoom_indoor"):GetFloat()
	local belowOn = (S.Below and S.Below() or 0) > 0
	local outsideOn = (S.Outside and S.Outside() or 0) > 0
	local def = S.Definition()
	local startDef = def
	local made = {}

	for key0 in pairs(made0 or {}) do
		made[key0] = true
	end

	local out = {mode = mode, steps = 0, units = 0, changes = 0, veils = 0, madeMain = 0, madeMainUnder = 0, madeHeld = 0, madeBelow = 0, madeOutside = 0, heldSteps = 0, examples = {}}
	local veilSeen = {}
	local clock = 1000
	local realRT, realHas = RealTime, C.Has
	local prevDrawn, prev

	local function key(id, tx, ty, d)
		return id .. "|" .. tx .. "," .. ty .. "," .. d
	end

	C.Has = function(tile)
		if realHas(tile) then
			return true
		end

		return made[key(tile.level, tile.tx, tile.ty, tile.ppm)] == true
	end

	F.Reset()
	RealTime = function() return clock end

	local probe = {level = "", tx = 0, ty = 0, res = res, ppm = 0}

	local function has(id, tx, ty, d)
		probe.level, probe.tx, probe.ty, probe.ppm = id, tx, ty, d

		return C.Has(probe)
	end

	local ok, err = pcall(function()
		for i = 1, #route do
			local p = route[i]

			clock = clock + 0.3
			out.steps = out.steps + 1

			if prev and not p.jump then
				local dx, dy, dz = p.x - prev.x, p.y - prev.y, p.z - prev.z

				out.units = out.units + math.sqrt(dx * dx + dy * dy + dz * dz)
			end

			local pos = Vector(p.x, p.y, p.z)
			local inside = Z.Indoor(pos) == true
			local range = inside and indoor or foot

			def = S.AutoDefinitionFor(k / range, def)
			S.SetAutoDefinition(def) -- the radar does it at every draw: the hold's test of a ready tile (Floors.TileReady) reads the definition in use

			local shown, own = levels(F, pos)
			local asked = mode ~= "old" and own or shown
			local ux, uy = C.TileOf(p.x, p.y, res, def)

			if shown.id ~= own.id then
				out.heldSteps = out.heldSteps + 1

				if #out.examples < 8 then
					out.examples[#out.examples + 1] = string.format("%d,%d,%d shown %s place %s", p.x, p.y, p.z, shown.id, own.id)
				end
			end

			-- what is drawn under the player: the shown level's tile, else (new) the place's
			local drawn = shown

			if mode ~= "old" and not has(shown.id, ux, uy, def) then
				drawn = own
			end

			if not has(drawn.id, ux, uy, def) then
				local vk = key(drawn.id, ux, uy, def)

				if not veilSeen[vk] then
					veilSeen[vk] = true
					out.veils = out.veils + 1
				end
			end

			if prevDrawn and not p.jump and prevDrawn ~= drawn.id then
				out.changes = out.changes + 1
			end

			prevDrawn, prev = drawn.id, p

			-- what the radar asks for: the window of the asked level, its floor below, the outside
			local extent = range / mpu * factor
			local tx0, ty0 = C.TileOf(p.x - extent, p.y - extent, res, def)
			local tx1, ty1 = C.TileOf(p.x + extent, p.y + extent, res, def)
			local below = belowOn and F.Below(asked) or nil
			local outside = outsideOn and F.Outside(asked) or nil

			for tx = tx0 - 1, tx1 + 1 do
				for ty = ty0 - 1, ty1 + 1 do
					-- mode "skip": the place's tile is not made where the held level's tile is there (it is the one drawn)
					local wanted = not has(asked.id, tx, ty, def)

					if wanted and mode == "skip" and shown.id ~= own.id and has(shown.id, tx, ty, def) then
						wanted = false
					end

					if wanted then
						made[key(asked.id, tx, ty, def)] = true
						out.madeMain = out.madeMain + 1

						if asked.id ~= own.id then
							out.madeHeld = out.madeHeld + 1 -- a level that is not the level of the place: nothing could have prepared it
						end

						if tx == ux and ty == uy then
							out.madeMainUnder = out.madeMainUnder + 1
						end
					end

					if below and below.id ~= asked.id and not has(below.id, tx, ty, def) then
						made[key(below.id, tx, ty, def)] = true
						out.madeBelow = out.madeBelow + 1
					end

					if outside and outside.id ~= asked.id and not has(outside.id, tx, ty, def) then
						made[key(outside.id, tx, ty, def)] = true
						out.madeOutside = out.madeOutside + 1
					end
				end
			end

			if job and i % 150 == 0 then
				job:yield()
			end
		end
	end)

	RealTime = realRT
	C.Has = realHas
	S.SetAutoDefinition(startDef)
	F.Reset()

	if not ok then
		error(err)
	end

	out.units = math.floor(out.units)
	out.changesPer1000 = out.units > 0 and math.floor(out.changes * 10000 / out.units) / 10 or 0
	out.madePer1000 = out.units > 0 and math.floor((out.madeMain + out.madeBelow + out.madeOutside) * 10000 / out.units) / 10 or 0

	return out
end

function DW.reverse(route)
	local back = {}

	for i = #route, 1, -1 do
		back[#back + 1] = route[i]
	end

	return back
end

-- The tiles a preload would have made along a route: the level of the place (PeekAt) at a place every `every` units, the tiles within `radius` units of it, at the definition of the
-- walk. {key = true}, for DW.walk's `made0`.
function DW.prepare(route, every, radius)
	local F, C, S, Z = M.Floors, M.Cache, M.Settings, GryMod.ZoneMapClient
	local k = S.ScreenConstant()
	local res = S.TileRes()
	local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
	local indoor = GetConVar("gry_radar_zoom_indoor"):GetFloat()
	local def = S.Definition()
	local set, sinceLast, prev = {}, math.huge, nil

	for i = 1, #route do
		local p = route[i]

		if prev then
			local dx, dy, dz = p.x - prev.x, p.y - prev.y, p.z - prev.z

			sinceLast = sinceLast + math.sqrt(dx * dx + dy * dy + dz * dz)
		end

		prev = p

		if sinceLast >= every then
			sinceLast = 0

			local inside = Z.Indoor(Vector(p.x, p.y, p.z)) == true

			def = S.AutoDefinitionFor(k / (inside and indoor or foot), def)

			local own = F.PeekAt(p.x, p.y, p.z)
			local tx0, ty0 = C.TileOf(p.x - radius, p.y - radius, res, def)
			local tx1, ty1 = C.TileOf(p.x + radius, p.y + radius, res, def)

			for tx = tx0, tx1 do
				for ty = ty0, ty1 do
					set[own.id .. "|" .. tx .. "," .. ty .. "," .. def] = true
				end
			end
		end
	end

	return set
end

-- The recorded stairs and ramps of the map (DW_STAIRS, see the fixtures): each one walked up and down, in both modes, with a preload every 128 units (radius 256) along it.
-- Fresh scratch cache for each (the walk's own made set; the real cache is the scratch one, empty of these levels).
function DW.stairs(job, every, radius)
	local out = {}

	for name, list in pairs(DW_STAIRS) do
		local route = {}

		for i = 1, #list do
			route[i] = {x = list[i][1], y = list[i][2], z = list[i][3]}
		end

		local back = DW.reverse(route)
		local row = {}

		for _, mode in ipairs({"old", "new", "skip"}) do
			row[mode .. "_up"] = DW.walk(route, mode, job, DW.prepare(route, every or 128, radius or 256))
			row[mode .. "_down"] = DW.walk(back, mode, job, DW.prepare(back, every or 128, radius or 256))
		end

		out[name] = row
	end

	return out
end

-- one line for a result of DW.walk (the full tables are long)
function DW.line(r)
	return string.format("u=%d ch=%d (%.1f/1000) held=%d veils=%d made main=%d (held-level %d, under player %d) below=%d outside=%d", r.units, r.changes, r.changesPer1000, r.heldSteps, r.veils,
		r.madeMain, r.madeHeld, r.madeMainUnder, r.madeBelow, r.madeOutside)
end

function DW.lines(res)
	local out = {}

	for name, v in pairs(res) do
		if type(v) == "table" and v.madeMain then
			out[name] = DW.line(v)
		elseif type(v) == "table" then
			out[name] = DW.lines(v)
		else
			out[name] = v
		end
	end

	return out
end
