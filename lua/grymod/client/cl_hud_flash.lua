-- The Crysis HUD drawn from the original Scaleform movie (HUD_AmmoHealthEnergySuit), see cl_flash.lua.
--
-- Everything the movie shows is driven by hand-ported parts of its ActionScript: setHealth, setEnergy,
-- setMode, setAmmo (with updateTextColor), setFireMode and destroy. The movie stays what the original
-- designers made; this file only says what the original code said, with GryMod's values.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Module = {}
GryMod.FlashHUD = Module

Module.MOVIE = "hud_ammohealthenergysuit"

-- The theme colours the movie's colour-set clips copy: hud_colorLine (outlines and icons), hud_colorOver
-- (active indicators) and hud_colorText (digits and letters). The game keeps them as 0xRRGGBB integers and hands
-- them to the movie unchanged; these are the four sets its options menu offers (read from the demo's
-- Options movie), "default" being the game's own default.
function Module.ColourFromInt(value)
	return {math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256}
end

local function theme(line, over, text)
	return {Line = Module.ColourFromInt(line), Over = Module.ColourFromInt(over), Text = Module.ColourFromInt(text)}
end

Module.Themes = {
	blue = theme(5079987, 5938225, 7906489),
	default = theme(4481854, 14125840, 12386209),
	white = theme(13553087, 9942506, 16777215),
	orange = theme(12612932, 16761744, 15108923)
}

-- The game's own default (its code and its shipped profile): military green. The other three are choices of its options menu.
Module.DefaultTheme = Module.Themes.default
Module.Theme = Module.DefaultTheme

local HUD = {}
HUD.__index = HUD

local MODE_FRAME = {Cloak = 1, Speed = 2, Strength = 3, Armor = 4}
local MAX_NUMBER = 999

local function number(value, default)
	if value == nil or value ~= value then
		return default
	end

	return value
end

local function clampNumber(value)
	return math.Clamp(number(value, 0), 0, MAX_NUMBER)
end

-- The three digits the original script computes for a displayed value.
local function digits(value)
	local hundreds = math.floor(value / 100)
	local tens = math.floor((value - hundreds * 100) / 10)
	local ones = math.floor(value - hundreds * 100 - tens * 10)

	return hundreds, tens, ones
end

-- A HUD from a converted movie (nil when the movie is missing).
function Module.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or Module.Theme)
	local main = root:Child("Root")

	if not main then
		return nil
	end

	local hud = setmetatable({
		root = root,
		main = main,
		status = 0, -- destroy(): 0 working, 1 malfunction, 2 flickering
		destroyMode = 4,
		health = 100,
		energy = 100,
		ammo = {mag = 0, reserve = 0, size = 0, grenades = 0, grenadeType = "explosivegrenade", fireMode = "Single"}
	}, HUD)

	hud:_start()

	return hud
end

-- The steady state of the original (SkipSequence is always true): the "on2" frames, and only the player
-- HUD shown (updateAmmoMode).
function HUD:_start()
	self.main:GotoAndStop("on2")
	self:_resolve()
	self.player:GotoAndStop("on2")
	self:_resolve()
	self:_refresh()
end

function HUD:_resolve()
	local main = self.main
	self.player = main:Child("Player")
	self.healthBar = main:Child("HealthBar")
	self.energyBar = main:Child("EnergyBar")
	self.icons = main:Child("SuitModeIcons")
	self.numbers = self.root:Find("Root.Texts.HealthEnergy.Colorset")

	for _, name in ipairs({"Tank", "VTOL", "EmptyHUD"}) do
		local other = main:Child(name)

		if other then
			other:SetVisible(false)
		end
	end

	if self.player then
		self.player:SetVisible(true)

		local overheat = self.player:Child("OverheatBar")

		if overheat then
			overheat:SetVisible(false) -- shown again by _applyHeat when a weapon gives a heat
		end
	end

	self.mainFrame, self.playerFrame = main:CurrentFrame(), self.player and self.player:CurrentFrame()
end

-- setHealth: the engine sends the percentage plus one (100 % = 101); the bar frame is that minus one.
function HUD:SetHealth(value)
	self.health = value
	local shown = math.floor(clampNumber(value))

	if shown > 0 then
		shown = shown - 1
	end

	if self.healthBar then
		self.healthBar:GotoAndStop(shown)
	end

	if self.numbers then
		local hundreds, tens, ones = digits(shown)
		self.numbers:SetText("HealthText1", hundreds)
		self.numbers:SetText("HealthText2", tens)
		self.numbers:SetText("HealthText3", ones)
	end
end

-- setEnergy: the same, with the energy plus one.
function HUD:SetEnergy(value)
	self.energy = value
	local shown = math.floor(clampNumber(value)) - 1

	if self.energyBar then
		self.energyBar:GotoAndStop(shown)
	end

	if self.numbers then
		local hundreds, tens, ones = digits(math.max(shown, 0))
		self.numbers:SetText("EnergyText1", hundreds)
		self.numbers:SetText("EnergyText2", tens)
		self.numbers:SetText("EnergyText3", ones)
	end
end

-- The suit's energy bar at the exact value, not at whole percents (cl_hud_bar_smooth.lua): `energy` is the float the bar shows, 0 to 100, the one SetEnergy was
-- given before its rounding. The bar is at its integer frame as SetEnergy put it, and the fraction is the cut line and the clone at the next frame. Nothing
-- is done (the bar is as the original draws it) when a step is a pixel or less or the setting gry_hud_bar_smooth is off. The digits stay whole numbers.
function HUD:SetEnergyExact(energy)
	local clip = self.energyBar
	local Smooth = GryMod.FlashBarSmooth

	if not clip or not Smooth then
		return
	end

	local bar = self.energySmooth

	-- the clip is another one when the HUD made its panel again (the movie's restart)
	if bar == nil or (bar and bar.mask ~= clip) then
		bar = Smooth.ForClip(clip, 0)
		self.energySmooth = bar or false
	end

	if bar then
		Smooth.Apply(bar, energy)
	end
end

-- setOverheatBar: the bar above the weapon icon. frame: 1 to 100 (the heat in percent), 0 or nil hides it (the original hides it for 0).
-- The movie's player HUD only; nothing is shown for a weapon that gives no heat.
function HUD:SetHeat(frame)
	self.heat = isnumber(frame) and number(frame, 0) or 0
	self:_applyHeat()
end

function HUD:_applyHeat()
	local bar = self.player and self.player:Child("OverheatBar")

	if not bar then
		return
	end

	local frame = math.Clamp(math.floor(self.heat or 0), 0, 100)

	if frame == 0 then
		bar:SetVisible(false)

		return
	end

	bar:SetVisible(true)
	bar:GotoAndStop(frame)
end

-- setMode: "Cloak", "Speed", "Strength" or "Armor" (anything else is ignored). While the suit is
-- malfunctioning the new icon starts in its malfunction animation.
function HUD:SetMode(mode)
	local frame = MODE_FRAME[mode]

	if not frame or not self.icons then
		return
	end

	self.mode = mode
	local changed = self.icons:CurrentFrame() ~= frame
	self.icons:GotoAndStop(frame)

	if self.status == 1 then
		-- only when the icon just changed: a refresh must not restart its animation at every frame
		if not changed then
			return
		end

		local icon = self.icons:Child(mode)

		if icon then
			icon:GotoAndPlay("malfunction")
		end
	else
		self.destroyMode = frame
	end
end

-- blinkAll: a real ammo update (setAmmo), where the original's updateColor plays the blink of every digit, changed or not.
-- Without it (the values put back at a refresh) a digit only flashes when its value changes.
local function setNumberClip(clip, value, colour, blinkAll)
	if not clip then
		return
	end

	local changed = blinkAll or clip.shownValue ~= value
	clip.shownValue = value
	clip:GotoAndStop(colour)

	local text = clip:Child("NumberText")

	if text then
		text:SetText("NumberText", value)
	end

	local blink = clip:Child("NumberText_blink")

	if blink and changed then
		blink:GotoAndPlay(2)

		local set = blink:Find("Set.Colorset")

		if set then
			set:SetText("NumberText", value)
		end
	end
end

-- setAmmo + updateTextColor of the player HUD. mag: rounds in the magazine (-1 = no ammo system),
-- reserve: rounds left, size: magazine capacity, grenades: how many, grenadeType: a GrenadeMode label.
-- weaponChanged: the values come from another weapon (its fire mode icon is not a switch of mode, so no blink).
-- The icon of the fire mode and the grenade icon blink when they change (the original calls switchFireMode and
-- switchGrenades when the player switches them), never at the first display.
-- launcher: the count of the weapon's secondary ammo shown in the grenade slot (nil: the hand grenades). launcherIcon: the label of the
-- weapon slot icon shown there ("Grenade", the 40 mm grenade, when nil), launcherLabel: the short text the weapon gives its secondary
-- (kept, see GetLauncherLabel: the movie has no text field for it).
function HUD:SetAmmo(mag, reserve, size, grenades, grenadeType, fireMode, launcher, weaponChanged, launcherIcon, launcherLabel)
	local ammo = self.ammo
	local shown, previousMode, previousGrenade = ammo.shown, ammo.fireMode, ammo.grenadeType
	ammo.launcher = launcher ~= nil and number(launcher, 0) or nil
	ammo.launcherIcon = ammo.launcher ~= nil and launcherIcon or nil
	ammo.launcherLabel = ammo.launcher ~= nil and launcherLabel or nil
	ammo.mag, ammo.reserve, ammo.size = number(mag, 0), number(reserve, 0), number(size, 0)
	ammo.grenades = number(grenades, 0)
	ammo.grenadeType = grenadeType or ammo.grenadeType
	ammo.fireMode = fireMode or ammo.fireMode
	self:_applyAmmo(true)
	ammo.shown = true

	-- after the icons are in place: a new icon frame rebuilds its clips, which would stop an animation started before
	if shown then
		if ammo.fireMode ~= previousMode and not weaponChanged then
			self:SwitchFireMode()
		end

		if ammo.grenadeType ~= previousGrenade then
			self:SwitchGrenades()
		end
	end
end

-- The short text the weapon in hand gives its secondary fire ("40mm"...), or nil. Not drawn yet: the movie has no text field
-- for it, and the atlases are not touched.
function HUD:GetLauncherLabel()
	return self.ammo.launcherLabel
end

-- switchFireMode: the "play" label of the Blink clip inside the fire mode icon (the hand grenade icon has none).
function HUD:SwitchFireMode()
	local slot = self.player and self.player:Child("AmmoMode")
	local blink = slot and slot:Child("Blink")

	if blink then
		blink:GotoAndPlay("play")
	end
end

-- switchGrenades: the "play" label of the Grenade clip inside the grenade icon (the 40 mm icon of a launcher has none).
function HUD:SwitchGrenades()
	local slot = self.player and self.player:Child("GrenadeMode")
	local grenade = slot and slot:Child("Grenade")

	if grenade then
		grenade:GotoAndPlay("play")
	end
end

-- The two icon sets of the movie: the hand grenades (GrenadeMode, one frame per kind) and the weapon slot
-- (AmmoMode, one frame per fire mode; its "Grenade" frame is the 40 mm grenade). Each slot can show the other set.
local iconIds = setmetatable({}, {__mode = "k"})

local function iconSets(movie)
	local found = iconIds[movie]

	if not found then
		found = {}

		for id, definition in pairs(movie.chars) do
			if definition.k == "sprite" and definition.labels then
				if definition.labels.explosivegrenade then found.hand = id end
				if definition.labels.Claymore then found.mode = id end
			end
		end

		iconIds[movie] = found
	end

	return found
end

local BLEND_ADD = 8

-- Makes the slot `name` of `parent` hold the character `id` (when it does not already) on the frame `frame`.
-- `add`: the icon (depth 1 of the slot's frame) is drawn with the blend mode "add". The weapon slot of the movie is
-- added as a whole, the grenade slot is not (its hand grenade icons are added one by one), so an icon of the weapon
-- slot shown in the grenade slot has to be added by itself: normal blended it is a dark shape (the theme's outline
-- colour at full strength) next to the other icons, which are brightened by what is behind them.
local function fillSlot(parent, name, id, frame, add)
	local entry = parent.names[name]

	if not entry or not id then
		return
	end

	if entry.id ~= id then
		local depth = entry.depth
		local op = {d = depth, c = id, n = name, m = entry.m, cx = entry.cx, bl = entry.blend}
		parent:_remove(depth)
		parent:_add(depth, id, op)
		entry = parent.names[name]
	end

	if entry and entry.clip then
		entry.clip:GotoAndStop(frame)

		local icon = add and entry.clip.list[1]

		if icon and icon.blend ~= BLEND_ADD then
			icon.blend = BLEND_ADD
			entry.clip:_touch()
		end
	end
end

function HUD:_applyAmmo(blinkAll)
	local player = self.player
	local ammo = self.ammo

	if not player then
		return
	end

	local texts = player:Child("AmmoTexts")
	local infinite = ammo.mag == -1 or ammo.size == -1
	local small = texts and self.root:Find("Root.Player.AmmoTexts.MagAmmo.Colorset")

	if texts then
		local icon = texts:Child("PrimaryInfinityIcon")

		if icon then
			icon:SetVisible(infinite)
		end

		local secondary = texts:Child("SecondaryInfinityIcon")

		if secondary then
			secondary:SetVisible(false)
		end
	end

	if small then
		small:SetText("MagAmmo", infinite and " " or tostring(math.floor(clampNumber(ammo.reserve))))
		small:SetText("GrenadeAmmo", tostring(math.floor(clampNumber(ammo.launcher or ammo.grenades))))
	end

	local primary = texts and texts:Child("PrimaryAmmo")

	if primary then
		local one, two, three = primary:Child("ObjNumber1"), primary:Child("ObjNumber2"), primary:Child("ObjNumber3")

		if infinite then
			for _, clip in ipairs({one, two, three}) do
				if clip then
					clip:SetVisible(false)
				end
			end
		else
			local value = math.floor(clampNumber(ammo.mag))
			local colour = "green"

			if ammo.size ~= 0 and value <= ammo.size / 3 then
				colour = "red"
			end

			local hundreds, tens, ones = digits(value)
			setNumberClip(one, hundreds, (value > 100 and "" or "low") .. colour, blinkAll)
			setNumberClip(two, tens, (value > 9 and "" or "low") .. colour, blinkAll)
			setNumberClip(three, ones, colour, blinkAll)

			if one then one:SetVisible(ammo.size > 100) end
			if two then two:SetVisible(ammo.size > 9) end
			if three then three:SetVisible(true) end
		end
	end

	local sets = iconSets(self.root.movie)

	-- a launcher shows the icon its weapon chose (by default the 40 mm grenade) where the hand grenades are, the hand grenade
	-- weapon its own icon in the weapon slot
	if ammo.launcher ~= nil then
		fillSlot(player, "GrenadeMode", sets.mode, ammo.launcherIcon or "Grenade", true)
	else
		fillSlot(player, "GrenadeMode", sets.hand, ammo.grenadeType)
	end

	if ammo.fireMode == "HandGrenade" then
		fillSlot(player, "AmmoMode", sets.hand, ammo.grenadeType)
	else
		fillSlot(player, "AmmoMode", sets.mode, ammo.fireMode)
	end
end

-- Switch: after a malfunction the icon of the current mode plays its "reboot" animation (RebootHUD runs reboot() on every movie).
local IconRebootConVar = CreateClientConVar("gry_icon_reboot", "1", true, false, "After a HUD malfunction the suit mode icon plays its reboot animation (the original); 0: it does not")

-- destroy: 0 the suit works again, 1 malfunction, 2 flickering. The original also plays a sound.
function HUD:Destroy(status)
	local previous = self.status
	self.status = status

	local label = status == 1 and "malfunction" or status == 2 and "flickering" or "normal"

	if self.icons then
		local names = {"Cloak", "Speed", "Strength", "Armor"}
		local icon = self.icons:Child(names[self.destroyMode])

		if icon then
			icon:GotoAndPlay(label)
		end
	end

	if status == 0 then
		-- the original plays "normal", whose script jumps straight to the steady frames again
		self.main:GotoAndPlay("normal")
		self.main:GotoAndStop("on2")
		self:_resolve()
		self.player:GotoAndStop("on2")
		self:_resolve()
		self:_refresh()

		-- RebootHUD: destroy(0) then reboot(), which plays the "reboot" label (frames 43 to 49, 0.23 s) of the icon now shown
		if previous == 1 and IconRebootConVar:GetBool() and self.icons and self.mode then
			local current = self.icons:Child(self.mode)

			if current then
				current:GotoAndPlay("reboot")
			end
		end
	else
		self.main:GotoAndPlay(label)

		-- frame 30 of the movie's root: the player HUD malfunctions too (its script does it for the current HUD)
		if status == 1 and self.player then
			self.player:GotoAndPlay("malfunction")
		end

		if status == 2 and self.player then
			self.player:GotoAndPlay("flickering")
		end
	end
end

-- Puts every shown value back (what the original frame scripts do whenever the clips are rebuilt).
function HUD:_refresh()
	self:SetHealth(self.health)
	self:SetEnergy(self.energy)

	if self.mode then
		self:SetMode(self.mode)
	end

	self:_applyAmmo()
	self:_applyHeat()
end

function HUD:Update(dt)
	self.root:Advance(dt)

	-- a timeline that went back rebuilt its clips: the texts start over, so say them again
	local frame, playerFrame = self.main:CurrentFrame(), self.player and self.player:CurrentFrame()

	if frame ~= self.mainFrame or playerFrame ~= self.playerFrame then
		self:_resolve()
		self:_refresh()
	end
end

function HUD:Draw(x, y, scale)
	Flash.Draw(self.root, x, y, scale)
end

-- ---------------------------------------------------------------------------------------------------------
-- GryMod's values, and the paint hook
-- ---------------------------------------------------------------------------------------------------------

local themeConVar = CreateClientConVar("gry_hud_theme", "default", true, false, "HUD colours: default (military green), blue (ice blue), white, orange or custom (gry_hud_color_*)")

-- The three colours of the "custom" theme, each written "r g b" (0 to 255), as the original's hud_colorLine,
-- hud_colorOver and hud_colorText but readable.
local CUSTOM_CONVARS = {
	Line = CreateClientConVar("gry_hud_color_line", "77 131 179", true, false, "Custom HUD colour of the outlines and icons: r g b"),
	Over = CreateClientConVar("gry_hud_color_over", "90 156 177", true, false, "Custom HUD colour of the active indicators: r g b"),
	Text = CreateClientConVar("gry_hud_color_text", "120 183 185", true, false, "Custom HUD colour of the digits and letters: r g b")
}

-- "r g b" as {r, g, b} with each number held between 0 and 255; nil when it is not three numbers.
function Module.ParseColour(text)
	if type(text) ~= "string" then
		return nil
	end

	local r, g, b, rest = string.match(text, "^%s*(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*(.*)$")
	r, g, b = tonumber(r), tonumber(g), tonumber(b)

	if not (r and g and b) or rest ~= "" then
		return nil
	end

	return {
		math.Clamp(math.Round(r), 0, 255),
		math.Clamp(math.Round(g), 0, 255),
		math.Clamp(math.Round(b), 0, 255)
	}
end

-- The theme made of the gry_hud_color_* settings (the default colour stands in for a setting that cannot be read).
function Module.CustomTheme()
	local result = {}

	for part, convar in pairs(CUSTOM_CONVARS) do
		result[part] = Module.ParseColour(convar:GetString()) or Module.DefaultTheme[part]
	end

	return result
end

-- Chooses the colours (default, blue, white, orange, custom) of the HUD drawn from now on.
function Module.SetTheme(name)
	if name == "custom" then
		Module.Theme = Module.CustomTheme()
	else
		Module.Theme = Module.Themes[name] or Module.DefaultTheme
	end
end

Module.SetTheme(themeConVar:GetString())

local MODE_NAME = {
	[GryMod.Modes.ARMOR] = "Armor",
	[GryMod.Modes.SPEED] = "Speed",
	[GryMod.Modes.CLOAK] = "Cloak",
	[GryMod.Modes.STRENGTH] = "Strength"
}

-- GryMod's suit mode as the movie names it (the parachute mode has no icon in the original: armor).
function Module.ModeName(mode)
	return MODE_NAME[mode] or "Armor"
end

-- What the engine sends for the health bar: the percentage plus one.
function Module.HealthValue(health, maxHealth)
	if not maxHealth or maxHealth <= 0 then
		maxHealth = 100
	end

	return math.floor(math.Clamp(health / maxHealth * 100, 0, MAX_NUMBER) + 1)
end

function Module.EnergyValue(energy)
	return math.floor(math.Clamp(energy, 0, MAX_NUMBER) + 1)
end

-- The icons the movie has for the weapon above the grenade (the labels of its AmmoMode clip): the registry's list of icons, which
-- is also what a weapon definition may choose (icon, slotIcon, altIcon).
local FIRE_MODE_ICONS = GryMod.API and GryMod.API.WeaponIcons or {}

-- What a weapon says about itself comes from the weapon registry (GryMod.API, sh_api_weapons.lua): the stock weapons are registered
-- there as data (compat/hl2/sh_weapons.lua) like any addon's, and nothing in this file knows a class. Without the registry a weapon
-- is a plain one.
local function weaponValue(weapon, field, explicit)
	local read = GryMod.API and GryMod.API.WeaponValue

	return read and read(weapon, field, explicit) or nil
end

-- The icon label of a declared fire mode.
local FIRE_LABEL = {auto = "Auto", semi = "Single", burst = "Burst", none = "NoGun"}

local resolvers = {}
local keyed = {}

local function removeResolver(fn)
	for i, other in ipairs(resolvers) do
		if other == fn then
			table.remove(resolvers, i)

			return
		end
	end
end

-- Weapon bases that keep their fire mode in their own fields can say how to read it: fn(weapon) returns one
-- of the movie's icon labels, or nil when this weapon is not theirs. Returns a function that removes it.
-- `key` (optional, any value) names the resolver: adding another one with the same key replaces the first, so a file that is loaded twice (a hot reload) does not pile
-- its resolver up. The function a replaced resolver returned takes nothing away any more.
function Module.AddFireModeResolver(fn, key)
	if key ~= nil then
		local old = keyed[key]

		if old then
			removeResolver(old)
		end

		keyed[key] = fn
	end

	resolvers[#resolvers + 1] = fn

	return function()
		removeResolver(fn)

		if key ~= nil and keyed[key] == fn then
			keyed[key] = nil
		end
	end
end

-- A mode kept as a string ("auto", "3burst", "Automatic", "Safe"...) as the icon label of the weapon slot: "Burst", "Auto", or "Single" for anything else (a safety
-- catch, a semi-automatic mode, a value that is no text). For the readers of the weapon bases that keep their mode as text (TFA, CW 2.0, FA:S 2.0, an addon's).
function Module.FireModeFromName(name)
	if not isstring(name) then
		return "Single"
	end

	name = string.lower(name)

	if string.find(name, "burst", 1, true) then
		return "Burst"
	end

	if string.find(name, "auto", 1, true) then
		return "Auto"
	end

	return "Single"
end

-- (the readers of the weapon bases are in lua/grymod/compat/weapons/, one file each, loaded after this file)

-- The icon for what the player holds: what the weapon registry declares for it (icon, slotIcon or the fire mode), else what a
-- registered base says, else the generic SWEP rule (Primary.Automatic: automatic, otherwise one shot at a time).
-- Player:GetActiveWeapon() gives the NULL entity (not nil) when the player holds nothing.
local function validWeapon(weapon)
	if not weapon or (weapon.IsValid and not weapon:IsValid()) then
		return nil
	end

	return weapon
end

function Module.FireModeFor(weapon)
	weapon = validWeapon(weapon)

	if not weapon then
		return "NoGun"
	end

	local declared = weaponValue(weapon, "icon", true) or weaponValue(weapon, "slotIcon", true) or FIRE_LABEL[weaponValue(weapon, "fire", true)]

	if declared then
		return declared
	end

	for _, resolver in ipairs(resolvers) do
		local ok, label = pcall(resolver, weapon)

		if ok and FIRE_MODE_ICONS[label] then
			return label
		end
	end

	return FIRE_LABEL[weaponValue(weapon, "fire")] or "Single"
end

-- The ammo the weapon's secondary fire counts in the grenade slot, or nil: a grenade launcher (the SMG's grenade) or the energy ball
-- of the AR2 are counted, what the weapon registry says (alt = "grenade" or "energy" and its altAmmo). A weapon the registry does
-- not know keeps the old rule: its secondary ammo is a grenade type that is not the hand grenade's.
local function launcherAmmo(weapon)
	local alt = weaponValue(weapon, "alt")

	if alt ~= "grenade" and alt ~= "energy" then
		return nil
	end

	local ammo = weaponValue(weapon, "altAmmo")

	if not ammo or game.GetAmmoID(ammo) < 0 then
		return nil
	end

	return ammo
end

-- The grenades (or energy balls) a launcher weapon holds, or nil when the weapon has none.
function Module.LauncherFor(ply, weapon)
	weapon = validWeapon(weapon)

	if not weapon then
		return nil
	end

	local ammo = launcherAmmo(weapon)

	if not ammo then
		return nil
	end

	return ply:GetAmmoCount(ammo)
end

-- What the grenade slot shows for the weapon's secondary: the icon label (the 40 mm grenade when the weapon does not choose) and the
-- short text; nil when the weapon has no launcher.
function Module.LauncherLookFor(weapon)
	weapon = validWeapon(weapon)

	if not weapon or not launcherAmmo(weapon) then
		return nil
	end

	return weaponValue(weapon, "altIcon") or "Grenade", weaponValue(weapon, "altLabel")
end

-- The kind of hand grenade the grenade slot shows while this weapon is in hand: what the weapon registry declares (`grenade`), else the
-- explosive grenade, the one of Half-Life 2.
function Module.GrenadeKindFor(weapon)
	weapon = validWeapon(weapon)

	return weapon and weaponValue(weapon, "grenade", true) or "explosivegrenade"
end

-- magazine, reserve, magazine size, grenades, fire mode icon and the kind of hand grenade of what the player holds. -1 = no ammo system.
-- A weapon that declares its own kind of grenade (a flash grenade, a smoke grenade...) counts its own primary ammo in the grenade slot
-- (the hand grenades of the player are the explosive ones).
function Module.AmmoFor(ply, weapon)
	weapon = validWeapon(weapon)

	local grenades = ply:GetAmmoCount("Grenade")
	local fireMode = Module.FireModeFor(weapon)
	local kind = Module.GrenadeKindFor(weapon)

	if not weapon or weapon:GetPrimaryAmmoType() < 0 then
		return -1, 0, -1, grenades, fireMode, kind
	end

	local type = weapon:GetPrimaryAmmoType()
	local clip = weapon:Clip1()

	if kind ~= "explosivegrenade" then
		grenades = ply:GetAmmoCount(type)
	end

	if clip < 0 then
		-- no magazine: the reserve is what is shown
		local count = ply:GetAmmoCount(type)

		return count, 0, count, grenades, fireMode, kind
	end

	return clip, ply:GetAmmoCount(type), math.max(weapon:GetMaxClip1(), clip), grenades, fireMode, kind
end

-- The frame of the overheat bar for a heat of 0 (cold) to 1 (overheated): 0 hides the bar, anything above 0 is at least the frame 1.
-- Anything that is not a number is a cold weapon.
function Module.HeatFrame(heat)
	if not isnumber(heat) or heat ~= heat or heat <= 0 then
		return 0
	end

	return math.Clamp(math.ceil(heat * 100 - 0.5), 1, 100)
end

-- What tells the heat of this weapon: the function the weapon registry declares (`heat`), or nil: the weapon has no heat source, no weapon
-- in hand, or the player turned the bar off (gry_hud_overheat). Asked when the weapon changes, not at every frame.
function Module.HeatSourceFor(weapon)
	weapon = validWeapon(weapon)

	if not weapon or (GryMod.HUDOptions and not GryMod.HUDOptions.Enabled("overheat")) then
		return nil
	end

	local source = weaponValue(weapon, "heat", true)

	return isfunction(source) and source or nil
end

local heatIds = setmetatable({}, {__index = function(ids, class)
	ids[class] = "weapon:" .. class .. "/heat"

	return ids[class]
end})

-- The frame of the bar for the weapon, from its heat source (HeatSourceFor): 0 when it has none or the source fails (it runs under
-- GryMod.API.SafeCall, so a broken one never reaches the HUD).
function Module.HeatOf(weapon, source)
	if not source then
		return 0
	end

	local class = weapon.GetClass and weapon:GetClass()
	local ok, heat = GryMod.API.SafeCall(heatIds[isstring(class) and class or "?"], source, weapon)

	return ok and Module.HeatFrame(heat) or 0
end

-- The energy (0 to 100) at which the suit stops under GryMod's old rule (gry_malfunction_empty): the HUD malfunctions
-- (red) while the bar is empty and reboots once it is back above RECOVER_AT. Between the two, and with no usable value, the state stays as it is.
Module.RECOVER_AT = 10

function Module.MalfunctionFor(energy, current)
	current = current == 1 and 1 or 0

	if type(energy) ~= "number" or energy ~= energy then
		return current
	end

	if energy <= 0 then
		return 1
	end

	if current == 1 and energy < Module.RECOVER_AT then
		return 1
	end

	return 0
end

-- GryMod's earlier rule: the HUD also malfunctions while the energy bar is empty (see MalfunctionFor). In the original
-- the HUD only goes down on an EMP or a death, and leaving the camouflage by firing or striking empties the bar without
-- any malfunction, so the rule is off by default. The case of an electric attack that ends the armor bar is the server's
-- (GryMalfunction, sv_malfunction.lua).
local emptyRuleConVar = CreateClientConVar("gry_malfunction_empty", "0", true, false, "1: the HUD malfunctions while the energy bar is empty (GryMod's old rule); 0: only when the server says the suit is down (EMP, electric attack), as in the original")

-- The status the HUD shows. The server says when the suit is down (GryMod.Malfunction: an EMP, an electric hit...):
-- that is status 1 whatever the energy. With emptyRule (gry_malfunction_empty) the empty-bar rule above applies too,
-- except just after a restart (restarted): the bar is still empty then and the HUD reboots anyway. A flicker (a light
-- shock) is status 2 when nothing else is wrong.
function Module.StatusFor(energy, current, down, restarted, flicker, emptyRule)
	if down then
		return 1
	end

	local status = 0

	if emptyRule and not restarted then
		status = Module.MalfunctionFor(energy, current)
	end

	if status == 0 and flicker then
		return 2
	end

	return status
end

-- The restart hold: armed while the suit is down, released once the bar has started to recharge.
function Module.RestartHold(held, down, energy)
	if down then
		return true
	end

	if held and type(energy) == "number" and energy > 0 then
		return false
	end

	return held
end

-- The original's death handler puts the HUD down (the "lost" function): the HUD turns red, the emergency shutdown animation plays with the
-- malfunction sound. Here the HUD used to vanish at the death; with this setting (on) it stays on the screen, red, with that screen and sound
-- for as long as the player is dead, and a respawn starts it again from nothing (the start-up log of the spawn plays as it always did).
local lostOnDeathConVar = CreateClientConVar("gry_hud_lost_on_death", "1", true, false, "1: when the player dies the HUD goes red with the emergency shutdown animation and sound until the respawn (the original); 0: the HUD just disappears", 0, 1)

-- What the paint does about the life of the player, as one of: "start" (the player has just died with the HUD up: it goes down, red), "keep" (still dead, the
-- red HUD stays), "respawn" (alive again after a death shown this way: a fresh HUD), "drop" (dead and nothing to show: the HUD is dropped, as it used
-- to be), nil (alive, nothing special). alive and wasAlive: the state now and at the last paint; shown: the death is on the screen; built: there is
-- a HUD to turn red; wanted: the setting.
function Module.DeathPhase(alive, wasAlive, shown, built, wanted)
	if alive then
		return shown and "respawn" or nil
	end

	if shown then
		return "keep"
	end

	if wanted and built and wasAlive then
		return "start"
	end

	return "drop"
end

-- Whether the movie is there (the HUD and the other pieces need it).
function Module.Available()
	return Flash.Load(Module.MOVIE) ~= nil
end

-- Whether the suit of the player is on. An addon can switch it off (GryMod.API.SetSuitEnabled on the server: the suit is not on
-- the player's body yet): the HUD is then hidden. Nothing to hide for a player that is not there yet.
function Module.SuitOn(ply)
	local API = GryMod.API

	-- the HUD events "disabled" (until "enabled" or "reset") hide the HUD of this screen only: the suit itself is unchanged
	if Module.LocalOff then
		return false
	end

	if not (API and API.IsSuitEnabled) or not IsValid(ply) then
		return true
	end

	return API.IsSuitEnabled(ply)
end

-- The HUD events "disabled" and "enabled" (cl_api_hud_events.lua): the HUD of this screen is hidden, or shown again.
Module.LocalOff = false

function Module.SetLocalOff(off)
	Module.LocalOff = off == true
end

function Module.IsLocalOff()
	return Module.LocalOff == true
end

-- Whether the player wants a HUD at all (gry_hud) and the movie is there, whatever the state of the suit: the shutdown animation
-- of the "disabled" event is drawn while the HUD itself is hidden.
function Module.HudWanted()
	local convar = GetConVar("gry_hud")

	return (not convar or convar:GetBool()) and Module.Available()
end

-- Whether the HUD is on (gry_hud, and the suit is on) and can be drawn.
function Module.Enabled()
	local convar = GetConVar("gry_hud")

	return (not convar or convar:GetBool()) and Module.SuitOn(LocalPlayer()) and Module.Available()
end

local hud, panel
local lastTime
local fed = {}
local deathShown = false -- the player died with the HUD up and the setting on: the red HUD stays until the respawn
local wasAlive = false -- the player was alive at the last paint
-- what the damage effects look at each frame (one table, filled in again)
local fxSample = {}

-- The energy the server last told (cl_energy_smooth.lua: at every tick, where the networked float only comes about
-- every 0.1 s), for what looks at thresholds and drops; the bar and the digits get the predicted one.
local function serverEnergy(ply)
	local smooth = GryMod.EnergySmooth

	if smooth then
		return (smooth.Raw(ply, CurTime()))
	end

	return ply:GetNW2Float("GryEnergy")
end

local function feed(ply)
	local maxHealth = ply:GetMaxHealth()
	local health = Module.HealthValue(ply:Health(), maxHealth)

	if fed.health ~= health then
		fed.health = health
		hud:SetHealth(health)
	end

	-- the original gives its HUD the energy as a float at every frame (setEnergy); here it is predicted between
	-- the server's updates (cl_energy_smooth.lua)
	local smooth = GryMod.EnergySmooth
	local exactEnergy = smooth and smooth.Shown(ply, CurTime()) or ply:GetNW2Float("GryEnergy")
	local energy = Module.EnergyValue(exactEnergy)

	if fed.energy ~= energy then
		fed.energy = energy
		hud:SetEnergy(energy)
	end

	-- and the bar at the exact value (the cut line: cl_hud_bar_smooth.lua)
	hud:SetEnergyExact(exactEnergy)

	-- the server says when the suit is down (an EMP, an electric hit) and when a light shock flickers the HUD
	local down = ply:GetNW2Bool("GryMalfunction", false)
	local rawEnergy = serverEnergy(ply)
	fed.restartHold = Module.RestartHold(fed.restartHold or false, down, rawEnergy)
	local status = Module.StatusFor(rawEnergy, hud.status, down, fed.restartHold and not down, ply:GetNW2Float("GryFlicker", 0) > CurTime(), emptyRuleConVar:GetBool())

	if status ~= hud.status then
		hud:Destroy(status)

		if panel then
			panel:Destroy(status)
		end

		-- the start-up and reboot sequences follow the state of the HUD
		hook.Run("GryMod_HUDStatus", status)
	end

	local mode = Module.ModeName(ply.NanosuitMode)

	if fed.mode ~= mode then
		fed.mode = mode
		hud:SetMode(mode)
	end

	local weapon = ply:GetActiveWeapon()
	local mag, reserve, size, grenades, fireMode, grenadeKind = Module.AmmoFor(ply, weapon)
	local launcher = Module.LauncherFor(ply, weapon)
	local launcherIcon, launcherLabel

	if launcher ~= nil then
		launcherIcon, launcherLabel = Module.LauncherLookFor(weapon)
	end

	local weaponChanged = fed.weapon ~= weapon
	local previousWeapon = fed.weapon
	fed.weapon = weapon

	-- the weapon list (cl_hud_weaponlist_flash.lua) shows at each real change of the weapon in hand; nothing of its own runs between two changes
	if weaponChanged and GryMod.FlashWeaponList then
		GryMod.FlashWeaponList.OnWeaponChanged(ply, weapon, previousWeapon)
	end

	-- the heat bar: the source is looked up when the weapon (or the switch) changes, the weapon is asked at each frame. Nothing runs
	-- for a weapon without a heat source.
	local heatOn = not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("overheat")

	if weaponChanged or fed.heatOn ~= heatOn then
		fed.heatOn = heatOn
		fed.heatSource = Module.HeatSourceFor(weapon)
	end

	local heat = fed.heatSource and Module.HeatOf(weapon, fed.heatSource) or 0

	if fed.heat ~= heat then
		fed.heat = heat
		hud:SetHeat(heat)
		pcall(hook.Run, "GryMod_WeaponHeat", ply, weapon, heat) -- a broken listener must not stop the paint
	end

	if fed.mag ~= mag or fed.reserve ~= reserve or fed.size ~= size or fed.grenades ~= grenades or fed.fireMode ~= fireMode or fed.launcher ~= launcher
		or fed.launcherIcon ~= launcherIcon or fed.launcherLabel ~= launcherLabel or fed.grenadeKind ~= grenadeKind then
		fed.mag, fed.reserve, fed.size, fed.grenades, fed.fireMode, fed.launcher = mag, reserve, size, grenades, fireMode, launcher
		fed.launcherIcon, fed.launcherLabel, fed.grenadeKind = launcherIcon, launcherLabel, grenadeKind
		hud:SetAmmo(mag, reserve, size, grenades, grenadeKind, fireMode, launcher, weaponChanged, launcherIcon, launcherLabel)
	end
end

-- The jump of a heavy hit (stage pixels) as whole screen pixels. The images of the panel's groups are made for a position, and a
-- jump that is a fraction of a pixel made every one of them again at every frame of the shaking (up to 30 images, 0.4 to 2 ms);
-- a whole number of pixels only moves the images that are kept (cl_flash_draw.lua).
function Module.JumpPixels(jump, scale)
	return math.floor(jump * scale + 0.5)
end

-- gry_xadd spreads the two panels apart (the left one goes left), gry_xdist shifts both.
local function xOffsets()
	local add, distance = GetConVar("gry_xadd"), GetConVar("gry_xdist")
	add, distance = add and add:GetInt() or 0, distance and distance:GetInt() or 0

	return add + distance, distance - add
end

-- The paint hook: nothing while dead or spectating, a fresh HUD after every respawn.
-- When the engine frees and rebuilds its graphics (another Garry's Mod starting: Facepunch garrysmod-issues #7137; an
-- alt-tab; a video change) the render targets lose what was drawn in them, but the interface keeps reusing its cached
-- picture of them: the panels would stay empty. The rebuild blocks the main thread for seconds, so a long gap between two
-- paints is how it is noticed: the interface is then rebuilt, and draws itself again.
Module.RESTORE_GAP = 2
local lastPaintAt

function Module.IsRestoreGap(gap)
	return isnumber(gap) and gap == gap and gap >= Module.RESTORE_GAP
end

-- The next paint is a first one again (a new level, the HUD off): the time since the last paint means nothing.
function Module.ForgetPaintTime()
	lastPaintAt = nil
end

-- Called by each paint with the real time; rebuilds the interface after a restore. Returns whether it did.
function Module.CheckRestore(now)
	local gap = lastPaintAt and now - lastPaintAt
	lastPaintAt = now

	if Module.IsRestoreGap(gap) then
		Module.ResetAll()

		return true
	end

	return false
end

hook.Add("InitPostEntity", "GRYFLASHHUDRESTORE", function()
	Module.ForgetPaintTime()
end)

-- The status of the HUD as the movie's destroy() left it (0 working, 1 malfunction, 2 flickering), nil when there is no HUD.
function Module.Status()
	return hud and hud.status or nil
end

-- Whether the HUD is on the screen only because the player is dead (the red HUD of gry_hud_lost_on_death).
function Module.DeathShown()
	return deathShown
end

-- The player has died with the HUD up: it goes down, as the movie's destroy(1) does it for the original's death handler. The report to the
-- other pieces is the one of every HUD status change (the hook GryMod_HUDStatus, with the reason "death" as a second argument), so the
-- emergency shutdown screen and its sound are the event "lost", by the same path as a suit that goes down. Nothing is fed to the HUD while the
-- player is dead: it keeps what it showed.
function Module.GoDown()
	if not hud then
		return
	end

	if hud.status ~= 1 then
		hud:Destroy(1)

		if panel then
			panel:Destroy(1)
		end

		hook.Run("GryMod_HUDStatus", 1, "death")
	end

	if GryMod.FlashBoot then
		GryMod.FlashBoot.HoldDeath(true)
	end
end

function Module.Paint()
	Module.CheckRestore(RealTime())

	local ply = LocalPlayer()

	if not IsValid(ply) or not Module.SuitOn(ply) then
		deathShown, wasAlive = false, false
		Module.Reset()

		return
	end

	local alive = ply:Alive()
	local phase = Module.DeathPhase(alive, wasAlive, deathShown, hud ~= nil, lostOnDeathConVar:GetBool())
	wasAlive = alive

	if phase == "drop" then
		Module.Reset()

		return
	elseif phase == "start" then
		deathShown = true
		Module.GoDown()
	elseif phase == "respawn" then
		-- alive again: the red HUD and its Lost screen end here, whatever order the pieces are painted in
		deathShown = false
		Module.Reset()

		if GryMod.FlashBoot then
			GryMod.FlashBoot.EndDeath()
		end

		if GryMod.FlashCorners then
			GryMod.FlashCorners.SetStatus(0)
		end

		-- the death told every listener "1"; the new HUD starts at 0, so its first feed sees no change and would never say it: the big map would open
		-- on "Satellite Uplink disconnected" and the binoculars keep the malfunction look. The boot sequences hear it after EndDeath: no reboot sound.
		hook.Run("GryMod_HUDStatus", 0, "respawn")
	end

	if not hud then
		hud = Module.New(Flash.Load(Module.MOVIE))
		panel = GryMod.FlashRadar and GryMod.FlashRadar.New(Flash.Load(GryMod.FlashRadar.MOVIE))
		fed = {}
		lastTime = nil

		if not hud then
			return
		end

		-- a HUD made again while the death is shown (a new colour) is red as well
		if deathShown then
			Module.GoDown()
		end
	end

	if alive then
		feed(ply)
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	-- the stage is 1024 x 768, scaled to the screen height; the ammo block sits at the bottom right and the
	-- compass panel at the bottom left, as in the original
	local scale = ScrH() / 768
	local right, left = xOffsets()

	hud:Update(dt)

	-- a heavy armor hit makes both panels jump together (cl_damage_fx.lua: the original's HUD interference), and the
	-- screen effects of damage are started from here (one look at the player a frame)
	local jumpX, jumpY = 0, 0
	local damageFx = GryMod.DamageFx

	if damageFx then
		-- (a dead player's health and energy are no hit)
		if alive then
			fxSample.health = ply:Health()
			fxSample.max = ply:GetMaxHealth()
			fxSample.energy = serverEnergy(ply)
			fxSample.armor = Module.ModeName(ply.NanosuitMode) == "Armor"
			fxSample.malfunction = ply:GetNW2Bool("GryMalfunction", false) -- the start of a malfunction empties the bar: not a hit
			damageFx.Observe(damageFx.State, fxSample, now, damageFx.Options())
		end

		jumpX, jumpY = damageFx.HudOffset(damageFx.State, dt)
		jumpX, jumpY = Module.JumpPixels(jumpX, scale), Module.JumpPixels(jumpY, scale)
	end

	-- each panel has its own switch (gry_hud_status, gry_hud_radar); a hidden one keeps running so that it is
	-- in the right state when it comes back
	if not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("status") then
		hud:Draw(ScrW() - 1024 * scale + right + jumpX, ScrH() - 768 * scale + jumpY, scale)
	end

	if panel then
		local Radar = GryMod.FlashRadar

		if alive then
			panel:SetHeading(Radar.BearingFromYaw(Flash.ViewYaw(ply)))
			panel:SetFOV(Radar.FovFrame(Radar.ViewFov(ply)))
			-- the contacts and the stealth bar (cl_hud_radar_units.lua); the radar still draws if that file did not load
			if Radar.Feed then
				Radar.Feed(panel, ply, dt)
			end
		end

		panel:Update(dt)

		if not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("radar") then
			panel:Draw(left + jumpX, ScrH() - 768 * scale + jumpY, scale)
		end
	end

	-- the corner marks (cl_hud_corners_flash.lua), their own setting
	if GryMod.FlashCorners then
		GryMod.FlashCorners.Paint(dt)
	end

	-- the night vision's energy bar (cl_hud_nightvision_flash.lua): one test of a flag while it is not up
	if GryMod.FlashNightVisionBar then
		GryMod.FlashNightVisionBar.Paint(dt)
	end
end

-- Drops the HUD so that the next frame builds a new one (a new theme, a respawn...): the render targets of its
-- groups go back to the pool instead of being kept for ever.
function Module.Reset()
	if hud then
		Flash.ReleaseClip(hud.root)
	end

	if panel then
		panel:Release()
	end

	hud, panel = nil, nil

	if GryMod.FlashCorners then
		GryMod.FlashCorners.Reset()
	end

	if GryMod.FlashNightVisionBar then
		GryMod.FlashNightVisionBar.Reset()
	end

	-- the energy bar starts on the real value (a respawn)
	if GryMod.EnergySmooth then
		GryMod.EnergySmooth.view:Reset()
	end

	-- a respawn starts with no damage effect and a fresh reference health
	if GryMod.DamageFx then
		GryMod.DamageFx.Reset(GryMod.DamageFx.State)
	end
end

-- Adds or removes the paint hook; returns whether this style is the one being drawn.
function Module.Apply(enabled)
	local active = enabled and Module.Available()

	if active then
		hook.Add("HUDPaint", "GRYFLASHHUD", Module.Paint)
	else
		hook.Remove("HUDPaint", "GRYFLASHHUD")
		Module.ForgetPaintTime()
		Module.Reset()
	end

	return active
end

-- Drops every piece of the interface so that the next frame builds them again (a new theme).
function Module.ResetAll()
	Module.Reset()

	for _, module in ipairs({GryMod.FlashMenu, GryMod.FlashBinoculars, GryMod.FlashGrenade, GryMod.FlashCrosshair, GryMod.FlashBoot, GryMod.FlashMessages, GryMod.FlashUse, GryMod.FlashPickup, GryMod.FlashCorners, GryMod.FlashNightVisionBar, GryMod.FlashWeaponList, GryMod.FlashObjectives}) do
		-- a piece that has a state to keep (the boot sequences) rebuilds its pictures instead of starting over
		local rebuild = module and (module.Rebuild or module.Reset)

		if rebuild then
			rebuild()
		end
	end
end

cvars.AddChangeCallback("gry_hud_theme", function(_, _, value)
	Module.SetTheme(value)

	if GryMod.ApplyHUD then
		Module.ResetAll()
	end
end, "GryModHUDTheme")

-- a custom colour changes: the interface follows it, but only while the custom theme is the one in use
for part, convar in pairs(CUSTOM_CONVARS) do
	cvars.AddChangeCallback(convar:GetName(), function()
		if themeConVar:GetString() ~= "custom" then
			return
		end

		Module.SetTheme("custom")

		if GryMod.ApplyHUD then
			Module.ResetAll()
		end
	end, "GryModHUDColour" .. part)
end

