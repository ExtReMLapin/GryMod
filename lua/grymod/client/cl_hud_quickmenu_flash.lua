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
	local pointer = setmetatable({x = 0, y = 0, active = false}, Pointer)
	local start = START[mode]

	if start then
		pointer:Move(start[1], start[2])
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
	choice = self:Choice()

	if self.malfunction == 1 then
		if circle and circle:CurrentLabel() ~= "malfunction" then
			circle:GotoAndStop("malfunction")
		end
	elseif circle then
		if circle:CurrentLabel() == "malfunction" then
			circle:GotoAndStop(1)
		end

		local green, orange, indicator = circle:Child("Circle_green"), circle:Child("Circle_orange"), circle:Child("Indicator")

		if green then green:SetVisible(choice ~= nil and choice ~= false) end
		if orange then orange:SetVisible(not choice) end
		if indicator then indicator:SetVisible(choice ~= nil and choice ~= false) end
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

-- The menu closes without changing anything when the player dies or a game menu opens (the key release may never
-- reach us then).
function Menu.ShouldCancel(ply, gameUiVisible)
	if not ply or not ply.Alive then
		return true
	end

	return not ply:Alive() or gameUiVisible
end

function Menu.Cancel()
	if not opened then
		return
	end

	opened = false

	if menu then
		menu:Close()
	end

	play(snd_close)
end

hook.Add("CreateMove", "GRYQUICKMENU", function(cmd)
	if not opened then
		return
	end

	if Menu.ShouldCancel(LocalPlayer(), gui.IsGameUIVisible()) then
		Menu.Cancel()

		return
	end

	pointer:Move(cmd:GetMouseX(), cmd:GetMouseY())

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
		local selection = pointer:Selection()
		menu:Select(selection)
		menu:SetAngle(pointer:Theta())

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
