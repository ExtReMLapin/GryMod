-- The in/out map made by the SERVER (design: docs/superpowers/specs/2026-11-22-zonemap-design.md). On the start of a map it looks for the
-- file of that exact map in data/grymod/zonemap and, when there is none, makes the map from the engine's node graph (GryMod.AIN): 13 rays at each ground node
-- (5 up, 8 around) say whether the place is under a ceiling and narrow (indoor) and how high the ceiling is (a class of the minimap's levels); the pure module
-- GryMod.ZoneMap (sh_zonemap.lua) turns the samples into boxes, writes and reads the file. The clients get the state and the file through four net messages:
--   gry_zonemap_state  (server -> client)  UInt(3) state, UInt(24) done, UInt(24) total. States: 0 off, 1 no graph, 2 waiting, 3 computing, 4 ready,
--                                          5 incomplete (made, but not from every node), 6 failed (the reason is in the server log). To everybody at each change
--                                          (while computing at most four times a second), to one client when it asks.
--   gry_zonemap_data   (server -> client)  UInt(16) index (0 .. count - 1), UInt(16) count, UInt(16) length, Data(length): the file in chunks of at most 30000
--                                          bytes. To everybody when the map becomes ready or incomplete, to one client when it asks and it is.
--   gry_zonemap_want   (client -> server)  no payload: "tell me the state and send me the map". Two a second per player at most.
--   gry_zonemap_reset  (client -> server)  no payload: an administrator (GryMod.MayConfigure; the host of a listen server and the single player are) deletes
--                                          the file and the map in memory and makes it again. One a second per player; a refusal is silent.
-- Settings: gry_zonemap (the switch, in the administrators' list of sh_server_options.lua), gry_zonemap_budget_ms (milliseconds of rays per server frame while it
-- computes, 0.5 to 10) and gry_zonemap_max_nodes (more ground nodes than this: the first ones only, and the result is flagged incomplete), both console only.
-- Cost: NO permanent hook. The computation adds a Think hook when it starts and removes it when it ends; a frame works until the budget in milliseconds is used
-- (the clock is read after each node, never inside the 13 rays of one node) and the tables of the rays are made once. One map is a few hundred bytes to a few KB.
-- Tests: everything the module needs from the engine is a field of GryMod.ZoneMapServer (the trace, the graph reader, the files, the clocks, the log), which the
-- tests replace and put back; RunNow makes the whole map at once with the code of the frames, and no hook.

util.AddNetworkString("gry_zonemap_state")
util.AddNetworkString("gry_zonemap_data")
util.AddNetworkString("gry_zonemap_want")
util.AddNetworkString("gry_zonemap_reset")

GryMod = GryMod or {}

local ZS = GryMod.ZoneMapServer or {}
GryMod.ZoneMapServer = ZS

local STATE = {OFF = 0, NO_GRAPH = 1, WAITING = 2, COMPUTING = 3, READY = 4, INCOMPLETE = 5, FAILED = 6}
ZS.STATE = STATE

local HOOK = "GryMod zonemap"
local DIR = "grymod/zonemap"

local CHUNK = 30000 -- bytes of a data message: a net message stays under 64 KB
local SEND_INTERVAL = 0.25 -- seconds between two state messages while computing
local WANT_LIMIT, WANT_WINDOW = 2, 1 -- messages per player per window
local RESET_LIMIT, RESET_WINDOW = 1, 1

-- the rays of a node: five up (the centre and four 48 units away along the world's X and Y), eight around
local UP_START = 72 -- over the node
local UP_LENGTH = 32768
local MAX_RISE = 512 -- a ceiling higher than this over the node is the open sky
local SIDE_HEIGHT = 36
local SIDE_LENGTH = 1050 -- 20 m, the cap of a distance
local NARROW_BELOW = 787.5 -- 15 m, the middle of the client's hysteresis (12 / 18 m)
local UP_DX = {0, 48, -48, 0, 0}
local UP_DY = {0, 0, 0, 48, -48}

local switch = CreateConVar("gry_zonemap", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The server makes an in/out map of the level from its node graph and sends it to the players (the automatic zoom of the radar uses it); 0 turns it off")
local budgetVar = CreateConVar("gry_zonemap_budget_ms", "2", FCVAR_ARCHIVE,
	"Milliseconds of rays per server frame while the in/out map is made (0.5 to 10)", 0.5, 10)
local maxNodesVar = CreateConVar("gry_zonemap_max_nodes", "20000", FCVAR_ARCHIVE,
	"A graph with more ground nodes than this makes the in/out map from the first ones only, flagged incomplete", 1)

-- the state of the module; it survives a hot reload of this file (a computation that runs goes on with the new code)
local st = ZS.st or {}
ZS.st = st

if st.state == nil then
	st.state, st.done, st.total = STATE.WAITING, 0, 0
	st.started = false
end

-- ---------------------------------------------------------------------------------------------------------
-- the fields the tests replace (the engine's calls, made through the table at each use)
-- ---------------------------------------------------------------------------------------------------------

ZS.Trace = util.TraceLine
ZS.Clock = SysTime
ZS.Now = RealTime
ZS.MapName = game.GetMap

function ZS.Graph(map)
	return GryMod.AIN.Load(map)
end

-- the size of maps/<map>.bsp, 0 when unknown (the file belongs to that exact map)
function ZS.BspSize(map)
	local size = file.Size("maps/" .. tostring(map) .. ".bsp", "GAME")

	if size and size > 0 then
		return size
	end

	return 0
end

function ZS.ReadFile(path)
	return file.Read(path, "DATA")
end

-- creates every folder of the path, one level at a time
local function ensureDir(path)
	local dir = ""

	for part in string.gmatch(string.match(path, "^(.*)/[^/]*$") or "", "[^/]+") do
		dir = dir == "" and part or (dir .. "/" .. part)

		if not file.IsDir(dir, "DATA") then
			file.CreateDir(dir)

			if not file.IsDir(dir, "DATA") then
				return false, "cannot create the folder " .. dir
			end
		end
	end

	return true
end

-- WriteFile(path, bytes) -> true | false, reason. ONE File:Write, then the size on disk is checked and a wrong file is deleted
function ZS.WriteFile(path, bytes)
	local ok, err = ensureDir(path)

	if not ok then
		return false, err
	end

	local f = file.Open(path, "wb", "DATA")

	if not f then
		return false, "cannot open " .. path .. " for writing"
	end

	local written, werr = pcall(f.Write, f, bytes)

	f:Close()

	if not written then
		file.Delete(path)

		return false, "write failed: " .. tostring(werr)
	end

	local size = file.Size(path, "DATA")

	if size ~= #bytes then
		file.Delete(path)

		return false, "wrote " .. tostring(size) .. " bytes, expected " .. #bytes
	end

	return true
end

function ZS.DeleteFile(path)
	file.Delete(path)
end

function ZS.Log(text)
	MsgN("[GryMod] zone map: " .. text)
end

-- ---------------------------------------------------------------------------------------------------------
-- the sample of one node: 13 rays
-- ---------------------------------------------------------------------------------------------------------

-- the tables of the rays, made once: only the two Vectors of a ray are written again
local upRays, sideRays = {}, {}
local scratch = {}

for i = 1, 5 do
	upRays[i] = {start = Vector(0, 0, 0), endpos = Vector(0, 0, 0), mask = MASK_SOLID_BRUSHONLY, output = {}}
end

for i = 1, 8 do
	local a = (i - 1) * math.pi / 4

	sideRays[i] = {
		dx = math.cos(a) * SIDE_LENGTH, dy = math.sin(a) * SIDE_LENGTH,
		params = {start = Vector(0, 0, 0), endpos = Vector(0, 0, 0), mask = MASK_SOLID_BRUSHONLY, output = {}}
	}
end

-- SampleNode(x, y, z) -> indoor, ceil. `indoor` is under a ceiling AND narrow; `ceil` is the class index of the ceiling (GryMod.ZoneMap.CeilIndex), 0 when open.
-- Under a ceiling: the HIGHEST of the five upward rays that hit the brushes (a side ray in the sky or in nothing is ignored; a centre ray in the sky or in
-- nothing means open and ends the sample, the rays around are not needed); a ceiling more than 512 over the node is open. Narrow: the median of the eight
-- distances (each capped at 20 m) is under 15 m, as the client's own probe.
function ZS.SampleNode(x, y, z)
	local trace = ZS.Trace
	local ceiling

	for i = 1, 5 do
		local params = upRays[i]
		local start, endpos = params.start, params.endpos
		local px, py = x + UP_DX[i], y + UP_DY[i]

		start.x, start.y, start.z = px, py, z + UP_START
		endpos.x, endpos.y, endpos.z = px, py, z + UP_LENGTH

		local tr = trace(params)
		local hit = tr.HitPos
		local hz = hit and hit.z

		if tr.HitSky or not tr.Hit or not hz or hz - hz ~= 0 then
			if i == 1 then
				return false, 0
			end
		elseif not ceiling or hz > ceiling then
			ceiling = hz
		end
	end

	if not ceiling or ceiling - z > MAX_RISE then
		return false, 0
	end

	-- eight distances, sorted by insertion in a table that is made once
	for i = 1, 8 do
		local ray = sideRays[i]
		local params = ray.params
		local start, endpos = params.start, params.endpos

		start.x, start.y, start.z = x, y, z + SIDE_HEIGHT
		endpos.x, endpos.y, endpos.z = x + ray.dx, y + ray.dy, z + SIDE_HEIGHT

		local tr = trace(params)
		local d = SIDE_LENGTH

		if tr.Hit then
			d = tr.Fraction * SIDE_LENGTH

			if d > SIDE_LENGTH then
				d = SIDE_LENGTH
			end
		end

		local j = i - 1

		while j >= 1 and scratch[j] > d do
			scratch[j + 1] = scratch[j]
			j = j - 1
		end

		scratch[j + 1] = d
	end

	local indoor = (scratch[4] + scratch[5]) / 2 < NARROW_BELOW

	return indoor, GryMod.ZoneMap.CeilIndex(ceiling - z)
end

-- ---------------------------------------------------------------------------------------------------------
-- network
-- ---------------------------------------------------------------------------------------------------------

local function clamp24(n)
	if n > 16777215 then
		return 16777215
	end

	return n
end

-- the target of a message: nil or "all" is everybody, else one player
local function dispatch(target)
	if target == nil or target == "all" then
		net.Broadcast()
	else
		net.Send(target)
	end
end

-- SendState(target): the present state, done and total
function ZS.SendState(target)
	net.Start("gry_zonemap_state")
	net.WriteUInt(st.state, 3)
	net.WriteUInt(clamp24(st.done), 24)
	net.WriteUInt(clamp24(st.total), 24)
	dispatch(target)
end

-- SendData(target, bytes): the file in chunks of at most 30000 bytes (the bytes in memory when none is given)
function ZS.SendData(target, bytes)
	bytes = bytes or st.bytes

	if not bytes then
		return
	end

	local count = math.max(1, math.ceil(#bytes / CHUNK))

	for i = 1, count do
		local piece = string.sub(bytes, (i - 1) * CHUNK + 1, i * CHUNK)

		net.Start("gry_zonemap_data")
		net.WriteUInt(i - 1, 16) -- 0 .. count - 1, as the client reads it
		net.WriteUInt(count, 16)
		net.WriteUInt(#piece, 16)
		net.WriteData(piece, #piece)
		dispatch(target)
	end
end

-- tells everybody; while computing at most four times a second unless `force`
local function announce(force)
	local now = ZS.Now()

	if not force and st.state == STATE.COMPUTING and st.sentAt and now - st.sentAt < SEND_INTERVAL then
		return
	end

	st.sentAt = now
	ZS.SendState(nil)
end

local function setState(state, done, total, silent)
	st.state, st.done, st.total = state, done or 0, total or 0

	if not silent then
		announce(true)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- the computation
-- ---------------------------------------------------------------------------------------------------------

local function cancelJob()
	st.job = nil
	hook.Remove("Think", HOOK)
end

local function failed(err)
	cancelJob()
	st.map, st.bytes = nil, nil
	ZS.Log("failed: " .. tostring(err))
	setState(STATE.FAILED, 0, 0)
end

local function pathFor(map, size)
	return DIR .. "/" .. GryMod.ZoneMap.Key(map, size) .. ".dat"
end

-- the budget of a frame in seconds
local function budgetSeconds()
	local ms = budgetVar:GetFloat()

	if ms ~= ms then
		ms = 2
	end

	return math.Clamp(ms, 0.5, 10) / 1000
end

-- one step: nodes until the budget (seconds) is used. The clock is read after each node, so a step ends at most one node past its budget.
-- A node of the graph that is not a ground node costs nothing; a node with a coordinate that is not a number is counted and skipped.
local function runStep(job, budget)
	local clock = ZS.Clock
	local t0 = clock()
	local deadline = t0 + budget
	local nodes, samples = job.nodes, job.samples
	local i, taken, total, n = job.i, job.taken, job.total, #job.samples
	local skipped = job.skipped

	while taken < total do
		local node = nodes[i]

		i = i + 1

		if not node then
			taken = total

			break
		end

		if node.type == 2 then
			local x, y, z = node.x, node.y, node.z

			taken = taken + 1

			if x - x == 0 and y - y == 0 and z - z == 0 then
				local indoor, ceil = ZS.SampleNode(x, y, z)

				n = n + 1
				samples[n] = {x = x, y = y, z = z, indoor = indoor, ceil = ceil}
			else
				skipped = skipped + 1
			end

			if clock() >= deadline then
				break
			end
		end
	end

	job.i, job.taken, job.skipped = i, taken, skipped
	job.steps = job.steps + 1
	job.seconds = job.seconds + (clock() - t0)
end

local function setReady(complete, samples)
	setState(complete and STATE.READY or STATE.INCOMPLETE, samples, samples)
	ZS.SendData(nil, st.bytes)
end

-- the end of a computation: build, encode, write, keep, tell
local function finishJob(job)
	local Z = GryMod.ZoneMap
	local map = Z.Build(job.samples)
	local complete = job.skipped == 0 and (map.skipped or 0) == 0 and not job.over
	local bytes = Z.Encode(map, {bspSize = st.bsp or 0, nodeCount = job.ground, complete = complete, overBudget = job.over})
	local ok, written, why = pcall(ZS.WriteFile, st.path, bytes)

	if not ok or not written then
		ZS.Log("could not write " .. tostring(st.path) .. ": " .. tostring(ok and why or written))
	end

	cancelJob()
	st.map, st.bytes = map, bytes
	st.stats = {
		nodes = job.nodeCount, ground = job.ground, taken = job.taken, skipped = job.skipped, samples = #job.samples,
		boxes = type(map.boxes) == "table" and #map.boxes or 0, steps = job.steps, seconds = job.seconds, bytes = #bytes
	}
	setReady(complete, #job.samples)
end

-- one frame of work (the Think hook, and RunNow with its own budget)
local function advance(budget)
	local job = st.job

	if not job then
		hook.Remove("Think", HOOK)

		return
	end

	local ok, err = pcall(runStep, job, budget)

	if not ok then
		failed(err)

		return
	end

	if job.taken >= job.total then
		ok, err = pcall(finishJob, job)

		if not ok then
			failed(err)
		end

		return
	end

	st.done = job.taken
	announce(false)
end

local function onThink()
	advance(budgetSeconds())
end

local function noGraph(reason)
	st.reason = reason
	ZS.Log("no usable node graph (" .. tostring(reason) .. "): no in/out map for this level")
	setState(STATE.NO_GRAPH, 0, 0)
end

-- the whole start: the switch, the file of this map, the graph, the job. `sync`: no hook (RunNow steps it itself)
local function startInner(sync)
	if not switch:GetBool() then
		setState(STATE.OFF, 0, 0)

		return
	end

	local Z = GryMod.ZoneMap
	local map = ZS.MapName()
	local size = ZS.BspSize(map) or 0
	local path = pathFor(map, size)

	st.path, st.bsp = path, size

	-- the file of this exact map: read with one call, valid when its bsp size is the one of the map (when both are known)
	local bytes = ZS.ReadFile(path)

	if bytes then
		local decoded, header = Z.Decode(bytes)

		if decoded and (size == 0 or not header.bspSize or header.bspSize == 0 or header.bspSize == size) then
			st.map, st.bytes = decoded, bytes
			setReady(header.complete and not header.overBudget, header.sampleCount or 0)

			return
		end
	end

	local graph, reason = ZS.Graph(map)

	if type(graph) ~= "table" or type(graph.nodes) ~= "table" then
		noGraph(reason or "no graph")

		return
	end

	local nodes = graph.nodes
	local ground = 0

	for i = 1, #nodes do
		if nodes[i].type == 2 then
			ground = ground + 1
		end
	end

	if ground == 0 then
		noGraph(#nodes == 0 and "empty graph" or "no ground node")

		return
	end

	local max = maxNodesVar:GetInt()

	if max < 1 then
		max = 1
	end

	local total = math.min(ground, max)

	st.job = {
		nodes = nodes, nodeCount = #nodes, ground = ground, total = total, over = ground > max,
		i = 1, taken = 0, skipped = 0, samples = {}, steps = 0, seconds = 0
	}

	setState(STATE.COMPUTING, 0, total)

	if not sync then
		hook.Add("Think", HOOK, onThink)
	end
end

local function start(sync)
	cancelJob()
	st.started = true
	st.map, st.bytes, st.reason, st.stats = nil, nil, nil, nil
	setState(STATE.WAITING, 0, 0, true) -- seen only by the graph reader: the real answer follows at once

	local ok, err = pcall(startInner, sync)

	if not ok then
		failed(err)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- the public functions
-- ---------------------------------------------------------------------------------------------------------

-- State() -> state, done, total, length of the file in memory
function ZS.State()
	return st.state, st.done, st.total, st.bytes and #st.bytes or 0
end

function ZS.Bytes()
	return st.bytes
end

function ZS.Map()
	return st.map
end

function ZS.Reason()
	return st.reason
end

-- Stats() -> {nodes, ground, taken, skipped, samples, boxes, steps, seconds, bytes} of the last computation of this map (empty when the file was read)
function ZS.Stats()
	return st.stats or {}
end

-- starts from the file or the graph: the map start, the switch going on, a reset
function ZS.Start()
	start(false)
end

-- stops the computation that runs (the hook goes away); the state stays as it is
function ZS.Cancel()
	cancelJob()
end

-- forgets everything about this map, as at the start of a map; the file is not touched
function ZS.Unload()
	cancelJob()
	st.map, st.bytes, st.reason, st.stats, st.path, st.bsp, st.sentAt = nil, nil, nil, nil, nil, nil, nil
	st.started = false
	st.state, st.done, st.total = STATE.WAITING, 0, 0
end

-- RunNow(budgetMs, fresh) -> state: the whole map at once, with the code of the frames and no hook. `budgetMs` is the length of each step (none: one step);
-- `fresh` deletes the file first. For the tests and the tools.
function ZS.RunNow(budgetMs, fresh)
	if fresh then
		cancelJob()

		local map = ZS.MapName()

		pcall(ZS.DeleteFile, pathFor(map, ZS.BspSize(map) or 0))
	end

	start(true)

	local budget = budgetMs and budgetMs / 1000 or math.huge

	while st.job do
		advance(budget)
	end

	return st.state
end

-- Reset(): the file and the map in memory are deleted, a computation that runs is cancelled, and it starts again
function ZS.Reset()
	cancelJob()
	st.map, st.bytes = nil, nil

	local map = ZS.MapName()

	pcall(ZS.DeleteFile, pathFor(map, ZS.BspSize(map) or 0))
	start(false)
end

-- the switch changed: on starts, off stops and forgets
function ZS.OnSwitch(old, new)
	local on, was = tobool(new), tobool(old)

	if on == was then
		return
	end

	if on then
		ZS.Start()
	else
		cancelJob()
		st.map, st.bytes = nil, nil
		setState(STATE.OFF, 0, 0)
	end
end

cvars.AddChangeCallback("gry_zonemap", function(_, old, new)
	ZS.OnSwitch(old, new)
end, HOOK)

-- ---------------------------------------------------------------------------------------------------------
-- the clients
-- ---------------------------------------------------------------------------------------------------------

local wantWindows = setmetatable({}, {__mode = "k"}) -- [player] = {start, count}
local resetWindows = setmetatable({}, {__mode = "k"})

local function allowed(windows, ply, now, limit, span)
	local w = windows[ply]

	if not w or now - w.start >= span then
		windows[ply] = {start = now, count = 1}

		return true
	end

	if w.count >= limit then
		return false
	end

	w.count = w.count + 1

	return true
end

-- HandleWant(ply, now) -> "ok" | "rate" | "invalid"
function ZS.HandleWant(ply, now)
	if not IsValid(ply) then
		return "invalid"
	end

	if not allowed(wantWindows, ply, now, WANT_LIMIT, WANT_WINDOW) then
		return "rate"
	end

	ZS.SendState(ply)

	if (st.state == STATE.READY or st.state == STATE.INCOMPLETE) and st.bytes then
		ZS.SendData(ply, st.bytes)
	end

	return "ok"
end

-- HandleReset(ply, now) -> "ok" | "rate" | "denied": the sender is a valid player, within the rate, and GryMod.MayConfigure accepts him
function ZS.HandleReset(ply, now)
	if not IsValid(ply) then
		return "denied"
	end

	if not allowed(resetWindows, ply, now, RESET_LIMIT, RESET_WINDOW) then
		return "rate"
	end

	if not GryMod.MayConfigure(ply) then
		return "denied"
	end

	ZS.Reset()

	return "ok"
end

net.Receive("gry_zonemap_want", function(_, ply)
	ZS.HandleWant(ply, RealTime())
end)

net.Receive("gry_zonemap_reset", function(_, ply)
	ZS.HandleReset(ply, RealTime())
end)

-- ---------------------------------------------------------------------------------------------------------
-- the start of a map: one shot (InitPostEntity), or a file that was loaded late (a hot reload in a running game)
-- ---------------------------------------------------------------------------------------------------------

hook.Add("InitPostEntity", HOOK, function()
	if not st.started then
		ZS.Start()
	end
end)

if not st.started and CurTime() > 1 then
	timer.Simple(0, function()
		if not st.started then
			ZS.Start()
		end
	end)
end
