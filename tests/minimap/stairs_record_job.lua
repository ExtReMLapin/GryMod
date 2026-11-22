-- MANUAL RECORDING TOOL (not a GLuaTest) for the stairs and ramps the owner shows. One call in the CLIENT realm with gmod-mcp (lua_exec_file this file, then run
--   REC.run("funkis_stairs_5"))
-- reads where the player stands and faces, what the ground and the ceiling are around him, follows the ground straight ahead every 12 units (down rays, stops at a wall, a drop
-- of more than 50 units, or after 840 units) and shoots the five up rays of Floors.CurrentAt at each place. It writes data/grymod_tmp/stairs_<name>.txt and returns a summary.
-- Then run dev_resources/save_stairs.py <name> (Bash): it appends the samples to tests/minimap/fixtures/<map>_stairs.lua, the position and the view to
-- docs/superpowers/plans/2026-11-22-stairs-test-positions.md (private) and commits the fixture. Options: REC.run(name, {length = 840, step = 12, dry = true}) (dry: no file).
-- Everything is read only: no player is moved, nothing of the game is changed.

REC = REC or {}

local function r2(n)
	return math.floor(n * 100) / 100
end

-- the five up rays of Floors.CurrentAt at a place: the highest ceiling that is not the sky (-99999 when none), 1 when the centre ray saw the sky or nothing, the height of the sky or 0
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

function REC.run(name, opts)
	opts = opts or {}

	local step = opts.step or 12
	local maxLength = opts.length or 840
	local ply = LocalPlayer()
	local pos, ang = ply:GetPos(), ply:EyeAngles()
	local dir = Angle(0, ang.y, 0):Forward()
	local map = game.GetMap()

	-- the ground in front, every 50 units (to see the slope), and the level the rule gives here
	local ahead = {}

	for d = 0, 400, 50 do
		local p = pos + dir * d
		local g = util.TraceLine({start = p + Vector(0, 0, 80), endpos = p - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY})

		ahead[#ahead + 1] = d .. ":" .. (g.Hit and math.floor(g.HitPos.z * 10) / 10 or "none")
	end

	local F = GryMod and GryMod.Minimap and GryMod.Minimap.Floors
	local level = F and F.PeekAt and F.PeekAt(pos.x, pos.y, pos.z)
	local ceiling = util.TraceLine({start = pos + Vector(0, 0, 72), endpos = pos + Vector(0, 0, 32768), mask = MASK_SOLID_BRUSHONLY})

	-- the ground followed straight ahead
	local x, y, z = pos.x, pos.y, pos.z
	local lines, stop = {}, "length"
	local zStart, zEnd

	for i = 0, math.floor(maxLength / step) do
		local c, o, s = shoot(x, y, z)

		zStart = zStart or z
		zEnd = z
		lines[#lines + 1] = string.format("{%.1f, %.1f, %.2f, %s, %d, %.2f}", x, y, z, c == -99999 and "-99999" or string.format("%.2f", c), o, s)

		local nx, ny = x + dir.x * step, y + dir.y * step
		local wall = util.TraceLine({start = Vector(x, y, z + 30), endpos = Vector(nx, ny, z + 30), mask = MASK_PLAYERSOLID_BRUSHONLY})

		if wall.Hit then
			stop = "wall"

			break
		end

		local g = util.TraceLine({start = Vector(nx, ny, z + 50), endpos = Vector(nx, ny, z - 70), mask = MASK_PLAYERSOLID_BRUSHONLY})

		if not g.Hit or g.StartSolid or math.abs(g.HitPos.z - z) > 50 then
			stop = "drop"

			break
		end

		x, y, z = nx, ny, g.HitPos.z
	end

	local ceilingText = ceiling.HitSky and "sky" or (ceiling.Hit and tostring(r2(ceiling.HitPos.z)) or "none")
	local summary = {
		name = name, map = map, bsp = file.Size("maps/" .. map .. ".bsp", "GAME"),
		pos = {r2(pos.x), r2(pos.y), r2(pos.z)}, angles = {r2(ang.p), r2(ang.y), r2(ang.r)},
		level = level and level.id or "none", ceiling = ceilingText, ceilingAbove = ceiling.Hit and not ceiling.HitSky and r2(ceiling.HitPos.z - pos.z) or nil,
		ahead = table.concat(ahead, " "), samples = #lines, zStart = r2(zStart), zEnd = r2(zEnd), length = (#lines - 1) * step, stop = stop, onGround = ply:IsOnGround()
	}

	if not opts.dry then
		file.CreateDir("grymod_tmp")

		local head = {
			"name=" .. name, "map=" .. map, "bsp=" .. tostring(summary.bsp),
			"pos=" .. table.concat(summary.pos, ","), "angles=" .. table.concat(summary.angles, ","),
			"level=" .. summary.level, "ceiling=" .. summary.ceiling, "ceilingAbove=" .. tostring(summary.ceilingAbove or ""),
			"ahead=" .. summary.ahead, "stop=" .. stop, "samples=" .. #lines, "zStart=" .. summary.zStart, "zEnd=" .. summary.zEnd, "length=" .. summary.length,
			"---"
		}

		file.Write("grymod_tmp/stairs_" .. name .. ".txt", table.concat(head, "\n") .. "\n" .. table.concat(lines, ",\n"))
	end

	return summary
end
