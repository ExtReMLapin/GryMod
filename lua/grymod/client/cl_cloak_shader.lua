-- The camouflage's electric sparks, drawn by the original game's own pixel shader (client).
--
-- In Crysis the sparks of a camouflaged suit are the second pass of its cloak shader (CloakLayer.cfx, CloakSparksPS): the 128 cube of 3D
-- noise is read three times in a chain, the result indexes a 256 colour profile at three offsets, and the sum, squared, is multiplied by a
-- triangle wave of the screen row (the scan lines) and by max(speed, transition ^ 2). Source cannot run that with its stock materials, but
-- a custom pixel shader can be shipped since March 2025 (shaders/fxc/*.vcs): shaders/src/grymod_cloak_*.hlsl is the port, compiled by
-- tools/build_shaders.py, and the textures it reads (a real volume texture, the profile) come from tools/make_cloak_shader_textures.py.
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

-- The sparks' colour (the original's SparksColor).
Sh.COLOR = {0.3, 0.3, 1}

-- The scan lines: four screen rows to a period in the original (at its 1080 line pictures), more on a taller screen so that they look the
-- same; they jump to another place 30 times a second.
Sh.ROWS = 4
Sh.JUMP_RATE = 30

-- Under this strength nothing is drawn.
Sh.MIN_STRENGTH = 0.01

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

-- The three constant registers: {{units per volume, time, strength, rows to a period}, {variation x, variation y, row offset, 0}, {colour, 0}}.
function Sh.Constants(curtime, amount, strength, screenHeight, index)
	local time = Sh.Time(curtime, index)
	local vx, vy = Sh.Variation(time, amount)
	local period = Sh.RowPeriod(screenHeight)

	return {
		{Sh.UNITS, time, strength, period},
		{vx, vy, Sh.RowOffset(curtime, period), 0},
		{Sh.COLOR[1], Sh.COLOR[2], Sh.COLOR[3], 0}
	}
end

local REGISTERS = {"x", "y", "z", "w"}

local function setConstants(material, constants)
	for r = 1, 3 do
		for i = 1, 4 do
			material:SetFloat("$c" .. (r - 1) .. "_" .. REGISTERS[i], constants[r][i])
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
			["$c2_x"] = "0.3", ["$c2_y"] = "0.3", ["$c2_z"] = "1", ["$c2_w"] = "0"
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

		setConstants(material, {{Sh.UNITS, 0.37, 1, 4}, {0.05, 0.02, 1, 0}, {Sh.COLOR[1], Sh.COLOR[2], Sh.COLOR[3], 0}})

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
-- Whatever happens, the material override comes off. Returns whether it drew.
function Sh.Draw(ent, strength, amount, draw)
	if not Sh.Active() or strength < Sh.MIN_STRENGTH or not IsValid(ent) then return false end

	local material = Sh.Material()

	setConstants(material, Sh.Constants(CurTime(), amount, strength, ScrH(), ent:EntIndex()))

	local ok = pcall(function()
		render.MaterialOverride(material)
		draw(ent)
	end)

	render.MaterialOverride(nil)

	return ok
end

-- The test draw is made once, a little after the map is up (a render target is needed, and the shaders and textures have to be there), and
-- only when the player wants the shader.
local PROBE_DELAY = 3
local readyAt

hook.Add("Think", "GryCloakShaderProbe", function()
	if Sh.works ~= nil or not Sh.Enabled() or not IsValid(LocalPlayer()) then return end

	readyAt = readyAt or CurTime() + PROBE_DELAY

	if CurTime() >= readyAt then
		Sh.Probe()
	end
end)
