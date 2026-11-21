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

-- ---------------------------------------------------------------------------------------------------------
-- The game's rules, as pure functions
-- ---------------------------------------------------------------------------------------------------------

-- The crosshair the original game shows by default in its profile (hud_crosshair).
Cross.DEFAULT_STYLE = 6

-- Weapons that show no crosshair in the original (fists, the LAW).
local HIDDEN_WEAPONS = {weapon_fists = true, weapon_rpg = true}

-- The crosshair number for a style: 0 (none) when there is no weapon, the weapon hides it (or draws its own: its
-- DrawCrosshair is false) or the player zooms; a style that is not one of the movie's 13 gives the default.
function Cross.IndexFor(style, class, weaponDraws, zoomed)
	if not class or HIDDEN_WEAPONS[class] or not weaponDraws or zoomed then
		return 0
	end

	if type(style) ~= "number" or style ~= style or style < 1 or style > Cross.COUNT then
		return Cross.DEFAULT_STYLE
	end

	return math.floor(style)
end

-- The spread (0 to 1) the crosshair is heading for: half of it at a run, more in the air and right after a shot,
-- less crouched. The original reads the weapon's spread; Garry's Mod weapons have no common one, so this is
-- estimated from what the player does.
function Cross.SpreadTarget(speedFraction, onGround, crouching, kick)
	local spread = 0.5 * math.Clamp(speedFraction or 0, 0, 1)

	if not onGround then
		spread = spread + 0.35
	end

	if crouching then
		spread = spread * 0.5
	end

	return math.Clamp(spread + (kick or 0), 0, 1)
end

-- The original eases the value towards its target at a rate of 20 a second.
function Cross.Ease(current, target, dt)
	return current + (target - current) * (1 - math.exp(-20 * math.max(dt, 0)))
end

-- The arcs (1 north, 2 east, 3 south, 4 west of the original's world) for damage that came from the shooter: the
-- direction from the shooter to the player, 0.35 of an axis is enough, two arcs for a diagonal, all four for no
-- horizontal direction. The original's north is the +X of the game here (its yaw and the game's turn the same way).
function Cross.ArcsFor(playerPos, shooterPos)
	local d = playerPos - shooterPos
	local length = d:Length()
	local arcs = {}

	if length > 1e-6 then
		d = d / length
		-- the original's frame: x east, y north
		local x, y = -d.y, d.x

		if math.abs(y) > 0.35 then
			arcs[#arcs + 1] = y > 0 and 1 or 3
		end

		if math.abs(x) > 0.35 then
			arcs[#arcs + 1] = x > 0 and 2 or 4
		end
	end

	if #arcs == 0 then
		arcs = {1, 2, 3, 4}
	end

	return arcs
end

-- The rotation of the arcs' compass: the yaw of the view plus 180 degrees.
function Cross.ArcRotation(yaw)
	return (yaw + 180) % 360
end

local USE_CLASSES = {
	func_button = true, func_rot_button = true, momentary_rot_button = true, prop_door_rotating = true,
	func_door_rotating = true, func_useableladder = true, prop_physics = true, prop_physics_multiplayer = true,
	prop_ragdoll = true
}

-- setUsable's mode for what the player aims at: 1 something can be used or taken, 2 it can not (a weapon the
-- player already has), 0 nothing.
function Cross.UsableFor(ent, ply)
	if not ent or not IsValid(ent) then
		return 0
	end

	local class = ent:GetClass()

	if ent:IsWeapon() then
		return ply and ply:HasWeapon(class) and 2 or 1
	end

	if string.sub(class, 1, 5) == "item_" or USE_CLASSES[class] then
		return 1
	end

	return 0
end

local FRIENDLY_NPCS = {
	npc_citizen = true, npc_alyx = true, npc_barney = true, npc_eli = true, npc_kleiner = true, npc_mossman = true,
	npc_monk = true, npc_odessa = true, npc_magnusson = true, npc_dog = true, npc_vortigaunt = true
}

-- Whether what the player aims at is an ally: a player of the same team (when the game has teams), or one of the
-- Half-Life 2 rebels' NPCs. The original asks its game rules; Garry's Mod has no common answer.
function Cross.IsFriendly(ent, ply)
	if not ent or not IsValid(ent) then
		return false
	end

	if ent:IsPlayer() then
		local team = ent:Team()

		return ent ~= ply and ply ~= nil and team == ply:Team() and team ~= 1001 and team ~= 1002
	end

	return ent:IsNPC() and FRIENDLY_NPCS[ent:GetClass()] == true
end

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

-- The player is hurt by something at shooterPos: the arcs on that side, turned with the view for 2 seconds.
function Instance:OnDamage(playerPos, shooterPos, yaw, now)
	for _, arc in ipairs(Cross.ArcsFor(playerPos, shooterPos)) do
		self:SetDamageDirection(arc)
	end

	self.damageAt = now
	self:SetViewYaw(yaw, now)
end

-- The yaw of the view, every frame: the arcs' compass turns with it for 2 seconds after a hit.
function Instance:SetViewYaw(yaw, now)
	local arcs = self.root:Child("DamageDirection")

	if arcs and self.damageAt and now - self.damageAt < 2 then
		arcs:SetRotation(Cross.ArcRotation(yaw))
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

-- ---------------------------------------------------------------------------------------------------------
-- In the game
-- ---------------------------------------------------------------------------------------------------------

Cross.FRIENDLY_MOVIE = "hud_friendlycross"

local STYLE_CONVAR = CreateClientConVar("gry_hud_crosshair_style", tostring(Cross.DEFAULT_STYLE), true, false,
	"Crosshair style, 1 to 13 (the original's profile uses 6)")

local instance, friendly
local lastTime
local spread, kick, lastNextFire = 0, 0, 0
local usableMode, friendlyShown = 0, false
local nextScan = 0

-- Whether the crosshair is on (gry_hud, gry_hud_crosshair) and its movie is there.
function Cross.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled()
		and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("crosshair"))
		and Flash.Load(Cross.MOVIE) ~= nil
end

function Cross.Current()
	return instance
end

-- The server says the player hit something alive (the original's indicateHit).
function Cross.NotifyHit()
	if instance and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("hit")) then
		instance:Hit()
	end
end

-- The server says something hurt the player from shooterPos: the arcs of the damage direction.
function Cross.NotifyDamage(shooterPos)
	local ply = LocalPlayer()

	if instance and IsValid(ply) and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("damage")) then
		instance:OnDamage(ply:GetPos(), shooterPos, ply:EyeAngles().y, CurTime())
	end
end

net.Receive("gry_hit", function()
	Cross.NotifyHit()
end)

net.Receive("gry_damage_dir", function()
	Cross.NotifyDamage(net.ReadVector())
end)

-- The crosshair is not wanted while the suit is down, the quick menu is up, or the player is in a vehicle.
local function hidden(ply)
	return (GryMod.FlashBoot and GryMod.FlashBoot.IsLost())
		or (GryMod.FlashMenu and GryMod.FlashMenu.IsOpen())
		or ply:InVehicle()
end

local function zooming(ply)
	if GryMod.FlashBinoculars and GryMod.FlashBinoculars.Wanted then
		return GryMod.FlashBinoculars.Wanted(ply)
	end

	return ply:KeyDown(IN_ZOOM)
end

-- What the player aims at, looked for ten times a second: the mode of setUsable and the friendly cross.
local function scan(ply)
	local now = RealTime()

	if now < nextScan then
		return
	end

	nextScan = now + 0.1

	local trace = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 110,
		filter = ply
	})
	local mode = trace.Entity and Cross.UsableFor(trace.Entity, ply) or 0

	if mode ~= usableMode then
		usableMode = mode
		instance:SetUsable(mode)
	end

	local far = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 3000,
		filter = ply
	})
	local isFriendly = far.Entity and Cross.IsFriendly(far.Entity, ply) or false

	if isFriendly and not friendlyShown and friendly then
		friendly:GotoAndPlay("restart")
	end

	friendlyShown = isFriendly
end

-- The spread: the original reads the weapon's, here it comes from what the player does (see SpreadTarget).
local function updateSpread(ply, weapon, dt)
	local nextFire = IsValid(weapon) and weapon:GetNextPrimaryFire() or 0

	if nextFire > lastNextFire + 0.001 then
		kick = math.min(kick + 0.25, 1)
	end

	lastNextFire = nextFire
	kick = math.max(0, kick - 1.5 * dt)

	local speed = ply:GetVelocity():Length2D() / math.max(ply:GetRunSpeed(), 1)

	spread = Cross.Ease(spread, Cross.SpreadTarget(speed, ply:OnGround(), ply:Crouching(), kick), dt)
end

function Cross.Paint()
	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() or not Cross.Enabled() then
		return
	end

	if not instance then
		instance = Cross.New(Flash.Load(Cross.MOVIE))
		friendly = nil
		local movie = Flash.Load(Cross.FRIENDLY_MOVIE)
		local holder = movie and Flash.NewRoot(movie, GryMod.FlashHUD.Theme)
		friendly = holder and holder:Child("Root") and {root = holder, clip = holder:Child("Root")} or nil

		if not instance then
			return
		end

		lastTime, spread, kick, usableMode, friendlyShown = nil, 0, 0, 0, false
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	local weapon = ply:GetActiveWeapon()
	local class = IsValid(weapon) and weapon:GetClass() or nil
	local draws = not IsValid(weapon) or weapon.DrawCrosshair ~= false
	local index = Cross.IndexFor(STYLE_CONVAR:GetInt(), class, draws, zooming(ply))

	if hidden(ply) then
		index = 0
	end

	if index ~= instance.index then
		instance:SetCrosshair(index)
		-- a crosshair that is just shown has its usable state said again
		usableMode = 0
		nextScan = 0
	end

	updateSpread(ply, weapon, dt)
	instance:SetRecoil(index >= 11 and spread * 40 or spread)
	instance:SetViewYaw(ply:EyeAngles().y, CurTime())
	scan(ply)
	instance:Update(dt)

	local scale = ScrH() / STAGE_H
	local x = (ScrW() - STAGE_W * scale) / 2

	instance:Draw(x, 0, scale)

	if friendly and friendlyShown and index ~= 0 then
		friendly.root:Advance(dt)
		Flash.Draw(friendly.root, x, 0, scale)
	end
end

-- Drops the crosshair so that the next frame builds a new one (a new theme, a respawn).
function Cross.Reset()
	if instance then
		Flash.ReleaseClip(instance.root)
	end

	if friendly then
		Flash.ReleaseClip(friendly.root)
	end

	instance, friendly = nil, nil
	lastTime, spread, kick, usableMode, friendlyShown = nil, 0, 0, 0, false
end

hook.Add("HUDPaint", "GRYFLASHCROSSHAIR", Cross.Paint)

-- the Half-Life 2 crosshair stays away while ours is on
hook.Add("HUDShouldDraw", "GRYCROSSHAIRHIDE", function(name)
	if name == "CHudCrosshair" and Cross.Enabled() then
		return false
	end
end)
