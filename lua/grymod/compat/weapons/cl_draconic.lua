-- Draconic Base (client): the fire mode icon of the weapon slot. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses the public GryMod.FlashHUD.
-- AddFireModeResolver, answers nil for a weapon that is not Draconic's and does nothing when the base is not installed.
--
-- The fire mode: Draconic keeps it in a networked integer, CurFireMode (1 semi-automatic, 2 automatic, 3 burst; weapons/draconic_base/shared.lua, InitialFireMode), and CLEARS Primary.Automatic
-- for a burst weapon, so GryMod's generic reading of Primary.Automatic shows a single shot for it. A melee weapon (the fists, drc_unarmed: IsMelee) is no gun.
--
-- The crosshair needs nothing: every Draconic weapon draws a crosshair of its own (the spread of the weapon, in the hook HUDPaint "drc_crosshair") and defines SWEP:DoDrawCrosshair, which
-- GryMod's crosshair reads as "this weapon draws its own" (Cross.WeaponDraws): GryMod's is not drawn for it, so the two are never one over the other (looked at in a game).

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

GryMod.AddOptionTab("compat", "Draconic", function(root)
	GryMod.OptionNote(root, "A Draconic weapon draws the crosshair of its own (the spread of the weapon): GryMod's crosshair is not drawn for it. Draconic's scope and its inspection screen stay as they are.")
	GryMod.OptionNote(root, "The fire mode icon of the weapon slot follows the fire mode of the Draconic weapon (single, automatic, burst), and its fists and melee weapons show no gun.")
	GryMod.OptionNote(root, "A projectile, a grenade or a blow of a Draconic weapon ends the camouflage, and an EMP of the base (the Draconic EMP gun) puts the suit down. The weapon icon of the quick menu opens Draconic's customization menu (the attachments and the camouflages), the one its own keys open with use + sprint + reload, then zoom; the gun is shown plain while it is up.")
end, 35)
