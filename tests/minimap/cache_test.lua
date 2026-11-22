-- Tests of the minimap cache (lua/grymod/client/minimap/cache.lua): the cache key, the tile geometry, the tile names, the index file, the
-- store of tiles, the materials (lazy, LRU of 64, Forget) and Clear / Prune. GLuaTest format, client realm.
-- The module under test is always reached as GryMod.Minimap.Cache at call time. The VTF module is owned by another agent: the cases that
-- do not test it install a stand-in (saved and put back in afterEach, inside a pcall, also when a case failed). The same goes for the globals
-- the cases replace (Material, game.GetMap, file.*, METRES_PER_UNIT) and for Cache.Key (replaced so that no test touches the real cache of the
-- map that is loaded). Every file written goes under data/grymod/minimap/test_* and is deleted before and after each case.

local ROOT = "grymod/minimap/"
local KEY_A = "test_mapa_1234_v2"

local function C()
	local cache = GryMod and GryMod.Minimap and GryMod.Minimap.Cache

	if not cache then
		error("GryMod.Minimap.Cache is missing", 2)
	end

	return cache
end

local function tile(level, tx, ty, res, ppm)
	return {level = level or "a1", tx = tx or 0, ty = ty or 0, res = res or 16, ppm = ppm or 4}
end

local function mkdirs(path)
	local dir = ""

	for part in string.gmatch(string.match(path, "^(.*)/[^/]*$") or "", "[^/]+") do
		dir = dir == "" and part or (dir .. "/" .. part)
		file.CreateDir(dir)
	end
end

-- removes every test directory (files first: a directory is deleted when empty)
local function wipe()
	local _, dirs = file.Find(ROOT .. "test_*", "DATA")

	for _, d in ipairs(dirs or {}) do
		local files = file.Find(ROOT .. d .. "/*", "DATA")

		for _, f in ipairs(files or {}) do
			file.Delete(ROOT .. d .. "/" .. f)
		end

		file.Delete(ROOT .. d)
	end
end

-- the current key of the cache is the one the case says; Reset forgets what the module had loaded for the previous one
local function useKey(state, key)
	state.key = key
	C().Key = function()
		return state.key
	end
	C().Reset()
end

-- the size of a real .vtf of this resolution in DXT1: 80 bytes of header + 128 of thumbnail, then 8 bytes for each 4x4 block (512 -> 131072 + 208), worked out here
-- independently of the module; with bgra = true the data is 4 bytes a pixel
local function vtfSizeFor(res, bgra)
	local blocks = math.max(1, math.ceil(res / 4))

	return 208 + (bgra and res * res * 4 or blocks * blocks * 8)
end

-- a stand-in of the VTF module: records its calls, writes small real files (the cache checks the disk), can be made to fail
local function installVTF(state)
	state.calls = {write = {}, vmt = {}}
	state.failWrite, state.failVMT = nil, nil -- the state table is shared by the cases of the file
	state.vtfSize = nil -- bytes written in a .vtf (the size of a real DXT1 file of that resolution by default); a case sets it after installVTF

	GryMod.Minimap.VTF = {
		FORMAT_BGRA8888 = 12,
		FORMAT_DXT1 = 13,
		Write = function(path, w, h, format, data)
			local list = state.calls.write
			list[#list + 1] = {path = path, w = w, h = h, format = format, data = data}

			if state.failWrite then
				return false, state.failWrite
			end

			mkdirs(path)
			file.Write(path, string.rep("x", state.vtfSize or vtfSizeFor(w)))

			return true
		end,
		WriteVMT = function(path, base)
			local list = state.calls.vmt
			list[#list + 1] = {path = path, base = base}

			if state.failVMT then
				return false, state.failVMT
			end

			mkdirs(path)
			file.Write(path, base)

			return true
		end
	}
end

-- a stand-in of the global Material: counts the loads, gives one fake material per path
local function installMaterial(state)
	state.loads = {}
	state.downloads = 0
	state.errorMaterial = false

	state.downloadSawFile = {} -- for each Download: did the .vtf of that material exist at that moment?

	Material = function(path)
		state.loads[#state.loads + 1] = path

		local texture = {
			Download = function()
				state.downloads = state.downloads + 1
				state.downloadSawFile[#state.downloadSawFile + 1] = state.origFile.Exists(string.gsub(path, "^%.%./data/", "") .. ".vtf", "DATA")
			end
		}

		return {
			IsError = function()
				return state.errorMaterial
			end,
			GetTexture = function(_, name)
				state.textureAsked = name

				return texture
			end,
			path = path
		}
	end
end

local function store(tl, data)
	return C().Store(tl, data or "dxt")
end

-- the bytes the .vtf and .vmt files of these tiles take on the disk, read by the test itself
local function diskBytes(tiles)
	local sum = 0

	for _, t in ipairs(tiles) do
		local path = C().Path(t)

		sum = sum + math.max(file.Size(path .. ".vtf", "DATA"), 0) + math.max(file.Size(path .. ".vmt", "DATA"), 0)
	end

	return sum
end

-- counts the calls of every file.* function the case saved in state.origFile (and passes them through); the originals are put back by afterEach
local function spyFile(state, counts)
	for name, fn in pairs(state.origFile) do
		counts[name] = 0

		file[name] = function(...)
			counts[name] = counts[name] + 1

			return fn(...)
		end
	end
end

-- 66 tiles in a row, stored through the stand-in VTF (Store is the only public way to fill the cache)
local function storeMany(n)
	local list = {}

	for i = 1, n do
		list[i] = tile("a1", i, 0)
		expect(store(list[i])).to.beTrue()
	end

	return list
end

return {
	groupName = "GryMod minimap cache (client)",
	beforeEach = function(state)
		state.origVTF = GryMod.Minimap.VTF
		state.origMaterial = Material
		state.origGetMap = game.GetMap
		state.origMPU = GryMod.RadarShared and GryMod.RadarShared.METRES_PER_UNIT
		state.origKey = GryMod.Minimap.Cache and GryMod.Minimap.Cache.Key
		state.origFile = {
			Exists = file.Exists,
			Read = file.Read,
			Size = file.Size,
			Find = file.Find,
			Open = file.Open,
			IsDir = file.IsDir,
			Time = file.Time,
			Write = file.Write
		}
		wipe()

		if GryMod.Minimap.Cache and GryMod.Minimap.Cache.Reset then
			GryMod.Minimap.Cache.Reset()
		end
	end,
	afterEach = function(state)
		pcall(collectgarbage, "restart") -- a case may have stopped the collector to count allocations

		pcall(function()
			GryMod.Minimap.VTF = state.origVTF
			Material = state.origMaterial
			game.GetMap = state.origGetMap

			for name, fn in pairs(state.origFile) do
				file[name] = fn
			end

			if GryMod.RadarShared then
				GryMod.RadarShared.METRES_PER_UNIT = state.origMPU
			end

			if GryMod.Minimap.Cache then
				if state.origKey then
					GryMod.Minimap.Cache.Key = state.origKey
				end

				if GryMod.Minimap.Cache.Reset then
					GryMod.Minimap.Cache.Reset()
				end

				if GryMod.Minimap.Cache.SetCapacity then
					GryMod.Minimap.Cache.SetCapacity(160) -- a case may have changed it
				end
			end
		end)

		pcall(wipe)
	end,
	cases = {
		-- (1) the key ---------------------------------------------------------------------------------------------------------------
		{
			-- fails if KeyFor does not lowercase, does not turn each odd byte into "_", does not add the size or the version
			name = "KeyFor sanitises the map name: lowercase, every byte outside [a-z0-9_] becomes an underscore, then _<size>_v2",
			func = function()
				expect(C().KeyFor("GM_Construct", 1234)).to.equal("gm_construct_1234_v2")
				expect(C().KeyFor("My Map-v2!", 7)).to.equal("my_map_v2__7_v2")
				expect(C().KeyFor("ab\xC3\xA9", 0)).to.equal("ab___0_v2") -- the two bytes of an accented letter give two underscores
				expect(C().KeyFor("../../x", 1)).to.equal("______x_1_v2") -- no path character survives
			end
		},
		{
			-- fails if a negative, missing or odd size is written as it is, or if an empty name makes an empty key
			name = "KeyFor: an unknown size (negative, nil, not a number) is 0, an empty or missing name is 'unknown'",
			func = function()
				expect(C().KeyFor("a", -1)).to.equal("a_0_v2")
				expect(C().KeyFor("a", nil)).to.equal("a_0_v2")
				expect(C().KeyFor("a", "12")).to.equal("a_0_v2")
				expect(C().KeyFor("", 5)).to.equal("unknown_5_v2")
				expect(C().KeyFor(nil, 5)).to.equal("unknown_5_v2")
			end
		},
		{
			-- fails if Key does not read the .bsp size (here a map that is not on disk: size 0, file.Size says -1)
			name = "Key: the size is 0 when the .bsp is unknown, the name comes from game.GetMap, the version is v2",
			func = function()
				game.GetMap = function()
					return "Test_Bogus Map"
				end
				C().Reset()

				expect(C().Key()).to.equal("test_bogus_map_0_v2")
			end
		},
		{
			-- fails if Key does not use file.Size("maps/<map>.bsp", "GAME")
			name = "Key: a map that ships (gm_construct) carries the size of its .bsp",
			func = function()
				local size = file.Size("maps/gm_construct.bsp", "GAME")

				expect(size).to.beGreaterThan(0)

				game.GetMap = function()
					return "gm_construct"
				end
				C().Reset()

				expect(C().Key()).to.equal("gm_construct_" .. size .. "_v2")
			end
		},
		{
			-- fails if Dir does not give a path relative to data/ in grymod/minimap/<key>
			name = "Dir: grymod/minimap/<key>, relative to data/ (the current key when none is given)",
			func = function()
				useKey({}, KEY_A)

				expect(C().Dir("abc_1_v2")).to.equal("grymod/minimap/abc_1_v2")
				expect(C().Dir()).to.equal("grymod/minimap/" .. KEY_A)
			end
		},
		-- (2) TileUnits ---------------------------------------------------------------------------------------------------------------
		{
			-- fails if the formula is not res / ppm / METRES_PER_UNIT; values worked out by hand: 1 / 0.01905 = 52.4934383
			name = "TileUnits = res / ppm / METRES_PER_UNIT: 512 px at 1 px/m, 1024 at 4, 2048 at 16 (worked out by hand)",
			func = function()
				expect(C().TileUnits(512, 1)).to.aboutEqual(26876.640, 0.01) -- 512 * 52.4934383
				expect(C().TileUnits(1024, 4)).to.aboutEqual(13438.320, 0.01) -- 256 * 52.4934383
				expect(C().TileUnits(2048, 16)).to.aboutEqual(6719.160, 0.01) -- 128 * 52.4934383
				expect(C().TileUnits(1024, 3)).to.aboutEqual(17917.760, 0.01) -- 341.3333 * 52.4934383
			end
		},
		{
			-- fails if the constant is copied into the module instead of being read at call time
			name = "TileUnits reads METRES_PER_UNIT at call time (not a copy made at load)",
			func = function()
				GryMod.RadarShared.METRES_PER_UNIT = 0.5

				expect(C().TileUnits(1024, 4)).to.equal(512)
				expect(C().TileUnits(512, 1)).to.equal(1024)
			end
		},
		{
			-- fails if a zero, negative or missing value goes through (a division by zero would give inf)
			name = "TileUnits refuses a bad definition (nil, 0, negative, NaN) instead of returning inf",
			func = function()
				local a, ea = C().TileUnits(0, 4)
				local b = C().TileUnits(1024, 0)
				local c = C().TileUnits(1024, -3)
				local d = C().TileUnits(nil, 4)
				local e = C().TileUnits(1024, 0 / 0)

				expect(a).to.beNil()
				expect(type(ea)).to.equal("string")
				expect(b).to.beNil()
				expect(c).to.beNil()
				expect(d).to.beNil()
				expect(e).to.beNil()
			end
		},
		-- (3) TileOf ------------------------------------------------------------------------------------------------------------------
		{
			-- exact tile edge: with 0.25 m per unit, 1024 px at 4 px/m is 1024 units, so every boundary is exact in floating point
			name = "TileOf: positive coordinates, the lower edge belongs to the tile, the upper edge to the next one",
			func = function()
				GryMod.RadarShared.METRES_PER_UNIT = 0.25

				local tx, ty = C().TileOf(100, 200, 1024, 4)
				expect(tx).to.equal(0)
				expect(ty).to.equal(0)

				tx, ty = C().TileOf(1024, 2048, 1024, 4)
				expect(tx).to.equal(1)
				expect(ty).to.equal(2)

				tx, ty = C().TileOf(1023.999, 2047.999, 1024, 4)
				expect(tx).to.equal(0)
				expect(ty).to.equal(1)
			end
		},
		{
			-- fails with math.floor replaced by a truncation (math.modf or a cast), which gives tile 0 for -0.001
			name = "TileOf: negative coordinates fall in the negative tiles (floor, not truncation)",
			func = function()
				GryMod.RadarShared.METRES_PER_UNIT = 0.25

				local tx, ty = C().TileOf(-0.001, -1, 1024, 4)
				expect(tx).to.equal(-1)
				expect(ty).to.equal(-1)

				tx, ty = C().TileOf(-1024, -1024.0001, 1024, 4)
				expect(tx).to.equal(-1) -- exactly on the edge: the tile that starts there
				expect(ty).to.equal(-2)

				tx, ty = C().TileOf(-3000, -5000, 1024, 4)
				expect(tx).to.equal(-3)
				expect(ty).to.equal(-5)
			end
		},
		{
			name = "TileOf: very large coordinates (1e12 units) stay exact on the edges",
			func = function()
				GryMod.RadarShared.METRES_PER_UNIT = 0.25

				local tx, ty = C().TileOf(1e12, -1e12, 1024, 4)

				expect(tx).to.equal(976562500) -- 1e12 / 1024
				expect(ty).to.equal(-976562500)
			end
		},
		{
			name = "TileOf refuses a coordinate that is not a finite number",
			func = function()
				expect(C().TileOf(nil, 0, 1024, 4)).to.beNil()
				expect(C().TileOf(0 / 0, 0, 1024, 4)).to.beNil()
				expect(C().TileOf(0, math.huge, 1024, 4)).to.beNil()
				expect(C().TileOf(0, 0, 1024, 0)).to.beNil()
			end
		},
		-- (4) TileBounds --------------------------------------------------------------------------------------------------------------
		{
			-- fails if the bounds are not [tx*T, (tx+1)*T) x [ty*T, (ty+1)*T)
			name = "TileBounds: {minx, miny, maxx, maxy} = tile index times the edge, for negative and positive tiles",
			func = function()
				GryMod.RadarShared.METRES_PER_UNIT = 0.25

				local b = C().TileBounds(tile("a1", -2, 3, 1024, 4))

				expect(b.minx).to.equal(-2048)
				expect(b.maxx).to.equal(-1024)
				expect(b.miny).to.equal(3072)
				expect(b.maxy).to.equal(4096)
			end
		},
		{
			-- fails if TileOf and TileBounds do not use the same edge or the same rounding (real constant, awkward edge length)
			name = "TileBounds is consistent with TileOf: the centre of a tile falls back in that tile, and its corners are inside or on the edge",
			func = function()
				local list = {
					tile("a1", 0, 0, 1024, 3), tile("a1", -1, -1, 1024, 3), tile("a1", 7, -5, 512, 1),
					tile("a1", -13, 22, 2048, 16), tile("a1", 100, 100, 1024, 4)
				}

				for _, t in ipairs(list) do
					local b = C().TileBounds(t)
					local tx, ty = C().TileOf((b.minx + b.maxx) / 2, (b.miny + b.maxy) / 2, t.res, t.ppm)

					expect(tx).to.equal(t.tx)
					expect(ty).to.equal(t.ty)
					expect(b.maxx - b.minx).to.aboutEqual(C().TileUnits(t.res, t.ppm), 0.001)
					expect(b.maxy - b.miny).to.aboutEqual(C().TileUnits(t.res, t.ppm), 0.001)
				end
			end
		},
		-- (5) Name / Path -------------------------------------------------------------------------------------------------------------
		{
			-- fails if a negative number is written with a minus sign (not allowed in the names) or without the n prefix
			name = "Name: t_<level>_<tx>_<ty>_<res>_<ppm>, negative numbers with an n prefix",
			func = function()
				expect(C().Name(tile("a1", 3, -2, 1024, 3))).to.equal("t_a1_3_n2_1024_3")
				expect(C().Name(tile("a1", -3, 2, 1024, 3))).to.equal("t_a1_n3_2_1024_3")
				expect(C().Name(tile("a1", 0, 0, 512, 16))).to.equal("t_a1_0_0_512_16")
				expect(C().Name(tile("a1", -10, -20, 2048, 1))).to.equal("t_a1_n10_n20_2048_1")
			end
		},
		{
			-- fails if the level id goes into the name as it is
			name = "Name: the level id is sanitised like the key (lowercase, [a-z0-9_] only)",
			func = function()
				expect(C().Name(tile("Fn 1", 0, 0))).to.equal("t_fn_1_0_0_16_4")
				expect(C().Name(tile("../A1", 0, 0))).to.equal("t____a1_0_0_16_4")
			end
		},
		{
			-- fails if two tiles that differ share a name (for example a - sign dropped, or 1_12 against 11_2)
			name = "Name: neighbouring tiles, mirrored tiles, other levels, other definitions all have different names",
			func = function()
				local seen, count = {}, 0

				local function add(t)
					seen[C().Name(t)] = true
					count = count + 1
				end

				for _, level in ipairs({"a1", "a2"}) do
					for tx = -3, 3 do
						for ty = -3, 3 do
							add(tile(level, tx, ty))
						end
					end
				end

				add(tile("a1", 1, 12))
				add(tile("a1", 11, 2))
				add(tile("a1", 1, 1, 512, 4))
				add(tile("a1", 1, 1, 1024, 3))

				local n = 0

				for _ in pairs(seen) do
					n = n + 1
				end

				expect(count).to.equal(102) -- 98 + 4 tiles that all differ
				expect(n).to.equal(count)
			end
		},
		{
			-- fails if a tile that is not valid gets a name (it would be written to a wrong file)
			name = "Name refuses a bad tile: no level, fractional index, res not a power of two, ppm 0, not a table",
			func = function()
				expect(C().Name({tx = 0, ty = 0, res = 16, ppm = 4})).to.beNil()
				expect(C().Name({level = "a1", tx = 0.5, ty = 0, res = 16, ppm = 4})).to.beNil()
				expect(C().Name({level = "a1", tx = 0, ty = 0, res = 1000, ppm = 4})).to.beNil()
				expect(C().Name({level = "a1", tx = 0, ty = 0, res = 16, ppm = 0})).to.beNil()
				expect(C().Name(nil)).to.beNil()
				expect(C().Name("t_a1")).to.beNil()
				expect(C().Name({level = "", tx = 0, ty = 0, res = 16, ppm = 4})).to.beNil()
			end
		},
		{
			name = "Path = <directory of the current key>/<name> without extension",
			func = function(state)
				useKey(state, KEY_A)

				expect(C().Path(tile("a1", 3, -2, 1024, 3))).to.equal("grymod/minimap/" .. KEY_A .. "/t_a1_3_n2_1024_3")
			end
		},
		-- (6) Has / Store / index -----------------------------------------------------------------------------------------------------
		{
			name = "Has is false for a tile that was never stored, whatever the index",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(C().Has(tile("a1", 1, 1))).to.beFalse()
				expect(C().Has(nil)).to.beFalse()
				expect(C().Has({})).to.beFalse()
			end
		},
		{
			-- fails if Store does not call VTF.Write then VTF.WriteVMT with the right path, size, format and basetexture
			name = "Store: VTF.Write (path .vtf, res x res, DXT1, the bytes) then VTF.WriteVMT (.vmt, basetexture ../data/<path>), then Has is true",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 3, -2, 16, 4)
				local base = "grymod/minimap/" .. KEY_A .. "/t_a1_3_n2_16_4"

				expect(C().Has(t)).to.beFalse()
				expect(C().Store(t, "BYTES")).to.beTrue()
				expect(C().Has(t)).to.beTrue()

				expect(#state.calls.write).to.equal(1)
				expect(state.calls.write[1].path).to.equal(base .. ".vtf")
				expect(state.calls.write[1].w).to.equal(16)
				expect(state.calls.write[1].h).to.equal(16)
				expect(state.calls.write[1].format).to.equal(13)
				expect(state.calls.write[1].data).to.equal("BYTES")
				expect(#state.calls.vmt).to.equal(1)
				expect(state.calls.vmt[1].path).to.equal(base .. ".vmt")
				expect(state.calls.vmt[1].base).to.equal("../data/" .. base)
			end
		},
		{
			-- fails if the format is not forwarded to VTF.Write (20 = DXT1 with one bit of alpha), or if the default is not DXT1 (13)
			name = "Store(tile, data, format): the default is 13 (DXT1), 20 (DXT1 with alpha) and 12 are forwarded to VTF.Write",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(C().Store(tile("a1", 1, 1), "x")).to.beTrue()
				expect(C().Store(tile("a1", 2, 1), "x", nil)).to.beTrue()
				expect(C().Store(tile("a1", 3, 1), "x", 20)).to.beTrue()
				expect(C().Store(tile("a1", 4, 1), "x", 12)).to.beTrue()
				expect(C().Store(tile("a1", 5, 1), "x", 13)).to.beTrue()

				expect(state.calls.write[1].format).to.equal(13)
				expect(state.calls.write[2].format).to.equal(13)
				expect(state.calls.write[3].format).to.equal(20)
				expect(state.calls.write[4].format).to.equal(12)
				expect(state.calls.write[5].format).to.equal(13)
				expect(C().Count()).to.equal(5)
			end
		},
		{
			-- fails if any number is passed on to the VTF module (it would be written under a wrong format)
			name = "Store refuses a format other than 12, 13 or 20 (false, reason), writes nothing and leaves the index alone",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				for _, bad in ipairs({0, 7, 14, 19, 21, -1, 13.5, "13", true, {}}) do
					local ok, err = C().Store(t, "x", bad)

					expect(ok).to.beFalse()
					expect(type(err)).to.equal("string")
				end

				expect(#state.calls.write).to.equal(0)
				expect(C().Has(t)).to.beFalse()
				expect(C().Count()).to.equal(0)
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if the index file is not written, or lacks the version, the key or the tile name
			name = "Store writes index.json: {version = 1, key, tiles = {<base>...}}",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("a1", 3, -2))).to.beTrue()
				expect(store(tile("a2", 0, 0))).to.beTrue()
				expect(C().Flush()).to.beTrue() -- the index is written in batches: Flush writes it now

				local text = file.Read(ROOT .. KEY_A .. "/index.json", "DATA")

				expect(type(text)).to.equal("string")

				local idx = util.JSONToTable(text)

				expect(idx.version).to.equal(1)
				expect(idx.key).to.equal(KEY_A)
				expect(#idx.tiles).to.equal(2)

				local names = {}

				for _, n in ipairs(idx.tiles) do
					names[n] = true
				end

				expect(names[C().Name(tile("a1", 3, -2))]).to.beTrue()
				expect(names[C().Name(tile("a2", 0, 0))]).to.beTrue()
			end
		},
		{
			-- fails if the index is only kept in memory (nothing is read back from disk)
			name = "a new load of the index (Reset) finds the stored tiles again, and only those",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("a1", 1, 1))).to.beTrue()
				expect(store(tile("a1", 1, 2))).to.beTrue()

				C().Reset()

				expect(C().Has(tile("a1", 1, 1))).to.beTrue()
				expect(C().Has(tile("a1", 1, 2))).to.beTrue()
				expect(C().Has(tile("a1", 1, 3))).to.beFalse()
				expect(C().Count()).to.equal(2)
			end
		},
		{
			-- fails if a tile whose .vtf is gone stays in the index
			name = "a tile listed in the index whose .vtf was deleted by hand disappears at load",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t1, t2 = tile("a1", 1, 1), tile("a1", 2, 2)

				expect(store(t1)).to.beTrue()
				expect(store(t2)).to.beTrue()

				file.Delete(C().Path(t1) .. ".vtf")
				C().Reset()

				expect(C().Has(t1)).to.beFalse()
				expect(C().Has(t2)).to.beTrue()
				expect(C().Count()).to.equal(1)
			end
		},
		{
			-- fails if a damaged index.json crashes the load, or if a name of it that is not a tile name is trusted (a way out of the directory).
			-- The index is rebuilt from the .vtf files of the directory, so the real tile is still there whatever the index says.
			name = "a damaged index.json, one of another key or version, or one with strange names: no error, only real tiles, the index is rebuilt from the directory",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()

				local path = ROOT .. KEY_A .. "/index.json"

				file.Write(path, "this is { not json")
				C().Reset()
				expect(C().Has(t)).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(util.JSONToTable(file.Read(path, "DATA")).key).to.equal(KEY_A) -- written again

				file.Write(path, util.TableToJSON({version = 1, key = "test_other_1_v2", tiles = {C().Name(t)}}))
				C().Reset()
				expect(C().Has(t)).to.beTrue()
				expect(C().Count()).to.equal(1)

				file.Write(path, util.TableToJSON({version = 2, key = KEY_A, tiles = {C().Name(t)}}))
				C().Reset()
				expect(C().Has(t)).to.beTrue()

				file.Write(path, util.TableToJSON({version = 1, key = KEY_A, tiles = {"../../evil", 12, "t_nothing_there_1_1_16_4", C().Name(t)}}))
				C().Reset()
				expect(C().Count()).to.equal(1) -- the evil name, the number and the tile without a file are not tiles
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			-- fails if a second Store of the same tile is counted twice or listed twice
			name = "Store of the same tile twice: one entry in the index, Count stays 1",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(store(t, "second")).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(1)
				expect(state.calls.write[2].data).to.equal("second")
			end
		},
		{
			-- fails if Has asks the engine (disk, map name) each time: it is called at every draw
			name = "Has works from memory: no file.* call and no game.GetMap call once the index is loaded",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				C().Has(t) -- the first call may load the index

				local touched = 0
				local function spy()
					touched = touched + 1
				end

				for name in pairs(state.origFile) do
					file[name] = function(...)
						spy()

						return state.origFile[name](...)
					end
				end

				game.GetMap = function()
					spy()

					return state.origGetMap()
				end

				for _ = 1, 200 do
					C().Has(t)
				end

				C().Has(tile("a1", 9, 9))

				expect(touched).to.equal(0)
			end
		},
		-- (7) Store refuses / propagates ----------------------------------------------------------------------------------------------
		{
			-- fails if Store accepts anything as bytes (an empty file would be a corrupt VTF)
			name = "Store refuses data that is not a non-empty string, and a bad tile, without writing anything",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)
				local ok, err = C().Store(t, nil)

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")
				expect(C().Store(t, "")).to.beFalse()
				expect(C().Store(t, 12)).to.beFalse()
				expect(C().Store(t, {})).to.beFalse()
				expect(C().Store({level = "a1", tx = 0, ty = 0, res = 1000, ppm = 4}, "x")).to.beFalse()
				expect(C().Store(nil, "x")).to.beFalse()

				expect(#state.calls.write).to.equal(0)
				expect(C().Has(t)).to.beFalse()
				expect(C().Count()).to.equal(0)
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if the error of VTF.Write is swallowed, or if the failed tile ends up in the index
			name = "a failing VTF.Write: Store returns its error, the tile is not in the index, the index of the others is intact",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local good, bad = tile("a1", 1, 1), tile("a1", 2, 2)

				expect(store(good)).to.beTrue()

				state.failWrite = "disk full"

				local ok, err = C().Store(bad, "x")

				expect(ok).to.beFalse()
				expect(err).to.equal("disk full")
				expect(C().Has(bad)).to.beFalse()
				expect(C().Has(good)).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(1)

				C().Reset()
				expect(C().Has(bad)).to.beFalse()
				expect(C().Has(good)).to.beTrue()
			end
		},
		{
			name = "a failing VTF.WriteVMT: Store returns its error and the tile is not in the index",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				state.failVMT = "no vmt"

				local t = tile("a1", 1, 1)
				local ok, err = C().Store(t, "x")

				expect(ok).to.beFalse()
				expect(err).to.equal("no vmt")
				expect(C().Has(t)).to.beFalse()

				C().Reset()
				expect(C().Has(t)).to.beFalse()
			end
		},
		{
			-- fails if the missing module makes Store raise instead of returning false
			name = "Store without the VTF module (nil) answers false, 'reason', and does not raise",
			func = function(state)
				useKey(state, KEY_A)

				GryMod.Minimap.VTF = nil

				local ok, err = C().Store(tile("a1", 1, 1), "x")

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")
			end
		},
		{
			name = "Store catches an error raised by VTF.Write (returns false, message)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				GryMod.Minimap.VTF.Write = function()
					error("exploded")
				end

				local ok, err = C().Store(tile("a1", 1, 1), "x")

				expect(ok).to.beFalse()
				expect(string.find(err, "exploded", 1, true) ~= nil).to.beTrue()
				expect(C().Count()).to.equal(0)
			end
		},
		-- (8) Material ----------------------------------------------------------------------------------------------------------------
		{
			-- fails if Material loads a material for a tile that is not in the cache (it would be an error material by name)
			name = "Material of a tile that is not in the cache is nil and does not call the engine",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				expect(C().Material(tile("a1", 1, 1))).to.beNil()
				expect(C().Material(nil)).to.beNil()
				expect(#state.loads).to.equal(0)
			end
		},
		{
			-- fails if the material is loaded at each call, or with another path than ../data/<path without extension>
			name = "Material loads lazily, once: two calls, one Material('../data/<path>')",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 3, -2)

				expect(store(t)).to.beTrue()
				expect(#state.loads).to.equal(0) -- Store alone does not load anything

				local m1 = C().Material(t)
				local m2 = C().Material(t)

				expect(m1 ~= nil).to.beTrue()
				expect(m2 == m1).to.beTrue()
				expect(#state.loads).to.equal(1)
				expect(state.loads[1]).to.equal("../data/grymod/minimap/" .. KEY_A .. "/t_a1_3_n2_16_4")
			end
		},
		{
			-- fails if an error material is returned (the radar would draw the purple and black checkerboard)
			name = "Material is nil when the engine gives an error material (IsError)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()

				state.errorMaterial = true
				expect(C().Material(t)).to.beNil()
			end
		},
		{
			-- fails if the engine is asked again at every frame for a tile whose file it cannot use (the tile must leave the index to be made again)
			name = "Material for a tile of the index that the engine cannot use (IsError) removes it from the index and the disk: no second engine call, a new Store works",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t, other = tile("a1", 1, 1), tile("a1", 2, 2)

				expect(store(t)).to.beTrue()
				expect(store(other)).to.beTrue()

				state.errorMaterial = true
				expect(C().Material(t)).to.beNil()
				expect(#state.loads).to.equal(1)

				-- the failure is remembered: the tile is no longer known, so no further engine call at all
				expect(C().Material(t)).to.beNil()
				expect(C().Material(t)).to.beNil()
				expect(#state.loads).to.equal(1)
				expect(C().Has(t)).to.beFalse()
				expect(C().Count()).to.equal(1)
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()
				expect(file.Exists(C().Path(t) .. ".vmt", "DATA")).to.beFalse()
				expect(C().Has(other)).to.beTrue() -- the others are untouched

				-- it is made again: a Store brings it back, and its material loads
				state.errorMaterial = false
				expect(store(t)).to.beTrue()
				expect(C().Material(t) ~= nil).to.beTrue()

				-- and it stays gone after a reload when the index was written in between
				expect(C().Flush()).to.beTrue()
				C().Reset()
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			name = "Material is nil when the engine gives nothing at all, and the tile is removed from the index",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local calls = 0

				Material = function()
					calls = calls + 1

					return nil
				end

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Material(t)).to.beNil()
				expect(C().Material(t)).to.beNil()
				expect(calls).to.equal(1)
				expect(C().Has(t)).to.beFalse()
			end
		},
		{
			-- fails with the old limit of 64: a cyclic walk over 100 tiles would miss every time
			name = "Capacity: 160 materials by default, SetCapacity clamps to 16..512 and ignores what is not a number",
			func = function()
				expect(C().MAX_MATERIALS).to.equal(160)
				expect(C().Capacity()).to.equal(160)

				expect(C().SetCapacity(300)).to.equal(300)
				expect(C().Capacity()).to.equal(300)
				expect(C().SetCapacity(3)).to.equal(16)
				expect(C().SetCapacity(100000)).to.equal(512)
				expect(C().SetCapacity(40.9)).to.equal(40)
				expect(C().SetCapacity(nil)).to.equal(40) -- unchanged
				expect(C().SetCapacity("200")).to.equal(40)
				expect(C().SetCapacity(0 / 0)).to.equal(40)
				expect(C().SetCapacity(160)).to.equal(160)
			end
		},
		{
			-- the walk of the radar: more tiles than the old limit of 64 but fewer than the capacity are all kept
			name = "a cyclic walk over 100 tiles loads each material once with the default capacity",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local list = storeMany(100)

				for _ = 1, 3 do
					for i = 1, 100 do
						expect(C().Material(list[i]) ~= nil).to.beTrue()
					end
				end

				expect(#state.loads).to.equal(100)
			end
		},
		{
			-- fails with no limit (17 loads kept) or with a limit that is not the capacity
			name = "LRU: the capacity is kept; one more pushes out the oldest, which is loaded again when asked",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				expect(C().SetCapacity(16)).to.equal(16)

				local list = storeMany(17)

				for i = 1, 16 do
					expect(C().Material(list[i]) ~= nil).to.beTrue()
				end

				expect(#state.loads).to.equal(16)

				for i = 1, 16 do
					C().Material(list[i])
				end

				expect(#state.loads).to.equal(16) -- all 16 are kept

				C().Material(list[17])
				expect(#state.loads).to.equal(17)

				C().Material(list[1]) -- the oldest was dropped
				expect(#state.loads).to.equal(18)
				expect(state.loads[18]).to.equal("../data/" .. C().Path(list[1]))
			end
		},
		{
			-- fails if the order is the order of loading (FIFO) instead of the order of last use
			name = "LRU: a tile used again is the youngest; the one dropped is the least recently used",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				C().SetCapacity(16)

				local list = storeMany(17)

				for i = 1, 16 do
					C().Material(list[i])
				end

				C().Material(list[1]) -- 1 becomes the youngest, 2 the oldest
				C().Material(list[17]) -- pushes 2 out
				expect(#state.loads).to.equal(17)

				C().Material(list[1])
				expect(#state.loads).to.equal(17) -- still there

				C().Material(list[2])
				expect(#state.loads).to.equal(18) -- dropped, loaded again
			end
		},
		{
			-- fails if a smaller capacity only applies to the next load (the surplus would stay)
			name = "SetCapacity to a smaller value drops the surplus at once, the least recently used first",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local list = storeMany(20)

				for i = 1, 20 do
					C().Material(list[i])
				end

				expect(#state.loads).to.equal(20)

				C().SetCapacity(16) -- 4 go: the first four

				C().Material(list[20])
				C().Material(list[5])
				expect(#state.loads).to.equal(20) -- 5 and 20 are still there

				C().Material(list[1])
				expect(#state.loads).to.equal(21) -- 1 was dropped
			end
		},
		{
			-- fails if Forget does not call Download on $basetexture, or calls it more than once
			name = "Forget drops the material and calls Download on its $basetexture once; the next Material loads it again",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				C().Material(t)
				expect(state.downloads).to.equal(0)

				C().Forget(t)
				expect(state.downloads).to.equal(1)
				expect(state.textureAsked).to.equal("$basetexture")

				C().Material(t)
				expect(#state.loads).to.equal(2)
			end
		},
		{
			name = "Forget of a tile never loaded does nothing (no Download, no error, no load)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				C().Forget(t)
				C().Forget(tile("a1", 9, 9))
				C().Forget(nil)

				expect(state.downloads).to.equal(0)
				expect(#state.loads).to.equal(0)
			end
		},
		{
			-- fails if a tile pushed out of the Lua table is forgotten for good: the engine still holds its texture, a rewrite would not be read
			name = "Forget of a tile that was loaded once but pushed out by the LRU still asks the engine to read the file again",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				C().SetCapacity(16)

				local list = storeMany(17)

				for i = 1, 17 do
					C().Material(list[i])
				end

				state.downloads = 0
				C().Forget(list[1]) -- pushed out of the table when the 17th came in

				expect(state.downloads).to.equal(1)
			end
		},
		{
			-- fails if Store does not call Forget before a rewrite of a tile that is loaded
			name = "Store over a tile that is loaded as a material calls Forget (one Download), and the next Material loads the new file",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				C().Material(t)
				expect(state.downloads).to.equal(0)

				expect(store(t, "new bytes")).to.beTrue()
				expect(state.downloads).to.equal(1)
				expect(state.downloadSawFile[1]).to.beTrue() -- asked after the new files were written

				C().Material(t)
				expect(#state.loads).to.equal(2)
			end
		},
		{
			-- fails if Forget is called before the write: after a Clear the Download would be asked for a file that is not there (the engine keeps the old texture)
			name = "Store after a Clear asks the engine to read the file again only once the new file is on the disk",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Material(t) ~= nil).to.beTrue()
				expect(C().Clear()).to.beTrue()
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()
				expect(state.downloads).to.equal(0)

				expect(store(t)).to.beTrue()
				expect(state.downloads).to.equal(1)
				expect(state.downloadSawFile[1]).to.beTrue()
			end
		},
		{
			-- the failure case: nothing was written, the engine is not asked to read anything
			name = "a failing Store calls no Download (the files were not rewritten)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Material(t) ~= nil).to.beTrue()

				state.failVMT = "no vmt"
				expect(C().Store(t, "x")).to.beFalse()
				expect(state.downloads).to.equal(0)
			end
		},
		{
			name = "Store of a new tile (nothing loaded) calls no Download",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				expect(store(tile("a1", 1, 1))).to.beTrue()
				expect(state.downloads).to.equal(0)
			end
		},
		-- (9) Clear / Prune -----------------------------------------------------------------------------------------------------------
		{
			-- fails if Clear removes other keys' files, or leaves a file of its own key
			name = "Clear(key) deletes the .vtf, .vmt and index.json of that key only, and its in-memory index when it is the current key",
			func = function(state)
				installVTF(state)

				local t1, t2 = tile("a1", 1, 1), tile("a1", 2, 2)
				local KEY_B = "test_mapb_55_v2"

				useKey(state, KEY_A)
				expect(store(t1)).to.beTrue()
				expect(store(t2)).to.beTrue()
				local dirA = C().Dir(KEY_A)
				local pathA1, pathA2 = C().Path(t1), C().Path(t2)

				useKey(state, KEY_B)
				expect(store(t1)).to.beTrue()
				expect(C().Flush()).to.beTrue()
				local pathB1 = C().Path(t1)

				-- B is the current key: clearing A (another key) leaves the memory alone
				expect(C().Clear(KEY_A)).to.beTrue()
				expect(file.Exists(pathA1 .. ".vtf", "DATA")).to.beFalse()
				expect(file.Exists(pathA1 .. ".vmt", "DATA")).to.beFalse()
				expect(file.Exists(pathA2 .. ".vtf", "DATA")).to.beFalse()
				expect(file.Exists(pathA2 .. ".vmt", "DATA")).to.beFalse()
				expect(file.Exists(dirA .. "/index.json", "DATA")).to.beFalse()
				expect(file.Exists(pathB1 .. ".vtf", "DATA")).to.beTrue()
				expect(file.Exists(pathB1 .. ".vmt", "DATA")).to.beTrue()
				expect(file.Exists(C().Dir(KEY_B) .. "/index.json", "DATA")).to.beTrue()
				expect(C().Has(t1)).to.beTrue()
				expect(C().Count()).to.equal(1)

				-- clearing the current key empties the memory too
				expect(C().Clear(KEY_B)).to.beTrue()
				expect(file.Exists(pathB1 .. ".vtf", "DATA")).to.beFalse()
				expect(C().Has(t1)).to.beFalse()
				expect(C().Count()).to.equal(0)

				-- and a later Reset does not bring it back
				C().Reset()
				expect(C().Has(t1)).to.beFalse()
			end
		},
		{
			name = "Clear() without argument clears the current key",
			func = function(state)
				installVTF(state)
				useKey(state, KEY_A)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Clear()).to.beTrue()
				expect(C().Has(t)).to.beFalse()
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if Clear leaves the directory's other files alone no more: it must remove tile files and the index, nothing else
			name = "Clear refuses a key that is not a plain key (path characters) and leaves unrelated files of the directory",
			func = function(state)
				installVTF(state)
				useKey(state, KEY_A)

				expect(store(tile("a1", 1, 1))).to.beTrue()
				file.Write(C().Dir(KEY_A) .. "/keep_me.txt", "x")

				local ok, err = C().Clear("../minimap")

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")
				expect(C().Clear("a/b")).to.beFalse()
				expect(C().Clear("")).to.beFalse()
				expect(C().Has(tile("a1", 1, 1))).to.beTrue()

				expect(C().Clear(KEY_A)).to.beTrue()
				expect(file.Exists(C().Dir(KEY_A) .. "/keep_me.txt", "DATA")).to.beTrue()
			end
		},
		{
			-- fails if Prune touches another map (even one whose name starts with ours) or the current key, or leaves another size of our map
			name = "Prune deletes the other keys of the SAME map (changed size) and spares the current key, other maps, and a map whose name extends ours",
			func = function(state)
				installVTF(state)

				local t = tile("a1", 1, 1)
				local keys = {
					current = "test_mapa_100_v2",
					old1 = "test_mapa_200_v2",
					old2 = "test_mapa_300_v2",
					other = "test_mapb_100_v2",
					longer = "test_mapa_v2_100_v2"
				}
				local paths = {}

				for name, key in pairs(keys) do
					useKey(state, key)
					expect(store(t)).to.beTrue()
					paths[name] = C().Path(t) .. ".vtf"
				end

				useKey(state, keys.current)

				expect(C().Prune()).to.equal(2)

				expect(file.Exists(paths.old1, "DATA")).to.beFalse()
				expect(file.Exists(paths.old2, "DATA")).to.beFalse()
				expect(file.Exists(paths.current, "DATA")).to.beTrue()
				expect(file.Exists(paths.other, "DATA")).to.beTrue()
				expect(file.Exists(paths.longer, "DATA")).to.beTrue()
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			-- fails if the version part of a key is compared (the _v1 tiles are opaque and stale) or if Prune stops at the same size
			name = "Prune treats the _v1 keys of the same map as stale (even with the same size), and spares the _v1 and _v2 keys of other maps",
			func = function(state)
				installVTF(state)

				local t = tile("a1", 1, 1)
				local keys = {
					current = "test_mapa_100_v2",
					sameSizeV1 = "test_mapa_100_v1",
					otherSizeV1 = "test_mapa_90_v1",
					otherSizeV2 = "test_mapa_80_v2",
					otherMapV1 = "test_mapb_100_v1",
					otherMapV2 = "test_mapb_100_v2"
				}
				local paths = {}

				for name, key in pairs(keys) do
					useKey(state, key)
					expect(store(t)).to.beTrue()
					paths[name] = C().Path(t) .. ".vtf"
				end

				useKey(state, keys.current)

				expect(C().Prune()).to.equal(3)

				expect(file.Exists(paths.sameSizeV1, "DATA")).to.beFalse()
				expect(file.Exists(paths.otherSizeV1, "DATA")).to.beFalse()
				expect(file.Exists(paths.otherSizeV2, "DATA")).to.beFalse()
				expect(file.Exists(paths.current, "DATA")).to.beTrue()
				expect(file.Exists(paths.otherMapV1, "DATA")).to.beTrue()
				expect(file.Exists(paths.otherMapV2, "DATA")).to.beTrue()
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			name = "Prune with nothing to delete returns 0 and does not touch the current cache",
			func = function(state)
				installVTF(state)
				useKey(state, KEY_A)

				expect(store(tile("a1", 1, 1))).to.beTrue()
				expect(C().Prune()).to.equal(0)
				expect(C().Count()).to.equal(1)
			end
		},
		-- (10) Count ------------------------------------------------------------------------------------------------------------------
		{
			name = "Count: 0 at first, one more per different tile, unchanged for a tile stored again, back to 0 after Clear",
			func = function(state)
				installVTF(state)
				useKey(state, KEY_A)

				expect(C().Count()).to.equal(0)
				expect(store(tile("a1", 1, 1))).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(store(tile("a1", 2, 1))).to.beTrue()
				expect(store(tile("a2", 2, 1))).to.beTrue()
				expect(C().Count()).to.equal(3)
				expect(store(tile("a1", 2, 1))).to.beTrue()
				expect(C().Count()).to.equal(3)
				expect(C().Clear()).to.beTrue()
				expect(C().Count()).to.equal(0)
			end
		},
		-- KnownLevels -----------------------------------------------------------------------------------------------------------------
		{
			-- fails if the level is cut at the first underscore, or if a number field is taken for part of the level
			name = "KnownLevels: the level ids of the index, sorted, without duplicates (negative tiles, 'open', an id with an underscore, a fractional ppm)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("f96t184", 1, 1))).to.beTrue()
				expect(store(tile("f96t184", -4, 7))).to.beTrue() -- same level again
				expect(store(tile("f96t184", 2, 2, 512, 1))).to.beTrue()
				expect(store(tile("fn96tn8", -1, -1))).to.beTrue()
				expect(store(tile("open", 0, 0, 1024, 2.5))).to.beTrue()
				expect(store(tile("a_b", 3, 3))).to.beTrue()

				local levels = C().KnownLevels()

				expect(#levels).to.equal(4)
				expect(levels[1]).to.equal("a_b")
				expect(levels[2]).to.equal("f96t184")
				expect(levels[3]).to.equal("fn96tn8")
				expect(levels[4]).to.equal("open")

				-- the same after a new load of the index from the disk
				C().Reset()
				levels = C().KnownLevels()

				expect(#levels).to.equal(4)
				expect(levels[2]).to.equal("f96t184")
			end
		},
		{
			name = "KnownLevels without any tile (no index, or after Clear) is an empty array",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local levels = C().KnownLevels()

				expect(type(levels)).to.equal("table")
				expect(#levels).to.equal(0)

				expect(store(tile("open", 0, 0))).to.beTrue()
				expect(#C().KnownLevels()).to.equal(1)
				expect(C().Clear()).to.beTrue()
				expect(#C().KnownLevels()).to.equal(0)
			end
		},
		{
			-- fails if the levels of another key (another map) leak in, or a tile whose Store failed is listed
			name = "KnownLevels lists only the current key, and not a tile whose Store failed",
			func = function(state)
				installVTF(state)
				useKey(state, "test_mapb_55_v2")
				expect(store(tile("other", 0, 0))).to.beTrue()

				useKey(state, KEY_A)
				expect(store(tile("mine", 0, 0))).to.beTrue()

				state.failWrite = "disk full"
				expect(C().Store(tile("failed", 0, 0), "x")).to.beFalse()

				local levels = C().KnownLevels()

				expect(#levels).to.equal(1)
				expect(levels[1]).to.equal("mine")
			end
		},
		-- Trim ------------------------------------------------------------------------------------------------------------------------
		{
			-- fails if Trim deletes something while the folder is under the limit
			name = "Trim under the limit removes nothing and reports the size of the folder (.vtf + .vmt of the index)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {tile("a1", 1, 1), tile("a1", 2, 1), tile("a1", 3, 1)}

				for _, t in ipairs(list) do
					expect(store(t)).to.beTrue()
				end

				local r = C().Trim(1000000)

				expect(r.removed).to.equal(0)
				expect(r.bytes).to.equal(diskBytes(list))
				expect(r.bytes).to.beGreaterThan(3 * 336) -- the .vmt files count too

				for _, t in ipairs(list) do
					expect(C().Has(t)).to.beTrue()
				end
			end
		},
		{
			-- fails if Trim keeps the oldest, stops at the limit instead of 90 % of it, or leaves the index and the files out of step
			name = "Trim over the limit removes the oldest tiles first, down to under 90 % of the limit, and keeps the index consistent",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {}

				for i = 1, 5 do
					list[i] = tile("a1", i, 1)
					expect(store(list[i])).to.beTrue()
				end

				local before = diskBytes(list)
				local limit = 1110
				local r = C().Trim(limit)

				expect(before).to.beGreaterThan(limit)
				expect(r.removed).to.equal(3) -- 390 bytes a tile (336 of .vtf + 54 of .vmt): two are left (780 <= 999), three are not (1170 > 999)
				expect(r.bytes).to.beLessThan(limit * 0.9 + 1)
				expect(r.bytes).to.equal(diskBytes({list[4], list[5]}))

				for i = 1, 3 do
					expect(C().Has(list[i])).to.beFalse()
					expect(file.Exists(C().Path(list[i]) .. ".vtf", "DATA")).to.beFalse()
					expect(file.Exists(C().Path(list[i]) .. ".vmt", "DATA")).to.beFalse()
				end

				for i = 4, 5 do
					expect(C().Has(list[i])).to.beTrue()
					expect(file.Exists(C().Path(list[i]) .. ".vtf", "DATA")).to.beTrue()
				end

				expect(C().Count()).to.equal(2)

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(2)

				C().Reset()
				expect(C().Count()).to.equal(2)
				expect(C().Has(list[5])).to.beTrue()
				expect(C().Has(list[1])).to.beFalse()
			end
		},
		{
			-- fails if the order is the order of writing instead of the last access (Has / Material count as an access)
			name = "Trim removes the least recently used: a tile that was drawn (Has) after the others were written survives",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {}

				for i = 1, 4 do
					list[i] = tile("a1", i, 1)
					expect(store(list[i])).to.beTrue()
				end

				expect(C().Has(list[1])).to.beTrue() -- the oldest written is now the youngest used

				local r = C().Trim(1110) -- 4 x 390 = 1560 > 1110: two go (780 <= 999)

				expect(r.removed).to.equal(2)
				expect(C().Has(list[1])).to.beTrue()
				expect(C().Has(list[4])).to.beTrue()
				expect(C().Has(list[2])).to.beFalse()
				expect(C().Has(list[3])).to.beFalse()
			end
		},
		{
			name = "Trim: a tile whose material was asked (Material) counts as used",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local list = {}

				for i = 1, 4 do
					list[i] = tile("a1", i, 1)
					expect(store(list[i])).to.beTrue()
				end

				expect(C().Material(list[2]) ~= nil).to.beTrue()
				expect(C().Trim(1110).removed).to.equal(2)

				expect(C().Has(list[2])).to.beTrue()
				expect(C().Has(list[4])).to.beTrue()
				expect(C().Has(list[1])).to.beFalse()
				expect(C().Has(list[3])).to.beFalse()
			end
		},
		{
			-- fails if the tile Store just wrote can be removed (the generator trims right after a Store)
			name = "Trim never removes the tile that was written last, even when the limit is smaller than the folder of that tile alone",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {tile("a1", 1, 1), tile("a1", 2, 1), tile("a1", 3, 1)}

				for _, t in ipairs(list) do
					expect(store(t)).to.beTrue()
				end

				expect(C().Has(list[3])).to.beTrue()
				expect(C().Has(list[1])).to.beTrue() -- list[1] is the last one USED, list[3] the last one WRITTEN

				local r = C().Trim(1)

				expect(r.removed).to.equal(2)
				expect(C().Has(list[3])).to.beTrue()
				expect(C().Has(list[1])).to.beFalse()
				expect(C().Has(list[2])).to.beFalse()
				expect(file.Exists(C().Path(list[3]) .. ".vtf", "DATA")).to.beTrue()
				expect(r.bytes).to.equal(diskBytes({list[3]}))
			end
		},
		{
			-- fails if the loaded materials of the removed tiles are not forgotten (the engine would keep serving the deleted texture)
			name = "Trim calls Forget on the tiles it removes (one Download for a loaded material)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local list = {}

				for i = 1, 3 do
					list[i] = tile("a1", i, 1)
					expect(store(list[i])).to.beTrue()
				end

				expect(C().Material(list[1]) ~= nil).to.beTrue()
				-- list[1] is the oldest WRITTEN, but make it the oldest USED: touch the two others afterwards
				expect(C().Has(list[2])).to.beTrue()
				expect(C().Has(list[3])).to.beTrue()

				expect(C().Trim(740).removed).to.equal(2) -- 3 x 390 = 1170 > 740, one tile (390) is under 666
				expect(state.downloads).to.equal(1)
				expect(C().Has(list[1])).to.beFalse()
			end
		},
		{
			-- fails if the age of a tile is lost at a reload: without a time stamp in the session the time of the .vtf file decides
			name = "Trim: for a tile not used in this session (index just loaded) the time of its .vtf decides, oldest first",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {tile("a1", 1, 1), tile("a1", 2, 1), tile("a1", 3, 1)}

				for _, t in ipairs(list) do
					expect(store(t)).to.beTrue()
				end

				local times = {}

				times[C().Path(list[1]) .. ".vtf"] = 300
				times[C().Path(list[2]) .. ".vtf"] = 100
				times[C().Path(list[3]) .. ".vtf"] = 200

				C().Reset() -- forgets the stamps of the session

				file.Time = function(path, where)
					return times[path] or state.origFile.Time(path, where)
				end

				local r = C().Trim(555) -- 1170 > 555, down to 500: only one tile (390) stays

				expect(r.removed).to.equal(2)
				expect(C().Has(list[1])).to.beTrue() -- the most recent file time
				expect(C().Has(list[2])).to.beFalse()
				expect(C().Has(list[3])).to.beFalse()
			end
		},
		{
			-- fails if the stamps of this session and the file times are mixed up (a file time is a date, a stamp is a counter)
			name = "Trim: a tile used in this session is younger than any tile known only by the time of its file",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {tile("a1", 1, 1), tile("a1", 2, 1), tile("a1", 3, 1)}

				for _, t in ipairs(list) do
					expect(store(t)).to.beTrue()
				end

				local times = {}

				times[C().Path(list[1]) .. ".vtf"] = 300
				times[C().Path(list[2]) .. ".vtf"] = 100 -- oldest file...
				times[C().Path(list[3]) .. ".vtf"] = 200

				C().Reset()

				file.Time = function(path, where)
					return times[path] or state.origFile.Time(path, where)
				end

				expect(C().Has(list[2])).to.beTrue() -- ...but used just now

				expect(C().Trim(555).removed).to.equal(2)
				expect(C().Has(list[2])).to.beTrue()
				expect(C().Has(list[3])).to.beFalse()
				expect(C().Has(list[1])).to.beFalse()
			end
		},
		{
			-- fails if a bad limit is taken as "delete everything" (0) or as a number (inf, NaN, a string)
			name = "Trim with a bad limit (nil, 0, negative, NaN, inf, string, table) returns nil, 'bad limit' and removes nothing",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local list = {tile("a1", 1, 1), tile("a1", 2, 1)}

				for _, t in ipairs(list) do
					expect(store(t)).to.beTrue()
				end

				for _, bad in ipairs({0, -5, 0 / 0, math.huge, "1000", true, {}}) do
					local r, err = C().Trim(bad)

					expect(r).to.beNil()
					expect(err).to.equal("bad limit")
				end

				expect(C().Trim(nil)).to.beNil()

				expect(C().Count()).to.equal(2)
				expect(C().Has(list[1])).to.beTrue()
				expect(C().Has(list[2])).to.beTrue()
				expect(file.Exists(C().Path(list[1]) .. ".vtf", "DATA")).to.beTrue()
			end
		},
		{
			name = "Trim of an empty cache: nothing removed, 0 bytes",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local r = C().Trim(1000)

				expect(r.removed).to.equal(0)
				expect(r.bytes).to.equal(0)
			end
		},
		-- Empty tiles (no file) -------------------------------------------------------------------------------------------------------
		{
			-- fails if StoreEmpty writes a file, or if the tile is not known afterwards
			name = "StoreEmpty: the tile exists (Has, IsEmpty, Count) and no .vtf, no .vmt is written, no VTF call is made",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e, n = tile("a1", 1, 1), tile("a1", 2, 1)

				expect(C().IsEmpty(e)).to.beFalse()
				expect(C().StoreEmpty(e)).to.beTrue()
				expect(store(n)).to.beTrue()

				expect(C().Has(e)).to.beTrue()
				expect(C().IsEmpty(e)).to.beTrue()
				expect(C().Has(n)).to.beTrue()
				expect(C().IsEmpty(n)).to.beFalse() -- a normal tile is not empty
				expect(C().IsEmpty(tile("a1", 9, 9))).to.beFalse() -- an unknown tile is not empty either
				expect(C().Count()).to.equal(2) -- both count

				expect(#state.calls.write).to.equal(1) -- only the normal tile
				expect(#state.calls.vmt).to.equal(1)
				expect(file.Exists(C().Path(e) .. ".vtf", "DATA")).to.beFalse()
				expect(file.Exists(C().Path(e) .. ".vmt", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if the empty list is not written, or if the empty tile is also listed among the tiles that have a file
			name = "StoreEmpty writes index.json: the name in `empty`, not in `tiles`; version stays 1",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e, n = tile("a1", 1, 1), tile("a1", 2, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				expect(store(n)).to.beTrue()
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(idx.version).to.equal(1)
				expect(idx.key).to.equal(KEY_A)
				expect(#idx.tiles).to.equal(1)
				expect(idx.tiles[1]).to.equal(C().Name(n))
				expect(#idx.empty).to.equal(1)
				expect(idx.empty[1]).to.equal(C().Name(e))
			end
		},
		{
			-- the index of a cache with no empty tile does not carry an `empty` key at all (the old layout, byte for byte)
			name = "an index without empty tiles has no `empty` list",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("a1", 1, 1))).to.beTrue()
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(idx.empty).to.beNil()
			end
		},
		{
			-- fails if the empty tiles are only kept in memory
			name = "empty tiles survive a new load of the index (Reset): Has, IsEmpty, Count",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e, n = tile("a1", 1, 1), tile("a2", 2, 2)

				expect(C().StoreEmpty(e)).to.beTrue()
				expect(store(n)).to.beTrue()
				expect(C().Flush()).to.beTrue() -- the empty tiles exist only in the index file

				C().Reset()

				expect(C().Has(e)).to.beTrue()
				expect(C().IsEmpty(e)).to.beTrue()
				expect(C().IsEmpty(n)).to.beFalse()
				expect(C().Count()).to.equal(2)
			end
		},
		{
			-- an index written before the empty tiles existed must read as before
			name = "an index file without `empty` (the old layout) loads as before, with no empty tile",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local n = tile("a1", 1, 1)

				expect(store(n)).to.beTrue()
				file.Write(ROOT .. KEY_A .. "/index.json", util.TableToJSON({version = 1, key = KEY_A, tiles = {C().Name(n)}}))
				C().Reset()

				expect(C().Has(n)).to.beTrue()
				expect(C().IsEmpty(n)).to.beFalse()
				expect(C().Count()).to.equal(1)
			end
		},
		{
			-- fails if names of the empty list are trusted without the same check as the others
			name = "a damaged `empty` list (strange names, numbers, a table that is not a list) is ignored without error",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local good = tile("a1", 1, 1)
				local path = ROOT .. KEY_A .. "/index.json"

				mkdirs(path) -- no tile at all in the directory: only the index says what is there

				file.Write(path, util.TableToJSON({version = 1, key = KEY_A, tiles = {}, empty = {"../../evil", 12, C().Name(good), C().Name(good), "t_no_res_here"}}))
				C().Reset()
				expect(C().Count()).to.equal(1) -- only the good name, once
				expect(C().IsEmpty(good)).to.beTrue()

				file.Write(path, util.TableToJSON({version = 1, key = KEY_A, tiles = {}, empty = "not a list"}))
				C().Reset()
				expect(C().Count()).to.equal(0)

				file.Write(path, util.TableToJSON({version = 1, key = KEY_A, tiles = {}, empty = 12}))
				C().Reset()
				expect(C().Count()).to.equal(0)
			end
		},
		{
			-- fails if StoreEmpty accepts anything as a tile
			name = "StoreEmpty refuses a bad tile (false, reason) and writes nothing",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local ok, err = C().StoreEmpty({level = "a1", tx = 0, ty = 0, res = 1000, ppm = 4})

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")
				expect(C().StoreEmpty(nil)).to.beFalse()
				expect(C().StoreEmpty("a1")).to.beFalse()
				expect(C().Count()).to.equal(0)
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse()
			end
		},
		{
			name = "StoreEmpty twice for the same tile: one entry in the index, Count stays 1",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e = tile("a1", 1, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.empty).to.equal(1)
			end
		},
		{
			-- fails if Material tries to load a material for a tile that has no file (an error material by name would be cached by the engine)
			name = "Material of an empty tile is nil, without any engine call and without error",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local e = tile("a1", 1, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Material(e)).to.beNil()
				expect(C().Material(e)).to.beNil()
				expect(#state.loads).to.equal(0)
			end
		},
		{
			name = "Forget of an empty tile does nothing (no Download, no error)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local e = tile("a1", 1, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				C().Forget(e)

				expect(state.downloads).to.equal(0)
				expect(#state.loads).to.equal(0)
				expect(C().Has(e)).to.beTrue()
			end
		},
		{
			-- fails if the empty tile stays marked empty after a real Store, or if its list entry stays
			name = "a normal Store for a tile marked empty makes it a normal tile (files written, not empty, one entry)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(C().StoreEmpty(t)).to.beTrue()
				expect(store(t)).to.beTrue()

				expect(C().IsEmpty(t)).to.beFalse()
				expect(C().Has(t)).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beTrue()
				expect(file.Exists(C().Path(t) .. ".vmt", "DATA")).to.beTrue()
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(1)
				expect(idx.empty).to.beNil()

				C().Reset()
				expect(C().IsEmpty(t)).to.beFalse()
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			-- fails if the files of the tile stay on the disk (they would be orphans the index no longer lists), or if the loaded material is not forgotten
			name = "StoreEmpty over a normal tile deletes its files, forgets its material (one Download) and marks it empty",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Material(t) ~= nil).to.beTrue()

				expect(C().StoreEmpty(t)).to.beTrue()

				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()
				expect(file.Exists(C().Path(t) .. ".vmt", "DATA")).to.beFalse()
				expect(state.downloads).to.equal(1)
				expect(C().IsEmpty(t)).to.beTrue()
				expect(C().Has(t)).to.beTrue()
				expect(C().Count()).to.equal(1)
				expect(C().Material(t)).to.beNil()
				expect(C().Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(0)
				expect(#idx.empty).to.equal(1)

				C().Reset()
				expect(C().IsEmpty(t)).to.beTrue()
			end
		},
		{
			-- fails if a failed Store over an empty tile leaves files behind or loses the empty mark
			name = "a failing Store over an empty tile leaves it empty, with no file",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(C().StoreEmpty(t)).to.beTrue()
				expect(C().Flush()).to.beTrue()

				state.failVMT = "no vmt" -- the .vtf is written, then the .vmt fails

				expect(C().Store(t, "x")).to.beFalse()
				expect(C().IsEmpty(t)).to.beTrue()
				expect(C().Has(t)).to.beTrue()
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()

				C().Reset()
				expect(C().IsEmpty(t)).to.beTrue()
			end
		},
		{
			-- fails if the levels that only have empty tiles are missing (Floors would generate them again)
			name = "KnownLevels also lists a level that has only empty tiles",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(C().StoreEmpty(tile("open", 0, 0))).to.beTrue()
				expect(C().StoreEmpty(tile("fn96tn8", -1, -1))).to.beTrue()
				expect(store(tile("f96t184", 1, 1))).to.beTrue()

				local levels = C().KnownLevels()

				expect(#levels).to.equal(3)
				expect(levels[1]).to.equal("f96t184")
				expect(levels[2]).to.equal("fn96tn8")
				expect(levels[3]).to.equal("open")

				expect(C().Flush()).to.beTrue()
				C().Reset()
				expect(#C().KnownLevels()).to.equal(3)
			end
		},
		{
			-- fails if the empty tiles take part in the size (they have 0 bytes) or are removed (it would free nothing and lose the knowledge)
			name = "Trim does not count the empty tiles (0 bytes) and keeps them while it removes the normal ones",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local normals, empties = {}, {}

				for i = 1, 4 do
					empties[i] = tile("a1", i, 5)
					expect(C().StoreEmpty(empties[i])).to.beTrue()
				end

				for i = 1, 4 do
					normals[i] = tile("a1", i, 1)
					expect(store(normals[i])).to.beTrue()
				end

				local before = diskBytes(normals)
				local r = C().Trim(1110) -- 4 x 390 = 1560 > 1110: two normal tiles go (780 <= 999)

				expect(before).to.beGreaterThan(1110)
				expect(r.removed).to.equal(2)
				expect(r.bytes).to.equal(diskBytes({normals[3], normals[4]}))

				for i = 1, 4 do
					expect(C().Has(empties[i])).to.beTrue()
					expect(C().IsEmpty(empties[i])).to.beTrue()
				end

				expect(C().Count()).to.equal(6)

				C().Reset()
				expect(C().Count()).to.equal(6)
			end
		},
		{
			name = "Trim of a cache with only empty tiles: nothing removed, 0 bytes",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(C().StoreEmpty(tile("a1", 1, 1))).to.beTrue()
				expect(C().StoreEmpty(tile("a1", 2, 1))).to.beTrue()

				local r = C().Trim(1)

				expect(r.removed).to.equal(0)
				expect(r.bytes).to.equal(0)
				expect(C().Count()).to.equal(2)
			end
		},
		{
			-- fails if Clear leaves the empty tiles of the key (in memory or in the index file)
			name = "Clear removes the empty tiles of the key too (memory and index file)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e = tile("a1", 1, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Clear()).to.beTrue()
				expect(C().Has(e)).to.beFalse()
				expect(C().IsEmpty(e)).to.beFalse()
				expect(C().Count()).to.equal(0)
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse()

				C().Reset()
				expect(C().Has(e)).to.beFalse()
			end
		},
		{
			-- fails if a cache directory that holds only an index (all empty tiles) is not removed by Prune
			name = "Prune removes a stale key whose only content is an index of empty tiles, and spares the current key",
			func = function(state)
				installVTF(state)

				local e = tile("a1", 1, 1)

				useKey(state, "test_mapa_100_v1")
				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Flush()).to.beTrue()

				useKey(state, KEY_A)
				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Flush()).to.beTrue()

				expect(C().Prune()).to.equal(1)
				expect(file.Exists(ROOT .. "test_mapa_100_v1/index.json", "DATA")).to.beFalse()
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beTrue()
				expect(C().IsEmpty(e)).to.beTrue()
			end
		},
		{
			-- the empty tile is a use too: Trim's order does not depend on it, but Has must stay true after any number of calls
			name = "Has of an empty tile works from memory (no file call) once the index is loaded",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local e = tile("a1", 1, 1)

				expect(C().StoreEmpty(e)).to.beTrue()
				C().Has(e)

				local touched = 0

				for name in pairs(state.origFile) do
					file[name] = function(...)
						touched = touched + 1

						return state.origFile[name](...)
					end
				end

				for _ = 1, 100 do
					C().Has(e)
					C().IsEmpty(e)
				end

				expect(touched).to.equal(0)
			end
		},
		-- The index in batches (Flush) --------------------------------------------------------------------------------------------------
		{
			-- fails if the index is written at every Store (O(n^2) for hundreds of tiles) or never without Flush
			name = "the index is written every 16 changes, not at every Store; Flush writes it at once and writes nothing when it is clean",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local indexWrites = 0

				file.Write = function(path, content)
					if string.find(path, "index.json", 1, true) then
						indexWrites = indexWrites + 1
					end

					return state.origFile.Write(path, content)
				end

				local path = ROOT .. KEY_A .. "/index.json"

				expect(C().FLUSH_EVERY).to.equal(16)

				for i = 1, 15 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				expect(indexWrites).to.equal(0)
				expect(file.Exists(path, "DATA")).to.beFalse()

				expect(store(tile("a1", 16, 0))).to.beTrue() -- the 16th change
				expect(indexWrites).to.equal(1)
				expect(#util.JSONToTable(file.Read(path, "DATA")).tiles).to.equal(16)

				for i = 17, 19 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				expect(indexWrites).to.equal(1)
				expect(#util.JSONToTable(file.Read(path, "DATA")).tiles).to.equal(16) -- still the old one

				expect(C().Flush()).to.beTrue()
				expect(indexWrites).to.equal(2)
				expect(#util.JSONToTable(file.Read(path, "DATA")).tiles).to.equal(19)

				expect(C().Flush()).to.beTrue() -- clean: nothing to write
				expect(indexWrites).to.equal(2)

				for i = 20, 40 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				expect(indexWrites).to.equal(3) -- 16 more changes since the Flush: one write (tile 35), not 21
			end
		},
		{
			name = "Flush without any change, or before anything was loaded, is true and writes nothing",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(C().Flush()).to.beTrue()
				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse()
			end
		},
		{
			-- fails if a failed write is taken for a success because an older index.json exists (the check was only "does the file exist")
			name = "Flush checks what was written: a write that does nothing or truncates is reported (false, reason), the index stays dirty and a later Flush works",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("a1", 1, 0))).to.beTrue()
				expect(C().Flush()).to.beTrue() -- an index.json exists now
				expect(store(tile("a1", 2, 0))).to.beTrue()

				file.Write = function() end -- the write silently fails: the old index.json is still there

				local ok, err = C().Flush()

				expect(ok).to.beFalse()
				expect(type(err)).to.equal("string")

				file.Write = function(path)
					state.origFile.Write(path, "x") -- truncated
				end

				expect(C().Flush()).to.beFalse()

				file.Write = state.origFile.Write

				expect(C().Flush()).to.beTrue() -- still dirty: written now
				C().Reset()
				expect(C().Count()).to.equal(2)
				expect(util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA")).tiles[2]).to.equal(C().Name(tile("a1", 2, 0)))
			end
		},
		{
			-- fails if a Store whose periodic index write fails is reported as a failure (the tile is on the disk and will be adopted)
			name = "a periodic index write that fails does not make Store fail: the tile is on the disk and found again at the next load",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local indexWrite = function() end

				file.Write = function(path, content)
					if string.find(path, "index.json", 1, true) then
						return indexWrite(path, content)
					end

					return state.origFile.Write(path, content)
				end

				for i = 1, 16 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				expect(file.Exists(ROOT .. KEY_A .. "/index.json", "DATA")).to.beFalse() -- the write did nothing

				C().Reset()
				expect(C().Count()).to.equal(16)
			end
		},
		{
			-- fails if a tile written since the last index write is lost at a load (the index is rebuilt from the directory)
			name = "a .vtf the index does not list (Stores since the last write, a crash, no index at all) is adopted at load, and the index is written again",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				for i = 1, 3 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				local path = ROOT .. KEY_A .. "/index.json"

				expect(file.Exists(path, "DATA")).to.beFalse() -- never written

				C().Reset()

				expect(C().Count()).to.equal(3)

				for i = 1, 3 do
					expect(C().Has(tile("a1", i, 0))).to.beTrue()
				end

				expect(file.Exists(path, "DATA")).to.beTrue() -- the load wrote the rebuilt index
				expect(#util.JSONToTable(file.Read(path, "DATA")).tiles).to.equal(3)
			end
		},
		{
			-- fails if the empty tiles are lost when only some of the .vtf files are listed (they exist only in the index)
			name = "the rebuild keeps the empty tiles of the index and adopts the .vtf files written after it",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local a, e, b = tile("a1", 1, 0), tile("a1", 2, 0), tile("a1", 3, 0)

				expect(store(a)).to.beTrue()
				expect(C().StoreEmpty(e)).to.beTrue()
				expect(C().Flush()).to.beTrue()
				expect(store(b)).to.beTrue() -- after the last write of the index

				C().Reset()

				expect(C().Count()).to.equal(3)
				expect(C().Has(a)).to.beTrue()
				expect(C().Has(b)).to.beTrue()
				expect(C().IsEmpty(e)).to.beTrue()
				expect(C().IsEmpty(b)).to.beFalse()
			end
		},
		{
			-- a tile that was made empty in memory but whose index was not written: the files are gone, so it is simply unknown (made again), never a ghost
			name = "StoreEmpty over a tile with files, then a reload before any Flush: no ghost tile (the files are gone, the tile is made again)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 0)

				expect(store(t)).to.beTrue()
				expect(C().Flush()).to.beTrue()
				expect(C().StoreEmpty(t)).to.beTrue()

				C().Reset()

				expect(C().Has(t)).to.beFalse()
				expect(C().Count()).to.equal(0)
			end
		},
		{
			-- fails if the load asks the disk once for each tile (a file.Exists a tile) instead of listing the directory once
			name = "the load lists the directory with one file.Find and asks no file.Exists",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				for i = 1, 8 do
					expect(store(tile("a1", i, 0))).to.beTrue()
				end

				expect(C().Flush()).to.beTrue()
				C().Reset()

				local counts = {}

				spyFile(state, counts)

				expect(C().Count()).to.equal(8)
				expect(counts.Find).to.equal(1)
				expect(counts.Exists).to.equal(0)
			end
		},
		-- File size of a tile --------------------------------------------------------------------------------------------------------
		{
			-- fails if only the existence of the file is checked: a truncated .vtf would be given to the engine
			name = "a tile whose .vtf has the wrong size (truncated, too long) is dropped at load and its files are deleted, listed in the index or not",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local good, short, long, orphan = tile("a1", 1, 0), tile("a1", 2, 0), tile("a1", 3, 0), tile("a1", 4, 0)

				expect(store(good)).to.beTrue()

				state.vtfSize = vtfSizeFor(16) - 1
				expect(store(short)).to.beTrue()
				state.vtfSize = vtfSizeFor(16) + 1
				expect(store(long)).to.beTrue()

				expect(C().Flush()).to.beTrue() -- the first three are listed

				state.vtfSize = 5
				expect(store(orphan)).to.beTrue() -- not listed: found by the directory listing

				C().Reset()

				expect(C().Has(good)).to.beTrue()
				expect(C().Has(short)).to.beFalse()
				expect(C().Has(long)).to.beFalse()
				expect(C().Has(orphan)).to.beFalse()
				expect(C().Count()).to.equal(1)

				for _, t in ipairs({short, long, orphan}) do
					expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beFalse()
				end

				-- written again: the index no longer lists the dropped ones
				local idx = util.JSONToTable(file.Read(ROOT .. KEY_A .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(1)
			end
		},
		{
			-- fails if the expected size is wrong for a resolution: 512 -> 131072 + 208, 1024 -> 524288 + 208 in DXT1 / DXT1A, and 4 bytes a pixel in BGRA
			name = "the sizes a file must have: DXT1 for 512 (131072 + 208) and 1024 (524288 + 208), BGRA for 16 (1024 + 208) are accepted, anything near is not",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(vtfSizeFor(512)).to.equal(131072 + 208) -- the test's own figures
				expect(vtfSizeFor(1024)).to.equal(524288 + 208)
				expect(vtfSizeFor(16, true)).to.equal(1024 + 208)

				local t512, t1024, bgra, off = tile("a1", 1, 0, 512, 1), tile("a1", 2, 0, 1024, 4), tile("a1", 3, 0, 16, 4), tile("a1", 4, 0, 512, 1)

				expect(store(t512)).to.beTrue()
				expect(store(t1024)).to.beTrue()

				state.vtfSize = vtfSizeFor(16, true)
				expect(C().Store(bgra, "x", 12)).to.beTrue()

				state.vtfSize = 131072 + 208 + 8 -- one more block of 8 bytes
				expect(store(off)).to.beTrue()

				expect(C().Flush()).to.beTrue()
				C().Reset()

				expect(C().Has(t512)).to.beTrue()
				expect(C().Has(t1024)).to.beTrue()
				expect(C().Has(bgra)).to.beTrue()
				expect(C().Has(off)).to.beFalse()
			end
		},
		-- Trim without disk calls -----------------------------------------------------------------------------------------------------
		{
			-- fails if Trim asks the disk for the size of each tile (3 calls a tile before): the sizes are remembered at Store
			name = "Trim counts from the remembered sizes: no file.Size, file.Exists, file.Find or file.Time call when every tile was used in this session",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				for i = 1, 6 do
					expect(store(tile("a1", i, 1))).to.beTrue()
				end

				local counts = {}

				spyFile(state, counts)

				local r = C().Trim(1110) -- 6 x 390 = 2340 > 1110: down to 999 means 2 tiles left (780)

				expect(r.removed).to.equal(4)
				expect(r.bytes).to.equal(780)
				expect(counts.Size).to.equal(1) -- the one that checks what the index write put on the disk; nothing for the tiles
				expect(counts.Exists).to.equal(0)
				expect(counts.Find).to.equal(0)
				expect(counts.Time).to.equal(0)
			end
		},
		{
			name = "Trim after a reload: the sizes were read once at load (no file.Size during Trim); only the file time is asked for the unused tiles",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				for i = 1, 4 do
					expect(store(tile("a1", i, 1))).to.beTrue()
				end

				expect(C().Flush()).to.beTrue()
				C().Reset()
				expect(C().Count()).to.equal(4)

				local counts = {}

				spyFile(state, counts)

				local r = C().Trim(1110)

				expect(r.removed).to.equal(2)
				expect(r.bytes).to.equal(780)
				expect(counts.Size).to.equal(1) -- the check of the index write only
				expect(counts.Time).to.equal(4)
			end
		},
		-- Name memo --------------------------------------------------------------------------------------------------------------------
		{
			-- fails if Name builds its strings again at every call (about 8 strings a call): 10000 Has would cost hundreds of KB
			name = "Has of a known tile allocates nothing: 10000 calls make the memory grow by less than 2 KB (the collector is stopped, so garbage counts)",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t, missing = tile("a1", 3, -2, 1024, 3), tile("a1", 9, 9, 1024, 3)

				expect(store(t)).to.beTrue()
				expect(C().Has(t)).to.beTrue() -- the first call loads the index and memoises the name
				expect(C().Has(missing)).to.beFalse()

				-- warm-up: the JIT compiles its traces (they are objects of the collector too) before the measure starts
				for _ = 1, 3000 do
					C().Has(t)
					C().Has(missing)
				end

				collectgarbage("collect")
				collectgarbage("stop")

				-- two windows of 10000 calls (the collector stopped): the first absorbs what the JIT and the test runner still allocate once (a few KB at most),
				-- the second is the steady state that is asserted. A name built again at every call would cost about 8 strings a call, hundreds of KB a window.
				local drifts = {}

				for w = 1, 2 do
					local before = collectgarbage("count")

					for _ = 1, 10000 do
						C().Has(t)
						C().Has(missing)
					end

					drifts[w] = collectgarbage("count") - before
				end

				collectgarbage("restart")

				expect(drifts[1]).to.beLessThan(16)
				expect(drifts[2]).to.beLessThan(2)
			end
		},
		{
			-- fails if the memo is keyed on the table of the tile instead of its fields (a reused table with other values), or serves a name for an invalid tile
			name = "Name memo: a tile table reused with other fields gets the right name, an invalid one still gets nil, equal tiles in two tables share one name",
			func = function()
				local t = tile("a1", 3, 4, 1024, 3)
				local first = C().Name(t)

				expect(first).to.equal("t_a1_3_4_1024_3")
				expect(C().Name(t)).to.equal(first)

				t.tx = -5
				expect(C().Name(t)).to.equal("t_a1_n5_4_1024_3")

				t.tx = 3
				t.level = "b2"
				expect(C().Name(t)).to.equal("t_b2_3_4_1024_3")

				t.level = "a1"
				t.ppm = 2.5
				expect(C().Name(t)).to.equal("t_a1_3_4_1024_2p5")

				t.ppm = 3
				t.res = 1000
				expect(C().Name(t)).to.beNil() -- a valid tile with this level and tx was memoised: the memo must not answer for res 1000
				t.res = 1024
				t.ty = nil
				expect(C().Name(t)).to.beNil()
				t.ty = 0 / 0
				expect(C().Name(t)).to.beNil()

				expect(C().Name(tile("a1", 3, 4, 1024, 3))).to.equal(first)
			end
		},
		-- real VTF module (owned by another agent) ------------------------------------------------------------------------------------
		{
			-- skipped while the VTF module is not there; then it runs for real: the engine must accept the file the module wrote
			name = "integration with the REAL VTF module: Store of a hand-made DXT1 16x16, then Material is not nil and not an error",
			skip = not (GryMod.Minimap.VTF and GryMod.Minimap.VTF.Write and GryMod.Minimap.VTF.WriteVMT),
			func = function(state)
				useKey(state, "test_integration_1_v2")

				-- 16x16 pixels = 4 x 4 blocks of 8 bytes: end points white (0xFFFF) and black (0x0000), all indices 0 (= white)
				local data = string.rep("\255\255\0\0\0\0\0\0", 16)
				-- a different tile at each run: the engine caches materials by name, a name already loaded would hide a stale file
				local t = tile("a1", math.random(10000, 99999), -math.random(1, 9999), 16, 4)

				expect(C().Store(t, data)).to.beTrue()
				expect(C().Has(t)).to.beTrue()
				expect(file.Exists(C().Path(t) .. ".vtf", "DATA")).to.beTrue()
				expect(file.Exists(C().Path(t) .. ".vmt", "DATA")).to.beTrue()

				local mat = C().Material(t)

				expect(mat ~= nil).to.beTrue()
				expect(mat:IsError()).to.beFalse()

				-- the file the real module wrote has the size the cache expects of a file of this resolution: a new load keeps the tile
				expect(C().Flush()).to.beTrue()
				C().Reset()
				expect(C().Has(t)).to.beTrue()
			end
		},
		{
			-- same with the alpha format (20): the real VTF module must write a file the engine loads
			name = "integration with the REAL VTF module: Store with format 20 (DXT1 with alpha), then Material is not nil and not an error",
			skip = not (GryMod.Minimap.VTF and GryMod.Minimap.VTF.Write and GryMod.Minimap.VTF.WriteVMT and GryMod.Minimap.VTF.FORMAT_DXT1A == 20),
			func = function(state)
				useKey(state, "test_integration_1_v2")

				-- 3-colour mode (c0 <= c1): all 16 blocks are index 3 = transparent black, and index 0 pixels are the colour c0
				local data = string.rep("\0\0\255\255\0\0\0\255", 16)
				local t = tile("a1", math.random(10000, 99999), -math.random(1, 9999), 16, 4)

				expect(C().Store(t, data, 20)).to.beTrue()

				local mat = C().Material(t)

				expect(mat ~= nil).to.beTrue()
				expect(mat:IsError()).to.beFalse()

				expect(C().Flush()).to.beTrue()
				C().Reset()
				expect(C().Has(t)).to.beTrue() -- the size of the real file passes the check of the load
			end
		}
	}
}
