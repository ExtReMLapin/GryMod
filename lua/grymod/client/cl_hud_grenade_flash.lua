-- The grenade warning drawn from the original Scaleform movie (HUD_GrenadeDetect), see cl_flash.lua. A red
-- hexagon follows a grenade coming at the player, with its type and its distance; it shrinks with the distance. The
-- movie's functions (showGrenadeDetector, hideGrenadeDetector, setDistance, setGrenadeType) are ported by hand; the
-- game's rules are from its code (research notes: research-ui/NOTES.md). What is not known from the original and
-- chosen here: the range, and which projectiles count (the Half-Life 2 grenade, rifle grenade and rocket).

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Grenade = {}
GryMod.FlashGrenade = Grenade

Grenade.MOVIE = "hud_grenadedetect"

-- Metres from which a grenade is warned about (not in the original code we could read).
Grenade.RANGE = 60

-- Nothing is warned about within this distance of the eye: a grenade that leaves the hand appears 0.7 m from the eye
-- (the one thrown by weapon_frag) or at 0.9 m (a picked up one that is let go) and is 3 m away a tenth of a second
-- later (measured), so the player's own throw does not blink at the hand. A projectile that close is on top of the
-- player: the warning has nothing left to tell.
Grenade.MIN_OWN = 1

local STAGE_W, STAGE_H = 1366, 768
local HALF_ICON = 18 -- stage pixels from the icon's corner to the centre of its hexagon, at full size
local EDGE = 0.03 -- the screen position is held between 3 and 97 percent
local OPEN_LAST_FRAME = 27

local TYPES = {
	npc_grenade_frag = "FRAG GRENADE",
	grenade_ar2 = "RIFLE GRENADE",
	rpg_missile = "MISSILE",
	grenade_helicopter = "BOMB",
	combine_mine = "MINE",
	prop_combine_ball = "ENERGY BALL"
}

function Grenade.TypeFor(class)
	return TYPES[class]
end

-- The size of the icon in percent for a distance in metres: 100 minus 1.5 a metre, never under 45.
function Grenade.SizeFor(metres)
	return math.max(45, 100 - metres * 1.5)
end

-- The stage position of the icon's corner for a point of the screen (the stage is scaled to the screen height and
-- centred). The icon hangs from its corner and shrinks towards it with the distance, so the hexagon's centre is
-- 18 * size from the corner: that centre is what lands on the point.
function Grenade.StagePosition(screenX, screenY, screenW, screenH, metres)
	local scale = screenH / STAGE_H
	local half = HALF_ICON * Grenade.SizeFor(metres or 0) / 100
	screenX = math.Clamp(screenX, EDGE * screenW, (1 - EDGE) * screenW)

	return (screenX - (screenW - STAGE_W * scale) / 2) / scale - half, screenY / scale - half
end

-- The nearest of the candidates ({class, metres, onScreen, own, armed}) that deserves a warning, or nil. `armed` is
-- the server's mark (sv_grenade.lua): true for a projectile that is active and not held in the player's hands, so an
-- inert one (lying around, a mine on the ground) and the one in the hands are not warned about, unless armedOnly is
-- false (the switch gry_grenade_armed_only, for debugging). The player's own thrown grenade is warned about like an
-- enemy's, once it is more than MIN_OWN from the eye.
function Grenade.Pick(candidates, armedOnly)
	local best

	for _, c in ipairs(candidates or {}) do
		if TYPES[c.class] and c.onScreen and c.metres >= Grenade.MIN_OWN and c.metres <= Grenade.RANGE and (armedOnly == false or c.armed) and (not best or c.metres < best.metres) then
			best = c
		end
	end

	return best
end

local Instance = {}
Instance.__index = Instance

function Grenade.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local icon = root:Find("Root.GrenadeDetect")

	if not icon then
		return nil
	end

	return setmetatable({root = root, icon = icon, shown = false, metres = 0, type = "", x = 0, y = 0}, Instance)
end

function Instance:IsShown()
	return self.shown
end

-- showGrenadeDetector(): the icon plays its opening from "open".
function Instance:Show()
	if self.shown then
		return
	end

	self.shown = true
	self.icon:GotoAndPlay("open")
	self:_apply()
end

-- hideGrenadeDetector()
function Instance:Hide()
	self.shown = false
end

-- setDistance("34.06M"): the text, the "update" animation of the distance and the size: 100 percent minus 1.5 a
-- metre, never under 45.
function Instance:SetDistance(metres)
	self.metres = metres
	self:_applyDistance(true)
end

function Instance:SetType(text)
	self.type = text
	self:_applyType()
end

-- Where the game puts the icon each frame (stage pixels of the icon's corner).
function Instance:SetPosition(x, y)
	self.x, self.y = x, y
	self.icon:SetX(x)
	self.icon:SetY(y)
end

-- The movie keeps the shown distance in a text field of the root (setDistance writes _root.TargetDistance.text) and
-- the first frame of the Distance clip copies it into its own field (this.TargetDistance.text = _root.TargetDistance.text):
-- every time the clip is recreated, by the "update" animation or by the opening, its field is given the distance again.
-- The converted movie does not carry that copy, so it is done here: the text is held in the instance and written
-- into the fields whenever they are not what it says (the field of the type goes through the same rebuilds).
function Instance:_syncFields()
	local distance = self.icon:Child("Distance")

	if distance and self.distanceText then
		distance:SetText("TargetDistance", self.distanceText)
	end

	local text = self.icon:Child("Text")

	if text then
		text:SetText("GrenadeText", self.type)
	end
end

function Instance:_applyDistance(update)
	local distance = self.icon:Child("Distance")

	if distance then
		local text = string.format("%.2fM", self.metres)
		local changed = text ~= self.distanceText
		self.distanceText = text

		-- the "update" animation plays when the shown distance changes, not at every frame
		if update and changed then
			distance:GotoAndPlay("update")
		end

		-- the clip may have gone back to its first frame: its field takes the distance again
		distance:SetText("TargetDistance", text)
	end

	local size = Grenade.SizeFor(self.metres)
	self.icon:SetScale(size, size)
end

function Instance:_applyType()
	local text = self.icon:Child("Text")

	if text then
		text:SetText("GrenadeText", self.type)
	end
end

function Instance:_apply()
	self:_applyDistance(false)
	self:_applyType()
	self.icon:SetX(self.x)
	self.icon:SetY(self.y)
end

function Instance:Update(dt)
	if not self.shown then
		return
	end

	self.root:Advance(dt)
	self:_syncFields()

	-- the opening rebuilds the clips: say the values again while it plays
	local frame = self.icon:CurrentFrame()

	if frame ~= self.lastFrame then
		self.lastFrame = frame
		self:_apply()
	end
end

function Instance:Draw(x, y, scale)
	if self.shown then
		Flash.Draw(self.root, x, y, scale)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- In the game: the nearest grenade coming
-- ---------------------------------------------------------------------------------------------------------

local warning
local lastTime
local armedSwitch

-- The HUD is on and so is this piece (gry_hud_grenade).
function Grenade.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("grenade"))
end

local enabled = Grenade.Enabled

-- The grenades in the world are looked for five times a second; their positions are read every frame.
local scanned = {}
local nextScan = 0

local function scan()
	local now = RealTime()

	if now < nextScan then
		return
	end

	nextScan = now + 0.2
	scanned = {}

	for class in pairs(TYPES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			scanned[#scanned + 1] = ent
		end
	end
end

-- What Pick reads of an entity: its class, the distance in metres from the eye, whether it is on the screen (the point
-- is its projection), the server's mark (sv_grenade.lua) and whether it is the player's own.
function Grenade.Candidate(ent, ply, point)
	point = point or ent:WorldSpaceCenter():ToScreen()
	local owner = ent:GetOwner()

	return {
		ent = ent,
		class = ent:GetClass(),
		metres = ply:EyePos():Distance(ent:GetPos()) / 52.49,
		onScreen = point.visible,
		own = IsValid(owner) and owner == ply,
		armed = ent:GetNWBool("GryArmed"),
		screen = point
	}
end

local function candidates(ply)
	local list = {}

	for _, ent in ipairs(scanned) do
		if IsValid(ent) then
			list[#list + 1] = Grenade.Candidate(ent, ply)
		end
	end

	return list
end

hook.Add("HUDPaint", "GRYGRENADEWARNING", function()
	local ply = LocalPlayer()

	-- dead, or the HUD is off: the warning goes away, and plays its opening again when it comes back
	if not enabled() or not IsValid(ply) or not ply:Alive() then
		if warning then
			warning:Hide()
		end

		return
	end

	scan()
	-- the server's switch (a server without the module marks nothing: then every projectile counts)
	armedSwitch = armedSwitch or GetConVar("gry_grenade_armed_only")
	local switch = armedSwitch
	local best = Grenade.Pick(candidates(ply), switch ~= nil and switch:GetBool())

	if not best then
		if warning then
			warning:Hide()
		end

		return
	end

	if not warning then
		warning = Grenade.New(Flash.Load(Grenade.MOVIE))

		if not warning then
			return
		end
	end

	warning:Show()
	warning:SetType(TYPES[best.class])
	warning:SetDistance(best.metres)
	warning:SetPosition(Grenade.StagePosition(best.screen.x, best.screen.y, ScrW(), ScrH(), best.metres))

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now
	warning:Update(dt)

	local scale = ScrH() / STAGE_H
	warning:Draw((ScrW() - STAGE_W * scale) / 2, 0, scale)
end)

function Grenade.Reset()
	if warning then
		Flash.ReleaseClip(warning.root)
	end

	warning = nil
end
