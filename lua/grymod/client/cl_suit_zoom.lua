-- The suit zoom of the binoculars as a key of its own (option gry_zoom_own), so that they do not hang on the Half-Life 2 suit zoom
-- (IN_ZOOM, the +zoom bind). One module owns "the player is zooming": the binoculars, the crosshair and the view hooks ask
-- GryMod.SuitZoom.IsActive(), the key and the +gry_zoom / -gry_zoom console commands open it, and SuitZoom.Exit(reason) is the only way
-- to close it, whatever the reason (the key let go, a death, a menu, a vehicle...). With the option off (the default) this file does
-- nothing: the Half-Life 2 key drives the binoculars as before.
--
-- The design, the hooks used and what was verified are in docs/superpowers/plans/2026-11-21-zoom-key-hooks.md.
--
-- The situations that end a zoom are facts about the world, read into one table (SuitZoom.Read) and turned into "must it end, and why" by
-- a pure function (SuitZoom.Reason): that is what the tests drive. Some also have an event (the chat opening, a menu, a map change);
-- the rest is polled once per frame, and only while a zoom is open or a key is held, so a player who does not zoom pays nothing.
--
-- A reason is "hard" when the zoom must be gone at once (death, vehicle, menus, the suit down, another view, a map change: the
-- binoculars are put away without their closing animation and the field of view is back in the same frame) or "soft" (the key
-- let go, a weapon change, the water: the binoculars close as usual, in 0.2 s).

GryMod = GryMod or {}

local Zoom = {}
GryMod.SuitZoom = Zoom

local OwnConVar = CreateClientConVar("gry_zoom_own", "0", true, false, "The binoculars' zoom has a key of its own (gry_zoom_key, or `bind <key> +gry_zoom`) and the mouse wheel steps its stages 2x, 4x, 8x; the Half-Life 2 zoom key then does nothing. Off: the Half-Life 2 zoom key drives the binoculars")
local ToggleConVar = CreateClientConVar("gry_zoom_toggle", "0", true, false, "The own zoom key opens the zoom with one press and closes it with the next (off: hold the key)")

-- The key of the zoom (a button code, 0 = none). It must not be the quick menu's, nor the wheel's.
local Key = GryMod.KeyBinder.New{
	convar = "gry_zoom_key",
	description = "Key of the binoculars' own zoom (a button code, 0 = none; `bind <key> +gry_zoom` works too)",
	command = "+gry_zoom",
	title = "GryMod binoculars zoom",
	text = "The binoculars have their own zoom key, and none is\nchosen yet. Click the box and press the key you want\n(or bind one to +gry_zoom in the console).",
	y = 190,
	active = function() return OwnConVar:GetBool() end,
	refuse = function(code)
		return code == MOUSE_WHEEL_UP or code == MOUSE_WHEEL_DOWN or (GryMod.MenuKey ~= nil and GryMod.MenuKey.Chosen() == code)
	end
}

Zoom.Key = Key

-- The prompt for the key comes once per session, while the option is on and no key is chosen: it never blocks anything.
Zoom.asked = false

function Zoom.MaybePrompt()
	if Zoom.asked or not Zoom.Owns() or Key.IsBound() then
		return
	end

	Zoom.asked = true
	Key.ShowPrompt()
end

-- ---------------------------------------------------------------------------------------------------------
-- State: one table, nothing allocated per frame.
-- ---------------------------------------------------------------------------------------------------------

local S = {
	-- the two sources of "the key is down": the chosen key, a +gry_zoom bind
	held = {key = false, bind = false},
	active = false,
	-- an Exit happened while the key was down: nothing opens until it is let go and pressed again
	blocked = false,
	-- the weapon in hand when the zoom opened
	weapon = nil,
	-- the frame of the last view that the binoculars' CalcView gave (Zoom.Stamp)
	frame = 0,
	reason = nil,
	-- the frames in a row in which the key was found up while it was held
	upFrames = 0
}

Zoom.State = S

-- the key found up this many frames in a row, while "held", is a release that never came
Zoom.RELEASE_FRAMES = 2
-- a view not given by our CalcView for more than this many frames is another addon's
Zoom.VIEW_FRAMES = 2

-- The reasons that put the binoculars away at once. The others (release, toggle, weapon, weaponkey, water) close them as usual.
Zoom.HARD = {
	init = true, death = true, disabled = true, quickmenu = true, pause = true, console = true, ui = true, chat = true, focus = true,
	malfunction = true, vehicle = true, thirdperson = true, viewentity = true, observer = true, frozen = true, viewtaken = true,
	shutdown = true, spawnmenu = true, contextmenu = true
}

function Zoom.Owns()
	return OwnConVar:GetBool()
end

function Zoom.Toggle()
	return ToggleConVar:GetBool()
end

-- The one question the others ask: a table read.
function Zoom.IsActive()
	return S.active
end

-- Forgets a key that was held and a block that waited for its release (a map change, the option going off).
function Zoom.Forget()
	S.held.key, S.held.bind, S.blocked, S.upFrames = false, false, false, 0
end

-- Everything back to the start, silently (no event, nothing put away).
function Zoom.Reset()
	Zoom.Forget()
	S.active, S.weapon, S.reason = false, nil, nil
end

-- ---------------------------------------------------------------------------------------------------------
-- The situation
-- ---------------------------------------------------------------------------------------------------------

-- Whether a zoom may go on (active: one is open), the reason it must end or nil, from the facts of a situation, the cheapest first:
-- valid, alive, enabled, quickmenu, pause, console, cursor, focusPanel, typing, focus, malfunction, vehicle, thirdperson, viewother,
-- observer, frozen, water, and for an open zoom weapon (against entered) and viewAge. Pure.
function Zoom.Reason(sit, active)
	if not sit.valid then return "init" end
	if not sit.alive then return "death" end
	if not sit.enabled then return "disabled" end
	if sit.quickmenu then return "quickmenu" end
	if sit.pause then return "pause" end
	if sit.console then return "console" end
	if sit.cursor or sit.focusPanel then return "ui" end
	if sit.typing then return "chat" end
	if not sit.focus then return "focus" end
	if sit.malfunction then return "malfunction" end
	if sit.vehicle then return "vehicle" end
	if sit.thirdperson then return "thirdperson" end
	if sit.viewother then return "viewentity" end
	if sit.observer ~= 0 then return "observer" end
	if sit.frozen then return "frozen" end
	if sit.water >= 3 then return "water" end

	if active then
		if sit.weapon ~= sit.entered then return "weapon" end
		if sit.viewAge > Zoom.VIEW_FRAMES then return "viewtaken" end
	end

	return nil
end

-- The button to ask the input system about while a key is held: the chosen key, or the one a +gry_zoom bind is on.
local function heldButton()
	if S.held.key then
		local chosen = Key.Chosen()

		if chosen > 0 then
			return chosen
		end
	end

	if S.held.bind then
		local name = input.LookupBinding("+gry_zoom")

		return name and input.GetKeyCode(name) or nil
	end

	return nil
end

-- Reads the world into a situation (a table that is filled again each time).
function Zoom.Read(sit)
	local ply = LocalPlayer()

	sit.valid = IsValid(ply)

	if not sit.valid then
		return sit
	end

	local Bino, menu, boot = GryMod.FlashBinoculars, GryMod.FlashMenu, GryMod.FlashBoot

	-- (a player killed is at 0 health, and has lost the weapon, one frame before Alive() says so: measured)
	sit.alive = ply:Alive() and ply:Health() > 0
	sit.enabled = Bino ~= nil and Bino.Enabled() and not (Bino.IsMissing and Bino.IsMissing())
	sit.quickmenu = menu ~= nil and menu.IsOpen() or false
	sit.pause = gui.IsGameUIVisible()
	sit.console = gui.IsConsoleVisible()
	sit.cursor = vgui.CursorVisible()
	sit.focusPanel = IsValid(vgui.GetKeyboardFocus())
	sit.typing = ply:IsTyping()
	sit.focus = system.HasFocus()
	-- the suit down: the server's flag, or the HUD in its lost state (an empty energy bar with the HUD's empty rule)
	sit.malfunction = ply:GetNWBool("GryMalfunction", false) or (boot ~= nil and boot.IsLost() or false)
	sit.vehicle = ply:InVehicle()
	sit.thirdperson = ply:ShouldDrawLocalPlayer()
	sit.viewother = ply:GetViewEntity() ~= ply
	sit.observer = ply:GetObserverMode()
	sit.frozen = ply:IsFrozen()
	sit.water = ply:WaterLevel()
	sit.weapon = ply:GetActiveWeapon()
	sit.entered = S.weapon
	sit.viewAge = FrameNumber() - S.frame

	sit.keyUp = false

	if S.held.key or S.held.bind then
		local button = heldButton()

		sit.keyUp = button ~= nil and button > 0 and not input.IsButtonDown(button)
	end

	return sit
end

local situation = {}

-- ---------------------------------------------------------------------------------------------------------
-- Open and close
-- ---------------------------------------------------------------------------------------------------------

-- Opens the zoom when nothing in the world prevents it. Returns whether it did.
local function open()
	local sit = Zoom.Read(situation)

	if Zoom.Reason(sit, false) ~= nil then
		return false
	end

	S.active, S.weapon, S.frame, S.reason = true, sit.weapon, FrameNumber(), nil
	hook.Run("GryMod_SuitZoom", true)

	return true
end

-- Whether a zoom could open now (the same conditions, nothing changes).
function Zoom.CanEnter()
	return Zoom.Reason(Zoom.Read(situation), false) == nil
end

-- THE way to close the zoom, safe to call from anywhere, as often as wanted. A key that is still down stays blocked until it is
-- let go (else a death, a vehicle or a menu would reopen the zoom at the next frame).
function Zoom.Exit(reason)
	if S.held.key or S.held.bind then
		S.blocked = true
	end

	if not S.active then
		return
	end

	S.active, S.reason, S.weapon = false, reason, nil

	if Zoom.HARD[reason] then
		local Bino = GryMod.FlashBinoculars

		if Bino and Bino.Drop then
			Bino.Drop()
		end
	end

	hook.Run("GryMod_SuitZoom", false, reason)
end

-- The key (source "key": the chosen key; "bind": +gry_zoom) goes down or up.
function Zoom.Press(source, down)
	if down and not Zoom.Owns() then
		return
	end

	local was = S.held.key or S.held.bind
	S.held[source] = down

	if down then
		if was then
			return
		end

		S.upFrames = 0

		if S.blocked then
			return
		end

		if S.active then
			if Zoom.Toggle() then
				Zoom.Exit("toggle")
			end
		else
			open()
		end

		return
	end

	-- the release is always taken, whatever is on screen
	if S.held.key or S.held.bind then
		return
	end

	S.blocked, S.upFrames = false, 0

	if S.active and not Zoom.Toggle() then
		Zoom.Exit("release")
	end
end

-- The binoculars' CalcView has given the view this frame (see the reason "viewtaken").
function Zoom.Stamp()
	S.frame = FrameNumber()
end

-- Once per frame: the situations that cannot be waited for as events, and a key that was let go without telling us. Does nothing (and
-- reads nothing) while no zoom is open and no key is held.
function Zoom.Guard()
	if not Zoom.Owns() then
		if S.active or S.held.key or S.held.bind or S.blocked then
			Zoom.Exit("disabled")
			Zoom.Forget()
		end

		return
	end

	local held = S.held.key or S.held.bind

	if not S.active and not held then
		return
	end

	local sit = Zoom.Read(situation)

	if S.active then
		local reason = Zoom.Reason(sit, true)

		if reason then
			Zoom.Exit(reason)
		end
	end

	if not held then
		return
	end

	-- a key found up for a few frames in a row while it is held: its release was lost (the chat or a panel had the keyboard)
	if not sit.keyUp then
		S.upFrames = 0

		return
	end

	S.upFrames = S.upFrames + 1

	if S.upFrames >= Zoom.RELEASE_FRAMES then
		Zoom.Forget()

		if S.active and not Zoom.Toggle() then
			Zoom.Exit("release")
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------------------------------------

-- (a press can be run again while the engine predicts the same command: only the first time counts)
hook.Add("PlayerButtonDown", "GRYSUITZOOM", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	local chosen = Key.Chosen()

	if chosen > 0 and button == chosen then
		Zoom.Press("key", true)
	end
end)

-- The release is taken whatever is on screen; it is not delivered at all when a panel has the keyboard (the poll in Guard covers it).
hook.Add("PlayerButtonUp", "GRYSUITZOOM", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	local chosen = Key.Chosen()

	if chosen > 0 and button == chosen then
		Zoom.Press("key", false)
	end
end)

-- `bind <key> +gry_zoom` (the engine runs -gry_zoom at the release).
function Zoom.Command(ply, command)
	Zoom.Press("bind", command == "+gry_zoom")
end

concommand.Add("+gry_zoom", Zoom.Command)
concommand.Add("-gry_zoom", Zoom.Command)

hook.Add("Think", "GRYSUITZOOM", function()
	Zoom.Guard()
end)

-- ---------------------------------------------------------------------------------------------------------
-- The Half-Life 2 zoom stays out of it, and the wheel is the zoom's while it is up (only with the own zoom key on)
-- ---------------------------------------------------------------------------------------------------------

-- Whether a bind runs the Half-Life 2 suit zoom: +zoom itself, or an alias of the player's that runs it.
local function isZoomBind(bind)
	if bind == "+zoom" then
		return true
	end

	local target = input.TranslateAlias(bind)

	if not target then
		return false
	end

	for command in string.gmatch(target, "[^;]+") do
		if string.Trim(command) == "+zoom" then
			return true
		end
	end

	return false
end

-- The keys that change the weapon (slot1 to slot6, last weapon, `use <weapon>`); the wheel's invprev / invnext are the zoom's.
local function isWeaponBind(bind)
	return string.find(bind, "^slot%d+$") ~= nil or bind == "lastinv" or string.sub(bind, 1, 4) == "use "
end

-- PlayerBindPress. +zoom is taken, so the Half-Life 2 zoom never starts (-zoom goes on: it is harmless and stops a zoom that was up when
-- the option was switched on). While the zoom is up the wheel is ours, known by its button (112 / 113: still the wheel when the player
-- has bound it to something else) and by the binds invprev / invnext, and every notch is taken, even at the end of the stages; the weapon
-- keys are not taken: they change the weapon and end the zoom. With no zoom up nothing is taken: the wheel changes the weapon.
function Zoom.BindPress(ply, bind, pressed, code)
	if not Zoom.Owns() then
		return nil
	end

	if isZoomBind(bind) then
		return true
	end

	if not S.active then
		return nil
	end

	-- (a death or a menu of this very frame: Think has not seen it yet, the wheel must go back to the game)
	Zoom.Guard()

	if not S.active then
		return nil
	end

	local direction

	if code == MOUSE_WHEEL_UP then
		direction = "invprev"
	elseif code == MOUSE_WHEEL_DOWN then
		direction = "invnext"
	elseif bind == "invprev" or bind == "invnext" then
		direction = bind
	end

	if direction then
		local Bino = GryMod.FlashBinoculars

		if pressed and Bino then
			Bino.StepWheel(direction)
		end

		return true
	end

	if isWeaponBind(bind) then
		Zoom.Exit("weaponkey")
	end

	return nil
end

-- StartCommand, the player's own command: IN_ZOOM is removed (the keys PlayerBindPress cannot see: F1 to F12 and aliases), and while the
-- zoom is up the wheel's delta too (a weapon that reads it, the physgun, would scroll under the zoom).
function Zoom.StartCommand(ply, cmd)
	if not Zoom.Owns() or ply ~= LocalPlayer() then
		return
	end

	cmd:RemoveKey(IN_ZOOM)

	if S.active then
		cmd:SetMouseWheel(0)
	end
end

hook.Add("PlayerBindPress", "GRYSUITZOOM", function(ply, bind, pressed, code)
	return Zoom.BindPress(ply, bind, pressed, code)
end)

hook.Add("StartCommand", "GRYSUITZOOM", function(ply, cmd)
	Zoom.StartCommand(ply, cmd)
end)

-- The events that end the zoom at once. None returns anything: the chat, the menus and the rest must go on as they would.
hook.Add("StartChat", "GRYSUITZOOM", function() Zoom.Exit("chat") end)
hook.Add("OnSpawnMenuOpen", "GRYSUITZOOM", function() Zoom.Exit("spawnmenu") end)
hook.Add("OnContextMenuOpen", "GRYSUITZOOM", function() Zoom.Exit("contextmenu") end)
-- (the main menu: not called when the player holds Shift, so Guard polls gui.IsGameUIVisible too)
hook.Add("OnPauseMenuShow", "GRYSUITZOOM", function() Zoom.Exit("pause") end)

hook.Add("ShutDown", "GRYSUITZOOM", function()
	Zoom.Exit("shutdown")
	Zoom.Forget()
end)

hook.Add("InitPostEntity", "GRYSUITZOOM", function()
	Zoom.Exit("init")
	Zoom.Forget()
end)

-- The HUD goes down (status 1: the suit failure, or the empty-energy rule): the binoculars are a part of it.
hook.Add("GryMod_HUDStatus", "GRYSUITZOOM", function(status)
	if status == 1 then
		Zoom.Exit("malfunction")
	end
end)

-- The option goes off while a zoom is up (or a key is held): all of it is put away.
cvars.AddChangeCallback("gry_zoom_own", function(_, _, new)
	if (tonumber(new) or 0) == 0 and (S.active or S.held.key or S.held.bind or S.blocked) then
		Zoom.Exit("disabled")
		Zoom.Forget()
	end
end, "GRYSUITZOOM")
