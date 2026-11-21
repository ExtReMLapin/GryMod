-- The camouflage, seen by everyone (client side). The original game does not swap a texture: a layer over the suit
-- shows the picture behind it, bent by a small normal map and tinted blue on the outline, and the layer fades in and
-- out over under a second. Sparks run over the surface while the player moves and during the change. This file
-- does the same with Source's Refract material:
--
--   * the server only says who is camouflaged (the network switch "GryCloak" of the player, sv_system.lua);
--   * every client turns that into a level that glides from 0 to 1 and back (Step), per player;
--   * the level and the speed give three numbers (Visibility): how much the picture is bent, how much of the plain
--     model stays (almost nothing when still), and how strong the sparks are. They follow the original's layer: the
--     opacity of the plain model goes down linearly with the level (the layer's alpha is 0.8 x level), the bend is
--     11 times stronger at the start than at the end, and the sparks flash in the first tenth of the change
--     (the curve of its texture cloak_transition.dds) then die down;
--   * the draw hooks put the layers on the player, on the weapon in the hand, and on the view model and the hands
--     of the local player. The refraction is drawn first and the plain model over it, half transparent, so that the
--     fade is a real one (in first person too: the view model's own draw is the one that is made part transparent);
--   * the player who switches the camouflage on gets a short screen effect (grey and colour fringes, 1.7 s, the
--     graph "suit_cloakmode" of the original game).
--
-- Switches (client): gry_cloak_fx, 0 gives the previous look back (the material "cloak/organic" on the model);
-- gry_cloak_transition, 0 makes the change instant (no fade, no sparks flash).

GryMod = GryMod or {}

local F = GryMod.CloakFX or {}
GryMod.CloakFX = F

local convar = GetConVar("gry_cloak_fx") or CreateClientConVar("gry_cloak_fx", "1", true, false,
	"1: the camouflage bends the picture behind the player and fades in and out; 0: the old material on the model", 0, 1)

function F.Enabled()
	return convar:GetBool()
end

local transition = GetConVar("gry_cloak_transition") or CreateClientConVar("gry_cloak_transition", "1", true, false,
	"1: the camouflage fades in and out progressively, in first and third person; 0: it switches at once", 0, 1)

function F.TransitionEnabled()
	return transition:GetBool()
end

--------------------------------------------------------------------------------------------------------------------
-- Rules (pure functions)
--------------------------------------------------------------------------------------------------------------------

-- Seconds from fully visible to fully camouflaged and back. The original's value is in the engine, which was not
-- read: these are set by eye against the sound of the mode change (0.55 s) and the first stage of its screen
-- effect (0.7 s).
F.ActivateTime = 0.8
F.DeactivateTime = 0.6

-- The speed at which the effect is complete: a run (400 units per second) is above it, a walk (200) a little under.
F.FullSpeed = 300

-- What the plain model still shows once fully camouflaged: a trace when still, more when moving (the original
-- layer keeps 20 % of the suit at rest, 0.8 being its largest blend).
F.BaseStill = 0.03
F.BaseMoving = 0.28

-- How much the picture behind is bent (the value of $refractamount): still, moving, and the extra at the start of the
-- change, which goes down to nothing as the level goes up (the original bends 11 times more at the start than once
-- done: 2.75 against 0.25).
F.RefractStill = 0.035
F.RefractMoving = 0.09
F.RefractChange = 0.2

-- The speed shown by the sparks follows the real one with this delay (seconds)
F.SpeedDelay = 0.15

local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end

	return x
end

-- The level goes towards the switch at the pace of the transition. Linear: like the original's blend, which the
-- layer's alpha follows directly. With gry_cloak_transition 0 it goes at once.
function F.Step(amount, cloaked, dt)
	if not F.TransitionEnabled() then
		return cloaked and 1 or 0
	end

	if cloaked then
		return math.min(1, amount + dt / F.ActivateTime)
	end

	return math.max(0, amount - dt / F.DeactivateTime)
end

function F.SmoothSpeed(previous, speed, dt)
	return speed + (previous - speed) * math.exp(-dt / F.SpeedDelay)
end

-- The alpha of the original's texture cloak_transition.dds (256 samples, here every 8th and the last one): the sparks'
-- strength is this value squared, as a function of the level. 0 at the start, full from 24/255 to 40/255, then down
-- to 55/255 when the change is done.
local TRANSITION = {0, 79, 191, 255, 255, 255, 254, 253, 251, 248, 245, 241, 236, 232, 228, 222, 217, 211, 205, 200,
	193, 186, 180, 172, 164, 146, 129, 112, 97, 83, 70, 61, 55}

function F.TransitionCurve(level)
	level = clamp01(level) * 255

	-- the 32 first knots are 8 samples apart, the last one is 7 after the previous
	local i = math.min(math.floor(level / 8), 31)
	local from, to = i * 8, (i == 31) and 255 or (i + 1) * 8
	local t = (level - from) / (to - from)

	return (TRANSITION[i + 1] + (TRANSITION[i + 2] - TRANSITION[i + 1]) * t) / 255
end

-- what the sparks still show when everything is done and still: not drawn (the original's pattern there is faint)
local restSpark = F.TransitionCurve(1) ^ 2

-- level (0 plain, 1 camouflaged) and speed (units per second) -> refraction amount, opacity of the plain model drawn
-- over it, strength of the sparks (0 to 1). No table: this runs for every camouflaged player at every frame.
function F.Visibility(amount, speed)
	if amount <= 0 then
		return 0, 1, 0
	end

	local b = clamp01(amount)
	local s = clamp01(speed / F.FullSpeed)

	-- the original's bump scale is 0.25 + 2.5 x (1 - level): eleven times more at the start than at the end
	local refract = b * (F.RefractStill + (F.RefractMoving - F.RefractStill) * s) + F.RefractChange * (1 - b)
	local base = 1 - b * (1 - (F.BaseStill + (F.BaseMoving - F.BaseStill) * s))
	local spark = math.max(b * s, F.TransitionCurve(b) ^ 2 - restSpark)

	return refract, base, clamp01(spark)
end

-- The screen effect of the activation, read from the original's graph (seconds -> grey level, fringes, condensation):
-- the saturation goes 1 -> 0.5 in 0.7 s then back in 1 s, the colour fringes 0 -> 0.4 in 0.7 s then back in 1 s, and
-- the condensation 0 -> 1.5 in 0.2 s, -> 0.3 in 0.25 s, -> 0 in 1 s.
F.ScreenFxDuration = 1.7

local function lerp(t, a, b)
	return a + (b - a) * t
end

function F.ScreenFx(t)
	if t <= 0 or t >= F.ScreenFxDuration then
		return 1, 0, 0
	end

	local saturation, fringes, condensation

	if t < 0.7 then
		saturation = lerp(t / 0.7, 1, 0.5)
		fringes = lerp(t / 0.7, 0, 0.4)
	else
		saturation = lerp((t - 0.7) / 1, 0.5, 1)
		fringes = lerp((t - 0.7) / 1, 0.4, 0)
	end

	if t < 0.2 then
		condensation = lerp(t / 0.2, 0, 1.5)
	elseif t < 0.45 then
		condensation = lerp((t - 0.2) / 0.25, 1.5, 0.3)
	else
		condensation = lerp((t - 0.45) / 1, 0.3, 0)
	end

	return saturation, fringes, condensation
end

--------------------------------------------------------------------------------------------------------------------
-- State of each camouflaged player
--------------------------------------------------------------------------------------------------------------------

-- player -> {amount, speed, cloaked}; a player who is plain again is forgotten, so that nothing is done (and nothing
-- is looked at) while nobody is camouflaged.
F.States = F.States or {}
local States = F.States

-- The draw hooks (below) exist only while somebody is camouflaged: with nobody, the engine does not even call them.
local drawHooks = {}
local drawHooksOn = false

function F.SetDrawHooks(on)
	if on == drawHooksOn then return end

	drawHooksOn = on

	for event, fn in pairs(drawHooks) do
		if on then
			hook.Add(event, "GryCloakFX", fn)
		else
			hook.Remove(event, "GryCloakFX")
		end
	end
end

local legacyMaterial = "cloak/organic"

-- gry_cloak_fx 0: the previous look, the material of the old camouflage on the player and the hands
local function setLegacy(ply, on)
	if ply.SetMaterial then
		ply:SetMaterial(on and legacyMaterial or "")
	end

	if ply == LocalPlayer() then
		local vm = ply:GetViewModel()
		local hands = ply:GetHands()

		if IsValid(vm) then vm:SetMaterial(on and legacyMaterial or "") end
		if IsValid(hands) then hands:SetMaterial(on and legacyMaterial or "") end
	end
end

local screenFxStart

local function startScreenFx()
	screenFxStart = CurTime()
	hook.Add("RenderScreenspaceEffects", "GryCloakFXScreen", F.DrawScreenFx)
end

-- Follows the player's switch for one frame. Nothing is made for a player who was never camouflaged.
function F.Update(ply)
	local cloaked = ply:GetNWBool("GryCloak", false) and ply:Alive()
	local s = States[ply]

	if not s then
		if not cloaked then
			return nil
		end

		s = {amount = 0, speed = 0, cloaked = false, legacy = false}
		States[ply] = s
		F.SetDrawHooks(true)

		if ply == LocalPlayer() and F.Enabled() then
			startScreenFx()
		end
	end

	local dt = FrameTime()
	s.cloaked = cloaked
	s.amount = F.Step(s.amount, cloaked, dt)
	s.speed = F.SmoothSpeed(s.speed, ply:GetVelocity():Length2D(), dt)

	local legacy = F.Enabled() == false and (cloaked or s.amount > 0)

	-- a camouflaged player casts no shadow (the original's layer has a "CloakShadowBias" for that)
	local shadowless = s.amount > 0.5

	if shadowless ~= s.shadowless and ply.DrawShadow then
		s.shadowless = shadowless
		ply:DrawShadow(not shadowless)
	end

	if legacy ~= s.legacy then
		s.legacy = legacy
		setLegacy(ply, legacy)
	end

	if not cloaked and s.amount <= 0 then
		if s.shadowless and ply.DrawShadow then
			ply:DrawShadow(true)
		end

		-- the view model was being drawn when the player went away (death, disconnect): nothing is left on
		if s.firstPerson then
			render.MaterialOverride(nil)
			render.SetBlend(1)
		end

		States[ply] = nil

		if not next(States) then
			F.SetDrawHooks(false)
		end
	end

	return s
end

-- The players that are not followed yet are looked at this often (seconds): a short delay, so that the change of another
-- player starts when the server hides his weapon (nothing is run while nobody is camouflaged but this look).
F.ScanInterval = 0.1

local lastScan = 0

hook.Add("Think", "GryCloakFX", function()
	-- the ones already followed, at every frame
	for ply in pairs(States) do
		if IsValid(ply) then
			F.Update(ply)
		else
			States[ply] = nil

			if not next(States) then
				F.SetDrawHooks(false)
			end
		end
	end

	-- the new ones: the local player at every frame, the others every ScanInterval
	local me = LocalPlayer()

	if IsValid(me) and not States[me] and me:GetNWBool("GryCloak", false) then
		F.Update(me)
	end

	local now = RealTime()

	if now - lastScan > F.ScanInterval then
		lastScan = now

		for _, ply in ipairs(player.GetAll()) do
			if not States[ply] and ply:GetNWBool("GryCloak", false) then
				F.Update(ply)
			end
		end
	end
end)

--------------------------------------------------------------------------------------------------------------------
-- Materials
--------------------------------------------------------------------------------------------------------------------

local matRefract, matEdge

local function materials()
	if not matRefract then
		matRefract = Material("grymod/cloak/cloak_refract")
		matEdge = Material("grymod/cloak/cloak_edge")
	end

	return matRefract, matEdge
end

-- the blue of the sparks and of the outline (the original's SparksColor is 0.3, 0.3, 1)
local SPARK_R, SPARK_G, SPARK_B = 0.3, 0.45, 1

-- Draws the entity through the layers, whatever happens the render state comes back (nothing leaks to what is
-- drawn next): the refraction first, the sparks added on it, then the plain model over it at the opacity `base`.
local drawing = false

local function drawLayers(ent, refract, base, spark)
	local refractMat, edgeMat = materials()
	drawing = true

	local ok, err = pcall(function()
		refractMat:SetFloat("$refractamount", refract)
		render.MaterialOverride(refractMat)
		ent:DrawModel()

		if spark > 0.02 then
			render.MaterialOverride(edgeMat)
			render.SetColorModulation(SPARK_R, SPARK_G, SPARK_B)
			render.SetBlend(spark * (0.7 + 0.3 * math.sin(CurTime() * 37 + ent:EntIndex() * 1.7))) -- the scintillation
			ent:DrawModel()
		end

		if base >= F.Invisible then
			render.MaterialOverride(nil)
			render.SetColorModulation(1, 1, 1)
			render.SetBlend(base)
			ent:DrawModel()
		end
	end)

	render.MaterialOverride(nil)
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
	drawing = false

	return ok, err
end

--------------------------------------------------------------------------------------------------------------------
-- Draw hooks
--------------------------------------------------------------------------------------------------------------------

-- under this opacity the plain model is not worth drawing
F.Invisible = 0.05

-- The engine does not draw a camouflaged player: it is drawn after everything else (PostDrawTranslucentRenderables),
-- when the picture behind it is complete. The Refract material shows the copy of the screen (UpdateRefractTexture,
-- once per frame): drawn earlier, among the opaque things, it would show the previous frame's picture.
drawHooks.PrePlayerDraw = function(ply)
	if drawing then return end

	local s = States[ply]

	if s and s.amount > 0 and F.Enabled() then
		return true
	end
end

-- Farther than this the sparks and the weapon are not drawn (not worth the cost); farther than the second one the
-- player is not drawn at all.
F.DetailDistance = 1200
F.MaxDistance = 6000

-- is the player to be seen at all: not dormant, in front of the camera (the engine's own culling does not apply to
-- what is drawn from here), and not too far. The local player's own body only in third person.
local function drawn(ply, eye, forward)
	if ply:IsDormant() then return false, 0 end
	if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then return false, 0 end

	local to = ply:WorldSpaceCenter() - eye
	local distance = to:Length()

	if distance > F.MaxDistance then return false, distance end

	-- 80 degrees to each side of the view is generous (the fields of view go up to 110 degrees across); right next
	-- to the camera nothing is culled
	if distance > 120 and to:Dot(forward) < distance * 0.17 then return false, distance end

	return true, distance
end

drawHooks.PostDrawTranslucentRenderables = function(depth, skybox, skybox3d)
	if depth or skybox or skybox3d or drawing or not next(States) or not F.Enabled() then return end

	-- Also in the render targets: a mirror (func_reflective_glass draws the world again into _rt_waterreflection, with the
	-- local player in it), the water, a camera. PrePlayerDraw hides the player in every view, so a view skipped here
	-- would show nobody at all. The screen copy below is made per view (it copies the target being drawn into).
	local updated = false
	local eye, forward = EyePos(), EyeVector()

	for ply, s in pairs(States) do
		if s.amount > 0 and IsValid(ply) then
			local visible, distance = drawn(ply, eye, forward)

			if visible then
				if not updated then
					updated = true
					render.UpdateRefractTexture()
				end

				local refract, base, spark = F.Visibility(s.amount, s.speed)

				if distance > F.DetailDistance then
					spark = 0
				end

				drawLayers(ply, refract, base, spark)

				-- the weapon in the hand follows the body (its world model is hidden by the server, see sv_system.lua, so
				-- it is drawn from here): the refraction, then the plain model at the same opacity, without sparks
				local weapon = ply:GetActiveWeapon()

				if IsValid(weapon) and distance <= F.DetailDistance then
					drawLayers(weapon, refract, base, 0)
				end
			end
		end
	end
end

-- The local player's view model and hands. The refraction is drawn by hand first, then the engine's own draw of the
-- model goes on over it, part transparent (render.SetBlend before the model is drawn works on it; a second draw
-- from the Post hook comes out opaque), or not at all when the opacity is under F.Invisible (a blend of 0). The blue
-- outline is added in the Post hook. So the arms and the gun fade away like the third person body does.
F.FirstPersonEdge = 0.45

-- how bent the picture is in first person (the arms are close to the camera, the bend is seen larger)
F.FirstPersonBend = 1.5

local function firstPersonLayers(s)
	local refract, base, spark = F.Visibility(s.amount, s.speed)

	return refract * F.FirstPersonBend, base, math.max(spark, F.FirstPersonEdge * clamp01(s.amount))
end

local function startFirstPerson(ent, ply)
	if drawing or ply ~= LocalPlayer() or not F.Enabled() then return end

	local s = States[ply]

	if not s or s.amount <= 0 then return end

	local refract, base = firstPersonLayers(s)
	local refractMat = materials()

	s.firstPerson = true

	-- the refraction first, unless the plain model is still all there (the very start of the change)
	if base < 0.99 and ent:IsValid() then
		-- one copy of the screen per frame, for the view model (the hands come right after it)
		if ent == ply:GetViewModel() then
			render.UpdateRefractTexture()
		end

		drawing = true
		pcall(function()
			refractMat:SetFloat("$refractamount", refract)
			render.MaterialOverride(refractMat)
			ent:DrawModel()
		end)
		render.MaterialOverride(nil)
		drawing = false
	end

	-- the engine's draw comes next: part transparent, or switched off
	render.SetBlend(base >= F.Invisible and base or 0)
end

local function endFirstPerson(ent, ply)
	local s = States[ply]

	if not s or not s.firstPerson then return end

	s.firstPerson = false
	render.MaterialOverride(nil)
	render.SetBlend(1)

	local _, _, edge = firstPersonLayers(s)

	if edge >= F.Invisible and IsValid(ent) then
		local _, edgeMat = materials()
		drawing = true
		pcall(function()
			render.MaterialOverride(edgeMat)
			render.SetColorModulation(SPARK_R, SPARK_G, SPARK_B)
			render.SetBlend(edge)
			ent:DrawModel()
		end)
		render.MaterialOverride(nil)
		render.SetColorModulation(1, 1, 1)
		render.SetBlend(1)
		drawing = false
	end
end

drawHooks.PreDrawViewModel = function(vm, ply, weapon)
	startFirstPerson(vm, ply)
end

drawHooks.PostDrawViewModel = function(vm, ply, weapon)
	endFirstPerson(vm, ply)
end

drawHooks.PreDrawPlayerHands = function(hands, vm, ply, weapon)
	startFirstPerson(hands, ply)
end

drawHooks.PostDrawPlayerHands = function(hands, vm, ply, weapon)
	endFirstPerson(hands, ply)
end

--------------------------------------------------------------------------------------------------------------------
-- Screen effect of the activation (only while it lasts: the hook is put back when it ends)
--------------------------------------------------------------------------------------------------------------------

local colourModify = {
	["$pp_colour_addr"] = 0,
	["$pp_colour_addg"] = 0,
	["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0,
	["$pp_colour_contrast"] = 1,
	["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0,
	["$pp_colour_mulg"] = 0,
	["$pp_colour_mulb"] = 0
}

local fringeMat

local function fringes(amount)
	if not fringeMat then
		fringeMat = CreateMaterial("GryCloakFringe", "UnlitGeneric", {
			["$basetexture"] = "_rt_FullFrameFB",
			["$additive"] = "1",
			["$ignorez"] = "1",
			["$vertexcolor"] = "1",
			["$vertexalpha"] = "0"
		})
	end

	render.UpdateScreenEffectTexture()
	local w, h = ScrW(), ScrH()
	local shift = amount * 0.012 * w
	render.SetMaterial(fringeMat)

	-- a red ghost one way, a blue one the other: the fringes of a lens
	fringeMat:SetVector("$color", Vector(amount * 0.5, 0, 0))
	render.DrawScreenQuadEx(shift, 0, w, h)
	fringeMat:SetVector("$color", Vector(0, 0, amount * 0.7))
	render.DrawScreenQuadEx(-shift, 0, w, h)
end

function F.DrawScreenFx()
	local t = CurTime() - (screenFxStart or -10)

	if t >= F.ScreenFxDuration or not F.Enabled() then
		hook.Remove("RenderScreenspaceEffects", "GryCloakFXScreen")

		return
	end

	local saturation, fringe = F.ScreenFx(t)
	colourModify["$pp_colour_colour"] = saturation
	DrawColorModify(colourModify)

	if fringe > 0.01 then
		fringes(fringe)
	end
end

-- after a reload of this file: the hooks of the previous copy go, the right ones are put back if somebody is camouflaged
for event in pairs(drawHooks) do
	hook.Remove(event, "GryCloakFX")
end

F.SetDrawHooks(next(States) ~= nil)
