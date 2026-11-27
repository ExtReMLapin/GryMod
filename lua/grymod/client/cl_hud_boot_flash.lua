-- The HUD boot sequences drawn from the original Scaleform movies, see cl_flash.lua:
--   HUD_Initialize: the log of the start (2.97 s). The game plays the reboot sound as it starts and the activate
--     sound when it ends (frame 88 of the movie).
--   HUD_Lost: the "system overrun, emergency shutdown" animation, which loops while the suit is down (the HUD
--     malfunctions, red); the malfunction sound starts with it.
--   HUD_Reboot: the emergency reboot sequence that runs when the suit comes back (3.97 s and a closing animation);
--     silent.
-- The rules are from the game's code (research notes: research-ui2/crosshair-reboot.md). The sounds are the
-- demo's own (hud_reboot, hud_activate, hud_malfunction). GryMod has no EMP and no level start: the HUD malfunction
-- is the energy running out (see cl_hud_flash.lua) and the log plays at the first spawn after the map loads (every
-- spawn with gry_boot_every_spawn). The reboot after a malfunction plays no sound, as in the original.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Boot = {}
GryMod.FlashBoot = Boot

Boot.MOVIES = {initialize = "hud_initialize", reboot = "hud_reboot", lost = "hud_lost"}

-- How long each sequence runs (seconds); the Lost animation loops until the malfunction ends.
Boot.DURATION = {initialize = 89 / 30, reboot = 3.97 + 0.67}

-- The Lost movie ends by itself (frame 137, 4.6 s after it starts) on an empty stage, as the original's does. A DEATH keeps the panel until the respawn: the
-- movie's stage stops here, on a frame where the panel is still on (the orange frame with its side bars, which is what the movie shows for most of its length).
Boot.LOST_HOLD_FRAME = 100

local STAGE_W, STAGE_H = 1024, 768

-- Where the stage of the movies (4:3) goes on a screen of w x h pixels: x and y of its origin and the scale. The stage
-- is as high as the screen and centred across its width, whatever the aspect ratio.
function Boot.Placement(w, h)
	local scale = h / STAGE_H

	return (w - STAGE_W * scale) / 2, 0, scale
end

-- The Lost screen ("DANGER SYSTEM OVERRUN") is drawn LOW in its own movie: the clip's origin is at the centre of the stage and the panels sit 80 to 378 stage
-- pixels under it (hud_lost.lua), so the frame spans y 464 to 762 of the 768 and its centre is at about 80 % of the height. The Initialize and Reboot movies are
-- centred. That is the original's placement (the movie files are the same), so it is what is drawn by default; gry_hud_lost_centered moves only this screen up so
-- that the centre of its panel is the centre of the screen.
Boot.LOST_CENTRE_Y = 613

local LostCenteredConVar = CreateClientConVar("gry_hud_lost_centered", "0", true, false, "1: the shutdown screen (DANGER SYSTEM OVERRUN, shown when the suit goes down or at a death) is in the middle of the screen; 0: low, where the original's movie puts it", 0, 1)

-- Where a sequence of this kind goes on a screen of w x h pixels: Placement, and for the Lost screen with gry_hud_lost_centered the stage is moved up so that
-- the centre of the panel is the centre of the screen.
function Boot.PlacementFor(kind, w, h)
	local x, y, scale = Boot.Placement(w, h)

	if kind == "lost" and LostCenteredConVar:GetBool() then
		y = y + (STAGE_H / 2 - Boot.LOST_CENTRE_Y) * scale
	end

	return x, y, scale
end

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
local shutdown = false -- the "disabled" event holds its shutdown animation over the hidden HUD
local deathHeld = false -- the player is dead and the HUD shows it: the Lost screen stays (see HoldDeath)
local hasSpawned = false -- the player has already spawned since this Lua state was made (a new map makes a new one)

-- Switch: the log of the start at every spawn (the old behaviour) instead of the first one only.
local EverySpawnConVar = CreateClientConVar("gry_boot_every_spawn", "0", true, false, "The start-up log (with its sounds) at every spawn, not only at the first one after the map loads")

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

-- The player dies: whatever was on ends, and the malfunction of that life is forgotten.
function Boot.Died()
	current = nil
	malfunctioning = false
	deathHeld = false
end

-- The HUD shows the death (gry_hud_lost_on_death, cl_hud_flash.lua): the Lost screen that the "lost" event started stays while the player is dead
-- instead of ending with the life.
function Boot.HoldDeath(on)
	deathHeld = on == true
end

function Boot.DeathHeld()
	return deathHeld
end

-- The respawn: the Lost screen of the death ends, with no sound and no reboot sequence (the start-up log of the spawn is Spawned's business).
-- Both the HUD and this file's paint call it, so the order they are painted in does not matter.
function Boot.EndDeath()
	if not deathHeld then
		return
	end

	deathHeld = false
	current = nil
	malfunctioning = false
end

-- Forget that the player has spawned (the next spawn is a first one again). Tests only.
function Boot.ResetSpawn()
	hasSpawned = false
end

-- The player spawns. The log of the start, with its reboot sound, is the start of the level in the original: it plays
-- for the first spawn only (the first one after the map loads), unless gry_boot_every_spawn asks for every spawn.
-- A suit that is already down (the energy is still empty) keeps its shutdown animation: the HUD may have said so
-- before this runs.
function Boot.Spawned()
	local first = not hasSpawned
	hasSpawned = true

	if not enabled() then
		current = nil
		malfunctioning = false

		return
	end

	if malfunctioning then
		return
	end

	if not (first or EverySpawnConVar:GetBool()) then
		return
	end

	-- the log of the start and its sound are the HUD event "boot" (it follows the HUD boot sequences option itself)
	if GryMod.API and GryMod.API.HUDEvent then
		GryMod.API.HUDEvent("boot")
	end
end

-- The player has spawned while the HUD is off: that was the first spawn all the same.
function Boot.NoteSpawn()
	hasSpawned = true
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

		-- the original's RebootHUD plays no sound: hud_reboot and hud_activate belong to the start of the level
		begin("reboot")
	end
end

-- One step of time (no drawing): a sequence that is over gives its place back; the end of the start log plays the
-- activate sound (the game's StopInitialize), the reboot after a malfunction ends in silence.
function Boot.Step(dt)
	local seq = current and sequences[current]

	if not seq then
		return
	end

	seq:Update(dt)

	-- a death holds the Lost panel on its full frame (one check a step, nothing is redone once the stage is stopped)
	if deathHeld and current == "lost" then
		local stage = seq.root:Child("Root")

		if stage and stage.playing and stage.frame >= Boot.LOST_HOLD_FRAME then
			stage:GotoAndStop(Boot.LOST_HOLD_FRAME)
		end
	end

	if seq:IsDone() then
		local kind = current
		current = nil

		if kind == "initialize" then
			play(snd_activate)
		end
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
	shutdown = false
	deathHeld = false
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

-- The HUD changes its state: the game says so by calling the HUD events (a malfunction is "lost", its end "reboot"). A return to
-- normal while nothing was wrong is no reboot. 2 is the flicker of a light shock.
hook.Add("GryMod_HUDStatus", "GRYBOOT", function(status, why)
	local API = GryMod.API

	if not (API and API.HUDEvent) then
		return
	end

	if status == 1 then
		API.HUDEvent("lost")
	elseif status == 0 and malfunctioning and why ~= "gone" then
		-- (the reason "gone": the HUD is dropped, not rebooted; this file's own paint ends what was on, cl_hud_flash.lua TellGone)
		API.HUDEvent("reboot")
	end
end)

-- The "disabled" event: the shutdown animation plays (with its sound) over a HUD that is hidden; Stop ends it, "enabled" reboots.
function Boot.Malfunctioning()
	return malfunctioning
end

function Boot.Shutdown()
	shutdown = true
	Boot.OnStatus(1)
end

function Boot.ShutdownHeld()
	return shutdown
end

-- Ends whatever is on, with no sound: the sequences and the shutdown.
function Boot.Stop()
	current = nil
	malfunctioning = false
	shutdown = false
	deathHeld = false
end

-- The suit is back after a "disabled": the reboot sequence (silent, as in the original game).
function Boot.Restart()
	Boot.Stop()

	if enabled() then
		begin("reboot")
	end
end

hook.Add("HUDPaint", "GRYFLASHBOOT", function()
	local ply = LocalPlayer()
	local alive = IsValid(ply) and ply:Alive()
	local Hud = GryMod.FlashHUD
	local normal = Hud and Hud.Enabled()
	-- the shutdown of the "disabled" event is drawn while the HUD itself is hidden
	local held = not normal and shutdown and Hud and Hud.HudWanted and Hud.HudWanted()

	if not normal and not held then
		if alive and not wasAlive then
			Boot.NoteSpawn()
		end

		wasAlive = alive
		-- nothing stays on while the HUD is off: it would not be told when the suit comes back
		current = nil
		malfunctioning = false
		deathHeld = false

		return
	end

	if normal then
		-- the first spawn starts the log (every spawn with gry_boot_every_spawn); dying ends whatever was on, unless the HUD shows the death
		-- (a life that is back ends the death screen on any paint, not only on the one where it came back)
		if alive then
			Boot.EndDeath()
		end

		if alive and not wasAlive then
			Boot.Spawned()
		elseif not alive and not deathHeld then
			current = nil
			malfunctioning = false
		end
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
		sequences[current]:Draw(Boot.PlacementFor(current, ScrW(), ScrH()))
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The built-in HUD events of the extension API (cl_api.lua, docs/api.md): GryMod.API.HUDEvent("boot" | "reboot" | "lost" |
-- "malfunction"). They play the sequences above, as the game's own states do, and respect the player's choice (the HUD boot
-- sequences option, gry_hud_boot): when it is off they play nothing.
-- ---------------------------------------------------------------------------------------------------------

local API_MALFUNCTION_TIMER = "GryApiMalfunction"
local DEFAULT_MALFUNCTION_SECONDS = 5

-- The end of a malfunction asked by the "malfunction" event: the HUD reboots.
function Boot.EndApiMalfunction()
	timer.Remove(API_MALFUNCTION_TIMER)
	Boot.OnStatus(0)
end

function Boot.RegisterEvents()
	local API = GryMod.API

	if not (API and API.RegisterHUDEvent) then
		return
	end

	-- the start-up log of the HUD (HUD_Initialize), with its sound
	API.RegisterHUDEvent("boot", function()
		if enabled() and begin("initialize") then
			play(snd_reboot)
		end
	end, {
		label = "Boot log",
		follows = {{"gry_hud_boot", "the start-up and reboot sequences"}, {"gry_sounds", "the start-up sound"}}
	})

	-- the suit is down: the emergency shutdown animation (HUD_Lost) with its sound, until a "reboot"
	API.RegisterHUDEvent("lost", function()
		Boot.OnStatus(1)
	end, {
		label = "Emergency shutdown",
		follows = {{"gry_hud_boot", "the start-up and reboot sequences"}, {"gry_sounds", "the malfunction sound"}}
	})

	-- the suit comes back: the reboot sequence (silent, as in the original game)
	API.RegisterHUDEvent("reboot", function()
		timer.Remove(API_MALFUNCTION_TIMER)

		if malfunctioning then
			Boot.OnStatus(0)
		elseif enabled() then
			begin("reboot")
		end
	end, {
		label = "Reboot",
		follows = {{"gry_hud_boot", "the start-up and reboot sequences"}}
	})

	-- a malfunction of the HUD for data.seconds (5 by default, from 0.1 to 60): the shutdown animation, then the reboot
	API.RegisterHUDEvent("malfunction", function(data)
		local seconds = math.Clamp(tonumber(data.seconds) or DEFAULT_MALFUNCTION_SECONDS, 0.1, 60)

		Boot.OnStatus(1)
		timer.Create(API_MALFUNCTION_TIMER, seconds, 1, Boot.EndApiMalfunction)
	end, {
		label = "Malfunction",
		follows = {{"gry_hud_boot", "the start-up and reboot sequences"}, {"gry_sounds", "the malfunction sound"}}
	})
end

Boot.RegisterEvents()
