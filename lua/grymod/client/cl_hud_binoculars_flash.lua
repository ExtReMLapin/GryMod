-- The binoculars drawn from the original Scaleform movie (HUD_Binoculars), see cl_flash.lua. In GryMod they are the
-- Half-Life 2 suit zoom (the zoom key): the movie shows while it is held, with the distance of what is aimed at,
-- the zoom factor and the world position. Hand-ported parts of its ActionScript: setVisible, closeBinoculars,
-- setPosition, setDistance, setZoomMode, and the horizon ladder (Attitude._y, sent by the game's code every frame). Not
-- ported: the target lock icons (hidden). Added from the original's code, each with its own switch (see
-- docs/superpowers/plans/2026-11-21-binoculars-features.md): the aim rules (4 rays 0.3 m off the centre, 300 m, the
-- distance to the entity itself), the sounds of opening and closing with the ambience loop, and the scan that tags an NPC
-- aimed at for 0.55 s (the radar shows it).

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Bino = {}
GryMod.FlashBinoculars = Bino

Bino.MOVIE = "hud_binoculars"

local Instance = {}
Instance.__index = Instance

-- World units in a metre (the same ratio as the original game's scale: 1 unit = 1.905 cm).
Bino.UNITS_PER_METRE = 52.49

-- The aim rules of the original (hud_binocsScanningWidth 0.3, a ray 300 m long, hud_radarScanningDelay 0.55 and the
-- 0.05 s that an aimed entity waits before its scan queues): see the features note.
Bino.RAY_OFFSET = 0.3 * Bino.UNITS_PER_METRE
Bino.RANGE = 300 * Bino.UNITS_PER_METRE
Bino.SCAN_SECONDS = 0.55
Bino.SCAN_DEBOUNCE = 0.05

-- one saved switch for each addition: the binoculars are the original's whatever they say, these only choose the extras
local SoundsConVar = CreateClientConVar("gry_binoculars_sounds", "1", true, false, "The binoculars' sounds: opening, closing, the ambience loop, a target locked")
local AimConVar = CreateClientConVar("gry_binoculars_aim", "1", true, false, "The original's aim rules: four rays 0.3 m off the centre, 300 m, the distance to the entity aimed at (off: one ray, 1000 m, the distance to the point hit)")
local HorizonConVar = CreateClientConVar("gry_binoculars_horizon", "1", true, false, "The binoculars' horizon ladder follows where you look")
local TagConVar = CreateClientConVar("gry_binoculars_tag", "1", true, false, "An NPC aimed at through the binoculars for half a second is tagged: the radar shows it")

function Bino.SoundsEnabled() return SoundsConVar:GetBool() end
function Bino.AimRules() return AimConVar:GetBool() end
function Bino.HorizonEnabled() return HorizonConVar:GetBool() end
function Bino.TagEnabled() return TagConVar:GetBool() end

-- The mode (1 to 4, shown as X02 to X08) of a zoom: the factor is the ratio of the tangents of the half fields
-- of view, and each mode covers two factors.
function Bino.ZoomModeFor(defaultFov, fov)
	if type(defaultFov) ~= "number" or type(fov) ~= "number" or fov ~= fov or defaultFov ~= defaultFov or fov <= 0 then
		return 1
	end

	local factor = math.tan(math.rad(defaultFov) / 2) / math.tan(math.rad(fov) / 2)

	return math.Clamp(math.floor(factor / 2), 1, 4)
end

-- The two numbers setDistance wants (whole metres, hundredths), (0, 0) when nothing is aimed at; the display has
-- three digits.
function Bino.MetresFrom(units)
	if type(units) ~= "number" or units ~= units or units <= 0 then
		return 0, 0
	end

	local metres = units / Bino.UNITS_PER_METRE

	if metres >= 1000 then
		return 999, 99
	end

	local int = math.floor(metres)

	return int, math.floor((metres - int) * 100 + 1e-6)
end

-- One coordinate of the readout: the original prints a number as digit groups, DD"MM'SS.hh (not base 60: the seconds go
-- on past 59). The number is 50155927 at the origin for the first one and 10647257 for the second, and grows by ten
-- per metre (the metres times ten, cut toward zero).
local ORIGIN_N, ORIGIN_W = 50155927, 10647257

local function cut(value)
	-- the epsilon keeps 5 metres at 50, whatever the division by the scale did to the last bit
	if value >= 0 then
		return math.floor(value + 1e-6)
	end

	return math.ceil(value - 1e-6)
end

local function group(number)
	return string.format("%02d\"%02d'%02d.%02d", math.floor(number / 1000000), math.floor((number % 1000000) / 10000),
		math.floor((number % 10000) / 100), number % 100)
end

-- setPosition's two strings for a world position: the first is "N" and follows x, the second "W" and follows y.
function Bino.PositionStrings(position)
	local x, y = position.x / Bino.UNITS_PER_METRE, position.y / Bino.UNITS_PER_METRE
	local north, west = Flash.Localise("@ui_N"), Flash.Localise("@ui_W")

	return group(ORIGIN_N + cut(x * 10)) .. " " .. north, group(ORIGIN_W + cut(y * 10)) .. " " .. west
end

-- The horizon ladder's place in the movie (Root.Binoculars.Attitude._y): forward.z * 360 + 336 every frame, with no easing.
function Bino.HorizonY(forwardZ)
	if type(forwardZ) ~= "number" or forwardZ ~= forwardZ then
		return 336
	end

	return math.Clamp(forwardZ, -1, 1) * 360 + 336
end

-- The rays that look for what is aimed at run along the view from the corners of a square 0.3 m each way around the eye,
-- in the original's order: right and up, right and down, left and down, left and up. The original casts only these four
-- (its characters have capsules wider than 0.3 m, so one standing in the middle is hit by all four); in this game the
-- hitboxes are narrower and a character exactly in the middle would be missed by the four of them (measured: citizen 15 m
-- ahead, 16 units from each ray, found by none), so the ray along the eye's own line is cast too, and comes LAST: the
-- number read when no entity is found is the last ray's hit, as in the original, and so is the centre's here.
function Bino.RayOrigins(eye, right, up, width)
	local r, u = right * width, up * width

	return {eye + r + u, eye + r - u, eye - r - u, eye - r + u, eye}
end

-- What the four rays say: rays is a list of {hit, distance, entity} (hit: found something that is not the sky; entity:
-- an entity that is not the world), centre(entity) the distance to an entity. The first ray that found an entity gives
-- the distance to that entity (not to the point hit); with none, the hit of the LAST ray gives the distance, and a last
-- ray that found nothing gives none whatever the others did. Returns the distance in world units (or nil) and the entity.
function Bino.AimedDistance(rays, centre)
	for i = 1, #rays do
		local ray = rays[i]

		if ray.hit and ray.entity then
			return centre(ray.entity), ray.entity
		end
	end

	local last = rays[#rays]

	if last and last.hit then
		return last.distance, nil
	end

	return nil, nil
end

-- How many rays are cast and how far: the original's four of 300 m (and the centre one, see RayOrigins), or the port's earlier
-- single one of 1000 m.
function Bino.TraceCount()
	return Bino.AimRules() and 5 or 1
end

function Bino.TraceLength()
	return Bino.AimRules() and Bino.RANGE or 1000 * Bino.UNITS_PER_METRE
end

function Bino.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local bino = root:Find("Root.Binoculars")

	if not bino then
		return nil
	end

	for _, name in ipairs({"Line", "Over", "Text"}) do
		local holder = root:Child(name)

		if holder then
			holder:SetVisible(false)
		end
	end

	return setmetatable({
		root = root,
		bino = bino,
		shown = false,
		closing = false,
		zoom = 1,
		north = "000° 000.00 N",
		west = "000° 000.00 W",
		metres = 0,
		hundredths = 0,
		horizon = nil
	}, Instance)
end

function Instance:IsShown()
	return self.shown
end

-- setVisible(true, true): the intro plays from its first frame.
function Instance:Show()
	if self.shown and not self.closing then
		return
	end

	self.shown = true
	self.closing = false
	self.bino:GotoAndPlay(1)
	self:_apply()
end

-- closeBinoculars(): the close animation; the binoculars are hidden at its end.
function Instance:Close()
	if not self.shown or self.closing then
		return
	end

	self.closing = true
	self.bino:GotoAndPlay("close")
end

function Instance:SetZoomMode(mode)
	self.zoom = mode
	self:_applyZoom()
end

function Instance:SetPosition(north, west)
	self.north, self.west = north, west
	self:_applyPosition()
end

function Instance:SetDistance(metres, hundredths)
	self.metres, self.hundredths = metres, hundredths
	self:_applyDistance()
end

-- Root.Binoculars.Attitude._y (the horizon ladder): the game's code sends it every frame, from the pitch of the view.
function Instance:SetHorizon(y)
	self.horizon = y
	self:_applyHorizon()
end

function Instance:_applyHorizon()
	local attitude = self.horizon and self.bino:Child("Attitude")

	if attitude then
		attitude:SetY(self.horizon)
	end
end

function Instance:_applyZoom()
	local zoom = self.bino:Find("Zoom.Colorset")

	if zoom then
		zoom:SetText("Zoom", "X0" .. self.zoom * 2)
	end
end

function Instance:_applyPosition()
	local north, west = self.bino:Find("DegreeN.Colorset"), self.bino:Find("DegreeW.Colorset")

	if north then
		north:SetText("DegreeN", self.north)
	end

	if west then
		west:SetText("DegreeW", self.west)
	end
end

-- setDistance(int, float): three digits (the leading zeros are shown dim), two decimals, the dot and the M; with
-- nothing aimed at, the digits are blank and the icon shows.
function Instance:_applyDistance()
	local d = self.bino:Find("TargetDistance.Colorset")

	if not d then
		return
	end

	local int, frac = self.metres, self.hundredths
	local digits = {math.floor(int / 100), math.floor((int % 100) / 10), int % 10}
	local leading = true

	for i = 0, 2 do
		local clip = d:Child("ObjNumber" .. i)
		local digit = digits[i + 1]

		if clip then
			leading = leading and digit == 0 and (i < 2 or int == 0)

			-- a leading zero is a dim one (frame 2, its text in "Low"), the others are plain digits (frame 1)
			if digit == 0 and leading then
				clip:GotoAndStop(2)
				local low = clip:Child("Low")

				if low then
					low:SetText("ObjNumber" .. i, "0")
				end
			else
				leading = false
				clip:GotoAndStop(1)
				clip:SetText("ObjNumber" .. i, tostring(digit))
			end
		end
	end

	d:SetText("ObjNumber4", tostring(math.floor((frac % 100) / 10)))
	d:SetText("ObjNumber5", tostring(frac % 10))

	local icon = d:Child("Icon")

	if int == 0 and frac == 0 then
		for i = 0, 2 do
			local clip = d:Child("ObjNumber" .. i)

			if clip then
				clip:SetText("ObjNumber" .. i, "")
				local low = clip:Child("Low")

				if low then
					low:SetText("ObjNumber" .. i, "")
				end
			end
		end

		d:SetText("ObjNumber4", "")
		d:SetText("ObjNumber5", "")
		d:SetText("Dot", "")
		d:SetText("MTEXT", "")

		if icon then icon:SetVisible(true) end
	else
		d:SetText("Dot", ".")
		d:SetText("MTEXT", "M")

		if icon then icon:SetVisible(false) end
	end
end

-- The target lock icons (the brackets and the lock symbol) are placed by the game's code on what it locks onto; with
-- nothing locked they sit at the corner of the stage, so they stay hidden. The lock symbol has no instance name.
local LOCK_SYMBOL = 51

function Instance:_hideTargets()
	for _, entry in ipairs(self.bino:Entries()) do
		if entry.clip and ((entry.name and string.find(entry.name, "^TargetIcon")) or entry.id == LOCK_SYMBOL) then
			entry.clip:SetVisible(false)
		end
	end
end

function Instance:_apply()
	self:_hideTargets()
	self:_applyZoom()
	self:_applyPosition()
	self:_applyDistance()
	self:_applyHorizon()
end

function Instance:Update(dt)
	if not self.shown then
		return
	end

	self.root:Advance(dt)

	-- the frames rebuild the clips (the intro, the close): say the values again while the timeline moves
	local frame = self.bino:CurrentFrame()

	if frame ~= self.lastFrame then
		self.lastFrame = frame
		self:_apply()
	end

	if self.closing and (not self.bino.playing or frame >= self.bino.n) then
		self.shown = false
		self.closing = false
		self.lastFrame = nil
	end
end

function Instance:Draw(x, y, scale)
	if self.shown then
		Flash.Draw(self.root, x, y, scale)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Sounds: the original plays binocular_select and starts binocular_ambience (a loop) when the binoculars come up, and
-- plays binocular_deselect and stops the loop when they go; the zoom steps' own sounds belong to the wheel, which the
-- Half-Life 2 zoom has not (not wired).
-- ---------------------------------------------------------------------------------------------------------

Bino.Sounds = {
	select = "grymod/binoculars/binocular_select.wav",
	deselect = "grymod/binoculars/binocular_deselect.wav",
	loop = "grymod/binoculars/binocular_ambience.wav",
	locked = "grymod/binoculars/binocular_tagged.wav"
}

-- What to do when the binoculars go from wanted to not wanted or back: a list of cue names.
function Bino.SoundCues(wasWanted, wanted)
	if wanted and not wasWanted then
		return {"select", "loop_start"}
	end

	if wasWanted and not wanted then
		return {"deselect", "loop_stop"}
	end

	return {}
end

-- the ambience loop: a channel made once (the loading is asynchronous), played from silence and brought up by the frame
local loop = {channel = nil, loading = false, playing = false, start = 0}

-- the volume of the loop: the mix's level for its file, brought up over the first hundredths of a second (a loop that
-- starts at once at its level clicks)
function Bino.LoopVolume(elapsed)
	return GryMod.SoundMix.Volume(Bino.Sounds.loop) * GryMod.SoundMix.FadeIn(elapsed)
end

function Bino.StartLoop()
	loop.playing = true
	loop.start = GryMod.SoundMix.Now()

	if IsValid(loop.channel) then
		loop.channel:SetTime(0)
		loop.channel:SetVolume(0)
		loop.channel:Play()

		return
	end

	if loop.loading then
		return
	end

	loop.loading = true

	sound.PlayFile("sound/" .. Bino.Sounds.loop, "noblock noplay", function(created)
		loop.loading = false

		if not IsValid(created) then
			return
		end

		loop.channel = created
		created:EnableLooping(true)

		if loop.playing then
			loop.start = GryMod.SoundMix.Now()
			created:SetVolume(0)
			created:Play()
		end
	end)
end

function Bino.StopLoop()
	loop.playing = false

	if IsValid(loop.channel) then
		loop.channel:SetVolume(0)
		loop.channel:Pause()
	end
end

local audio = {wanted = false, looping = false}

function Bino.AudioReset()
	audio.wanted, audio.looping = false, false
end

-- Once per frame: wanted says whether the binoculars are up. The sounds go through GryMod.PlaySound (the mix's level and
-- pitch); with the sounds off nothing plays and a loop that was going stops, and what is up when they come back on
-- is not announced again.
function Bino.AudioStep(wanted)
	local cues = Bino.SoundCues(audio.wanted, wanted)
	audio.wanted = wanted

	if not Bino.SoundsEnabled() then
		if audio.looping then
			audio.looping = false
			Bino.StopLoop()
		end

		return
	end

	for i = 1, #cues do
		local cue = cues[i]

		if cue == "loop_start" then
			audio.looping = true
			Bino.StartLoop()
		elseif cue == "loop_stop" then
			audio.looping = false
			Bino.StopLoop()
		else
			GryMod.PlaySound(Bino.Sounds[cue])
		end
	end

	if loop.playing and IsValid(loop.channel) then
		loop.channel:SetVolume(Bino.LoopVolume(GryMod.SoundMix.Now() - loop.start))
	end
end

-- The sound of a scan that ends on an entity (binocular_target_locked, at the pitch of its event).
function Bino.PlayLocked()
	if Bino.SoundsEnabled() then
		GryMod.PlaySound(Bino.Sounds.locked)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The scan (CHUDRadar::UpdateScanner): an entity aimed at for 0.05 s joins a queue; the scans run one at a time, 0.55 s
-- each (they go on if the aim leaves the entity); the entity at the end of its scan is tagged.
-- ---------------------------------------------------------------------------------------------------------

local EPSILON = 1e-9

function Bino.NewScan()
	return {target = nil, debounce = 0, queue = {}, current = nil, timer = 0}
end

function Bino.ScanReset(st)
	st.target, st.debounce, st.queue, st.current, st.timer = nil, 0, {}, nil, 0
end

-- One frame: target is what the aim finds (nil for nothing), accepts(entity) whether an entity may be scanned (it is asked
-- when the debounce ends, when a scan starts and when it ends). Returns the entity whose scan just ended, or nil.
function Bino.ScanStep(st, target, dt, accepts)
	local finished

	if target == nil then
		st.target = nil
	elseif target ~= st.target then
		st.target = target
		st.debounce = Bino.SCAN_DEBOUNCE
	elseif st.debounce > 0 then
		st.debounce = st.debounce - dt

		if st.debounce <= EPSILON then
			st.debounce = 0

			if target ~= st.current and accepts(target) then
				local queued = false

				for i = 1, #st.queue do
					queued = queued or st.queue[i] == target
				end

				if not queued then
					st.queue[#st.queue + 1] = target
				end
			end
		end
	end

	if st.timer > 0 then
		st.timer = st.timer - dt

		if st.timer <= EPSILON then
			local entity = st.current
			st.timer, st.current = 0, nil

			if entity ~= nil and accepts(entity) then
				finished = entity
			end
		end
	end

	if st.timer <= 0 then
		while #st.queue > 0 do
			local entity = table.remove(st.queue, 1)

			if accepts(entity) then
				st.current, st.timer = entity, Bino.SCAN_SECONDS

				break
			end
		end
	end

	return finished
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game: the Half-Life 2 suit zoom (the zoom key) shows the binoculars
-- ---------------------------------------------------------------------------------------------------------

local binoculars
local lastTime
local fed = {}
-- the movie could not be loaded: the Half-Life 2 zoom overlay must stay then
local missing = false
local scan = Bino.NewScan()
-- the entities this player has tagged (the server keeps them until their death, or the player's)
local tagged = setmetatable({}, {__mode = "k"})

-- The HUD is on and so are the binoculars (gry_hud_binoculars).
function Bino.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("binoculars"))
end

local enabled = Bino.Enabled

-- Whether the player is zooming: the suit zoom key held, alive, not in a menu.
function Bino.Wanted(ply)
	return IsValid(ply) and ply:Alive() and ply:KeyDown(IN_ZOOM)
end

-- An entity whose own position reads as a distance: the living (NPCs, players) and vehicles. A prop's origin can be
-- anywhere in it and a brush entity's far off the surface that was hit: they read as the point hit.
local function aimable(entity)
	return IsValid(entity) and not entity:IsWorld() and (entity:IsNPC() or entity:IsPlayer() or entity:IsNextBot() or entity:IsVehicle())
end

local trace = {}
local traced = {}
local rays = {{}, {}, {}, {}, {}}
local aimer

local function centreOf(entity)
	return aimer:GetPos():Distance(entity:GetPos())
end

-- The distance (world units, or nil) and the entity of what the player aims at, by the original's rules or the earlier
-- single ray (see Bino.TraceCount).
local function aim(ply)
	local eye = ply:EyePos()
	local angles = ply:EyeAngles()
	local forward = angles:Forward()
	local length = Bino.TraceLength()

	trace.filter, trace.mask, trace.output = ply, MASK_SHOT, traced

	if not Bino.AimRules() then
		trace.start, trace.endpos = eye, eye + forward * length
		util.TraceLine(trace)

		return traced.Hit and not traced.HitSky and eye:Distance(traced.HitPos) or nil, aimable(traced.Entity) and traced.Entity or nil
	end

	local origins = Bino.RayOrigins(eye, angles:Right(), angles:Up(), Bino.RAY_OFFSET)
	local along = forward * length

	for i = 1, #origins do
		trace.start, trace.endpos = origins[i], origins[i] + along
		util.TraceLine(trace)

		local ray = rays[i]
		ray.hit = traced.Hit and not traced.HitSky
		ray.distance = ray.hit and origins[i]:Distance(traced.HitPos) or 0
		ray.entity = ray.hit and aimable(traced.Entity) and traced.Entity or nil
	end

	aimer = ply

	return Bino.AimedDistance(rays, centreOf)
end

-- An NPC that is alive and not tagged yet may be scanned.
local function scannable(entity)
	return IsValid(entity) and entity:IsNPC() and entity:Health() > 0 and not tagged[entity]
end

-- The scan ended on an entity: its sound, and the server tags it (the radar shows it).
local function locked(entity)
	tagged[entity] = true
	Bino.PlayLocked()
	net.Start("gry_radar_scan")
	net.WriteUInt(entity:EntIndex(), 13)
	net.SendToServer()
end

local function feed(ply, dt)
	local defaultFov = ply:GetInfoNum("fov_desired", 75)
	local zoom = Bino.ZoomModeFor(defaultFov, ply:GetFOV())

	if fed.zoom ~= zoom then
		fed.zoom = zoom
		binoculars:SetZoomMode(zoom)
	end

	local north, west = Bino.PositionStrings(ply:GetPos())

	if fed.north ~= north or fed.west ~= west then
		fed.north, fed.west = north, west
		binoculars:SetPosition(north, west)
	end

	local units, entity = aim(ply)
	local metres, hundredths = Bino.MetresFrom(units)

	if fed.metres ~= metres or fed.hundredths ~= hundredths then
		fed.metres, fed.hundredths = metres, hundredths
		binoculars:SetDistance(metres, hundredths)
	end

	if Bino.HorizonEnabled() then
		local y = Bino.HorizonY(ply:EyeAngles():Forward().z)

		if fed.horizon ~= y then
			fed.horizon = y
			binoculars:SetHorizon(y)
		end
	end

	if Bino.TagEnabled() then
		local done = Bino.ScanStep(scan, entity, dt, scannable)

		if done then
			locked(done)
		end
	else
		Bino.ScanReset(scan)
	end
end

hook.Add("HUDPaint", "GRYBINOCULARS", function()
	if not enabled() then
		Bino.AudioStep(false)
		Bino.ScanReset(scan)

		return
	end

	local ply = LocalPlayer()
	local wanted = Bino.Wanted(ply)

	if not IsValid(ply) or not ply:Alive() then
		tagged = setmetatable({}, {__mode = "k"})
	end

	if not binoculars then
		if not wanted then
			Bino.AudioStep(false)

			return
		end

		binoculars = Bino.New(Flash.Load(Bino.MOVIE))

		if not binoculars then
			missing = true

			return
		end

		missing = false

		fed, lastTime = {}, nil
	end

	Bino.AudioStep(wanted)

	if wanted then
		binoculars:Show()
	else
		binoculars:Close()
		Bino.ScanReset(scan)
	end

	if not binoculars:IsShown() then
		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	if wanted then
		feed(ply, dt)
	end

	binoculars:Update(dt)

	-- the stage is 1366 x 768: scaled to the screen height, centred
	local scale = ScrH() / 768
	binoculars:Draw((ScrW() - 1366 * scale) / 2, 0, scale)
end)

-- The Half-Life 2 suit zoom has its own overlay (CHudZoom, the black ring); our binoculars replace it while they
-- are on. Hiding the element does not stop the zoom itself (see the HUD element list of the wiki).
hook.Add("HUDShouldDraw", "GRYBINOCULARSHIDEZOOM", function(name)
	if name == "CHudZoom" and not missing and Bino.Enabled() and Bino.Wanted(LocalPlayer()) then
		return false
	end
end)

function Bino.Reset()
	if binoculars then
		Flash.ReleaseClip(binoculars.root)
	end

	binoculars = nil
	missing = false
	Bino.StopLoop()
	Bino.AudioReset()
	Bino.ScanReset(scan)
end
