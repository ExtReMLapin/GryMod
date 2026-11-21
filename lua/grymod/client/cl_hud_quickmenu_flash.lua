-- The quick menu (suit mode wheel) drawn from the original Scaleform movie (HUD_QuickMenu), see cl_flash.lua.
-- What the game does around the movie is ported from its code (research notes: research-qm/NOTES.md): the
-- pointer is the mouse movement added up into a vector (a flick past 25 selects, coming back under 12.5 returns
-- to the centre), the selection is an angle sector, the movie only shows it. The movie's own ActionScript
-- (showQuickMenu, setActive, setDefect, destroy, setAutosnapItem...) is ported by hand in the Menu methods.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Menu = {}
GryMod.FlashMenu = Menu

Menu.MOVIE = "hud_quickmenu"

local MODES = {"Speed", "Strength", "Cloak", "Armor", "Weapon"}
local MODE_CLIPS = {"Cloak", "Weapon", "Armor", "Strength", "Speed"}

-- ---------------------------------------------------------------------------------------------------------
-- The pointer and the sectors
-- ---------------------------------------------------------------------------------------------------------

-- The angle of a vector in degrees, as the game computes it: 0 to the right, 90 up, anticlockwise (the screen's y
-- grows downwards).
function Menu.ThetaFor(x, y)
	local length = math.sqrt(x * x + y * y)

	if length == 0 then
		return 0
	end

	local angle = math.deg(math.acos(math.Clamp(x / length, -1, 1)))

	if y >= 0 then
		angle = 360 - angle
	end

	return angle % 360
end

-- The sector limits the game reads (degrees): Speed 52-128, Armor ("Defense") 128-205, Weapon 205-260,
-- Cloak 260-342, Strength the rest.
function Menu.SectorFor(theta)
	if theta >= 342 or theta < 52 then
		return "Strength"
	elseif theta < 128 then
		return "Speed"
	elseif theta < 205 then
		return "Defense"
	elseif theta < 260 then
		return "Weapon"
	end

	return "Cloak"
end

local Pointer = {}
Pointer.__index = Pointer

Menu.SELECT_DISTANCE = 25
Menu.RELEASE_DISTANCE = 12.5

-- Where the game puts the cursor when the menu opens, so that the current mode is already selected.
local START = {Speed = {0, -30}, Strength = {30, 0}, Cloak = {20, 30}, Armor = {-30, 0}}

function Menu.NewPointer(mode)
	local pointer = setmetatable({x = 0, y = 0, active = false, pendX = 0, pendY = 0, pendTime = 0, shown = 90}, Pointer)
	local start = START[mode]

	if start then
		pointer:Move(start[1], start[2])
		pointer.shown = pointer:Theta()
	end

	return pointer
end

function Pointer:Move(dx, dy)
	self.x, self.y = self.x + dx, self.y + dy
	local length = math.sqrt(self.x * self.x + self.y * self.y)

	if self.active and length < Menu.RELEASE_DISTANCE then
		self.x, self.y, self.active = 0, 0, false
	elseif length > Menu.SELECT_DISTANCE then
		self.x, self.y = self.x / length * Menu.SELECT_DISTANCE, self.y / length * Menu.SELECT_DISTANCE
		self.active = true
	end
end

function Pointer:Theta()
	return Menu.ThetaFor(self.x, self.y)
end

-- The film pointer. The game runs its rule once per frame of a 2007 engine on the sum of the mouse counts of the frame; on a client
-- at 144 to 240 fps the same rule, run on every frame, turns the arrow back over a hundred times a second (the counts are integers
-- of a few units on a radius of 25: see 2026-11-21-quickmenu-pointer-research.md). Here the rule (Pointer:Move) runs on a fixed clock:
-- the counts of a frame are spread over the time since the previous call, so the result depends on the movement and not on how it was cut
-- into frames. The angle the arrow shows eases toward the vector's angle by the short way (exact for a target that changes at the steps).
Menu.POINTER_STEP = 1 / 30 -- the movie's own frame rate
Menu.POINTER_EASE = 0.015 -- seconds
Menu.POINTER_MAX_DT = 0.1 -- a stall counts for this much

local function easeBy(pointer, seconds)
	if pointer.active then
		local k = 1 - math.exp(-seconds / Menu.POINTER_EASE)
		pointer.shown = (pointer.shown + ((Menu.ThetaFor(pointer.x, pointer.y) - pointer.shown + 180) % 360 - 180) * k) % 360
	end
end

-- Mouse counts dx, dy made since the previous call, `now` in seconds (RealTime). Call it with 0, 0 on a frame the mouse did not move: the
-- arrow keeps easing.
function Pointer:Feed(dx, dy, now)
	local dt = self.clock and now - self.clock or 0
	self.clock = now

	if dt <= 0 then
		-- the same instant: the counts wait for the next step
		self.pendX, self.pendY = self.pendX + dx, self.pendY + dy

		return
	end

	dt = math.min(dt, Menu.POINTER_MAX_DT)
	local vx, vy = dx / dt, dy / dt
	local step = Menu.POINTER_STEP
	local left = dt

	while left > 1e-9 do
		local use = math.min(step - self.pendTime, left)
		self.pendX, self.pendY = self.pendX + vx * use, self.pendY + vy * use
		self.pendTime = self.pendTime + use
		left = left - use
		easeBy(self, use)

		if self.pendTime >= step - 1e-9 then
			local wasActive = self.active
			self:Move(self.pendX, self.pendY)
			self.pendX, self.pendY, self.pendTime = 0, 0, 0

			-- a pointer that has just left the centre points at once (nothing to ease from)
			if self.active and not wasActive then
				self.shown = self:Theta()
			end
		end
	end
end

-- The angle the arrow shows (the film pointer).
function Pointer:DisplayTheta()
	return self.shown
end

-- One mouse sample into the pointer: the film pointer (fixed clock) or the previous rule (every sample).
function Menu.PointerInput(pointer, dx, dy, now, film)
	if film then
		pointer:Feed(dx, dy, now)
	else
		pointer:Move(dx, dy)
	end
end

-- The angle the arrow shows: eased for the film pointer, the vector's own for the previous rule.
function Menu.PointerAngle(pointer, film)
	if film then
		return pointer:DisplayTheta()
	end

	return pointer:Theta()
end

-- "Center", or the name of the sector (Speed, Strength, Cloak, Defense, Weapon).
function Pointer:Selection()
	if not self.active then
		return "Center"
	end

	return Menu.SectorFor(self:Theta())
end

-- GryMod's suit modes against the movie's names: the armor is "Defense" in the selection and "Armor" for the
-- icon; dropping the weapon takes the place of the weapon accessories.
local NAME_MODE = {
	Defense = GryMod.Modes.ARMOR,
	Armor = GryMod.Modes.ARMOR,
	Speed = GryMod.Modes.SPEED,
	Cloak = GryMod.Modes.CLOAK,
	Strength = GryMod.Modes.STRENGTH,
	Weapon = GryMod.Modes.DROP
}

local MODE_NAME = {
	[GryMod.Modes.ARMOR] = "Armor",
	[GryMod.Modes.SPEED] = "Speed",
	[GryMod.Modes.CLOAK] = "Cloak",
	[GryMod.Modes.STRENGTH] = "Strength",
	[GryMod.Modes.DROP] = "Weapon"
}

function Menu.ModeFromName(name)
	return NAME_MODE[name]
end

function Menu.NameFromMode(mode)
	return MODE_NAME[mode]
end

-- ---------------------------------------------------------------------------------------------------------
-- The movie
-- ---------------------------------------------------------------------------------------------------------

local Instance = {}
Instance.__index = Instance

-- The frame of the movie's QuickMenu where its functions exist (the hover sent before is not understood).
local READY_FRAME = 8
local END_FRAME = 18

-- Switch: the pointer runs the game's rule on a fixed clock and the arrow is eased, so that it does not flutter at a high frame rate;
-- off: the rule runs on every mouse sample and the arrow shows the vector's angle as it comes (the first port).
local PointerFilm = CreateClientConVar("gry_menu_pointer_film", "1", true, false, "The quick menu pointer runs the game's rule on a fixed 1/30 s clock and the arrow is eased: it does not flutter at a high frame rate (0: the rule runs on every mouse sample)")

-- Switch: the icon that was chosen stays lit while the menu fades out (the original); off: it goes plain at the release.
local KeepHighlight = CreateClientConVar("gry_menu_keep_highlight", "1", true, false, "The quick menu icon that was chosen stays lit during the fade-out, as in the original (0: it goes back to plain at the release)")

function Menu.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local qm = root:Find("Root.QuickMenu")

	if not qm then
		return nil
	end

	-- the holders of the colour sets and the legacy "critical" gauge never show
	for _, name in ipairs({"Line", "Over", "Text", "Back", "OverBack"}) do
		local holder = root:Child(name)

		if holder then
			holder:SetVisible(false)
		end
	end

	local critical = root:Find("Root.CriticalArea")

	if critical then
		critical:SetVisible(false)
	end

	return setmetatable({
		root = root,
		qm = qm,
		shown = false,
		closing = false,
		malfunction = 0,
		active = {},
		defect = {},
		selected = "Center",
		ring = RING_CENTER,
		angle = 90
	}, Instance)
end

function Instance:IsShown()
	return self.shown
end

-- showQuickMenu(): the root is visible and the QuickMenu plays from "open".
function Instance:Open()
	if self.shown and not self.closing then
		return
	end

	self.shown = true
	self.closing = false
	self.selected = "Center"
	self.ring = RING_CENTER
	self.qm:GotoAndPlay("open")
end

-- hideQuickMenu(): plays "close"; the menu is hidden when it has finished.
function Instance:Close()
	if not self.shown or self.closing then
		return
	end

	self.closing = true
	self.qm:GotoAndPlay("close")
end

-- setActive(bitset) and setDefect(bitset): tables keyed by Speed, Strength, Cloak, Armor, Weapon.
function Instance:SetStates(active, defect)
	self.active = active or {}
	self.defect = defect or {}
end

-- destroy(status): 1 is the malfunction (everything red, nothing can be chosen), 0 the normal state.
function Instance:Destroy(status)
	self.malfunction = status or 0
end

-- The selection (setAutosnapItem): "Center" or a sector name.
function Instance:Select(name)
	self.selected = name or "Center"
end

-- The pointer angle in degrees (the game sends the ring's rotation, 90 minus the angle).
function Instance:SetAngle(theta)
	self.angle = theta
	self:_applyIndicator()
end

local function iconName(selection)
	return selection == "Defense" and "Armor" or selection
end

-- Switch: the ring follows the film's rules (an inactive mode does not touch it); off: the ring follows the choice alone.
local RingFilm = CreateClientConVar("gry_menu_ring_film", "1", true, false, "The quick menu ring keeps its colour when the pointer goes from an active mode to an inactive one (the original); 0: it turns orange")

local RING_CENTER = {green = false, orange = true, indicator = false}
local RING_MODE = {green = true, orange = false, indicator = true}
local RING_MODES = {Weapon = true, Speed = true, Strength = true, Armor = true, Cloak = true}

-- The ring (the Indicator and the two circles) after the pointer goes to `selection`, from the state it was in: the film's
-- setMovieClipFrame sets it for the centre (orange, no indicator) and for a mode that is active, not defective and with the suit
-- working (green, indicator); for any other mode no branch matches, so the ring is left as it was. active and defect are keyed
-- by mode name, malfunction is the HUD status (1: down). The states are shared tables: do not change them.
function Menu.RingAfter(previous, selection, active, defect, malfunction)
	if selection == "Center" then
		return RING_CENTER
	end

	local name = iconName(selection)

	if RING_MODES[name] and active and active[name] and not (defect and defect[name]) and malfunction ~= 1 then
		return RING_MODE
	end

	return previous or RING_CENTER
end

-- The mode the player would get now: the selected one when it is active, not defective and the suit works.
function Instance:Choice()
	local name = iconName(self.selected)

	if name == "Center" or self.malfunction == 1 or not self.active[name] or self.defect[name] then
		return nil
	end

	return self.selected
end

function Instance:_applyIndicator()
	local circle = self.qm:Child("Circle")
	local indicator = circle and circle:Child("Indicator")

	if indicator then
		indicator:SetRotation(90 - self.angle)
	end
end

-- The states the movie's own scripts keep: each mode on its frame (1 normal, 2 hover, 3 inactive, 4 defective)
-- and the ring.
function Instance:_applyStates()
	local qm = self.qm
	-- the original keeps the chosen icon lit through the close: it only changes it when the selection moves
	local ready = (KeepHighlight:GetBool() or not self.closing) and qm:CurrentFrame() >= READY_FRAME
	local choice = ready and self:Choice()
	local choiceName = choice and iconName(choice)

	for _, name in ipairs(MODE_CLIPS) do
		local clip = qm:Child(name)

		if clip then
			local frame

			if self.malfunction == 1 or self.defect[name] then
				frame = 4
			elseif not self.active[name] then
				frame = 3
			elseif choiceName == name then
				frame = 2
			else
				frame = 1
			end

			if clip:CurrentFrame() ~= frame then
				clip:GotoAndStop(frame)
			end
		end
	end

	local circle = qm:Child("Circle")
	-- the ring keeps its last state while the menu fades out
	local ring

	if RingFilm:GetBool() then
		self.ring = Menu.RingAfter(self.ring, self.selected, self.active, self.defect, self.malfunction)
		ring = self.ring
	else
		choice = self:Choice()
		ring = (choice ~= nil and choice ~= false) and RING_MODE or RING_CENTER
	end

	if self.malfunction == 1 then
		if circle and circle:CurrentLabel() ~= "malfunction" then
			circle:GotoAndStop("malfunction")
		end
	elseif circle then
		if circle:CurrentLabel() == "malfunction" then
			circle:GotoAndStop(1)
		end

		local green, orange, indicator = circle:Child("Circle_green"), circle:Child("Circle_orange"), circle:Child("Indicator")

		if green then green:SetVisible(ring.green) end
		if orange then orange:SetVisible(ring.orange) end
		if indicator then indicator:SetVisible(ring.indicator) end
	end

	self:_applyIndicator()
end

function Instance:Update(dt)
	if not self.shown then
		return
	end

	self.root:Advance(dt)

	if self.closing and self.qm:CurrentFrame() >= END_FRAME then
		self.shown = false
		self.closing = false

		return
	end

	self:_applyStates()
end

function Instance:Draw(x, y, scale)
	if self.shown then
		Flash.Draw(self.root, x, y, scale)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game: the key, the mouse, the sounds and the mode change
-- ---------------------------------------------------------------------------------------------------------

-- The game's own sounds (HUD sound ids): 4 modification_menu_appear when the key goes down, 5 modification_menu_disappear when
-- it goes up (whatever is chosen), 3 temperature_beep when the mode chosen is the active one. The game has no sound for the
-- pointer moving: preset_navigation_beep (id 2, the menu of the weapon's presets) stands in for it, and suit_usage_error
-- for the refusal while the suit is down.
Menu.Sounds = {
	open = Sound("grymod/menu/modification_menu_appear.wav"),
	close = Sound("grymod/menu/modification_menu_dissapear.wav"),
	hover = Sound("grymod/menu/preset_navigation_beep_02.wav"),
	same = Sound("grymod/menu/temperature_beep.wav"),
	error = Sound("grymod/suit/suit_usage_error.wav")
}

local snd_open, snd_close, snd_hover, snd_same, snd_error =
	Menu.Sounds.open, Menu.Sounds.close, Menu.Sounds.hover, Menu.Sounds.same, Menu.Sounds.error

local menu, pointer, locked
local opened = false
local lastTime, lastSelection

local function play(path)
	if GryMod.PlaySound then
		GryMod.PlaySound(path)
	end
end

-- Whether the quick menu can be drawn (its movie is there); it works with the HUD off too.
function Menu.Enabled()
	return Flash.Load(Menu.MOVIE) ~= nil and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("quickmenu"))
end

function Menu.IsOpen()
	return opened
end

-- The pointer of the open menu (nil when it is closed); for the tests.
function Menu.GetPointer()
	return opened and pointer or nil
end

local function feedStates(ply)
	-- while the suit is down the menu is in its malfunction state: nothing can be chosen
	menu:Destroy(GryMod.FlashBoot and GryMod.FlashBoot.IsLost() and 1 or 0)
	menu:SetStates({
		Speed = true,
		Strength = true,
		Cloak = true,
		Armor = true,
		Weapon = IsValid(ply:GetActiveWeapon())
	}, {})
end

-- The key goes down: the menu opens on the current mode, the view stays where it is.
function Menu.Begin()
	local ply = LocalPlayer()

	-- already open (a bind and gry_menu_key together send the press twice)
	if opened then
		return false
	end

	if not IsValid(ply) or not ply:Alive() then
		play(snd_error)

		return false
	end

	if not menu then
		menu = Menu.New(Flash.Load(Menu.MOVIE))
	end

	if not menu then
		return false
	end

	pointer = Menu.NewPointer(Menu.NameFromMode(ply.NanosuitMode))
	locked = ply:EyeAngles()
	feedStates(ply)
	menu:Open()
	menu:Select(pointer:Selection())
	menu:SetAngle(pointer:Theta())
	lastSelection = pointer:Selection()
	lastTime = nil
	opened = true
	play(snd_open)

	return true
end

-- The key goes up: the selected mode is applied (the server stays the master of it), or nothing at the centre.
function Menu.Finish()
	if not opened then
		return
	end

	opened = false
	local choice = menu:Choice()
	local refused = menu.malfunction == 1 and menu.selected ~= "Center" -- the suit is down: the original beeps
	menu:Close()

	if refused then
		play(snd_error)

		return
	end

	local ply = LocalPlayer()
	local mode = choice and Menu.ModeFromName(choice)

	if not (mode and IsValid(ply) and ply:Alive()) then
		play(snd_close)

		return
	end

	-- the key's release always plays the menu's disappear sound; the active mode chosen again beeps (the original)
	play(snd_close)

	if mode == ply.NanosuitMode then
		play(snd_same)
	else
		ply:SetNanosuitMode(mode, true)
	end
end

-- The menu closes without changing anything when the player dies or a game menu opens, and when the key release may never
-- reach us: a panel took the cursor or the keyboard (the chat, the Q or C menu), the console is up, or the key it was
-- opened with is not down any more. `extra` (optional): {cursor, typing, console, keyUp}, true for each case that holds.
function Menu.ShouldCancel(ply, gameUiVisible, extra)
	if not ply or not ply.Alive then
		return true
	end

	if not ply:Alive() or gameUiVisible then
		return true
	end

	return extra ~= nil and (extra.cursor == true or extra.typing == true or extra.console == true or extra.keyUp == true)
end

function Menu.Cancel()
	if not opened then
		return
	end

	opened = false

	if GryMod.MenuKey then
		GryMod.MenuKey.Forget()
	end

	if menu then
		menu:Close()
	end

	play(snd_close)
end

-- one table, filled each frame the menu is open
local reasons = {}

hook.Add("StartChat", "GRYQUICKMENU", function()
	Menu.Cancel()
end)

hook.Add("CreateMove", "GRYQUICKMENU", function(cmd)
	if not opened then
		return
	end

	local ply = LocalPlayer()
	local key = GryMod.MenuKey and GryMod.MenuKey.Pressed()

	reasons.cursor = vgui.CursorVisible()
	reasons.typing = IsValid(ply) and ply:IsTyping()
	reasons.console = gui.IsConsoleVisible()
	reasons.keyUp = key ~= nil and not input.IsButtonDown(key)

	if Menu.ShouldCancel(ply, gui.IsGameUIVisible(), reasons) then
		Menu.Cancel()

		return
	end

	Menu.PointerInput(pointer, cmd:GetMouseX(), cmd:GetMouseY(), RealTime(), PointerFilm:GetBool())

	-- the mouse moves the pointer, not the view, and shooting is off while the menu is open
	if locked then
		cmd:SetViewAngles(locked)
	end

	cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(bit.bor(IN_ATTACK, IN_ATTACK2))))
	cmd:SetMouseX(0)
	cmd:SetMouseY(0)
end)

hook.Add("HUDPaint", "GRYQUICKMENUDRAW", function()
	if not menu or not menu:IsShown() then
		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	if opened then
		local film = PointerFilm:GetBool()

		-- the clock of the film pointer runs on every frame, whether the mouse moved or not (the arrow keeps easing)
		if film then
			pointer:Feed(0, 0, now)
		end

		local selection = pointer:Selection()
		menu:Select(selection)
		menu:SetAngle(Menu.PointerAngle(pointer, film))

		if selection ~= lastSelection then
			lastSelection = selection

			if selection ~= "Center" then
				play(snd_hover)
			end
		end

		if IsValid(LocalPlayer()) then
			feedStates(LocalPlayer())
		end
	end

	menu:Update(dt)

	-- the stage is 1024 x 768, scaled to the screen height and centred: the ring sits on the screen's centre
	local scale = ScrH() / 768
	menu:Draw((ScrW() - 1024 * scale) / 2, 0, scale)
end)

-- Drops the menu (a new theme, a respawn): its render targets go back to the pool.
function Menu.Reset()
	if menu then
		Flash.ReleaseClip(menu.root)
	end

	menu, pointer, locked, opened = nil, nil, nil, false
end
