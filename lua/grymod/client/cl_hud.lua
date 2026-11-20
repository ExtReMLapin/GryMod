-- The GryMod interface lives in the cl_*_flash.lua files (the Crysis HUD, the quick menu, the binoculars, the
-- grenade warning), drawn from the original Scaleform movies (see cl_flash.lua). This file keeps the settings, the
-- sounds, the suit mode on the client and the glue.
-- All the settings are saved between sessions (second argument)
CreateClientConVar("gry_xadd", "0", true, false)
CreateClientConVar("gry_xdist", "0", true, false)
local HUDEnabled = CreateClientConVar("gry_hud", "1", true, false, "Draw the GryMod HUD (the quick menu and the suit abilities work without it)")
local SoundsEnabled = CreateClientConVar("gry_sounds", "1", true, false, "Play the GryMod suit sounds")
local meta = FindMetaTable("Player")

-- Every GryMod sound goes through here, so players can switch them off (gry_sounds 0)
function GryMod.PlaySound(path)
	if not SoundsEnabled:GetBool() then
		return false
	end

	surface.PlaySound(path)

	return true
end

function GryMod.SoundsEnabled()
	return SoundsEnabled:GetBool()
end

function meta:CanGryMod()
	return self:Alive()
end

-- You can change it , for others admins mods , but you'll have to change it in example : 
--[[  
function meta:CanGryMod() 
	return self:IsAdmin() or self:IsVip() 
end
]]

net.Receive("gry_jump", function()
	GryMod.PlaySound("suit/strengthjump.mp3")
end)

function meta:SetNanosuitMode(mode, networked)
	if (mode == LocalPlayer().NanosuitMode) then
		return
	end

	if mode == GryMod.Modes.ARMOR then
		GryMod.PlaySound(Sound("suit/suit_maximum_armor.mp3"))
		GryMod.PlaySound(Sound("suit/suit_armor_108.mp3"))
	end

	if mode == GryMod.Modes.SPEED then
		GryMod.PlaySound(Sound("suit/suit_maximum_speed.mp3"))
		GryMod.PlaySound(Sound("suit/suit_speed_activate_07_good.wa.mp3"))
	end

	if mode == GryMod.Modes.STRENGTH then
		GryMod.PlaySound(Sound("suit/suit_maximum_strength.mp3"))
		GryMod.PlaySound(Sound("suit/strengthmode.mp3"))
	end

	if mode == GryMod.Modes.CLOAK then
		if IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
			LocalPlayer():GetViewModel():SetMaterial("cloak/organic")

			-- some gamemodes do not give c_arms hands
			if IsValid(LocalPlayer():GetHands()) then
				LocalPlayer():GetHands():SetMaterial("cloak/organic")
			end

			GryMod.PlaySound(Sound("suit/suit_modification_engaged.mp3"))
			GryMod.PlaySound(Sound("suit/suit_cloak_chameleon_101_r.mp3"))
		end
	elseif IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
		LocalPlayer():GetViewModel():SetMaterial("")

		if IsValid(LocalPlayer():GetHands()) then
			LocalPlayer():GetHands():SetMaterial("")
		end
	end

	if mode == GryMod.Modes.DROP then
		net.Start("gry_drop")
		net.SendToServer()
	else
		if networked then
			net.Start("gry_nanosuit_mode_change")
			net.WriteUInt(mode, 3)
			net.SendToServer()
		end

		LocalPlayer().NanosuitMode = mode
	end
	-- it's not a real mode so don't change anything
end

-- The server decides the mode (at every respawn it goes back to Armor). This must not wait for the
-- player to be alive on the client: the respawn message can arrive first, and a client that kept its old
-- mode ignores the player picking that mode again, so the suit stayed in Armor with a Speed icon.
function GryMod.ApplyServerMode(mode)
	if not IsValid(LocalPlayer()) then
		return
	end

	LocalPlayer():SetNanosuitMode(mode, false)
end

net.Receive("gry_nanosuit_mode_change", function()
	GryMod.ApplyServerMode(net.ReadUInt(3))
end)

-- The quick menu key goes down or up (+crysishud, -crysishud, or the key chosen with gry_menu_key): the menu is
-- drawn from the original movie, see cl_hud_quickmenu_flash.lua.
function GryMod.CryOpenClose(ply, command, args)
	if not (GryMod.FlashMenu and GryMod.FlashMenu.Enabled()) then
		return
	end

	if command == "+crysishud" then
		GryMod.FlashMenu.Begin()
	else
		GryMod.FlashMenu.Finish()
	end
end

concommand.Add("+crysishud", GryMod.CryOpenClose)
concommand.Add("-crysishud", GryMod.CryOpenClose)

function GryMod.CloackAttack(ply, key)
	if key == IN_ATTACK and LocalPlayer().NanosuitMode == GryMod.Modes.CLOAK then
		LocalPlayer():SetNanosuitMode(GryMod.Modes.ARMOR, true)
		net.Start("gry_empty_energy")
		net.SendToServer() -- too lazy to fight cheaters
	end
end

-- How many NPCs are near: the stealth bar of the compass panel shows it.
function GryMod.CountNearbyNPCs()
	local count = 0

	for _, ent in ipairs(ents.FindInSphere(LocalPlayer():GetPos(), 1280)) do
		if ent:IsNPC() then
			count = count + 1
		end
	end

	return count
end

function GryMod.UpdateRadar()
	if not IsValid(LocalPlayer()) then
		return
	end

	GryMod.RadarCount = GryMod.CountNearbyNPCs() -- the compass panel shows it on its stealth bar
end

-- One named timer: loading the file again replaces it instead of stacking another one
function GryMod.StartRadar()
	timer.Create("GryModRadar", 0.1, 0, GryMod.UpdateRadar)
end

GryMod.StartRadar()
-- no key for the quick menu yet: a prompt asks for one (every time, while there is none)
net.Receive("gry_spawn", function()
	if GryMod.MenuKey then
		timer.Simple(2, GryMod.MenuKey.MaybePrompt)
	end
end)

local hidethings = {
	["CHudHealth"] = true,
	["CHudBattery"] = true,
	["CHudAmmo"] = true,
	["CHudSecondaryAmmo"] = true
}

local function HUDShouldDraw(name)
	if (hidethings[name]) then
		return false
	end
end

-- The HUD (health, energy, ammo, radar, compass) can be turned off with gry_hud 0 or from the options
-- menu; the quick menu and the suit abilities keep working. The choice is saved with the convar.
local function applyHUD(enabled)
	if GryMod.FlashHUD then
		GryMod.FlashHUD.Apply(enabled)
	end

	if enabled then
		hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
	else
		hook.Remove("HUDShouldDraw", "How to: HUD Example HUD hider")
	end
end

-- re-applies the settings (a theme change calls it)
function GryMod.ApplyHUD()
	applyHUD(HUDEnabled:GetBool())
end

function GryMod.SetHUDEnabled(enabled)
	HUDEnabled:SetBool(enabled)
	applyHUD(enabled)
end

-- the options menu (or the console) changes the convar: follow it
cvars.AddChangeCallback("gry_hud", function(convar_name, value_old, value_new)
	applyHUD(tonumber(value_new) ~= 0)
end, "GryModHUD")

hook.Add("KeyPress", "AttackDetection", GryMod.CloackAttack)
GryMod.SetHUDEnabled(HUDEnabled:GetBool())
