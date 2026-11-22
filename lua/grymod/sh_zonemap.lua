-- GryMod: the in/out map (zone map). SHARED: the server makes it from the node graph (sv_zonemap.lua) and the client reads it (the automatic zoom of
-- the radar, the debug drawing). Design: docs/superpowers/specs/2026-11-22-zonemap-design.md. This file is PURE: no engine call, no file, no util, no entity;
-- every function takes values and returns values, so the same code runs in both realms and is tested without a map.
--
-- A SAMPLE is {x, y, z, indoor = bool, ceil = 0..7} (one ground node). The world is cut into CELLS of 128 x 128 units on LAYERS 128 units high; a cell holds a
-- state (1 outdoor, 2 indoor) and a ceiling class index (0 = open, 1..7 = the classes of CLASSES). Build makes boxes from the samples, Encode / Decode
-- write and read them as a file, Index / Lookup answer "what is here".
GryMod = GryMod or {}
GryMod.ZoneMap = GryMod.ZoneMap or {}

local ZM = GryMod.ZoneMap

ZM.CELL = 128
ZM.LAYER_H = 128
ZM.RADIUS = 3
ZM.CLASSES = {56, 88, 120, 160, 224, 320, 448}
ZM.MAX_BOX = 255
ZM.FORMAT_VERSION = 1

local CELL, LAYER_H, RADIUS, CLASSES, MAX_BOX = ZM.CELL, ZM.LAYER_H, ZM.RADIUS, ZM.CLASSES, ZM.MAX_BOX

local floor = math.floor
local type = type
local byte = string.byte
local schar = string.char
local concat = table.concat
local sort = table.sort
local unpack = unpack

local INV_CELL = 1 / CELL -- exact: a power of two
local INV_LAYER = 1 / LAYER_H

-- the file stores a layer as an int16 limited to -4096..4095 and a cell as an int16 (-32768..32767)
local LAYER_BIAS, CELL_BIAS = 4096, 32768

-- the samples are accepted well inside those limits, so that a spread or a box of 255 cells never leaves them
local LIMIT_CELL = 32000
local LIMIT_LAYER = 4000

-- Layer(z) -> the layer of a height
function ZM.Layer(z)
	return floor((z + LAYER_H / 2) * INV_LAYER)
end

-- CellOf(x) -> the cell index of a coordinate (x or y)
function ZM.CellOf(x)
	return floor(x * INV_CELL)
end

-- CeilIndex(room) -> 1..7: room = highest ceiling minus the node's z. The biggest class that is <= room - 8, and 1 (class 56) at least; a non number gives 1
function ZM.CeilIndex(room)
	if type(room) ~= "number" then
		return 1
	end

	local limit = room - 8
	local index = 1

	for i = 2, 7 do
		if limit >= CLASSES[i] then
			index = i
		end
	end

	return index
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------------------------------------------------
-- While it builds, a cell is ONE number made for the area of the samples: key = (layer - layerMin) * stepL + (cx - cxMin + MARGIN) * stepX + (cy - cyMin +
-- MARGIN), with stepX = height of the area and stepL = width * height (the area has a margin of MARGIN cells all around, so a neighbour, a spread or a
-- probe of a box never wraps into another column). The keys are small, so a table of cells is a dense array or a light hash (a key of 2^40 made the same
-- loops four times slower). The order of the keys is the order layer, cx, cy.

local MARGIN = RADIUS + 1

-- the cell of a ring around a raster cell is filled when it is empty (the spread, one distance at a time); returns the new length of `all`
local function fillCell(cur, all, n, t, v)
	if cur[t] == nil then
		cur[t] = v
		n = n + 1
		all[n] = t
	end

	return n
end

-- Build(samples) -> map {boxes = {{layer, x1, y1, x2, y2, state, ceil}...}, sampleCount, skipped, cells}
-- 1. raster by majority, 2. spread within RADIUS from the raster only, 3. smoothing once, 4. greedy rectangles of at most MAX_BOX cells.
-- Nothing depends on the order of the samples (the keys are sorted before they are walked).
function ZM.Build(samples)
	local map = {boxes = {}, sampleCount = 0, skipped = 0, cells = 0}

	if type(samples) ~= "table" then
		return map
	end

	-- the samples that are valid: their cell and layer, and the area they cover
	local ax, ay, al, av = {}, {}, {}, {}
	local used, skipped = 0, 0
	local minX, maxX, minY, maxY, minL, maxL = LIMIT_CELL, -LIMIT_CELL, LIMIT_CELL, -LIMIT_CELL, LIMIT_LAYER, -LIMIT_LAYER

	for i = 1, #samples do
		local s = samples[i]
		local ok = false

		if type(s) == "table" then
			local x, y, z, indoor, ceil = s.x, s.y, s.z, s.indoor, s.ceil

			if type(x) == "number" and type(y) == "number" and type(z) == "number" and type(ceil) == "number" and type(indoor) == "boolean" and x - x == 0
				and y - y == 0 and z - z == 0 and ceil >= 0 and ceil <= 7 and ceil == floor(ceil) then
				local cx, cy, layer = floor(x * INV_CELL), floor(y * INV_CELL), floor((z + LAYER_H / 2) * INV_LAYER)

				if cx >= -LIMIT_CELL and cx <= LIMIT_CELL and cy >= -LIMIT_CELL and cy <= LIMIT_CELL and layer >= -LIMIT_LAYER and layer <= LIMIT_LAYER then
					used = used + 1
					ax[used], ay[used], al[used], av[used] = cx, cy, layer, ceil * 2 + (indoor and 1 or 0)
					ok = true

					if cx < minX then
						minX = cx
					end

					if cx > maxX then
						maxX = cx
					end

					if cy < minY then
						minY = cy
					end

					if cy > maxY then
						maxY = cy
					end

					if layer < minL then
						minL = layer
					end

					if layer > maxL then
						maxL = layer
					end
				end
			end
		end

		if not ok then
			skipped = skipped + 1
		end
	end

	map.sampleCount, map.skipped = used, skipped

	if used == 0 then
		return map
	end

	local width, height = maxX - minX + 1 + 2 * MARGIN, maxY - minY + 1 + 2 * MARGIN
	local stepX, stepL = height, width * height
	local offX, offY, offL = MARGIN - minX, MARGIN - minY, -minL

	-- 1. raster: the votes of every cell
	local indoorVotes, outdoorVotes, classVotes = {}, {}, {}
	local keys, nKeys = {}, 0

	for i = 1, used do
		local k = (al[i] + offL) * stepL + (ax[i] + offX) * stepX + ay[i] + offY
		local code = av[i]
		local ceil = floor(code / 2)

		if indoorVotes[k] == nil then
			indoorVotes[k], outdoorVotes[k] = 0, 0
			nKeys = nKeys + 1
			keys[nKeys] = k
		end

		if code % 2 == 1 then
			indoorVotes[k] = indoorVotes[k] + 1
		else
			outdoorVotes[k] = outdoorVotes[k] + 1
		end

		local ck = k * 8 + ceil

		classVotes[ck] = (classVotes[ck] or 0) + 1
	end

	ax, ay, al, av = nil, nil, nil, nil

	sort(keys)

	-- the state (indoor only when strictly more votes than outdoor) and the class (the most common, the lower on a tie) of every raster cell
	local cur = {}

	for i = 1, nKeys do
		local k = keys[i]
		local bestClass, bestVotes = 0, -1

		for c = 0, 7 do
			local n = classVotes[k * 8 + c] or 0

			if n > bestVotes then
				bestClass, bestVotes = c, n
			end
		end

		cur[k] = (indoorVotes[k] > outdoorVotes[k] and 2 or 1) * 8 + bestClass
	end

	indoorVotes, outdoorVotes, classVotes = nil, nil, nil

	-- 2. spread: an empty cell takes the value of the nearest raster cell of its layer within RADIUS (Chebyshev). The rings are walked from the nearest to the
	-- farthest and the raster cells in key order, so a tie goes to the cell found first in the order layer, cx, cy. Only raster cells spread.
	local all, n = {}, nKeys

	for i = 1, nKeys do
		all[i] = keys[i]
	end

	for d = 1, RADIUS do
		local dx = d * stepX

		for i = 1, nKeys do
			local k = keys[i]
			local v = cur[k]

			for o = -d, d do
				local col = k + o * stepX

				n = fillCell(cur, all, n, col - d, v)
				n = fillCell(cur, all, n, col + d, v)
			end

			for o = -d + 1, d - 1 do
				n = fillCell(cur, all, n, k - dx + o, v)
				n = fillCell(cur, all, n, k + dx + o, v)
			end
		end
	end

	-- 3. smoothing, once, on the state before the pass: a cell that differs from at least 5 of its known neighbours and has at most one of its own state
	-- takes the other state, with the most common class among the neighbours of that state
	local neighbours = {-stepX - 1, -stepX, -stepX + 1, -1, 1, stepX - 1, stepX, stepX + 1}
	local flipKeys, flipValues, nFlips = {}, {}, 0
	local classCount = {}

	for i = 1, n do
		local k = all[i]
		local own = cur[k] >= 16
		local same, diff = 0, 0

		for j = 1, 8 do
			local nv = cur[k + neighbours[j]]

			if nv then
				if (nv >= 16) == own then
					same = same + 1
				else
					diff = diff + 1
				end
			end
		end

		if diff >= 5 and same <= 1 then
			for c = 0, 7 do
				classCount[c] = 0
			end

			for j = 1, 8 do
				local nv = cur[k + neighbours[j]]

				if nv and (nv >= 16) ~= own then
					local c = nv % 8

					classCount[c] = classCount[c] + 1
				end
			end

			local bestClass, bestVotes = 0, -1

			for c = 0, 7 do
				if classCount[c] > bestVotes then
					bestClass, bestVotes = c, classCount[c]
				end
			end

			nFlips = nFlips + 1
			flipKeys[nFlips] = k
			flipValues[nFlips] = (own and 1 or 2) * 8 + bestClass
		end
	end

	for i = 1, nFlips do
		cur[flipKeys[i]] = flipValues[i]
	end

	map.cells = n

	-- 4. rectangles: per layer, the cells in the order cy, cx; the first free cell grows in x, then in y while the whole row is free and equal. A cell that
	-- is taken is set to false in `cur`, so it is never equal to a value again. The margin keeps a probe outside the area from reaching another cell.
	for i = 1, n do
		local k = all[i]
		local layerPart = floor(k / stepL)
		local rem = k - layerPart * stepL
		local col = floor(rem / stepX)
		local row = rem - col * stepX

		-- the same cell with y more significant than x
		all[i] = layerPart * stepL + row * width + col
	end

	sort(all)

	local boxes, nBoxes = map.boxes, 0

	for i = 1, n do
		local q = all[i]
		local layerPart = floor(q / stepL)
		local rem = q - layerPart * stepL
		local row = floor(rem / width)
		local col = rem - row * width
		local k = layerPart * stepL + col * stepX + row
		local v = cur[k]

		if v then
			local w = 1

			while w < MAX_BOX and cur[k + w * stepX] == v do
				w = w + 1
			end

			local h = 1

			while h < MAX_BOX do
				local rowOk = true

				for dxo = 0, w - 1 do
					if cur[k + h + dxo * stepX] ~= v then
						rowOk = false

						break
					end
				end

				if not rowOk then
					break
				end

				h = h + 1
			end

			for dxo = 0, w - 1 do
				local c = k + dxo * stepX

				for dyo = 0, h - 1 do
					cur[c + dyo] = false
				end
			end

			local x1, y1 = col - offX, row - offY

			nBoxes = nBoxes + 1
			boxes[nBoxes] = {layer = layerPart - offL, x1 = x1, y1 = y1, x2 = x1 + w - 1, y2 = y1 + h - 1, state = v >= 16 and 2 or 1, ceil = v % 8}
		end
	end

	return map
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- File format
-- ---------------------------------------------------------------------------------------------------------------------------------
-- little endian: 24 bytes header ("GZM1", version, flags, 2 reserved, bsp size, node count, sample count, box count), 9 bytes a box (int16 layer, int16 x1,
-- int16 y1, uint8 width - 1, uint8 height - 1, uint8 flags: bit 0 indoor, bits 1..3 class), 4 bytes checksum (sum of every byte before it, modulo 2^32)

local HEADER_SIZE = 24
local BOX_SIZE = 9
local CHECKSUM_SIZE = 4
local BATCH = 4096 -- bytes made into a string at a time (string.char takes its arguments from the stack)
local MAGIC1, MAGIC2, MAGIC3, MAGIC4 = 71, 90, 77, 49 -- "GZM1"
local FLAG_COMPLETE, FLAG_OVER_BUDGET = 1, 2

-- true when the box fits the file and the key range
local function boxFits(b)
	if type(b) ~= "table" then
		return false
	end

	local layer, x1, y1, x2, y2, state, ceil = b.layer, b.x1, b.y1, b.x2, b.y2, b.state, b.ceil

	if type(layer) ~= "number" or type(x1) ~= "number" or type(y1) ~= "number" or type(x2) ~= "number" or type(y2) ~= "number" or type(state) ~= "number"
		or type(ceil) ~= "number" then
		return false
	end

	-- the equalities also refuse NaN and the infinities (an infinity floors to itself but fails the range)
	if layer ~= floor(layer) or x1 ~= floor(x1) or y1 ~= floor(y1) or x2 ~= floor(x2) or y2 ~= floor(y2) or ceil ~= floor(ceil) then
		return false
	end

	return layer >= -LAYER_BIAS and layer < LAYER_BIAS and x1 >= -CELL_BIAS and x2 < CELL_BIAS and y1 >= -CELL_BIAS and y2 < CELL_BIAS and x2 >= x1 and y2 >= y1
		and x2 - x1 < MAX_BOX and y2 - y1 < MAX_BOX and (state == 1 or state == 2) and ceil >= 0 and ceil <= 7
end

-- a header number as an unsigned 32 bit integer (0 when it is not a number)
local function u32Field(n)
	if type(n) ~= "number" or n ~= n then
		return 0
	end

	if n < 0 then
		return 0
	elseif n > 4294967295 then
		return 4294967295
	end

	return floor(n)
end

-- Encode(map, header) -> string | nil, reason. header = {bspSize, nodeCount, complete, overBudget}; the sample count comes from the map
function ZM.Encode(map, header)
	if type(map) ~= "table" or type(map.boxes) ~= "table" then
		return nil, "bad map"
	end

	header = type(header) == "table" and header or {}

	local boxes = map.boxes
	local nBoxes = #boxes
	local parts, nParts = {}, 0
	local buf, n = {}, 0
	local sum = 0

	local flags = (header.complete == true and FLAG_COMPLETE or 0) + (header.overBudget == true and FLAG_OVER_BUDGET or 0)
	local numbers = {u32Field(header.bspSize), u32Field(header.nodeCount), u32Field(map.sampleCount), nBoxes}

	buf[1], buf[2], buf[3], buf[4], buf[5], buf[6], buf[7], buf[8] = MAGIC1, MAGIC2, MAGIC3, MAGIC4, ZM.FORMAT_VERSION, flags, 0, 0
	n = 8

	for j = 1, 4 do
		local v = numbers[j]

		buf[n + 1], buf[n + 2], buf[n + 3], buf[n + 4] = v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216)
		n = n + 4
	end

	for i = 1, nBoxes do
		local b = boxes[i]

		if not boxFits(b) then
			return nil, "bad box " .. i
		end

		if n > BATCH - BOX_SIZE then
			for j = 1, n do
				sum = sum + buf[j]
			end

			nParts = nParts + 1
			parts[nParts] = schar(unpack(buf, 1, n))
			n = 0
		end

		local layer, x1, y1 = b.layer, b.x1, b.y1

		if layer < 0 then
			layer = layer + 65536
		end

		if x1 < 0 then
			x1 = x1 + 65536
		end

		if y1 < 0 then
			y1 = y1 + 65536
		end

		buf[n + 1], buf[n + 2] = layer % 256, floor(layer / 256)
		buf[n + 3], buf[n + 4] = x1 % 256, floor(x1 / 256)
		buf[n + 5], buf[n + 6] = y1 % 256, floor(y1 / 256)
		buf[n + 7], buf[n + 8] = b.x2 - b.x1, b.y2 - b.y1
		buf[n + 9] = (b.state == 2 and 1 or 0) + b.ceil * 2
		n = n + BOX_SIZE
	end

	for j = 1, n do
		sum = sum + buf[j]
	end

	nParts = nParts + 1
	parts[nParts] = schar(unpack(buf, 1, n))

	sum = sum % 4294967296
	nParts = nParts + 1
	parts[nParts] = schar(sum % 256, floor(sum / 256) % 256, floor(sum / 65536) % 256, floor(sum / 16777216))

	return concat(parts)
end

local function readU32(s, i)
	local a, b, c, d = byte(s, i, i + 3)

	return a + b * 256 + c * 65536 + d * 16777216
end

-- Decode(bytes) -> map, header | nil, reason. Strict: nothing is trusted, a bad file is refused with a reason
function ZM.Decode(bytes)
	if type(bytes) ~= "string" then
		return nil, "not a string"
	end

	local size = #bytes

	if size < HEADER_SIZE + CHECKSUM_SIZE then
		return nil, "too short"
	end

	local m1, m2, m3, m4 = byte(bytes, 1, 4)

	if m1 ~= MAGIC1 or m2 ~= MAGIC2 or m3 ~= MAGIC3 or m4 ~= MAGIC4 then
		return nil, "bad magic"
	end

	if byte(bytes, 5) ~= ZM.FORMAT_VERSION then
		return nil, "bad version"
	end

	local nBoxes = readU32(bytes, 21)

	if size ~= HEADER_SIZE + BOX_SIZE * nBoxes + CHECKSUM_SIZE then
		return nil, "bad size"
	end

	-- checksum: eight bytes at a time
	local body = size - CHECKSUM_SIZE
	local sum, i = 0, 1

	while i + 7 <= body do
		local a, b, c, d, e, f, g, h = byte(bytes, i, i + 7)

		sum = sum + a + b + c + d + e + f + g + h
		i = i + 8
	end

	while i <= body do
		sum = sum + byte(bytes, i)
		i = i + 1
	end

	if sum % 4294967296 ~= readU32(bytes, body + 1) then
		return nil, "bad checksum"
	end

	local flags, r1, r2 = byte(bytes, 6, 8)

	if r1 ~= 0 or r2 ~= 0 or flags >= 4 then
		return nil, "bad header"
	end

	local header = {
		bspSize = readU32(bytes, 9),
		nodeCount = readU32(bytes, 13),
		complete = flags % 2 == 1,
		overBudget = flags >= FLAG_OVER_BUDGET,
		sampleCount = readU32(bytes, 17)
	}

	local boxes, cells = {}, 0
	local o = HEADER_SIZE + 1

	for j = 1, nBoxes do
		local l1, l2, x1, x2, y1, y2, w, h, f = byte(bytes, o, o + 8)

		local layer = l1 + l2 * 256
		local cx = x1 + x2 * 256
		local cy = y1 + y2 * 256

		if layer >= 32768 then
			layer = layer - 65536
		end

		if cx >= 32768 then
			cx = cx - 65536
		end

		if cy >= 32768 then
			cy = cy - 65536
		end

		if f >= 16 or layer < -LAYER_BIAS or layer >= LAYER_BIAS or cx + w >= CELL_BIAS or cy + h >= CELL_BIAS then
			return nil, "bad box"
		end

		boxes[j] = {layer = layer, x1 = cx, y1 = cy, x2 = cx + w, y2 = cy + h, state = f % 2 + 1, ceil = floor(f / 2)}
		cells = cells + (w + 1) * (h + 1)
		o = o + BOX_SIZE
	end

	return {boxes = boxes, sampleCount = header.sampleCount, skipped = 0, cells = cells}, header
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Index and lookup
-- ---------------------------------------------------------------------------------------------------------------------------------
-- The index is a table with one entry per cell (value = state * 8 + ceil) and, under string keys, the area of the boxes: gx, gy (first cell), gW, gH (size
-- in cells), gl (first layer), gL (number of layers) and the cell count. The key of a cell is ((layer - gl) * gW + (cx - gx)) * gH + (cy - gy): one number,
-- exact, and two different cells of the area never share it (a lookup outside the area answers before it makes a key).

-- Index(map) -> index
function ZM.Index(map)
	local index = {count = 0, gx = 0, gy = 0, gW = 0, gH = 0, gl = 0, gL = 0}

	if type(map) ~= "table" or type(map.boxes) ~= "table" then
		return index
	end

	local boxes = map.boxes
	local nBoxes = #boxes
	local minX, maxX, minY, maxY, minL, maxL
	local any = false

	for i = 1, nBoxes do
		local b = boxes[i]

		if boxFits(b) then
			if not any then
				minX, maxX, minY, maxY, minL, maxL = b.x1, b.x2, b.y1, b.y2, b.layer, b.layer
				any = true
			else
				if b.x1 < minX then
					minX = b.x1
				end

				if b.x2 > maxX then
					maxX = b.x2
				end

				if b.y1 < minY then
					minY = b.y1
				end

				if b.y2 > maxY then
					maxY = b.y2
				end

				if b.layer < minL then
					minL = b.layer
				end

				if b.layer > maxL then
					maxL = b.layer
				end
			end
		end
	end

	if not any then
		return index
	end

	local gW, gH = maxX - minX + 1, maxY - minY + 1

	index.gx, index.gy, index.gW, index.gH, index.gl, index.gL = minX, minY, gW, gH, minL, maxL - minL + 1

	local count = 0

	for i = 1, nBoxes do
		local b = boxes[i]

		if boxFits(b) then
			local value = b.state * 8 + b.ceil
			local layerBase = (b.layer - minL) * gW - minX

			for cx = b.x1, b.x2 do
				local col = (layerBase + cx) * gH - minY

				for cy = b.y1, b.y2 do
					local k = col + cy

					if index[k] == nil then
						count = count + 1
					end

					index[k] = value
				end
			end
		end
	end

	index.count = count

	return index
end

-- Count(index) -> number of cells
function ZM.Count(index)
	if type(index) ~= "table" then
		return 0
	end

	return index.count or 0
end

-- Lookup(index, x, y, z) -> state, ceil (0, 0 when unknown or when a number is bad). The layer of the point, then the layer above and the one below (stairs).
-- No table, closure or engine call.
function ZM.Lookup(index, x, y, z)
	if type(index) ~= "table" or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return 0, 0
	end

	if x - x ~= 0 or y - y ~= 0 or z - z ~= 0 then
		return 0, 0
	end

	local gx = index.gx

	if not gx then
		return 0, 0
	end

	local gW, gH, gL = index.gW, index.gH, index.gL
	local dx, dy = floor(x * INV_CELL) - gx, floor(y * INV_CELL) - index.gy

	if dx < 0 or dx >= gW or dy < 0 or dy >= gH then
		return 0, 0
	end

	local ld = floor((z + LAYER_H / 2) * INV_LAYER) - index.gl
	local v

	if ld >= 0 and ld < gL then
		v = index[(ld * gW + dx) * gH + dy]
	end

	if not v and ld >= -1 and ld + 1 < gL then
		v = index[((ld + 1) * gW + dx) * gH + dy]
	end

	if not v and ld > 0 and ld - 1 < gL then
		v = index[((ld - 1) * gW + dx) * gH + dy]
	end

	if not v then
		return 0, 0
	end

	local state = v >= 16 and 2 or 1

	return state, v - state * 8
end

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Key
-- ---------------------------------------------------------------------------------------------------------------------------------

-- Key(map, bspSize, source) -> "<map>_<bspSize>_v1": lower case, every byte outside a-z 0-9 _ - . replaced by "_" (a non string or empty map gives "unknown", a bad size 0).
-- `source` is optional: "navmesh" (the map made from the nav areas) appends "_navmesh"; nil, "nodes" and anything else give the key of the node files, unchanged.
function ZM.Key(map, bspSize, source)
	if type(map) ~= "string" or map == "" then
		map = "unknown"
	end

	if type(bspSize) ~= "number" or bspSize - bspSize ~= 0 or bspSize < 0 then
		bspSize = 0
	end

	return string.gsub(string.lower(map), "[^a-z0-9_%-%.]", "_") .. "_" .. string.format("%d", floor(bspSize)) .. "_v" .. ZM.FORMAT_VERSION
		.. (source == "navmesh" and "_navmesh" or "")
end
