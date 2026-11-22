-- Real-pixel checks of the minimap's capture module (lua/grymod/client/minimap/capture.lua), to run as a gmod-mcp lua_job in the CLIENT realm (the capture needs
-- a render hook: the job does its work inside a PostRender hook). Phases, chosen by args.phase:
--   "basic" (default): Capture.Render of a real 512 tile around the player. Checks: the length is res * res * 4, the picture is not uniform, the channel order is
--      B, G, R, A (a red clear gives 0, 0, 255), the time of a capture (several runs, the first one creates the render target), IsCapturing is false afterwards, no
--      entity changed its NoDraw state; the alpha is real: the capture has void pixels (alpha 0 AND black) and solid ones, the pixels of alpha 0 that carry a colour
--      are counted as solid (Capture.IsVoid), see out.classes / out.checks. Writes data/grymod/minimap/test_capture_basic.dat and test_capture_classes.dat (void black,
--      solid white, alpha 0 but coloured red) to look at (delete them afterwards).
--   "base": the same tile, kept in _G.GRY_CAPTURE_JOB (bytes and tile) BEFORE a test entity exists.
--   "prop": the same tile again after a prop was spawned on the server (the brief of the test spawns it with lua_exec in the server realm, see below): the capture
--      with the module's masking must be the same as the base (the prop is not in it); the same capture with the prop declared "created by the map" (a stand-in of
--      Entity:CreatedByMap, put back inside a pcall) must differ (the prop is in it). It also reports what the client says about that prop (CreatedByMap).
--      Writes test_capture_masked.dat and test_capture_unmasked.dat.
--   args.size: tile resolution in pixels (512 by default), args.ppm: pixels per metre (3 by default), args.cls / args.model: what to look for in "prop".
--
-- The prop of the "prop" phase (server realm, lua_exec, between "base" and "prop", then remove it). The slab of the job's level goes from 32 units under the player's
-- feet to 128 above (the "base" phase prints it as level.zhi). The origin of the cube is at its bottom, and the picture only shows what is inside the slab seen from
-- above, so the TOP face of the cube is put 5 units under the top of the slab (nothing else of the map can then hide it), at a place of the tile near the player:
--   local p = ents.Create("prop_physics") p:SetModel("models/hunter/blocks/cube8x8x8.mdl")
--   p:SetPos(Vector(X, Y, ZHI - 5 - p:OBBMaxs().z)) p:Spawn() p:SetMoveType(MOVETYPE_NONE)   -- X, Y: inside tile.tx / tile.ty, in the player's PVS
-- Measured on gm_funkis (tile 8959 units, 512 px): masked vs base 5 pixels of 262144 (animation noise), unmasked vs base 316, masked vs unmasked 311.

local Capture = GryMod.Minimap.Capture
local phase = args.phase or "basic"
local res = args.size or 512
local ppm = args.ppm or 3

assert(Capture and Capture.Render, "the capture module is not loaded")

-- ---------------------------------------------------------------------------------------------------------
-- A 24-bit BMP of the BGRA bytes (a picture to look at; data/ only accepts some extensions, so the file is .dat: rename it to .bmp)
-- ---------------------------------------------------------------------------------------------------------
local function le32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function writeBMP(path, bytes, size)
	local rows = {}
	local byte, char = string.byte, string.char

	-- BMP rows go from the bottom to the top
	for row = size - 1, 0, -1 do
		local base = row * size * 4
		local px = {}

		for col = 0, size - 1 do
			local i = base + col * 4 + 1
			local b, g, r = byte(bytes, i, i + 2)

			px[col + 1] = char(b, g, r)
		end

		rows[#rows + 1] = table.concat(px)

		if row % 32 == 0 then
			job:step()
		end
	end

	local body = table.concat(rows)
	local header = "BM" .. le32(54 + #body) .. le32(0) .. le32(54) .. le32(40) .. le32(size) .. le32(size) .. "\1\0\24\0" .. le32(0) .. le32(#body) .. le32(2835) .. le32(2835) .. le32(0) .. le32(0)

	file.CreateDir("grymod")
	file.CreateDir("grymod/minimap")
	file.Write(path, header .. body)
end

-- ---------------------------------------------------------------------------------------------------------
-- The tile: the one around the player (or the one kept by the "base" phase)
-- ---------------------------------------------------------------------------------------------------------
local function playerTile()
	local pos = LocalPlayer():GetPos()
	local T = res / ppm / GryMod.RadarShared.METRES_PER_UNIT
	local tile = {level = "job", tx = math.floor(pos.x / T), ty = math.floor(pos.y / T), res = res, ppm = ppm}
	local level = {id = "job", zlo = pos.z - 32, zhi = pos.z + 128}

	return tile, level, T
end

local tile, level, T
local kept = rawget(_G, "GRY_CAPTURE_JOB")

if phase == "prop" then
	assert(kept, "run the \"base\" phase first")
	tile, level, T = kept.tile, kept.level, kept.T
else
	tile, level, T = playerTile()
end

-- ---------------------------------------------------------------------------------------------------------
-- What is done inside the PostRender hook (one hook call per phase step: a capture is a few milliseconds)
-- ---------------------------------------------------------------------------------------------------------
local out = {phase = phase, map = game.GetMap(), tile = tile, level = level, tileUnits = T}
local finished, failure

local function noDrawSnapshot()
	local s = {}

	for _, e in ipairs(ents.GetAll()) do
		s[#s + 1] = {e = e, nd = e:GetNoDraw()}
	end

	return s
end

local function snapshotDiffers(s)
	local changed = 0

	for i = 1, #s do
		if IsValid(s[i].e) and s[i].e:GetNoDraw() ~= s[i].nd then
			changed = changed + 1
		end
	end

	return changed
end

local function timedRender()
	local t0 = SysTime()
	local bytes, why = Capture.Render(tile, level)

	return bytes, why, (SysTime() - t0) * 1000
end

local function body()
	if phase == "basic" then
		local snap = noDrawSnapshot()
		local times, bytes, why = {}, nil, nil

		for i = 1, 6 do
			local ms
			bytes, why, ms = timedRender()
			times[i] = ms

			if not bytes then
				out.error = tostring(why)

				return
			end
		end

		out.times_ms = times
		out.length = #bytes
		out.expected_length = res * res * 4
		out.isCapturingAfter = Capture.IsCapturing()
		out.noDrawChanged = snapshotDiffers(snap)
		out.hooksLeft = 0

		for _, event in ipairs({"PreDrawHalos", "PreDrawEffects", "PrePlayerDraw", "PreDrawViewModel", "PreDrawSkyBox", "SetupWorldFog"}) do
			local t = hook.GetTable()[event]

			if t and t["GryMod minimap capture"] ~= nil then
				out.hooksLeft = out.hooksLeft + 1
			end
		end

		-- the channel order: a clear to pure red read back through the same target must be B = 0, G = 0, R = 255
		local rt = Capture.GetRT(res)

		render.PushRenderTarget(rt)
		render.Clear(255, 0, 0, 255, true, true)

		local red = render.Capture({format = "bgra", x = 0, y = 0, w = res, h = res})

		render.PopRenderTarget()

		local b, g, r, a = string.byte(red, 1, 4)

		out.redClear = {b = b, g = g, r = r, a = a}

		-- not uniform: the number of distinct colours among about 2700 sampled pixels, and the range of each channel
		local distinct, count = {}, 0
		local lo, hi = {255, 255, 255}, {0, 0, 0}

		for p = 0, res * res - 1, 97 do
			local i = p * 4 + 1
			local bb, gg, rr = string.byte(bytes, i, i + 2)
			local key = bb * 65536 + gg * 256 + rr

			if not distinct[key] then
				distinct[key] = true
				count = count + 1
			end

			if bb < lo[1] then lo[1] = bb end
			if gg < lo[2] then lo[2] = gg end
			if rr < lo[3] then lo[3] = rr end
			if bb > hi[1] then hi[1] = bb end
			if gg > hi[2] then hi[2] = gg end
			if rr > hi[3] then hi[3] = rr end
		end

		out.distinctColours = count
		out.channelMin = lo
		out.channelMax = hi
		out.bytes = bytes
	elseif phase == "base" then
		local bytes, why = timedRender()

		if not bytes then
			out.error = tostring(why)

			return
		end

		_G.GRY_CAPTURE_JOB = {tile = tile, level = level, T = T, bytes = bytes}
		out.kept = #bytes
	else
		-- "prop": masked (the module as it is), then unmasked (the prop answers CreatedByMap = true)
		local cls, model = args.cls or "prop_physics", args.model or "models/hunter/blocks/cube8x8x8.mdl"
		local prop

		for _, e in ipairs(ents.FindByClass(cls)) do
			if string.lower(e:GetModel() or "") == string.lower(model) then
				prop = e
			end
		end

		if not prop then
			out.error = "the test prop is not on the client (spawn it on the server first)"

			return
		end

		out.prop = {index = prop:EntIndex(), createdByMap = prop:CreatedByMap(), mapCreationID = prop:MapCreationID(), noDraw = prop:GetNoDraw(), pos = prop:GetPos()}

		local snap = noDrawSnapshot()
		local masked, why = Capture.Render(tile, level)

		if not masked then
			out.error = tostring(why)

			return
		end

		local meta = FindMetaTable("Entity")
		local original = meta.CreatedByMap
		local unmasked, why2

		meta.CreatedByMap = function(e)
			if e == prop then
				return true
			end

			return original(e)
		end

		local ok, a, b = pcall(Capture.Render, tile, level)

		meta.CreatedByMap = original

		if not ok then
			out.error = "unmasked render raised: " .. tostring(a)

			return
		end

		unmasked, why2 = a, b

		if not unmasked then
			out.error = tostring(why2)

			return
		end

		out.noDrawChanged = snapshotDiffers(snap)
		out.masked, out.unmasked = masked, unmasked
	end
end

hook.Add("PostRender", "gry_capture_job", function()
	hook.Remove("PostRender", "gry_capture_job")

	local ok, err = pcall(body)

	-- never leave the Entity metatable changed
	finished = true

	if not ok then
		failure = tostring(err)
	end
end)

job:wait(function() return finished end, 20)

if failure then
	out.failure = failure

	return out
end

-- ---------------------------------------------------------------------------------------------------------
-- The analysis, outside the render hook (it does not need a render context)
-- ---------------------------------------------------------------------------------------------------------
local function countDiff(a, b)
	if a == b then
		return 0
	end

	local n = 0

	for p = 0, res * res - 1 do
		local i = p * 4 + 1
		local b1, g1, r1 = string.byte(a, i, i + 2)
		local b2, g2, r2 = string.byte(b, i, i + 2)

		if b1 ~= b2 or g1 ~= g2 or r1 ~= r2 then
			n = n + 1
		end

		if p % 20000 == 0 then
			job:step()
		end
	end

	return n
end

-- The void rule (Capture.IsVoid) on a real capture: counts of void pixels (alpha 0 AND black), solid pixels, and among the solid ones those with alpha 0 but a colour
-- (the geometry that writes alpha 0, about 5 % of the alpha 0 pixels measured) and the black ones with alpha > 0. Also a picture of the classification
-- (void black, solid white, alpha 0 but coloured red) to look at.
local function classify(bytes)
	local IsVoid = Capture.IsVoid
	local byte, char = string.byte, string.char
	local stats = {void = 0, solid = 0, alpha0Coloured = 0, alpha0Total = 0, solidBlackAlphaSet = 0, alphaValues = {}}
	local picture = {}

	for p = 0, res * res - 1 do
		local i = p * 4 + 1
		local b, g, r, a = byte(bytes, i, i + 3)

		stats.alphaValues[a] = (stats.alphaValues[a] or 0) + 1

		if a == 0 then
			stats.alpha0Total = stats.alpha0Total + 1
		end

		if IsVoid(b, g, r, a) then
			stats.void = stats.void + 1
			picture[p + 1] = "\0\0\0\255"
		else
			stats.solid = stats.solid + 1

			if a == 0 then
				stats.alpha0Coloured = stats.alpha0Coloured + 1
				picture[p + 1] = "\0\0\255\255"
			else
				if b == 0 and g == 0 and r == 0 then
					stats.solidBlackAlphaSet = stats.solidBlackAlphaSet + 1
				end

				picture[p + 1] = "\255\255\255\255"
			end
		end

		if p % 20000 == 0 then
			job:step()
		end
	end

	stats.picture = table.concat(picture)

	return stats
end

if phase == "basic" then
	local stats = classify(out.bytes)

	out.classes = {
		void = stats.void,
		solid = stats.solid,
		alpha0Total = stats.alpha0Total,
		alpha0ColouredTreatedAsSolid = stats.alpha0Coloured,
		alpha0ColouredShareOfAlpha0 = stats.alpha0Total > 0 and stats.alpha0Coloured / stats.alpha0Total or 0,
		solidBlackWithAlpha = stats.solidBlackAlphaSet,
		alphaValues = stats.alphaValues
	}
	out.checks = {
		hasVoid = stats.void > 0,
		hasSolid = stats.solid > 0,
		-- a pixel of alpha 0 with a colour is solid, never void (IsVoid on the first such pixel is checked in capture_test.lua too)
		alpha0ColouredNotVoid = stats.void + stats.solid == res * res and stats.void == stats.alpha0Total - stats.alpha0Coloured
	}
	writeBMP("grymod/minimap/test_capture_basic.dat", out.bytes, res)
	writeBMP("grymod/minimap/test_capture_classes.dat", stats.picture, res)
	out.bytes = nil
elseif phase == "prop" and out.masked then
	local base = kept.bytes

	out.pixels = res * res
	out.maskedVsBase = countDiff(out.masked, base)
	out.unmaskedVsBase = countDiff(out.unmasked, base)
	out.maskedVsUnmasked = countDiff(out.masked, out.unmasked)
	writeBMP("grymod/minimap/test_capture_masked.dat", out.masked, res)
	writeBMP("grymod/minimap/test_capture_unmasked.dat", out.unmasked, res)
	out.masked, out.unmasked = nil, nil
end

return out
