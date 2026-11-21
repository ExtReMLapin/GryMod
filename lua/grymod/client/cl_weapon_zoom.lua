-- Asks the server to end the zoom of a weapon at the moment the binoculars open. The crossbow's right click zooms (the engine's field of
-- view goes to 20 and the WEAPON owns that zoom); the binoculars give a view of their own (the stages' field of view, see
-- cl_hud_binoculars_flash.lua), and when they close they hand the view back to the engine, whose field of view is still the crossbow's: a
-- jump to the weapon's zoom (measured, see docs/superpowers/plans/2026-11-21-weapon-zoom-cancel.md). The Half-Life 2 zoom key cannot take
-- the zoom from a weapon that owns it either, so the binoculars opened by that key behave the same.
--
-- The decision is made at the OPENING of the binoculars (Bino.Wanted going from false to true, whichever of the own zoom or the Half-Life 2
-- key opened them) and only there: the weapon in hand is on the list (the crossbow) and the player's field of view is below the normal one
-- (fov_desired). The client cannot always tell the weapon's zoom from the Half-Life 2 zoom just starting with the same weapon in hand
-- (measured: the key can be seen down a frame after the suit's field of view began to move, and a request was then sent for nothing), so
-- the server has the last word (sv_weapon_zoom.lua: the zoom really owned by that weapon, a living player, 5 requests a second): a
-- request that finds the suit's zoom or none does nothing. One check box (gry_zoom_cancel_weapon, on by default).

GryMod = GryMod or {}

local WeaponZoom = GryMod.WeaponZoom or {}
GryMod.WeaponZoom = WeaponZoom

local OptionConVar = CreateClientConVar("gry_zoom_cancel_weapon", "1", true, false, "When the binoculars open while the crossbow is zoomed (right click), the crossbow's zoom is ended, so that it does not come back when the binoculars close (off: it comes back, a jump)")

-- the weapons whose zoom the binoculars end (the server has the same list)
WeaponZoom.Weapons = {weapon_crossbow = true}

-- a field of view this much below the normal one is a zoom (degrees)
WeaponZoom.TOLERANCE = 0.5

local previous = false

function WeaponZoom.Enabled()
	return OptionConVar:GetBool()
end

-- Whether to ask the server to end the weapon's zoom. Pure.
function WeaponZoom.Decide(enabled, wasWanted, wanted, class, fov, defaultFov)
	if not enabled or wasWanted or not wanted then
		return false
	end

	if class == nil or not WeaponZoom.Weapons[class] then
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

-- Forgets that the binoculars were up.
function WeaponZoom.Reset()
	previous = false
end

-- Once per frame: reads the world only at an opening of the binoculars.
function WeaponZoom.Step(ply)
	local Bino = GryMod.FlashBinoculars
	local wanted = Bino ~= nil and IsValid(ply) and Bino.Wanted(ply) or false
	local was = previous
	previous = wanted

	if was or not wanted or not WeaponZoom.Enabled() then
		return
	end

	-- (the element off or the movie missing: the binoculars are not drawn and their view is not given, nothing changes on the screen)
	if not Bino.Enabled() or Bino.IsMissing() then
		return
	end

	local weapon = ply:GetActiveWeapon()
	local class = IsValid(weapon) and weapon:GetClass() or nil

	if WeaponZoom.Decide(true, was, wanted, class, ply:GetFOV(), ply:GetInfoNum("fov_desired", 75)) then
		WeaponZoom.Send()
	end
end

hook.Add("Think", "GRYWEAPONZOOM", function()
	WeaponZoom.Step(LocalPlayer())
end)
