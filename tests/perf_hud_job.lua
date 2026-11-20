-- HUD cost benchmark, to run as a gmod-mcp lua_job in the CLIENT realm (needs a loaded map):
--   lua_job {realm = "client", path = ".../tests/perf_hud_job.lua", timeout_s = 300}
-- Launch the game uncapped (instances_launch fps_max = 0) and leave the player standing in the same
-- place for every run, with the same weapon and ammo.
--
-- Result: fps for four configurations (median of the rounds), the Lua time spent in the HUD hooks per
-- frame, and the Lua memory they allocate per frame.

local FRAMES = args and args.frames or 1500
local ROUNDS = args and args.rounds or 4
local names = {"HUDBASECRY", "GRYHUD"} -- the HUD and the quick menu
local originals = {}

for _, n in ipairs(names) do
	originals[n] = hook.GetTable().HUDPaint[n]
	assert(originals[n], "hook " .. n .. " is not registered")
end

local function install(set)
	for _, n in ipairs(names) do
		if set[n] then
			hook.Add("HUDPaint", n, set[n] == true and originals[n] or set[n])
		else
			hook.Remove("HUDPaint", n)
		end
	end
end

local configs = {
	{name = "none", set = {}},
	{name = "hud only", set = {HUDBASECRY = true}},
	{name = "quick menu only", set = {GRYHUD = true}},
	{name = "both", set = {HUDBASECRY = true, GRYHUD = true}}
}

-- frames per second over FRAMES frames
local function fps()
	job:frames(5) -- settle
	local t0 = SysTime()

	for _ = 1, FRAMES do
		job:frames(1)
	end

	return FRAMES / (SysTime() - t0)
end

local samples = {}

for _, c in ipairs(configs) do
	samples[c.name] = {}
end

for round = 1, ROUNDS do
	-- rotate the order so that a slow drift does not favour one configuration
	for i = 0, #configs - 1 do
		local c = configs[(i + round - 1) % #configs + 1]
		install(c.set)
		table.insert(samples[c.name], fps())
		job:progress((round - 1) * #configs + i + 1, ROUNDS * #configs, c.name)
	end
end

local function median(t)
	table.sort(t)

	return t[math.ceil(#t / 2)]
end

local result = {fps = {}}

for _, c in ipairs(configs) do
	result.fps[c.name] = math.floor(median(samples[c.name]) + 0.5)
end

-- Lua time and allocations inside the two hooks, with the real set installed
local stats = {}
local wrappers = {}

for _, n in ipairs(names) do
	stats[n] = {t = 0, kb = 0, calls = 0}
	wrappers[n] = function(...)
		local st = stats[n]
		local k0 = collectgarbage("count")
		local t0 = SysTime()
		originals[n](...)
		st.t = st.t + (SysTime() - t0)
		local dk = collectgarbage("count") - k0
		st.kb = st.kb + (dk > 0 and dk or 0) -- a collection in the middle gives a negative delta
		st.calls = st.calls + 1
	end
end

install(wrappers)
collectgarbage("collect")
collectgarbage("stop") -- so that the memory only goes up while the hooks run
job:frames(2)
for _ = 1, 300 do job:frames(1) end
collectgarbage("restart")
install({HUDBASECRY = true, GRYHUD = true})

result.perFrame = {}

for _, n in ipairs(names) do
	local st = stats[n]
	result.perFrame[n] = {
		luaMicroseconds = math.floor(st.t / st.calls * 1e6 * 10 + 0.5) / 10,
		allocatedKB = math.floor(st.kb / st.calls * 100 + 0.5) / 100,
		calls = st.calls
	}
end

-- fps is noisy (about 5 %): the Lua time and the allocations above are the figures to compare
result.hudCostMsPerFrame = math.floor((1000 / result.fps["both"] - 1000 / result.fps["none"]) * 1000 + 0.5) / 1000

return result
