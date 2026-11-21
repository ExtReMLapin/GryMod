-- Ends the zoom of a weapon when the binoculars open (the client asks: gry_cancel_weapon_zoom, no payload). The crossbow's right click
-- zooms: the weapon asks the engine for a field of view of 20 and OWNS that zoom (Player m_hZoomOwner is the weapon). The binoculars give a
-- view of their own (a field of view from their stages, see cl_hud_binoculars_flash.lua) and, when they close, hand the view back to the
-- engine, whose field of view is still the crossbow's: a jump to the weapon's zoom (measured: 61.6 eased up to 100, then 20 after 0.6 s;
-- the same with the Half-Life 2 zoom key, which cannot take the zoom from a weapon that owns it).
--
-- What the server does, only for a weapon whose registry entry says alt = "zoom" that really owns the zoom of a living player:
--   * the next command of the player carries IN_ATTACK2 once: the crossbow toggles its zoom off itself, with its own state (m_bInZoom,
--     not readable from Lua) put right, so the next right click zooms again at once (a field of view released from outside leaves that
--     state on, and the next click would do nothing visible);
--   * a moment later, if the weapon still owns the zoom (the command never came, or the weapon was not ready for a secondary attack),
--     the player's field of view is released with the weapon as the requester (Player:SetFOV(0, t) without it is refused: measured).
-- Nothing is done for another weapon, for a zoom the player owns (the suit's) or for nobody's: an IN_ATTACK2 there would ZOOM the crossbow.
-- A player may ask 5 times a second at most (the questions beyond are ignored), like the friendly cross (sv_friendly.lua).

util.AddNetworkString("gry_cancel_weapon_zoom")

GryMod = GryMod or {}

local WeaponZoom = GryMod.WeaponZoom or {}
GryMod.WeaponZoom = WeaponZoom

-- The weapons whose zoom the binoculars end are the ones whose registry entry says that the right click zooms (alt = "zoom": the
-- crossbow's entry in sh_api_weapons_hl2.lua, or any other addon's weapon declared that way); the client asks the registry the same way.

WeaponZoom.LIMIT = 5 -- requests per player per window
WeaponZoom.WINDOW = 1 -- seconds
-- how long the command is given to work before the field of view is released by force, seconds
WeaponZoom.FALLBACK_DELAY = 0.3

local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}
local pending = setmetatable({}, {__mode = "k"}) -- [player] = the weapon whose zoom is to end

-- Everything forgotten (the tests).
function WeaponZoom.Reset()
	windows = setmetatable({}, {__mode = "k"})
	pending = setmetatable({}, {__mode = "k"})
end

function WeaponZoom.Forget(ply)
	windows[ply] = nil
	pending[ply] = nil
end

-- Whether the player may ask now (5 a second).
function WeaponZoom.Allowed(ply, now)
	local w = windows[ply]

	if not w or now - w.start >= WeaponZoom.WINDOW then
		windows[ply] = {start = now, count = 1}

		return true
	end

	if w.count >= WeaponZoom.LIMIT then
		return false
	end

	w.count = w.count + 1

	return true
end

-- The weapon whose zoom the player is in, when it is the one in his hands, its registry entry says alt = "zoom", he is alive and the weapon owns the
-- zoom; nil otherwise.
function WeaponZoom.Zoomer(ply)
	if not ply or not IsValid(ply) or not ply:Alive() then
		return nil
	end

	local weapon = ply:GetActiveWeapon()

	if not weapon or not IsValid(weapon) or GryMod.API.WeaponValue(weapon, "alt", true) ~= "zoom" then
		return nil
	end

	if ply:GetInternalVariable("m_hZoomOwner") ~= weapon then
		return nil
	end

	return weapon
end

-- The safety net: the weapon still owns the zoom, its owner's field of view goes back to normal in a tenth of a second.
function WeaponZoom.Fallback(ply, weapon)
	if pending[ply] == weapon then
		pending[ply] = nil
	end

	if WeaponZoom.Zoomer(ply) == weapon then
		ply:SetFOV(0, 0.1, weapon)
	end
end

-- One request. `schedule(delay, fn)` runs the safety net later (timer.Simple). Returns whether the zoom is to end.
function WeaponZoom.Handle(ply, now, schedule)
	if not ply or not IsValid(ply) or not WeaponZoom.Allowed(ply, now) then
		return false
	end

	local weapon = WeaponZoom.Zoomer(ply)

	if not weapon then
		return false
	end

	pending[ply] = weapon
	schedule = schedule or timer.Simple
	schedule(WeaponZoom.FALLBACK_DELAY, function()
		WeaponZoom.Fallback(ply, weapon)
	end)

	return true
end

-- The player's command (StartCommand): the one IN_ATTACK2, only while the weapon that was to be toggled off still owns the zoom.
function WeaponZoom.Command(ply, cmd)
	local weapon = pending[ply]

	if not weapon then
		return
	end

	pending[ply] = nil

	if WeaponZoom.Zoomer(ply) == weapon then
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK2))
	end
end

net.Receive("gry_cancel_weapon_zoom", function(_, ply)
	WeaponZoom.Handle(ply, RealTime())
end)

hook.Add("StartCommand", "GryMod weapon zoom", function(ply, cmd)
	if next(pending) ~= nil then
		WeaponZoom.Command(ply, cmd)
	end
end)

hook.Add("PlayerDisconnected", "GryMod weapon zoom", function(ply)
	WeaponZoom.Forget(ply)
end)

hook.Add("PostPlayerDeath", "GryMod weapon zoom", function(ply)
	pending[ply] = nil
end)
