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

-- The theme colours the movie's colour-set clips copy (the original sets them from the game's HUD colour
-- settings; these are the blue-green ones of the retail game).
Module.Theme = {
	Line = {150, 205, 230},
	Over = {170, 220, 240},
	Text = {200, 235, 250}
}

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
	self.icons:GotoAndStop(frame)

	if self.status == 1 then
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

	clip:GotoAndStop(colour)

	local text = clip:Child("NumberText")

	if text then
		text:SetText("NumberText", value)
	end

	local blink = clip:Child("NumberText_blink")

	if blink then
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
-- GryMod's values, and the paint hook (the "crysis" style of gry_hud_style; "classic" is the older HUD)
-- ---------------------------------------------------------------------------------------------------------

local styleConVar = CreateClientConVar("gry_hud_style", "classic", true, false)

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

-- magazine, reserve, magazine size, grenades and fire mode of what the player holds. -1 = no ammo system.
function Module.AmmoFor(ply, weapon)
	local grenades = ply:GetAmmoCount("Grenade")

	if not weapon or weapon:GetPrimaryAmmoType() < 0 then
		return -1, 0, -1, grenades, "Single"
	end

	local fireMode = weapon.Primary and weapon.Primary.Automatic and "Auto" or "Single"
	local type = weapon:GetPrimaryAmmoType()
	local clip = weapon:Clip1()

	if clip < 0 then
		-- no magazine: the reserve is what is shown
		local count = ply:GetAmmoCount(type)

		return count, 0, count, grenades, fireMode
	end

	return clip, ply:GetAmmoCount(type), math.max(weapon:GetMaxClip1(), clip), grenades, fireMode
end

function Module.Enabled()
	return styleConVar:GetString() == "crysis" and Flash.Load(Module.MOVIE) ~= nil
end

local hud
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

local function xOffset()
	local add, distance = GetConVar("gry_xadd"), GetConVar("gry_xdist")

	return (add and add:GetInt() or 0) + (distance and distance:GetInt() or 0)
end

-- The paint hook: nothing while dead or spectating, a fresh HUD after every respawn.
function Module.Paint()
	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() then
		hud = nil

		return
	end

	if not hud then
		hud = Module.New(Flash.Load(Module.MOVIE))
		fed = {}
		lastTime = nil

		if not hud then
			return
		end
	end

	feed(ply)

	local now = RealTime()
	hud:Update(math.min(now - (lastTime or now), 0.1))
	lastTime = now

	-- the stage is 1024 x 768, scaled to the screen height and anchored to the bottom right
	local scale = ScrH() / 768
	hud:Draw(ScrW() - 1024 * scale + xOffset(), ScrH() - 768 * scale, scale)
end

-- Adds or removes the paint hook; returns whether this style is the one being drawn.
function Module.Apply(enabled)
	local active = enabled and Module.Enabled()

	if active then
		hook.Add("HUDPaint", "GRYFLASHHUD", Module.Paint)
	else
		hook.Remove("HUDPaint", "GRYFLASHHUD")
		hud = nil
	end

	return active
end

cvars.AddChangeCallback("gry_hud_style", function()
	if GryMod.ApplyHUD then
		GryMod.ApplyHUD()
	end
end, "GryModHUDStyle")
