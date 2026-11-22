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

-- Same with an alpha: f(x, y) -> r, g, b, a.
local function imageA(w, h, f)
	local rows = {}

	for y = 0, h - 1 do
		local row = {}

		for x = 0, w - 1 do
			local r, g, b, a = f(x, y)
			row[x + 1] = string.char(b, g, r, a)
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

		-- Wave 2: real alpha (opts.alpha). A pixel is VOID when alpha == 0 and b == g == r == 0 (Capture.IsVoid); every other pixel is solid, whatever its alpha.
		-- A block with a void pixel is written in the 3-colour mode (c0 <= c1, indices 0 = c0, 1 = c1, 2 = middle, 3 = transparent), its end points from the solid
		-- pixels only. Production change that breaks these cases: another void rule, end points that include the void pixels, c0 > c1 in 3-colour mode, a wrong index.
		{
			name = "alpha, hand-computed: one void pixel in a black and white block gives the 3-colour mode (c0 = black <= c1 = white, white index 1, void index 3)",
			func = function()
				local D = dxt()
				local V, W, K = px(0, 0, 0, 0), px(255, 255, 255, 255), px(0, 0, 0, 1) -- a black SOLID pixel has alpha 1
				local rows = {
					V .. W .. K .. W, -- 3 1 0 1 -> 3 + 1*4 + 0 + 1*64 = 0x47
					W .. W .. W .. W, -- 0x55
					K .. K .. K .. K, -- 0x00
					W .. K .. W .. K, -- 1 0 1 0 -> 1 + 16 = 0x11
				}

				expect(hex(D.Compress(table.concat(rows), 4, 4, {alpha = true}))).to.equal("00 00 FF FF 47 55 00 11 ")
			end
		},
		{
			name = "alpha, hand-computed: three void pixels, two grey levels (40 and 200): end points from the solid pixels, index 0 dark, 1 light, 3 void",
			func = function()
				local D = dxt()
				-- 40: r5 5, g6 10, b5 5 -> 0x2945; 200: r5 24, g6 49, b5 24 -> 0xC638; 0x2945 < 0xC638 so c0 = 0x2945
				local V, Dk, Lt = px(0, 0, 0, 0), px(40, 40, 40, 255), px(200, 200, 200, 255)
				local rows = {
					V .. Dk .. Lt .. V, -- 3 0 1 3 -> 3 + 0 + 16 + 192 = 0xD3
					Lt .. Lt .. Dk .. Dk, -- 1 1 0 0 -> 0x05
					Dk .. Dk .. Lt .. Lt, -- 0 0 1 1 -> 0x50
					Lt .. Dk .. Dk .. V, -- 1 0 0 3 -> 1 + 192 = 0xC1
				}

				expect(hex(D.Compress(table.concat(rows), 4, 4, {alpha = true}))).to.equal("45 29 38 C6 D3 05 50 C1 ")
			end
		},
		{
			name = "alpha, hand-computed: vivid colours (red and yellow) keep their exact end points next to a void pixel",
			func = function()
				local D = dxt()
				local V, R, Y = px(0, 0, 0, 0), px(255, 0, 0, 255), px(255, 255, 0, 255)
				local rows = {
					V .. R .. Y .. Y, -- 3 0 1 1 -> 3 + 16 + 64 = 0x53
					R .. R .. R .. R, -- 0x00
					Y .. Y .. Y .. Y, -- 0x55
					Y .. R .. V .. R, -- 1 0 3 0 -> 1 + 48 = 0x31
				}

				-- c0 = 0xF800 (red), c1 = 0xFFE0 (yellow)
				expect(hex(D.Compress(table.concat(rows), 4, 4, {alpha = true}))).to.equal("00 F8 E0 FF 53 00 55 31 ")
			end
		},
		{
			name = "alpha, hand-computed: an all-void block is c0 = c1 = 0 with every index 3; a block with a single solid pixel has c0 == c1 and index 0 for it",
			func = function()
				local D = dxt()
				local V, R = px(0, 0, 0, 0), px(255, 0, 0, 255)

				expect(hex(D.Compress(string.rep(V, 16), 4, 4, {alpha = true}))).to.equal("00 00 00 00 FF FF FF FF ")

				local rows = {V .. V .. V .. V, V .. V .. V .. V, V .. R .. V .. V, V .. V .. V .. V}

				-- the solid pixel is at (1, 2): 3 + 0*4 + 3*16 + 3*64 = 0xF3
				expect(hex(D.Compress(table.concat(rows), 4, 4, {alpha = true}))).to.equal("00 F8 00 F8 FF FF F3 FF ")
			end
		},
		{
			name = "alpha: a pixel with alpha 0 but a colour is SOLID (the void rule needs the colour to be black too): it gets index 0, only the black alpha-0 pixel is void",
			func = function()
				local D = dxt()
				local rows = {px(0, 0, 0, 0) .. string.rep(px(200, 100, 50, 0), 3)}

				for y = 2, 4 do
					rows[y] = string.rep(px(200, 100, 50, 0), 4)
				end

				-- c0 = c1 = 0xC326; the void pixel is index 3 in the lowest bits of the first row
				expect(hex(D.Compress(table.concat(rows), 4, 4, {alpha = true}))).to.equal("26 C3 26 C3 03 00 00 00 ")
			end
		},
		{
			name = "alpha on an image without any void pixel is byte for byte the same as without opts (4-colour blocks as before)",
			func = function()
				local D = dxt()
				local images = {noise(64, 64, 31), landscape(128), solid(16, 16, 128, 64, 32), image(32, 32, function(x, y) return x * 8, y * 8, (x + y) * 4 end)}

				for n, img in ipairs(images) do
					local w = math.floor(math.sqrt(#img / 4) + 0.5)

					expect(D.Compress(img, w, w, {alpha = true}) == D.Compress(img, w, w)).to.beTrue()
					expect(D.Compress(img, w, w, {}) == D.Compress(img, w, w)).to.beTrue()
					expect(D.Compress(img, w, w, {alpha = false}) == D.Compress(img, w, w)).to.beTrue()
				end
			end
		},
		{
			name = "alpha: blocks with void pixels are 3-colour (c0 <= c1), blocks without are 4-colour (c0 > c1, or c0 == c1 with indices 0), in a noisy image with voids",
			func = function()
				local D = dxt()
				local rnd = lcg(8)
				local img = imageA(64, 64, function(x, y)
					if (x % 16) < 3 and (y % 8) < 5 then
						return 0, 0, 0, 0
					end

					return 20 + rnd() % 200, 20 + rnd() % 200, 20 + rnd() % 200, 255
				end)
				local c = D.Compress(img, 64, 64, {alpha = true})
				local three, four = 0, 0

				for by = 0, 15 do
					for bx = 0, 15 do
						local i = (by * 16 + bx) * 8 + 1
						local c0, c1 = u16(c, i), u16(c, i + 2)
						local hasVoid = false

						for y = 0, 3 do
							for x = 0, 3 do
								local o = ((by * 4 + y) * 64 + bx * 4 + x) * 4 + 1

								if img:sub(o, o + 3) == "\0\0\0\0" then
									hasVoid = true
								end
							end
						end

						if hasVoid then
							three = three + 1
							expect(c0 <= c1).to.beTrue()
						else
							four = four + 1
							expect(c0 >= c1).to.beTrue()

							if c0 == c1 then
								expect(string.byte(c, i + 4)).to.equal(0)
							end
						end
					end
				end

				expect(three).to.beGreaterThan(0)
				expect(four).to.beGreaterThan(0)
			end
		},
		{
			name = "alpha round trip: voids come back transparent (alpha 0, black), solids come back solid (alpha 255) with PSNR >= 33 dB on the solids",
			func = function()
				local D = dxt()
				local size = 256
				local base = landscape(size)
				-- punch a void disc and a void band in it, add black solid pixels (alpha 1) and coloured alpha-0 pixels (solid by the rule)
				local rows = {}

				for y = 0, size - 1 do
					local row = {}

					for x = 0, size - 1 do
						local i = (y * size + x) * 4 + 1
						local p = base:sub(i, i + 3)
						local dx, dy = x - 90, y - 130

						if dx * dx + dy * dy < 60 * 60 or (y > 200 and y < 215) or (x > 230 and (y % 7) < 3) then
							p = "\0\0\0\0"
						elseif x == 10 and y % 5 == 0 then
							p = "\0\0\0\1" -- black solid
						elseif x == 12 and y % 5 == 0 then
							p = "\9\8\7\0" -- coloured, alpha 0: solid
						end

						row[x + 1] = p
					end

					rows[y + 1] = table.concat(row)
				end

				local img = table.concat(rows)
				local c = D.Compress(img, size, size, {alpha = true})
				local back = D.Decode(c, size, size)
				local voids, solids = 0, 0

				for y = 0, size - 1 do
					for x = 0, size - 1 do
						local i = (y * size + x) * 4 + 1
						local ob, og, or_, oa = string.byte(img, i, i + 3)
						local bb, bg, br, ba = string.byte(back, i, i + 3)

						if oa == 0 and ob == 0 and og == 0 and or_ == 0 then
							voids = voids + 1
							expect(ba).to.equal(0)
							expect(bb + bg + br).to.equal(0)
						else
							solids = solids + 1
							expect(ba).to.equal(255)
						end
					end
				end

				expect(voids).to.beGreaterThan(1000)
				expect(solids).to.beGreaterThan(1000)

				local e = D.ErrorSolid(img, back)

				expect(e).to.exist()
				expect(e.lost).to.equal(0)
				expect(e.solid).to.equal(solids)
				expect(e.psnr).to.beGreaterThan(33)
			end
		},
		{
			name = "alpha: CompressRows chunks (1, 7, 32 and the rest) concatenated are byte for byte Compress, with voids",
			func = function()
				local D = dxt()
				local w, h = 64, 128
				local rnd = lcg(77)
				local img = imageA(w, h, function(x, y)
					if (x * 3 + y * 5) % 11 < 3 then
						return 0, 0, 0, 0
					end

					return 30 + rnd() % 180, 30 + rnd() % 180, 30 + rnd() % 180, 255
				end)
				local whole = D.Compress(img, w, h, {alpha = true})
				local rows = h / 4

				expect(#whole).to.equal((w / 4) * rows * 8)
				expect(whole ~= D.Compress(img, w, h)).to.beTrue()

				for _, size in ipairs({1, 7, 32, 13}) do
					local parts, first = {}, 0

					while first < rows do
						local last = math.min(first + size - 1, rows - 1)
						local s, err = D.CompressRows(img, w, h, first, last, {alpha = true})

						expect(err).to.beNil()
						parts[#parts + 1] = s
						first = last + 1
					end

					expect(table.concat(parts) == whole).to.beTrue()
				end
			end
		},
		{
			name = "alpha: bad opts and the usual refusals give nil and a reason",
			func = function()
				local D = dxt()
				local img = solid(8, 8, 1, 2, 3)

				for _, o in ipairs({"alpha", 12, true}) do
					local s, err = D.Compress(img, 8, 8, o)

					expect(s).to.beNil()
					expect(err).to.beA("string")

					s, err = D.CompressRows(img, 8, 8, 0, 1, o)
					expect(s).to.beNil()
					expect(err).to.beA("string")
				end

				local s, err = D.Compress(img, 7, 8, {alpha = true})

				expect(s).to.beNil()
				expect(err).to.beA("string")

				s, err = D.CompressRows(img, 8, 8, 1, 2, {alpha = true})
				expect(s).to.beNil()
				expect(err).to.beA("string")

				s, err = D.CompressRows(img, 8, 8, 2, 1, {alpha = true})
				expect(s).to.beNil()
				expect(err).to.beA("string")
			end
		},
		{
			name = "ErrorSolid: only the solid pixels of A are measured (alpha ignored), hand-computed mae, max, psnr; the void ones do not count",
			func = function()
				local D = dxt()
				local a = px(10, 20, 30, 1) .. px(0, 0, 0, 0) .. px(100, 100, 100, 255)
				local b = px(13, 20, 26, 255) .. px(50, 50, 50, 255) .. px(100, 100, 100, 0)
				local e = D.ErrorSolid(a, b)

				-- two solid pixels, 6 channels: |d| sum 7, d^2 sum 25
				expect(e.solid).to.equal(2)
				expect(e.lost).to.equal(0)
				expect(e.max).to.equal(4)
				expect(e.mae).to.aboutEqual(7 / 6, 1e-9)
				expect(e.psnr).to.aboutEqual(10 * math.log10(255 * 255 / (25 / 6)), 1e-9)
			end
		},
		{
			name = "ErrorSolid: a solid pixel of A that is void in B is counted in lost (and its colour difference is measured)",
			func = function()
				local D = dxt()
				local a = px(10, 20, 30, 255) .. px(100, 100, 100, 255)
				local b = px(10, 20, 30, 255) .. px(0, 0, 0, 0)
				local e = D.ErrorSolid(a, b)

				expect(e.solid).to.equal(2)
				expect(e.lost).to.equal(1)
				expect(e.max).to.equal(100)
			end
		},
		{
			name = "ErrorSolid: identical solids give mae 0 and psnr 99; no solid pixel, different lengths or wrong types give nil and a reason",
			func = function()
				local D = dxt()
				local a = px(10, 20, 30, 255) .. px(0, 0, 0, 0)
				local e = D.ErrorSolid(a, a)

				expect(e.mae).to.equal(0)
				expect(e.psnr).to.equal(99)
				expect(e.solid).to.equal(1)

				for _, args in ipairs({{px(0, 0, 0, 0), px(0, 0, 0, 0)}, {a, a .. px(1, 1, 1, 1)}, {a, ""}, {"", ""}, {1, a}, {a, nil}, {"xyz", "xyz"}}) do
					local ok, r, err = pcall(D.ErrorSolid, args[1], args[2])

					expect(ok).to.beTrue()
					expect(r).to.beNil()
					expect(err).to.beA("string")
				end
			end
		},

		-- IsAllVoid: true only when every pixel is void (alpha 0 and colour 0), early exit on the first solid pixel.
		{
			name = "IsAllVoid: an empty image is all void, whatever its size (also with a number of pixels that is not a multiple of 4)",
			func = function()
				local D = dxt()

				for _, size in ipairs({{4, 4}, {16, 16}, {1, 1}, {3, 3}, {5, 7}, {1024, 4}}) do
					local w, h = size[1], size[2]
					local r, err = D.IsAllVoid(string.rep("\0", w * h * 4), w, h)

					expect(err).to.beNil()
					expect(r).to.equal(true)
				end
			end
		},
		{
			name = "IsAllVoid: ONE solid pixel is found wherever it is: the very last byte, the first byte, the middle, and in the leftover pixels of a 3x3 image",
			func = function()
				local D = dxt()
				local w, h = 16, 16
				local n = w * h * 4

				-- a nonzero byte at each of these offsets (1-based): first, middle, 16-byte step edges, last
				for _, at in ipairs({1, 2, 3, 4, 15, 16, 17, 130, n / 2, n / 2 + 1, n - 16, n - 15, n - 1, n}) do
					local img = string.rep("\0", at - 1) .. "\1" .. string.rep("\0", n - at)

					expect(#img).to.equal(n)
					expect(D.IsAllVoid(img, w, h)).to.equal(false)
				end

				-- 3x3: 36 bytes, the last 4 are not covered by the 16-byte reads
				for at = 33, 36 do
					local img = string.rep("\0", at - 1) .. "\200" .. string.rep("\0", 36 - at)

					expect(D.IsAllVoid(img, 3, 3)).to.equal(false)
				end
			end
		},
		{
			name = "IsAllVoid: a black pixel with alpha 1 is solid; a coloured pixel with alpha 0 is solid; an all-zero pixel among them is not enough",
			func = function()
				local D = dxt()
				local V = px(0, 0, 0, 0)

				expect(D.IsAllVoid(string.rep(V, 7) .. px(0, 0, 0, 1) .. string.rep(V, 8), 4, 4)).to.equal(false)
				expect(D.IsAllVoid(string.rep(V, 3) .. px(9, 0, 0, 0) .. string.rep(V, 12), 4, 4)).to.equal(false)
				expect(D.IsAllVoid(string.rep(V, 15) .. px(0, 5, 0, 0), 4, 4)).to.equal(false)
				expect(D.IsAllVoid(string.rep(V, 15) .. px(0, 0, 255, 0), 4, 4)).to.equal(false)
				expect(D.IsAllVoid(string.rep(V, 16), 4, 4)).to.equal(true)
			end
		},
		{
			name = "IsAllVoid: wrong length, wrong types or bad sizes give nil and a reason, no error",
			func = function()
				local D = dxt()
				local img = string.rep("\0", 64)

				for _, args in ipairs({{img, 4, 3}, {img, 5, 4}, {img .. "\0", 4, 4}, {"", 4, 4}, {"", 0, 0}, {nil, 4, 4}, {12, 4, 4}, {{}, 4, 4}, {img, "4", 4},
					{img, 4, nil}, {img, 0, 16}, {img, -4, -4}, {img, 2.5, 8}, {img, math.huge, 4}, {img, 0 / 0, 4}}) do
					local ok, r, err = pcall(D.IsAllVoid, args[1], args[2], args[3])

					expect(ok).to.beTrue()
					expect(r).to.beNil()
					expect(err).to.beA("string")
				end
			end
		},
	}
}
