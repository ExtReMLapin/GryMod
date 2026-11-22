-- Where the time of the main HUD paint (hook GRYFLASHHUD) goes, frame by frame. Run as a gmod-mcp lua_job in the CLIENT
-- realm, uncapped (fps_max 0), the player alive, a map loaded:
--   lua_job {realm = "client", path = ".../tests/perf_hud_draw_job.lua", args = {frames = 600, label = "rest"}}
-- The scenario (rest, energy moving, damage, mode switches) is driven from the server realm by the caller.
--
-- Result per component (whole paint, the status panel's Flash.Draw, the radar panel's Flash.Draw, the rest): mean, p50, p95,
-- p99 and max in milliseconds over the frames, plus the allocated kilobytes a frame (a second pass with the collector
-- stopped) and the worst frames with their breakdown.

local FRAMES = args and args.frames or 600
local JAM = args and args.jam
local Flash = GryMod.Flash
local statusMovie = Flash.Load(GryMod.FlashHUD.MOVIE)

local original = hook.GetTable().HUDPaint.GRYFLASHHUD
assert(original, "the hook GRYFLASHHUD is not registered")

local realDraw = Flash.Draw
local tTotal, tStatus, tRadar, gcRan, kbFrame = {}, {}, {}, {}, {}
local sStatus, sRadar = 0, 0

Flash.Draw = function(clip, x, y, scale)
	local t0 = SysTime()
	local ok = realDraw(clip, x, y, scale)
	local dt = SysTime() - t0

	if clip.movie == statusMovie then
		sStatus = sStatus + dt
	else
		sRadar = sRadar + dt
	end

	return ok
end

local frame = 0

local function install()
	hook.Add("HUDPaint", "GRYFLASHHUD", function(...)
		frame = frame + 1

		if JAM and GryMod.DamageFx then
			GryMod.DamageFx.Jam(GryMod.DamageFx.State, 1, GryMod.DamageFx.Options())
		end

		sStatus, sRadar = 0, 0
		local k0 = collectgarbage("count")
		local t0 = SysTime()
		original(...)
		local dt = SysTime() - t0
		local k1 = collectgarbage("count")
		tTotal[frame], tStatus[frame], tRadar[frame] = dt, sStatus, sRadar
		gcRan[frame] = k1 < k0
		kbFrame[frame] = k1 - k0
	end)
end

local function stats(list, n)
	local copy = {}
	local sum = 0

	for i = 1, n do
		copy[i] = list[i] * 1000
		sum = sum + copy[i]
	end

	table.sort(copy)

	local function pct(p)
		return math.Round(copy[math.max(1, math.ceil(n * p))], 3)
	end

	return {mean = math.Round(sum / n, 3), p50 = pct(0.5), p95 = pct(0.95), p99 = pct(0.99), max = math.Round(copy[n], 3)}
end

local result = {label = args and args.label or "?"}

local function pass(name, stop)
	tTotal, tStatus, tRadar, gcRan, kbFrame = {}, {}, {}, {}, {}
	frame = 0
	collectgarbage("collect")

	if stop then
		collectgarbage("stop")
	end

	install()

	for _ = 1, FRAMES do
		job:frames(1)
	end

	hook.Add("HUDPaint", "GRYFLASHHUD", original)
	collectgarbage("restart")

	local n = frame
	local rest = {}

	for i = 1, n do
		rest[i] = math.max(0, tTotal[i] - tStatus[i] - tRadar[i])
	end

	local out = {frames = n, total = stats(tTotal, n), status = stats(tStatus, n), radar = stats(tRadar, n), rest = stats(rest, n)}

	if stop then
		local sum = 0

		for i = 1, n do
			sum = sum + kbFrame[i]
		end

		out.kbPerFrame = math.Round(sum / n, 2)
	else
		local order = {}

		for i = 1, n do
			order[i] = i
		end

		table.sort(order, function(a, b) return tTotal[a] > tTotal[b] end)

		local worst, gcFrames = {}, 0

		for i = 1, n do
			if gcRan[i] then
				gcFrames = gcFrames + 1
			end
		end

		for k = 1, 8 do
			local i = order[k]
			worst[k] = string.format("f%d total %.2f status %.2f radar %.2f rest %.2f gc=%s", i, tTotal[i] * 1000, tStatus[i] * 1000, tRadar[i] * 1000, (tTotal[i] - tStatus[i] - tRadar[i]) * 1000, tostring(gcRan[i]))
		end

		out.worst = worst
		out.framesWithGcStep = gcFrames
	end

	result[name] = out
end

local ok, err = pcall(function()
	job:frames(args and args.warm or 0)
	pass("gcOn", false)

	if not (args and args.quick) then
		pass("gcStopped", true)
	end
end)

Flash.Draw = realDraw
hook.Add("HUDPaint", "GRYFLASHHUD", original)
collectgarbage("restart")

if not ok then
	error(err)
end

return result
