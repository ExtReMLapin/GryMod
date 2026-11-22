-- Survey of the places of a map for the level rule of the minimap (lua_job, SERVER realm, 2026-11-22). Not a test: a measuring tool.
-- Around every ground node of the map's node graph (GryMod.AIN), the points of a global grid of 32 units within RADIUS of the node: the floor under each point
-- (one ray down from 48 over the node's floor), then the five up rays of Floors.CurrentAt (centre and four at 48, brush mask, from 72 over the feet: the highest
-- hit that is not the sky, and whether the centre ray saw the sky or nothing), and two rays at 36 over the feet to the +x and +y neighbours (is there a wall between).
-- Writes data/zz_levels_survey/<map>.txt, one line per point: x y feet ceiling(-99999 none) centreOpen centreHitZ(-99999 none) openX openY
-- (the folder is a test folder: copy the file out and delete it). args.radius (128), args.maxNodes (4000).
local map = game.GetMap()
local radius = (job.args and job.args.radius) or 128
local maxNodes = (job.args and job.args.maxNodes) or 4000
local GRID = 32
local graph = GryMod and GryMod.AIN and GryMod.AIN.Load(map)

if type(graph) ~= "table" or type(graph.nodes) ~= "table" then
	return {map = map, err = "no graph"}
end

local ground = {}

for _, n in ipairs(graph.nodes) do
	if n.type == 2 then
		ground[#ground + 1] = n
	end
end

local stride = math.max(1, math.floor(#ground / maxNodes))
local seen, lines = {}, {}
local MASK = MASK_SOLID_BRUSHONLY
local tr = {}
local p = {start = Vector(), endpos = Vector(), mask = MASK, output = tr}
local DX = {0, 48, -48, 0, 0}
local DY = {0, 0, 0, 48, -48}

local function trace(x1, y1, z1, x2, y2, z2)
	p.start.x, p.start.y, p.start.z = x1, y1, z1
	p.endpos.x, p.endpos.y, p.endpos.z = x2, y2, z2
	util.TraceLine(p)

	return tr
end

local cells = math.floor(radius / GRID)
local done = 0

for i = 1, #ground, stride do
	local n = ground[i]
	local t0 = trace(n.x, n.y, n.z + 32, n.x, n.y, n.z - 96)

	if t0.Hit and not t0.StartSolid and not t0.HitSky then
		local nf = t0.HitPos.z
		local gx0, gy0 = math.floor(n.x / GRID + 0.5), math.floor(n.y / GRID + 0.5)

		for ix = -cells, cells do
			for iy = -cells, cells do
				if ix * ix + iy * iy <= cells * cells then
					local x, y = (gx0 + ix) * GRID, (gy0 + iy) * GRID
					local t = trace(x, y, nf + 48, x, y, nf - 80)

					if t.Hit and not t.StartSolid and not t.HitSky then
						local f = t.HitPos.z
						local key = (gx0 + ix) .. "," .. (gy0 + iy) .. "," .. math.floor(f / 24 + 0.5)

						if not seen[key] and math.abs(f - nf) <= 64 then
							seen[key] = true

							local ceiling, centreOpen, centreHit = nil, 0, -99999

							for r = 1, 5 do
								local u = trace(x + DX[r], y + DY[r], f + 72, x + DX[r], y + DY[r], f + 32768)
								local z = u.HitPos.z

								if u.HitSky or not u.Hit then
									if r == 1 then
										centreOpen = 1

										if u.HitSky then
											centreHit = z
										end
									end
								else
									if r == 1 then
										centreHit = z
									end

									if u.StartSolid then
										z = f + 72 -- the ray started in a solid (a ceiling under 72): the ceiling is there
									end

									if not ceiling or z > ceiling then
										ceiling = z
									end
								end
							end

							local wx = trace(x, y, f + 36, x + GRID, y, f + 36)
							local openX = (wx.Hit or wx.StartSolid) and 0 or 1
							local wy = trace(x, y, f + 36, x, y + GRID, f + 36)
							local openY = (wy.Hit or wy.StartSolid) and 0 or 1
							lines[#lines + 1] = string.format("%d %d %.2f %.2f %d %.2f %d %d", x, y, f, ceiling or -99999, centreOpen, centreHit, openX, openY)
						end
					end
				end

				job:step()
			end
		end
	end

	done = done + 1

	if done % 50 == 0 then
		job:progress(i, #ground, #lines .. " points")
	end
end

file.CreateDir("zz_levels_survey")
file.Write("zz_levels_survey/" .. map .. ".txt", table.concat(lines, "\n"))

return {map = map, nodes = #ground, stride = stride, points = #lines}
