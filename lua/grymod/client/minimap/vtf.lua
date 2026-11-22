-- GryMod minimap: module vtf. Filled by its owner agent (see docs/superpowers/specs/2026-11-21-minimap-design.md).
GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.VTF = GryMod.Minimap.VTF or {}

-- Builds, writes and parses VTF 7.2 files, the texture format the engine loads, and the VMT text that makes a material of one. The minimap stores
-- every tile as a VTF under data/ and loads it with Material("../data/<path>"). The file is built whole in memory (string.char and bit, one
-- string) and written with ONE File:Write: a byte-per-byte write of a 4 MB image would cost seconds, one call costs about 2 ms.
-- Layout (offsets from the start of the file, little endian): 0 "VTF\0", 4 u32 7, 8 u32 2, 12 u32 header size 80, 16 u16 width, 18 u16 height,
-- 20 u32 flags, 24 u16 frames, 26 u16 first frame, 28 padding, 32 three float32 0.5, 44 padding, 48 float32 1.0, 52 u32 format, 56 u8 mips,
-- 57 u32 thumbnail format, 61 u8 thumbnail width, 62 u8 thumbnail height, 63 u16 depth, 65..79 padding; then the thumbnail, then the image data.

local VTF = GryMod.Minimap.VTF

local band, rshift = bit.band, bit.rshift
local schar, sbyte, ssub, sfind, srep = string.char, string.byte, string.sub, string.find, string.rep

VTF.FORMAT_BGRA8888 = 12
VTF.FORMAT_DXT1 = 13
-- DXT1 with one bit of alpha: same data size as DXT1, a block in 3-colour mode (c0 <= c1) has transparent pixels at index 3
VTF.FORMAT_DXT1A = 20

-- CLAMPS 0x4 + CLAMPT 0x8 + NOMIP 0x100 + NOLOD 0x200. No POINTSAMPLE: the map is shown smaller than its definition and turns, sampling is linear.
VTF.FLAGS = 0x30C
-- the flags of format 20: the same plus ONEBITALPHA 0x1000, so the engine keeps the alpha of the texture
VTF.FLAGS_ALPHA = 0x130C
VTF.HEADER_SIZE = 80
VTF.THUMBNAIL_SIZE = 128
VTF.MIN_SIZE = 4
VTF.MAX_SIZE = 4096

local FORMAT_DXT5 = 15

-- the thumbnail the engine expects: DXT1 16x16, 16 blocks of solid grey (RGB565 0x8410 twice, indices 0)
local THUMBNAIL = srep(schar(0x10, 0x84, 0x10, 0x84, 0, 0, 0, 0), 16)

local function u16(n)
	return schar(band(n, 255), band(rshift(n, 8), 255))
end

local function u32(n)
	return schar(band(n, 255), band(rshift(n, 8), 255), band(rshift(n, 16), 255), band(rshift(n, 24), 255))
end

-- the constant part of the header from offset 20 to 55 (flags, frames, first frame, padding, reflectivity, padding, bump scale), then the format
local MIDDLE_REST = u16(1) .. u16(0) .. srep("\0", 4) .. srep("\0\0\0\63", 3) .. srep("\0", 4) .. "\0\0\128\63"
local MIDDLE = u32(VTF.FLAGS) .. MIDDLE_REST
local MIDDLE_ALPHA = u32(VTF.FLAGS_ALPHA) .. MIDDLE_REST
local TAIL = "\1" .. u32(VTF.FORMAT_DXT1) .. "\16\16" .. u16(1) .. srep("\0", 15)
local START = "VTF\0" .. u32(7) .. u32(2) .. u32(VTF.HEADER_SIZE)

-- bytes of one image of w x h pixels, nil for a format this module does not know
local function imageBytes(format, w, h)
	if format == VTF.FORMAT_BGRA8888 then
		return w * h * 4
	end

	if format == VTF.FORMAT_DXT1 or format == VTF.FORMAT_DXT1A then
		return math.ceil(w / 4) * math.ceil(h / 4) * 8
	end

	if format == FORMAT_DXT5 then
		return math.ceil(w / 4) * math.ceil(h / 4) * 16
	end

	return nil
end

local function checkSize(v, what)
	if type(v) ~= "number" or not (v >= VTF.MIN_SIZE and v <= VTF.MAX_SIZE) or v ~= math.floor(v) then
		return false, what .. " must be a whole number from " .. VTF.MIN_SIZE .. " to " .. VTF.MAX_SIZE
	end

	if band(v, v - 1) ~= 0 then
		return false, what .. " must be a power of two"
	end

	return true
end

-- Build(w, h, format, data) -> the whole file as a string | nil, reason
function VTF.Build(w, h, format, data)
	local ok, err = checkSize(w, "width")

	if not ok then
		return nil, err
	end

	ok, err = checkSize(h, "height")

	if not ok then
		return nil, err
	end

	if format ~= VTF.FORMAT_BGRA8888 and format ~= VTF.FORMAT_DXT1 and format ~= VTF.FORMAT_DXT1A then
		return nil, "unknown format " .. tostring(format) .. " (12 = BGRA8888, 13 = DXT1, 20 = DXT1A)"
	end

	if type(data) ~= "string" then
		return nil, "data must be a string"
	end

	local want = imageBytes(format, w, h)

	if #data ~= want then
		return nil, "data is " .. #data .. " bytes, expected " .. want
	end

	return START .. u16(w) .. u16(h) .. (format == VTF.FORMAT_DXT1A and MIDDLE_ALPHA or MIDDLE) .. u32(format) .. TAIL .. THUMBNAIL .. data
end

-- a path under data/: lowercase [a-z0-9_/.-], no "..", no leading or doubled slash, ends with ext (and is more than ext)
local function checkPath(path, ext)
	if type(path) ~= "string" or path == "" then
		return false, "path must be a non-empty string"
	end

	if sfind(path, "[^a-z0-9_/%.%-]") then
		return false, "path has a character outside a-z 0-9 _ / . - : " .. path
	end

	if sfind(path, "..", 1, true) or ssub(path, 1, 1) == "/" or sfind(path, "//", 1, true) then
		return false, "path must be relative with no '..' or empty folder: " .. path
	end

	if #path <= #ext or ssub(path, -#ext) ~= ext then
		return false, "path must end with " .. ext .. ": " .. path
	end

	return true
end

-- creates every folder of the path (not the file) under data/, one level at a time
local function ensureDir(path)
	local dir = ""

	for part in string.gmatch(ssub(path, 1, #path - #(string.match(path, "[^/]*$"))), "[^/]+") do
		dir = dir == "" and part or (dir .. "/" .. part)

		if not file.IsDir(dir, "DATA") then
			file.CreateDir(dir)

			if not file.IsDir(dir, "DATA") then
				return false, "cannot create the folder " .. dir
			end
		end
	end

	return true
end

-- writes the string with one File:Write and checks the size on disk; a file of the wrong size is deleted
local function writeWhole(path, bytes)
	local ok, err = ensureDir(path)

	if not ok then
		return false, err
	end

	local f = file.Open(path, "wb", "DATA")

	if not f then
		return false, "cannot open " .. path .. " for writing"
	end

	local written, werr = pcall(f.Write, f, bytes)

	f:Close()

	if not written then
		file.Delete(path)

		return false, "write failed: " .. tostring(werr)
	end

	local size = file.Size(path, "DATA")

	if size ~= #bytes then
		file.Delete(path)

		return false, "wrote " .. tostring(size) .. " bytes, expected " .. #bytes
	end

	return true
end

-- Write(path, w, h, format, data) -> true | false, reason
function VTF.Write(path, w, h, format, data)
	local ok, err = checkPath(path, ".vtf")

	if not ok then
		return false, err
	end

	local bytes, berr = VTF.Build(w, h, format, data)

	if not bytes then
		return false, berr
	end

	return writeWhole(path, bytes)
end

-- the material file text: an unlit material, the vertex colour and alpha apply (View draws it faded), $translucent because the texture carries
-- an alpha (format 20 voids; harmless for the opaque formats), no level of detail
function VTF.VMTText(basetexturePath)
	return "\"UnlitGeneric\"\n{\n\t\"$basetexture\" \"" .. tostring(basetexturePath) .. "\"\n\t\"$vertexcolor\" 1\n\t\"$vertexalpha\" 1\n\t\"$translucent\" 1\n\t\"$nolod\" 1\n}\n"
end

-- WriteVMT(path, basetexturePath) -> true | false, reason. basetexturePath is what Material() will look up, e.g. "../data/grymod/minimap/<key>/<base>":
-- the same characters as a data path (so no quote can break out of the text) but it may start with "../".
function VTF.WriteVMT(path, basetexturePath)
	local ok, err = checkPath(path, ".vmt")

	if not ok then
		return false, err
	end

	if type(basetexturePath) ~= "string" or basetexturePath == "" or sfind(basetexturePath, "[^a-z0-9_/%.%-]") then
		return false, "texture path must be a non-empty string of a-z 0-9 _ / . - only"
	end

	return writeWhole(path, VTF.VMTText(basetexturePath))
end

local function readU16(s, i)
	local a, b = sbyte(s, i, i + 1)

	return a + b * 256
end

local function readU32(s, i)
	local a, b, c, d = sbyte(s, i, i + 3)

	return a + b * 256 + c * 65536 + d * 16777216
end

-- Parse(bytes) -> {version = {7, minor}, headerSize, width, height, flags, frames, format, mips, thumbFormat, thumbW, thumbH, depth, dataOffset,
-- dataLength} | nil, reason. An independent, strict reader of 7.0 to 7.2: the file length must be exactly header + thumbnail + image data.
function VTF.Parse(bytes)
	if type(bytes) ~= "string" then
		return nil, "bytes must be a string"
	end

	local length = #bytes

	if length < 64 then
		return nil, "file shorter than a header (" .. length .. " bytes)"
	end

	if ssub(bytes, 1, 4) ~= "VTF\0" then
		return nil, "bad signature"
	end

	local major, minor = readU32(bytes, 5), readU32(bytes, 9)

	if major ~= 7 or minor > 2 then
		return nil, "unsupported version " .. major .. "." .. minor
	end

	local headerSize = readU32(bytes, 13)
	local wantHeader = minor >= 2 and 80 or 64

	if headerSize ~= wantHeader then
		return nil, "header size " .. headerSize .. ", expected " .. wantHeader
	end

	if length < headerSize then
		return nil, "header cut short"
	end

	local width, height = readU16(bytes, 17), readU16(bytes, 19)
	local flags = readU32(bytes, 21)
	local frames = readU16(bytes, 25)
	local format = readU32(bytes, 53)
	local mips = sbyte(bytes, 57)
	local thumbFormat = readU32(bytes, 58)
	local thumbW, thumbH = sbyte(bytes, 62, 63)
	local depth = minor >= 2 and readU16(bytes, 64) or 1

	if width < 1 or height < 1 or frames < 1 or mips < 1 or mips > 16 or depth < 1 then
		return nil, "a size, frame, mip or depth count is zero or out of range"
	end

	local thumbBytes

	if thumbFormat == 0xFFFFFFFF and thumbW == 0 and thumbH == 0 then
		thumbBytes = 0
	elseif thumbFormat == VTF.FORMAT_DXT1 and thumbW > 0 and thumbH > 0 then
		thumbBytes = imageBytes(thumbFormat, thumbW, thumbH)
	else
		return nil, "unsupported thumbnail (format " .. thumbFormat .. ", " .. thumbW .. "x" .. thumbH .. ")"
	end

	local dataLength = 0

	for level = 0, mips - 1 do
		local bytesOfLevel = imageBytes(format, math.max(1, rshift(width, level)), math.max(1, rshift(height, level)))

		if not bytesOfLevel then
			return nil, "unsupported format " .. format
		end

		dataLength = dataLength + bytesOfLevel
	end

	dataLength = dataLength * frames * depth

	local dataOffset = headerSize + thumbBytes

	if dataOffset + dataLength ~= length then
		return nil, "file is " .. length .. " bytes, header announces " .. (dataOffset + dataLength)
	end

	return {
		version = {major, minor},
		headerSize = headerSize,
		width = width,
		height = height,
		flags = flags,
		frames = frames,
		format = format,
		mips = mips,
		thumbFormat = thumbFormat,
		thumbW = thumbW,
		thumbH = thumbH,
		depth = depth,
		dataOffset = dataOffset,
		dataLength = dataLength
	}
end
