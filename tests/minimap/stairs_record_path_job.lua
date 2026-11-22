-- MANUAL RECORDING TOOL (not a GLuaTest), the SERVER realm twin of stairs_record_job.lua, for a stairs or a ramp that is not straight in front of the player: it follows the navigation mesh
-- between two positions. With gmod-mcp (realm server): lua_exec_file this file, then
--   SREC.path("fork_ramp_1", Vector(x1, y1, z1), Vector(x2, y2, z2))   -- from the first position to the second one (both on the ground)
-- It finds the nearest navigation mesh area to each position, a breadth first path through the adjacent areas, samples one position every 12 units along the area centres (a down ray
-- gives the ground, the five up rays of Floors.CurrentAt give the ceiling), writes data/grymod_tmp/stairs_<name>.txt in the format dev_resources/save_stairs.py reads, and returns a summary.
-- Options: SREC.path(name, p1, p2, {angles = {pitch, yaw, roll} of the view at p1, step = 12, maxAreas = 120000}). Read only: nothing is moved, nothing is changed.

SREC = SREC or {}

local function r2(n)
	return math.floor(n * 100) / 100
end

local function shoot(x, y, z)
	local best, centreOpen, sky = nil, 0, 0
	local offs = {{0, 0}, {48, 0}, {-48, 0}, {0, 48}, {0, -48}}

	for i, o in ipairs(offs) do
		local tr = util.TraceLine({start = Vector(x + o[1], y + o[2], z + 72), endpos = Vector(x + o[1], y + o[2], z + 32768), mask = MASK_SOLID_BRUSHONLY})

		if tr.HitSky or not tr.Hit then
			if i == 1 then
				centreOpen = 1

				if tr.HitSky then
					sky = tr.HitPos.z
				end
			end
		elseif not best or tr.HitPos.z > best then
			best = tr.HitPos.z
		end
	end

	return best or -99999, centreOpen, sky
end

function SREC.path(name, p1, p2, opts)
	opts = opts or {}

	local step = opts.step or 12
	local areas = navmesh.GetAllNavAreas()

	if #areas == 0 then
		return {error = "this map has no navigation mesh: use REC.run (client) instead"}
	end

	local function nearest(p)
		local best, bd

		for _, a in ipairs(areas) do
			local d = a:GetCenter():DistToSqr(p)

			if not bd or d < bd then
				best, bd = a, d
			end
		end

		return best, math.sqrt(bd)
	end

	local a1, d1 = nearest(p1)
	local a2, d2 = nearest(p2)
	local prev, queue, head = {[a1:GetID()] = false}, {a1}, 1
	local found = false

	while head <= #queue and #queue < (opts.maxAreas or 120000) do
		local a = queue[head]

		head = head + 1

		if a:GetID() == a2:GetID() then
			found = true

			break
		end

		for _, n in ipairs(a:GetAdjacentAreas()) do
			if prev[n:GetID()] == nil then
				prev[n:GetID()] = a:GetID()
				queue[#queue + 1] = n
			end
		end
	end

	if not found then
		return {error = "no path through the navigation mesh between the two positions", explored = #queue, d1 = r2(d1), d2 = r2(d2)}
	end

	local path, id = {}, a2:GetID()

	while id do
		path[#path + 1] = navmesh.GetNavAreaByID(id)
		id = prev[id]
	end

	local route = {}

	for i = #path, 1, -1 do
		route[#route + 1] = path[i]:GetCenter()
	end

	local lines, opens, zStart, zEnd = {}, 0, nil, nil

	for i = 1, #route - 1 do
		local a, b = route[i], route[i + 1]
		local n = math.max(1, math.floor(a:Distance(b) / step))

		for k = 0, n - 1 do
			local t = k / n
			local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
			local g = util.TraceLine({start = Vector(x, y, math.max(a.z, b.z) + 60), endpos = Vector(x, y, math.min(a.z, b.z) - 200), mask = MASK_PLAYERSOLID_BRUSHONLY})

			if g.Hit and not g.StartSolid then
				local c, o, s = shoot(x, y, g.HitPos.z)

				if o == 1 then
					opens = opens + 1
				end

				zStart = zStart or g.HitPos.z
				zEnd = g.HitPos.z
				lines[#lines + 1] = string.format("{%.1f, %.1f, %.2f, %s, %d, %.2f}", x, y, g.HitPos.z, c == -99999 and "-99999" or string.format("%.2f", c), o, s)
			end
		end
	end

	local map = game.GetMap()
	local ang = opts.angles or {0, 0, 0}
	local c1 = shoot(p1.x, p1.y, p1.z)
	local head = {
		"name=" .. name, "map=" .. map, "bsp=" .. tostring(file.Size("maps/" .. map .. ".bsp", "GAME")),
		"pos=" .. r2(p1.x) .. "," .. r2(p1.y) .. "," .. r2(p1.z), "angles=" .. table.concat(ang, ","), "level=see the recording", "ceiling=" .. r2(c1),
		"ceilingAbove=" .. (c1 > -90000 and tostring(r2(c1 - p1.z)) or ""),
		"ahead=a path through the navigation mesh (" .. #path .. " areas) from " .. r2(p1.x) .. "," .. r2(p1.y) .. "," .. r2(p1.z) .. " to " .. r2(p2.x) .. "," .. r2(p2.y) .. "," .. r2(p2.z) .. "; " .. opens .. " of " .. #lines .. " positions have the open sky over them",
		"stop=navigation mesh path", "samples=" .. #lines, "zStart=" .. r2(zStart or p1.z), "zEnd=" .. r2(zEnd or p2.z), "length=" .. (#lines - 1) * step, "---"
	}

	file.CreateDir("grymod_tmp")
	file.Write("grymod_tmp/stairs_" .. name .. ".txt", table.concat(head, "\n") .. "\n" .. table.concat(lines, ",\n"))

	return {name = name, map = map, areas = #path, samples = #lines, zStart = r2(zStart or 0), zEnd = r2(zEnd or 0), openSamples = opens, d1 = r2(d1), d2 = r2(d2)}
end
