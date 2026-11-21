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
local VignetteConVar = CreateClientConVar("gry_binoculars_vignette", "1", true, false, "The dark vignette of the binoculars fades out as they close, in the 14 frames of the original's film (off: it goes with the picture, at once)")
local TagConVar = CreateClientConVar("gry_binoculars_tag", "1", true, false, "An NPC aimed at through the binoculars for half a second is tagged: the radar shows it")
local MoodConVar = CreateClientConVar("gry_binoculars_mood", "1", true, false, "The original's cryvision sound mood while the binoculars are up: explosions, collisions and vehicles are lowered (in and out in half a second)")
local SilhouetteConVar = CreateClientConVar("gry_binoculars_silhouette", "1", true, false, "The NPC scanned through the binoculars is outlined in pale blue from the last 0.3 s of its scan until the binoculars come down (at most 8 at once; needs the tag switch: the scan is the tag's)")
local StagesConVar = CreateClientConVar("gry_binoculars_stages", "1", true, false, "The original's zoom stages (2x, 4x, 8x) with the mouse wheel while the binoculars are up, a straight 0.2 s to open and close and 0.055 s between two stages (off: the Half-Life 2 zoom, one fixed field of view). Changes how the mouse feels; on by default")

local VisionConVar = CreateClientConVar("gry_binoculars_vision", "0", true, false, "The renderer's full-screen binoculars vision: a cool tint (0.7, 0.8, 1.0), fine scan lines (period of 4 pixels) and a darkening towards the edges (1 - 0.6 * distance from the centre). The original shows it in the High quality only and the film already has its own vignette: the edges get darker twice. Off by default")
local SwayConVar = CreateClientConVar("gry_binoculars_sway", "1", true, false, "The original's slow sway of the view while the binoculars are up (a figure of eight, strongest at the start and settling in about a second, less when crouching or in strength mode). Moves the view (on by default)")

-- The stages are on with their own switch, and always while the own zoom has a key (gry_zoom_own, see cl_suit_zoom.lua): the wheel is
-- its interface.
function Bino.StagesEnabled()
	return StagesConVar:GetBool() or (GryMod.SuitZoom ~= nil and GryMod.SuitZoom.HasKey())
end

function Bino.SwayEnabled() return SwayConVar:GetBool() end
function Bino.VisionEnabled() return VisionConVar:GetBool() end
function Bino.SilhouetteEnabled() return SilhouetteConVar:GetBool() end
function Bino.MoodEnabled() return MoodConVar:GetBool() end
function Bino.SoundsEnabled() return SoundsConVar:GetBool() end
function Bino.AimRules() return AimConVar:GetBool() end
function Bino.HorizonEnabled() return HorizonConVar:GetBool() end
function Bino.TagEnabled() return TagConVar:GetBool() end
function Bino.VignetteFade() return VignetteConVar:GetBool() end

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

-- The vignette: the film's full-screen black gradient (clear in the middle, 0.93 black in the corners), held by the clip
-- called Alpha beside the Binoculars clip. Its own timeline is one still frame at full strength, and a "close" label
-- that fades it out in 14 frames; the Binoculars clip starts that fade from its frame 26 (its script
-- `_root.Root.Alpha.gotoAndPlay("close")`), the call the converted film does not carry.
function Instance:_vignette()
	return self.root:Find("Root.Alpha")
end

-- setVisible(true, true): the intro plays from its first frame; the vignette is there at full strength at once, as in
-- the film (it has no fade in).
function Instance:Show()
	if self.shown and not self.closing then
		return
	end

	self.shown = true
	self.closing = false
	self.bino:GotoAndPlay(1)

	local vignette = self:_vignette()

	if vignette then
		vignette:GotoAndStop(1)
	end

	self:_apply()
end

-- closeBinoculars(): the close animation; the binoculars are hidden at its end. The vignette fades out with it
-- (Bino.VignetteFade), otherwise it stays until the picture is gone.
function Instance:Close()
	if not self.shown or self.closing then
		return
	end

	self.closing = true
	self.bino:GotoAndPlay("close")

	local vignette = self:_vignette()

	if vignette and Bino.VignetteFade() then
		vignette:GotoAndPlay("close")
	end
end

-- The picture is gone at once, with no closing animation (a death, a menu, a vehicle): the next Show plays the intro again.
function Instance:Hide()
	self.shown = false
	self.closing = false
	self.lastFrame = nil
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
	locked = "grymod/binoculars/binocular_tagged.wav",
	zoom_in = "grymod/binoculars/binocular_zoom_in.wav",
	zoom_out = "grymod/binoculars/binocular_zoom_out.wav"
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

-- The cryvision sound mood (GryMod.SoundMix.Moods): on while the binoculars are up, off when they go (or the switch is off).
-- Said every frame: the mix does nothing for a mood that is already in the state asked for.
function Bino.MoodStep(wanted)
	GryMod.SoundMix.MoodSet("cryvision", wanted and Bino.MoodEnabled() or false)
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
-- The silhouette (CHUDRadar::UpdateScanner, constant 0x392644c4; FUN_391cffa0 highlights the entity, the CryVision silhouette):
-- from the last 0.3 s of a scan the entity being scanned is outlined, and the outline STAYS: the entry has no end time (-1.0,
-- never expires) and FUN_391d04a0 clears the entries only when the binoculars come down (DEDUCED from that, see the research
-- note 8.5). So the scan state machine only gives the start; the outlined entities are kept in a set (at most
-- SILHOUETTE_MAX, the oldest dropped first) until the binoculars are let go, the entity is dead or invalid, or a reset.
-- ---------------------------------------------------------------------------------------------------------

Bino.SILHOUETTE_SECONDS = 0.3
Bino.SILHOUETTE_MAX = 8

-- The outline: the vision parameters the original gives the entity's render proxy are (0.8, 0.8, 1.0, 0.5), a pale blue-white
-- (204, 204, 255 in 8 bits), VERIFIED in the research note 8.5. The thickness (about 3 pixels, then a glow) is the engine's
-- pass: a halo of two passes of 3 pixels is the nearest GMod has.
Bino.SilhouetteColor = Color(204, 204, 255, 255)
Bino.SILHOUETTE_BLUR = 3
Bino.SILHOUETTE_PASSES = 2

-- The entities outlined now, oldest first (see Bino.SilhouetteAdd).
Bino.Silhouettes = {}

-- The entity to outline for this scan state, or nil: the one being scanned, with at most 0.3 s of the countdown left (and
-- some), while valid(entity) says it still may be (alive).
function Bino.SilhouetteTarget(st, valid)
	local entity = st.current

	if entity ~= nil and st.timer > 0 and st.timer <= Bino.SILHOUETTE_SECONDS + EPSILON and valid(entity) then
		return entity
	end

	return nil
end

-- Puts an entity in the set (once), dropping the oldest ones past SILHOUETTE_MAX.
function Bino.SilhouetteAdd(set, entity)
	if entity == nil then
		return set
	end

	for i = 1, #set do
		if set[i] == entity then
			return set
		end
	end

	set[#set + 1] = entity

	while #set > Bino.SILHOUETTE_MAX do
		table.remove(set, 1)
	end

	return set
end

-- Drops from the set the entities that valid() refuses (dead, gone), keeping the order; the same table comes back.
function Bino.SilhouetteLive(set, valid)
	local kept = 0

	for i = 1, #set do
		local entity = set[i]

		if valid(entity) then
			kept = kept + 1
			set[kept] = entity
		end
	end

	for i = #set, kept + 1, -1 do
		set[i] = nil
	end

	return set
end

function Bino.SilhouetteClear(set)
	for i = #set, 1, -1 do
		set[i] = nil
	end

	return set
end

-- An NPC that is alive and exists.
function Bino.SilhouetteValid(entity)
	return entity ~= nil and IsValid(entity) and entity:IsNPC() and entity:Health() > 0
end

-- ---------------------------------------------------------------------------------------------------------
-- The zoom stages (option): in the original the zoom class (vtable 0x3927e0b8) has the stages 2x, 4x, 8x of Binoculars.xml,
-- the wheel steps them (sounds 7 in / 8 out, FUN_3917f9f0 / FUN_3917fad0) and the field of view moves in a straight line
-- over zoom_in_time / zoom_out_time (0.2 s, FUN_3917b430). The engine's zoom here is the suit's: one fixed field of view
-- eased over 0.4 s. Owning the view while the binoculars are up needs a CalcView (the field of view), PlayerBindPress (the
-- wheel) and AdjustMouseSensitivity (the engine scales the mouse for ITS field of view, 25 degrees, not ours). All of it
-- is a state machine in the pure functions below; the hooks only feed it. DEDUCED: the stages are magnifications (the ratio
-- of the tangents of the half fields, as the label's rule), the first stage is up at the opening, the wheel stops at the ends
-- (the original's stage change wraps, whether the wheel does was not read), and the stage starts again at 2x each time.
-- ---------------------------------------------------------------------------------------------------------

Bino.ZOOM_STAGES = {2, 4, 8}
Bino.ZOOM_IN_TIME = 0.2
Bino.ZOOM_OUT_TIME = 0.2
-- a step from one stage to the next: the zoom class's stage time, default 0.055 s (0x3927dfec), which Binoculars.xml does not set
-- (DEDUCED, research note 8.3); opening and closing keep zoom_in_time / zoom_out_time
Bino.ZOOM_STEP_TIME = 0.055
-- how long the override goes on at most after the key is let go, waiting for the engine's own return to the base
Bino.ZOOM_HOLD_MAX = 0.6
-- the film's mode (X02, X04, X06) of each stage: the original's last stage reads X06 (FUN_391cd590), not X08
Bino.StageModes = {1, 2, 3}

-- The field of view (degrees) of a magnification at a base field of view.
function Bino.StageFov(base, factor)
	return math.deg(2 * math.atan(math.tan(math.rad(base) / 2) / factor))
end

local function validFov(fov)
	return type(fov) == "number" and fov == fov and fov > 0 and fov < 180
end

-- The film's mode for the field of view in force: the last stage whose magnification it has reached, the first one before
-- any (the label is decided every frame from the field of view, so it changes in the middle of a transition).
function Bino.StageModeFor(base, fov)
	local mode = Bino.StageModes[1]

	if not validFov(base) or not validFov(fov) then
		return mode
	end

	local factor = math.tan(math.rad(base) / 2) / math.tan(math.rad(fov) / 2)

	for i, stage in ipairs(Bino.ZOOM_STAGES) do
		if factor >= stage - 1e-6 then
			mode = Bino.StageModes[i]
		end
	end

	return mode
end

function Bino.NewZoom()
	return {stage = 0, active = false, fov = nil, from = 0, to = 0, start = 0, duration = 0, closeStart = nil, lastStage = 0}
end

function Bino.ZoomReset(z)
	z.stage, z.active, z.fov, z.from, z.to, z.start, z.duration, z.closeStart, z.lastStage = 0, false, nil, 0, 0, 0, 0, nil, 0
end

local function zoomFovAt(z, now)
	if z.duration <= 0 then
		return z.to
	end

	return z.from + (z.to - z.from) * math.Clamp((now - z.start) / z.duration, 0, 1)
end

-- One frame of the zoom: wanted is whether the binoculars are up, base the field of view without zoom, engineFov the one the
-- engine is using (it eases back to the base after the key is let go). Returns the field of view to give the view, or nil
-- when the override is not needed (nothing up, or over).
function Bino.ZoomStep(z, now, wanted, base, engineFov)
	if wanted then
		z.closeStart = nil

		if z.stage == 0 then
			z.stage = 1
		end
	elseif z.stage ~= 0 then
		z.stage = 0
		z.closeStart = now
	end

	if not z.active then
		if not wanted then
			return nil
		end

		z.active, z.fov, z.from, z.to, z.start, z.duration = true, base, base, base, now, 0
	end

	-- the field of view the stage wants (the base once the key is let go): a change starts a straight line from where it is
	local target = z.stage > 0 and Bino.StageFov(base, Bino.ZOOM_STAGES[z.stage]) or base

	if math.abs(target - z.to) > 1e-6 then
		local current = zoomFovAt(z, now)
		-- opening (from no stage) and closing (to none) take 0.2 s, a step between two stages 0.055 s
		local stepping = z.stage ~= 0 and z.lastStage ~= 0

		z.from, z.to, z.start = current, target, now
		z.lastStage = z.stage

		if stepping then
			z.duration = Bino.ZOOM_STEP_TIME
		else
			z.duration = target < current and Bino.ZOOM_IN_TIME or Bino.ZOOM_OUT_TIME
		end
	end

	z.fov = zoomFovAt(z, now)

	-- back at the base: the override ends once the engine's own return is done (it eases over 0.4 s), or too long after
	if z.stage == 0 and z.fov >= base - 1e-6 then
		local engineBack = type(engineFov) ~= "number" or engineFov >= base - 0.5

		if engineBack or now - (z.closeStart or now) >= Bino.ZOOM_HOLD_MAX then
			Bino.ZoomReset(z)

			return nil
		end
	end

	return z.fov
end

-- The wheel: invprev (up) goes to the next stage, invnext (down) to the previous. Returns whether the key is the wheel's and
-- a stage is up (the key is then taken, even at an end), and the cue of the sound when the stage changed.
function Bino.ZoomWheel(z, bind)
	if z.stage == 0 or (bind ~= "invprev" and bind ~= "invnext") then
		return false
	end

	local stage = z.stage + (bind == "invprev" and 1 or -1)

	if stage < 1 or stage > #Bino.ZOOM_STAGES then
		return true
	end

	z.stage = stage

	return true, bind == "invprev" and "zoom_in" or "zoom_out"
end

-- The fraction of the normal mouse sensitivity for the field of view in force (the engine's formula for its own zoom:
-- fov / default fov * zoom_sensitivity_ratio), nil while the stages are not up.
function Bino.SensitivityScale(z, base, ratio)
	if not z.active or not z.fov then
		return nil
	end

	return z.fov / base * ratio
end

-- The film's mode for the label: the stage's while the stages are up, else the Half-Life 2 zoom's own rule.
function Bino.ZoomLabelMode(z, base, engineFov)
	if z.active and z.fov then
		return Bino.StageModeFor(base, z.fov)
	end

	return Bino.ZoomModeFor(base, engineFov)
end

-- ---------------------------------------------------------------------------------------------------------
-- The sway of the zoom (option gry_binoculars_sway, on by default; research note 8.2 and recipe 8.6): the original's zoom class
-- (vtable 0x3927e0b8, slot 22, the function 0x3917aba0) turns the VIEW, never the field of view, by two angles that are a
-- deterministic figure of eight (no noise): with t the seconds since the zoom started and p = 0.3 t (mod 1),
--   pitch = 0.012 * k * sin(4 pi p), yaw = 0.015 * k * -cos(2 pi p), both in radians (the zoomSway block of Binoculars.xml),
--   k = max(0.2, 1 - t / 1.125) * (0.75 crouching, 0.5 lying down) * (0.75 in strength mode).
-- VERIFIED: the form and the numbers; DEDUCED: which angle is which and the stance and strength readings. The offsets are
-- absolute (recomputed each frame from t, never added up), so there is nothing to undo: the camera of one frame is the only
-- thing touched, through CalcView.
-- ---------------------------------------------------------------------------------------------------------

Bino.SWAY_PITCH = 0.012
Bino.SWAY_YAW = 0.015
Bino.SWAY_RATE = 0.3
-- stabilizeTime 1.5 * strengthScaleTime 0.75: the time the strength takes to fall to its floor (the floor is 0.2)
Bino.SWAY_SETTLE = 1.125
Bino.SWAY_MIN = 0.2
Bino.SWAY_CROUCH = 0.75
Bino.SWAY_PRONE = 0.5
Bino.SWAY_STRENGTH = 0.75

-- The pitch and yaw offsets (radians) t seconds after the zoom started.
function Bino.SwayOffset(t, crouch, prone, strength)
	if type(t) ~= "number" or t ~= t or t < 0 then
		return 0, 0
	end

	local phase = (Bino.SWAY_RATE * t) % 1
	local k = math.max(Bino.SWAY_MIN, 1 - t / Bino.SWAY_SETTLE)

	if prone then
		k = k * Bino.SWAY_PRONE
	elseif crouch then
		k = k * Bino.SWAY_CROUCH
	end

	if strength then
		k = k * Bino.SWAY_STRENGTH
	end

	return Bino.SWAY_PITCH * k * math.sin(4 * math.pi * phase), Bino.SWAY_YAW * k * -math.cos(2 * math.pi * phase)
end

function Bino.NewSway()
	return {t = 0, last = nil}
end

function Bino.SwayReset(s)
	s.t, s.last = 0, nil
end

-- One frame: wanted says whether the binoculars are up, now the clock. Returns the offsets, or nothing (and forgets the time:
-- the next raising starts at 0) while they are down. A long frame counts 0.1 s at most.
function Bino.SwayStep(s, wanted, now, crouch, prone, strength)
	if not wanted then
		Bino.SwayReset(s)

		return nil
	end

	s.t = s.t + math.min(now - (s.last or now), 0.1)
	s.last = now

	return Bino.SwayOffset(s.t, crouch, prone, strength)
end

-- The stance of the player: crouching, lying down (only for the addons that give a player an IsProne), the suit in strength mode.
function Bino.SwayStance(ply)
	local prone = isfunction(ply.IsProne) and ply:IsProne() or false
	local crouch = isfunction(ply.Crouching) and ply:Crouching() or false

	return crouch, prone, ply.NanosuitMode == GryMod.Modes.STRENGTH
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
Bino.ScanState = scan
-- the zoom stages' state (see Bino.ZoomStep)
local zoom = Bino.NewZoom()
Bino.ZoomState = zoom
-- the entities this player has tagged (the server keeps them until their death, or the player's)
local tagged = setmetatable({}, {__mode = "k"})

-- The HUD is on and so are the binoculars (gry_hud_binoculars).
function Bino.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("binoculars"))
end

local enabled = Bino.Enabled

-- Whether the player is zooming: alive and either the Half-Life 2 suit zoom key (IN_ZOOM) is held, as it always was, or the own zoom (a
-- zoom of its own on a key of its own, see cl_suit_zoom.lua) is open. One answer for both: the binoculars are one state, up when either
-- asks and down when neither does.
function Bino.Wanted(ply)
	if not IsValid(ply) or not ply:Alive() then
		return false
	end

	if ply:KeyDown(IN_ZOOM) then
		return true
	end

	local suit = GryMod.SuitZoom

	return suit ~= nil and suit.IsActive()
end

-- Whether the movie could not be loaded (the own zoom is then not offered).
function Bino.IsMissing()
	return missing
end

-- A vehicle or a mine (what is neither an NPC nor a nextbot and that the registry of tracked entities gives a radar rule) that the radar may
-- list, so that the binoculars may scan it: the server decides in the end (Radar.Scan), this only spares the sound of a lock it would
-- refuse. Not the vehicle the player sits in; nothing with the switch gry_radar_objects off.
function Bino.IsObject(entity)
	if not IsValid(entity) or entity:IsNPC() or entity:IsNextBot() or entity:IsPlayer() then
		return false
	end

	local switch = GetConVar("gry_radar_objects")

	if switch and not switch:GetBool() then
		return false
	end

	local API = GryMod.API
	local tracked = API and API.GetTracked and API.GetTracked(entity)

	if not tracked or tracked.radar == nil or tracked.radar == "never" or tracked.scan == false then
		return false
	end

	local ply = LocalPlayer()

	if IsValid(ply) and entity:IsVehicle() and ply:GetVehicle() == entity then
		return false
	end

	return true
end

-- An entity whose own position reads as a distance: the living (NPCs, players), vehicles and the mines. A prop's origin can be
-- anywhere in it and a brush entity's far off the surface that was hit: they read as the point hit.
local function aimable(entity)
	return IsValid(entity) and not entity:IsWorld() and (entity:IsNPC() or entity:IsPlayer() or entity:IsNextBot() or entity:IsVehicle() or Bino.IsObject(entity))
end

Bino.Aimable = aimable

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

-- Whether the binoculars may scan the entity: an NPC that is alive and not tagged yet, unless the registry of tracked entities
-- says scan = false for it; a nextbot only when the registry has an entry for it (the server decides in the end, Radar.Scan:
-- this only spares the sound of a lock the server would refuse). Without the registry (a hot reload) it is the NPC rule.
function Bino.Scannable(entity, isTagged)
	if isTagged or entity == nil or not IsValid(entity) then
		return false
	end

	local API = GryMod.API
	local tracked = API and API.GetTracked and API.GetTracked(entity)

	if entity:IsNPC() then
		if entity:Health() <= 0 then
			return false
		end
	elseif tracked and entity:IsNextBot() then
		-- a nextbot may have no health at all (0 of 0): only one that lost its health is dead
		if entity:Health() <= 0 and entity:GetMaxHealth() > 0 then
			return false
		end
	elseif not Bino.IsObject(entity) then
		-- (a vehicle or a mine: no health to look at)
		return false
	end

	return not (tracked and tracked.scan == false)
end

local function scannable(entity)
	return Bino.Scannable(entity, tagged[entity])
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
	local zoomMode = Bino.ZoomLabelMode(zoom, defaultFov, ply:GetFOV())

	if fed.zoom ~= zoomMode then
		fed.zoom = zoomMode
		binoculars:SetZoomMode(zoomMode)
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
	Bino.VisionStep(Bino.Wanted(LocalPlayer()))

	if not enabled() then
		Bino.AudioStep(false)
		Bino.MoodStep(false)
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
			Bino.MoodStep(false)

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
	Bino.MoodStep(wanted)

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

-- The outline of the entities scanned (see Bino.SilhouetteTarget): one halo for the whole set, drawn only while the
-- binoculars are wanted (asked here too: this runs before the HUD paints the frame in which the key is let go); with the
-- binoculars down (or the HUD off) the set is emptied, so they are not outlined again at the next opening.
function Bino.DrawSilhouette()
	local set = Bino.Silhouettes

	if not Bino.Enabled() or not Bino.Wanted(LocalPlayer()) then
		if #set > 0 then
			Bino.SilhouetteClear(set)
		end

		return
	end

	if not Bino.SilhouetteEnabled() then
		return
	end

	Bino.SilhouetteAdd(set, Bino.SilhouetteTarget(scan, Bino.SilhouetteValid))
	Bino.SilhouetteLive(set, Bino.SilhouetteValid)

	if #set > 0 then
		halo.Add(set, Bino.SilhouetteColor, Bino.SILHOUETTE_BLUR, Bino.SILHOUETTE_BLUR, Bino.SILHOUETTE_PASSES, true, false)
	end
end

hook.Add("PreDrawHalos", "GRYBINOCULARSSILHOUETTE", function()
	Bino.DrawSilhouette()
end)

-- ---------------------------------------------------------------------------------------------------------
-- The zoom stages' hooks (option gry_binoculars_stages, see Bino.ZoomStep). They only act while the stages are on, the
-- binoculars element is on and the zoom key is held (or its field of view is on its way back), and give the view back
-- to the other addons' hooks the rest of the time.
-- ---------------------------------------------------------------------------------------------------------

function Bino.Now() return RealTime() end

-- The engine's own scale of the mouse for a zoomed field of view (the Half-Life 2 client's zoom_sensitivity_ratio, 1 by default).
function Bino.ZoomRatio()
	local convar = GetConVar("zoom_sensitivity_ratio")

	return convar and convar:GetFloat() or 1
end

local function stagesOn()
	return Bino.StagesEnabled() and Bino.Enabled() and not missing
end

-- ---------------------------------------------------------------------------------------------------------
-- The full-screen vision (option gry_binoculars_vision, off by default; research note 8.1): the renderer's post effect CryVision
-- runs on the whole screen while the binoculars are up, but only with HDR rendering, i.e. in the High and Very High qualities. In
-- the shader's own terms (PostEffectsGame.cfx, BinocularViewFinal, no silhouettes): the picture times the tint (0.7, 0.8, 1.0),
-- times an interlacing (a triangle wave of the pixel row, period 4 pixels, times 1.5: rows 0 and 3 of each four at 1.3125, rows
-- 1 and 2 at 0.9375), times a vignette saturate(1 - 0.6 * distance from the centre in texture units). Reproduced in
-- RenderScreenspaceEffects (before the HUD, so the film is not tinted) with three multiplicative passes, all with the blend source *
-- destination + destination * source (2 * s * d, so that a gain above 1 is reachable): the tint at the gain of the bright rows over
-- the whole screen, then the dim rows (1 and 2 of each four) darkened by the ratio of the two gains with strips of two pixel rows, then
-- a small vignette texture stretched over the screen. The strips are drawn as rectangles: a 4-row texture tiled over the screen was
-- tried first and MEASURED to be sampled with a 5 to 6 rows period (the engine repeats a texel at each wrap). MEASURED on the test
-- client (hdr level 2): the framebuffer blends in LINEAR light (the doubling is worth only 2 ^ (1 / 2.2) = 1.37 on the pixel values
-- that are seen) and a 2D draw is also attenuated, by about 0.87 in linear light (0.80 on a pixel at a quarter of the range, 0.88 at
-- three quarters; even a white texel multiplies by 0.93, not 1), so the levels of the small textures are computed through the sRGB curves
-- and that attenuation ("linear" mode); where the blend is in gamma space and not attenuated the levels are simply half the gain
-- ("gamma" mode). The first frames of the vision probe the framebuffer once (a pixel) and choose the mode.
-- The masked blur of the original is NOT done: the direction of its mask is not verified. VERIFIED: the numbers; limits: 8-bit
-- banding, the gains above 1 clip at 255.
-- ---------------------------------------------------------------------------------------------------------

Bino.VISION_TINT = {0.7, 0.8, 1.0}
Bino.VISION_SCAN_GAIN = 1.5
Bino.VISION_PERIOD = 4
Bino.VISION_VIGNETTE = 0.6
Bino.VISION_VIGNETTE_SIZE = 64

-- The gain of the interlacing on a pixel row (sampled at the centre of the row).
function Bino.InterlaceGain(row)
	local frac = ((row + 0.5) / Bino.VISION_PERIOD) % 1

	return (0.5 + 0.5 * math.abs(2 * frac - 1)) * Bino.VISION_SCAN_GAIN
end

-- The three gains (red, green, blue) of a pixel row: the tint times the interlacing.
function Bino.VisionRowGains(row)
	local scan = Bino.InterlaceGain(row)
	local tint = Bino.VISION_TINT

	return tint[1] * scan, tint[2] * scan, tint[3] * scan
end

local function toByte(gain)
	return math.Clamp(math.floor(gain * 255 + 0.5), 0, 255)
end

-- The sRGB transfer curves (a value 0 to 1 in, a value 0 to 1 out).
function Bino.SrgbDecode(v)
	if v <= 0.04045 then
		return v / 12.92
	end

	return ((v + 0.055) / 1.055) ^ 2.4
end

function Bino.SrgbEncode(v)
	if v <= 0.0031308 then
		return v * 12.92
	end

	return 1.055 * v ^ (1 / 2.4) - 0.055
end

-- The level (0 to 1) of a texel that makes a pixel's value go up by `gain` when drawn with the blend 2 * source * destination.
-- "gamma": blending in the space of the pixel values, gain / 2. "linear": blending in linear light with the 2D attenuation
-- (VISION_ATTENUATION, measured), so the texel is worked back through the sRGB curves for a destination at the middle of the range
-- (VISION_REF; the gain then holds within 2 % from 0.4 to 0.8 and within 8 % at 0.25). It cannot exceed 1: the largest gain
-- reachable is about 1.29, so the blue of the bright rows (1.3125) falls 2 % short.
Bino.VISION_REF = 0.5
Bino.VISION_ATTENUATION = 0.87

function Bino.VisionLevel(gain, mode)
	if mode == "gamma" then
		return gain / 2
	end

	local ref = Bino.VISION_REF

	return Bino.SrgbEncode(Bino.SrgbDecode(math.min(gain * ref, 1)) / (2 * Bino.VISION_ATTENUATION * Bino.SrgbDecode(ref)))
end

-- The three bytes of the tint texel (the gain of the bright rows, rows 0 and 3 of each four).
function Bino.VisionTintTexel(mode)
	local r, g, b = Bino.VisionRowGains(0)

	return toByte(Bino.VisionLevel(r, mode)), toByte(Bino.VisionLevel(g, mode)), toByte(Bino.VisionLevel(b, mode))
end

-- The ratio of the gain of the dim rows to that of the bright ones (the same for the three channels), and the byte of the grey
-- texel that gives it.
function Bino.VisionDimRatio()
	return Bino.InterlaceGain(1) / Bino.InterlaceGain(0)
end

function Bino.VisionDimTexel(mode)
	return toByte(Bino.VisionLevel(Bino.VisionDimRatio(), mode))
end

-- Whether a pixel row is one of the dim rows (1 and 2 of each four): the strips start at VisionFirstDim and are two rows tall.
Bino.VISION_DIM_FIRST = 1
Bino.VISION_DIM_ROWS = 2

function Bino.VisionIsDim(row)
	local gain = Bino.InterlaceGain(row)

	return gain < Bino.InterlaceGain(0) - 1e-9
end

-- What a pixel of value `dest` (0 to 1) becomes, as a ratio, under the blend 2 * source * destination with a texel of level `texel`.
function Bino.VisionPredict(texel, dest, mode)
	if mode == "gamma" then
		return 2 * texel
	end

	return Bino.SrgbEncode(2 * Bino.VISION_ATTENUATION * Bino.SrgbDecode(texel) * Bino.SrgbDecode(dest)) / dest
end

-- The mode whose prediction is nearest to the ratio that was measured.
function Bino.VisionClassify(ratio, texel, dest)
	if math.abs(ratio - Bino.VisionPredict(texel, dest, "linear")) <= math.abs(ratio - Bino.VisionPredict(texel, dest, "gamma")) then
		return "linear"
	end

	return "gamma"
end

-- The gain of the vignette at a point of the screen in texture units (0 to 1 each way).
function Bino.VignetteGain(u, v)
	local du, dv = u - 0.5, v - 0.5

	return math.Clamp(1 - Bino.VISION_VIGNETTE * math.sqrt(du * du + dv * dv), 0, 1)
end

function Bino.VignetteTexel(u, v, mode)
	return toByte(Bino.VisionLevel(Bino.VignetteGain(u, v), mode))
end

-- The three materials, built once (a render target each, drawn at the first need, then kept): the tint, the dim rows' grey and the
-- vignette. mode is the blend's space they were painted for.
local vision = {tint = nil, dim = nil, vignette = nil, tintTarget = nil, dimTarget = nil, vignetteTarget = nil, builds = 0, hooked = false, mode = nil, paintedFor = "linear", probes = 0}
Bino.VisionState = vision

local function drawTexture(name, width, height, paint)
	local target = GetRenderTargetEx(name, width, height, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)

	render.PushRenderTarget(target)
	render.Clear(0, 0, 0, 255, false, false)
	cam.Start2D()
	local ok, err = pcall(paint)
	cam.End2D()
	render.PopRenderTarget()

	if not ok then
		error(err, 0)
	end

	return target
end

local function paintTint()
	local r, g, b = Bino.VisionTintTexel(vision.paintedFor)
	surface.SetDrawColor(r, g, b, 255)
	surface.DrawRect(0, 0, Bino.VISION_PERIOD, Bino.VISION_PERIOD)
end

local function paintDim()
	local level = Bino.VisionDimTexel(vision.paintedFor)
	surface.SetDrawColor(level, level, level, 255)
	surface.DrawRect(0, 0, Bino.VISION_PERIOD, Bino.VISION_PERIOD)
end

local function paintVignette()
	local size = Bino.VISION_VIGNETTE_SIZE

	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local level = Bino.VignetteTexel((x + 0.5) / size, (y + 0.5) / size, vision.paintedFor)
			surface.SetDrawColor(level, level, level, 255)
			surface.DrawRect(x, y, 1, 1)
		end
	end
end

local function materialFor(name, target)
	return CreateMaterial(name, "UnlitGeneric", {
		["$basetexture"] = target:GetName(),
		["$ignorez"] = 1,
		["$vertexcolor"] = 0,
		["$vertexalpha"] = 0,
		["$nocull"] = 1
	})
end

-- Paints the two small textures again for a mode (the blend's space).
local function repaint(mode)
	vision.paintedFor = mode

	for _, entry in ipairs({{vision.tintTarget, paintTint}, {vision.dimTarget, paintDim}, {vision.vignetteTarget, paintVignette}}) do
		render.PushRenderTarget(entry[1])
		cam.Start2D()
		pcall(entry[2])
		cam.End2D()
		render.PopRenderTarget()
	end
end

-- Builds the textures and materials the first time, nothing after; true when they are there.
function Bino.VisionBuild()
	if vision.tint and vision.dim and vision.vignette then
		return true
	end

	local ok, err = pcall(function()
		vision.tintTarget = drawTexture("gry_bino_tint_rt", Bino.VISION_PERIOD, Bino.VISION_PERIOD, paintTint)
		vision.dimTarget = drawTexture("gry_bino_dim_rt", Bino.VISION_PERIOD, Bino.VISION_PERIOD, paintDim)
		vision.vignetteTarget = drawTexture("gry_bino_vignette_rt", Bino.VISION_VIGNETTE_SIZE, Bino.VISION_VIGNETTE_SIZE, paintVignette)

		vision.tint = materialFor("gry_bino_tint_mat", vision.tintTarget)
		vision.dim = materialFor("gry_bino_dim_mat", vision.dimTarget)
		vision.vignette = materialFor("gry_bino_vignette_mat", vision.vignetteTarget)
		vision.builds = vision.builds + 1
	end)

	if not ok then
		vision.tint, vision.dim, vision.vignette = nil, nil, nil
		ErrorNoHalt("GryMod binoculars vision: " .. tostring(err) .. "\n")

		return false
	end

	return true
end

local function visionPasses()
	local width, height = ScrW(), ScrH()

	-- the three passes are all 2 * source * destination (the texels' levels allow for the blend's space), the tint at the gain of
	-- the bright rows over the whole screen first
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_SRC_COLOR, BLENDFUNC_ADD)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(vision.tint)
	surface.DrawTexturedRect(0, 0, width, height)

	-- the dim rows (1 and 2 of each four), two pixel rows a strip, by the ratio of the two gains
	surface.SetMaterial(vision.dim)

	for y = Bino.VISION_DIM_FIRST, height - 1, Bino.VISION_PERIOD do
		surface.DrawTexturedRect(0, y, width, math.min(Bino.VISION_DIM_ROWS, height - y))
	end

	-- the vignette
	surface.SetMaterial(vision.vignette)
	surface.DrawTexturedRect(0, 0, width, height)
end

-- The blend's space, found once: a pixel near the middle of the screen is multiplied by the tint texel and read back; the ratio
-- says whether the framebuffer blends in linear light or in gamma space, and the two textures are painted again for that mode if
-- it is not the one they were painted for. A scene too dark or too bright at that pixel waits for a later frame; after
-- VISION_PROBES tries the guess ("linear", the measured one) stays.
Bino.VISION_PROBES = 60

local function drawProbe(x, y)
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_SRC_COLOR, BLENDFUNC_ADD)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(vision.tint)
	surface.DrawTexturedRect(x, y, 1, 1)
end

-- Which channel (1 to 3) of a pixel can tell the blend's space: a value from 60 to 150 (a dark one gives nothing to measure, a bright
-- one reaches 255 with the gain), the first such channel, or nil.
function Bino.VisionProbeChannel(r, g, b)
	local values = {r, g, b}

	for i = 1, 3 do
		if values[i] >= 60 and values[i] <= 150 then
			return i
		end
	end

	return nil
end

local probeSpots = {{0.5, 0.5}, {0.25, 0.5}, {0.75, 0.5}, {0.5, 0.25}, {0.5, 0.75}}

local function probeBlend()
	vision.probes = vision.probes + 1

	if vision.probes > Bino.VISION_PROBES then
		vision.mode = vision.paintedFor

		return
	end

	local width, height = ScrW(), ScrH()
	local x, y, channel, before

	render.CapturePixels()

	for i = 1, #probeSpots do
		local px, py = math.floor(width * probeSpots[i][1]), math.floor(height * probeSpots[i][2])
		local r, g, b = render.ReadPixel(px, py)
		local c = Bino.VisionProbeChannel(r, g, b)

		if c then
			x, y, channel, before = px, py, c, c == 1 and r or (c == 2 and g or b)

			break
		end
	end

	if not x then
		return
	end

	cam.Start2D()
	local ok = pcall(drawProbe, x, y)
	render.OverrideBlend(false)
	cam.End2D()

	if not ok then
		return
	end

	render.CapturePixels()

	local r, g, b = render.ReadPixel(x, y)
	local after = channel == 1 and r or (channel == 2 and g or b)
	local texel = select(channel, Bino.VisionTintTexel(vision.paintedFor))

	vision.mode = Bino.VisionClassify(after / before, texel / 255, before / 255)

	if vision.mode ~= vision.paintedFor then
		repaint(vision.mode)
	end
end

-- RenderScreenspaceEffects: only while the binoculars are up in first person with the option on (the hook itself is added only
-- then, see Bino.VisionStep). The blend is always put back and the 2D ended, whatever a draw does.
function Bino.DrawVision()
	if not Bino.VisionEnabled() or not Bino.Enabled() then
		return
	end

	local ply = LocalPlayer()

	if not Bino.Wanted(ply) or ply:ShouldDrawLocalPlayer() or not Bino.VisionBuild() then
		return
	end

	if not vision.mode then
		probeBlend()
	end

	cam.Start2D()
	local ok, err = pcall(visionPasses)
	render.OverrideBlend(false)
	cam.End2D()

	if not ok then
		ErrorNoHalt("GryMod binoculars vision: " .. tostring(err) .. "\n")
	end
end

local function visionHook()
	Bino.DrawVision()
end

-- Once per frame (from the HUD): the hook on RenderScreenspaceEffects exists only while the vision is wanted, so with the
-- binoculars down nothing runs at all.
function Bino.VisionStep(wanted)
	local want = wanted and Bino.VisionEnabled() and Bino.Enabled() and not missing

	if want and not vision.hooked then
		vision.hooked = true
		hook.Add("RenderScreenspaceEffects", "GRYBINOCULARSVISION", visionHook)
	elseif not want and vision.hooked then
		vision.hooked = false
		hook.Remove("RenderScreenspaceEffects", "GRYBINOCULARSVISION")
	end
end

-- The sway of the binoculars (see Bino.SwayOffset): its pitch and yaw for this frame, or nil, and the state is dropped as soon as
-- it is not wanted (the binoculars down, the option or the HUD element off).
local sway = Bino.NewSway()
Bino.SwayState = sway

local function swayFor(ply, wanted)
	if not wanted or not Bino.SwayEnabled() or not Bino.Enabled() or missing then
		if sway.last then
			Bino.SwayReset(sway)
		end

		return nil
	end

	local crouch, prone, strength = Bino.SwayStance(ply)

	return Bino.SwayStep(sway, true, Bino.Now(), crouch, prone, strength)
end

-- CalcView: the view with the stage's field of view and / or the sway's angles, or nothing (the stage state is dropped as soon as
-- the stages are not wanted, the sway's as soon as the binoculars are down).
function Bino.CalcView(ply, origin, angles, fov, znear, zfar)
	local suit = GryMod.SuitZoom

	-- the own zoom looks at the world before the view is given: with the game paused (the menu or the console open in a single
	-- player game) Think does not run but CalcView does (measured), and a zoom that must end must not give one more view
	if suit and suit.Wanted() then
		suit.Guard()
	end

	local own = suit ~= nil and suit.IsActive()

	-- with the own zoom up never a view in a vehicle: the game's CalcView would not run (our table ends the hook chain) and the
	-- vehicle's camera would be lost (the zoom itself ends in the next Think, see SuitZoom.Reason)
	if own and ply:InVehicle() then
		if zoom.active then
			Bino.ZoomReset(zoom)
		end

		return nil
	end

	local wanted = Bino.Wanted(ply)

	-- a view of ours this frame: the suit zoom knows that no other addon's CalcView took it
	if own and wanted then
		suit.Stamp()
	end

	local stageFov

	if not stagesOn() then
		if zoom.active then
			Bino.ZoomReset(zoom)
		end
	elseif wanted or zoom.active then
		stageFov = Bino.ZoomStep(zoom, Bino.Now(), wanted, ply:GetInfoNum("fov_desired", 75), fov)
	end

	local pitch, yaw = swayFor(ply, wanted)

	if not stageFov and not pitch then
		return nil
	end

	if pitch then
		angles = Angle(angles.p + math.deg(pitch), angles.y + math.deg(yaw), angles.r)
	end

	return {origin = origin, angles = angles, fov = stageFov or fov, znear = znear, zfar = zfar}
end

-- The sound of a stage step, through the mix like the others (nothing with the binoculars' sounds off).
function Bino.PlayZoomSound(cue)
	if Bino.SoundsEnabled() then
		GryMod.PlaySound(Bino.Sounds[cue])
	end
end

-- A notch of the wheel while the zoom is up: invprev (wheel up) goes to the next stage, invnext (wheel down) to the previous, with
-- the stage's sound. Returns nothing.
function Bino.StepWheel(bind)
	local _, cue = Bino.ZoomWheel(zoom, bind)

	if cue then
		Bino.PlayZoomSound(cue)
	end
end

-- PlayerBindPress: the wheel (invprev / invnext) steps the stage while the binoculars are up; the press and the release are
-- taken (the weapon is not changed), the other keys go on to the game. While the own zoom is up the suit zoom module is the wheel's
-- owner (it also knows the wheel by its button, whatever the bind), and this does nothing.
function Bino.BindPress(ply, bind, pressed)
	if (bind ~= "invprev" and bind ~= "invnext") or zoom.stage == 0 or not stagesOn() or not Bino.Wanted(ply) then
		return nil
	end

	if GryMod.SuitZoom and GryMod.SuitZoom.IsActive() then
		return nil
	end

	if pressed then
		Bino.StepWheel(bind)
	end

	return true
end

-- AdjustMouseSensitivity: the fraction of the normal sensitivity for the field of view in force, nothing to leave the engine's.
function Bino.AdjustSensitivity(ply)
	if not zoom.active or not Bino.StagesEnabled() then
		return nil
	end

	return Bino.SensitivityScale(zoom, ply:GetInfoNum("fov_desired", 75), Bino.ZoomRatio())
end

hook.Add("CalcView", "GRYBINOCULARSZOOM", function(ply, origin, angles, fov, znear, zfar)
	return Bino.CalcView(ply, origin, angles, fov, znear, zfar)
end)

hook.Add("PlayerBindPress", "GRYBINOCULARSZOOM", function(ply, bind, pressed)
	return Bino.BindPress(ply, bind, pressed)
end)

hook.Add("AdjustMouseSensitivity", "GRYBINOCULARSZOOM", function()
	return Bino.AdjustSensitivity(LocalPlayer())
end)

-- The Half-Life 2 suit zoom has its own overlay (CHudZoom, the black ring); our binoculars replace it while they
-- are on. Hiding the element does not stop the zoom itself (see the HUD element list of the wiki).
hook.Add("HUDShouldDraw", "GRYBINOCULARSHIDEZOOM", function(name)
	if name == "CHudZoom" and not missing and Bino.Enabled() and Bino.Wanted(LocalPlayer()) then
		return false
	end
end)

-- Whether the picture is on screen (opening, up or closing).
function Bino.IsUp()
	return binoculars ~= nil and binoculars:IsShown()
end

-- The binoculars put away at once, with no closing animation and no sound (a death, a menu, a vehicle, a map change: the hard reasons
-- of cl_suit_zoom.lua): the picture is hidden, the stages, the sway, the scan, the outlines, the loop, the mood and the vision go.
function Bino.Drop()
	if binoculars then
		binoculars:Hide()
	end

	Bino.StopLoop()
	Bino.AudioReset()
	Bino.MoodStep(false)
	Bino.ScanReset(scan)
	Bino.SilhouetteClear(Bino.Silhouettes)
	Bino.ZoomReset(zoom)
	Bino.SwayReset(Bino.SwayState)
	Bino.VisionStep(false)
end

function Bino.Reset()
	if binoculars then
		Flash.ReleaseClip(binoculars.root)
	end

	binoculars = nil
	missing = false
	Bino.StopLoop()
	Bino.AudioReset()
	Bino.MoodStep(false)
	Bino.ScanReset(scan)
	Bino.SilhouetteClear(Bino.Silhouettes)
	Bino.ZoomReset(zoom)
	Bino.SwayReset(Bino.SwayState)
	Bino.VisionStep(false)
end
