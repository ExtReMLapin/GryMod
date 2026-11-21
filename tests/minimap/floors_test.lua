-- Tests of GryMod.Minimap.Floors (lua/grymod/client/minimap/floors.lua), GLuaTest format, client realm. The floors (levels) of a map come from the
-- height of the ground nodes of its AI node graph: a histogram with bins of 64 units, a bin with enough nodes is a floor, adjacent floor bins merge,
-- the slab of a level goes from 48 units under its lowest floor bin to 112 units over its highest one. Everything here runs for real (the maths are pure);
-- only the node graph reader (module AIN, written by another agent) and game.GetMap are replaced by stand-ins, and put back in afterEach.
--
-- Real maps (cases at the bottom): the expected slabs were computed by an independent script (Python, same rule: ground nodes of type 2,
-- bins of 64, minCount 20, minFraction 0.04) on the .ain files shipped in garrysmod/maps/graphs. Where the owner's rough reading of the histograms
-- showed two neighbouring peaks (d1_canals_05: -512..-384 and -384..-320) the rule merges them into one level, because the bins touch.

local GROUND, AIR, CLIMB, WATER, ANY, DELETED = 2, 3, 4, 5, 0, 1

local function F()
	return GryMod.Minimap.Floors or {}
end

-- n ground-like nodes of the given type, all at height z (x spreads them so the nodes are not the same table)
local function cluster(z, n, kind, into)
	into = into or {}

	for i = 1, n do
		into[#into + 1] = {x = i * 10, y = 0, z = z, yaw = 0, type = kind or GROUND, info = 0, zone = 0}
	end

	return into
end

local function sameLevel(level, id, zlo, zhi, count)
	expect(level ~= nil).to.beTrue()
	expect(level.id).to.equal(id)
	expect(level.zlo).to.equal(zlo)
	expect(level.zhi).to.equal(zhi)

	if count then
		expect(level.count).to.equal(count)
	end
end

-- a stand-in of AIN: Load(map) answers from `graphs[map]` and counts its calls
local function standIn(state, graphs)
	state.loads = {}
	GryMod.Minimap.AIN = {
		Load = function(map)
			state.loads[#state.loads + 1] = map
			local g = graphs[map]

			if g == nil then
				return nil, "no graph"
			end

			return g
		end
	}
end

local function setMap(state, name)
	state.map = name
end

-- minimal reader of a .ain (header of 12 bytes, nodes of 61 bytes): only used when the real AIN.Load does not exist yet
local function f32(s, i)
	local b1, b2, b3, b4 = string.byte(s, i, i + 3)
	local sign = b4 >= 128 and -1 or 1
	local exp = (b4 % 128) * 2 + math.floor(b3 / 128)
	local mant = (b3 % 128) * 65536 + b2 * 256 + b1

	if exp == 0 then
		return 0
	end

	return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end

local function readNodes(map)
	local A = GryMod.Minimap.AIN
	local path = "maps/graphs/" .. map .. ".ain"

	if A and A.Load then
		local g = A.Load(map)

		if g and g.nodes then
			return g.nodes
		end
	end

	local s = file.Read(path, "GAME")

	if not s then
		return nil
	end

	local n = string.byte(s, 9) + string.byte(s, 10) * 256 + string.byte(s, 11) * 65536
	local nodes = {}

	for i = 0, n - 1 do
		local o = 13 + 61 * i
		nodes[#nodes + 1] = {x = f32(s, o), y = f32(s, o + 4), z = f32(s, o + 8), type = string.byte(s, o + 56)}
	end

	return nodes
end

return {
	groupName = "GryMod minimap floors (client)",
	beforeEach = function(state)
		state.realAIN = GryMod.Minimap.AIN
		state.realGetMap = game.GetMap
		state.map = "test_floor_map"
		game.GetMap = function() return state.map end

		if F().Reset then
			F().Reset()
		end
	end,
	afterEach = function(state)
		-- always put the real ones back, also when a case failed
		pcall(function() GryMod.Minimap.AIN = state.realAIN end)
		pcall(function() game.GetMap = state.realGetMap end)
		pcall(function() if F().Reset then F().Reset() end end)
	end,
	cases = {
		{
			-- breaks if: the histogram, the sort, the 48 / 112 margins, the ids or the count change
			name = "FromNodes: two clusters of ground nodes (z 0 and 300, 50 each) give two levels sorted by height, ids a1 a2, slabs computed by hand",
			func = function()
				-- given in the wrong order on purpose: the result must be sorted by z
				local nodes = cluster(300, 50)
				cluster(0, 50, GROUND, nodes)

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(2)
				-- z 0 is bin 0 (0..64): zlo = 0 - 48, zhi = 64 + 112
				sameLevel(levels[1], "a1", -48, 176, 50)
				-- z 300 is bin 4 (256..320): zlo = 256 - 48, zhi = 320 + 112
				sameLevel(levels[2], "a2", 208, 432, 50)
			end
		},
		{
			-- breaks if: a node of another type than 2 enters the histogram
			name = "FromNodes: nodes of type any, deleted, air, climb and water are ignored",
			func = function()
				local nodes = cluster(0, 50)
				cluster(500, 100, AIR, nodes)
				cluster(1000, 100, CLIMB, nodes)
				cluster(2000, 100, WATER, nodes)
				cluster(3000, 100, ANY, nodes)
				cluster(4000, 100, DELETED, nodes)

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -48, 176, 50)
			end
		},
		{
			-- breaks if: the minCount gate is missing or off by one
			name = "FromNodes: fewer than minCount (20) ground nodes give {} (19: none, 20: one level)",
			func = function()
				local none = F().FromNodes(cluster(0, 19))

				expect(type(none)).to.equal("table")
				expect(#none).to.equal(0)
				expect(#F().FromNodes(cluster(0, 20))).to.equal(1)
				expect(#F().FromNodes({})).to.equal(0)
				-- air nodes only do not count as ground
				expect(#F().FromNodes(cluster(0, 500, AIR))).to.equal(0)
			end
		},
		{
			-- breaks if: the minCount / minFraction thresholds are not applied to each bin
			name = "FromNodes: a small cluster beside a big one is no level (under minCount, or over minCount but under minFraction)",
			func = function()
				local small = cluster(0, 100)
				cluster(300, 5, GROUND, small)

				expect(#F().FromNodes(small)).to.equal(1)

				-- 30 nodes are over minCount (20) but 30 / 1030 = 2.9 % is under minFraction (4 %)
				local fraction = cluster(0, 1000)
				cluster(300, 30, GROUND, fraction)

				expect(#F().FromNodes(fraction)).to.equal(1)

				-- 50 of 1050 = 4.76 % passes
				local enough = cluster(0, 1000)
				cluster(300, 50, GROUND, enough)

				expect(#F().FromNodes(enough)).to.equal(2)
			end
		},
		{
			-- breaks if: adjacent peak bins are not merged, or bins that are not adjacent are
			name = "FromNodes: three adjacent bins make one level; bins separated by a gap (or by a bin under the threshold) make two",
			func = function()
				local merged = cluster(10, 25)
				cluster(70, 25, GROUND, merged)
				cluster(130, 25, GROUND, merged)

				local levels = F().FromNodes(merged)

				-- bins 0, 1, 2: peakLow 0, peakHigh 192
				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -48, 304, 75)

				-- bins 0 and 2 with nothing between
				local gap = cluster(10, 25)
				cluster(130, 25, GROUND, gap)

				levels = F().FromNodes(gap)

				expect(#levels).to.equal(2)
				sameLevel(levels[1], "a1", -48, 176, 25)
				sameLevel(levels[2], "a2", 80, 304, 25)

				-- bins 0 and 2 with a bin 1 that is under the threshold between them
				local weak = cluster(10, 25)
				cluster(70, 5, GROUND, weak)
				cluster(130, 25, GROUND, weak)

				levels = F().FromNodes(weak)

				expect(#levels).to.equal(2)
				sameLevel(levels[1], "a1", -48, 176, 25)
				sameLevel(levels[2], "a2", 80, 304, 25)
			end
		},
		{
			-- breaks if: one of the options is ignored
			name = "FromNodes: the options bin, minCount and minFraction are respected",
			func = function()
				-- bin: z 10 and z 130 are bins 0 and 2 at 64 (two levels) but bins 0 and 1 at 128 (one level, peakHigh 256)
				local two = cluster(10, 25)
				cluster(130, 25, GROUND, two)

				expect(#F().FromNodes(two)).to.equal(2)

				local one = F().FromNodes(two, {bin = 128})

				expect(#one).to.equal(1)
				sameLevel(one[1], "a1", -48, 368, 50)

				-- minCount: 15 nodes are enough with minCount 10, too few with the default, and 25 are too few for 30
				expect(#F().FromNodes(cluster(0, 15), {minCount = 10})).to.equal(1)
				expect(#F().FromNodes(cluster(0, 15))).to.equal(0)
				expect(#F().FromNodes(cluster(0, 25), {minCount = 30})).to.equal(0)

				-- minFraction: 1000 + 30 nodes, the small cluster is a level with 1 % and is not with the default 4 %
				local nodes = cluster(0, 1000)
				cluster(300, 30, GROUND, nodes)

				expect(#F().FromNodes(nodes, {minFraction = 0.01})).to.equal(2)
				expect(#F().FromNodes(nodes)).to.equal(1)
				expect(#F().FromNodes(nodes, {minFraction = 0.5})).to.equal(1)
			end
		},
		{
			-- breaks if: the bin is computed by truncation (z / 64 toward zero) instead of floor
			name = "FromNodes: negative heights use floor (z = -1 is bin -1, z = -64 too, z = -65 is bin -2)",
			func = function()
				local levels = F().FromNodes(cluster(-1, 30))

				-- bin -1 covers -64..0: zlo = -64 - 48, zhi = 0 + 112
				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -112, 112, 30)

				local edge = cluster(-1, 25)
				cluster(-64, 25, GROUND, edge)
				levels = F().FromNodes(edge)

				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -112, 112, 50)

				local two = cluster(-1, 25)
				cluster(-65, 25, GROUND, two)
				levels = F().FromNodes(two)

				-- bins -2 and -1 are adjacent: one level from -128 to 0
				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -176, 112, 50)
			end
		},
		{
			-- breaks if: bad entries raise
			name = "FromNodes: anything that is not a list of nodes gives {} without raising; a node without a height is skipped",
			func = function()
				expect(#F().FromNodes(nil)).to.equal(0)
				expect(#F().FromNodes("x")).to.equal(0)

				local nodes = cluster(0, 30)
				nodes[#nodes + 1] = {type = GROUND}
				nodes[#nodes + 1] = 7
				nodes[#nodes + 1] = {x = 0, y = 0, z = "high", type = GROUND}

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(1)
				expect(levels[1].count).to.equal(30)
			end
		},
		{
			-- breaks if: the slab test or the empty list handling changes
			name = "LevelAt: inside a slab gives that level, between two slabs gives nil, an empty list gives nil",
			func = function()
				local levels = {{id = "a1", zlo = -48, zhi = 176}, {id = "a2", zlo = 208, zhi = 432}}

				expect(F().LevelAt(levels, 0).id).to.equal("a1")
				expect(F().LevelAt(levels, 300).id).to.equal("a2")
				-- the borders belong to the slab
				expect(F().LevelAt(levels, -48).id).to.equal("a1")
				expect(F().LevelAt(levels, 176).id).to.equal("a1")
				expect(F().LevelAt(levels, 208).id).to.equal("a2")
				expect(F().LevelAt(levels, 190)).to.beNil()
				expect(F().LevelAt(levels, -49)).to.beNil()
				expect(F().LevelAt(levels, 433)).to.beNil()
				expect(F().LevelAt({}, 0)).to.beNil()
				expect(F().LevelAt(nil, 0)).to.beNil()
			end
		},
		{
			-- breaks if: the first slab found wins, or the highest one
			name = "LevelAt: two slabs that overlap give the one whose peak is nearest below z",
			func = function()
				-- peaks (slab bounds + 48 / - 112): a1 0..64, a2 148..320
				local levels = {{id = "a1", zlo = -48, zhi = 176}, {id = "a2", zlo = 100, zhi = 432}}

				-- z 120 is in both slabs; the peak of a1 (0) is below it, the one of a2 (148) is above
				expect(F().LevelAt(levels, 120).id).to.equal("a1")
				-- z 200: both peaks are below, a2's is the nearest
				expect(F().LevelAt(levels, 200).id).to.equal("a2")
				expect(F().LevelAt(levels, 148).id).to.equal("a2")
				-- order of the list does not matter
				expect(F().LevelAt({levels[2], levels[1]}, 120).id).to.equal("a1")
			end
		},
		{
			-- breaks if: the hysteresis is missing, is not 24 units, or is not symmetric
			name = "LevelAt: hysteresis, the current level is kept within 24 units of its slab and left beyond",
			func = function()
				local levels = {{id = "a1", zlo = -48, zhi = 176}, {id = "a2", zlo = 208, zhi = 432}}
				local a1, a2 = levels[1], levels[2]

				-- over the top of a1 by 14 and 24: still a1; by 25: nil (the gap)
				expect(F().LevelAt(levels, 190, a1).id).to.equal("a1")
				expect(F().LevelAt(levels, 200, a1).id).to.equal("a1")
				expect(F().LevelAt(levels, 201, a1)).to.beNil()
				-- without a current level there is no hysteresis
				expect(F().LevelAt(levels, 190)).to.beNil()
				expect(F().LevelAt(levels, 190, a2).id).to.equal("a2")
				-- under the bottom of a2 (208) by 24: still a2; by 25: the gap
				expect(F().LevelAt(levels, 184, a2).id).to.equal("a2")
				expect(F().LevelAt(levels, 183, a2)).to.beNil()
				-- under the bottom of a1
				expect(F().LevelAt(levels, -72, a1).id).to.equal("a1")
				expect(F().LevelAt(levels, -73, a1)).to.beNil()
				-- into the other slab: the other level
				expect(F().LevelAt(levels, 210, a1).id).to.equal("a2")
				expect(F().LevelAt(levels, 0, a2).id).to.equal("a1")
			end
		},
		{
			-- breaks if: the hysteresis does not win over the "nearest peak" rule, or a foreign current level is trusted
			name = "LevelAt: with overlapping slabs the current level stays within its hysteresis; a current level that is not in the list is ignored",
			func = function()
				local levels = {{id = "a1", zlo = -48, zhi = 176}, {id = "a2", zlo = 100, zhi = 432}}

				-- z 200 would be a2 (nearest peak) but a1 is the current level and 200 is 24 over its slab
				expect(F().LevelAt(levels, 200, levels[1]).id).to.equal("a1")
				expect(F().LevelAt(levels, 210, levels[1]).id).to.equal("a2")

				local foreign = {id = "zz", zlo = 0, zhi = 1000}
				local two = {{id = "a1", zlo = -48, zhi = 176}, {id = "a2", zlo = 208, zhi = 432}}

				expect(F().LevelAt(two, 190, foreign)).to.beNil()
			end
		},
		{
			-- breaks if: the step 32, the rounding (half up), the margins -56 / +72 or the id format change
			name = "Fallback: the slab follows the feet in steps of 32 (z 0 is z0 from -56 to 72, z 16 is z1, z -200 is zn6, z 5000 is z156)",
			func = function()
				sameLevel(F().Fallback(0), "z0", -56, 72)
				-- 16 / 32 = 0.5, rounded half up: N = floor(0.5 + 0.5) = 1
				sameLevel(F().Fallback(16), "z1", -24, 104)
				-- N = floor(-91.97 / 32 + 0.5) = floor(-2.374) = -3 (-91.97 is nearer to -96 than to -64); negative numbers are written with n
				sameLevel(F().Fallback(-91.97), "zn3", -152, -24)
				-- N = floor(-6.25 + 0.5) = -6
				sameLevel(F().Fallback(-200), "zn6", -248, -120)
				-- N = floor(156.25 + 0.5) = 156
				sameLevel(F().Fallback(5000), "z156", 4936, 5064)
				-- the id "z0" for N = 0, also for a z just under 0 (-15.9 / 32 + 0.5 = 0.003)
				expect(F().Fallback(-15.9).id).to.equal("z0")
			end
		},
		{
			-- breaks if: the change of level is not at 16 + 32 k, or the slab does not contain the feet, or reaches a ceiling at 128
			name = "Fallback: z = 15.9 and 16 are on both sides of a change of level; the slab contains the feet and its top is 72 over its level",
			func = function()
				expect(F().Fallback(15.9).id).to.equal("z0")
				expect(F().Fallback(16).id).to.equal("z1")
				-- the next change is 32 higher
				expect(F().Fallback(47.9).id).to.equal("z1")
				expect(F().Fallback(48).id).to.equal("z2")

				-- whatever z the feet are at, the slab contains them with at least 40 to spare under (a step) and its top is under a ceiling at 128
				for z = -300, 300, 3 do
					local level = F().Fallback(z)

					expect(level.zlo <= z and z <= level.zhi).to.beTrue()
					expect(z - level.zlo >= 40).to.beTrue()
					expect(level.zhi - z >= 56 and level.zhi - z <= 88).to.beTrue()
					expect(level.zhi - level.zlo).to.equal(128)
				end
			end
		},
		{
			-- breaks if: ForMap raises, does not name the failure, or ignores the AIN module's answer
			name = "ForMap: a map without graph gives nil, \"no graph\"; with nodes it gives the levels",
			func = function(state)
				standIn(state, {})

				local levels, err = F().ForMap()

				expect(levels).to.beNil()
				expect(err).to.equal("no graph")

				F().Reset()
				local nodes = cluster(0, 50)
				cluster(300, 50, GROUND, nodes)
				standIn(state, {test_floor_map = {nodes = nodes, links = {}}})

				levels, err = F().ForMap()

				expect(err).to.beNil()
				expect(#levels).to.equal(2)
				sameLevel(levels[1], "a1", -48, 176, 50)
				sameLevel(levels[2], "a2", 208, 432, 50)
				-- the graph is asked for the loaded map
				expect(state.loads[1]).to.equal("test_floor_map")
			end
		},
		{
			-- breaks if: a graph with no level (or too few ground nodes) is returned as an empty list
			name = "ForMap: a graph that gives no level answers nil, \"no graph\"",
			func = function(state)
				-- air nodes only
				standIn(state, {test_floor_map = {nodes = cluster(0, 100, AIR)}})

				local levels, err = F().ForMap()

				expect(levels).to.beNil()
				expect(err).to.equal("no graph")
			end
		},
		{
			-- breaks if: the cache is missing, shared between maps, or never emptied
			name = "ForMap: cached per map name (the AIN module is called once per map), read again when the name changes or after Reset",
			func = function(state)
				local nodes = cluster(0, 50)
				cluster(300, 50, GROUND, nodes)
				local other = cluster(1000, 50)

				standIn(state, {map_a = {nodes = nodes}, map_b = {nodes = other}})
				setMap(state, "map_a")

				local first = F().ForMap()
				local second = F().ForMap()

				expect(#state.loads).to.equal(1)
				expect(#first).to.equal(2)
				expect(second).to.equal(first)

				setMap(state, "map_b")
				local third = F().ForMap()

				expect(#state.loads).to.equal(2)
				expect(state.loads[2]).to.equal("map_b")
				expect(#third).to.equal(1)
				-- 1000 is bin 15 (960..1024)
				sameLevel(third[1], "a1", 912, 1136, 50)

				-- back to the first map: read again (only one map is kept)
				setMap(state, "map_a")
				expect(#F().ForMap()).to.equal(2)
				expect(#state.loads).to.equal(3)

				F().Reset()
				F().ForMap()
				expect(#state.loads).to.equal(4)

				-- a missing graph is remembered too, the file will not appear while the map is played
				setMap(state, "map_none")
				expect(F().ForMap()).to.beNil()
				expect(F().ForMap()).to.beNil()
				expect(#state.loads).to.equal(5)
			end
		},
		{
			-- breaks if: a missing module or a raising reader escapes
			name = "ForMap: a missing AIN module or a reader that raises gives nil and a reason, never an error",
			func = function(state)
				GryMod.Minimap.AIN = nil

				local levels, err = F().ForMap()

				expect(levels).to.beNil()
				expect(type(err)).to.equal("string")

				F().Reset()
				GryMod.Minimap.AIN = {Load = function() error("boom") end}
				levels, err = F().ForMap()

				expect(levels).to.beNil()
				expect(type(err)).to.equal("string")
			end
		},
		{
			-- breaks if: Current uses another rule than the slab that follows the feet (for example the levels of the node graph)
			name = "Current: the slab follows the feet in steps of 32 (z 0 is z0 from -56 to 72, z 16 is z1, z -91.97 is zn3), with no help from the node graph",
			func = function(state)
				-- a node graph that would give other levels: Current must not read it, nor even ask for it
				local nodes = cluster(0, 50)
				cluster(300, 50, GROUND, nodes)
				standIn(state, {map_graph = {nodes = nodes}})
				setMap(state, "map_graph")

				sameLevel(F().Current(0), "z0", -56, 72)
				F().Reset()
				sameLevel(F().Current(16), "z1", -24, 104)
				F().Reset()
				sameLevel(F().Current(-91.97), "zn3", -152, -24)
				F().Reset()
				sameLevel(F().Current(300), "z9", 232, 360)
				expect(#state.loads).to.equal(0)
			end
		},
		{
			-- breaks if: the hysteresis is missing, is not 16 + 12 = 28 units from the centre of the previous level, or is not symmetric
			name = "Current: hysteresis, from z = 0 the level stays z0 up to z = 28 then goes to z1; going down it stays z1 down to z = 4 and goes to z0 under",
			func = function()
				expect(F().Current(0).id).to.equal("z0")
				-- 16 would be z1 by itself (and 20, 28) but the player is on z0 and 28 is its limit
				expect(F().Current(16).id).to.equal("z0")
				expect(F().Current(20).id).to.equal("z0")
				expect(F().Current(28).id).to.equal("z0")
				-- over 28: z1, whose centre is 32 (limit 4 .. 60)
				sameLevel(F().Current(28.01), "z1", -24, 104)
				-- going down: z1 stays down to 4, which is 28 under its centre
				expect(F().Current(16).id).to.equal("z1")
				expect(F().Current(4).id).to.equal("z1")
				-- 3.9 is 28.1 from 32: the pure level of 3.9 is z0
				expect(F().Current(3.9).id).to.equal("z0")
				-- and downwards from z0: stays z0 down to -28, then zn1
				expect(F().Current(-16).id).to.equal("z0")
				expect(F().Current(-28).id).to.equal("z0")
				sameLevel(F().Current(-28.01), "zn1", -88, 40)
				-- up from zn1: it stays zn1 up to -4
				expect(F().Current(-16).id).to.equal("zn1")
				expect(F().Current(-4).id).to.equal("zn1")
				expect(F().Current(-3.9).id).to.equal("z0")
			end
		},
		{
			-- breaks if: a jump of several levels is held back by the hysteresis, or Reset does not forget the previous level
			name = "Current: a jump of several levels follows at once; Reset forgets the previous level",
			func = function()
				expect(F().Current(0).id).to.equal("z0")
				-- far from the previous level: the pure level of 300 (N = floor(9.375 + 0.5) = 9)
				expect(F().Current(300).id).to.equal("z9")
				expect(F().Current(-300).id).to.equal("zn9")

				F().Reset()
				-- no previous level: the pure level (16 is z1), the same as Fallback
				expect(F().Current(16).id).to.equal("z1")
				F().Reset()
				expect(F().Current(16).id).to.equal(F().Fallback(16).id)
				-- a pure function: Fallback has no memory
				expect(F().Fallback(0).id).to.equal("z0")
				expect(F().Fallback(20).id).to.equal("z1")
			end
		},
		{
			-- breaks if: the histogram or the margins change; the numbers come from an independent script on the shipped file
			name = "real d1_trainstation_03: 157 ground nodes, three levels (peaks 0..64, 256..320 and 384..448; the last two slabs overlap)",
			func = function(state)
				local nodes = readNodes("d1_trainstation_03")

				expect(nodes ~= nil).to.beTrue()

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(3)
				sameLevel(levels[1], "a1", -48, 176, 22)
				sameLevel(levels[2], "a2", 208, 432, 56)
				-- 384..448: zlo = 384 - 48 = 336 is under the top of a2 (432), the two slabs overlap
				sameLevel(levels[3], "a3", 336, 560, 49)
				-- at z = 300 the nearest peak below is the one of a2 (256), at z = 400 it is the one of a3 (384)
				expect(F().LevelAt(levels, 300).id).to.equal("a2")
				expect(F().LevelAt(levels, 400).id).to.equal("a3")
				expect(F().LevelAt(levels, 350).id).to.equal("a2")
			end
		},
		{
			-- breaks if: as above
			name = "real d3_citadel_03: 266 ground nodes, two levels (peaks 2048..2176 and 2304..2368)",
			func = function()
				local nodes = readNodes("d3_citadel_03")

				expect(nodes ~= nil).to.beTrue()

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(2)
				sameLevel(levels[1], "a1", 2000, 2288, 169)
				sameLevel(levels[2], "a2", 2256, 2480, 74)
			end
		},
		{
			-- breaks if: adjacent bins are no longer merged
			name = "real d1_canals_05: the bins -512..-384 and -384..-320 touch, so they make one level (-560 to -208)",
			func = function()
				local nodes = readNodes("d1_canals_05")

				expect(nodes ~= nil).to.beTrue()

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -560, -208, 290)
			end
		},
		{
			-- breaks if: as above
			name = "real ep2_outland_07: 369 ground nodes, the main peak 128..192 and its neighbours merge into one wide level (-48 to 432)",
			func = function()
				local nodes = readNodes("ep2_outland_07")

				expect(nodes ~= nil).to.beTrue()

				local levels = F().FromNodes(nodes)

				expect(#levels).to.equal(1)
				sameLevel(levels[1], "a1", -48, 432, 347)
			end
		},
		{
			-- breaks if: a map without sharp peaks makes the function raise or return garbage
			name = "real d1_town_02 (continuous heights): no error, few levels, sorted, every slab well formed",
			func = function()
				local nodes = readNodes("d1_town_02")

				expect(nodes ~= nil).to.beTrue()

				local levels = F().FromNodes(nodes)

				-- the reference script finds one main level and two small ones on 466 ground nodes
				expect(#levels).to.equal(3)
				sameLevel(levels[1], "a1", -3632, -3088, 328)
				sameLevel(levels[2], "a2", -3184, -2960, 57)
				sameLevel(levels[3], "a3", -3056, -2832, 36)

				for i = 1, #levels do
					expect(levels[i].zlo < levels[i].zhi).to.beTrue()

					if i > 1 then
						expect(levels[i].zlo > levels[i - 1].zlo).to.beTrue()
					end
				end
			end
		}
	}
}
