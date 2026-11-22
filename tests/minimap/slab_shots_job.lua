-- Pictures of slabs of the map for the level rule of the minimap (lua_job, CLIENT realm, 2026-11-22). Not a test: a measuring tool.
-- args.shots = {{name =, x =, y =, zlo =, zhi =, clip = {nx, ny, nz, d} (optional: one custom clip plane pushed around the capture, render.PushCustomClipPlane)}, ...},
-- args.size (512), args.ppm (3). Each shot is Capture.Render of the tile that holds (x, y), made inside a PostRender hook; the picture is written to
-- data/zz_levels_shots/<name>.dat (a 24-bit BMP: rename to .bmp; copy the folder out and delete it). Returns per shot: solid pixels (not void by Capture.IsVoid), and the number of
-- pixels that differ from the shot named in its `vs` field (if any).
local Capture = GryMod.Minimap.Capture
local res = args.size or 512
local ppm = args.ppm or 3
local shots = args.shots or {}

assert(Capture and Capture.Render, "the capture module is not loaded")

local function le32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function writeBMP(path, bytes, size)
	local rows = {}
	local byte, char = string.byte, string.char

	for row = size - 1, 0, -1 do
		local base = row * size * 4
		local px = {}

		for col = 0, size - 1 do
			local i = base + col * 4 + 1
			local b, g, r, a = byte(bytes, i, i + 3)

			if not args.raw and Capture.IsVoid(b, g, r, a) then
				b, g, r = 255, 0, 255 -- the void (Capture.IsVoid) in magenta
			end

			px[col + 1] = char(b, g, r)
		end

		rows[#rows + 1] = table.concat(px)
	end

	local body = table.concat(rows)
	local header = "BM" .. le32(54 + #body) .. le32(0) .. le32(54) .. le32(40) .. le32(size) .. le32(size) .. "\1\0\24\0" .. le32(0) .. le32(#body) .. le32(2835) .. le32(2835) .. le32(0) .. le32(0)

	file.CreateDir("zz_levels_shots")
	file.Write(path, header .. body)
end

local Cache = GryMod.Minimap.Cache
local T = Cache and Cache.TileUnits and Cache.TileUnits(res, ppm) or res / ppm / GryMod.RadarShared.METRES_PER_UNIT
local results, pictures = {}, {}
local index, finished = 1, false

hook.Add("PostRender", "gry_levels_shots", function()
	local shot = shots[index]

	if not shot then
		finished = true
		hook.Remove("PostRender", "gry_levels_shots")

		return
	end

	index = index + 1

	local tile = {level = "zz_shot", tx = math.floor(shot.x / T), ty = math.floor(shot.y / T), res = res, ppm = ppm}
	local level = {id = "zz_shot", zlo = shot.zlo, zhi = shot.zhi}
	local old

	if shot.clip then
		old = render.EnableClipping(true)
		render.PushCustomClipPlane(Vector(shot.clip[1], shot.clip[2], shot.clip[3]), shot.clip[4])

		if shot.clip2 then
			render.PushCustomClipPlane(Vector(shot.clip2[1], shot.clip2[2], shot.clip2[3]), shot.clip2[4])
		end
	end

	local ok, bytes, why = pcall(Capture.Render, tile, level)

	if shot.clip then
		if shot.clip2 then
			render.PopCustomClipPlane()
		end

		render.PopCustomClipPlane()
		render.EnableClipping(old or false)
	end

	local r = {name = shot.name, ok = ok, why = (not ok and tostring(bytes)) or why}

	if ok and type(bytes) == "string" then
		pictures[shot.name] = bytes

		local solid = 0

		for i = 1, #bytes, 4 do
			if not Capture.IsVoid(string.byte(bytes, i, i + 3)) then
				solid = solid + 1
			end
		end

		r.solid = solid -- not void by the capture's own rule (alpha 0 AND black is void)

		local other = shot.vs and pictures[shot.vs]

		if other then
			local diff = 0

			for i = 1, #bytes, 4 do
				if string.sub(bytes, i, i + 3) ~= string.sub(other, i, i + 3) then
					diff = diff + 1
				end
			end

			r.diff = diff
		end

		r.bytes = bytes
	end

	results[#results + 1] = r
end)

job:wait(function() return finished end, 60)
hook.Remove("PostRender", "gry_levels_shots")

for _, r in ipairs(results) do
	if r.bytes then
		writeBMP("zz_levels_shots/" .. r.name .. ".dat", r.bytes, res)
		r.bytes = nil
	end

	job:step()
end

return {tileUnits = T, results = results}
