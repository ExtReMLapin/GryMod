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
