-- The compass and radar panel drawn from the original Scaleform movie (HUD_RadarCompassStealth), see
-- cl_flash.lua and cl_hud_flash.lua. Hand-ported parts of its ActionScript: the start (SkipSequence),
-- setCompassRotation (the heading strip), setFOV (the view cone), the stealth bar and the sector name.

GryMod = GryMod or {}

local Flash = GryMod.Flash

-- The tables are kept when this file is loaded again (a hot reload): cl_hud_radar_units.lua adds to them, and a panel or a hook built from the
-- earlier load would find them empty otherwise.
local Radar = GryMod.FlashRadar or {}
GryMod.FlashRadar = Radar

Radar.MOVIE = "hud_radarcompassstealth"

-- Stage pixels the heading strip moves per degree: the same letter comes back every 360.1 pixels in the movie
-- (measured on the letters' positions), which holds three and a half turns of the compass.
Radar.PIXELS_PER_DEGREE = 360.1 / 360
-- Where the strip sits when the bearing is 0 (north is under the marker of the view cone).
Radar.HEADING_ORIGIN = 0
-- GryMod's world has north at this yaw (the old compass used the same offset).
Radar.NORTH_YAW = -6.256798

local Panel = Radar.Panel or {}
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

-- The widest the "Zone" field is made, in stage pixels. The field of the movie is 23 pixels wide and cuts its text to that width ("In/out 40%"
-- was seen as "In/o"): it is widened to the text, up to this width, which is what the map area leaves it from the field's left edge at the
-- bottom of the radar (measured on screen: a text of 86 pixels, "Navigation mesh...", ends well inside the area; 110 still does).
Radar.ZONE_MAX_WIDTH = 110

-- The zone field shows the progress text when there is one, else the sector name. Neither one erases the other. The field is as wide as
-- its text needs (up to Radar.ZONE_MAX_WIDTH), and goes back to the movie's width when it is empty.
function Panel:_applyZoneText()
	local text = self.progressText or self.sector

	if self.zone and (text ~= nil or self.zoneWritten) then
		self.zone:SetText("Zone", text)
		self.zone:FitTextWidth("Zone", text, Radar.ZONE_MAX_WIDTH)
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

-- How many times the radius the tiles asked for reach from the player when the view cannot say (View.ExtentFactor does): the farthest corner of the window
-- (Radar.FRAME) is 90 radar pixels away, 2.1 radiuses, and the part of it the map fills 84 pixels, 1.97.
Radar.MAP_EXTENT = 2
-- The alpha of the map (0 to 1) when the settings do not say (Settings.Opacity): the glass of the movie is behind it, so a low value dims the map.
Radar.MAP_ALPHA = 0.9
-- Where in the Root clip's drawing the map goes: just before the entry at this depth, after the glass (depth 1) and before the mask of the map area (3), the
-- noise, the units and the rest. Drawn before the whole movie the map was under the glass, which dims it.
Radar.MAP_DEPTH = 3
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
-- `label` (optional) goes before the percentage: the in/out map's loading is shown as "In/out 40%", the tiles' own as "40%". `noPercent` (optional, with a label)
-- shows the label alone, "Navigation mesh...": a wait that has no progress to tell.
function Panel:_mapProgress(present, percent, label, noPercent)
	if present then
		if self.mapPresent == false then
			self.mapPresent = true
			self.mapPercent = nil
			self.mapLabel = nil
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

	if noPercent and label then
		percent = nil -- the text has no number: only the label can change it
	end

	if self.mapPercent ~= percent or self.mapLabel ~= label then
		self.mapPercent = percent
		self.mapLabel = label

		if percent == nil then
			self:SetProgressText(label .. "...")
		else
			self:SetProgressText(label and (label .. " " .. percent .. "%") or (percent .. "%"))
		end
	end
end

-- Whether the in/out map of the server is still being waited for (cl_zonemap.lua), and its percentage. A missing module or one that raises is "no": then the
-- tiles decide, as before. The third answer is the phase ("wait": the server waits for the navigation mesh, no percentage; anything else: a percentage).
local function inOutLoading()
	local Zone = GryMod.ZoneMapClient

	if not Zone or not Zone.Loading then
		return false
	end

	local ok, loading, percent, phase = pcall(Zone.Loading)

	if ok and loading then
		return true, percent, phase
	end

	return false
end

-- The pixels of the screen that show one metre of ground: the radar's pixels per metre (PIXELS for the range, as Radar.Contacts places the contacts) times the
-- screen pixels of one radar pixel (the length of a column of the transform `xf`, which MapTransform builds from the live matrices of the movie). Nil when it is
-- no usable number.
function Radar.ScreenPixelsPerMetre(xf, metres)
	local pixels = GryMod.RadarShared.PIXELS

	if type(xf) ~= "table" or type(pixels) ~= "number" or type(metres) ~= "number" or metres <= 0 then
		return nil
	end

	local density = pixels / metres * math.sqrt(xf[1] * xf[1] + xf[2] * xf[2])

	if density ~= density or density == math.huge then
		return nil
	end

	return density
end

-- Gives Settings the level of the automatic definition for this frame: the rule (pure, in Settings) from the density of the screen, keeping the level in use
-- while the density stays near it.
local function autoDefinition(Settings, xf, metres)
	local density = Radar.ScreenPixelsPerMetre(xf, metres)

	if density then
		Settings.SetAutoDefinition(Settings.AutoDefinitionFor(density, Settings.Definition()))

		-- the screen constant for the tile preload (density times range: the same at every range)
		if Settings.SetScreenConstant then
			Settings.SetScreenConstant(density * metres)
		end
	end
end

-- Whether the tile under the player exists at the previous definition of the automatic pyramid (Settings.PreviousDefinition), when that is another one than
-- `ppm`. `tile` (the tile asked at `ppm`) is given back as it was.
local function coveredByPrevious(Settings, Cache, tile, px, py, res, ppm)
	local previous = Settings.PreviousDefinition and Settings.PreviousDefinition()

	if type(previous) ~= "number" or previous ~= previous or previous <= 0 or previous == ppm then
		return false
	end

	local ptx, pty = Cache.TileOf(px, py, res, previous)

	if not ptx then
		return false
	end

	local tx, ty = tile.tx, tile.ty

	tile.tx, tile.ty, tile.ppm = ptx, pty, previous

	local found = Cache.Has(tile)

	tile.tx, tile.ty, tile.ppm = tx, ty, ppm

	return found and true or false
end

-- Whether the discovery mode is wanted: Settings.VeilInDiscovery exists and says no veil. A Settings without it, one that raises, or one that answers anything but false
-- is the old behaviour (the veil as soon as the tile under the player is missing).
local function discoveryWanted(Settings)
	local read = Settings.VeilInDiscovery

	if type(read) ~= "function" then
		return false
	end

	local ok, veil = pcall(read)

	return ok and veil == false
end

-- Whether there is something to show of the map around the player although the tile under them is missing: some tile of the level (or of the place) lies under the
-- range circle (View.Coverage, no drawing). A view without Coverage, one that raises, or that answers nothing above 0 is "nothing to show" (the veil: the old, safe
-- answer). `range` is the range the map is drawn with, in units.
local function somethingToShow(M, px, py, range, level, own)
	local View = M.View
	local coverage = View and View.Coverage

	if type(coverage) ~= "function" then
		return false
	end

	local ok, share = pcall(coverage, px, py, range, level, own)

	if not ok then
		reportError("View.Coverage: " .. tostring(share))

		return false
	end

	return type(share) == "number" and share > 0
end

-- Asks the minimap for its tiles and draws them (called with pcall by Draw, so no closure and no table made here when nothing changes).
local function drawMap(self, x, y, scale)
	local M = GryMod.Minimap
	local Settings = M and M.Settings

	if not Settings then
		return
	end

	if not Settings.Enabled() then
		-- switched off while the map was being made: the veil goes with it, and the generator stops (its PostRender hook would go on emptying the queue)
		self:_mapProgress(true)

		if not self.mapCancelled then
			self.mapCancelled = true

			local Gen = M.Gen

			if Gen and Gen.Cancel then
				local ok, err = pcall(Gen.Cancel)

				if not ok then
					reportError(err)
				end
			end
		end

		return
	end

	self.mapCancelled = false

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
	-- the range the map is DRAWN with (it glides while the automatic zoom changes mode) and the range the player asked for (the target, whole metres): the
	-- definition of the tiles and the tiles asked for follow the target at once, so a glide only scales what is there and makes no tiles on the way
	local metres = Radar.Range()
	local target = Radar.TargetRange()
	local range = metres / GryMod.RadarShared.METRES_PER_UNIT
	local requestRange = target / GryMod.RadarShared.METRES_PER_UNIT

	-- the automatic definition: the level of the pyramid for what the screen shows now, given to Settings (which then answers it as the definition in use, to
	-- Gen, View and the tile looked up below). Done before anything asks for the definition. A failure here is told once and the map goes on at the level it had.
	if Settings.DefinitionAuto and Settings.AutoDefinitionFor and Settings.SetAutoDefinition and Settings.DefinitionAuto() then
		local ok, err = pcall(autoDefinition, Settings, xf, target)

		if not ok then
			reportError(err)
		end
	end
	-- the level of the player: CurrentAt looks up for a ceiling (an open level outdoors), the height alone is the older rule. CurrentAt answers the level to SHOW (the
	-- display holds the level it showed while that is still right and its tile is there) and the level of the PLACE: the generator is asked for the place's only (the
	-- preload predicts it, nothing predicts a held level), the view draws the held level where its tile is and the place's elsewhere. `own` is nil when nothing is held.
	local Floors = M.Floors
	local level, own

	if Floors.CurrentAt then
		level, own = Floors.CurrentAt(pos)
	else
		level = Floors.Current(pos.z)
	end

	if not level then
		return
	end

	if type(own) ~= "table" or own.id == level.id then
		own = nil
	end

	-- the floor below, seen through the voids of this one, at the opacity the player chose (Settings.Below, 0 to 1; 0 or missing: none).
	-- Floors.Below may be missing or answer nil and a reason: then there is no floor below, which is not an error
	local belowOpacity = Settings.Below and Settings.Below() or 0

	if type(belowOpacity) ~= "number" or belowOpacity ~= belowOpacity then
		belowOpacity = 0
	end

	local below, belowOwn = nil, nil

	if belowOpacity > 0 and M.Floors.Below then
		below = M.Floors.Below(level)

		if own then
			belowOwn = M.Floors.Below(own)
		end
	end

	if not below then
		belowOpacity = 0
		belowOwn = nil
	end

	-- the outside (the open level of the map, the whole height of the world), seen faintly under everything else through the solid parts of the floors, at the
	-- opacity the player chose (Settings.Outside, 0 to 1; 0 or missing: none). Floors.Outside may be missing, answer nil and a reason (the player is outdoors
	-- already, the world's bounds are unknown): then there is no outside, which is not an error. An error inside it is told, and the map goes on without.
	-- The setting is read at every draw, so a change is seen by the next request (Gen compares the id of the outside with its previous request).
	local outsideOpacity = Settings.Outside and Settings.Outside() or 0

	if type(outsideOpacity) ~= "number" or outsideOpacity ~= outsideOpacity then
		outsideOpacity = 0
	end

	local outside = nil

	if outsideOpacity > 0 and Floors.Outside then
		local ok, found = pcall(Floors.Outside, level)

		if ok then
			outside = found
		else
			reportError("Floors.Outside: " .. tostring(found))
		end
	end

	if type(outside) ~= "table" then
		outside, outsideOpacity = nil, 0
	end

	-- the tiles the window can show, whatever way the map turns: the view knows the reach of its frame, else the constant
	local extent = M.View.ExtentFactor and M.View.ExtentFactor() or Radar.MAP_EXTENT

	-- a request the generator refuses answers nil and a reason (too many tiles, no tile size): nothing waits for it, it is told once
	local requested, refusal = M.Gen.Request(own or level, px, py, requestRange * extent, belowOwn or below, outside)

	if not requested and refusal then
		reportError("Gen.Request: " .. tostring(refusal))
	end

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

	local progress = M.Gen.Progress()
	local active = progress and progress.active

	local present = M.Cache.Has(tile)

	-- a held level whose tile is not there: the view draws the place's tile under the player instead
	if not present and own then
		tile.level = own.id
		present = M.Cache.Has(tile)
	end

	-- a change of level of the automatic definition (a zoom) leaves the new tile missing while the tiles of the previous level, which the view goes on drawing,
	-- already cover the player: no veil then
	local covered = present

	if present then
		-- the level whose tile is drawn under the player: the picture the discovery mode keeps if the next level's tile is not there yet
		self.mapKept = tile.level == level.id and level or own
	else
		local ok, found = pcall(coveredByPrevious, Settings, M.Cache, tile, px, py, res, ppm)

		if ok then
			covered = found
		else
			reportError(found)
		end
	end

	-- THE DISCOVERY MODE (setting gry_minimap_veil_discovery off, the default). The map is made as the player walks: the veil is for a real loading, not for a tile that
	-- is a few seconds late. The states, told in self.mapState:
	--   "ready":     the tile under the player is drawn (the level's, the place's, or the previous definition's);
	--   "discovery": that tile is missing but a picture is shown: the level just left (kept while the generator makes the new tile: a stair, a lift) or the tiles around
	--                that exist (View.Coverage above 0): no veil, no percentage; the new tile comes over it when it is ready;
	--   "loading":   nothing to show (no tile of the map under the range circle, or the in/out map of the server is still being made): the noise veil and the percentage.
	-- With the setting on (or no such setting) every missing tile under the player is "loading", as it was before.
	local state = covered and "ready" or "loading"

	if not covered and discoveryWanted(Settings) then
		local kept = self.mapKept

		-- the picture of the level just left, drawn instead of the empty tile while the generator works on the new one (idle: nothing is coming, it would lie for good)
		if active and type(kept) == "table" and kept.id ~= level.id and not (own and kept.id == own.id) then
			tile.level = kept.id

			if M.Cache.Has(tile) then
				-- the kept level is shown, the place's level (the one the generator was asked for) is the base that stands in where the kept one has no tile
				own = own or level
				level = kept
				covered, state = true, "discovery"

				if belowOpacity > 0 then
					belowOwn = belowOwn or below
					below = M.Floors.Below(level)

					if not below then
						belowOpacity, belowOwn = 0, nil
					end
				end
			end
		end

		if not covered and somethingToShow(M, px, py, range, level, own) then
			covered, state = true, "discovery"
		end
	end

	self.mapState = state

	-- the in/out map comes first: the radar is veiled from the moment the player is in the game until the server has made it and sent it (the server's percentage),
	-- then the veil is the tiles' own (the client's percentage), as before
	local inOut, inOutPercent, inOutPhase = inOutLoading()

	if inOut then
		self.mapState = "loading"

		if inOutPhase == "wait" then
			-- the server waits for the navigation mesh: the engine gives no progress, so no percentage
			self:_mapProgress(false, 0, "Navigation mesh", true)
		else
			self:_mapProgress(false, inOutPercent, "In/out")
		end
	elseif covered then
		self:_mapProgress(true)
	else
		self:_mapProgress(false, progress and progress.percent)
	end

	-- the generation ends when the tile under the player is there and the generator is idle: the index of the cache is written then, in one go
	if active or not present then
		self.mapBusy = true
	elseif present and self.mapBusy then
		self.mapBusy = false

		local Cache = M.Cache

		if Cache.Flush then
			local ok, err = pcall(Cache.Flush)

			if not ok then
				reportError(err)
			end
		end
	end

	local alpha = Settings.Opacity and Settings.Opacity()

	if type(alpha) ~= "number" or alpha ~= alpha then
		alpha = Radar.MAP_ALPHA
	end

	alpha = math.Clamp(alpha, 0, 1)

	-- what View.Draw is given, kept for the hook that draws it in the middle of the movie (drawPendingMap). The map turns with the player's view like the
	-- contacts (Radar.Contacts).
	local call = self.mapCall

	if not call then
		call = {}
		self.mapCall = call
	end

	call.xf, call.px, call.py, call.yaw, call.range, call.level, call.alpha, call.below, call.belowAlpha = xf, px, py, ply:EyeAngles().y, range, level, alpha, below, belowOpacity * alpha
	call.base, call.belowBase = own, belowOwn
	call.outside, call.outsideAlpha = outside, outsideOpacity * alpha
	self.mapPending = true
end

-- The hook of the Root clip (drawBefore of cl_flash_draw.lua): draws the map with the call drawMap prepared. View.Draw leaves the map's alpha in surface's colour,
-- so it is put back to opaque white after it, whether the call returned or raised. Never raises: a failure here is told once and the movie goes on.
local function drawPendingMap(self)
	if not self.mapPending then
		return
	end

	self.mapPending = false

	local call = self.mapCall
	local View = GryMod.Minimap.View
	local ok, err = pcall(View.Draw, call.xf, call.px, call.py, call.yaw, call.range, call.level, call.alpha, call.below, call.belowAlpha, call.outside, call.outsideAlpha, call.base, call.belowBase)
	surface.SetDrawColor(255, 255, 255, 255)

	if not ok then
		reportError(err)
	end

	-- the view swallows its own errors and keeps the last one: told once per message, then given back
	local swallowed = View.LastError

	if swallowed ~= nil then
		reportError(swallowed)
		View.LastError = nil
	end
end

function Panel:Draw(x, y, scale)
	self.mapPending = false

	local ok, err = pcall(drawMap, self, x, y, scale)

	if not ok then
		reportError(err)
		self.mapPending = false
	end

	-- the map is drawn by the movie's own drawing, in the middle of the Root clip (a rebuilt clip lost the hook: it is put back)
	local main = self.main

	if self.mapPending then
		if not self.mapHook then
			self.mapHook = function() drawPendingMap(self) end
		end

		if main.drawBefore ~= self.mapHook or main.drawBeforeDepth ~= Radar.MAP_DEPTH then
			main.drawBefore, main.drawBeforeDepth = self.mapHook, Radar.MAP_DEPTH
		end
	end

	Flash.Draw(self.root, x, y, scale)

	-- a movie drawing that did not reach the hook leaves no map to draw later: it would be on top
	self.mapPending = false
end
