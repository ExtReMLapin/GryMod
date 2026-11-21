-- GryMod minimap: module dxt1. BGRA to DXT1 compressor (chunkable), reference decoder and error metric (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.DXT1 = GryMod.Minimap.DXT1 or {}

-- Formats
--   BGRA string: 4 bytes per pixel (blue, green, red, alpha), rows from top to bottom, pixels from left to right. Alpha is ignored when compressing
--   and written as 255 by the decoder (except for the transparent black of the 3-colour mode, see Decode).
--   DXT1 string: 8 bytes per 4x4 block, blocks in row-major order. A block is c0 (u16 little-endian RGB565), c1 (same), then 4 bytes of 2-bit
--   indices, one byte per pixel row, the pixel x = 0 in the lowest two bits. Palette (c0 > c1, four colours): 0 = c0, 1 = c1, 2 = (2*c0 + c1) / 3,
--   3 = (c0 + 2*c1) / 3.
--
-- Method (cheap and chunkable, no engine call in the loops):
--   * end points = corners of the bounding box of the 16 pixels (minimum and maximum of each channel), quantised to 565 by (v*31 + 127) / 255 and
--     (v*63 + 127) / 255 (rounding to the nearest). The box diagonal runs from the minima to the maxima, except that red and green are swapped
--     (min <-> max) when that channel varies against blue (negative covariance with the centre of the box): a red roof next to green grass lies on the
--     other diagonal and would otherwise be projected far from its two colours. Then c0 and c1 are ordered so that c0 > c1 on the packed integers;
--   * every channel quantising to one value (also for a block that is not solid): c0 == c1 and all indices are 0, because c0 <= c1 would select the
--     3-colour mode, whose index 3 is transparent black;
--   * index of a pixel: position t along the axis from c1 (t = 0) to c0 (t = 1), measured on the colours the decoder will rebuild, clamped to [0, 1];
--     n = round(3 * t) in 0..3, then the DXT1 index is {[0] = 1, [1] = 3, [2] = 2, [3] = 0}[n].
-- LuaJIT: the string is read by four string.byte ranges per block (15 useful bytes per line, the alpha of the last pixel is not needed) into 48
-- locals, the block is unrolled by hand (generated, then pasted), minima, maxima and clamps use math.min / math.max (no branch for the trace to
-- guard on), the output is one string.char of 8 bytes per block and table.concat; no table is allocated per block, no closure, no engine call.

local DXT1 = GryMod.Minimap.DXT1

local byte, char, floor, concat, log10, min, max = string.byte, string.char, math.floor, table.concat, math.log10, math.min, math.max
local band, rshift = bit.band, bit.rshift

-- Value returned by Error for an exact copy (the PSNR of a zero error is infinite; a finite value keeps the numbers printable and comparable).
local PSNR_EXACT = 99

-- Quantisation tables: Q5[v] / Q6[v] = the 5 / 6 bit value of the 8 bit v; ER5[v] / ER6[v] = what the decoder rebuilds from it (bit replication).
local Q5, Q6, ER5, ER6 = {}, {}, {}, {}

for v = 0, 255 do
	local q5 = floor((v * 31 + 127) / 255)
	local q6 = floor((v * 63 + 127) / 255)

	Q5[v], Q6[v] = q5, q6
	ER5[v] = q5 * 8 + rshift(q5, 2)
	ER6[v] = q6 * 4 + rshift(q6, 4)
end

-- DXT1 index of the rounded position n (0 at c1, 3 at c0) along the axis.
local INDEX = {[0] = 1, [1] = 3, [2] = 2, [3] = 0}

-- Checks a BGRA picture: returns a reason when it cannot be a w x h picture with w and h multiples of 4, nil when it is fine.
local function checkPicture(bgra, w, h)
	if type(bgra) ~= "string" then
		return "the picture is not a string"
	end

	if type(w) ~= "number" or type(h) ~= "number" then
		return "width and height must be numbers"
	end

	if w ~= floor(w) or h ~= floor(h) or w < 4 or h < 4 or w == math.huge or h == math.huge then
		return "width and height must be integers of at least 4"
	end

	if w % 4 ~= 0 or h % 4 ~= 0 then
		return "width and height must be multiples of 4"
	end

	if #bgra ~= w * h * 4 then
		return "the string length does not match width * height * 4"
	end
end

-- Compresses the block rows [first, last] of a checked picture, returns one string. Two loops per block row: the first finds the end points and the axis of
-- each block, the second computes the indices and writes the 8 bytes. A single loop does the same work but is about ten times slower: its body is too
-- big for LuaJIT to compile as one trace (measured: the same code split in two loops runs in 20 ms instead of 120 ms for 1024 x 1024).
local function compressRows(d, w, first, last)
	local bw = w / 4
	local stride = w * 4
	local parts = {}
	-- parameters of the blocks of the current row: position = r * KR + g * KG + b * KB + K0, then INDEX[FLIP + STEP * clamp(floor(position))]
	local KR, KG, KB, K0, FLIP, STEP, C0, C1 = {}, {}, {}, {}, {}, {}, {}, {}

	for by = first, last do
		local rowBase = by * 4 * stride + 1

		for bx = 0, bw - 1 do
			local o = rowBase + bx * 16
			local rmin, rmax, gmin, gmax, bmin, bmax = 255, 0, 255, 0, 255, 0

			-- bounding box (the lines are read again by the next steps: reading is nearly free in a trace and keeps the number of live values small)
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 0, o + stride * 0 + 14)
				rmin, rmax = min(rmin, r0, r1, r2, r3), max(rmax, r0, r1, r2, r3)
				gmin, gmax = min(gmin, g0, g1, g2, g3), max(gmax, g0, g1, g2, g3)
				bmin, bmax = min(bmin, b0, b1, b2, b3), max(bmax, b0, b1, b2, b3)
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 1, o + stride * 1 + 14)
				rmin, rmax = min(rmin, r0, r1, r2, r3), max(rmax, r0, r1, r2, r3)
				gmin, gmax = min(gmin, g0, g1, g2, g3), max(gmax, g0, g1, g2, g3)
				bmin, bmax = min(bmin, b0, b1, b2, b3), max(bmax, b0, b1, b2, b3)
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 2, o + stride * 2 + 14)
				rmin, rmax = min(rmin, r0, r1, r2, r3), max(rmax, r0, r1, r2, r3)
				gmin, gmax = min(gmin, g0, g1, g2, g3), max(gmax, g0, g1, g2, g3)
				bmin, bmax = min(bmin, b0, b1, b2, b3), max(bmax, b0, b1, b2, b3)
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 3, o + stride * 3 + 14)
				rmin, rmax = min(rmin, r0, r1, r2, r3), max(rmax, r0, r1, r2, r3)
				gmin, gmax = min(gmin, g0, g1, g2, g3), max(gmax, g0, g1, g2, g3)
				bmin, bmax = min(bmin, b0, b1, b2, b3), max(bmax, b0, b1, b2, b3)
			end

			local qrmin, qrmax, qgmin, qgmax, qbmin, qbmax = Q5[rmin], Q5[rmax], Q6[gmin], Q6[gmax], Q5[bmin], Q5[bmax]
			local c0, c1, kr, kg, kb, k0, flip, step

			if qrmin == qrmax and qgmin == qgmax and qbmin == qbmax then
				-- one colour after quantisation: c0 == c1 and every index 0 (a position clamped to 3 is the index 0 with flip 0 and step 1)
				c0 = qrmax * 2048 + qgmax * 32 + qbmax
				c1, kr, kg, kb, k0, flip, step = c0, 0, 0, 0, 10, 0, 1
			else
				-- orientation of the axis: when red (or green) varies against blue, its two end points are swapped, so the axis goes through the two
				-- real colours of anti-correlated blocks (a red roof on green grass) instead of along the wrong diagonal of the box
				local mr, mg, mb = rmin + rmax, gmin + gmax, bmin + bmax
				local srb, sgb, sr, sg, sb = 0, 0, 0, 0, 0

				do
					local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 0, o + stride * 0 + 14)
					srb = srb + r0 * b0 + r1 * b1 + r2 * b2 + r3 * b3
					sgb = sgb + g0 * b0 + g1 * b1 + g2 * b2 + g3 * b3
					sr, sg, sb = sr + r0 + r1 + r2 + r3, sg + g0 + g1 + g2 + g3, sb + b0 + b1 + b2 + b3
				end
				do
					local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 1, o + stride * 1 + 14)
					srb = srb + r0 * b0 + r1 * b1 + r2 * b2 + r3 * b3
					sgb = sgb + g0 * b0 + g1 * b1 + g2 * b2 + g3 * b3
					sr, sg, sb = sr + r0 + r1 + r2 + r3, sg + g0 + g1 + g2 + g3, sb + b0 + b1 + b2 + b3
				end
				do
					local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 2, o + stride * 2 + 14)
					srb = srb + r0 * b0 + r1 * b1 + r2 * b2 + r3 * b3
					sgb = sgb + g0 * b0 + g1 * b1 + g2 * b2 + g3 * b3
					sr, sg, sb = sr + r0 + r1 + r2 + r3, sg + g0 + g1 + g2 + g3, sb + b0 + b1 + b2 + b3
				end
				do
					local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 3, o + stride * 3 + 14)
					srb = srb + r0 * b0 + r1 * b1 + r2 * b2 + r3 * b3
					sgb = sgb + g0 * b0 + g1 * b1 + g2 * b2 + g3 * b3
					sr, sg, sb = sr + r0 + r1 + r2 + r3, sg + g0 + g1 + g2 + g3, sb + b0 + b1 + b2 + b3
				end

				-- sum over the 16 pixels of (2r - mr) * (2b - mb) and (2g - mg) * (2b - mb): only their signs matter
				sr = 4 * srb - 2 * mb * sr - 2 * mr * sb + 16 * mr * mb
				sg = 4 * sgb - 2 * mb * sg - 2 * mg * sb + 16 * mg * mb

				-- branch-free: clamp to -1, 0 or 1, then 1 only when the covariance is negative
				local fr, fg = max(0, -max(-1, min(1, sr))), max(0, -max(-1, min(1, sg)))
				local ar, br = rmin + (rmax - rmin) * fr, rmax - (rmax - rmin) * fr
				local ag, bg = gmin + (gmax - gmin) * fg, gmax - (gmax - gmin) * fg
				local cA = Q5[ar] * 2048 + Q6[ag] * 32 + Q5[bmin]
				local cB = Q5[br] * 2048 + Q6[bg] * 32 + Q5[bmax]
				-- axis from A to B measured on the colours the decoder will rebuild; the position of a pixel is r * kr + g * kg + b * kb + k0 (0 at A, 3 at B)
				local ra, ga, ba = ER5[ar], ER6[ag], ER5[bmin]
				local dr, dg, db = ER5[br] - ra, ER6[bg] - ga, ER5[bmax] - ba
				local k = 3 / (dr * dr + dg * dg + db * db)
				kr, kg, kb = dr * k, dg * k, db * k
				k0 = 0.5 - ra * kr - ga * kg - ba * kb
				-- c0 must be above c1 (4-colour mode): when A is above B the axis is walked the other way (n -> 3 - n)
				local sw = max(0, min(1, cA - cB))
				flip, step = sw * 3, 1 - 2 * sw
				c0, c1 = cB + (cA - cB) * sw, cA - (cA - cB) * sw
			end

			local i = bx + 1
			KR[i], KG[i], KB[i], K0[i], FLIP[i], STEP[i], C0[i], C1[i] = kr, kg, kb, k0, flip, step, c0, c1
		end

		local row = {}

		for bx = 0, bw - 1 do
			local o = rowBase + bx * 16
			local i = bx + 1
			local kr, kg, kb, k0, flip, step = KR[i], KG[i], KB[i], K0[i], FLIP[i], STEP[i]
			local x0, x1, x2, x3

			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 0, o + stride * 0 + 14)
				local i0 = INDEX[flip + step * max(0, min(3, floor(r0 * kr + g0 * kg + b0 * kb + k0)))]
				local i1 = INDEX[flip + step * max(0, min(3, floor(r1 * kr + g1 * kg + b1 * kb + k0)))]
				local i2 = INDEX[flip + step * max(0, min(3, floor(r2 * kr + g2 * kg + b2 * kb + k0)))]
				local i3 = INDEX[flip + step * max(0, min(3, floor(r3 * kr + g3 * kg + b3 * kb + k0)))]
				x0 = i0 + i1 * 4 + i2 * 16 + i3 * 64
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 1, o + stride * 1 + 14)
				local i0 = INDEX[flip + step * max(0, min(3, floor(r0 * kr + g0 * kg + b0 * kb + k0)))]
				local i1 = INDEX[flip + step * max(0, min(3, floor(r1 * kr + g1 * kg + b1 * kb + k0)))]
				local i2 = INDEX[flip + step * max(0, min(3, floor(r2 * kr + g2 * kg + b2 * kb + k0)))]
				local i3 = INDEX[flip + step * max(0, min(3, floor(r3 * kr + g3 * kg + b3 * kb + k0)))]
				x1 = i0 + i1 * 4 + i2 * 16 + i3 * 64
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 2, o + stride * 2 + 14)
				local i0 = INDEX[flip + step * max(0, min(3, floor(r0 * kr + g0 * kg + b0 * kb + k0)))]
				local i1 = INDEX[flip + step * max(0, min(3, floor(r1 * kr + g1 * kg + b1 * kb + k0)))]
				local i2 = INDEX[flip + step * max(0, min(3, floor(r2 * kr + g2 * kg + b2 * kb + k0)))]
				local i3 = INDEX[flip + step * max(0, min(3, floor(r3 * kr + g3 * kg + b3 * kb + k0)))]
				x2 = i0 + i1 * 4 + i2 * 16 + i3 * 64
			end
			do
				local b0, g0, r0, _, b1, g1, r1, _, b2, g2, r2, _, b3, g3, r3 = byte(d, o + stride * 3, o + stride * 3 + 14)
				local i0 = INDEX[flip + step * max(0, min(3, floor(r0 * kr + g0 * kg + b0 * kb + k0)))]
				local i1 = INDEX[flip + step * max(0, min(3, floor(r1 * kr + g1 * kg + b1 * kb + k0)))]
				local i2 = INDEX[flip + step * max(0, min(3, floor(r2 * kr + g2 * kg + b2 * kb + k0)))]
				local i3 = INDEX[flip + step * max(0, min(3, floor(r3 * kr + g3 * kg + b3 * kb + k0)))]
				x3 = i0 + i1 * 4 + i2 * 16 + i3 * 64
			end

			local c0, c1 = C0[i], C1[i]
			local c0lo, c1lo = band(c0, 255), band(c1, 255)

			row[i] = char(c0lo, rshift(c0, 8), c1lo, rshift(c1, 8), x0, x1, x2, x3)
		end

		parts[#parts + 1] = concat(row)
	end

	return concat(parts)
end

-- DXT1.Compress(bgra, w, h) -> string | nil, reason
function DXT1.Compress(bgra, w, h)
	local err = checkPicture(bgra, w, h)

	if err then
		return nil, err
	end

	return compressRows(bgra, w, 0, h / 4 - 1)
end

-- DXT1.CompressRows(bgra, w, h, firstBlockRow, lastBlockRow) -> string | nil, reason
-- Block rows are numbered from 0 (4 pixel rows each) and both bounds are inclusive. The concatenation of consecutive chunks is Compress.
function DXT1.CompressRows(bgra, w, h, first, last)
	local err = checkPicture(bgra, w, h)

	if err then
		return nil, err
	end

	if type(first) ~= "number" or type(last) ~= "number" or first ~= floor(first) or last ~= floor(last) then
		return nil, "the block row bounds must be integers"
	end

	if first > last then
		return nil, "first block row is after the last one"
	end

	if first < 0 or last > h / 4 - 1 then
		return nil, "block rows outside the picture"
	end

	return compressRows(bgra, w, first, last)
end

-- DXT1.Decode(dxt, w, h) -> BGRA string | nil, reason
-- Reference decoder, clarity before speed. Reconstruction as on current GPUs: 5 to 8 bits by (v << 3) | (v >> 2), 6 to 8 bits by (v << 2) | (v >> 4); the
-- interpolated colours are computed per channel in integers with a truncating division, (2*a + b) / 3 and (a + 2*b) / 3 (half-way (a + b) / 2 in 3-colour
-- mode). Hardware differs by a unit here, far below the compression error. Alpha is 255, except for index 3 of a block with c0 <= c1 (the
-- "transparent black" of the 3-colour mode: 0, 0, 0, alpha 0), which the compressor never produces.
function DXT1.Decode(dxt, w, h)
	if type(dxt) ~= "string" then
		return nil, "the data is not a string"
	end

	if type(w) ~= "number" or type(h) ~= "number" or w ~= floor(w) or h ~= floor(h) or w < 4 or h < 4 or w == math.huge or h == math.huge then
		return nil, "width and height must be integers of at least 4"
	end

	if w % 4 ~= 0 or h % 4 ~= 0 then
		return nil, "width and height must be multiples of 4"
	end

	local bw, bh = w / 4, h / 4

	if #dxt ~= bw * bh * 8 then
		return nil, "the data length does not match the size"
	end

	local out = {}
	local palette = {}
	local lines = {{}, {}, {}, {}}

	for by = 0, bh - 1 do
		for bx = 0, bw - 1 do
			local i = (by * bw + bx) * 8 + 1
			local c0lo, c0hi, c1lo, c1hi, ib0, ib1, ib2, ib3 = byte(dxt, i, i + 7)
			local c0, c1 = c0lo + c0hi * 256, c1lo + c1hi * 256
			local v0r, v0g, v0b = rshift(c0, 11), band(rshift(c0, 5), 63), band(c0, 31)
			local v1r, v1g, v1b = rshift(c1, 11), band(rshift(c1, 5), 63), band(c1, 31)
			local r0, g0, b0 = v0r * 8 + rshift(v0r, 2), v0g * 4 + rshift(v0g, 4), v0b * 8 + rshift(v0b, 2)
			local r1, g1, b1 = v1r * 8 + rshift(v1r, 2), v1g * 4 + rshift(v1g, 4), v1b * 8 + rshift(v1b, 2)

			palette[0] = char(b0, g0, r0, 255)
			palette[1] = char(b1, g1, r1, 255)

			if c0 > c1 then
				palette[2] = char(floor((2 * b0 + b1) / 3), floor((2 * g0 + g1) / 3), floor((2 * r0 + r1) / 3), 255)
				palette[3] = char(floor((b0 + 2 * b1) / 3), floor((g0 + 2 * g1) / 3), floor((r0 + 2 * r1) / 3), 255)
			else
				palette[2] = char(floor((b0 + b1) / 2), floor((g0 + g1) / 2), floor((r0 + r1) / 2), 255)
				palette[3] = char(0, 0, 0, 0)
			end

			lines[1][bx + 1] = palette[band(ib0, 3)] .. palette[band(rshift(ib0, 2), 3)] .. palette[band(rshift(ib0, 4), 3)] .. palette[rshift(ib0, 6)]
			lines[2][bx + 1] = palette[band(ib1, 3)] .. palette[band(rshift(ib1, 2), 3)] .. palette[band(rshift(ib1, 4), 3)] .. palette[rshift(ib1, 6)]
			lines[3][bx + 1] = palette[band(ib2, 3)] .. palette[band(rshift(ib2, 2), 3)] .. palette[band(rshift(ib2, 4), 3)] .. palette[rshift(ib2, 6)]
			lines[4][bx + 1] = palette[band(ib3, 3)] .. palette[band(rshift(ib3, 2), 3)] .. palette[band(rshift(ib3, 4), 3)] .. palette[rshift(ib3, 6)]
		end

		for y = 1, 4 do
			out[#out + 1] = concat(lines[y])
		end
	end

	return concat(out)
end

-- DXT1.Error(bgraA, bgraB) -> {mae, psnr, max} | nil, reason
-- Over the three colour channels (alpha ignored): mae = mean absolute difference (0..255), max = largest absolute difference of one channel,
-- psnr = 10 * log10(255^2 / mse) in dB. For two identical pictures (mse = 0) psnr is PSNR_EXACT = 99.
function DXT1.Error(a, b)
	if type(a) ~= "string" or type(b) ~= "string" then
		return nil, "both pictures must be strings"
	end

	if #a ~= #b then
		return nil, "the pictures have different lengths"
	end

	if #a == 0 or #a % 4 ~= 0 then
		return nil, "the length must be a positive multiple of 4"
	end

	local sumAbs, sumSq, max = 0, 0, 0

	for i = 1, #a, 4 do
		local ab, ag, ar = byte(a, i, i + 2)
		local bb, bg, br = byte(b, i, i + 2)
		local db, dg, dr = ab - bb, ag - bg, ar - br

		sumSq = sumSq + db * db + dg * dg + dr * dr

		if db < 0 then db = -db end
		if dg < 0 then dg = -dg end
		if dr < 0 then dr = -dr end

		sumAbs = sumAbs + db + dg + dr

		if db > max then max = db end
		if dg > max then max = dg end
		if dr > max then max = dr end
	end

	local samples = #a / 4 * 3
	local mse = sumSq / samples

	return {mae = sumAbs / samples, psnr = mse > 0 and 10 * log10(65025 / mse) or PSNR_EXACT, max = max}
end
