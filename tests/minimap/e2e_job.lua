-- End-to-end checks of the minimap pipeline with the REAL modules (Capture, DXT1, VTF, Cache, Gen), to run as a gmod-mcp lua_job in the CLIENT realm:
--   lua_job {realm = "client", instance = "client-5540", path = ".../tests/minimap/e2e_job.lua", timeout_s = 240}
-- It needs a render context for the capture and for the pixels of a drawn material, so those parts run inside one-shot PostRender hooks; everything else runs in
-- the job (job:step() / job:yield(), no slice above about 8 ms). args.only = "1235" runs only the listed scenarios (default: all):
--   1  one tile of 512 px: Capture.Render -> DXT1.Compress (alpha) -> Cache.Store (20) -> Has -> Material (not an error, 512x512) -> VTF.Parse of the file
--   2  a tile rewritten under the same name: does the material show the NEW pixels? (reads the centre pixel with render.ReadPixel before / after, over frames)
--   3  the void rule end to end: the captured tile drawn on an opaque red background: void pixels show red, solid pixels the map (proportions)
--   4  the real generator: Gen.Request over a small extent (3 x 3 tiles at least: the request adds a tile of margin), progress, events, hook removal, timing,
--      then the same with a floor `below`
--   5  Gen.Cancel in the middle, Cache.Trim on the real tiles, Cache.Clear, nothing left in data/grymod/minimap/test_e2e_*
-- (the key change of map and Cache.Prune are in tests/minimap/e2e_test.lua)
--
-- Isolation: Cache.Key is replaced by a stand-in returning a TEST key ("test_e2e_job_<time>_v2") and Cache.Reset() is called, so the real cache of the map is
-- never read nor written. Other stand-ins: Settings.Enabled (false: the radar does not call Gen.Request / View.Draw meanwhile), Settings.TileRes (512) and
-- Settings.Definition (3), Gen.Step (a timing wrapper) and Cache.Store (a logging wrapper). Everything is put back in a pcall at the end, whatever happened, the
-- real Gen request is cancelled at the start (the radar asks again by itself) and data/grymod/minimap/test_e2e_* is deleted.

local M = GryMod.Minimap
local Cache, Capture, DXT1, VTF, Gen, Settings = M.Cache, M.Capture, M.DXT1, M.VTF, M.Gen, M.Settings

assert(Cache and Capture and DXT1 and VTF and Gen and Settings, "a minimap module is not loaded")
assert(Capture.Render and DXT1.Compress and Cache.Store and Gen.Request and Gen._state, "a minimap module is incomplete")

local only = args and args.only
local floor, abs, byte, char = math.floor, math.abs, string.byte, string.char

local function want(n)
	return only == nil or string.find(only, tostring(n), 1, true) ~= nil
end

local RES, PPM = 512, 3
local ROOT = "grymod/minimap"

local out = {checks = {}, failures = {}, measures = {}}

local function check(name, cond, detail)
	if cond then
		out.checks[#out.checks + 1] = "PASS " .. name
	else
		out.checks[#out.checks + 1] = "FAIL " .. name .. ": " .. tostring(detail)
		out.failures[#out.failures + 1] = name .. ": " .. tostring(detail)
	end
end

local function measure(name, value)
	out.measures[name] = value
end

-- ---------------------------------------------------------------------------------------------------------
-- stand-ins and their restoration
-- ---------------------------------------------------------------------------------------------------------
local orig = {
	Key = Cache.Key,
	Store = Cache.Store,
	StoreEmpty = Cache.StoreEmpty,
	Step = Gen.Step,
	Enabled = Settings.Enabled,
	TileRes = Settings.TileRes,
	Definition = Settings.Definition,
	prunedMap = Gen._state.prunedMap,
	storedSinceTrim = Gen._state.storedSinceTrim
}

local testKey = Cache.KeyFor("test_e2e_job", os.time() % 1000000)

-- The instance is shared: another agent's test or job may replace a module (GryMod.Minimap.Gen = nil, a stand-in Cache...) while this job waits for frames.
-- intact() says whether what this job installed and the modules it works with are still the ones it saw; a Gen scenario that fails while it is false was
-- disturbed from outside, not broken (the report says so: out.interference).
local seen = {}

-- the things this job relies on, by name: {table, field} pairs compared with what they were when the job installed its stand-ins
local function watched()
	return {
		{"M.Gen", M.Gen, seen.Gen}, {"M.Cache", M.Cache, seen.Cache}, {"M.Capture", M.Capture, seen.Capture}, {"M.DXT1", M.DXT1, seen.DXT1},
		{"M.Settings", M.Settings, seen.Settings}, {"M.VTF", M.VTF, seen.VTF},
		{"Gen.Request", Gen.Request, seen.Request}, {"Gen.Step", Gen.Step, seen.Step}, {"Gen.Cancel", Gen.Cancel, seen.Cancel},
		{"Cache.Key", Cache.Key, seen.Key}, {"Cache.Store", Cache.Store, seen.CacheStore}, {"Cache.Has", Cache.Has, seen.Has},
		{"Cache.Material", Cache.Material, seen.Material}, {"Cache.StoreEmpty", Cache.StoreEmpty, seen.StoreEmpty}, {"Cache.Reset", Cache.Reset, seen.Reset},
		{"Capture.Render", Capture.Render, seen.Render}, {"DXT1.CompressRows", DXT1.CompressRows, seen.CompressRows},
		{"VTF.Write", VTF.Write, seen.VTFWrite}, {"Settings.TileRes", Settings.TileRes, seen.TileRes}, {"Settings.Definition", Settings.Definition, seen.Definition},
		{"Settings.Enabled", Settings.Enabled, seen.Enabled}
	}
end

-- name of the first watched thing that is not what the job saw, or nil
local function brokenThing()
	for _, w in ipairs(watched()) do
		if w[2] ~= w[3] then
			return w[1]
		end
	end

	return nil
end

local function intact()
	return brokenThing() == nil
end

-- records the first thing found changed (called every frame of a wait and after each run)
local function noteInterference(label)
	local what = brokenThing()

	if what then
		out.interference = out.interference or {}

		if #out.interference < 6 then
			out.interference[#out.interference + 1] = label .. ": " .. what .. " changed at frame " .. FrameNumber()
		end
	end
end

local hookNames = {}
local started = false

-- the stand-ins this job installed (filled by installStandIns); restoreAll puts a field back ONLY if it still holds this job's stand-in: when the owner of a module saved
-- a new version meanwhile, the game reloaded it, and writing the old function back would bring the stale code back
local mine = {}

local function restoreField(tbl, name, key)
	if mine[key] ~= nil and tbl[name] == mine[key] then
		tbl[name] = orig[key]
	end
end

local function restoreAll()
	pcall(Gen.Cancel)

	for _, h in ipairs(hookNames) do
		pcall(hook.Remove, h[1], h[2])
	end

	restoreField(Gen, "Step", "Step")
	restoreField(Cache, "Store", "Store")
	restoreField(Cache, "StoreEmpty", "StoreEmpty")
	restoreField(Cache, "Key", "Key")
	restoreField(Settings, "Enabled", "Enabled")
	restoreField(Settings, "TileRes", "TileRes")
	restoreField(Settings, "Definition", "Definition")

	if Gen._state then
		Gen._state.prunedMap = orig.prunedMap
		Gen._state.storedSinceTrim = orig.storedSinceTrim or 0
	end

	Cache.Reset()
end

local function sweepAll()
	local _, dirs = file.Find(ROOT .. "/test_e2e_*", "DATA")

	for _, d in ipairs(dirs or {}) do
		for _, f in ipairs(file.Find(ROOT .. "/" .. d .. "/*", "DATA") or {}) do
			file.Delete(ROOT .. "/" .. d .. "/" .. f)
		end

		file.Delete(ROOT .. "/" .. d)
	end

	return #(select(2, file.Find(ROOT .. "/test_e2e_*", "DATA")) or {})
end

local function addHook(event, name, f)
	hook.Add(event, name, f)
	hookNames[#hookNames + 1] = {event, name}
end

-- ---------------------------------------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------------------------------------
local function waitFor(f, seconds)
	local t0 = SysTime()

	while not f() and SysTime() - t0 < seconds do
		job:yield()
	end

	return f()
end

-- runs fn() in a one-shot PostRender hook (render context); returns fn's first result, or nil, reason
local function inRender(fn)
	local done, ok, res = false, nil, nil
	local name = "gry_e2e_job_render"

	addHook("PostRender", name, function()
		hook.Remove("PostRender", name)
		ok, res = pcall(fn)
		done = true
	end)

	if not waitFor(function() return done end, 20) then
		pcall(hook.Remove, "PostRender", name)

		return nil, "no PostRender within 20 s"
	end

	if not ok then
		return nil, "raised: " .. tostring(res)
	end

	return res
end

-- draws mat over the whole target (1:1) on an opaque background; returns {pixels at pts (render.ReadPixel)}, bgra of the whole target (render.Capture) or nil
local function drawOn(mat, bg, pts, wantFull)
	local rt = Capture.GetRT(RES)
	local result = {}

	render.PushRenderTarget(rt)

	local ok, err = pcall(function()
		render.Clear(bg[1], bg[2], bg[3], 255, true, true)
		cam.Start2D()

		local ok2, err2 = pcall(function()
			surface.SetMaterial(mat)
			surface.SetDrawColor(255, 255, 255, 255)
			-- one textured quad with surface.DrawPoly, the way View.Draw draws a tile (clockwise on screen, u v over the whole texture)
			surface.DrawPoly({
				{x = 0, y = 0, u = 0, v = 0},
				{x = RES, y = 0, u = 1, v = 0},
				{x = RES, y = RES, u = 1, v = 1},
				{x = 0, y = RES, u = 0, v = 1}
			})
		end)

		cam.End2D()

		if not ok2 then
			error(err2, 0)
		end

		if pts then
			render.CapturePixels()
			result.pixels = {}

			for i, p in ipairs(pts) do
				local r, g, b, a = render.ReadPixel(p[1], p[2])

				result.pixels[i] = {r = r, g = g, b = b, a = a}
			end
		end

		if wantFull then
			result.full = render.Capture({format = "bgra", x = 0, y = 0, w = RES, h = RES})
		end
	end)

	render.PopRenderTarget()

	if not ok then
		error(err, 0)
	end

	return result
end

local function near(p, r, g, b, tol)
	return abs(p.r - r) <= tol and abs(p.g - g) <= tol and abs(p.b - b) <= tol
end

local function fileBytes(path)
	local s = file.Size(path, "DATA")

	return (s and s > 0) and s or 0
end

-- a picture of one flat colour (BGRA, opaque), compressed in slices; returns the DXT1 (format 20 compatible: alpha option on)
local function flatDXT(b, g, r)
	local bgra = string.rep(char(b, g, r, 255), RES * RES)
	local parts = {}
	local rows = RES / 4

	for first = 0, rows - 1, 32 do
		parts[#parts + 1] = DXT1.CompressRows(bgra, RES, RES, first, math.min(first + 31, rows - 1), {alpha = true})
		job:step()
	end

	return table.concat(parts)
end

-- the tiles of a request, as Gen.Request computes them (the test's oracle: the square around (cx, cy) plus one tile of margin)
local function tileList(levelId, cx, cy, extent)
	local tx0, ty0 = Cache.TileOf(cx - extent, cy - extent, RES, PPM)
	local tx1, ty1 = Cache.TileOf(cx + extent, cy + extent, RES, PPM)
	local list = {}

	for tx = tx0 - 1, tx1 + 1 do
		for ty = ty0 - 1, ty1 + 1 do
			list[#list + 1] = {level = levelId, tx = tx, ty = ty, res = RES, ppm = PPM}
		end
	end

	return list
end

local function countHave(list)
	local n = 0

	for _, t in ipairs(list) do
		if Cache.Has(t) then
			n = n + 1
		end
	end

	return n
end

local function removeHookCheck()
	local t = hook.GetTable().PostRender

	return not (t and t[Gen.HOOK_NAME] ~= nil)
end

-- ---------------------------------------------------------------------------------------------------------
-- the scenarios
-- ---------------------------------------------------------------------------------------------------------
local tile1, level1, bgra1, dxt1, mat1

local function scenario1()
	local pos = LocalPlayer():GetPos()
	local T = Cache.TileUnits(RES, PPM)

	tile1 = {level = "e2e1", tx = floor(pos.x / T), ty = floor(pos.y / T), res = RES, ppm = PPM}
	level1 = {id = "e2e1", zlo = pos.z - 56, zhi = pos.z + 72}
	measure("tile1", tile1)
	measure("tileUnits", T)

	local r, why = inRender(function()
		local t0 = SysTime()
		local b, err = Capture.Render(tile1, level1)

		return {b = b, err = err, ms = (SysTime() - t0) * 1000}
	end)

	check("1 capture: Capture.Render answered", r ~= nil and r.b ~= nil, why or (r and r.err))

	if not (r and r.b) then
		return
	end

	bgra1 = r.b
	measure("capture_ms", r.ms)
	check("1 capture: length is res*res*4", #bgra1 == RES * RES * 4, #bgra1)

	job:yield() -- a fresh frame for the compression (about 6 ms)

	local t0 = SysTime()
	local err

	dxt1, err = DXT1.Compress(bgra1, RES, RES, {alpha = true})
	measure("compress_ms", (SysTime() - t0) * 1000)
	check("1 compress: DXT1.Compress with alpha", dxt1 ~= nil and #dxt1 == RES * RES / 2, err or (dxt1 and #dxt1))

	if not dxt1 then
		return
	end

	local ok, serr = Cache.Store(tile1, dxt1, 20)

	check("1 store: Cache.Store(tile, dxt, 20)", ok == true, serr)
	check("1 Cache.Has(tile)", Cache.Has(tile1) == true, "Has is false after Store")
	check("1 Cache.Count() == 1", Cache.Count() == 1, Cache.Count())

	local path = Cache.Path(tile1)
	local bytes = file.Read(path .. ".vtf", "DATA")
	local info, perr = VTF.Parse(bytes or "")

	check("1 VTF.Parse of the written file", info ~= nil, perr)

	if info then
		check("1 vtf format 20", info.format == 20, info.format)
		check("1 vtf flags 0x130C", info.flags == 0x130C, string.format("0x%X", info.flags))
		check("1 vtf size 512x512", info.width == RES and info.height == RES, info.width .. "x" .. info.height)
		check("1 vtf data length 512*512/2", info.dataLength == RES * RES / 2, info.dataLength)
		check("1 vtf data is the compressed tile", string.sub(bytes, info.dataOffset + 1) == dxt1, "bytes differ")
	end

	mat1 = Cache.Material(tile1)
	check("1 Cache.Material non nil", mat1 ~= nil, "nil")

	if mat1 then
		check("1 material is not an error", mat1:IsError() == false, "IsError")

		-- the texture is loaded in the background on some games (no GetTexture for 1 to 2 frames): wait up to 20 frames for it
		local tex

		waitFor(function()
			tex = mat1:GetTexture("$basetexture")

			return tex ~= nil
		end, 2)

		check("1 texture 512x512", tex ~= nil and tex:Width() == RES and tex:Height() == RES, tex and (tex:Width() .. "x" .. tex:Height()) or "no texture after 2 s")
	end
end

local function scenario2()
	local t = {level = "e2e2", tx = 0, ty = 0, res = RES, ppm = PPM}
	local A = {0, 200, 0} -- B, G, R of the first picture: green
	local B = {200, 0, 200} -- magenta
	local dA, dB = flatDXT(A[1], A[2], A[3]), flatDXT(B[1], B[2], B[3])
	local pts = {{256, 256}, {100, 400}}

	check("2 Store A", Cache.Store(t, dA, 20) == true, "Store failed")

	local matA = Cache.Material(t)

	check("2 Material A", matA ~= nil, "nil")

	if not matA then
		return
	end

	local rA, whyA = inRender(function() return drawOn(matA, {255, 0, 0}, pts, false) end)

	check("2 drew A", rA ~= nil, whyA)

	if not rA then
		return
	end

	local pa = rA.pixels[1]

	measure("2_pixel_A", {r = pa.r, g = pa.g, b = pa.b, a = pa.a})
	check("2 pixel of A is green (0,200,0)", near(pa, 0, 200, 0, 12), pa.r .. "," .. pa.g .. "," .. pa.b)

	-- the rewrite under the same name, then the material as the radar would ask for it
	check("2 Store B (same name)", Cache.Store(t, dB, 20) == true, "Store failed")

	local matB = Cache.Material(t)

	check("2 Material B", matB ~= nil, "nil")
	measure("2_same_material_object", matB == matA)

	if not matB then
		return
	end

	local reads, changedAt = {}, nil

	for _, wait in ipairs({0, 1, 2, 5, 10, 20}) do
		for _ = 1, wait do
			job:yield()
		end

		local r = inRender(function() return drawOn(matB, {255, 0, 0}, pts, false) end)
		local p = r and r.pixels[1]

		reads[#reads + 1] = {framesLater = wait, r = p and p.r, g = p and p.g, b = p and p.b}

		if p and near(p, 200, 0, 200, 12) and not changedAt then
			changedAt = wait
		end
	end

	measure("2_pixel_after_rewrite_by_frames", reads)
	check("2 the new pixels show within 10 frames of the rewrite (measured: the old pixels stay 1 to 5 frames, the engine reloads the texture later)", changedAt ~= nil and changedAt <= 10,
		"still the old pixel after 20 frames: " .. reads[#reads].r .. "," .. reads[#reads].g .. "," .. reads[#reads].b)

	if changedAt == nil then
		-- experiments, only to name a correction: Download() after the write, then a new name
		local tex = matB:GetTexture("$basetexture")

		pcall(tex.Download, tex)
		job:yield()
		job:yield()

		local r1 = inRender(function() return drawOn(matB, {255, 0, 0}, pts, false) end)

		measure("2_after_Download_after_write", r1 and {r = r1.pixels[1].r, g = r1.pixels[1].g, b = r1.pixels[1].b})

		pcall(matB.Recompute, matB)
		job:yield()

		local r2 = inRender(function() return drawOn(matB, {255, 0, 0}, pts, false) end)

		measure("2_after_Recompute", r2 and {r = r2.pixels[1].r, g = r2.pixels[1].g, b = r2.pixels[1].b})

		local t2 = {level = "e2e2r1", tx = 0, ty = 0, res = RES, ppm = PPM}

		Cache.Store(t2, dB, 20)

		local m2 = Cache.Material(t2)
		local r3 = m2 and inRender(function() return drawOn(m2, {255, 0, 0}, pts, false) end)

		measure("2_new_name_pixel", r3 and {r = r3.pixels[1].r, g = r3.pixels[1].g, b = r3.pixels[1].b})
	end
end

-- 3b: a synthetic tile, void on one half and solid green on the other (an edge on a block boundary), drawn 1:1 on red: is the edge sharp (a texel maps to exactly
-- one pixel) or blurred / shifted by the engine's sampling? Once with a vertical edge (void left, x = 255 / 256), once with a horizontal one (void on top, y = 255 / 256).
local function scenario3b()
	local half = RES / 2
	local parts, rows = {}, RES / 4

	for _, kind in ipairs({"vertical", "horizontal"}) do
		local t = {level = "e2e3b" .. kind, tx = 0, ty = 0, res = RES, ppm = PPM}
		local bgra

		if kind == "vertical" then
			bgra = string.rep(string.rep("    ", half) .. string.rep(char(0, 200, 0, 255), half), RES)
		else
			bgra = string.rep(string.rep("    ", RES), half) .. string.rep(string.rep(char(0, 200, 0, 255), RES), half)
		end

		parts = {}

		for first = 0, rows - 1, 32 do
			parts[#parts + 1] = DXT1.CompressRows(bgra, RES, RES, first, math.min(first + 31, rows - 1), {alpha = true})
			job:step()
		end

		check("3b store the " .. kind .. " half void / half green tile", Cache.Store(t, table.concat(parts), 20) == true, "Store failed")

		local mat = Cache.Material(t)

		if not mat then
			check("3b material " .. kind, false, "nil")
		else
			local pts = {}

			for k = half - 4, half + 3 do
				pts[#pts + 1] = kind == "vertical" and {k, 100} or {100, k}
			end

			local r = inRender(function() return drawOn(mat, {255, 0, 0}, pts, false) end)

			if not r then
				check("3b drew " .. kind, false, "no result")
			else
				local line = {}

				for i, p in ipairs(r.pixels) do
					line[i] = {at = half - 5 + i, r = p.r, g = p.g, b = p.b}
				end

				measure("3b_" .. kind .. "_pixels_" .. (half - 4) .. "_to_" .. (half + 3), line)

				local left, right = r.pixels[4], r.pixels[5] -- 255 (last void) and 256 (first solid)

				check("3b " .. kind .. ": the last void pixel is pure red", left.r >= 250 and left.g <= 5 and left.b <= 5, left.r .. "," .. left.g .. "," .. left.b)
				check("3b " .. kind .. ": the first solid pixel is pure green", right.r <= 5 and right.g >= 195 and right.b <= 5, right.r .. "," .. right.g .. "," .. right.b)
			end
		end
	end
end

-- 3c: alternating columns (void, green, void, green...): a texel-exact 1:1 draw keeps the alternation; a lower mip level or a filter would average neighbours
local function scenario3c()
	local t = {level = "e2e3c", tx = 0, ty = 0, res = RES, ppm = PPM}
	local row = string.rep("    " .. char(0, 200, 0, 255), RES / 2)
	local bgra = string.rep(row, RES)
	local parts, rows = {}, RES / 4

	for first = 0, rows - 1, 32 do
		parts[#parts + 1] = DXT1.CompressRows(bgra, RES, RES, first, math.min(first + 31, rows - 1), {alpha = true})
		job:step()
	end

	check("3c store the alternating columns tile", Cache.Store(t, table.concat(parts), 20) == true, "Store failed")

	local mat = Cache.Material(t)

	if not mat then
		check("3c material", false, "nil")

		return
	end

	-- eight pixels at x = 8.., 252.. and 500.. : does the blur depend on the place in the tile (a scale / offset error of the 1:1 draw)?
	local pts, starts = {}, {8, 252, 500}

	for _, x0 in ipairs(starts) do
		for x = x0, x0 + 7 do
			pts[#pts + 1] = {x, 100}
		end
	end

	local r = inRender(function() return drawOn(mat, {255, 0, 0}, pts, false) end)

	if not r then
		check("3c drew", false, "no result")

		return
	end

	local line = {}

	for i, p in ipairs(r.pixels) do
		line[i] = p.r .. "," .. p.g .. "," .. p.b
	end

	measure("3c_row100_x8_252_500_rgb", line)
	r.pixels = {unpack(r.pixels, 1, 8)}
	measure("mat_picmip", GetConVar("mat_picmip") and GetConVar("mat_picmip"):GetInt())

	-- even x = void (red), odd x = green
	local sharp = r.pixels[1].r >= 250 and r.pixels[2].g >= 195 and r.pixels[3].r >= 250 and r.pixels[4].g >= 195

	check("3c alternating void / solid columns stay one pixel wide (texel-exact sampling)", sharp, table.concat(line, " | "))
end

local function scenario3()
	if not (tile1 and bgra1 and dxt1 and mat1) then
		check("3 needs scenario 1", false, "scenario 1 gave no tile")

		return
	end

	local r, why = inRender(function() return drawOn(mat1, {255, 0, 0}, nil, true) end)

	check("3 drew the tile on a red background", r ~= nil and r.full ~= nil, why)

	if not (r and r.full) then
		return
	end

	local rend = r.full
	local IsVoid = Capture.IsVoid
	local c = {void = 0, voidDecTransparent = 0, voidRed = 0, solid = 0, solidDecOpaque = 0, solidEqDecode = 0, solidWithin16 = 0, solidWithin32 = 0, solidTurnedRed = 0}
	local bands, bandRows = RES / 4 / 16, 64

	for band = 0, bands - 1 do
		local sub = string.sub(dxt1, band * 16 * (RES / 4) * 8 + 1, (band + 1) * 16 * (RES / 4) * 8)
		local dec = DXT1.Decode(sub, RES, bandRows)

		job:step()

		for row = 0, bandRows - 1 do
			local y = band * bandRows + row

			for x = 0, RES - 1 do
				local i = (y * RES + x) * 4 + 1
				local j = (row * RES + x) * 4 + 1
				local ob, og, orr, oa = byte(bgra1, i, i + 3)
				local rb, rg, rr = byte(rend, i, i + 2)
				local db, dg, dr, da = byte(dec, j, j + 3)
				local red = rr >= 240 and rg <= 15 and rb <= 15

				if IsVoid(ob, og, orr, oa) then
					c.void = c.void + 1

					if da == 0 then
						c.voidDecTransparent = c.voidDecTransparent + 1
					end

					if red then
						c.voidRed = c.voidRed + 1
					end
				else
					c.solid = c.solid + 1

					if da == 255 then
						c.solidDecOpaque = c.solidDecOpaque + 1
					end

					local d = abs(rb - ob)
					local d2 = abs(rg - og)
					local d3 = abs(rr - orr)

					if d2 > d then d = d2 end
					if d3 > d then d = d3 end

					if d <= 16 then
						c.solidWithin16 = c.solidWithin16 + 1
					end

					if d <= 32 then
						c.solidWithin32 = c.solidWithin32 + 1
					end

					local e, e2, e3 = abs(rb - db), abs(rg - dg), abs(rr - dr)

					if e2 > e then e = e2 end
					if e3 > e then e = e3 end

					if e <= 8 then
						c.solidEqDecode = c.solidEqDecode + 1
					end

					if red and not (orr >= 240 and og <= 15 and ob <= 15) then
						c.solidTurnedRed = c.solidTurnedRed + 1
					end

					-- diagnosis: a solid pixel with a void pixel next to it (4-neighbourhood, in the capture) is an "edge" pixel; the others are "interior"
					local edge = false

					if x > 0 and IsVoid(byte(bgra1, i - 4, i - 1)) then edge = true end
					if x < RES - 1 and IsVoid(byte(bgra1, i + 4, i + 7)) then edge = true end
					if y > 0 and IsVoid(byte(bgra1, i - RES * 4, i - RES * 4 + 3)) then edge = true end
					if y < RES - 1 and IsVoid(byte(bgra1, i + RES * 4, i + RES * 4 + 3)) then edge = true end

					if edge then
						c.edge = (c.edge or 0) + 1

						if e <= 8 then c.edgeEq = (c.edgeEq or 0) + 1 end
						if d <= 32 then c.edgeW32 = (c.edgeW32 or 0) + 1 end
					else
						c.interior = (c.interior or 0) + 1

						if e <= 8 then c.interiorEq = (c.interiorEq or 0) + 1 end
						if d <= 32 then c.interiorW32 = (c.interiorW32 or 0) + 1 end

						if e > 8 and (c.samples or 0) < 3 then
							c.samples = (c.samples or 0) + 1
							out.mismatchSamples = out.mismatchSamples or {}
							local bx, by = floor(x / 4), floor(y / 4)
							local bytesAt = (by * (RES / 4) + bx) * 8 + 1
							local c0lo, c0hi, c1lo, c1hi = byte(dxt1, bytesAt, bytesAt + 3)
							local blk = {}

							for yy = 0, 3 do
								for xx = 0, 3 do
									local ii = ((by * 4 + yy) * RES + bx * 4 + xx) * 4 + 1
									local jj = ((by * 4 + yy - band * bandRows) * RES + bx * 4 + xx) * 4 + 1
									local qb, qg, qr, qa = byte(bgra1, ii, ii + 3)
									local wb, wg, wr = byte(rend, ii, ii + 2)
									local kb, kg, kr, ka = byte(dec, jj, jj + 3)

									blk[#blk + 1] = "cap " .. qr .. "," .. qg .. "," .. qb .. "," .. qa .. " dec " .. kr .. "," .. kg .. "," .. kb .. "," .. ka .. " rend " .. wr .. "," .. wg .. "," .. wb
								end
							end

							out.mismatchSamples[#out.mismatchSamples + 1] = {x = x, y = y, c0 = c0lo + c0hi * 256, c1 = c1lo + c1hi * 256, block = blk}
						end
					end
				end
			end

			if row % 8 == 7 then
				job:step()
			end
		end
	end

	local function pct(a, b)
		if b == 0 then
			return nil
		end

		return floor(a * 10000 / b + 0.5) / 100
	end

	measure("3_counts", c)
	measure("3_pct", {
		void_rendered_red = pct(c.voidRed, c.void),
		void_decoded_transparent = pct(c.voidDecTransparent, c.void),
		solid_decoded_opaque = pct(c.solidDecOpaque, c.solid),
		solid_equals_engine_decode_8 = pct(c.solidEqDecode, c.solid),
		solid_within16_of_capture = pct(c.solidWithin16, c.solid),
		solid_within32_of_capture = pct(c.solidWithin32, c.solid),
		solid_turned_red = pct(c.solidTurnedRed, c.solid),
		void_share_of_tile = pct(c.void, c.void + c.solid)
	})

	check("3 the capture has void pixels and solid pixels", c.void > 0 and c.solid > 0, "void " .. c.void .. " solid " .. c.solid)

	if c.void > 0 and c.solid > 0 then
		check("3 every void pixel shows the red background (>= 99.9 %)", c.voidRed / c.void >= 0.999, pct(c.voidRed, c.void) .. " %")
		check("3 every solid pixel is the engine's decode of the DXT1A data (within 8, >= 99.9 %)", c.solidEqDecode / c.solid >= 0.999, pct(c.solidEqDecode, c.solid) .. " %")
		-- the rest is the compression error of the 3-colour blocks (about 1 % of the solid pixels are more than 32 away, 12 % more than 16), not a rendering one
		check("3 at least 95 % of the solid pixels keep the map colour (within 32 of the capture)", c.solidWithin32 / c.solid >= 0.95, pct(c.solidWithin32, c.solid) .. " %")
		check("3 at most 0.1 % of the solid pixels turned transparent", c.solidTurnedRed / c.solid <= 0.001, pct(c.solidTurnedRed, c.solid) .. " %")
	end
end

-- stats of Gen.Step (the timing wrapper)
local stepStats = {n = 0, max = 0, total = 0, over8 = 0, over16 = 0, errors = 0}
local ev = {progress = {}, ready = 0, below = 0}
local storeLog = {}
local storeTiles = {} -- the same tiles as tables (for Has)
local emptyLog = {} -- the tiles the generator recorded as empty (Cache.StoreEmpty)

local function resetRun()
	stepStats.n, stepStats.max, stepStats.total, stepStats.over8, stepStats.over16, stepStats.errors = 0, 0, 0, 0, 0, 0
	ev.progress, ev.ready, ev.below, ev.belowAtReady, ev.mainAtBelow = {}, 0, 0, nil, nil
end

local function genRun(label, level, below, cx, cy, extent)
	resetRun()

	ev.mainList = tileList(level.id, cx, cy, extent)
	ev.belowList = below and tileList(below.id, cx, cy, extent) or {}

	local before = Cache.Count()
	local t0 = SysTime()
	local frames0 = FrameNumber()
	local ok, why = Gen.Request(level, cx, cy, extent, below)

	check(label .. " Gen.Request accepted", ok == true, tostring(ok) .. " " .. tostring(why))

	local total = #ev.mainList
	local p0 = Gen.Progress()

	check(label .. " total tiles = 3x3 (range + margin)", p0.total == total, p0.total .. " vs " .. total)
	check(label .. " Progress starts at 0 %", p0.done == 0 and p0.percent == 0 and p0.active == true, p0.done .. " " .. p0.percent)

	local finished = waitFor(function()
		noteInterference(label)
		return (ev.ready >= 1 and (not below or ev.below >= 1)) or not intact()
	end, 90)

	local dt = SysTime() - t0
	local frames = FrameNumber() - frames0

	check(label .. " finished within 90 s", finished, "ready " .. ev.ready .. " below " .. ev.below .. " done " .. Gen.Progress().done)
	measure(label .. "_total_ms", floor(dt * 1000))
	measure(label .. "_frames", frames)
	measure(label .. "_steps", {n = stepStats.n, max_ms = floor(stepStats.max * 100) / 100, avg_ms = stepStats.n > 0 and floor(stepStats.total / stepStats.n * 100) / 100 or 0, over8 = stepStats.over8, over16 = stepStats.over16})

	local p = Gen.Progress()

	check(label .. " Progress 100 %", p.percent == 100 and p.done == total and p.total == total and p.failed == 0 and p.active == false,
		"done " .. p.done .. "/" .. p.total .. " " .. p.percent .. "% failed " .. p.failed .. " active " .. tostring(p.active))
	check(label .. " GryMod_MinimapReady fired exactly once", ev.ready == 1, ev.ready)

	local last = ev.progress[#ev.progress]

	check(label .. " last Progress event is (total, total)", last ~= nil and last[1] == total and last[2] == total, last and (last[1] .. "/" .. last[2]))

	local mono, dup = true, false

	for i = 2, #ev.progress do
		if ev.progress[i][1] < ev.progress[i - 1][1] then
			mono = false
		end

		if ev.progress[i][1] == ev.progress[i - 1][1] and ev.progress[i][2] == ev.progress[i - 1][2] then
			dup = true
		end
	end

	check(label .. " Progress events monotonic, none repeated", mono and not dup, "mono " .. tostring(mono) .. " dup " .. tostring(dup))
	check(label .. " Progress events: one per change (total + 1)", #ev.progress == total + 1, #ev.progress)

	local added = Cache.Count() - before
	local expectAdded = total + (below and #ev.belowList or 0)

	check(label .. " Cache.Count grew by " .. expectAdded, added == expectAdded, added)
	check(label .. " every wanted tile of the main level is in the cache", countHave(ev.mainList) == total, countHave(ev.mainList))
	check(label .. " Pending() == 0", Gen.Pending() == 0, Gen.Pending())

	job:yield()

	check(label .. " the generator's PostRender hook is gone", removeHookCheck(), "still in hook.GetTable().PostRender")
	check(label .. " no tile left in progress, no picture kept", Gen._state.current == nil, "Gen._state.current is set")

	if below then
		check(label .. " GryMod_MinimapBelowReady fired exactly once", ev.below == 1, ev.below)
		check(label .. " main level first: no below tile existed when Ready fired", ev.belowAtReady == 0, ev.belowAtReady)
		check(label .. " all main tiles existed when BelowReady fired", ev.mainAtBelow == total, ev.mainAtBelow)
		check(label .. " every below tile is in the cache", countHave(ev.belowList) == #ev.belowList, countHave(ev.belowList))
		check(label .. " belowDone/belowTotal", p.belowDone == #ev.belowList and p.belowTotal == #ev.belowList and p.belowFailed == 0,
			p.belowDone .. "/" .. p.belowTotal .. " failed " .. p.belowFailed)
	end

	-- a tile the generator found entirely empty is recorded with no file (Cache.StoreEmpty: Has true, Material nil); every other tile loads as a material
	local bad, emptyN, emptyWithFile = 0, 0, 0
	local isEmpty = Cache.IsEmpty or function() return false end

	for _, t in ipairs(ev.mainList) do
		if isEmpty(t) then
			emptyN = emptyN + 1

			local name = Cache.Name(t)

			if file.Exists(Cache.Dir() .. "/" .. name .. ".vtf", "DATA") or file.Exists(Cache.Dir() .. "/" .. name .. ".vmt", "DATA") then
				emptyWithFile = emptyWithFile + 1
			end
		else
			local m = Cache.Material(t)

			if not m or m:IsError() then
				bad = bad + 1
				out.badTiles = out.badTiles or {}

				if #out.badTiles < 12 then
					local name = Cache.Name(t)

					out.badTiles[#out.badTiles + 1] = {label = label, name = name, has = Cache.Has(t), vtf = file.Size(Cache.Dir() .. "/" .. name .. ".vtf", "DATA"), matNil = m == nil, isError = m ~= nil and m:IsError()}
				end
			end
		end
	end

	measure(label .. "_main_tiles_empty_vs_drawn", {empty = emptyN, drawn = total - emptyN})
	check(label .. " the non-empty main tiles load as materials", bad == 0, bad .. " bad")
	check(label .. " an empty tile has no .vtf / .vmt", emptyWithFile == 0, emptyWithFile .. " with a file")
	noteInterference(label)
end

local function installGenStandIns()
	Settings.Enabled = function() return false end
	Settings.TileRes = function() return RES end
	Settings.Definition = function() return PPM end

	Gen.Step = function(now)
		local t0 = SysTime()
		local ok, err = pcall(orig.Step, now)
		local ms = (SysTime() - t0) * 1000

		stepStats.n = stepStats.n + 1
		stepStats.total = stepStats.total + ms

		if ms > stepStats.max then
			stepStats.max = ms
		end

		if ms > 8 then
			stepStats.over8 = stepStats.over8 + 1
		end

		if ms > 16 then
			stepStats.over16 = stepStats.over16 + 1
		end

		if not ok then
			stepStats.errors = stepStats.errors + 1
			out.stepError = tostring(err)
		end
	end

	Cache.Store = function(tile, data, format)
		local ok, err = orig.Store(tile, data, format)

		if ok then
			storeLog[#storeLog + 1] = Cache.Name(tile)
			storeTiles[#storeTiles + 1] = tile
		end

		return ok, err
	end

	if orig.StoreEmpty then
		Cache.StoreEmpty = function(tile)
			local ok, err = orig.StoreEmpty(tile)

			if ok then
				emptyLog[#emptyLog + 1] = tile
			end

			return ok, err
		end
	end

	addHook("GryMod_MinimapProgress", "gry_e2e_progress", function(done, total)
		ev.progress[#ev.progress + 1] = {done, total}
	end)
	addHook("GryMod_MinimapReady", "gry_e2e_ready", function()
		ev.ready = ev.ready + 1
		ev.belowAtReady = countHave(ev.belowList or {})
	end)
	addHook("GryMod_MinimapBelowReady", "gry_e2e_below", function()
		ev.below = ev.below + 1
		ev.mainAtBelow = countHave(ev.mainList or {})
	end)
end

-- The instance is shared with other agents' tests and jobs, which may call Gen.Request / fire the Gen events / reload gen.lua while this job waits for frames. A Gen scenario
-- that fails is therefore run again (up to 3 times, on fresh level ids, after a pause of 3 seconds); the checks of the attempts before the last one are thrown away from
-- the result and kept in out.discardedAttempts, so that a bug that shows every time is reported (it fails every attempt) and an outside disturbance is not.
local function withRetries(label, fn)
	for n = 1, 3 do
		local c0, f0 = #out.checks, #out.failures

		fn(n)

		if #out.failures == f0 or n == 3 then
			out.attempts = out.attempts or {}
			out.attempts[label] = n

			return
		end

		local dropped = {}

		for i = #out.failures, f0 + 1, -1 do
			dropped[#dropped + 1] = out.failures[i]
			out.failures[i] = nil
		end

		for i = #out.checks, c0 + 1, -1 do
			out.checks[i] = nil
		end

		out.discardedAttempts = out.discardedAttempts or {}
		out.discardedAttempts[#out.discardedAttempts + 1] = {scenario = label, attempt = n, failures = dropped}
		pcall(Gen.Cancel)

		for _ = 1, 180 do
			job:yield()
		end
	end
end

local function scenario4(n)
	local pos = LocalPlayer():GetPos()
	local T = Cache.TileUnits(RES, PPM)
	local cx, cy = (floor(pos.x / T) + 0.5) * T, (floor(pos.y / T) + 0.5) * T
	local extent = 100

	-- 4a: the main level only
	local levelA = {id = "e2e4a" .. n, zlo = pos.z - 56, zhi = pos.z + 72}

	genRun("4a", levelA, nil, cx, cy, extent)

	-- 4b: a new main level and the floor below
	local levelB = {id = "e2e4b" .. n, zlo = pos.z - 56, zhi = pos.z + 72}
	local below = {id = "e2e4below" .. n, zlo = pos.z - 184, zhi = pos.z - 56}

	genRun("4b", levelB, below, cx, cy, extent)

	-- the same request again does nothing
	local again = Gen.Request(levelB, cx, cy, extent, below)

	check("4 the same request again returns false and changes nothing", again == false, tostring(again))
	check("4 ... and adds no hook", removeHookCheck(), "hook added")
end

local function scenario5(n)
	local pos = LocalPlayer():GetPos()
	local T = Cache.TileUnits(RES, PPM)
	local cx, cy = (floor(pos.x / T) + 0.5) * T, (floor(pos.y / T) + 0.5) * T
	local level = {id = "e2e5" .. n, zlo = pos.z - 56, zhi = pos.z + 72}

	resetRun()
	ev.mainList, ev.belowList = tileList(level.id, cx, cy, 100), {}

	local before, logBefore, emptyBefore = Cache.Count(), #storeLog, #emptyLog
	local ok = Gen.Request(level, cx, cy, 100)

	check("5 Request accepted", ok == true, tostring(ok))

	local reached = waitFor(function() noteInterference("5"); return Gen.Progress().done >= 3 or not intact() end, 60)

	check("5 three tiles done before the cancel", reached, Gen.Progress().done)

	local stepsBefore = stepStats.n

	Gen.Cancel()

	local p = Gen.Progress()
	local stored = Cache.Count() - before

	measure("5_tiles_stored_before_cancel", stored)
	check("5 after Cancel: Pending() == 0", Gen.Pending() == 0, Gen.Pending())
	check("5 after Cancel: not active, request forgotten", p.active == false and p.total == 0 and p.done == 0, p.done .. "/" .. p.total)
	check("5 after Cancel: the hook is gone", removeHookCheck(), "still hooked")
	check("5 after Cancel: no tile in progress", Gen._state.current == nil, "current set")

	local readyAt = ev.ready

	for _ = 1, 10 do
		job:yield()
	end

	check("5 ten frames later: no new tile, no Step, no Ready", Cache.Count() - before == stored and stepStats.n == stepsBefore and ev.ready == readyAt,
		(Cache.Count() - before) .. " vs " .. stored .. ", steps " .. stepStats.n .. " vs " .. stepsBefore .. ", ready " .. ev.ready)

	-- the tiles of this run: the real ones (Cache.Store) and the ones recorded as empty (Cache.StoreEmpty, no file)
	local mine = {}

	for i = logBefore + 1, #storeLog do
		mine[#mine + 1] = storeLog[i]
	end

	check("5 the tiles of this run are all accounted for (stored + empty)", #mine + (#emptyLog - emptyBefore) == stored, #mine .. " + " .. (#emptyLog - emptyBefore) .. " vs " .. stored)

	-- Trim on the real tiles of the whole run (Trim never counts nor removes an empty tile): keep two of them
	local emptyNow = 0

	for _, t in ipairs(emptyLog) do
		if Cache.IsEmpty(t) then
			emptyNow = emptyNow + 1
		end
	end

	local dir = Cache.Dir()
	local oneTile = fileBytes(dir .. "/" .. storeLog[#storeLog] .. ".vtf") + fileBytes(dir .. "/" .. storeLog[#storeLog] .. ".vmt")
	local total = Cache.Trim(1e12)

	check("5 Trim above the size removes nothing", total ~= nil and total.removed == 0, total and total.removed)

	-- the oldest stored tile is used again: it is now the most recently used one (Trim is LRU: a Has that says yes counts as a use)
	local revived = storeTiles[1]

	check("5 the oldest stored tile is still there before the Trim", revived ~= nil and Cache.Has(revived) == true, "gone")

	local r = Cache.Trim(floor(oneTile * 2.4)) -- target 90 % = 2.16 tiles: two stay

	measure("5_trim", {tileBytes = oneTile, cacheBytesBefore = total and total.bytes, removed = r and r.removed, bytesLeft = r and r.bytes, emptyTilesKept = emptyNow, realTilesBefore = #storeLog})
	check("5 Trim(2.4 tiles) leaves exactly 2 real tiles (+ the empty ones, which it never touches)", r ~= nil and Cache.Count() == 2 + emptyNow, Cache.Count() .. " vs 2 + " .. emptyNow)

	if #storeLog >= 3 and Cache.Count() == 2 + emptyNow then
		local last = storeLog[#storeLog]

		check("5 the last stored tile stays (Trim never removes it)", file.Exists(dir .. "/" .. last .. ".vtf", "DATA"), "gone")
		check("5 the tile used again stays (least recently used go first)", file.Exists(dir .. "/" .. storeLog[1] .. ".vtf", "DATA"), "gone")
		check("5 the second stored tile (not used since) is gone", not file.Exists(dir .. "/" .. storeLog[2] .. ".vtf", "DATA") and not file.Exists(dir .. "/" .. storeLog[2] .. ".vmt", "DATA"), "still there")
	end

	check("5 Cache.Clear(test key)", Cache.Clear(testKey) == true, "false")
	noteInterference("5")
	check("5 after Clear: Count 0, directory gone", Cache.Count() == 0 and not file.IsDir(dir, "DATA") and #(file.Find(dir .. "/*", "DATA") or {}) == 0,
		Cache.Count() .. " isDir " .. tostring(file.IsDir(dir, "DATA")))
end

-- ---------------------------------------------------------------------------------------------------------
-- run
-- ---------------------------------------------------------------------------------------------------------
local ok, err = pcall(function()
	pcall(Gen.Cancel) -- the radar's own request goes away; it asks again by itself
	Cache.Key = function() return testKey end
	Cache.Reset()
	sweepAll()
	installGenStandIns()
	started = true

	seen.Gen, seen.Cache, seen.Capture, seen.DXT1, seen.Settings, seen.VTF = M.Gen, M.Cache, M.Capture, M.DXT1, M.Settings, M.VTF
	seen.Request, seen.Step, seen.Cancel, seen.Key, seen.CacheStore, seen.Has, seen.Material, seen.Reset = Gen.Request, Gen.Step, Gen.Cancel, Cache.Key, Cache.Store, Cache.Has, Cache.Material, Cache.Reset
	seen.StoreEmpty = Cache.StoreEmpty
	mine.Step, mine.Store, mine.StoreEmpty, mine.Key = Gen.Step, Cache.Store, Cache.StoreEmpty, Cache.Key
	mine.Enabled, mine.TileRes, mine.Definition = Settings.Enabled, Settings.TileRes, Settings.Definition
	seen.Render, seen.CompressRows, seen.VTFWrite = Capture.Render, DXT1.CompressRows, VTF.Write
	seen.TileRes, seen.Definition, seen.Enabled = Settings.TileRes, Settings.Definition, Settings.Enabled
	out.map = game.GetMap()
	out.testKey = testKey

	if want(1) then scenario1() end
	if want(2) then scenario2() end
	if want(3) then scenario3() scenario3b() scenario3c() end
	if want(4) then withRetries("4", scenario4) end
	if want(5) then withRetries("5", scenario5) end
end)

if not ok then
	out.raised = tostring(err)
	out.failures[#out.failures + 1] = "the job raised: " .. tostring(err)
end

pcall(restoreAll)

local left = sweepAll()

out.leftover_test_dirs = left
check("6 nothing left under data/grymod/minimap/test_e2e_*", left == 0, left .. " directories")
-- none of the stand-ins is still installed (a field that holds another function than the original was reloaded by its owner meanwhile: fine, not a leak)
local leaked = {}

for key, standIn in pairs(mine) do
	for _, holder in ipairs({Cache, Gen, Settings}) do
		for name, value in pairs(holder) do
			if value == standIn and name ~= "Key_" then
				leaked[#leaked + 1] = name
			end
		end
	end
end

check("6 no stand-in of this job is left installed (Cache.Key, Cache.Store, Gen.Step, Settings.*)", #leaked == 0, table.concat(leaked, ", "))
check("6 no test hook left", removeHookCheck(), "generator hook")

out.summary = (#out.failures == 0) and "ALL PASS" or (#out.failures .. " FAIL")
out.stepErrors = stepStats.errors

return out
