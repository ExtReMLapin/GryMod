-- Cost of the Crysis-style HUD, to run as a gmod-mcp lua_job in the CLIENT realm
-- (needs a loaded map, the player alive and holding a weapon; launch the game uncapped, fps_max = 0):
--   lua_job {realm = "client", path = ".../tests/perf_flash_job.lua", timeout_s = 120}
-- The atlas materials must be reachable (see tests/flash_pixels_job.lua for the dev path override).
--
-- Result, for each style: the Lua time and the Lua memory allocated per frame inside the paint hook, and the fps.

local FRAMES = args and args.frames or 400

local styles = {
	{name = "crysis", hookName = "GRYFLASHHUD"}
}

local result = {}

for _, s in ipairs(styles) do
	GryMod.ApplyHUD()
	job:frames(20) -- the first frames create the clips and the materials

	local original = hook.GetTable().HUDPaint[s.hookName]
	assert(original, "the hook " .. s.hookName .. " is not registered")

	local t, kb, calls = 0, 0, 0

	hook.Add("HUDPaint", s.hookName, function(...)
		local k0 = collectgarbage("count")
		local t0 = SysTime()
		original(...)
		t = t + (SysTime() - t0)
		local dk = collectgarbage("count") - k0
		kb = kb + (dk > 0 and dk or 0)
		calls = calls + 1
	end)

	collectgarbage("collect")
	collectgarbage("stop")
	local t0 = SysTime()

	for _ = 1, FRAMES do
		job:frames(1)
	end

	local elapsed = SysTime() - t0
	collectgarbage("restart")
	hook.Add("HUDPaint", s.hookName, original)

	result[s.name] = {
		luaMicroseconds = math.floor(t / calls * 1e6 * 10 + 0.5) / 10,
		allocatedKB = math.floor(kb / calls * 100 + 0.5) / 100,
		fps = math.floor(FRAMES / elapsed + 0.5),
		calls = calls
	}
end

GryMod.ApplyHUD()

return result
