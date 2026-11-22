-- Tests of the in/out map (lua/grymod/sh_zonemap.lua, GryMod.ZoneMap), GLuaTest format, SHARED: the same file runs in the client realm and in the
-- server realm. The module is pure (no engine call), so everything here runs for real. Three things are written here independently of the module so that
-- a wrong module cannot hide behind a wrong test: a brute-force reference of the build steps 1 to 3 (strings as keys, scans over all the known cells), the
-- expansion of boxes into cells, and a byte encoder for the file format.
--
-- The design is docs/superpowers/specs/2026-11-22-zonemap-design.md (sections Model, Build, Lookup, File format).

local floor = math.floor

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------------------------------------

local function Z()
	local z = GryMod and GryMod.ZoneMap

	expect(z ~= nil).to.beTrue()
	expect(type(z.Build)).to.equal("function")

	return z
end

-- The test runner counts instructions with a debug hook (the time limit of a step), and a hook keeps LuaJIT from compiling: timings measured under it are
-- those of the interpreter, three to four times slower than the game. The measures of speed and of allocation therefore run with the hook taken off and
-- put back afterwards (also when the function fails); returns what the function returned.
local function unhooked(fn)
	local hook, mask, count = debug.gethook()

	debug.sethook()

	local results = {pcall(fn)}

	pcall(function()
		if hook then
			debug.sethook(hook, mask, count)
		end
	end)

	if not results[1] then
		error(results[2], 0)
	end

	return unpack(results, 2)
end

-- Park-Miller generator: deterministic and local, so the test never touches the game's random state (products stay under 2^53)
local function rng(seed)
	local s = seed

	return function(n)
		s = (s * 48271) % 2147483647

		return s % n
	end
end

-- a sample at the centre of the cell (cx, cy) of a layer
local function S(cx, cy, layer, indoor, ceil)
	return {x = cx * 128 + 64, y = cy * 128 + 64, z = layer * 128, indoor = indoor, ceil = ceil}
end

-- boxes -> get(layer, cx, cy) -> state, ceil, and the number of cells; an overlap is an error
local function expand(map)
	local cells, count = {}, 0

	for _, b in ipairs(map.boxes) do
		if b.x2 < b.x1 or b.y2 < b.y1 or b.x2 - b.x1 > 254 or b.y2 - b.y1 > 254 then
			error("bad box size")
		end

		for cx = b.x1, b.x2 do
			for cy = b.y1, b.y2 do
				local k = b.layer .. "," .. cx .. "," .. cy

				if cells[k] then
					error("boxes overlap at " .. k)
				end

				cells[k] = b.state * 8 + b.ceil
				count = count + 1
			end
		end
	end

	return function(layer, cx, cy)
		local v = cells[layer .. "," .. cx .. "," .. cy]

		if not v then
			return 0, 0
		end

		return floor(v / 8), v % 8
	end, count, cells
end

-- brute-force reference of the build steps 1 to 3: returns key -> state * 8 + class, and the number of cells
local R_SPREAD = 3

local function refBuild(samples)
	local raster = {}
	local order = {}

	for _, s in ipairs(samples) do
		local l, cx, cy = floor((s.z + 64) / 128), floor(s.x / 128), floor(s.y / 128)
		local k = l .. "," .. cx .. "," .. cy
		local c = raster[k]

		if not c then
			c = {l = l, cx = cx, cy = cy, indoor = 0, outdoor = 0, cls = {}}
			raster[k] = c
			order[#order + 1] = c
		end

		if s.indoor then
			c.indoor = c.indoor + 1
		else
			c.outdoor = c.outdoor + 1
		end

		c.cls[s.ceil] = (c.cls[s.ceil] or 0) + 1
	end

	local known = {}

	for _, c in ipairs(order) do
		local best, bestN = 0, -1

		for cls = 0, 7 do
			local n = c.cls[cls] or 0

			if n > bestN then
				best, bestN = cls, n
			end
		end

		c.state = c.indoor > c.outdoor and 2 or 1
		c.class = best
	end

	-- spread: for every cell of the squares around the known cells, the nearest known cell of the layer, a tie to the lowest (cx, cy)
	local cur = {}

	for _, c in ipairs(order) do
		cur[c.l .. "," .. c.cx .. "," .. c.cy] = c.state * 8 + c.class
	end

	local candidates = {}

	for _, c in ipairs(order) do
		for dx = -R_SPREAD, R_SPREAD do
			for dy = -R_SPREAD, R_SPREAD do
				local k = c.l .. "," .. (c.cx + dx) .. "," .. (c.cy + dy)

				if not raster[k] and not candidates[k] then
					candidates[k] = {l = c.l, cx = c.cx + dx, cy = c.cy + dy}
				end
			end
		end
	end

	for k, t in pairs(candidates) do
		local best, bestD

		for _, c in ipairs(order) do
			if c.l == t.l then
				local d = math.max(math.abs(c.cx - t.cx), math.abs(c.cy - t.cy))

				if d <= R_SPREAD and (not bestD or d < bestD or (d == bestD and (c.cx < best.cx or (c.cx == best.cx and c.cy < best.cy)))) then
					best, bestD = c, d
				end
			end
		end

		if best then
			cur[k] = best.state * 8 + best.class
		end
	end

	-- smoothing: simultaneous, on the cells of steps 1 and 2
	local flips = {}

	for k, v in pairs(cur) do
		local l, cx, cy = string.match(k, "^(-?%d+),(-?%d+),(-?%d+)$")

		l, cx, cy = tonumber(l), tonumber(cx), tonumber(cy)

		local state = floor(v / 8)
		local same, diff, perClass = 0, 0, {}
		local clsCount = {[1] = {}, [2] = {}}

		for dx = -1, 1 do
			for dy = -1, 1 do
				if dx ~= 0 or dy ~= 0 then
					local nv = cur[l .. "," .. (cx + dx) .. "," .. (cy + dy)]

					if nv then
						local ns = floor(nv / 8)

						if ns == state then
							same = same + 1
						else
							diff = diff + 1
						end

						clsCount[ns][nv % 8] = (clsCount[ns][nv % 8] or 0) + 1
					end
				end
			end
		end

		if diff >= 5 and same <= 1 then
			-- every neighbour of the other state is what the majority is (there are two states): the most common class among them
			local other = 3 - state
			local bestCls, bestN = 0, -1

			for cls = 0, 7 do
				local n = clsCount[other][cls] or 0

				if n > bestN then
					bestCls, bestN = cls, n
				end
			end

			flips[k] = other * 8 + bestCls
		end
	end

	local count = 0

	for k, v in pairs(flips) do
		cur[k] = v
	end

	for _ in pairs(cur) do
		count = count + 1
	end

	return cur, count
end

-- random samples over a w x h cells area on `layers` layers, the state depending on the position so that there are blobs and noise
local function randomSamples(seed, n, w, h, layers, noisy)
	local r = rng(seed)
	local out = {}

	for i = 1, n do
		local cx, cy = r(w), r(h)
		local layer = r(layers)
		local blob = (floor(cx / 6) + floor(cy / 6)) % 2 == 0
		local pIndoor = blob and 85 or 15

		if noisy then
			pIndoor = 50
		end

		out[i] = {
			x = cx * 128 + r(128),
			y = cy * 128 + r(128),
			z = layer * 128 + r(128) - 64,
			indoor = r(100) < pIndoor,
			ceil = r(8)
		}
	end

	return out
end

local function boxesEqual(a, b)
	if #a ~= #b then
		return false
	end

	for i = 1, #a do
		local p, q = a[i], b[i]

		if p.layer ~= q.layer or p.x1 ~= q.x1 or p.y1 ~= q.y1 or p.x2 ~= q.x2 or p.y2 ~= q.y2 or p.state ~= q.state or p.ceil ~= q.ceil then
			return false
		end
	end

	return true
end

-- byte encoders independent of the module
local function u32(n)
	n = n % 4294967296

	return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function u16(n)
	n = n % 65536

	return string.char(n % 256, floor(n / 256))
end

local function sumBytes(s)
	local t = 0

	for i = 1, #s do
		t = t + string.byte(s, i)
	end

	return t % 4294967296
end

-- recompute the checksum of a file whose body was edited (to reach the checks after the checksum)
local function fix(s)
	local body = string.sub(s, 1, #s - 4)

	return body .. u32(sumBytes(body))
end

local function replaceAt(s, pos, bytes)
	return string.sub(s, 1, pos - 1) .. bytes .. string.sub(s, pos + #bytes)
end

local function refused(zm, bytes, reason)
	local m, h = zm.Decode(bytes)

	expect(m).to.beNil()
	expect(type(h)).to.equal("string")

	if reason then
		expect(h).to.equal(reason)
	end
end

-- a small map with three boxes
local function smallMap()
	return {
		boxes = {
			{layer = -2, x1 = -300, y1 = 300, x2 = -298, y2 = 304, state = 2, ceil = 5},
			{layer = 7, x1 = 0, y1 = 0, x2 = 254, y2 = 0, state = 1, ceil = 0},
			{layer = 0, x1 = 10, y1 = -10, x2 = 10, y2 = -10, state = 2, ceil = 7}
		},
		sampleCount = 77, skipped = 0, cells = 15 + 255 + 1
	}
end

local SMALL_HEADER = {bspSize = 16909060, nodeCount = 410, complete = true, overBudget = false}

-- random boxes with every field in its valid range (they may overlap: only the file round trip uses them)
local function randomBoxes(seed, n)
	local r = rng(seed)
	local boxes = {}

	for i = 1, n do
		local w, h = 1 + r(255), 1 + r(255)
		local x1 = r(65536 - w + 1) - 32768
		local y1 = r(65536 - h + 1) - 32768

		boxes[i] = {layer = r(8192) - 4096, x1 = x1, y1 = y1, x2 = x1 + w - 1, y2 = y1 + h - 1, state = 1 + r(2), ceil = r(8)}
	end

	return boxes
end

-- the box of the list that holds the cell, nil when none (brute force over the boxes)
local function boxAt(boxes, layer, cx, cy)
	for _, b in ipairs(boxes) do
		if b.layer == layer and cx >= b.x1 and cx <= b.x2 and cy >= b.y1 and cy <= b.y2 then
			return b
		end
	end
end

-- reference of Lookup over the boxes: own layer, then +1, then -1
local function refLookup(boxes, x, y, z)
	local layer, cx, cy = floor((z + 64) / 128), floor(x / 128), floor(y / 128)

	for _, l in ipairs({layer, layer + 1, layer - 1}) do
		local b = boxAt(boxes, l, cx, cy)

		if b then
			return b.state, b.ceil
		end
	end

	return 0, 0
end

return {
	groupName = "GryMod zone map (shared)",
	cases = {
		{
			-- fails if a constant of the design changes
			name = "constants match the design",
			func = function()
				local z = Z()

				expect(z.CELL).to.equal(128)
				expect(z.LAYER_H).to.equal(128)
				expect(z.RADIUS).to.equal(3)
				expect(z.MAX_BOX).to.equal(255)
				expect(z.FORMAT_VERSION).to.equal(1)
				expect(#z.CLASSES).to.equal(7)

				local want = {56, 88, 120, 160, 224, 320, 448}

				for i = 1, 7 do
					expect(z.CLASSES[i]).to.equal(want[i])
				end
			end
		},
		{
			-- fails if the class is not the biggest one <= room - 8, if 56 is not the floor, or if a non number is not 1
			name = "CeilIndex: boundaries of the classes (room - 8), 1 at least, a non number gives 1",
			func = function()
				local z = Z()
				local cases = {
					{-5, 1}, {0, 1}, {63, 1}, {63.9, 1}, {64, 1}, {95, 1}, {96, 2}, {127, 2}, {128, 3}, {167, 3}, {168, 4}, {231, 4}, {232, 5}, {327, 5},
					{328, 6}, {455, 6}, {456, 7}, {1000, 7}, {math.huge, 7}, {-math.huge, 1}
				}

				for _, c in ipairs(cases) do
					expect(z.CeilIndex(c[1])).to.equal(c[2])
				end

				expect(z.CeilIndex(nil)).to.equal(1)
				expect(z.CeilIndex("300")).to.equal(1)
				expect(z.CeilIndex({})).to.equal(1)
				expect(z.CeilIndex(0 / 0)).to.equal(1)
			end
		},
		{
			-- fails if the layer or the cell is computed with another offset or rounds toward zero
			name = "Layer and CellOf: floor((z + 64) / 128) and floor(x / 128), negative values included",
			func = function()
				local z = Z()

				expect(z.Layer(0)).to.equal(0)
				expect(z.Layer(63.9)).to.equal(0)
				expect(z.Layer(64)).to.equal(1)
				expect(z.Layer(-64)).to.equal(0)
				expect(z.Layer(-64.1)).to.equal(-1)
				expect(z.Layer(300)).to.equal(2)
				expect(z.CellOf(0)).to.equal(0)
				expect(z.CellOf(127.9)).to.equal(0)
				expect(z.CellOf(128)).to.equal(1)
				expect(z.CellOf(-0.1)).to.equal(-1)
				expect(z.CellOf(-128)).to.equal(-1)
				expect(z.CellOf(-128.1)).to.equal(-2)
			end
		},
		{
			-- fails if the spread radius is not 3 cells (Chebyshev), if the cell or its box is wrong, if the sample is not counted
			name = "Build: one sample gives its cell and the spread over RADIUS cells in a square, nothing beyond",
			func = function()
				local m = Z().Build({S(5, 5, 0, true, 3)})

				expect(m.sampleCount).to.equal(1)
				expect(m.skipped).to.equal(0)
				expect(m.cells).to.equal(49)
				expect(#m.boxes).to.equal(1)

				local b = m.boxes[1]

				expect(b.layer).to.equal(0)
				expect(b.x1).to.equal(2)
				expect(b.y1).to.equal(2)
				expect(b.x2).to.equal(8)
				expect(b.y2).to.equal(8)
				expect(b.state).to.equal(2)
				expect(b.ceil).to.equal(3)
			end
		},
		{
			-- fails if the cell is taken with a rounding toward zero (the sample at x = -64 is in the cell -1) or if the layer offset is wrong
			name = "Build: negative coordinates and the layer of a z below zero",
			func = function()
				local m = Z().Build({{x = -64, y = -1, z = -100, indoor = false, ceil = 0}})

				expect(#m.boxes).to.equal(1)

				local b = m.boxes[1]

				expect(b.layer).to.equal(-1)
				expect(b.x1).to.equal(-4)
				expect(b.x2).to.equal(2)
				expect(b.y1).to.equal(-4)
				expect(b.y2).to.equal(2)
				expect(b.state).to.equal(1)
			end
		},
		{
			-- fails if a bad sample is used, if skipped is not counted, if a good sample is refused
			name = "Build: non finite numbers, a ceiling class out of 0..7, a missing indoor, a non table are skipped and counted",
			func = function()
				local nan, inf = 0 / 0, math.huge
				local samples = {
					S(0, 0, 0, true, 2),
					{x = nan, y = 0, z = 0, indoor = true, ceil = 1},
					{x = 0, y = inf, z = 0, indoor = true, ceil = 1},
					{x = 0, y = 0, z = -inf, indoor = true, ceil = 1},
					{x = 0, y = 0, z = 0, indoor = true, ceil = 8},
					{x = 0, y = 0, z = 0, indoor = true, ceil = -1},
					{x = 0, y = 0, z = 0, indoor = true, ceil = 1.5},
					{x = 0, y = 0, z = 0, indoor = true},
					{x = 0, y = 0, z = 0, ceil = 1},
					{x = "5", y = 0, z = 0, indoor = true, ceil = 1},
					{x = 0, y = 0, z = 0, indoor = true, ceil = "3"},
					{x = 1e12, y = 0, z = 0, indoor = true, ceil = 1},
					5
				}
				local m = Z().Build(samples)

				expect(m.sampleCount).to.equal(1)
				expect(m.skipped).to.equal(12)
				expect(#m.boxes).to.equal(1)
				expect(m.cells).to.equal(49)
			end
		},
		{
			-- fails if Build raises on an empty or missing list
			name = "Build: an empty list or no list gives an empty map",
			func = function()
				local z = Z()

				for _, input in ipairs({{}, "x", false}) do
					local m = z.Build(input)

					expect(#m.boxes).to.equal(0)
					expect(m.sampleCount).to.equal(0)
					expect(m.cells).to.equal(0)
				end

				local m = z.Build(nil)

				expect(#m.boxes).to.equal(0)
			end
		},
		{
			-- fails if two far apart samples are merged, if a state is wrong or if the boxes are not in the scan order (cy, cx)
			name = "Build: two samples of different state far apart give two boxes of their own state",
			func = function()
				local m = Z().Build({S(20, 0, 0, false, 0), S(0, 0, 0, true, 2)})

				expect(#m.boxes).to.equal(2)
				expect(m.cells).to.equal(98)

				local a, b = m.boxes[1], m.boxes[2]

				expect(a.x1).to.equal(-3)
				expect(a.x2).to.equal(3)
				expect(a.state).to.equal(2)
				expect(a.ceil).to.equal(2)
				expect(b.x1).to.equal(17)
				expect(b.x2).to.equal(23)
				expect(b.state).to.equal(1)
				expect(b.ceil).to.equal(0)
			end
		},
		{
			-- fails if the layers are mixed: a cell of another layer used by the spread, or the same cell of two layers merged
			name = "Build: two layers (z = 0 and z = 300) stay separate, and the spread never crosses layers",
			func = function()
				local z = Z()
				local m = z.Build({{x = 64, y = 64, z = 0, indoor = true, ceil = 2}, {x = 64, y = 64, z = 300, indoor = false, ceil = 5}})
				local get, count = expand(m)

				expect(count).to.equal(98)
				expect(#m.boxes).to.equal(2)

				local s0, c0 = get(0, 0, 0)
				local s2, c2 = get(2, 0, 0)

				expect(s0).to.equal(2)
				expect(c0).to.equal(2)
				expect(s2).to.equal(1)
				expect(c2).to.equal(5)
				expect(get(1, 0, 0)).to.equal(0)

				-- adjacent cells on layers 0 and 1: nothing of one layer shows in the other
				local m2 = z.Build({S(0, 0, 0, true, 1), S(1, 0, 1, false, 2)})
				local get2 = expand(m2)

				expect(get2(0, 1, 0)).to.equal(2)
				expect(get2(0, 4, 0)).to.equal(0)
				expect(get2(1, -3, 0)).to.equal(0)
				expect(get2(1, 0, 0)).to.equal(1)
				expect(select(2, expand(m2))).to.equal(98)
			end
		},
		{
			-- fails if the nearest known cell is not used, if a tie does not go to the first cell in (layer, cx, cy) order, if the spread chains
			name = "Build: the spread takes the nearest known cell (Chebyshev), a tie goes to the lowest cx then cy, no chaining",
			func = function()
				local m = Z().Build({S(0, 0, 0, true, 1), S(4, 0, 0, false, 2)})
				local get = expand(m)

				-- on the line between them
				expect(get(0, 1, 0)).to.equal(2)
				expect(get(0, 2, 0)).to.equal(2) -- tie (2 and 2): the lower cx, indoor
				expect(select(2, get(0, 2, 0))).to.equal(1)
				expect(get(0, 3, 0)).to.equal(1)
				expect(select(2, get(0, 3, 0))).to.equal(2)
				expect(get(0, 2, 2)).to.equal(2) -- tie: distance 2 and 2
				expect(get(0, 3, 3)).to.equal(2) -- tie: distance 3 and 3
				-- farther than RADIUS of both: unknown
				expect(get(0, 2, 4)).to.equal(0)
				expect(get(0, 4, 4)).to.equal(0)
				expect(get(0, 0, 4)).to.equal(0)
				expect(get(0, -4, 0)).to.equal(0)
				expect(get(0, 8, 0)).to.equal(0)
				expect(get(0, 7, 0)).to.equal(1)
			end
		},
		{
			-- fails if the state is not the majority of the votes, if a tie is not outdoor, if the class is not the most common (tie: the lower)
			name = "Build: a cell takes the majority state (tie: outdoor) and the most common class (tie: the lower)",
			func = function()
				local z = Z()
				local function samples(list)
					local out = {}

					for i, v in ipairs(list) do
						out[i] = {x = 10 + i * 20, y = 100, z = 5, indoor = v[1], ceil = v[2]}
					end

					return out
				end

				local m = z.Build(samples({{true, 5}, {true, 5}, {false, 2}}))

				expect(#m.boxes).to.equal(1)
				expect(m.boxes[1].state).to.equal(2)
				expect(m.boxes[1].ceil).to.equal(5)

				m = z.Build(samples({{true, 6}, {false, 3}}))
				expect(m.boxes[1].state).to.equal(1) -- 1 against 1: outdoor
				expect(m.boxes[1].ceil).to.equal(3) -- 6 against 3: the lower

				m = z.Build(samples({{true, 4}, {false, 4}, {false, 7}, {true, 7}, {false, 7}}))
				expect(m.boxes[1].state).to.equal(1) -- 2 against 3
				expect(m.boxes[1].ceil).to.equal(7) -- 4 twice, 7 three times

				expect(m.sampleCount).to.equal(5)
			end
		},
		{
			-- fails if the smoothing is missing, if it keeps the class of the flipped cell, or if it flips more or less than the isolated cell
			name = "Build: the smoothing flips an isolated indoor cell inside an outdoor area and gives it the class of its neighbours",
			func = function()
				local samples = {}

				for cx = 0, 2 do
					for cy = 0, 2 do
						if cx == 1 and cy == 1 then
							samples[#samples + 1] = S(cx, cy, 0, true, 1)
						else
							samples[#samples + 1] = S(cx, cy, 0, false, 4)
						end
					end
				end

				local m = Z().Build(samples)

				expect(#m.boxes).to.equal(1)

				local b = m.boxes[1]

				expect(b.x1).to.equal(-3)
				expect(b.x2).to.equal(5)
				expect(b.y1).to.equal(-3)
				expect(b.y2).to.equal(5)
				expect(b.state).to.equal(1)
				expect(b.ceil).to.equal(4)
				expect(m.cells).to.equal(81)
			end
		},
		{
			-- fails if the smoothing rule "all the neighbours but at most one" is loosened: a real wall (2 cells thick) has to stay
			name = "Build: the smoothing keeps a real wall two cells thick (and flips a domino of two cells, as the rule says)",
			func = function()
				local z = Z()
				local samples = {}

				for cx = 0, 7 do
					for cy = 0, 7 do
						local wall = (cx == 3 or cx == 4) and cy >= 1 and cy <= 6

						samples[#samples + 1] = S(cx, cy, 0, wall, wall and 3 or 0)
					end
				end

				local m = z.Build(samples)
				local get = expand(m)

				for cx = 3, 4 do
					for cy = 1, 6 do
						expect(get(0, cx, cy)).to.equal(2)
						expect(select(2, get(0, cx, cy))).to.equal(3)
					end
				end

				expect(get(0, 2, 3)).to.equal(1)
				expect(get(0, 5, 3)).to.equal(1)

				-- a domino: each cell has one neighbour of its own state and seven of the other: flips (design: at most one equal neighbour)
				samples = {}

				for cx = 0, 7 do
					for cy = 0, 7 do
						local domino = (cx == 3 or cx == 4) and cy == 3

						samples[#samples + 1] = S(cx, cy, 0, domino, 2)
					end
				end

				m = z.Build(samples)
				get = expand(m)
				expect(get(0, 3, 3)).to.equal(1)
				expect(get(0, 4, 3)).to.equal(1)
				expect(#m.boxes).to.equal(1)
			end
		},
		{
			-- fails if a flip makes the next cell see a changed neighbour (not simultaneous), or if cells farther than the flip's reach change
			name = "Build: a line of three indoor cells (one cell thick) is not an isolated cell: only its ends are compared with the rule",
			func = function()
				local samples = {}

				for cx = 0, 7 do
					for cy = 0, 7 do
						local line = cy == 3 and cx >= 2 and cx <= 4

						samples[#samples + 1] = S(cx, cy, 0, line, 1)
					end
				end

				local get = expand(Z().Build(samples))

				-- each end cell has 1 neighbour of its state (the middle one) and 7 of the other: flips; the middle one has 2 equal ones: stays
				expect(get(0, 2, 3)).to.equal(1)
				expect(get(0, 4, 3)).to.equal(1)
				expect(get(0, 3, 3)).to.equal(2)
			end
		},
		{
			-- fails if equal cells are not merged into one rectangle
			name = "Build: a long corridor of equal cells makes ONE box",
			func = function()
				local samples = {}

				for cx = 0, 39 do
					samples[#samples + 1] = S(cx, 0, 0, true, 2)
				end

				local m = Z().Build(samples)

				expect(#m.boxes).to.equal(1)

				local b = m.boxes[1]

				expect(b.x1).to.equal(-3)
				expect(b.x2).to.equal(42)
				expect(b.y1).to.equal(-3)
				expect(b.y2).to.equal(3)
				expect(m.cells).to.equal(46 * 7)
			end
		},
		{
			-- fails if cells with another class are merged
			name = "Build: cells of the same state but another class are not merged",
			func = function()
				local m = Z().Build({S(0, 0, 0, true, 2), S(1, 0, 0, true, 3)})
				local get, count = expand(m)

				expect(#m.boxes > 1).to.beTrue()
				expect(select(2, get(0, 0, 0))).to.equal(2)
				expect(select(2, get(0, 1, 0))).to.equal(3)
				expect(count).to.equal(m.cells)
			end
		},
		{
			-- fails if a box is wider or taller than 255, or if the cut loses cells
			name = "Build: boxes wider or taller than 255 cells are cut",
			func = function()
				local z = Z()
				local samples = {}

				for cx = 0, 599 do
					samples[#samples + 1] = S(cx, 0, 0, true, 2)
				end

				local m = z.Build(samples)

				expect(#m.boxes).to.equal(3)
				expect(m.boxes[1].x2 - m.boxes[1].x1 + 1).to.equal(255)
				expect(m.boxes[2].x2 - m.boxes[2].x1 + 1).to.equal(255)
				expect(m.boxes[3].x2 - m.boxes[3].x1 + 1).to.equal(96)
				expect(m.cells).to.equal(606 * 7)
				expect(select(2, expand(m))).to.equal(606 * 7)

				samples = {}

				for cy = 0, 299 do
					samples[#samples + 1] = S(0, cy, 0, true, 2)
				end

				m = z.Build(samples)
				expect(#m.boxes).to.equal(2)
				expect(m.boxes[1].y2 - m.boxes[1].y1 + 1).to.equal(255)
				expect(m.boxes[2].y2 - m.boxes[2].y1 + 1).to.equal(51)
				expect(m.cells).to.equal(306 * 7)
			end
		},
		{
			-- fails if the raster, the spread (nearest, ties), the smoothing (simultaneous, classes) or the boxes differ from the reference
			name = "Build: the cells equal a brute-force reference on random maps (blobs and noise, several layers)",
			func = function()
				local z = Z()

				for seed = 1, 8 do
					local noisy = seed > 4
					local samples = randomSamples(seed * 977, 150 + seed * 40, 24, 24, 3, noisy)
					local want, wantCount = refBuild(samples)
					local m = z.Build(samples)
					local get, count, cells = expand(m)

					expect(count).to.equal(wantCount)
					expect(m.cells).to.equal(wantCount)

					for k, v in pairs(want) do
						if cells[k] ~= v then
							error("seed " .. seed .. ": cell " .. k .. " is " .. tostring(cells[k]) .. ", the reference says " .. v)
						end
					end
				end
			end
		},
		{
			-- fails if the result depends on the order of the samples (a table iteration order, a first sample winning a tie...)
			name = "Build: determinism, the same samples shuffled give the same boxes",
			func = function()
				local z = Z()
				local samples = randomSamples(4242, 600, 20, 20, 2, true)
				local m1 = z.Build(samples)
				local r = rng(99)

				for round = 1, 3 do
					local shuffled = {}

					for i = 1, #samples do
						shuffled[i] = samples[i]
					end

					for i = #shuffled, 2, -1 do
						local j = 1 + r(i)

						shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
					end

					local m2 = z.Build(shuffled)

					expect(boxesEqual(m1.boxes, m2.boxes)).to.beTrue()
					expect(m2.cells).to.equal(m1.cells)
					expect(m2.sampleCount).to.equal(m1.sampleCount)
				end
			end
		},
		{
			-- fails if the compact keys of Build overflow or collide on the widest area (cells -32000..32000, layers -4000..4000), where a column is 64000 cells high
			name = "Build: samples at the extreme corners of the accepted area equal the reference (and nothing beyond is accepted)",
			func = function()
				local z = Z()
				local samples = {
					S(-32000, -32000, -4000, true, 1), S(32000, 32000, 4000, false, 2), S(32000, -32000, 0, true, 3), S(-32000, 32000, 4000, true, 4),
					S(-31999, -32000, -4000, true, 1), S(0, 0, 0, false, 5), S(31999, 32000, 4000, false, 2),
					S(32001, 0, 0, true, 1), S(0, -32001, 0, true, 1), S(0, 0, 4001, true, 1), S(0, 0, -4001, true, 1)
				}
				local want, wantCount = refBuild({unpack(samples, 1, 7)})
				local m = z.Build(samples)
				local _, count, cells = expand(m)

				expect(m.sampleCount).to.equal(7)
				expect(m.skipped).to.equal(4)
				expect(count).to.equal(wantCount)

				for k, v in pairs(want) do
					if cells[k] ~= v then
						error("cell " .. k .. " is " .. tostring(cells[k]) .. ", the reference says " .. v)
					end
				end

				-- the file and the index take the extreme boxes too
				local back = z.Decode(z.Encode(m, SMALL_HEADER))

				expect(back ~= nil).to.beTrue()
				expect(boxesEqual(m.boxes, back.boxes)).to.beTrue()
				expect(z.Count(z.Index(m))).to.equal(m.cells)
			end
		},
		{
			-- fails if the input table is changed by Build
			name = "Build: does not change its input",
			func = function()
				local samples = randomSamples(7, 50, 10, 10, 1, false)
				local copy = {}

				for i, s in ipairs(samples) do
					copy[i] = {x = s.x, y = s.y, z = s.z, indoor = s.indoor, ceil = s.ceil}
				end

				Z().Build(samples)
				expect(#samples).to.equal(#copy)

				for i, s in ipairs(samples) do
					expect(s.x).to.equal(copy[i].x)
					expect(s.indoor).to.equal(copy[i].indoor)
					expect(s.ceil).to.equal(copy[i].ceil)
				end
			end
		},
		{
			-- fails if the bytes of the format are not exactly the ones of the design
			name = "Encode: the exact bytes of a known map (header 24, box 9, checksum 4, little endian)",
			func = function()
				local z = Z()
				local m = smallMap()
				local s = z.Encode(m, SMALL_HEADER)

				expect(type(s)).to.equal("string")

				local want = "GZM1" .. string.char(1, 1, 0, 0) .. u32(16909060) .. u32(410) .. u32(77) .. u32(3)
					.. u16(-2) .. u16(-300) .. u16(300) .. string.char(2, 4, 1 + 5 * 2)
					.. u16(7) .. u16(0) .. u16(0) .. string.char(254, 0, 0)
					.. u16(0) .. u16(10) .. u16(-10) .. string.char(0, 0, 1 + 7 * 2)

				want = want .. u32(sumBytes(want))

				expect(#s).to.equal(24 + 9 * 3 + 4)
				expect(s).to.equal(want)

				-- flags: bit 0 complete, bit 1 over budget
				for _, c in ipairs({{false, false, 0}, {true, false, 1}, {false, true, 2}, {true, true, 3}}) do
					local t = z.Encode(m, {bspSize = 0, nodeCount = 0, complete = c[1], overBudget = c[2]})

					expect(string.byte(t, 6)).to.equal(c[3])
				end
			end
		},
		{
			-- fails if Encode raises or writes an invalid file for an empty map or a missing header
			name = "Encode: an empty map and a missing header give a valid 28 byte file",
			func = function()
				local z = Z()
				local s = z.Encode({boxes = {}, sampleCount = 0, skipped = 0, cells = 0})

				expect(#s).to.equal(28)

				local m, h = z.Decode(s)

				expect(m ~= nil).to.beTrue()
				expect(#m.boxes).to.equal(0)
				expect(h.bspSize).to.equal(0)
				expect(h.nodeCount).to.equal(0)
				expect(h.complete).to.beFalse()
				expect(h.overBudget).to.beFalse()
			end
		},
		{
			-- fails if a field of the box that does not fit in the file is written anyway (the file would be refused when read)
			name = "Encode: refuses a box that does not fit in the format, with a reason",
			func = function()
				local z = Z()
				local bad = {
					{layer = 4096, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 1, ceil = 0},
					{layer = 0, x1 = 0, y1 = 0, x2 = 255, y2 = 0, state = 1, ceil = 0},
					{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 255, state = 1, ceil = 0},
					{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 3, ceil = 0},
					{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 1, ceil = 8},
					{layer = 0, x1 = 5, y1 = 0, x2 = 4, y2 = 0, state = 1, ceil = 0},
					{layer = 0, x1 = 32767, y1 = 0, x2 = 32768, y2 = 0, state = 1, ceil = 0},
					{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 1, ceil = 1.5},
					{layer = 0.5, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 1, ceil = 1}
				}

				for i, b in ipairs(bad) do
					local s, err = z.Encode({boxes = {b}, sampleCount = 1}, SMALL_HEADER)

					expect(s).to.beNil()
					expect(type(err)).to.equal("string")
				end

				local s, err = z.Encode(nil, SMALL_HEADER)

				expect(s).to.beNil()
				expect(type(err)).to.equal("string")
			end
		},
		{
			-- fails if any field is lost or changed by the round trip of a map of several thousand boxes
			name = "Encode / Decode: round trip of random boxes (several thousand), every field kept",
			func = function()
				local z = Z()
				local boxes = randomBoxes(31337, 6000)
				local cells = 0

				for _, b in ipairs(boxes) do
					cells = cells + (b.x2 - b.x1 + 1) * (b.y2 - b.y1 + 1)
				end

				local header = {bspSize = 4000000001, nodeCount = 4629, complete = false, overBudget = true}
				local s = z.Encode({boxes = boxes, sampleCount = 4321, skipped = 3, cells = cells}, header)

				expect(#s).to.equal(24 + 9 * 6000 + 4)

				local m, h = z.Decode(s)

				expect(m ~= nil).to.beTrue()
				expect(boxesEqual(boxes, m.boxes)).to.beTrue()
				expect(m.sampleCount).to.equal(4321)
				expect(m.skipped).to.equal(0)
				expect(m.cells).to.equal(cells)
				expect(h.bspSize).to.equal(4000000001)
				expect(h.nodeCount).to.equal(4629)
				expect(h.complete).to.beFalse()
				expect(h.overBudget).to.beTrue()
				expect(h.sampleCount).to.equal(4321)

				-- and the same for a map made by Build
				local built = z.Build(randomSamples(555, 1200, 40, 40, 3, false))
				local t = z.Encode(built, {bspSize = 123456, nodeCount = 1200, complete = true, overBudget = false})
				local m2, h2 = z.Decode(t)

				expect(m2 ~= nil).to.beTrue()
				expect(boxesEqual(built.boxes, m2.boxes)).to.beTrue()
				expect(m2.cells).to.equal(built.cells)
				expect(h2.complete).to.beTrue()
				expect(h2.overBudget).to.beFalse()
				expect(h2.sampleCount).to.equal(built.sampleCount)
			end
		},
		{
			-- fails if a short file, whatever its length, is accepted or raises
			name = "Decode: every length from 0 to the full size minus one is refused",
			func = function()
				local z = Z()
				local s = z.Encode(smallMap(), SMALL_HEADER)

				for n = 0, #s - 1 do
					refused(z, string.sub(s, 1, n))
				end

				expect(z.Decode(s) ~= nil).to.beTrue()
			end
		},
		{
			-- fails if a changed byte, anywhere, is accepted
			name = "Decode: every byte flipped, one by one, is refused",
			func = function()
				local z = Z()
				local s = z.Encode(smallMap(), SMALL_HEADER)

				for i = 1, #s do
					for _, mask in ipairs({1, 128, 255}) do
						local b = string.byte(s, i)
						local flipped = bit.bxor(b, mask)
						local t = string.sub(s, 1, i - 1) .. string.char(flipped) .. string.sub(s, i + 1)

						refused(z, t)
					end
				end
			end
		},
		{
			-- fails if a reason is wrong or a check missing
			name = "Decode: the reasons (not a string, too short, bad magic, bad version, bad size, bad checksum, trailing bytes)",
			func = function()
				local z = Z()
				local s = z.Encode(smallMap(), SMALL_HEADER)

				refused(z, nil, "not a string")
				refused(z, 5, "not a string")
				refused(z, {}, "not a string")
				refused(z, "", "too short")
				refused(z, string.sub(s, 1, 27), "too short")
				refused(z, fix(replaceAt(s, 1, "GZM2")), "bad magic")
				refused(z, fix(replaceAt(s, 1, "gzm1")), "bad magic")
				refused(z, fix(replaceAt(s, 5, string.char(2))), "bad version")
				refused(z, fix(replaceAt(s, 5, string.char(0))), "bad version")
				-- a box count of 4 for 3 boxes, then 2: the size is not 24 + 9 B + 4
				refused(z, fix(replaceAt(s, 21, u32(4))), "bad size")
				refused(z, fix(replaceAt(s, 21, u32(2))), "bad size")
				refused(z, fix(replaceAt(s, 21, u32(4294967295))), "bad size")
				refused(z, s .. "x", "bad size")
				refused(z, s .. string.rep("\0", 9), "bad size")
				refused(z, string.sub(s, 1, #s - 1), "bad size")
				-- a wrong checksum: the last 4 bytes, and the same body with its checksum of another file
				refused(z, string.sub(s, 1, #s - 4) .. u32(sumBytes(string.sub(s, 1, #s - 4)) + 1), "bad checksum")
				refused(z, string.sub(s, 1, #s - 4) .. u32(0), "bad checksum")
				-- a body change that the checksum sees (the box count and the size are right)
				refused(z, replaceAt(s, 30, string.char(99)), "bad checksum")
			end
		},
		{
			-- fails if a file with a good checksum but an invalid content is accepted
			name = "Decode: invalid content behind a good checksum is refused (reserved bytes, unknown flags, box out of range)",
			func = function()
				local z = Z()
				local s = z.Encode(smallMap(), SMALL_HEADER)

				-- reserved bytes
				refused(z, fix(replaceAt(s, 7, string.char(1))), "bad header")
				refused(z, fix(replaceAt(s, 8, string.char(1))), "bad header")
				-- unknown flag bits
				refused(z, fix(replaceAt(s, 6, string.char(5))), "bad header")
				refused(z, fix(replaceAt(s, 6, string.char(128))), "bad header")
				-- the first box: flags at offset 24 + 9 = 33 (1-based)
				refused(z, fix(replaceAt(s, 33, string.char(16))), "bad box")
				refused(z, fix(replaceAt(s, 33, string.char(255))), "bad box")
				-- layer 4096 (int16) and layer -4097
				refused(z, fix(replaceAt(s, 25, u16(4096))), "bad box")
				refused(z, fix(replaceAt(s, 25, u16(-4097))), "bad box")
				-- x1 = 32700 with a width of 255 reaches over 32767
				refused(z, fix(replaceAt(s, 27, u16(32700) .. u16(0) .. string.char(254))), "bad box")
				refused(z, fix(replaceAt(s, 29, u16(32767) .. string.char(0, 1))), "bad box")
				-- an edit that stays valid is accepted (the test itself works)
				expect(z.Decode(fix(replaceAt(s, 33, string.char(3)))) ~= nil).to.beTrue()
			end
		},
		{
			-- fails if the corner cases of the coordinates are lost in the file
			name = "Decode: the extreme valid boxes are accepted (layer -4096 and 4095, cells at -32768 and 32767)",
			func = function()
				local z = Z()
				local boxes = {
					{layer = -4096, x1 = -32768, y1 = -32768, x2 = -32514, y2 = -32768, state = 1, ceil = 0},
					{layer = 4095, x1 = 32767, y1 = 32767, x2 = 32767, y2 = 32767, state = 2, ceil = 7}
				}
				local m = z.Decode(z.Encode({boxes = boxes, sampleCount = 2}, SMALL_HEADER))

				expect(m ~= nil).to.beTrue()
				expect(boxesEqual(boxes, m.boxes)).to.beTrue()
				expect(m.cells).to.equal(256)
			end
		},
		{
			-- fails if the index has a cell wrong, a cell missing, or if Count is not the number of cells
			name = "Index / Lookup: equal to a brute force over the boxes on random points (inside, outside, other layers)",
			func = function()
				local z = Z()
				local map = z.Build(randomSamples(2024, 500, 30, 30, 3, false))
				local index = z.Index(map)
				local r = rng(8)

				expect(z.Count(index)).to.equal(map.cells)

				for i = 1, 6000 do
					local x = r(36 * 128) - 3 * 128 + r(100) / 100
					local y = r(36 * 128) - 3 * 128
					local zz = r(700) - 100
					local ws, wc = refLookup(map.boxes, x, y, zz)
					local gs, gc = z.Lookup(index, x, y, zz)

					if gs ~= ws or gc ~= wc then
						error("point " .. x .. " " .. y .. " " .. zz .. ": got " .. gs .. "," .. gc .. " expected " .. ws .. "," .. wc)
					end
				end
			end
		},
		{
			-- fails if a cell is wrong on the exact edges of a box (the lookup uses floor on negatives and the boundary at a multiple of 128)
			name = "Lookup: the edges of the cells (multiples of 128, negative coordinates, z at the layer boundary)",
			func = function()
				local z = Z()
				local index = z.Index({boxes = {{layer = 0, x1 = -1, y1 = -1, x2 = 0, y2 = 0, state = 2, ceil = 4}}})

				expect(z.Count(index)).to.equal(4)

				local function at(x, y, zz)
					return z.Lookup(index, x, y, zz)
				end

				expect(at(0, 0, 0)).to.equal(2)
				expect(at(127.99, 127.99, 63.99)).to.equal(2)
				expect(at(128, 0, 0)).to.equal(0)
				expect(at(0, 128, 0)).to.equal(0)
				expect(at(-0.01, -0.01, 0)).to.equal(2)
				expect(at(-128, -128, 0)).to.equal(2)
				expect(at(-128.01, 0, 0)).to.equal(0)
				expect(at(0, 0, -64)).to.equal(2)
				-- z = 64 is layer 1: the stairs rule finds layer 0 (layer - 1)
				expect(at(0, 0, 64)).to.equal(2)
				-- layer 2 is two layers away: unknown
				expect(at(0, 0, 192)).to.equal(0)
				expect(select(2, z.Lookup(index, 0, 0, 0))).to.equal(4)
			end
		},
		{
			-- fails if the layers +1 / -1 are not looked at when the cell of the layer is unknown, or if the own layer does not win, or the order changes
			name = "Lookup: the stairs rule, own layer first, then layer + 1, then layer - 1",
			func = function()
				local z = Z()
				local map = {boxes = {
					{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 2, ceil = 3},
					{layer = 2, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 1, ceil = 5},
					{layer = 5, x1 = 10, y1 = 10, x2 = 10, y2 = 10, state = 2, ceil = 1},
					{layer = 3, x1 = 20, y1 = 20, x2 = 20, y2 = 20, state = 1, ceil = 2}
				}}
				local index = z.Index(map)
				local function at(x, y, layer)
					return z.Lookup(index, x * 128 + 64, y * 128 + 64, layer * 128)
				end

				-- layer 1 is unknown at (0, 0): the layer above (2) wins over the layer below (0)
				local s, c = at(0, 0, 1)

				expect(s).to.equal(1)
				expect(c).to.equal(5)
				-- own layer wins
				s, c = at(0, 0, 0)
				expect(s).to.equal(2)
				expect(c).to.equal(3)
				s, c = at(0, 0, 2)
				expect(s).to.equal(1)
				expect(c).to.equal(5)
				-- only the layer below known (layer 4 asks, layer 5 holds the cell above... and the cell (10, 10) of layer 5 is found from 4 and 6)
				expect(at(10, 10, 4)).to.equal(2)
				expect(at(10, 10, 6)).to.equal(2)
				expect(at(10, 10, 3)).to.equal(0)
				expect(at(10, 10, 7)).to.equal(0)
				-- the layer below only
				expect(at(20, 20, 4)).to.equal(1)
				expect(at(20, 20, 2)).to.equal(1)
				expect(at(20, 20, 1)).to.equal(0)
			end
		},
		{
			-- fails if a bad number makes Lookup raise or answer something other than 0, 0
			name = "Lookup: bad numbers, a missing index and huge coordinates give 0, 0",
			func = function()
				local z = Z()
				local index = z.Index({boxes = {{layer = 0, x1 = 0, y1 = 0, x2 = 0, y2 = 0, state = 2, ceil = 4}}})
				local nan, inf = 0 / 0, math.huge
				local calls = {
					{index, nan, 0, 0}, {index, 0, nan, 0}, {index, 0, 0, nan}, {index, inf, 0, 0}, {index, 0, -inf, 0}, {index, 0, 0, inf},
					{index, nil, 0, 0}, {index, 0, nil, 0}, {index, 0, 0, nil}, {index, "0", 0, 0}, {index, {}, 0, 0}, {index, 1e30, 0, 0}, {index, 0, 0, 1e30},
					{index, 0, 5e9, 0}, {nil, 0, 0, 0}, {"x", 0, 0, 0}
				}

				for i, c in ipairs(calls) do
					local s, cl = z.Lookup(c[1], c[2], c[3], c[4])

					if s ~= 0 or cl ~= 0 then
						error("call " .. i .. " gave " .. tostring(s) .. ", " .. tostring(cl))
					end
				end

				local s, cl = z.Lookup(index, 10, 10, 10)

				expect(s).to.equal(2)
				expect(cl).to.equal(4)
			end
		},
		{
			-- fails if Index / Count refuse or raise on an empty or a missing map
			name = "Index: an empty map or no map gives an empty index (Count 0, Lookup 0, 0)",
			func = function()
				local z = Z()

				for _, m in ipairs({{boxes = {}}, {}}) do
					local index = z.Index(m)

					expect(z.Count(index)).to.equal(0)
					expect(z.Lookup(index, 5, 5, 5)).to.equal(0)
				end

				expect(z.Count(z.Index(nil))).to.equal(0)
				expect(z.Count(nil)).to.equal(0)
			end
		},
		{
			-- fails if two different cells share a key (the extreme layers and cells)
			name = "Index: the keys of the extreme cells never collide (layers -4096..4095, cells -32768..32767)",
			func = function()
				local z = Z()
				local boxes = {}
				local n = 0
				local ls = {-4096, -4095, -1, 0, 1, 4094, 4095}
				local cs = {-32768, -32767, -1, 0, 1, 32766, 32767}

				for _, l in ipairs(ls) do
					for _, cx in ipairs(cs) do
						for _, cy in ipairs(cs) do
							n = n + 1
							boxes[n] = {layer = l, x1 = cx, y1 = cy, x2 = cx, y2 = cy, state = 1 + n % 2, ceil = n % 8}
						end
					end
				end

				local index = z.Index({boxes = boxes})

				expect(z.Count(index)).to.equal(n)

				for _, b in ipairs(boxes) do
					local s, c = z.Lookup(index, b.x1 * 128 + 1, b.y1 * 128 + 1, b.layer * 128)

					if s ~= b.state or c ~= b.ceil then
						error("cell " .. b.layer .. "," .. b.x1 .. "," .. b.y1 .. " gave " .. s .. "," .. c)
					end
				end
			end
		},
		{
			-- fails if Lookup allocates (a table, a closure, a string per call)
			name = "Lookup: no allocation (100000 calls change the memory by under 8 KB)",
			func = function()
				local z = Z()
				local index = z.Index(z.Build(randomSamples(11, 300, 20, 20, 2, false)))
				local lookup = z.Lookup

				local function run()
					for i = 1, 100000 do
						lookup(index, (i * 37) % 3000, (i * 53) % 3000, (i % 3) * 128)
					end
				end

				local delta = unhooked(function()
					-- warm up: the compiler's own objects (traces) are counted by the collector, they are not Lookup's garbage
					run()
					run()
					collectgarbage("collect")
					collectgarbage("collect")
					collectgarbage("stop")

					local ok, d = pcall(function()
						local before = collectgarbage("count")

						run()

						return collectgarbage("count") - before
					end)

					collectgarbage("restart")

					if not ok then
						error(d, 0)
					end

					return d
				end)

				expect(delta < 8).to.beTrue()
			end
		},
		{
			-- fails if the key is not "<map>_<size>_v1" lower case with the other bytes replaced by _
			name = "Key: lower case <map>_<bspSize>_v1, bytes outside a-z 0-9 _ - . replaced by _",
			func = function()
				local z = Z()

				expect(z.Key("gm_funkis", 12345678)).to.equal("gm_funkis_12345678_v1")
				expect(z.Key("GM_BigCity", 5)).to.equal("gm_bigcity_5_v1")
				expect(z.Key("rp_a-b.c", 0)).to.equal("rp_a-b.c_0_v1")
				expect(z.Key("a b/c\\d:e", 1)).to.equal("a_b_c_d_e_1_v1")
				expect(z.Key("../x", 1)).to.equal(".._x_1_v1")
				expect(z.Key("caf\195\169", 1)).to.equal("caf___1_v1")
				expect(z.Key("a\0b", 1)).to.equal("a_b_1_v1")
				expect(z.Key("gm_x", 4000000000)).to.equal("gm_x_4000000000_v1")
			end
		},
		{
			-- fails if a bad map name or size is not turned into the defaults
			name = "Key: a non string or empty map gives unknown, a bad size gives 0",
			func = function()
				local z = Z()

				expect(z.Key(nil, 3)).to.equal("unknown_3_v1")
				expect(z.Key(42, 3)).to.equal("unknown_3_v1")
				expect(z.Key({}, 3)).to.equal("unknown_3_v1")
				expect(z.Key("", 3)).to.equal("unknown_3_v1")
				expect(z.Key("gm_x", nil)).to.equal("gm_x_0_v1")
				expect(z.Key("gm_x", -5)).to.equal("gm_x_0_v1")
				expect(z.Key("gm_x", 0 / 0)).to.equal("gm_x_0_v1")
				expect(z.Key("gm_x", math.huge)).to.equal("gm_x_0_v1")
				expect(z.Key("gm_x", "12")).to.equal("gm_x_0_v1")
				expect(z.Key("gm_x", 7.9)).to.equal("gm_x_7_v1")
			end
		},
		{
			-- fails if the navmesh source does not add "_navmesh" to the key, if the nodes source (or none, or a word that is not a source) changes the old key, or if the
			-- suffix is not added after the version (the node files of the owner stay valid under the same names)
			name = "Key: the optional third parameter: \"navmesh\" appends _navmesh, nil, \"nodes\" and anything else give the old key exactly",
			func = function()
				local z = Z()

				expect(z.Key("gm_funkis", 12345678, "navmesh")).to.equal("gm_funkis_12345678_v1_navmesh")
				expect(z.Key("GM_BigCity", 5, "navmesh")).to.equal("gm_bigcity_5_v1_navmesh")
				expect(z.Key(nil, nil, "navmesh")).to.equal("unknown_0_v1_navmesh")
				expect(z.Key("gm_funkis", 12345678, nil)).to.equal("gm_funkis_12345678_v1")
				expect(z.Key("gm_funkis", 12345678, "nodes")).to.equal("gm_funkis_12345678_v1")
				expect(z.Key("gm_funkis", 12345678, "other")).to.equal("gm_funkis_12345678_v1")
				expect(z.Key("gm_funkis", 12345678, 42)).to.equal("gm_funkis_12345678_v1")
				expect(z.Key("gm_funkis", 12345678, "navmesh") ~= z.Key("gm_funkis", 12345678)).to.beTrue()
			end
		},
		{
			-- fails if Build is slower than 250 ms on 20000 random samples over 400 x 400 cells (the worst case: random states, almost every cell its own box)
			name = "Performance: Build of 20000 random samples over 400 x 400 cells in under 250 ms",
			func = function()
				local z = Z()
				local samples = randomSamples(321, 20000, 400, 400, 1, true)
				local m, ms = unhooked(function()
					local t0 = SysTime()
					local built = z.Build(samples)

					return built, (SysTime() - t0) * 1000
				end)

				print(string.format("[zonemap perf] Build 20000 samples: %.1f ms, %d boxes, %d cells", ms, #m.boxes, m.cells))
				expect(m.sampleCount).to.equal(20000)
				expect(ms < 250).to.beTrue()
			end
		},
		{
			-- fails if Index of a large map plus 100000 lookups takes 60 ms or more
			name = "Performance: Index of a large map plus 100000 Lookups in under 60 ms",
			func = function()
				local z = Z()
				local m = z.Build(randomSamples(321, 20000, 400, 400, 1, true))
				local r = rng(5)
				local xs, ys, zs = {}, {}, {}

				for i = 1, 100000 do
					xs[i], ys[i], zs[i] = r(51200), r(51200), r(100)
				end

				local lookup = z.Lookup
				local index, hits, indexMs, lookupMs = unhooked(function()
					local t0 = SysTime()
					local idx = z.Index(m)
					local t1 = SysTime()
					local h = 0

					for i = 1, 100000 do
						if lookup(idx, xs[i], ys[i], zs[i]) ~= 0 then
							h = h + 1
						end
					end

					return idx, h, (t1 - t0) * 1000, (SysTime() - t1) * 1000
				end)

				print(string.format("[zonemap perf] Index %.1f ms (%d cells), 100000 Lookups %.1f ms, total %.1f ms, hits %d", indexMs, z.Count(index), lookupMs,
					indexMs + lookupMs, hits))
				expect(z.Count(index)).to.equal(m.cells)
				expect(hits > 50000).to.beTrue()
				expect(indexMs + lookupMs < 60).to.beTrue()
			end
		},
		{
			-- fails if Encode / Decode of a large map is slow or lossy (100000 boxes is the planned worst case: batches of 4096 bytes)
			name = "Performance: Encode and Decode of 100000 boxes round trip",
			func = function()
				local z = Z()
				local boxes = {}
				local cells = 0

				for i = 1, 100000 do
					boxes[i] = {layer = i % 7 - 3, x1 = i % 300 - 150, y1 = floor(i / 300) - 150, x2 = i % 300 - 150, y2 = floor(i / 300) - 150, state = 1 + i % 2, ceil = i % 8}
					cells = cells + 1
				end

				local t0 = SysTime()
				local s = z.Encode({boxes = boxes, sampleCount = 100000, skipped = 0, cells = cells}, SMALL_HEADER)
				local t1 = SysTime()
				local m = z.Decode(s)
				local t2 = SysTime()

				print(string.format("[zonemap perf] Encode 100000 boxes %.1f ms, Decode %.1f ms (%d bytes)", (t1 - t0) * 1000, (t2 - t1) * 1000, #s))
				expect(#s).to.equal(24 + 9 * 100000 + 4)
				expect(m ~= nil).to.beTrue()
				expect(boxesEqual(boxes, m.boxes)).to.beTrue()
			end
		}
	}
}
