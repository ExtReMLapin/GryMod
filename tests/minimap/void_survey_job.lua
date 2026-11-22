-- MANUAL MEASUREMENT TOOL (not a GLuaTest): what the engine writes in the alpha of a captured tile, to check the rule "alpha 255 is the background of the engine".
-- CLIENT realm, run as a gmod-mcp lua_job (the capture needs a render hook: each capture is made inside a PostRender hook, one per frame). Nothing is stored in the cache.
--
-- args:
--   res (1024), ppm (4)          the tile definition
--   tiles = {{tx, ty, id}, ...}   tiles by their index and their level id "c<top>t<thickness>" (for example {0, -1, "cn7360t192"}: top -7360, thickness 192)
--   points = {{x, y, z}, ...}     or world positions: the tile around the point and the level the radar would use there (Floors.PeekAt)
--   stride (3)                    one pixel in `stride` is read, in both directions
--   random = {n, seed, around = {x, y, z, radius}}   n places found by traces (see below); `around` limits the box (default: the bounds of the world)
--   compact = false              return a table per capture instead of one line
--   summary = true               return only the totals and the captures with more than 0.2 % of alpha-255 pixels that are not of the most frequent colour
--   keep = true                   keep the pictures (BGRA strings, one per capture) in _G.VOID_SURVEY, to look at them with another job
-- Result, for each capture: the number of sampled pixels by alpha class (a0: alpha 0, a1: alpha 1, mid: 2..254, a255), and for the alpha-255 pixels the colours they carry
-- (the three most frequent, and `other255`: how many alpha-255 pixels are NOT of the most frequent one), plus `solid255Share` (what share of the pixels is alpha 255) and `ms` (time of the render).
-- The question it answers: is alpha 255 always the SAME colour (the background the engine paints where nothing is drawn: the sky colour, the fog colour, black), or does
-- geometry write 255 too (then there are several colours)? Measured on 2026-11-22 (docs/minimap.md, Known traps): one fill colour per picture, a few other colours
-- at the edges of translucent geometry (0.01 to 0.7 % of the alpha-255 pixels).

local Capture = GryMod.Minimap.Capture
local Cache = GryMod.Minimap.Cache
local res, ppm = args.res or 1024, args.ppm or 4
local stride = args.stride or 3

assert(Capture and Capture.Render, "the capture module is not loaded")

local function levelFromId(id)
	local top, thick = string.match(id, "^c(n?%d+)t(%d+)$")

	assert(top, "bad level id " .. tostring(id))

	top = top:sub(1, 1) == "n" and -tonumber(top:sub(2)) or tonumber(top)
	thick = tonumber(thick)

	return {id = id, top = top, thick = thick, z = top - thick, zlo = top - thick, zhi = top}
end

local jobs = {}

for _, t in ipairs(args.tiles or {}) do
	jobs[#jobs + 1] = {tile = {level = t[3], tx = t[1], ty = t[2], res = res, ppm = ppm}, level = levelFromId(t[3]), label = "tile " .. t[1] .. "," .. t[2] .. " " .. t[3]}
end

for _, p in ipairs(args.points or {}) do
	local level = GryMod.Minimap.Floors.PeekAt(p[1], p[2], p[3])
	local tx, ty = Cache.TileOf(p[1], p[2], res, ppm)

	assert(level and tx, "no level or tile for a point")

	jobs[#jobs + 1] = {tile = {level = level.id, tx = tx, ty = ty, res = res, ppm = ppm}, level = level, label = string.format("point %d,%d,%d %s", p[1], p[2], p[3], level.id)}
end

-- args.random = {n = 16, seed = 1}: n places of the map found by traces from random points of the world bounds (a floor that is not sky), as `points`
if args.random then
	local mn, mx = game.GetWorld():GetModelBounds()
	local found, tries = 0, 0

	-- around = {x, y, z, radius}: only the places within that box of the player's side of the map (the skybox of a map is far above its playable part)
	local around = args.random.around

	if around then
		mn = Vector(around[1] - around[4], around[2] - around[4], around[3] - around[4])
		mx = Vector(around[1] + around[4], around[2] + around[4], around[3] + around[4])
	end

	math.randomseed(args.random.seed or 1)

	while found < (args.random.n or 16) and tries < 6000 do
		tries = tries + 1

		local x, y, z = math.random(mn.x, mx.x), math.random(mn.y, mx.y), math.random(mn.z, mx.z)
		local from = Vector(x, y, z)

		if bit.band(util.PointContents(from), CONTENTS_SOLID) == 0 then
			local tr = util.TraceLine({start = from, endpos = Vector(x, y, z - 400), mask = MASK_SOLID_BRUSHONLY})

			if tr.Hit and not tr.HitSky and tr.HitNormal.z > 0.7 then
				local px, py, pz = math.floor(x), math.floor(y), math.floor(tr.HitPos.z) + 1
				local level = GryMod.Minimap.Floors.PeekAt(px, py, pz)
				local tx, ty = Cache.TileOf(px, py, res, ppm)

				if level and tx then
					found = found + 1
					jobs[#jobs + 1] = {tile = {level = level.id, tx = tx, ty = ty, res = res, ppm = ppm}, level = level, label = string.format("point %d,%d,%d %s", px, py, pz, level.id)}
				end
			end
		end
	end
end

local sbyte = string.byte
local results = {}
local kept = args.keep and {} or nil
_G.VOID_SURVEY = kept

local function analyse(bytes)
	local a0, a1, mid, a255 = 0, 0, 0, 0
	local colours, ndistinct = {}, 0
	local sampled = 0

	for y = 0, res - 1, stride do
		local base = y * res * 4 + 1

		for x = 0, res - 1, stride do
			local i = base + x * 4
			local b, g, r, a = sbyte(bytes, i, i + 3)

			sampled = sampled + 1

			if a == 0 then
				a0 = a0 + 1
			elseif a == 1 then
				a1 = a1 + 1
			elseif a == 255 then
				a255 = a255 + 1

				local key = b * 65536 + g * 256 + r
				local c = colours[key]

				if c then
					c.n = c.n + 1
				else
					ndistinct = ndistinct + 1
					colours[key] = {n = 1, rgb = r .. "," .. g .. "," .. b}
				end
			else
				mid = mid + 1
			end
		end

		job:step()
	end

	-- the most frequent colour of the alpha-255 pixels (the background, if the rule holds) and what is not that colour
	local modal
	local list = {}

	for _, c in pairs(colours) do
		list[#list + 1] = c

		if not modal or c.n > modal.n then
			modal = c
		end
	end

	table.sort(list, function(p, q) return p.n > q.n end)

	local top = {}

	for k = 1, math.min(3, #list) do
		top[k] = list[k].rgb .. " x" .. list[k].n
	end

	return {sampled = sampled, a0 = a0, a1 = a1, mid = mid, a255 = a255, solid255Share = a255 / sampled, ndistinct = ndistinct, colours255 = top, other255 = modal and (a255 - modal.n) or 0}
end

for k, j in ipairs(jobs) do
	local done, bytes, why, ms

	hook.Add("PostRender", "gry_void_survey", function()
		hook.Remove("PostRender", "gry_void_survey")

		local t0 = SysTime()

		bytes, why = Capture.Render(j.tile, j.level)
		ms = (SysTime() - t0) * 1000

		done = true
	end)

	job:wait(function() return done end, 20)

	if not bytes then
		results[k] = {label = j.label, error = tostring(why)}
	else
		local r = analyse(bytes)

		r.label, r.ms = j.label, ms
		-- one short line per capture (args.compact, default true): easier to read for twenty tiles
		if args.compact ~= false then
			r = string.format("%s | a0 %d a1 %d mid %d a255 %d (%.0f%%) | %d colour(s), top: %s | not the modal colour: %d | %.1f ms", r.label, r.a0, r.a1, r.mid, r.a255, 100 * r.solid255Share, r.ndistinct, table.concat(r.colours255, "; "), r.other255, r.ms)
		end

		results[k] = r

		if kept then
			kept[k] = bytes
		end
	end

	job:progress(k, #jobs, j.label)
end

if args.summary then
	-- args.summary = true: the totals and only the captures where the pixels that are not of the most frequent alpha-255 colour are more than 0.2 % of the alpha-255 pixels
	local sum = {captures = #results, withA255 = 0, strayPixels = 0, a255Pixels = 0, worst = {}}

	for k, r in ipairs(results) do
		local line = type(r) == "string" and r or r.label
		local a255, other = tonumber(string.match(line, "a255 (%d+)")) or 0, tonumber(string.match(line, "modal colour: (%d+)")) or 0

		if a255 > 0 then
			sum.withA255 = sum.withA255 + 1
			sum.a255Pixels = sum.a255Pixels + a255
			sum.strayPixels = sum.strayPixels + other

			if other / a255 > 0.002 then
				sum.worst[#sum.worst + 1] = line
			end
		end
	end

	return sum
end

return results
