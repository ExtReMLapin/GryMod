-- MANUAL MEASUREMENT TOOL, the SERVER half of discovery_walk_job.lua (read its header): lua_job in the SERVER realm, async: true, started BEFORE the client's job. It waits for
-- data/grymod_tmp/dw_go.txt ("speed,maxUnits"), then moves the first player along the route the client wrote (data/grymod_tmp/dw_route.txt, "x,y,z,jump;..."), at `speed` units a
-- second, in noclip so that the feet follow the recorded ground, and writes data/grymod_tmp/dw_done.txt at the end. The player is put back where it was, with its movement type.

local ply = player.GetAll()[1]

if not IsValid(ply) then
	return {error = "no player"}
end

job:wait(function() return file.Exists("grymod_tmp/dw_go.txt", "DATA") and file.Exists("grymod_tmp/dw_route.txt", "DATA") end, 900)

local speed, maxUnits = string.match(file.Read("grymod_tmp/dw_go.txt", "DATA") or "", "([%d%.]+),([%d%.]+)")
speed, maxUnits = tonumber(speed) or 266, tonumber(maxUnits) or 40000

local route = {}

for x, y, z, jump in string.gmatch(file.Read("grymod_tmp/dw_route.txt", "DATA") or "", "(-?%d+),(-?%d+),(-?%d+),(%d)") do
	route[#route + 1] = {x = tonumber(x), y = tonumber(y), z = tonumber(z), jump = jump == "1"}
end

local home, moveType = ply:GetPos(), ply:GetMoveType()
local ok, err = pcall(function()
	ply:SetMoveType(MOVETYPE_NOCLIP)
	ply:SetPos(Vector(route[1].x, route[1].y, route[1].z))

	local i, travelled, along, lastT = 1, 0, 0, SysTime()

	job:sleep(1)

	while i < #route and travelled < maxUnits do
		local a, b = route[i], route[i + 1]

		if b.jump then
			i, along, lastT = i + 1, 0, SysTime()
			ply:SetPos(Vector(b.x, b.y, b.z))
		else
			local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
			local length = math.sqrt(dx * dx + dy * dy + dz * dz)

			-- the distance of the time since the last resume (SysTime: the server's FrameTime is the tick's, not the frame the job is resumed at), the leftover of a segment carried on
			local nowT = SysTime()
			local step = speed * math.min(nowT - lastT, 0.1)

			lastT = nowT

			along = along + step
			travelled = travelled + step

			while length > 0 and along >= length and i < #route do
				along = along - length
				i = i + 1
				a, b = route[i], route[i + 1]

				if not b or b.jump then
					break
				end

				dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
				length = math.sqrt(dx * dx + dy * dy + dz * dz)
			end

			if length > 0 and b and not b.jump then
				local t = math.min(along / length, 1)

				ply:SetPos(Vector(a.x + dx * t, a.y + dy * t, a.z + dz * t))
			end
		end

		ply:SetVelocity(-ply:GetVelocity())
		job:yield()
	end
end)

ply:SetMoveType(moveType)
ply:SetPos(home)
ply:SetVelocity(-ply:GetVelocity())
file.Write("grymod_tmp/dw_done.txt", "1")

if not ok then
	return {error = tostring(err)}
end

return {steps = #route, home = tostring(home)}
