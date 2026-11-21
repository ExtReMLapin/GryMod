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

	self:_applyNoise()

	local indicator = self.view and self.view:Child("Indicator")

	if indicator then
		indicator:SetVisible(false)
	end

	self.mainFrame = main:CurrentFrame()
end

-- The noise strength of a malfunction (the movie's destroy(1) sends 0.6).
Radar.NOISE_VALUE = 0.6

-- setNoiseValue: the noise clip is visible and looping at alpha value * 50 % over the units, which go to (1 - value) * 100 %;
-- value 0 hides the noise, stops it and puts the units back to 100 %. Two things ask for noise: the malfunction (a fixed 0.6 while
-- status is 1) and SetNoise (self.noise, e.g. the minimap's progress veil); the stronger one is shown. With keepUnits (SetNoise's
-- second argument) the units are only dimmed by the malfunction. Called by SetNoise and by _resolve when the movie rebuilt its clips.
function Panel:_applyNoise()
	local main = self.main
	local noise = main:Child("Noise")
	local units = main:Child("Units")
	local malfunction = self.status == 1 and Radar.NOISE_VALUE or 0
	local value = math.max(malfunction, self.noise or 0)
	local unitsValue = self.keepUnits and malfunction or value

	if noise then
		noise:SetVisible(value > 0)
		noise:SetAlpha(value * 50)

		if value > 0 then
			-- the movie's NoisePlaying: the loop starts once per clip (a rebuilt clip starts again)
			if self.noisePlaying ~= noise then
				noise:GotoAndPlay("loop")
				self.noisePlaying = noise
			end
		elseif self.noisePlaying == noise then
			noise:GotoAndStop(1)
			self.noisePlaying = nil
		end
	end

	if units then
		units:SetAlpha((1 - unitsValue) * 100)
	end
end

-- setNoiseValue(v) of the movie, v in 0..1 (nil and NaN are 0). keepUnits true leaves the units at 100 %.
function Panel:SetNoise(value, keepUnits)
	if type(value) ~= "number" or value ~= value then
		value = 0
	end

	self.noise = math.Clamp(value, 0, 1)
	self.keepUnits = (keepUnits and self.noise > 0) or false
	self:_applyNoise()
end

-- destroy(status): 0 normal (the movie plays "to_normal" and lands on its steady frames), 1 malfunction (the
-- noise over the units, red until the next destroy(0)), 2 flickering.
function Panel:Destroy(status)
	self.status = status

	if status == 1 then
		self.main:GotoAndPlay("malfunction")
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

-- The zone field shows the progress text when there is one, else the sector name. Neither one erases the other.
function Panel:_applyZoneText()
	local text = self.progressText or self.sector

	if self.zone and (text ~= nil or self.zoneWritten) then
		self.zone:SetText("Zone", text)
		self.zoneWritten = true
	end
end

-- setSector: the name shown at the bottom.
function Panel:SetSector(name)
	self.sector = name
	self:_applyZoneText()
end

-- A short text (the minimap's "40%") that takes the place of the sector name until it is cleared with nil.
function Panel:SetProgressText(text)
	self.progressText = text
	self:_applyZoneText()
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

	self:_applyZoneText()
end

function Panel:Update(dt)
	self.root:Advance(dt)

	if self.main:CurrentFrame() ~= self.mainFrame then
		self:_resolve()
		self:_refresh()
	end
end

-- The minimap under the contacts (GryMod.Minimap, lua/grymod/client/minimap/). Everything about it is optional: a failure here never
-- keeps the radar from drawing.

-- The reach of the movie's frame in range units: its farthest corner is about 1.75 times the radius (see the minimap design).
Radar.MAP_EXTENT = 1.75
-- The alpha of the map under the contacts.
Radar.MAP_ALPHA = 0.6
-- The strength of the veil over the map while the tile under the player is missing.
Radar.MAP_VEIL = 0.6

-- The way a failure of the minimap is told (replaced by the tests).
function Radar.LogMinimapError(message)
	ErrorNoHalt("[GryMod] Minimap drawing failed: " .. message .. "\n")
end

-- A message is told once, not at every frame; the memory is bounded.
local told, toldCount = {}, 0

-- Forgets the messages already told (the tests).
function Radar.ForgetMinimapErrors()
	told, toldCount = {}, 0
end

local function reportError(err)
	local message = tostring(err)

	if told[message] then
		return
	end

	if toldCount >= 16 then
		told, toldCount = {}, 0
	end

	told[message] = true
	toldCount = toldCount + 1
	Radar.LogMinimapError(message)
end

-- The matrix {a, b, c, d, tx, ty} that sends a radar pixel (x right, y down, 0 0 the player, as Radar.Contacts places the contacts) to the
-- screen, for a Draw(x, y, scale): the point of the Units clip (UNITS_CENTRE + pixel * UNITS_PIXEL), the matrix of Units, the matrix of
-- Root, then the scale and the offset of Draw. The matrices are the live ones of the movie (a malfunction animation may move them).
-- `out` is filled and returned; nil when the panel has no Units clip.
function Panel:MapTransform(x, y, scale, out)
	local rootEntry = self.main and self.main.entry
	local units = self.main and self.main:Child("Units")
	local unitsEntry = units and units.entry

	if not rootEntry or not unitsEntry then
		return nil
	end

	-- a child matrix m inside a parent (a, b, c, d, tx, ty): the same product as the drawing's
	local a, b, c, d, tx, ty = scale, 0, 0, scale, x, y
	local m = rootEntry.m
	a, b, c, d, tx, ty = a * m[1] + c * m[2], b * m[1] + d * m[2], a * m[3] + c * m[4], b * m[3] + d * m[4], a * m[5] + c * m[6] + tx, b * m[5] + d * m[6] + ty
	m = unitsEntry.m
	a, b, c, d, tx, ty = a * m[1] + c * m[2], b * m[1] + d * m[2], a * m[3] + c * m[4], b * m[3] + d * m[4], a * m[5] + c * m[6] + tx, b * m[5] + d * m[6] + ty

	-- the Units clip's own point of a radar pixel
	local k = Radar.UNITS_PIXEL or 110 / 94
	local ox, oy = Radar.UNITS_CENTRE_X or 64.1, Radar.UNITS_CENTRE_Y or 52.3
	out = out or {}
	out[1], out[2], out[3], out[4] = a * k, b * k, c * k, d * k
	out[5], out[6] = a * ox + c * oy + tx, b * ox + d * oy + ty

	return out
end

-- The veil and the text that say the map is being made: only changes are applied (the state lives in the panel, which is rebuilt at
-- every death; `present` nil means nothing was asked yet, which is the same as present).
function Panel:_mapProgress(present, percent)
	if present then
		if self.mapPresent == false then
			self.mapPresent = true
			self.mapPercent = nil
			self:SetNoise(0)
			self:SetProgressText(nil)
		end

		return
	end

	percent = math.Clamp(math.floor(tonumber(percent) or 0), 0, 100)

	if self.mapPresent ~= false then
		self.mapPresent = false
		self:SetNoise(Radar.MAP_VEIL, true)
	end

	if self.mapPercent ~= percent then
		self.mapPercent = percent
		self:SetProgressText(percent .. "%")
	end
end

-- Asks the minimap for its tiles and draws them (called with pcall by Draw, so no closure and no table made here when nothing changes).
local function drawMap(self, x, y, scale)
	local M = GryMod.Minimap
	local Settings = M and M.Settings

	if not Settings then
		return
	end

	if not Settings.Enabled() then
		-- switched off while the map was being made: the veil goes with it
		self:_mapProgress(true)

		return
	end

	local ply = LocalPlayer()

	if not IsValid(ply) then
		return
	end

	local xf = self:MapTransform(x, y, scale, self.mapXf)

	if not xf then
		return
	end

	self.mapXf = xf

	local pos = ply:GetPos()
	local px, py = pos.x, pos.y
	local range = Radar.Range() / GryMod.RadarShared.METRES_PER_UNIT
	local level = M.Floors.Current(pos.z)

	if not level then
		return
	end

	M.Gen.Request(level, px, py, range * Radar.MAP_EXTENT)

	-- the tile under the player decides the veil
	local res = Settings.TileRes()
	local ppm = Settings.Definition()
	local tx, ty = M.Cache.TileOf(px, py, res, ppm)
	local tile = self.mapTile

	if not tile then
		tile = {}
		self.mapTile = tile
	end

	tile.level, tile.tx, tile.ty, tile.res, tile.ppm = level.id, tx, ty, res, ppm

	if M.Cache.Has(tile) then
		self:_mapProgress(true)
	else
		local progress = M.Gen.Progress()
		self:_mapProgress(false, progress and progress.percent)
	end

	-- the map turns with the player's view like the contacts (Radar.Contacts)
	-- View.Draw leaves the map's alpha in surface's colour: Draw puts it back whether the call returned or raised
	self.mapDrawing = true
	M.View.Draw(xf, px, py, ply:EyeAngles().y, range, level, Radar.MAP_ALPHA)
end

function Panel:Draw(x, y, scale)
	local ok, err = pcall(drawMap, self, x, y, scale)

	if not ok then
		reportError(err)
	end

	if self.mapDrawing then
		self.mapDrawing = false
		surface.SetDrawColor(255, 255, 255, 255)
	end

	Flash.Draw(self.root, x, y, scale)
end
