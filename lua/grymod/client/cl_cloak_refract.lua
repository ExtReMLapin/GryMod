-- The camouflage's refraction layer, drawn by the original game's own pixel shader (client).
--
-- In Crysis the cloak is a layer drawn over the suit (CloakLayer.cfx, CloakRefrationPS): the picture behind it, bent by the suit's relief and
-- tinted at its edges, blended with the cloak's level as its alpha. Source's own Refract material ignores the alpha (it replaces what it covers), so
-- the plain model had to be drawn translucent over it, and the engine draws a translucent model flat and dark. The port is a pixel shader
-- (dev_resources/shaders/grymod_cloak_refract_*.hlsl, compiled to shaders/fxc): the engine draws the model opaque as it always does, and this layer
-- is blended over it (the material has $alphablend). Each part of a model gets its own relief map, the one of its material (its $bumpmap), as the
-- original uses the suit's own; a part with none gets the generic one (cloak_n). cl_cloak_fx.lua draws it; when the game cannot run it (a test draw
-- tells, as for the sparks) the older Refract layer stays. One check box: gry_cloak_refract.

GryMod = GryMod or {}

local F = GryMod.CloakFX or {}
GryMod.CloakFX = F

local R = F.Refract or {}
F.Refract = R

local convar = GetConVar("gry_cloak_refract") or CreateClientConVar("gry_cloak_refract", "1", true, false,
	"1: the camouflage's refraction is the original game's own pixel shader, blended over the model (when the game can run it); 0: the older Refract material", 0, 1)

-- The shader files (shaders/fxc) and the textures. The game keeps the code of a shader name until it is closed: to try another build give the new
-- files another name here before the first draw.
R.PIXEL = R.PIXEL or "grymod_cloak_refract_ps30"
R.VERTEX = R.VERTEX or "grymod_cloak_refract_vs30"
R.SCREEN = "_rt_FullFrameFB"
R.BUMP = "grymod/cloak/cloak_n"
R.PALETTE = "grymod/cloak/cloak_palette"
R.INTERLATION = "grymod/cloak/cloak_interlation"
-- (the name carries what makes the material what it is: CreateMaterial hands back an existing material of the same name, with its old parameters)
R.prefix = "GryCloakRefractSrgb"

-- Model units to one metre (the original's units: its bend is in metres).
R.UNITS = 52.49

-- How much the picture is bent: the original's bump scale times this.
R.BEND_GAIN = 1

-- The light of the rim colours (the original takes a fifth of the light amount).
R.RIM_LIGHT = 0.2

-- The strength of the relief map's bend of the normal, and the tiling of the generic map over the model's coordinates (the models' own maps cover
-- them once).
R.RELIEF = 1
R.GENERIC_TILING = 2

-- The copy of the screen holds the colours as they are shown, and the layer's output goes into a linear buffer, so the picture behind is read through
-- the sRGB conversion the engine applies to colours ($linearread_basetexture 0): the camouflaged arm then shows exactly what is behind it. Read as it
-- is, the picture came out brighter than the scene, an icy glassy arm (measured, and the owner's verdict: no).

-- Under this alpha nothing is drawn.
R.MIN_ALPHA = 0.01

function R.Enabled()
	return convar:GetBool()
end

local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end

	return x
end

--------------------------------------------------------------------------------------------------------------------
-- What the shader is given (pure functions)
--------------------------------------------------------------------------------------------------------------------

-- The original's bump scale (0.25 + 0.25 x (1 - level) x 10) of the cloak's level: eleven times more at the start of the change than once done.
function R.BumpScale(level)
	return (0.25 + 2.5 * (1 - clamp01(level))) * R.BEND_GAIN
end

-- The alpha of the layer: what the plain model has lost.
function R.Alpha(base)
	return clamp01(1 - base)
end

-- The three constant registers: {{bump scale, alpha, the rim's light, rows to a period}, {scan lines' offset, half a pixel x, half a pixel y,
-- units to a metre}, {tiling, relief strength}}. `into` (optional) is the result of an earlier call, filled again instead of making new tables.
function R.Constants(bump, alpha, curtime, screenW, screenH, tiling, into)
	local period = F.Shader.RowPeriod(screenH)
	local c = into or {{}, {}, {}}
	local r1, r2, r3 = c[1], c[2], c[3]

	r1[1], r1[2], r1[3], r1[4] = bump, alpha, R.RIM_LIGHT, period
	r2[1], r2[2], r2[3], r2[4] = F.Shader.RowOffset(curtime, period), 0.5 / screenW, 0.5 / screenH, R.UNITS
	r3[1], r3[2], r3[3], r3[4] = tiling, R.RELIEF, 0, 0

	return c
end

local REGISTERS = {"x", "y", "z", "w"}

-- the names of the material's twelve parameters, made once
local NAMES = {}

for r = 1, 3 do
	NAMES[r] = {}

	for i = 1, 4 do
		NAMES[r][i] = "$c" .. (r - 1) .. "_" .. REGISTERS[i]
	end
end

-- What a material was last given. Every SetFloat goes through the engine and nearly every constant is the same from one frame to the next (only the
-- scan lines' offset moves, 30 times a second, and the bend and the alpha while the change lasts). A material not written whole for a second is
-- written whole again, so that a change made from outside (a reload of the materials) cannot stay for long.
local REFRESH = 1
local written = setmetatable({}, {__mode = "k"})

local function setConstants(material, constants)
	local last = written[material]
	local now = RealTime()

	if not last or now - last.stamp >= REFRESH then
		last = {stamp = now}
		written[material] = last
	end

	for r = 1, 3 do
		local row, names = constants[r], NAMES[r]

		for i = 1, 4 do
			local value, key = row[i], names[i]

			if last[key] ~= value then
				material:SetFloat(key, value)
				last[key] = value
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The materials: one for each part of a model
--------------------------------------------------------------------------------------------------------------------

local parts = {}

-- The material that draws the layer over a part of a model whose own material is `path`, with that material's relief map. Made once.
function R.Part(path)
	local name = R.prefix .. "_" .. R.PIXEL .. "_" .. R.VERTEX .. "_" .. string.gsub(path, "[^%w]", "_")
	local part = parts[name]

	if part then
		return part
	end

	local bump, tiling = R.BUMP, R.GENERIC_TILING
	local source = Material(path)
	local texture = source and not source:IsError() and source:GetTexture("$bumpmap")

	if texture and not texture:IsErrorTexture() then
		bump, tiling = texture:GetName(), 1
	end

	part = {
		tiling = tiling,
		material = CreateMaterial(name, "screenspace_general", {
			["$pixshader"] = R.PIXEL,
			["$vertexshader"] = R.VERTEX,
			["$basetexture"] = R.SCREEN,
			["$texture1"] = bump,
			["$texture2"] = R.PALETTE,
			["$texture3"] = R.INTERLATION,
			["$linearread_basetexture"] = "0",
			["$linearread_texture1"] = "1",
			["$linearread_texture2"] = "1",
			["$linearread_texture3"] = "1",
			["$model"] = "1",
			["$softwareskin"] = "1",
			["$vertexnormal"] = "1",
			["$alphablend"] = "1",
			["$cull"] = "1",
			["$depthtest"] = "1",
			["$c0_x"] = "1", ["$c0_y"] = "0", ["$c0_z"] = "0.2", ["$c0_w"] = "4",
			["$c1_x"] = "0", ["$c1_y"] = "0.0001", ["$c1_z"] = "0.0001", ["$c1_w"] = "52.49",
			["$c2_x"] = tostring(tiling), ["$c2_y"] = "1", ["$c2_z"] = "0", ["$c2_w"] = "0"
		})
	}
	parts[name] = part

	return part
end

--------------------------------------------------------------------------------------------------------------------
-- The test draw
--------------------------------------------------------------------------------------------------------------------

-- A plate seen from above in a 64 x 64 render target cleared to red, drawn twice with the layer: at alpha 0 it must leave the red as it was
-- (nothing is added to what is behind), at alpha 1 it must show the picture behind (any colour but the red it was cleared to). A shader the game
-- does not have fails one or the other: the engine draws pure white whatever the alpha (measured), or nothing, or its flat magenta (the first
-- material with that name); Material:IsError() says nothing about it. Returns whether the game ran the shader, and the share of the plate that
-- behaved (the smaller of the two draws').
R.PROBE_MODEL = "models/hunter/plates/plate1x1.mdl"
R.PROBE_MATERIAL = "models/debug/debugwhite"
R.PROBE_SIZE = 64
R.PROBE_SHARE = 0.9

local function isBackground(r, g, b)
	return r > 200 and g < 40 and b < 40
end

local function isErrorColour(r, g, b)
	return r > 140 and b > 140 and g < 40 and math.abs(r - b) < 80
end

local function isPicture(r, g, b)
	return not isBackground(r, g, b) and not isErrorColour(r, g, b)
end

-- One draw of the plate at `alpha`, and the share of its pixels that `wanted` accepts.
local function shoot(plate, part, target, alpha, wanted)
	local size = R.PROBE_SIZE
	local share = 0

	setConstants(part.material, R.Constants(1, alpha, 0, size, size, part.tiling))
	render.PushRenderTarget(target)

	local drawn = pcall(function()
		render.Clear(255, 0, 0, 255, true, true)
		cam.Start({type = "3D", origin = Vector(0, 0, 100), angles = Angle(90, 0, 0), x = 0, y = 0, w = size, h = size,
			ortho = {left = -24, right = 24, top = -24, bottom = 24}, znear = 1, zfar = 300})
		render.MaterialOverride(part.material)
		plate:DrawModel()
		render.MaterialOverride(nil)
		cam.End3D()
		render.CapturePixels()

		local accepted, total = 0, 0

		for y = 8, size - 9 do
			for x = 8, size - 9 do
				local r, g, b = render.ReadPixel(x, y)
				total = total + 1

				if wanted(r, g, b) then
					accepted = accepted + 1
				end
			end
		end

		share = accepted / total
	end)

	render.PopRenderTarget()
	render.MaterialOverride(nil)

	return drawn and share or 0
end

function R.Probe()
	local share = 0
	local ok = pcall(function()
		local target = GetRenderTarget("GryCloakRefractProbe", R.PROBE_SIZE, R.PROBE_SIZE)
		local part = R.Part(R.PROBE_MATERIAL)
		local plate = ClientsideModel(R.PROBE_MODEL)
		plate:SetNoDraw(true)
		plate:SetPos(Vector(0, 0, 0))
		plate:SetAngles(Angle(0, 0, 0))

		render.UpdateScreenEffectTexture()

		local untouched = shoot(plate, part, target, 0, isBackground)
		local shown = shoot(plate, part, target, 1, isPicture)

		plate:Remove()
		share = math.min(untouched, shown)
	end)

	R.works = ok and share >= R.PROBE_SHARE

	return R.works, share
end

-- Whether the test draw worked (nil: not made yet).
function R.Works()
	return R.works
end

-- Used when the player wants it and the game can run it.
function R.Active()
	return R.works == true and R.Enabled()
end

--------------------------------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------------------------------

-- Whether the layer leaves a material as it is, in first person (the view model, the hands and the models a weapon draws itself). What the player aims with is not the
-- body of the weapon: the picture of a scope (a render target on its lens), the dot or the reticle of a sight (an unlit material, drawn as it is whatever the light),
-- the glass of a lens. Covered by the refraction they were blurred away and the weapon could not be aimed. The body is an opaque surface lit by the world (a vertex lit
-- material with a texture file) and is covered. So an optic is found by what its materials ARE, for any weapon of any base: no weapon, no attachment and no material is
-- named. A material is kept when it is unlit (a reticle, a holographic sight), translucent or additive (glass: the lens of a red dot sight has its dot painted on a
-- translucent lit material), or when its texture is not a file (a render target, a picture made by the game: no .vtf of that name in the game). A missing material and one
-- with no texture are covered. Answered once for each material.
local FLAG_ADDITIVE, FLAG_TRANSLUCENT = 128, 2097152 -- MATERIAL_VAR_ADDITIVE (1 << 7) and MATERIAL_VAR_TRANSLUCENT (1 << 21) of the engine's material flags
local kept = {}

function R.Keeps(path)
	if not isstring(path) or path == "" then
		return false
	end

	local known = kept[path]

	if known ~= nil then
		return known
	end

	local keeps = false
	local material = Material(path)

	if material and not material:IsError() then
		if material:GetShader() == "UnlitGeneric" or bit.band(material:GetInt("$flags"), FLAG_ADDITIVE + FLAG_TRANSLUCENT) ~= 0 then
			keeps = true
		else
			local texture = material:GetTexture("$basetexture")

			if texture and not texture:IsErrorTexture() and not file.Exists("materials/" .. texture:GetName() .. ".vtf", "GAME") then
				keeps = true
			end
		end
	end

	kept[path] = keeps

	return keeps
end

-- The parts (one for each material of the model) of an entity, resolved once for each model, and the list of the materials that are kept (false when there is none).
local modelParts, modelKept = {}, {}

local function partsOf(ent)
	local key = R.PIXEL .. R.VERTEX .. ent:GetModel()
	local list = modelParts[key]

	if not list then
		list = {}

		local keptList, any = {}, false

		for index, path in ipairs(ent:GetMaterials()) do
			local keeps = R.Keeps(path) == true

			list[index] = R.Part(path)
			keptList[index] = keeps
			any = any or keeps
		end

		modelParts[key] = list
		modelKept[key] = any and keptList or false
	end

	return list, modelKept[key]
end

-- The materials of a model that the layers leave as they are (one entry for each material, true for a kept one), or nil when the model has none.
function R.KeptParts(ent)
	local _, keptList = partsOf(ent)

	return keptList or nil
end

-- Draws `ent` through the layer: the bend (`bump`, from R.BumpScale of the cloak's level) and the alpha (R.Alpha of the plain model's opacity). The
-- picture behind has to be copied before the model is drawn (render.UpdateScreenEffectTexture). `draw` draws the entity in a way its own draw
-- hook lets through (cl_cloak_fx.lua). Every part of the model has its own material for the length of the draw; whatever happens the overrides come
-- off. `keep` (first person: the view model, the hands, the parts of a weapon) leaves the materials that R.Keeps names as they are. Returns whether it drew.
local drawConstants

function R.Draw(ent, bump, alpha, draw, keep)
	if not R.Active() or alpha < R.MIN_ALPHA or not IsValid(ent) then return false end

	local list, keptList = partsOf(ent)

	if not keep then
		keptList = nil
	end

	local curtime, w, h = CurTime(), ScrW(), ScrH()

	-- the same numbers for every part but the tiling of its relief map: one set of tables, kept from a draw to the next, with the tiling put in for each part
	local constants = R.Constants(bump, alpha, curtime, w, h, 1, drawConstants)
	drawConstants = constants

	for index, part in ipairs(list) do
		if not (keptList and keptList[index]) then
			constants[3][1] = part.tiling
			setConstants(part.material, constants)
			render.MaterialOverrideByIndex(index - 1, part.material)
		end
	end

	local ok = pcall(draw or ent.DrawModel, ent)

	for index in ipairs(list) do
		render.MaterialOverrideByIndex(index - 1, nil)
	end

	return ok
end

-- The test draw is made once, a little after the map is up (a render target is needed, and the shaders and textures have to be there), and only
-- when the player wants the layer. A little after the sparks' own (cl_cloak_shader.lua). It is made from a Think of the game, so a
-- Think hook waits for the time, and it does not stay: it takes itself away when the test is made or when the option is off, and a
-- callback on the option puts it back if the test is still to be made (the file is loaded again on every map, and the state of the test
-- starts over with it).
local PROBE_DELAY = 3.5
local PROBE_HOOK = "GryCloakRefractProbe"
local readyAt

local function stopWaiting()
	hook.Remove("Think", PROBE_HOOK)
end

local function wait()
	if R.works ~= nil or not R.Enabled() then return stopWaiting() end
	if not IsValid(LocalPlayer()) then return end

	readyAt = readyAt or CurTime() + PROBE_DELAY

	if CurTime() >= readyAt then
		stopWaiting()
		R.Probe()
	end
end

local function startWaiting()
	if R.works ~= nil or not R.Enabled() then return stopWaiting() end

	hook.Add("Think", PROBE_HOOK, wait)
end

-- Same identifier at every load: the callback is replaced, not added.
cvars.AddChangeCallback("gry_cloak_refract", startWaiting, PROBE_HOOK)
startWaiting()
