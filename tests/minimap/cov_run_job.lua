-- One whole run of the preload coverage tool (preload_coverage_job.lua, which must be loaded first with lua_exec_file) on the current map, as a lua_job in the CLIENT
-- realm: waits for the in/out map, begins (scratch cache, baseline walk), waits for the preload to finish, measures again, puts everything back. args.points: "nav" to read
-- data/grymod_tmp/centres.txt (the server writes it), else the ground nodes of the graph. Returns the baseline, the result and the counts of the reasons.
local Z = GryMod.ZoneMapClient

job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)

local pts = (job.args and job.args.points == "nav") and COV.readCentres() or nil
local begun = COV.begin({points = pts})
local G = GryMod.Minimap.Gen

job:sleep(2)
job:wait(function()
	local p = G.PreloadProgress()

	return p and p.total and p.total > 0 and G.Pending() == 0 and (p.done or 0) + (p.failed or 0) >= p.total
end, 1500)

local r = COV.result()

r.examples = nil
COV.finish()

return {begun = begun, result = r}
