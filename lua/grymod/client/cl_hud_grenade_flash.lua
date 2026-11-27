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
-- in compat/hl2/sh_tracked.lua and an addon's own go through the same code. The entry that names the class, or nil: none, or no
-- registry (a hot reload of this file).
local function dangerEntry(class)
	local API = GryMod.API

	return API and API.GetDanger and API.GetDanger(class) or nil
end

-- The text the warning shows for a projectile (the `label` of its danger entry), nil for one that is not a danger. `entry` is the one the candidate carries (an entry
-- found by a base or a match function has no class to be read by); without it the class names it.
function Grenade.TypeFor(class, entry)
	entry = entry or dangerEntry(class)

	return entry and entry.danger.label or nil
end

-- The size of the icon in percent for a distance in metres: 100 minus 1.5 a metre, never under 45.
function Grenade.SizeFor(metres)
	return math.max(45, 100 - metres * 1.5)
end

-- The stage position of the icon's corner for a point of the screen (the stage is scaled to the screen height and
-- centred). The icon hangs from its corner and shrinks towards it with the distance, so the hexagon's centre is
-- 18 * size from the corner: that centre is what lands on the point.
-- Where the icon goes for a grenade in front of the player whose projection (x, y) may be off the screen: a point that is inside the
-- frame (3 percent in from every side) stays, one outside is brought back along the line from the centre of the screen, so the icon sits
-- at the edge the grenade is on and points to it. Returns x, y and whether it moved.
function Grenade.EdgePoint(x, y, screenW, screenH)
	local marginX, marginY = EDGE * screenW, EDGE * screenH

	if x >= marginX and x <= screenW - marginX and y >= marginY and y <= screenH - marginY then
		return x, y, false
	end

	local centreX, centreY = screenW / 2, screenH / 2
	local dx, dy = x - centreX, y - centreY
	local keep = 1

	if dx ~= 0 then
		keep = math.min(keep, (centreX - marginX) / math.abs(dx))
	end

	if dy ~= 0 then
		keep = math.min(keep, (centreY - marginY) / math.abs(dy))
	end

	return centreX + dx * keep, centreY + dy * keep, true
end

-- With `edge` (gry_hud_grenade_edge) the point is held inside the frame on both axes (EdgePoint); without it only x is, as before.
function Grenade.StagePosition(screenX, screenY, screenW, screenH, metres, edge)
	local scale = screenH / STAGE_H
	local half = HALF_ICON * Grenade.SizeFor(metres or 0) / 100

	if edge then
		screenX, screenY = Grenade.EdgePoint(screenX, screenY, screenW, screenH)
	else
		screenX = math.Clamp(screenX, EDGE * screenW, (1 - EDGE) * screenW)
	end

	return (screenX - (screenW - STAGE_W * scale) / 2) / scale - half, screenY / scale - half
end

-- Whether a candidate ({class, metres, onScreen, own, armed, visible}) deserves a warning. `armed` is the server's mark
-- (sv_grenade.lua): true for a projectile that is active and not held in the player's hands, so an inert one (lying
-- around, a mine on the ground) and the one in the hands are not warned about, unless armedOnly is false (the switch
-- gry_grenade_armed_only, for debugging). opts: range (metres, default DEFAULT_RANGE), ownWarn (true: the player's own hand
-- grenade warns within OWN_WARN_RANGE, the old rule; default false: a grenade the player threw never warns, whatever the
-- distance), los (true: only a projectile seen from the eye, `visible` not false; default false, as in the original, which
-- warns through walls), edge (true: a projectile off the screen but in front, c.front, warns too; default false).
function Grenade.Warns(c, armedOnly, opts)
	opts = opts or {}
	local range = opts.range or Grenade.DEFAULT_RANGE
	local entry = c.entry or dangerEntry(c.class)

	-- only the entries whose indicator is the warning (the grenade-detect film) are drawn here; "marker" and "none" are stored
	if not entry or entry.indicator ~= "warning" then
		return false
	end

	-- the entry's own range can only shorten the player's
	if entry.danger.range and entry.danger.range < range then
		range = entry.danger.range
	end

	if c.metres < Grenade.MIN_OWN or c.metres > range then
		return false
	end

	-- the side: with the edge setting the alert also follows a grenade that is off the screen but in front of the player (it sits at the
	-- screen edge, see EdgePoint); only one behind the camera is dropped, as in the original. A candidate that does not say (front nil) is
	-- judged by the screen.
	local inView = c.onScreen

	if opts.edge and c.front ~= nil then
		inView = c.front
	end

	if not inView then
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
local edgeVar = CreateClientConVar("gry_hud_grenade_edge", "1", true, false,
	"1: the grenade warning stays at the edge of the screen when the grenade is off it to the side, above or below (the original); 0: it goes away", 0, 1)

function Grenade.Options()
	return {range = Grenade.ClampRange(rangeVar:GetFloat()), ownWarn = ownWarnVar:GetBool(), los = losVar:GetBool(), edge = edgeVar:GetBool()}
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

-- The projectiles are followed from their creation (the hooks below, as the server does in sv_grenade.lua): the world is never
-- searched while the game runs. Their positions are read every frame. Measured on live entities: a networked entity already has its
-- class and its model in OnEntityCreated; an entity that is out of the player's view is dormant, it stays in the client's list and
-- is not made again when it comes back, so nothing is lost when it leaves and returns. Keys are weak: an entity that goes without
-- its hook does not stay.
local followed = setmetatable({}, {__mode = "k"})
local pending = setmetatable({}, {__mode = "k"})
local settling = false
local seen -- the list of danger classes the world was last searched for (a new list is made at every change of the registry)

-- The engine's class of an entity that does not have its own yet ("class C_BaseEntity")
local function unresolved(class)
	return class == "" or string.sub(class, 1, 6) == "class "
end

-- Follows the entity when the registry has a danger entry for it (by its class, its base or the entry's match function: the registry asks once for it and keeps the
-- answer). Returns whether it does.
function Grenade.Follow(ent)
	local API = GryMod.API

	if not IsValid(ent) or not API or not API.GetDanger then
		return false
	end

	if API.GetDanger(ent) then
		followed[ent] = true

		return true
	end

	return false
end

function Grenade.Forget(ent)
	followed[ent] = nil
	pending[ent] = nil
end

-- One frame after a creation: the entities that had no class yet are judged again (one timer for all of the frame).
local function settle()
	settling = false

	for ent in pairs(pending) do
		pending[ent] = nil
		Grenade.Follow(ent)
	end
end

-- Judges the waiting entities now (the timer's job, at once); a timer that did not run leaves nothing waiting for it. For the tests.
Grenade.Settle = settle

hook.Add("OnEntityCreated", "GRYGRENADEFOLLOW", function(ent)
	local API = GryMod.API

	if not IsValid(ent) or not API or not API.GetDanger then
		return
	end

	-- (an entry that names its entities by a base or a function may not place an entity that is only made: its fields come a frame later, like a class)
	if Grenade.Follow(ent) then
		return
	end

	if unresolved(ent:GetClass()) or (API.DangerNeedsEntity and API.DangerNeedsEntity()) then
		pending[ent] = true

		if not settling then
			settling = true
			timer.Simple(0, settle)
		end
	end
end)

hook.Add("EntityRemoved", "GRYGRENADEFOLLOW", function(ent)
	followed[ent] = nil
	pending[ent] = nil
end)

-- The entities that stand when the registry changes (and when this file is loaded: a hot reload, or the module started late) are
-- looked for once, class by class; after that only the events follow. Each change of the registry makes a new list of classes
-- (sh_api_tracked.lua), so one comparison tells whether it changed.
local function catchUp()
	local API = GryMod.API

	if not API or not API.DangerClasses then
		return
	end

	local classes = API.DangerClasses()

	if classes == seen then
		return
	end

	seen = classes

	for _, class in ipairs(classes) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			Grenade.Follow(ent)
		end
	end
end

catchUp()

-- What Pick reads of an entity: its class, the distance in metres from the eye, whether it is on the screen (the point
-- is its projection), the server's mark (sv_grenade.lua), whether it is the player's own (the engine's owner, or the
-- thrower the server writes), the line of sight when it was read (`visible`: true, false, or nil when not asked) and the side of the
-- eye it is on (`front`).
function Grenade.Candidate(ent, ply, point, visible, front)
	point = point or ent:WorldSpaceCenter():ToScreen()
	local owner = ent:GetOwner()
	local thrower = ent:GetNW2Entity("GryThrower")

	return {
		ent = ent,
		class = ent:GetClass(),
		metres = ply:EyePos():Distance(ent:GetPos()) / 52.49,
		onScreen = point.visible,
		own = (IsValid(owner) and owner == ply) or (IsValid(thrower) and thrower == ply),
		armed = ent:GetNW2Bool("GryArmed"),
		visible = visible,
		front = front, -- whether it is in front of the eye (nil: not asked); the screen point of one behind the camera is mirrored
		screen = point
	}
end

-- Whether this projectile may warn THIS player: the entry's `danger.warnFor(ent, ply)` (a missile that locks another player's vehicle is no danger to this one). No
-- function, an answer that is not false, or an error (it runs under SafeCall) is a yes: the default is to warn.
function Grenade.WarnFor(entry, ent, ply)
	local warnFor = entry.danger.warnFor

	if warnFor == nil then
		return true
	end

	local ok, answer = GryMod.API.SafeCall(entry.warnId, warnFor, ent, ply)

	return not (ok and answer == false)
end

-- The projectiles followed whose entry draws a warning (the registry's indicator, read now: an entry changed since the entity was
-- made counts), as candidates for Pick.
function Grenade.Candidates(ply, opts)
	catchUp()

	local list = {}
	local API = GryMod.API

	if not API or not API.GetDanger then
		return list
	end

	local eye, looking

	for ent in pairs(followed) do
		if IsValid(ent) then
			local entry = API.GetDanger(ent)

			if entry and entry.indicator == "warning" and Grenade.WarnFor(entry, ent, ply) then
				local centre = ent:WorldSpaceCenter()
				local point = centre:ToScreen()
				local visible

				-- in front of the eye: the projection of a point behind the camera lands on the screen mirrored and says nothing
				eye = eye or ply:EyePos()
				looking = looking or EyeVector()
				local front = (centre - eye):Dot(looking) > 0

				-- the line of sight costs a ray: only for a projectile that is on the screen (or at its edge) and active
				if opts.los and (point.visible or (opts.edge and front)) and ent:GetNW2Bool("GryArmed") then
					visible = lineOfSight(ent, ply)
				end

				local candidate = Grenade.Candidate(ent, ply, point, visible, front)

				candidate.entry = entry -- (an entry found by a base or a function is not found again by the class)
				list[#list + 1] = candidate
			end
		else
			followed[ent] = nil
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

	-- the server's switch (a server without the module marks nothing: then every projectile counts)
	armedSwitch = armedSwitch or GetConVar("gry_grenade_armed_only")
	local switch = armedSwitch
	local opts = Grenade.Options()
	local best = Grenade.Pick(Grenade.Candidates(ply, opts), switch ~= nil and switch:GetBool(), opts)

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
	warning:SetPosition(Grenade.StagePosition(best.screen.x, best.screen.y, ScrW(), ScrH(), best.metres, opts.edge))

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
