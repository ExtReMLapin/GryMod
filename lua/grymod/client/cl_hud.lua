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

-- The sound of the HUD event "mode" (cl_api_hud_events.lua): the activation sound of the mode entered, then its voice. The picture
-- (the tint of cl_mode_fx.lua) is played by the same event.
GryMod.ModeSounds = {
	[GryMod.Modes.ARMOR] = {"grymod/suit/suit_armor_108.wav", "grymod/suit/suit_maximum_armor.wav"},
	[GryMod.Modes.SPEED] = {"grymod/suit/suit_speed_activate_07_good.wav", "grymod/suit/suit_maximum_speed.wav"},
	[GryMod.Modes.STRENGTH] = {"grymod/suit/suit_strength_101_r.wav", "grymod/suit/suit_maximum_strength.wav"},
	[GryMod.Modes.CLOAK] = {"grymod/suit/suit_cloak_chameleon_101_r.wav", "grymod/suit/suit_modification_engaged.wav"}
}

function GryMod.PlayModeSound(mode)
	local files = GryMod.ModeSounds[mode]

	if not files then
		return false
	end

	GryMod.PlaySound(Sound(files[1]))
	playModeVoice(files[2])

	return true
end

-- Tells the HUD that the suit changed to this mode (the event plays the tint and the sound together). The tint is asked for only
-- when the change is a real one (GryMod.ModeFX.TintDue); `quiet` keeps the sound out (the camouflage's sound waits for a view model).
local function modeEvent(mode, quiet)
	local API, FX = GryMod.API, GryMod.ModeFX
	local name = FX and FX.NameOf(mode)

	if not (API and API.HUDEvent and name) then
		return false
	end

	local data = {mode = name, tint = FX.TintNow(LocalPlayer().NanosuitMode, mode)}

	if quiet then
		data.sound = false
	end

	return API.HUDEvent("mode", data)
end

function meta:SetNanosuitMode(mode, networked)
	-- the same mode again does nothing, unless the mode on the client is only the default guess (AssumeDefaultMode below): then the first one set is real
	if mode == LocalPlayer().NanosuitMode and not LocalPlayer().NanosuitModeAssumed then
		return
	end

	-- the voice of the last mode is not heard any more (dropping the suit's item is not a mode)
	if mode ~= GryMod.Modes.DROP then
		timer.Remove("GryModModeVoice")
	end

	-- the tint and the sound of the mode: one HUD event (the camouflage's own picture is cl_cloak_fx.lua's)
	local viewModelThere = IsValid(LocalPlayer()) and IsValid(LocalPlayer():GetViewModel())

	modeEvent(mode, mode == GryMod.Modes.CLOAK and not viewModelThere)

	if mode == GryMod.Modes.CLOAK then
		if viewModelThere then
			-- the view model and the hands are made camouflaged by cl_cloak_fx.lua; the old material only with gry_cloak_fx 0
			if not GryMod.CloakFX.Enabled() then
				LocalPlayer():GetViewModel():SetMaterial("cloak/organic")

				-- some gamemodes do not give c_arms hands
				if IsValid(LocalPlayer():GetHands()) then
					LocalPlayer():GetHands():SetMaterial("cloak/organic")
				end
			end
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
		LocalPlayer().NanosuitModeAssumed = nil
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

-- A player who joins a game in progress may miss the message of the spawn: the engine does not deliver net messages reliably before the client's
-- InitPostEntity. So the client says when it is ready (SendReady: at InitPostEntity, and when this file is loaded again in a running game, where
-- there is no InitPostEntity) and the server answers with the mode it really keeps (sv_system.lua, GryMod.AnswerReady). Until something is
-- received the mode is armor, the one every suit starts in (the spawn puts it there). The default is only a guess: NanosuitModeAssumed makes the first
-- real mode go through the whole change (the early return of SetNanosuitMode above is for a mode that is really set), as it did when the field was empty.
function GryMod.AssumeDefaultMode(ply)
	if not IsValid(ply) or ply.NanosuitMode ~= nil then
		return false
	end

	ply.NanosuitMode = GryMod.Modes.ARMOR
	ply.NanosuitModeAssumed = true

	return true
end

function GryMod.SendReady()
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return false
	end

	GryMod.AssumeDefaultMode(ply)

	-- a server that does not know the message (it was not reloaded with this file) makes net.Start raise an error: nothing to lose here
	local ok = pcall(function()
		net.Start("gry_client_ready")
		net.SendToServer()
	end)

	return ok
end

hook.Add("InitPostEntity", "GryModClientReady", GryMod.SendReady)
GryMod.SendReady() -- loaded again in a running game (does nothing before the level is loaded: there is no local player yet)

-- The quick menu key goes down or up (+crysishud, -crysishud, or the key chosen with gry_menu_key): the menu is
-- drawn from the original movie, see cl_hud_quickmenu_flash.lua.
function GryMod.CryOpenClose(ply, command, args)
	if not (GryMod.FlashMenu and GryMod.FlashMenu.Enabled()) then
		return
	end

	if command == "+crysishud" then
		-- (the key bound to the command, to poll for its release: the hooks that tell it are not called in a single player game)
		if GryMod.MenuKey and GryMod.MenuKey.TrackBinding then
			GryMod.MenuKey.TrackBinding()
		end

		GryMod.FlashMenu.Begin()
	else
		GryMod.FlashMenu.Finish()
	end
end

concommand.Add("+crysishud", GryMod.CryOpenClose)
concommand.Add("-crysishud", GryMod.CryOpenClose)

-- Switch: the right click also ends the camouflage when the weapon really fires with it.
local CloakAltFire = CreateClientConVar("gry_cloak_altfire", "1", true, false, "The camouflage also ends on a right click that really fires: the shotgun's double barrel, the SMG grenade, the AR2 energy ball, the frag grenade's lob")

-- Does the right click of this weapon fire a shot right now? Pure: the class, the magazine (Clip1) and the ammo reserve of the
-- primary and of the secondary ammo type of the weapon. What the secondary IS comes from the weapon registry (GryMod.API, the stock
-- weapons are registered there as data): the shotgun's right click needs a shell in the magazine (both barrels with two, a single shot
-- with the last one: the engine's own rule, which the first version of this table got wrong), a grenade, an energy ball
-- or another shot needs its secondary ammo, the frag grenade's lob needs a grenade left. A zoom (the crossbow), a swing and the
-- weapons the registry does not know never count.
function GryMod.AltFireShoots(class, clip1, primaryReserve, secondaryReserve)
	local read = GryMod.API and GryMod.API.ResolveWeapon
	local def = isstring(class) and read and read(class)

	if not def or def.altShoots ~= true then
		return false
	end

	local alt = def.alt

	if alt == "doublebarrel" then
		return (clip1 or 0) >= 1 -- both barrels with two shells or more; with the last one the engine fires a single shot instead
	elseif alt == "throwlow" then
		return (primaryReserve or 0) > 0 -- the lob, while there is a grenade
	elseif alt == "grenade" or alt == "energy" or alt == "shoot" then
		if alt == "shoot" and not def.altAmmo then
			return true -- a shot that costs no ammo of its own
		end

		return (secondaryReserve or 0) > 0 -- the grenade, the energy ball, a shot with its own ammo
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

-- The weapon selector of Half-Life 2 (the wheel, the weapon keys). Measured on a test client with real wheel and click events: it
-- eats the click that confirms a selection (no KeyPress, the weapon changes), but it closes BY ITSELF 1.2 s after the last notch
-- (between 1.20 and 1.25 s on 48 clicks), and a click after that fires the weapon in hand for real (magazine down, next fire time
-- moved on): the player who scrolled, looked at the fading selector and clicked a moment too late lost the camouflage by a shot
-- he never meant. The state below follows the selector from the binds: a pure table, the times are given by the caller.
GryMod.SelectorState = {
	TIMEOUT = 1.2, -- the engine's own timeout, from the last notch
	GRACE = 0.5, -- a click this long after the close is still taken for the confirmation the player meant
	CONFIRM = 0.25, -- the press of a confirming click reaches KeyPress up to this long after the bind (measured: the same millisecond)
}

local Sel = GryMod.SelectorState

function Sel.New()
	return {notchAt = nil, steps = 0, known = true, confirmedAt = nil}
end

function Sel.Reset(s)
	s.notchAt, s.steps, s.known, s.confirmedAt = nil, 0, true, nil
end

-- "open" (the selector is up: the engine takes the click), "late" (it closed on its own a moment ago), or "none".
function Sel.Phase(s, now)
	if not s.notchAt or now < s.notchAt then
		return "none"
	end

	local age = now - s.notchAt

	if age < Sel.TIMEOUT then
		return "open"
	elseif age < Sel.TIMEOUT + Sel.GRACE then
		return "late"
	end

	return "none"
end

-- The kind of a bind: "next" and "prev" (the wheel), "slot" (a weapon key), "close" (the last weapon: a direct switch), "attack"
-- (the left click press), nothing for the others. A release or the right click are not the selector's.
function Sel.BindKind(bind)
	if bind == "invnext" then
		return "next"
	elseif bind == "invprev" then
		return "prev"
	elseif bind == "lastinv" then
		return "close"
	elseif bind == "+attack" then
		return "attack"
	elseif type(bind) == "string" and string.find(bind, "^slot%d+$") then
		return "slot"
	end

	return nil
end

-- A notch (kind "next", "prev" or "slot") at this time. A notch while the selector is up goes on from its selection, a notch
-- after it closed starts a new selection from the weapon in hand. A weapon key makes the target unknown.
function Sel.Notch(s, now, kind)
	if Sel.Phase(s, now) ~= "open" then
		s.steps, s.known = 0, true
	end

	s.notchAt = now

	if kind == "next" then
		s.steps = s.steps + 1
	elseif kind == "prev" then
		s.steps = s.steps - 1
	else
		s.known = false
	end
end

-- The attack key pressed at this time: "confirm" (the engine takes it), "late" (the selector closed a moment ago) or "shot" (a
-- plain click), then the steps of the selection (nil when unknown). The selector is closed after it.
function Sel.Attack(s, now)
	local phase, steps, known = Sel.Phase(s, now), s.steps, s.known

	Sel.Reset(s)

	if phase == "open" then
		s.confirmedAt = now -- the press may still come to KeyPress as IN_ATTACK (Sel.ConfirmsPress)

		return "confirm", known and steps or nil
	elseif phase == "late" then
		return "late", known and steps or nil
	end

	return "shot", nil
end

-- The press of the attack key that reaches KeyPress (IN_ATTACK) at this time is the selector's confirming click: the bind came a
-- moment ago and was a confirmation, or the selector is up and the bind has not come yet. Measured with a real mouse (the owner's
-- game): the click 0.277 s after the last notch reached KeyPress as IN_ATTACK in the same millisecond as the bind, the weapon
-- fired nothing (magazine and next fire time unchanged) and changed 18 ms later. (Posted window messages are eaten by the engine
-- and never reach KeyPress: they are not the real path.) The confirmation is used up by this press.
function Sel.ConfirmsPress(s, now)
	local confirmed = s.confirmedAt ~= nil and now >= s.confirmedAt and now - s.confirmedAt < Sel.CONFIRM

	if confirmed or Sel.Phase(s, now) == "open" then
		Sel.Reset(s)

		return true
	end

	return false
end

-- The weapon the selection ends on. entries: {id, slot, pos, selectable} of the weapons of the player; the engine walks them by
-- slot then position, wrapping round, and skips the ones it cannot select (no ammo): the weapon in hand always counts. nil when
-- the steps are unknown or the weapon in hand is not in the list.
function Sel.Target(entries, activeId, steps)
	if steps == nil then
		return nil
	end

	local list = {}

	for _, entry in ipairs(entries) do
		if entry.selectable or entry.id == activeId then
			list[#list + 1] = entry
		end
	end

	table.sort(list, function(a, b)
		if a.slot ~= b.slot then
			return a.slot < b.slot
		end

		return a.pos < b.pos
	end)

	for index, entry in ipairs(list) do
		if entry.id == activeId then
			return list[(index - 1 + steps) % #list + 1].id
		end
	end

	return nil
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
	-- (the HUD event "decloak": cl_damage_fx.lua, gry_decloak_glitch)
	if GryMod.API and GryMod.API.HUDEvent then
		GryMod.API.HUDEvent("decloak")
	end
end

-- A shot the SERVER saw: bullets left the player's weapon (the hook EntityFireBullets, sv_system.lua: the shotgun in either mode, the other
-- addons' weapons, whatever their rules). It ends the camouflage like the press that caused it, unless the player turned the right click
-- off (gry_cloak_altfire) and it was one. The press is judged by the numbers of the weapon; this is the shot itself: nothing to guess.
-- The suit is already out of the camouflage when the press ended it first, so the second one finds nothing to do.
function GryMod.CloakShot(ply, alt)
	if ply.NanosuitMode ~= GryMod.Modes.CLOAK then
		return
	end

	if alt and not CloakAltFire:GetBool() then
		return
	end

	endCloak(ply)
end

net.Receive("gry_cloak_shot", function()
	local alt = net.ReadBool()
	local ply = LocalPlayer()

	if IsValid(ply) then
		GryMod.CloakShot(ply, alt)
	end
end)

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

-- Switch: in the camouflage, the click that comes a moment after the weapon selector closed on its own is taken for the click that
-- confirms the selection (it selects the weapon the wheel was on, and fires nothing) instead of a shot that ends the camouflage.
local SelectorGuard = CreateClientConVar("gry_cloak_selector_guard", "1", true, false, "In the camouflage, a click a moment after the weapon selector closed by itself (1.2 s after the last notch of the wheel) confirms the selection instead of firing the weapon in hand and ending the camouflage")

local selectorState = Sel.New()
GryMod.CloakSelectorState = selectorState

-- The wheel is the zoom's while the suit zoom or the binoculars' stages are up (cl_suit_zoom.lua, cl_hud_binoculars_flash.lua): no
-- notch of the selector then.
local function wheelTaken()
	local zoom = GryMod.SuitZoom

	if zoom and zoom.IsActive and zoom.IsActive() then
		return true
	end

	local bino = GryMod.FlashBinoculars

	return bino ~= nil and bino.IsUp ~= nil and bino.StagesEnabled ~= nil and bino.IsUp() and bino.StagesEnabled()
end

-- Selects the weapon the wheel was on when the selector closed (steps notches from the weapon in hand); nothing when unknown.
local function selectOnTheWheel(ply, steps)
	local active = ply:GetActiveWeapon()

	if steps == nil or not IsValid(active) then
		return
	end

	local entries = {}

	for _, weapon in ipairs(ply:GetWeapons()) do
		entries[#entries + 1] = {id = weapon, slot = weapon:GetSlot(), pos = weapon:GetSlotPos(), selectable = weapon:HasAmmo()}
	end

	local target = Sel.Target(entries, active, steps)

	if IsValid(target) and target ~= active then
		input.SelectWeapon(target)
	end
end

-- PlayerBindPress, which comes before the engine and works in single player (the predicted hooks do not): follows the selector from
-- the binds. Returns true (the bind is taken, the weapon does not fire) for the late click in the camouflage.
function GryMod.CloakSelectorBind(ply, bind, pressed, code)
	if not pressed then
		return nil
	end

	local kind = Sel.BindKind(bind)

	if kind == nil then
		return nil
	end

	local now = CurTime()

	if kind == "attack" then
		local verdict, steps = Sel.Attack(selectorState, now)

		if verdict ~= "late" or not SelectorGuard:GetBool() or ply.NanosuitMode ~= GryMod.Modes.CLOAK then
			return nil
		end

		selectOnTheWheel(ply, steps)

		return true
	elseif kind == "close" then
		Sel.Reset(selectorState)
	elseif not wheelTaken() then
		Sel.Notch(selectorState, now, kind)
	end

	return nil
end

hook.Add("PlayerBindPress", "GryCloakSelector", GryMod.CloakSelectorBind)

-- The confirming click of the selector reached KeyPress: it is no shot. When it stays held the new weapon (it comes a few
-- milliseconds later) may fire as soon as it is drawn: the same watch as a press during the draw, on the weapon then in hand.
local function watchAfterConfirmation(ply)
	timer.Simple(0.1, function()
		if ply.NanosuitMode ~= GryMod.Modes.CLOAK or not ply:KeyDown(IN_ATTACK) then
			return
		end

		local weapon = ply:GetActiveWeapon()

		if IsValid(weapon) then
			watchHeldAttack(ply, weapon, weapon:GetNextPrimaryFire(), weapon:Clip1(), CurTime())
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

		if SelectorGuard:GetBool() and Sel.ConfirmsPress(selectorState, CurTime()) then
			watchAfterConfirmation(ply) -- the selector's click: no shot, unless it stays held and the new weapon fires
		elseif attackNow(ply, weapon) then
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
	-- the first second after a respawn gets no mode tint (cl_mode_fx.lua)
	if GryMod.ModeFX then
		GryMod.ModeFX.Spawned()
	end

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
