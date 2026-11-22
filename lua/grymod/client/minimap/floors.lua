-- GryMod minimap: module floors. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}

-- Floors (levels) of a map. A level is {id, zlo, zhi}: a slab of heights drawn as one picture of the map. Two sources:
--
--   1) What the minimap draws (Current, Fallback): a slab that follows the height of the player's FEET, in steps of 32 units (ids "z<N>", "zn<N>" for a
--      negative N). The node graph is not used for it: one level of the graph can hold several floors (gm_funkis has one from -112 to 240), so it cannot
--      tell where the floor under the player is. See the comment above Fallback.
--   2) The levels of the node graph (FromNodes, ForMap, LevelAt): kept, tested, and not used by Current today; they are meant for the preloading of the
--      floors of a map. Levels {id = "a1", zlo, zhi, count} come from the heights (z) of the ground nodes (type 2) of the map's AI node graph: where
--      they pile up in a histogram, there is a floor. Nothing there calls the engine inside a loop: one pass over the nodes, a count table indexed by
--      integers, then arithmetic on the few bins that were used. The rules (the numbers are the design's):
--        * bin = floor(z / 64); a bin is a floor peak when its count is at least minCount (20) and at least minFraction (4 %) of all the ground nodes;
--        * adjacent peak bins merge into one level; peakLow = low edge of the first bin, peakHigh = high edge of the last one;
--        * zlo = peakLow - 48 and zhi = peakHigh + 112;
--        * the level of a height is the slab that contains it (borders included); with two slabs, the one whose peak is nearest below the height; a
--          level the player is already on is kept up to 24 units outside its slab, so that standing on a step does not flip between two levels.

local Floors = GryMod.Minimap.Floors or {}
GryMod.Minimap.Floors = Floors

local GROUND = 2
local BIN = 64
local MIN_COUNT = 20
local MIN_FRACTION = 0.04
local MARGIN_LOW = 48
local MARGIN_HIGH = 112
local HYSTERESIS = 24

local mathFloor = math.floor
local mathAbs = math.abs
local tableSort = table.sort
local type = type

-- state: the levels of one map (the cache lives for one map name only), the step number of the level Current gave last, and what CurrentAt remembers:
-- the registry of the anchor levels known for one map name (list in creation order, byId to find a duplicate), the last ray (its place, its time and
-- the level it gave) and the bounds of the world (once per map name)
local cache = {map = nil, levels = nil, err = nil, nodes = nil}
local previousStep = nil
local anchors = {map = nil, list = {}, byId = {}}
-- the last shot of CurrentAt; ONE table that is written again at each shot (valid = false: nothing remembered), so a shot allocates no table for it
local memo = {valid = false, x = 0, y = 0, z = 0, t = 0, level = nil, since = nil}
-- the world's bounds (once per map name) and the open level that goes with them (one table per map: only its z changes from one shot to the next)
local worldBox = {map = nil, zmin = nil, zmax = nil, worldTop = nil, byTop = nil, open = nil}
-- the level under an anchor, by the floor of the anchor: Below gives the same table every time (see Below), and builds nothing after the first call
local belowCache = {}
local belowCount = 0
-- the parameters of the five rays: five tables, each with its own two Vectors and its own output table, made at the first shot and written again at each
-- shot (util.TraceLine reads them at once and keeps nothing)
local rayParams = nil

local function resetCache()
	cache.map, cache.levels, cache.err, cache.nodes = nil, nil, nil, nil
end

local function clearBelow()
	belowCache, belowCount = {}, 0
end

-- Reset: forgets the cache of the graph levels, the previous level of Current and everything CurrentAt remembers (public for the tests; ForMap empties
-- its cache by itself when the map name changes, and so does CurrentAt with its registry)
function Floors.Reset()
	resetCache()
	previousStep = nil
	anchors.map, anchors.list, anchors.byId = nil, {}, {}
	memo.valid, memo.level, memo.since = false, nil, nil
	worldBox.map, worldBox.zmin, worldBox.zmax, worldBox.worldTop, worldBox.byTop, worldBox.open = nil, nil, nil, nil, nil, nil
	clearBelow()
end

-- FromNodes(nodes, opts) -> levels. nodes = {{x, y, z, type, ...}, ...}; opts = {bin =, minCount =, minFraction =}, all optional.
-- Never raises: anything that is not a list of nodes gives {}.
function Floors.FromNodes(nodes, opts)
	local levels = {}

	if type(nodes) ~= "table" then
		return levels
	end

	local bin, minCount, minFraction = BIN, MIN_COUNT, MIN_FRACTION

	if type(opts) == "table" then
		if type(opts.bin) == "number" and opts.bin > 0 then
			bin = opts.bin
		end

		if type(opts.minCount) == "number" then
			minCount = opts.minCount
		end

		if type(opts.minFraction) == "number" then
			minFraction = opts.minFraction
		end
	end

	-- one pass: the count of each bin, and the list of the bins used (to read them in order without scanning a range of empty ones)
	local counts, used = {}, {}
	local total, nUsed = 0, 0

	for i = 1, #nodes do
		local node = nodes[i]

		if type(node) == "table" and node.type == GROUND then
			local z = node.z

			if type(z) == "number" then
				local b = mathFloor(z / bin)
				local c = counts[b]

				if c then
					counts[b] = c + 1
				else
					counts[b] = 1
					nUsed = nUsed + 1
					used[nUsed] = b
				end

				total = total + 1
			end
		end
	end

	if total < minCount then
		return levels
	end

	tableSort(used)

	local threshold = minFraction * total
	local n = 0
	local firstBin, lastBin, sum

	-- the used bins are sorted: a run of peak bins whose numbers follow each other is one floor
	for i = 1, nUsed do
		local b = used[i]
		local c = counts[b]

		if c >= minCount and c >= threshold then
			if lastBin and b == lastBin + 1 then
				lastBin = b
				sum = sum + c
			else
				if firstBin then
					n = n + 1
					levels[n] = {id = "a" .. n, zlo = firstBin * bin - MARGIN_LOW, zhi = (lastBin + 1) * bin + MARGIN_HIGH, count = sum}
				end

				firstBin, lastBin, sum = b, b, c
			end
		end
	end

	if firstBin then
		n = n + 1
		levels[n] = {id = "a" .. n, zlo = firstBin * bin - MARGIN_LOW, zhi = (lastBin + 1) * bin + MARGIN_HIGH, count = sum}
	end

	return levels
end

-- ForMap() -> levels | nil, err. The levels of the map being played, from its node graph; cached for that map name (a graph that is missing is
-- remembered too: the file does not appear while the map is played). nil, "no graph" when there is no graph or no level in it.
function Floors.ForMap()
	local map = game.GetMap()

	if cache.map == map then
		return cache.levels, cache.err
	end

	-- a new map: the old cache is of no use
	resetCache()

	local levels, err, nodes
	local AIN = GryMod.Minimap.AIN

	if type(AIN) ~= "table" or type(AIN.Load) ~= "function" then
		-- no reader: not cached, the module may load a moment later
		return nil, "no ain module"
	end

	local ok, graph, loadErr = pcall(AIN.Load, map)

	if not ok then
		err = "ain load failed: " .. tostring(graph)
	elseif type(graph) ~= "table" or type(graph.nodes) ~= "table" then
		err = (type(loadErr) == "string" and loadErr) or "no graph"
	else
		nodes = graph.nodes
		levels = Floors.FromNodes(nodes)

		if #levels == 0 then
			levels, err = nil, "no graph"
		end
	end

	-- the nodes are kept for the cap of the open level (playableTop), once per map name
	cache.map, cache.levels, cache.err, cache.nodes = map, levels, err, nodes

	return levels, err
end

-- the peak of a level is its slab without the margins
local function peakLow(level)
	return level.zlo + MARGIN_LOW
end

-- LevelAt(levels, z, current) -> level | nil. See the rules at the top of the file. `current` only counts when it is one of `levels` (same id).
function Floors.LevelAt(levels, z, current)
	if type(levels) ~= "table" or type(z) ~= "number" then
		return nil
	end

	-- hysteresis: the level the player is on stays until z is 24 units outside its slab
	if type(current) == "table" then
		for i = 1, #levels do
			local level = levels[i]

			if level.id == current.id then
				if z >= level.zlo - HYSTERESIS and z <= level.zhi + HYSTERESIS then
					return level
				end

				break
			end
		end
	end

	-- best = the slab that contains z whose peak is the nearest below z; with none below, the nearest peak above
	local best, bestLow
	local bestBelow = false

	for i = 1, #levels do
		local level = levels[i]

		if z >= level.zlo and z <= level.zhi then
			local low = peakLow(level)
			local below = low <= z

			if not best then
				best, bestLow, bestBelow = level, low, below
			elseif below and (not bestBelow or low > bestLow) then
				best, bestLow, bestBelow = level, low, true
			elseif not below and not bestBelow and low < bestLow then
				best, bestLow = level, low
			end
		end
	end

	return best
end

-- The slab that follows the player's feet (what Current gives). The feet are rounded to a step of 32 units (N = nearest multiple, a half rounds up) and the
-- slab around that step goes from 56 units under it to 72 over it: the feet are inside with at least 40 units to spare under them (a stair step), and the
-- top, at most 88 over the feet, is a cut at head height that stays under a ceiling 128 units high.
local function isFinite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local STEP = 32
local SLAB_BELOW = 56
local SLAB_ABOVE = 72
local STEP_HYSTERESIS = STEP / 2 + 12 -- a level is kept while the feet are within 28 units of its centre (N * 32)

local function stepLevel(n)
	local id

	if n < 0 then
		id = "zn" .. (-n)
	else
		id = "z" .. n
	end

	-- z is the quantised foot height (the floor the slab is built on), the base of Below
	return {id = id, z = n * STEP, zlo = n * STEP - SLAB_BELOW, zhi = n * STEP + SLAB_ABOVE}
end

-- Fallback(z) -> level: the slab of the step nearest to z (N = floor(z / 32 + 0.5)), named "z<N>" ("zn<-N>" when N is negative), with the field
-- z = N * 32. Pure: no memory. A z that is nil, NaN, infinite or not a number gives nil, "bad z".
function Floors.Fallback(z)
	if not isFinite(z) then
		return nil, "bad z"
	end

	return stepLevel(mathFloor(z / STEP + 0.5))
end

local STOREY = 128 -- the height of one storey: Below is the level that far under

-- the id of an anchor writes a negative number with the prefix n (-96 is "n96"); "+ 0" turns a -0 into 0
local function idNumber(v)
	if v < 0 then
		return "n" .. (-v)
	end

	return tostring(v + 0)
end

-- An anchor level, the kind CurrentAt gives: {id = "f<A>c<C>", fz = A, cls = C, top = A + C, z = A, zlo = A - 56, zhi = A + C}: a floor at A (absolute) and a
-- slab that goes from 56 under it to C over it (C is a height class). Two anchors with the same A and C are the same level, which is what lets the tiles
-- be reused.
local function anchorLevel(a, k)
	return {id = "f" .. idNumber(a) .. "c" .. idNumber(k), fz = a, cls = k, top = a + k, z = a, zlo = a - SLAB_BELOW, zhi = a + k}
end

-- Below(level) -> level | nil, reason: the level one storey lower.
--   * an open level (the ray hit the sky) has nothing under it: nil, "open";
--   * an anchor level (it has fz): the fixed level f<A-128>c88, 128 lower and of class 88, whose slab ends at A - 40, under the floor of this one (the
--     floor of this level is the ceiling of the one under it). It does not depend on the class, and it is not entered in the registry;
--   * a step level of Current / Fallback (it has z, no fz): Fallback(level.z - 128) (z0 gives zn4, z4 gives z0), as before.
-- The level under an anchor is made once and kept (by the floor of the anchor): Below gives THE SAME TABLE for the same floor, and allocates nothing after
-- the first call (the radar asks at every frame). So the LEVELS ARE READ-ONLY: a caller that changes a level it was given (or the one Below gave) corrupts
-- the next answers. The kept levels are forgotten by Reset and when CurrentAt starts a new map name.
-- Pure otherwise: the hysteresis of Current is not touched. A level that is nil, or has no finite number fz / z, gives nil, "bad level".
function Floors.Below(level)
	if type(level) ~= "table" then
		return nil, "bad level"
	end

	if level.open then
		return nil, "open"
	end

	local fz = level.fz

	if fz ~= nil then
		if not isFinite(fz) then
			return nil, "bad level"
		end

		local below = belowCache[fz]

		if not below then
			-- a few hundred floors at most on a map; the cache starts again if somebody asks for more than that
			if belowCount >= 512 then
				clearBelow()
			end

			below = anchorLevel(fz - STOREY, 88)
			belowCache[fz] = below
			belowCount = belowCount + 1
		end

		return below
	end

	local z = level.z

	if not isFinite(z) then
		return nil, "bad level"
	end

	return Floors.Fallback(z - STOREY)
end

-- Current(z) -> level: Fallback(z) with a hysteresis on the previous answer: while the feet stay within 28 units of the centre of the previous level
-- (16 for the half step and 12 more), that level is kept, so that a player standing near a limit does not make the tiles flicker.
-- The node graph (FromNodes / ForMap / LevelAt) is not used here.
function Floors.Current(z)
	if not isFinite(z) then
		-- nothing changes, the previous level stays
		return nil, "bad z"
	end

	local n

	if previousStep and mathAbs(z - previousStep * STEP) <= STEP_HYSTERESIS then
		n = previousStep
	else
		n = mathFloor(z / STEP + 0.5)
	end

	previousStep = n

	return stepLevel(n)
end

-- ---------------------------------------------------------------------------------------------------------
-- CurrentAt: the level the minimap draws, from the feet AND the ceiling over them.
--
-- FIVE rays go straight up from 72 units over the feet: one at the centre and four 48 units away along +X, -X, +Y and -Y of the world. The ceiling that
-- counts is the HIGHEST of the ones they hit (a pipe, a beam or a lamp under a room's ceiling must not lower it: they show on the map as objects, which
-- is right). A lateral ray that sees the sky or nothing (a skylight) is ignored. If the CENTRE ray sees the sky or nothing the player is outside: the OPEN
-- level (the whole height of the world, so rocks, dunes and roofs show up). A highest ceiling more than 512 over the feet is open as well.
-- The mask is MASK_SOLID_BRUSHONLY on purpose: the rays go through props (measured: a bathtub 130 units over the head is not hit), so only the map's own
-- brushes are a ceiling.
--
-- Levels are ANCHORS with HEIGHT CLASSES, never a slab cut at the measured height: on a slope with a sloping ceiling, or under a ceiling that is full of
-- things, the measure changes at every step, and one level per height would make a new set of tiles (bitmaps, traces, starts of a map) all the time.
--   * An anchor is a floor A (feet rounded to 16) and a class C of {56, 88, 120, 160, 224, 320, 448}: id "f<A>c<C>" (n before a negative number), slab
--     zlo = A - 56 .. zhi = A + C.
--   * C is the biggest class <= (highest ceiling - A) - 8, and 56 at least (with a ceiling under A + 64, no room for a player, the slab goes 56 up all
--     the same: there is no lower class).
--   * An anchor is USABLE with feet at f and a highest ceiling at c when A - 24 <= f <= A + 40, and C == 56, or A + C >= f + 72 (the head cut is
--     inside) and C <= c - A - 8. The class 56 is always usable on its floor: the head cut does not apply to it (a cut under the head in a low duct).
-- At each shot: (1) the level of the last shot stays while it is usable, and its class goes up only when a bigger class has stayed available at every
-- shot for one second (RealTime) in a row, never at each shot; (2) else, among the known anchors that are usable the one with the biggest class, then the
-- nearest floor; (3) else a new anchor, which enters the registry.
-- The registry is per map name; at the first shot of a map it is seeded with the ids Cache.KnownLevels() gives (the levels that have tiles on disk).
-- The shot is remembered: CurrentAt shoots again only if the feet moved more than 48 units (3D) from the last shot or a second went by, otherwise it gives
-- the remembered level back with no engine call but RealTime (the radar asks at every frame).
-- ---------------------------------------------------------------------------------------------------------

local CLASSES = {448, 320, 224, 160, 120, 88, 56} -- biggest first
local MIN_CLASS = 56 -- a duct or a thin ceiling: the slab stops 56 over the floor (under 64 units of ceiling there is no passage for a player anyway)
local RAY_OFFSET = 48
local RAY_START = 72 -- over the feet
local RAY_LENGTH = 32768
local RAY_MOVE_SQ = 48 * 48
local RAY_INTERVAL = 1 -- seconds; also the time a bigger class has to stay available before it is taken
local MAX_RISE = 512 -- a ceiling higher than this over the feet is the open sky
local FLOOR_BELOW = 24 -- the window of the feet around an anchor's floor: A - 24 .. A + 40
local FLOOR_ABOVE = 40
local HEAD_CUT = 72
local CEILING_GAP = 8
local FLOOR_ROUND = 16
local OPEN_MARGIN = 16
local CAP_NODES = 96 -- the ground nodes whose up rays give the sky height of the playable area (once per map)
local sformat = string.format

-- the five places of the rays around the feet, as offsets in x and y
local RAY_DX = {0, RAY_OFFSET, -RAY_OFFSET, 0, 0}
local RAY_DY = {0, 0, 0, RAY_OFFSET, -RAY_OFFSET}

local function isClass(c)
	for i = 1, #CLASSES do
		if CLASSES[i] == c then
			return true
		end
	end

	return false
end

-- the biggest class that fits under a ceiling at c for a floor at a (56 when none does: with a ceiling under a + 64 the slab goes over the ceiling all the
-- same, there is no lower class)
local function classFor(a, c)
	local room = c - a - CEILING_GAP

	for i = 1, #CLASSES do
		if CLASSES[i] <= room then
			return CLASSES[i]
		end
	end

	return MIN_CLASS
end

local function usable(level, f, c)
	local a, k = level.fz, level.cls

	if a - FLOOR_BELOW > f or f > a + FLOOR_ABOVE then
		return false
	end

	-- the lowest class is always usable on its floor (the head cut does not apply to it: a cut under the head in a low duct); the others must have the
	-- head cut inside and fit under the ceiling
	return k == MIN_CLASS or (a + k >= f + HEAD_CUT and k <= c - a - CEILING_GAP)
end

local function addAnchor(a, k)
	local level = anchorLevel(a, k)
	local known = anchors.byId[level.id]

	if known then
		return known
	end

	anchors.byId[level.id] = level
	anchors.list[#anchors.list + 1] = level

	return level
end

-- "f<A>c<C>" with a negative A written n<digits> and C one of the classes; nil otherwise
local function parseAnchorId(id)
	if type(id) ~= "string" then
		return nil
	end

	local a, k = string.match(id, "^f(n?%d+)c(%d+)$")

	if not a then
		return nil
	end

	if string.sub(a, 1, 1) == "n" then
		a = -tonumber(string.sub(a, 2))
	else
		a = tonumber(a)
	end

	k = tonumber(k)

	if not a or not isClass(k) then
		return nil
	end

	return a, k
end

-- a new map name: the registry starts again from the levels that have tiles on disk (Cache.KnownLevels, written by the Cache module; anything wrong
-- with it only means an empty start), and the remembered shot is of no use
local function startMap(map)
	anchors.map, anchors.list, anchors.byId = map, {}, {}
	memo.valid, memo.level, memo.since = false, nil, nil
	clearBelow()

	local Cache = GryMod.Minimap.Cache

	if type(Cache) ~= "table" or type(Cache.KnownLevels) ~= "function" then
		return
	end

	local ok, ids = pcall(Cache.KnownLevels)

	if not ok or type(ids) ~= "table" then
		return
	end

	for i = 1, #ids do
		local a, k = parseAnchorId(ids[i])

		if a then
			addAnchor(a, k)
		end
	end
end

-- The top of the playable area, seen from the sky: the highest SKY hit of an up ray (brush mask) shot from the ground nodes of the node graph (at most CAP_NODES
-- of them, spread over the list) and from `playerSky` (the sky height the player's own centre ray saw, or nil). nil when no ray saw the sky: then nothing is
-- known and the world's bounds stay. Once per map name (CurrentAt and Outside ask worldHeights, which asks this), never in the per-frame path.
-- Why (gm_construct, 2026-11-22): the world's bounds include the 3D skybox, a small room far over the map, so the camera of the open level looked at that room
-- first. The sky of the playable area (9984 there) is the real top; the skybox starts over it.
local function playableTop(map, playerSky)
	local top = playerSky

	-- the nodes of the graph (ForMap reads and keeps them once per map name; nothing when there is no graph)
	Floors.ForMap()

	local nodes = cache.map == map and cache.nodes or nil

	if type(nodes) == "table" then
		local ground = 0

		for i = 1, #nodes do
			local node = nodes[i]

			if type(node) == "table" and node.type == GROUND then
				ground = ground + 1
			end
		end

		local stride = mathFloor((ground + CAP_NODES - 1) / CAP_NODES)

		if stride < 1 then
			stride = 1
		end

		local seen = 0

		for i = 1, #nodes do
			local node = nodes[i]

			if type(node) == "table" and node.type == GROUND then
				seen = seen + 1

				if (seen - 1) % stride == 0 and isFinite(node.x) and isFinite(node.y) and isFinite(node.z) then
					local ok, tr = pcall(util.TraceLine, {
						start = Vector(node.x, node.y, node.z + RAY_START),
						endpos = Vector(node.x, node.y, node.z + RAY_LENGTH),
						mask = MASK_SOLID_BRUSHONLY
					})

					if ok and type(tr) == "table" and tr.HitSky and tr.HitPos and isFinite(tr.HitPos.z) and (not top or tr.HitPos.z > top) then
						top = tr.HitPos.z
					end
				end
			end
		end
	end

	return top
end

-- The top of the slab of an open level for a ray that hit at height `hit`: 16 under the hit, down to a multiple of 64. The slab ends UNDER the hit, never over
-- it (what is over the hit, the skybox room or the piece above, must stay out of the picture), and the rounding keeps the number of levels small (the same
-- height, give or take a step, is the same level and so the same tiles).
local OPEN_STEP = 64

local function cappedTop(hit)
	return mathFloor((hit - OPEN_MARGIN) / OPEN_STEP) * OPEN_STEP
end

-- the height of the world's bounds, asked once per map name; the top is cut to the playable area's sky when that is lower (see playableTop), and then the
-- open level gets the id "open_t<top>" so that the tiles made with the whole height (the skybox in the picture) are never used again
local function worldHeights(map, playerSky)
	if worldBox.map == map and worldBox.zmin then
		return worldBox.zmin, worldBox.zmax
	end

	local ok, world = pcall(game.GetWorld)

	if not ok or not world then
		return nil
	end

	local ok2, low, high = pcall(world.GetModelBounds, world)

	if not ok2 or not low or not high then
		return nil
	end

	local zmin, zmax = low.z, high.z

	if not isFinite(zmin) or not isFinite(zmax) then
		return nil
	end

	local worldTop = zmax
	local open = {id = "open", open = true, z = 0, zlo = zmin - OPEN_MARGIN, zhi = zmax + OPEN_MARGIN}
	local byTop = {}
	local top = playableTop(map, playerSky)

	if top and top < zmax then
		local q = cappedTop(top)

		if q > zmin then
			zmax = q
			open.id, open.zhi = "open_t" .. sformat("%d", q), q
			byTop[q] = open
		end
	end

	-- worldTop: the bounds' own top (a hit under it makes a level of its own, see openAt); byTop: the open levels made for this map, by their top
	worldBox.map, worldBox.zmin, worldBox.zmax, worldBox.worldTop, worldBox.byTop = map, zmin, zmax, worldTop, byTop
	worldBox.open = open

	return zmin, zmax
end

-- The open level for a place where the up ray (the player's) hit at `hit` (the sky, or a solid far over the feet; nil when it hit nothing): the camera goes
-- where the ray hit, as the owner asked, so a piece of the map over another one with void between them is not hidden by the upper one. A hit that is not
-- under the world's own top (or no hit) gives the open level of the map. One table per top (made once, then found by its number), shared with the map's own
-- open level when it has the same top, so the tiles are made once.
local function openAt(zmin, hit)
	local box = worldBox

	if hit and hit < box.worldTop then
		local q = cappedTop(hit)

		if q > zmin then
			local level = box.byTop[q]

			if not level then
				level = {id = "open_t" .. sformat("%d", q), open = true, z = 0, zlo = zmin - OPEN_MARGIN, zhi = q}
				box.byTop[q] = level
			end

			return level
		end
	end

	return box.open
end

-- the five parameter tables of the rays, made once (a Vector for the start and one for the end of each, and a table util.TraceLine fills with its answer)
local function makeRayParams()
	local list = {}

	for i = 1, 5 do
		list[i] = {start = Vector(0, 0, 0), endpos = Vector(0, 0, 0), mask = MASK_SOLID_BRUSHONLY, output = {}}
	end

	return list
end

-- the level for feet at f under a highest ceiling at c, and the time since when a bigger class has been available (nil when it has not been)
-- `last` = the memo of the previous shot (its level and its hold)
local function chooseAnchor(f, c, last, now)
	local current = last and last.level

	if current and current.fz and usable(current, f, c) then
		local better = classFor(current.fz, c)

		if better <= current.cls then
			return current, nil
		end

		local since = last.since or now

		if now - since >= RAY_INTERVAL then
			return addAnchor(current.fz, better), nil
		end

		return current, since
	end

	local best
	local list = anchors.list

	for i = 1, #list do
		local level = list[i]

		if usable(level, f, c) then
			if not best or level.cls > best.cls or (level.cls == best.cls and mathAbs(level.fz - f) < mathAbs(best.fz - f)) then
				best = level
			end
		end
	end

	if best then
		return best, nil
	end

	local a = mathFloor(f / FLOOR_ROUND + 0.5) * FLOOR_ROUND

	return addAnchor(a, classFor(a, c)), nil
end

-- The five up rays and the choice of the level for feet at (x, y, f): the part of CurrentAt that is the same for a player and for a place asked about (PeekAt). `last` is
-- the remembered shot of the player (nil for a place: no hold) and `now` the clock; `map` the map name. Gives level, since (the time since when a bigger class has been
-- available, or nil), or nil when the engine failed for the centre ray. Changes nothing but the registry of anchors (and the open levels): not the remembered shot.
local function decide(x, y, f, last, now, map)
	rayParams = rayParams or makeRayParams()

	local ceiling -- the highest ceiling hit by a ray that is not in the sky
	local centreOpen = false
	local centreSky -- the height of the sky the centre ray saw, if it saw the sky

	for i = 1, 5 do
		-- the same five parameter tables at every shot: only the two Vectors are written again
		local params = rayParams[i]
		local start, endpos = params.start, params.endpos

		start.x, start.y, start.z = x + RAY_DX[i], y + RAY_DY[i], f + RAY_START
		endpos.x, endpos.y, endpos.z = x + RAY_DX[i], y + RAY_DY[i], f + RAY_LENGTH

		local ok, tr = pcall(util.TraceLine, params)

		if i == 1 and (not ok or type(tr) ~= "table") then
			return nil -- the engine failed for the centre ray
		end

		if ok and type(tr) == "table" then
			local hit = tr.HitPos
			local z = hit and hit.z

			if tr.HitSky or not tr.Hit or not isFinite(z) then
				if i == 1 then
					centreOpen = true

					if tr.HitSky and isFinite(z) then
						centreSky = z
					end
				end
			elseif not ceiling or z > ceiling then
				ceiling = z
			end
		end
	end

	if centreOpen or not ceiling or ceiling - f > MAX_RISE then
		local zmin = worldHeights(map, centreSky)

		if zmin then
			-- the camera goes where the up ray hit: the sky seen by the centre ray, or the highest solid when it hit one far over the feet. One table per top
			return openAt(zmin, centreOpen and centreSky or (not centreOpen and ceiling) or nil), nil
		end

		return Floors.Fallback(f), nil
	end

	return chooseAnchor(f, ceiling, last, now)
end

-- CurrentAt(pos) -> level | nil, "bad position". pos = the Vector of the player's feet. See the block above.
function Floors.CurrentAt(pos)
	if type(pos) ~= "table" and type(pos) ~= "Vector" then
		return nil, "bad position"
	end

	local x, y, f = pos.x, pos.y, pos.z

	if not (isFinite(x) and isFinite(y) and isFinite(f)) then
		return nil, "bad position"
	end

	local now = RealTime()
	local last = memo.valid and memo or nil

	if last and now - last.t < RAY_INTERVAL then
		local dx, dy, dz = x - last.x, y - last.y, f - last.z

		if dx * dx + dy * dy + dz * dz <= RAY_MOVE_SQ then
			return last.level
		end
	end

	-- new rays
	local map = game.GetMap()

	if anchors.map ~= map then
		startMap(map)
		last = nil
	end

	local level, since = decide(x, y, f, last, now, map)

	if not level then
		-- the engine failed for the centre ray: the plain slab of the step, and the next call tries again
		memo.valid, memo.level, memo.since = false, nil, nil

		return Floors.Fallback(f)
	end

	if level.open then
		level.z = f -- the open level of a map is one table per top (only its z, the feet, changes)
	end

	memo.valid, memo.x, memo.y, memo.z, memo.t, memo.level, memo.since = true, x, y, f, now, level, since

	return level
end

-- PeekAt(x, y, z) -> level | nil, "bad position". The level CurrentAt would give a player standing at (x, y) with the feet at z, for the tile preload (which asks it for the
-- ground places of the node graph, the floors). The same rays and the same choice, with no player: the remembered shot is not read and not changed (the player's own level
-- goes on), and a bigger class is taken at once (there is no clock to hold it: a place is not passed under in a moment). The anchors it makes are the ones the player would
-- make there, so the preloaded tiles are the ones the player finds. A centre ray that fails gives the plain slab of the step.
function Floors.PeekAt(x, y, z)
	if not (isFinite(x) and isFinite(y) and isFinite(z)) then
		return nil, "bad position"
	end

	local map = game.GetMap()

	if anchors.map ~= map then
		startMap(map)
	end

	local level = decide(x, y, z, nil, RealTime(), map)

	return level or Floors.Fallback(z)
end

-- OpenAt(x, y, z) -> level | nil, reason. The open level a player standing at (x, y) with the ground at height z would get from CurrentAt, found with ONE
-- up ray (brush mask) and no player, no memory of the last shot: for the tile preload, which asks it for the outdoor places of the in/out map.
--   * the ray sees the sky or nothing: the open level at the sky it hit (the very table CurrentAt gives, so the tiles are shared);
--   * it hits a solid more than MAX_RISE over z (the underside of a piece far above): the open level under it;
--   * it hits a solid within MAX_RISE (a roof, a ceiling): nil, "roofed" (an anchor level of the floors, not an open one);
--   * nil, "bad position", "ray failed" or "no world bounds" when it cannot say.
function Floors.OpenAt(x, y, z)
	if not (isFinite(x) and isFinite(y) and isFinite(z)) then
		return nil, "bad position"
	end

	local ok, tr = pcall(util.TraceLine, {
		start = Vector(x, y, z),
		endpos = Vector(x, y, z + RAY_LENGTH),
		mask = MASK_SOLID_BRUSHONLY
	})

	if not ok or type(tr) ~= "table" then
		return nil, "ray failed"
	end

	local hit = tr.HitPos and tr.HitPos.z
	local hasHit = isFinite(hit)
	local isSky = tr.HitSky or not tr.Hit or not hasHit

	if not isSky and hit - z <= MAX_RISE then
		return nil, "roofed"
	end

	local skyZ = tr.HitSky and hasHit and hit or nil
	local zmin = worldHeights(game.GetMap(), skyZ)

	if not zmin then
		return nil, "no world bounds"
	end

	return openAt(zmin, isSky and skyZ or hit)
end

-- GroundAt(x, y, top) -> z | nil. The height of the ground under `top` (the top of a layer of the in/out map): ONE ray down, GROUND_REACH units, brush mask. nil when it hits nothing,
-- starts inside a solid (no ground to speak of), hits the sky (not a floor), or the numbers are bad. For the tile preload, which finds the floors of an indoor box with it.
local GROUND_REACH = 256

function Floors.GroundAt(x, y, top)
	if not (isFinite(x) and isFinite(y) and isFinite(top)) then
		return nil
	end

	local ok, tr = pcall(util.TraceLine, {
		start = Vector(x, y, top),
		endpos = Vector(x, y, top - GROUND_REACH),
		mask = MASK_SOLID_BRUSHONLY
	})

	if not ok or type(tr) ~= "table" or not tr.Hit or tr.StartSolid or tr.HitSky then
		return nil
	end

	local z = tr.HitPos and tr.HitPos.z

	if not isFinite(z) then
		return nil
	end

	return z
end

-- MapOpenTop() -> number | nil: the top (zhi) of the map's own open level, the one Outside gives: the whole height of the world cut at the sky the nodes see. The tile
-- preload leaves out the places whose level is higher (outside the playable area). nil when the world's bounds are unknown.
function Floors.MapOpenTop()
	if not worldHeights(game.GetMap(), nil) then
		return nil
	end

	return worldBox.open.zhi
end

-- Outside(level) -> level | nil, reason: the level that shows what is OUTSIDE the slab of `level`, the open level of the map (the whole height of the world:
-- rocks, roofs and terrain, the same table, id "open", that CurrentAt gives outdoors, so the tiles already made for it are used). The radar draws it under
-- the floor below, faintly, so that the solid parts of a floor (earth cut by the slice) show a part of what is outside.
--   * an open level has nothing behind it: nil, "open" (by its flag);
--   * a value that is not a table is nil, "bad level";
--   * the bounds of the world are asked once per map name (as CurrentAt does); when they are unknown: nil and a reason.
-- Like Below, the level is READ-ONLY and it is ONE table per map name (only its z, the feet, is changed by CurrentAt): nothing is allocated after the first
-- call, the radar asks at every frame.
function Floors.Outside(level)
	if type(level) ~= "table" then
		return nil, "bad level"
	end

	if level.open then
		return nil, "open"
	end

	local map = game.GetMap()

	if not worldHeights(map) then
		return nil, "no world bounds"
	end

	return worldBox.open
end

-- Known() -> array: a copy of the anchor levels the registry knows for the current map (the tests read it; nothing else should)
function Floors.Known()
	local copy = {}
	local list = anchors.list

	for i = 1, #list do
		local level = list[i]

		copy[i] = {id = level.id, fz = level.fz, cls = level.cls, top = level.top, z = level.z, zlo = level.zlo, zhi = level.zhi}
	end

	return copy
end
