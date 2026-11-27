-- The camouflage's electric sparks, drawn by the original game's own pixel shader (client).
--
-- In Crysis the sparks of a camouflaged suit are the second pass of its cloak shader (CloakLayer.cfx, CloakSparksPS): the 128 cube of 3D
-- noise is read three times in a chain, the result indexes a 256 colour profile at three offsets, and the sum, squared, is multiplied by a
-- triangle wave of the screen row (the scan lines) and by max(speed, transition ^ 2). Source cannot run that with its stock materials, but
-- a custom pixel shader can be shipped since March 2025 (shaders/fxc/*.vcs): dev_resources/shaders/grymod_cloak_*.hlsl is the port, compiled by
-- dev_resources/shaders/build_shaders.py, and the textures it reads (a real volume texture, the profile) come from dev_resources/shaders/make_cloak_shader_textures.py.
--
-- This file gives the shader what the original's engine gave it (the time, the variation, the strength, the random offset of the scan
-- lines) and draws the entity through it, added to the picture. The game may not be able to run it (another graphics level, a driver),
-- so at the start a plate is drawn into a small render target and its pixels read back (Probe): a shader the game does not have draws
-- nothing, and then cl_cloak_fx.lua keeps the older approximation (the edge layer and cl_cloak_lines.lua). One check box: gry_cloak_shader.

GryMod = GryMod or {}

local F = GryMod.CloakFX or {}
GryMod.CloakFX = F

local Sh = F.Shader or {}
F.Shader = Sh

local convar = GetConVar("gry_cloak_shader") or CreateClientConVar("gry_cloak_shader", "1", true, false,
	"1: the sparks of the camouflage are drawn by the original game's own pixel shader (when the game can run it); 0: the older approximation", 0, 1)

-- The names of the shader files (shaders/fxc), of the material that runs them and of the two textures it reads. The game keeps the code
-- of a shader name until it is closed: to try another build, give the new files another name here before the first draw.
Sh.PIXEL = Sh.PIXEL or "grymod_cloak_ps30"
Sh.VERTEX = Sh.VERTEX or "grymod_cloak_vs30"
Sh.NOISE = "grymod/cloak/noise3d"
Sh.PROFILE = "grymod/cloak/spark_profile"
Sh.materialName = Sh.materialName or "GryCloakSparksShader"

-- Model units to one volume of noise: the original's coordinates are the model's own in metres (a metre is 52.49 units).
Sh.UNITS = 52.49

-- The original's time (AnimGenParams) runs at 0.4 of the game's. It wraps at 5, a whole number of periods of the three lookups (1, 0.5 and
-- 1 / 1.4), so that its precision does not wear out in a long session. Each entity gets its own shift so that two players do not spark in step.
Sh.TIME_SCALE = 0.4
Sh.TIME_WRAP = 5
Sh.ENTITY_SHIFT = 0.137

-- The sparks' colour (the original's SparksColor), which the pixel shader holds itself; here only to tell the sparks from the engine's error colour.
Sh.COLOR = {0.3, 0.3, 1}

-- The scan lines: four screen rows to a period in the original (at its 1080 line pictures), more on a taller screen so that they look the
-- same; they jump to another place 30 times a second.
Sh.ROWS = 4
Sh.JUMP_RATE = 30

-- Under this strength nothing is drawn.
Sh.MIN_STRENGTH = 0.01

-- The pattern's drift while the player moves. The original shifted the green lookup by the distance to the world origin, 0.1 of a profile length per
-- METRE: in the game's units that was 52 times more, and walking made the pattern run 25 times faster, one way or the other. The drift is now
-- given by the Lua (the fourth component of the colour register): 0.1 per metre a second as the original meant it, and never more than the
-- rest rate of the animation (the green lookup runs at 2 x TIME_SCALE a second), so that the sparks run twice as fast at most.
Sh.DRIFT_GAIN = 0.1
Sh.DRIFT_CAP = 2 * Sh.TIME_SCALE

-- The longest frame that counts for the drift (a pause or a loading screen is no movement).
Sh.DRIFT_MAX_STEP = 0.1

function Sh.Enabled()
	return convar:GetBool()
end

--------------------------------------------------------------------------------------------------------------------
-- What the shader is given (pure functions)
--------------------------------------------------------------------------------------------------------------------

-- The shader's time for the game's time, for an entity.
function Sh.Time(curtime, index)
	return (curtime * Sh.TIME_SCALE + (index or 0) * Sh.ENTITY_SHIFT) % Sh.TIME_WRAP
end

-- How far the lookups of the noise are moved (vConstants of the original, with no speed term: the strength is given separately): it moves with
-- the frac of the time while the camouflage is not complete, and goes down to a small steady value.
function Sh.Variation(time, amount)
	local rest = 1 - amount

	return (time % 1) * 2 * 0.1 * rest, 0.1 * math.max(rest * 0.2, 0.1)
end

function Sh.RowPeriod(screenHeight)
	return Sh.ROWS * math.max(1, screenHeight / 1080)
end

-- A whole number of rows, from 0 to period - 1, that changes JUMP_RATE times a second (the original's random offset of the scan lines).
function Sh.RowOffset(curtime, period)
	local frame = math.floor(curtime * Sh.JUMP_RATE)
	local random = (math.sin(frame * 12.9898) * 43758.5453) % 1

	return math.floor(random * period)
end

-- How fast the pattern drifts for a player moving at `speed` units a second, in profile lengths a second.
function Sh.DriftRate(speed)
	if not (speed > 0) then return 0 end

	return math.min(speed / Sh.UNITS * Sh.DRIFT_GAIN, Sh.DRIFT_CAP)
end

-- The one whose movement an entity follows: the player, the owner of his weapon, and for the view model and the hands (no owner of their own
-- worth the name) the local player.
local function ownerOf(ent)
	if ent.IsPlayer and ent:IsPlayer() then return ent end

	local owner = ent.GetOwner and ent:GetOwner()

	if IsValid(owner) and owner.IsPlayer and owner:IsPlayer() then return owner end

	return LocalPlayer()
end

local drifts = setmetatable({}, {__mode = "k"})

-- The phase of the drift for an entity (0 up to 1, the profile repeats), advanced once per frame whatever the number of draws (the body, the
-- weapon, a mirror) by the owner's speed at the capped rate.
function Sh.Drift(ent)
	local owner = ownerOf(ent)

	if not IsValid(owner) then return 0 end

	local frame, now = FrameNumber(), CurTime()
	local state = drifts[owner]

	if not state then
		state = {phase = 0, frame = frame, time = now}
		drifts[owner] = state
	elseif state.frame ~= frame then
		local step = math.min(math.max(now - state.time, 0), Sh.DRIFT_MAX_STEP)
		state.phase = (state.phase + Sh.DriftRate(owner:GetVelocity():Length2D()) * step) % 1
		state.frame, state.time = frame, now
	end

	return state.phase
end

-- The four constant registers: {{units per volume, time, strength, rows to a period}, {variation x, variation y, row offset, 0},
-- {the entity's angles in radians: pitch, yaw, roll; the drift}, {the entity's origin, 0}}. The vertex position the engine hands to the shader is in the
-- WORLD (measured: a plate moved elsewhere showed another pattern, a plate turned a quarter the same one), so a pattern read from it stayed put in the world
-- and a walking player slid through it: the shader reads it relative to the entity's own origin and angles (as the original's object space is).
-- `into` (optional) is the result of an earlier call, filled again instead of making new tables.
function Sh.Constants(curtime, amount, strength, screenHeight, index, drift, pos, ang, into)
	local time = Sh.Time(curtime, index)
	local vx, vy = Sh.Variation(time, amount)
	local period = Sh.RowPeriod(screenHeight)
	local c = into or {{}, {}, {}, {}}
	local r1, r2, r3, r4 = c[1], c[2], c[3], c[4]

	r1[1], r1[2], r1[3], r1[4] = Sh.UNITS, time, strength, period
	r2[1], r2[2], r2[3], r2[4] = vx, vy, Sh.RowOffset(curtime, period), 0
	r3[1], r3[2], r3[3], r3[4] = ang and math.rad(ang.p) or 0, ang and math.rad(ang.y) or 0, ang and math.rad(ang.r) or 0, drift or 0
	r4[1], r4[2], r4[3], r4[4] = pos and pos.x or 0, pos and pos.y or 0, pos and pos.z or 0, 0

	return c
end

local REGISTERS = {"x", "y", "z", "w"}

-- the names of the material's sixteen parameters, made once
local NAMES = {}

for r = 1, 4 do
	NAMES[r] = {}

	for i = 1, 4 do
		NAMES[r][i] = "$c" .. (r - 1) .. "_" .. REGISTERS[i]
	end
end

-- What a material was last given: every SetFloat goes through the engine and part of the constants are the same from one draw to the next (the
-- period, the units, the strength, the variation once the change is done). A material not written whole for a second is written whole again, so
-- that a change made from outside (a reload of the materials) cannot stay for long.
local REFRESH = 1
local written = setmetatable({}, {__mode = "k"})

local function setConstants(material, constants)
	local last = written[material]
	local now = RealTime()

	if not last or now - last.stamp >= REFRESH then
		last = {stamp = now}
		written[material] = last
	end

	for r = 1, #constants do
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
-- The material, the test draw
--------------------------------------------------------------------------------------------------------------------

-- The material that runs the shader. The two textures are DATA the shader calculates with, so they are read as they are (no sRGB
-- conversion): $linearread_*. It is added to the picture, and tested against the depth of the scene.
function Sh.Material()
	if not Sh.material then
		Sh.material = CreateMaterial(Sh.materialName, "screenspace_general", {
			["$pixshader"] = Sh.PIXEL,
			["$vertexshader"] = Sh.VERTEX,
			["$basetexture"] = Sh.NOISE,
			["$texture1"] = Sh.PROFILE,
			["$linearread_basetexture"] = "1",
			["$linearread_texture1"] = "1",
			["$model"] = "1",
			["$softwareskin"] = "1",
			["$vertexnormal"] = "1",
			["$additive"] = "1",
			["$cull"] = "1",
			["$depthtest"] = "1",
			["$c0_x"] = "52.49", ["$c0_y"] = "0", ["$c0_z"] = "0", ["$c0_w"] = "4",
			["$c1_x"] = "0", ["$c1_y"] = "0", ["$c1_z"] = "0", ["$c1_w"] = "0",
			["$c2_x"] = "0", ["$c2_y"] = "0", ["$c2_z"] = "0", ["$c2_w"] = "0",
			["$c3_x"] = "0", ["$c3_y"] = "0", ["$c3_z"] = "0", ["$c3_w"] = "0"
		})
	end

	return Sh.material
end

-- The test draw: a plate seen from above in a 64 x 64 render target, with constants that make the sparks show (measured: 183 blue pixels
-- of 4096). Returns whether the game ran the shader, and how many blue pixels there were. Material:IsError() says nothing about a shader
-- the game does not have; what is drawn instead is either nothing (black) or, for the first material with that name, the engine's flat
-- magenta: neither has blue sparks.
Sh.PROBE_MODEL = "models/hunter/plates/plate1x1.mdl"
Sh.PROBE_SIZE = 64
Sh.PROBE_LIT = 20
Sh.PROBE_LEVEL = 30

function Sh.Probe()
	local lit = 0
	local ok = pcall(function()
		local size = Sh.PROBE_SIZE
		local target = GetRenderTarget("GryCloakShaderProbe", size, size)
		local material = Sh.Material()
		local plate = ClientsideModel(Sh.PROBE_MODEL)
		plate:SetNoDraw(true)
		plate:SetPos(Vector(0, 0, 0))
		plate:SetAngles(Angle(0, 0, 0))

		setConstants(material, {{Sh.UNITS, 0.37, 1, 4}, {0.05, 0.02, 1, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}})

		render.PushRenderTarget(target)

		local drawn = pcall(function()
			render.Clear(0, 0, 0, 255, true, true)
			cam.Start({type = "3D", origin = Vector(0, 0, 100), angles = Angle(90, 0, 0), x = 0, y = 0, w = size, h = size,
				ortho = {left = -24, right = 24, top = -24, bottom = 24}, znear = 1, zfar = 300})
			render.MaterialOverride(material)
			plate:DrawModel()
			render.MaterialOverride(nil)
			cam.End3D()
			render.CapturePixels()

			for y = 0, size - 1 do
				for x = 0, size - 1 do
					local r, g, b = render.ReadPixel(x, y)

					-- the sparks are blue (red is 9 % of blue); the engine's error colour is magenta (measured 194, 0, 194)
					if b > Sh.PROBE_LEVEL and b > r * 2 then
						lit = lit + 1
					end
				end
			end
		end)

		render.PopRenderTarget()
		render.MaterialOverride(nil)
		plate:Remove()

		if not drawn then
			lit = 0
		end
	end)

	Sh.works = ok and lit >= Sh.PROBE_LIT

	return Sh.works, lit
end

-- Whether the test draw worked (nil: not made yet).
function Sh.Works()
	return Sh.works
end

-- Used when the player wants it and the game can run it.
function Sh.Active()
	return Sh.works == true and Sh.Enabled()
end

--------------------------------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------------------------------

-- Draws `ent` through the shader, added to the picture, with the strength of the sparks (0 to 1; the original's max(speed, transition ^ 2))
-- and the camouflage's level `amount` (0 to 1). `draw` draws the entity in a way its own draw hook lets through (cl_cloak_fx.lua).
-- Whatever happens, the material override comes off. `keep` (first person) leaves the materials that the refraction layer keeps (the picture of a scope, the dot of a
-- sight: GryMod.CloakFX.Refract.Keeps) without sparks. Returns whether it drew.
local drawConstants

function Sh.Draw(ent, strength, amount, draw, keep)
	if not Sh.Active() or strength < Sh.MIN_STRENGTH or not IsValid(ent) then return false end

	local material = Sh.Material()

	-- (the tables are kept from a draw to the next: nothing is made for each draw)
	drawConstants = Sh.Constants(CurTime(), amount, strength, ScrH(), ent:EntIndex(), Sh.Drift(ent), ent:GetPos(), ent:GetAngles(), drawConstants)
	setConstants(material, drawConstants)

	-- a model with something to keep gets the material part by part; any other model, and the third person, the one override as before
	local Refract = GryMod.CloakFX and GryMod.CloakFX.Refract
	local keptList = keep and Refract and Refract.KeptParts and Refract.KeptParts(ent) or nil

	local ok = pcall(function()
		if keptList then
			for index = 1, #keptList do
				if not keptList[index] then
					render.MaterialOverrideByIndex(index - 1, material)
				end
			end
		else
			render.MaterialOverride(material)
		end

		draw(ent)
	end)

	render.MaterialOverride(nil)

	if keptList then
		for index = 1, #keptList do
			render.MaterialOverrideByIndex(index - 1, nil)
		end
	end

	return ok
end

-- The test draw is made once, a little after the map is up (a render target is needed, and the shaders and textures have to be there), and
-- only when the player wants the shader. It is made from a Think of the game, so a Think hook waits for the time, and it does not stay:
-- it takes itself away when the test is made or when the option is off, and a callback on the option puts it back if the test is still to
-- be made (the file is loaded again on every map, and the state of the test starts over with it).
local PROBE_DELAY = 3
local PROBE_HOOK = "GryCloakShaderProbe"
local readyAt

local function stopWaiting()
	hook.Remove("Think", PROBE_HOOK)
end

local function wait()
	if Sh.works ~= nil or not Sh.Enabled() then return stopWaiting() end
	if not IsValid(LocalPlayer()) then return end

	readyAt = readyAt or CurTime() + PROBE_DELAY

	if CurTime() >= readyAt then
		stopWaiting()
		Sh.Probe()
	end
end

local function startWaiting()
	if Sh.works ~= nil or not Sh.Enabled() then return stopWaiting() end

	hook.Add("Think", PROBE_HOOK, wait)
end

-- Same identifier at every load: the callback is replaced, not added.
cvars.AddChangeCallback("gry_cloak_shader", startWaiting, PROBE_HOOK)
startWaiting()
