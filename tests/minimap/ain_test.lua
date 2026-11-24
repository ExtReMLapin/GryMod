-- Tests of the minimap's AIN module (lua/grymod/sh_ain.lua): the strict reader of the .ain node graph (version 37), GLuaTest format,
-- client realm. The synthetic files are built here with an encoder that shares nothing with the decoder (string.char and arithmetic, math.frexp
-- for the float32), so a wrong decoder cannot hide behind a wrong encoder. The expected values of the real files come from the reference
-- parser the orchestrator wrote in Python (130 files checked, size = 16 + 65 * N + 14 * L).

local GRAPHS = "maps/graphs/"

-- ---------------------------------------------------------------------------------------------------------------------------------
-- Encoder (independent of the module)
-- ---------------------------------------------------------------------------------------------------------------------------------

local function u32(n)
	n = n % 4294967296

	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function u16(n)
	n = n % 65536

	return string.char(n % 256, math.floor(n / 256))
end

local function u8(n)
	return string.char(n % 256)
end

-- float32 from a Lua number: sign, exponent (bias 127), 23-bit mantissa rounded to nearest; 0 is all zero bytes
local function f32(x)
	if x == 0 then
		return u32(0)
	end

	local sign = 0

	if x < 0 then
		sign, x = 1, -x
	end

	local m, e = math.frexp(x) -- x = m * 2^e, m in [0.5, 1)
	local exp = e - 1 + 127
	local mant = math.floor((m * 2 - 1) * 8388608 + 0.5)

	if mant >= 8388608 then
		mant, exp = 0, exp + 1
	end

	return u32(sign * 2147483648 + exp * 8388608 + mant)
end

-- one node record: 61 bytes; node = {x, y, z, yaw, type, info, zone} plus an optional raw 4-byte string per float (rawx...)
local function nodeBytes(nd)
	local parts = {
		nd.rawx or f32(nd.x or 0), nd.rawy or f32(nd.y or 0), nd.rawz or f32(nd.z or 0), nd.rawyaw or f32(nd.yaw or 0)
	}

	for hull = 1, 10 do
		parts[#parts + 1] = f32(hull * 8) -- the vertical offsets of the 10 hulls (not returned by the module)
	end

	parts[#parts + 1] = u8(nd.type or 2)
	parts[#parts + 1] = u16(nd.info or 0)
	parts[#parts + 1] = u16(nd.zone or 0)

	return table.concat(parts)
end

local function linkBytes(lk)
	local parts = {u16(lk[1]), u16(lk[2])}

	for hull = 1, 10 do
		parts[#parts + 1] = u8(hull) -- the 10 move capabilities (not returned)
	end

	return table.concat(parts)
end

-- a whole file; o.nodes (list), o.links (list of {src, dest}, 0-based like on disk), o.version, o.mapVersion, o.count / o.linkCount to lie
-- in the header, o.lookup (list; default 0..N-1), o.extra (bytes after the end), o.cut (number of bytes to cut off the end)
local function build(o)
	o = o or {}

	local nodes, links = o.nodes or {}, o.links or {}
	local parts = {u32(o.version or 37), u32(o.mapVersion or 7), u32(o.count or #nodes)}

	for i = 1, #nodes do
		parts[#parts + 1] = nodeBytes(nodes[i])
	end

	parts[#parts + 1] = u32(o.linkCount or #links)

	for i = 1, #links do
		parts[#parts + 1] = linkBytes(links[i])
	end

	local lookup = o.lookup

	for i = 1, #nodes do
		parts[#parts + 1] = u32(lookup and lookup[i] or i - 1)
	end

	local s = table.concat(parts) .. (o.extra or "")

	if o.cut then
		s = string.sub(s, 1, #s - o.cut)
	end

	return s
end

local function sample()
	return build({
		mapVersion = 12345,
		nodes = {
			{x = 100.5, y = -200.25, z = 64, yaw = 90, type = 2, info = 0, zone = 4},
			{x = -3444, y = 1064, z = -3572, yaw = 180, type = 4, info = 65535, zone = -1},
			{x = 0, y = 0, z = 1e30, yaw = -45.5, type = 3, info = 32, zone = -32768}
		},
		links = {{0, 1}, {2, 0}},
		lookup = {5, 70000, -2}
	})
end

-- ---------------------------------------------------------------------------------------------------------------------------------

local function ain()
	local M = GryMod and GryMod.Minimap

	expect(M ~= nil and M.AIN ~= nil and type(M.AIN.Parse) == "function" and type(M.AIN.Load) == "function").to.beTrue()

	return M.AIN
end

-- the decoded x of a file whose first node has these 4 raw bytes as x (nil when refused)
local function decodeX(raw)
	local r = ain().Parse(build({nodes = {{rawx = raw}}}))

	return r and r.nodes[1].x
end

local function near(a, b, relTol)
	return math.abs(a - b) <= math.abs(b) * relTol
end

local function refused(bytes, fragment)
	local r, err = ain().Parse(bytes)

	expect(r).to.beNil()
	expect(type(err)).to.equal("string")
	expect(string.find(err, fragment, 1, true) ~= nil).to.beTrue()
end

return {
	groupName = "GryMod minimap AIN reader (client)",
	beforeEach = function(state)
		state.read = nil
		state.exists = nil
	end,
	afterEach = function(state)
		-- put back file.Read (and file.Exists) if a case counted the calls or stood in for them
		pcall(function()
			if state.read then
				file.Read = state.read
				state.read = nil
			end

			if state.exists then
				file.Exists = state.exists
				state.exists = nil
			end
		end)
	end,
	cases = {
		{
			-- fails if NODE_TYPE is missing or a value differs
			name = "NODE_TYPE names the six node types of the engine (0 any ... 5 water)",
			func = function()
				local T = ain().NODE_TYPE

				expect(T.ANY).to.equal(0)
				expect(T.DELETED).to.equal(1)
				expect(T.GROUND).to.equal(2)
				expect(T.AIR).to.equal(3)
				expect(T.CLIMB).to.equal(4)
				expect(T.WATER).to.equal(5)
			end
		},
		{
			-- fails if a field is read at a wrong offset, if indices are not 1-based, if the lookup is dropped or the header is misread
			name = "a valid synthetic file with 3 nodes and 2 links gives every field back exactly, 1-based links",
			func = function()
				local r, err = ain().Parse(sample())

				expect(err).to.beNil()
				expect(r ~= nil).to.beTrue()
				expect(r.version).to.equal(37)
				expect(r.mapVersion).to.equal(12345)
				expect(#r.nodes).to.equal(3)
				expect(#r.links).to.equal(2)
				expect(#r.lookup).to.equal(3)

				local n1, n2, n3 = r.nodes[1], r.nodes[2], r.nodes[3]

				expect(n1.x).to.equal(100.5)
				expect(n1.y).to.equal(-200.25)
				expect(n1.z).to.equal(64)
				expect(n1.yaw).to.equal(90)
				expect(n1.type).to.equal(2)
				expect(n1.info).to.equal(0)
				expect(n1.zone).to.equal(4)

				expect(n2.x).to.equal(-3444)
				expect(n2.y).to.equal(1064)
				expect(n2.z).to.equal(-3572)
				expect(n2.yaw).to.equal(180)
				expect(n2.type).to.equal(4)
				expect(n2.info).to.equal(65535) -- uint16, not signed
				expect(n2.zone).to.equal(-1) -- int16, signed

				expect(near(n3.z, 1e30, 1e-6)).to.beTrue()
				expect(n3.yaw).to.equal(-45.5)
				expect(n3.type).to.equal(3)
				expect(n3.info).to.equal(32)
				expect(n3.zone).to.equal(-32768)

				expect(r.links[1].src).to.equal(1)
				expect(r.links[1].dest).to.equal(2)
				expect(r.links[2].src).to.equal(3)
				expect(r.links[2].dest).to.equal(1)

				expect(r.lookup[1]).to.equal(5)
				expect(r.lookup[2]).to.equal(70000)
				expect(r.lookup[3]).to.equal(-2) -- int32, signed
			end
		},
		{
			-- fails if the node stride is not 61 or the link stride not 14 (the second node would be garbage)
			name = "the strides are 61 bytes per node and 14 per link: 40 nodes and 39 links in a row read back in order",
			func = function()
				local nodes, links = {}, {}

				for i = 1, 40 do
					nodes[i] = {x = i, y = -i * 2, z = i * 0.5, yaw = i % 360, type = i % 6, info = i * 3, zone = -i}
				end

				for i = 1, 39 do
					links[i] = {i - 1, i}
				end

				local r = ain().Parse(build({nodes = nodes, links = links}))

				expect(r ~= nil).to.beTrue()
				expect(#r.nodes).to.equal(40)
				expect(#r.links).to.equal(39)

				for i = 1, 40 do
					local n = r.nodes[i]

					expect(n.x).to.equal(i)
					expect(n.y).to.equal(-i * 2)
					expect(n.z).to.equal(i * 0.5)
					expect(n.type).to.equal(i % 6)
					expect(n.info).to.equal(i * 3)
					expect(n.zone).to.equal(-i)
				end

				for i = 1, 39 do
					expect(r.links[i].src).to.equal(i)
					expect(r.links[i].dest).to.equal(i + 1)
				end
			end
		},
		{
			-- fails if N = 0 is refused or if a nil table comes back instead of empty ones
			name = "N = 0 (a 16-byte file) is valid and gives three empty tables",
			func = function()
				local bytes = build({})

				expect(#bytes).to.equal(16)

				local r, err = ain().Parse(bytes)

				expect(err).to.beNil()
				expect(r ~= nil).to.beTrue()
				expect(r.version).to.equal(37)
				expect(#r.nodes).to.equal(0)
				expect(#r.links).to.equal(0)
				expect(#r.lookup).to.equal(0)
			end
		},
		{
			-- fails if the maximum N is refused (off by one on the bound). The bound is a memory guard, not the engine's 1500: the Workshop maps gm_cloak (4629),
			-- gm_fugu_lawson (4477) and gm_boreas (4019) are real, exact graphs (the survey of 2026-11-22 found no real graph over 5000)
			name = "N = 20000, the largest allowed, is accepted (the real Workshop graphs go to 4629)",
			func = function()
				local nodes = {}

				for i = 1, 20000 do
					nodes[i] = {x = i}
				end

				local r = ain().Parse(build({nodes = nodes}))

				expect(r ~= nil).to.beTrue()
				expect(#r.nodes).to.equal(20000)
				expect(r.nodes[20000].x).to.equal(20000)
				expect(ain().MAX_NODES).to.equal(20000)
			end
		},
		{
			-- fails if a graph with more than 1500 nodes (the old bound) is refused
			name = "N = 4629 (the size of gm_cloak) and N = 1501 are accepted",
			func = function()
				for _, count in ipairs({1501, 4629}) do
					local nodes = {}

					for i = 1, count do
						nodes[i] = {x = i}
					end

					local r, err = ain().Parse(build({nodes = nodes}))

					expect(err).to.beNil()
					expect(#r.nodes).to.equal(count)
				end
			end
		},
		{
			-- fails if a float32 case is decoded wrongly (sign, exponent bias, mantissa weight)
			name = "float32 decoding: 0, 1, -1, 0.5, 123.456, -2048.25, 2^24, 1e-3, 1e30, -1e30",
			func = function()
				local cases = {0, 1, -1, 0.5, 123.456, -2048.25, 16777216, 1e-3, 1e30, -1e30, 3.5e-30, 65536.5}

				for i = 1, #cases do
					local want = cases[i]
					local got = decodeX(f32(want))

					expect(got ~= nil).to.beTrue()

					if want == 0 then
						expect(got).to.equal(0)
					else
						-- float32 holds 24 bits: 6e-8 of relative error at most (123.456 is within 1e-3 absolute as asked)
						expect(near(got, want, 1e-6)).to.beTrue()
					end
				end

				-- the exactly representable ones come back exactly
				expect(decodeX(f32(1))).to.equal(1)
				expect(decodeX(f32(-1))).to.equal(-1)
				expect(decodeX(f32(0.5))).to.equal(0.5)
				expect(decodeX(f32(-2048.25))).to.equal(-2048.25)
				expect(decodeX(f32(16777216))).to.equal(16777216)
				expect(math.abs(decodeX(f32(123.456)) - 123.456) < 1e-3).to.beTrue()
			end
		},
		{
			-- fails if a denormal or a negative zero comes out as something else than 0 (the design: 0 and denormals give 0)
			name = "zero, negative zero and denormals decode to 0",
			func = function()
				expect(decodeX("\0\0\0\0")).to.equal(0)
				expect(decodeX("\0\0\0\128")).to.equal(0) -- -0
				expect(decodeX("\1\0\0\0")).to.equal(0) -- smallest denormal
				expect(decodeX("\255\255\127\0")).to.equal(0) -- largest denormal
				expect(decodeX("\255\255\127\128")).to.equal(0) -- negative denormal
				expect(1 / decodeX("\0\0\0\128") > 0).to.beTrue() -- really +0, not -0
			end
		},
		{
			-- fails if the smallest and the largest normal float32 are mis-weighted at the extremes of the exponent
			name = "the extremes of the normal range: 2^-126 and the largest float32",
			func = function()
				expect(near(decodeX("\0\0\128\0"), 2 ^ -126, 1e-9)).to.beTrue()
				expect(near(decodeX("\255\255\127\127"), 3.4028234663852886e38, 1e-9)).to.beTrue()
				expect(near(decodeX("\255\255\127\255"), -3.4028234663852886e38, 1e-9)).to.beTrue()
			end
		},
		{
			-- fails if a NaN or an infinity gets through (any of the four floats, either sign)
			name = "a NaN or an infinity in x, y, z or yaw makes the whole file invalid",
			func = function()
				local bad = {"\0\0\192\127", "\1\0\128\127", "\0\0\128\127", "\0\0\128\255", "\255\255\255\255"}
				local keys = {"rawx", "rawy", "rawz", "rawyaw"}

				for i = 1, #bad do
					for k = 1, #keys do
						local nd = {x = 1, y = 2, z = 3, yaw = 4}

						nd[keys[k]] = bad[i]
						refused(build({nodes = {nd}}), "float")
					end
				end
			end
		},
		{
			-- fails if the version is not checked, or checked loosely (< or >=)
			name = "refused: version 36 and 38 (only 37 is read), 0 and a negative version too",
			func = function()
				refused(build({version = 36}), "version")
				refused(build({version = 38}), "version")
				refused(build({version = 0}), "version")
				refused(build({version = -37}), "version")
				refused(build({version = 4294967296 + 37 - 1}), "version")
			end
		},
		{
			-- fails if N = 20001 or a negative N (int32 read as unsigned) is accepted or crashes
			name = "refused: N = 20001, N negative (signed int32), N huge",
			func = function()
				refused(build({count = 20001}), "node count")
				refused(build({count = -1}), "node count")
				refused(build({count = -2147483648}), "node count")
				refused(build({count = 2147483647}), "node count")
				refused(build({count = 4294967295}), "node count") -- the same -1, written unsigned
			end
		},
		{
			-- fails if a missing header or a missing link count is read past the end of the string
			name = "refused: empty string, 1 to 15 bytes, a header that promises nodes and stops",
			func = function()
				refused("", "short")

				local full = build({})

				for n = 1, 15 do
					refused(string.sub(full, 1, n), "short")
				end

				-- a header with 2 nodes announced and nothing behind it
				refused(string.sub(build({nodes = {{}, {}}}), 1, 16), "truncated")
			end
		},
		{
			-- fails if a file cut anywhere is accepted
			name = "refused: a valid file cut at any length (inside a node, inside a link, inside the lookup, one byte short)",
			func = function()
				local full = sample()

				expect(ain().Parse(full) ~= nil).to.beTrue()

				for n = 0, #full - 1 do
					local r, err = ain().Parse(string.sub(full, 1, n))

					expect(r).to.beNil()
					expect(type(err)).to.equal("string")
				end
			end
		},
		{
			-- fails if the exact size is not demanded (a tolerant "at least" check)
			name = "refused: bytes left after the end of the file (1 and 100)",
			func = function()
				refused(build({nodes = {{}}, extra = "\0"}), "trailing")
				refused(build({nodes = {{}, {}}, links = {{0, 1}}, extra = string.rep("x", 100)}), "trailing")
				refused(build({extra = "\0"}), "trailing")
			end
		},
		{
			-- fails if link ids are not range checked (src and dest, both bounds: -1 and N)
			name = "refused: link src or dest out of range (negative, equal to N, far above)",
			func = function()
				local two = {{}, {}}

				refused(build({nodes = two, links = {{2, 0}}}), "range")
				refused(build({nodes = two, links = {{0, 2}}}), "range")
				refused(build({nodes = two, links = {{-1, 0}}}), "range")
				refused(build({nodes = two, links = {{0, -1}}}), "range")
				refused(build({nodes = two, links = {{0, 1}, {1, 0}, {0, 32767}}}), "range")
				refused(build({nodes = {}, links = {{0, 0}}}), "range")

				-- the ids at the edge are fine
				expect(ain().Parse(build({nodes = two, links = {{0, 1}, {1, 1}}})) ~= nil).to.beTrue()
			end
		},
		{
			-- fails if a negative or absurd link count is not caught before the size is computed or the loop runs
			name = "refused: link count negative or absurd (the size then cannot match)",
			func = function()
				refused(build({nodes = {{}}, linkCount = -1}), "link count")
				refused(build({nodes = {{}}, linkCount = -2147483648}), "link count")
				refused(build({nodes = {{}}, linkCount = 2147483647}), "link")
				refused(build({nodes = {{}}, linkCount = 1000000}), "link")
				-- announces 1 link, has none: the size is short by 14 bytes
				refused(build({nodes = {{}}, linkCount = 1}), "truncated")
				-- announces none, has one
				refused(build({nodes = {{}}, links = {{0, 0}}, linkCount = 0}), "trailing")
			end
		},
		{
			-- fails if the input type is not checked
			name = "refused: anything that is not a string",
			func = function()
				local A = ain()
				local things = {{nil}, {false}, {true}, {0}, {37}, {{}}, {function() end}, {Vector(0, 0, 0)}}

				for i = 1, #things do
					local r, err = A.Parse(things[i][1])

					expect(r).to.beNil()
					expect(type(err)).to.equal("string")
				end

				local r, err = A.Parse()

				expect(r).to.beNil()
				expect(type(err)).to.equal("string")
			end
		},
		{
			-- fails if the node list or a node is shared between two calls (a cache table kept in the module)
			name = "two Parse calls on the same bytes share no table: editing the first result leaves the second untouched",
			func = function()
				local bytes = sample()
				local a = ain().Parse(bytes)
				local b = ain().Parse(bytes)

				expect(a ~= b).to.beTrue()
				expect(a.nodes ~= b.nodes).to.beTrue()
				expect(a.nodes[1] ~= b.nodes[1]).to.beTrue()
				expect(a.links ~= b.links).to.beTrue()
				expect(a.links[1] ~= b.links[1]).to.beTrue()
				expect(a.lookup ~= b.lookup).to.beTrue()

				a.nodes[1].x = 999999
				a.nodes[1].type = 5
				a.links[1].src = 42
				a.lookup[1] = -1
				a.nodes[#a.nodes + 1] = {}
				a.links[#a.links + 1] = {}

				local c = ain().Parse(bytes)

				expect(c.nodes[1].x).to.equal(100.5)
				expect(c.nodes[1].type).to.equal(2)
				expect(c.links[1].src).to.equal(1)
				expect(c.lookup[1]).to.equal(5)
				expect(#c.nodes).to.equal(3)
				expect(#c.links).to.equal(2)
				expect(b.nodes[1].x).to.equal(100.5)

				-- same for the empty file
				local e1, e2 = ain().Parse(build({})), ain().Parse(build({}))

				expect(e1.nodes ~= e2.nodes).to.beTrue()
				e1.nodes[1] = {}
				expect(#e2.nodes).to.equal(0)
			end
		},
		{
			-- fails if Load does not read the right path, mis-decodes real data, or the counts differ from the Python parser
			name = "Load: the real counts of five maps match the reference parser (nodes / links)",
			func = function()
				local want = {
					d1_trainstation_03 = {157, 236}, d1_canals_05 = {351, 916}, d3_citadel_03 = {320, 839}, ep2_outland_07 = {369, 1023},
					d1_town_02 = {518, 1629}
				}

				for map, nl in pairs(want) do
					local r, err = ain().Load(map)

					expect(err).to.beNil()
					expect(r ~= nil).to.beTrue()
					expect(#r.nodes).to.equal(nl[1])
					expect(#r.links).to.equal(nl[2])
					expect(#r.lookup).to.equal(nl[1])
					expect(r.version).to.equal(37)
				end
			end
		},
		{
			-- fails if the node fields of real data are read at a wrong offset (the values come from the Python parser, first node and first link)
			name = "Load: first node, first link and first lookup values of real files equal the reference parser's",
			func = function()
				-- {x, y, z, yaw, type, info, zone, link src, link dest (1-based), lookup 1..3}
				local want = {
					d1_trainstation_03 = {-3581, -4744, 268, 0, 2, 0, 4, 1, 12, 1072, 1073, 1074},
					d1_canals_05 = {5305, 868, -454, 0, 2, 0, 4, 1, 2, 1385, 1397, 1289},
					d3_citadel_03 = {11152.5, 95, 2069.25, 0, 2, 0, 1, 2, 4, 1, 209, 210},
					ep2_outland_07 = {-10029.099609375, -9661.08984375, 55, 0, 2, 32, 4, 1, 2, 315, 316, 318},
					d1_town_02 = {-3444, 1064, -3572, 180, 4, 2, 4, 1, 2, 636, 635, 485},
					ttt_bigcity = {-2165.760009765625, 6198.7900390625, -11135, 0, 2, 0, 4, 1, 2, 185, 186, 187}
				}

				for map, w in pairs(want) do
					local r = ain().Load(map)

					expect(r ~= nil).to.beTrue()

					local n, l = r.nodes[1], r.links[1]

					expect(n.x).to.equal(w[1])
					expect(n.y).to.equal(w[2])
					expect(n.z).to.equal(w[3])
					expect(n.yaw).to.equal(w[4])
					expect(n.type).to.equal(w[5])
					expect(n.info).to.equal(w[6])
					expect(n.zone).to.equal(w[7])
					expect(l.src).to.equal(w[8])
					expect(l.dest).to.equal(w[9])
					expect(r.lookup[1]).to.equal(w[10])
					expect(r.lookup[2]).to.equal(w[11])
					expect(r.lookup[3]).to.equal(w[12])
				end
			end
		},
		{
			-- fails if the type byte is misread (signedness, offset) on real data
			name = "Load: the node types of d1_trainstation_03 (157 ground) and d1_town_02 (466 ground, 34 climb, 18 air)",
			func = function()
				local T = ain().NODE_TYPE

				local function count(map)
					local c = {}
					local r = ain().Load(map)

					expect(r ~= nil).to.beTrue()

					for i = 1, #r.nodes do
						local t = r.nodes[i].type

						c[t] = (c[t] or 0) + 1
					end

					return c
				end

				local a = count("d1_trainstation_03")

				expect(a[T.GROUND]).to.equal(157)
				expect(next(a, T.GROUND)).to.beNil() -- nothing else (only key 2)

				local b = count("d1_town_02")

				expect(b[T.GROUND]).to.equal(466)
				expect(b[T.CLIMB]).to.equal(34)
				expect(b[T.AIR]).to.equal(18)
				expect(b[T.ANY]).to.beNil()
				expect(b[T.WATER]).to.beNil()
			end
		},
		{
			-- fails if a map without nodes raises or returns nil instead of an empty graph
			name = "Load: gm_melancholia and pba_demo have a graph file with 0 nodes: a valid empty table",
			func = function()
				local maps = {"gm_melancholia", "pba_demo"}

				for i = 1, #maps do
					local r, err = ain().Load(maps[i])

					expect(err).to.beNil()
					expect(r ~= nil).to.beTrue()
					expect(#r.nodes).to.equal(0)
					expect(#r.links).to.equal(0)
				end
			end
		},
		{
			-- fails if a missing file is not reported as "no graph" (a Parse error would read "too short")
			name = "Load: a map with no graph file gives nil, \"no graph\"",
			func = function()
				local r, err = ain().Load("this_map_does_not_exist_zz9")

				expect(r).to.beNil()
				expect(err).to.equal("no graph")

				-- gm_bigcity ships no .ain either
				r, err = ain().Load("gm_bigcity")

				if not file.Exists(GRAPHS .. "gm_bigcity.ain", "GAME") then
					expect(r).to.beNil()
					expect(err).to.equal("no graph")
				end
			end
		},
		{
			-- fails if the name is not validated (path traversal, wrong types) or the failure is a raise
			name = "Load: a bad map name (not a string, empty, with a slash or ..) is refused with a reason, nothing is read",
			func = function()
				local A = ain()
				local names = {{nil}, {false}, {12}, {{}}, {""}, {"../d1_canals_05"}, {"a/b"}, {"a\\b"}, {".."}, {"maps/graphs/d1_canals_05"}}

				for i = 1, #names do
					local r, err = A.Load(names[i][1])

					expect(r).to.beNil()
					expect(type(err)).to.equal("string")
				end

				local r, err = A.Load()

				expect(r).to.beNil()
				expect(type(err)).to.equal("string")
			end
		},
		{
			-- fails if Load reads the file in several calls, with another path or another search path
			name = "Load: one single file.Read(\"maps/graphs/<map>.ain\", \"GAME\"), no other file call counted",
			func = function(state)
				local calls = {}
				local orig = file.Read

				state.read = orig
				file.Read = function(path, gamePath, ...)
					calls[#calls + 1] = {path, gamePath}

					return orig(path, gamePath, ...)
				end

				local ok, res, err = pcall(function()
					return ain().Load("d1_trainstation_03")
				end)

				file.Read = orig
				state.read = nil

				expect(ok).to.beTrue()
				expect(err).to.beNil()
				expect(res ~= nil).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal("maps/graphs/d1_trainstation_03.ain")
				expect(calls[1][2]).to.equal("GAME")
			end
		},
		{
			-- fails if an empty read through "GAME" (rp_apocalypse: file.Size 135568, file.Read "") ends in "too short" instead of the readable copy
			name = "Load: an empty read through \"GAME\" goes on to the other search paths and finds the readable copy",
			func = function(state)
				local orig, origExists = file.Read, file.Exists
				local good = orig("maps/graphs/d1_trainstation_03.ain", "GAME")
				local calls = {}

				expect(type(good) == "string" and #good > 16).to.beTrue()

				state.read, state.exists = orig, origExists

				file.Read = function(path, gamePath)
					calls[#calls + 1] = gamePath

					if gamePath == "GAME" then
						return ""
					end

					if gamePath == "WORKSHOP" then
						return good
					end

					return nil
				end

				local ok, res, err = pcall(function()
					return ain().Load("some_map_with_two_graphs")
				end)

				file.Read, file.Exists = orig, origExists
				state.read, state.exists = nil, nil

				expect(ok).to.beTrue()
				expect(err).to.beNil()
				expect(res ~= nil).to.beTrue()
				expect(#res.nodes > 0).to.beTrue()
				expect(calls[1]).to.equal("GAME")
				expect(calls[2]).to.equal("WORKSHOP")
			end
		},
		{
			-- fails if a file that exists and reads empty everywhere is reported as a short graph, or as no graph at all
			name = "Load: a file that exists but reads empty on every path is \"unreadable\", a missing one stays \"no graph\"",
			func = function(state)
				local orig, origExists = file.Read, file.Exists

				state.read, state.exists = orig, origExists

				file.Read = function()
					return ""
				end

				file.Exists = function()
					return true
				end

				local ok, res, err = pcall(function()
					return ain().Load("some_unreadable_map")
				end)

				file.Exists = function()
					return false
				end

				local ok2, res2, err2 = pcall(function()
					return ain().Load("some_missing_map")
				end)

				file.Read, file.Exists = orig, origExists
				state.read, state.exists = nil, nil

				expect(ok and ok2).to.beTrue()
				expect(res).to.beNil()
				expect(err).to.equal("unreadable")
				expect(res2).to.beNil()
				expect(err2).to.equal("no graph")
			end
		},
		{
			-- fails if any real file is refused: the 130 files of the game, plus the cross check size = 16 + 65 N + 14 L
			name = "every .ain of maps/graphs parses without error and the sum of the sizes is the sum of 16 + 65 N + 14 L",
			func = function()
				-- "MOD" = the game folder only (130 files). "GAME" also lists the maps of mounted addons (181 here): some of those are not valid v37
				-- graphs (ep1_intro is version 35) and the strict reader rightly refuses them; the next case reads the version 37 ones of "GAME"
				local files = file.Find(GRAPHS .. "*.ain", "MOD")

				expect(#files >= 100).to.beTrue() -- 130 on the dev machine

				local sizeSum, formulaSum, nodes, links = 0, 0, 0, 0

				for i = 1, #files do
					local path = GRAPHS .. files[i]
					local bytes = file.Read(path, "MOD")

					expect(type(bytes)).to.equal("string")
					expect(#bytes).to.equal(file.Size(path, "MOD")) -- the whole file was read, no cut at a 0 byte

					local r, err = ain().Parse(bytes)

					if not r then
						error(files[i] .. ": " .. tostring(err), 0)
					end

					sizeSum = sizeSum + #bytes
					formulaSum = formulaSum + 16 + 65 * #r.nodes + 14 * #r.links
					nodes, links = nodes + #r.nodes, links + #r.links

					for k = 1, #r.links do
						local lk = r.links[k]

						if lk.src < 1 or lk.src > #r.nodes or lk.dest < 1 or lk.dest > #r.nodes then
							error(files[i] .. ": link out of range after parsing", 0)
						end
					end
				end

				expect(formulaSum).to.equal(sizeSum)
				expect(nodes > 0 and links > 0).to.beTrue()
			end
		},
		{
			-- fails if a real version 37 graph of a mounted addon is refused, big ones included (the Workshop maps with more than 1500 nodes) or does not
			-- match the exact size formula. Files of another version are not graphs this reader knows and are left out
			name = "every version 37 .ain visible to the game (mounted addons included) parses, and its size is 16 + 65 N + 14 L",
			func = function()
				local files = file.Find(GRAPHS .. "*.ain", "GAME")
				local checked, big = 0, 0

				for i = 1, #files do
					local path = GRAPHS .. files[i]
					local bytes = file.Read(path, "GAME")

					if type(bytes) == "string" and #bytes >= 16 then
						local a, b, c, d = string.byte(bytes, 1, 4)

						if a + b * 256 + c * 65536 + d * 16777216 == 37 then
							local r, err = ain().Parse(bytes)

							if not r then
								error(files[i] .. ": " .. tostring(err), 0)
							end

							expect(#bytes).to.equal(16 + 65 * #r.nodes + 14 * #r.links)
							checked = checked + 1

							if #r.nodes > 1500 then
								big = big + 1
							end
						end
					end
				end

				expect(checked >= 100).to.beTrue()
				-- how many are over the old bound is only information: 3 on the dev machine (gm_cloak, gm_fugu_lawson, gm_boreas)
				expect(big >= 0).to.beTrue()
			end
		},
		{
			-- fails if the parse of the largest real file takes 50 ms or more (a per-node engine call, a string.format, a closure...)
			name = "performance: the largest real file (N near 1500) parses in under 50 ms on the first call",
			func = function()
				local files = file.Find(GRAPHS .. "*.ain", "MOD")
				local bestPath, bestSize = nil, -1

				-- the bigcity file when it is there, otherwise the largest
				for i = 1, #files do
					local path = GRAPHS .. files[i]
					local size = file.Size(path, "MOD")

					if files[i] == "ttt_bigcity.ain" then
						bestPath, bestSize = path, math.huge

						break
					end

					if size > bestSize then
						bestPath, bestSize = path, size
					end
				end

				expect(bestPath ~= nil).to.beTrue()

				local bytes = file.Read(bestPath, "MOD")

				expect(type(bytes)).to.equal("string")

				local t0 = SysTime()
				local r, err = ain().Parse(bytes)
				local first = (SysTime() - t0) * 1000

				expect(err).to.beNil()
				expect(r ~= nil).to.beTrue()

				-- a few more, to see the compiled speed too
				local best = first

				for _ = 1, 5 do
					t0 = SysTime()
					ain().Parse(bytes)
					best = math.min(best, (SysTime() - t0) * 1000)
				end

				MsgN(string.format("[AIN perf] %s: %d nodes, %d links, %d bytes: first parse %.2f ms, best of 6 %.2f ms", bestPath, #r.nodes, #r.links, #bytes, first, best))

				expect(first < 50).to.beTrue()
			end
		}
	}
}
