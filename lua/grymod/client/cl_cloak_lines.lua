-- The scan lines of the camouflage (client). In the original game the sparks of a camouflaged suit are blotches of electric blue
-- crossed by fine horizontal lines that jump to another place at every frame (the "interlation" of its cloak layer). The model's
-- texture coordinates cannot give horizontal lines on the screen, so they are drawn here in SCREEN space:
--
--   1. the camouflaged player is drawn into the stencil buffer with no colour written (only where it is seen: the depth test
--      is the world's, so what is behind a wall is not marked);
--   2. one textured quad of the picture materials/grymod/cloak/cloak_lines (blotches x lines, made by tools/make_cloak_lines.py)
--      is drawn over the box that holds the player on the screen, added to the picture, only where the stencil is set;
--   3. the stencil and the colour writes are put back, whatever happens in between.
--
-- cl_cloak_fx.lua calls Lines.Draw with the strength of the sparks (they run while the player moves and in a flash at the start
-- of the change) and a function that draws the entity in a way its own hook lets through. One check box: gry_cloak_lines.

GryMod = GryMod or {}

local F = GryMod.CloakFX or {}
GryMod.CloakFX = F

local Lines = F.Lines or {}
F.Lines = Lines

local convar = GetConVar("gry_cloak_lines") or CreateClientConVar("gry_cloak_lines", "1", true, false,
	"1: the sparks of the camouflage are crossed by electric blue scan lines drawn on the screen over the silhouette; 0: no lines", 0, 1)

function Lines.Enabled()
	return convar:GetBool()
end

-- The picture: 512 texels square, one line every PERIOD texels, one texel is one pixel of a 1080 screen.
Lines.TEXTURE = 512
Lines.PERIOD = 4

-- What is added to the box that holds the player's corners, pixels (the model sticks out of its box a little).
Lines.MARGIN = 8

-- Under this size (pixels) the box is not worth drawing.
Lines.MIN_SIZE = 6

-- The drift of the blotches, in pictures per second, and how many times per second the lines jump.
Lines.DRIFT = 0.06
Lines.JUMP_RATE = 30

local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end

	return x
end

-- The box on the screen that holds the corners (a list of {x, y, visible}: visible is false for a corner behind the camera),
-- with a margin, cut at the screen's edges: x, y, width, height in whole pixels, or nil when nothing is to be drawn.
function Lines.Rect(points, screenW, screenH)
	local minX, minY, maxX, maxY

	for _, p in ipairs(points) do
		if p.visible then
			minX = minX and math.min(minX, p.x) or p.x
			maxX = maxX and math.max(maxX, p.x) or p.x
			minY = minY and math.min(minY, p.y) or p.y
			maxY = maxY and math.max(maxY, p.y) or p.y
		end
	end

	if not minX then return nil end

	local x0 = math.max(0, math.floor(minX - Lines.MARGIN))
	local y0 = math.max(0, math.floor(minY - Lines.MARGIN))
	local x1 = math.min(screenW, math.ceil(maxX + Lines.MARGIN))
	local y1 = math.min(screenH, math.ceil(maxY + Lines.MARGIN))

	if x1 - x0 < Lines.MIN_SIZE or y1 - y0 < Lines.MIN_SIZE then return nil end

	return x0, y0, x1 - x0, y1 - y0
end

-- Where the picture starts, for this frame: the lines jump by a whole number of periods (so that they never blur), the
-- blotches slide along slowly. Same frame and time, same answer.
function Lines.Offset(frame, time)
	local stepCount = Lines.TEXTURE / Lines.PERIOD
	-- a cheap hash of the frame number: the same frame always jumps to the same line
	local h = (frame * 2654435761) % 4294967296
	local jump = math.floor(h / 65536) % stepCount

	return (time * Lines.DRIFT) % 1, jump * Lines.PERIOD / Lines.TEXTURE
end

-- The texture coordinates of a box w x h pixels, starting at the offset (u, v), on a screen screenH pixels high: one texel is
-- one pixel at 1080, so the picture grows with the screen and the lines keep their look.
function Lines.UV(w, h, screenH, u, v)
	local scale = screenH / 1080

	return u, v, u + w / (Lines.TEXTURE * scale), v + h / (Lines.TEXTURE * scale)
end

-- The brightness of the lines for a strength of the sparks (0 to 1).
Lines.GAIN = 1

function Lines.Alpha(strength)
	return clamp01(strength * Lines.GAIN)
end

-- The corners of the entity's box on the screen, for Rect.
function Lines.ScreenPoints(ent)
	local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	local points = {}

	for i = 0, 7 do
		local corner = Vector(i % 2 == 0 and mins.x or maxs.x, math.floor(i / 2) % 2 == 0 and mins.y or maxs.y, i < 4 and mins.z or maxs.z)
		local screen = ent:LocalToWorld(corner):ToScreen()
		points[#points + 1] = {x = screen.x, y = screen.y, visible = screen.visible}
	end

	return points
end

local material

local function lineMaterial()
	material = material or Material("grymod/cloak/cloak_lines")

	return material
end

local frame = 0

-- Draws the lines over the entity. `draw(ent)` draws the entity's model (it is called once, with the colours off). Returns true
-- when something was drawn (or nothing was to be), and false and the error when the drawing failed: the state is back anyway.
function Lines.Draw(ent, strength, draw)
	if not Lines.Enabled() then return true end

	local alpha = Lines.Alpha(strength)

	if alpha <= 0 then return true end

	local w, h = ScrW(), ScrH()
	local x, y, bw, bh = Lines.Rect(Lines.ScreenPoints(ent), w, h)

	if not x then return true end

	frame = frame + 1
	local in2D = false

	local ok, err = pcall(function()
		-- 1. the silhouette into the stencil
		render.SetStencilEnable(true)
		render.SetStencilWriteMask(255)
		render.SetStencilTestMask(255)
		render.SetStencilReferenceValue(1)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilPassOperation(STENCIL_REPLACE)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.ClearStencilBufferRectangle(x, y, x + bw, y + bh, 0)
		render.OverrideColorWriteEnable(true, false)
		draw(ent)
		render.OverrideColorWriteEnable(false, false)

		-- 2. the lines, only where the stencil is set
		render.SetStencilCompareFunction(STENCIL_EQUAL)
		render.SetStencilPassOperation(STENCIL_KEEP)

		local u, v = Lines.Offset(frame, RealTime())
		local u0, v0, u1, v1 = Lines.UV(bw, bh, h, u, v)
		local level = math.floor(255 * alpha + 0.5)

		cam.Start2D()
		in2D = true
		surface.SetMaterial(lineMaterial())
		surface.SetDrawColor(level, level, level, 255)
		surface.DrawTexturedRectUV(x, y, bw, bh, u0, v0, u1, v1)
		cam.End2D()
		in2D = false
	end)

	-- 3. whatever happened: a 2D context that was opened is closed, the stencil and the colours are back
	if in2D then
		cam.End2D()
	end

	render.OverrideColorWriteEnable(false, false)
	render.SetStencilEnable(false)

	if not ok then
		return false, err
	end

	return true
end
