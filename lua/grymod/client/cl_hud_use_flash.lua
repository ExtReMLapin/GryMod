-- The use prompt under the crosshair drawn from the original Scaleform movie (HUD_InterActiveIcons), see cl_flash.lua: an icon (use,
-- enter, pickup, grab or ladder) and a text ("TAKE <weapon>", "ENTER VEHICLE", "CLIMB", "USE") when the player looks at something he
-- can use or take. The movie's functions (setUseIcon, setText) are ported by hand: the icon is a frame of its Icons clip, the text a field
-- in it. The text keys of the original (@use_vehicle...) are the English texts of game_text_messages.xml, kept in the registry of usable
-- entities (sh_api_usable.lua).
--
-- WHETHER something can be used is the crosshair's own test (GryMod.FlashCrosshair.UsableFor, run ten times a second by its scan, which
-- also opens its "usable" state); this file adds WHAT it is. The crosshair says it with the hook GryMod_UsableChanged(ent, mode, ply) at
-- each change, so nothing runs here between two changes: no scan, no timer. The paint hook exists only while a prompt is shown.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local API = GryMod.API

local Use = {}
GryMod.FlashUse = Use

Use.MOVIE = "hud_interactiveicons"

local STAGE_W, STAGE_H = 1024, 768

-- What a usable thing that no entry names shows: the plain use (shared, never changed).
local PLAIN = {icon = "use", text = "USE"}

-- The picture of the stage on a screen of w x h pixels: as high as the screen, centred across its width.
function Use.Placement(w, h)
	local scale = h / STAGE_H

	return (w - STAGE_W * scale) / 2, 0, scale
end

-- ---------------------------------------------------------------------------------------------------------
-- What the key does to the prompt. Two kinds of use (the registry's `use` field):
--   "once" (the default): the use changes the state of the thing (a grenade taken, a mounted gun, a vehicle): the prompt goes away AT ONCE and stays
--     away while the same thing is aimed; it comes back after the player looked away or at another thing;
--   "repeat": a door, a button, a charger: the prompt stays, one HUD event (use_feedback: the icon pulses and a sound plays) says the key was seen,
--     and the prompt is dimmed for the entry's cooldown (0.5 s when it gives none), or while its ready(ent) says no.
--   a "repeat" entry with `hold` (the chargers, the wheels: the key is kept down while they work): the event comes ONCE, at the press, however many times
--     the bind repeats while the key is down, and the prompt is not dimmed; the release (or looking elsewhere) lets the next press count again.
-- The key is seen through PlayerBindPress, which the game calls when a bind is pressed: nothing runs between two presses.
-- ---------------------------------------------------------------------------------------------------------

Use.DEFAULT_COOLDOWN = 0.5
Use.PULSE_SECONDS = 0.25
Use.DIM = 0.35 -- the opacity of a prompt that cannot be used yet
Use.FEEDBACK_SOUND = "grymod/menu/preset_navigation_beep_02.wav" -- the quick menu's navigation beep

local feedbackVar = CreateClientConVar("gry_usehint_feedback", "1", true, false, "1: the use prompt pulses and beeps when you press the use key on a door, a button or a charger, then dims for a moment; 0: no feedback", 0, 1)

local shown -- {icon, text} on show, or nil
local hooked = false
local shownEnt, shownEntry -- what the prompt on show is for
local hiddenEnt -- a one-shot use was made on this thing: no prompt for it until the player looks elsewhere
local cooldownEnt, cooldownUntil = nil, 0
local heldEnt -- the thing a "hold" use is being done on: the key is down, the next presses are repeats
local pulseAt = -math.huge

-- Whether the prompt on show is dimmed at `now`: the key was just used on it (the cooldown), or its ready(ent) says it cannot be used yet.
function Use.Dimmed(now)
	if not shownEnt or not IsValid(shownEnt) then
		return false
	end

	if cooldownEnt == shownEnt and (now or RealTime()) < cooldownUntil then
		return true
	end

	return shownEntry ~= nil and shownEntry.ready ~= nil and not API.UsableReady(shownEnt, shownEntry)
end

-- The pulse of the icon at `now`: 1 right at the key, down to 0 after PULSE_SECONDS.
function Use.Pulse(now)
	local age = (now or RealTime()) - pulseAt

	if age < 0 or age >= Use.PULSE_SECONDS then
		return 0
	end

	return 1 - age / Use.PULSE_SECONDS
end

-- The use key went down (from the bind hook, or called by a test with a clock). Returns whether it did something to the prompt.
function Use.OnUsePressed(now)
	if not shown or not shownEnt or not IsValid(shownEnt) then
		return false
	end

	now = now or RealTime()

	if shownEntry and shownEntry.hold then
		-- the key is already down on this thing: a repeat of the bind, not a new use
		if heldEnt == shownEnt then
			return false
		end

		heldEnt = shownEnt

		if not feedbackVar:GetBool() then
			return false
		end

		if API and API.HUDEvent then
			API.HUDEvent("use_feedback")
		end

		return true
	end

	if shownEntry and shownEntry.use == "repeat" then
		if not feedbackVar:GetBool() or Use.Dimmed(now) then
			return false
		end

		cooldownEnt, cooldownUntil = shownEnt, now + (shownEntry.cooldown or Use.DEFAULT_COOLDOWN)

		if API and API.HUDEvent then
			API.HUDEvent("use_feedback")
		end

		return true
	end

	-- a one-shot use (and a thing no entry names): the state changed, the prompt goes
	hiddenEnt = shownEnt
	Use.Set(nil)

	return true
end

-- The use key went up: the next press on a thing used by holding counts as a new use.
function Use.OnUseReleased()
	heldEnt = nil
end

if API and API.RegisterHUDEvent then
	-- ONE event: the pulse of the icon and its sound together (docs/events.md)
	API.RegisterHUDEvent("use_feedback", function()
		pulseAt = RealTime()

		if GryMod.PlaySound then
			GryMod.PlaySound(Use.FEEDBACK_SOUND)
		end
	end, {
		label = "Use key feedback",
		follows = {{"gry_usehint_feedback", "the pulse and the dimming after the key"}, {"gry_sounds", "the sound"}}
	})
end

-- Whether the prompt is on: the HUD is on (and the suit with it) and the player did not turn the use prompt off.
function Use.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("usehint"))
end

-- What to show for what the crosshair aims at: {icon, text}, or nil for nothing. `mode` is the crosshair's (1 can be used or taken, 2 can
-- not, 0 nothing): a thing that can not be used (a weapon the player already has) shows no prompt, the crosshair turns red for it.
function Use.Describe(ent, mode, ply)
	if mode ~= 1 or not ent or not IsValid(ent) then
		return nil
	end

	local entry = API and API.GetUsable and API.GetUsable(ent)

	if not entry then
		return PLAIN
	end

	return {icon = entry.icon, text = API.UsableText(ent, ply, entry) or PLAIN.text}, entry
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local instance -- {root, icons}
local failed = false
local HOOK = "GRYFLASHUSE"

local function ensure()
	if instance then
		return instance
	end

	if failed then
		return nil
	end

	local movie = Flash.Load(Use.MOVIE)
	local root = movie and Flash.NewRoot(movie, GryMod.FlashHUD and GryMod.FlashHUD.Theme)
	local holder = root and root:Child("Root")
	local icons = holder and holder:Child("Icons")

	if not icons then
		if root then
			Flash.ReleaseClip(root)
		end

		failed = true

		return nil
	end

	instance = {root = root, icons = icons}

	return instance
end

-- Puts the icon and the text in the movie: setUseIcon (a frame of the Icons clip) and setText. The frame first: going back to an earlier
-- one makes the clip again from its first frame, and its text with it.
local function write(current, info)
	current.icons:GotoAndStop(info.icon)

	local holder = current.icons:Find("InterActiveText.Colorset")

	if holder then
		holder:SetText("InterActiveText", info.text)
	end
end

function Use.Paint()
	local ply = LocalPlayer()
	local Cross = GryMod.FlashCrosshair

	if not shown or not IsValid(ply) or not ply:Alive() or not Use.Enabled() then
		return
	end

	-- the prompt goes with the crosshair: the crosshair switched off, or hidden (the quick menu, a vehicle, the Lost animation)
	if not Cross or not Cross.Enabled() or Cross.IsHidden(ply) then
		return
	end

	local current = instance

	if not current then
		current = ensure()

		if not current then
			return
		end

		write(current, shown)
	end

	local x, y, scale = Use.Placement(ScrW(), ScrH())
	local now = RealTime()
	local pulse = Use.Pulse(now)

	-- the pulse: the icon grows a little and comes back, around the middle of the screen (the crosshair)
	if pulse > 0 then
		local grown = scale * (1 + 0.18 * pulse)
		local cx, cy = x + STAGE_W * scale / 2, STAGE_H * scale / 2

		x, y, scale = cx - STAGE_W * grown / 2, cy - STAGE_H * grown / 2, grown
	end

	local dimmed = Use.Dimmed(now)

	if dimmed then
		surface.SetAlphaMultiplier(Use.DIM)
	end

	Flash.Draw(current.root, x, y, scale)

	if dimmed then
		surface.SetAlphaMultiplier(1)
	end
end

local function stopPaint()
	if hooked then
		hook.Remove("HUDPaint", HOOK)
		hooked = false
	end
end

-- Shows this prompt ({icon, text}), or takes it away (nil). The paint hook is added and removed with it.
function Use.Set(info)
	shown = info

	if not info then
		stopPaint()

		return
	end

	local current = ensure()

	if not current then
		shown = nil

		return
	end

	write(current, info)

	if not hooked then
		hook.Add("HUDPaint", HOOK, Use.Paint)
		hooked = true
	end
end

-- What is on show now: the icon and the text, or nil (tests and tools).
function Use.Shown()
	return shown
end

function Use.Active()
	return hooked
end

-- The Icons clip of the movie (its frame is the icon, its InterActiveText the text), or nil before the first prompt (tests and tools).
function Use.Icons()
	return instance and instance.icons
end

-- Takes everything away (a new life, a new theme): the next prompt builds the movie again.
function Use.Reset()
	stopPaint()
	shown = nil
	shownEnt, shownEntry, hiddenEnt, cooldownEnt, cooldownUntil, pulseAt, heldEnt = nil, nil, nil, nil, 0, -math.huge, nil

	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
end

-- The crosshair says what it aims at (see the head of this file).
hook.Add("GryMod_UsableChanged", "GryUsePrompt", function(ent, mode, ply)
	-- another thing, or nothing: the hide of a one-shot use and the cooldown of a repeatable one end
	if ent ~= hiddenEnt then
		hiddenEnt = nil
	end

	if ent ~= cooldownEnt then
		cooldownEnt = nil
	end

	-- the key may have gone up while another thing was aimed, with nobody to see it: a hold ends with the thing
	if ent ~= heldEnt then
		heldEnt = nil
	end

	if not Use.Enabled() or (ent ~= nil and ent == hiddenEnt) then
		shownEnt, shownEntry = nil, nil
		Use.Set(nil)

		return
	end

	local info, entry = Use.Describe(ent, mode, ply)

	shownEnt, shownEntry = info and ent or nil, info and entry or nil
	Use.Set(info)
end)

-- The use key: seen when pressed, never taken away from the game (nothing is returned).
hook.Add("PlayerBindPress", "GryUseFeedback", function(ply, bind, pressed)
	if isstring(bind) and string.find(bind, "+use", 1, true) then
		if pressed then
			Use.OnUsePressed(RealTime())
		else
			Use.OnUseReleased()
		end
	end
end)
