-- Tests of the minimap's DXT1 module (lua/grymod/client/minimap/dxt1.lua), GLuaTest format, client realm. The module is pure (strings in, strings
-- out): everything here runs for real, nothing is replaced, so nothing has to be restored.
--
-- Pixel convention of the module: a BGRA string, 4 bytes per pixel (blue, green, red, alpha), rows from top to bottom, left to right. A DXT1 string
-- is 8 bytes per 4x4 block, blocks in row-major order; a block is c0 (u16 LE), c1 (u16 LE), then 4 bytes of 2-bit indices, one byte per pixel
-- row, the pixel x = 0 in bits 0-1.

local function dxt()
	local D = GryMod and GryMod.Minimap and GryMod.Minimap.DXT1

	expect(D).to.exist()
	expect(D.Compress).to.beA("function")

	return D
end

-- One BGRA pixel.
local function px(r, g, b, a)
	return string.char(b, g, r, a or 255)
end

local function solid(w, h, r, g, b)
	return string.rep(px(r, g, b), w * h)
end

-- Image from a function f(x, y) -> r, g, b (rows are assembled with table.concat; only meant for tests).
local function image(w, h, f)
	local rows = {}

	for y = 0, h - 1 do
		local row = {}

		for x = 0, w - 1 do
			local r, g, b = f(x, y)
			row[x + 1] = string.char(b, g, r, 255)
		end

		rows[y + 1] = table.concat(row)
	end

	return table.concat(rows)
end

local function pixel(bgra, w, x, y)
	local i = (y * w + x) * 4 + 1
	local b, g, r = string.byte(bgra, i, i + 2)

	return r, g, b
end

local function hex(s)
	return (s:gsub(".", function(c)
		return string.format("%02X ", c:byte())
	end))
end

-- Deterministic pseudo-random numbers (the Numerical Recipes LCG, exact in a double), returns a function giving 0..255.
local function lcg(seed)
	local state = seed

	return function()
		state = (state * 1664525 + 1013904223) % 4294967296

		return math.floor(state / 65536) % 256
	end
end

local function noise(w, h, seed)
	local rnd = lcg(seed)

	return image(w, h, function()
		return rnd(), rnd(), rnd()
	end)
end

local function u16(s, i)
	local lo, hi = string.byte(s, i, i + 1)

	return lo + hi * 256
end

-- A cheap synthetic landscape with sharp edges: grass in a few shades, a grid of roads, a diagonal road, rectangular buildings and a river.
local function landscape(size)
	local grass = {}

	for k = 0, 7 do
		grass[k] = px(60 + k * 3, 120 + k * 4, 50 + k * 2)
	end

	local road, line, roof, wall, water = px(90, 90, 95), px(210, 200, 90), px(150, 60, 50), px(200, 190, 170), px(40, 80, 160)
	local rows = {}

	for y = 0, size - 1 do
		local row = {}

		for x = 0, size - 1 do
			local p = grass[(math.floor(x / 64) + math.floor(y / 64)) % 8]
			local dx, dy = x % 128, y % 128

			if dx < 10 or dy < 10 then
				p = road

				if dx == 4 or dy == 4 then
					p = line
				end
			end

			if math.abs(x - y) < 6 then
				p = road
			end

			if dx >= 30 and dx < 90 and dy >= 30 and dy < 80 then
				p = roof

				if dx < 33 or dy >= 77 then
					p = wall
				end
			end

			if y > 600 and y < 640 + math.floor(math.sin(x / 90) * 20) then
				p = water
			end

			row[x + 1] = p
		end

		rows[y + 1] = table.concat(row)
	end

	return table.concat(rows)
end

return {
	groupName = "GryMod minimap DXT1",
	cases = {
		-- Hand-computed blocks. Production change that makes them fail: a different quantisation, endpoint order, index mapping or byte order.
		{
			name = "a solid block: c0 == c1, all indices 0 (quantised (v*31+127)/255 and (v*63+127)/255, little-endian)",
			func = function()
				local D = dxt()
				-- (128, 64, 32): r5 = 16, g6 = 16, b5 = 4 -> 16<<11 | 16<<5 | 4 = 0x8204
				expect(hex(D.Compress(solid(4, 4, 128, 64, 32), 4, 4))).to.equal("04 82 04 82 00 00 00 00 ")
				-- (200, 100, 50): r5 = 24, g6 = 25, b5 = 6 -> 0xC326
				expect(hex(D.Compress(solid(4, 4, 200, 100, 50), 4, 4))).to.equal("26 C3 26 C3 00 00 00 00 ")
				-- pure red: 0xF800, and the green and blue channels at 0
				expect(hex(D.Compress(solid(4, 4, 255, 0, 0), 4, 4))).to.equal("00 F8 00 F8 00 00 00 00 ")
			end
		},
		{
			name = "a block of two colours (black and white): c0 = 0xFFFF, c1 = 0x0000, index 0 for white and 1 for black, pixel x = 0 in bits 0-1",
			func = function()
				local D = dxt()
				local W, K = px(255, 255, 255), px(0, 0, 0)
				local rows = {
					W .. K .. W .. K, -- indices 0 1 0 1 -> 0 | 1<<2 | 0 | 1<<6 = 0x44
					W .. W .. W .. W, -- 0x00
					K .. K .. K .. K, -- 1 1 1 1 -> 0x55
					K .. W .. W .. W, -- 1 0 0 0 -> 0x01 (the first pixel is the lowest bits)
				}

				expect(hex(D.Compress(table.concat(rows), 4, 4))).to.equal("FF FF 00 00 44 00 55 01 ")
			end
		},
		{
			name = "a simple gradient block: the four grey levels 0, 85, 170, 255 take the indices 1, 3, 2, 0",
			func = function()
				local D = dxt()
				local row = px(0, 0, 0) .. px(85, 85, 85) .. px(170, 170, 170) .. px(255, 255, 255)
				-- 1 | 3<<2 | 2<<4 | 0<<6 = 1 + 12 + 32 = 0x2D on each of the four rows
				expect(hex(D.Compress(string.rep(row, 4), 4, 4))).to.equal("FF FF 00 00 2D 2D 2D 2D ")
			end
		},
		{
			name = "a block that is not solid but collapses to one 565 colour: still c0 == c1 and indices 0 (never the 3-colour mode)",
			func = function()
				local D = dxt()
				-- 128 and 129 give the same 5 and 6 bit values: r5 = 16, g6 = 32, b5 = 16 -> 0x8410
				local a, b = px(128, 128, 128), px(129, 129, 129)
				local rows = {a .. b .. a .. b, b .. b .. a .. a, a .. a .. a .. b, b .. a .. b .. a}

				expect(hex(D.Compress(table.concat(rows), 4, 4))).to.equal("10 84 10 84 00 00 00 00 ")
			end
		},
		{
			name = "alpha is ignored: the same colours with another alpha give the same bytes",
			func = function()
				local D = dxt()
				local a = image(4, 4, function(x, y) return x * 60, y * 60, 100 end)
				local b = a:gsub("(...).", "%1\7")

				expect(#b).to.equal(#a)
				expect(D.Compress(b, 4, 4)).to.equal(D.Compress(a, 4, 4))
			end
		},

		-- Orientation.
		{
			name = "orientation: a red 4x4 corner at the top left is the first block, the next block (offset 8) is blue",
			func = function()
				local D = dxt()
				local img = image(8, 8, function(x, y)
					if x < 4 and y < 4 then
						return 255, 0, 0
					end

					return 0, 0, 255
				end)
				local c = D.Compress(img, 8, 8)

				expect(#c).to.equal(32)

				local d = D.Decode(c, 8, 8)

				expect(#d).to.equal(8 * 8 * 4)

				local r, g, b = pixel(d, 8, 0, 0)
				expect(r).to.equal(255)
				expect(g).to.equal(0)
				expect(b).to.equal(0)

				r, g, b = pixel(d, 8, 3, 3)
				expect(r).to.equal(255)
				expect(b).to.equal(0)

				-- the second block (offset 8) is the one to the right: blue
				r, g, b = pixel(d, 8, 4, 0)
				expect(r).to.equal(0)
				expect(g).to.equal(0)
				expect(b).to.equal(255)

				-- blocks are row-major: the third block (offset 16) is the one below the first one, blue as well
				r, g, b = pixel(d, 8, 0, 4)
				expect(b).to.equal(255)
				expect(r).to.equal(0)

				-- the raw bytes: block 0 is c0 = c1 = 0xF800 (red), block 1 is c0 = c1 = 0x001F (blue)
				expect(hex(c:sub(1, 8))).to.equal("00 F8 00 F8 00 00 00 00 ")
				expect(hex(c:sub(9, 16))).to.equal("1F 00 1F 00 00 00 00 00 ")
			end
		},
		{
			name = "orientation inside a block: one white pixel at (x = 2, y = 1) on black comes back at (2, 1), not mirrored or transposed",
			func = function()
				local D = dxt()
				local img = image(4, 4, function(x, y)
					if x == 2 and y == 1 then
						return 255, 255, 255
					end

					return 0, 0, 0
				end)
				local d = D.Decode(D.Compress(img, 4, 4), 4, 4)

				for y = 0, 3 do
					for x = 0, 3 do
						local r, g, b = pixel(d, 4, x, y)
						local want = (x == 2 and y == 1) and 255 or 0

						expect(r).to.equal(want)
						expect(g).to.equal(want)
						expect(b).to.equal(want)
					end
				end
			end
		},
		{
			name = "Decode reads the bytes by hand: c0 = 0xFFFF, c1 = 0, indices 0 / 1 / 2 / 3 by columns (white, black, two thirds, one third)",
			func = function()
				local D = dxt()
				local blk = string.char(0xFF, 0xFF, 0x00, 0x00) .. string.rep(string.char(0 + 1 * 4 + 2 * 16 + 3 * 64), 4)
				local d = D.Decode(blk, 4, 4)
				local r0 = pixel(d, 4, 0, 0)
				local r1 = pixel(d, 4, 1, 0)
				local r2 = pixel(d, 4, 2, 0)
				local r3 = pixel(d, 4, 3, 0)

				expect(r0).to.equal(255)
				expect(r1).to.equal(0)
				-- (2 * 255 + 0) / 3 = 170 and (255 + 2 * 0) / 3 = 85, integer division
				expect(r2).to.equal(170)
				expect(r3).to.equal(85)
				expect(string.byte(d, 4)).to.equal(255) -- alpha
			end
		},
		{
			name = "Decode rebuilds 8 bits from 565 by bit replication: 0x001F -> blue 255, 0x07E0 -> green 255, 0x0010 -> blue 132",
			func = function()
				local D = dxt()
				local function one(c)
					local blk = string.char(c % 256, math.floor(c / 256), c % 256, math.floor(c / 256), 0, 0, 0, 0)
					return pixel(D.Decode(blk, 4, 4), 4, 0, 0)
				end
				local r, g, b = one(0x001F)

				expect(r).to.equal(0)
				expect(g).to.equal(0)
				expect(b).to.equal(255)

				r, g, b = one(0x07E0)
				expect(g).to.equal(255)
				expect(b).to.equal(0)

				r, g, b = one(0x0010)
				expect(b).to.equal(132) -- (16 << 3) | (16 >> 2)

				r, g, b = one(0x8000)
				expect(r).to.equal(132)

				r, g, b = one(0x0200)
				expect(g).to.equal(65) -- g6 = 16: (16 << 2) | (16 >> 4)
			end
		},

		-- Round trips.
		{
			name = "round trip: black and white images come back exactly",
			func = function()
				local D = dxt()

				for _, v in ipairs({0, 255}) do
					local img = solid(32, 16, v, v, v)
					local back = D.Decode(D.Compress(img, 32, 16), 32, 16)

					expect(back == img).to.beTrue()
				end
			end
		},
		{
			name = "round trip: a flat colour stays within the 565 quantisation error",
			func = function()
				local D = dxt()
				local img = solid(64, 64, 128, 64, 32)
				local e = D.Error(img, D.Decode(D.Compress(img, 64, 64), 64, 64))

				expect(e.max).to.beLessThan(5)
				expect(e.mae).to.beLessThan(3)
				expect(e.psnr).to.beGreaterThan(38)
			end
		},
		{
			name = "round trip: horizontal and vertical gradients, PSNR above 35 dB",
			func = function()
				local D = dxt()
				local h = image(256, 64, function(x) return x, x, x end)
				local v = image(64, 256, function(_, y) return y, 255 - y, 128 end)

				local eh = D.Error(h, D.Decode(D.Compress(h, 256, 64), 256, 64))
				local ev = D.Error(v, D.Decode(D.Compress(v, 64, 256), 64, 256))

				expect(eh.psnr).to.beGreaterThan(35)
				expect(eh.mae).to.beLessThan(3)
				expect(ev.psnr).to.beGreaterThan(35)
				expect(ev.mae).to.beLessThan(3)
			end
		},
		{
			name = "round trip: a 4 px checkerboard aligned on the blocks (every block solid), PSNR above 38 dB",
			func = function()
				local D = dxt()
				local img = image(64, 64, function(x, y)
					if (math.floor(x / 4) + math.floor(y / 4)) % 2 == 0 then
						return 200, 50, 50
					end

					return 30, 150, 220
				end)
				local e = D.Error(img, D.Decode(D.Compress(img, 64, 64), 64, 64))

				expect(e.psnr).to.beGreaterThan(38)
			end
		},
		{
			name = "round trip: a 1 px checkerboard of two colours that vary against each other (red high, green low: the axis must be flipped), PSNR above 40 dB",
			func = function()
				local D = dxt()
				local img = image(64, 64, function(x, y)
					if (x + y) % 2 == 0 then
						return 200, 50, 50
					end

					return 30, 150, 220
				end)
				local e = D.Error(img, D.Decode(D.Compress(img, 64, 64), 64, 64))

				expect(e.psnr).to.beGreaterThan(40)

				-- the same two colours the other way round (both channels rising together) give the same quality: the flip makes the orientation irrelevant
				local diag = image(64, 64, function(x, y)
					if (x + y) % 2 == 0 then
						return 200, 150, 220
					end

					return 30, 50, 50
				end)
				local ed = D.Error(diag, D.Decode(D.Compress(diag, 64, 64), 64, 64))

				expect(ed.psnr).to.beGreaterThan(40)
			end
		},
		{
			name = "round trip: uniform noise (the worst case for a 4 colour block) is still closer to the original than a flat mid-grey",
			func = function()
				local D = dxt()
				local img = noise(64, 64, 12345)
				local e = D.Error(img, D.Decode(D.Compress(img, 64, 64), 64, 64))
				local grey = D.Error(img, solid(64, 64, 128, 128, 128))

				expect(e.psnr).to.beGreaterThan(grey.psnr + 1)
				expect(e.mae).to.beLessThan(grey.mae)
			end
		},
		{
			name = "round trip of a non-square image keeps the geometry (width and height not swapped)",
			func = function()
				local D = dxt()
				local img = image(32, 8, function(x, y) return x * 4, y * 8, 77 end)
				local c = D.Compress(img, 32, 8)

				expect(#c).to.equal((32 / 4) * (8 / 4) * 8)

				local back = D.Decode(c, 32, 8)

				expect(#back).to.equal(#img)
				expect(D.Error(img, back).psnr).to.beGreaterThan(33)
			end
		},

		-- Structure of the output.
		{
			name = "every block of a noisy image has c0 >= c1, and c0 == c1 comes with indices 0 (never the 3-colour mode)",
			func = function()
				local D = dxt()
				local images = {noise(128, 64, 777), image(128, 64, function(x, y)
					-- small variations: many blocks collapse to one 565 colour
					local v = 128 + ((x * 7 + y * 13) % 3)
					return v, v, v
				end)}

				for n, img in ipairs(images) do
					local c = D.Compress(img, 128, 64)

					expect(#c).to.equal(32 * 16 * 8)

					local equal = 0

					for i = 1, #c, 8 do
						local c0, c1 = u16(c, i), u16(c, i + 2)

						expect(c0 >= c1).to.beTrue()

						if c0 == c1 then
							equal = equal + 1
							expect(string.byte(c, i + 4)).to.equal(0)
							expect(string.byte(c, i + 5)).to.equal(0)
							expect(string.byte(c, i + 6)).to.equal(0)
							expect(string.byte(c, i + 7)).to.equal(0)
						end
					end

					if n == 2 then
						expect(equal).to.beGreaterThan(0)
					end
				end
			end
		},
		{
			name = "indices only use the four-colour mode palette order: a block whose pixels are the two end points has only indices 0 and 1",
			func = function()
				local D = dxt()
				local rnd = lcg(99)
				local rows = {}

				for y = 1, 4 do
					local t = {}

					for x = 1, 4 do
						t[x] = (rnd() % 2 == 0) and px(250, 10, 120) or px(10, 240, 30)
					end

					rows[y] = table.concat(t)
				end

				local c = D.Compress(table.concat(rows), 4, 4)

				for i = 5, 8 do
					local byte = string.byte(c, i)

					for k = 0, 3 do
						local idx = bit.band(bit.rshift(byte, 2 * k), 3)

						expect(idx == 0 or idx == 1).to.beTrue()
					end
				end
			end
		},

		-- CompressRows
		{
			name = "CompressRows: consecutive chunks (sizes 1, 7, 32 and the rest) concatenated are byte for byte Compress",
			func = function()
				local D = dxt()
				local w, h = 128, 256 -- 64 block rows
				local img = noise(w, h, 4242)
				local whole = D.Compress(img, w, h)
				local rows = h / 4

				expect(#whole).to.equal((w / 4) * rows * 8)

				for _, size in ipairs({1, 7, 32, 64, 13}) do
					local parts, first = {}, 0

					while first < rows do
						local last = math.min(first + size - 1, rows - 1)
						local s, err = D.CompressRows(img, w, h, first, last)

						expect(err).to.beNil()
						expect(#s).to.equal((last - first + 1) * (w / 4) * 8)
						parts[#parts + 1] = s
						first = last + 1
					end

					expect(table.concat(parts) == whole).to.beTrue()
				end
			end
		},
		{
			name = "CompressRows: a chunk is the right slice of the picture (the last block row, alone)",
			func = function()
				local D = dxt()
				local img = image(16, 16, function(x, y)
					if y >= 12 then
						return 255, 255, 255
					end

					return 0, 0, 0
				end)
				local last = D.CompressRows(img, 16, 16, 3, 3)

				expect(#last).to.equal(4 * 8)
								local first = D.CompressRows(img, 16, 16, 0, 0)

				expect(hex(first:sub(1, 8))).to.equal("00 00 00 00 00 00 00 00 ")
				-- an all-white block row: c0 = c1 = 0xFFFF, indices 0
				expect(hex(last:sub(1, 8))).to.equal("FF FF FF FF 00 00 00 00 ")
			end
		},
		{
			name = "CompressRows refuses bad bounds with nil and a reason (first > last, outside the picture, not integers)",
			func = function()
				local D = dxt()
				local img = solid(16, 16, 1, 2, 3)

				for _, bounds in ipairs({{2, 1}, {-1, 0}, {0, 4}, {4, 4}, {0.5, 1}, {0, 1.5}}) do
					local s, err = D.CompressRows(img, 16, 16, bounds[1], bounds[2])

					expect(s).to.beNil()
					expect(err).to.beA("string")
				end

				local s, err = D.CompressRows(img, 16, 16, "0", 1)

				expect(s).to.beNil()
				expect(err).to.beA("string")

				s, err = D.CompressRows(img, 16, 16, nil, nil)
				expect(s).to.beNil()
				expect(err).to.beA("string")

				-- the picture itself is validated as well
				s, err = D.CompressRows(img, 15, 16, 0, 0)
				expect(s).to.beNil()
				expect(err).to.beA("string")
			end
		},

		-- Refusals
		{
			name = "refusals: sizes that are not multiples of 4, a wrong string length and wrong types give nil and a reason, no error",
			func = function()
				local D = dxt()
				local img = solid(8, 8, 1, 2, 3)
				local bad = {
					{img, 7, 8},
					{img, 8, 6},
					{img, 0, 8},
					{img, 8, 0},
					{img, -4, -16},
					{img, 8.5, 8},
					{img, 8, 8.5},
					{img:sub(1, -2), 8, 8},
					{img .. "x", 8, 8},
					{img, 4, 8}, -- the string is too long for 4x8
					{"", 4, 4},
					{nil, 8, 8},
					{12, 8, 8},
					{{}, 8, 8},
					{img, "8", 8},
					{img, 8, nil},
					{img, math.huge, 8},
					{img, 0 / 0, 8},
				}

				for i, args in ipairs(bad) do
					local ok, s, err = pcall(D.Compress, args[1], args[2], args[3])

					expect(ok).to.beTrue()
					expect(s).to.beNil()
					expect(err).to.beA("string")
				end

				-- Decode refuses as well
				for _, args in ipairs({{string.rep("\0", 8), 7, 4}, {string.rep("\0", 7), 4, 4}, {nil, 4, 4}, {"x", 4, 4}, {string.rep("\0", 8), "4", 4}}) do
					local ok, s, err = pcall(D.Decode, args[1], args[2], args[3])

					expect(ok).to.beTrue()
					expect(s).to.beNil()
					expect(err).to.beA("string")
				end
			end
		},

		-- Error
		{
			name = "Error: two identical images give mae 0, max 0 and psnr 99 (the documented value for a zero error)",
			func = function()
				local D = dxt()
				local img = noise(16, 16, 5)
				local e = D.Error(img, img)

				expect(e.mae).to.equal(0)
				expect(e.max).to.equal(0)
				expect(e.psnr).to.equal(99)
			end
		},
		{
			name = "Error: a known difference (3, 0, 4 on one pixel of two, alpha ignored) gives the hand-computed mae, max and psnr",
			func = function()
				local D = dxt()
				local a = px(10, 20, 30, 255) .. px(100, 100, 100, 255)
				local b = px(13, 20, 26, 0) .. px(100, 100, 100, 17)
				local e = D.Error(a, b)
				-- sum of |d| = 7 over 6 channels; sum of d^2 = 25 over 6 channels
				expect(e.mae).to.aboutEqual(7 / 6, 1e-9)
				expect(e.max).to.equal(4)
				expect(e.psnr).to.aboutEqual(10 * math.log10(255 * 255 / (25 / 6)), 1e-9)

				-- symmetric
				local f = D.Error(b, a)

				expect(f.mae).to.aboutEqual(e.mae, 1e-12)
				expect(f.psnr).to.aboutEqual(e.psnr, 1e-12)
			end
		},
		{
			name = "Error: the largest difference is found whatever its position (first, middle, last pixel and last channel)",
			func = function()
				local D = dxt()
				local n = 37 -- odd on purpose: not a multiple of the internal step
				local base = string.rep(px(50, 50, 50), n)

				for _, at in ipairs({1, 18, 37}) do
					local other = base:sub(1, (at - 1) * 4) .. px(50, 50, 200) .. base:sub(at * 4 + 1)

					expect(#other).to.equal(#base)
					expect(D.Error(base, other).max).to.equal(150)
				end
			end
		},
		{
			name = "Error: different lengths, empty strings and wrong types give nil and a reason",
			func = function()
				local D = dxt()
				local a = solid(4, 4, 1, 1, 1)

				for _, args in ipairs({{a, a .. px(0, 0, 0)}, {a, ""}, {"", ""}, {a, nil}, {nil, a}, {1, 2}, {a, "xyz"}, {"xyz", "xyz"}}) do
					local ok, e, err = pcall(D.Error, args[1], args[2])

					expect(ok).to.beTrue()
					expect(e).to.beNil()
					expect(err).to.beA("string")
				end
			end
		},

		-- Performance and realistic content
		{
			name = "performance: 1024x1024 compresses in under 150 ms even from cold (a coarse guard against a regression; the hot figure is measured by tests/minimap/dxt1_job.lua)",
			func = function()
				local D = dxt()
				local img = noise(256, 256, 1)
				-- 1024x1024 = 16 copies of the 256x256 noise, cheaper to build than a fresh noise
				local rows = {}

				for y = 0, 255 do
					rows[y + 1] = string.rep(img:sub(y * 1024 + 1, (y + 1) * 1024), 4)
				end

				local big = string.rep(table.concat(rows), 4)

				expect(#big).to.equal(1024 * 1024 * 4)

				-- The test runner calls the cases under a debug hook, which keeps LuaJIT from compiling anything (about 100 times slower for this
				-- code). A reference loop tells whether the compiler works here: if it does not, the guard is only a sanity bound.
				local t0 = SysTime()
				local s = 0

				for i = 1, 30000000 do
					s = s + i % 7
				end

				local loopMs = (SysTime() - t0) * 1000
				local jitWorks = loopMs < 150

				t0 = SysTime()

				local c = D.Compress(big, 1024, 1024)
				local ms = (SysTime() - t0) * 1000

				expect(#c).to.equal(1024 * 1024 / 2)
				expect(ms).to.beLessThan(jitWorks and 150 or 8000)
			end
		},
		{
			name = "a realistic 1024x1024 landscape (roads, buildings, water, sharp edges): PSNR above 33 dB, 8 times smaller",
			func = function()
				local D = dxt()
				local img = landscape(1024)

				expect(#img).to.equal(1024 * 1024 * 4)

				local c = D.Compress(img, 1024, 1024)

				expect(#c * 8).to.equal(#img)

				local back = D.Decode(c, 1024, 1024)

				expect(#back).to.equal(#img)

				local e = D.Error(img, back)

				expect(e.psnr).to.beGreaterThan(33)
			end
		},
	}
}
