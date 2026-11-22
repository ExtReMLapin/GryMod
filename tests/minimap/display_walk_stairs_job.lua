-- The recorded stairs and ramps of the map walked up and down by the display walk tool (display_walk_tool.lua), as a lua_job in the CLIENT realm. Load before it, with
-- lua_exec_file: preload_coverage_job.lua, display_walk_tool.lua, and the fixture of the map turned into a global (DW_STAIRS = {...}: the file of the fixtures with its
-- first "return {" replaced by "DW_STAIRS = {"). A scratch cache is used and put back. Returns, for each recorded stretch, the walk in both modes and both directions.
local Z = GryMod.ZoneMapClient

job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)
DW.scratch()

local ok, res = pcall(DW.stairs, job, job.args and job.args.every, job.args and job.args.radius)

COV.finish()

if not ok then
	error(res)
end

if job.args and job.args.compact then
	return DW.lines(res)
end

return res
