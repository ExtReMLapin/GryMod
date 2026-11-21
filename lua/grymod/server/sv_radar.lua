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
--   - the icon type: 1 ground, 2 flying, 3 machines (the registry's `type` and `size`: the stock classes are entries too).
--   - the registry of tracked entities (GryMod.API.RegisterTracked, sh_api_tracked.lua) overrides all this for the NPCs and
--     nextbots it matches: the icon type and size, the relation, when the contact is listed (radar = "always", "hostile",
--     "scan" or "never") and whether the binoculars may tag it (scan = false); an entity that is not registered is as above.
-- Cost: one timer every fifth of a second that only looks at the players that asked for the contacts (their HUD has the
-- radar on); one ents.FindInSphere around each of them, filtered by IsNPC; nothing is sent when the list did not change.

util.AddNetworkString("gry_radar")
util.AddNetworkString("gry_radar_want")
util.AddNetworkString("gry_radar_scan")

GryMod = GryMod or {}

local Radar = GryMod.Radar or {}
GryMod.Radar = Radar

local S = GryMod.RadarShared

local enabled = CreateConVar("gry_radar_contacts", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY),
	"The radar of the HUD shows the NPCs that are alerted to the player and the ones that shot at him; 0 turns the contacts off")

-- replicated and archived like the other server options, so that the options panel of an administrator shows the real value
local alliesAlways = CreateConVar("gry_radar_allies_always", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The allies of the player (NPCs that like him) are on the radar at once, in blue; 0 treats them like the hostiles: only when alerted or fighting within 26 m, or scanned")

local INTERVAL = 0.2

-- Whether the allies are on the radar without having been noticed.
function Radar.AlliesAlways()
	return alliesAlways:GetBool()
end

-- The state of the AI as the original's alert level: 2 when the NPC is fighting the player, 1 when it is alerted (it heard
-- something, is looking for him, or fights someone else), 0 otherwise. Having the player as enemy is level 2 whatever the
-- state says: the machines have no useful one (MEASURED on gm_construct: a floor turret that shoots the player stays in
-- NPC_STATE_IDLE with the player as its enemy; a ceiling turret and a camera stay in NPC_STATE_NONE); only a lost player
-- (ALERT, which can keep the last enemy) stays level 1, and a dead NPC is nothing.
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
		return 1
	end

	return 0
end

-- The icon of the original: 1 infantry, 2 helicopters, 3 other vehicles and machines, and whether it is drawn twice the size (the
-- original doubles the Hunter and the Alien warrior). Which class has which is the registry's (the `type` and `size` fields of
-- GryMod.API.RegisterTracked, sh_api_tracked.lua): the Half-Life 2 classes are registered as data in sh_api_tracked_hl2.lua and
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

-- A nextbot has none of the NPC's functions: it has no state and no enemy.
local function npcState(npc)
	if isfunction(npc.GetNPCState) then
		return npc:GetNPCState()
	end

	return NPC_STATE_NONE
end

-- What the rules need to know about an NPC (or a registered nextbot), for one player. The fields type, big, radar and noScan are
-- there only when the registry has an entry for it: type (the icon, 1 to 3) and big replace the ones of its class, radar says when
-- it is listed (see Step), noScan that the binoculars may not tag it. The relation comes through the relation chain, which asks the
-- registry too.
function Radar.Describe(npc, ply)
	local pos = npc:GetPos()
	local enemy = isfunction(npc.GetEnemy) and npc:GetEnemy() or nil
	local relation = GryMod.Friendly.Relation(ply, npc)
	local tracked = trackedOf(npc)

	local d = {
		key = npc,
		id = npc:EntIndex(),
		class = npc:GetClass(),
		relation = relation,
		hostile = relation == "hostile",
		ally = relation == "ally",
		state = npcState(npc),
		enemyIsPlayer = enemy == ply,
		health = npc:Health(),
		maxHealth = npc:GetMaxHealth(),
		x = pos.x, y = pos.y, z = pos.z,
		yaw = npc:GetAngles().y
	}

	if tracked then
		d.type = tracked.type
		d.radar = tracked.radar

		if tracked.size ~= nil then
			d.big = tracked.size == "big"
		end

		if tracked.scan == false then
			d.noScan = true
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

-- The binoculars' scan ended on an NPC (the client counted the 0.55 s of the original's scanner): it is tagged for this
-- player, as if it had been noticed within 26 m, and stays on the radar until it dies. The ray of the binoculars is 300 m
-- long; a tenth more is allowed for the lag between the client's aim and the server's positions. Returns whether it was tagged.
local SCAN_METRES = 300 * 1.1

function Radar.Scan(ply, npc)
	if not IsValid(ply) or not ply:Alive() or not IsValid(npc) then
		return false
	end

	local tracked = trackedOf(npc)

	if npc:IsNPC() then
		if npc:Health() <= 0 then
			return false
		end
	elseif tracked and npc:IsNextBot() then
		-- a nextbot may have no health at all (0 of 0, like a rollermine): only one that lost its health is dead
		if npc:Health() <= 0 and npc:GetMaxHealth() > 0 then
			return false
		end
	else
		return false
	end

	if tracked and tracked.scan == false then
		return false
	end

	if ply:GetPos():Distance(npc:GetPos()) * S.METRES_PER_UNIT > SCAN_METRES then
		return false
	end

	local st = Radar.State(ply)
	st.tagged[npc] = true
	st.markers[npc] = nil

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
function Radar.Step(origin, descs, st, now, alliesAlways)
	local gate2 = S.GateUnits() ^ 2
	local scan2 = S.ScanUnits() ^ 2
	local list = {}

	if alliesAlways == nil then
		alliesAlways = Radar.AlliesAlways()
	end

	for i = 1, #descs do
		local d = descs[i]
		local key = d.key

		-- dead: no health left, unless it never had any (MEASURED: a rollermine has 0 of 0 health all its life and is removed
		-- when it is destroyed, so 0 health says nothing about it)
		if d.health <= 0 and (d.maxHealth == nil or d.maxHealth > 0) or d.state == NPC_STATE_DEAD then
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
			local level = (watched or asHostile) and Radar.Level(d.state, d.enemyIsPlayer) or 0
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

	if enabled:GetBool() and ply.GryRadarWant and ply:Alive() then
		local origin = ply:GetPos()
		local descs, seen = {}, {}

		for _, ent in ipairs(ents.FindInSphere(origin, S.ScanUnits())) do
			if ent ~= ply and (ent:IsNPC() or ent:IsNextBot() and trackedOf(ent)) then
				descs[#descs + 1] = Radar.Describe(ent, ply)
				seen[ent] = true
			end
		end

		for key in pairs(st.markers) do
			if IsValid(key) and not seen[key] then
				descs[#descs + 1] = Radar.Describe(key, ply)
			end
		end

		list = Radar.Step(origin, descs, st, now)
	end

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

	local attacker = dmg:GetAttacker()

	if IsValid(attacker) and attacker:IsNPC() then
		Radar.Mark(Radar.State(victim), attacker, CurTime())
	end
end)

hook.Add("PlayerSpawn", "GryMod radar", function(ply)
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

		if ply.GryRadarWant or (st and st.sent) then
			Radar.Tick(ply)
		end
	end
end)
