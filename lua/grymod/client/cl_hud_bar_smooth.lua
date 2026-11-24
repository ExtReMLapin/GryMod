-- Smooth energy bars: the suit's energy bar and the night vision's energy bar drawn at the exact fraction of a step, not at whole percents.
--
-- The movies draw a bar at one frame of 100, a frame is one percent, and on a screen where a bar is more than 100 pixels wide a step is more than a pixel
-- (1.2 px at 1280 x 720, 1.8 at 1920 x 1080 for the suit's bar; 1.4 and 2.1 for the night vision's): the bar is seen to jump. The values themselves are
-- floats that move at every frame (cl_energy_smooth.lua for the suit, NV.Bar for the night vision); only the drawing quantised them.
--
-- The way (the whole idea and its pure part are in sh_flash_bar.lua, tested outside the game): the bar is drawn at its integer frame, as it always was, and a
-- second clip of the same kind is kept at the next frame; the player (cl_flash_draw.lua) draws the cached image of each, the first on the track side of a
-- vertical line and the second on the fill side, and the line is at the x between the two frames' fill edges that the fraction says. Nothing is rebuilt: a
-- paint is two cut quads, the images are made only when a frame changes (twice: the clip's and its clone's), no table and no polygon is made at a frame.
-- The colours (the red of a low night vision energy, the theme's), the segments and the additive blend are the integer frames' own. When a step is a pixel or
-- less (a small screen) or the setting gry_hud_bar_smooth is off, the bar is drawn as before: the frame, rounded down, and no second image.
--
-- No hook and no Think: the HUD's paint calls Apply for the bar when it gives it its value.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Smooth = GryMod.FlashBarSmooth or {}
GryMod.FlashBarSmooth = Smooth

local Math = include("grymod/sh_flash_bar.lua")
Smooth.Math = Math

local STAGE_H = 768

-- Whether the setting gry_hud_bar_smooth is on (it is one of the HUD elements: cl_hud_options.lua).
function Smooth.Enabled()
	return GryMod.HUDOptions == nil or GryMod.HUDOptions.Enabled("bar_smooth")
end

-- The edges of the bar clip `mask`'s sprite, read once from its movie (kept with the sprite's definition; false when it has no mask).
function Smooth.EdgesOf(mask)
	local movie = mask.movie
	local definition = movie.chars[mask.id]

	if not definition then
		return nil
	end

	local edges = definition.barEdges

	if edges == nil then
		edges = Math.Edges(definition, movie.chars) or false
		definition.barEdges = edges
	end

	return edges or nil
end

-- A bar: `group` is the clip the player draws as one image (the one with the blend mode), `mask` the clip that holds the mask (the same clip, or one inside
-- it), `offset` the value's offset on the frames (Math.Position). `cloneGroup` and `cloneMask` are the same clips of a second copy of the clip, kept at the
-- next frame; when they are not given the copy is made from the clip (a clip of the same sprite) at the first fraction. Returns nil for a clip that has no mask.
function Smooth.New(group, mask, offset, cloneGroup, cloneMask)
	local edges = Smooth.EdgesOf(mask)

	if not edges then
		return nil
	end

	return {group = group, mask = mask, offset = offset or 0, edges = edges, cloneGroup = cloneGroup, cloneMask = cloneMask}
end

-- A bar that is one clip, which is the group and holds the mask: the suit's energy bar. Its clone is made when it is first needed.
function Smooth.ForClip(clip, offset)
	return Smooth.New(clip, clip, offset)
end

-- The width of one step of the bar on the screen, in pixels (the clip's scale on the stage, and the stage as high as the screen).
function Smooth.StepPixels(bar, screenHeight)
	return bar.edges.step * bar.mask:ScaleX() * (screenHeight or ScrH()) / STAGE_H
end

-- The cut and the frames for a value of the bar. Gives the frame and the fraction (tests); the clip is moved to its frame as the original did (the value
-- rounded down) when nothing is smoothed.
function Smooth.Apply(bar, value, screenHeight)
	local edges, mask, group = bar.edges, bar.mask, bar.group
	local divisions = 1

	if Smooth.Enabled() then
		divisions = Math.Subdivisions(Smooth.StepPixels(bar, screenHeight))
	end

	local frame, fraction = Math.Split(Math.Quantise(Math.Position(value, bar.offset, edges.n), divisions), edges.n)

	if mask:CurrentFrame() ~= frame then
		mask:GotoAndStop(frame)
	end

	if fraction == 0 then
		if group.cutClone then
			group:ClearCut()
		end

		return frame, 0
	end

	if not bar.cloneMask then
		-- the clone of a clip that is its own group: a clip of the same sprite, in the same colours (the colour-set scripts run when it is made)
		local clone = Flash.NewClip(group.movie, group.id, group.theme)

		bar.cloneGroup, bar.cloneMask = clone, clone
	end

	if bar.cloneMask:CurrentFrame() ~= frame + 1 then
		bar.cloneMask:GotoAndStop(frame + 1)
	end

	local x, y = Math.Cut(edges, frame, fraction), edges.y

	if mask ~= group then
		x, y = mask:PointIn(group, x, y)
	end

	group:SetCut(x, y, edges.side, bar.cloneGroup)

	return frame, fraction
end

-- Puts the bar back as the original draws it (the cut line off): the setting went off, the bar is given back.
function Smooth.Clear(bar)
	if bar and bar.group.cutClone then
		bar.group:ClearCut()
	end
end
