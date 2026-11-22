-- GryMod minimap: module cache. Tile geometry and naming, the index file, the store of tiles on disk and the materials that draw them.
-- Design: docs/superpowers/specs/2026-11-21-minimap-design.md. Everything here is client side; the cache holds the map AS SHIPPED.
--
-- Decisions (the design leaves them to the builder):
--   * Key = sanitised "<map name>_<size of maps/<map>.bsp in bytes>_v2" (size 0 when the .bsp is unknown: file.Size gives -1). Sanitised = lowercase, every byte outside
--     [a-z0-9_] becomes "_" (so the key is safe in a path). A map that changes size gets a new key, hence a new directory; Prune removes the old ones. "_v1" tiles were
--     written without alpha and must not be reused (Prune removes them too).
--   * Directory = "grymod/minimap/<key>" (relative to data/). Files: "<base>.vtf", "<base>.vmt" and "index.json".
--   * Base name = "t_<level>_<tx>_<ty>_<res>_<ppm>"; a negative number is written with an "n" prefix ("n3"), a fractional ppm has "p" for the point; the level id
--     is sanitised like the key. The last four fields are always numbers, so the name can be read from the right: two different tiles never share a name.
--     Name(tile) is memoised per (level, tx, ty, res, ppm) in nested tables: a tile that is already known costs lookups and no allocation (Has runs at every draw).
--   * Cache.TileOf uses math.floor(x / T): a negative coordinate falls in a negative tile, the lower edge of a tile belongs to it.
--   * THE INDEX. index.json = {version = 1, key = "...", tiles = {"<base>", ...}, empty = {"<base>", ...}} (`empty` is absent when there is none). The index is a cache of
--     what the directory holds, not the truth: at the first use ONE file.Find lists the .vtf files, then
--       - a listed tile is kept only when its .vtf is there AND has the size a file of that resolution must have (208 bytes of header and thumbnail, then the DXT1 /
--         DXT1A data or the BGRA data: a truncated or damaged file is dropped, and deleted so it is made again);
--       - a .vtf on the disk that the index does not list (index absent or damaged, or older than the last Stores because the index is written in batches) is adopted
--         after the same check: the index is rebuilt from the directory;
--       - the empty tiles exist only in the index (no file): they are kept as the index says.
--     The index is rewritten when the load changed something. Names that do not look like tile names are never trusted (a name is a way out of the directory).
--   * THE INDEX IS WRITTEN IN BATCHES: Store and StoreEmpty only mark it dirty, and it is written every FLUSH_EVERY (16) changes and by Cache.Flush() (Gen calls it when
--     its queue is empty and at Cancel). A crash loses nothing that has a file (the next load adopts it) and only the "this tile is empty" knowledge of the last few
--     StoreEmpty (those tiles are made again). A write that fails (checked by the size on disk, so an old index that is still there does not hide it) leaves the index dirty:
--     Flush answers false, reason and the next change tries again; Store itself is not a failure then, the tile is on the disk.
--   * Store writes the .vtf, then the .vmt (basetexture "../data/<path without extension>"). A failure writes nothing to the index. A tile that is loaded as a material
--     (or was, and was pushed out of the Lua table: the engine still holds its texture) is forgotten AFTER the new files are written, so the engine reads them.
--   * The size of every tile (.vtf + .vmt) is remembered at Store and at load: Trim does no disk call to count.
--   * Material loads lazily with Material("../data/<path>") and keeps at most Capacity() of them (160 by default, SetCapacity from 16 to 512): the least recently used is
--     dropped from the Lua table (only references are kept, the engine owns the textures). A cyclic walk over more tiles than the capacity would miss every time, so the
--     View must never ask for more tiles than the capacity in one frame (the visible tiles of the radar are far fewer). When the engine gives nothing or an error material
--     for a tile of the index, the tile is REMOVED from the index (and its files deleted): it will be made again, instead of asking the engine at every frame.
--   * Empty tiles (StoreEmpty): known in the index (`empty` list) with no .vtf and no .vmt; Has is true, Material is nil, Trim never counts nor removes them.
--   * Prune removes the directories of OTHER keys of the SAME map name only (another size, or the stale "_v1" version): the name part of the key is compared whole, so the
--     map "gm_a_v2" is not "gm_a". It is meant to be called by the generator once per map load.
-- Modules reach each other as GryMod.Minimap.<Module> at call time (VTF here), and this module's own public functions are called through the Cache table, so a test can
-- replace them. Cache.Reset() forgets everything held in memory (the next use reads the disk again; it does NOT write the index: Flush first if that matters).

GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.Cache = GryMod.Minimap.Cache or {}

local Cache = GryMod.Minimap.Cache

local floor, sfind, smatch, sgsub, slower, sformat, ssub = math.floor, string.find, string.match, string.gsub, string.lower, string.format, string.sub
local band = bit.band

local ROOT = "grymod/minimap"
local VERSION_TAG = "v2" -- v1 tiles had no alpha: they are stale (Prune removes their directories)
local INDEX_FILE = "index.json"
local MAX_COORD = 2 ^ 31 -- larger tile indices are not tiles any more (and would print with an exponent)
local HEADER_BYTES = 208 -- 80 bytes of VTF header + 128 of thumbnail, before the image data
local MEMO_LIMIT = 50000 -- tiles whose name is memoised; the memo starts again beyond that

Cache.MAX_MATERIALS = 160 -- the default capacity
Cache.FLUSH_EVERY = 16 -- changes (Store, StoreEmpty) between two writes of index.json

local capacity = Cache.MAX_MATERIALS

-- in-memory state: the key and its index, the materials. Cache.Reset() replaces it.
local state
local keyMemo -- map name -> key, so that the size of the .bsp is read once per map
local levelMemo -- level id -> sanitised level id
local nameMemo, memoCount -- level -> tx -> ty -> res -> ppm -> base name

function Cache.Reset()
	state = {
		key = nil,
		dir = nil,
		loaded = false,
		set = {}, -- base name -> true: every tile the cache knows, with a file or empty
		empty = {}, -- base name -> true: the tiles of `set` that are entirely empty (no file on disk)
		size = {}, -- base name -> bytes of its .vtf + .vmt (tiles with files)
		count = 0,
		dirty = false, -- the index in memory is not what index.json says
		pending = 0, -- changes since the last write of index.json
		mats = {}, -- base name -> {mat = IMaterial, stamp = number}
		matCount = 0,
		tick = 0,
		ever = {}, -- base name -> true: loaded once and no longer in mats (the engine may still hold its texture)
		clock = 0, -- counter of accesses (no engine call: Has runs at every draw)
		access = {}, -- base name -> value of the clock at its last Store / Material / Has that said yes (Trim keeps the recent ones)
		lastStored = nil -- base name of the tile Store wrote last: Trim never removes it
	}
	keyMemo = {}
	levelMemo = {}
	nameMemo = {}
	memoCount = 0
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

local function memoise(level, tx, ty, res, ppm, name)
	if memoCount >= MEMO_LIMIT then
		nameMemo = {}
		memoCount = 0
	end

	local a = nameMemo[level]

	if not a then
		a = {}
		nameMemo[level] = a
	end

	local b = a[tx]

	if not b then
		b = {}
		a[tx] = b
	end

	local c = b[ty]

	if not c then
		c = {}
		b[ty] = c
	end

	local d = c[res]

	if not d then
		d = {}
		c[res] = d
	end

	d[ppm] = name
	memoCount = memoCount + 1
end

-- Name(tile) -> base file name | nil, reason. Also what says whether a tile is valid: a level id, whole tx and ty, res a power of two from 4 to 4096, ppm > 0.
-- Only valid tiles are memoised, so a hit needs no check (the lookups below never allocate, also with a nil or NaN field).
function Cache.Name(tile)
	if type(tile) ~= "table" then
		return nil, "tile is not a table"
	end

	local level, tx, ty, res, ppm = tile.level, tile.tx, tile.ty, tile.res, tile.ppm
	local m = nameMemo[level]

	m = m and m[tx]
	m = m and m[ty]
	m = m and m[res]
	m = m and m[ppm]

	if m then
		return m
	end

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

	local name = "t_" .. lv .. "_" .. numberText(tx) .. "_" .. numberText(ty) .. "_" .. numberText(res) .. "_" .. numberText(ppm)

	memoise(level, tx, ty, res, ppm, name)

	return name
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

local function fileBytes(path)
	local size = file.Size(path, "DATA")

	return (size and size > 0) and size or 0
end

-- writes index.json from the in-memory sets; true | false, reason. The result is checked by the size on the disk: an old index that is still there would make a
-- plain "does it exist" check say yes after a failed write.
local function writeIndex()
	local list, empties = {}, {}

	for name in pairs(state.set) do
		if state.empty[name] then
			empties[#empties + 1] = name
		else
			list[#list + 1] = name
		end
	end

	table.sort(list)
	table.sort(empties)

	ensureDir(state.dir)

	local path = state.dir .. "/" .. INDEX_FILE
	local idx = {version = 1, key = state.key, tiles = list}

	if #empties > 0 then
		idx.empty = empties -- absent when there is none
	end

	local json = util.TableToJSON(idx)

	file.Write(path, json)

	if file.Size(path, "DATA") ~= #json or file.Read(path, "DATA") ~= json then
		return false, "cannot write " .. path
	end

	state.dirty = false
	state.pending = 0

	return true
end

-- a change of the index in memory: written when FLUSH_EVERY changes are waiting (a failure keeps it dirty: Flush reports it, the next change tries again)
local function markDirty()
	state.dirty = true
	state.pending = state.pending + 1

	if state.pending >= Cache.FLUSH_EVERY then
		writeIndex()
	end
end

-- Flush() -> true | false, reason: writes index.json now when it is dirty (Gen calls it when its queue is empty and at Cancel)
function Cache.Flush()
	if not state.loaded or not state.dirty then
		return true
	end

	return writeIndex()
end

-- the resolution written in a base name (the field before the last), or nil when the name is not the name of a valid tile
local function resOfName(name)
	local r = smatch(name, "^t_.+_n?%d+_n?%d+_(%d+)_[%dp]+$")

	r = r and tonumber(r)

	if r and r >= 4 and r <= 4096 and band(r, r - 1) == 0 then
		return r
	end

	return nil
end

-- the size a .vtf of this resolution has: the header and thumbnail, then DXT1 / DXT1A data (8 bytes per 4x4 block) or BGRA data (4 bytes a pixel)
local function sizeFits(res, size)
	local blocks = floor((res + 3) / 4)

	return size == HEADER_BYTES + blocks * blocks * 8 or size == HEADER_BYTES + res * res * 4
end

-- checks the files of a tile of the directory and registers it; true | false, corrupt (corrupt: the .vtf is there but has the wrong size)
local function adoptTile(name, dir)
	local res = resOfName(name)

	if not res then
		return false, false
	end

	local size = file.Size(dir .. "/" .. name .. ".vtf", "DATA")

	if not size or not sizeFits(res, size) then
		return false, true
	end

	state.set[name] = true
	state.size[name] = size + fileBytes(dir .. "/" .. name .. ".vmt")
	state.count = state.count + 1

	return true, false
end

local function validName(name)
	return type(name) == "string" and #name <= 200 and sfind(name, "^t_[a-z0-9_]+$") ~= nil
end

-- reads the directory and index.json once (see the header for the rules)
local function ensureIndex()
	if state.loaded then
		return
	end

	local key = currentKey()
	local dir = Cache.Dir(key)

	state.dir = dir
	state.loaded = true
	state.set = {}
	state.empty = {}
	state.size = {}
	state.count = 0
	state.dirty = false
	state.pending = 0

	local onDisk = {} -- base name -> true, the .vtf files of the directory

	for _, f in ipairs(file.Find(dir .. "/t_*.vtf", "DATA") or {}) do
		onDisk[ssub(f, 1, -5)] = true
	end

	local text = file.Read(dir .. "/" .. INDEX_FILE, "DATA")
	local idx = type(text) == "string" and util.JSONToTable(text) or nil
	local changed = false
	local tried = {}

	if type(idx) ~= "table" or idx.version ~= 1 or idx.key ~= key or type(idx.tiles) ~= "table" then
		idx = nil
		changed = text ~= nil -- a damaged index is written again; no index at all is not a change by itself
	end

	local function try(name)
		tried[name] = true

		local ok, corrupt = adoptTile(name, dir)

		if corrupt then
			-- a truncated or damaged file: it is made again
			file.Delete(dir .. "/" .. name .. ".vtf")
			file.Delete(dir .. "/" .. name .. ".vmt")
		end

		return ok
	end

	if idx then
		for _, name in ipairs(idx.tiles) do
			if not validName(name) then
				changed = true
			elseif not state.set[name] and not tried[name] then
				if not onDisk[name] or not try(name) then
					changed = true
				end
			end
		end
	end

	-- a .vtf the index does not list: the index is absent, damaged, or older than the last Stores
	for name in pairs(onDisk) do
		if not tried[name] and validName(name) and try(name) then
			changed = true
		end
	end

	-- the empty tiles have no file to check; the same name check, and a tile that has a file wins (the file is what is drawn)
	if idx and idx.empty ~= nil then
		if type(idx.empty) == "table" then
			for _, name in ipairs(idx.empty) do
				if validName(name) and resOfName(name) then
					if not state.set[name] then
						state.set[name] = true
						state.empty[name] = true
						state.count = state.count + 1
					end
				else
					changed = true
				end
			end
		else
			changed = true
		end
	end

	if changed then
		state.dirty = true

		writeIndex()
	end
end

-- Has(tile) -> bool. From memory only once the index is loaded (called at every draw).
function Cache.Has(tile)
	local name = Cache.Name(tile)

	if not name then
		return false
	end

	ensureIndex()

	if state.set[name] == true then
		state.clock = state.clock + 1
		state.access[name] = state.clock

		return true
	end

	return false
end

-- IsEmpty(tile) -> bool: the tile is known and entirely empty (it has no file)
function Cache.IsEmpty(tile)
	local name = Cache.Name(tile)

	if not name then
		return false
	end

	ensureIndex()

	return state.empty[name] == true
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

-- drops the material of a tile (by base name) and has the engine read its file again next time; also for a tile pushed out of the Lua table by the LRU
local function forgetName(name)
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

-- Forget(tile): see forgetName
function Cache.Forget(tile)
	local name = Cache.Name(tile)

	if not name then
		return
	end

	ensureIndex()
	forgetName(name)
end

-- drops the least recently used material (never `keep`)
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

-- evicts until the materials fit the capacity (never `keep`)
local function fitCapacity(keep)
	while state.matCount > capacity do
		local before = state.matCount

		evict(keep)

		if state.matCount == before then
			break
		end
	end
end

-- Capacity() -> number of materials kept in the Lua table
function Cache.Capacity()
	return capacity
end

-- SetCapacity(n) -> the capacity now: whole number from 16 to 512 (clamped; a value that is not a number changes nothing). A smaller capacity drops the surplus at once.
-- The View never asks for more tiles in one frame than this (a cyclic walk over more tiles than the capacity would miss every time).
function Cache.SetCapacity(n)
	if finite(n) then
		capacity = math.max(16, math.min(512, floor(n)))
		fitCapacity(nil)
	end

	return capacity
end

-- removes a tile from the cache: the index, the memory, the files (a tile whose file the engine cannot use is made again). Not for an empty tile's flags: it has no file.
local function removeTile(name)
	local entry = state.mats[name]

	if entry then
		state.mats[name] = nil
		state.matCount = state.matCount - 1
	end

	state.ever[name] = nil

	if state.set[name] then
		state.set[name] = nil
		state.count = state.count - 1
	end

	state.empty[name] = nil
	state.size[name] = nil
	state.access[name] = nil

	if state.lastStored == name then
		state.lastStored = nil
	end

	file.Delete(state.dir .. "/" .. name .. ".vtf")
	file.Delete(state.dir .. "/" .. name .. ".vmt")
	markDirty()
end

-- Material(tile) -> IMaterial | nil (tile missing, empty, or the engine gave nothing or an error material: then the tile is removed from the index to be made again)
function Cache.Material(tile)
	local name = Cache.Name(tile)

	if not name then
		return nil
	end

	ensureIndex()

	if not state.set[name] or state.empty[name] then
		return nil -- unknown, or entirely empty: there is no file, nothing to load
	end

	state.tick = state.tick + 1
	state.clock = state.clock + 1
	state.access[name] = state.clock

	local entry = state.mats[name]

	if entry then
		entry.stamp = state.tick

		return entry.mat
	end

	local mat = Material(materialPath(name))

	if not mat or mat:IsError() then
		removeTile(name)

		return nil
	end

	state.mats[name] = {mat = mat, stamp = state.tick}
	state.matCount = state.matCount + 1
	state.ever[name] = true

	fitCapacity(name)

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

-- Store(tile, bytes, format) -> true | false, reason. format: 13 DXT1 (default), 20 DXT1 with one bit of alpha, 12 BGRA8888; anything else is refused.
-- The index is only marked dirty (see the header): Flush writes it.
function Cache.Store(tile, data, format)
	local name, err = Cache.Name(tile)

	if not name then
		return false, err
	end

	if type(data) ~= "string" or data == "" then
		return false, "no image data"
	end

	if format == nil then
		format = 13
	elseif format ~= 12 and format ~= 13 and format ~= 20 then
		return false, "unsupported image format (12, 13 or 20 only)"
	end

	local VTF = GryMod.Minimap.VTF

	if type(VTF) ~= "table" or not VTF.Write or not VTF.WriteVMT then
		return false, "VTF module missing"
	end

	ensureIndex()

	local path = state.dir .. "/" .. name
	local known = state.set[name] == true
	local wasEmpty = state.empty[name] == true -- known, but with no file: a normal tile from now on
	local ok, werr = checked("VTF.Write", VTF.Write, path .. ".vtf", tile.res, tile.res, format, data)

	if ok then
		ok, werr = checked("VTF.WriteVMT", VTF.WriteVMT, path .. ".vmt", "../data/" .. path)
	end

	if not ok then
		if not known or wasEmpty then
			-- nothing half written is left behind for a tile that must have no file
			file.Delete(path .. ".vtf")
			file.Delete(path .. ".vmt")
		end

		return false, werr
	end

	if not known then
		state.set[name] = true
		state.count = state.count + 1
	end

	state.empty[name] = nil
	state.size[name] = fileBytes(path .. ".vtf") + fileBytes(path .. ".vmt")

	-- a tile the engine may hold already: it reads the new file now that it is there
	if state.mats[name] or state.ever[name] then
		forgetName(name)
	end

	state.clock = state.clock + 1
	state.access[name] = state.clock
	state.lastStored = name

	markDirty()

	return true
end

-- StoreEmpty(tile) -> true | false, reason. Records that the tile exists and is entirely empty (the map has nothing in it): no .vtf and no .vmt is written, only the
-- index. A tile that had files loses them (and its material is forgotten); a later Store makes it a normal tile again.
function Cache.StoreEmpty(tile)
	local name, err = Cache.Name(tile)

	if not name then
		return false, err
	end

	ensureIndex()

	local path = state.dir .. "/" .. name
	local known = state.set[name] == true

	if state.empty[name] then
		return true -- nothing changes: the index already says so
	end

	state.set[name] = true
	state.empty[name] = true

	if not known then
		state.count = state.count + 1
	else
		-- it had a file: the material is dropped, then the files go
		forgetName(name)
		state.size[name] = nil
		file.Delete(path .. ".vtf")
		file.Delete(path .. ".vmt")
	end

	state.clock = state.clock + 1
	state.access[name] = state.clock

	markDirty()

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
		state.empty = {}
		state.size = {}
		state.count = 0
		state.access = {}
		state.lastStored = nil
		state.dirty = false
		state.pending = 0
	end

	return true
end

-- Prune() -> number of cache directories removed: the other keys of the same map name, whatever their size or version (a map that changed size, and the opaque
-- "_v1" tiles of before the alpha). Never another map, never the current key. The version part is matched as "_v<digits>" on purpose.
function Cache.Prune()
	local key = currentKey()
	local mapName = smatch(key, "^(.+)_%d+_v%d+$")

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

-- ---------------------------------------------------------------------------------------------------------
-- KnownLevels, Trim
-- ---------------------------------------------------------------------------------------------------------

-- KnownLevels() -> sorted array of the level ids that have at least one tile (with a file or empty) in the index of the current key ({} without index).
-- The level is what stands between "t_" and the last four fields (tx, ty, res, ppm), which are numbers: it may itself contain underscores.
function Cache.KnownLevels()
	ensureIndex()

	local seen, list = {}, {}

	for name in pairs(state.set) do
		local level = smatch(name, "^t_(.+)_n?%d+_n?%d+_%d+_[%dp]+$")

		if level and not seen[level] then
			seen[level] = true
			list[#list + 1] = level
		end
	end

	table.sort(list)

	return list
end

-- Trim(maxBytes) -> {removed = n, bytes = bytes left} | nil, "bad limit". Limits the folder of the CURRENT key: the size is the sum of the .vtf and .vmt sizes remembered
-- at Store and at load (no disk call to count). Over the limit, the least recently used tiles go first (Store, Material and a Has that says yes count as a use; a tile that
-- was not used in this session is placed by the time of its .vtf file, and before every tile used in this session), until the size is at or under 90 % of the limit. The
-- tile Store wrote last is never removed. An empty tile has no file (0 bytes): removing it would free nothing and lose the fact that it is empty, so it is never a
-- candidate. The index is written at once, the materials of the removed tiles are forgotten.
-- (The access stamps are a counter and not RealTime(): Has runs at every draw and must not call the engine; only the order matters here.)
function Cache.Trim(maxBytes)
	if not finite(maxBytes) or maxBytes <= 0 then
		return nil, "bad limit"
	end

	ensureIndex()

	local dir = state.dir
	local entries, total = {}, 0

	for name in pairs(state.set) do
		if not state.empty[name] then
			local size = state.size[name] or 0
			local stamp = state.access[name]

			entries[#entries + 1] = {name = name, size = size, used = stamp ~= nil, order = stamp}
			total = total + size
		end
	end

	if total <= maxBytes then
		return {removed = 0, bytes = total}
	end

	-- the time of the file is only asked for the tiles not used in this session, and only now that something must go
	for _, e in ipairs(entries) do
		if not e.used then
			e.order = file.Time(dir .. "/" .. e.name .. ".vtf", "DATA") or 0
		end
	end

	-- the tiles not used in this session first (by file time), then the ones used (by stamp), oldest first; the name makes ties stable
	table.sort(entries, function(a, b)
		if a.used ~= b.used then
			return not a.used
		end

		if a.order ~= b.order then
			return a.order < b.order
		end

		return a.name < b.name
	end)

	local target = maxBytes * 0.9
	local removed = 0

	for _, e in ipairs(entries) do
		if total <= target then
			break
		end

		if e.name ~= state.lastStored then
			forgetName(e.name)
			removeTile(e.name)

			total = total - e.size
			removed = removed + 1
		end
	end

	if removed > 0 then
		writeIndex()
	end

	return {removed = removed, bytes = total}
end
