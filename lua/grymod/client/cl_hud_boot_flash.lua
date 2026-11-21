-- The HUD boot sequences drawn from the original Scaleform movies, see cl_flash.lua:
--   HUD_Initialize: the log of the start (2.97 s). The game plays the reboot sound as it starts and the activate
--     sound when it ends (frame 88 of the movie).
--   HUD_Lost: the "system overrun, emergency shutdown" animation, which loops while the suit is down (the HUD
--     malfunctions, red); the malfunction sound starts with it.
--   HUD_Reboot: the emergency reboot sequence that runs when the suit comes back (3.97 s and a closing animation).
-- The rules are from the game's code (research notes: research-ui2/crosshair-reboot.md). The sounds are the
-- demo's own (hud_reboot, hud_activate, hud_malfunction). GryMod has no EMP and no level start: the HUD malfunction
-- is the energy running out (see cl_hud_flash.lua) and the log plays at every spawn.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Boot = {}
GryMod.FlashBoot = Boot

Boot.MOVIES = {initialize = "hud_initialize", reboot = "hud_reboot", lost = "hud_lost"}

-- How long each sequence runs (seconds); the Lost animation loops until the malfunction ends.
Boot.DURATION = {initialize = 89 / 30, reboot = 3.97 + 0.67}

local STAGE_W, STAGE_H = 1024, 768

-- The movies hold localisation keys (@ui_init_text01): the English texts of the original game (Flash.Localise).
function Boot.Localise(text)
	return Flash.Localise(text)
end

local Sequence = {}
Sequence.__index = Sequence

-- A sequence of one kind ("initialize", "reboot" or "lost") from its converted movie (nil when it is missing).
function Boot.New(kind, movie, theme)
	if not movie or not Boot.MOVIES[kind] then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))

	return setmetatable({kind = kind, root = root, time = 0, started = false}, Sequence)
end

-- The clips the Reboot movie's showProgressBar() opens and closes.
local REBOOT_CLIPS = {"Alpha", "Logo.Colorset", "Texts", "LoadBars", "Outlines.Colorset", "Alpha2"}
local REBOOT_CLOSE_AT = 3.97 -- seconds; the closing animation runs 0.67 s more

-- showProgressBar(true) / showProgressBar(false) of HUD_Reboot
function Sequence:_showProgressBar(open)
	local holder = self.root:Child("Root")

	if not holder then
		return
	end

	for _, path in ipairs(REBOOT_CLIPS) do
		local clip = holder:Find(path)

		if clip then
			clip:GotoAndPlay(open and "open" or "close")
		end
	end

	-- setStatus(): the four load bars stop on their second frame
	if open then
		for i = 1, 4 do
			local bar = holder:Find("LoadBars.LoadBar" .. i)

			if bar then
				bar:GotoAndStop(2)
			end
		end
	end

	self.closed = not open
end

function Sequence:Start()
	self.time = 0
	self.started = true
	self.closed = false

	local holder = self.root:Child("Root")

	if self.kind == "initialize" then
		-- resetColor(): Root.gotoAndPlay("restart")
		if holder then
			holder:GotoAndPlay("restart")
		end
	elseif self.kind == "lost" then
		self.root:GotoAndPlay(2)
	elseif self.kind == "reboot" then
		self:_showProgressBar(true)
	end

	self.root:MapText(Boot.Localise)
end

function Sequence:Update(dt)
	if not self.started then
		return
	end

	self.time = self.time + dt

	-- the game closes the reboot movie once its sequence is over
	if self.kind == "reboot" and not self.closed and self.time >= REBOOT_CLOSE_AT then
		self:_showProgressBar(false)
	end

	local version = self.root.version

	self.root:Advance(dt)

	-- a frame can rebuild its text fields: say the words again (only when something changed)
	if self.root.version ~= version then
		self.root:MapText(Boot.Localise)
	end
end

function Sequence:IsDone()
	local duration = Boot.DURATION[self.kind]

	return duration ~= nil and self.time >= duration
end

function Sequence:Draw(x, y, scale)
	if self.started then
		Flash.Draw(self.root, x, y, scale)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The state: which sequence is on, and the sounds
-- ---------------------------------------------------------------------------------------------------------

local snd_reboot, snd_activate, snd_malfunction =
	Sound("grymod/hud/hud_reboot.wav"), Sound("grymod/hud/hud_activate_01.wav"), Sound("grymod/hud/hud_malfunction_hit.wav")

local sequences = {}
local current -- the kind that is on, or nil
local malfunctioning = false

local function play(path)
	if GryMod.PlaySound then
		GryMod.PlaySound(path)
	end
end

local function enabled()
	return not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("boot")
end

local function begin(kind)
	local seq = sequences[kind]

	if not seq then
		seq = Boot.New(kind, Flash.Load(Boot.MOVIES[kind]))
		sequences[kind] = seq
	end

	if not seq then
		current = nil

		return false
	end

	seq:Start()
	current = kind

	return true
end

-- The kind of sequence that is on ("initialize", "reboot", "lost") or nil.
function Boot.Current()
	return current
end

function Boot.IsLost()
	return current == "lost"
end

-- The player spawns: the log of the start, with the reboot sound. A suit that is already down (the energy is
-- still empty) keeps its shutdown animation: the HUD may have said so before this runs.
function Boot.Spawned()
	if not enabled() then
		current = nil
		malfunctioning = false

		return
	end

	if malfunctioning then
		return
	end

	if begin("initialize") then
		play(snd_reboot)
	end
end

-- The HUD changes its state (1: malfunction, 0: normal), as the movie's destroy(status).
function Boot.OnStatus(status)
	-- 2 is the flicker of a light shock: neither a malfunction nor the end of one
	if status == 2 then
		return
	end

	if not enabled() then
		malfunctioning = false
		current = nil

		return
	end

	if status == 1 then
		if malfunctioning then
			return
		end

		malfunctioning = true

		if begin("lost") then
			play(snd_malfunction)
		end
	elseif malfunctioning then
		malfunctioning = false

		if begin("reboot") then
			play(snd_reboot)
		end
	end
end

-- One step of time (no drawing): a sequence that is over gives its place back, with the activate sound.
function Boot.Step(dt)
	local seq = current and sequences[current]

	if not seq then
		return
	end

	seq:Update(dt)

	if seq:IsDone() then
		current = nil
		play(snd_activate)
	end
end

local function release()
	for _, seq in pairs(sequences) do
		Flash.ReleaseClip(seq.root)
	end

	sequences = {}
end

function Boot.Reset()
	release()
	current = nil
	malfunctioning = false
end

-- The pictures are rebuilt (a new colour): the sequence that is on starts again from its beginning with the new
-- colours, and the state (a malfunction) stays, without any sound.
function Boot.Rebuild()
	local kind = current

	release()
	current = nil

	if kind then
		begin(kind)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game
-- ---------------------------------------------------------------------------------------------------------

local lastTime
local wasAlive = false

hook.Add("GryMod_HUDStatus", "GRYBOOT", function(status)
	Boot.OnStatus(status)
end)

hook.Add("HUDPaint", "GRYFLASHBOOT", function()
	local ply = LocalPlayer()
	local alive = IsValid(ply) and ply:Alive()

	if not (GryMod.FlashHUD and GryMod.FlashHUD.Enabled()) then
		wasAlive = alive
		-- nothing stays on while the HUD is off: it would not be told when the suit comes back
		current = nil
		malfunctioning = false

		return
	end

	-- every spawn starts the log; dying ends whatever was on
	if alive and not wasAlive then
		Boot.Spawned()
	elseif not alive then
		current = nil
		malfunctioning = false
	end

	wasAlive = alive

	local seq = current and sequences[current]

	if not seq then
		lastTime = nil

		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	Boot.Step(dt)

	-- the sequence may have ended in this step
	if current and sequences[current] then
		local scale = ScrH() / STAGE_H

		sequences[current]:Draw((ScrW() - STAGE_W * scale) / 2, 0, scale)
	end
end)
