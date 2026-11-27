-- TFA (client): the weapon icon of the suit's quick menu opens TFA's own menu for the weapon in hand (the attachments, the ammunition: TFA calls it the inspection).
-- Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses GryMod's public GryMod.API.AddWeaponMenuProvider and TFA's own way of opening the
-- menu, the impulse TFA.INSPECTION_IMPULSE that TFA's key sends (tfa_hooks.lua), so the weapon handles it exactly as it does for the key. It answers nothing for a weapon
-- that is not TFA's, while the server forbids the menu (sv_tfa_cmenu 0) or when TFA does not tell its impulse, and does nothing when TFA is not installed.

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local function open()
	RunConsoleCommand("impulse", tostring(TFA.INSPECTION_IMPULSE))
end

API.AddWeaponMenuProvider("compat.tfa", function(weapon)
	if weapon.IsTFAWeapon ~= true or not isfunction(weapon.ToggleInspect) then
		return nil
	end

	if not istable(TFA) or not isnumber(TFA.INSPECTION_IMPULSE) then
		return nil
	end

	-- a weapon with no attachment slot at all (a knife) has nothing to choose in the menu: none offered (a weapon that does not declare the table keeps it)
	if istable(weapon.Attachments) and next(weapon.Attachments) == nil then
		return nil
	end

	local allowed = GetConVar("sv_tfa_cmenu")

	if allowed and not allowed:GetBool() then
		return nil
	end

	return open
end)
