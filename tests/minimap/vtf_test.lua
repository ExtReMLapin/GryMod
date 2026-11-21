-- Tests of the minimap VTF module (lua/grymod/client/minimap/vtf.lua), GLuaTest format, client realm. The module builds, writes and parses
-- VTF 7.2 files (the texture format the engine loads) and the VMT text that points to them. The header is checked byte by byte against
-- references written by hand in this file (one per shape), so a field that moves by one byte fails. The engine cases write real files under
-- data/grymod/minimap/test_vtf_* and load them with Material(); every file is deleted afterwards. The pixel reading is in tests/minimap/vtf_job.lua.

local function V()
	return GryMod.Minimap.VTF or {}
end

local function hex(s)
	return (s:gsub("%s", ""):gsub("%x%x", function(h)
		return string.char(tonumber(h, 16))
	end))
end

-- The reference header of a VTF 7.2 file as the engine reads it, field by field (offset in the comment), for the three shapes the tests check.
local function reference(widthHex, heightHex, formatHex)
	return hex(
		"56 54 46 00" .. -- 0: "VTF\0"
		"07 00 00 00" .. -- 4: major version 7
		"02 00 00 00" .. -- 8: minor version 2
		"50 00 00 00" .. -- 12: header size 80
		widthHex .. -- 16: width (u16)
		heightHex .. -- 18: height (u16)
		"0C 03 00 00" .. -- 20: flags CLAMPS 0x4 + CLAMPT 0x8 + NOMIP 0x100 + NOLOD 0x200
		"01 00" .. -- 24: frames
		"00 00" .. -- 26: first frame
		"00 00 00 00" .. -- 28: padding
		"00 00 00 3F 00 00 00 3F 00 00 00 3F" .. -- 32: reflectivity 0.5 0.5 0.5
		"00 00 00 00" .. -- 44: padding
		"00 00 80 3F" .. -- 48: bumpmap scale 1.0
		formatHex .. -- 52: high resolution format (u32)
		"01" .. -- 56: mip count
		"0D 00 00 00" .. -- 57: thumbnail format 13 (DXT1)
		"10" .. -- 61: thumbnail width 16
		"10" .. -- 62: thumbnail height 16
		"01 00" .. -- 63: depth
		string.rep("00", 15) -- 65..79: padding
	)
end

local BGRA, DXT1 = "0C 00 00 00", "0D 00 00 00"
local REF_4x4_BGRA = reference("04 00", "04 00", BGRA)
local REF_64x64_BGRA = reference("40 00", "40 00", BGRA)
local REF_1024_DXT1 = reference("00 04", "00 04", DXT1)
local THUMBNAIL = string.rep(hex("10 84 10 84 00 00 00 00"), 16)

local function bgraData(w, h)
	return string.rep("\1\2\3\255", w * h)
end

local function dxt1Data(w, h)
	return string.rep(hex("00 F8 00 F8 00 00 00 00"), (w / 4) * (h / 4))
end

-- first byte that differs, as text ("identical" when the two strings are equal): a readable failure message
local function describeDiff(got, want)
	for i = 1, math.max(#got, #want) do
		if string.byte(got, i) ~= string.byte(want, i) then
			return "offset " .. (i - 1) .. " got " .. tostring(string.byte(got, i)) .. " want " .. tostring(string.byte(want, i))
		end
	end

	return "identical"
end

local function u32(s, offset)
	local a, b, c, d = string.byte(s, offset + 1, offset + 4)

	return a + b * 256 + c * 65536 + d * 16777216
end

local counter = 0

local function uniqueDir()
	counter = counter + 1

	return "grymod/minimap/test_vtf_" .. os.time() .. "_" .. math.random(1, 999999) .. "_" .. counter
end

-- deletes a test directory and everything below it (only called on a directory of this test)
local function wipe(dir)
	local files, dirs = file.Find(dir .. "/*", "DATA")

	for _, name in ipairs(files or {}) do
		file.Delete(dir .. "/" .. name)
	end

	for _, name in ipairs(dirs or {}) do
		wipe(dir .. "/" .. name)
	end

	file.Delete(dir)
end

-- the 16x16 BGRA image of the engine cases: a corner of each colour, so a mirror, a rotation or a channel swap changes what is read.
-- Pixel (col, row) from the top-left: (0,0) red, (15,0) green, (0,15) blue, (15,15) white, the rest black. Alpha 255.
local function cornerImageBGRA()
	local out = {}

	for row = 0, 15 do
		for col = 0, 15 do
			local r, g, b = 0, 0, 0

			if col == 0 and row == 0 then r = 255
			elseif col == 15 and row == 0 then g = 255
			elseif col == 0 and row == 15 then b = 255
			elseif col == 15 and row == 15 then r, g, b = 255, 255, 255 end

			out[#out + 1] = string.char(b, g, r, 255)
		end
	end

	return table.concat(out)
end

-- 16x16 DXT1 made by hand: 4x4 blocks of one colour each (RGB565 end points equal, indices 0), top-left red, top-right green, bottom-left blue, rest black
local function cornerImageDXT1()
	local blocks = {}
	local colours = {[0] = "00 F8", [3] = "E0 07", [12] = "1F 00", [15] = "FF FF"}

	for i = 0, 15 do
		local c = colours[i] or "00 00"
		blocks[#blocks + 1] = hex(c .. " " .. c .. " 00 00 00 00")
	end

	return table.concat(blocks)
end

return {
	groupName = "GryMod minimap VTF",
	beforeEach = function(state)
		state.dirs = {}
	end,
	afterEach = function(state)
		for _, dir in ipairs(state.dirs or {}) do
			pcall(wipe, dir)
		end
	end,
	cases = {
		{
			-- fails if any field of the header is moved, resized or written with another value
			name = "Build: the 80-byte header is exactly the reference, byte by byte (4x4 BGRA)",
			func = function()
				local out = V().Build(4, 4, 12, bgraData(4, 4))

				expect(describeDiff(string.sub(out, 1, 80), REF_4x4_BGRA)).to.equal("identical")
			end
		},
		{
			name = "Build: the 80-byte header is exactly the reference, byte by byte (64x64 BGRA)",
			func = function()
				local out = V().Build(64, 64, 12, bgraData(64, 64))

				expect(describeDiff(string.sub(out, 1, 80), REF_64x64_BGRA)).to.equal("identical")
			end
		},
		{
			name = "Build: the 80-byte header is exactly the reference, byte by byte (1024x1024 DXT1, flags 0x30C)",
			func = function()
				local out = V().Build(1024, 1024, 13, dxt1Data(1024, 1024))

				expect(describeDiff(string.sub(out, 1, 80), REF_1024_DXT1)).to.equal("identical")
			end
		},
		{
			-- fails if the thumbnail is missing, another size or another colour, or the data does not start at 80 + 128
			name = "Build: the thumbnail is 128 bytes (16 DXT1 blocks of grey 0x8410, indices 0) and the image data follows it unchanged",
			func = function()
				local data = bgraData(4, 4)
				local out = V().Build(4, 4, 12, data)

				expect(#THUMBNAIL).to.equal(128)
				expect(describeDiff(string.sub(out, 81, 208), THUMBNAIL)).to.equal("identical")
				expect(string.sub(out, 209) == data).to.beTrue()
			end
		},
		{
			-- fails if the total is not header + thumbnail + data for one of the shapes
			name = "Build: total size is 80 + 128 + data for BGRA and DXT1 at 4, 16, 64, 1024, 2048 and 4096",
			func = function()
				for _, n in ipairs({4, 16, 64, 1024, 2048}) do
					local bgra = V().Build(n, n, 12, bgraData(n, n))
					expect(#bgra).to.equal(80 + 128 + n * n * 4)
					expect(u32(bgra, 52)).to.equal(12)
				end

				for _, n in ipairs({4, 16, 64, 1024, 2048, 4096}) do
					local dxt = V().Build(n, n, 13, dxt1Data(n, n))
					expect(#dxt).to.equal(80 + 128 + n * n / 2)
					expect(u32(dxt, 52)).to.equal(13)
				end
			end
		},
		{
			name = "Build: 4096x4096 BGRA (64 MB) is accepted and has the right size; a non-square 64x256 keeps width and height in the right fields",
			func = function()
				local big = V().Build(4096, 4096, 12, string.rep("\0", 4096 * 4096 * 4))
				expect(#big).to.equal(80 + 128 + 4096 * 4096 * 4)

				local rect = V().Build(64, 256, 12, bgraData(64, 256))
				local w = string.byte(rect, 17) + 256 * string.byte(rect, 18)
				local h = string.byte(rect, 19) + 256 * string.byte(rect, 20)

				expect(w).to.equal(64)
				expect(h).to.equal(256)
				expect(#rect).to.equal(80 + 128 + 64 * 256 * 4)
			end
		},
		{
			-- fails if Build raises or accepts one of these inputs
			name = "Build: refuses what is not a valid image with (nil, reason): dimensions, format, data length, types",
			func = function()
				local bad = {
					{3, 4, 12, bgraData(4, 4), "width below 4"},
					{4, 3, 12, bgraData(4, 4), "height below 4"},
					{0, 0, 12, "", "zero"},
					{6, 4, 12, bgraData(4, 4), "not a power of two"},
					{4, 12, 12, bgraData(4, 4), "height not a power of two"},
					{8192, 4, 12, "", "above 4096"},
					{4, 8192, 13, "", "height above 4096"},
					{4.5, 4, 12, bgraData(4, 4), "fraction"},
					{-4, 4, 12, bgraData(4, 4), "negative"},
					{0 / 0, 4, 12, bgraData(4, 4), "nan"},
					{math.huge, 4, 12, bgraData(4, 4), "inf"},
					{"4", 4, 12, bgraData(4, 4), "width is a string"},
					{4, nil, 12, bgraData(4, 4), "height is nil"},
					{4, 4, 99, bgraData(4, 4), "unknown format"},
					{4, 4, nil, bgraData(4, 4), "no format"},
					{4, 4, "bgra", bgraData(4, 4), "format as text"},
					{4, 4, 12, string.sub(bgraData(4, 4), 1, 63), "BGRA one byte short"},
					{4, 4, 12, bgraData(4, 4) .. "\0", "BGRA one byte too many"},
					{4, 4, 12, "", "BGRA empty"},
					{4, 4, 13, string.rep("\0", 7), "DXT1 one byte short"},
					{4, 4, 13, string.rep("\0", 9), "DXT1 one byte too many"},
					{16, 16, 13, bgraData(16, 16), "DXT1 given the BGRA length"},
					{4, 4, 12, nil, "data is nil"},
					{4, 4, 12, 64, "data is a number"},
					{4, 4, 12, {}, "data is a table"}
				}

				for _, c in ipairs(bad) do
					local out, err = V().Build(c[1], c[2], c[3], c[4])

					expect(out).to.beNil()
					expect(type(err)).to.equal("string")
					expect(#err > 0).to.beTrue()
				end
			end
		},
		{
			name = "Write: refuses a bad path with (false, reason) and writes nothing: capitals, spaces, .., no .vtf, empty, not a string",
			func = function()
				local data = bgraData(4, 4)
				local paths = {
					"Grymod/minimap/test_vtf_x.vtf", "grymod/minimap/test vtf.vtf", "grymod/../x.vtf", "../x.vtf", "grymod/minimap/test_vtf_x.vmt",
					"grymod/minimap/test_vtf_x", "grymod/minimap/test_vtf_x.vtf.txt", "", ".vtf", "/grymod/test_vtf_x.vtf", "grymod//test_vtf_x.vtf",
					"grymod/minimap/test_vtf_\"x.vtf", "grymod\\minimap\\test_vtf_x.vtf", 42, true, {}
				}

				for _, p in ipairs(paths) do
					local ok, err = V().Write(p, 4, 4, 12, data)

					expect(ok).to.beFalse()
					expect(type(err)).to.equal("string")
				end

				expect(file.Exists("grymod/minimap/test_vtf_x.vtf", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if Write writes a file for data Build refuses
			name = "Write: a refused image (bad length) returns (false, reason) and leaves no file",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				local ok, err = V().Write(dir .. "/bad.vtf", 4, 4, 12, "short")

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")
				expect(file.Exists(dir .. "/bad.vtf", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if the directories are not created level by level, or the file is not the one Build returns
			name = "Write: creates the missing directories (two new levels) and the file read back is exactly Build()",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir .. "/sub/deeper"
				state.dirs[#state.dirs + 1] = dir .. "/sub"
				state.dirs[#state.dirs + 1] = dir

				expect(file.IsDir(dir, "DATA")).to.beFalse()

				local data = bgraData(8, 8)
				local ok, err = V().Write(dir .. "/sub/deeper/img.vtf", 8, 8, 12, data)

				expect(err).to.beNil()
				expect(ok).to.beTrue()
				expect(file.IsDir(dir .. "/sub/deeper", "DATA")).to.beTrue()
				expect(file.Exists(dir .. "/sub/deeper/img.vtf", "DATA")).to.beTrue()
				expect(file.Size(dir .. "/sub/deeper/img.vtf", "DATA")).to.equal(80 + 128 + 8 * 8 * 4)
			end
		},
		{
			-- fails if a zero byte truncates or alters the file: the header, the thumbnail and the image are full of them
			name = "Write: a file with many zero bytes read back with file.Read(..., \"DATA\") has the size and content of Build()",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				local parts = {}

				for i = 0, 16 * 16 * 4 - 1 do
					parts[#parts + 1] = string.char((i * 37) % 256)
				end

				local data = table.concat(parts)
				local expected = V().Build(16, 16, 12, data)

				expect(string.find(data, "\0", 1, true) ~= nil).to.beTrue()
				expect(V().Write(dir .. "/zeros.vtf", 16, 16, 12, data)).to.beTrue()

				local back = file.Read(dir .. "/zeros.vtf", "DATA")

				expect(#back).to.equal(#expected)
				expect(describeDiff(back, expected)).to.equal("identical")
			end
		},
		{
			-- the old manual test never tried a File:Write of more than 4 MB
			name = "Write: a body above 4 MB (2048x2048 BGRA, 16 MB) and an 8 MB DXT1 (4096x4096) are written whole, in one File:Write",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				local bgra = string.rep("\7\0\9\255", 2048 * 2048)
				local expected = V().Build(2048, 2048, 12, bgra)

				expect(V().Write(dir .. "/big.vtf", 2048, 2048, 12, bgra)).to.beTrue()
				expect(file.Size(dir .. "/big.vtf", "DATA")).to.equal(#expected)
				expect(file.Read(dir .. "/big.vtf", "DATA") == expected).to.beTrue()

				local dxt = dxt1Data(4096, 4096)
				local expectedDxt = V().Build(4096, 4096, 13, dxt)

				expect(V().Write(dir .. "/bigdxt.vtf", 4096, 4096, 13, dxt)).to.beTrue()
				expect(file.Size(dir .. "/bigdxt.vtf", "DATA")).to.equal(#expectedDxt)
				expect(file.Read(dir .. "/bigdxt.vtf", "DATA") == expectedDxt).to.beTrue()
			end
		},
		{
			name = "Write: writing the same path again replaces the file (a rewritten tile)",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				expect(V().Write(dir .. "/again.vtf", 16, 16, 12, bgraData(16, 16))).to.beTrue()
				expect(V().Write(dir .. "/again.vtf", 4, 4, 12, bgraData(4, 4))).to.beTrue()
				expect(file.Size(dir .. "/again.vtf", "DATA")).to.equal(80 + 128 + 64)
			end
		},
		{
			-- fails if the VMT text differs by one character from what the engine cases below load
			name = "VMTText: the exact text (UnlitGeneric, $basetexture, $vertexcolor 1, $vertexalpha 1, $nolod 1)",
			func = function()
				expect(V().VMTText("../data/grymod/minimap/test_vtf_a/t_a1_0_0_1024_3")).to.equal(
					"\"UnlitGeneric\"\n{\n\t\"$basetexture\" \"../data/grymod/minimap/test_vtf_a/t_a1_0_0_1024_3\"\n\t\"$vertexcolor\" 1\n\t\"$vertexalpha\" 1\n\t\"$nolod\" 1\n}\n")
			end
		},
		{
			name = "WriteVMT: writes the VMT text under data/ (directory created), refuses a bad path or texture path with (false, reason)",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir .. "/vmt"
				state.dirs[#state.dirs + 1] = dir

				local tex = "../data/" .. dir .. "/vmt/img"

				expect(V().WriteVMT(dir .. "/vmt/img.vmt", tex)).to.beTrue()
				expect(file.Read(dir .. "/vmt/img.vmt", "DATA")).to.equal(V().VMTText(tex))

				for _, p in ipairs({"Grymod/x.vmt", "grymod/x y.vmt", "grymod/../x.vmt", "grymod/x.vtf", "grymod/x", "", 7, {}}) do
					local ok, err = V().WriteVMT(p, tex)

					expect(ok).to.beFalse()
					expect(type(err)).to.equal("string")
				end

				for _, t in ipairs({"", "has space", "has\"quote", "Capital", 5, true}) do
					local ok, err = V().WriteVMT(dir .. "/vmt/other.vmt", t)

					expect(ok).to.beFalse()
					expect(type(err)).to.equal("string")
				end

				expect(file.Exists(dir .. "/vmt/other.vmt", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if one field of Parse reads the wrong offset or size
			name = "Parse: the round trip with Build gives every field (BGRA 64x32 and DXT1 1024x1024)",
			func = function()
				local out = V().Build(64, 32, 12, bgraData(64, 32))
				local info, err = V().Parse(out)

				expect(err).to.beNil()
				expect(info.version[1]).to.equal(7)
				expect(info.version[2]).to.equal(2)
				expect(info.headerSize).to.equal(80)
				expect(info.width).to.equal(64)
				expect(info.height).to.equal(32)
				expect(info.flags).to.equal(0x30C)
				expect(info.frames).to.equal(1)
				expect(info.format).to.equal(12)
				expect(info.mips).to.equal(1)
				expect(info.thumbFormat).to.equal(13)
				expect(info.thumbW).to.equal(16)
				expect(info.thumbH).to.equal(16)
				expect(info.depth).to.equal(1)
				expect(info.dataOffset).to.equal(208)
				expect(info.dataLength).to.equal(64 * 32 * 4)

				local dxt = V().Build(1024, 1024, 13, dxt1Data(1024, 1024))
				local info2 = V().Parse(dxt)

				expect(info2.width).to.equal(1024)
				expect(info2.height).to.equal(1024)
				expect(info2.format).to.equal(13)
				expect(info2.dataOffset).to.equal(208)
				expect(info2.dataLength).to.equal(524288)
			end
		},
		{
			name = "Parse: reads older files (7.0 and 7.1 have a 64-byte header, no depth field)",
			func = function()
				local out = V().Build(4, 4, 12, bgraData(4, 4))

				for minor = 0, 1 do
					-- the 7.2 header cut to 64 bytes, minor version and header size changed
					local old = string.sub(out, 1, 8) .. string.char(minor, 0, 0, 0) .. string.char(64, 0, 0, 0) .. string.sub(out, 17, 64) .. string.sub(out, 81)
					local info, err = V().Parse(old)

					expect(err).to.beNil()
					expect(info.version[2]).to.equal(minor)
					expect(info.headerSize).to.equal(64)
					expect(info.dataOffset).to.equal(64 + 128)
					expect(info.dataLength).to.equal(64)
					expect(info.depth).to.equal(1)
				end
			end
		},
		{
			-- fails if the reader is lenient: each of these files is broken in one way
			name = "Parse: refuses (nil, reason) a wrong signature, 7.3, 6.x, a truncated header, a wrong header size, bad data size, a longer file",
			func = function()
				local good = V().Build(4, 4, 12, bgraData(4, 4))

				expect(V().Parse(good)).to.beA("table")

				local function patched(index, byteValue)
					return string.sub(good, 1, index - 1) .. string.char(byteValue) .. string.sub(good, index + 1)
				end

				local bad = {
					{"VTX" .. string.sub(good, 4), "signature"},
					{patched(9, 3), "version 7.3"},
					{patched(9, 4), "version 7.4"},
					{patched(5, 6), "version 6.2"},
					{patched(5, 8), "version 8.2"},
					{string.sub(good, 1, 79), "header cut by one byte"},
					{string.sub(good, 1, 10), "header cut"},
					{"", "empty"},
					{patched(13, 79), "header size 79"},
					{patched(13, 64), "header size 64 for a 7.2 file"},
					{string.sub(good, 1, #good - 1), "data one byte short"},
					{good .. "\0", "file longer than announced"},
					{patched(57, 2), "2 mips announced but the data is for one"},
					{patched(17, 0), "width 0 (the high byte is 0 too)"},
					{patched(53, 99), "unknown format"},
					{patched(25, 0), "zero frames"},
					{patched(64, 0), "depth 0"},
					{patched(58, 12), "thumbnail format with no valid size"}
				}

				for _, c in ipairs(bad) do
					local info, err = V().Parse(c[1])

					expect(info).to.beNil()
					expect(type(err)).to.equal("string")
				end

				for _, notString in ipairs({1, true, {}}) do
					local info, err = V().Parse(notString)

					expect(info).to.beNil()
					expect(type(err)).to.equal("string")
				end

				expect((V().Parse(nil))).to.beNil()
			end
		},
		{
			-- fails if the file written by this module is not what the engine reads: size, then the pixels' bytes
			name = "engine: Material() loads a 16x16 BGRA VTF + VMT written by the module, texture 16x16, no error material",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				local base = dir .. "/bgra"

				expect(V().Write(base .. ".vtf", 16, 16, 12, cornerImageBGRA())).to.beTrue()
				expect(V().WriteVMT(base .. ".vmt", "../data/" .. base)).to.beTrue()

				local mat = Material("../data/" .. base)

				expect(mat:IsError()).to.beFalse()

				local tex = mat:GetTexture("$basetexture")

				expect(tex ~= nil).to.beTrue()
				expect(tex:Width()).to.equal(16)
				expect(tex:Height()).to.equal(16)
			end
		},
		{
			name = "engine: Material() loads a hand-made 16x16 DXT1 VTF + VMT (no DXT1 module involved), texture 16x16",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir

				local base = dir .. "/dxt1"

				expect(V().Write(base .. ".vtf", 16, 16, 13, cornerImageDXT1())).to.beTrue()
				expect(V().WriteVMT(base .. ".vmt", "../data/" .. base)).to.beTrue()

				local mat = Material("../data/" .. base)

				expect(mat:IsError()).to.beFalse()

				local tex = mat:GetTexture("$basetexture")

				expect(tex:Width()).to.equal(16)
				expect(tex:Height()).to.equal(16)
			end
		},
		{
			-- fails if the engine cannot find a tile that is in a new directory (what Cache.Store relies on)
			name = "engine: a 1024x1024 DXT1 tile written into a directory that did not exist loads with Width() == Height() == 1024",
			func = function(state)
				local dir = uniqueDir()
				state.dirs[#state.dirs + 1] = dir .. "/new"
				state.dirs[#state.dirs + 1] = dir

				local base = dir .. "/new/tile"

				expect(V().Write(base .. ".vtf", 1024, 1024, 13, dxt1Data(1024, 1024))).to.beTrue()
				expect(V().WriteVMT(base .. ".vmt", "../data/" .. base)).to.beTrue()

				local mat = Material("../data/" .. base)

				expect(mat:IsError()).to.beFalse()
				expect(mat:GetTexture("$basetexture"):Width()).to.equal(1024)
				expect(mat:GetTexture("$basetexture"):Height()).to.equal(1024)
			end
		}
	}
}
