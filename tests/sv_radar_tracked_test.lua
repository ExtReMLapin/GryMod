-- Tests of the radar contacts when entities are registered in the tracked entity registry (GryMod.Radar Describe / Scan / Step /
-- Tick, lua/grymod/server/sv_radar.lua), GLuaTest format, server realm. An entity that is NOT registered behaves exactly as before
-- (sv_radar_test.lua); an entry changes: the icon type and size, the relation (through the relation chain), when the contact is
-- listed (`radar`: always, hostile, scan, never) and whether the binoculars may tag it (`scan = false`). NPCs and nextbots are
-- looked at; the other entities (vehicles) are accepted by the registry and ignored by the radar for now.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, part 5.

local function ply()
	return player.GetAll()[1]
end

local R, S, API
local GATE, SCAN

local KEYS = {"t_rad_a", "t_rad_b"}
local NEXTBOT = "t_b2_nextbot"

local nextKey = 0

-- a described NPC (what Describe gives), `ahead` units in front of the origin
local function npc(ahead, extra)
	nextKey = nextKey + 1
	local d = {key = {}, id = 500 + nextKey, class = "npc_combine_s", relation = "hostile", hostile = true, ally = false, state = NPC_STATE_IDLE,
		enemyIsPlayer = false, health = 50, x = ahead, y = 0, z = 0, yaw = 0}

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

local function newState()
	return {tagged = setmetatable({}, {__mode = "k"}), markers = setmetatable({}, {__mode = "k"})}
end

local ORIGIN = Vector(0, 0, 0)

local function step(descs, st, now, alliesAlways)
	return R.Step(ORIGIN, descs, st or newState(), now or 0, alliesAlways)
end

-- the three kinds of relation a description can have
local function neutral(ahead, extra)
	local d = npc(ahead, {relation = "neutral", hostile = false})

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

local function ally(ahead, extra)
	local d = npc(ahead, {relation = "ally", hostile = false, ally = true})

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

-- net stubs: what a tick sends
local sent
local real = {}
local recording = false

local function startRecording()
	sent = {}
	recording = true
	real.Start, real.Send, real.WriteUInt, real.WriteInt, real.WriteBool = net.Start, net.Send, net.WriteUInt, net.WriteInt, net.WriteBool
	net.Start = function(name) sent[#sent + 1] = {name = name, values = {}} return true end
	net.WriteUInt = function(v) local m = sent[#sent] m.values[#m.values + 1] = v end
	net.WriteInt = function(v) local m = sent[#sent] m.values[#m.values + 1] = v end
	net.WriteBool = function(v) local m = sent[#sent] m.values[#m.values + 1] = v and 1 or 0 end
	net.Send = function(p) sent[#sent].to = p end
end

local function stopRecording()
	if not recording then return end
	recording = false
	net.Start, net.Send, net.WriteUInt, net.WriteInt, net.WriteBool = real.Start, real.Send, real.WriteUInt, real.WriteInt, real.WriteBool
end

-- one tick of the player's radar, the contacts of the message by entity index: {type, sub, big}
local function tickContacts(p, now)
	startRecording()
	local ok, err = pcall(R.Tick, p, now)
	stopRecording()

	if not ok then
		error(err, 0)
	end

	local list = {}
	local message = sent[#sent]

	if message then
		local values = message.values

		for i = 1, values[1] do
			local at = 2 + (i - 1) * 9 -- id, type, sub, marker, big, x, y, z, yaw
			list[values[at]] = {type = values[at + 1], sub = values[at + 2], big = values[at + 4] == 1}
		end
	end

	return list
end

local spawned = {}

local function spawnEnt(class, pos)
	local e = ents.Create(class)
	e:SetPos(pos)
	e:Spawn()
	spawned[#spawned + 1] = e

	return e
end

return {
	groupName = "GryMod radar contacts: tracked entities (server)",
	beforeAll = function(state)
		R, S, API = GryMod.Radar, GryMod.RadarShared, GryMod.API
		GATE, SCAN = S.GateUnits(), S.ScanUnits()

		scripted_ents.Register({Type = "nextbot", Base = "base_nextbot", Spawnable = false, Initialize = function(self)
			self:SetModel("models/props_junk/PopCan01a.mdl")
		end}, NEXTBOT)
	end,
	beforeEach = function(state)
		local c = GetConVar("gry_radar_allies_always")
		state.alliesAlways = c and c:GetString()

		if c then
			c:SetString("0")
		end

		local p = ply()

		if not p:Alive() then p:Spawn() end
	end,
	afterEach = function(state)
		pcall(stopRecording)

		local c = GetConVar("gry_radar_allies_always")

		if c and state.alliesAlways then
			c:SetString(state.alliesAlways)
		end

		for _, key in ipairs(KEYS) do
			API.UnregisterTracked(key)
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:SetPos(Vector(0, 0, -30000))
				e:Remove()
			end
		end

		spawned = {}
		local p = ply()

		if IsValid(p) and R then
			R.Reset(p)
			p.GryRadarWant = nil
		end
	end,
	cases = {
		{
			name = "radar = always: the contact is on the radar at once, calm and never scanned, in its relation's colour, whatever the allies switch says; past the radar's scan radius it is not",
			func = function()
				local st = newState()
				local foe, other, friend = npc(SCAN - 100, {radar = "always"}), neutral(SCAN - 120, {radar = "always"}), ally(SCAN - 140, {radar = "always"})
				local list = step({foe, other, friend}, st, 0, false)
				local bySub = {}

				for _, c in ipairs(list) do
					bySub[c.id] = c.sub
				end

				expect(#list).to.equal(3)
				expect(bySub[foe.id]).to.equal(2) -- a hostile that is calm
				expect(bySub[other.id]).to.equal(0) -- neither hostile nor ally
				expect(bySub[friend.id]).to.equal(S.SUB_ALLY)
				expect(next(st.tagged)).to.beNil() -- nothing remembered: the entry decides every time

				foe.x = SCAN + 100
				expect(#step({foe}, st, 0, false)).to.equal(0)
			end
		},
		{
			name = "radar = always: a hostile that is alerted or fighting shows its state's colour, as any hostile",
			func = function()
				local alerted = npc(500, {radar = "always", state = NPC_STATE_ALERT})
				local fighting = npc(600, {radar = "always", state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local list = step({alerted, fighting}, newState(), 0, false)

				expect(list[1].sub).to.equal(3)
				expect(list[2].sub).to.equal(4)
			end
		},
		{
			name = "radar = always: a dead one is gone",
			func = function()
				local st = newState()
				local d = ally(500, {radar = "always", health = 0})

				expect(#step({d}, st, 0, false)).to.equal(0)
			end
		},
		{
			name = "radar = hostile: the rules of the enemies whatever the relation: alerted within 26 m it is listed and tagged, calm it is not, an ally with it follows the enemy rule too (the allies switch does not apply)",
			func = function()
				local st = newState()
				local other = neutral(GATE - 10, {radar = "hostile", state = NPC_STATE_ALERT})
				local calm = neutral(GATE - 20, {radar = "hostile"})
				local list = step({other, calm}, st, 0, false)

				expect(#list).to.equal(1)
				expect(list[1].id).to.equal(other.id)
				expect(list[1].sub).to.equal(3) -- shown like an enemy: its alert is its colour
				expect(st.tagged[other.key]).to.beTrue()
				expect(st.tagged[calm.key]).to.beNil()

				local friend = ally(500, {radar = "hostile"})
				expect(#step({friend}, newState(), 0, true)).to.equal(0) -- calm: not at once, though the switch is on

				friend.state = NPC_STATE_COMBAT
				friend.x = GATE - 10
				list = step({friend}, newState(), 0, true)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(S.SUB_ALLY)
			end
		},
		{
			name = "radar = scan: only once scanned: its alert does not tag it, the allies switch does not show it, a marker does not show it; a scanned one is listed",
			func = function()
				local st = newState()
				local foe = npc(GATE - 10, {radar = "scan", state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local friend = ally(500, {radar = "scan"})

				expect(#step({foe, friend}, st, 0, true)).to.equal(0)
				expect(st.tagged[foe.key]).to.beNil()

				R.Mark(st, foe.key, 0)
				expect(#step({foe}, st, 1, true)).to.equal(0)

				st.tagged[foe.key] = true
				st.tagged[friend.key] = true
				local list = step({foe, friend}, st, 1, true)

				expect(#list).to.equal(2)
				expect(list[1].id).to.equal(friend.id) -- the nearest first
				expect(list[1].sub).to.equal(S.SUB_ALLY)
				expect(list[2].id).to.equal(foe.id)
				expect(list[2].sub).to.equal(4) -- a scanned hostile has its state's colour
			end
		},
		{
			name = "radar = never: never listed: not by its alert, not scanned, not as a marker, not as an ally that is on the radar at once",
			func = function()
				local st = newState()
				local foe = npc(GATE - 10, {radar = "never", state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local friend = ally(500, {radar = "never"})

				expect(#step({foe, friend}, st, 0, true)).to.equal(0)
				expect(st.tagged[foe.key]).to.beNil()

				st.tagged[foe.key] = true
				R.Mark(st, friend.key, 0)
				expect(#step({foe, friend}, st, 1, true)).to.equal(0)
			end
		},
		{
			name = "a description without a radar field follows the rules as before (the switch decides for the allies)",
			func = function()
				local friend = ally(500)

				expect(#step({friend}, newState(), 0, true)).to.equal(1)
				expect(#step({friend}, newState(), 0, false)).to.equal(0)
			end
		},
		{
			name = "the type and the size of a description replace the ones of its class; with none the class decides as before",
			func = function()
				local list = step({npc(100, {type = 2}), npc(200, {type = 3, big = true}), npc(300, {class = "npc_strider"}), npc(400, {class = "npc_strider", type = 1})}, newState(), 0, nil)

				-- not alerted and not always: none is listed, so make them listed with the radar rule
				expect(#list).to.equal(0)

				local descs = {npc(100, {type = 2, radar = "always"}), npc(200, {type = 3, big = true, radar = "always"}), npc(300, {class = "npc_strider", radar = "always"}), npc(400, {class = "npc_strider", type = 1, radar = "always"}), npc(500, {radar = "always"})}
				list = step(descs, newState(), 0, nil)

				expect(#list).to.equal(5)
				expect(list[1].type).to.equal(2)
				expect(list[1].big).to.beFalse()
				expect(list[2].type).to.equal(3)
				expect(list[2].big).to.beTrue()
				expect(list[3].type).to.equal(3) -- the class of a strider
				expect(list[3].big).to.beTrue()
				expect(list[4].type).to.equal(1) -- the entry's type
				expect(list[4].big).to.beTrue() -- the entry gave no size: the class's
				expect(list[5].type).to.equal(1)
				expect(list[5].big).to.beFalse()
			end
		},
		{
			name = "Describe of an NPC that is not registered gives nothing more than before (no type, size, radar or scan field)",
			func = function()
				local p = ply()
				local e = spawnEnt("npc_citizen", p:GetPos() + Vector(300, 0, 0))
				local d = R.Describe(e, p)

				expect(d.type).to.beNil()
				expect(d.big).to.beNil()
				expect(d.radar).to.beNil()
				expect(d.noScan).to.beNil()
			end
		},
		{
			name = "Describe of a registered NPC gives its entry's type, size and radar rule, and its relation (through the chain)",
			func = function()
				local p = ply()
				local e = spawnEnt("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				e:AddEntityRelationship(p, D_HT, 99)
				API.RegisterTracked("t_rad_a", {class = "npc_zombie", radar = "always", relation = "ally", type = "machine", size = "big", scan = false})

				local d = R.Describe(e, p)

				expect(d.type).to.equal(3)
				expect(d.big).to.beTrue()
				expect(d.radar).to.equal("always")
				expect(d.noScan).to.beTrue()
				expect(d.relation).to.equal("ally")
				expect(d.ally).to.beTrue()
				expect(d.hostile).to.beFalse()
				expect(d.class).to.equal("npc_zombie")
			end
		},
		{
			name = "Scan: an entry with scan = false cannot be tagged by the binoculars, one with scan true (the default) can, an NPC that is not registered can as before",
			func = function()
				local p = ply()
				local near = spawnEnt("npc_combine_s", p:GetPos() + Vector(400, 0, 20))
				local other = spawnEnt("npc_citizen", p:GetPos() + Vector(400, 100, 20))
				local plain = spawnEnt("npc_zombie", p:GetPos() + Vector(400, 200, 20))
				local st = R.State(p)

				API.RegisterTracked("t_rad_a", {class = "npc_combine_s", scan = false})
				API.RegisterTracked("t_rad_b", {class = "npc_citizen"})

				expect(R.Scan(p, near)).to.beFalse()
				expect(st.tagged[near]).to.beNil()
				expect(R.Scan(p, other)).to.beTrue()
				expect(st.tagged[other]).to.beTrue()
				expect(R.Scan(p, plain)).to.beTrue()
			end
		},
		{
			name = "a nextbot that is registered can be tagged by a scan (it has no NPC state, and its health may be 0 of 0 like a rollermine's); one that is not registered cannot",
			func = function()
				local p = ply()
				local bot = spawnEnt(NEXTBOT, p:GetPos() + Vector(400, 0, 20))
				local st = R.State(p)

				expect(R.Scan(p, bot)).to.beFalse()
				expect(st.tagged[bot]).to.beNil()

				API.RegisterTracked("t_rad_a", {class = NEXTBOT})
				expect(R.Scan(p, bot)).to.beTrue()
				expect(st.tagged[bot]).to.beTrue()
			end
		},
		{
			name = "Describe of a registered nextbot works without the NPC functions it lacks: neutral state, no enemy, the entry's relation",
			func = function()
				local p = ply()
				local bot = spawnEnt(NEXTBOT, p:GetPos() + Vector(300, 0, 20))

				API.RegisterTracked("t_rad_a", {class = NEXTBOT, relation = "hostile", type = "flying"})
				local d = R.Describe(bot, p)

				expect(d.key).to.equal(bot)
				expect(d.id).to.equal(bot:EntIndex())
				expect(d.relation).to.equal("hostile")
				expect(d.hostile).to.beTrue()
				expect(d.type).to.equal(2)
				expect(d.enemyIsPlayer).to.beFalse()
				expect(d.state).to.equal(NPC_STATE_NONE)
			end
		},
		{
			name = "a tick lists a real NPC registered as always visible in its entry's colour, type and size, with the allies switch off; once the entry goes, the calm hostile is not listed",
			func = function()
				local p = ply()
				local e = spawnEnt("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				p.GryRadarWant = true
				e:AddEntityRelationship(p, D_HT, 99)
				API.RegisterTracked("t_rad_a", {class = "npc_zombie", radar = "always", relation = "ally", type = "machine", size = "big"})

				local list = tickContacts(p, 50)
				local c = list[e:EntIndex()]

				expect(c).toNot.beNil()
				expect(c.sub).to.equal(S.SUB_ALLY)
				expect(c.type).to.equal(3)
				expect(c.big).to.beTrue()

				API.UnregisterTracked("t_rad_a")
				list = tickContacts(p, 51)
				expect(list[e:EntIndex()]).to.beNil()
			end
		},
		{
			name = "a tick never lists a real NPC registered as radar = never, even alerted next to the player",
			func = function()
				local p = ply()
				local e = spawnEnt("npc_zombie", p:GetPos() + Vector(300, 0, 0))

				p.GryRadarWant = true
				e:AddEntityRelationship(p, D_HT, 99)
				e:SetNPCState(NPC_STATE_ALERT)

				local list = tickContacts(p, 50)
				expect(list[e:EntIndex()]).toNot.beNil() -- not registered: the alert lists it, as before

				API.RegisterTracked("t_rad_a", {class = "npc_zombie", radar = "never"})
				R.Reset(p) -- a new list is worked out from nothing (an unchanged list is not sent at all)
				p.GryRadarWant = true
				list = tickContacts(p, 51)
				expect(list[e:EntIndex()]).to.beNil()
			end
		},
		{
			name = "a tick lists a registered nextbot (the radar looked at NPCs only), with its entry's type, and not an unregistered one",
			func = function()
				local p = ply()
				local bot = spawnEnt(NEXTBOT, p:GetPos() + Vector(300, 0, 20))

				p.GryRadarWant = true
				local list = tickContacts(p, 50)
				expect(list[bot:EntIndex()]).to.beNil()

				API.RegisterTracked("t_rad_a", {class = NEXTBOT, radar = "always", relation = "hostile", type = "flying"})
				list = tickContacts(p, 51)

				expect(list[bot:EntIndex()]).toNot.beNil()
				expect(list[bot:EntIndex()].type).to.equal(2)
				expect(list[bot:EntIndex()].sub).to.equal(2) -- a hostile, calm
			end
		}
	}
}
