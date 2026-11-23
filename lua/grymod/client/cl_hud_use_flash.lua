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

	return {icon = entry.icon, text = API.UsableText(ent, ply, entry) or PLAIN.text}
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local instance -- {root, icons}
local failed = false
local shown -- {icon, text} on show, or nil
local hooked = false

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

	Flash.Draw(current.root, x, y, scale)
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

	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
end

-- The crosshair says what it aims at (see the head of this file).
hook.Add("GryMod_UsableChanged", "GryUsePrompt", function(ent, mode, ply)
	if Use.Enabled() then
		Use.Set(Use.Describe(ent, mode, ply))
	else
		Use.Set(nil)
	end
end)
