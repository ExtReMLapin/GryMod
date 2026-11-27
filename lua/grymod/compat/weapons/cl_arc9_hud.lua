-- ARC9 (client): ARC9 draws a HUD of its own (the weapon's name, the ammunition, the fire mode, the bars of the sights...) in the bottom left corner, under the minimap of
-- GryMod's HUD. This patch lets the player hide it while GryMod's HUD is up (gry_arc9_hide_hud, on the ARC9 tab of the Compatibility page, on by default), without touching
-- ARC9's own settings (arc9_hud_arc9, arc9_hud_force_disable...). Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing when ARC9 is not installed.
--
-- How: ARC9 asks its own function ARC9.ShouldDrawHUD() whether to draw the HUD (its HUDPaint hook ARC9_DrawHud and its HUDShouldDraw hook ARC9_HideHUD, cl_hud.lua) and, when
-- the answer is nothing, draws only the key hints of the weapon (the list on the left: aim, fire mode, attachments, safety) and the hints at the middle of the screen, which are
-- what ARC9 does itself with its option "HUD off". The function is the one place the HUD is decided, so it is asked through a wrapper: with the option on and GryMod's HUD up
-- the answer is nothing, and in ARC9's customization menu (its hints, its menu) and in every other case ARC9's own answer. No hook is added, nothing runs by itself: the
-- wrapper only runs when ARC9 asks. The original function is kept once, so a file loaded again does not wrap the wrapper.

GryMod = GryMod or {}

local H = GryMod.ARC9HUD or {}
GryMod.ARC9HUD = H

local hideConvar = GetConVar("gry_arc9_hide_hud") or CreateClientConVar("gry_arc9_hide_hud", "1", true, false,
	"1: ARC9's own HUD (weapon name, ammunition, fire mode) is hidden while GryMod's HUD is up; its key hints and its customization menu stay. 0: both HUDs are drawn", 0, 1)

-- Whether ARC9's HUD is to be hidden now: the option is on, GryMod's HUD is up, and the weapon in hand is not in ARC9's customization menu.
function H.Hidden()
	if not hideConvar:GetBool() or not GryMod.FlashHUD or not GryMod.FlashHUD.Enabled() then
		return false
	end

	local ply = LocalPlayer()
	local weapon = IsValid(ply) and ply:GetActiveWeapon()

	if IsValid(weapon) and weapon.ARC9 == true and isfunction(weapon.GetCustomize) and weapon:GetCustomize() then
		return false
	end

	return true
end

-- the wrappers of this file and of its earlier loads (a file loaded again must not take a wrapper for ARC9's own function)
H.wrappers = H.wrappers or setmetatable({}, {__mode = "k"})

local function wrapper(...)
	if H.Hidden() then
		return nil
	end

	return H.original(...)
end

H.wrappers[wrapper] = true

-- Puts the wrapper on ARC9's function. True when it is there (also when it already was), false when ARC9 is not installed or has no such function.
function H.Install()
	if not istable(ARC9) then
		return false
	end

	if not isfunction(ARC9.ShouldDrawHUD) then
		-- ARC9 is there but its function is not (ARC9 changed): the patch is off, the owner is told once the game is up (ARC9 defines its functions when its own files load)
		if GryMod.API and GryMod.API.WarnPatchMissing then
			GryMod.API.WarnPatchMissing("ARC9", "ARC9.ShouldDrawHUD", function() return istable(ARC9) and not isfunction(ARC9.ShouldDrawHUD) end)
		end

		return false
	end

	local current = ARC9.ShouldDrawHUD

	if current == wrapper then
		return true
	end

	-- the wrapper of an earlier load is the current function: the original is the one it kept
	if not H.wrappers[current] then
		H.original = current
	end

	ARC9.ShouldDrawHUD = wrapper

	return true
end

-- ARC9 defines its function when its own files load, which may be after this one: asked again when the game is up.
H.Install()
hook.Add("InitPostEntity", "GryMod compat arc9 hud", H.Install)
