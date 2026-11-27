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

-- Weapons that show no crosshair in the original (the fists, the LAW) say so in the weapon registry (crosshair = false, see
-- compat/hl2/sh_weapons.lua): so does any other addon's weapon that wants none.

-- The crosshair number for a style: 0 (none) when there is no weapon, the weapon hides it (or draws its own: its
-- DrawCrosshair is false) or the player zooms; a style that is not one of the movie's 13 gives the default.
-- A weapon may choose its own crosshair (the registry's `crosshair` is a number from 1 to 13, as the original forces the 11 to 13 by
-- weapon) unless `weaponStyles` is false (the player's gry_hud_crosshair_weapon: he wants his own style everywhere).
function Cross.IndexFor(style, class, weaponDraws, zoomed, weaponStyles)
	if not class or not weaponDraws or zoomed then
		return 0
	end

	local declared = GryMod.API.WeaponValue(class, "crosshair", true)

	if declared == false then
		return 0
	end

	if weaponStyles ~= false and isnumber(declared) and declared >= 1 and declared <= Cross.COUNT then
		return math.floor(declared)
	end

	if type(style) ~= "number" or style ~= style or style < 1 or style > Cross.COUNT then
		return Cross.DEFAULT_STYLE
	end

	return math.floor(style)
end

-- The crosshair a zoomed weapon asks for (its registry's zoomCrosshair, see cl_weapon_zoom.lua) over the one chosen: only over a crosshair that is shown
-- (0 stays 0: the binoculars, a weapon without one) and not when the player wants his own style everywhere (gry_hud_crosshair_weapon 0).
function Cross.ZoomOverride(index, zoomIndex, weaponStyles)
	if index ~= 0 and zoomIndex and weaponStyles ~= false then
		return zoomIndex
	end

	return index
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

-- What a shot adds to the kick of the crosshair: 0.25 times the suit's recoil scale (GryMod.SuitWeapons.RecoilScale: smaller in the strength mode), never over 1. The crosshair reads no
-- weapon's own spread (the bases have none in common): it estimates its opening from what the player does, so the reduced recoil of the suit shows here for every weapon base.
function Cross.KickAfterShot(kick, scale)
	if not isnumber(scale) or scale ~= scale then
		scale = 1
	end

	return math.min(kick + 0.25 * math.max(scale, 0), 1)
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

-- The limits of what the player lifts with +use: CBasePlayer::CanPickupObject(ent, 35, 128) of the Source SDK, which is what gives a physics
-- prop its use capability: at most 35 kg and 128 units on every side. The client reads the size of the box. It CANNOT read the mass: it has no physics
-- object for a prop of the server (checked: GetPhysicsObject is invalid there), so the server tells it (sv_usable_mass.lua). POLICY: a prop whose mass
-- is not known yet is NOT offered (the question goes out at once, the answer is back before the next scan, a tenth of a second later), and a prop the
-- server says is heavier than 35 kg is never offered.
Cross.PICKUP_MASS = 35
Cross.PICKUP_SIZE = 128

local MASS_ASK_EVERY = 3 -- a prop that is still aimed at is asked again after this many seconds (a tool can change its mass)
local MASS_TRUST_FOR = 10 -- an answer older than this is dropped

local masses = {} -- [entity index] = {mass = kg, answered = time, asked = time}

-- Asks the server for the mass of the prop of this index (replaceable by the tests).
function Cross.AskMass(index)
	net.Start("gry_mass_ask")
	net.WriteUInt(index, 13)
	net.SendToServer()
end

-- The server's answer.
function Cross.OnMassAnswer(index, mass, now)
	local entry = masses[index] or {asked = now}

	entry.mass, entry.answered = mass, now
	masses[index] = entry
end

function Cross.ForgetMasses()
	masses = {}
end

net.Receive("gry_mass", function()
	local index = net.ReadUInt(13)

	Cross.OnMassAnswer(index, net.ReadFloat(), RealTime())
end)

function Cross.Grabbable(ent, now)
	if isfunction(ent.OBBMins) and isfunction(ent.OBBMaxs) then
		local size = ent:OBBMaxs() - ent:OBBMins()

		if size.x > Cross.PICKUP_SIZE or size.y > Cross.PICKUP_SIZE or size.z > Cross.PICKUP_SIZE then
			return false
		end
	end

	-- a stand-in that is no entity has no index to ask for
	if not isfunction(ent.EntIndex) then
		return true
	end

	now = now or RealTime()

	local index = ent:EntIndex()
	local entry = masses[index]

	if not entry or now - entry.asked >= MASS_ASK_EVERY then
		entry = entry or {}
		entry.asked = now
		masses[index] = entry
		Cross.AskMass(index)
	end

	if entry.answered and now - entry.answered <= MASS_TRUST_FOR then
		return entry.mass <= Cross.PICKUP_MASS
	end

	return false
end

-- The kinds of prompt the player can switch off: an entry of the registry with a `group` follows the client convar gry_usehint_<group> when there is one
-- (the props: gry_usehint_props, off by default, since "you can pick up almost anything" is not what everyone wants a prompt for); a group no convar
-- names is on.
CreateClientConVar("gry_usehint_props", "0", true, false, "1: the use prompt (PICK UP) also shows on the props, ragdolls and physboxes you can lift; 0: only on what really needs the use key (doors, buttons, ladders, vehicles, chargers, mounted guns, people)", 0, 1)

local groupVars = {}

function Cross.GroupEnabled(group)
	if not isstring(group) then
		return true
	end

	local var = groupVars[group]

	if var == nil then
		var = GetConVar("gry_usehint_" .. group) or false
		groupVars[group] = var
	end

	return not var or var:GetBool()
end

-- setUsable's mode for what the player aims at: 1 something can be used or taken, 0 nothing. WHAT can be used is the registry of usable entities
-- (GryMod.API.RegisterUsable): anything it names counts, but not an entry of a group the player switched off, not one that is busy (a ladder being climbed),
-- an entity with the "grab" icon only when the player can lift it (Cross.Grabbable: not for an entry with `nolimits`), a vehicle not while the player sits
-- in one. What is taken by walking over it (a weapon, an item) is in no entry, so it is not usable: it needs no key. The registry also drops an entity
-- whose spawnflags say the key does nothing (a door that ignores it...), see GryMod.API.GetUsable. `dist` (units from the eye to what was hit, optional) is
-- tested against the reach of the key: 80 units, or the entry's own `range`; the HUD used to test 110, so a prompt showed where the key did nothing.
function Cross.UsableFor(ent, ply, dist)
	if not ent or not IsValid(ent) then
		return 0
	end

	local API = GryMod.API

	if not (API and API.GetUsable) then
		return 0
	end

	local entry = API.GetUsable(ent)

	if not entry then
		return 0
	end

	if entry.group and not Cross.GroupEnabled(entry.group) then
		return 0
	end

	-- an addon that knows who may use it (a prop protection, a locked vehicle) can refuse: GryMod.API.AddUsableFilter
	if API.UsableFiltered and API.UsableFiltered(ent, ply) then
		return 0
	end

	if dist and dist > API.UsableRange(entry) then
		return 0
	end

	if entry.icon == "grab" and not entry.nolimits and not Cross.Grabbable(ent) then
		return 0
	end

	if entry.icon == "enter" and ply and isfunction(ply.InVehicle) and ply:InVehicle() then
		return 0
	end

	if entry.busy and API.UsableBusy(ent, ply, entry) then
		return 0
	end

	return 1
end

-- The thing the eye trace cannot hit because it is not solid (a ladder), when the aim ray goes through its box: `maxDist` is how far the ray may
-- go (the use range, or the distance of what the trace hit if that is nearer: a wall in front hides it). Only the classes the registry marks nonsolid
-- are looked at (GryMod.API.UsableNonSolidClasses, a ladder for the stock ones), so this costs one list per class, at the scan's ten a second, and only
-- when the trace found nothing usable. Returns the entity or nil.
local PAD = 6 -- units added around the box: the aim need not be exact

-- How far the scan looks for what can be used: the greatest reach of the registry's entries (80 units, the key's own, for the stock ones).
function Cross.UseTraceLength()
	local API = GryMod.API

	return API and API.UsableMaxRange and API.UsableMaxRange() or 80
end

function Cross.NonSolidAimed(ply, maxDist)
	local API = GryMod.API
	local classes = API and API.UsableNonSolidClasses and API.UsableNonSolidClasses()

	if not classes or #classes == 0 then
		return nil
	end

	local eye = ply:EyePos()
	local aim = ply:GetAimVector()
	local pad = Vector(PAD, PAD, PAD)

	for i = 1, #classes do
		local list = ents.FindByClass(classes[i])

		for j = 1, #list do
			local ent = list[j]

			-- the ray first (cheap, and the registry's question for a toggle goes to the server: it is asked only for what the player aims at), then
			-- only what the registry says is usable now: a class name shared by other things (the client calls a wheel and a lot of toggles
			-- "class C_BaseToggle") must not stop the search at one that is not
			if IsValid(ent) then
				local mins, maxs = ent:OBBMins() - pad, ent:OBBMaxs() + pad

				if util.IntersectRayWithOBB(eye, aim * maxDist, ent:GetPos(), ent:GetAngles(), mins, maxs) then
					local entry = API.GetUsable(ent)

					-- the key's reach for this very thing (a ladder: 64 units)
					if entry and (API.UsableRange(entry) >= maxDist or util.IntersectRayWithOBB(eye, aim * API.UsableRange(entry), ent:GetPos(), ent:GetAngles(), mins, maxs)) then
						return ent
					end
				end
			end
		end
	end

	return nil
end

-- Whether what the player aims at is an ally: a player of the same team (when the game has teams), or an NPC that the
-- SERVER says likes the player (D_LI, see sv_friendly.lua): the attitude of an NPC is what counts, not its class (the
-- "Enemy Rebel" of the NPC menu is an npc_citizen that hates the player). `known` is the server's answer for an NPC
-- (Cross.Relation): while it is not there (nil) or says no, the cross stays closed, so that no hostile NPC ever shows
-- it. The original asks its game rules; Garry's Mod has no common answer.
function Cross.IsFriendly(ent, ply, known)
	if not ent or not IsValid(ent) then
		return false
	end

	if ent:IsPlayer() then
		local team = ent:Team()

		return ent ~= ply and ply ~= nil and team == ply:Team() and team ~= 1001 and team ~= 1002
	end

	return GryMod.API.IsCreature(ent) and known == true
end

-- ---------------------------------------------------------------------------------------------------------
-- The attitude of an NPC towards the player, from the server (Disposition only exists there)
-- ---------------------------------------------------------------------------------------------------------

local ASK_EVERY = 1 -- an NPC that is still aimed at is asked again after this many seconds (it can turn hostile)
local TRUST_FOR = 2 -- an answer older than this is dropped (the server limits the questions: no answer, no cross)
local ASK_GAP = 0.2 -- two questions are at least this far apart, the server answers 5 a second to a player

local relations = {} -- [entity index] = {friendly = bool, relation = "ally"|"neutral"|"hostile", answered = time, asked = time}
local lastAsk = -math.huge

-- Asks the server whether the NPC of this index is an ally (replaceable by the tests).
function Cross.AskServer(index)
	net.Start("gry_friendly_ask")
	net.WriteUInt(index, 13)
	net.SendToServer()
end

-- The entry of the entity's answer at `now` when it is there and fresh, else nil. Asks the server when the entity is new or its answer is a second old (at most one
-- question every ASK_GAP seconds in all, whoever asks: the crosshair, GryMod.API.ClientRelation).
local function answerOf(ent, now)
	local index = ent:EntIndex()
	local entry = relations[index]

	if (not entry or now - entry.asked >= ASK_EVERY) and now - lastAsk >= ASK_GAP then
		entry = entry or {asked = now}
		entry.asked = now
		relations[index] = entry
		lastAsk = now
		Cross.AskServer(index)
	end

	if entry and entry.answered and now - entry.answered <= TRUST_FOR then
		return entry
	end

	return nil
end

-- What the server answered for the NPC at `now`: true (ally), false (not), nil (not known, or too old).
function Cross.Relation(ent, now)
	local entry = answerOf(ent, now)

	return entry and entry.friendly
end

-- The same answer as a word: "ally", "neutral" or "hostile", nil when it is not known or too old. A server that only says whether it is an ally (the older message) gives
-- "ally" or "neutral".
function Cross.RelationName(ent, now)
	local entry = answerOf(ent, now)

	return entry and entry.relation
end

local RELATION_NAMES = {[0] = "neutral", "ally", "hostile"}

-- The server's answer (`relation`: the word, when the server sends it).
function Cross.OnAnswer(index, friendly, now, relation)
	local entry = relations[index] or {asked = now}
	entry.friendly, entry.answered = friendly and true or false, now
	entry.relation = (relation == "ally" or relation == "neutral" or relation == "hostile") and relation or (friendly and "ally" or "neutral")
	relations[index] = entry
end

function Cross.ForgetRelations()
	relations = {}
	lastAsk = -math.huge
end

-- Reads the message of the server from `reader` (the net library): the index, whether it is an ally, and the relation as a code (0 neutral, 1 ally, 2 hostile) when the
-- server wrote one after the bool (nil for the older message, which ends there).
function Cross.ReadAnswer(reader)
	local index = reader.ReadUInt(13)
	local friendly = reader.ReadBool()
	local _, bits = reader.BytesLeft()
	local code

	if bits and bits > 0 then
		code = reader.ReadUInt(2)
	end

	return index, friendly, RELATION_NAMES[code]
end

net.Receive("gry_friendly", function()
	local index, friendly, relation = Cross.ReadAnswer(net)

	Cross.OnAnswer(index, friendly, RealTime(), relation)
end)

-- What a player is to the local player, from the teams (the server's built-in rule): "ally" for a player of the same team when the game has teams (not unassigned 1001, nor
-- spectator 1002), never the player himself; "neutral" otherwise.
function Cross.PlayerRelation(ent, ply)
	if ent ~= ply and ply ~= nil then
		local team = ent:Team()

		if team == ply:Team() and team ~= 1001 and team ~= 1002 then
			return "ally"
		end
	end

	return "neutral"
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
	local current = self.current
	local version = current and current.version

	self.root:Advance(dt)

	-- an animation of the crosshair can rebuild its clips: the spread is said again (only then)
	if self.current == current and current and current.version ~= version then
		self:_applyRecoil()
	end
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

local WEAPON_CONVAR = CreateClientConVar("gry_hud_crosshair_weapon", "1", true, false,
	"A weapon that declares its own crosshair (the weapon registry's crosshair field) shows it; 0: always the style chosen above")

-- Whether the weapons may choose their crosshair (gry_hud_crosshair_weapon).
function Cross.WeaponStyles()
	return WEAPON_CONVAR:GetBool()
end

local instance, friendly
local lastTime
local spread, kick, lastNextFire = 0, 0, 0
local usableMode, friendlyShown = 0, false
local usableEnt -- the entity that can be used and was last reported (nil: none)
local reportedMode = 0 -- the mode that was last reported with it

-- How long the crosshair must stay on the same usable thing before the use prompt shows (seconds): the original's prompt does not flash up
-- when the crosshair only passes over a thing. 0: at once. The crosshair's own usable state is not delayed. 0.10 s is the original's: the aim must stay
-- 0.05 s on the thing to select it, and the text comes 0.05 s after the selection (CryAction's interactor, see docs/superpowers/plans/2026-11-23-crysis-timings-catalogue.md U1).
local DELAY_CONVAR = CreateClientConVar("gry_usehint_delay", "0.1", true, false, "Seconds the crosshair must stay on the same usable thing before the use prompt shows (0.1 is the original's: 0.05 to select + 0.05 to the text; 0: at once). The prompt goes at once when the thing changes", 0, 2)
Cross.DWELL_DEFAULT = 0.1

-- How long the prompt stays after the crosshair leaves the thing (seconds): the original keeps the selection 0.2 s. 0: it goes at once. Another usable thing under
-- the crosshair ends the hold at once.
local HOLD_CONVAR = CreateClientConVar("gry_usehint_hold", "0.2", true, false, "Seconds the use prompt stays after the crosshair leaves the usable thing (0.2 is the original's; 0: it goes at once). Another usable thing replaces it at once", 0, 2)
Cross.HOLD_DEFAULT = 0.2

function Cross.HoldDuration()
	local hold = HOLD_CONVAR:GetFloat()

	if hold ~= hold then
		return Cross.HOLD_DEFAULT
	end

	return math.Clamp(hold, 0, 2)
end

function Cross.DwellDelay()
	local delay = DELAY_CONVAR:GetFloat()

	if delay ~= delay then
		return Cross.DWELL_DEFAULT
	end

	return math.Clamp(delay, 0, 2)
end

-- The dwell: state {ent, since}. Given the thing under the crosshair now (nil for none) it says which thing may be shown now: the same one for `delay` seconds
-- gives it, a different one starts the wait again and nothing is shown for it meanwhile, nothing gives nothing at once. Pure.
function Cross.DwellStep(state, ent, now, delay)
	if ent ~= state.ent then
		state.ent, state.since = ent, now
	end

	if ent == nil then
		return nil
	end

	-- (a hair of tolerance: the convar is a 32 bit float, 0.2 reads 0.2000000030, and the 10 Hz scan would else wait a whole extra step)
	if now - state.since >= delay - 1e-6 then
		return ent
	end

	return nil
end

local dwell = {ent = nil, since = 0}

-- The hold: set while the prompt stays after the aim left its thing (holdUntil: when it ends, holdPly: the player the end is told for). Its timer exists only
-- for that time; nothing runs otherwise (the scan, which runs anyway, also ends it, whichever comes first).
local HOLD_TIMER = "GryMod_UsableHold"
local holdUntil, holdPly

function Cross.Holding()
	return holdUntil ~= nil
end

local function endHold()
	holdUntil, holdPly = nil, nil
	timer.Remove(HOLD_TIMER)
end

-- The hold is over: the thing is told gone (once; nothing when there is no hold).
function Cross.ExpireHold()
	if not holdUntil then
		return
	end

	local ply = holdPly

	endHold()
	usableEnt, reportedMode = nil, 0
	Cross.ReportUsable(nil, 0, ply)
end

function Cross.ResetDwell()
	dwell.ent, dwell.since = nil, 0
	usableEnt, reportedMode = nil, 0
	endHold()
end

-- The scan's report: the thing that can be used under the crosshair (nil, mode 0 when none), delayed by the dwell and held after the aim leaves. The hook is run
-- once at each change of what is SHOWN (the entity or its mode), as before; with the delay and the hold at 0 that is what it always was.
function Cross.ReportDwelled(usable, mode, ply, now)
	local shown = Cross.DwellStep(dwell, usable, now, Cross.DwellDelay())

	-- something is on show and the dwell gives nothing now: the hold decides
	if shown == nil and usableEnt ~= nil then
		if holdUntil then
			if now >= holdUntil - 1e-6 then
				Cross.ExpireHold()
			elseif usable == usableEnt then
				-- the aim came back to the thing: it never went
				endHold()
				shown = usable
			elseif usable ~= nil then
				-- another usable thing: this one goes at once, the other comes after its own delay
				Cross.ExpireHold()
			else
				return
			end
		elseif usable == nil and Cross.HoldDuration() > 0 then
			holdUntil, holdPly = now + Cross.HoldDuration(), ply
			timer.Create(HOLD_TIMER, Cross.HoldDuration(), 1, Cross.ExpireHold)

			return
		end
	elseif holdUntil then
		endHold()
	end

	local shownMode = shown ~= nil and mode or 0

	if shown ~= usableEnt or shownMode ~= reportedMode then
		usableEnt, reportedMode = shown, shownMode
		Cross.ReportUsable(shown, shownMode, ply)
	end
end
local nextScan = 0
local failed = false -- the movie could not make a crosshair: not tried again until Reset

-- Whether the friendly cross is up (the player aims at an ally).
function Cross.FriendlyShown()
	return friendlyShown
end

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

-- The server says something hurt the player from this direction (a unit vector from the player towards the
-- shooter): the arcs of the damage direction.
function Cross.NotifyDamage(direction)
	local ply = LocalPlayer()

	if instance and IsValid(ply) and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("damage")) then
		instance:OnDamage(ply:GetPos(), ply:GetPos() + direction * 100, Flash.ViewYaw(ply), CurTime())
	end
end

net.Receive("gry_hit", function()
	Cross.NotifyHit()
end)

net.Receive("gry_damage_dir", function()
	Cross.NotifyDamage(net.ReadNormal())
end)

-- The crosshair is not wanted while the suit is down, the quick menu is up, the player is in a vehicle, or he sees himself from behind (third person: the crosshair sits
-- at the middle of the screen, which is no longer where he aims).
local function hidden(ply)
	return (GryMod.FlashBoot and GryMod.FlashBoot.IsLost())
		or (GryMod.FlashMenu and GryMod.FlashMenu.IsOpen())
		or ply:InVehicle()
		or ply:ShouldDrawLocalPlayer()
end

-- Whether the crosshair is hidden for this player (the Lost animation, the quick menu, a vehicle): what hangs on it, such as the use
-- prompt (cl_hud_use_flash.lua), goes with it.
Cross.IsHidden = hidden

-- Whether the player is zooming with the binoculars on (with them off the zoom is the plain game's).
function Cross.Zooming(ply)
	-- (the binoculars know both zooms, the game's key and the own zoom)
	local binoculars = GryMod.FlashBinoculars

	if binoculars and binoculars.Wanted then
		return binoculars.Enabled() and binoculars.Wanted(ply)
	end

	return ply:KeyDown(IN_ZOOM)
end

-- Whether the weapon leaves the crosshair to the game: not when it hides it (DrawCrosshair false) or draws its
-- own (DoDrawCrosshair, which the game only calls from its own crosshair).
function Cross.WeaponDraws(weapon)
	if not weapon or not IsValid(weapon) then
		return true
	end

	return weapon.DrawCrosshair ~= false and weapon.DoDrawCrosshair == nil
end

-- Whether the game's own crosshair is hidden for this weapon: always, except for a weapon that draws its own
-- through DoDrawCrosshair (that call lives inside the game's crosshair).
function Cross.VanillaHiddenFor(weapon)
	return not (weapon and IsValid(weapon) and weapon.DoDrawCrosshair ~= nil)
end

-- The thing the player aims at that can be used changed (`ent` is nil and `mode` 0 when there is none; `mode` is setUsable's: 1 can be used or
-- taken, 2 can not). The hook GryMod_UsableChanged(ent, mode, ply) tells the other parts and the addons; nothing reads what it returns. The use
-- prompt (cl_hud_use_flash.lua) hangs on it. A field so that a test can replace it.
function Cross.ReportUsable(ent, mode, ply)
	-- a listener that fails must not break the crosshair's frame: its error is printed, the crosshair goes on
	local ok, err = pcall(hook.Run, "GryMod_UsableChanged", ent, mode, ply)

	if not ok then
		ErrorNoHalt("[GryMod] A listener of GryMod_UsableChanged failed: " .. tostring(err) .. "\n")
	end
end

-- What the player aims at, looked for ten times a second: the mode of setUsable and the friendly cross.
local function scan(ply)
	local now = RealTime()

	if now < nextScan then
		return
	end

	nextScan = now + 0.1

	-- the key's reach (80 units for the stock things), not the 110 the scan used to look at
	local eye = ply:EyePos()
	local length = Cross.UseTraceLength()
	local trace = util.TraceLine({
		start = eye,
		endpos = eye + ply:GetAimVector() * length,
		filter = ply
	})
	local aimedAt = trace.Entity
	local mode = aimedAt and Cross.UsableFor(aimedAt, ply, trace.Hit and eye:Distance(trace.HitPos) or nil) or 0

	-- nothing usable was hit: a non-solid thing (a ladder) in front, nearer than what the trace hit, may be
	if mode == 0 then
		local reach = trace.Hit and eye:Distance(trace.HitPos) or length
		local ghost = Cross.NonSolidAimed(ply, reach)

		if ghost then
			aimedAt = ghost
			mode = Cross.UsableFor(ghost, ply)
		end
	end

	local usable = mode ~= 0 and aimedAt or nil

	if mode ~= usableMode then
		usableMode = mode
		instance:SetUsable(mode)
	end

	-- the same test says WHAT can be used: the report is made once at each change of the entity or of the mode (after the dwell), not at each look
	Cross.ReportDwelled(usable, mode, ply, now)

	local far = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 3000,
		filter = ply
	})
	local aimed = far.Entity
	local known = nil

	-- an NPC's attitude comes from the server: asked only for what is aimed at
	if aimed and IsValid(aimed) and GryMod.API.IsCreature(aimed) then
		known = Cross.Relation(aimed, now)
	end

	local isFriendly = aimed and Cross.IsFriendly(aimed, ply, known) or false

	if isFriendly and not friendlyShown and friendly then
		friendly.clip:GotoAndPlay("restart")
	end

	friendlyShown = isFriendly
end

-- The spread: the original reads the weapon's, here it comes from what the player does (see SpreadTarget).
local function updateSpread(ply, weapon, dt)
	local nextFire = IsValid(weapon) and weapon:GetNextPrimaryFire() or 0

	if nextFire > lastNextFire + 0.001 then
		local suit = GryMod.SuitWeapons

		kick = Cross.KickAfterShot(kick, suit and suit.RecoilScale(suit.ModeOf(ply), suit.EnergyOf(ply)) or 1)
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

	if failed then
		return
	end

	if not instance then
		instance = Cross.New(Flash.Load(Cross.MOVIE))

		if not instance then
			failed = true

			return
		end

		local movie = Flash.Load(Cross.FRIENDLY_MOVIE)
		local holder = movie and Flash.NewRoot(movie, GryMod.FlashHUD.Theme)
		friendly = holder and holder:Child("Root") and {root = holder, clip = holder:Child("Root")} or nil

		if holder and not friendly then
			Flash.ReleaseClip(holder)
		end

		lastTime, spread, kick, usableMode, friendlyShown = nil, 0, 0, 0, false
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	local weapon = ply:GetActiveWeapon()
	local class = IsValid(weapon) and weapon:GetClass() or nil
	local index = Cross.IndexFor(STYLE_CONVAR:GetInt(), class, Cross.WeaponDraws(weapon), Cross.Zooming(ply), WEAPON_CONVAR:GetBool())
	local zoomWeapon = GryMod.WeaponZoom

	if zoomWeapon and zoomWeapon.CrosshairFor then
		index = Cross.ZoomOverride(index, zoomWeapon.CrosshairFor(ply), WEAPON_CONVAR:GetBool())
	end

	if hidden(ply) then
		index = 0
	end

	if index ~= instance.index then
		instance:SetCrosshair(index)
		-- a crosshair that is just shown has its usable state said again
		usableMode = 0
		reportedMode = 0
		nextScan = 0
	end

	updateSpread(ply, weapon, dt)
	instance:SetRecoil(index >= 11 and spread * 40 or spread)
	instance:SetViewYaw(Flash.ViewYaw(ply), CurTime())
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
	nextScan, failed = 0, false
	Cross.ResetDwell()
	Cross.ForgetRelations()
end

hook.Add("HUDPaint", "GRYFLASHCROSSHAIR", Cross.Paint)

-- the Half-Life 2 crosshair stays away while ours is on
hook.Add("HUDShouldDraw", "GRYCROSSHAIRHIDE", function(name)
	if name == "CHudCrosshair" and Cross.Enabled() then
		local ply = LocalPlayer()

		if IsValid(ply) and not Cross.VanillaHiddenFor(ply:GetActiveWeapon()) then
			return
		end

		return false
	end
end)
