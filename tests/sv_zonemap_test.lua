-- Tests of the SERVER side of the in/out map (GryMod.ZoneMapServer, lua/grymod/server/sv_zonemap.lua), GLuaTest format, server realm.
-- Design: docs/superpowers/specs/2026-11-22-zonemap-design.md. What the module does: it reads the map's node graph (GryMod.AIN), casts 13 rays at each ground
-- node (5 up, 8 around) to find out whether the place is under a ceiling and narrow, builds the map (GryMod.ZoneMap, the pure shared module), keeps it in a file
-- of data/grymod/zonemap, and sends it to the clients through four net messages. Everything the module needs from the engine (the trace, the graph, the files, the
-- clock) is a field of GryMod.ZoneMapServer, so these cases replace them with fakes; every stand-in is put back by ONE function (cleanup) that runs after each case
-- even when the case failed (a leaked net stub once left the owner's client without network), and the net functions are recorded, never sent.
-- The pure module may not exist yet: then a small stand-in of GryMod.ZoneMap is defined here (and removed at the end).

local ZS, Z
local standIn = false
local HOOK = "GryMod zonemap"
local MAPNAME = "grymod_test_zonemap"
local BSP = 1234
local ORIGINAL = {} -- the real fields of ZS, taken once
local FIELDS = {"Trace", "Graph", "Clock", "ReadFile", "WriteFile", "DeleteFile", "BspSize", "MapName", "Now", "Log", "OnSwitch", "NavAreas", "NavCount", "OnSource"}
local CONVARS = {"gry_zonemap", "gry_zonemap_budget_ms", "gry_zonemap_max_nodes", "gry_zonemap_navmesh"}
local CONVAR_ORIGINAL = {}

-- ---------------------------------------------------------------------------------------------------------
-- the stand-in of the pure module (used only while sh_zonemap.lua does not exist)
-- ---------------------------------------------------------------------------------------------------------
local function makeStandIn()
	local S = {}
	local CLASSES = {56, 88, 120, 160, 224, 320, 448}

	function S.CeilIndex(room)
		local r = room - 8
		local index = 1

		for i = 1, 7 do
			if CLASSES[i] <= r then
				index = i
			end
		end

		return index
	end

	function S.Key(map, size)
		return string.lower(string.gsub(tostring(map), "[^a-zA-Z0-9_%-%.]", "_")) .. "_" .. tostring(size or 0) .. "_v1"
	end

	function S.Build(samples)
		local boxes = {}

		for i = 1, #samples do
			boxes[i] = {layer = 0, x1 = i, y1 = 0, x2 = i, y2 = 0, state = samples[i].indoor and 2 or 1, ceil = samples[i].ceil}
		end

		return {boxes = boxes, sampleCount = #samples, skipped = 0, cells = #samples}
	end

	local function sum(text)
		local total = 0

		for i = 1, #text do
			total = (total + string.byte(text, i)) % 4294967296
		end

		return total
	end

	function S.Encode(map, header)
		local body = table.concat({"GZMX", header.bspSize or 0, header.nodeCount or 0, header.complete and 1 or 0, header.overBudget and 1 or 0, map.sampleCount, #map.boxes}, "|")

		return body .. "|" .. sum(body)
	end

	function S.Decode(bytes)
		if type(bytes) ~= "string" then
			return nil, "not a string"
		end

		local body, check = string.match(bytes, "^(.*)|(%d+)$")

		if not body or tonumber(check) ~= sum(body) then
			return nil, "bad checksum"
		end

		local magic, bsp, nodes, complete, over, samples, boxes = string.match(body, "^(GZMX)|(%d+)|(%d+)|(%d)|(%d)|(%d+)|(%d+)$")

		if not magic then
			return nil, "bad magic"
		end

		local list = {}

		for i = 1, tonumber(boxes) do
			list[i] = {}
		end

		return {boxes = list, sampleCount = tonumber(samples), skipped = 0, cells = 0},
			{bspSize = tonumber(bsp), nodeCount = tonumber(nodes), complete = complete == "1", overBudget = over == "1", sampleCount = tonumber(samples)}
	end

	return S
end

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

-- the files the tests may have made in data/grymod/zonemap for the test map (the real run of the integration case makes the file of the REAL map: not touched)
local function cleanTestFiles()
	for _, name in ipairs(file.Find("grymod/zonemap/" .. MAPNAME .. "*", "DATA") or {}) do
		file.Delete("grymod/zonemap/" .. name)
	end
end

local function cleanup()
	if ZS then
		-- a convar put back must not start anything: the switch's callback does nothing while the stand-ins go away
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

	-- whatever happened, the real functions are back (a stand-in that outlives its case would stay in the owner's game)
	if ZS then
		for _, f in ipairs(FIELDS) do
			if ORIGINAL[f] ~= nil then
				ZS[f] = ORIGINAL[f]
			end
		end
	end

	pcall(cleanTestFiles)
end

-- a case that cleans up whatever happens
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

local function messages(name)
	local list = {}

	for _, m in ipairs(sent) do
		if m.name == name then
			list[#list + 1] = m
		end
	end

	return list
end

-- the numbers of a state message: state, done, total
local function stateOf(m)
	return m.w[1][2], m.w[2][2], m.w[3][2]
end

local function fakePlayer(admin)
	return {
		IsValid = function() return true end,
		IsAdmin = function() return admin end,
		Nick = function() return admin and "admin" or "player" end
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- fake world: the trace
-- ---------------------------------------------------------------------------------------------------------
local calls, traceCalls, clockT, nowT, graphCalls, logs, disk, deleted

-- spec.ceil: nil (nothing above), "sky", a height over the node, or a function(ox, oy) of the ray's offset from the node (spec.x, spec.y);
-- spec.wall: a distance in units (nil or >= 1050: nothing hit), or a function(index 0..7) with index = the direction in 45 degree steps;
-- spec.tick: seconds the fake clock moves at each ray; spec.fraction: the walls answer a Fraction (otherwise the distance is in HitPos too).
local function makeTrace(spec)
	return function(p)
		traceCalls = traceCalls + 1

		if spec.tick then
			clockT = clockT + spec.tick
		end

		local s, e = p.start, p.endpos

		calls[#calls + 1] = {sx = s.x, sy = s.y, sz = s.z, ex = e.x, ey = e.y, ez = e.z, mask = p.mask}

		if e.z - s.z > 1000 then
			local rel = spec.ceil

			if type(rel) == "function" then
				rel = rel(s.x - (spec.x or 0), s.y - (spec.y or 0))
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
		local index = math.floor(math.atan2(dy, dx) / (math.pi / 4) + 0.5) % 8
		local d = spec.wall

		if type(d) == "function" then
			d = d(index)
		end

		if d == nil or d >= length then
			return {Hit = false, HitSky = false, HitPos = Vector(e.x, e.y, e.z), Fraction = 1}
		end

		return {Hit = true, HitSky = false, HitPos = Vector(s.x + dx / length * d, s.y + dy / length * d, s.z), Fraction = d / length}
	end
end

local function graphOf(ground, air)
	local nodes = {}

	for i = 1, air or 0 do
		nodes[#nodes + 1] = {x = 99999, y = 99999, z = 0, yaw = 0, type = 3, info = 0, zone = 0}
	end

	for i = 1, ground do
		nodes[#nodes + 1] = {x = i * 64, y = (i % 7) * 64, z = 100, yaw = 0, type = 2, info = 0, zone = 0}
	end

	return {version = 37, mapVersion = 1, nodes = nodes, links = {}, lookup = {}}
end

-- an indoor room: a ceiling 200 over the nodes, walls 300 away
local ROOM = {ceil = 200, wall = 300}

-- installs the fakes; the switch's callback does nothing, the clock and the time are the test's
local function useFakes(spec, graph)
	calls, traceCalls, clockT, nowT, graphCalls, logs, disk, deleted = {}, 0, 0, 0, 0, {}, {}, {}

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

		return graph or graphOf(10, 2)
	end)
	setConvar("gry_zonemap", "1")
	setConvar("gry_zonemap_budget_ms", "2")
	setConvar("gry_zonemap_max_nodes", "20000")
	-- these cases are about the node source: the navmesh of the test game does not count (the navmesh source has its own file, sv_zonemap_navmesh_test.lua)
	setConvar("gry_zonemap_navmesh", "0")
	ZS.Unload()
end

local function path()
	return "grymod/zonemap/" .. Z.Key(MAPNAME, BSP) .. ".dat"
end

local function thinkHook()
	local list = hook.GetTable().Think

	return list and list[HOOK]
end

-- one frame of the engine for the module: the Think hook, if it is there
local function think()
	local f = thinkHook()

	if f then
		f()

		return true
	end

	return false
end

-- Think until the hook is gone; the number of frames
local function finish(limit)
	local n = 0

	while thinkHook() and n < (limit or 10000) do
		think()
		n = n + 1
	end

	return n
end

-- the samples that reach GryMod.ZoneMap.Build
local function spyBuild()
	local got = {}
	local real = Z.Build

	stub(Z, "Build", function(samples)
		got.samples = samples

		return real(samples)
	end)

	return got
end

-- the sample of one node, the 13 rays and their order seen from outside
local function sampleOf(spec, x, y, z)
	calls, traceCalls = {}, 0
	stub(ZS, "Trace", makeTrace(spec))
	spec.x, spec.y = x, y

	return ZS.SampleNode(x, y, z)
end

local function countCalls(up)
	local n = 0

	for _, c in ipairs(calls) do
		if (c.ez - c.sz > 1000) == up then
			n = n + 1
		end
	end

	return n
end

-- ---------------------------------------------------------------------------------------------------------
return {
	groupName = "GryMod zone map, server side (sv_zonemap.lua)",
	beforeAll = function()
		ZS = GryMod.ZoneMapServer

		if not GryMod.ZoneMap then
			GryMod.ZoneMap = makeStandIn()
			standIn = true
		end

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

		if standIn then
			GryMod.ZoneMap = nil
		end

		-- the game goes on with its real map: the switch's value as it was, then the module starts again from the file (or makes it)
		for _, name in ipairs(CONVARS) do
			local convar = GetConVar(name)

			if convar and CONVAR_ORIGINAL[name] and convar:GetString() ~= CONVAR_ORIGINAL[name] then
				pcall(convar.SetString, convar, CONVAR_ORIGINAL[name])
			end
		end

		if ZS and ZS.Unload and not standIn then
			pcall(ZS.Unload)
			pcall(ZS.Start)
		end
	end,
	cases = {
		-- ----------------------------------------------------------------------------------------------- wiring
		case("the module exists with its public functions and the fields the tests replace", function()
			expect(ZS ~= nil).to.beTrue()

			for _, f in ipairs({"State", "Bytes", "Map", "RunNow", "Reset", "Start", "Cancel", "Unload", "SampleNode", "SendData", "SendState", "HandleWant", "HandleReset"}) do
				expect(isfunction(ZS[f])).to.beTrue()
			end

			for _, f in ipairs(FIELDS) do
				expect(isfunction(ZS[f])).to.beTrue()
			end
		end),
		case("the five net strings exist and the two receivers are registered", function()
			for _, name in ipairs({"gry_zonemap_state", "gry_zonemap_data", "gry_zonemap_want", "gry_zonemap_reset"}) do
				expect(util.NetworkStringToID(name) ~= 0).to.beTrue()
			end

			expect(net.Receivers["gry_zonemap_want"] ~= nil).to.beTrue()
			expect(net.Receivers["gry_zonemap_reset"] ~= nil).to.beTrue()
		end),
		case("the switch gry_zonemap is in the administrators' white list (a yes / no setting, replicated, on by default); the budget and the node maximum are not", function()
			local S = GryMod.ServerSettings
			expect(S.Find("gry_zonemap") ~= nil).to.beTrue()
			expect(S.Find("gry_zonemap").kind).to.equal("bool")
			expect(S.Validate("gry_zonemap", "1")).to.equal("1")
			expect(S.Validate("gry_zonemap", "0")).to.equal("0")
			expect(S.Validate("gry_zonemap", "2")).to.beNil()

			local switch = GetConVar("gry_zonemap")
			expect(switch ~= nil).to.beTrue()
			expect(switch:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
			expect(switch:IsFlagSet(FCVAR_NOTIFY)).to.beTrue()
			expect(switch:GetDefault()).to.equal("1")

			expect(S.Find("gry_zonemap_budget_ms")).to.beNil()
			expect(S.Find("gry_zonemap_max_nodes")).to.beNil()

			local budget, max = GetConVar("gry_zonemap_budget_ms"), GetConVar("gry_zonemap_max_nodes")
			expect(budget ~= nil and max ~= nil).to.beTrue()
			expect(budget:GetDefault()).to.equal("2")
			expect(budget:GetMin()).to.equal(0.5)
			expect(budget:GetMax()).to.equal(10)
			expect(max:GetDefault()).to.equal("20000")
		end),
		case("no Think hook while nothing is computed, and the map-start hook is there", function()
			useFakes()
			expect(thinkHook()).to.beNil()
			expect(hook.GetTable().InitPostEntity[HOOK] ~= nil).to.beTrue()
		end),
		case("the map-start hook starts the module once: a second call does nothing", function()
			useFakes()
			local f = hook.GetTable().InitPostEntity[HOOK]
			f()
			expect(graphCalls).to.equal(1)
			f()
			expect(graphCalls).to.equal(1)
		end),

		-- ----------------------------------------------------------------------------------------------- the sample of a node
		case("a centre ray that hits the sky is open: not indoor, ceiling class 0, and the node costs no more than the 13 rays", function()
			useFakes()
			local indoor, ceil = sampleOf({ceil = "sky", wall = 300}, 500, -300, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(0)
			expect(traceCalls <= 13).to.beTrue()
		end),
		case("a centre ray that hits nothing is open too", function()
			useFakes()
			local indoor, ceil = sampleOf({ceil = nil, wall = 300}, 0, 0, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(0)
		end),
		case("an indoor node casts exactly 13 rays: five up from z + 72 to z + 32768 (the centre and four 48 units away) with the brush mask, eight around at z + 36 of 1050 units", function()
			useFakes()
			local indoor = sampleOf({ceil = 200, wall = 300}, 500, -300, 100)
			expect(indoor).to.beTrue()
			expect(#calls).to.equal(13)
			expect(countCalls(true)).to.equal(5)
			expect(countCalls(false)).to.equal(8)

			local offsets = {}

			for _, c in ipairs(calls) do
				expect(c.mask).to.equal(MASK_SOLID_BRUSHONLY)

				if c.ez - c.sz > 1000 then
					expect(c.sz).to.equal(172)
					expect(c.ez).to.equal(100 + 32768)
					expect(c.ex).to.equal(c.sx)
					expect(c.ey).to.equal(c.sy)
					offsets[#offsets + 1] = (c.sx - 500) .. "," .. (c.sy + 300)
				else
					expect(c.sz).to.equal(136)
					expect(c.ez).to.equal(136)
					expect(c.sx).to.equal(500)
					expect(c.sy).to.equal(-300)
					expect(math.abs(math.sqrt((c.ex - c.sx) ^ 2 + (c.ey - c.sy) ^ 2) - 1050) < 0.01).to.beTrue()
				end
			end

			table.sort(offsets)
			expect(table.concat(offsets, " ")).to.equal("-48,0 0,-48 0,0 0,48 48,0")

			-- eight different directions
			local seen = {}

			for _, c in ipairs(calls) do
				if c.ez - c.sz <= 1000 then
					seen[math.floor(math.atan2(c.ey - c.sy, c.ex - c.sx) / (math.pi / 4) + 0.5) % 8] = true
				end
			end

			expect(table.Count(seen)).to.equal(8)
		end),
		case("the ceiling class is the one of GryMod.ZoneMap.CeilIndex(ceiling - z): 56 .. 448 for 40 .. 512 units, as the floors of the minimap", function()
			useFakes()

			-- {ceiling height over the node, expected class index}
			local table_ = {{40, 1}, {64, 1}, {100, 2}, {130, 3}, {170, 4}, {240, 5}, {330, 6}, {460, 7}, {512, 7}}

			for _, row in ipairs(table_) do
				local indoor, ceil = sampleOf({ceil = row[1], wall = 300}, 0, 0, 100)
				expect(indoor).to.beTrue()
				expect(ceil).to.equal(row[2])
				expect(ceil).to.equal(Z.CeilIndex(row[1]))
			end
		end),
		case("a ceiling more than 512 units over the node is open (not indoor, class 0), 512 itself is not", function()
			useFakes()

			for _, h in ipairs({513, 600, 5000}) do
				local indoor, ceil = sampleOf({ceil = h, wall = 300}, 0, 0, 100)
				expect(indoor).to.beFalse()
				expect(ceil).to.equal(0)
			end

			expect((sampleOf({ceil = 512, wall = 300}, 0, 0, 100))).to.beTrue()
		end),
		case("the highest of the five ceilings counts; a side ray that sees the sky or nothing is ignored; a centre ray in the sky is open whatever the others see", function()
			useFakes()

			-- the +X ray hits at 300: the highest, class of 300 (224 = 5)
			local _, ceil = sampleOf({ceil = function(ox, oy) return ox == 48 and 300 or 150 end, wall = 300}, 0, 0, 100)
			expect(ceil).to.equal(Z.CeilIndex(300))
			expect(ceil).to.equal(5)

			-- the sides see the sky or nothing: the centre's 150 counts (class 120 = 3)
			_, ceil = sampleOf({ceil = function(ox, oy) return (ox == 0 and oy == 0) and 150 or "sky" end, wall = 300}, 0, 0, 100)
			expect(ceil).to.equal(3)
			_, ceil = sampleOf({ceil = function(ox, oy) return (ox == 0 and oy == 0) and 150 or nil end, wall = 300}, 0, 0, 100)
			expect(ceil).to.equal(3)

			-- the centre sees the sky, the sides a ceiling: open
			local indoor
			indoor, ceil = sampleOf({ceil = function(ox, oy) return (ox == 0 and oy == 0) and "sky" or 150 end, wall = 300}, 0, 0, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(0)

			-- a side ray above 512 is the highest: open
			indoor, ceil = sampleOf({ceil = function(ox, oy) return ox == -48 and 700 or 150 end, wall = 300}, 0, 0, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(0)
		end),
		case("narrow is a median of the eight distances under 15 m = 787.5 units (each capped at 1050): 787 is indoor, 788 is not, nothing hit is wide; the class stays when the place is wide", function()
			useFakes()
			expect((sampleOf({ceil = 200, wall = 300}, 0, 0, 100))).to.beTrue()
			expect((sampleOf({ceil = 200, wall = 700}, 0, 0, 100))).to.beTrue()
			expect((sampleOf({ceil = 200, wall = 787}, 0, 0, 100))).to.beTrue()

			local indoor, ceil = sampleOf({ceil = 200, wall = 788}, 0, 0, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(4)

			indoor, ceil = sampleOf({ceil = 200, wall = nil}, 0, 0, 100)
			expect(indoor).to.beFalse()
			expect(ceil).to.equal(4)
		end),
		case("it is the MEDIAN, not the mean: three close walls and five open sides is wide, five close walls and three open sides is narrow", function()
			useFakes()
			local indoor = sampleOf({ceil = 200, wall = function(i) return i < 3 and 10 or nil end}, 0, 0, 100)
			expect(indoor).to.beFalse() -- mean 660 would say narrow; sorted: 10 10 10 1050 1050 ...: median 1050

			indoor = sampleOf({ceil = 200, wall = function(i) return i < 5 and 10 or nil end}, 0, 0, 100)
			expect(indoor).to.beTrue() -- sorted: 10 x5, 1050 x3: median 10

			-- four and four: the median is the middle of 10 and 1050 = 530
			indoor = sampleOf({ceil = 200, wall = function(i) return i < 4 and 10 or nil end}, 0, 0, 100)
			expect(indoor).to.beTrue()
		end),

		-- ----------------------------------------------------------------------------------------------- states
		case("the switch off: state 0, nothing read, nothing computed, no hook, and the state goes out", function()
			useFakes()
			setConvar("gry_zonemap", "0")
			ZS.Start()
			expect((ZS.State())).to.equal(0)
			expect(graphCalls).to.equal(0)
			expect(traceCalls).to.equal(0)
			expect(thinkHook()).to.beNil()
			expect(next(disk)).to.beNil()
			local list = messages("gry_zonemap_state")
			expect(#list).to.equal(1)
			expect(select(1, stateOf(list[1]))).to.equal(0)
			expect(list[1].target).to.equal("all")
		end),
		case("the graph is asked in state 2 (waiting), the state goes through 3 (computing, done / total) to 4 (ready)", function()
			local seen
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, nil)
			stub(ZS, "Graph", function()
				seen = ZS.State()
				graphCalls = graphCalls + 1

				return graphOf(10, 2)
			end)
			ZS.Start()
			expect(seen).to.equal(2)

			local state, done, total = ZS.State()
			expect(state).to.equal(3)
			expect(done).to.equal(0)
			expect(total).to.equal(10) -- the ground nodes only
			expect(thinkHook() ~= nil).to.beTrue()

			finish()
			state, done, total = ZS.State()
			expect(state).to.equal(4)
			expect(done).to.equal(10)
			expect(total).to.equal(10)
			expect(thinkHook()).to.beNil()
		end),
		case("no graph, a refused graph, an empty graph and a graph without ground node: state 1, the reason is kept and logged once, nothing is computed or written", function()
			for _, answer in ipairs({{nil, "no graph"}, {nil, "bad version"}, {{nodes = {}, links = {}}}, {graphOf(0, 5)}}) do
				useFakes()
				stub(ZS, "Graph", function() return answer[1], answer[2] end)
				ZS.Start()
				expect((ZS.State())).to.equal(1)
				expect(thinkHook()).to.beNil()
				expect(traceCalls).to.equal(0)
				expect(next(disk)).to.beNil()
				expect(#logs).to.equal(1)
				expect(isstring(ZS.Reason())).to.beTrue()

				if answer[2] then
					expect(ZS.Reason()).to.equal(answer[2])
				end

				expect(select(1, stateOf(messages("gry_zonemap_state")[#messages("gry_zonemap_state")]))).to.equal(1)
				cleanup()
			end
		end),
		case("the samples are the ground nodes (type 2 only) in file order, with the five fields Build reads", function()
			useFakes(ROOM, graphOf(6, 3))
			local got = spyBuild()
			ZS.Start()
			finish()
			expect(#got.samples).to.equal(6)

			for i, s in ipairs(got.samples) do
				expect(s.x).to.equal(i * 64)
				expect(s.y).to.equal((i % 7) * 64)
				expect(s.z).to.equal(100)
				expect(s.indoor).to.beTrue()
				expect(s.ceil).to.equal(Z.CeilIndex(200))
			end
		end),
		case("the file's header: the bsp size, the number of ground nodes, complete; the map and its bytes stay in memory", function()
			useFakes(ROOM, graphOf(8, 2))
			ZS.Start()
			finish()

			local bytes = ZS.Bytes()
			expect(isstring(bytes)).to.beTrue()
			expect(ZS.Map() ~= nil).to.beTrue()

			local map, header = Z.Decode(bytes)
			expect(map ~= nil).to.beTrue()
			expect(header.bspSize).to.equal(BSP)
			expect(header.nodeCount).to.equal(8)
			expect(header.complete).to.beTrue()
			expect(header.overBudget).to.beFalse()
			expect(select(4, ZS.State())).to.equal(#bytes)
			expect(disk[path()]).to.equal(bytes)
		end),
		case("over the node maximum: only the first ground nodes are used, the header says over budget and not complete, the state ends at 5", function()
			useFakes(ROOM, graphOf(10, 1))
			setConvar("gry_zonemap_max_nodes", "4")
			local got = spyBuild()
			ZS.Start()

			local _, done, total = ZS.State()
			expect(total).to.equal(4)
			finish()
			expect(#got.samples).to.equal(4)
			expect(got.samples[4].x).to.equal(4 * 64)

			local _, _, _ = ZS.State()
			expect((ZS.State())).to.equal(5)

			local _, header = Z.Decode(ZS.Bytes())
			expect(header.overBudget).to.beTrue()
			expect(header.complete).to.beFalse()
			expect(header.nodeCount).to.equal(10)
		end),
		case("a node with a coordinate that is not a number is skipped (no ray), and the result is incomplete: state 5", function()
			local graph = graphOf(5, 0)
			graph.nodes[3].x = 0 / 0
			graph.nodes[4].z = math.huge
			useFakes(ROOM, graph)
			local got = spyBuild()
			ZS.Start()
			finish()
			expect(#got.samples).to.equal(3)
			expect(traceCalls).to.equal(3 * 13)
			expect((ZS.State())).to.equal(5)

			local _, header = Z.Decode(ZS.Bytes())
			expect(header.complete).to.beFalse()
			expect(header.overBudget).to.beFalse()
		end),
		case("an error in the computation (the trace raises): state 6, logged once, nothing raised, the hook is removed, nothing is written; a new Start works again", function()
			useFakes()
			stub(ZS, "Trace", function() error("boom") end)
			ZS.Start()
			expect(thinkHook() ~= nil).to.beTrue()
			expect(function() think() end).to.succeed()
			expect((ZS.State())).to.equal(6)
			expect(thinkHook()).to.beNil()
			expect(#logs).to.equal(1)
			expect(string.find(logs[1], "boom", 1, true) ~= nil).to.beTrue()
			expect(next(disk)).to.beNil()
			expect(ZS.Bytes()).to.beNil()

			local list = messages("gry_zonemap_state")
			expect(select(1, stateOf(list[#list]))).to.equal(6)

			stub(ZS, "Trace", makeTrace(ROOM))
			ZS.Start()
			finish()
			expect((ZS.State())).to.equal(4)
		end),
		case("an error in the graph reader is state 6 too, nothing raised", function()
			useFakes()
			stub(ZS, "Graph", function() error("bad reader") end)
			expect(function() ZS.Start() end).to.succeed()
			expect((ZS.State())).to.equal(6)
			expect(thinkHook()).to.beNil()
			expect(#logs).to.equal(1)
		end),
		case("Start while a computation runs begins again from zero with one hook only", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()
			think()

			local _, done = ZS.State()
			expect(done > 0).to.beTrue()
			ZS.Start()

			local state
			state, done = ZS.State()
			expect(state).to.equal(3)
			expect(done).to.equal(0)
			finish()
			expect((ZS.State())).to.equal(4)
		end),
		case("the switch: 1 to 0 cancels the computation (state 0, no hook, nothing in memory), 0 to 1 starts it again", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			stub(ZS, "OnSwitch", ORIGINAL.OnSwitch)
			ZS.Start()
			think()
			expect((ZS.State())).to.equal(3)

			GetConVar("gry_zonemap"):SetString("0")
			expect((ZS.State())).to.equal(0)
			expect(thinkHook()).to.beNil()
			expect(ZS.Bytes()).to.beNil()

			GetConVar("gry_zonemap"):SetString("1")
			expect((ZS.State())).to.equal(3)
			expect(thinkHook() ~= nil).to.beTrue()
			finish()
			expect((ZS.State())).to.equal(4)
		end),

		-- ----------------------------------------------------------------------------------------------- the budget and the hook
		case("a frame works until the budget is used, never more than one node beyond it; the hook is there while it works and gone at the end", function()
			-- a node costs 13 rays of 10 microseconds = 130 us; the budget is 0.5 ms: four nodes a frame
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(100, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()
			expect(thinkHook() ~= nil).to.beTrue()
			expect(traceCalls).to.equal(0) -- Start itself computes nothing

			local frames, last = 0, 0
			local nodeTime = 13 * 0.00001

			while thinkHook() and frames < 1000 do
				local t0 = clockT
				think()
				frames = frames + 1

				local spent = clockT - t0
				expect(spent <= 0.0005 + nodeTime + 1e-9).to.beTrue()

				local _, done = ZS.State()
				expect(done > last).to.beTrue()

				-- not a node a frame: the budget is used (but at the last frame)
				if thinkHook() then
					expect(spent >= 0.0005 - 1e-9).to.beTrue()
				end

				last = done
			end

			expect(frames > 10).to.beTrue()
			expect(frames < 100).to.beTrue()
			expect((ZS.State())).to.equal(4)
			expect(thinkHook()).to.beNil()
		end),
		case("the budget is the convar's: 10 ms a frame does more per frame than 0.5 ms", function()
			local function framesFor(ms)
				useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(200, 0))
				setConvar("gry_zonemap_budget_ms", ms)
				ZS.Start()

				local n = finish()
				cleanup()

				return n
			end

			local small, big = framesFor("0.5"), framesFor("10")
			expect(big < small).to.beTrue()
			expect(big).to.equal(3) -- 200 nodes * 130 us = 26 ms: 10 ms makes 77 nodes a frame
		end),
		case("state messages while computing: the first at once, then at most four a second, the final one always", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(100, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()

			-- 25 frames, one every tenth of a second: 2.5 s
			local frames = 0

			while thinkHook() and frames < 200 do
				nowT = nowT + 0.1
				think()
				frames = frames + 1
			end

			local computing = 0

			for _, m in ipairs(messages("gry_zonemap_state")) do
				if select(1, stateOf(m)) == 3 then
					computing = computing + 1
				end
			end

			expect(computing >= 2).to.beTrue()
			expect(computing <= math.floor(nowT * 4) + 1).to.beTrue()

			local list = messages("gry_zonemap_state")
			local state, done, total = stateOf(list[#list])
			expect(state).to.equal(4)
			expect(done).to.equal(100)
			expect(total).to.equal(100)
		end),
		case("RunNow is a synchronous complete run: no hook at any time, state 4, the same file as the frames make", function()
			useFakes(ROOM, graphOf(30, 2))
			expect(ZS.RunNow()).to.equal(4)
			expect(thinkHook()).to.beNil()
			local bytes = ZS.Bytes()
			expect(disk[path()]).to.equal(bytes)

			ZS.Unload()
			disk = {}
			ZS.Start()
			finish()
			expect(ZS.Bytes()).to.equal(bytes)
		end),
		case("RunNow stops a computation that was running (one run only)", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()
			think()
			expect(ZS.RunNow()).to.equal(4)
			expect(thinkHook()).to.beNil()
		end),

		-- ----------------------------------------------------------------------------------------------- the file
		case("a file made once is read again with no graph, no ray, no hook: state 4", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.Start()
			finish()

			local bytes = ZS.Bytes()
			ZS.Unload()
			graphCalls, traceCalls = 0, 0
			ZS.Start()
			expect((ZS.State())).to.equal(4)
			expect(graphCalls).to.equal(0)
			expect(traceCalls).to.equal(0)
			expect(thinkHook()).to.beNil()
			expect(ZS.Bytes()).to.equal(bytes)
		end),
		case("a file flagged incomplete is ready as state 5, with no computation", function()
			useFakes(ROOM, graphOf(10, 0))
			local map = Z.Build({{x = 0, y = 0, z = 0, indoor = true, ceil = 2}, {x = 200, y = 0, z = 0, indoor = false, ceil = 0}})
			disk[path()] = Z.Encode(map, {bspSize = BSP, nodeCount = 99, complete = false, overBudget = true})
			ZS.Start()
			expect((ZS.State())).to.equal(5)
			expect(graphCalls).to.equal(0)
			expect(traceCalls).to.equal(0)
			expect(thinkHook()).to.beNil()
		end),
		case("a file that belongs to another bsp size is ignored and made again (and replaced)", function()
			useFakes(ROOM, graphOf(10, 0))
			local map = Z.Build({{x = 0, y = 0, z = 0, indoor = true, ceil = 2}})
			disk[path()] = Z.Encode(map, {bspSize = BSP + 1, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect(graphCalls).to.equal(1)
			expect((ZS.State())).to.equal(3)
			finish()
			expect((ZS.State())).to.equal(4)

			local _, header = Z.Decode(disk[path()])
			expect(header.bspSize).to.equal(BSP)
			expect(header.nodeCount).to.equal(10)
		end),
		case("when the bsp size is not known (the game's file is missing) or the file does not say, the file is kept", function()
			useFakes(ROOM, graphOf(10, 0))
			local map = Z.Build({{x = 0, y = 0, z = 0, indoor = true, ceil = 2}})
			disk[path()] = Z.Encode(map, {bspSize = 0, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect((ZS.State())).to.equal(4)
			expect(graphCalls).to.equal(0)

			cleanup()
			useFakes(ROOM, graphOf(10, 0))
			stub(ZS, "BspSize", function() return 0 end)
			disk["grymod/zonemap/" .. Z.Key(MAPNAME, 0) .. ".dat"] = Z.Encode(map, {bspSize = 777, nodeCount = 1, complete = true, overBudget = false})
			ZS.Start()
			expect((ZS.State())).to.equal(4)
			expect(graphCalls).to.equal(0)
		end),
		case("a corrupt, a truncated and a foreign file are ignored and the map is made again", function()
			for _, how in ipairs({"flip", "cut", "garbage", "empty"}) do
				useFakes(ROOM, graphOf(10, 0))
				ZS.Start()
				finish()

				local good = ZS.Bytes()
				local bad

				if how == "flip" then
					local at = math.floor(#good / 2)
					bad = string.sub(good, 1, at - 1) .. string.char((string.byte(good, at) + 1) % 256) .. string.sub(good, at + 1)
				elseif how == "cut" then
					bad = string.sub(good, 1, #good - 3)
				elseif how == "garbage" then
					bad = "this is not a zone map file"
				else
					bad = ""
				end

				ZS.Unload()
				disk[path()] = bad
				graphCalls = 0
				ZS.Start()
				expect(graphCalls).to.equal(1)
				finish()
				expect((ZS.State())).to.equal(4)
				expect(disk[path()]).to.equal(good)
				cleanup()
			end
		end),
		case("a write that fails does not lose the map: state 4, the bytes are in memory, the failure is logged", function()
			useFakes(ROOM, graphOf(10, 0))
			stub(ZS, "WriteFile", function() return false, "disk full" end)
			ZS.Start()
			finish()
			expect((ZS.State())).to.equal(4)
			expect(isstring(ZS.Bytes())).to.beTrue()
			expect(#logs).to.equal(1)
			expect(string.find(logs[1], "disk full", 1, true) ~= nil).to.beTrue()
		end),
		case("the real files: the file is written with one write, its size is the bytes' size, and a new start reads it back with no computation", function()
			useFakes(ROOM, graphOf(12, 1))
			stub(ZS, "ReadFile", ORIGINAL.ReadFile)
			stub(ZS, "WriteFile", ORIGINAL.WriteFile)
			stub(ZS, "DeleteFile", ORIGINAL.DeleteFile)
			cleanTestFiles()
			ZS.RunNow()
			expect((ZS.State())).to.equal(4)

			local bytes = ZS.Bytes()
			expect(file.Exists(path(), "DATA")).to.beTrue()
			expect(file.Size(path(), "DATA")).to.equal(#bytes)
			expect(file.Read(path(), "DATA") == bytes).to.beTrue()

			ZS.Unload()
			graphCalls, traceCalls = 0, 0
			ZS.Start()
			expect((ZS.State())).to.equal(4)
			expect(graphCalls).to.equal(0)
			expect(traceCalls).to.equal(0)
			expect(ZS.Bytes() == bytes).to.beTrue()

			-- a byte changed on the disk: ignored and made again, the file is right again
			local bad = string.sub(bytes, 1, 30) .. string.char((string.byte(bytes, 31) + 1) % 256) .. string.sub(bytes, 32)
			local f = file.Open(path(), "wb", "DATA")
			f:Write(bad)
			f:Close()
			ZS.Unload()
			ZS.Start()
			expect(graphCalls).to.equal(1)
			finish()
			expect(file.Read(path(), "DATA") == bytes).to.beTrue()
		end),
		case("a file of the wrong size on disk is deleted and the write is reported as failed", function()
			cleanTestFiles()
			local p = "grymod/zonemap/" .. MAPNAME .. "_wrong.dat"
			local ok, err

			stub(file, "Size", function() return 3 end)
			ok, err = ORIGINAL.WriteFile(p, "0123456789")
			file.Size = undo[#undo].old -- put back at once: the check below needs the real one
			undo[#undo] = nil

			expect(ok).to.beFalse()
			expect(isstring(err)).to.beTrue()
			expect(file.Exists(p, "DATA")).to.beFalse()
		end),
		case("Reset deletes the file and the map in memory, makes it again, and tells everybody", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.RunNow()
			expect(disk[path()] ~= nil).to.beTrue()
			sent = {}
			ZS.Reset()
			expect(deleted[#deleted]).to.equal(path())
			expect(disk[path()]).to.beNil()
			expect(ZS.Bytes()).to.beNil()
			expect((ZS.State())).to.equal(3)
			expect(thinkHook() ~= nil).to.beTrue()

			local list = messages("gry_zonemap_state")
			expect(select(1, stateOf(list[#list]))).to.equal(3)
			expect(list[#list].target).to.equal("all")
			finish()
			expect((ZS.State())).to.equal(4)
			expect(disk[path()] ~= nil).to.beTrue()
		end),

		-- ----------------------------------------------------------------------------------------------- the net
		case("the state message: name, widths 3 / 24 / 24, to everybody, at each change from start to ready; then the data, once, to everybody", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.Start()
			finish()

			local list = messages("gry_zonemap_state")
			expect(#list >= 2).to.beTrue()

			for _, m in ipairs(list) do
				expect(#m.w).to.equal(3)
				expect(m.w[1][3]).to.equal(3)
				expect(m.w[2][3]).to.equal(24)
				expect(m.w[3][3]).to.equal(24)
				expect(m.target).to.equal("all")
			end

			local state, done, total = stateOf(list[1])
			expect(state).to.equal(3)
			expect(done).to.equal(0)
			expect(total).to.equal(10)
			expect(select(1, stateOf(list[#list]))).to.equal(4)

			local data = messages("gry_zonemap_data")
			expect(#data).to.equal(1)
			expect(data[1].target).to.equal("all")

			-- the state comes before the data, so a client knows what it is about to receive
			local order = {}

			for _, m in ipairs(sent) do
				order[#order + 1] = m.name
			end

			expect(order[#order]).to.equal("gry_zonemap_data")
			expect(order[#order - 1]).to.equal("gry_zonemap_state")
		end),
		case("the data goes in chunks of at most 30000 bytes: 70000 bytes make 3 messages (index 0..2 as the client and the design say, count, length, data), the bytes put back together are the string", function()
			useFakes()
			local big = {}

			for i = 1, 70000 do
				big[i] = string.char(i % 256)
			end

			big = table.concat(big)
			local target = fakePlayer(true)
			ZS.SendData(target, big)

			local list = messages("gry_zonemap_data")
			expect(#list).to.equal(3)

			local parts, lengths = {}, {}

			for i, m in ipairs(list) do
				expect(#m.w).to.equal(4)
				expect(m.w[1][1] .. m.w[1][3]).to.equal("uint16")
				expect(m.w[2][1] .. m.w[2][3]).to.equal("uint16")
				expect(m.w[3][1] .. m.w[3][3]).to.equal("uint16")
				expect(m.w[4][1]).to.equal("data")
				expect(m.w[1][2]).to.equal(i - 1)
				expect(m.w[2][2]).to.equal(3)
				expect(m.w[3][2]).to.equal(#m.w[4][2])
				expect(m.w[4][3]).to.equal(m.w[3][2])
				expect(m.target).to.equal(target)
				lengths[i] = m.w[3][2]
				parts[i] = m.w[4][2]
			end

			expect(table.concat(lengths, ",")).to.equal("30000,30000,10000")
			expect(table.concat(parts) == big).to.beTrue()
		end),
		case("the chunk boundaries: 30000 bytes are one message, 30001 are two, 1 byte is one", function()
			useFakes()

			for _, row in ipairs({{1, 1}, {30000, 1}, {30001, 2}, {60000, 2}, {60001, 3}}) do
				sent = {}
				ZS.SendData("all", string.rep("a", row[1]))
				expect(#messages("gry_zonemap_data")).to.equal(row[2])

				for _, m in ipairs(sent) do
					expect(m.w[3][2] <= 30000).to.beTrue()
					expect(m.target).to.equal("all")
				end
			end
		end),
		case("want from a client: the state to that client only, and the data when the map is ready; never a broadcast", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.RunNow()
			sent = {}

			local p = fakePlayer(false)
			expect(ZS.HandleWant(p, 100)).to.equal("ok")
			expect(#sent).to.equal(2)
			expect(sent[1].name).to.equal("gry_zonemap_state")
			expect(select(1, stateOf(sent[1]))).to.equal(4)
			expect(sent[2].name).to.equal("gry_zonemap_data")

			for _, m in ipairs(sent) do
				expect(m.target).to.equal(p)
			end

			local data = {}

			for i, m in ipairs(messages("gry_zonemap_data")) do
				data[i] = m.w[4][2]
			end

			expect(table.concat(data) == ZS.Bytes()).to.beTrue()
		end),
		case("want while the map is not ready: the state only (computing, off or no graph), no data", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()
			sent = {}

			local p = fakePlayer(false)
			ZS.HandleWant(p, 100)
			expect(#sent).to.equal(1)
			expect(select(1, stateOf(sent[1]))).to.equal(3)
			expect(sent[1].target).to.equal(p)

			cleanup()
			useFakes()
			setConvar("gry_zonemap", "0")
			ZS.Start()
			sent = {}
			ZS.HandleWant(p, 100)
			expect(#sent).to.equal(1)
			expect(select(1, stateOf(sent[1]))).to.equal(0)
		end),
		case("want: two a second per player at most, the third is ignored, the window opens again after a second, another player is not affected", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.RunNow()

			local a, b = fakePlayer(false), fakePlayer(false)
			sent = {}
			expect(ZS.HandleWant(a, 10)).to.equal("ok")
			expect(ZS.HandleWant(a, 10.4)).to.equal("ok")

			local before = #sent
			expect(ZS.HandleWant(a, 10.8)).to.equal("rate")
			expect(ZS.HandleWant(a, 10.9)).to.equal("rate")
			expect(#sent).to.equal(before)
			expect(ZS.HandleWant(b, 10.9)).to.equal("ok")
			expect(ZS.HandleWant(a, 11.1)).to.equal("ok")
		end),
		case("want from nobody (nil, NULL, a player who left) is ignored", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.RunNow()
			sent = {}
			expect(ZS.HandleWant(nil, 1)).to.equal("invalid")
			expect(ZS.HandleWant(NULL, 2)).to.equal("invalid")
			expect(ZS.HandleWant({IsValid = function() return false end}, 3)).to.equal("invalid")
			expect(#sent).to.equal(0)
		end),
		case("reset from an administrator deletes, cancels, starts again and tells everybody; the host of a listen server is one", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.RunNow()
			sent = {}
			expect(ZS.HandleReset(fakePlayer(true), 50)).to.equal("ok")
			expect(deleted[#deleted]).to.equal(path())
			expect((ZS.State())).to.equal(3)

			local list = messages("gry_zonemap_state")
			expect(#list >= 1).to.beTrue()
			expect(list[#list].target).to.equal("all")
			finish()
			expect((ZS.State())).to.equal(4)

			local host = player.GetAll()[1]

			if IsValid(host) then
				expect(ZS.HandleReset(host, RealTime())).to.equal("ok")
			end
		end),
		case("reset in the middle of a computation cancels it and starts from zero", function()
			useFakes({ceil = 200, wall = 300, tick = 0.00001}, graphOf(40, 0))
			setConvar("gry_zonemap_budget_ms", "0.5")
			ZS.Start()
			think()
			think()

			local _, done = ZS.State()
			expect(done > 0).to.beTrue()
			expect(ZS.HandleReset(fakePlayer(true), 50)).to.equal("ok")

			local state
			state, done = ZS.State()
			expect(state).to.equal(3)
			expect(done).to.equal(0)
			finish()
			expect((ZS.State())).to.equal(4)
		end),
		case("reset from a player who is not an administrator, from nobody or from the console: refused, silent, nothing deleted, nothing sent, nothing changed", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.RunNow()

			local bytes = ZS.Bytes()
			sent, deleted = {}, {}
			expect(ZS.HandleReset(fakePlayer(false), 10)).to.equal("denied")
			expect(ZS.HandleReset(nil, 20)).to.equal("denied")
			expect(ZS.HandleReset(NULL, 30)).to.equal("denied")
			expect(ZS.HandleReset({IsValid = function() return false end, IsAdmin = function() return true end}, 40)).to.equal("denied")
			expect(#sent).to.equal(0)
			expect(#deleted).to.equal(0)
			expect((ZS.State())).to.equal(4)
			expect(ZS.Bytes()).to.equal(bytes)
			expect(disk[path()]).to.equal(bytes)
			expect(thinkHook()).to.beNil()
		end),
		case("reset: one a second per player, a refused message counts too, another player is not affected", function()
			useFakes(ROOM, graphOf(10, 0))
			ZS.RunNow()

			local admin, other = fakePlayer(true), fakePlayer(true)
			expect(ZS.HandleReset(admin, 100)).to.equal("ok")
			finish()
			expect(ZS.HandleReset(admin, 100.5)).to.equal("rate")
			expect(ZS.HandleReset(other, 100.5)).to.equal("ok")
			finish()
			expect(ZS.HandleReset(admin, 101.1)).to.equal("ok")

			-- a player who is not an admin that spams is rate limited too (and costs nobody else)
			local player_ = fakePlayer(false)
			expect(ZS.HandleReset(player_, 200)).to.equal("denied")
			expect(ZS.HandleReset(player_, 200.1)).to.equal("rate")
		end),

		-- ----------------------------------------------------------------------------------------------- the real map
		case("on the real map of the game: RunNow gives state 4, a file the pure module decodes, boxes, and a file on disk", function()
			-- only the clock and the net are replaced; the trace, the graph, the files and the map are the real ones
			stubNet()
			stub(ZS, "OnSwitch", noop)
			stub(ZS, "OnSource", noop)

			for _, f in ipairs({"Trace", "Graph", "Clock", "ReadFile", "WriteFile", "DeleteFile", "BspSize", "MapName", "Now", "Log"}) do
				stub(ZS, f, ORIGINAL[f])
			end

			setConvar("gry_zonemap", "1")
			setConvar("gry_zonemap_budget_ms", "2")
			setConvar("gry_zonemap_max_nodes", "20000")
			setConvar("gry_zonemap_navmesh", "0")

			local graph = GryMod.AIN.Load(game.GetMap())

			if not graph then
				-- a map with no graph (not the case of the test game): the module says so
				ZS.Unload()
				ZS.Start()
				expect((ZS.State())).to.equal(1)

				return
			end

			local ground = 0

			for _, node in ipairs(graph.nodes) do
				if node.type == 2 then
					ground = ground + 1
				end
			end

			expect(ground > 0).to.beTrue()
			expect(ZS.RunNow(nil, true)).to.equal(4)

			local bytes = ZS.Bytes()
			local map, header = Z.Decode(bytes)
			expect(map ~= nil).to.beTrue()
			expect(#map.boxes > 0).to.beTrue()
			expect(header.nodeCount).to.equal(ground)
			expect(header.complete).to.beTrue()
			expect(header.sampleCount).to.equal(ground)

			local real = "grymod/zonemap/" .. Z.Key(game.GetMap(), file.Size("maps/" .. game.GetMap() .. ".bsp", "GAME")) .. ".dat"
			expect(file.Read(real, "DATA") == bytes).to.beTrue()
			expect(ZS.Stats().ground).to.equal(ground)
		end),
	}
}
