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

Module.Theme = Module.Themes.blue

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
			overheat:SetVisible(false)
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

local function setNumberClip(clip, value, colour)
	if not clip then
		return
	end

	-- the digit flashes when its value changes, not every time the clips are put back
	local changed = clip.shownValue ~= value
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
function HUD:SetAmmo(mag, reserve, size, grenades, grenadeType, fireMode)
	local ammo = self.ammo
	ammo.mag, ammo.reserve, ammo.size = number(mag, 0), number(reserve, 0), number(size, 0)
	ammo.grenades = number(grenades, 0)
	ammo.grenadeType = grenadeType or ammo.grenadeType
	ammo.fireMode = fireMode or ammo.fireMode
	self:_applyAmmo()
end

function HUD:_applyAmmo()
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
		small:SetText("GrenadeAmmo", tostring(math.floor(clampNumber(ammo.grenades))))
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
			setNumberClip(one, hundreds, (value > 100 and "" or "low") .. colour)
			setNumberClip(two, tens, (value > 9 and "" or "low") .. colour)
			setNumberClip(three, ones, colour)

			if one then one:SetVisible(ammo.size > 100) end
			if two then two:SetVisible(ammo.size > 9) end
			if three then three:SetVisible(true) end
		end
	end

	local grenadeMode = player:Child("GrenadeMode")

	if grenadeMode then
		grenadeMode:GotoAndStop(ammo.grenadeType)
	end

	local fireMode = player:Child("AmmoMode")

	if fireMode then
		fireMode:GotoAndStop(ammo.fireMode)
	end
end

-- destroy: 0 the suit works again, 1 malfunction, 2 flickering. The original also plays a sound.
function HUD:Destroy(status)
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

local themeConVar = CreateClientConVar("gry_hud_theme", "blue", true, false, "HUD colours: blue, default, white, orange or custom (gry_hud_color_*)")

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

-- The theme made of the gry_hud_color_* settings (the blue colour stands in for a setting that cannot be read).
function Module.CustomTheme()
	local result = {}

	for part, convar in pairs(CUSTOM_CONVARS) do
		result[part] = Module.ParseColour(convar:GetString()) or Module.Themes.blue[part]
	end

	return result
end

-- Chooses the colours (blue, default, white, orange, custom) of the HUD drawn from now on.
function Module.SetTheme(name)
	if name == "custom" then
		Module.Theme = Module.CustomTheme()
	else
		Module.Theme = Module.Themes[name] or Module.Themes.blue
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

-- The icons the movie has for the weapon above the grenade (the labels of its AmmoMode clip).
local FIRE_MODE_ICONS = {}

for _, label in ipairs({"Single", "Burst", "Auto", "Grenade", "Incendiary", "Tranquilizer", "infinity", "Shotgun",
	"Narrow", "Mine", "Repairkit", "Moac", "Moar", "TACCannon", "C4", "Gauss", "Gunner", "Missle", "Mounted",
	"NoGun", "Claymore"}) do
	FIRE_MODE_ICONS[label] = true
end

-- The stock weapons are written in C++: no Primary table to read, so their icon is listed here.
local STOCK_WEAPON_ICON = {
	weapon_pistol = "Single", weapon_357 = "Single", weapon_crossbow = "Single",
	weapon_smg1 = "Auto", weapon_ar2 = "Auto", weapon_flechettegun = "Auto",
	weapon_shotgun = "Shotgun", weapon_rpg = "Missle", weapon_frag = "Grenade", weapon_slam = "Mine",
	weapon_medkit = "Repairkit",
	weapon_crowbar = "NoGun", weapon_stunstick = "NoGun", weapon_physcannon = "NoGun", weapon_physgun = "NoGun",
	weapon_fists = "NoGun", gmod_tool = "NoGun", gmod_camera = "NoGun", weapon_bugbait = "NoGun"
}

local resolvers = {}

-- Weapon bases that keep their fire mode in their own fields can say how to read it: fn(weapon) returns one
-- of the movie's icon labels, or nil when this weapon is not theirs. Returns a function that removes it.
function Module.AddFireModeResolver(fn)
	resolvers[#resolvers + 1] = fn

	return function()
		for i, other in ipairs(resolvers) do
			if other == fn then
				table.remove(resolvers, i)

				return
			end
		end
	end
end

-- Readers for the weapon bases that keep their fire mode in their own fields (read from their source code).
-- A safety catch shows the single shot icon: the weapon is not an automatic one at that moment.

-- ARC9: GetCurrentFiremode() is the Mode number: below 0 automatic, 0 safety, 1 semi, above 1 a burst.
Module.AddFireModeResolver(function(weapon)
	if weapon.ARC9 ~= true or not weapon.GetCurrentFiremode then
		return nil
	end

	if weapon.GetUBGL and weapon:GetUBGL() then
		return "Grenade"
	end

	local mode = weapon:GetCurrentFiremode()

	if mode < 0 then
		return "Auto"
	end

	return mode > 1 and "Burst" or "Single"
end)

-- ArcCW: GetCurrentFiremode() is a table whose Mode is the other way round: 2 or more automatic, 1 semi,
-- 0 safety, negative a burst.
Module.AddFireModeResolver(function(weapon)
	if weapon.ArcCW ~= true or not weapon.GetCurrentFiremode then
		return nil
	end

	if weapon.GetInUBGL and weapon:GetInUBGL() then
		return "Grenade"
	end

	local current = weapon:GetCurrentFiremode()
	local mode = current and current.Mode or 1

	if mode >= 2 then
		return "Auto"
	end

	return mode < 0 and "Burst" or "Single"
end)

-- A mode kept as a string ("auto", "3burst", "Automatic", "Safe"...): TFA, CW 2.0 and FA:S 2.0.
local function modeFromName(name)
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

-- TFA: GetFireMode() is an index into FireModes, a list of names.
Module.AddFireModeResolver(function(weapon)
	if weapon.IsTFAWeapon ~= true or not weapon.GetFireMode or not weapon.FireModes then
		return nil
	end

	return modeFromName(weapon.FireModes[weapon:GetFireMode()])
end)

-- M9K: GetAutomatic(); its shotguns have their own base.
local M9K_BASES = {bobs_gun_base = true, bobs_scoped_base = true, bobs_shotty_base = true}

Module.AddFireModeResolver(function(weapon)
	if not M9K_BASES[weapon.Base] or not weapon.GetAutomatic then
		return nil
	end

	if weapon.Base == "bobs_shotty_base" then
		return "Shotgun"
	end

	return weapon:GetAutomatic() and "Auto" or "Single"
end)

-- CW 2.0 and FA:S 2.0: FireMode is a string the server sends when the player changes it (nil until it arrives).
Module.AddFireModeResolver(function(weapon)
	if weapon.CW20Weapon ~= true and weapon.IsFAS2Weapon ~= true then
		return nil
	end

	return modeFromName(weapon.FireMode)
end)

-- The icon for what the player holds: a stock weapon's own icon, else what a registered base says, else the
-- generic SWEP rule (Primary.Automatic: automatic, otherwise one shot at a time).
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

	local class = weapon.GetClass and weapon:GetClass()

	if class and STOCK_WEAPON_ICON[class] then
		return STOCK_WEAPON_ICON[class]
	end

	for _, resolver in ipairs(resolvers) do
		local ok, label = pcall(resolver, weapon)

		if ok and FIRE_MODE_ICONS[label] then
			return label
		end
	end

	local primary = weapon.Primary

	if istable(primary) and primary.Automatic then
		return "Auto"
	end

	return "Single"
end

-- magazine, reserve, magazine size, grenades and fire mode icon of what the player holds. -1 = no ammo system.
function Module.AmmoFor(ply, weapon)
	weapon = validWeapon(weapon)

	local grenades = ply:GetAmmoCount("Grenade")
	local fireMode = Module.FireModeFor(weapon)

	if not weapon or weapon:GetPrimaryAmmoType() < 0 then
		return -1, 0, -1, grenades, fireMode
	end

	local type = weapon:GetPrimaryAmmoType()
	local clip = weapon:Clip1()

	if clip < 0 then
		-- no magazine: the reserve is what is shown
		local count = ply:GetAmmoCount(type)

		return count, 0, count, grenades, fireMode
	end

	return clip, ply:GetAmmoCount(type), math.max(weapon:GetMaxClip1(), clip), grenades, fireMode
end

-- The energy (0 to 100) at which the suit stops: the HUD malfunctions (red) while the bar is empty and reboots
-- once it is back above RECOVER_AT. Between the two, and with no usable value, the state stays as it is.
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

-- Whether the movie is there (the HUD and the other pieces need it).
function Module.Available()
	return Flash.Load(Module.MOVIE) ~= nil
end

-- Whether the HUD is on (gry_hud) and can be drawn.
function Module.Enabled()
	local convar = GetConVar("gry_hud")

	return (not convar or convar:GetBool()) and Module.Available()
end

local hud, panel
local lastTime
local fed = {}

local function feed(ply)
	local maxHealth = ply:GetMaxHealth()
	local health = Module.HealthValue(ply:Health(), maxHealth)

	if fed.health ~= health then
		fed.health = health
		hud:SetHealth(health)
	end

	local energy = Module.EnergyValue(ply:GetNWFloat("GryEnergy"))

	if fed.energy ~= energy then
		fed.energy = energy
		hud:SetEnergy(energy)
	end

	local status = Module.MalfunctionFor(ply:GetNWFloat("GryEnergy"), hud.status)

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

	local mag, reserve, size, grenades, fireMode = Module.AmmoFor(ply, ply:GetActiveWeapon())

	if fed.mag ~= mag or fed.reserve ~= reserve or fed.size ~= size or fed.grenades ~= grenades or fed.fireMode ~= fireMode then
		fed.mag, fed.reserve, fed.size, fed.grenades, fed.fireMode = mag, reserve, size, grenades, fireMode
		hud:SetAmmo(mag, reserve, size, grenades, "explosivegrenade", fireMode)
	end
end

-- gry_xadd spreads the two panels apart (the left one goes left), gry_xdist shifts both.
local function xOffsets()
	local add, distance = GetConVar("gry_xadd"), GetConVar("gry_xdist")
	add, distance = add and add:GetInt() or 0, distance and distance:GetInt() or 0

	return add + distance, distance - add
end

-- The paint hook: nothing while dead or spectating, a fresh HUD after every respawn.
function Module.Paint()
	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() then
		Module.Reset()

		return
	end

	if not hud then
		hud = Module.New(Flash.Load(Module.MOVIE))
		panel = GryMod.FlashRadar and GryMod.FlashRadar.New(Flash.Load(GryMod.FlashRadar.MOVIE))
		fed = {}
		lastTime = nil

		if not hud then
			return
		end
	end

	feed(ply)

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	-- the stage is 1024 x 768, scaled to the screen height; the ammo block sits at the bottom right and the
	-- compass panel at the bottom left, as in the original
	local scale = ScrH() / 768
	local right, left = xOffsets()

	hud:Update(dt)

	-- each panel has its own switch (gry_hud_status, gry_hud_radar); a hidden one keeps running so that it is
	-- in the right state when it comes back
	if not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("status") then
		hud:Draw(ScrW() - 1024 * scale + right, ScrH() - 768 * scale, scale)
	end

	if panel then
		local Radar = GryMod.FlashRadar
		panel:SetHeading(Radar.BearingFromYaw(ply:EyeAngles().y))
		panel:SetFOV(ply:GetFOV())
		panel:SetStealth(Radar.StealthFromCount(GryMod.RadarCount))
		panel:Update(dt)

		if not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("radar") then
			panel:Draw(left, ScrH() - 768 * scale, scale)
		end
	end
end

-- Drops the HUD so that the next frame builds a new one (a new theme, a respawn...): the render targets of its
-- groups go back to the pool instead of being kept for ever.
function Module.Reset()
	if hud then
		Flash.ReleaseClip(hud.root)
	end

	if panel then
		Flash.ReleaseClip(panel.root)
	end

	hud, panel = nil, nil
end

-- Adds or removes the paint hook; returns whether this style is the one being drawn.
function Module.Apply(enabled)
	local active = enabled and Module.Available()

	if active then
		hook.Add("HUDPaint", "GRYFLASHHUD", Module.Paint)
	else
		hook.Remove("HUDPaint", "GRYFLASHHUD")
		Module.Reset()
	end

	return active
end

-- Drops every piece of the interface so that the next frame builds them again (a new theme).
function Module.ResetAll()
	Module.Reset()

	for _, module in ipairs({GryMod.FlashMenu, GryMod.FlashBinoculars, GryMod.FlashGrenade, GryMod.FlashCrosshair, GryMod.FlashBoot}) do
		if module and module.Reset then
			module.Reset()
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

