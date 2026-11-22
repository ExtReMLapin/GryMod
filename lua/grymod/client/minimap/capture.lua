-- GryMod minimap: module capture. One render of one tile of the map seen from above, as the raw bytes of the picture (BGRA, res * res * 4).
-- Design: docs/superpowers/specs/2026-11-21-minimap-design.md (section Capture). The caller guarantees the PostRender context (render.Capture
-- reads the current render target and answers nil while the menu is open).
--
-- What Render does, in this order:
--   1. checks the tile and the level (nothing is touched when they are wrong);
--   2. hides the entities that are visible, that the map did not create and that are not the local player (the props a server added must
--      not end in the cache: the cache holds the map as shipped). An entity that was already NoDraw is never touched and never shown again;
--   3. installs temporary hooks that return true (halos, effects, players, view model, sky box, world fog: a fog controller would drown the
--      picture seen from 50000 units up);
--   4. pushes the render target of that resolution, clears it to transparent black (0, 0, 0, 0), renders an orthographic view from straight
--      above with render.SetWriteDepthToDestAlpha(false) (the height slab of the level is cut with znear / zfar of a camera very high up: with a
--      low camera the engine ignores the slab), puts the write back to true and reads the bytes BEFORE the render target is popped. The BGRA keeps
--      its alpha: see Capture.IsVoid for the rule that tells the void from the solid pixels;
--   5. whatever happened (an error included): puts the depth-to-alpha write back to true, pops the target if it was pushed, removes the hooks,
--      shows again ONLY the entities this call hid and that are still valid.
-- The picture: top = world +X, right = world -Y (measured), `2 * half` units across.

GryMod = GryMod or {}
GryMod.Minimap = GryMod.Minimap or {}
GryMod.Minimap.Capture = GryMod.Minimap.Capture or {}

local Capture = GryMod.Minimap.Capture

local HOOK_NAME = "GryMod minimap capture"
-- the events whose hook answers true while the capture runs; SetupWorldFog also switches the fog off
local EVENTS = {"PreDrawHalos", "PreDrawEffects", "PrePlayerDraw", "PreDrawViewModel", "PreDrawSkyBox", "SetupWorldFog"}
local FOG_EVENT = "SetupWorldFog"

-- the camera is this high above the top of the level, znear = OFFSET, zfar = OFFSET + height of the slab (measured: with 1000 the slab is ignored)
local CAMERA_OFFSET = 50000
local MIN_RES, MAX_RES = 4, 4096

-- one capture at a time; `state` holds what the clean-up must undo, whatever the capture did
local capturing = false
local state = {hidden = nil, pushed = false, depthAlphaOff = false}
local targets = {}

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isInteger(n)
	return isFinite(n) and n == math.floor(n)
end

local function isResolution(res)
	return isInteger(res) and res >= MIN_RES and res <= MAX_RES and bit.band(res, res - 1) == 0
end

-- Edge of a tile in world units: the Cache module's formula when it is there and gives a usable number, else the same formula here
local function tileUnits(res, ppm)
	local Cache = GryMod.Minimap.Cache

	if Cache and type(Cache.TileUnits) == "function" then
		local ok, units = pcall(Cache.TileUnits, res, ppm)

		if ok and isFinite(units) and units > 0 then
			return units
		end
	end

	local shared = GryMod.RadarShared
	local metres = shared and shared.METRES_PER_UNIT

	if not isFinite(metres) or metres <= 0 then
		return nil
	end

	return res / ppm / metres
end

-- true | false, reason
local function validate(tile, level)
	if type(tile) ~= "table" then
		return false, "bad tile"
	end

	if type(level) ~= "table" then
		return false, "bad level"
	end

	if not isResolution(tile.res) then
		return false, "bad resolution"
	end

	if not isInteger(tile.tx) or not isInteger(tile.ty) then
		return false, "bad tile coordinates"
	end

	if not isFinite(tile.ppm) or tile.ppm <= 0 then
		return false, "bad pixels per metre"
	end

	if type(level.id) ~= "string" or type(tile.level) ~= "string" or tile.level ~= level.id then
		return false, "bad level id"
	end

	if not isFinite(level.zlo) or not isFinite(level.zhi) or level.zlo >= level.zhi then
		return false, "bad level slab"
	end

	return true
end

-- Hides into `list` every entity that is visible, not the map's and not the local player. An entity is put in the list BEFORE it is hidden, so
-- a raise halfway leaves a list that the restoration can use.
local function hideInto(list)
	local all = ents.GetAll()
	local me = LocalPlayer()
	local n = 0

	for i = 1, #all do
		local e = all[i]

		if IsValid(e) and not e:GetNoDraw() and e ~= me and not e:IsWorld() and not e:CreatedByMap() then
			n = n + 1
			list[n] = e
			e:SetNoDraw(true)
		end
	end
end

-- Shows again the entities of the list that are still valid. Each one under its own pcall: one failure must not keep the others hidden.
local function restoreList(list)
	if type(list) ~= "table" then
		return
	end

	for i = 1, #list do
		local e = list[i]

		if IsValid(e) then
			pcall(e.SetNoDraw, e, false)
		end
	end
end

-- The entities the map did not create are hidden; the answer is the list to give to Restore. On an error what was hidden is restored: nil, reason.
function Capture.HideNonMap()
	local list = {}
	local ok, err = pcall(hideInto, list)

	if not ok then
		restoreList(list)

		return nil, tostring(err)
	end

	return list
end

function Capture.Restore(hidden)
	restoreList(hidden)
end

function Capture.IsCapturing()
	return capturing
end

-- THE VOID RULE (measured on gm_funkis): the picture has a real alpha. The target is cleared to (0, 0, 0, 0) and the view renders without writing the
-- depth to the alpha, so what no geometry draws keeps alpha 0 and geometry gets alpha 1 (0 or 1 only). But about 5 % of the pixels that have alpha 0
-- carry a colour (geometry that writes alpha 0), so the alpha alone is NOT a mask. A pixel is void (transparent) when its alpha is 0 AND its colour is
-- (0, 0, 0); every other pixel is solid, a black solid pixel included (its alpha is 1). Pure: no engine call. A missing channel is not void.
function Capture.IsVoid(b, g, r, a)
	return a == 0 and b == 0 and g == 0 and r == 0
end

-- THE BACKGROUND OF THE ENGINE (measured on gm_funkis, d1_canals_01, d2_coast_07, gm_everpine_mall, ep2_outland_02 and gm_boreas, with tests/minimap/void_survey_job.lua):
-- where nothing is drawn, the engine sometimes paints a flat colour with alpha 255 instead of leaving the cleared (0, 0, 0, 0). The colour is the one of the map's sky or fog:
-- black on funkis, canals, coast and everpine, a sky blue on boreas (a tunnel there was drawn inside a solid light-blue wall). The same tile came back void from one render and
-- entirely that colour from the next (seen on funkis: it came and went with where the player stood). The geometry's own alpha is 1, so the alpha 255 is the engine's fill.
--   * the colour of the fill is the same over a whole picture but NOT over time (on boreas it drifted from (123, 161, 201) to (128, 168, 209) within seconds): it is read from each
--     picture (FindBackground), never kept per map;
--   * it is not "every alpha-255 pixel": translucent geometry drawn over the fill keeps alpha 255 with its own colour at its edges (dark greens, near blacks: 0.01 to 0.7 % of the
--     alpha-255 pixels on the maps above, never a whole area). Only the colour of the fill is void; those pixels stay solid;
--   * by the void rule above a pixel of the fill is solid, so a tile of the floor below stored with it was a wall painted over the outside: an invisible thing erasing a visible one.
-- IsBackground is the rule; BackgroundToVoid and IsAllBackground apply it to a whole picture and FindBackground finds the colour (the Gen module decides for which set of tiles).
-- A background (`bg`) is a pixel as a string of four bytes B, G, R, 255 (the format of the pictures); none given means black. Pure: no engine call. The pictures are strings of BGRA pixels; only a whole pixel at a position that is a
-- multiple of 4 counts (the bytes of a colour followed by 255 also appear across two pixels). A pixel that is almost the fill (a channel off by one, an alpha of 254) is geometry and
-- is never touched.
local BLACK_BACKGROUND = "\0\0\0\255"
local sfind, ssub, srep, sbyte, concat = string.find, string.sub, string.rep, string.byte, table.concat
local VOID_PIXEL = "\0\0\0\0"
local VOID_RUNS = {} -- number of pixels (up to 512) -> a string of that many void pixels: the short runs are the most frequent, and the same ones come back

function Capture.IsBackground(b, g, r, a, bg)
	if a ~= 255 then
		return false
	end

	local bb, bgg, br, ba = sbyte(bg or BLACK_BACKGROUND, 1, 4)

	return b == bb and g == bgg and r == br and ba == 255
end

-- the position after the run of pixels of the colour (B, G, R) with alpha 255 that starts at `q` (a multiple of 4, plus 1). The run is read four pixels at a time with string.byte,
-- which makes no string (measured: a whole 1024 x 1024 picture in 2 to 4 ms; comparing chunks made megabytes of garbage and cost ten times more).
local function runEnd(s, q, B, G, R)
	local n = #s

	while q + 15 <= n do
		local b1, g1, r1, a1, b2, g2, r2, a2, b3, g3, r3, a3, b4, g4, r4, a4 = sbyte(s, q, q + 15)

		if a1 + a2 + a3 + a4 ~= 1020 or b1 ~= B or b2 ~= B or b3 ~= B or b4 ~= B or g1 ~= G or g2 ~= G or g3 ~= G or g4 ~= G or r1 ~= R or r2 ~= R or r3 ~= R or r4 ~= R then
			break
		end

		q = q + 16
	end

	-- the last pixels (fewer than four, or the first of the group that was not all the fill), one at a time
	while q + 3 <= n do
		local b, g, r, a = sbyte(s, q, q + 3)

		if a ~= 255 or b ~= B or g ~= G or r ~= R then
			break
		end

		q = q + 4
	end

	return q
end

local function checkPicture(bgra)
	if type(bgra) ~= "string" then
		return false, "the picture is not a string"
	end

	if #bgra % 4 ~= 0 then
		return false, "the length of the picture is not a multiple of 4"
	end

	return true
end

-- the bytes of bg (black when nil) | nil, reason
local function backgroundBytes(bg)
	if bg == nil then
		return 0, 0, 0
	end

	if type(bg) ~= "string" or #bg ~= 4 or sbyte(bg, 4) ~= 255 then
		return nil, "the background is not a pixel of alpha 255 (four bytes B, G, R, 255)"
	end

	return sbyte(bg, 1, 3)
end

-- BackgroundToVoid(bgra, bg) -> the picture with every pixel of the fill (the colour of bg, alpha 255) turned into a void pixel (0, 0, 0, 0), the number of pixels changed | nil, reason.
-- The same string and 0 when there is none (nothing is copied). The scan looks for the alpha byte (255), which is rare in the void and in the geometry (the search for the whole
-- pixel would stop at every zero of the void), and checks the three bytes before it.
function Capture.BackgroundToVoid(bgra, bg)
	local valid, why = checkPicture(bgra)

	if not valid then
		return nil, why
	end

	local B, G, R = backgroundBytes(bg)

	if not B then
		return nil, G
	end

	local pos = sfind(bgra, "\255", 1, true)

	if not pos then
		return bgra, 0
	end

	local parts, n, last, count = {}, 0, 1, 0

	while pos do
		local b, g, r

		if pos % 4 == 0 then
			b, g, r = sbyte(bgra, pos - 3, pos - 1)
		end

		if b == B and g == G and r == R then
			-- the pixel at pos - 3 .. pos is of the fill: follow the run, then replace all of it at once
			local start, stop = pos - 3, runEnd(bgra, pos + 1, B, G, R)

			if start > last then
				n = n + 1
				parts[n] = ssub(bgra, last, start - 1)
			end

			local pixels = (stop - start) / 4
			local void = VOID_RUNS[pixels]

			if not void then
				void = srep(VOID_PIXEL, pixels)

				if pixels <= 512 then
					VOID_RUNS[pixels] = void
				end
			end

			n = n + 1
			parts[n] = void
			count = count + pixels
			last = stop
			pos = sfind(bgra, "\255", stop, true)
		else
			-- a 255 that is not the alpha of a pixel of the fill (geometry, a colour, or a byte of another pixel)
			pos = sfind(bgra, "\255", pos + 1, true)
		end
	end

	if count == 0 then
		return bgra, 0
	end

	if last <= #bgra then
		parts[n + 1] = ssub(bgra, last)
	end

	return concat(parts), count
end

-- IsAllBackground(bgra, bg) -> true when every pixel is the fill, false as soon as one is not | nil, reason (an empty picture is not a picture of anything)
function Capture.IsAllBackground(bgra, bg)
	local valid, why = checkPicture(bgra)

	if not valid then
		return nil, why
	end

	local n = #bgra

	if n == 0 then
		return nil, "the picture is empty"
	end

	local B, G, R = backgroundBytes(bg)

	if not B then
		return nil, G
	end

	return runEnd(bgra, 1, B, G, R) == n + 1
end

-- FindBackground(bgra) -> the fill of the picture as a pixel (B, G, R, 255), or nil when it has none | nil, reason (not a picture).
-- The fill is the colour that most of the alpha-255 pixels have, counted on a sample: the pixels 0, BACKGROUND_STEP, 2 * BACKGROUND_STEP... (a prime step: the sample does not
-- follow the rows). It needs at least BACKGROUND_MIN_SAMPLES samples of that colour and a strict majority of the alpha-255 samples: the edge pixels of translucent geometry are
-- few and each of its own colour, so they never make one, and a picture that has none of the fill (a floor of solid geometry) gives nil. A picture with nil: the caller uses the
-- black, as the first version of the rule did. About 15000 samples for a 1024 x 1024 picture.
Capture.BACKGROUND_STEP = 67
Capture.BACKGROUND_MIN_SAMPLES = 8

function Capture.FindBackground(bgra)
	local valid, why = checkPicture(bgra)

	if not valid then
		return nil, why
	end

	local len = #bgra

	if len == 0 then
		return nil, "the picture is empty"
	end

	local step = Capture.BACKGROUND_STEP * 4
	local counts, total = {}, 0
	local bestKey, bestCount = nil, 0

	for i = 1, len - 3, step do
		local b, g, r, a = sbyte(bgra, i, i + 3)

		if a == 255 then
			local key = b * 65536 + g * 256 + r
			local c = (counts[key] or 0) + 1

			counts[key] = c
			total = total + 1

			if c > bestCount then
				bestKey, bestCount = key, c
			end
		end
	end

	if not bestKey or bestCount < Capture.BACKGROUND_MIN_SAMPLES or bestCount * 2 <= total then
		return nil
	end

	return string.char(math.floor(bestKey / 65536), math.floor(bestKey / 256) % 256, bestKey % 256, 255)
end

local function answerTrue()
	return true
end

local function answerFog()
	render.FogMode(MATERIAL_FOG_NONE)

	return true
end

local function installHooks()
	for i = 1, #EVENTS do
		local event = EVENTS[i]

		hook.Add(event, HOOK_NAME, event == FOG_EVENT and answerFog or answerTrue)
	end
end

local function removeHooks()
	for i = 1, #EVENTS do
		pcall(hook.Remove, EVENTS[i], HOOK_NAME)
	end
end

-- The render target of a resolution, created once (the engine keeps targets by name). Separate depth: a render with a slab needs its own depth buffer.
function Capture.GetRT(res)
	if not isResolution(res) then
		return nil, "bad resolution"
	end

	local rt = targets[res]

	if rt then
		return rt
	end

	rt = GetRenderTargetEx("gry_minimap_rt_" .. res, res, res, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888)

	if not rt then
		return nil, "render target unavailable"
	end

	targets[res] = rt

	return rt
end

-- Forgets the render targets kept in Lua (the engine keeps its own): for the tests that replace the engine's creation.
function Capture.ResetRTCache()
	targets = {}
end

-- The body of a capture, under pcall in Render. The state it needs to be undone is in `state`.
local function run(tile, level)
	local res = tile.res
	local rt, why = Capture.GetRT(res)

	if not rt then
		error(why, 0)
	end

	hideInto(state.hidden)
	installHooks()

	local units = tileUnits(res, tile.ppm)

	if not units then
		error("no scale", 0)
	end

	local half = units / 2

	render.PushRenderTarget(rt)
	state.pushed = true
	-- transparent black: what no geometry draws keeps alpha 0 (the void rule, see the header)
	render.Clear(0, 0, 0, 0, true, true)
	render.SetLightingMode(0)

	-- the depth is not written to the alpha while the view renders: the geometry then gets alpha 1 (0 or 1 only), the void stays 0
	state.depthAlphaOff = true
	render.SetWriteDepthToDestAlpha(false)
	render.RenderView({
		origin = Vector((tile.tx + 0.5) * units, (tile.ty + 0.5) * units, level.zhi + CAMERA_OFFSET),
		angles = Angle(90, 0, 0),
		ortho = {left = -half, right = half, top = -half, bottom = half},
		znear = CAMERA_OFFSET,
		zfar = CAMERA_OFFSET + (level.zhi - level.zlo),
		x = 0, y = 0, w = res, h = res,
		aspect = 1,
		drawviewmodel = false,
		drawhud = false,
		drawmonitors = false,
		dopostprocess = false,
		drawviewer = false,
		bloomtone = false
	})

	state.depthAlphaOff = false
	render.SetWriteDepthToDestAlpha(true)

	-- the bytes are read BEFORE the target is popped: render.Capture reads the current one (and the alpha comes back as drawn)
	local bytes = render.Capture({format = "bgra", x = 0, y = 0, w = res, h = res})

	state.pushed = false
	render.PopRenderTarget()

	if type(bytes) ~= "string" then
		return nil, "capture unavailable"
	end

	if #bytes ~= res * res * 4 then
		return nil, "capture size mismatch"
	end

	return bytes
end

-- What is undone whatever the capture did: the target pushed and not popped, the hooks, the hidden entities.
local function cleanup()
	-- in the order of the normal path: the depth write first, then the target
	if state.depthAlphaOff then
		state.depthAlphaOff = false
		pcall(render.SetWriteDepthToDestAlpha, true)
	end

	if state.pushed then
		state.pushed = false
		pcall(render.PopRenderTarget)
	end

	removeHooks()
	restoreList(state.hidden)
	state.hidden = nil
end

-- One render of the tile (see the header). -> the BGRA bytes | nil, reason. Never raises.
-- A nil with "capture unavailable" is not a failure: the menu is open, the caller tries again at the next frame.
function Capture.Render(tile, level)
	local valid, why = validate(tile, level)

	if not valid then
		return nil, why
	end

	if capturing then
		return nil, "capture already running"
	end

	capturing = true
	state.hidden = {}
	state.pushed = false
	state.depthAlphaOff = false

	local ok, bytes, reason = pcall(run, tile, level)

	pcall(cleanup)
	capturing = false

	if not ok then
		return nil, tostring(bytes)
	end

	return bytes, reason
end
