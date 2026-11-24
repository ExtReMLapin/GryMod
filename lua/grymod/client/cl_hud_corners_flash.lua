-- The two corner marks of the original HUD (movies HUD_Corner_Left and HUD_Corner_Right), see cl_flash.lua: a thin bracket in each top corner of
-- the screen, in the colour of the HUD. The original loads them with the rest of the HUD and nothing hides them (research notes of the audit
-- of the movies); they are a decoration. The movie's one function, destroy(status), puts the mark in the state of the suit: red while the HUD
-- is down, off while it flickers. It is called from the report every other piece listens to (the hook GryMod_HUDStatus), nothing is polled.
--
-- On by default since 2026-11-24 (gry_hud_corners, one of the HUD elements of cl_hud_options.lua; it was off at first, GryMod's HUD never had them). Drawn by the HUD's own paint
-- (cl_hud_flash.lua calls Corners.Paint), so they follow the HUD: gone with it when it is off (gry_hud, the suit off, the player dead), red
-- with it when it goes down, and on the screen as long as the red HUD of a death is.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Corners = {}
GryMod.FlashCorners = Corners

Corners.MOVIES = {left = "hud_corner_left", right = "hud_corner_right"}

-- the instance names of the marks inside the movies' Root clip
local CLIP_NAMES = {left = "Corner_Left", right = "Corner_Right"}

local STAGE_W, STAGE_H = 1024, 768

-- Where the stage of a movie goes on a screen of w x h pixels: x and y of its origin and the scale. The stage is as high as the screen. The left
-- mark's movie is against the left edge of the screen and the right mark's against the right edge, so each mark sits at the same distance
-- from its corner on any aspect ratio (the other panels of the HUD are placed the same way).
function Corners.Placement(side, w, h)
	local scale = h / STAGE_H

	if side == "right" then
		return w - STAGE_W * scale, 0, scale
	end

	return 0, 0, scale
end

local Instance = {}
Instance.__index = Instance

-- A mark from its converted movie (nil when the movie is missing or has no such clip).
function Corners.New(side, movie, theme)
	if not movie or not CLIP_NAMES[side] then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local clip = root:Find("Root." .. CLIP_NAMES[side])

	if not clip then
		return nil
	end

	-- the three clips the colours come from (the movie keeps them above its stage, out of sight): nothing to draw
	for _, name in ipairs({"Line", "Over", "Text"}) do
		local source = root:Child(name)

		if source then
			source:SetVisible(false)
		end
	end

	return setmetatable({side = side, root = root, clip = clip}, Instance)
end

-- destroy(status): 0 the mark is as it should be, 1 the HUD is down (red), 2 it flickers (the mark is off).
function Instance:Destroy(status)
	local label = status == 1 and "malfunction" or status == 2 and "flickering" or "normal"

	self.clip:GotoAndPlay(label)
	self.status = status
end

function Instance:Update(dt)
	self.root:Advance(dt)
end

function Instance:Draw(w, h)
	local x, y, scale = Corners.Placement(self.side, w, h)

	Flash.Draw(self.root, x, y, scale)
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game
-- ---------------------------------------------------------------------------------------------------------

local instances = {}
local status = 0 -- what the HUD last reported

-- Whether the marks are wanted: the HUD element gry_hud_corners (on by default). The HUD itself being on is the caller's business.
function Corners.Wanted()
	return GryMod.HUDOptions ~= nil and GryMod.HUDOptions.Enabled("corners")
end

-- The state of the suit as the HUD last reported it; the marks in being take it now.
function Corners.SetStatus(value)
	status = value

	for _, instance in pairs(instances) do
		instance:Destroy(value)
	end
end

function Corners.Status()
	return status
end

-- The marks made now, and the one of a side (tests).
function Corners.Count()
	local count = 0

	for _ in pairs(instances) do
		count = count + 1
	end

	return count
end

function Corners.Mark(side)
	return instances[side]
end

function Corners.Reset()
	for side, instance in pairs(instances) do
		Flash.ReleaseClip(instance.root)
		instances[side] = nil
	end
end

-- The marks of one paint of the HUD: made at the first one, moved on and drawn. Nothing is made or kept while the setting is off.
function Corners.Paint(dt)
	if not Corners.Wanted() then
		if next(instances) then
			Corners.Reset()
		end

		return
	end

	local w, h = ScrW(), ScrH()

	for side, name in pairs(Corners.MOVIES) do
		local instance = instances[side]

		if not instance then
			instance = Corners.New(side, Flash.Load(name))

			if not instance then
				return
			end

			instances[side] = instance

			if status ~= 0 then
				instance:Destroy(status)
			end
		end

		instance:Update(dt)
		instance:Draw(w, h)
	end
end

-- The HUD changes its state (cl_hud_flash.lua: 1 malfunction, 0 normal, 2 flicker).
hook.Add("GryMod_HUDStatus", "GRYCORNERS", function(value)
	Corners.SetStatus(value)
end)
