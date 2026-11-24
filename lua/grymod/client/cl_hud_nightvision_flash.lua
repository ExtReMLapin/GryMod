-- The night vision's energy bar drawn from the original Scaleform movie (HUD_NightVision), see cl_flash.lua: a small bar of four segments with tick
-- marks at the top right of the screen, next to the corner mark, that empties while the night vision is on and fills again while it is off. The
-- picture of the night vision itself is a screen effect (cl_nightvision_fx.lua); the state (on or off, the energy) is cl_nightvision.lua's.
--
-- WHAT THE MOVIE DOES (its ActionScript, read with FFDec): setVisible(b) shows or hides the whole movie, setNightVisionBar(v) puts the bar at
-- frame floor(v) + 1 of its 102-frame clip (frame 1 is empty, frame 102 is full: v is 0 to 100), destroy(status) plays the states of the HUD
-- (1 red, the malfunction; 2 flickers; 0 normal, as the corner marks do), and the movie starts with setVisible(true) and setNightVisionBar(100).
--
-- WHEN THE ORIGINAL SHOWS IT (read in the Remaster's executable, and the demo's notes in docs/superpowers/plans/2026-11-24-nightvision-crysis-study.md):
--   CONFIRMED (the Remaster's toggle code and its HUD update, read in the executable): a flag of the HUD says "the bar is up". Switching the night
--   vision on the first time sets it and shows the movie (a call with 1); the update of every frame moves the energy and calls setNightVisionBar
--   only while the energy is not full; when the energy is back to its maximum (30) and the flag is up, it hides the movie (a call with 0) and clears
--   the flag. So the bar is NOT always on: it comes up when the night vision is used, stays while it is on and while the energy refills, and goes
--   away when the energy is full again.
--   DEDUCED: the object that is shown and hidden is the bar's movie (the executable keeps two pointers for the night vision HUD, one the bar's
--   function caller and one the object that is shown; the demo's code only loads the movie at the first switch on, at 0x391aed57).
--   CHOICE: the opening animation (17 frames, the ticks come one by one) plays when the movie is made, once, as in the demo (setVisible only
--   changes the visibility); here the movie is made at the first paint after the first switch on and kept until the HUD is dropped.
--
-- WHERE: the movie's root is at x 823, y 28.7 of the 1024 x 768 stage, which sits against the right edge of the screen as high as the screen, the way the
-- corner marks (cl_hud_corners_flash.lua) are placed; so is the HUD offset (the corner marks ignore gry_xadd and gry_xdist, and so does this).
--
-- NOTHING RUNS BY ITSELF. It is drawn by the HUD's own paint (cl_hud_flash.lua calls NightBar.Paint), so it follows the HUD: gone with it when it is off
-- (gry_hud, the suit off, the player dead and the HUD dropped), red with it when it goes down. While the bar is not up, the paint is one test of a
-- flag: no convar, no energy, no movie. The energy is read (NV.Bar) only while the bar is up. The only hook is the report of the night vision
-- (GryMod_NightVision), which raises the flag.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local NightBar = GryMod.FlashNightVisionBar or {}
GryMod.FlashNightVisionBar = NightBar

NightBar.MOVIE = "hud_nightvision"

local STAGE_W, STAGE_H = 1024, 768

-- The frames of the clip that holds the bar: 1 is 0, 102 is 100.
NightBar.FRAMES = 102

-- The path of the bar's clip inside the movie: the movie's "Root" (the states of the HUD) holds the opening clip "Bar", which holds the 102-frame "Bar".
NightBar.PATH = "Root.Bar.Bar"

-- The frame of the 102-frame clip for a value of 0 to 100: the movie's setNightVisionBar does floor(value) + 1. A value out of the range is held in it, anything
-- that is not a number counts as 0.
function NightBar.FrameFor(value)
	value = tonumber(value)

	if not value or value ~= value then
		return 1
	end

	if value <= 0 then
		return 1
	end

	if value >= NightBar.FRAMES - 1 then
		return NightBar.FRAMES
	end

	return math.floor(value) + 1
end

-- Where the stage of the movie goes on a screen of w x h pixels: x and y of its origin and the scale (the stage as high as the screen, against the right edge
-- of the screen like the right corner mark's, so the bar keeps its distance from the corner on any aspect ratio).
function NightBar.Placement(w, h)
	local scale = h / STAGE_H

	return w - STAGE_W * scale, 0, scale
end

-- The 102-frame clip of a root of the movie (NightBar.PATH), by plain lookups: Clip:Find splits a path into strings, which makes garbage, and this is asked at every paint.
local function barClipOf(root)
	local states = root:Child("Root")
	local opening = states and states:Child("Bar")

	return opening and opening:Child("Bar") or nil
end

local Instance = {}
Instance.__index = Instance

-- The bar from its converted movie (nil when the movie is missing or has no such clip).
function NightBar.New(movie, theme)
	if not movie then
		return nil
	end

	theme = theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme)

	local root = Flash.NewRoot(movie, theme)
	local states = root:Child("Root")

	if not states or not root:Find(NightBar.PATH) then
		return nil
	end

	-- the three clips the colours come from (the movie keeps them above its stage, out of sight): nothing to draw
	for _, name in ipairs({"Line", "Over", "Text"}) do
		local source = root:Child(name)

		if source then
			source:SetVisible(false)
		end
	end

	-- a second copy of the movie, never drawn by itself: it is kept at the next frame of the bar, and its image is what the fill side of the cut line shows (the
	-- smooth bar, cl_hud_bar_smooth.lua). It plays the same time as the first one, so that the two are the same picture but for the bar's frame.
	local copy = Flash.NewRoot(movie, theme)

	for _, name in ipairs({"Line", "Over", "Text"}) do
		local source = copy:Child(name)

		if source then
			source:SetVisible(false)
		end
	end

	return setmetatable({root = root, clip = states, copy = copy, copyClip = copy:Child("Root"), value = 100, status = 0}, Instance)
end

-- setNightVisionBar(value): the bar's frame. The clip is looked for every time: the movie's restart after a flicker makes the bar again, at its first frame.
function Instance:SetBar(value)
	self.value = value

	local bar = barClipOf(self.root)

	if not bar then
		return
	end

	-- the bar at the exact value (the cut line, the second copy at the next frame: cl_hud_bar_smooth.lua), or at its whole frame when a step is a pixel or less
	-- or the setting is off. The frames are the movie's: floor(value) + 1 (offset 1 on 102 frames).
	local Smooth = GryMod.FlashBarSmooth

	if Smooth then
		local mask = barClipOf(self.copy)
		local smooth = self.smooth

		if smooth == nil or (smooth and (smooth.mask ~= bar or smooth.cloneMask ~= mask)) then
			smooth = Smooth.New(self.clip, bar, 1, self.copyClip, mask)
			self.smooth = smooth or false
		end

		if smooth then
			Smooth.Apply(smooth, value)

			return
		end
	end

	local frame = NightBar.FrameFor(value)

	if bar:CurrentFrame() ~= frame then
		bar:GotoAndStop(frame)
	end
end

-- destroy(status): 0 the bar is as it should be, 1 the HUD is down (red), 2 it flickers.
function Instance:Destroy(status)
	local label = status == 1 and "malfunction" or status == 2 and "flickering" or "normal"

	self.clip:GotoAndPlay(label)
	self.copyClip:GotoAndPlay(label)
	self.status = status
end

function Instance:Update(dt)
	self.root:Advance(dt)
	self.copy:Advance(dt)
end

function Instance:Draw(w, h)
	local x, y, scale = NightBar.Placement(w, h)

	Flash.Draw(self.root, x, y, scale)
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game
-- ---------------------------------------------------------------------------------------------------------

local instance
local up = false -- the original's flag: the bar is up (set at a switch on, cleared when the energy is full again)
local status = 0 -- what the HUD last reported

-- Whether the bar is wanted: the HUD element gry_hud_nightvision (on by default). The HUD itself being on is the caller's business.
function NightBar.Wanted()
	return GryMod.HUDOptions == nil or GryMod.HUDOptions.Enabled("nightvision")
end

-- The night vision was switched on: the bar comes up.
function NightBar.Raise()
	up = true
end

-- Whether the bar is up (a flag; it can be up and not drawn: the setting off, the energy not limited).
function NightBar.IsUp()
	return up
end

-- The state of the suit as the HUD last reported it; the bar in being takes it now.
function NightBar.SetStatus(value)
	status = value

	if instance then
		instance:Destroy(value)
	end
end

function NightBar.Status()
	return status
end

-- The bar made now (tests).
function NightBar.Bar()
	return instance
end

function NightBar.Reset()
	if instance then
		Flash.ReleaseClip(instance.root)
		instance = nil
	end
end

-- Whether a paint has anything to do. The flag is the whole cost while the bar is down. The bar goes down, as in the original, when the night vision is off and
-- the energy is at its maximum again (that is also a night vision without a limit: its energy is always full), and for a night vision that has no bar to show.
function NightBar.Shown()
	if not up then
		return false
	end

	local NV = GryMod.NightVision

	if not NV then
		up = false

		return false
	end

	if not NV.BarVisible() then
		up = false

		return false
	end

	if not NV.IsOn() and NV.Energy() >= NV.MAX then
		up = false

		return false
	end

	return true
end

-- The bar of one paint of the HUD: made at the first one, set to the energy, moved on and drawn. Nothing is made or kept while the setting is off.
function NightBar.Paint(dt)
	if not up then
		return
	end

	if not NightBar.Wanted() then
		-- the setting is off: nothing is made, the flag keeps (the bar is back when the setting is)
		NightBar.Reset()

		return
	end

	if not NightBar.Shown() then
		return
	end

	local NV = GryMod.NightVision

	if not instance then
		instance = NightBar.New(Flash.Load(NightBar.MOVIE))

		if not instance then
			return
		end

		if status ~= 0 then
			instance:Destroy(status)
		end
	end

	instance:SetBar(NV.Bar())
	instance:Update(dt)
	instance:Draw(ScrW(), ScrH())
end

-- The HUD changes its state (cl_hud_flash.lua: 1 malfunction, 0 normal, 2 flicker).
hook.Add("GryMod_HUDStatus", "GRYNIGHTVISIONBAR", function(value)
	NightBar.SetStatus(value)
end)

-- The night vision is switched on or off (cl_nightvision.lua): a switch on brings the bar up.
hook.Add("GryMod_NightVision", "GRYNIGHTVISIONBAR", function(on)
	if on then
		NightBar.Raise()
	end
end)

-- This file loaded in the middle of a game with the night vision already on: the bar is up.
if GryMod.NightVision and GryMod.NightVision.IsOn() then
	up = true
end
