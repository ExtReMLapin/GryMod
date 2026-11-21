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

-- state: the levels of one map (the cache lives for one map name only) and the step number of the level Current gave last
local cache = {map = nil, levels = nil, err = nil}
local previousStep = nil

local function resetCache()
	cache.map, cache.levels, cache.err = nil, nil, nil
end

-- Reset: forgets the cache of the graph levels and the previous level of Current (public for the tests; ForMap empties the cache by itself when the
-- map name changes)
function Floors.Reset()
	resetCache()
	previousStep = nil
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

	local levels, err
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
		levels = Floors.FromNodes(graph.nodes)

		if #levels == 0 then
			levels, err = nil, "no graph"
		end
	end

	cache.map, cache.levels, cache.err = map, levels, err

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

	return {id = id, zlo = n * STEP - SLAB_BELOW, zhi = n * STEP + SLAB_ABOVE}
end

-- Fallback(z) -> level: the slab of the step nearest to z (N = floor(z / 32 + 0.5)), named "z<N>" ("zn<-N>" when N is negative). Pure: no memory.
function Floors.Fallback(z)
	return stepLevel(mathFloor(z / STEP + 0.5))
end

-- Current(z) -> level: Fallback(z) with a hysteresis on the previous answer: while the feet stay within 28 units of the centre of the previous level
-- (16 for the half step and 12 more), that level is kept, so that a player standing near a limit does not make the tiles flicker.
-- The node graph (FromNodes / ForMap / LevelAt) is not used here.
function Floors.Current(z)
	local n

	if previousStep and mathAbs(z - previousStep * STEP) <= STEP_HYSTERESIS then
		n = previousStep
	else
		n = mathFloor(z / STEP + 0.5)
	end

	previousStep = n

	return stepLevel(n)
end
