-- The contacts of the radar of the Crysis HUD, worked out on the server and sent to the players that have the radar. The
-- rules are those of the original (CHUDRadar::Update), see docs/superpowers/plans/2026-11-21-radar-research.md:
--   - what shows is the AI's own alertness: a hostile NPC that is alerted (it heard something, or lost the player) or fighting
--     the player (it has him as enemy) and is within 26 m is put on the radar and TAGGED; a tagged NPC stays on the radar,
--     at any distance of the radar, in the colour of its present state (calm included), until it dies;
--   - the allies of the player (NPCs that like him, GryMod.Friendly.Relation) are on the radar from the start, in blue, while
--     gry_radar_allies_always is on (GryMod's own rule: the original has no such thing); with it off they follow the rule of
--     the hostiles above (alerted or fighting within 26 m, or scanned). Neutrals (animals, NPCs that neither like nor hate the
--     player) show only when scanned or when they hurt him;
--   - the NPC that hurt the player is marked for 10 s, on the border of the radar if it is out of it;
--   - in a team game (at least two teams with players, GryMod.Radar.TeamsInUse) the living players of the player's team are contacts of type 7 (the original's
--     team mate icon), wherever they are, while gry_radar_teammates is on;
--   - the icon type: 1 ground, 2 flying, 3 machines (the registry's `type` and `size`: the stock classes are entries too).
--   - the vehicles (the rectangle icons, type 3) and the Combine mines (type 4, a rectangle with a disc) are contacts once the binoculars
--     scanned them (the registry gives them radar = "scan"): a vehicle in the colour of its DRIVER (nobody or a neutral: grey, a friend:
--     blue, a hostile: red), never the one the player sits in; a mine is hostile, and an ally once the player has taken it with the
--     gravity gun and put it down (m_bPlacedByPlayer); one switch, gry_radar_objects (the administrators' option);
--   - the registry of tracked entities (GryMod.API.RegisterTracked, sh_api_tracked.lua) overrides all this for the NPCs and
--     nextbots it matches: the icon type and size, the relation, when the contact is listed (radar = "always", "hostile",
--     "scan" or "never") and whether the binoculars may tag it (scan = false); an entity that is not registered is as above.
--   - the danger bar and the hexagon also hear of the hostiles that are NOT contacts: one that has the player as enemy or sees him counts 2, one that hears him
--     1, wherever it is in the search sphere (Radar.Detect, message gry_radar_detect, switch gry_radar_detect); the contacts keep their own rules above.
-- Cost: one timer every fifth of a second that only looks at the players that asked for the contacts (their HUD has the
-- radar on); one ents.FindInSphere around each of them, filtered by IsNPC; nothing is sent when the list did not change.

util.AddNetworkString("gry_radar")
util.AddNetworkString("gry_radar_want")
util.AddNetworkString("gry_radar_scan")
util.AddNetworkString("gry_radar_detect")

GryMod = GryMod or {}

local Radar = GryMod.Radar or {}
GryMod.Radar = Radar

local S = GryMod.RadarShared

local enabled = CreateConVar("gry_radar_contacts", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY),
	"The radar of the HUD shows the NPCs that are alerted to the player and the ones that shot at him; 0 turns the contacts off")

-- replicated and archived like the other server options, so that the options panel of an administrator shows the real value
local alliesAlways = CreateConVar("gry_radar_allies_always", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The allies of the player (NPCs that like him) are on the radar at once, in blue; 0 treats them like the hostiles: only when alerted or fighting within 26 m, or scanned")

-- The vehicles and the mines (every entity that is not an NPC and that the registry gives a radar rule): on the radar once scanned.
local objects = CreateConVar("gry_radar_objects", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The radar shows the vehicles and the Combine mines once the binoculars have scanned them; 0 leaves them off the radar")

-- The players of the same team (the original's icon type 7). Only in a team game: see Radar.TeamsInUse.
local teammatesOn = CreateConVar("gry_radar_teammates", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The living players of your team (a team game: at least two teams with players) are on your radar, on the edge of it when they are far; 0 leaves them off")

-- What the hostiles see and hear, for the danger bar and the hexagon (Radar.Detect).
local detectOn = CreateConVar("gry_radar_detect", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The danger bar and the radar hexagon also react to the hostile NPCs that see or hear you from beyond 26 m (not only to the alerted ones that are on the radar); 0 gives the old behaviour")

local INTERVAL = 0.2

-- Whether the allies are on the radar without having been noticed.
function Radar.AlliesAlways()
	return alliesAlways:GetBool()
end

-- The state of the AI as the original's alert level, which gives the colour of the unit on the radar: 2 (red) when the NPC is in combat
-- (NPC_STATE_COMBAT: it fights, whoever its enemy is) or has the player as enemy while its state says nothing useful; 1 (yellow) when it
-- is alerted (NPC_STATE_ALERT: it heard something, is searching, lost the player) and has not fought; 0 otherwise. An NPC that is only
-- suspicious or searching is never red. Having the player as enemy is level 2 whatever the state says, except ALERT: the machines have no
-- useful state (MEASURED on gm_construct: a floor turret that shoots the player stays in NPC_STATE_IDLE with the player as its enemy; a
-- ceiling turret and a camera stay in NPC_STATE_NONE); only a lost player (ALERT, which can keep the last enemy) stays level 1, and a
-- dead NPC is nothing.
function Radar.Level(state, enemyIsPlayer)
	if state == NPC_STATE_DEAD then
		return 0
	end

	if state == NPC_STATE_ALERT then
		return 1
	end

	if enemyIsPlayer then
		return 2
	end

	if state == NPC_STATE_COMBAT then
		return 2
	end

	return 0
end

-- The icon of the original: 1 infantry, 2 helicopters, 3 other vehicles and machines, and whether it is drawn twice the size (the
-- original doubles the Hunter and the Alien warrior). Which class has which is the registry's (the `type` and `size` fields of
-- GryMod.API.RegisterTracked, sh_api_tracked.lua): the Half-Life 2 classes are registered as data in compat/hl2/sh_tracked.lua and
-- an addon's own go through the same code. A class that no entry names is a ground unit.
Radar.Flying, Radar.Machines, Radar.Big = nil, nil, nil -- the old class tables: a hot reload keeps the table of the earlier copy

function Radar.TypeOf(class)
	local API = GryMod.API
	local entry = API and API.GetTrackedByClass and API.GetTrackedByClass(class)

	if not entry then
		return 1, false
	end

	return entry.type or 1, entry.size == "big"
end

-- The registry entry of the entity (GryMod.API.GetTracked), or nil: none, or no registry (a hot reload of this file).
local function trackedOf(ent)
	local API = GryMod.API

	return API and API.GetTracked and API.GetTracked(ent) or nil
end

-- Whether the radar lists vehicles and mines at all.
function Radar.ObjectsEnabled()
	return objects:GetBool()
end

-- The driver of a vehicle (the player or the NPC at the wheel), or nil. A field of Radar so that a test can replace it (the methods of
-- a real entity cannot be overridden on the instance).
-- The vehicle providers of the extension API (sh_api_vehicles.lua) know the drivers of the vehicles that are not the engine's (LVS, Glide, simfphys); the entity's own
-- GetDriver is the fallback inside GryMod.API.GetVehicleDriver.
function Radar.DriverOf(ent)
	return GryMod.API.GetVehicleDriver(ent)
end

-- Whether the player sits in this vehicle.
-- The vehicle of a player is the LOGICAL one (GryMod.API.GetVehicleOf: the providers of other addons first, the engine's Player:GetVehicle after): a car that has
-- its own seats is not the entity the engine says he sits in.
function Radar.Sits(ply, ent)
	return IsValid(ply) and IsValid(ent) and GryMod.API.GetVehicleOf(ply) == ent
end

-- A contact that is neither an NPC nor a nextbot: a vehicle or a mine, whatever the registry gives a radar rule (a vehicle of another
-- addon registered through the API is one too). Never the player, never what the player sits in.
function Radar.IsObject(ent, ply, tracked)
	if not IsValid(ent) or GryMod.API.IsCreature(ent) or ent:IsNextBot() or ent:IsPlayer() or not Radar.ObjectsEnabled() then
		return false
	end

	tracked = tracked or trackedOf(ent)

	if not tracked or tracked.radar == nil or tracked.radar == "never" then
		return false
	end

	if Radar.Sits(ply, ent) then
		return false
	end

	return true
end

-- A nextbot has none of the NPC's functions: it has no state and no enemy.
local function npcState(npc)
	if isfunction(npc.GetNPCState) then
		return npc:GetNPCState()
	end

	return NPC_STATE_NONE
end

-- What an entity that makes its own perception (a nextbot of another addon, the smart soldier) says about one player, through its method
-- ENT:GetGryAwareness(ply) -> level (0 calm, 1 alerted, 2 fighting), exposure (0 to 1), seen, heard. Called under GryMod.API.SafeCall (a broken
-- method is disabled after a few errors and never breaks the radar); the values are clamped. nil when the entity has no such method or the
-- call failed: the radar then keeps its own rule.
-- An entity that cannot get a method (a vehicle of another addon) says the same through the `awareness` field of its registry entry (the method wins when both exist).
function Radar.AwarenessOf(ent, ply)
	local fn = ent.GetGryAwareness
	local id

	if isfunction(fn) then
		id = "awareness:" .. (GryMod.API.ClassOf(ent) or ent:GetClass())
	else
		local entry = trackedOf(ent)

		if not entry or not entry.awareness then
			return nil
		end

		fn, id = entry.awareness, entry.awarenessId
	end

	local ok, level, exposure, seen, heard = GryMod.API.SafeCall(id, fn, ent, ply)

	if not ok then
		return nil
	end

	level = tonumber(level) or 0
	level = math.Clamp(math.floor(level), 0, 2)
	exposure = tonumber(exposure) or 0

	if exposure ~= exposure then
		exposure = 0
	end

	return {level = level, exposure = math.Clamp(exposure, 0, 1), seen = seen and true or false, heard = heard and true or false}
end

-- The alert level of a description (what Describe gives): the entity's own word when it reported one, the radar's rule from the NPC's state
-- and enemy otherwise.
function Radar.LevelOf(d)
	if d.awareLevel ~= nil then
		return d.awareLevel
	end

	return Radar.Level(d.state, d.enemyIsPlayer)
end

-- The alert level (0, 1, 2) of an NPC for a player, the radar's rule (Radar.Level) from the NPC's own state and enemy: the binoculars' hologram colours a hostile by it
-- (idle, alerted, in combat), as the original does. Anything that is not a living NPC is 0. An entity that reports its awareness gives its own level.
function Radar.AlertLevelOf(npc, ply)
	if not IsValid(npc) then
		return 0
	end

	local aware = Radar.AwarenessOf(npc, ply)

	if aware then
		return aware.level
	end

	local enemy = isfunction(npc.GetEnemy) and npc:GetEnemy() or nil

	return Radar.Level(npcState(npc), enemy ~= nil and enemy == ply)
end

-- What the rules need to know about an NPC (or a registered nextbot), for one player. The fields type, big, radar and noScan are
-- there only when the registry has an entry for it: type (the icon, 1 to 4) and big replace the ones of its class, radar says when
-- it is listed (see Step), noScan that the binoculars may not tag it. The relation comes through the relation chain, which asks the
-- registry too.
-- The way an entity faces, in degrees: its own yaw, except for a vehicle, which faces 90 degrees from it (MEASURED: the Buggy and the
-- airboat at yaw 0 face along +y): the rectangle on the radar points where it drives. The raw angles on both sides, the same rule
-- as the client's (Radar.Facing, cl_hud_radar_units.lua): the forward vector of a vehicle differs between the server and the client.
function Radar.Facing(ent)
	-- the registry says where an entity faces (`facing`: the world forward): a vector that is null or not a vector is no answer
	local entry = trackedOf(ent)

	if entry and entry.facing then
		local ok, forward = GryMod.API.SafeCall(entry.facingId, entry.facing, ent)

		if ok and isvector(forward) and forward.x == forward.x and forward.y == forward.y and (forward.x ~= 0 or forward.y ~= 0) then
			return forward:Angle().y
		end
	end

	local yaw = ent:GetAngles().y

	if ent:IsVehicle() then
		return yaw + 90
	end

	return yaw
end

-- What the occupants of a vehicle make it to the player: "hostile" if one of them is, else "ally" if one is, else "neutral". The player himself does not count.
-- `entry.crew(ent)` runs under SafeCall: a list of players and NPCs.
function Radar.CrewRelation(ply, ent, entry)
	local ok, crew = GryMod.API.SafeCall(entry.crewId, entry.crew, ent)

	if not ok or not istable(crew) then
		return "neutral"
	end

	local result = "neutral"

	for i = 1, #crew do
		local member = crew[i]

		if member ~= ply and (isentity(member) or istable(member)) and IsValid(member) then
			local relation = GryMod.Friendly.Relation(ply, member)

			if relation == "hostile" then
				return "hostile"
			elseif relation == "ally" then
				result = "ally"
			end
		end
	end

	return result
end

-- Whether the entry says the entity is destroyed (`dead`): a destroyed entity is not a contact and cannot be tagged.
function Radar.IsDeadEntry(ent, entry)
	if not entry or not entry.dead then
		return false
	end

	local ok, dead = GryMod.API.SafeCall(entry.deadId, entry.dead, ent)

	return ok and dead == true
end

function Radar.Describe(npc, ply)
	local pos = npc:GetPos()
	local enemy = isfunction(npc.GetEnemy) and npc:GetEnemy() or nil
	local relation = GryMod.Friendly.Relation(ply, npc)
	local tracked = trackedOf(npc)

	-- a vehicle is the colour of its crew when its entry lists one (`crew`: hostile if an occupant is, else allied if one is, else neutral), or of its
	-- driver (nobody, or a driver that is neither friend nor foe: neutral); an entry that says what the vehicle is to the player (a relation of its
	-- own) is not overridden. The vehicle is any entity that is not a creature: the vehicles of other addons are not engine vehicles (IsVehicle)
	if relation == "neutral" then
		if tracked and tracked.crew then
			relation = Radar.CrewRelation(ply, npc, tracked)
		elseif npc:IsVehicle() or not GryMod.API.IsCreature(npc) and not npc:IsNextBot() then
			local driver = Radar.DriverOf(npc)

			if driver and driver ~= ply then
				relation = GryMod.Friendly.Relation(ply, driver)
			end
		end
	end

	local seen, heard = false, false
	local aware = Radar.AwarenessOf(npc, ply)

	if aware then
		-- an entity that makes its own perception says what it sees and hears of this player
		seen, heard = aware.seen, aware.heard
	elseif isfunction(npc.HasCondition) and COND then
		-- what the engine's AI says about the player this very moment: it sees him, it hears his sounds (footsteps, shots); only an NPC has conditions
		seen = COND.SEE_PLAYER ~= nil and npc:HasCondition(COND.SEE_PLAYER) or false
		heard = COND.HEAR_PLAYER ~= nil and npc:HasCondition(COND.HEAR_PLAYER) or false
	end

	local d = {
		key = npc,
		id = npc:EntIndex(),
		seen = seen,
		heard = heard,
		class = GryMod.API.ClassOf(npc) or npc:GetClass(),
		relation = relation,
		hostile = relation == "hostile",
		ally = relation == "ally",
		state = npcState(npc),
		enemyIsPlayer = enemy == ply,
		health = npc:Health(),
		maxHealth = npc:GetMaxHealth(),
		x = pos.x, y = pos.y, z = pos.z,
		yaw = Radar.Facing(npc)
	}

	if aware then
		d.awareLevel = aware.level
		d.exposure = aware.exposure
	end

	if tracked then
		d.type = tracked.type
		d.radar = tracked.radar

		if tracked.size ~= nil then
			d.big = tracked.size == "big"
		end

		if tracked.scan == false then
			d.noScan = true
		end

		if tracked.dead then
			d.dead = Radar.IsDeadEntry(npc, tracked)
		end
	end

	return d
end

local weak = {__mode = "k"}

-- [player] = {tagged = {[key] = true}, markers = {[key] = the time it ends}, sent = the list the client has}
local states = setmetatable({}, weak)

function Radar.State(ply)
	local st = states[ply]

	if not st then
		st = {tagged = setmetatable({}, weak), markers = setmetatable({}, weak)}
		states[ply] = st
	end

	return st
end

-- The unit that hurt the player: marked for ten seconds, unless it is tagged or already marked (a second hit does not
-- start the ten seconds again).
function Radar.Mark(st, key, now)
	if st.tagged[key] or st.markers[key] then
		return
	end

	st.markers[key] = now + S.MARKER_SECONDS
end

-- The hook GryMod_TargetSpotted(ply, ent, relation): the player's binoculars spotted `ent` (the scan ended on it and the radar shows it from now on).
-- relation is what the entity is to the player ("ally", "neutral", "hostile"). A field so that a test can replace it. A listener that fails
-- is shown in the console and does not stop the tag.
function Radar.ReportSpotted(ply, ent)
	local ok, err = pcall(hook.Run, "GryMod_TargetSpotted", ply, ent, GryMod.Friendly.Relation(ply, ent))

	if not ok then
		ErrorNoHalt("[GryMod] A listener of GryMod_TargetSpotted failed: " .. tostring(err) .. "\n")
	end
end

-- The binoculars' scan ended on an NPC (the client counted the 0.55 s of the original's scanner): it is tagged for this
-- player, as if it had been noticed within 26 m, and stays on the radar until it dies. The ray of the binoculars is 300 m
-- long; a tenth more is allowed for the lag between the client's aim and the server's positions. Returns whether it was tagged.
local SCAN_METRES = 300 * 1.1

function Radar.Scan(ply, npc)
	if not IsValid(ply) or not ply:Alive() or not IsValid(npc) then
		return false
	end

	local tracked = trackedOf(npc)

	if Radar.IsDeadEntry(npc, tracked) then
		return false
	end

	if GryMod.API.IsCreature(npc) then
		if npc:Health() <= 0 then
			return false
		end
	elseif tracked and npc:IsNextBot() then
		-- a nextbot may have no health at all (0 of 0, like a rollermine): only one that lost its health is dead
		if npc:Health() <= 0 and npc:GetMaxHealth() > 0 then
			return false
		end
	elseif not Radar.IsObject(npc, ply, tracked) then
		-- (a vehicle or a mine: no health to look at, see IsObject)
		return false
	end

	if tracked and tracked.scan == false then
		return false
	end

	if ply:GetPos():Distance(npc:GetPos()) * S.METRES_PER_UNIT > SCAN_METRES then
		return false
	end

	local st = Radar.State(ply)
	local first = not st.tagged[npc]

	st.tagged[npc] = true
	st.markers[npc] = nil

	-- once, when the binoculars spot it for the first time: a report for the addons (nothing is read from it)
	if first then
		Radar.ReportSpotted(ply, npc)
	end

	return true
end

-- The rules. descs: what Describe gives for the NPCs around `origin` (the markers' too, wherever they are); st: the
-- state of the player; now: the time; alliesAlways: whether the allies show without being noticed (the convar when not told).
-- Returns the contacts {id, x, y, z, yaw, type, sub, marker, big}, the markers first then the nearest, no more than the
-- limit. sub: 0 tagged but neither hostile nor ally, 1 marker of one of those, 2 hostile and calm, 3 alerted, 4 fighting the
-- player, 5 (S.SUB_ALLY) an ally, in whatever state.
-- A description may carry what the registry of tracked entities says (Describe): `radar`: "always" (listed at once, in the colour
-- of its relation and state, whatever the allies switch says), "hostile" (the rules of the hostiles whatever its relation: alerted
-- or fighting within 26 m, or scanned; the allies switch does not apply), "scan" (only once scanned: its alert, a marker and the
-- allies switch do not list it), "never" (never listed); nothing: the rules above. `type` and `big` replace the ones of the class.
function Radar.Step(origin, descs, st, now, alliesAlways, range)
	local gate2 = S.GateUnits(range) ^ 2
	local scan2 = S.ScanUnits(range) ^ 2
	local list = {}

	if alliesAlways == nil then
		alliesAlways = Radar.AlliesAlways()
	end

	for i = 1, #descs do
		local d = descs[i]
		local key = d.key

		-- dead: no health left, unless it never had any (MEASURED: a rollermine has 0 of 0 health all its life and is removed
		-- when it is destroyed, so 0 health says nothing about it)
		if d.health <= 0 and (d.maxHealth == nil or d.maxHealth > 0) or d.state == NPC_STATE_DEAD or d.dead then
			st.tagged[key] = nil
			st.markers[key] = nil
		elseif d.radar == "never" then
			-- never on the radar: not by its alert, a scan, a marker or the allies switch
		else
			local mode = d.radar
			local dx, dy, dz = d.x - origin.x, d.y - origin.y, d.z - origin.z
			local distance2 = dx * dx + dy * dy + dz * dz
			-- the alert of an ally counts as a hostile's (its enemy is never the player, so level 1 at most): with the
			-- switch off it is how an ally gets noticed
			local watched

			if mode == "scan" then
				watched = false
			elseif mode == "hostile" then
				watched = true
			else
				watched = d.hostile or d.ally and not alliesAlways
			end

			-- shown like an enemy: the colours of its state (an ally keeps its own)
			local asHostile = d.hostile or mode == "hostile" and not d.ally
			-- (a hostile that can only be scanned is not noticed by its alert, but once scanned it shows its state's colour)
			local level = (watched or asHostile) and Radar.LevelOf(d) or 0
			local marker = st.markers[key]

			if marker and now > marker then
				st.markers[key] = nil
				marker = nil
			end

			if mode == "scan" then
				marker = nil
			end

			local tagged = st.tagged[key]

			if not tagged and watched and level >= 1 and distance2 <= gate2 then
				tagged = true
				st.tagged[key] = true
				st.markers[key] = nil
				marker = nil
			end

			local sub, isMarker

			if tagged then
				sub = d.ally and S.SUB_ALLY or asHostile and (2 + level) or 0
			elseif marker then
				sub = d.ally and S.SUB_ALLY or asHostile and 2 or 1
				isMarker = true
			elseif mode == "always" or d.ally and alliesAlways and mode == nil then
				sub = d.ally and S.SUB_ALLY or asHostile and (2 + level) or 0
			end

			if sub and (isMarker or distance2 <= scan2) then
				local kind, large = Radar.TypeOf(d.class)

				if d.type then
					kind = d.type
				end

				if d.big ~= nil then
					large = d.big
				end

				list[#list + 1] = {
					id = d.id, x = d.x, y = d.y, z = d.z, yaw = d.yaw, type = kind, sub = sub, marker = isMarker and true or false,
					big = large, distance2 = isMarker and -1 or distance2
				}
			end
		end
	end

	table.sort(list, function(a, b)
		if a.distance2 ~= b.distance2 then
			return a.distance2 < b.distance2
		end

		return a.id < b.id
	end)

	for i = #list, S.MAX_CONTACTS + 1, -1 do
		list[i] = nil
	end

	return list
end

-- The teams that say something: the engine's connecting, unassigned and spectator "teams" do not (Sandbox keeps everybody in the unassigned one).
local function realTeam(team)
	return team ~= nil and team ~= TEAM_CONNECTING and team ~= TEAM_UNASSIGNED and team ~= TEAM_SPECTATOR
end

-- Whether the game uses teams: at least two real teams have a player among `players`.
function Radar.TeamsInUse(players)
	local first

	for _, p in ipairs(players) do
		if IsValid(p) then
			local team = p:Team()

			if realTeam(team) then
				if first == nil then
					first = team
				elseif team ~= first then
					return true
				end
			end
		end
	end

	return false
end

-- The contacts of the team mates of `ply` among `players` (all the players when not given): the other living players of his team that are not
-- spectating, as type 7 icons (subtype 0, the original's), wherever they are (the client holds the far ones on the circle of the range). Nothing when
-- the switch is off or the game has no teams.
function Radar.Mates(ply, players)
	local mates = {}

	if not teammatesOn:GetBool() then
		return mates
	end

	players = players or player.GetAll()

	local team = ply:Team()

	if not realTeam(team) or not Radar.TeamsInUse(players) then
		return mates
	end

	for _, p in ipairs(players) do
		if p ~= ply and IsValid(p) and p:Team() == team and p:Alive() and p:GetObserverMode() == OBS_MODE_NONE then
			local at = p:GetPos()

			mates[#mates + 1] = {
				id = p:EntIndex(), x = at.x, y = at.y, z = at.z, yaw = p:GetAngles().y, type = 7, sub = 0, marker = false, big = false
			}
		end
	end

	return mates
end

-- The list with the mates added: they are never the ones to give way when the list is full, the farthest hostiles are. The list is changed and returned.
function Radar.AddMates(list, mates)
	if #mates == 0 then
		return list
	end

	for i = #list, S.MAX_CONTACTS - #mates + 1, -1 do
		list[i] = nil
	end

	for i = 1, math.min(#mates, S.MAX_CONTACTS) do
		list[#list + 1] = mates[i]
	end

	return list
end

-- What the hostiles that are NOT contacts know of the player, for the danger bar and the hexagon: two numbers, the highest over the soldiers and the highest over
-- the machines (icon types 2 and 3, S.VEHICLE_TYPES), each 0, 1 or 2. An NPC counts 2 when it has the player as enemy (it has seen him: the original's
-- exposure) or sees him now, 1 when it only hears him or has lost him and looks for him (an ALERT with the player as last enemy), else 0. A hostile
-- fighting someone else, or alert to something else, does not count: far away it says nothing about the player. descs: what Describe gives; listed:
-- [id] = true for the NPCs that are contacts (the contact list carries their state). Nothing while gry_radar_detect is off.
function Radar.Detect(descs, listed)
	local puppet, vehicle, exposure = 0, 0, 0

	if not detectOn:GetBool() then
		return puppet, vehicle, exposure
	end

	for i = 1, #descs do
		local d = descs[i]
		local mode = d.radar
		local counts = mode ~= "never" and mode ~= "scan" and (d.hostile or mode == "hostile" and not d.ally)
			and not (d.health <= 0 and (d.maxHealth == nil or d.maxHealth > 0)) and d.state ~= NPC_STATE_DEAD and not d.dead

		-- the exposure an entity reports (its own perception, contact or not): the stealth bar shows the highest
		if counts and d.exposure and d.exposure > exposure then
			exposure = d.exposure
		end

		if counts and not listed[d.id] then
			local level = 0

			if d.awareLevel ~= nil then
				level = d.awareLevel
			elseif d.enemyIsPlayer then
				level = Radar.Level(d.state, true)
			end

			if d.seen and level < 2 then
				level = 2
			elseif d.heard and level < 1 then
				level = 1
			end

			if level > 0 then
				local kind = d.type

				if not kind then
					kind = Radar.TypeOf(d.class)
				end

				if S.VEHICLE_TYPES[kind] then
					vehicle = math.max(vehicle, level)
				else
					puppet = math.max(puppet, level)
				end
			end
		end
	end

	return puppet, vehicle, exposure
end

-- Tells the player the two numbers of Radar.Detect when they changed since the last time (st.detectSent); an unchanged pair, and a pair of zeros for a player
-- that never had any, send nothing.
function Radar.SendDetect(ply, st, puppet, vehicle, exposure)
	-- the exposure goes on the wire as a step of 1/63: two values of the same step are the same message
	local step = S.ExposureStep(exposure)
	local last = st.detectSent

	if not last and puppet == 0 and vehicle == 0 and step == 0 or last and last[1] == puppet and last[2] == vehicle and last[3] == step then
		return
	end

	st.detectSent = (puppet ~= 0 or vehicle ~= 0 or step ~= 0) and {puppet, vehicle, step} or nil
	net.Start("gry_radar_detect")
	S.WriteDetect(puppet, vehicle, exposure)
	net.Send(ply)
end

local function send(ply, list)
	net.Start("gry_radar")
	S.Write(list)
	net.Send(ply)
end

-- Works out the contacts of one player and sends them when they changed. An empty list is sent once, when the contacts end.
function Radar.Tick(ply, now)
	if not IsValid(ply) then
		return
	end

	now = now or CurTime()
	local st = Radar.State(ply)
	local list = {}
	local puppet, vehicle, exposure = 0, 0, 0

	if enabled:GetBool() and ply.GryRadarWant and ply:Alive() then
		local origin = ply:GetPos()
		local descs, seen = {}, {}

		local range = S.ClampRange(ply.GryRadarRange)

		for _, ent in ipairs(ents.FindInSphere(origin, S.ScanUnits(range))) do
			if ent ~= ply and (GryMod.API.IsCreature(ent) or ent:IsNextBot() and trackedOf(ent) or Radar.IsObject(ent, ply)) then
				descs[#descs + 1] = Radar.Describe(ent, ply)
				seen[ent] = true
			end
		end

		for key in pairs(st.markers) do
			if IsValid(key) and not seen[key] then
				descs[#descs + 1] = Radar.Describe(key, ply)
			end
		end

		list = Radar.AddMates(Radar.Step(origin, descs, st, now, nil, range), Radar.Mates(ply))

		-- the hostiles that see or hear the player and are not contacts (the same descriptions: no new search, no new call per NPC beyond two conditions)
		local listed = {}

		for i = 1, #list do
			listed[list[i].id] = true
		end

		puppet, vehicle, exposure = Radar.Detect(descs, listed)
	end

	Radar.SendDetect(ply, st, puppet, vehicle, exposure)

	local last = st.sent

	if last and S.Same(last, list) or not last and #list == 0 then
		return
	end

	st.sent = list
	send(ply, list)
end

-- A player's death or respawn: the tags and the markers go, and the client is told if it had a list.
function Radar.Reset(ply)
	local st = states[ply]
	states[ply] = nil

	if st and st.detectSent and IsValid(ply) then
		Radar.SendDetect(ply, st, 0, 0, 0)
	end

	if st and st.sent and #st.sent > 0 and IsValid(ply) then
		send(ply, {})
	end
end

-- A hit counts whatever its amount: the suit's armor can take all of it before this hook runs (sv_health.lua sets the
-- damage to 0; the hooks run in no fixed order), and the original's hit event does not look at what the armor absorbed
-- either. The crosshair feedback (sv_feedback.lua) does ask for an amount, and gets the one from before the armor.
hook.Add("EntityTakeDamage", "GryMod radar", function(victim, dmg)
	if not IsValid(victim) or not victim:IsPlayer() then
		return
	end

	-- a hit that a filter of another addon makes the suit ignore (GryMod.API.AddHitFilter) marks nobody
	if GryMod.API.HitVerdict and GryMod.API.HitVerdict(victim, dmg) == "ignore" then
		return
	end

	local attacker = dmg:GetAttacker()

	if IsValid(attacker) and GryMod.API.IsCreature(attacker) then
		Radar.Mark(Radar.State(victim), attacker, CurTime())
	end
end)

hook.Add("PlayerSpawn", "GryMod radar", function(ply)
	-- a restore in place (GryMod_CanResetOnSpawn) keeps the tags and the markers: the same life goes on
	if GryMod.KeepStateOnSpawn and GryMod.KeepStateOnSpawn(ply) then
		return
	end

	Radar.Reset(ply)
end)

-- PostPlayerDeath: Player:KillSilent skips PlayerDeath
hook.Add("PostPlayerDeath", "GryMod radar", function(ply)
	Radar.Reset(ply)
end)

hook.Add("PlayerDisconnected", "GryMod radar", function(ply)
	states[ply] = nil
end)

-- The client says whether its HUD has the radar contacts on (the first thing it does with a radar, and at each change).
net.Receive("gry_radar_want", function(_, ply)
	if not IsValid(ply) then
		return
	end

	ply.GryRadarWant = net.ReadBool()
	-- the radius the player chose, in metres (8 bits; 0 or nothing from an older client is the original's 75)
	ply.GryRadarRange = S.ClampRange(net.ReadUInt(8))
end)

-- The client says which entity its binoculars scanned (13 bits, as the contacts' ids).
net.Receive("gry_radar_scan", function(_, ply)
	if not IsValid(ply) then
		return
	end

	Radar.Scan(ply, Entity(net.ReadUInt(13)))
end)

timer.Create("GryMod radar", INTERVAL, 0, function()
	for _, ply in ipairs(player.GetAll()) do
		local st = states[ply]

		if ply.GryRadarWant or (st and (st.sent or st.detectSent)) then
			Radar.Tick(ply)
		end
	end
end)

-- an entity that makes its own perception may report it (ENT:GetGryAwareness, Radar.AwarenessOf)
GryMod.API.AddFeature("awareness")
