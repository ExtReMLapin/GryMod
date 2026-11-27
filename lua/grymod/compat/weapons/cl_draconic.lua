-- Draconic Base (client): the fire mode icon of the weapon slot, and the crosshair. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.
-- AddFireModeResolver, answers nil for a weapon that is not Draconic's and does nothing when the base is not installed.
--
-- The fire mode: Draconic keeps it in a networked integer, CurFireMode (1 semi-automatic, 2 automatic, 3 burst; weapons/draconic_base/shared.lua, InitialFireMode), and CLEARS Primary.Automatic
-- for a burst weapon, so GryMod's generic reading of Primary.Automatic shows a single shot for it. A melee weapon (the fists, drc_unarmed: IsMelee) is no gun.
--
-- The crosshair: every Draconic weapon draws a crosshair of its own (the spread of the weapon) in the hook HUDPaint "drc_crosshair" (draconic/cl/hud.lua), over the crosshair of GryMod's
-- HUD. gry_draconic_hide_crosshair (on by default, Draconic tab of the Compatibility page) does not call Draconic's while GryMod's crosshair is up; none of Draconic's settings is changed
-- (cl_drc_disable_crosshairs is the player's own). No hook is added, nothing runs by itself: the wrapper only runs when Draconic's hook does.

GryMod = GryMod or {}

local HUD = GryMod.FlashHUD

if not HUD or not HUD.AddFireModeResolver then
	return -- cl_hud_flash.lua is included first (grymod_shared.lua)
end

local MODES = {"Single", "Auto", "Burst"}

HUD.AddFireModeResolver(function(weapon)
	if weapon.Draconic ~= true then
		return nil
	end

	if weapon.IsMelee == true then
		return "NoGun"
	end

	if not isfunction(weapon.GetNW2Int) then
		return nil
	end

	return MODES[weapon:GetNW2Int("CurFireMode")]
end, "compat.draconic")

local H = GryMod.DraconicHUD or {}
GryMod.DraconicHUD = H

local hideConvar = GetConVar("gry_draconic_hide_crosshair") or CreateClientConVar("gry_draconic_hide_crosshair", "1", true, false,
	"1: Draconic's own crosshair is not drawn while GryMod's crosshair is up (two crosshairs one over the other). 0: both are drawn", 0, 1)

-- Whether Draconic's crosshair is to be left out now: the option is on, GryMod's HUD is up and its crosshair is not switched off by the player.
function H.Hidden()
	if not hideConvar:GetBool() or not GryMod.FlashHUD or not GryMod.FlashHUD.Enabled() then
		return false
	end

	return not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("crosshair")
end

-- the wrappers of this file and of its earlier loads (a file loaded again must not take a wrapper for Draconic's own function)
H.wrappers = H.wrappers or setmetatable({}, {__mode = "k"})

local function wrapper(...)
	if H.Hidden() then
		return nil
	end

	return H.original(...)
end

H.wrappers[wrapper] = true

-- Puts the wrapper on Draconic's hook. True when it is there (also when it already was), false when Draconic's hook does not exist.
function H.Install()
	local hooks = hook.GetTable().HUDPaint
	local current = hooks and hooks["drc_crosshair"]

	if not isfunction(current) then
		return false
	end

	if current == wrapper then
		return true
	end

	if not H.wrappers[current] then
		H.original = current
	end

	hook.Add("HUDPaint", "drc_crosshair", wrapper)

	return true
end

-- Draconic adds its hook when its own files load, which may be after this one: asked again when the game is up.
H.Install()
hook.Add("InitPostEntity", "GryMod compat draconic hud", H.Install)

GryMod.AddOptionTab("compat", "Draconic", function(root)
	GryMod.OptionBox(root, "Hide Draconic's own crosshair", "gry_draconic_hide_crosshair", "Draconic weapons draw a crosshair of their own in the middle of the screen, over the crosshair of GryMod's HUD. Left out while GryMod's crosshair is up. Draconic's scope, its inspection screen and its own settings stay as they are.")
	GryMod.OptionNote(root, "The fire mode icon of the weapon slot follows the fire mode of the Draconic weapon (single, automatic, burst), and its fists and melee weapons show no gun.")
	GryMod.OptionNote(root, "A projectile, a grenade or a blow of a Draconic weapon ends the camouflage, and an EMP of the base (the Draconic EMP gun) puts the suit down. Draconic's own attachment menu is opened with its keys (use, reload, then zoom): the quick menu cannot open it.")
end, 35)
