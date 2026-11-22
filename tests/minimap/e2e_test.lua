-- End-to-end checks of the minimap pipeline with the REAL modules (DXT1 -> VTF -> Cache -> engine material), GLuaTest format, client realm.
-- This file covers what does not need a render context: the compression of a picture that has void pixels, the write of the VTF/VMT/index, the engine
-- loading the material, the rewrite of a tile under the same name, Clear, Trim, the key per map and Prune. What needs a render hook (the capture itself,
-- the pixels of a drawn material, the generator running over frames) is in tests/minimap/e2e_job.lua (a lua_job).
--
-- Isolation: Cache.Key is replaced by a stand-in that returns a TEST key ("test_e2e_unit_..."), and Cache.Reset() is called so the cache works on that
-- key: the real cache of the map is never read nor written. Everything is put back in afterEach inside a pcall (Cache.Key, game.GetMap, Cache.Reset), and the
-- directories data/grymod/minimap/test_e2e_* are deleted, also when a case failed. Nothing runs over frames, so no other hook can reach the stand-ins.

local M = GryMod.Minimap
local Cache, DXT1, VTF = M.Cache, M.DXT1, M.VTF

local ROOT = "grymod/minimap"

-- what is saved before any stand-in, and put back in afterEach
local origKey = Cache.Key
local origGetMap = game.GetMap
local currentKey = nil
local lastAfter = nil -- what the previous afterEach left (checked by the last case)

local function standInKey()
	return currentKey
end

-- the keys this case created (their directories are swept in afterEach)
local created = {}

local function useKey(key)
	currentKey = key
	created[key] = true
	Cache.Reset()
end

-- deletes every file of a directory under data/grymod/minimap, then the directory
local function sweepDir(name)
	local dir = ROOT .. "/" .. name
	local files = file.Find(dir .. "/*", "DATA")

	for _, f in ipairs(files or {}) do
		file.Delete(dir .. "/" .. f)
	end

	file.Delete(dir)
end

local function sweepAll()
	local _, dirs = file.Find(ROOT .. "/test_e2e_*", "DATA")

	for _, d in ipairs(dirs or {}) do
		sweepDir(d)
	end
end

local function leftovers()
	local _, dirs = file.Find(ROOT .. "/test_e2e_*", "DATA")

	return dirs or {}
end

local function restore()
	Cache.Key = origKey
	game.GetMap = origGetMap
	currentKey = nil
	Cache.Reset()
end

-- A w x h BGRA picture with real void pixels (alpha 0 AND black) in the first `voidCols` columns, a coloured gradient elsewhere (never black).
local function picture(w, h, voidCols, seed)
	local rows, voidPixel = {}, "\0\0\0\0"

	for y = 0, h - 1 do
		local px = {}

		for x = 0, w - 1 do
			if x < voidCols then
				px[x + 1] = voidPixel
			else
				px[x + 1] = string.char((30 + x + seed) % 200 + 20, (60 + y + seed * 3) % 180 + 40, (200 - x + seed * 7) % 200 + 40, 255)
			end
		end

		rows[y + 1] = table.concat(px)
	end

	return table.concat(rows)
end

local function tile(tx, ty, res)
	return {level = "e2e", tx = tx, ty = ty, res = res or 64, ppm = 3}
end

-- a picture of one flat colour, compressed for real
local function flat(res, b, g, r)
	local bgra = string.rep(string.char(b, g, r, 255), res * res)
	local dxt = DXT1.Compress(bgra, res, res, {alpha = true})

	return dxt
end

return {
	groupName = "GryMod minimap, end to end (real modules, test cache key)",
	beforeEach = function(state)
		created = {}
		useKey(Cache.KeyFor("test_e2e_unit", 1000))
		Cache.Key = standInKey
		Cache.Reset()
		sweepDir(currentKey) -- a previous crashed run
	end,
	afterEach = function(state)
		pcall(restore)
		pcall(sweepAll)

		lastAfter = {keyBack = Cache.Key == origKey, mapBack = game.GetMap == origGetMap}
	end,
	cases = {
		{
			-- production change that would make it fail: Store ignoring its format argument (the header would say 13), a compressor writing 4-colour blocks for void
			-- pixels (decode alpha 255), a VMT without $translucent, a wrong flags word, a material that does not load
			name = "pipeline: DXT1 (alpha) -> Cache.Store (format 20) -> Has -> Material -> VTF.Parse of the file on disk",
			func = function()
				local res = 128
				local t = tile(3, -2, res)
				local bgra = picture(res, res, 40, 0)
				local dxt, err = DXT1.Compress(bgra, res, res, {alpha = true})

				expect(err).to.beNil()
				expect(#dxt).to.equal(res * res / 2)

				expect(Cache.Has(t)).to.beFalse()
				expect(Cache.Material(t)).to.beNil()

				local ok, why = Cache.Store(t, dxt, 20)

				expect(why).to.beNil()
				expect(ok).to.beTrue()
				expect(Cache.Has(t)).to.beTrue()
				expect(Cache.Count()).to.equal(1)

				-- the file on disk, read back by an independent reader
				local path = Cache.Path(t)
				local bytes = file.Read(path .. ".vtf", "DATA")

				expect(type(bytes)).to.equal("string")

				local info, perr = VTF.Parse(bytes)

				expect(perr).to.beNil()
				expect(info.format).to.equal(20)
				expect(info.flags).to.equal(0x130C)
				expect(info.width).to.equal(res)
				expect(info.height).to.equal(res)
				expect(info.dataLength).to.equal(res * res / 2)
				expect(string.sub(bytes, info.dataOffset + 1)).to.equal(dxt)

				local vmt = file.Read(path .. ".vmt", "DATA")

				expect(string.find(vmt, "$translucent", 1, true) ~= nil).to.beTrue()
				expect(string.find(vmt, "../data/" .. path, 1, true) ~= nil).to.beTrue()

				-- the engine loads it (Material is not an error). Its texture is loaded in the background and only exists 1 to 2 frames later on some games (matW 32, no
				-- GetTexture before), and this case runs inside one frame: the size of the texture is checked in tests/minimap/e2e_job.lua, which can wait for frames.
				local mat = Cache.Material(t)

				expect(mat).to.exist()
				expect(mat:IsError()).to.beFalse()

				-- the decoded tile keeps the void: transparent where the picture was void, opaque elsewhere
				local decoded = DXT1.Decode(dxt, res, res)
				local voidOk, solidOk = 0, 0

				for y = 0, res - 1, 4 do
					for x = 0, res - 1, 4 do
						local a = string.byte(decoded, (y * res + x) * 4 + 4)

						if x < 40 and a == 0 then
							voidOk = voidOk + 1
						elseif x >= 44 and a == 255 then
							solidOk = solidOk + 1
						end
					end
				end

				expect(voidOk).to.beGreaterThan(0)
				expect(solidOk).to.beGreaterThan(0)

				-- the index on disk lists the tile (it is written in batches: Flush writes it now), and a fresh read of it (after a Reset) finds it again
				expect(Cache.Flush()).to.beTrue()

				local idx = util.JSONToTable(file.Read(Cache.Dir() .. "/index.json", "DATA") or "")

				expect(idx.tiles[1]).to.equal(Cache.Name(t))
				Cache.Reset()
				expect(Cache.Has(t)).to.beTrue()
			end
		},
		{
			-- production change that would make it fail: a Store that appends or keeps the old file, an index that counts the tile twice
			name = "a tile rewritten under the same name: the file holds the new data, still one tile, the material loads",
			func = function()
				local res = 64
				local t = tile(0, 0, res)
				local a, b = flat(res, 0, 200, 0), flat(res, 200, 0, 200)

				expect(a ~= b).to.beTrue()
				expect(Cache.Store(t, a, 20)).to.beTrue()
				expect(Cache.Material(t)).to.exist()

				expect(Cache.Store(t, b, 20)).to.beTrue()

				local bytes = file.Read(Cache.Path(t) .. ".vtf", "DATA")
				local info = VTF.Parse(bytes)

				expect(info).to.exist()
				expect(string.sub(bytes, info.dataOffset + 1)).to.equal(b)
				expect(Cache.Count()).to.equal(1)

				local mat = Cache.Material(t)

				expect(mat).to.exist()
				expect(mat:IsError()).to.beFalse()
			end
		},
		{
			-- production change that would make it fail: a Clear that leaves the index or the directory, a Material that answers for a deleted tile
			name = "Cache.Clear(key) deletes the tiles, the index and the directory; nothing is left; the tile is gone",
			func = function()
				local res = 64
				local t1, t2 = tile(0, 0, res), tile(1, 0, res)

				expect(Cache.Store(t1, flat(res, 10, 20, 30), 20)).to.beTrue()
				expect(Cache.Store(t2, flat(res, 30, 20, 10), 20)).to.beTrue()
				expect(Cache.Count()).to.equal(2)

				local dir = Cache.Dir()

				expect(Cache.Flush()).to.beTrue() -- the index is written in batches of 16 changes: write it now
				expect(#file.Find(dir .. "/*", "DATA")).to.equal(5) -- 2 vtf, 2 vmt, index.json

				expect(Cache.Clear(currentKey)).to.beTrue()
				expect(Cache.Count()).to.equal(0)
				expect(Cache.Has(t1)).to.beFalse()
				expect(Cache.Material(t1)).to.beNil()
				expect(#file.Find(dir .. "/*", "DATA")).to.equal(0)
				expect(file.IsDir(dir, "DATA")).to.beFalse()
			end
		},
		{
			-- production change that would make it fail: Trim removing the most recent tile first, or the last stored one, or not updating the index file
			name = "Cache.Trim(small limit) removes the least recently used tiles, keeps the recent and the last stored, updates the index",
			func = function()
				local res = 64
				local t = {tile(0, 0, res), tile(1, 0, res), tile(2, 0, res), tile(3, 0, res)}

				for i = 1, 4 do
					expect(Cache.Store(t[i], flat(res, i * 40, 100, 50), 20)).to.beTrue()
				end

				-- t[1] is used again: it is now more recent than t[2] and t[3]
				expect(Cache.Has(t[1])).to.beTrue()

				local full = Cache.Trim(1e9)

				expect(full.removed).to.equal(0)

				-- target = 90 % of the limit = 54 % of the total: about two of the four tiles may stay
				local r = Cache.Trim(math.floor(full.bytes * 0.6))

				expect(r).to.exist()
				expect(r.removed).to.equal(2)
				expect(r.bytes).to.beLessThan(full.bytes * 0.6 * 0.9 + 1)

				expect(Cache.Has(t[1])).to.beTrue() -- used recently
				expect(Cache.Has(t[4])).to.beTrue() -- the last stored
				expect(Cache.Has(t[2])).to.beFalse()
				expect(Cache.Has(t[3])).to.beFalse()
				expect(Cache.Count()).to.equal(2)

				for _, i in ipairs({2, 3}) do
					expect(file.Exists(Cache.Path(t[i]) .. ".vtf", "DATA")).to.beFalse()
					expect(file.Exists(Cache.Path(t[i]) .. ".vmt", "DATA")).to.beFalse()
				end

				local idx = util.JSONToTable(file.Read(Cache.Dir() .. "/index.json", "DATA"))

				expect(#idx.tiles).to.equal(2)
				expect(Cache.Trim(-1)).to.beNil()
			end
		},
		{
			-- production change that would make it fail: a key that ignores the map name or the bsp size, a memo that survives the change of map
			name = "a map that changes: Cache.Key() gives another key and another directory",
			func = function()
				game.GetMap = function() return "test_e2e_mapx" end
				Cache.Reset()

				local kx = origKey()

				game.GetMap = function() return "test_e2e_mapy" end
				Cache.Reset()

				local ky = origKey()

				game.GetMap = origGetMap
				Cache.Reset()

				local real = origKey()

				expect(kx).to.equal("test_e2e_mapx_0_v2") -- no such .bsp: size 0
				expect(ky).to.equal("test_e2e_mapy_0_v2")
				expect(Cache.Dir(kx) ~= Cache.Dir(ky)).to.beTrue()
				expect(Cache.Dir(kx) ~= Cache.Dir(real)).to.beTrue()
				expect(real).to.equal(Cache.KeyFor(game.GetMap(), file.Size("maps/" .. game.GetMap() .. ".bsp", "GAME")))
			end
		},
		{
			-- production change that would make it fail: a Prune that matches by prefix (the map "..._pa_x" would be taken for "..._pa"), that touches another map,
			-- that keeps the stale _v1 or another-size directory of the same map, or that removes the current key
			name = "Cache.Prune removes the stale keys of the SAME map (other size, old version) and never another map or the current key",
			func = function()
				local res = 64
				local current = currentKey -- test_e2e_unit_1000_v2
				local stale1 = Cache.KeyFor("test_e2e_unit", 900) -- the map changed size
				local stale2 = "test_e2e_unit_1000_v1" -- the opaque tiles of before the alpha
				local other1 = Cache.KeyFor("test_e2e_unitb", 1000) -- another map
				local other2 = Cache.KeyFor("test_e2e_unit_x", 1000) -- another map whose name starts like this one
				local t = tile(0, 0, res)

				for _, key in ipairs({stale1, stale2, other1, other2, current}) do
					useKey(key)
					expect(Cache.Store(t, flat(res, 1, 2, 3), 20)).to.beTrue()
					expect(Cache.Flush()).to.beTrue() -- Reset (in useKey) does not write the index: write it before leaving this key
				end

				useKey(current)
				expect(Cache.Has(t)).to.beTrue()

				expect(Cache.Prune()).to.equal(2)

				for _, key in ipairs({stale1, stale2}) do
					expect(file.IsDir(Cache.Dir(key), "DATA")).to.beFalse()
					expect(#file.Find(Cache.Dir(key) .. "/*", "DATA")).to.equal(0)
				end

				for _, key in ipairs({other1, other2, current}) do
					expect(file.IsDir(Cache.Dir(key), "DATA")).to.beTrue()
					expect(file.Exists(Cache.Dir(key) .. "/index.json", "DATA")).to.beTrue()
				end

				expect(Cache.Has(t)).to.beTrue()
				expect(Cache.Prune()).to.equal(0) -- nothing left to remove
			end
		},
		{
			name = "nothing is left behind: no test directory under data/grymod/minimap, Cache.Key and game.GetMap are the originals",
			func = function()
				-- the cases above ran their afterEach (restore and sweep): what they left would show here, before this case writes anything
				expect(lastAfter).to.exist()
				expect(lastAfter.keyBack).to.beTrue()
				expect(lastAfter.mapBack).to.beTrue()
				expect(#leftovers()).to.equal(0)
			end
		},
	}
}
