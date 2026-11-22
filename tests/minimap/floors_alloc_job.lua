-- Memory of GryMod.Minimap.Floors in the real engine (no stand-in): what Floors.Below and Floors.CurrentAt allocate. Run as a gmod-mcp lua_job in the
-- CLIENT realm, on a map, after the module is loaded:
--   lua_job {realm = "client", path = ".../tests/minimap/floors_alloc_job.lua"}
-- A GLuaTest case cannot measure this: the test runner's budget hook and LuaJIT's own trace compilation add memory of their own to collectgarbage("count"),
-- so each measure runs after a warm-up, with the garbage collector stopped, in one go (no yield inside).
-- Result: kilobytes for 1000 Below calls, for 1000 CurrentAt calls inside a shot's life (remembered level), and per CurrentAt call that shoots its five rays.
-- What the engine itself gives back at each ray (the result tables of util.TraceLine) stays in the third number.

local F = GryMod.Minimap.Floors

local function measure(fn, n)
	collectgarbage("collect")
	collectgarbage("stop")

	local before = collectgarbage("count")

	fn(n)

	local after = collectgarbage("count")

	collectgarbage("restart")

	return after - before
end

local anchor = {id = "f0c120", fz = 0, cls = 120, top = 120, z = 0, zlo = -56, zhi = 120}
local p = LocalPlayer():GetPos()

F.Reset()

local function below(n)
	for _ = 1, n do
		F.Below(anchor)
	end
end

local function remembered(n)
	for _ = 1, n do
		F.CurrentAt(p)
	end
end

local places = {}

for i = 1, 200 do
	places[i] = Vector(p.x + 60 * i, p.y, p.z)
end

local function shots(n)
	for i = 1, n do
		F.CurrentAt(places[i])
	end
end

-- warm-ups
below(2000)
F.CurrentAt(p)
remembered(2000)
shots(200)

local result = {
	below_1000_calls_KB = measure(below, 1000),
	currentAt_remembered_1000_calls_KB = measure(remembered, 1000),
	currentAt_per_shot_KB = measure(shots, 200) / 200
}

F.Reset()

return result
