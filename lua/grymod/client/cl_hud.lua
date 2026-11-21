-- The GryMod interface lives in the cl_*_flash.lua files (the Crysis HUD, the quick menu, the binoculars, the
-- grenade warning), drawn from the original Scaleform movies (see cl_flash.lua). This file keeps the settings, the
-- sounds, the suit mode on the client and the glue.
-- All the settings are saved between sessions (second argument)
CreateClientConVar("gry_xadd", "0", true, false)
CreateClientConVar("gry_xdist", "0", true, false)
local HUDEnabled = CreateClientConVar("gry_hud", "1", true, false, "Draw the GryMod HUD (the quick menu and the suit abilities work without it)")
local SoundsEnabled = CreateClientConVar("gry_sounds", "1", true, false, "Play the GryMod suit sounds")
local meta = FindMetaTable("Player")

-- Every GryMod sound goes through here, so players can switch them off (gry_sounds 0) and the mix sets their volume
-- (cl_sound_mix.lua); scale (default 1) multiplies it (the armor hits that stack)
function GryMod.PlaySound(path, scale)
	if not SoundsEnabled:GetBool() then
		return false
	end

	GryMod.SoundMix.Emit(path, GryMod.SoundMix.Volume(path) * (scale or 1))

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
	GryMod.PlaySound("grymod/suit/suit_sound_137.wav")
end)

-- The voice ("maximum armor"...) comes half a second after the sound of the mode, as in the original game (the two
-- together made one muddy burst). A mode change before it is heard cancels it.
GryMod.ModeVoiceDelay = 0.5

local function playModeVoice(path)
	timer.Remove("GryModModeVoice")
	timer.Create("GryModModeVoice", GryMod.ModeVoiceDelay, 1, function()
		GryMod.PlaySound(Sound(path))
	end)
end

function meta:SetNanosuitMode(mode, networked)
	if (mode == LocalPlayer().NanosuitMode) then
		return
	end

	-- the voice of the last mode is not heard any more (dropping the suit's item is not a mode)
	if mode ~= GryMod.Modes.DROP then
		timer.Remove("GryModModeVoice")
	end

	if mode == GryMod.Modes.ARMOR then
		GryMod.PlaySound(Sound("grymod/suit/suit_armor_108.wav"))
		playModeVoice("grymod/suit/suit_maximum_armor.wav")
	end

	if mode == GryMod.Modes.SPEED then
		GryMod.PlaySound(Sound("grymod/suit/suit_speed_activate_07_good.wav"))
		playModeVoice("grymod/suit/suit_maximum_speed.wav")
	end

	if mode == GryMod.Modes.STRENGTH then
		GryMod.PlaySound(Sound("grymod/suit/suit_strength_101_r.wav"))
		playModeVoice("grymod/suit/suit_maximum_strength.wav")
	end

	if mode == GryMod.Modes.CLOAK then
		if IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel()) then
			-- the view model and the hands are made camouflaged by cl_cloak_fx.lua; the old material only with gry_cloak_fx 0
			if not GryMod.CloakFX.Enabled() then
				LocalPlayer():GetViewModel():SetMaterial("cloak/organic")

				-- some gamemodes do not give c_arms hands
				if IsValid(LocalPlayer():GetHands()) then
					LocalPlayer():GetHands():SetMaterial("cloak/organic")
				end
			end

			GryMod.PlaySound(Sound("grymod/suit/suit_cloak_chameleon_101_r.wav"))
			playModeVoice("grymod/suit/suit_modification_engaged.wav")
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

-- Switch: the right click also ends the camouflage when the weapon really fires with it.
local CloakAltFire = CreateClientConVar("gry_cloak_altfire", "1", true, false, "The camouflage also ends on a right click that really fires: the shotgun's double barrel, the SMG grenade, the AR2 energy ball, the frag grenade's lob")

-- Does the right click of this Half-Life 2 weapon fire a shot right now? Pure: the class, the magazine (Clip1) and the
-- ammo reserve of the primary and of the secondary ammo type of the weapon. The crossbow's right click is a zoom, and
-- the weapons of other addons are unknown: neither counts.
function GryMod.AltFireShoots(class, clip1, primaryReserve, secondaryReserve)
	if class == "weapon_shotgun" then
		return (clip1 or 0) >= 2 -- the double barrel fires both shells
	elseif class == "weapon_smg1" or class == "weapon_ar2" then
		return (secondaryReserve or 0) > 0 -- the grenade, the energy ball
	elseif class == "weapon_frag" then
		return (primaryReserve or 0) > 0 -- the lob, while there is a grenade
	end

	return false
end

-- Does a press of the attack key fire a shot? Pure: when the weapon may fire next (its next primary fire time), the time
-- now, the magazine (Clip1, -1 without one), the ammo type of the primary fire (-1 for none) and the reserve of that ammo,
-- all of them read BEFORE the weapon ran the press. A click while a weapon is being drawn (the Half-Life 2 selector's
-- confirmation click, then another one), while it cools down, with an empty magazine or with no grenade left fires nothing:
-- the camouflage must not end for it (measured: the press reaches the KeyPress hook all the same, and the magazine and the
-- next fire time do not move). Numbers the weapon does not give count as "may fire": the press keeps its old meaning.
function GryMod.AttackShoots(nextFire, now, clip1, ammoType, reserve)
	if (nextFire or 0) > now then
		return false
	end

	if clip1 == 0 then
		return false -- the weapon reloads, nothing is fired
	end

	if (clip1 or -1) < 0 and (ammoType or -1) >= 0 and (reserve or 0) <= 0 then
		return false -- no magazine and nothing in reserve (the frag grenade with no grenade)
	end

	return true
end

-- Has the weapon fired since these numbers were read? Pure: the next primary fire time and the magazine then, and now. A shot
-- moves the next fire time on or lowers the magazine (a weapon with no magazine reports -1 and only moves the time).
function GryMod.ShotSince(nextBefore, clipBefore, nextNow, clipNow)
	if (nextNow or 0) > (nextBefore or 0) + 0.001 then
		return true
	end

	return (clipBefore or -1) >= 0 and (clipNow or -1) < clipBefore
end

-- The numbers of the weapon in hand at the last command of the player that pressed no attack key. The KeyPress hook comes
-- AFTER the weapon ran the press, a few commands later (measured: at the KeyPress and at the start of the command before it the
-- next fire time had already moved on by the shot and the magazine had dropped), so what the weapon could do is read from here.
-- Taken only in the camouflage (the hook returns at once otherwise).
local pre = {}
local live = {}

local function readWeapon(ply, weapon, into)
	local primary, secondary = weapon:GetPrimaryAmmoType(), weapon:GetSecondaryAmmoType()

	into.weapon = weapon
	into.nextPrimary = weapon:GetNextPrimaryFire()
	into.nextSecondary = weapon:GetNextSecondaryFire()
	into.clip = weapon:Clip1()
	into.primaryType = primary
	into.primaryReserve = ply:GetAmmoCount(primary)
	into.secondaryReserve = ply:GetAmmoCount(secondary)

	return into
end

function GryMod.CloakSnapshot(ply)
	local weapon = ply:GetActiveWeapon()

	if IsValid(weapon) then
		readWeapon(ply, weapon, pre)
	else
		pre.weapon = nil
	end
end

hook.Add("StartCommand", "GryCloakSnapshot", function(ply, cmd)
	if ply.NanosuitMode == GryMod.Modes.CLOAK and not cmd:KeyDown(IN_ATTACK) and not cmd:KeyDown(IN_ATTACK2) then
		GryMod.CloakSnapshot(ply)
	end
end)

-- The numbers to judge a press by: the snapshot of this weapon, or, when there is none (the weapon came, or the camouflage
-- began, in the last command), its live numbers with the times unknown, so that the press counts as it always did.
local function numbers(ply, weapon)
	if pre.weapon == weapon then
		return pre
	end

	readWeapon(ply, weapon, live)
	live.nextPrimary, live.nextSecondary = 0, 0

	return live
end

-- The press of the attack key fires a shot now (GryMod.AttackShoots on the numbers of the weapon in hand).
local function attackNow(ply, weapon)
	local n = numbers(ply, weapon)

	return GryMod.AttackShoots(n.nextPrimary, CurTime(), n.clip, n.primaryType, n.primaryReserve)
end

-- The right click of the weapon the player holds fires a shot now (GryMod.AltFireShoots on its real numbers).
local function altFireNow(ply)
	local weapon = ply:GetActiveWeapon()

	if not IsValid(weapon) then
		return false
	end

	local n = numbers(ply, weapon)

	if n.nextSecondary > CurTime() then
		return false -- the weapon is being drawn
	end

	return GryMod.AltFireShoots(weapon:GetClass(), n.clip, n.primaryReserve, n.secondaryReserve)
end

local function endCloak(ply)
	ply:SetNanosuitMode(GryMod.Modes.ARMOR, true)
	net.Start("gry_empty_energy")
	net.SendToServer() -- too lazy to fight cheaters

	-- the bar is emptied by the server: that is no armor hit, but the glitch of firing out of the camouflage plays on purpose
	-- (cl_damage_fx.lua, gry_decloak_glitch)
	if GryMod.DamageFx then
		GryMod.DamageFx.Decloak(GryMod.DamageFx.State, RealTime())
	end
end

-- How long a press that came too early (the weapon is being drawn) is followed, in seconds.
local ATTACK_WATCH = 2

-- A press that came while the weapon could not fire yet, and is still held: the weapon fires as soon as it is ready, and that
-- shot ends the camouflage. One timer set for the moment the weapon is ready, not a check at every frame. readyAt and clip
-- are the weapon's next fire time and magazine when the press came.
local function watchHeldAttack(ply, weapon, readyAt, clip, since)
	local wait = math.Clamp(readyAt - CurTime(), 0, ATTACK_WATCH) + 0.03

	timer.Simple(wait, function()
		if ply.NanosuitMode ~= GryMod.Modes.CLOAK or not ply:KeyDown(IN_ATTACK) then
			return
		end

		if not IsValid(weapon) or ply:GetActiveWeapon() ~= weapon then
			return
		end

		if GryMod.ShotSince(readyAt, clip, weapon:GetNextPrimaryFire(), weapon:Clip1()) then
			endCloak(ply)
		elseif CurTime() < readyAt + 0.05 and CurTime() - since < ATTACK_WATCH then
			watchHeldAttack(ply, weapon, readyAt, clip, since) -- the timer came a little early
		end
	end)
end

-- Shooting ends the camouflage: a press of the attack key when the weapon fires with it, a right click when the weapon fires
-- with it (GryMod.AltFireShoots).
function GryMod.CloackAttack(ply, key)
	if ply.NanosuitMode ~= GryMod.Modes.CLOAK then
		return
	end

	if key == IN_ATTACK then
		local weapon = ply:GetActiveWeapon()

		if not IsValid(weapon) then
			return
		end

		if attackNow(ply, weapon) then
			endCloak(ply)
		else
			local n = numbers(ply, weapon)
			watchHeldAttack(ply, weapon, n.nextPrimary, n.clip, CurTime())
		end
	elseif key == IN_ATTACK2 and CloakAltFire:GetBool() and altFireNow(ply) then
		endCloak(ply)
	end
end

-- (The stealth bar of the compass panel used to count every NPC within 1280 units here, friends included. It now shows the
-- awareness of the hostile NPCs the server sends as radar contacts: cl_hud_radar_units.lua, Radar.StealthTarget.)
-- no key for the quick menu yet: a prompt asks for one (every time, while there is none)
net.Receive("gry_spawn", function()
	if GryMod.MenuKey then
		timer.Simple(2, GryMod.MenuKey.MaybePrompt)
	end

	-- the binoculars' own zoom key, when that option is on and no key is chosen (once per session, after the menu's prompt)
	if GryMod.SuitZoom then
		timer.Simple(2.5, GryMod.SuitZoom.MaybePrompt)
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
	local drawn = GryMod.FlashHUD and GryMod.FlashHUD.Apply(enabled)

	-- the vanilla HUD is only hidden when ours is really drawn (a missing movie must not leave no HUD at all)
	if enabled and drawn then
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
