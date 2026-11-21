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
local StagesConVar = CreateClientConVar("gry_binoculars_stages", "0", true, false, "The original's zoom stages (2x, 4x, 8x) with the mouse wheel while the binoculars are up, a straight 0.2 s between them (off: the Half-Life 2 zoom, one fixed field of view). Changes how the mouse feels")

function Bino.StagesEnabled() return StagesConVar:GetBool() end
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
	return {stage = 0, active = false, fov = nil, from = 0, to = 0, start = 0, duration = 0, closeStart = nil}
end

function Bino.ZoomReset(z)
	z.stage, z.active, z.fov, z.from, z.to, z.start, z.duration, z.closeStart = 0, false, nil, 0, 0, 0, 0, nil
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
		z.from, z.to, z.start = current, target, now
		z.duration = target < current and Bino.ZOOM_IN_TIME or Bino.ZOOM_OUT_TIME
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

-- CalcView: the view with the stage's field of view, or nothing (the state is dropped as soon as the stages are not wanted).
function Bino.CalcView(ply, origin, angles, fov, znear, zfar)
	if not stagesOn() then
		if zoom.active then
			Bino.ZoomReset(zoom)
		end

		return nil
	end

	local wanted = Bino.Wanted(ply)

	if not wanted and not zoom.active then
		return nil
	end

	local stageFov = Bino.ZoomStep(zoom, Bino.Now(), wanted, ply:GetInfoNum("fov_desired", 75), fov)

	if not stageFov then
		return nil
	end

	return {origin = origin, angles = angles, fov = stageFov, znear = znear, zfar = zfar}
end

-- The sound of a stage step, through the mix like the others (nothing with the binoculars' sounds off).
function Bino.PlayZoomSound(cue)
	if Bino.SoundsEnabled() then
		GryMod.PlaySound(Bino.Sounds[cue])
	end
end

-- PlayerBindPress: the wheel (invprev / invnext) steps the stage while the binoculars are up; the press and the release are
-- taken (the weapon is not changed), the other keys go on to the game.
function Bino.BindPress(ply, bind, pressed)
	if (bind ~= "invprev" and bind ~= "invnext") or zoom.stage == 0 or not stagesOn() or not Bino.Wanted(ply) then
		return nil
	end

	if pressed then
		local _, cue = Bino.ZoomWheel(zoom, bind)

		if cue then
			Bino.PlayZoomSound(cue)
		end
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
end
