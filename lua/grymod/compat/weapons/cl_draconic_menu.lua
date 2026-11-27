-- Draconic Base (client): the weapon icon of the quick menu opens Draconic's customization menu (the attachments and the camouflages of the weapon in hand, what the base calls the
-- inspection menu, normally reached with use + sprint + reload, then the zoom key), and the camouflage leaves the gun plain while that menu is up. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): the public GryMod.API.AddWeaponMenuProvider and AddPlainViewProvider only, nothing for a weapon that is not Draconic's and nothing when the base is
-- not installed.
--
-- Draconic opens the menu from the SERVER (DRC:ForceAttachmentMenu puts the weapon in inspection mode, the state the base's own rules and its server handlers expect, then tells the client
-- to open the panel): the opener only sends the request "gry_draconic_customize" (lua/grymod/compat/weapons/sv_draconic.lua, S.OpenCustomize), which checks everything again.

local API = GryMod.API

if not API or not API.AddWeaponMenuProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local M = GryMod.DraconicMenu or {}
GryMod.DraconicMenu = M

local TIMER = "GryMod compat draconic menu"
local STEP = 0.05
local STEPS = 40 -- two seconds

local function panelUp()
	local drc = _G.DRC

	return istable(drc) and istable(drc.AttachMenu) and IsValid(drc.AttachMenu.mpanel)
end

-- One look at the base while the menu is being opened. True when there is nothing more to wait for (the panel is up, or the weapon is no longer in hand), false to look again.
-- Draconic's own message "open the menu" comes from the server in the same tick as the inspection mode, BEFORE the base has drawn its inspection screen once (DRC.Inspection.ThemeColours_Attachments
-- is made by that screen), and DRC:ToggleAttachmentMenu then refuses to build the panel while it already marks the weapon as customizing: no menu, and the gun is plain. So the panel is asked
-- for again here, once the weapon is inspecting and the base is ready.
function M.Step(weapon)
	local drc = _G.DRC
	local ply = LocalPlayer()

	if not istable(drc) or not IsValid(weapon) or not IsValid(ply) or ply:GetActiveWeapon() ~= weapon then
		return true
	end

	if panelUp() then
		return true
	end

	local inspection = drc.Inspection

	if weapon:GetNW2Bool("Inspecting", false) ~= true or not istable(inspection) or not istable(inspection.ThemeColours_Attachments) then
		return false
	end

	pcall(drc.ToggleAttachmentMenu, drc, weapon, true)

	return true
end

-- The wait is over without a panel: the weapon is not left marked as customizing (it would stay plain with no menu).
function M.GiveUp(weapon)
	if IsValid(weapon) and weapon.Draconic == true and not panelUp() then
		weapon.Customizing = false
	end
end

local function open(weapon)
	net.Start("gry_draconic_customize")
	net.SendToServer()

	-- a short wait, only until the panel is up: no permanent hook
	timer.Create(TIMER, STEP, STEPS, function()
		if M.Step(weapon) then
			timer.Remove(TIMER)
		elseif timer.RepsLeft(TIMER) == 0 then
			M.GiveUp(weapon)
		end
	end)
end

API.AddWeaponMenuProvider("compat.draconic", function(weapon)
	local drc = _G.DRC

	-- the base is not there, or the server has switched the inspection off (it refuses the menu with it)
	if not istable(drc) or not istable(drc.SV) or drc.SV.drc_inspections == 0 then
		return nil
	end

	if weapon.Draconic ~= true or not isfunction(weapon.CanCustomize) then
		return nil
	end

	-- the base's own question, with its bypass for the inspection mode (the weapon is not inspecting yet when the quick menu opens): false for a weapon with a slot that offers no
	-- choice (fists, a melee weapon with no skin), and when the server forbids the modification of attachments
	local ok, can = pcall(weapon.CanCustomize, weapon, true)

	if not ok or can ~= true then
		return nil
	end

	-- the base answers "yes" for any melee weapon (it has no attachment slot to count): the fists would open an empty menu. A melee weapon is offered the menu when it has camouflages to choose.
	if weapon.IsMelee == true and weapon.WeaponSkinDefaultMat == nil then
		return nil
	end

	return open
end)

if API.AddPlainViewProvider then
	-- Customizing is set by the base while its menu is up (DRC:ToggleAttachmentMenu)
	API.AddPlainViewProvider("compat.draconic", function(weapon)
		return weapon.Draconic == true and weapon.Customizing == true
	end)
end
