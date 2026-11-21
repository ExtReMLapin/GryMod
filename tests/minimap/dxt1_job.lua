-- Hot timing and quality of the minimap's DXT1 compressor (lua/grymod/client/minimap/dxt1.lua). The GLuaTest runner calls the cases under a debug hook,
-- which keeps LuaJIT from compiling, so the real speed is measured here. Run as a gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", path = ".../tests/minimap/dxt1_job.lua"}
-- Returns the best of several runs for 1024 x 1024 pictures (noise: every block takes the full path; smooth: a gradient; landscape: roads, roofs, water),
-- the cold time of the first call, and the PSNR / MAE of each.

local D = GryMod.Minimap.DXT1
local SIZE = 1024

local function build(f)
	local rows = {}

	for y = 0, SIZE - 1 do
		local row = {}

		for x = 0, SIZE - 1 do
			local r, g, b = f(x, y)
			row[x + 1] = string.char(b, g, r, 255)
		end

		rows[y + 1] = table.concat(row)

		if y % 64 == 63 then
			job:step()
		end
	end

	return table.concat(rows)
end

local state = 12345
local function rnd()
	state = (state * 1664525 + 1013904223) % 4294967296

	return math.floor(state / 65536) % 256
end

local pictures = {
	noise = build(function() return rnd(), rnd(), rnd() end),
	smooth = build(function(x, y)
		local v = (x * 0.2 + y * 0.1) % 256

		return v, (v * 0.5) % 256, 100
	end),
	landscape = build(function(x, y)
		local dx, dy = x % 128, y % 128

		if dx < 10 or dy < 10 or math.abs(x - y) < 6 then
			return 90, 90, 95
		end

		if dx >= 30 and dx < 90 and dy >= 30 and dy < 80 then
			return 150, 60, 50
		end

		if y > 600 and y < 640 + math.floor(math.sin(x / 90) * 20) then
			return 40, 80, 160
		end

		return 60 + (math.floor(x / 64) + math.floor(y / 64)) % 8 * 3, 124, 52
	end),
}

local result = {}

for _, name in ipairs({"noise", "smooth", "landscape"}) do
	local img = pictures[name]
	local runs = {}
	local data

	for i = 1, 6 do
		job:frames(1)

		local t0 = SysTime()
		data = D.Compress(img, SIZE, SIZE)
		runs[i] = (SysTime() - t0) * 1000
	end

	local best = math.huge

	for i = 2, #runs do
		best = math.min(best, runs[i])
	end

	local t0 = SysTime()
	local back = D.Decode(data, SIZE, SIZE)
	local decodeMs = (SysTime() - t0) * 1000
	local e = D.Error(img, back)

	result[name] = {firstMs = runs[1], hotMs = best, decodeMs = decodeMs, psnr = e.psnr, mae = e.mae, max = e.max, bytes = #data}
end

return result
