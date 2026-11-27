-- The night vision of the suit, CLIENT STATE (design: docs/superpowers/plans/2026-11-24-nightvision-implementation.md, contract in its section "Contract
-- between the pieces"). This file owns whether the night vision is on, its own energy, its fade, its key, its sounds and the report to the others. It draws
-- NOTHING: the screen effect (cl_nightvision_fx.lua, GryMod.NightVisionFX) and the energy bar (cl_hud_nightvision_flash.lua) read it, through NV.IsOn,
-- NV.Fade, NV.Mix, NV.Bar and the hook GryMod_NightVision.
--
-- The original game (the study of docs/superpowers/plans/2026-11-24-nightvision-crysis-study.md, section C): its own energy bar, 30 at most, 0.5 a
-- second used while it is on (60 s from full), 2 a second recovered while it is off (15 s from empty); at zero it switches itself off, and it cannot be
-- switched on at zero; the picture fades in and out by 4 a second (0.25 s); the sounds are select (on), a loop (while on) and deselect (off).
--
-- NOTHING RUNS BY ITSELF. The energy and the fade are not stepped: the state keeps the energy and the time of its last change, and the value is worked
-- out from the clock when somebody reads it (a night vision that was off for an hour needs no tick to be full). The one thing that must happen at a
-- given moment, the energy reaching zero while it is on, is ONE timer set for that very second (GryMod_NightVisionEmpty), taken away when it goes off.
-- While it is on (only) a guard watches the player at every frame (death, suit down, settings), and it is removed the moment it goes off. The other hooks
-- are events: the HUD status, the HUD events, the end of the game, the arrival in a map, the settings.
--
-- A switch always goes through NV.Set(on, reason): the state changes, then the HUD event `night_vision` {on = ..., reason = ...} is played, which plays
-- the sounds (select and the loop, or the end of the loop and deselect) and runs the hook GryMod_NightVision(on, reason). The event can be played from
-- outside too (the effects test window, an addon, the server): it asks for the same switch, under the same rules (the option, the server's switch, a
-- living player with a working suit, some energy). It goes off by itself on death, a suit that goes down or off, the end of the game, a new map, no
-- energy, the option turned off and the server's switch turned off, and it never comes back by itself.
--
-- The reasons: key, toggle, api (from code), event (played from outside); and when it goes off by itself: energy, dead, invalid, suit, malfunction,
-- death (the HUD's death), disabled (the suit's own HUD event), option, server, shutdown (end of the game), init (a new map).

GryMod = GryMod or {}

local NV = GryMod.NightVision or {}
GryMod.NightVision = NV

-- ---------------------------------------------------------------------------------------------------------
-- The settings
-- ---------------------------------------------------------------------------------------------------------

local OptionCV = CreateClientConVar("gry_nightvision", "1", true, false, "The suit's night vision (a light amplifier with its own energy, key N by default); 0: it cannot be switched on")
local HoldCV = CreateClientConVar("gry_nightvision_hold", "0", true, false, "How the night vision key works: 0 press to switch on and again to switch off, 1 hold the key (on while it is down)", 0, 1)
local EnergyCV = CreateClientConVar("gry_nightvision_energy", "1", true, false, "The night vision has an energy of its own (60 s of use from full, 15 s to refill, it switches off when empty); 0: no limit and no bar", 0, 1)
local DrainCV = CreateClientConVar("gry_nightvision_drain", "0.5", true, false, "Energy the night vision uses in a second while it is on (30 at most: 0.5 is 60 s of use, the original's)", 0.05, 5)
local RechargeCV = CreateClientConVar("gry_nightvision_recharge", "2", true, false, "Energy the night vision recovers in a second while it is off (2 is 15 s from empty, the original's)", 0.1, 20)

-- The ones the screen effect reads (cl_nightvision_fx.lua): they are made here, with the rest of the options.
CreateClientConVar("gry_nightvision_light", "1", true, false, "Night vision: a soft projected light behind you, with shadows, that lights what you look at", 0, 1)
CreateClientConVar("gry_nightvision_star", "1", true, false, "Night vision: a faint starlight pass that lifts the darkest parts (costs a second render of the world)", 0, 1)
CreateClientConVar("gry_nightvision_localgain", "1", true, false, "Night vision: each dark area of the screen is brightened on its own; 0: one gain for the whole screen", 0, 1)
CreateClientConVar("gry_nightvision_fx", "1", true, false, "Night vision: the screen effect; 0 keeps only the sounds and the energy bar", 0, 1)

-- ---------------------------------------------------------------------------------------------------------
-- The pure parts
-- ---------------------------------------------------------------------------------------------------------

-- The energy of the night vision at most, and what the bar of the HUD shows for it (0 to 100).
NV.MAX = 30
-- The picture rises by this much in a second while it is on and falls by it while it is off (0.25 s each way).
NV.FADE_RATE = 4
-- An energy this close to zero is zero (the timer of the game may come a hundredth of a second early).
NV.EMPTY = 0.01

-- What a stretch of dt seconds does to the energy: state = {energy, on}, cfg = {max, drain, recharge} (units a second). Gives the new energy and whether
-- it reached zero (only while on). Pure; a clock that went back (dt <= 0) changes nothing.
function NV.Advance(state, dt, cfg)
	if not (dt > 0) then
		dt = 0
	end

	local energy = state.energy

	if state.on then
		if not (cfg.drain > 0) then
			return energy, false
		end

		local left = energy - cfg.drain * dt

		if left <= 0 then
			return 0, true
		end

		return left, false
	end

	return math.min(energy + cfg.recharge * dt, cfg.max), false
end

-- The fade after dt seconds towards on (fade rises) or off (it falls), held between 0 and 1. Pure.
function NV.FadeStep(fade, on, dt)
	if not (dt > 0) then
		dt = 0
	end

	return math.Clamp(fade + (on and NV.FADE_RATE or -NV.FADE_RATE) * dt, 0, 1)
end

-- The weight of the effect on the picture: the fade squared (the original blends with fade * fade, so the switch is eased). With no argument, the one of
-- the night vision now.
function NV.Mix(fade)
	if fade == nil then
		fade = NV.Fade()
	end

	return fade * fade
end

-- The first reason the night vision cannot be on, from the facts of a situation, or nil. w = {option, server, valid, alive, suit, malfunction, energy}. Pure.
function NV.Refuse(w)
	if not w.option then return "option" end
	if not w.server then return "server" end
	if not w.valid then return "invalid" end
	if not w.alive then return "dead" end
	if not w.suit then return "suit" end
	if w.malfunction then return "malfunction" end
	if not (w.energy > 0) then return "empty" end

	return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- The state: when it last changed and what it was then. Nothing is stepped.
-- ---------------------------------------------------------------------------------------------------------

local S = NV.State or {on = false, energy0 = NV.MAX, t0 = 0, fade0 = 0, fadeT0 = 0}
NV.State = S

local TIMER = "GryMod_NightVisionEmpty"
local GUARD = "GRYNIGHTVISIONGUARD"
local LOOPUP = "GryMod_NightVisionLoopUp"

-- the status of the HUD as last reported (0 working, 1 the suit is down, 2 flickering)
local hudStatus = 0

-- The clock of the energy and of the fade: the game's time (it stands still while the game is paused). Replaced by the tests.
function NV.Clock()
	return CurTime()
end

local cfg = {max = NV.MAX, drain = 0.5, recharge = 2}
local scratch = {energy = 0, on = false}

-- The rates now, from the settings (one table, filled again).
function NV.Config()
	cfg.drain = math.max(DrainCV:GetFloat(), 0)
	cfg.recharge = math.max(RechargeCV:GetFloat(), 0)

	return cfg
end

function NV.Option()
	return OptionCV:GetBool()
end

function NV.Hold()
	return HoldCV:GetBool()
end

-- The energy is not limited (the setting gry_nightvision_energy at 0): it is always whole, no timer, and the HUD has no bar to show.
function NV.Unlimited()
	return not EnergyCV:GetBool()
end

-- Whether the bar of the energy is to be shown (the HUD's own switches apart).
function NV.BarVisible()
	return not NV.Unlimited()
end

-- Whether it is on (the wanted state). The picture follows it in 0.25 s (NV.Fade).
function NV.IsOn()
	return S.on
end

-- The energy now (0 to 30), worked out from the last change.
function NV.Energy()
	if NV.Unlimited() then
		return NV.MAX
	end

	scratch.energy, scratch.on = S.energy0, S.on

	return (NV.Advance(scratch, NV.Clock() - S.t0, NV.Config()))
end

-- The energy as the bar of the HUD takes it (0 to 100).
function NV.Bar()
	return NV.Energy() * 100 / NV.MAX
end

-- The fade now (0 to 1), worked out from the last change.
function NV.Fade()
	return NV.FadeStep(S.fade0, S.on, NV.Clock() - S.fadeT0)
end

-- The one timer: set for the second the energy reaches zero while it is on, nothing otherwise.
local function arm()
	timer.Remove(TIMER)

	if not S.on or NV.Unlimited() then
		return
	end

	local drain = NV.Config().drain

	if not (drain > 0) then
		return
	end

	timer.Create(TIMER, math.max(NV.Energy() / drain, 0), 1, NV.Expire)
end

-- The timer came: if the energy is at zero it goes off (reason energy), else (a timer a moment early, a setting changed) it is set again for the rest.
function NV.Expire()
	if not S.on then
		return
	end

	if NV.Unlimited() or NV.Energy() > NV.EMPTY then
		arm()

		return
	end

	NV.Set(false, "energy")
end

-- The energy is set to this value from now (the tests, an addon that gives or takes energy).
function NV.SetEnergy(energy)
	S.energy0, S.t0 = math.Clamp(tonumber(energy) or NV.MAX, 0, NV.MAX), NV.Clock()
	arm()
end

-- ---------------------------------------------------------------------------------------------------------
-- What the world says
-- ---------------------------------------------------------------------------------------------------------

local svConVar

-- The server's switch (gry_sv_nightvision, replicated): on while the server has none (a game of the old version).
function NV.ServerAllowed()
	svConVar = svConVar or GetConVar("gry_sv_nightvision")

	return svConVar == nil or svConVar:GetBool()
end

-- Fills a table with the facts that decide whether it can be on (see NV.Refuse). Replaced by the tests.
function NV.ReadWorld(w)
	local ply = LocalPlayer()

	w.option = OptionCV:GetBool()
	w.server = NV.ServerAllowed()
	w.valid = IsValid(ply)
	w.alive, w.suit, w.malfunction = false, false, false

	if w.valid then
		local API, Boot = GryMod.API, GryMod.FlashBoot

		-- (a player killed is at 0 health one frame before Alive() says so: measured by the zoom)
		w.alive = ply:Alive() and ply:Health() > 0
		w.suit = not (API and API.IsSuitEnabled) or API.IsSuitEnabled(ply)
		w.malfunction = hudStatus == 1 or ply:GetNW2Bool("GryMalfunction", false) or (Boot ~= nil and Boot.IsLost ~= nil and Boot.IsLost() == true)
	end

	w.energy = NV.Energy()

	return w
end

local world = {}

-- The reason it cannot be switched on now, or nil: option, server, invalid, dead, suit, malfunction, empty, or "veto": an addon whose own view must not be disturbed (a
-- camera, a cinematic) refused it through the hook GryMod_CanUseView("nightvision", reason), by returning false (SHARED-VIEW-VETO-1). `reason` is what asks to switch it
-- on ("key", "toggle", "api", "event", or "query" for a question that switches nothing). Only the switching on is asked: a night vision that is on stays on.
function NV.Refusal(reason)
	local why = NV.Refuse(NV.ReadWorld(world))

	if why == nil and hook.Run("GryMod_CanUseView", "nightvision", reason or "query") == false then
		return "veto"
	end

	return why
end

function NV.CanTurnOn()
	return NV.Refusal("query") == nil
end

-- ---------------------------------------------------------------------------------------------------------
-- The sounds (the files of the contract: cl_sound_mix.lua has their level)
-- ---------------------------------------------------------------------------------------------------------

NV.Sounds = {
	select = "grymod/suit/night_vision_select.wav",
	loop = "grymod/suit/night_vision_ambience.wav",
	deselect = "grymod/suit/night_vision_deselect.wav"
}

-- Whether a sound file is there (the game's files). A file that is not there plays nothing and is no error. Replaced by the tests.
function NV.FileExists(path)
	return file.Exists("sound/" .. path, "GAME")
end

-- The ambience loop: one channel, made the first time it is wanted (the loading is asynchronous), played from silence and brought up in a few hundredths
-- of a second (a loop that starts at its level clicks). Nothing looks at it: the events start it and stop it.
local loop = {channel = nil, loading = false, playing = false}

NV.Loop = {
	GetChannel = function() return loop.channel end,
	SetChannel = function(channel) loop.channel = channel end,
	IsPlaying = function() return loop.playing end
}

local function loopVolume()
	local path = NV.Sounds.loop

	return GryMod.SoundMix.Volume(path) * GryMod.SoundMix.SuitGain(path)
end

local function raiseLoop()
	if loop.playing and IsValid(loop.channel) then
		loop.channel:SetVolume(loopVolume())
	end
end

local function startLoop()
	if loop.playing then
		return
	end

	loop.playing = true

	if IsValid(loop.channel) then
		loop.channel:SetTime(0)
		loop.channel:SetVolume(0)
		loop.channel:Play()
		timer.Create(LOOPUP, GryMod.SoundMix.FadeInSeconds, 1, raiseLoop)

		return
	end

	if loop.loading then
		return
	end

	loop.loading = true

	sound.PlayFile("sound/" .. NV.Sounds.loop, "noblock noplay", function(created)
		loop.loading = false

		if not IsValid(created) then
			return
		end

		loop.channel = created
		created:EnableLooping(true)

		if loop.playing then
			created:SetVolume(0)
			created:Play()
			timer.Create(LOOPUP, GryMod.SoundMix.FadeInSeconds, 1, raiseLoop)
		end
	end)
end

local function stopLoop()
	if not loop.playing then
		return
	end

	loop.playing = false
	timer.Remove(LOOPUP)

	if IsValid(loop.channel) then
		loop.channel:SetVolume(0)
		loop.channel:Pause()
	end
end

-- The loop plays while it is on, the sounds are on and the file is there; anything else stops it.
function NV.Loop.Sync()
	if S.on and GryMod.SoundsEnabled() and NV.FileExists(NV.Sounds.loop) then
		startLoop()
	else
		stopLoop()
	end
end

local function playSound(path)
	if NV.FileExists(path) then
		GryMod.PlaySound(path)
	end
end

-- The reasons that make no sound of their own (the game ends, a new map: nothing to announce).
NV.SILENT = {shutdown = true, init = true}

local reportedError

-- What a switch plays: the sounds (select and the loop, or the end of the loop and deselect) and the hook GryMod_NightVision(on, reason). This is the
-- sound half of the HUD event night_vision (the picture reads the state). A listener of the hook that fails is told once and stops nothing.
function NV.Play(on, reason)
	local silent = NV.SILENT[reason]

	NV.Loop.Sync()

	if not silent then
		playSound(on and NV.Sounds.select or NV.Sounds.deselect)
	end

	local ok, err = pcall(hook.Run, "GryMod_NightVision", on, reason)

	if not ok and err ~= reportedError then
		reportedError = err
		ErrorNoHalt("[GryMod] GryMod_NightVision listener: " .. tostring(err) .. "\n")
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Switching
-- ---------------------------------------------------------------------------------------------------------

-- Once per frame while it is ON (the hook exists only then): the player and the options, as the situation of a zoom is watched. Whatever refuses it
-- (but the energy: the timer has that) switches it off.
function NV.Guard()
	if not S.on then
		return
	end

	NV.ReadWorld(world)
	world.energy = NV.MAX

	local reason = NV.Refuse(world)

	if reason then
		NV.Set(false, reason)
	end
end

local function guardThink()
	NV.Guard()
end

-- The state changes (no report): the energy and the fade are kept as they are at this moment, then the new direction, the timer and the guard.
local function apply(on)
	local now = NV.Clock()
	local energy = NV.Energy()

	if S.on and energy <= NV.EMPTY then
		energy = 0
	end

	S.energy0, S.t0, S.fade0, S.fadeT0, S.on = energy, now, NV.Fade(), now, on

	if on then
		hook.Add("Think", GUARD, guardThink)
	else
		hook.Remove("Think", GUARD)
	end

	arm()
end

-- true while NV.Set reports its own switch to the event (the handler then plays and does not switch again)
local reporting = false

-- The report of a switch: the HUD event, which plays the sounds and runs the hook. Without the API, the same thing directly.
local function report(on, reason)
	local API = GryMod.API

	if API and API.HUDEvent then
		reporting = true

		local ok, err = API.HUDEvent("night_vision", {on = on, reason = reason})

		reporting = false

		if ok or err ~= "unknown event" then
			return
		end
	end

	NV.Play(on, reason)
end

-- Switches it on or off. Returns true when it changed; false and the reason when it did not ("same": it already was so, or why it cannot be on, see
-- NV.Refusal). Going on is refused when it cannot be on; going off never is.
function NV.Set(on, reason)
	on = on == true

	if on == S.on then
		return false, "same"
	end

	if on then
		local why = NV.Refusal(reason or "api")

		if why then
			return false, why
		end
	end

	apply(on)
	report(on, reason or "api")

	return true
end

function NV.Toggle(reason)
	return NV.Set(not S.on, reason or "toggle")
end

-- The key goes down or up. Hold: on while it is down. Toggle: each press switches, the release does nothing.
function NV.Press(down)
	if HoldCV:GetBool() then
		NV.Set(down == true, "key")
	elseif down then
		NV.Toggle("key")
	end
end

-- Everything back to the start, silently (nothing is told): off, whole energy, no fade, no timer, no guard, the loop stopped.
function NV.Reset()
	local now = NV.Clock()

	timer.Remove(TIMER)
	hook.Remove("Think", GUARD)
	stopLoop()
	S.on, S.energy0, S.t0, S.fade0, S.fadeT0 = false, NV.MAX, now, 0, now
	hudStatus = 0
end

-- ---------------------------------------------------------------------------------------------------------
-- The HUD event night_vision
-- ---------------------------------------------------------------------------------------------------------

-- The event: data.on (true or false), data.reason (optional, "event" by default). Played by NV.Set it plays the sounds and runs the hook; played from
-- outside (the effects test window, an addon, the server) it asks for the switch under the same rules, then plays. A state it is already in plays nothing.
local function eventHandler(data)
	local on = data.on

	if on ~= true and on ~= false then
		return
	end

	local reason = isstring(data.reason) and data.reason or "event"

	if reporting then
		NV.Play(on, reason)

		return
	end

	if S.on == on or (on and NV.Refusal("event")) then
		return
	end

	apply(on)
	NV.Play(on, reason)
end

function NV.RegisterEvent()
	local API = GryMod.API

	if not (API and API.RegisterHUDEvent) then
		return false
	end

	return API.RegisterHUDEvent("night_vision", eventHandler, {
		label = "Night vision",
		variants = {{label = "Night vision on", data = {on = true}}, {label = "Night vision off", data = {on = false}}},
		follows = {{"gry_nightvision", "the night vision"}, {"gry_sounds", "the sounds"}}
	})
end

NV.RegisterEvent()

-- ---------------------------------------------------------------------------------------------------------
-- The key
-- ---------------------------------------------------------------------------------------------------------

local Key

local defaultKey, defaultUntil = nil, -math.huge

-- The default key: N, while nothing in the game is bound to it and neither the zoom nor the quick menu has it. It is never saved in the player's settings;
-- looked up once in half a second (the engine calls walk the binds).
function NV.DefaultKey()
	local now = RealTime()

	if now >= defaultUntil or now < defaultUntil - 0.5 then
		local zoom, menu = GryMod.SuitZoom, GryMod.MenuKey
		local taken = (zoom ~= nil and zoom.Key.Effective() == KEY_N) or (menu ~= nil and menu.Chosen() == KEY_N)

		defaultKey, defaultUntil = nil, now + 0.5

		if not taken and GryMod.KeyBinder.Conflict(KEY_N, "+gry_nightvision") == nil then
			defaultKey = KEY_N
		end
	end

	return defaultKey
end

-- A bind just made, a key just chosen, a test: the next question looks at the binds again.
function NV.ForgetBinding()
	Key.ForgetBinding()
	defaultKey, defaultUntil = nil, -math.huge
end

Key = GryMod.KeyBinder.New{
	convar = "gry_nightvision_key",
	description = "Key of the night vision (a button code, 0 = none; `bind <key> +gry_nightvision` works too). While none is chosen the default is N, if nothing is bound to it",
	command = "+gry_nightvision",
	title = "GryMod night vision",
	text = "Click the box and press the key of the night vision\n(or bind one to +gry_nightvision in the console).",
	y = 330,
	active = function() return OptionCV:GetBool() end,
	default = function()
		if not OptionCV:GetBool() or Key.IsBoundCached() then
			return nil
		end

		return NV.DefaultKey()
	end,
	refuse = function(code)
		return code == MOUSE_WHEEL_UP or code == MOUSE_WHEEL_DOWN
			or (GryMod.SuitZoom ~= nil and GryMod.SuitZoom.Key.Chosen() == code)
			or (GryMod.MenuKey ~= nil and GryMod.MenuKey.Chosen() == code)
	end,
	press = function(down)
		NV.Press(down)
	end
}

NV.Key = Key

-- `bind <key> +gry_nightvision` (the engine runs -gry_nightvision at the release).
concommand.Add("+gry_nightvision", function()
	NV.ForgetBinding()
	NV.Press(true)
end)

concommand.Add("-gry_nightvision", function()
	NV.Press(false)
end)

-- ---------------------------------------------------------------------------------------------------------
-- What switches it off by itself (and the arrival in a game)
-- ---------------------------------------------------------------------------------------------------------

-- The HUD's status (cl_hud_flash.lua): 1 is the suit down (a malfunction, or the death when the second argument says so), 0 working, 2 flickering.
function NV.OnHUDStatus(status, why)
	hudStatus = status

	if status == 1 then
		NV.Set(false, why == "death" and "death" or "malfunction")
	end
end

-- The HUD events: the suit's own shutdown (the server's flag, GryMod.API.SetSuitEnabled) is the event "disabled".
function NV.OnHUDEvent(name)
	if name == "disabled" then
		NV.Set(false, "disabled")
	end
end

-- The end of the game (a disconnect, the game closing).
function NV.OnShutdown()
	NV.Set(false, "shutdown")
	NV.Loop.Sync()
end

-- The arrival in a map: off and back to the start (whole energy, a new HUD).
function NV.OnInit()
	NV.Set(false, "init")
	NV.Reset()
	svConVar = nil
	NV.ForgetBinding()
end

-- A setting changed (the player's, or the server's switch as it arrives): what must go off does, a timer follows the new rates.
function NV.OnSettingChanged(name)
	if name == "gry_nightvision" or name == "gry_sv_nightvision" then
		NV.Guard()
	elseif name == "gry_sounds" then
		NV.Loop.Sync()
	elseif S.on then
		arm()
	end
end

hook.Add("GryMod_HUDStatus", "GRYNIGHTVISION", function(status, why)
	NV.OnHUDStatus(status, why)
end)

hook.Add("GryMod_HUDEvent", "GRYNIGHTVISION", function(name)
	NV.OnHUDEvent(name)
end)

hook.Add("ShutDown", "GRYNIGHTVISION", function()
	NV.OnShutdown()
end)

hook.Add("InitPostEntity", "GRYNIGHTVISION", function()
	NV.OnInit()
end)

for _, name in ipairs({"gry_nightvision", "gry_sv_nightvision", "gry_sounds", "gry_nightvision_energy", "gry_nightvision_drain", "gry_nightvision_recharge"}) do
	cvars.AddChangeCallback(name, function(convar)
		NV.OnSettingChanged(convar)
	end, "GRYNIGHTVISION")
end
