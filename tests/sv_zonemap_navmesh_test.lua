-- Tests of the NAVMESH source of the in/out map (GryMod.ZoneMapServer, lua/grymod/server/sv_zonemap.lua), GLuaTest format, server realm.
-- The server can make the in/out map from two sources: "nodes" (the ground nodes of the AI graph, tests/sv_zonemap_test.lua) and "navmesh" (the nav areas of the
-- level: one point per 128 x 128 cell of every area, classified by the SAME GryMod.ZoneMapServer.SampleNode). The setting gry_zonemap_navmesh (on by default) picks
-- the source; each source keeps its own file (<key>.dat for the nodes, <key>_navmesh.dat for the navmesh).
-- Everything the module needs from the engine is a field of GryMod.ZoneMapServer (the nav areas, the trace, the graph, the files, the clocks, the log): these cases
-- replace them with fakes (a fake nav area is a table with GetCorner, GetCenter and GetZ) and put every one back with ONE function that runs after each case, even
-- when the case failed. The net functions are recorded, never sent. The real files are not touched (the disk is a table).

local ZS, Z
local HOOK = "GryMod zonemap"
local MAPNAME = "grymod_test_zonemap_nav"
local BSP = 4321
local ORIGINAL = {}
local FIELDS = {"Trace", "Graph", "Clock", "ReadFile", "WriteFile", "DeleteFile", "BspSize", "MapName", "Now", "Log", "OnSwitch", "OnSource", "NavAreas", "NavCount",
	"SampleNode", "NavFileExists", "TimerCreate", "TimerRemove"}
local NAV_TIMER = "GryMod zonemap navwait"
local CONVARS = {"gry_zonemap", "gry_zonemap_budget_ms", "gry_zonemap_max_nodes", "gry_zonemap_navmesh"}
local CONVAR_ORIGINAL = {}

-- ---------------------------------------------------------------------------------------------------------
-- stand-ins and their undoing
-- ---------------------------------------------------------------------------------------------------------
local undo = {}

local function stub(tbl, key, value)
	undo[#undo + 1] = {tbl = tbl, key = key, old = tbl[key]}
	tbl[key] = value
end

local function setConvar(name, value)
	local convar = GetConVar(name)
	local old = convar:GetString()

	undo[#undo + 1] = {fn = function() convar:SetString(old) end}
	convar:SetString(value)
end

local function noop() end

local function cleanup()
	if ZS then
		-- a convar put back must not start anything
		ZS.OnSwitch = noop
		ZS.OnSource = noop

		pcall(ZS.Cancel)
	end

	for i = #undo, 1, -1 do
		local entry = undo[i]

		if entry.fn then
			pcall(entry.fn)
		else
			entry.tbl[entry.key] = entry.old
		end
	end

	undo = {}

	-- whatever happened, the real functions are back
	if ZS then
		for _, f in ipairs(FIELDS) do
			if ORIGINAL[f] ~= nil then
				ZS[f] = ORIGINAL[f]
			end
		end
	end
end

local function case(name, fn)
	return {
		name = name,
		func = function()
			local ok, err = pcall(fn)

			cleanup()

			if not ok then
				error(err, 0)
			end
		end
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- the net: recorded, never sent
-- ---------------------------------------------------------------------------------------------------------
local sent, current

local function stubNet()
	sent, current = {}, nil

	stub(net, "Start", function(name)
		current = {name = name, w = {}}

		return true
	end)
	stub(net, "WriteUInt", function(value, bits)
		current.w[#current.w + 1] = {"uint", value, bits}
	end)
	stub(net, "WriteData", function(data, length)
		current.w[#current.w + 1] = {"data", data, length}
	end)
	stub(net, "Send", function(target)
		current.target = target
		sent[#sent + 1] = current
		current = nil
	end)
	stub(net, "Broadcast", function()
		current.target = "all"
		sent[#sent + 1] = current
		current = nil
	end)
end

local function stateMessages()
	local list = {}

	for _, m in ipairs(sent) do
		if m.name == "gry_zonemap_state" then
			list[#list + 1] = {state = m.w[1][2], done = m.w[2][2], total = m.w[3][2]}
		end
	end

	return list
end

-- ---------------------------------------------------------------------------------------------------------
-- fake nav areas
-- ---------------------------------------------------------------------------------------------------------
local clockT, nowT, navCalls, getZCalls, graphCalls, sampleCalls, logs, disk, deleted
-- the late load of the navmesh: what the fake NavCount answers (nil: the number of fake areas), whether the fake .nav file exists, and the fake timers
local navNow, fileExists, fileCalls, timers, timerCreates, timerRemoves

-- a nav area: the rectangle (x1, y1) .. (x2, y2) at height z. opts.zAt(px, py) answers GetZ (default: z); opts.getZ replaces GetZ altogether (to raise or to
-- answer something that is not a number); opts.swap gives the corners the other way round (corner 0 is the larger one); opts.tick moves the fake clock at each GetZ
local function area(x1, y1, x2, y2, z, opts)
	opts = opts or {}

	local a = {}
	local c0, c2 = Vector(x1, y1, z), Vector(x2, y2, z)

	if opts.swap then
		c0, c2 = c2, c0
	end

	function a.GetCorner(_, i)
		if i == 0 then
			return c0
		elseif i == 2 then
			return c2
		end

		return Vector(x1, y2, z)
	end

	function a.GetCenter()
		return Vector((x1 + x2) / 2, (y1 + y2) / 2, z)
	end

	function a.GetZ(_, v)
		getZCalls = getZCalls + 1

		if opts.tick then
			clockT = clockT + opts.tick
		end

		if opts.getZ then
			return opts.getZ(v)
		end

		if opts.zAt then
			return opts.zAt(v.x, v.y)
		end

		return z
	end

	return a
end

-- the grid of the one-cell areas: n areas, the i-th covering the cell (i - 1, 0) (rectangle inside the cell, around its centre), at height z
local function cellAreas(n, z, opts)
	local list = {}

	for i = 1, n do
		local cx = (i - 1) * 128 + 64

		list[i] = area(cx - 20, 44, cx + 20, 84, z, opts)
	end

	return list
end

-- spec.ceil: nil (nothing above), "sky", a height over the node, or a function(x, y) of the ray's start (to make the places differ)
local function makeTrace(spec)
	return function(p)
		local s, e = p.start, p.endpos

		if e.z - s.z > 1000 then
			local rel = spec.ceil

			if type(rel) == "function" then
				rel = rel(s.x, s.y)
			end

			if rel == nil then
				return {Hit = false, HitSky = false, HitPos = Vector(e.x, e.y, e.z), Fraction = 1}
			elseif rel == "sky" then
				return {Hit = true, HitSky = true, HitPos = Vector(e.x, e.y, e.z), Fraction = 0.5}
			end

			return {Hit = true, HitSky = false, HitPos = Vector(s.x, s.y, s.z - 72 + rel), Fraction = 0.01}
		end

		local dx, dy = e.x - s.x, e.y - s.y
		local length = math.sqrt(dx * dx + dy * dy)
		local d = spec.wall

		if d == nil or d >= length then
			return {Hit = false, HitSky = false, HitPos = Vector(e.x, e.y, e.z), Fraction = 1}
		end

		return {Hit = true, HitSky = false, HitPos = Vector(s.x + dx / length * d, s.y + dy / length * d, s.z), Fraction = d / length}
	end
end

local ROOM = {ceil = 200, wall = 300}

local function graphOf(ground)
	local nodes = {}

	for i = 1, ground do
		nodes[#nodes + 1] = {x = i * 64, y = (i % 7) * 64, z = 100, yaw = 0, type = 2, info = 0, zone = 0}
	end

	return {version = 37, mapVersion = 1, nodes = nodes, links = {}, lookup = {}}
end

-- installs the fakes. `areas`: the list the fake navmesh holds (nil: none, NavCount 0); `graph`: nil is no graph. The convar of the source is the test's (on).
-- The sample of a point is the real SampleNode over the fake trace (spec), unless a case replaces it.
local function useFakes(areas, graph, spec)
	clockT, nowT, navCalls, getZCalls, graphCalls, sampleCalls, logs, disk, deleted = 0, 0, 0, 0, 0, 0, {}, {}, {}
	navNow, fileExists, fileCalls, timers, timerCreates, timerRemoves = nil, false, 0, {}, 0, {}

	stubNet()
	stub(ZS, "OnSwitch", noop)
	stub(ZS, "OnSource", noop)
	stub(ZS, "MapName", function() return MAPNAME end)
	stub(ZS, "BspSize", function() return BSP end)
	stub(ZS, "ReadFile", function(path) return disk[path] end)
	stub(ZS, "WriteFile", function(path, bytes)
		disk[path] = bytes

		return true
	end)
	stub(ZS, "DeleteFile", function(path)
		deleted[#deleted + 1] = path
		disk[path] = nil
	end)
	stub(ZS, "Log", function(text) logs[#logs + 1] = text end)
	stub(ZS, "Clock", function() return clockT end)
	stub(ZS, "Now", function() return nowT end)
	stub(ZS, "Trace", makeTrace(spec or ROOM))
	stub(ZS, "Graph", function()
		graphCalls = graphCalls + 1

		return graph
	end)
	stub(ZS, "NavCount", function()
		if navNow ~= nil then
			return navNow
		end

		return areas and #areas or 0
	end)
	stub(ZS, "NavFileExists", function()
		fileCalls = fileCalls + 1

		return fileExists
	end)
	stub(ZS, "TimerCreate", function(name, delay, reps, fn)
		timerCreates = timerCreates + 1
		timers[name] = {delay = delay, reps = reps, fn = fn}
	end)
	stub(ZS, "TimerRemove", function(name)
		timerRemoves[#timerRemoves + 1] = name
		timers[name] = nil
	end)
	stub(ZS, "NavAreas", function()
		navCalls = navCalls + 1

		return areas or {}
	end)
	setConvar("gry_zonemap", "1")
	setConvar("gry_zonemap_budget_ms", "2")
	setConvar("gry_zonemap_max_nodes", "20000")
	setConvar("gry_zonemap_navmesh", "1")
	ZS.Unload()
end

local function navPath()
	return "grymod/zonemap/" .. Z.Key(MAPNAME, BSP, "navmesh") .. ".dat"
end

local function nodesPath()
	return "grymod/zonemap/" .. Z.Key(MAPNAME, BSP) .. ".dat"
end

local function thinkHook()
	local list = hook.GetTable().Think

	return list and list[HOOK]
end

local function think()
	local f = thinkHook()

	if f then
		f()

		return true
	end

	return false
end

local function finish(limit)
	local n = 0

	while thinkHook() and n < (limit or 10000) do
		think()
		n = n + 1
	end

	return n
end

-- the samples that reach GryMod.ZoneMap.Build (and the real Build runs unless `fake`)
local function spyBuild(fake)
	local got = {}
	local real = Z.Build

	stub(Z, "Build", function(samples)
		got.samples = samples

		if fake then
			return {boxes = {}, sampleCount = #samples, skipped = 0, cells = 0}
		end

		return real(samples)
	end)

	return got
end

-- SampleNode replaced by a recorder: every call is {x, y, z}, the answer is a function of them (default: outdoor, open); `tick` moves the fake clock
local function recordSamples(answer, tick)
	local list = {}

	stub(ZS, "SampleNode", function(x, y, z)
		list[#list + 1] = {x = x, y = y, z = z}
		sampleCalls = sampleCalls + 1

		if tick then
			clockT = clockT + tick
		end

		if answer then
			return answer(x, y, z)
		end

		return false, 0
	end)

	return list
end

-- "x,y,z" of every point, sorted: the set of the points of a run, whatever their order
local function pointSet(list)
	local out = {}

	for i, p in ipairs(list) do
		out[i] = p.x .. "," .. p.y .. "," .. p.z
	end

	table.sort(out)

	return table.concat(out, " ")
end

local function setOf(...)
	local out = {...}

	table.sort(out)

	return table.concat(out, " ")
end

-- ---------------------------------------------------------------------------------------------------------
return {
	groupName = "GryMod zone map, navmesh source (sv_zonemap.lua)",
	beforeAll = function()
		ZS = GryMod.ZoneMapServer
		Z = GryMod.ZoneMap

		if ZS then
			for _, f in ipairs(FIELDS) do
				ORIGINAL[f] = ZS[f]
			end
		end

		for _, name in ipairs(CONVARS) do
			local convar = GetConVar(name)
			CONVAR_ORIGINAL[name] = convar and convar:GetString()
		end
	end,
	afterEach = function()
		cleanup()
	end,
	afterAll = function()
		cleanup()

		for _, name in ipairs(CONVARS) do
			local convar = GetConVar(name)

			if convar and CONVAR_ORIGINAL[name] and convar:GetString() ~= CONVAR_ORIGINAL[name] then
				pcall(convar.SetString, convar, CONVAR_ORIGINAL[name])
			end
		end

		-- the game goes on with its real map
		if ZS and ZS.Unload then
			pcall(ZS.Unload)
			pcall(ZS.Start)
		end
	end,
	cases = {
		-- ----------------------------------------------------------------------------------------------- wiring
		-- breaks if: the convar is missing, not replicated / archived / notified, or its default is not on
		case("gry_zonemap_navmesh is a replicated, notified setting (the engine does not report the archive flag of a convar, as for gry_zonemap), on by default, and a yes / no setting of the administrators' white list", function()
			local convar = GetConVar("gry_zonemap_navmesh")
			expect(convar ~= nil).to.beTrue()
			expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
			expect(convar:IsFlagSet(FCVAR_NOTIFY)).to.beTrue()
			expect(convar:GetDefault()).to.equal("1")

			local S = GryMod.ServerSettings
			expect(S.Find("gry_zonemap_navmesh") ~= nil).to.beTrue()
			expect(S.Find("gry_zonemap_navmesh").kind).to.equal("bool")
			expect(S.Validate("gry_zonemap_navmesh", "1")).to.equal("1")
			expect(S.Validate("gry_zonemap_navmesh", "0")).to.equal("0")
			expect(S.Validate("gry_zonemap_navmesh", "2")).to.beNil()
			expect(S.Validate("gry_zonemap_navmesh", "yes")).to.beNil()
		end),
		-- breaks if: a field is missing (the tests could not replace it) or the cap is not 60000
		case("the module has the fields of the navmesh source: NavAreas, NavCount, Source, OnSource and the cap of 60000 samples", function()
			for _, f in ipairs({"NavAreas", "NavCount", "Source", "OnSource"}) do
				expect(isfunction(ZS[f])).to.beTrue()
			end

			expect(ZS.NAV_MAX).to.equal(60000)
		end),

		-- ----------------------------------------------------------------------------------------------- the points of an area
		-- breaks if: the cells are taken from the corners instead of the centres, the grid is not the 128 grid, or the z is not the one GetZ gives at the point
		case("a rectangle gives the cell centres inside it, at the height GetZ gives there", function()
			-- 0..300: the centres 64 and 192 are inside (320 is not): four points; the height depends on the point
			useFakes({area(0, 0, 300, 300, 50, {zAt = function(px, py) return 50 + (px + py) / 64 end})}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(pointSet(list)).to.equal(setOf("64,64,52", "64,192,54", "192,64,54", "192,192,56"))
			expect((ZS.State())).to.equal(4)
		end),
		-- breaks if: a centre exactly on the edge of the rectangle is left out, or a negative rectangle is rounded the wrong way
		case("the edges count (a centre on the edge is inside) and a rectangle with negative coordinates is read with the same rule", function()
			useFakes({area(64, 64, 192, 64, 10), area(-300, -300, -100, -100, 10)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			-- the first: centres 64 and 192 on the edges (in x), 64 in y; the second: -192 only (-320 and -64 are outside -300..-100)
			expect(pointSet(list)).to.equal(setOf("64,64,10", "192,64,10", "-192,-192,10"))
		end),
		-- breaks if: the rectangle is taken from corner 0 as the minimum and corner 2 as the maximum without sorting them
		case("the corners may come in any order: the rectangle is the min and max of x and y", function()
			useFakes({area(0, 0, 300, 300, 10, {swap = true})}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(#list).to.equal(4)
			expect(pointSet(list)).to.equal(setOf("64,64,10", "64,192,10", "192,64,10", "192,192,10"))
		end),
		-- breaks if: a small area (no cell centre inside) gives no sample, or its point is not its own centre
		case("an area that covers no cell centre gives one sample at its own centre (its height is the centre's)", function()
			-- 10..50 holds no centre (64); GetZ would say 999: the centre's z (70) is used
			useFakes({area(10, 10, 50, 50, 70, {zAt = function() return 999 end})}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(pointSet(list)).to.equal(setOf("30,30,70"))
		end),
		-- breaks if: a failing GetZ stops the map instead of using the centre, or a value that is not a number is used
		case("when GetZ raises, answers nothing, NaN or a text, the height of the area's centre is used", function()
			local answers = {
				function() error("no height here") end,
				function() return nil end,
				function() return 0 / 0 end,
				function() return "5" end
			}

			for _, answer in ipairs(answers) do
				useFakes({area(0, 0, 100, 100, 33, {getZ = answer})}, nil)

				local list = recordSamples()
				ZS.RunNow()
				expect(pointSet(list)).to.equal(setOf("64,64,33"))
				expect((ZS.State())).to.equal(4)
				cleanup()
			end
		end),
		-- breaks if: the layer is not part of the pair: two floors over the same cells would give four points, not eight
		case("two areas at two heights over the same cells give two layers of points", function()
			useFakes({area(0, 0, 300, 300, 50), area(0, 0, 300, 300, 300)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(#list).to.equal(8)
			expect(Z.Layer(50)).to.equal(0)
			expect(Z.Layer(300)).to.equal(2)
		end),
		-- breaks if: the (layer, cell) pair is not remembered: the same cell and layer would be sampled again
		case("a (layer, cell) pair that already has a sample is not sampled twice, and the first one is kept", function()
			-- the same rectangle at 50 and at 60 (the same layer): one point per cell, at 50; an area at the same place and height again changes nothing
			useFakes({area(0, 0, 300, 300, 50), area(0, 0, 300, 300, 60), area(0, 0, 300, 300, 50), area(64, 64, 100, 100, 55)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(pointSet(list)).to.equal(setOf("64,64,50", "64,192,50", "192,64,50", "192,192,50"))
		end),
		-- breaks if: the small area's own point skips the dedupe (a cell that already has its sample would get a second one)
		case("the point of a small area is deduplicated like the others", function()
			-- a big area over the cell (0, 0), then a small one inside the same cell and layer without any centre
			useFakes({area(0, 0, 128, 128, 50), area(10, 10, 20, 20, 52)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(#list).to.equal(1)
			expect(pointSet(list)).to.equal(setOf("64,64,50"))
		end),
		-- breaks if: an area with a bad number is not counted as skipped (the map would be said complete), or if it stops the others
		case("an area with a coordinate that is not a number is skipped and counted: the others are used and the result is flagged incomplete (state 5)", function()
			useFakes({area(0, 0, 0 / 0, 100, 10), area(0, 0, 100, 100, 10)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(pointSet(list)).to.equal(setOf("64,64,10"))
			expect((ZS.State())).to.equal(5)

			local _, header = Z.Decode(ZS.Bytes())
			expect(header.complete).to.beFalse()
			expect(header.overBudget).to.beFalse()
		end),
		-- breaks if: an area wider than the whole map is walked cell by cell (the server would freeze)
		case("an area that spans more than 256 cells in one direction is refused (counted as skipped), not walked", function()
			useFakes({area(0, 0, 128 * 300, 100, 10)}, nil)

			local list = recordSamples()
			ZS.RunNow()
			expect(#list).to.equal(0)
			expect(getZCalls).to.equal(0)
			expect((ZS.State())).to.equal(5)
		end),

		-- ----------------------------------------------------------------------------------------------- the classification and the file
		-- breaks if: the points are classified by another rule than SampleNode (13 rays at most each, the answer goes into the sample)
		case("each point is classified by SampleNode (13 rays at most) and the samples that reach Build have its answer", function()
			-- the places under x = 1000 have a ceiling at 200 and walls at 300 (indoor), the others the open sky
			useFakes({area(0, 0, 300, 300, 50), area(2000, 0, 2300, 300, 50)}, nil, {ceil = function(x) return x < 1000 and 200 or "sky" end, wall = 300})

			local traces = 0
			local real = ZS.Trace

			stub(ZS, "Trace", function(p)
				traces = traces + 1

				return real(p)
			end)

			local got = spyBuild()
			ZS.RunNow()
			expect(#got.samples).to.equal(8)
			expect(traces <= 13 * 8).to.beTrue()

			for _, s in ipairs(got.samples) do
				local indoor, ceil = ZS.SampleNode(s.x, s.y, s.z)
				expect(s.indoor).to.equal(indoor)
				expect(s.ceil).to.equal(ceil)
				expect(s.indoor).to.equal(s.x < 1000)
				expect(s.ceil).to.equal(s.x < 1000 and Z.CeilIndex(200) or 0)
			end
		end),
		-- breaks if: the header does not say what the file was made from (the bsp size, the number of areas, complete), or the file does not go to the navmesh path
		case("the file is the navmesh file: the header has the bsp size, the number of areas and complete; the map and its bytes stay in memory", function()
			useFakes({area(0, 0, 300, 300, 50), area(400, 0, 700, 300, 50)}, nil)
			ZS.RunNow()

			local bytes = ZS.Bytes()
			local map, header = Z.Decode(bytes)
			expect(map ~= nil).to.beTrue()
			expect(header.bspSize).to.equal(BSP)
			expect(header.nodeCount).to.equal(2)
			expect(header.sampleCount).to.equal(8)
			expect(header.complete).to.beTrue()
			expect(header.overBudget).to.beFalse()
			expect(disk[navPath()]).to.equal(bytes)
			expect(disk[nodesPath()]).to.beNil()
			expect(string.sub(navPath(), -12)).to.equal("_navmesh.dat")
			expect(ZS.Stats().source).to.equal("navmesh")
			expect(ZS.Stats().samples).to.equal(8)
		end),

		-- breaks if: the key version goes back to 1 (the files made with the old ceiling rule would be read again) for either source
		case("the cache files carry the version 2 of the ceiling rule: <map>_<bsp>_v2_navmesh.dat for the navmesh and <map>_<bsp>_v2.dat for the nodes", function()
			useFakes({area(0, 0, 300, 300, 50)}, nil)
			ZS.RunNow()
			expect(disk["grymod/zonemap/" .. MAPNAME .. "_" .. BSP .. "_v2_navmesh.dat"] ~= nil).to.beTrue()

			useFakes(nil, graphOf(3))
			setConvar("gry_zonemap_navmesh", "0")
			ZS.RunNow()
			expect(disk["grymod/zonemap/" .. MAPNAME .. "_" .. BSP .. "_v2.dat"] ~= nil).to.beTrue()
		end),

		-- ----------------------------------------------------------------------------------------------- the cap
		-- breaks if: the cap is removed (60025 samples would be taken), or the cut is not flagged
		case("the cap: more than 60000 samples keep the first 60000, flagged incomplete and over budget (state 5)", function()
			-- 245 x 245 cells = 60025 centres in one area
			useFakes({area(0, 0, 245 * 128, 245 * 128, 10)}, nil)

			local list = recordSamples()
			local got = spyBuild(true)
			ZS.RunNow()
			expect(#list).to.equal(60000)
			expect(#got.samples).to.equal(60000)
			expect((ZS.State())).to.equal(5)

			local state, done, total = ZS.State()
			expect(state).to.equal(5)
			expect(done).to.equal(60000)
			expect(total).to.equal(60000)

			local _, header = Z.Decode(ZS.Bytes())
			expect(header.overBudget).to.beTrue()
			expect(header.complete).to.beFalse()
		end),
		-- breaks if: the cap is applied one sample too early (60000 exactly must not be flagged)
		case("exactly 60000 samples is not over the cap: state 4, complete", function()
			-- 250 x 240 cells = 60000 centres
			useFakes({area(0, 0, 250 * 128, 240 * 128, 10)}, nil)

			local list = recordSamples()
			spyBuild(true)
			ZS.RunNow()
			expect(#list).to.equal(60000)
			expect((ZS.State())).to.equal(4)

			local _, header = Z.Decode(ZS.Bytes())
			expect(header.overBudget).to.beFalse()
			expect(header.complete).to.beTrue()
		end),

		-- ----------------------------------------------------------------------------------------------- the budget and the progress
		-- breaks if: the list of points is made in one go (a frame would be as long as all the areas) or the clock is read less often than after each area / sample
		case("a frame works until the budget is used, never more than one area or one sample beyond it, in the listing and in the sampling; the hook goes at the end", function()
			-- one-cell areas: 100 of them, each costs 100 us of GetZ; each sample costs 100 us; the budget is 0.5 ms
			useFakes(cellAreas(100, 10, {tick = 0.0001}), nil)
			setConvar("gry_zonemap_budget_ms", "0.5")
			recordSamples(nil, 0.0001)
			ZS.Start()
			expect(thinkHook() ~= nil).to.beTrue()
			expect(sampleCalls).to.equal(0) -- Start itself computes nothing
			expect(getZCalls).to.equal(0)

			local frames = 0

			while thinkHook() and frames < 1000 do
				local t0 = clockT
				think()
				frames = frames + 1

				local spent = clockT - t0
				expect(spent <= 0.0005 + 0.0001 + 1e-9).to.beTrue()

				-- the budget is used, but at the last frame
				if thinkHook() then
					expect(spent >= 0.0005 - 1e-9).to.beTrue()
				end
			end

			expect(frames > 10).to.beTrue()
			expect(frames < 100).to.beTrue()
			expect(sampleCalls).to.equal(100)
			expect(getZCalls).to.equal(100)
			expect((ZS.State())).to.equal(4)
			expect(thinkHook()).to.beNil()
		end),
		-- breaks if: the total is not the number of points (the players' percentage would be wrong) or done does not count the samples of the navmesh
		case("the progress counts the samples of the source: total = the number of points, done grows to it, the last message is ready with done = total", function()
			-- two heights over 2 x 2 cells: 8 points
			useFakes({area(0, 0, 300, 300, 50), area(0, 0, 300, 300, 300)}, nil)
			setConvar("gry_zonemap_budget_ms", "0.5")
			recordSamples(nil, 0.0002)
			ZS.Start()

			local state, done, total = ZS.State()
			expect(state).to.equal(3)
			expect(done).to.equal(0)

			local last, sawTotal = 0, false

			while thinkHook() do
				nowT = nowT + 1 -- a state message every frame
				think()
				state, done, total = ZS.State()

				if state == 3 and total > 0 then
					sawTotal = true
					expect(total).to.equal(8)
					expect(done >= last).to.beTrue()
					expect(done <= 8).to.beTrue()
					last = done
				end
			end

			expect(sawTotal).to.beTrue()
			state, done, total = ZS.State()
			expect(state).to.equal(4)
			expect(done).to.equal(8)
			expect(total).to.equal(8)

			local list = stateMessages()
			expect(list[#list].state).to.equal(4)
			expect(list[#list].done).to.equal(8)
			expect(list[#list].total).to.equal(8)

			for _, m in ipairs(list) do
				expect(m.total == 0 or m.total == 8).to.beTrue() -- never a total of the other source
			end
		end),
		-- breaks if: the navmesh job needs a permanent hook or leaves it behind
		case("no Think hook before the start, one while it computes, none after; RunNow never adds one", function()
			useFakes({area(0, 0, 300, 300, 50)}, nil)
			expect(thinkHook()).to.beNil()
			ZS.Start()
			expect(thinkHook() ~= nil).to.beTrue()
			finish()
			expect(thinkHook()).to.beNil()

			ZS.Unload()
			disk = {}
			expect(ZS.RunNow()).to.equal(4)
			expect(thinkHook()).to.beNil()
		end),
		-- breaks if: an error in the navmesh job is not caught (state 6, hook removed, nothing written)
		case("an error in the sampling (the trace raises) is state 6, logged, nothing raised, the hook is gone, nothing written", function()
			useFakes({area(0, 0, 300, 300, 50)}, nil)
			stub(ZS, "Trace", function() error("boom") end)
			ZS.Start()
			expect(function() think() end).to.succeed()
			expect((ZS.State())).to.equal(6)
			expect(thinkHook()).to.beNil()
			expect(#logs).to.equal(1)
			expect(string.find(logs[1], "boom", 1, true) ~= nil).to.beTrue()
			expect(next(disk)).to.beNil()
		end),

		-- ----------------------------------------------------------------------------------------------- the choice of the source
		-- breaks if: the choice ignores the setting, the navmesh, the graph or the API's failure; the table is every combination
		case("the source: the setting, a navmesh or not (or an API that raises or answers nonsense), a graph or not", function()
			local navs = {area(0, 0, 300, 300, 50)}
			local graph = graphOf(5)

			-- {setting, navmesh: "yes" | "no" | "raises" | "nonsense", graph, expected source, expected state after Start, times the graph is asked, log lines,
			-- the first of them is "no navmesh"}
			local rows = {
				{"1", "yes", graph, "navmesh", 3, 0, 0, false},
				{"1", "yes", nil, "navmesh", 3, 0, 0, false},
				{"1", "no", graph, "nodes", 3, 1, 1, true},
				{"1", "no", nil, "nodes", 1, 1, 2, true}, -- "no navmesh", then "no usable node graph"
				{"1", "raises", graph, "nodes", 3, 1, 1, true},
				{"1", "nonsense", graph, "nodes", 3, 1, 1, true},
				{"0", "yes", graph, "nodes", 3, 1, 0, false},
				{"0", "yes", nil, "nodes", 1, 1, 1, false}, -- the owner chose the nodes and there is no graph: state 1 (the log is the graph's)
				{"0", "no", graph, "nodes", 3, 1, 0, false}
			}

			for i, row in ipairs(rows) do
				useFakes(row[2] == "no" and {} or navs, row[3])

				if row[2] == "raises" then
					stub(ZS, "NavCount", function() error("no navmesh API") end)
				elseif row[2] == "nonsense" then
					stub(ZS, "NavCount", function() return "many" end)
				end

				setConvar("gry_zonemap_navmesh", row[1])
				ZS.Start()

				local label = "row " .. i .. ": "
				expect(label .. ZS.Source()).to.equal(label .. row[4])
				expect(label .. (ZS.State())).to.equal(label .. row[5])
				expect(label .. graphCalls).to.equal(label .. row[6])
				expect(label .. #logs).to.equal(label .. row[7])

				if row[8] then
					expect(string.find(logs[1], "no navmesh", 1, true) ~= nil).to.beTrue()
				else
					for _, text in ipairs(logs) do
						expect(string.find(text, "no navmesh", 1, true)).to.beNil()
					end
				end

				cleanup()
			end
		end),
		-- breaks if: the "no navmesh" line is logged at each start instead of once
		case("the fall back to the nodes is logged once, not at each start", function()
			useFakes({}, graphOf(5))
			ZS.Start()
			ZS.Start()
			ZS.Start()
			expect(#logs).to.equal(1)
		end),
		-- breaks if: a navmesh whose areas cannot be read blocks the map without a word
		case("the navmesh is there but its areas cannot be read (NavAreas raises, answers nothing or an empty list): state 1 with a reason, logged, no hook", function()
			for _, answer in ipairs({function() error("bad areas") end, function() return nil end, function() return {} end}) do
				useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
				stub(ZS, "NavAreas", answer)
				ZS.Start()
				expect((ZS.State())).to.equal(1)
				expect(thinkHook()).to.beNil()
				expect(isstring(ZS.Reason())).to.beTrue()
				expect(#logs).to.equal(1)
				cleanup()
			end
		end),
		-- breaks if: the source is computed again at each call (Source must not log) or is not the one the last start used
		case("Source() answers the source of the last start, and the setting's choice before any start, without logging", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			expect(ZS.Source()).to.equal("navmesh")
			setConvar("gry_zonemap_navmesh", "0")
			expect(ZS.Source()).to.equal("nodes")
			setConvar("gry_zonemap_navmesh", "1")
			ZS.Start()
			expect(ZS.Source()).to.equal("navmesh")
			expect(#logs).to.equal(0)
		end),

		-- ----------------------------------------------------------------------------------------------- the two files
		-- breaks if: the two sources share a file name, or the switch recomputes a source whose file is there, or reads the wrong one
		case("both files live side by side: switching the setting reads the file of that source with no computation", function()
			useFakes({area(0, 0, 300, 300, 50), area(400, 0, 700, 300, 50)}, graphOf(6))
			stub(ZS, "OnSource", ORIGINAL.OnSource)

			-- the navmesh map
			ZS.Start()
			finish()
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(4)

			local navBytes = ZS.Bytes()
			expect(disk[navPath()]).to.equal(navBytes)
			expect(disk[nodesPath()]).to.beNil()

			-- to the nodes: computed once, the navmesh file stays
			GetConVar("gry_zonemap_navmesh"):SetString("0")
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			finish()
			expect((ZS.State())).to.equal(4)

			local nodeBytes = ZS.Bytes()
			expect(nodeBytes ~= navBytes).to.beTrue()
			expect(disk[nodesPath()]).to.equal(nodeBytes)
			expect(disk[navPath()]).to.equal(navBytes)
			expect(navPath() ~= nodesPath()).to.beTrue()

			-- back to the navmesh: the file is read, no area, no sample, no hook
			navCalls, getZCalls, sampleCalls, graphCalls = 0, 0, 0, 0
			GetConVar("gry_zonemap_navmesh"):SetString("1")
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(4)
			expect(ZS.Bytes()).to.equal(navBytes)
			expect(thinkHook()).to.beNil()
			expect(navCalls).to.equal(0)
			expect(getZCalls).to.equal(0)
			expect(graphCalls).to.equal(0)

			-- and again to the nodes: read too
			GetConVar("gry_zonemap_navmesh"):SetString("0")
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(4)
			expect(ZS.Bytes()).to.equal(nodeBytes)
			expect(thinkHook()).to.beNil()
			expect(graphCalls).to.equal(0)
		end),
		-- breaks if: the change does not tell the clients (the veil and the percentage follow the state messages and the data)
		case("the switch tells everybody: the new state and, when the file is there, the data", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(6))
			stub(ZS, "OnSource", ORIGINAL.OnSource)
			ZS.Start()
			finish()
			GetConVar("gry_zonemap_navmesh"):SetString("0")
			finish()
			sent = {}
			GetConVar("gry_zonemap_navmesh"):SetString("1") -- the navmesh file is there: ready at once

			local list = stateMessages()
			expect(#list >= 1).to.beTrue()
			expect(list[#list].state).to.equal(4)

			local data = 0

			for _, m in ipairs(sent) do
				expect(m.target).to.equal("all")

				if m.name == "gry_zonemap_data" then
					data = data + 1
				end
			end

			expect(data).to.equal(1)
		end),
		-- breaks if: a file of another bsp size (another version of the map) is trusted
		case("the navmesh file of another bsp size is ignored and made again", function()
			useFakes({area(0, 0, 300, 300, 50)}, nil)
			disk[navPath()] = Z.Encode(Z.Build({{x = 0, y = 0, z = 0, indoor = true, ceil = 2}}), {bspSize = BSP + 1, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect(navCalls).to.equal(1)
			expect((ZS.State())).to.equal(3)
			finish()

			local _, header = Z.Decode(disk[navPath()])
			expect(header.bspSize).to.equal(BSP)
			expect(header.sampleCount).to.equal(4)
		end),
		-- breaks if: the switch changing in the middle of a computation does not cancel it, or leaves two hooks
		case("switching the source in the middle of a computation cancels it and starts the other one from zero", function()
			useFakes(cellAreas(60, 10, {tick = 0.0001}), graphOf(10))
			stub(ZS, "OnSource", ORIGINAL.OnSource)
			setConvar("gry_zonemap_budget_ms", "0.5")
			recordSamples(nil, 0.0001)
			ZS.Start()
			think()
			think()

			local _, done = ZS.State()
			expect(done >= 0).to.beTrue()
			GetConVar("gry_zonemap_navmesh"):SetString("0")
			expect(ZS.Source()).to.equal("nodes")

			local state, done2, total = ZS.State()
			expect(state).to.equal(3)
			expect(done2).to.equal(0)
			expect(total).to.equal(10)
			expect(thinkHook() ~= nil).to.beTrue()
			finish()
			expect((ZS.State())).to.equal(4)
			expect(thinkHook()).to.beNil()
			expect(disk[nodesPath()] ~= nil).to.beTrue()
		end),
		-- breaks if: the callback starts the module while the switch is off, or on a change that is not a change
		case("OnSource does nothing while the in/out map is off, and nothing when the value did not really change", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			setConvar("gry_zonemap", "0")
			ZS.Start()
			sent = {}
			navCalls, graphCalls = 0, 0
			ORIGINAL.OnSource("1", "0")
			expect((ZS.State())).to.equal(0)
			expect(thinkHook()).to.beNil()
			expect(#sent).to.equal(0)

			setConvar("gry_zonemap", "1")
			ZS.Start()
			finish()
			sent = {}
			navCalls, graphCalls = 0, 0
			ORIGINAL.OnSource("1", "1")
			ORIGINAL.OnSource("0", "0")
			ORIGINAL.OnSource("1", "5") -- "5" is on: the same as "1"
			expect(#sent).to.equal(0)
			expect(navCalls).to.equal(0)
			expect(graphCalls).to.equal(0)
		end),
		-- breaks if: the real callback is not registered on the convar
		case("the convar's change callback is the module's: changing the setting really calls OnSource", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))

			local seen = {}

			stub(ZS, "OnSource", function(old, new) seen[#seen + 1] = old .. ">" .. new end)
			GetConVar("gry_zonemap_navmesh"):SetString("0")
			GetConVar("gry_zonemap_navmesh"):SetString("1")
			expect(table.concat(seen, ",")).to.equal("1>0,0>1")
		end),

		-- ----------------------------------------------------------------------------------------------- the navmesh that loads late
		-- The engine can answer "0 areas" at the start of a map whose .nav file exists (a Workshop map: the file is in the map's GMA) and have the navmesh some
		-- seconds later. The choice of the source must not give up at the first 0 when the file is there.
		-- breaks if: the choice goes back to "0 areas means nodes": the state would be 3 (the nodes) at once, with no timer
		case("0 areas at the start, but the map's .nav file exists and there is no cache file: the source is the navmesh, the state is 2 (waiting), nothing is computed, a poll timer every 0.1 s runs and the wait is logged once", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			recordSamples()
			ZS.Start()
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(2)
			expect(thinkHook()).to.beNil()
			expect(sampleCalls).to.equal(0)
			expect(navCalls).to.equal(0)
			expect(graphCalls).to.equal(0)
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
			-- breaks if: the poll goes back to every 0.5 s (a map would be seen up to half a second late)
			expect(ZS.NAV_POLL).to.equal(0.1)
			expect(timers[NAV_TIMER].delay).to.equal(0.1)
			expect(timers[NAV_TIMER].reps).to.equal(0)
			expect(timerCreates).to.equal(1)
			expect(#logs).to.equal(1)
			expect(string.find(logs[1], "waiting for the navigation mesh (the file exists): checking every 0.1 s", 1, true) ~= nil).to.beTrue()

			-- the clients are told once (the radar veils on the state 2)
			local list = stateMessages()
			expect(#list).to.equal(1)
			expect(list[1].state).to.equal(2)
		end),
		-- breaks if: the poll does not remove the timer, does not start the computation with the navmesh source, or does not log the elapsed time
		case("the count becomes > 0 after some polls: the timer is removed, 'navigation mesh available after X.X s' is logged (the real elapsed time), the computation runs with the navmesh source and ends in state 4", function()
			useFakes({area(0, 0, 300, 300, 50), area(400, 0, 700, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			nowT = 100 -- the elapsed time is a difference, not the clock
			ZS.Start()

			for i = 1, 2 do
				nowT = nowT + 0.5
				timers[NAV_TIMER].fn()
				expect((ZS.State())).to.equal(2)
				expect(timers[NAV_TIMER] ~= nil).to.beTrue()
				expect(#logs).to.equal(1)
			end

			navNow = 2
			nowT = 101.46
			timers[NAV_TIMER].fn()
			expect(timers[NAV_TIMER]).to.beNil()
			expect(#timerRemoves).to.equal(1)
			expect(timerRemoves[1]).to.equal(NAV_TIMER)
			expect(#logs).to.equal(2)
			expect(logs[2]).to.equal("navigation mesh available after 1.5 s")
			expect((ZS.State())).to.equal(3)
			expect(ZS.Source()).to.equal("navmesh")
			expect(thinkHook() ~= nil).to.beTrue()

			finish()
			expect((ZS.State())).to.equal(4)
			expect(ZS.Source()).to.equal("navmesh")
			expect(thinkHook()).to.beNil()
			expect(graphCalls).to.equal(0)
			expect(disk[navPath()] ~= nil).to.beTrue()
			expect(disk[nodesPath()]).to.beNil()
			expect(ZS.Stats().source).to.equal("navmesh")

			local states = {}

			for _, m in ipairs(stateMessages()) do
				states[#states + 1] = m.state
			end

			expect(states[1]).to.equal(2)
			expect(states[#states]).to.equal(4)
			expect(timerCreates).to.equal(1)
		end),
		-- breaks if: a poll that raises (NavCount fails) stops the wait or the timer is left behind
		case("a poll where NavCount raises or answers nonsense counts as 'not yet': the wait goes on", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			ZS.Start()
			stub(ZS, "NavCount", function() error("not loaded") end)
			nowT = 0.5
			expect(function() timers[NAV_TIMER].fn() end).to.succeed()
			stub(ZS, "NavCount", function() return "many" end)
			nowT = 1
			expect(function() timers[NAV_TIMER].fn() end).to.succeed()
			expect((ZS.State())).to.equal(2)
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
		end),
		-- breaks if: the timeout is ignored (the wait would go on for ever), the timer is left behind, or the nodes are not used
		-- (the patience is a safety net of 60 s, the owner's decision of 2026-11-22; breaks if it goes back to 20 s: the wait would end at 30 s on the fake clock)
		case("the count stays 0 for 60 s: the timer is removed, 'the navigation mesh did not load in 60 s' is logged and the map is made from the nodes", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			expect(ZS.NAV_WAIT_MAX).to.equal(60)
			nowT = 10
			ZS.Start()
			nowT = 30 -- 20 s: the old patience is over, the new one is not
			timers[NAV_TIMER].fn()
			expect((ZS.State())).to.equal(2)
			nowT = 69
			timers[NAV_TIMER].fn()
			expect((ZS.State())).to.equal(2) -- 59 s: still waiting
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
			expect(ZS.Source()).to.equal("navmesh")

			nowT = 70
			timers[NAV_TIMER].fn()
			expect(timers[NAV_TIMER]).to.beNil()
			expect(#timerRemoves).to.equal(1)
			expect(#logs).to.equal(2)
			expect(logs[2]).to.equal("the navigation mesh did not load in 60 s: the in/out map is made from the AI node graph")
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			expect(graphCalls).to.equal(1)
			expect(navCalls).to.equal(0)

			finish()
			expect((ZS.State())).to.equal(4)
			expect(disk[nodesPath()] ~= nil).to.beTrue()
			expect(disk[navPath()]).to.beNil()
			expect(thinkHook()).to.beNil()
		end),
		-- breaks if: the choice waits when there is no .nav file (a level with no navmesh would be veiled for 20 s)
		case("no .nav file and 0 areas: the nodes at once, 'no navmesh' logged, no timer, the file was asked", function()
			useFakes({}, graphOf(5))
			navNow, fileExists = 0, false
			ZS.Start()
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			expect(next(timers)).to.beNil()
			expect(timerCreates).to.equal(0)
			expect(#logs).to.equal(1)
			expect(string.find(logs[1], "no navmesh", 1, true) ~= nil).to.beTrue()
			expect(fileCalls).to.equal(1)
		end),
		-- breaks if: a loaded navmesh still asks for the file or waits
		case("the count is already > 0: the navmesh at once, no wait, no timer, the file is not even asked", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			fileExists = true
			ZS.Start()
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(3)
			expect(next(timers)).to.beNil()
			expect(fileCalls).to.equal(0)
			expect(#logs).to.equal(0)
		end),
		-- breaks if: the cache file is not read at once when the engine's navmesh is not loaded (the wait would be useless: a file is read with no navmesh)
		case("a valid navmesh cache file is read at once even when the count is 0 and the file exists: state 4, the data sent, no wait, no timer, no area read", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			disk[navPath()] = Z.Encode(Z.Build({{x = 64, y = 64, z = 50, indoor = true, ceil = 2}}), {bspSize = BSP, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect((ZS.State())).to.equal(4)
			expect(ZS.Source()).to.equal("navmesh")
			expect(ZS.Bytes()).to.equal(disk[navPath()])
			expect(next(timers)).to.beNil()
			expect(timerCreates).to.equal(0)
			expect(thinkHook()).to.beNil()
			expect(navCalls).to.equal(0)
			expect(#logs).to.equal(0)

			local data = 0

			for _, m in ipairs(sent) do
				if m.name == "gry_zonemap_data" then
					data = data + 1
				end
			end

			expect(data).to.equal(1)
		end),
		-- breaks if: any cache file is trusted during the wait (a file made for another bsp must not end it)
		case("a navmesh cache file of another bsp size does not count: the wait starts", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			disk[navPath()] = Z.Encode(Z.Build({{x = 64, y = 64, z = 50, indoor = true, ceil = 2}}), {bspSize = BSP + 1, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect((ZS.State())).to.equal(2)
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
		end),
		-- breaks if: the setting at 0 waits for a navmesh the owner did not ask for
		case("the setting at 0: the nodes at once, even with 0 areas and a .nav file: no wait, no timer", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			setConvar("gry_zonemap_navmesh", "0")
			ZS.Start()
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			expect(next(timers)).to.beNil()
			expect(#logs).to.equal(0)
		end),
		-- breaks if: the switch of the setting during the wait does not cancel it (a timer left behind that would start a computation later)
		case("switching the setting during the wait cancels it: the timer is removed, the other source starts, and the old poll does nothing if it fires", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			stub(ZS, "OnSource", ORIGINAL.OnSource)
			navNow, fileExists = 0, true
			ZS.Start()
			expect((ZS.State())).to.equal(2)

			local oldPoll = timers[NAV_TIMER].fn

			GetConVar("gry_zonemap_navmesh"):SetString("0")
			expect(timers[NAV_TIMER]).to.beNil()
			expect(#timerRemoves).to.equal(1)
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			expect(thinkHook() ~= nil).to.beTrue()

			-- a poll that still fires (the engine's timer was already due) changes nothing
			navNow = 1
			nowT = 5
			oldPoll()
			expect(ZS.Source()).to.equal("nodes")
			expect((ZS.State())).to.equal(3)
			expect(next(timers)).to.beNil()

			finish()
			expect((ZS.State())).to.equal(4)
			expect(disk[nodesPath()] ~= nil).to.beTrue()
			expect(disk[navPath()]).to.beNil()
		end),
		-- breaks if: the switch back to the navmesh does not start a new wait (the navmesh is still 0) or leaves the first one
		case("switching to the navmesh while it is not loaded starts the wait again with ONE timer", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			stub(ZS, "OnSource", ORIGINAL.OnSource)
			navNow, fileExists = 0, true
			setConvar("gry_zonemap_navmesh", "0")
			ZS.Start()
			finish()
			GetConVar("gry_zonemap_navmesh"):SetString("1")
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(2)
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
			expect(timerCreates).to.equal(1)
		end),
		-- breaks if: a Reset leaves the wait's timer behind
		case("a Reset during the wait removes the timer and starts again (here the navmesh is there by then: the computation runs)", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			ZS.Start()
			expect(timers[NAV_TIMER] ~= nil).to.beTrue()
			navNow = 1
			ZS.Reset()
			expect(timers[NAV_TIMER]).to.beNil()
			expect(#timerRemoves).to.equal(1)
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(3)
			expect(thinkHook() ~= nil).to.beTrue()
			finish()
			expect((ZS.State())).to.equal(4)
		end),
		-- breaks if: the module's cancel or the forgetting of the map (a map change) does not stop the wait
		case("Cancel and Unload during the wait remove the timer; a stale poll that still fires does nothing", function()
			for _, stop in ipairs({"Cancel", "Unload"}) do
				useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
				navNow, fileExists = 0, true
				ZS.Start()

				local poll = timers[NAV_TIMER].fn

				ZS[stop]()
				expect(timers[NAV_TIMER]).to.beNil()
				expect(#timerRemoves).to.equal(1)

				navNow = 1
				poll()
				expect(thinkHook()).to.beNil()
				expect(next(timers)).to.beNil()
				expect(#logs).to.equal(1) -- the log of the wait; the poll said nothing
				cleanup()
			end
		end),
		-- breaks if: the switch of the in/out map going off leaves the timer (cancelJob is the one place that stops the wait)
		case("turning the in/out map off during the wait removes the timer", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			ZS.Start()
			ORIGINAL.OnSwitch("1", "0")
			expect(timers[NAV_TIMER]).to.beNil()
			expect((ZS.State())).to.equal(0)
		end),
		-- breaks if: a start that ends (a computation, a file) leaves the poll timer of an earlier wait
		case("a start that follows a wait never leaves two timers: the wait's timer is removed before the new start", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(5))
			navNow, fileExists = 0, true
			ZS.Start()
			ZS.Start()
			expect(timerCreates).to.equal(2)
			expect(#timerRemoves).to.equal(1)

			local n = 0

			for _ in pairs(timers) do
				n = n + 1
			end

			expect(n).to.equal(1)
		end),

		-- ----------------------------------------------------------------------------------------------- Reset
		-- breaks if: Reset deletes the file of the other source too (the owner's node files are his backup)
		case("Reset deletes the file of the CURRENT source only, and makes that map again", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(6))

			-- both files exist
			ZS.RunNow()
			setConvar("gry_zonemap_navmesh", "0")
			ZS.RunNow()
			local nodeBytes = disk[nodesPath()]
			local navBytes = disk[navPath()]
			expect(nodeBytes ~= nil and navBytes ~= nil).to.beTrue()

			-- the nodes are the current source: only their file goes
			deleted = {}
			ZS.Reset()
			expect(table.concat(deleted, ",")).to.equal(nodesPath())
			expect(disk[navPath()]).to.equal(navBytes)
			expect((ZS.State())).to.equal(3)
			finish()
			expect(disk[nodesPath()]).to.equal(nodeBytes)

			-- the navmesh is: only its file goes
			setConvar("gry_zonemap_navmesh", "1")
			deleted = {}
			ZS.Reset()
			expect(table.concat(deleted, ",")).to.equal(navPath())
			expect(disk[nodesPath()]).to.equal(nodeBytes)
			expect(ZS.Source()).to.equal("navmesh")
			expect((ZS.State())).to.equal(3)
			finish()
			expect(disk[navPath()]).to.equal(navBytes)
		end),
		-- breaks if: the fresh run of the tools deletes the other file too
		case("RunNow with fresh deletes the current source's file only", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(6))
			ZS.RunNow()
			setConvar("gry_zonemap_navmesh", "0")
			ZS.RunNow()
			deleted = {}
			ZS.RunNow(nil, true)
			expect(table.concat(deleted, ",")).to.equal(nodesPath())
			expect(disk[navPath()] ~= nil).to.beTrue()
		end),
		-- breaks if: the reset of an administrator (the net message) does not go through the same rule
		case("the administrators' reset deletes the current source's file only", function()
			useFakes({area(0, 0, 300, 300, 50)}, graphOf(6))
			ZS.RunNow()
			setConvar("gry_zonemap_navmesh", "0")
			ZS.RunNow()
			setConvar("gry_zonemap_navmesh", "1")
			deleted = {}
			expect(ZS.HandleReset({IsValid = function() return true end, IsAdmin = function() return true end, Nick = function() return "admin" end}, 500)).to.equal("ok")
			expect(table.concat(deleted, ",")).to.equal(navPath())
			expect(disk[nodesPath()] ~= nil).to.beTrue()
		end),
	}
}
