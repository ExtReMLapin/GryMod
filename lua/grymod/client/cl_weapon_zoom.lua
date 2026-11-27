-- Asks the server to end the zoom of a weapon at the moment the binoculars open. The crossbow's right click zooms (the engine's field of
-- view goes to 20 and the WEAPON owns that zoom); the binoculars give a view of their own (the stages' field of view, see
-- cl_hud_binoculars_flash.lua), and when they close they hand the view back to the engine, whose field of view is still the crossbow's: a
-- jump to the weapon's zoom (measured, see docs/superpowers/plans/2026-11-21-weapon-zoom-cancel.md). The Half-Life 2 zoom key cannot take
-- the zoom from a weapon that owns it either, so the binoculars opened by that key behave the same.
--
-- The decision is made at the OPENING of the binoculars (the event GryMod_BinocularsToggled with true, whichever of the own zoom or the Half-Life 2
-- key opened them) and only there: the weapon in hand zooms with its right click (the crossbow: alt = "zoom" in the weapon registry) and the player's field of view is below the normal one
-- (fov_desired). The client cannot always tell the weapon's zoom from the Half-Life 2 zoom just starting with the same weapon in hand
-- (measured: the key can be seen down a frame after the suit's field of view began to move, and a request was then sent for nothing), so
-- the server has the last word (sv_weapon_zoom.lua: the zoom really owned by that weapon, a living player, 5 requests a second): a
-- request that finds the suit's zoom or none does nothing. One check box (gry_zoom_cancel_weapon, on by default).

GryMod = GryMod or {}

local WeaponZoom = GryMod.WeaponZoom or {}
GryMod.WeaponZoom = WeaponZoom

local OptionConVar = CreateClientConVar("gry_zoom_cancel_weapon", "1", true, false, "When the binoculars open while the crossbow is zoomed (right click), the crossbow's zoom is ended, so that it does not come back when the binoculars close (off: it comes back, a jump)")

local HideConVar = CreateClientConVar("gry_zoom_hide_crosshair", "1", true, false, "The crosshair of the HUD is hidden while the weapon in hand is zoomed (the crossbow's right click, or any weapon declared with alt = \"zoom\"), as it is while the binoculars are up (off: it stays)")

-- The weapons whose zoom the binoculars end are the ones whose registry entry says that the right click zooms (alt = "zoom", the
-- crossbow's entry in compat/hl2/sh_weapons.lua, or any other addon's weapon declared that way); the server asks the registry the same way.

-- a field of view this much below the normal one is a zoom (degrees)
WeaponZoom.TOLERANCE = 0.5

function WeaponZoom.Enabled()
	return OptionConVar:GetBool()
end

-- Whether the weapon in hand is zooming: its registry entry says the right click zooms (alt = "zoom") and the field of view is below the normal
-- one. The crosshair of the HUD asks it (below): a scope has its own aim. Nothing is allocated, the HUD asks every frame.
function WeaponZoom.IsZoomed(ply)
	if not HideConVar:GetBool() then
		return false
	end

	local weapon = WeaponZoom.ZoomingWeapon(ply)

	-- a weapon with no scope aim of its own (the crossbow) keeps the crosshair while it zooms (zoomCrosshair: true, or the number of the one it shows)
	return weapon ~= nil and not GryMod.API.WeaponValue(weapon, "zoomCrosshair", true)
end

-- The weapon in hand when it is zooming (its registry entry says the right click zooms and the field of view is below the normal one), else nil.
function WeaponZoom.ZoomingWeapon(ply)
	if not IsValid(ply) then
		return nil
	end

	local weapon = ply:GetActiveWeapon()

	if not IsValid(weapon) or GryMod.API.WeaponValue(weapon, "alt", true) ~= "zoom" then
		return nil
	end

	local fov, default = ply:GetFOV(), ply:GetInfoNum("fov_desired", 75)

	if type(fov) == "number" and type(default) == "number" and fov < default - WeaponZoom.TOLERANCE then
		return weapon
	end

	return nil
end

-- The crosshair of the movie (1 to 13) the weapon in hand wants while it zooms (its registry's zoomCrosshair, when that is a number), else nil: the player's
-- style. The crossbow is a precision weapon: its zoom shows the thin cross, not the wide circle of the default style.
function WeaponZoom.CrosshairFor(ply)
	local weapon = WeaponZoom.ZoomingWeapon(ply)
	local wanted = weapon and GryMod.API.WeaponValue(weapon, "zoomCrosshair", true)

	return isnumber(wanted) and wanted or nil
end

-- The crosshair's own test of "the player is zooming" (cl_hud_crosshair_flash.lua, Cross.Zooming, which knows the binoculars) also says yes
-- for a zoomed weapon. That file is loaded first; its function is wrapped once (a reload of this file does not wrap it again).
local Cross = GryMod.FlashCrosshair

if Cross and Cross.Zooming and Cross.Zooming ~= WeaponZoom.CrossWrapper then
	WeaponZoom.CrossBase = Cross.Zooming

	WeaponZoom.CrossWrapper = function(ply)
		return WeaponZoom.CrossBase(ply) or WeaponZoom.IsZoomed(ply)
	end

	Cross.Zooming = WeaponZoom.CrossWrapper
end

-- Whether to ask the server to end the weapon's zoom. `weapon` is the weapon in hand (an entity, or its class name; nil for none). Pure
-- as far as the weapon registry goes (it only reads it).
function WeaponZoom.Decide(enabled, wasWanted, wanted, weapon, fov, defaultFov)
	if not enabled or wasWanted or not wanted then
		return false
	end

	if weapon == nil or GryMod.API.WeaponValue(weapon, "alt", true) ~= "zoom" then
		return false
	end

	if type(fov) ~= "number" or type(defaultFov) ~= "number" or fov ~= fov or defaultFov ~= defaultFov then
		return false
	end

	return fov < defaultFov - WeaponZoom.TOLERANCE
end

-- The request: a message with no payload (the server looks at the weapon in the player's hands).
function WeaponZoom.Send()
	net.Start("gry_cancel_weapon_zoom")
	net.SendToServer()
end

-- The binoculars have just gone up (the event GryMod_BinocularsToggled, cl_hud_binoculars_flash.lua): reads the world once, now, and asks
-- if it must.
function WeaponZoom.Opened(ply)
	local Bino = GryMod.FlashBinoculars

	if not WeaponZoom.Enabled() or Bino == nil or not IsValid(ply) then
		return
	end

	-- (the element off or the movie missing: the binoculars are not drawn and their view is not given, nothing changes on the screen)
	if not Bino.Enabled() or Bino.IsMissing() then
		return
	end

	local weapon = ply:GetActiveWeapon()

	if WeaponZoom.Decide(true, false, true, IsValid(weapon) and weapon or nil, ply:GetFOV(), ply:GetInfoNum("fov_desired", 75)) then
		WeaponZoom.Send()
	end
end

-- No Think hook: the opening is an event. (A hook of an older copy of this file that looked at every frame goes.)
hook.Remove("Think", "GRYWEAPONZOOM")

hook.Add("GryMod_BinocularsToggled", "GRYWEAPONZOOM", function(wanted)
	if wanted then
		WeaponZoom.Opened(LocalPlayer())
	end
end)
