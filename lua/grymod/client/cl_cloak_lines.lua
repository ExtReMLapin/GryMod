-- The scan lines of the camouflage (client). In the original game the sparks of a camouflaged suit are blotches of electric blue
-- crossed by fine horizontal lines that jump to another place at every frame (the "interlation" of its cloak layer). The model's
-- texture coordinates cannot give horizontal lines on the screen, so they are drawn here in SCREEN space:
--
--   1. the camouflaged player is drawn into the stencil buffer with no colour written (only where it is seen: the depth test
--      is the world's, so what is behind a wall is not marked);
--   2. the picture materials/grymod/cloak/cloak_sparks, made by dev_resources/cloak/make_cloak_sparks.py from the original game's own textures
--      (the shader CloakLayer.cfx: the 3D noise read through the spark profile, times the interlation, a triangle wave four screen
--      rows to a period), is laid over the box that holds the player on the screen, added to the picture, only where the stencil is
--      set. The picture is 8 cells side by side, one for each eighth of the change (the noise moves with it);
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

-- The picture: FRAMES cells of CELL texels square side by side (4096 x 512), one texel is one pixel of a 2160 screen (the lines of the
-- interlation are PERIOD pixels to a period there, as in the original; half a pixel to a texel at 1080); the cells follow each other
-- RATE a second, in turn, so that the sparks never stand still.
Lines.CELL = 512
Lines.FRAMES = 8
Lines.PERIOD = 4
Lines.RATE = 30

-- The colour the intensity picture is given: the shader's SparksColor (0.3, 0.3, 1) squared is nearly pure blue; the video's own
-- grading (measured on a capture of the original: about 44, 54, 255 in the middle of a patch) lifts the red and the green a little.
Lines.TINT = {0.2, 0.25, 1}

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

-- Where the tiles start, for this frame, in pixels at 2160: the lines jump by a whole number of rows from 0 to PERIOD - 1 (the shader reads
-- the interlation at a random offset at every frame; the four rows of its period make four different pictures), the patches slide
-- along slowly. Same frame and time, same answer.
function Lines.Offset(frame, time)
	-- a cheap hash of the frame number: the same frame always jumps to the same row
	local h = (frame * 2654435761) % 4294967296
	local jump = math.floor(h / 65536) % Lines.PERIOD

	return math.floor(time * Lines.DRIFT * Lines.CELL) % Lines.CELL, jump
end

-- The cell of the picture at this time (seconds): the cells in turn, RATE a second.
function Lines.Cell(time)
	return math.floor(time * Lines.RATE) % Lines.FRAMES
end

-- The quads that lay the cell of `frame` over the box x, y, w, h on a screen screenH pixels high, the cells side by side from the
-- offset (ox, oy given in pixels at 2160): the picture grows with the screen so that the lines keep their look. Each quad is a
-- piece of one cell (a cell is read inside its own bounds): {x, y, w, h, u0, v0, u1, v1}, the quads cover the box exactly.
function Lines.Tiles(x, y, w, h, screenH, ox, oy, frame)
	local scale = screenH / 2160
	local size = Lines.CELL * scale
	local atlasW = Lines.CELL * Lines.FRAMES
	local startX = x - ox * scale
	local startY = y - oy * scale
	local quads = {}

	local firstColumn = math.floor((x - startX) / size)
	local firstRow = math.floor((y - startY) / size)
	local column = firstColumn

	while startX + column * size < x + w do
		local row = firstRow
		local tileX = startX + column * size

		while startY + row * size < y + h do
			local tileY = startY + row * size
			local x0, y0 = math.max(tileX, x), math.max(tileY, y)
			local x1, y1 = math.min(tileX + size, x + w), math.min(tileY + size, y + h)

			if x1 > x0 and y1 > y0 then
				quads[#quads + 1] = {
					x = x0, y = y0, w = x1 - x0, h = y1 - y0,
					u0 = (frame * Lines.CELL + (x0 - tileX) / scale) / atlasW,
					v0 = (y0 - tileY) / scale / Lines.CELL,
					u1 = (frame * Lines.CELL + (x1 - tileX) / scale) / atlasW,
					v1 = (y1 - tileY) / scale / Lines.CELL
				}
			end

			row = row + 1
		end

		column = column + 1
	end

	return quads
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
	material = material or Material("grymod/cloak/cloak_sparks")

	return material
end

local frame = 0

-- Draws the lines over the entity. `draw(ent)` draws the entity's model (it is called once, with the colours off). With `screen`
-- the lines cover the whole screen (only where the model is, still): for the view model and the hands, which are drawn with
-- their own field of view, so that their box cannot be found from the world's camera. Returns true when something was drawn (or
-- nothing was to be), and false and the error when the drawing failed: the state is back anyway.
function Lines.Draw(ent, strength, draw, screen)
	if not Lines.Enabled() then return true end

	local alpha = Lines.Alpha(strength)

	if alpha <= 0 then return true end

	local w, h = ScrW(), ScrH()
	local x, y, bw, bh

	if screen then
		x, y, bw, bh = 0, 0, w, h
	else
		x, y, bw, bh = Lines.Rect(Lines.ScreenPoints(ent), w, h)
	end

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

		local now = RealTime()
		local ox, oy = Lines.Offset(frame, now)
		local cell = Lines.Cell(now)
		local tint = Lines.TINT

		cam.Start2D()
		in2D = true
		surface.SetMaterial(lineMaterial())
		surface.SetDrawColor(math.floor(255 * alpha * tint[1] + 0.5), math.floor(255 * alpha * tint[2] + 0.5), math.floor(255 * alpha * tint[3] + 0.5), 255)

		for _, q in ipairs(Lines.Tiles(x, y, bw, bh, h, ox, oy, cell)) do
			surface.DrawTexturedRectUV(q.x, q.y, q.w, q.h, q.u0, q.v0, q.u1, q.v1)
		end

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
