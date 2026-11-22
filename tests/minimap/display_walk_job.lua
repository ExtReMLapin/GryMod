-- One whole run of the display walk tool (display_walk_tool.lua, which must be loaded after preload_coverage_job.lua with lua_exec_file) as a lua_job in the CLIENT realm:
-- waits for the in/out map, begins (scratch cache "zz_dl_...", radar that asks nothing), waits for the preload to finish, then walks the route forward and backward in mode
-- "old" (the radar asks for the level it shows) and "new" (it asks for the level of the place). args.points: "nav" reads data/grymod_tmp/dl_centres_<map>.txt (written by the
-- server), else the ground nodes of the graph. args.modes: list of modes (default old, new). Puts everything back at the end.
local Z = GryMod.ZoneMapClient

job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)

local pts

if job.args and job.args.points == "nav" then
	pts = COV.readCentres("grymod_tmp/dl_centres_" .. string.lower(game.GetMap()) .. ".txt")
end

local begun = DW.begin({points = pts})
local G = GryMod.Minimap.Gen

if begun.error then
	COV.finish()

	return begun
end

job:sleep(2)
job:wait(function()
	local p = G.PreloadProgress()

	return p and p.total and p.total > 0 and G.Pending() == 0 and (p.done or 0) + (p.failed or 0) >= p.total
end, 2400)

local prog = G.PreloadProgress()
local res = {begun = begun, preload = {total = prog.total, failed = prog.failed, seconds = math.floor((SysTime() - COV.t0) * 10) / 10}}
local modes = (job.args and job.args.modes) or {"old", "new", "skip"}
local back = DW.reverse(COV.nav)

for _, mode in ipairs(modes) do
	res[mode .. "_fwd"] = DW.walk(COV.nav, mode, job)
	res[mode .. "_bwd"] = DW.walk(back, mode, job)
end

COV.finish()

if job.args and job.args.compact then
	return DW.lines(res)
end

return res
