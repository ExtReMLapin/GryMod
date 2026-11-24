-- The night vision of the suit, SCREEN EFFECT (design: docs/superpowers/plans/2026-11-24-nightvision-implementation.md, section "What V43 is"; the
-- measurements behind every number are in docs/superpowers/plans/2026-11-24-nightvision-render-lab.md). The state (on or off, energy, fade, key, sounds,
-- events) is cl_nightvision.lua's, GryMod.NightVision: this file only READS it (NV.Fade, NV.Mix, NV.IsOn) and draws.
--
-- What the picture is, in the order the frame draws it:
--   1. a soft wide projected light with shadows (ProjectedTexture), BEHIND the player (120 units back, 21 right, 20 up of the eye) and aimed at the
--      point the eye ray hits, through a cookie of our own (a small render target: flat across the width, dimmer towards the floor and the ceiling),
--      and a long grey fog (linear 300 to 4000, density 0.9): both are made by the world's render, so both follow the weight of the picture;
--   2. a faint starlight floor: the world rendered a second time without any lighting (fullbright), added at 3 %. It lifts the darkest parts so that
--      a pitch black room still shows its layout. It costs a second render of the world: gry_nightvision_star 0 turns it off;
--   3. the amplifier, on the picture the engine finished: a gain of the LOCAL kind (a 32 x 18 map of how much each part of the screen is held back,
--      so that a bright patch does not blind the dark parts around it: gry_nightvision_localgain), then ONE gain for the whole screen that follows the
--      light the screen really has (0.27 / the mean luminance, 1.5 to 25, with a half second time constant: it does not read the engine's exposure,
--      it reads the picture, so the HDR auto exposure of the player's game, or none, gives the same picture), a soft glow with scan lines, a grain
--      that is new at every frame, two more soft gains, one S curve on the luminance, and the palette (dark green to pale green to near white,
--      built from the luminance with our own passes: nothing of the original game's files);
--   4. the picture blends with the one the engine drew by the fade squared (NV.Mix).
-- NOT in it, on purpose: no vignette, no field of view limiter, no Sobel, no sharpening, no dependence on HDR.
--
-- NOTHING RUNS WHILE THE NIGHT VISION IS OFF. The four hooks (the screen effect, the world fog, the sky fog, the lamp's placing) exist only from the
-- switch on to the end of the fade out; the lamp (a ProjectedTexture) only while it is wanted. The render targets and materials are made once (Prewarm,
-- at the arrival in a map, with their size in their name: a new screen size makes new ones) and stay. Every hook body is guarded: an error is told
-- once, the hook is removed after five, and the render state (render targets pushed, 2D camera, blend, lighting mode) is put back at each error and
-- at each stop. gry_nightvision_fx 0 keeps everything away; gry_nightvision_light 0 makes no lamp, gry_nightvision_star 0 no second render.
--
-- The hook ids all begin with GryMod_NightVisionFX_ (the state's tests look for GRYNIGHTVISION).

GryMod = GryMod or {}

local NV = GryMod.NightVision

local FX = GryMod.NightVisionFX or {}
GryMod.NightVisionFX = FX

-- A reload: what the previous copy of this file had made is taken away first (its hooks, its lamp).
if FX.Stop then
	FX.Stop()
end

local S = FX.State or {}
FX.State = S
S.res = nil -- (a reload makes the sized resources again: the list of them may have changed)
S.cost = S.cost or {} -- (the measures: FX.State.profile = true records the time each hook body takes, in milliseconds)

-- ---------------------------------------------------------------------------------------------------------
-- The numbers of V43 (the look the owner chose in the lab)
-- ---------------------------------------------------------------------------------------------------------

-- The fog: linear from `start` to `finish`, the colour (grey 5 %), the densest it gets; the sky's fog is the world's scaled by `sky`.
FX.FOG = {start = 300, finish = 4000, color = 13, density = 0.9, sky = 1 / 16}

-- The lamp: a square frustum of 140 degrees (a lamp that casts shadows needs a square one), brightness 4 at full weight, near plane 8, far plane
-- 500 beyond the fog's end (at least 3000); where it hangs relative to the eye (units: forward, right, up) and how far the eye ray looks for what it aims at.
FX.LIGHT = {fov = 140, brightness = 4, nearZ = 8, farZ = math.max(3000, FX.FOG.finish + 500), back = -120, right = 21, up = 20, aim = 2500, hull = 8, margin = 4, ldr = 0.12}

-- The cookie of the lamp (a 128 x 128 render target): the vertical angle `theta0` where the light has fallen to 1 / sqrt 2, never under `floor`;
-- flat across the width until |u| = `flat`, then a cosine down to `edge` at the border.
FX.COOKIE = {size = 128, theta0 = 20, power = 1, floor = 0.3, flat = 0.6, edge = 0.15, tan = 2.747}

-- The automatic gain: the screen luminance it aims at (the mean of min(luma, 0.5) over a 16 x 9 reading, so that a bright window does not count for
-- more than half), its limits, its time constant, where it starts.
FX.GAIN = {target = 0.27, min = 1.5, max = 25, tau = 0.5, start = 3, lumCap = 0.5, maxStep = 0.1}

-- The local gain: map size, strength (alpha), the least a bright part is held to (amin), the time constant of the map.
FX.LOCAL = {w = 32, h = 18, alpha = 0.7, amin = 0.25, tau = 0.4, floor = 0.004}

-- The rest of the amplifier chain.
FX.CHAIN = {star = 0.03, starDiv = 4, pregainMin = 1, glow = 0.8, noise = 0.05, contrast = 1.25, colour = 0.65, ampPasses = 2}

-- ---------------------------------------------------------------------------------------------------------
-- The pure parts
-- ---------------------------------------------------------------------------------------------------------

-- The weight of the picture the engine drew in the blend (the night vision's weight is the fade squared, NV.Mix).
function FX.OriginalAlpha(mix)
	return 1 - math.Clamp(mix, 0, 1)
end

-- The gain the screen luminance asks for.
function FX.GainTarget(lum)
	local g = FX.GAIN

	return math.Clamp(g.target / math.max(lum, 1e-4), g.min, g.max)
end

-- One step of the gain towards what the luminance asks: a time constant of half a second; a frame longer than a tenth of a second counts for a tenth.
function FX.GainStep(gain, lum, dt)
	local g = FX.GAIN

	if not (dt > 0) then
		return gain
	end

	return gain + (FX.GainTarget(lum) - gain) * (1 - math.exp(-math.min(dt, g.maxStep) / g.tau))
end

-- The grey (0 to 255) of the cookie at the pixel (x, y) of a size x size picture. The same formula as the lab's: the vertical angle of the ray of a 140
-- degree square frustum is atan(|v| * tan 70), the light there 1 / (1 + (theta / theta0)^2)^(power / 2), not under the floor; flat across the width
-- until |u| > 0.6, then down to 0.15 at the border.
function FX.CookieValue(x, y, size)
	local c = FX.COOKIE
	local v = (y + 0.5) / size * 2 - 1
	local theta = math.deg(math.atan(math.abs(v) * c.tan))
	local vertical = math.max(c.floor, 1 / (1 + (theta / c.theta0) ^ 2) ^ (c.power / 2))
	local u = math.abs((x + 0.5) / size * 2 - 1)
	local across = 1

	if u > c.flat then
		across = c.edge + (1 - c.edge) * (0.5 + 0.5 * math.cos(math.pi * (u - c.flat) / (1 - c.flat)))
	end

	return math.floor(255 * vertical * across + 0.5)
end

-- The wall guard: how much of the lamp's offset (the length `length` from the eye) is free, from the result of a hull trace along it: no hit, all of it;
-- a hit at `fraction` of the way, that much minus `margin` units; nothing when the wall is right behind the player.
function FX.OffsetScale(hit, fraction, length, margin)
	if not hit or not (length > 0) then
		return 1
	end

	return math.Clamp(fraction - margin / length, 0, 1)
end

-- The scale of the offset in time: it drops at once (the lamp must never stay inside a wall), it comes back in a few hundredths of a second.
FX.SCALE_TAU = 0.07

function FX.ScaleStep(scale, target, dt)
	if target <= scale then
		return target
	end

	if not (dt > 0) then
		return scale
	end

	return scale + (target - scale) * (1 - math.exp(-math.min(dt, 0.1) / FX.SCALE_TAU))
end

-- The fog at a weight of the picture (mix 0 to 1) and a scale (1 for the world, 1/16 for the sky): start, end, grey, densest. The density follows the weight:
-- the fog neither shows before the picture nor stays after it.
function FX.FogParams(mix, scale)
	local f = FX.FOG

	return f.start * scale, f.finish * scale, f.color, f.density * math.Clamp(mix, 0, 1)
end

-- The lamp's brightness at a weight of the picture.
function FX.LightBrightness(mix)
	return FX.LIGHT.brightness * math.Clamp(mix, 0, 1)
end

-- The part of the lamp's brightness used when the game has HDR (all of it) or not (a part of it, see placeLamp). The measures can force a value with
-- FX.State.lampScale.
function FX.LampScale(hdr)
	if S.lampScale ~= nil then
		return S.lampScale
	end

	return hdr and 1 or FX.LIGHT.ldr
end

-- The engine's exposure (the HDR auto exposure: a scale the engine moves from 0.5 to 2 as the picture gets brighter or darker, 1 when there is no HDR) is
-- divided out of the picture before the amplifier, so that the picture is the one of an exposure of 1, the one the look was made with, whatever the player's
-- game does. The screen is in gamma space (about a power of 1/2.2 of the light), so a picture exposed s times is taken back by s^(-1/2.2).
FX.EXPOSURE = {gamma = 2.2, min = 0.25, max = 4, dead = 0.01}

function FX.ExposureFactor(scale)
	local e = FX.EXPOSURE

	if scale == nil then
		return 1
	end

	return math.Clamp(scale, e.min, e.max) ^ (-1 / e.gamma)
end

-- How a factor is drawn over the screen: ("multiply", factor) under 1, ("boost", factor - 1) above 1 (a colour is at most 1, so a boost reaches a factor
-- of 2), nothing within 1 % of 1.
function FX.ExposurePass(factor)
	if math.abs(factor - 1) < FX.EXPOSURE.dead then
		return nil
	end

	if factor < 1 then
		return "multiply", factor
	end

	return "boost", math.min(factor - 1, 1)
end

-- The size of the starlight picture for a screen of w x h and a divisor: rounded up, at least one pixel.
function FX.StarSize(w, h, div)
	return math.max(math.ceil(w / div), 1), math.max(math.ceil(h / div), 1)
end

-- The luminance of a pixel (0 to 1) from its channels (0 to 255).
function FX.Luma(r, g, b)
	return (0.299 * r + 0.587 * g + 0.114 * b) / 255
end

-- The blur of the map (3 x 3 box, the edge cells with the neighbours they have) from `from` into `to`, both w x h, 1-based rows.
local function blur3(from, to, w, h)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local sum, n = 0, 0

			for dy = -1, 1 do
				local yy = y + dy

				if yy >= 0 and yy < h then
					for dx = -1, 1 do
						local xx = x + dx

						if xx >= 0 and xx < w then
							sum = sum + from[yy * w + xx + 1]
							n = n + 1
						end
					end
				end
			end

			to[y * w + x + 1] = sum / n
		end
	end
end

-- The local gain map: from the luminance of each cell (`l`, w x h, 0 to 1) the part of the light each is held to, (median / l)^alpha between amin and 1
-- (a cell darker than the median keeps all its gain, a bright one is held back), blurred twice. Written in A (B and `sorted` are the caller's scratch, the same
-- size). Returns the median. Nothing is made: the caller's tables are reused at every reading.
function FX.LocalGainMap(l, w, h, alpha, amin, A, B, sorted)
	local n = w * h

	for i = 1, n do
		sorted[i] = l[i]
	end

	table.sort(sorted)

	local median = sorted[math.floor(n / 2)]
	local ref = math.max(median, FX.LOCAL.floor)

	for i = 1, n do
		A[i] = math.Clamp((ref / math.max(l[i], 1e-4)) ^ alpha, amin, 1)
	end

	blur3(A, B, w, h)
	blur3(B, A, w, h)

	return median
end

-- ---------------------------------------------------------------------------------------------------------
-- The settings (made by cl_nightvision.lua: only read here)
-- ---------------------------------------------------------------------------------------------------------

local convars = {}

local function flag(name)
	local convar = convars[name]

	if convar == nil then
		convar = GetConVar(name)

		if convar == nil then
			return true
		end

		convars[name] = convar
	end

	return convar:GetBool()
end

function FX.Enabled()
	return flag("gry_nightvision_fx")
end

-- ---------------------------------------------------------------------------------------------------------
-- The render state: what is pushed is counted, so that a failure can put it all back
-- ---------------------------------------------------------------------------------------------------------

local rtDepth = 0
local in2D = false

local function pushRT(rt)
	render.PushRenderTarget(rt)
	rtDepth = rtDepth + 1
end

local function popRT()
	render.PopRenderTarget()
	rtDepth = rtDepth - 1
end

local function start2D()
	cam.Start2D()
	in2D = true
end

local function end2D()
	cam.End2D()
	in2D = false
end

function FX.RenderTargetDepth()
	return rtDepth
end

-- Puts the render state back after a failure (or at a stop): every render target this file pushed popped, its 2D camera ended, the blend and the
-- lighting mode ordinary. Each under its own pcall: one that fails must not keep the others from running.
function FX.Recover()
	while rtDepth > 0 do
		pcall(render.PopRenderTarget)
		rtDepth = rtDepth - 1
	end

	if in2D then
		pcall(cam.End2D)
		in2D = false
	end

	pcall(render.OverrideBlend, false)
	pcall(render.SetLightingMode, 0)

	S.inStar = false
end

-- ---------------------------------------------------------------------------------------------------------
-- The resources: made once for a screen size
-- ---------------------------------------------------------------------------------------------------------

local R = S.res -- the resources of the screen size now

local function targetOf(name, w, h, flags)
	return GetRenderTargetEx(name, w, h, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_NONE, flags or 0, 0, IMAGE_FORMAT_RGBA8888)
end

local function materialOf(name, texture, extra)
	local t = {["$basetexture"] = texture, ["$ignorez"] = 1, ["$vertexcolor"] = 1, ["$color2"] = "[1 1 1]"}

	for k, v in pairs(extra or {}) do
		t[k] = v
	end

	return CreateMaterial(name, "UnlitGeneric", t)
end

-- The three textures that do not change with the screen: the noise (a 256 x 256 tile of sparse scintillation, random^3, laid one texel to a pixel and
-- moved at random at each frame), the scan pattern (four rows to a period: 1, 0.625, 0.25, 0.625, point sampled: flag 1) and the lamp's cookie (flags 4 + 8:
-- clamped on both axes, the lamp's frustum edge must not wrap around). They are made once and DRAWN once, but a render target does not keep what was
-- drawn in it for ever (measured: what was drawn at the loading screen was black afterwards; the same happens when the device is reset), so the drawing
-- is done after the first seconds of play, in small steps (FX.PaintStatic), and checked again (FX.StaticLost).
local function staticTargets()
	FX.NoiseTarget = FX.NoiseTarget or targetOf("gry_nv_noise", 256, 256)
	FX.ScanTarget = FX.ScanTarget or targetOf("gry_nv_scan", 4, 4, 1)
	FX.CookieTarget = FX.CookieTarget or targetOf("gry_nv_cookie", FX.COOKIE.size, FX.COOKIE.size, 12)
end

local SCAN_ROWS = {1.0, 0.625, 0.25, 0.625}

-- rows from y0 to y1 - 1 of the noise (the first call clears it)
local function paintNoise(y0, y1)
	pushRT(FX.NoiseTarget)

	if y0 == 0 then
		render.Clear(0, 0, 0, 255, true, true)
	end

	start2D()

	for y = y0, y1 - 1 do
		for x = 0, 255 do
			local g = math.floor(math.random() ^ 3 * 255)

			surface.SetDrawColor(g, g, g, 255)
			surface.DrawRect(x, y, 1, 1)
		end
	end

	end2D()
	popRT()
end

local function paintScan()
	pushRT(FX.ScanTarget)
	start2D()

	for y = 0, 3 do
		local g = math.floor(SCAN_ROWS[y + 1] * 255)

		surface.SetDrawColor(g, g, g, 255)
		surface.DrawRect(0, y, 4, 1)
	end

	end2D()
	popRT()
end

-- One rectangle for each run of pixels of the same grey in a row (the middle of a row is one rectangle, the sides are made of the taper's pixels).
local function paintCookie()
	local n = FX.COOKIE.size

	pushRT(FX.CookieTarget)
	render.Clear(0, 0, 0, 255, true, true)
	start2D()
	draw.NoTexture()

	for y = 0, n - 1 do
		local runStart, runGrey = 0, FX.CookieValue(0, y, n)

		for x = 1, n do
			local g = x < n and FX.CookieValue(x, y, n) or -1

			if g ~= runGrey then
				surface.SetDrawColor(runGrey, runGrey, runGrey, 255)
				surface.DrawRect(runStart, y, x - runStart, 1)
				runStart, runGrey = x, g
			end
		end
	end

	end2D()
	popRT()
end

local NOISE_ROWS_PER_STEP = 16

-- Draws the static textures; with a budget (milliseconds) it stops when the budget is used and goes on at the next call, without one it does everything.
-- Returns true when they are all drawn.
function FX.PaintStatic(budgetMs)
	staticTargets()

	local prep = S.prep

	if prep == nil or prep.done then
		prep = {stage = 1, row = 0, done = false}
		S.prep = prep
	end

	local started = SysTime()

	while not prep.done do
		if prep.stage == 1 then
			paintNoise(prep.row, prep.row + NOISE_ROWS_PER_STEP)
			prep.row = prep.row + NOISE_ROWS_PER_STEP

			if prep.row >= 256 then
				prep.stage = 2
			end
		elseif prep.stage == 2 then
			paintScan()
			prep.stage = 3
		else
			paintCookie()
			prep.done = true
		end

		if budgetMs ~= nil and (SysTime() - started) * 1000 >= budgetMs then
			break
		end
	end

	S.painted = prep.done

	return prep.done
end

-- Whether the static textures are drawn (at least once).
function FX.StaticPainted()
	return S.painted == true
end

-- Whether what was drawn in the static textures is gone (the scan pattern's first pixel is white when it is there). One read of a 4 x 4 target.
function FX.StaticLost()
	if FX.ScanTarget == nil then
		return true
	end

	pushRT(FX.ScanTarget)
	render.CapturePixels()

	local r = render.ReadPixel(0, 0)

	popRT()

	return r < 128
end

-- Everything the effect draws with, for a screen of w x h. The names carry the size (a render target keeps the size it was made with).
local function build(w, h)
	local tag = w .. "x" .. h
	local r = {w = w, h = h, count = 0}

	local function rt(name, tw, th)
		r.count = r.count + 1

		return targetOf("gry_nv_" .. name .. "_" .. tag, tw, th)
	end

	local function mat(name, texture, extra)
		r.count = r.count + 1

		return materialOf("gry_nv_" .. name .. "_" .. tag, texture, extra)
	end

	r.matScreen = CreateMaterial("gry_nv_screen", "UnlitGeneric", {["$basetexture"] = "_rt_FullFrameFB", ["$ignorez"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 0, ["$color2"] = "[1 1 1]"})

	r.rtQ = rt("q", math.max(math.floor(w / 4), 1), math.max(math.floor(h / 4), 1))
	r.matQ = mat("qm", "gry_nv_q_" .. tag)

	-- the three full size targets (the glow's picture uses the first, which is free until the S curve): the luminance L and L^2 of the S curve and of the palette,
	-- and the picture the engine drew (below)
	r.rtL1, r.rtL2 = rt("l1", w, h), rt("l2", w, h)
	r.matL1, r.matL2 = mat("l1m", "gry_nv_l1_" .. tag), mat("l2m", "gry_nv_l2_" .. tag)

	-- a flat white quad (the exposure pass multiplies or boosts the screen by its colour)
	r.matFlat = materialOf("gry_nv_flat_" .. tag, "color/white")
	r.count = r.count + 1

	-- the picture the engine drew, kept while the night vision fades in or out
	r.rtOrig = rt("orig", w, h)
	r.matOrig = mat("origm", "gry_nv_orig_" .. tag, {["$translucent"] = 1, ["$alpha"] = 1})

	-- the readings: the screen luminance (16 x 9), the local gain (32 x 18) and its map
	r.rtLum = rt("lum", 16, 9)
	r.rtLoc = rt("loc", FX.LOCAL.w, FX.LOCAL.h)
	r.rtMap = rt("map", FX.LOCAL.w, FX.LOCAL.h)
	r.matMap = mat("mapm", "gry_nv_map_" .. tag)

	-- the starlight's picture (the world without lighting) is made when it is first wanted, by starTarget, at its own size
	r.stars = {}

	staticTargets()
	r.rtNoise = FX.NoiseTarget
	r.matNoise = CreateMaterial("gry_nv_noisemat", "UnlitGeneric", {["$basetexture"] = "gry_nv_noise", ["$ignorez"] = 1, ["$vertexcolor"] = 1, ["$color2"] = "[1 1 1]"})

	r.rtScan = FX.ScanTarget
	r.matScan = mat("scanm", "gry_nv_scan")
	local m = Matrix()
	m:SetScale(Vector(w / 4, h / 4, 1))
	r.matScan:SetMatrix("$basetexturetransform", m)

	r.rtCookie = FX.CookieTarget

	-- scratch objects the frame reuses
	r.vec = Vector(0, 0, 0)
	r.noiseMatrix = Matrix()
	r.noiseScale = Vector(w / 256, h / 256, 1)
	r.noiseShift = Vector(0, 0, 0)
	r.colour = {
		["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_brightness"] = 0,
		["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
	}
	r.grey = {
		["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_brightness"] = 0,
		["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
	}
	r.colour["$pp_colour_contrast"] = FX.CHAIN.contrast
	r.colour["$pp_colour_colour"] = FX.CHAIN.colour

	return r
end

-- Makes the resources for the screen size now if they are not there, and draws the static textures if they are not drawn (or are lost). Called at the
-- first switch on and by the tests; safe to call at any time: it does nothing when everything is made. The screen sized targets alone are made by FX.Build.
function FX.Prewarm()
	local started = SysTime()

	FX.Build()

	if not S.painted or FX.StaticLost() then
		FX.PaintStatic()
	end

	FX.LastPrewarmMs = (SysTime() - started) * 1000

	return S.res
end

-- The screen sized targets and materials for the screen now (none are drawn in).
function FX.Build()
	local w, h = ScrW(), ScrH()

	if S.res and S.res.w == w and S.res.h == h then
		return S.res
	end

	local started = SysTime()

	S.res = build(w, h)
	R = S.res
	FX.LastBuildMs = (SysTime() - started) * 1000

	return S.res
end

function FX.ResourceCount()
	return S.res and S.res.count or 0
end

-- ---------------------------------------------------------------------------------------------------------
-- The drawing helpers (the lab's `fx`)
-- ---------------------------------------------------------------------------------------------------------

local BLEND_DST_COLOR, BLEND_ZERO, BLEND_ONE, BLEND_ADD = BLEND_DST_COLOR, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD

-- A full screen quad of `mat` (its colour r, g, b) with the blend (src, dst, func).
local function drawmat(mat, r, g, b, srcB, dstB, func)
	local v = R.vec

	v.x, v.y, v.z = r, g, b
	mat:SetVector("$color2", v)
	render.SetMaterial(mat)
	render.OverrideBlend(true, srcB, dstB, func or BLEND_ADD)
	render.DrawScreenQuad()
	render.OverrideBlend(false)
end

-- Draws the screen into the render target `rt` (at its size, bilinear). The engine's copy of the screen is made BEFORE the target is pushed: made
-- with another target current, it would copy that one.
local function screenToTarget(rt)
	render.UpdateScreenEffectTexture()

	local m = R.matScreen
	local v = R.vec

	m:SetTexture("$basetexture", render.GetScreenEffectTexture())
	v.x, v.y, v.z = 1, 1, 1
	m:SetVector("$color2", v)
	pushRT(rt)
	render.SetMaterial(m)
	render.DrawScreenQuad()
	popRT()
end

-- One soft gain pass: out = s + d * (1 - s) with s = c * d: a gain of 1 + c near black, saturating smoothly to 1.
local function gainpass(c)
	render.UpdateScreenEffectTexture()

	local m = R.matScreen
	local v = R.vec

	m:SetTexture("$basetexture", render.GetScreenEffectTexture())
	v.x, v.y, v.z = c, c, c
	m:SetVector("$color2", v)
	render.SetMaterial(m)
	render.OverrideBlend(true, BLEND_ONE, BLEND_ONE_MINUS_SRC_COLOR, BLEND_ADD)
	render.DrawScreenQuad()
	render.OverrideBlend(false)
end

local function desaturate()
	DrawColorModify(R.grey)
end

-- Additive scintillation, a random offset at each frame (the matrix and its vectors are reused).
local function grain(amp)
	local m, shift = R.noiseMatrix, R.noiseShift

	shift.x, shift.y = math.random(), math.random()
	m:SetScale(R.noiseScale)
	m:SetTranslation(shift)
	R.matNoise:SetMatrix("$basetexturetransform", m)
	drawmat(R.matNoise, amp, amp, amp, BLEND_ONE, BLEND_ONE)
end

-- ---------------------------------------------------------------------------------------------------------
-- The readings of the screen: the luminance and the local gain map (each every third frame, on frames of their own)
-- ---------------------------------------------------------------------------------------------------------

local LW, LH = FX.LOCAL.w, FX.LOCAL.h
local LN = LW * LH
local lumCells = {}
local sortScratch, blurScratch, mapTarget, mapCurrent = {}, {}, {}, {}

for i = 1, LN do
	lumCells[i], sortScratch[i], blurScratch[i], mapTarget[i], mapCurrent[i] = 0, 0, 0, 1, 1
end

-- The mean of min(luma, 0.5) over a 16 x 9 reading of the screen.
local function readLuminance()
	local g = FX.GAIN

	screenToTarget(R.rtQ)

	pushRT(R.rtLum)
	R.matQ:SetVector("$color2", R.vec)
	render.SetMaterial(R.matQ)
	render.DrawScreenQuad()
	render.CapturePixels()

	local sum = 0

	for y = 0, 8 do
		for x = 0, 15 do
			local r, gr, b = render.ReadPixel(x, y)

			sum = sum + math.min(FX.Luma(r, gr, b), g.lumCap)
		end
	end

	popRT()

	return sum / 144
end

-- The local gain's reading: the luminance of 32 x 18 cells into the map's target.
local function readLocalGain()
	local c = FX.LOCAL

	screenToTarget(R.rtQ)

	pushRT(R.rtLoc)
	R.matQ:SetVector("$color2", R.vec)
	render.SetMaterial(R.matQ)
	render.DrawScreenQuad()
	render.CapturePixels()

	for y = 0, LH - 1 do
		for x = 0, LW - 1 do
			local r, g, b = render.ReadPixel(x, y)

			lumCells[y * LW + x + 1] = math.min(FX.Luma(r, g, b), 1)
		end
	end

	popRT()

	S.median = FX.LocalGainMap(lumCells, LW, LH, c.alpha, c.amin, mapTarget, blurScratch, sortScratch)
end

-- The maps of the local gain (the one aimed at and the one drawn), for the tests and the measures.
function FX.LocalMaps()
	return mapTarget, mapCurrent
end

-- The local gain, drawn: the target map read on this frame's turn (every third frame), the current map moved towards it, drawn into a small target
-- and multiplied bilinearly over the screen.
local function localGain(dt)
	if S.frame % 3 == 0 or not S.haveMap then
		readLocalGain()

		if not S.haveMap then
			for i = 1, LN do
				mapCurrent[i] = mapTarget[i]
			end

			S.haveMap = true
		end
	end

	local k = 1 - math.exp(-math.min(dt, 0.1) / FX.LOCAL.tau)

	pushRT(R.rtMap)
	start2D()
	draw.NoTexture()

	for i = 1, LN do
		local cur = mapCurrent[i]

		cur = cur + (mapTarget[i] - cur) * k
		mapCurrent[i] = cur

		local g = math.floor(cur * 255 + 0.5)

		surface.SetDrawColor(g, g, g, 255)
		surface.DrawRect((i - 1) % LW, math.floor((i - 1) / LW), 1, 1)
	end

	end2D()
	popRT()

	drawmat(R.matMap, 1, 1, 1, BLEND_DST_COLOR, BLEND_ZERO)
end

-- ---------------------------------------------------------------------------------------------------------
-- The starlight: the world once more, fullbright, added at 3 %
-- ---------------------------------------------------------------------------------------------------------

local viewTable = {origin = Vector(), angles = Angle(), fov = 90, x = 0, y = 0, w = 0, h = 0, drawviewmodel = false, drawmonitors = false, dopostprocess = false, drawhud = false}

-- The starlight's render target: the world is drawn into a picture 1/div of the screen's width and height and stretched (bilinear) when it is added. It is a faint
-- floor (3 %), and what it shows is the layout of the place without any lighting, which needs no detail. One target for each divisor asked for (the game asks for
-- FX.CHAIN.starDiv, the measures for others), with a depth buffer of its own.
local function starTarget(div)
	local star = R.stars[div]

	if star == nil then
		local w, h = FX.StarSize(R.w, R.h, div)
		local name = "gry_nv_star_" .. R.w .. "x" .. R.h .. "_" .. div

		star = {
			w = w, h = h,
			rt = GetRenderTargetEx(name, w, h, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE, 0, 0, IMAGE_FORMAT_RGBA8888),
			mat = materialOf(name .. "_m", name)
		}
		R.stars[div] = star
		R.count = R.count + 2
	end

	return star
end

local function starlight(weight)
	local view = render.GetViewSetup()
	local star = starTarget(S.starDiv or FX.CHAIN.starDiv)

	S.inStar = true
	viewTable.origin, viewTable.angles, viewTable.fov = view.origin, view.angles, view.fov
	viewTable.w, viewTable.h = star.w, star.h

	pushRT(star.rt)
	render.SetLightingMode(1)

	local ok, err = pcall(render.RenderView, viewTable)

	render.SetLightingMode(0)
	popRT()
	S.inStar = false

	if not ok then
		error(err, 0)
	end

	drawmat(star.mat, weight, weight, weight, BLEND_ONE, BLEND_ONE)
end

-- ---------------------------------------------------------------------------------------------------------
-- The chain
-- ---------------------------------------------------------------------------------------------------------

local function capturing()
	local minimap = GryMod.Minimap

	return minimap ~= nil and minimap.Capture ~= nil and minimap.Capture.IsCapturing() == true
end

-- the test's way to make the screen hook fail (the failure rules are tested without a render)
local screenFault = false

function FX.SetScreenFault(on)
	screenFault = on == true
end

local function chain(mix, dt)
	local c = FX.CHAIN
	local stage = S.stage or 99 -- (the measures stop the chain after a stage: FX.State.stage = 1 .. 8, nil in play)

	S.frame = S.frame + 1

	-- the static textures can be lost (a reset of the device): looked at every two seconds or so
	if S.frame % 120 == 0 and FX.StaticLost() then
		FX.PaintStatic()
	end

	-- 0. the picture the engine drew, for the fade
	if mix < 1 then
		render.CopyRenderTargetToTexture(R.rtOrig)
	end

	-- 1. the starlight floor
	if c.star > 0 and flag("gry_nightvision_star") then
		starlight(c.star)
	end

	-- the engine's exposure divided out (HDR only: without HDR the scale is 1)
	if not S.exposureOff and render.GetHDREnabled() then
		local v = render.GetToneMappingScaleLinear()
		local kind, amount = FX.ExposurePass(FX.ExposureFactor(v and v.x))

		S.exposure = v and v.x

		if kind == "multiply" then
			drawmat(R.matFlat, amount, amount, amount, BLEND_DST_COLOR, BLEND_ZERO)
		elseif kind == "boost" then
			drawmat(R.matFlat, amount, amount, amount, BLEND_DST_COLOR, BLEND_ONE)
		end
	end

	if stage <= 1 then return end

	-- 2. the local gain, then the automatic gain on what is left
	if flag("gry_nightvision_localgain") then
		localGain(dt)
	end

	if stage <= 2 then return end

	if S.lum == nil or S.frame % 3 == 1 then
		S.lum = readLuminance()
	end

	S.gain = FX.GainStep(S.gain, S.lum, dt)
	S.gain = S.gainHold or S.gain -- (the measures hold the gain: FX.State.gainHold = a number, nil in play)
	gainpass(S.gain - 1)

	if stage <= 3 then return end

	-- 3. the glow: the screen at quarter size, bilinear, times the scan lines, added
	screenToTarget(R.rtQ)

	pushRT(R.rtL1)
	R.vec.x, R.vec.y, R.vec.z = 1, 1, 1
	R.matQ:SetVector("$color2", R.vec)
	render.SetMaterial(R.matQ)
	render.DrawScreenQuad()
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLEND_ADD)
	render.SetMaterial(R.matScan)
	render.DrawScreenQuad()
	render.OverrideBlend(false)
	popRT()

	drawmat(R.matL1, c.glow, c.glow, c.glow, BLEND_ONE, BLEND_ONE)

	if stage <= 4 then return end

	-- 4. the grain, then two more soft gains
	grain(c.noise)

	for _ = 1, c.ampPasses do
		gainpass(1)
	end

	if stage <= 5 then return end

	-- 5. the S curve on the luminance: smoothstep 3L^2 - 2L^3 = L^2 + 2 (L^2 - L^3). The screen is made L^3, then L^2 - L^3, which is copied into the first
	-- target (L is not needed any more) and added twice with L^2
	desaturate()
	render.CopyRenderTargetToTexture(R.rtL1)
	drawmat(R.matL1, 1, 1, 1, BLEND_DST_COLOR, BLEND_ZERO)
	render.CopyRenderTargetToTexture(R.rtL2)
	drawmat(R.matL1, 1, 1, 1, BLEND_DST_COLOR, BLEND_ZERO)
	drawmat(R.matL2, 1, 1, 1, BLEND_ONE, BLEND_ONE, BLENDFUNC_SUBTRACT)
	render.CopyRenderTargetToTexture(R.rtL1)
	drawmat(R.matL2, 1, 1, 1, BLEND_ONE, BLEND_ONE)
	drawmat(R.matL1, 1, 1, 1, BLEND_ONE, BLEND_ONE)

	if stage <= 6 then return end

	-- 6. the palette: luminance to green, R = 0.68 L + 0.32 L^3, G = 1.7 L - 0.7 L^2, B = L^3. The screen is made L^3 (from L and L^2, two copies), turned to
	-- (0.32 L^3, 0, L^3) by a multiply, and the other terms are added to it
	desaturate()
	render.CopyRenderTargetToTexture(R.rtL1)
	drawmat(R.matL1, 1, 1, 1, BLEND_DST_COLOR, BLEND_ZERO)
	render.CopyRenderTargetToTexture(R.rtL2)
	drawmat(R.matL1, 1, 1, 1, BLEND_DST_COLOR, BLEND_ZERO)
	drawmat(R.matFlat, 0.32, 0, 1, BLEND_DST_COLOR, BLEND_ZERO)
	drawmat(R.matL1, 0.68, 1.7, 0, BLEND_ONE, BLEND_ONE)
	drawmat(R.matL2, 0, 0.7, 0, BLEND_ONE, BLEND_ONE, BLENDFUNC_REVERSE_SUBTRACT)

	if stage <= 7 then return end

	-- 7. the contrast around 0.5 and 35 % back to grey
	DrawColorModify(R.colour)

	if stage <= 8 then return end

	-- 8. the blend with the picture the engine drew
	if mix < 1 then
		R.matOrig:SetFloat("$alpha", FX.OriginalAlpha(mix))
		render.SetMaterial(R.matOrig)
		render.DrawScreenQuad()
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The hooks
-- ---------------------------------------------------------------------------------------------------------

local ID = {
	screen = "GryMod_NightVisionFX_Screen",
	fog = "GryMod_NightVisionFX_Fog",
	skyFog = "GryMod_NightVisionFX_SkyFog",
	light = "GryMod_NightVisionFX_Light"
}

local EVENT = {screen = "RenderScreenspaceEffects", fog = "SetupWorldFog", skyFog = "SetupSkyboxFog", light = "PreRender"}

-- A hook body that fails: the render state is put back, the first error is told, and the hook is removed after five (the main hook takes the whole
-- effect with it: a picture without its screen pass would only be a lamp and a fog).
local MAX_ERRORS = 5

local function guarded(key, fn)
	local errors = 0

	hook.Add(EVENT[key], ID[key], function(...)
		local started = S.profile and SysTime()
		local memory = started and collectgarbage("count")
		local ok, result = pcall(fn, ...)

		if started then
			local cost = S.cost[key]

			if cost == nil then
				cost = {last = 0, max = 0, sum = 0, n = 0, kb = 0}
				S.cost[key] = cost
			end

			cost.last = (SysTime() - started) * 1000
			cost.max, cost.sum, cost.n = math.max(cost.max, cost.last), cost.sum + cost.last, cost.n + 1
			cost.kb = cost.kb + (collectgarbage("count") - memory) -- (meaningful with the collector stopped)
		end

		if ok then
			return result
		end

		errors = errors + 1
		FX.Recover()

		if errors == 1 then
			ErrorNoHalt("[GryMod] night vision (" .. key .. "): " .. tostring(result) .. "\n")
		end

		if errors >= MAX_ERRORS then
			hook.Remove(EVENT[key], ID[key])
			ErrorNoHalt("[GryMod] night vision (" .. key .. "): hook removed after " .. MAX_ERRORS .. " errors\n")

			if key == "screen" then
				FX.Stop()
			end
		end
	end)
end

-- Once per frame: the weight of the picture, nothing else; the others read it.
local function screenBody()
	if screenFault then
		error("screen fault (test)")
	end

	if FX.Check() then
		return
	end

	if S.inStar or capturing() then
		return
	end

	local mix = NV.Mix()

	if not (mix > 0) then
		return
	end

	local w, h = ScrW(), ScrH()

	if R == nil or R.w ~= w or R.h ~= h then
		FX.Prewarm()
	end

	chain(mix, FrameTime())
end

local function fogBody(scale)
	if S.inStar or capturing() then
		return
	end

	local start, finish, grey, density = FX.FogParams(NV.Mix(), scale)

	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(start)
	render.FogEnd(finish)
	render.FogColor(grey, grey, grey)
	render.FogMaxDensity(density)

	return true
end

local function worldFogBody()
	return fogBody(1)
end

local function skyFogBody()
	return fogBody(FX.FOG.sky)
end

-- ---------------------------------------------------------------------------------------------------------
-- The lamp
-- ---------------------------------------------------------------------------------------------------------

local lampTrace = {mask = MASK_SOLID_BRUSHONLY, output = {}}
local lampHull = {mask = MASK_SOLID_BRUSHONLY, output = {}}
local lampColor = Color(255, 255, 255)
local hullMin, hullMax

local function lampSize()
	if hullMin == nil then
		local h = FX.LIGHT.hull

		hullMin, hullMax = Vector(-h, -h, -h), Vector(h, h, h)
	end
end

-- The lamp (a valid ProjectedTexture) or nil.
function FX.Lamp()
	local lamp = S.lamp

	if lamp ~= nil and lamp:IsValid() then
		return lamp
	end

	return nil
end

local function removeLamp()
	local lamp = S.lamp

	S.lamp = nil

	if lamp ~= nil and lamp:IsValid() then
		lamp:Remove()
	end
end

local function makeLamp()
	local l = FX.LIGHT
	local lamp = ProjectedTexture()

	lamp:SetTexture(R.rtCookie)
	lamp:SetFOV(l.fov)
	lamp:SetNearZ(l.nearZ)
	lamp:SetFarZ(l.farZ)
	lamp:SetBrightness(0)
	lamp:SetEnableShadows(true)
	lamp:SetColor(lampColor)
	lamp:Update()

	S.lamp = lamp
	S.scale = 0
end

-- Places the lamp: behind the player, to the right and up, as far as the walls allow (a hull trace along the offset; the lamp never ends in the brush),
-- aimed at the point the eye ray hits. Brightness follows the weight of the picture, and is the lamp's `ldr` part of it when the game has no HDR (measured: the same
-- lamp lights the hall 8 times stronger in LDR, where nothing is exposed; at 0.12 the hall of the lab's scene D has the lab's numbers).
local function placeLamp(lamp, mix, dt)
	local l = FX.LIGHT
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return
	end

	lampSize()

	local eye = ply:EyePos()
	local ang = ply:EyeAngles()
	local forward = ang:Forward()
	local offset = forward * l.back + ang:Right() * l.right + ang:Up() * l.up
	local length = offset:Length()

	lampHull.start, lampHull.endpos, lampHull.mins, lampHull.maxs = eye, eye + offset, hullMin, hullMax

	local hull = util.TraceHull(lampHull)
	local target = FX.OffsetScale(hull.Hit, hull.Fraction, length, l.margin)

	S.scale = FX.ScaleStep(S.scale or target, target, dt)

	local pos = eye + offset * S.scale

	lampTrace.start, lampTrace.endpos = eye, eye + forward * l.aim

	local aim = util.TraceLine(lampTrace).HitPos

	if aim:DistToSqr(pos) < 100 then
		aim = eye + forward * l.aim
	end

	lamp:SetPos(pos)
	lamp:SetAngles((aim - pos):Angle())
	lamp:SetBrightness(FX.LightBrightness(mix) * FX.LampScale(render.GetHDREnabled()))
	lamp:Update()
end

-- Once per frame, before the world is drawn (the hook PreRender; also called by the tests): makes the lamp when it is wanted, takes it away when it is
-- not (the setting turned off, the effect stopped), and places it.
function FX.UpdateLight()
	local wanted = S.running and flag("gry_nightvision_light") and R ~= nil

	if not wanted then
		removeLamp()

		return
	end

	if FX.Lamp() == nil then
		makeLamp()
	end

	placeLamp(S.lamp, NV.Mix(), FrameTime())
end

-- ---------------------------------------------------------------------------------------------------------
-- Start, stop, and what keeps them in step with the night vision
-- ---------------------------------------------------------------------------------------------------------

-- THE MINIMAP CAPTURE (minimap/capture.lua) renders a tile of the map from above, in PostRender, and a ProjectedTexture lights every render: a tile made while the
-- night vision is on would carry the lamp's light into the cache. The capture's own hooks come too late for a light (they fire inside the render), so while the
-- effect runs Capture.Render and Capture.RenderTo are wrapped: the lamp's brightness goes to 0 for the capture and comes back after it (Update takes effect at once).
-- The wrappers are put in at Start and taken out at Stop (not if something else replaced the function meanwhile). The screen hook and the fogs already stay
-- out while Capture.IsCapturing(), and the starlight pass is part of the screen hook.
local CAPTURE_FUNCTIONS = {"Render", "RenderTo"}

local function wrapCapture()
	local capture = GryMod.Minimap and GryMod.Minimap.Capture

	if capture == nil or S.captureWrapped ~= nil then
		return
	end

	S.captureOriginal, S.captureWrapped = {}, {}

	for _, name in ipairs(CAPTURE_FUNCTIONS) do
		local original = capture[name]

		if isfunction(original) then
			local function wrapper(...)
				local lamp = FX.Lamp()
				local brightness = lamp ~= nil and lamp:GetBrightness() or 0

				if lamp ~= nil then
					lamp:SetBrightness(0)
					lamp:Update()
				end

				local ok, a, b = pcall(original, ...)

				if lamp ~= nil and lamp:IsValid() then
					lamp:SetBrightness(brightness)
					lamp:Update()
				end

				if not ok then
					error(a, 0)
				end

				return a, b
			end

			S.captureOriginal[name], S.captureWrapped[name] = original, wrapper
			capture[name] = wrapper
		end
	end
end

local function unwrapCapture()
	local capture = GryMod.Minimap and GryMod.Minimap.Capture

	if S.captureWrapped == nil then
		return
	end

	for name, wrapper in pairs(S.captureWrapped) do
		if capture ~= nil and capture[name] == wrapper then
			capture[name] = S.captureOriginal[name]
		end
	end

	S.captureOriginal, S.captureWrapped = nil, nil
end

function FX.IsRunning()
	return S.running == true
end

-- The effect is wanted while the setting allows it and the picture is up or rising: the night vision is on, or its fade is not over.
local function wanted()
	return flag("gry_nightvision_fx") and NV ~= nil and (NV.IsOn() or NV.Fade() > 0)
end

function FX.Start()
	if S.running or not wanted() then
		return
	end

	FX.Prewarm()

	R = S.res
	S.frame, S.lum, S.gain, S.haveMap = 0, nil, FX.GAIN.start, false
	S.running = true
	wrapCapture()

	guarded("screen", screenBody)
	guarded("fog", worldFogBody)
	guarded("skyFog", skyFogBody)
	guarded("light", FX.UpdateLight)
end

function FX.Stop()
	for key, id in pairs(ID) do
		hook.Remove(EVENT[key], id)
	end

	FX.Recover()
	removeLamp()
	unwrapCapture()
	S.running = false
end

-- Called at each frame by the screen hook, and by the tests: stops the effect when the night vision is off and its fade is over (or it is no longer
-- wanted). Returns true when it stopped.
function FX.Check()
	if S.running and not wanted() then
		FX.Stop()

		return true
	end

	return false
end

-- Starts or stops the effect to match what is wanted now (the settings changed, the night vision switched).
function FX.Sync()
	if wanted() then
		FX.Start()
	elseif S.running then
		FX.Stop()
	end
end

-- The test's way to run the screen hook as the engine does (through its guard).
function FX.RunScreenHook()
	local registered = hook.GetTable().RenderScreenspaceEffects

	if registered ~= nil and registered[ID.screen] ~= nil then
		registered[ID.screen]()
	end
end

function FX.OnShutdown()
	FX.Stop()
end

-- The end of the game, a new screen size and the arrival in a map; the night vision's own switch.
hook.Add("ShutDown", "GryMod_NightVisionFX", function()
	FX.OnShutdown()
end)

hook.Add("GryMod_NightVision", "GryMod_NightVisionFX", function()
	FX.Sync()
end)

-- The arrival in a map: the state (cl_nightvision.lua) starts again from nothing. The static textures (noise, scan lines, the lamp's cookie) are drawn in
-- small steps once the first seconds of play are past (what is drawn at the loading screen is gone afterwards), by a hook that removes itself when the
-- last step is done; a night vision switched on before that does the rest at once. Nothing is made when the effect is off.
local PREP_HOOK = "GryMod_NightVisionFX_Prep"
local PREP_DELAY = 3 -- seconds of play before the first step
local PREP_FRAMES = 60 -- and frames: a load that takes longer than the delay must not count the loading screen
local PREP_BUDGET = 2 -- milliseconds a step may use

function FX.PrepStep()
	S.prepFrames = (S.prepFrames or 0) + 1

	if RealTime() < (S.prepAt or 0) or S.prepFrames < PREP_FRAMES then
		return
	end

	if not flag("gry_nightvision_fx") or FX.PaintStatic(PREP_BUDGET) then
		hook.Remove("Think", PREP_HOOK)
	end
end

function FX.BeginPrep()
	hook.Remove("Think", PREP_HOOK)
	S.painted, S.prep, S.prepFrames = false, nil, 0

	if flag("gry_nightvision_fx") and flag("gry_nightvision") then
		S.prepAt = RealTime() + PREP_DELAY
		hook.Add("Think", PREP_HOOK, FX.PrepStep)
	end
end

hook.Add("InitPostEntity", "GryMod_NightVisionFX", function()
	FX.Stop()
	FX.BeginPrep()
end)

hook.Add("OnScreenSizeChanged", "GryMod_NightVisionFX", function()
	if S.running then
		FX.Prewarm()
	end
end)

for _, name in ipairs({"gry_nightvision_fx"}) do
	cvars.AddChangeCallback(name, function()
		FX.Sync()
	end, "GryMod_NightVisionFX")
end
