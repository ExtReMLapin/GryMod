-- The crosshair drawn from the original Scaleform movie (HUD_Crosshair), see cl_flash.lua. The movie holds 13
-- crosshairs (one per frame of its Root clip), their spread, the "usable" animations, the hit marker and the four
-- damage arcs around the centre. Its functions (setCrossHair, setRecoil, setUsable, indicateHit,
-- setDamageDirection, clearDamageDirection, setVisible, setOpacity) are ported by hand; the game's rules are from
-- its code (research notes: research-ui/NOTES.md, research-ui2/crosshair-reboot.md).

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Cross = {}
GryMod.FlashCrosshair = Cross

Cross.MOVIE = "hud_crosshair"
Cross.DEFAULT = 10
Cross.COUNT = 13

local STAGE_W, STAGE_H = 1024, 768

local Instance = {}
Instance.__index = Instance

-- The spread of each crosshair: the original's setRecoil of that frame, written for the clip of the crosshair.
local function at(cross, path, x, y)
	local clip = cross:Find(path)

	if not clip then
		return
	end

	if x then
		clip:SetX(x)
	end

	if y then
		clip:SetY(y)
	end
end

local function box(cross, a, b, c, d, r)
	at(cross, a, -r)
	at(cross, b, r)
	at(cross, c, nil, r)
	at(cross, d, nil, -r)
end

local function corners(cross, offset)
	at(cross, "LineTR", offset, -offset)
	at(cross, "LineTL", -offset, -offset)
	at(cross, "LineBR", offset, offset)
	at(cross, "LineBL", -offset, offset)
end

local RECOIL = {
	[1] = function(cross, r)
		r = 9.5 + r * 42
		at(cross, "LineL", -r)
		at(cross, "LineR", r)
		at(cross, "LineD", nil, r)
	end,
	[2] = function(cross, r)
		r = 100 + r * 200
		local line = cross:Find("Line")

		if line then
			line:SetScale(r, r)
		end
	end,
	[3] = function(cross, r)
		r = 11 + r * 42
		corners(cross, r)
	end,
	[4] = function(cross, r)
		box(cross, "LineL", "LineR", "LineD", "LineU", 8 + r * 52)
	end,
	[5] = function(cross, r)
		r = 20 + r * 32
		local line = cross:Find("Line2")

		if line then
			line:SetScale(50 + 2.5 * r, 50 + 2.5 * r)
		end
	end,
	[6] = function(cross, r)
		corners(cross, 10 + r * 48)
	end,
	[7] = function(cross, r)
		box(cross, "LineL", "LineR", "LineD", "LineU", 9.5 + r * 56)
	end,
	-- the original shakes the line once the value is above 20
	[8] = function(cross, r)
		if r > 20 then
			at(cross, "Line", (r - 20) * (math.random() * 3 - 1.5), (r - 20) * (math.random() * 3 - 1.5))
		else
			at(cross, "Line", 0, 0)
		end
	end,
	[11] = function(cross, r)
		r = math.max(r, 22)
		local base = "Lines.Colorset."
		at(cross, base .. "Line1", -r, -r + 5)
		at(cross, base .. "Line2", r, -r + 5)
		at(cross, base .. "Line3", -r, r - 5)
		at(cross, base .. "Line4", r, r - 5)
	end,
	[12] = function(cross, r)
		r = math.max(r, 10)
		local base = "Lines.Colorset."
		at(cross, base .. "LineTop", nil, -r)
		at(cross, base .. "LineRight", r)
		at(cross, base .. "LineBottom", nil, r)
		at(cross, base .. "LineLeft", -r)
	end,
	[13] = function(cross, r)
		r = math.max(r, 12)
		local base = "Lines.Colorset."
		at(cross, base .. "Line1", -r)
		at(cross, base .. "Line2", r)
	end
}

-- The clips that blink when something is hit (indicateHit), by crosshair.
local COLORSET = "Lines.Colorset."
local HIT = {
	[1] = {"LineL", "LineR", "LineD", "Pointer"},
	[2] = {"Line", "Pointer"},
	[3] = {"Pointer", "LineTL", "LineTR", "LineBL", "LineBR"},
	[4] = {"LineU", "LineL", "LineR", "LineD", "Pointer", "Line"},
	[5] = {"Line1", "Line2", "Pointer"},
	[6] = {"Pointer", "LineTL", "LineTR", "LineBL", "LineBR"},
	[7] = {"LineU", "LineL", "LineR", "LineD", "Pointer"},
	[10] = {"Line", "Line2"},
	[11] = {COLORSET .. "Lines", COLORSET .. "Line1", COLORSET .. "Line2", COLORSET .. "Line3", COLORSET .. "Line4"},
	[12] = {COLORSET .. "Line", COLORSET .. "LineTop", COLORSET .. "LineLeft", COLORSET .. "LineBottom", COLORSET .. "LineRight"},
	[13] = {COLORSET .. "Line1", COLORSET .. "Line2", COLORSET .. "Lines"}
}

-- setUsable(mode): the frame the crosshair is on decides where it goes (the original's if chains).
-- 1: something can be used, the crosshair opens; 0: nothing, it closes; 2: the second animation.
local USABLE = {
	[1] = {[1] = 2, [13] = 2, [8] = 6, [9] = 5, [10] = 4, [11] = 3, [12] = 2},
	[0] = {[2] = 12, [3] = 11, [4] = 10, [5] = 9, [6] = 8, [7] = 8, [14] = 20, [15] = 23, [16] = 22, [17] = 21, [18] = 20, [19] = 20},
	[2] = {[1] = 14, [13] = 14, [25] = 14, [14] = 19, [15] = 18, [16] = 17, [17] = 16, [18] = 15}
}

-- A crosshair from a converted movie (nil when the movie is missing).
function Cross.New(movie, theme)
	if not movie then
		return nil
	end

	local root = Flash.NewRoot(movie, theme or (GryMod.FlashHUD and GryMod.FlashHUD.Theme))
	local holder = root:Child("Root")

	if not holder then
		return nil
	end

	-- the movie's colour holder never shows
	local line = root:Child("Line")

	if line then
		line:SetVisible(false)
	end

	local this = setmetatable({root = root, holder = holder, recoil = 11.25, visible = true, opacity = 1}, Instance)
	this:SetCrosshair(Cross.DEFAULT)

	return this
end

function Instance:IsShown()
	return self.visible
end

-- setVisible(bool)
function Instance:SetVisible(visible)
	self.visible = visible and true or false
end

-- setOpacity(0 to 1): the alpha of the whole crosshair
function Instance:SetOpacity(opacity)
	self.opacity = opacity
	self.holder:SetAlpha(opacity * 100)
end

-- setCrossHair(n): 1 to 13 shows that crosshair, 0 shows none; anything else is ignored.
function Instance:SetCrosshair(index)
	if type(index) ~= "number" or index ~= index then
		return
	end

	index = math.floor(index)

	if index == 0 then
		self.holder:GotoAndStop("empty")
		self.index, self.current = 0, nil

		return
	end

	if index < 1 or index > Cross.COUNT then
		return
	end

	self.holder:GotoAndStop(index)
	self.index = index
	self.current = self.holder:Child("Crosshair" .. index)
	self:_applyRecoil()
end

-- setRecoil(value): the spread, in the unit each crosshair expects (a fraction for 1 to 7, pixels for 11 to 13).
function Instance:SetRecoil(value)
	if type(value) ~= "number" or value ~= value then
		return
	end

	self.recoil = value
	self:_applyRecoil()
end

function Instance:_applyRecoil()
	local apply = self.current and RECOIL[self.index]

	if apply then
		apply(self.current, self.recoil)
	end
end

-- indicateHit(): the lines of the shown crosshair blink.
function Instance:Hit()
	local paths = self.current and HIT[self.index]

	if not paths then
		return
	end

	for _, path in ipairs(paths) do
		local clip = self.current:Find(path)

		if clip then
			clip:GotoAndPlay("hit")
		end
	end
end

function Instance:SetUsable(mode)
	local current = self.current
	local rules = USABLE[mode]
	local target = current and rules and rules[current:CurrentFrame()]

	if target then
		current:GotoAndPlay(target)
	end
end

-- setDamageDirection(1 to 4): top, right, bottom, left arcs.
function Instance:SetDamageDirection(direction)
	local arcs = self.root:Child("DamageDirection")
	local arc = arcs and math.floor(direction or 0) == direction and arcs:Child("Damage" .. direction)

	if arc and direction >= 1 and direction <= 4 then
		arc:GotoAndPlay("play")
	end
end

function Instance:ClearDamageDirection()
	local arcs = self.root:Child("DamageDirection")

	if not arcs then
		return
	end

	for i = 1, 4 do
		local arc = arcs:Child("Damage" .. i)

		if arc then
			arc:GotoAndStop("stop")
		end
	end
end

function Instance:Update(dt)
	self.root:Advance(dt)
	-- an animation of the crosshair can rebuild its clips: the spread is said again
	self:_applyRecoil()
end

function Instance:Draw(x, y, scale)
	if self.visible then
		Flash.Draw(self.root, x, y, scale)
	end
end
