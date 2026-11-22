-- Server side of the preload coverage tool (lua_job, SERVER realm): writes the centres of the navigation mesh areas to data/grymod_tmp/<name>.txt, one "x,y,z" per line
-- (args.name, default "cov_centres_<map>"), for COV.readCentres(path) on the client. A map with no navigation mesh writes nothing. Returns the count.
local areas = navmesh and navmesh.GetAllNavAreas() or {}

if #areas == 0 and navmesh and navmesh.Load then
	pcall(navmesh.Load)
	areas = navmesh.GetAllNavAreas() or {}
end

if #areas == 0 then
	return {count = 0, note = "no navigation mesh"}
end

local lines = {}

for i = 1, #areas do
	local c = areas[i]:GetCenter()

	lines[#lines + 1] = string.format("%d,%d,%d", math.floor(c.x), math.floor(c.y), math.floor(c.z))

	if i % 2000 == 0 then
		job:step()
	end
end

local name = (job.args and job.args.name) or ("cov_centres_" .. game.GetMap())

file.CreateDir("grymod_tmp")
file.Write("grymod_tmp/" .. name .. ".txt", table.concat(lines, "\n"))

return {count = #lines, name = name}
