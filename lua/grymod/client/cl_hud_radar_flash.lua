-- The compass and radar panel drawn from the original Scaleform movie (HUD_RadarCompassStealth), see
-- cl_flash.lua and cl_hud_flash.lua. Hand-ported parts of its ActionScript: the start (SkipSequence),
-- setCompassRotation (the heading strip), setFOV (the view cone), the stealth bar and the sector name.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Radar = {}
GryMod.FlashRadar = Radar

Radar.MOVIE = "hud_radarcompassstealth"

-- Stage pixels the heading strip moves per degree: the same letter comes back every 360.1 pixels in the movie
-- (measured on the letters' positions), which holds three and a half turns of the compass.
Radar.PIXELS_PER_DEGREE = 360.1 / 360
-- Where the strip sits when the bearing is 0 (north is under the marker of the view cone).
Radar.HEADING_ORIGIN = 0
-- GryMod's world has north at this yaw (the old compass used the same offset).
Radar.NORTH_YAW = -6.256798

local Panel = {}
Panel.__index = Panel
Radar.Panel = Panel -- cl_hud_radar_units.lua adds the contacts (SetObjects)

function Radar.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local main = root:Child("Root")

	if not main then
		return nil
	end

	local panel = setmetatable({root = root, main = main, heading = 0, stealth = 0, fov = 15, status = 0}, Panel)
	panel:_start()

	return panel
end

-- The steady state of the original (SkipSequence): the "on" frames, the strip on its normal frame, and the
-- helper clips that only hold colours, the noise and the damage indicator hidden.
function Panel:_start()
	local main = self.main

	for _, name in ipairs({"Line", "Over", "Text"}) do
		local holder = self.root:Child(name)

		if holder then
			holder:SetVisible(false)
		end
	end

	main:GotoAndStop("on")
	self:_resolve()
	self.view:GotoAndPlay("on")
	self.strip:GotoAndStop("normal")
	self:_refresh()
end

function Panel:_resolve()
	local main = self.main
	self.strip = main:Child("Heading")
	self.view = main:Child("RadarCompassStealth")
	self.zone = self.root:Find("Root.Zone.Colorset")

	-- setNoiseValue: while the panel malfunctions the noise shows (alpha value * 50 %) over the units
	-- (alpha (1 - value) * 100 %); otherwise it is hidden and the units are at full strength
	local noise = main:Child("Noise")
	local units = main:Child("Units")
	local value = self.status == 1 and Radar.NOISE_VALUE or 0

	if noise then
		noise:SetVisible(value > 0)
		noise:SetAlpha(value * 50)
	end

	if units then
		units:SetAlpha((1 - value) * 100)
	end

	local indicator = self.view and self.view:Child("Indicator")

	if indicator then
		indicator:SetVisible(false)
	end

	self.mainFrame = main:CurrentFrame()
end

-- The noise strength of a malfunction (the movie's destroy(1) sends 0.6).
Radar.NOISE_VALUE = 0.6

-- destroy(status): 0 normal (the movie plays "to_normal" and lands on its steady frames), 1 malfunction (the
-- noise over the units, red until the next destroy(0)), 2 flickering.
function Panel:Destroy(status)
	self.status = status

	if status == 1 then
		self.main:GotoAndPlay("malfunction")
		local noise = self.main:Child("Noise")

		if noise then
			noise:GotoAndPlay("loop")
		end
	elseif status == 2 then
		self.main:GotoAndPlay("flickering")

		if self.strip then
			self.strip:GotoAndPlay("flickering")
		end
	else
		self.main:GotoAndPlay("to_normal")
	end

	self:_resolve()
	self:_refresh()
end

-- setCompassRotation: the strip's x for a bearing in degrees (0 = north, growing clockwise).
function Radar.StripX(bearing)
	if bearing == nil or bearing ~= bearing then
		bearing = 0
	end

	return Radar.HEADING_ORIGIN - (bearing % 360) * Radar.PIXELS_PER_DEGREE
end

-- How full the stealth bar is: the old radar bars filled with the number of NPCs near, 16 filling all four.
function Radar.StealthFromCount(count)
	if count == nil or count ~= count then
		return 0
	end

	return math.Clamp(count / 16, 0, 1)
end

-- The bearing GryMod's yaw means (north at NORTH_YAW, clockwise growing).
function Radar.BearingFromYaw(yaw)
	return (-(yaw - Radar.NORTH_YAW)) % 360
end

function Panel:SetHeading(bearing)
	if bearing == nil or bearing ~= bearing then
		bearing = 0
	end

	self.heading = bearing

	if self.strip then
		self.strip:SetX(Radar.StripX(bearing))
	end
end

-- The frame of the view cone for a Source horizontal field of view (degrees). The original sends the camera's
-- field of view times cl_fov (60) times 0.5, which is about 30 at its default view; Source's 75 horizontal on a
-- 4:3 screen is that 60 vertical, so the frame is half the vertical field of view in degrees (75 gives 30, 90 gives
-- 37, a 20 degree zoom gives 8). The unit of the original's factor is not resolved: this reading is the one that
-- gives 30 at the default view.
function Radar.FovFrame(fov)
	if fov == nil or fov ~= fov or fov <= 0 then
		return 1
	end

	local vertical = 2 * math.atan(0.75 * math.tan(math.rad(math.min(fov, 179)) / 2))

	return math.Clamp(math.floor(math.deg(vertical) / 2 + 0.5), 1, 100)
end

-- setFOV: the frame of the view cone (1-100).
function Panel:SetFOV(frame)
	self.fov = frame
	local cone = self.view and self.view:Find("View2.Pov")

	if cone then
		cone:GotoAndStop(math.Clamp(math.floor(frame), 1, 100))
	end
end

-- The stealth bar: 0 (nothing near) to 1.
function Panel:SetStealth(level)
	if level == nil or level ~= level then
		level = 0
	end

	self.stealth = level
	local bar = self.view and self.view:Child("StealthBar")

	if bar then
		bar:GotoAndStop(math.floor(math.Clamp(level, 0, 1) * 100 + 1.5))
	end
end

-- setDamage: the movie's damage ring, frame = value * 100 + 1, hidden above 1. The original only feeds it with the damage
-- state of the radar of the vehicle the player drives (never on foot, see 2026-11-21-damage-feedback-notes.md), so
-- nothing calls it in GryMod; the function mirrors the movie's.
function Panel:SetDamage(value)
	local ring = self.view and self.view:Child("Indicator")

	if not ring then
		return
	end

	if type(value) ~= "number" or value ~= value or value > 1 then
		ring:SetVisible(false)

		return
	end

	-- Flash goes to the last frame when the number is past the end (the ring has 22 frames)
	ring:SetVisible(true)
	ring:GotoAndStop(math.min(math.floor(math.max(value, 0) * 100 + 1), ring.n))
end

-- setSector: the name shown at the bottom.
function Panel:SetSector(name)
	self.sector = name

	if self.zone then
		self.zone:SetText("Zone", name)
	end
end

-- the compass letters are localisation keys ("@ui_NW"): the engine writes the names
local function localise(text)
	return (text:gsub("^@ui_", ""))
end

function Panel:_refresh()
	if self.strip then
		self.strip:MapText(localise)
	end

	self:SetHeading(self.heading)
	self:SetFOV(self.fov)
	self:SetStealth(self.stealth)

	if self.sector then
		self:SetSector(self.sector)
	end
end

function Panel:Update(dt)
	self.root:Advance(dt)

	if self.main:CurrentFrame() ~= self.mainFrame then
		self:_resolve()
		self:_refresh()
	end
end

function Panel:Draw(x, y, scale)
	Flash.Draw(self.root, x, y, scale)
end
