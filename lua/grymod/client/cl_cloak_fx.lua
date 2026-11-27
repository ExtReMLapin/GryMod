-- The camouflage, seen by everyone (client side). The original game does not swap a texture: a layer over the suit
-- shows the picture behind it, bent by a small normal map and tinted blue on the outline, and the layer fades in and
-- out over under a second. Sparks run over the surface while the player moves and during the change. This file
-- does the same with Source's Refract material:
--
--   * the server only says who is camouflaged (the network switch "GryCloak" of the player, sv_system.lua);
--   * every client turns that into a level that glides from 0 to 1 and back (Step), per player;
--   * the level gives three numbers (Visibility): how much the picture is bent, how much of the plain model stays
--     (almost nothing), and how strong the sparks are. The speed of the player counts for one thing only: the
--     electricity shows faintly (3 %) as he moves. A player who moves otherwise looks as one who stands. They follow the original's layer: the opacity of the plain model goes down linearly
--     with the level (the layer's alpha is 0.8 x level), the bend is 11 times stronger at the start than at the end,
--     and the sparks are there only while the change lasts, at a faint constant intensity;
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

-- A model drawn through a material override (the refraction layer, the sparks, the scan lines) goes through the engine's DYNAMIC vertex buffer, which holds 32768 vertices: a model with more
-- (the view model of the sonar grenade of ARC9's CS:GO pack: 36684, "Too many verts for a dynamic vertex buffer") makes the engine retry for ever and the game freezes. Such a model is drawn
-- plain, at the opacity of the camouflage, with no override. The size is the number of listed vertices of the model's first level of detail (util.GetModelMeshes: about 2.8 of them per
-- vertex of the buffer's size... measured: 102240 listed for 36684 in the buffer), kept per model; 60000 keeps a margin (the heaviest weapon view model measured is 51000). 0 = no guard.
local vertexLimit = GetConVar("gry_cloak_vertex_limit") or CreateClientConVar("gry_cloak_vertex_limit", "60000", true, false,
	"Models with more listed vertices than this are drawn plain by the camouflage (no refraction layer): the engine freezes on a model that is too big for its dynamic vertex buffer. 0 = no guard", 0, 1000000)

local modelWeights = F.modelWeights or {}
F.modelWeights = modelWeights

function F.ForgetModelWeights()
	for model in pairs(modelWeights) do
		modelWeights[model] = nil
	end
end

-- Whether drawing this model through a material override would overflow the dynamic vertex buffer.
function F.ModelTooHeavy(model)
	local limit = vertexLimit:GetInt()

	if limit <= 0 or not isstring(model) or model == "" then
		return false
	end

	local weight = modelWeights[model]

	if weight == nil then
		weight = 0

		local ok, meshes = pcall(util.GetModelMeshes, model, 0)

		if ok and istable(meshes) then
			for _, mesh in ipairs(meshes) do
				weight = weight + #(mesh.triangles or {})
			end
		end

		modelWeights[model] = weight
	end

	return weight > limit
end

-- The entity's model is too big for a material override (a missing method or an error is "no").
local function heavyEntity(ent)
	if not IsValid(ent) or not isfunction(ent.GetModel) then
		return false
	end

	local ok, model = pcall(ent.GetModel, ent)

	return ok and F.ModelTooHeavy(model)
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

-- The reference is a player who stands still. Moving changes one thing, and barely: once the change is done the ELECTRICITY shows a little,
-- MovingSpark of its strength at FullSpeed (the owner's allowance, "3 %"), at the same speed of animation. The plain model's opacity and the bend
-- are the same whatever his speed (the original's videos show no change there).
--
-- What the plain model still shows once fully camouflaged (the original layer keeps 20 % of the suit at rest, 0.8 being its largest blend).
F.BaseStill = 0.03
F.MovingSpark = 0.03

-- The speed (units a second) at which the faint sparks of a walk are complete: a run (400) is above it, a walk (200) a little under. The speed it
-- follows is the real one with a short delay, so that it does not flicker at every step.
F.FullSpeed = 300
F.SpeedDelay = 0.15

-- How much the picture behind is bent (the value of $refractamount) once done, and the extra at the start of the
-- change, which goes down to nothing as the level goes up (the original bends 11 times more at the start than once
-- done: 2.75 against 0.25).
F.RefractStill = 0.035
F.RefractChange = 0.2

-- Where a player's level starts when he is first seen camouflaged. A player seen from the start of his activation fades in from the plain model; one
-- who was camouflaged long before (this client joins, or he comes back into view) is simply done: starting him from 0 showed an activation (the fade
-- and the sparks of the change, 0.8 s) that was not happening. The server writes the time of the activation with the switch ("GryCloakSince",
-- sv_system.lua). The margin added to the length of the change is for the two clocks and the network: the client's CurTime can be ahead of the
-- server's by about the ping, the message takes about as long to come, and the float that carries the time has a precision of a few hundredths of a second
-- after hours of uptime; a fresh activation read as an old one would skip its fade, which is worse than a short false change, so the margin is wide.
-- A client that joins in the margin (0.5 s after the end of a change) sees the end of a change that is not there: it is at most half a second.
F.JoinMargin = 0.5

function F.StartAmount(since, now)
	-- a time that was never written (negative: the default asked for) or in the future (the client's clock is behind): the activation is going on
	if since < 0 or now - since <= F.ActivateTime + F.JoinMargin then
		return 0
	end

	return 1
end

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

function F.SmoothSpeed(previous, speed, dt)
	return speed + (previous - speed) * math.exp(-dt / F.SpeedDelay)
end

-- The sparks: only while the cloak goes in or out, always at the same intensity from the first frame to the last: not the flash of the start, nor the
-- motion on the screen. Nothing when plain, nothing once the change is done, whether he moves or not. The original's own value for a camouflaged
-- player who stands still (the transition texture's last value squared) is about 5 %: too faint to be seen, the owner chose 15 %.
F.SparkRest = 0.15

-- level (0 plain, 1 camouflaged) and speed (units a second, optional) -> refraction amount, opacity of the plain model drawn over it, strength of the
-- sparks (0 to 1). No table: this runs for every camouflaged player at every frame.
function F.Visibility(amount, speed)
	if amount <= 0 then
		return 0, 1, 0
	end

	local b = clamp01(amount)

	-- the original's bump scale is 0.25 + 2.5 x (1 - level): eleven times more at the start than at the end
	local refract = b * F.RefractStill + F.RefractChange * (1 - b)
	local base = 1 - b * (1 - F.BaseStill)

	return refract, base, F.SparkStrength(b, speed)
end

-- The sparks of the change alone, for the scan lines (cl_cloak_lines.lua): F.SparkRest during the change, else 0.
function F.TransitionSpark(amount)
	if amount <= 0 or amount >= 1 then
		return 0
	end

	return F.SparkRest
end

-- The strength of the sparks (the pixel shader's, cl_cloak_shader.lua, and the older layer's alpha): the change's own during the change, whatever the
-- speed; once it is done nothing when he stands and, as he moves, up to F.MovingSpark at F.FullSpeed; nothing for a plain player.
function F.SparkStrength(amount, speed)
	if amount <= 0 then
		return 0
	end

	if amount < 1 then
		return F.SparkRest
	end

	return F.MovingSpark * clamp01((speed or 0) / F.FullSpeed)
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

-- player -> {amount, cloaked}; a player who is plain again is forgotten, so that nothing is done (and nothing
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
	local cloaked = ply:GetNW2Bool("GryCloak", false) and ply:Alive()
	local s = States[ply]

	if not s then
		if not cloaked then
			return nil
		end

		local isLocal = ply == LocalPlayer()

		-- the local player always sees his own change (it begins when he asks for it); another player starts done when he was camouflaged long ago
		local start = 0

		if not isLocal then
			start = F.StartAmount(ply:GetNW2Float("GryCloakSince", -1), CurTime())
		end

		s = {amount = start, speed = 0, cloaked = false, legacy = false}
		States[ply] = s
		F.SetDrawHooks(true)

		if isLocal and F.Enabled() then
			startScreenFx()
		end
	end

	-- the others are told of each change of the switch, for every player (the state is made when the camouflage starts, so the first answer is "on")
	if s.told ~= cloaked then
		s.told = cloaked
		hook.Run("GryMod_CloakChanged", ply, cloaked, GryMod.API.CloakLevel(ply))
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

		F.ClearWeaponProxy(ply)
		States[ply] = nil

		if not next(States) then
			F.SetDrawHooks(false)
		end
	end

	return s
end

-- How a player comes to be followed. The game tells us, nothing is polled: the switch is a NW2 variable, so EntityNetworkedVarChanged is called when it
-- changes AND for every variable of every entity at a full update (somebody who joins while another player is camouflaged: the old value is nil); and
-- NotifyShouldTransmit is called when a player comes back into view. The hook runs before the client's value changes (measured by the wiki: it still reads
-- the old one), so the player is only put on a waiting list and read at the next Think, when the value is there.
local waiting = setmetatable({}, {__mode = "k"})

hook.Add("EntityNetworkedVarChanged", "GryCloakFX", function(ent, name)
	if name == "GryCloak" and IsValid(ent) and ent:IsPlayer() then
		waiting[ent] = true
	end
end)

hook.Add("NotifyShouldTransmit", "GryCloakFX", function(ent, shouldTransmit)
	if shouldTransmit and IsValid(ent) and ent:IsPlayer() then
		waiting[ent] = true
	end
end)

-- The players already camouflaged when this runs: at the load of the level (the full update may have come before the hooks were there) and when this
-- file is loaded again in a running game. Once, not a loop.
function F.CatchUp()
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetNW2Bool("GryCloak", false) then
			waiting[ply] = true
		end
	end
end

hook.Add("InitPostEntity", "GryCloakFX", F.CatchUp)

hook.Add("Think", "GryCloakFX", function()
	-- the ones already followed, at every frame
	for ply in pairs(States) do
		if IsValid(ply) then
			F.Update(ply)
		else
			F.ClearWeaponProxy(ply)
			States[ply] = nil

			if not next(States) then
				F.SetDrawHooks(false)
			end
		end
	end

	-- the ones the game told us about
	if next(waiting) then
		for ply in pairs(waiting) do
			waiting[ply] = nil

			if IsValid(ply) and not States[ply] then
				F.Update(ply)
			end
		end
	end
end)

if IsValid(LocalPlayer()) then
	F.CatchUp() -- loaded again in a running game
end

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

-- Draws the entity's own model for cl_cloak_lines.lua (the stencil pass): `drawing` lets it through the player's draw hook.
local function drawPlain(ent)
	drawing = true
	pcall(ent.DrawModel, ent)
	drawing = false
end

-- The sparks' shader and the scan lines draw the entity through overrides too: not for a model that is too big.
local function shaderDraw(shader, ent, strength, amount, plain, ...)
	if heavyEntity(ent) then return end

	return shader.Draw(ent, strength, amount, plain, ...)
end

local function linesDraw(ent, flash, plain, ...)
	if heavyEntity(ent) then return end

	return F.Lines.Draw(ent, flash, plain, ...)
end

local function drawLayers(ent, refract, base, spark, level)
	local refractMat, edgeMat = materials()
	drawing = true

	-- a model too big for the dynamic vertex buffer: the plain model at the opacity, no override (see gry_cloak_vertex_limit)
	if heavyEntity(ent) then
		local ok, err = pcall(function()
			render.MaterialOverride(nil)

			if base >= F.Invisible then
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

	-- The refraction layer's own pixel shader (cl_cloak_refract.lua): the plain model first, opaque as the engine always draws it, then the layer
	-- blended over it with the alpha the model has lost, then the outline. Under the opacity where the plain model is not worth drawing, the layer
	-- alone covers what is behind.
	if level and F.Refract and F.Refract.Active() then
		local ok, err = pcall(function()
			if base >= F.Invisible then
				render.MaterialOverride(nil)
				render.SetBlend(1)
				ent:DrawModel()
			end

			F.Refract.Draw(ent, F.Refract.BumpScale(level), F.Refract.Alpha(base), drawPlain)

			if spark > 0.02 then
				render.MaterialOverride(edgeMat)
				render.SetColorModulation(SPARK_R, SPARK_G, SPARK_B)
				render.SetBlend(spark * (0.7 + 0.3 * math.sin(CurTime() * 37 + ent:EntIndex() * 1.7)))
				ent:DrawModel()
			end
		end)

		render.MaterialOverride(nil)
		render.SetColorModulation(1, 1, 1)
		render.SetBlend(1)
		drawing = false

		return ok, err
	end

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

-- The weapon in a camouflaged player's hand. The server hides its world model (EF_NODRAW, sv_system.lua) so that the engine does not draw it plain,
-- and a weapon entity with that flag is out of the engine's render list: DrawModel on it draws NOTHING, whoever asks (measured in a mirror: the
-- calls were made every frame, with no error, and the hand held air). So it is drawn through a client model of its world model, bone-merged on the
-- player the way the engine does, which draws wherever it is asked. One for each player, made when the weapon first shows, kept while the model is
-- the same, replaced when it changes, removed with the player's state.
local proxies = setmetatable({}, {__mode = "k"})

function F.ClearWeaponProxy(ply)
	local entry = proxies[ply]

	if entry then
		proxies[ply] = nil

		if IsValid(entry.ent) then
			entry.ent:Remove()
		end
	end
end

-- The entity to draw for `weapon` (the player's active weapon), or nil when it has no world model to copy (then the weapon itself is drawn).
function F.WeaponProxy(ply, weapon)
	if not IsValid(weapon) then
		F.ClearWeaponProxy(ply)

		return nil
	end

	local model = weapon:GetModel()

	if not model or model == "" then
		F.ClearWeaponProxy(ply)

		return nil
	end

	local entry = proxies[ply]

	if entry and entry.model == model and IsValid(entry.ent) then
		return entry.ent
	end

	F.ClearWeaponProxy(ply)

	local ent = ClientsideModel(model)

	if not IsValid(ent) then return nil end

	ent:SetNoDraw(true) -- the engine never draws it: it is drawn from here only
	ent:SetParent(ply)
	ent:AddEffects(EF_BONEMERGE)
	ent:SetSkin(weapon:GetSkin())

	for group = 0, weapon:GetNumBodyGroups() - 1 do
		ent:SetBodygroup(group, weapon:GetBodygroup(group))
	end

	proxies[ply] = {ent = ent, model = model}

	return ent
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

local wornParts = {} -- the list of GryMod.API.GetPlayerParts, reused

drawHooks.PostDrawTranslucentRenderables = function(depth, skybox, skybox3d)
	if depth or skybox or skybox3d or drawing or not next(States) or not F.Enabled() then return end

	-- Also in the render targets: a mirror (func_reflective_glass draws the world again into _rt_waterreflection, with the
	-- local player in it), the water, a camera. PrePlayerDraw hides the player in every view, so a view skipped here
	-- would show nobody at all. The screen copy below is made per view (it copies the target being drawn into).
	local updated = false
	local eye, forward = EyePos(), EyeVector()

	-- the sparks: the original's pixel shader when the game can run it (cl_cloak_shader.lua), else the edge layer and the scan lines
	local shader = F.Shader and F.Shader.Active() and F.Shader

	for ply, s in pairs(States) do
		if s.amount > 0 and IsValid(ply) then
			local visible, distance = drawn(ply, eye, forward)

			if visible then
				if not updated then
					updated = true

					-- the picture behind, copied before any camouflaged player is on it: for the layer's own shader, or for the older Refract material
					if F.Refract and F.Refract.Active() then
						render.UpdateScreenEffectTexture()
					else
						render.UpdateRefractTexture()
					end
				end

				local refract, base, spark = F.Visibility(s.amount, s.speed)
				local strength = 0

				if distance > F.DetailDistance then
					spark = 0
				end

				if shader then
					-- the shader's sparks are added over the plain model while the change lasts, at the faint intensity of a player who stands
					-- still (nothing far away, where the sparks are not worth the cost)
					drawLayers(ply, refract, base, 0, s.amount)
					strength = distance <= F.DetailDistance and F.SparkStrength(s.amount, s.speed) or 0

					if strength > 0 then
						shaderDraw(shader, ply, strength, s.amount, drawPlain)
					end
				else
					drawLayers(ply, refract, base, spark, s.amount)

					-- the scan lines, on the screen over the silhouette: only in the electric flash of the start of the change
					local flash = F.TransitionSpark(s.amount)

					if distance <= F.DetailDistance and flash > 0.02 and F.Lines then
						linesDraw(ply, flash, drawPlain)
					end
				end

				-- the weapon in the hand follows the body (its world model is hidden by the server, see sv_system.lua, so
				-- it is drawn from here): the refraction, then the plain model at the same opacity, and the shader's sparks
				local weapon = ply:GetActiveWeapon()

				if IsValid(weapon) and distance <= F.DetailDistance then
					local held = F.WeaponProxy(ply, weapon) or weapon

					drawLayers(held, refract, base, 0, s.amount)

					if shader and strength > 0 then
						shaderDraw(shader, held, strength, s.amount, drawPlain)
					end
				elseif not IsValid(weapon) then
					F.ClearWeaponProxy(ply)
				end

				-- what the player wears that the engine does not draw as part of him (GryMod.API.AddPlayerPartsProvider): the same layers, the same opacity
				if distance <= F.DetailDistance then
					local worn, wornCount = GryMod.API.GetPlayerParts(ply, wornParts)

					for i = 1, wornCount do
						drawLayers(worn[i], refract, base, 0, s.amount)

						if shader and strength > 0 then
							shaderDraw(shader, worn[i], strength, s.amount, drawPlain)
						end
					end
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

-- from this opacity of the plain model up the arms are drawn as they are: no refraction under them, no translucent draw
F.NearlyPlain = 0.99

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

	-- the binoculars hide the view model and the hands: their hook on this very event returns true, and the engine then skips the Post hook too, which would put the render
	-- state back. Nothing is prepared here (and what a frame before left on is put back).
	local Bino = GryMod.FlashBinoculars

	if Bino and Bino.HideWeapon() == true then
		if s.firstPerson then
			s.firstPerson = false
			render.MaterialOverride(nil)
			render.SetBlend(1)
		end

		return
	end

	-- the weapon's own screen has the view (a customization menu): the gun is drawn plain there, the picture behind it is not the one the layer would copy
	if GryMod.API.IsPlainView(ply:GetActiveWeapon()) then return end

	local refract, base = firstPersonLayers(s)
	local refractMat = materials()

	s.firstPerson = true

	-- a view model too big for the dynamic vertex buffer (gry_cloak_vertex_limit): no refraction, no override; the engine's own draw only, at the opacity (the Post hook adds nothing)
	if heavyEntity(ent) then
		if base < F.NearlyPlain then
			render.SetBlend(base >= F.Invisible and base or 0)
		end

		return
	end

	-- The refraction layer's own pixel shader: the engine draws the arms opaque, as it always does, and the layer is blended over them in the Post
	-- hook; here only the picture behind is copied, before the model is on it (once per frame, for the view model: the hands come right after it).
	if F.Refract and F.Refract.Active() then
		if base < F.NearlyPlain and ent == ply:GetViewModel() then
			F.Refract.CaptureScreen()
		end

		return
	end

	-- the refraction first, unless the plain model is still all there (the very start of the change)
	if base < F.NearlyPlain and ent:IsValid() then
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

	-- the engine's draw comes next: part transparent, or switched off; with the plain model nearly all there (the end of the change, where the
	-- refraction has stopped too) it is left OPAQUE: the engine draws a translucent model flat and dark, even at 99.7 %, and the gun was a black
	-- shape for the last frame before the plain draw came back (measured on the last frames of a deactivation)
	if base < F.NearlyPlain then
		render.SetBlend(base >= F.Invisible and base or 0)
	end
end

-- The layers over a model of the first person view that has just been drawn plain (the engine drew the view model and the hands, the weapon drew its own
-- attachments): the refraction with the alpha the plain model has lost, the sparks of the shader or the outline of the older layer, the scan lines of the start
-- of the change. One function for every such model, so that the arms, the gun and a sight on it are treated the same.
local function firstPersonOver(ent, s)
	-- (a model too big for the dynamic vertex buffer gets no layer: see startFirstPerson)
	if heavyEntity(ent) then return end

	local _, layerBase, edge = firstPersonLayers(s)

	-- the engine draws the view model in the first tenth of the depth (so that it never goes into a wall). A weapon base that draws the view
	-- model itself (ARC9: its own camera and its own depth range, restored to the whole range when its draw ends, which the layer's draw of the view
	-- model runs through) leaves another range behind, and the layer was then hidden by the hands it covers (measured). Set it as the engine has it.
	render.DepthRange(0, 0.1)

	-- the refraction layer over the arms the engine has just drawn, with the alpha the plain model has lost; at the end of the change (the plain
	-- model nearly all there) nothing
	if F.Refract and F.Refract.Active() and layerBase < F.NearlyPlain and IsValid(ent) then
		F.Refract.Draw(ent, F.Refract.BumpScale(s.amount), F.Refract.Alpha(layerBase), drawPlain, true)
	end

	-- the sparks of the original's pixel shader instead of the outline and of the scan lines (which are in the shader)
	if F.Shader and F.Shader.Active() then
		if IsValid(ent) then
			-- the same faint strength as the body's, while the change lasts (the outline's floor is only for the older layer below)
			local strength = F.SparkStrength(s.amount, s.speed)

			if strength > 0 then
				shaderDraw(F.Shader, ent, strength, s.amount, drawPlain, true)
			end
		end

		return
	end

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

	-- the scan lines of the electric flash of the start of the change, over the arms and the gun (the whole screen is the
	-- box: the view model has its own field of view, see cl_cloak_lines.lua)
	local flash = F.TransitionSpark(s.amount)

	if flash > 0.02 and F.Lines and IsValid(ent) then
		linesDraw(ent, flash, drawPlain, true)
	end
end

-- the models the weapon in the hand draws itself (its attachments), asked at each frame: the buffer is kept (no table made per frame)
local weaponParts = {}

local function endFirstPerson(ent, ply)
	local s = States[ply]

	if not s or not s.firstPerson then return end

	s.firstPerson = false
	render.MaterialOverride(nil)
	render.SetBlend(1)

	firstPersonOver(ent, s)

	-- A weapon draws its attachments itself, in its own draw, between the view model's and this hook: models the engine does not know, which
	-- were left plain over the camouflaged gun (a sight on a TFA weapon: reported by the owner). They are asked of the weapon at each frame
	-- (GryMod.API.GetWeaponParts, the providers of lua/grymod/compat/weapons/): an attachment changed during the camouflage is the next frame's list.
	-- Only with the view model: the hands are not the weapon's.
	if ent == ply:GetViewModel() then
		local weapon = ply:GetActiveWeapon()
		local parts, count = GryMod.API.GetWeaponParts(weapon, weaponParts)

		for i = 1, count do
			firstPersonOver(parts[i], s)
		end
	end
end

-- The physgun draws its own glow sprites and beam, through this hook, inside the weapon's own draw: nothing drawn over the weapon covers them (a blue
-- patch stayed in the camouflaged hand, in first person, however well the model was refracted: measured). Returning false hides them, for whoever
-- looks, while the owner is camouflaged.
drawHooks.DrawPhysgunBeam = function(ply)
	local s = States[ply]

	if s and s.amount > 0 and F.Enabled() then
		return false
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
	if GryMod.Minimap and GryMod.Minimap.Capture and GryMod.Minimap.Capture.IsCapturing() then return end

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
