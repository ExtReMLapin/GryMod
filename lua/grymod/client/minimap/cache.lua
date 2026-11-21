-- GryMod minimap: module cache. Tile geometry and naming, the index file, the store of tiles on disk and the materials that draw them.
-- Design: docs/superpowers/specs/2026-11-21-minimap-design.md. Everything here is client side; the cache holds the map AS SHIPPED.
--
-- Decisions (the design leaves them to the builder):
--   * Key = sanitised "<map name>_<size of maps/<map>.bsp in bytes>_v1" (size 0 when the .bsp is unknown: file.Size gives -1). Sanitised = lowercase, every byte outside
--     [a-z0-9_] becomes "_" (so the key is safe in a path). A map that changes size gets a new key, hence a new directory; Prune removes the old ones.
--   * Directory = "grymod/minimap/<key>" (relative to data/). Files: "<base>.vtf", "<base>.vmt" and "index.json".
--   * Base name = "t_<level>_<tx>_<ty>_<res>_<ppm>"; a negative number is written with an "n" prefix ("n3"), a fractional ppm has "p" for the point; the level id
--     is sanitised like the key. The last four fields are always numbers, so the name can be read from the right: two different tiles never share a name.
--   * Cache.TileOf uses math.floor(x / T): a negative coordinate falls in a negative tile, the lower edge of a tile belongs to it.
--   * The index is read lazily, at the first use, from index.json: {version = 1, key = "...", tiles = {"<base>", ...}}. It is trusted only when the version and the key
--     are the expected ones and each name looks like a tile name; a tile whose .vtf is missing on disk is dropped (the index is then rewritten). Has works from memory
--     only (it is called at every draw): no engine call, no disk access once the index is loaded.
--   * Store writes the .vtf, then the .vmt (basetexture "../data/<path without extension>"), then the index. A failure leaves the index as it was. A tile that is loaded as a
--     material (or was, and was pushed out of the Lua table: the engine still holds its texture) is forgotten before the rewrite, so the new file is read again.
--   * Material loads lazily with Material("../data/<path>") and keeps at most MAX_MATERIALS (64) of them: the least recently used is dropped from the Lua table (only
--     references are kept, the engine owns the textures). An error material is never returned nor kept.
--   * Prune removes the directories of OTHER keys of the SAME map name only: the name part of the key is compared whole, so "gm_a_v2" is not "gm_a".
-- Modules reach each other as GryMod.Minimap.<Module> at call time (VTF here), and this module's own public functions are called through the Cache table, so a test can
-- replace them. Cache.Reset() forgets everything held in memory (the next use reads the disk again): for tests and for a change of map.

GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.Cache = GryMod.Minimap.Cache or {}

local Cache = GryMod.Minimap.Cache

local floor, sfind, smatch, sgsub, slower, sformat = math.floor, string.find, string.match, string.gsub, string.lower, string.format
local band = bit.band

local ROOT = "grymod/minimap"
local VERSION_TAG = "v1"
local INDEX_FILE = "index.json"
local MAX_COORD = 2 ^ 31 -- larger tile indices are not tiles any more (and would print with an exponent)

Cache.MAX_MATERIALS = 64

-- in-memory state: the key and its index, the materials. Cache.Reset() replaces it.
local state
local keyMemo -- map name -> key, so that the size of the .bsp is read once per map
local levelMemo -- level id -> sanitised level id

function Cache.Reset()
	state = {
		key = nil,
		dir = nil,
		loaded = false,
		set = {}, -- base name -> true
		count = 0,
		mats = {}, -- base name -> {mat = IMaterial, stamp = number}
		matCount = 0,
		tick = 0,
		ever = {} -- base name -> true: loaded once and no longer in mats (the engine may still hold its texture)
	}
	keyMemo = {}
	levelMemo = {}
end

Cache.Reset()

local function finite(n)
	return type(n) == "number" and n - n == 0
end

local function sanitise(s)
	return (sgsub(slower(s), "[^a-z0-9_]", "_"))
end

-- ---------------------------------------------------------------------------------------------------------
-- Key and directory
-- ---------------------------------------------------------------------------------------------------------

-- KeyFor(mapName, bspSize) -> key (pure; Key() reads the two values from the engine)
function Cache.KeyFor(mapName, bspSize)
	if type(mapName) ~= "string" or mapName == "" then
		mapName = "unknown"
	end

	if not finite(bspSize) or bspSize < 0 then
		bspSize = 0
	end

	return sanitise(mapName) .. "_" .. sformat("%d", floor(bspSize)) .. "_" .. VERSION_TAG
end

function Cache.Key()
	local map = game.GetMap()
	local key = keyMemo[map]

	if not key then
		key = Cache.KeyFor(map, file.Size("maps/" .. tostring(map) .. ".bsp", "GAME"))
		keyMemo[map] = key
	end

	return key
end

-- the key this cache works on, read once (Reset forgets it)
local function currentKey()
	local key = state.key

	if not key then
		key = Cache.Key()
		state.key = key
	end

	return key
end

-- Dir(key) -> "grymod/minimap/<key>" (the current key when none is given)
function Cache.Dir(key)
	return ROOT .. "/" .. (key or currentKey())
end

-- ---------------------------------------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------------------------------------

-- TileUnits(res, ppm) -> edge of a tile in world units = res / ppm / METRES_PER_UNIT | nil, reason
function Cache.TileUnits(res, ppm)
	if not finite(res) or res <= 0 then
		return nil, "bad tile size"
	end

	if not finite(ppm) or ppm <= 0 then
		return nil, "bad definition"
	end

	local mpu = GryMod.RadarShared and GryMod.RadarShared.METRES_PER_UNIT

	if not finite(mpu) or mpu <= 0 then
		return nil, "metres per unit unknown"
	end

	return res / ppm / mpu
end

-- TileOf(x, y, res, ppm) -> tx, ty (floor: negative coordinates fall in negative tiles) | nil, reason
function Cache.TileOf(x, y, res, ppm)
	if not finite(x) or not finite(y) then
		return nil, "bad coordinates"
	end

	local edge, err = Cache.TileUnits(res, ppm)

	if not edge then
		return nil, err
	end

	return floor(x / edge), floor(y / edge)
end

-- ---------------------------------------------------------------------------------------------------------
-- Tile names
-- ---------------------------------------------------------------------------------------------------------

local function isIndex(n)
	return finite(n) and n == floor(n) and n > -MAX_COORD and n < MAX_COORD
end

local function numberText(n)
	if n < 0 then
		return "n" .. (sgsub(tostring(-n), "%.", "p"))
	end

	return (sgsub(tostring(n), "%.", "p"))
end

-- Name(tile) -> base file name | nil, reason. Also what says whether a tile is valid: a level id, whole tx and ty, res a power of two from 4 to 4096, ppm > 0.
function Cache.Name(tile)
	if type(tile) ~= "table" then
		return nil, "tile is not a table"
	end

	local level, tx, ty, res, ppm = tile.level, tile.tx, tile.ty, tile.res, tile.ppm

	if type(level) ~= "string" or level == "" then
		return nil, "tile has no level"
	end

	if not isIndex(tx) or not isIndex(ty) then
		return nil, "tile index is not a whole number"
	end

	if not finite(res) or res < 4 or res > 4096 or res ~= floor(res) or band(res, res - 1) ~= 0 then
		return nil, "tile size is not a power of two between 4 and 4096"
	end

	if not finite(ppm) or ppm <= 0 or ppm > 1024 then
		return nil, "bad definition"
	end

	local lv = levelMemo[level]

	if not lv then
		lv = sanitise(level)
		levelMemo[level] = lv
	end

	return "t_" .. lv .. "_" .. numberText(tx) .. "_" .. numberText(ty) .. "_" .. numberText(res) .. "_" .. numberText(ppm)
end

-- Path(tile) -> "<dir>/<base>" (no extension) | nil, reason
function Cache.Path(tile)
	local name, err = Cache.Name(tile)

	if not name then
		return nil, err
	end

	return Cache.Dir() .. "/" .. name
end

-- TileBounds(tile) -> {minx, miny, maxx, maxy} in world units: x in [tx*T, (tx+1)*T), y in [ty*T, (ty+1)*T)
function Cache.TileBounds(tile)
	local name, err = Cache.Name(tile)

	if not name then
		return nil, err
	end

	local edge, err2 = Cache.TileUnits(tile.res, tile.ppm)

	if not edge then
		return nil, err2
	end

	return {minx = tile.tx * edge, miny = tile.ty * edge, maxx = (tile.tx + 1) * edge, maxy = (tile.ty + 1) * edge}
end

-- ---------------------------------------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------------------------------------

local function ensureDir(dir)
	local path = ""

	for part in string.gmatch(dir, "[^/]+") do
		path = path == "" and part or (path .. "/" .. part)

		if not file.IsDir(path, "DATA") then
			file.CreateDir(path)
		end
	end
end

-- writes index.json from the in-memory set; true | false, reason
local function saveIndex()
	local list = {}

	for name in pairs(state.set) do
		list[#list + 1] = name
	end

	table.sort(list)

	ensureDir(state.dir)

	local path = state.dir .. "/" .. INDEX_FILE

	file.Write(path, util.TableToJSON({version = 1, key = state.key, tiles = list}))

	if not file.Exists(path, "DATA") then
		return false, "cannot write " .. path
	end

	return true
end

-- reads index.json once; keeps only the tiles whose .vtf is still there
local function ensureIndex()
	if state.loaded then
		return
	end

	local key = currentKey()
	local dir = Cache.Dir(key)

	state.dir = dir
	state.loaded = true
	state.set = {}
	state.count = 0

	local path = dir .. "/" .. INDEX_FILE

	if not file.Exists(path, "DATA") then
		return
	end

	local text = file.Read(path, "DATA")
	local idx = type(text) == "string" and util.JSONToTable(text) or nil

	if type(idx) ~= "table" or idx.version ~= 1 or idx.key ~= key or type(idx.tiles) ~= "table" then
		return
	end

	local dropped = false

	for _, name in ipairs(idx.tiles) do
		if type(name) == "string" and #name <= 200 and sfind(name, "^t_[a-z0-9_]+$") then
			if state.set[name] then
				-- listed twice: counted once
			elseif file.Exists(dir .. "/" .. name .. ".vtf", "DATA") then
				state.set[name] = true
				state.count = state.count + 1
			else
				dropped = true
			end
		else
			dropped = true
		end
	end

	if dropped then
		saveIndex()
	end
end

-- Has(tile) -> bool. From memory only once the index is loaded (called at every draw).
function Cache.Has(tile)
	local name = Cache.Name(tile)

	if not name then
		return false
	end

	ensureIndex()

	return state.set[name] == true
end

function Cache.Count()
	ensureIndex()

	return state.count
end

-- ---------------------------------------------------------------------------------------------------------
-- Materials
-- ---------------------------------------------------------------------------------------------------------

-- asks the engine to read the texture of a material again (a file was rewritten)
local function download(mat)
	local ok, tex = pcall(mat.GetTexture, mat, "$basetexture")

	if ok and tex then
		pcall(tex.Download, tex)
	end
end

local function materialPath(name)
	return "../data/" .. state.dir .. "/" .. name
end

-- Forget(tile): drops the material and has the engine read the file again next time. Also for a tile that was pushed out of the Lua table by the LRU.
function Cache.Forget(tile)
	local name = Cache.Name(tile)

	if not name then
		return
	end

	ensureIndex()

	local entry = state.mats[name]

	if entry then
		state.mats[name] = nil
		state.matCount = state.matCount - 1
		state.ever[name] = nil
		download(entry.mat)
	elseif state.ever[name] then
		state.ever[name] = nil

		local ok, mat = pcall(Material, materialPath(name))

		if ok and mat then
			download(mat)
		end
	end
end

-- drops the least recently used material (never `keep`) once there are more than MAX_MATERIALS
local function evict(keep)
	local oldest, oldestStamp

	for name, entry in pairs(state.mats) do
		if name ~= keep and (not oldestStamp or entry.stamp < oldestStamp) then
			oldest, oldestStamp = name, entry.stamp
		end
	end

	if oldest then
		state.mats[oldest] = nil
		state.matCount = state.matCount - 1
		state.ever[oldest] = true
	end
end

-- Material(tile) -> IMaterial | nil (tile missing, or the engine gave an error material)
function Cache.Material(tile)
	local name = Cache.Name(tile)

	if not name then
		return nil
	end

	ensureIndex()

	if not state.set[name] then
		return nil
	end

	state.tick = state.tick + 1

	local entry = state.mats[name]

	if entry then
		entry.stamp = state.tick

		return entry.mat
	end

	local mat = Material(materialPath(name))

	if not mat or mat:IsError() then
		return nil
	end

	state.mats[name] = {mat = mat, stamp = state.tick}
	state.matCount = state.matCount + 1
	state.ever[name] = true

	while state.matCount > Cache.MAX_MATERIALS do
		local before = state.matCount

		evict(name)

		if state.matCount == before then
			break
		end
	end

	return mat
end

-- ---------------------------------------------------------------------------------------------------------
-- Store, Clear, Prune
-- ---------------------------------------------------------------------------------------------------------

-- calls f(...) protected; true | false, reason (a failure answer or a raised error)
local function checked(label, f, ...)
	local ok, a, b = pcall(f, ...)

	if not ok then
		return false, label .. " raised: " .. tostring(a)
	end

	if a ~= true then
		return false, b or (label .. " failed")
	end

	return true
end

-- Store(tile, dxt1Bytes) -> true | false, reason
function Cache.Store(tile, data)
	local name, err = Cache.Name(tile)

	if not name then
		return false, err
	end

	if type(data) ~= "string" or data == "" then
		return false, "no image data"
	end

	local VTF = GryMod.Minimap.VTF

	if type(VTF) ~= "table" or not VTF.Write or not VTF.WriteVMT then
		return false, "VTF module missing"
	end

	ensureIndex()

	local path = state.dir .. "/" .. name

	-- a tile the engine may hold already: it must read the file again after the rewrite
	if state.mats[name] or state.ever[name] then
		Cache.Forget(tile)
	end

	local known = state.set[name] == true
	local ok, werr = checked("VTF.Write", VTF.Write, path .. ".vtf", tile.res, tile.res, VTF.FORMAT_DXT1 or 13, data)

	if ok then
		ok, werr = checked("VTF.WriteVMT", VTF.WriteVMT, path .. ".vmt", "../data/" .. path)
	end

	if not ok then
		if not known then
			-- nothing half written is left behind for a tile the index does not know
			file.Delete(path .. ".vtf")
			file.Delete(path .. ".vmt")
		end

		return false, werr
	end

	if not known then
		state.set[name] = true
		state.count = state.count + 1
	end

	local saved, serr = saveIndex()

	if not saved then
		if not known then
			state.set[name] = nil
			state.count = state.count - 1
		end

		return false, serr
	end

	return true
end

-- Clear(key): deletes the .vtf, .vmt and index.json of that key (the current one when none is given), nothing else; true | false, reason
function Cache.Clear(key)
	key = key or currentKey()

	if type(key) ~= "string" or not sfind(key, "^[a-z0-9_]+$") then
		return false, "bad key"
	end

	local dir = Cache.Dir(key)
	local files = file.Find(dir .. "/*", "DATA")

	for _, f in ipairs(files or {}) do
		if f == INDEX_FILE or sfind(f, "^t_[a-z0-9_]+%.vtf$") or sfind(f, "^t_[a-z0-9_]+%.vmt$") then
			file.Delete(dir .. "/" .. f)
		end
	end

	file.Delete(dir) -- only removes an empty directory

	if key == currentKey() then
		-- the engine may still hold the textures of the tiles that were loaded: a later Store must make it read the file again
		for name in pairs(state.mats) do
			state.ever[name] = true
		end

		state.mats = {}
		state.matCount = 0
		state.dir = dir
		state.loaded = true
		state.set = {}
		state.count = 0
	end

	return true
end

-- Prune() -> number of cache directories removed: the other keys of the same map name (the map changed size). Never another map, never the current key.
function Cache.Prune()
	local key = currentKey()
	local mapName = smatch(key, "^(.+)_%d+_" .. VERSION_TAG .. "$")

	if not mapName then
		return 0
	end

	local _, dirs = file.Find(ROOT .. "/*", "DATA")
	local removed = 0

	for _, d in ipairs(dirs or {}) do
		if d ~= key and smatch(d, "^(.+)_%d+_v%d+$") == mapName and Cache.Clear(d) then
			removed = removed + 1
		end
	end

	return removed
end
