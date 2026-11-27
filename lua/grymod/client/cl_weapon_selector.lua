-- The weapon selector setting (gry_weapon_selector): what the mouse wheel does with the weapons, three positions.
--
--   0  the game's own selector, as it always was (the default: nothing in this file runs for it but one read of the setting at a wheel notch)
--   1  "wheel only": a notch of the wheel changes the weapon at once (down = the next weapon, up = the previous one), with no click to confirm.
--      The HUD's weapon list (cl_hud_weaponlist_flash.lua) shows by itself when the weapon changes, as it does for any change.
--   2  "wheel then click": the wheel walks the HUD's weapon list (bottom right, the selection is on its plate) and the left click confirms. It is the
--      game's wheel-and-click selector, moved into the HUD of GryMod. When that list cannot be shown (the HUD or the list is off, the movie is
--      missing) the wheel falls back to position 1: nobody scrolls a selection that is not on the screen.
--
-- It is one PlayerBindPress hook: nothing runs between two binds (no Think). The wheel is left to the game when it is used for something else: the
-- attack key is down (the physgun moves the prop with the wheel), a vehicle, no weapon in hand, a dead player, and while the zoom of the binoculars or
-- the suit is up (it steps its stages with the wheel). The weapon keys (slot1...) and the last weapon key are not touched: they keep the game's own
-- selector (and a selection of position 2 ends when one is pressed, the click then belongs to the game's selector).
--
-- The camouflage (cl_hud.lua, the selector guard): in positions 1 and 2 the game's selector is never open, so the notches are not given to the guard
-- (it would take the next real shot for the confirmation of a selector that is not there), and the click that confirms in position 2 is taken (the
-- weapon in hand does not fire) and marked, so that if the press still reaches KeyPress as IN_ATTACK it is not judged a shot either (ConfirmsPress,
-- asked by GryMod.CloackAttack). It works with the guard option on or off: it does not depend on it.

GryMod = GryMod or {}

local W = {}
GryMod.WeaponSelector = W

local Sel = GryMod.SelectorState

local ModeConVar = CreateClientConVar("gry_weapon_selector", "0", true, false, "What the mouse wheel does with the weapons: 0 the game's own selector, 1 a notch changes the weapon at once, 2 the wheel walks the HUD's weapon list and the left click confirms", 0, 2)

-- In position 1: how long a notch counts as not yet seen by the game. The weapon in hand changes a moment after the request (the change goes through the
-- server), and the next notch must go on from the weapon asked for, not start again from the one still in hand.
W.REACH = 0.5

-- the selection under way: the weapon the wheel is on, from when to when it counts, and whether the click confirms it (position 2 with a list on the screen)
local state = {cursor = nil, at = 0, expires = 0, confirmable = false, confirmedAt = nil}

local function endSelection()
	state.cursor, state.at, state.expires, state.confirmable = nil, 0, 0, false
end

-- Forgets everything (a hot reload, the tests).
function W.Reset()
	endSelection()
	state.confirmedAt = nil
end

-- The position, from 0 to 2.
function W.Mode()
	return math.Clamp(ModeConVar:GetInt(), 0, 2)
end

-- How long a selection of position 2 lasts from its last notch: as long as the list is on the screen (its hold, its fade, and the 0.2 s the list keeps
-- after the fade, GryMod.FlashWeaponList.Phase).
local function listWindow()
	local List = GryMod.FlashWeaponList

	return List.HOLD + List.FADE_FRAMES / 30 + 0.2
end

-- Is the wheel ours right now? The position is not 0 and nothing else is using the wheel (see the top of the file). Asked by this file and by the
-- camouflage guard, which must not follow a notch that the game's selector never saw.
function W.TakesWheel(ply)
	if W.Mode() == 0 then
		return false
	end

	if not IsValid(ply) or not ply:Alive() or ply:InVehicle() or not IsValid(ply:GetActiveWeapon()) then
		return false
	end

	if ply:KeyDown(IN_ATTACK) then
		return false -- the physgun, and any weapon that reads the wheel while the attack key is down
	end

	return not (GryMod.WheelTaken and GryMod.WheelTaken())
end

-- The weapons of the player as the selector walks them (slot, then place in the slot; the ones with no ammo are skipped, the weapon in hand never is).
local function entriesOf(ply)
	local list = {}

	for _, weapon in ipairs(ply:GetWeapons()) do
		list[#list + 1] = {id = weapon, slot = weapon:GetSlot(), pos = weapon:GetSlotPos(), selectable = weapon:HasAmmo()}
	end

	return list
end

local function has(list, weapon)
	for _, entry in ipairs(list) do
		if entry.id == weapon then
			return true
		end
	end

	return false
end

-- The weapon a notch starts from: the one the selection is on while it counts (and the player still has it), else the weapon in hand.
local function baseOf(list, active, now)
	local cursor = state.cursor

	if cursor ~= nil and now >= state.at and now < state.expires and has(list, cursor) then
		return cursor
	end

	return active
end

local function notch(ply, step, mode)
	local active = ply:GetActiveWeapon()
	local list = entriesOf(ply)
	local now = CurTime()
	local base = baseOf(list, active, now)
	local target = Sel.Target(list, base, step)

	if target == nil and base ~= active then
		base = active
		target = Sel.Target(list, active, step)
	end

	if target == nil then
		return nil -- the weapon in hand is not among the weapons: nothing to walk, the game keeps the wheel
	end

	local List = GryMod.FlashWeaponList

	if mode == 2 and List and List.Show and List.Show(ply, target) then
		state.cursor, state.at, state.expires, state.confirmable = target, now, now + listWindow(), true

		return true
	end

	-- position 1 (or position 2 with no list): the weapon changes now. The change is skipped only when nothing would change at all.
	state.cursor, state.at, state.expires, state.confirmable = target, now, now + W.REACH, false

	if not (target == active and base == active) then
		input.SelectWeapon(target)
	end

	return true
end

-- The left click, in position 2 with a selection on the list: the weapon the wheel is on is selected and the click is taken (the weapon in hand does not fire).
local function confirm(ply)
	if W.Mode() ~= 2 or not state.confirmable then
		return nil
	end

	local now = CurTime()
	local cursor = state.cursor

	if cursor == nil or now < state.at or now >= state.expires or not IsValid(ply) or not has(entriesOf(ply), cursor) then
		endSelection()

		return nil
	end

	endSelection()
	state.confirmedAt = now

	if cursor ~= ply:GetActiveWeapon() then
		input.SelectWeapon(cursor)
	end

	return true
end

-- PlayerBindPress. Returns true when the bind is taken (the game does not run it), nothing otherwise.
function W.BindPress(ply, bind, pressed, code)
	if not pressed then
		return nil
	end

	local mode = W.Mode()

	if mode == 0 then
		return nil
	end

	local kind = Sel.BindKind(bind)

	if kind == "next" or kind == "prev" then
		if not W.TakesWheel(ply) then
			return nil
		end

		return notch(ply, kind == "next" and 1 or -1, mode)
	elseif kind == "slot" or kind == "close" then
		endSelection() -- the game's selector is the one that is up now: it takes the click
	elseif kind == "attack" then
		return confirm(ply)
	end

	return nil
end

hook.Add("PlayerBindPress", "GryWeaponSelector", function(ply, bind, pressed, code)
	return W.BindPress(ply, bind, pressed, code)
end)

-- The press of the attack key that reaches KeyPress (IN_ATTACK) at this time is the click that confirmed a selection a moment ago: it is no shot.
-- Used up by this press. Asked by GryMod.CloackAttack (cl_hud.lua).
function W.ConfirmsPress(now)
	local at = state.confirmedAt

	if at ~= nil and now >= at and now - at < Sel.CONFIRM then
		state.confirmedAt = nil

		return true
	end

	return false
end
