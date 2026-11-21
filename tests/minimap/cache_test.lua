-- Tests of the minimap cache (lua/grymod/client/minimap/cache.lua): the cache key, the tile geometry, the tile names, the index file, the
-- store of tiles, the materials (lazy, LRU of 64, Forget) and Clear / Prune. GLuaTest format, client realm.
-- The module under test is always reached as GryMod.Minimap.Cache at call time. The VTF module is owned by another agent: the cases that
-- do not test it install a stand-in (saved and put back in afterEach, inside a pcall, also when a case failed). The same goes for the globals
-- the cases replace (Material, game.GetMap, file.*, METRES_PER_UNIT) and for Cache.Key (replaced so that no test touches the real cache of the
-- map that is loaded). Every file written goes under data/grymod/minimap/test_* and is deleted before and after each case.

local ROOT = "grymod/minimap/"
local KEY_A = "test_mapa_1234_v1"

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

-- a stand-in of the VTF module: records its calls, writes small real files (the cache checks the disk), can be made to fail
local function installVTF(state)
	state.calls = {write = {}, vmt = {}}
	state.failWrite, state.failVMT = nil, nil -- the state table is shared by the cases of the file

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
			file.Write(path, "vtf")

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

	local texture = {
		Download = function()
			state.downloads = state.downloads + 1
		end
	}

	Material = function(path)
		state.loads[#state.loads + 1] = path

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
			IsDir = file.IsDir
		}
		wipe()

		if GryMod.Minimap.Cache and GryMod.Minimap.Cache.Reset then
			GryMod.Minimap.Cache.Reset()
		end
	end,
	afterEach = function(state)
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
			end
		end)

		pcall(wipe)
	end,
	cases = {
		-- (1) the key ---------------------------------------------------------------------------------------------------------------
		{
			-- fails if KeyFor does not lowercase, does not turn each odd byte into "_", does not add the size or the version
			name = "KeyFor sanitises the map name: lowercase, every byte outside [a-z0-9_] becomes an underscore, then _<size>_v1",
			func = function()
				expect(C().KeyFor("GM_Construct", 1234)).to.equal("gm_construct_1234_v1")
				expect(C().KeyFor("My Map-v2!", 7)).to.equal("my_map_v2__7_v1")
				expect(C().KeyFor("ab\xC3\xA9", 0)).to.equal("ab___0_v1") -- the two bytes of an accented letter give two underscores
				expect(C().KeyFor("../../x", 1)).to.equal("______x_1_v1") -- no path character survives
			end
		},
		{
			-- fails if a negative, missing or odd size is written as it is, or if an empty name makes an empty key
			name = "KeyFor: an unknown size (negative, nil, not a number) is 0, an empty or missing name is 'unknown'",
			func = function()
				expect(C().KeyFor("a", -1)).to.equal("a_0_v1")
				expect(C().KeyFor("a", nil)).to.equal("a_0_v1")
				expect(C().KeyFor("a", "12")).to.equal("a_0_v1")
				expect(C().KeyFor("", 5)).to.equal("unknown_5_v1")
				expect(C().KeyFor(nil, 5)).to.equal("unknown_5_v1")
			end
		},
		{
			-- fails if Key does not read the .bsp size (here a map that is not on disk: size 0, file.Size says -1)
			name = "Key: the size is 0 when the .bsp is unknown, the name comes from game.GetMap, the version is v1",
			func = function()
				game.GetMap = function()
					return "Test_Bogus Map"
				end
				C().Reset()

				expect(C().Key()).to.equal("test_bogus_map_0_v1")
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

				expect(C().Key()).to.equal("gm_construct_" .. size .. "_v1")
			end
		},
		{
			-- fails if Dir does not give a path relative to data/ in grymod/minimap/<key>
			name = "Dir: grymod/minimap/<key>, relative to data/ (the current key when none is given)",
			func = function()
				useKey({}, KEY_A)

				expect(C().Dir("abc_1_v1")).to.equal("grymod/minimap/abc_1_v1")
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
			-- fails if the index file is not written, or lacks the version, the key or the tile name
			name = "Store writes index.json: {version = 1, key, tiles = {<base>...}}",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				expect(store(tile("a1", 3, -2))).to.beTrue()
				expect(store(tile("a2", 0, 0))).to.beTrue()

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
			-- fails if a damaged index.json crashes the load or is trusted (names that are not tile names are a way out of the directory)
			name = "a damaged index.json, one of another key, or one with a strange tile name gives an empty index, without error",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()

				local path = ROOT .. KEY_A .. "/index.json"

				file.Write(path, "this is { not json")
				C().Reset()
				expect(C().Has(t)).to.beFalse()
				expect(C().Count()).to.equal(0)

				file.Write(path, util.TableToJSON({version = 1, key = "test_other_1_v1", tiles = {C().Name(t)}}))
				C().Reset()
				expect(C().Has(t)).to.beFalse()

				file.Write(path, util.TableToJSON({version = 2, key = KEY_A, tiles = {C().Name(t)}}))
				C().Reset()
				expect(C().Has(t)).to.beFalse()

				file.Write(path, util.TableToJSON({version = 1, key = KEY_A, tiles = {"../../evil", 12, C().Name(t)}}))
				C().Reset()
				expect(C().Count()).to.equal(1)
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

				-- an error material is not kept: once the file is good, the next call loads again
				state.errorMaterial = false
				expect(C().Material(t) ~= nil).to.beTrue()
				expect(#state.loads).to.equal(2)
			end
		},
		{
			name = "Material is nil when the engine gives nothing at all",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)

				Material = function()
					return nil
				end

				local t = tile("a1", 1, 1)

				expect(store(t)).to.beTrue()
				expect(C().Material(t)).to.beNil()
			end
		},
		{
			-- fails with no limit (65 loads kept) or with a limit that is not 64
			name = "LRU: 64 materials are kept; the 65th pushes out the oldest, which is loaded again when asked",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				expect(C().MAX_MATERIALS).to.equal(64)

				local list = storeMany(65)

				for i = 1, 64 do
					expect(C().Material(list[i]) ~= nil).to.beTrue()
				end

				expect(#state.loads).to.equal(64)

				for i = 1, 64 do
					C().Material(list[i])
				end

				expect(#state.loads).to.equal(64) -- all 64 are kept

				C().Material(list[65])
				expect(#state.loads).to.equal(65)

				C().Material(list[1]) -- the oldest was dropped
				expect(#state.loads).to.equal(66)
				expect(state.loads[66]).to.equal("../data/" .. C().Path(list[1]))
			end
		},
		{
			-- fails if the order is the order of loading (FIFO) instead of the order of last use
			name = "LRU: a tile used again is the youngest; the one dropped is the least recently used",
			func = function(state)
				useKey(state, KEY_A)
				installVTF(state)
				installMaterial(state)

				local list = storeMany(65)

				for i = 1, 64 do
					C().Material(list[i])
				end

				C().Material(list[1]) -- 1 becomes the youngest, 2 the oldest
				C().Material(list[65]) -- pushes 2 out
				expect(#state.loads).to.equal(65)

				C().Material(list[1])
				expect(#state.loads).to.equal(65) -- still there

				C().Material(list[2])
				expect(#state.loads).to.equal(66) -- dropped, loaded again
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

				local list = storeMany(65)

				for i = 1, 65 do
					C().Material(list[i])
				end

				state.downloads = 0
				C().Forget(list[1]) -- pushed out of the table when the 65th came in

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

				C().Material(t)
				expect(#state.loads).to.equal(2)
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
				local KEY_B = "test_mapb_55_v1"

				useKey(state, KEY_A)
				expect(store(t1)).to.beTrue()
				expect(store(t2)).to.beTrue()
				local dirA = C().Dir(KEY_A)
				local pathA1, pathA2 = C().Path(t1), C().Path(t2)

				useKey(state, KEY_B)
				expect(store(t1)).to.beTrue()
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
					current = "test_mapa_100_v1",
					old1 = "test_mapa_200_v1",
					old2 = "test_mapa_300_v1",
					other = "test_mapb_100_v1",
					longer = "test_mapa_v2_100_v1"
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
		-- real VTF module (owned by another agent) ------------------------------------------------------------------------------------
		{
			-- skipped while the VTF module is not there; then it runs for real: the engine must accept the file the module wrote
			name = "integration with the REAL VTF module: Store of a hand-made DXT1 16x16, then Material is not nil and not an error",
			skip = not (GryMod.Minimap.VTF and GryMod.Minimap.VTF.Write and GryMod.Minimap.VTF.WriteVMT),
			func = function(state)
				useKey(state, "test_integration_1_v1")

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
			end
		}
	}
}
