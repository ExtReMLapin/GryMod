-- The grenade warning drawn from the original Scaleform movie (HUD_GrenadeDetect), see cl_flash.lua. A red
-- hexagon follows a grenade coming at the player, with its type and its distance; it shrinks with the distance. The
-- movie's functions (showGrenadeDetector, hideGrenadeDetector, setDistance, setGrenadeType) are ported by hand; the
-- game's rules are from its code (research notes: research-ui/NOTES.md). What is not known from the original and
-- chosen here: which projectiles count (the Half-Life 2 ones). What the original does NOT do and was added here, each
-- as a setting (docs/superpowers/plans/2026-11-21-grenade-range.md): a range (the original has none: the icon follows
-- the last projectile made anywhere), silence for the projectiles the player fired, and an optional line of sight.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Grenade = {}
GryMod.FlashGrenade = Grenade

Grenade.MOVIE = "hud_grenadedetect"

-- Metres from which a grenade is warned about. CHOICE: the original code has no range at all (read: the per-frame
-- function and the one that picks the projectile test nothing but the screen side). 40 m is a little more than where
-- the icon stops shrinking (36.7 m: 100 percent minus 1.5 a metre, floor 45), the distance the movie was drawn for.
-- The setting gry_grenade_range, 5 to 200.
Grenade.DEFAULT_RANGE = 40
Grenade.MIN_RANGE = 5
Grenade.MAX_RANGE = 200

function Grenade.ClampRange(metres)
	metres = tonumber(metres)

	if not metres then
		return Grenade.DEFAULT_RANGE
	end

	return math.Clamp(metres, Grenade.MIN_RANGE, Grenade.MAX_RANGE)
end

-- A grenade the player threw NEVER warns (the owner's decision: hand grenade included, from the hand or the lob, first or third
-- person, one picked up with the gravity gun and let go again). The server writes who threw each projectile (sv_grenade.lua,
-- GryThrower) and the engine's owner is read too (Grenade.Candidate). Only the setting gry_grenade_own_warn (off) brings back
-- the old rule: the player's own hand grenade warns within this distance (measured: a frag thrown flat goes 15 m at most
-- before it comes back).
Grenade.OWN_WARN_RANGE = 15

-- The projectiles a player FIRES (the `ownMissile` flag of the danger entry in the registry): a missile that leaves, a rifle
-- grenade, an energy ball. They never warn the player, not even with gry_grenade_own_warn. CHOICE: the original warns about them
-- too (nothing there looks at who fired).

-- The line of sight is read at most this often for a projectile, and a view that was lost is kept this long.
Grenade.LOS_EVERY = 0.2
Grenade.LOS_HOLD = 0.5

-- Nothing is warned about within this distance of the eye: a grenade that leaves the hand appears 0.7 m from the eye
-- (the one thrown by weapon_frag) or at 0.9 m (a picked up one that is let go) and is 3 m away a tenth of a second
-- later (measured), so the player's own throw does not blink at the hand. A projectile that close is on top of the
-- player: the warning has nothing left to tell.
Grenade.MIN_OWN = 1

local STAGE_W, STAGE_H = 1366, 768
local HALF_ICON = 18 -- stage pixels from the icon's corner to the centre of its hexagon, at full size
local EDGE = 0.03 -- the screen position is held between 3 and 97 percent
local OPEN_LAST_FRAME = 27

-- Which projectiles are dangerous, what they are called, which ones the player fires, how far each is warned about: all of it is
-- the registry's `danger` field (GryMod.API.RegisterTracked, sh_api_tracked.lua), the stock Half-Life 2 ones are registered as data
-- in sh_api_tracked_hl2.lua and an addon's own go through the same code. The entry that names the class, or nil: none, or no
-- registry (a hot reload of this file).
local function dangerEntry(class)
	local API = GryMod.API

	return API and API.GetDanger and API.GetDanger(class) or nil
end

-- The text the warning shows for a class (the `label` of its danger entry), nil for a class that is not a danger.
function Grenade.TypeFor(class)
	local entry = dangerEntry(class)

	return entry and entry.danger.label or nil
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

-- Whether a candidate ({class, metres, onScreen, own, armed, visible}) deserves a warning. `armed` is the server's mark
-- (sv_grenade.lua): true for a projectile that is active and not held in the player's hands, so an inert one (lying
-- around, a mine on the ground) and the one in the hands are not warned about, unless armedOnly is false (the switch
-- gry_grenade_armed_only, for debugging). opts: range (metres, default DEFAULT_RANGE), ownWarn (true: the player's own hand
-- grenade warns within OWN_WARN_RANGE, the old rule; default false: a grenade the player threw never warns, whatever the
-- distance), los (true: only a projectile seen from the eye, `visible` not false; default false, as in the original, which
-- warns through walls).
function Grenade.Warns(c, armedOnly, opts)
	opts = opts or {}
	local range = opts.range or Grenade.DEFAULT_RANGE
	local entry = dangerEntry(c.class)

	-- only the entries whose indicator is the warning (the grenade-detect film) are drawn here; "marker" and "none" are stored
	if not entry or entry.indicator ~= "warning" then
		return false
	end

	-- the entry's own range can only shorten the player's
	if entry.danger.range and entry.danger.range < range then
		range = entry.danger.range
	end

	if not c.onScreen or c.metres < Grenade.MIN_OWN or c.metres > range then
		return false
	end

	if armedOnly ~= false and not c.armed then
		return false
	end

	if c.own then
		-- what the player threw or fired never warns; with the old rule on, the hand grenade does while it is close
		if entry.danger.ownMissile or not opts.ownWarn or c.metres > Grenade.OWN_WARN_RANGE then
			return false
		end
	end

	if opts.los and c.visible == false then
		return false
	end

	return true
end

-- The nearest of the candidates that deserves a warning (see Warns), or nil.
function Grenade.Pick(candidates, armedOnly, opts)
	local best

	for _, c in ipairs(candidates or {}) do
		if Grenade.Warns(c, armedOnly, opts) and (not best or c.metres < best.metres) then
			best = c
		end
	end

	return best
end

-- The line of sight of one projectile, read through probe() (true: nothing in the way) at most every LOS_EVERY seconds,
-- and kept for LOS_HOLD seconds after it was last seen (a grenade that flickers behind a railing does not blink the
-- warning). `entry` is the projectile's own table, kept by the caller.
function Grenade.LosStep(entry, now, probe)
	if not entry.checked or now - entry.checked >= Grenade.LOS_EVERY then
		entry.checked = now

		if probe() then
			entry.seen = now
		end
	end

	return entry.seen ~= nil and now - entry.seen < Grenade.LOS_HOLD
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

-- The settings (client, saved): the range in metres, the old warning for the player's own hand grenade (off; a new name: a
-- saved gry_grenade_own 1 of the earlier rule must not bring it back), the line of sight (the original warns through walls: off).
local rangeVar = CreateClientConVar("gry_grenade_range", tostring(Grenade.DEFAULT_RANGE), true, false,
	"Distance in metres under which a projectile coming is warned about", Grenade.MIN_RANGE, Grenade.MAX_RANGE)
local ownWarnVar = CreateClientConVar("gry_grenade_own_warn", "0", true, false,
	"1: the player's own hand grenade warns within 15 m (the old rule); 0: a grenade the player threw never warns", 0, 1)
local losVar = CreateClientConVar("gry_grenade_los", "0", true, false,
	"Warn only about a projectile in the line of sight (0: also through walls, as in the original game)", 0, 1)

function Grenade.Options()
	return {range = Grenade.ClampRange(rangeVar:GetFloat()), ownWarn = ownWarnVar:GetBool(), los = losVar:GetBool()}
end

-- The line of sight of the projectiles, one table each (weak: they go with the entity).
local sight = setmetatable({}, {__mode = "k"})

local function lineOfSight(ent, ply)
	local entry = sight[ent]

	if not entry then
		entry = {}
		sight[ent] = entry
	end

	return Grenade.LosStep(entry, RealTime(), function()
		local from, to = ply:EyePos(), ent:WorldSpaceCenter()
		local hit = util.TraceLine({start = from, endpos = to, filter = {ply, ent}, mask = MASK_OPAQUE})

		return not hit.Hit
	end)
end

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

	local API = GryMod.API

	if not API or not API.DangerClasses then
		return
	end

	-- by class, through the registry: the classes that have a danger entry drawn as a warning
	for _, class in ipairs(API.DangerClasses()) do
		if API.GetDanger(class).indicator == "warning" then
			for _, ent in ipairs(ents.FindByClass(class)) do
				scanned[#scanned + 1] = ent
			end
		end
	end
end

-- What Pick reads of an entity: its class, the distance in metres from the eye, whether it is on the screen (the point
-- is its projection), the server's mark (sv_grenade.lua), whether it is the player's own (the engine's owner, or the
-- thrower the server writes) and the line of sight when it was read (`visible`: true, false, or nil when not asked).
function Grenade.Candidate(ent, ply, point, visible)
	point = point or ent:WorldSpaceCenter():ToScreen()
	local owner = ent:GetOwner()
	local thrower = ent:GetNWEntity("GryThrower")

	return {
		ent = ent,
		class = ent:GetClass(),
		metres = ply:EyePos():Distance(ent:GetPos()) / 52.49,
		onScreen = point.visible,
		own = (IsValid(owner) and owner == ply) or (IsValid(thrower) and thrower == ply),
		armed = ent:GetNWBool("GryArmed"),
		visible = visible,
		screen = point
	}
end

local function candidates(ply, opts)
	local list = {}

	for _, ent in ipairs(scanned) do
		if IsValid(ent) then
			local point = ent:WorldSpaceCenter():ToScreen()
			local visible

			-- the line of sight costs a ray: only for a projectile that is on the screen and active
			if opts.los and point.visible and ent:GetNWBool("GryArmed") then
				visible = lineOfSight(ent, ply)
			end

			list[#list + 1] = Grenade.Candidate(ent, ply, point, visible)
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
	local opts = Grenade.Options()
	local best = Grenade.Pick(candidates(ply, opts), switch ~= nil and switch:GetBool(), opts)

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
	warning:SetType(Grenade.TypeFor(best.class))
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
