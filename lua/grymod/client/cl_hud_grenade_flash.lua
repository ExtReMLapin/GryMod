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

local STAGE_W, STAGE_H = 1366, 768
local HALF_ICON = 18 -- screen pixels: the game puts the icon's corner this far before the projected point
local EDGE = 0.03 -- the screen position is held between 3 and 97 percent
local OPEN_LAST_FRAME = 27

local TYPES = {
	npc_grenade_frag = "FRAG GRENADE",
	grenade_ar2 = "RIFLE GRENADE",
	rpg_missile = "MISSILE",
	grenade_helicopter = "BOMB"
}

function Grenade.TypeFor(class)
	return TYPES[class]
end

-- The stage position of the icon for a point of the screen (the stage is scaled to the screen height and centred).
function Grenade.StagePosition(screenX, screenY, screenW, screenH)
	local scale = screenH / STAGE_H
	screenX = math.Clamp(screenX, EDGE * screenW, (1 - EDGE) * screenW)

	return (screenX - (screenW - STAGE_W * scale) / 2) / scale - HALF_ICON / scale, screenY / scale - HALF_ICON / scale
end

-- The nearest of the candidates ({class, metres, onScreen, own}) that deserves a warning, or nil.
function Grenade.Pick(candidates)
	local best

	for _, c in ipairs(candidates or {}) do
		if TYPES[c.class] and c.onScreen and not c.own and c.metres <= Grenade.RANGE and (not best or c.metres < best.metres) then
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

function Instance:_applyDistance(update)
	local distance = self.icon:Child("Distance")

	if distance then
		distance:SetText("TargetDistance", string.format("%.2fM", self.metres))

		if update then
			distance:GotoAndPlay("update")
		end
	end

	local size = math.max(45, 100 - self.metres * 1.5)
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

local function enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled()
end

local function candidates(ply)
	local list = {}
	local eye = ply:EyePos()

	for class in pairs(TYPES) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			local point = ent:WorldSpaceCenter():ToScreen()
			local owner = ent:GetOwner()

			list[#list + 1] = {
				ent = ent,
				class = class,
				metres = eye:Distance(ent:GetPos()) / 52.49,
				onScreen = point.visible,
				own = IsValid(owner) and owner == ply,
				screen = point
			}
		end
	end

	return list
end

hook.Add("HUDPaint", "GRYGRENADEWARNING", function()
	if not enabled() then
		return
	end

	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() then
		return
	end

	local best = Grenade.Pick(candidates(ply))

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
	warning:SetPosition(Grenade.StagePosition(best.screen.x, best.screen.y, ScrW(), ScrH()))

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
