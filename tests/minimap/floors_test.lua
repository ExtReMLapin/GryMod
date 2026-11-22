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

-- the height classes of the slab's top (A + C), from the design
local CLASSES = {56, 88, 120, 160, 224, 320, 448}

local function isClass(c)
	for _, v in ipairs(CLASSES) do
		if v == c then
			return true
		end
	end

	return false
end

-- the rule of the design for an anchor level (floor A, class C) to be usable with feet at f and a highest ceiling at c (written here again, independent
-- of the module): the floor window, the class under the ceiling (or the lowest class, 56, when there is no room), and the head cut inside (not for
-- the class 56: a cut under the head in a low duct)
local function compatible(level, f, c)
	local A, C = level.fz, level.cls

	return A - 24 <= f and f <= A + 40 and (C == 56 or A + C >= f + 72) and (C == 56 or C <= c - A - 8)
end

-- what a ray gives: a ceiling at height h, the sky, or nothing (the Vector is the hit position the engine gives)
local function ceil(h)
	return {Hit = true, HitSky = false, HitPos = Vector(0, 0, h)}
end

local function sky()
	return {Hit = true, HitSky = true, HitPos = Vector(0, 0, 32768)}
end

local function nothing()
	return {Hit = false, HitSky = false, HitPos = Vector(0, 0, 32768)}
end

-- the five rays of an evaluation, by their place around the feet: centre, then 48 units to +X, -X, +Y and -Y of the world
local function rays(state, centre, px, nx, py, ny)
	state.rays = {c = centre, ["+x"] = px or centre, ["-x"] = nx or centre, ["+y"] = py or centre, ["-y"] = ny or centre}
end

-- the number of evaluations (five rays each) the stand-in saw
local function rounds(state)
	expect(#state.traces % 5).to.equal(0)

	return #state.traces / 5
end

-- the sorted list of the floors (A) of the anchors the module knows
local function knownFloors()
	local list = {}

	for _, level in ipairs(F().Known()) do
		list[#list + 1] = level.fz
	end

	table.sort(list)

	return list
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
		state.realTraceLine = util.TraceLine
		state.realGetWorld = game.GetWorld
		state.realRealTime = RealTime
		state.map = "test_floor_map"
		game.GetMap = function() return state.map end

		-- stand-ins for CurrentAt: the ray (every call is recorded, the answer is state.ray), the world with its bounds, and the clock
		state.now = 100
		state.traces = {}
		state.boundsCalls = 0
		state.world = {
			GetModelBounds = function()
				state.boundsCalls = state.boundsCalls + 1

				return Vector(-1000, -2000, -300), Vector(3000, 4000, 900)
			end
		}
		-- every ray gets state.ray (a ceiling at 147 by default) unless state.rays has an answer for its place (key c, +x, -x, +y, -y) around
		-- (state.ox, state.oy), the place the test calls CurrentAt at
		state.ray = ceil(147)
		state.ox, state.oy = 0, 0
		state.rays = nil
		util.TraceLine = function(t)
			state.traces[#state.traces + 1] = t

			if state.rays then
				local dx, dy = t.start.x - state.ox, t.start.y - state.oy
				local key = (dx == 0 and dy == 0 and "c") or (dx == 48 and dy == 0 and "+x") or (dx == -48 and dy == 0 and "-x") or (dx == 0 and dy == 48 and "+y") or (dx == 0 and dy == -48 and "-y")

				if key and state.rays[key] then
					return state.rays[key]
				end
			end

			return state.ray
		end
		game.GetWorld = function() return state.world end
		RealTime = function() return state.now end

		-- a stand-in of the Cache module (written by another agent): the ids of the levels that have tiles on disk, state.known, none by default
		state.realCache = GryMod.Minimap.Cache
		state.known = {}
		state.knownCalls = 0
		GryMod.Minimap.Cache = {
			KnownLevels = function()
				state.knownCalls = state.knownCalls + 1

				return state.known
			end
		}

		if F().Reset then
			F().Reset()
		end
	end,
	afterEach = function(state)
		-- always put the real ones back, also when a case failed
		pcall(function() GryMod.Minimap.AIN = state.realAIN end)
		pcall(function() game.GetMap = state.realGetMap end)
		pcall(function() util.TraceLine = state.realTraceLine end)
		pcall(function() game.GetWorld = state.realGetWorld end)
		pcall(function() RealTime = state.realRealTime end)
		pcall(function() GryMod.Minimap.Cache = state.realCache end)
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
			-- breaks if: a level of Fallback or Current has no z, or the z is not the quantised height N * 32 (the one the slab is built on)
			name = "Fallback and Current levels carry z = N * 32, the quantised foot height (also when the hysteresis keeps the previous level)",
			func = function()
				expect(F().Fallback(0).z).to.equal(0)
				expect(F().Fallback(16).z).to.equal(32)
				expect(F().Fallback(15.9).z).to.equal(0)
				-- N = -3
				expect(F().Fallback(-91.97).z).to.equal(-96)
				expect(F().Fallback(5000).z).to.equal(4992)

				local level = F().Fallback(-91.97)

				expect(level.zlo).to.equal(level.z - 56)
				expect(level.zhi).to.equal(level.z + 72)

				expect(F().Current(20).z).to.equal(32)
				F().Reset()
				expect(F().Current(0).z).to.equal(0)
				-- 20 would be z1 (z = 32) by itself, the previous level z0 is kept and so is its z
				expect(F().Current(20).z).to.equal(0)
				expect(F().Current(20).id).to.equal("z0")
				expect(F().Current(-91.97).z).to.equal(-96)
			end
		},
		{
			-- breaks if: Below is not one storey (128 units) under the level's z, or builds its slab another way than Fallback does
			name = "Below: the level of the height level.z - 128 (z0 gives zn4 from -184 to -56, z4 gives z0)",
			func = function()
				local below = F().Below(F().Fallback(0))

				sameLevel(below, "zn4", -184, -56)
				expect(below.z).to.equal(-128)

				-- z = 128 is N = 4, a storey under it is N = 0
				local four = F().Fallback(128)

				expect(four.id).to.equal("z4")

				local down = F().Below(four)

				sameLevel(down, "z0", -56, 72)
				expect(down.z).to.equal(0)

				-- it is a Fallback of z - 128, whatever the level's slab says
				local odd = F().Below({id = "x", z = 200, zlo = 0, zhi = 1})

				sameLevel(odd, "z2", 8, 136)
				expect(odd.z).to.equal(64)
			end
		},
		{
			-- breaks if: a negative level is mishandled (the id prefix, the rounding of a negative height)
			name = "Below: negative levels (zn4 gives zn8), a level read from Current, and two storeys down",
			func = function()
				local negative = F().Fallback(-128)

				expect(negative.id).to.equal("zn4")

				local lower = F().Below(negative)

				sameLevel(lower, "zn8", -312, -184)
				expect(lower.z).to.equal(-256)

				-- z1 (z = 32): a storey lower is -96, N = -3
				local one = F().Below(F().Fallback(32))

				sameLevel(one, "zn3", -152, -24)
				expect(one.z).to.equal(-96)

				-- the level of Current (z 5 is z0) and two storeys down
				local twice = F().Below(F().Below(F().Current(5)))

				expect(twice.id).to.equal("zn8")
				expect(twice.z).to.equal(-256)
			end
		},
		{
			-- breaks if: Below keeps a memory, changes the hysteresis of Current, or changes its argument
			name = "Below is pure: it does not touch the previous level of Current nor the level it is given",
			func = function()
				local level = F().Current(0)

				expect(level.id).to.equal("z0")
				F().Below(level)
				F().Below(F().Fallback(1000))
				-- 20 is z1 by itself: the previous level z0 is still kept
				expect(F().Current(20).id).to.equal("z0")
				-- the level was not modified
				expect(level.id).to.equal("z0")
				expect(level.z).to.equal(0)
				expect(level.zlo).to.equal(-56)
				expect(level.zhi).to.equal(72)
				-- the same level gives the same answer
				expect(F().Below(level).id).to.equal(F().Below(level).id)
			end
		},
		{
			-- breaks if: a bad argument raises or gives a level
			name = "Below: a missing level or a level without a numeric z gives nil, \"bad level\", never an error",
			func = function()
				for _, bad in ipairs({{}, {id = "z0"}, {z = "0"}, {z = 0 / 0}, {z = math.huge}, {z = true}}) do
					local level, err = F().Below(bad)

					expect(level).to.beNil()
					expect(err).to.equal("bad level")
				end

				local level, err = F().Below(nil)

				expect(level).to.beNil()
				expect(err).to.equal("bad level")

				level, err = F().Below("z0")

				expect(level).to.beNil()
				expect(err).to.equal("bad level")
			end
		},
		{
			-- breaks if: the centre ray's sky does not open the level, or a lateral ray's sky does, or the highest ceiling over 512 does not
			name = "CurrentAt: the centre ray in the sky (or hitting nothing) gives the open level; a lateral ray in the sky does not; a highest ceiling over 512 does",
			func = function(state)
				state.ray = sky()

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("open")
				expect(level.open).to.beTrue()
				expect(level.z).to.equal(0)
				-- the bounds of the stand-in world are z -300 .. 900
				expect(level.zlo).to.equal(-316)
				expect(level.zhi).to.equal(916)
				expect(level.fz).to.beNil()
				-- the open level makes no anchor
				expect(#F().Known()).to.equal(0)

				F().Reset()
				state.ray = nothing()
				level = F().CurrentAt(Vector(0, 0, 40))

				expect(level.id).to.equal("open")
				expect(level.z).to.equal(40)

				-- a skylight: the centre has a ceiling, the four others see the sky or nothing, they are ignored
				F().Reset()
				rays(state, ceil(150), sky(), nothing(), sky(), sky())
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- the player is outside: the centre sees the sky although the four others hit something
				F().Reset()
				rays(state, sky(), ceil(150), ceil(150), ceil(150), ceil(150))
				expect(F().CurrentAt(Vector(0, 0, 0)).open).to.beTrue()

				-- the highest ceiling (here a lateral one, 600 over the feet) counts as open
				F().Reset()
				rays(state, ceil(300), ceil(600))
				expect(F().CurrentAt(Vector(0, 0, 0)).open).to.beTrue()

				-- 513 over the feet is open, 512 is not
				F().Reset()
				state.rays = nil
				state.ray = ceil(513)
				expect(F().CurrentAt(Vector(0, 0, 0)).open).to.beTrue()
				F().Reset()
				state.ray = ceil(512)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c448")
			end
		},
		{
			-- breaks if: the shape of an anchor level, its id or its slab (A - 56 .. A + C) change
			name = "CurrentAt: a ceiling at 150 over the feet makes the anchor f0c120 (fz, cls, top, z, zlo -56, zhi 120), remembered in the registry",
			func = function(state)
				state.ray = ceil(150)

				local level = F().CurrentAt(Vector(0, 0, 0))

				-- A = floor(0 / 16 + 0.5) * 16 = 0; the room under the ceiling is 150 - 0 - 8 = 142: the biggest class under it is 120
				expect(level.id).to.equal("f0c120")
				expect(level.fz).to.equal(0)
				expect(level.cls).to.equal(120)
				expect(level.top).to.equal(120)
				expect(level.z).to.equal(0)
				expect(level.zlo).to.equal(-56)
				expect(level.zhi).to.equal(120)
				expect(level.open).to.beNil()

				local known = F().Known()

				expect(#known).to.equal(1)
				expect(known[1].id).to.equal("f0c120")
			end
		},
		{
			-- breaks if: a class limit is off by one, the minimum 56 is lost, or a class is missing
			name = "CurrentAt: the class is the biggest of 56 88 120 160 224 320 448 that is <= the ceiling - A - 8 (56 also when there is no room)",
			func = function(state)
				-- {ceiling, class}: the room is the ceiling - 8 for feet at 0
				local table_ = {
					{20, 56}, {63, 56}, {64, 56}, {80, 56}, {95, 56}, {96, 88}, {127, 88}, {128, 120}, {167, 120}, {168, 160}, {231, 160}, {232, 224},
					{327, 224}, {328, 320}, {455, 320}, {456, 448}, {512, 448}
				}

				for _, row in ipairs(table_) do
					F().Reset()
					state.ray = ceil(row[1])

					local level = F().CurrentAt(Vector(0, 0, 0))

					expect(level.id).to.equal("f0c" .. row[2])
					expect(level.cls).to.equal(row[2])
					expect(level.zhi).to.equal(row[2])
					expect(level.zlo).to.equal(-56)
				end

				-- 95 gives 56, not 88 (the slab of 88 would go over the ceiling and its top face would hide the room): its top is under the ceiling - 8
				F().Reset()
				state.ray = ceil(95)
				expect(F().CurrentAt(Vector(0, 0, 0)).zhi).to.equal(56)

				-- under 64 over the floor there is no room for a player: the class 56 all the same (the lowest there is), its top over the ceiling - 8
				F().Reset()
				state.ray = ceil(40)

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("f0c56")
				expect(level.zhi).to.equal(56)
			end
		},
		{
			-- breaks if: A is not the feet rounded to 16 (half up), or a negative floor is written without the n prefix
			name = "CurrentAt: A is the feet rounded to 16 (24 gives 32, 20 gives 16), the room counts from A; negative numbers are written with n (fn96c120)",
			func = function(state)
				-- f 20: 20 / 16 + 0.5 = 1.75 -> 1 -> A 16; room = 170 - 16 - 8 = 146 -> 120
				state.ray = ceil(170)
				expect(F().CurrentAt(Vector(0, 0, 20)).id).to.equal("f16c120")

				-- f 24: 24 / 16 + 0.5 = 2 -> A 32; room = 174 - 32 - 8 = 134 -> 120
				F().Reset()
				state.ray = ceil(174)
				expect(F().CurrentAt(Vector(0, 0, 24)).id).to.equal("f32c120")

				-- f -100: -6.25 + 0.5 = -5.75 -> -6 -> A -96; room = 50 + 96 - 8 = 138 -> 120
				F().Reset()
				state.ray = ceil(50)

				local level = F().CurrentAt(Vector(0, 0, -100))

				expect(level.id).to.equal("fn96c120")
				expect(level.fz).to.equal(-96)
				expect(level.top).to.equal(24)
				expect(level.zlo).to.equal(-152)
				expect(level.zhi).to.equal(24)

				-- a low ceiling at -10: room = 86 - 8 = 78, class 56, top -40 (under the ceiling - 8 = -18)
				F().Reset()
				state.ray = ceil(-10)
				level = F().CurrentAt(Vector(0, 0, -100))

				expect(level.id).to.equal("fn96c56")
				expect(level.zhi).to.equal(-40)
			end
		},
		{
			-- breaks if: the ceiling is the lowest or the centre one instead of the highest of the five
			name = "CurrentAt: the ceiling kept is the highest of the five rays (a pipe on a ray, even on the centre one, does not lower it; the skies are ignored)",
			func = function(state)
				-- the pipe at 90 on one lateral ray
				rays(state, ceil(150), ceil(90))
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- the pipe on the centre one, the four others at 150
				F().Reset()
				rays(state, ceil(90), ceil(150), ceil(90), ceil(90), ceil(90))
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- the ceiling is at 90 everywhere: class 56 (room 82, 88 does not fit)
				F().Reset()
				state.rays = nil
				state.ray = ceil(90)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c56")

				-- the highest is a lateral one: 170 (room 162, class 160) over the centre's 150
				F().Reset()
				rays(state, ceil(150), ceil(170), sky(), nothing(), ceil(120))
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c160")

				-- the four others in the sky: the centre's ceiling
				F().Reset()
				rays(state, ceil(150), sky(), sky(), sky(), sky())
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")
			end
		},
		{
			-- breaks if: a ray does not start 72 over the feet, is not straight up, does not use the brush mask, or the five places are wrong
			name = "CurrentAt: five rays from 72 over the feet straight up to 32768, one at the centre and four 48 units away along +X -X +Y -Y, with the brush mask",
			func = function(state)
				F().CurrentAt(Vector(10, 20, 5))

				expect(#state.traces).to.equal(5)

				local starts = {}

				for _, t in ipairs(state.traces) do
					starts[t.start.x .. "," .. t.start.y .. "," .. t.start.z] = true
					expect(t.endpos.x).to.equal(t.start.x)
					expect(t.endpos.y).to.equal(t.start.y)
					expect(t.endpos.z).to.equal(32773)
					expect(t.mask).to.equal(MASK_SOLID_BRUSHONLY)
				end

				for _, key in ipairs({"10,20,77", "58,20,77", "-38,20,77", "10,68,77", "10,-28,77"}) do
					expect(starts[key]).to.beTrue()
				end
			end
		},
		{
			-- breaks if: a ceiling that moves a little makes new anchors or classes
			name = "CurrentAt: a ceiling that goes between 150 and 170 for 100 steps gives one anchor and one class",
			func = function(state)
				local ids = {}
				local count = 0

				for i = 1, 100 do
					state.now = state.now + 0.25
					state.ray = ceil(i % 2 == 1 and 150 or 170)

					local level = F().CurrentAt(Vector(60 * i, 0, 0))

					if not ids[level.id] then
						ids[level.id] = true
						count = count + 1
					end
				end

				expect(count).to.equal(1)
				expect(ids["f0c120"]).to.beTrue()
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: a bigger class is taken at once, never taken, or taken before one second; a smaller one is held when the ceiling drops
			name = "CurrentAt: the ceiling goes from 150 to 260 for good: the class goes up after one second, not before; a lower ceiling brings the lower class at once",
			func = function(state)
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- 260: room 252, class 224. The first measure is at 0 s, then every 0.25 s: 0.75 s after it nothing has changed
				state.ray = ceil(260)

				for i = 1, 4 do
					state.now = state.now + 0.25
					expect(F().CurrentAt(Vector(60 * i, 0, 0)).id).to.equal("f0c120")
				end

				-- a whole second after the first measure of the bigger class: it is taken
				state.now = state.now + 0.25
				expect(F().CurrentAt(Vector(300, 0, 0)).id).to.equal("f0c224")
				expect(#F().Known()).to.equal(2)

				-- the ceiling falls back to 150: 224 does not fit under it, the known f0c120 is taken at once (and nothing is created)
				state.ray = ceil(150)
				state.now = state.now + 0.25
				expect(F().CurrentAt(Vector(360, 0, 0)).id).to.equal("f0c120")
				expect(#F().Known()).to.equal(2)

				-- 260 again for good: the hold starts again from zero
				state.ray = ceil(260)

				for i = 1, 4 do
					state.now = state.now + 0.25
					expect(F().CurrentAt(Vector(360 + 60 * i, 0, 0)).id).to.equal("f0c120")
				end

				state.now = state.now + 0.25
				expect(F().CurrentAt(Vector(660, 0, 0)).id).to.equal("f0c224")
				expect(#F().Known()).to.equal(2)
			end
		},
		{
			-- breaks if: a class that was seen only now and then is taken (the hold is not reset when the better class goes away)
			name = "CurrentAt: a bigger class that is available for less than a second at a time is never taken (the hold starts again each time it goes away)",
			func = function(state)
				state.ray = ceil(150)
				F().CurrentAt(Vector(0, 0, 0))

				-- 0.75 s at 260, one measure at 150, 0.75 s at 260, ... for 20 rounds: never a whole second in a row
				local ids = {}

				for round = 1, 20 do
					state.ray = ceil(260)

					for i = 1, 3 do
						state.now = state.now + 0.25
						ids[F().CurrentAt(Vector(60 * (round * 4 + i), 0, 0)).id] = true
					end

					state.ray = ceil(150)
					state.now = state.now + 0.25
					ids[F().CurrentAt(Vector(60 * (round * 4 + 4), 0, 0)).id] = true
				end

				expect(ids["f0c224"]).to.beNil()
				expect(ids["f0c120"]).to.beTrue()
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: a usable current level is not kept, or one that is no longer usable is
			name = "CurrentAt: the current level is kept while it is usable (feet in A - 24 .. A + 40, class under the ceiling); the feet out of the window make a new anchor",
			func = function(state)
				state.ray = ceil(150)

				local first = F().CurrentAt(Vector(0, 0, 0))

				-- 60 units away, feet 30 up, ceiling 180 (a bigger class would fit, it is not taken at once): still f0c120, the same table
				state.ray = ceil(180)
				expect(F().CurrentAt(Vector(60, 0, 30))).to.equal(first)
				-- 24 under A, ceiling 150
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(120, 0, -24))).to.equal(first)
				expect(#F().Known()).to.equal(1)

				-- feet at 45 (over A + 40): a new anchor, A = floor(45 / 16 + 0.5) * 16 = 48, room = 195 - 48 - 8 = 139: 120
				state.ray = ceil(195)

				local second = F().CurrentAt(Vector(180, 0, 45))

				expect(second.id).to.equal("f48c120")
				expect(#F().Known()).to.equal(2)
			end
		},
		{
			-- breaks if: a class that does not fit under the ceiling is kept
			name = "CurrentAt: a ceiling too low for the class makes a new anchor (same floor, class 88), and it is kept when the ceiling goes up again",
			func = function(state)
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- ceiling 100: room 92, 120 does not fit; class 88
				state.ray = ceil(100)

				local low = F().CurrentAt(Vector(60, 0, 0))

				expect(low.id).to.equal("f0c88")
				expect(#F().Known()).to.equal(2)

				-- ceiling 150 again: the current f0c88 is still usable and kept (no jump up before a second)
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(120, 0, 0))).to.equal(low)
				expect(#F().Known()).to.equal(2)

				-- the registry has no duplicate: the same low ceiling again, a second later
				F().Reset()
				state.ray = ceil(90)
				F().CurrentAt(Vector(0, 0, 0))
				state.now = state.now + 2
				F().CurrentAt(Vector(1, 0, 0))
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: the choice among known anchors is not the biggest class, then the nearest floor
			name = "CurrentAt: with no current level the usable known anchor with the biggest class wins, then the nearest floor",
			func = function(state)
				-- f 10, c 200: f32c160 (floor 22 away), f16c160 (6 away) and f0c120 are all usable
				state.known = {"f32c160", "f0c120", "f16c160"}
				state.ray = ceil(200)
				expect(F().CurrentAt(Vector(0, 0, 10)).id).to.equal("f16c160")
				expect(#F().Known()).to.equal(3)

				-- the same floor: the bigger class
				F().Reset()
				state.known = {"f0c120", "f0c88"}
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- a class that does not fit under the ceiling is never taken: a new anchor
				F().Reset()
				state.known = {"f0c224"}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")
				expect(#F().Known()).to.equal(2)

				-- a floor that is out of the window of the feet is never taken
				F().Reset()
				state.known = {"f40c88"}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")
			end
		},
		{
			-- breaks if: the registry is not seeded from Cache.KnownLevels, is seeded more than once per map, or takes ids that are not anchors
			name = "CurrentAt: the registry is seeded once per map from Cache.KnownLevels (ids f<A>c<C> only, C a class), then the anchors are reused with no creation",
			func = function(state)
				state.known = {"f0c120", "fn96c88", "z3", "a1", "f5", "fx", "f0c120", "f100t50", "f1c", "f0c121", "f0c", "open", "fn5c"}
				state.ray = ceil(50)

				-- f -100, c 50: fn96c88 is usable (window -120 .. -56, A + C = -8 >= -28)
				local level = F().CurrentAt(Vector(0, 0, -100))

				expect(level.id).to.equal("fn96c88")
				expect(level.fz).to.equal(-96)
				expect(level.cls).to.equal(88)
				expect(level.top).to.equal(-8)
				expect(level.zlo).to.equal(-152)
				expect(level.zhi).to.equal(-8)
				expect(state.knownCalls).to.equal(1)

				-- only the two valid, different anchors; no creation
				local known = F().Known()

				expect(#known).to.equal(2)
				expect(known[1].id).to.equal("f0c120")
				expect(known[2].id).to.equal("fn96c88")

				-- more rays on the same map: no new seeding, the anchors are reused
				state.now = state.now + 2
				state.ray = ceil(150)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")
				expect(state.knownCalls).to.equal(1)
				expect(#F().Known()).to.equal(2)

				-- a new map name: seeded again, and the registry holds the new map's anchors only
				setMap(state, "another_map")
				state.known = {"f64c160"}
				state.now = state.now + 2
				state.ray = ceil(264)
				expect(F().CurrentAt(Vector(0, 0, 64)).id).to.equal("f64c160")
				expect(state.knownCalls).to.equal(2)
				expect(#F().Known()).to.equal(1)

				-- Reset empties the registry; the next ray seeds again
				F().Reset()
				expect(#F().Known()).to.equal(0)
				F().CurrentAt(Vector(0, 0, 64))
				expect(state.knownCalls).to.equal(3)
			end
		},
		{
			-- breaks if: a missing Cache, a KnownLevels that raises or answers badly stops CurrentAt
			name = "CurrentAt: without Cache.KnownLevels (missing, raising, or answering a non-table) it works with an empty registry",
			func = function(state)
				state.ray = ceil(150)

				GryMod.Minimap.Cache = nil
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				F().Reset()
				GryMod.Minimap.Cache = {}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				F().Reset()
				GryMod.Minimap.Cache = {KnownLevels = function() error("boom") end}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				F().Reset()
				GryMod.Minimap.Cache = {KnownLevels = function() return "f0c64" end}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: a slope makes an anchor every 32 units again, or going back down makes new ones
			name = "CurrentAt: on a slope (floor up 8 per 16 units, the ceiling 150 over it) a rise of 400 makes a few anchors of one class, and going back down makes none",
			func = function(state)
				util.TraceLine = function(t)
					state.traces[#state.traces + 1] = t

					return {Hit = true, HitSky = false, HitPos = Vector(t.start.x, t.start.y, t.start.z - 72 + 150)}
				end

				for k = 0, 50 do
					local level = F().CurrentAt(Vector(16 * k, 0, 8 * k))

					expect(level ~= nil and level.open == nil).to.beTrue()
				end

				local count = #F().Known()

				-- the window of an anchor is 62 wide and the rays are 48 units apart or more: about 9 anchors (one per 32 units would be 13 or more)
				expect(count >= 2).to.beTrue()
				expect(count <= 10).to.beTrue()

				-- one class only
				for _, level in ipairs(F().Known()) do
					expect(level.cls).to.equal(120)
				end

				-- two anchors are never closer than 32 units
				local floors = knownFloors()

				for i = 2, #floors do
					expect(floors[i] - floors[i - 1] >= 32).to.beTrue()
				end

				-- back down the same slope (a first ray at once): everything is reused
				state.now = state.now + 2

				for k = 50, 0, -1 do
					F().CurrentAt(Vector(16 * k, 0, 8 * k))
				end

				expect(#F().Known()).to.equal(count)

				-- and up again
				state.now = state.now + 2

				for k = 0, 50 do
					F().CurrentAt(Vector(16 * k, 0, 8 * k))
				end

				expect(#F().Known()).to.equal(count)
			end
		},
		{
			-- breaks if: any returned level is not usable with the feet and the highest ceiling it was chosen for, or its slab misses the head cut or the ceiling
			name = "CurrentAt: on 500 deterministic random positions every level is usable with (feet, highest ceiling), its class is one of the six, zlo <= f - 8 and f + 72 <= zhi <= c - 8",
			func = function(state)
				local seed = 20261121

				local function rnd(n)
					seed = (seed * 1664525 + 1013904223) % 4294967296

					return seed % n
				end

				-- a ray at random: the sky, nothing, or a ceiling 60 .. 512 over the feet
				local function lateral(f)
					local kind = rnd(5)

					if kind == 0 then
						return sky()
					elseif kind == 1 then
						return nothing()
					end

					return ceil(f + 60 + rnd(453))
				end

				for i = 1, 500 do
					local f = rnd(2501) - 500
					local ox, oy = rnd(2000), rnd(2000)
					local centre = ceil(f + 60 + rnd(453))
					local px, nx, py, ny = lateral(f), lateral(f), lateral(f), lateral(f)
					local cmax = centre.HitPos.z

					for _, r in ipairs({px, nx, py, ny}) do
						if not r.HitSky and r.Hit and r.HitPos.z > cmax then
							cmax = r.HitPos.z
						end
					end

					state.ox, state.oy = ox, oy
					rays(state, centre, px, nx, py, ny)
					-- the clock moves on at each call so that each one shoots its rays
					state.now = state.now + 2

					local level = F().CurrentAt(Vector(ox, oy, f))

					expect(level.open).to.beNil()
					expect(isClass(level.cls)).to.beTrue()
					expect(compatible(level, f, cmax)).to.beTrue()
					expect(level.zlo <= f - 8).to.beTrue()

					-- the head cut is inside, except for the class 56 (a cut under the head in a low duct)
					if level.cls ~= 56 then
						expect(f + 72 <= level.zhi).to.beTrue()
					end

					-- the slab stays under the ceiling, except when there is no room for the lowest class (a ceiling under A + 64)
					if cmax >= level.fz + 64 then
						expect(level.zhi <= cmax - 8).to.beTrue()
					end

					expect(level.zhi).to.equal(level.fz + level.cls)
					expect(level.top).to.equal(level.zhi)
					expect(level.zlo).to.equal(level.fz - 56)
				end

				-- many positions, a bounded number of anchors
				expect(#F().Known() < 500).to.beTrue()

				-- the centre in the sky, or a highest ceiling over 512: open
				for i = 1, 50 do
					local f = rnd(1000) - 200

					state.now = state.now + 2
					rays(state, sky(), ceil(f + 200))
					state.ox, state.oy = 0, 0
					expect(F().CurrentAt(Vector(0, 0, f)).open).to.beTrue()

					state.now = state.now + 2
					rays(state, ceil(f + 200), ceil(f + 513 + rnd(500)))
					expect(F().CurrentAt(Vector(0, 0, f)).open).to.beTrue()
				end
			end
		},
		{
			-- breaks if: the level is not remembered, or the rays are not shot again after 48 units or after one second
			name = "CurrentAt: the level is remembered (the five rays once for two calls); new rays after more than 48 units (3D) or after one second",
			func = function(state)
				local first = F().CurrentAt(Vector(0, 0, 0))
				local second = F().CurrentAt(Vector(0, 0, 0))

				expect(rounds(state)).to.equal(1)
				expect(second).to.equal(first)

				-- 40 units away (3D), 48 exactly, and 20 up: still the remembered level
				F().CurrentAt(Vector(40, 0, 0))
				F().CurrentAt(Vector(48, 0, 0))
				F().CurrentAt(Vector(0, 0, 20))
				expect(rounds(state)).to.equal(1)

				-- over 48: new rays, shot from that place (the centre ray is among them)
				F().CurrentAt(Vector(49, 0, 0))
				expect(rounds(state)).to.equal(2)

				local xs = {}

				for i = 6, 10 do
					xs[state.traces[i].start.x] = true
				end

				expect(xs[49]).to.beTrue()
				expect(xs[97]).to.beTrue()
				expect(xs[1]).to.beTrue()

				-- the distance counts from the place of the last rays
				F().CurrentAt(Vector(49, 48, 0))
				expect(rounds(state)).to.equal(2)
				F().CurrentAt(Vector(49, 0, 0.5))
				expect(rounds(state)).to.equal(2)
				-- 3D: 30 on one axis and 40 on another make 50
				F().CurrentAt(Vector(79, 40, 0))
				expect(rounds(state)).to.equal(3)

				-- time: half a second after the last rays nothing, one second new rays
				state.now = state.now + 0.5
				F().CurrentAt(Vector(79, 40, 0))
				expect(rounds(state)).to.equal(3)
				state.now = state.now + 0.5
				F().CurrentAt(Vector(79, 40, 0))
				expect(rounds(state)).to.equal(4)
				-- the second counts from those last rays
				state.now = state.now + 0.5
				F().CurrentAt(Vector(79, 40, 0))
				expect(rounds(state)).to.equal(4)
			end
		},
		{
			-- breaks if: the remembered level costs an engine call (other than the clock)
			name = "CurrentAt: between two shots the remembered level is given back with no ray, no bounds, no known-levels read",
			func = function(state)
				F().CurrentAt(Vector(0, 0, 0))

				local traces, knownCalls = #state.traces, state.knownCalls

				for i = 1, 100 do
					F().CurrentAt(Vector(i % 10, 0, 0))
				end

				expect(#state.traces).to.equal(traces)
				expect(state.knownCalls).to.equal(knownCalls)
				expect(state.boundsCalls).to.equal(0)
			end
		},
		{
			-- breaks if: the open level is not remembered, or the bounds of the world are asked at every shot (and not once per map name)
			name = "CurrentAt: the bounds of the world are asked once per map name (a new name asks again, Reset too)",
			func = function(state)
				state.ray = sky()

				F().CurrentAt(Vector(0, 0, 0))
				expect(state.boundsCalls).to.equal(1)
				expect(rounds(state)).to.equal(1)

				-- the open level is remembered like any other
				F().CurrentAt(Vector(1, 0, 0))
				expect(rounds(state)).to.equal(1)

				-- new rays, the same map: the bounds are not asked again
				state.now = state.now + 2
				F().CurrentAt(Vector(1, 0, 0))
				expect(rounds(state)).to.equal(2)
				expect(state.boundsCalls).to.equal(1)

				-- the map changes: the bounds are asked again
				setMap(state, "another_map")
				state.now = state.now + 2
				F().CurrentAt(Vector(1, 0, 0))
				expect(state.boundsCalls).to.equal(2)

				F().Reset()
				F().CurrentAt(Vector(1, 0, 0))
				expect(state.boundsCalls).to.equal(3)
			end
		},
		{
			-- breaks if: Reset leaves the remembered level or the registry
			name = "CurrentAt: Reset forgets the remembered level (new rays) and the registry of anchors",
			func = function(state)
				F().CurrentAt(Vector(0, 0, 0))
				expect(#F().Known()).to.equal(1)
				F().Reset()
				expect(#F().Known()).to.equal(0)
				F().CurrentAt(Vector(0, 0, 0))
				expect(rounds(state)).to.equal(2)
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: Known hands out the registry itself
			name = "Known: a copy of the registry (changing it changes nothing), empty at the start",
			func = function(state)
				expect(#F().Known()).to.equal(0)

				F().CurrentAt(Vector(0, 0, 0))

				local known = F().Known()

				known[1].top = 9999
				known[2] = {id = "x"}
				table.remove(known, 1)

				local again = F().Known()

				expect(#again).to.equal(1)
				expect(again[1].id).to.equal("f0c120")
				expect(again[1].top).to.equal(120)
			end
		},
		{
			-- breaks if: Current shoots a ray, or reads the world
			name = "Current, Fallback and Below stay pure: no ray, no bounds, no registry",
			func = function(state)
				F().Current(0)
				F().Current(300)
				F().Fallback(10)
				F().Below(F().Fallback(10))

				expect(#state.traces).to.equal(0)
				expect(state.boundsCalls).to.equal(0)
				expect(#F().Known()).to.equal(0)
			end
		},
		{
			-- breaks if: the class 56 has the head-cut rule, a class 88 is usable under a ceiling that has no room for it, or the 56 never goes up
			name = "CurrentAt: the class 56 under a low ceiling (a duct) is kept though its top is under the head; a known class 88 is not usable there; 56 goes up after a second",
			func = function(state)
				-- ceiling 64: room 56, class 56, top 56 (under f + 72 = 72: the head cut does not apply to this class)
				state.ray = ceil(64)

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("f0c56")
				expect(level.zlo).to.equal(-56)
				expect(level.zhi).to.equal(56)

				-- a second later, 10 units up: still usable, the same table
				state.now = state.now + 2
				expect(rawequal(F().CurrentAt(Vector(0, 0, 10)), level)).to.beTrue()
				expect(#F().Known()).to.equal(1)

				-- a known 88 is not usable under a ceiling at 90 (room 82): a new anchor of class 56; a known 56 is
				F().Reset()
				state.known = {"f0c88"}
				state.ray = ceil(90)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c56")
				expect(#F().Known()).to.equal(2)

				F().Reset()
				state.known = {"f0c56"}
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c56")
				expect(#F().Known()).to.equal(1)

				-- the room appears for good (150): 120 is taken after one second in a row, not before
				F().Reset()
				state.known = {}
				state.ray = ceil(64)
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c56")
				state.ray = ceil(150)

				for i = 1, 4 do
					state.now = state.now + 0.25
					expect(F().CurrentAt(Vector(60 * i, 0, 0)).id).to.equal("f0c56")
				end

				state.now = state.now + 0.25
				expect(F().CurrentAt(Vector(300, 0, 0)).id).to.equal("f0c120")
			end
		},
		{
			-- breaks if: Fallback or Current raises on nil, or makes "znan" / "zinf" levels out of NaN and infinity
			name = "Fallback and Current: a z that is nil, NaN, infinite or not a number gives nil, \"bad z\", and does not change the previous level of Current",
			func = function()
				for _, bad in ipairs({0 / 0, math.huge, -math.huge, "5", true, {}}) do
					local level, err = F().Fallback(bad)

					expect(level).to.beNil()
					expect(err).to.equal("bad z")

					level, err = F().Current(bad)

					expect(level).to.beNil()
					expect(err).to.equal("bad z")
				end

				-- nil (not through ipairs: it would stop the list)
				local level, err = F().Fallback(nil)

				expect(level).to.beNil()
				expect(err).to.equal("bad z")

				level, err = F().Current(nil)

				expect(level).to.beNil()
				expect(err).to.equal("bad z")

				-- a bad answer leaves the memory of Current alone: z0 is still the previous level, 20 is kept in it
				expect(F().Current(0).id).to.equal("z0")
				F().Current(nil)
				F().Current(0 / 0)
				expect(F().Current(20).id).to.equal("z0")

				-- good values are as before
				expect(F().Fallback(0).id).to.equal("z0")
				expect(F().Fallback(-91.97).id).to.equal("zn3")
			end
		},
		{
			-- breaks if: a bad position raises or shoots a ray, or a failing engine call stops the radar
			name = "CurrentAt: a bad position gives nil, \"bad position\"; a centre ray that raises or answers badly gives the plain slab of the step, a lateral one that raises is ignored",
			func = function(state)
				for _, bad in ipairs({{}, {x = 0, y = 0}, {x = "0", y = 0, z = 0}, {x = 0, y = 0, z = 0 / 0}, {x = 0, y = 0, z = math.huge}, "p", 5}) do
					local level, err = F().CurrentAt(bad)

					expect(level).to.beNil()
					expect(err).to.equal("bad position")
				end

				local level, err = F().CurrentAt(nil)

				expect(level).to.beNil()
				expect(err).to.equal("bad position")
				expect(#state.traces).to.equal(0)

				util.TraceLine = function() error("boom") end
				level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("z0")
				expect(level.z).to.equal(0)
				expect(level.zlo).to.equal(-56)
				expect(level.zhi).to.equal(72)

				F().Reset()
				util.TraceLine = function() return nil end
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("z0")

				-- only the lateral rays raise: the centre's ceiling is used
				F().Reset()
				util.TraceLine = function(t)
					if t.start.x ~= 0 or t.start.y ~= 0 then
						error("boom")
					end

					return ceil(150)
				end
				expect(F().CurrentAt(Vector(0, 0, 0)).id).to.equal("f0c120")

				-- a world that is not there: the open level cannot be built, the plain slab is given
				F().Reset()
				util.TraceLine = function() return sky() end
				game.GetWorld = function() return nil end
				level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("z0")
				expect(level.open).to.beNil()
			end
		},
		{
			-- gm_construct, measured 2026-11-22: the world's bounds go up to 15360 because the 3D skybox is a small room far above the map (its camera at 10991), and the
			-- sky of the playable area is at 9984. The open level took the whole height, so the camera looked at the little skybox room first: no map in the minimap.
			-- breaks if: the open level keeps the world's top when ground nodes see the sky lower than it, or the cap is not the highest sky seen, or the id stays "open"
			-- (the tiles already made with the wrong slab, under that id, would be used again)
			-- The top is rounded DOWN to a multiple of 64 after taking 16 off (the slab ends under the hit, never over it): a sky at 1000 gives 960.
			name = "Outside: the map's open level ends at the highest SKY seen by the ground nodes' up rays when that is lower than the world's top (id open_t960 for a sky at 1000)",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}

				local nodes = cluster(0, 10)
				local skyAt = {}

				for i, node in ipairs(nodes) do
					skyAt[node.x] = (i == 4) and 1000 or 900 -- one node sees the sky a little higher than the others
				end

				standIn(state, {[state.map] = {nodes = nodes}})
				-- the nodes' rays: the sky at the height of the place; the player's (x 0) is under a ceiling at 150
				util.TraceLine = function(t)
					state.traces[#state.traces + 1] = t

					if t.start.x >= 10 then
						return {Hit = true, HitSky = true, HitPos = Vector(t.start.x, t.start.y, skyAt[t.start.x] or 900)}
					end

					return ceil(150)
				end

				local anchor = F().CurrentAt(Vector(0, 0, 0))
				local outside = F().Outside(anchor)

				expect(outside.open).to.beTrue()
				expect(outside.id).to.equal("open_t960")
				expect(outside.zlo).to.equal(-316)
				expect(outside.zhi).to.equal(960)
			end
		},
		{
			-- The owner's rule (2026-11-22): the camera goes where the up ray hits, indoors and outdoors alike. A map can have pieces over each other with void between:
			-- over the lower piece the ray hits the underside of the upper one (far over 512). The old rule said "open sky", the whole height, so the camera looked at
			-- the upper piece only.
			-- breaks if: a solid hit over 512 still gives the level of the whole height, or the slab ends over the hit (the upper piece comes in), or the id has no height
			name = "open level: a solid hit far over the feet (the underside of a piece above, void between) puts the top of the slab under it, id open_t<top>, not the world's whole height",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}
				standIn(state, {}) -- no graph
				state.ray = ceil(3000)

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.open).to.beTrue()
				expect(level.id).to.equal("open_t2944")
				expect(level.zlo).to.equal(-316)
				expect(level.zhi).to.equal(2944)
				expect(level.zhi < 3000).to.beTrue()
				expect(rounds(state)).to.equal(1)

				-- the same step of 64 is the same table; another step is another level
				state.now = state.now + 2
				state.ray = ceil(3010)
				expect(F().CurrentAt(Vector(100, 0, 0))).to.equal(level)

				state.now = state.now + 2
				state.ray = ceil(3100)

				local other = F().CurrentAt(Vector(200, 0, 0))

				expect(other.id).to.equal("open_t3072")
				expect(other.zhi).to.equal(3072)
				expect(other ~= level).to.beTrue()

				-- going back gives the first table again (one table per level, nothing is made twice)
				state.now = state.now + 2
				state.ray = ceil(3000)
				expect(F().CurrentAt(Vector(300, 0, 0))).to.equal(level)
			end
		},
		{
			-- breaks if: the open level under the sky at the player's place and the map's (the one Outside gives) are two tables for the same height: their tiles would be made twice
			name = "open level: the level of the sky seen by the player and the map's open level of the same height are the same table (the tiles are shared)",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}
				standIn(state, {}) -- no graph: the map's top comes from the player's own ray
				state.ray = {Hit = true, HitSky = true, HitPos = Vector(0, 0, 5000)}

				local outdoors = F().CurrentAt(Vector(0, 0, 0))

				-- 5000 - 16 = 4984, down to a multiple of 64: 4928
				expect(outdoors.id).to.equal("open_t4928")

				state.now = state.now + 2
				state.ray = ceil(150)

				local indoors = F().CurrentAt(Vector(500, 0, 0))

				expect(indoors.open).to.beNil()
				expect(F().Outside(indoors)).to.equal(outdoors)
			end
		},
		{
			-- breaks if: a sky that is higher than the world's top raises the slab, or nodes whose rays hit a ceiling (not the sky) cut it (a roof the graph does not reach
			-- would be lost), or the id changes when nothing is cut
			name = "open level: nothing is cut when no ray sees the sky, or when the sky seen is not under the world's top (id open, the world's heights with 16 of margin)",
			func = function(state)
				local nodes = cluster(0, 10)

				standIn(state, {[state.map] = {nodes = nodes}})
				-- the nodes' rays hit a ceiling at 400; the player's ray (the centre ray of CurrentAt, at x 0) sees the sky at 32768
				util.TraceLine = function(t)
					state.traces[#state.traces + 1] = t

					if t.start.x >= 10 then
						return ceil(400)
					end

					return sky()
				end

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(level.id).to.equal("open")
				expect(level.zlo).to.equal(-316)
				expect(level.zhi).to.equal(916)

				-- every ray sees the sky, above the world's top (900): the top stays 900
				F().Reset()
				standIn(state, {[state.map] = {nodes = nodes}})
				util.TraceLine = function(t)
					state.traces[#state.traces + 1] = t

					return {Hit = true, HitSky = true, HitPos = Vector(t.start.x, t.start.y, 5000)}
				end

				level = F().CurrentAt(Vector(0, 0, 0))
				expect(level.id).to.equal("open")
				expect(level.zhi).to.equal(916)
			end
		},
		{
			-- breaks if: a map with no node graph (84 maps of 230) gets no cap although the player stands under the open sky, or the player's sky costs one more ray
			name = "open level: with no node graph the sky seen by the player's own centre ray caps the slab, with no extra ray",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}
				state.ray = {Hit = true, HitSky = true, HitPos = Vector(0, 0, 9984)}
				standIn(state, {}) -- no graph

				local level = F().CurrentAt(Vector(0, 0, 0))

				-- 9984 - 16 = 9968, down to a multiple of 64: 9920
				expect(level.id).to.equal("open_t9920")
				expect(level.zhi).to.equal(9920)
				expect(rounds(state)).to.equal(1)
			end
		},
		{
			-- PeekAt is what the preload asks for each ground place of the node graph (the floors): the level CurrentAt would give a player standing there, with no player: no
			-- memory of a last shot, none made. breaks if: it gives another level than CurrentAt for the same rays, it spoils the remembered shot of the player (the next
			-- CurrentAt would shoot again, or give another level), or it holds a bigger class back as the player's clock does
			name = "PeekAt: the level CurrentAt gives for the same place (an anchor under a ceiling, the open level under the sky), without touching the remembered shot, and no hold",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}
				standIn(state, {})
				expect(isfunction(F().PeekAt)).to.beTrue()

				-- the player's own shot first: under a ceiling at 150
				state.ray = ceil(150)

				local mine = F().CurrentAt(Vector(0, 0, 0))

				expect(mine.id).to.equal("f0c120")
				expect(rounds(state)).to.equal(1)

				-- a place far away, on another floor (feet at 100: the floor 96), under a ceiling at 300: the class is taken at once, 160 (the biggest that fits under 300 - 96 - 8)
				-- (a hold is for a player who may be passing under a pipe)
				state.ray = ceil(300)

				local other = F().PeekAt(2000, 0, 100)

				expect(other.id).to.equal("f96c160")
				expect(rounds(state)).to.equal(2) -- five rays for the peek

				-- the remembered shot is the player's: no new ray, the same level
				expect(F().CurrentAt(Vector(1, 0, 0))).to.equal(mine)
				expect(rounds(state)).to.equal(2)

				-- the same place as the player's gives the same table (the registry is shared)
				state.ray = ceil(150)
				expect(F().PeekAt(0, 0, 0)).to.equal(mine)

				-- under the sky: the open level, the same table as OpenAt gives
				state.ray = {Hit = true, HitSky = true, HitPos = Vector(0, 0, 5000)}
				expect(F().PeekAt(0, 0, 0).id).to.equal("open_t4928")

				-- bad numbers, and a centre ray that fails (the plain slab of the step)
				local bad, why = F().PeekAt(0 / 0, 0, 0)

				expect(bad).to.beNil()
				expect(why).to.equal("bad position")

				util.TraceLine = function() error("no ray") end
				expect(F().PeekAt(0, 0, 0).id).to.equal("z0")
			end
		},
		{
			-- the preload asks the top of the map's own open level to leave out the places whose ray goes above the playable area (the cells at the fringe of a box, where the
			-- spread of the in/out map is wider than the ground). breaks if: it gives the world's top when the map's open level is cut at the sky, or nothing without a world
			name = "MapOpenTop: the top of the map's open level (cut at the sky seen by the nodes, else the world's top with the margin), nil without world bounds",
			func = function(state)
				expect(isfunction(F().MapOpenTop)).to.beTrue()

				-- no node graph, no ray that sees the sky: the world's top (900) with the margin
				standIn(state, {})
				state.ray = ceil(150)
				expect(F().MapOpenTop()).to.equal(916)

				-- nodes that see the sky at 1000 under a world that goes up to 15360: 960
				F().Reset()
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}

				local nodes = cluster(0, 10)

				standIn(state, {[state.map] = {nodes = nodes}})
				util.TraceLine = function(t)
					return {Hit = true, HitSky = true, HitPos = Vector(t.start.x, t.start.y, 1000)}
				end
				expect(F().MapOpenTop()).to.equal(960)

				-- no world
				F().Reset()
				game.GetWorld = function() return nil end
				expect(F().MapOpenTop()).to.beNil()
			end
		},
		{
			-- OpenAt is what the tile preload asks for each outdoor place of the in/out map: the same level the game would give a player standing there, without
			-- a player. breaks if: it answers another table than CurrentAt for the same height (tiles made twice), shoots more than one ray, or gives a level under a roof
			name = "OpenAt: one up ray from the place gives the open level of its hit (the very table CurrentAt gives), nothing under a roof (within 512), a level under the piece above far over it",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}
				standIn(state, {})
				expect(isfunction(F().OpenAt)).to.beTrue()

				-- the sky at 5000
				state.ray = {Hit = true, HitSky = true, HitPos = Vector(0, 0, 5000)}

				local level = F().OpenAt(10, 20, 30)

				expect(level.id).to.equal("open_t4928")
				expect(#state.traces).to.equal(1)
				expect(state.traces[1].start.x).to.equal(10)
				expect(state.traces[1].start.y).to.equal(20)
				expect(state.traces[1].start.z).to.equal(30)
				expect(state.traces[1].endpos.z).to.equal(30 + 32768)
				expect(state.traces[1].mask).to.equal(MASK_SOLID_BRUSHONLY)
				expect(F().CurrentAt(Vector(0, 0, 0))).to.equal(level)

				-- a roof 300 over the place: not an open place
				state.ray = ceil(330)

				local none, why = F().OpenAt(10, 20, 30)

				expect(none).to.beNil()
				expect(why).to.equal("roofed")

				-- the underside of a piece far over it (3000): a level under it
				state.ray = ceil(3000)
				expect(F().OpenAt(10, 20, 30).id).to.equal("open_t2944")

				-- a ray that hits nothing: the open level of the map
				state.ray = nothing()
				expect(F().OpenAt(10, 20, 30).id).to.equal("open_t4928")

				-- bad numbers
				local bad, reason = F().OpenAt(0 / 0, 0, 0)

				expect(bad).to.beNil()
				expect(reason).to.equal("bad position")
			end
		},
		{
			-- breaks if: the cap makes thousands of rays on a big graph (the cost is once per map, at most 96 nodes), or uses nodes that are not ground
			name = "open level: at most 96 nodes are used for the cap (a graph of 5000 nodes), and only the ground ones (type 2)",
			func = function(state)
				state.world = {GetModelBounds = function() return Vector(-1000, -2000, -300), Vector(3000, 4000, 15360) end}

				local nodes = cluster(0, 5000)
				local air = cluster(0, 100, AIR)

				for i = 1, #air do
					air[i].x = 100000 + i
					nodes[#nodes + 1] = air[i]
				end

				standIn(state, {[state.map] = {nodes = nodes}})

				local airRays = 0

				util.TraceLine = function(t)
					state.traces[#state.traces + 1] = t

					if t.start.x >= 100000 then
						airRays = airRays + 1
					end

					return {Hit = true, HitSky = true, HitPos = Vector(t.start.x, t.start.y, 2000)}
				end

				F().CurrentAt(Vector(0, 0, 0))

				-- 5 rays of CurrentAt + at most 96 of the cap
				expect(#state.traces <= 5 + 96).to.beTrue()
				expect(#state.traces > 5).to.beTrue()
				expect(airRays).to.equal(0)
			end
		},
		{
			-- breaks if: Outside is missing, or gives a level of another id than "open", or a slab that is not the world's bounds with the margin of 16
			name = "Outside: an anchor level and a step level give the open level of the map (id open, the world's heights -300 and 900 with 16 of margin)",
			func = function(state)
				state.ray = ceil(150)

				local anchor = F().CurrentAt(Vector(0, 0, 0))
				expect(anchor.open).to.beNil()
				expect(isfunction(F().Outside)).to.beTrue()

				for _, level in ipairs({anchor, F().Fallback(0), F().Current(40)}) do
					local outside, err = F().Outside(level)

					expect(err).to.beNil()
					expect(outside ~= nil).to.beTrue()
					expect(outside.id).to.equal("open")
					expect(outside.open).to.beTrue()
					expect(outside.zlo).to.equal(-316)
					expect(outside.zhi).to.equal(916)
				end
			end
		},
		{
			-- breaks if: an open level gets a level behind it (it would be itself), or the reason is not "open"
			name = "Outside: an open level has nothing behind it, nil and \"open\" (by the flag, whatever its other fields)",
			func = function(state)
				state.ray = sky()

				local open = F().CurrentAt(Vector(0, 0, 0))
				local level, err = F().Outside(open)

				expect(level).to.beNil()
				expect(err).to.equal("open")

				level, err = F().Outside({id = "open", open = true})

				expect(level).to.beNil()
				expect(err).to.equal("open")
			end
		},
		{
			-- breaks if: Outside makes a new table at each call, or asks the world's bounds at each call, or is not the table CurrentAt gives outdoors
			name = "Outside: the same table at every call and the one CurrentAt gives when the player is outside; the bounds are asked once per map name",
			func = function(state)
				state.ray = ceil(150)

				local anchor = F().CurrentAt(Vector(0, 0, 0))
				local first = F().Outside(anchor)

				for i = 1, 20 do
					expect(F().Outside(anchor)).to.equal(first)
					expect(F().Outside(F().Fallback(i * 32))).to.equal(first)
				end

				expect(state.boundsCalls).to.equal(1)

				-- the very table of CurrentAt's open level (its tiles are the ones already in the cache under the id open)
				state.ray = sky()
				state.now = state.now + 2

				expect(F().CurrentAt(Vector(500, 0, 0))).to.equal(first)
				expect(state.boundsCalls).to.equal(1)

				-- another map: another bounds, asked again
				setMap(state, "another_map")
				state.ray = ceil(150)
				state.now = state.now + 2
				local other = F().CurrentAt(Vector(0, 0, 0))

				expect(F().Outside(other) ~= nil).to.beTrue()
				expect(state.boundsCalls).to.equal(2)
			end
		},
		{
			-- breaks if: Outside answers a level when the world is unknown, or raises
			name = "Outside: nil and a reason when the world's bounds are unknown (no world, a world that raises, bounds that are no numbers); a bad level is nil, \"bad level\"",
			func = function(state)
				local level = F().Fallback(0)

				game.GetWorld = function() return nil end
				local outside, err = F().Outside(level)
				expect(outside).to.beNil()
				expect(isstring(err)).to.beTrue()

				F().Reset()
				game.GetWorld = function() error("no world") end
				outside, err = F().Outside(level)
				expect(outside).to.beNil()
				expect(isstring(err)).to.beTrue()

				F().Reset()
				game.GetWorld = function() return {GetModelBounds = function() return Vector(0, 0, 0 / 0), Vector(0, 0, 1) end} end
				outside, err = F().Outside(level)
				expect(outside).to.beNil()
				expect(isstring(err)).to.beTrue()

				for _, bad in ipairs({"x", 5, true}) do
					outside, err = F().Outside(bad)
					expect(outside).to.beNil()
					expect(err).to.equal("bad level")
				end

				outside, err = F().Outside(nil)
				expect(outside).to.beNil()
				expect(err).to.equal("bad level")
			end
		},
		{
			-- breaks if: Below of an open level gives a level, or loses the "open" reason
			name = "Below: an open level gives nil, \"open\" (nothing is visible under the free sky)",
			func = function(state)
				state.ray = sky()

				local open = F().CurrentAt(Vector(0, 0, 0))
				local level, err = F().Below(open)

				expect(level).to.beNil()
				expect(err).to.equal("open")

				-- by its flag, whatever its other fields
				level, err = F().Below({open = true})

				expect(level).to.beNil()
				expect(err).to.equal("open")
			end
		},
		{
			-- breaks if: the anchor below is not the fixed level of class 88 one storey lower
			name = "Below: an anchor gives the level one storey lower, f<A-128>c88 (f0c120 gives fn128c88 from -184 to -40)",
			func = function(state)
				state.ray = ceil(150)

				local level = F().CurrentAt(Vector(0, 0, 0))
				local below = F().Below(level)

				expect(level.id).to.equal("f0c120")
				expect(below.id).to.equal("fn128c88")
				expect(below.fz).to.equal(-128)
				expect(below.cls).to.equal(88)
				expect(below.top).to.equal(-40)
				expect(below.z).to.equal(-128)
				expect(below.zlo).to.equal(-184)
				expect(below.zhi).to.equal(-40)
				expect(below.open).to.beNil()

				-- it does not depend on the class: the same below for f0c224
				expect(F().Below({id = "f0c224", fz = 0, cls = 224, top = 224, z = 0, zlo = -56, zhi = 224}).id).to.equal("fn128c88")

				-- A 64: -64 and top 24; A 128: 0 and top 88; A -96: -224 and top -136
				local a = F().Below({id = "f64c160", fz = 64, cls = 160, top = 224, z = 64, zlo = 8, zhi = 224})

				expect(a.id).to.equal("fn64c88")
				expect(a.zlo).to.equal(-120)
				expect(a.zhi).to.equal(24)

				local b = F().Below({id = "f128c320", fz = 128, cls = 320, top = 448, z = 128, zlo = 72, zhi = 448})

				expect(b.id).to.equal("f0c88")
				expect(b.z).to.equal(0)
				expect(b.zlo).to.equal(-56)
				expect(b.zhi).to.equal(88)

				local c = F().Below({id = "fn96c120", fz = -96, cls = 120, top = 24, z = -96, zlo = -152, zhi = 24})

				expect(c.id).to.equal("fn224c88")
				expect(c.fz).to.equal(-224)
				expect(c.zlo).to.equal(-280)
				expect(c.zhi).to.equal(-136)

				-- the below of the below is made the same way
				expect(F().Below(below).id).to.equal("fn256c88")

				-- the registry is not touched by Below
				expect(#F().Known()).to.equal(1)
			end
		},
		{
			-- breaks if: Below builds a new table (and a new id string) at each call, or gives one table for two floors, or keeps the cache over a Reset
			name = "Below: the same table for the same floor (whatever table the level is), another one for another floor; Reset forgets (the memory is measured by tests/minimap/floors_alloc_job.lua)",
			func = function(state)
				local a1 = {id = "f0c120", fz = 0, cls = 120, top = 120, z = 0, zlo = -56, zhi = 120}
				local a2 = {id = "f0c224", fz = 0, cls = 224, top = 224, z = 0, zlo = -56, zhi = 224}
				local b1 = F().Below(a1)

				expect(b1.id).to.equal("fn128c88")
				expect(rawequal(F().Below(a1), b1)).to.beTrue()
				-- the same floor from another table of another class: the same answer
				expect(rawequal(F().Below(a2), b1)).to.beTrue()

				local other = F().Below({id = "f64c160", fz = 64, cls = 160, top = 224, z = 64, zlo = 8, zhi = 224})

				expect(rawequal(other, b1)).to.beFalse()
				expect(other.id).to.equal("fn64c88")
				expect(rawequal(F().Below(F().Below(a1)), F().Below(F().Below(a1)))).to.beTrue()

				-- the level CurrentAt gives
				state.ray = ceil(150)

				local level = F().CurrentAt(Vector(0, 0, 0))

				expect(rawequal(F().Below(level), F().Below(level))).to.beTrue()
				expect(F().Below(level).id).to.equal("fn128c88")

				-- Reset forgets the kept levels: a new table with the same content
				F().Reset()

				local again = F().Below(a1)

				expect(rawequal(again, b1)).to.beFalse()
				expect(again.id).to.equal(b1.id)
				expect(again.zlo).to.equal(b1.zlo)
				expect(again.zhi).to.equal(b1.zhi)
			end
		},
		{
			-- breaks if: CurrentAt makes new parameter tables (or Vectors) for the rays at each shot, or a new open level
			name = "CurrentAt: the five parameter tables of the rays are the same at every shot (with their output table), and so is the open level of a map",
			func = function(state)
				state.ray = ceil(150)
				F().CurrentAt(Vector(0, 0, 0))
				state.now = state.now + 2
				F().CurrentAt(Vector(0, 0, 0))

				expect(rounds(state)).to.equal(2)

				for i = 1, 5 do
					expect(rawequal(state.traces[i], state.traces[i + 5])).to.beTrue()
					expect(type(state.traces[i].output)).to.equal("table")

					for j = i + 1, 5 do
						expect(rawequal(state.traces[i], state.traces[j])).to.beFalse()
					end
				end

				-- the open level: one table, only its z (the feet) changes
				F().Reset()
				state.ray = sky()

				local first = F().CurrentAt(Vector(0, 0, 5))

				expect(first.z).to.equal(5)
				state.now = state.now + 2

				local second = F().CurrentAt(Vector(1, 0, 9))

				expect(rawequal(first, second)).to.beTrue()
				expect(second.z).to.equal(9)
				expect(second.zlo).to.equal(-316)
				expect(second.zhi).to.equal(916)
			end
		},
		{
			-- breaks if: the rule of the anchors is applied to the old step levels, or the old one is lost
			name = "Below: a step level (z<N>, no fz) keeps the plain rule (Fallback of z - 128); an anchor with a bad floor or a level with nothing is a bad level",
			func = function()
				local plain = F().Below(F().Fallback(0))

				sameLevel(plain, "zn4", -184, -56)
				expect(plain.fz).to.beNil()

				for _, bad in ipairs({{id = "f0c88", fz = 0 / 0, cls = 88}, {id = "f0c88", fz = "0", cls = 88}, {id = "z0h4", cap = 128}}) do
					local level, err = F().Below(bad)

					expect(level).to.beNil()
					expect(err).to.equal("bad level")
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
