-- Tests of the radar contacts the server works out and sends (GryMod.Radar, sv_radar.lua), GLuaTest format, server realm.
-- The rules are those of the original's CHUDRadar::Update, see docs/superpowers/plans/2026-11-21-radar-research.md.

local function ply()
	return player.GetAll()[1]
end

local R -- GryMod.Radar, set in beforeAll

local GATE = nil -- units, set in beforeAll
local SCAN = nil

-- a described NPC (what Radar.Describe gives), `ahead` units in front of the origin
local nextKey = 0

local function npc(ahead, extra)
	nextKey = nextKey + 1
	local d = {key = {}, id = 100 + nextKey, class = "npc_combine_s", hostile = true, state = NPC_STATE_IDLE, enemyIsPlayer = false,
		health = 50, x = ahead, y = 0, z = 0, yaw = 0}

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

-- an ally (what Describe gives for an NPC that likes the player)
local function ally(ahead, extra)
	local d = npc(ahead, {hostile = false, ally = true, relation = "ally"})

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

local spawned = {}

local function spawnNPC(class, pos)
	local e = ents.Create(class)
	e:SetPos(pos)
	e:Spawn()
	spawned[#spawned + 1] = e

	return e
end

return {
	groupName = "GryMod radar contacts (server)",
	beforeAll = function(state)
		R = GryMod.Radar
		GATE = GryMod.RadarShared and GryMod.RadarShared.GateUnits()
		SCAN = GryMod.RadarShared and GryMod.RadarShared.ScanUnits()
	end,
	beforeEach = function(state)
		-- the radar's switch in a known state for every case: allies off, so that the entities other files left behind (a
		-- removed entity lives until the end of the frame) are not contacts; the cases of the allies set it themselves
		local c = GetConVar("gry_radar_allies_always")
		state.alliesAlways = c and c:GetString()

		if c then
			c:SetString("0")
		end
	end,
	afterEach = function(state)
		if stopRecording then pcall(stopRecording) end

		local c = GetConVar("gry_radar_allies_always")

		if c and state.alliesAlways then
			c:SetString(state.alliesAlways)
		end

		-- a removed entity lives until the end of the frame and a whole run is one frame: send it far away too, so that the
		-- next case does not find it in its search
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
			name = "the two messages and the switch exist",
			func = function(state)
				expect(util.NetworkStringToID("gry_radar") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_radar_want") ~= 0).to.beTrue()
				expect(GetConVar("gry_radar_contacts")).toNot.beNil()
				expect(GetConVar("gry_radar_contacts"):GetInt()).to.equal(1)
			end
		},
		{
			name = "the alert level: combat with the player as enemy is 2, any other alert is 1, calm is 0",
			func = function(state)
				expect(R.Level(NPC_STATE_COMBAT, true)).to.equal(2)
				expect(R.Level(NPC_STATE_COMBAT, false)).to.equal(1)
				expect(R.Level(NPC_STATE_ALERT, false)).to.equal(1)
				expect(R.Level(NPC_STATE_ALERT, true)).to.equal(1)
				expect(R.Level(NPC_STATE_IDLE, false)).to.equal(0)
				expect(R.Level(NPC_STATE_NONE, false)).to.equal(0)
				expect(R.Level(NPC_STATE_DEAD, false)).to.equal(0)
				expect(R.Level(NPC_STATE_SCRIPT, false)).to.equal(0)
				expect(R.Level(nil, false)).to.equal(0)
			end
		},
		{
			name = "the icon type: ground units 1, flying 2, machines 3 (the heavy ones are big), unknown classes 1",
			func = function(state)
				local t, big = R.TypeOf("npc_combine_s")
				expect(t).to.equal(1)
				expect(big).to.beFalse()
				expect(R.TypeOf("npc_zombie")).to.equal(1)
				expect(R.TypeOf("npc_antlion")).to.equal(1)
				expect(R.TypeOf("something_else")).to.equal(1)

				for _, class in ipairs({"npc_combinegunship", "npc_helicopter", "npc_combinedropship", "npc_cscanner", "npc_clawscanner", "npc_manhack"}) do
					expect(R.TypeOf(class)).to.equal(2)
				end

				for _, class in ipairs({"npc_strider", "npc_hunter"}) do
					t, big = R.TypeOf(class)
					expect(t).to.equal(3)
					expect(big).to.beTrue()
				end

				for _, class in ipairs({"npc_turret_floor", "npc_turret_ceiling", "npc_rollermine"}) do
					t, big = R.TypeOf(class)
					expect(t).to.equal(3)
					expect(big).to.beFalse()
				end

				t, big = R.TypeOf("npc_antlionguard")
				expect(t).to.equal(1)
				expect(big).to.beTrue()
			end
		},
		{
			name = "the icon type is read from the registry of tracked entities, no class table of the radar: a class registered by an addon has its icon, an earlier registration beats the stock one",
			func = function(state)
				local API = GryMod.API
				expect(R.Flying).to.beNil()
				expect(R.Machines).to.beNil()
				expect(R.Big).to.beNil()

				expect(API.RegisterTracked("t_radar_big_flyer", {class = "t_npc_flyer", type = "flying", size = "big"})).to.beTrue()
				expect(API.RegisterTracked("t_radar_strider", {class = "npc_strider", type = "human"})).to.beTrue()
				local ok, err = pcall(function()
					local t, big = R.TypeOf("t_npc_flyer")
					expect(t).to.equal(2)
					expect(big).to.beTrue()
					t, big = R.TypeOf("npc_strider")
					expect(t).to.equal(1)
					expect(big).to.beFalse()
				end)
				API.UnregisterTracked("t_radar_big_flyer")
				API.UnregisterTracked("t_radar_strider")
				if not ok then error(err, 0) end

				local t, big = R.TypeOf("npc_strider")
				expect(t).to.equal(3)
				expect(big).to.beTrue()
				expect(R.TypeOf("t_npc_flyer")).to.equal(1)
			end
		},
		{
			name = "a hostile NPC that is fighting the player within 26 m is listed in the attack colour and tagged",
			func = function(state)
				local st = newState()
				local d = npc(GATE - 10, {state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local list = step({d}, st)
				expect(#list).to.equal(1)
				expect(list[1].id).to.equal(d.id)
				expect(list[1].sub).to.equal(4)
				expect(list[1].type).to.equal(1)
				expect(list[1].marker).to.beFalse()
				expect(list[1].x).to.equal(GATE - 10)
				expect(st.tagged[d.key]).to.beTrue()
			end
		},
		{
			name = "an alerted hostile NPC within 26 m is shown in the alert colour",
			func = function(state)
				local list = step({npc(GATE - 10, {state = NPC_STATE_ALERT})})
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(3)
			end
		},
		{
			name = "an alerted hostile NPC farther than 26 m is not shown and not tagged, a calm one near is not either",
			func = function(state)
				local st = newState()
				local far = npc(GATE + 100, {state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local calm = npc(100, {state = NPC_STATE_IDLE})
				expect(#step({far, calm}, st)).to.equal(0)
				expect(st.tagged[far.key]).to.beNil()
				expect(st.tagged[calm.key]).to.beNil()
			end
		},
		{
			name = "a tagged NPC stays on the radar at any distance of the scan, in the colour of its present state, calm included",
			func = function(state)
				local st = newState()
				local d = npc(GATE - 10, {state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				step({d}, st)
				d.x = 3000 -- it was spotted, then it is far
				local list = step({d}, st)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(4)
				d.state = NPC_STATE_ALERT
				expect(step({d}, st)[1].sub).to.equal(3)
				d.state = NPC_STATE_IDLE
				d.enemyIsPlayer = false
				expect(step({d}, st)[1].sub).to.equal(2)
			end
		},
		{
			name = "losing the player does not untag a unit, its death does",
			func = function(state)
				local st = newState()
				local d = npc(500, {state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				step({d}, st)
				d.state = NPC_STATE_IDLE
				d.enemyIsPlayer = false -- it lost the player (an idle NPC that still had him as enemy would count as fighting)
				expect(#step({d}, st)).to.equal(1)
				d.health = 0
				expect(#step({d}, st)).to.equal(0)
				expect(st.tagged[d.key]).to.beNil()
				d.health = 50 -- it cannot come back, but the tag does not either
				expect(#step({d}, st)).to.equal(0)
			end
		},
		{
			name = "a tagged unit past the scan radius is not listed, and is listed again when it comes back",
			func = function(state)
				local st = newState()
				local d = npc(500, {state = NPC_STATE_ALERT})
				step({d}, st)
				d.x = SCAN + 500
				expect(#step({d}, st)).to.equal(0)
				expect(st.tagged[d.key]).to.beTrue()
				d.x = SCAN - 500
				expect(#step({d}, st)).to.equal(1)
			end
		},
		{
			name = "a friendly or neutral NPC is never tagged by its alert, a tagged one that turned friendly is dim",
			func = function(state)
				local st = newState()
				local friend = npc(500, {hostile = false, state = NPC_STATE_COMBAT})
				expect(#step({friend}, st)).to.equal(0)
				expect(st.tagged[friend.key]).to.beNil()
				local d = npc(500, {state = NPC_STATE_ALERT})
				step({d}, st)
				d.hostile = false
				local list = step({d}, st)
				expect(list[1].sub).to.equal(0)
			end
		},
		{
			name = "an NPC that hurt the player is marked for ten seconds, on the border, and the mark does not restart",
			func = function(state)
				local st = newState()
				local d = npc(SCAN + 5000, {state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				R.Mark(st, d.key, 100)
				local list = step({d}, st, 100)
				expect(#list).to.equal(1) -- a marker is listed at any distance
				expect(list[1].marker).to.beTrue()
				expect(list[1].sub).to.equal(2) -- hostile
				-- a second hit does not renew it
				R.Mark(st, d.key, 105)
				expect(#step({d}, st, 109.9)).to.equal(1)
				expect(#step({d}, st, 110.1)).to.equal(0)
				expect(st.markers[d.key]).to.beNil()
			end
		},
		{
			name = "a marker of a non hostile attacker has the other colour, a tagged one is shown as tagged, not as a marker",
			func = function(state)
				local st = newState()
				local d = npc(500, {hostile = false})
				R.Mark(st, d.key, 0)
				local list = step({d}, st, 1)
				expect(list[1].marker).to.beTrue()
				expect(list[1].sub).to.equal(1)
				local tagged = npc(500, {state = NPC_STATE_ALERT})
				step({tagged}, st, 1)
				R.Mark(st, tagged.key, 1)
				expect(st.markers[tagged.key]).to.beNil()
			end
		},
		{
			name = "a dead attacker's marker is not shown",
			func = function(state)
				local st = newState()
				local d = npc(500)
				R.Mark(st, d.key, 0)
				d.health = 0
				expect(#step({d}, st, 1)).to.equal(0)
			end
		},
		{
			name = "the list is sorted by distance with the markers first and cut at the limit",
			func = function(state)
				local st = newState()
				local descs = {}

				for i = 1, GryMod.RadarShared.MAX_CONTACTS + 20 do
					descs[i] = npc(10 + i, {state = NPC_STATE_ALERT})
				end

				local far = npc(SCAN - 10, {})
				R.Mark(st, far.key, 0)
				descs[#descs + 1] = far
				local list = step(descs, st, 1)
				expect(#list).to.equal(GryMod.RadarShared.MAX_CONTACTS)
				expect(list[1].id).to.equal(far.id) -- the marker first
				expect(list[2].id).to.equal(descs[1].id)
				expect(list[3].id).to.equal(descs[2].id)
			end
		},
		{
			name = "a described real NPC has its class, hostility, state, enemy, health, position and yaw",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				e:SetAngles(Angle(0, 90, 0))
				local d = R.Describe(e, p)
				expect(d.key).to.equal(e)
				expect(d.id).to.equal(e:EntIndex())
				expect(d.class).to.equal("npc_zombie")
				expect(d.health).to.equal(e:Health())
				expect(d.hostile).to.equal(e:Disposition(p) == D_HT)
				expect(d.state).to.equal(e:GetNPCState())
				expect(d.enemyIsPlayer).to.equal(e:GetEnemy() == p)
				expect(math.abs(d.x - e:GetPos().x) < 0.01).to.beTrue()
				expect(math.abs(d.yaw - 90) < 1).to.beTrue()
			end
		},
		{
			name = "the alert level: the NPC that has the player as enemy is level 2 whatever state it reports (machines have none), a lost player stays 1",
			func = function(state)
				expect(R.Level(NPC_STATE_IDLE, true)).to.equal(2)
				expect(R.Level(NPC_STATE_NONE, true)).to.equal(2)
				expect(R.Level(NPC_STATE_SCRIPT, true)).to.equal(2)
				expect(R.Level(NPC_STATE_COMBAT, true)).to.equal(2)
				expect(R.Level(NPC_STATE_ALERT, true)).to.equal(1)
				expect(R.Level(NPC_STATE_DEAD, true)).to.equal(0)
				expect(R.Level(NPC_STATE_IDLE, false)).to.equal(0)
			end
		},
		{
			name = "a floor turret that stays idle with the player as enemy is on the radar as fighting (measured: state IDLE, enemy the player)",
			func = function(state)
				local st = newState()
				local d = npc(GATE - 10, {class = "npc_turret_floor", health = 100, maxHealth = 100, state = NPC_STATE_IDLE, enemyIsPlayer = true})
				local list = step({d}, st)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(4)
				expect(list[1].type).to.equal(3)
				expect(st.tagged[d.key]).to.beTrue()
			end
		},
		{
			name = "a rollermine has no health (0 of 0, measured): chasing the player it is a contact, without an enemy it is none, a dead NPC with max health is still gone",
			func = function(state)
				local chasing = npc(GATE - 10, {class = "npc_rollermine", health = 0, maxHealth = 0, state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				local list = step({chasing})
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(4)
				expect(list[1].type).to.equal(3)
				expect(list[1].big).to.beFalse()
				local idle = npc(GATE - 10, {class = "npc_rollermine", health = 0, maxHealth = 0, state = NPC_STATE_IDLE, enemyIsPlayer = false})
				expect(#step({idle})).to.equal(0)
				local dead = npc(GATE - 10, {health = 0, maxHealth = 50, state = NPC_STATE_COMBAT, enemyIsPlayer = true})
				expect(#step({dead})).to.equal(0)
				local gone = npc(GATE - 10, {class = "npc_rollermine", health = 0, maxHealth = 0, state = NPC_STATE_DEAD})
				expect(#step({gone})).to.equal(0)
			end
		},
		{
			name = "a real rollermine is described with its max health, and a chasing one (state forced) is a contact",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_rollermine", p:GetPos() + Vector(-300, 0, 20))
				e:AddEntityRelationship(p, D_HT, 99)
				local d = R.Describe(e, p)
				expect(d.maxHealth).to.equal(e:GetMaxHealth())
				expect(d.hostile).to.beTrue()
				d.state, d.enemyIsPlayer = NPC_STATE_COMBAT, true
				local list = R.Step(p:GetPos(), {d}, newState(), 0)
				expect(#list).to.equal(1)
				expect(list[1].type).to.equal(3)
				expect(list[1].sub).to.equal(4)
			end
		},
		{
			name = "friendly NPCs (D_LI) around the player, with the allies switch off: calm ones are no contact, alerted or fighting ones within 26 m are, in the ally colour",
			func = function(state)
				local p = ply()
				p.GryRadarWant = true
				local friends = {}
				for i = 1, 3 do
					local e = spawnNPC("npc_citizen", p:GetPos() + Vector(-250 - 40 * i, 0, 10))
					e:AddEntityRelationship(p, D_LI, 99)
					e:SetNPCState(i == 1 and NPC_STATE_ALERT or NPC_STATE_COMBAT)
					friends[#friends + 1] = e
				end
				local d = R.Describe(friends[1], p)
				expect(d.hostile).to.beFalse()
				local descs = {R.Describe(friends[1], p), R.Describe(friends[2], p), R.Describe(friends[3], p)}
				-- calm: nothing, and nothing is sent
				for _, each in ipairs(descs) do
					each.state = NPC_STATE_IDLE
				end
				expect(#R.Step(p:GetPos(), descs, newState(), 0, false)).to.equal(0)
				-- alerted or fighting, within the gate: listed as allies
				descs = {R.Describe(friends[1], p), R.Describe(friends[2], p), R.Describe(friends[3], p)}
				local list = R.Step(p:GetPos(), descs, newState(), 0, false)
				expect(#list).to.equal(3)
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				startRecording()
				local ok, err = pcall(R.Tick, p, 10)
				stopRecording()
				assert(ok, err)
				expect(#sent).to.equal(1)
			end
		},
		{
			name = "the switch of the always visible allies exists: on by default and replicated (the archive flag is not readable here, the declaration is the one of gry_energy_net)",
			func = function(state)
				local c = GetConVar("gry_radar_allies_always")
				expect(c).toNot.beNil()
				expect(c:GetDefault()).to.equal("1")
				expect(c:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				c:SetString("1")
				expect(R.AlliesAlways()).to.beTrue()
				c:SetString("0")
				expect(R.AlliesAlways()).to.beFalse()
			end
		},
		{
			name = "a described real NPC has its relation to the player: like is an ally, hate is hostile, neutral and fear are neutral",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_citizen", p:GetPos() + Vector(300, 0, 0))
				e:AddEntityRelationship(p, D_LI, 99)
				local d = R.Describe(e, p)
				expect(d.relation).to.equal("ally")
				expect(d.ally).to.beTrue()
				expect(d.hostile).to.beFalse()
				e:AddEntityRelationship(p, D_HT, 99)
				d = R.Describe(e, p)
				expect(d.relation).to.equal("hostile")
				expect(d.ally).to.beFalse()
				expect(d.hostile).to.beTrue()
				e:AddEntityRelationship(p, D_NU, 99)
				d = R.Describe(e, p)
				expect(d.relation).to.equal("neutral")
				expect(d.ally).to.beFalse()
				expect(d.hostile).to.beFalse()
				e:AddEntityRelationship(p, D_FR, 99)
				expect(R.Describe(e, p).relation).to.equal("neutral")
			end
		},
		{
			name = "an ally is on the radar at once, calm and never scanned, in the ally colour, when the switch is on",
			func = function(state)
				local st = newState()
				local d = ally(SCAN - 100)
				local list = step({d}, st, 0, true)
				expect(#list).to.equal(1)
				expect(list[1].id).to.equal(d.id)
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				expect(list[1].marker).to.beFalse()
				expect(st.tagged[d.key]).to.beNil() -- nothing remembered: the switch decides every time
				-- past the radar's scan radius it is not listed
				d.x = SCAN + 100
				expect(#step({d}, st, 0, true)).to.equal(0)
			end
		},
		{
			name = "an ally stays in the ally colour whatever it does: calm, alerted, fighting the player's enemies",
			func = function(state)
				local st = newState()
				local d = ally(500)

				for _, s in ipairs({NPC_STATE_IDLE, NPC_STATE_ALERT, NPC_STATE_COMBAT}) do
					d.state = s
					expect(step({d}, st, 0, true)[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				end

				-- even when it is tagged (by a scan or an alert with the switch off) and the switch is on again
				st.tagged[d.key] = true
				expect(step({d}, st, 0, true)[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
			end
		},
		{
			name = "switch off: a calm ally is not on the radar, like a calm hostile",
			func = function(state)
				local st = newState()
				expect(#step({ally(500), ally(GATE - 10)}, st, 0, false)).to.equal(0)
				expect(#step({npc(500), npc(GATE - 10)}, st, 0, false)).to.equal(0)
				expect(next(st.tagged)).to.beNil()
			end
		},
		{
			name = "switch off: an ally that is alerted or fighting within 26 m is listed (blue) and tagged, one farther is not, a hostile is as before",
			func = function(state)
				local st = newState()
				local alerted = ally(GATE - 10, {state = NPC_STATE_ALERT})
				local fighting = ally(GATE - 20, {state = NPC_STATE_COMBAT})
				local far = ally(GATE + 100, {state = NPC_STATE_COMBAT})
				local list = step({alerted, fighting, far}, st, 0, false)
				expect(#list).to.equal(2)
				expect(list[1].id).to.equal(fighting.id)
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				expect(list[2].id).to.equal(alerted.id)
				expect(list[2].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				expect(st.tagged[alerted.key]).to.beTrue()
				expect(st.tagged[fighting.key]).to.beTrue()
				expect(st.tagged[far.key]).to.beNil()
				-- tagged: it stays at any distance of the scan, calm included, and is still blue
				alerted.x = 3000
				alerted.state = NPC_STATE_IDLE
				list = step({alerted}, st, 0.2, false)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
				-- a hostile in the same state keeps its own colours
				local foe = npc(GATE - 10, {state = NPC_STATE_ALERT})
				expect(step({foe}, newState(), 0, false)[1].sub).to.equal(3)
			end
		},
		{
			name = "switch off: a scanned ally is on the radar, blue, like a scanned hostile",
			func = function(state)
				local st = newState()
				local d = ally(500)
				st.tagged[d.key] = true
				local list = step({d}, st, 0, false)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
			end
		},
		{
			name = "a dead ally is gone, and its tag with it",
			func = function(state)
				local st = newState()
				local d = ally(500)
				st.tagged[d.key] = true
				d.health = 0
				expect(#step({d}, st, 0, true)).to.equal(0)
				expect(st.tagged[d.key]).to.beNil()
			end
		},
		{
			name = "a neutral NPC is as before whatever the switch: only a scan or a marker shows it, never its alert",
			func = function(state)
				for _, always in ipairs({true, false}) do
					local st = newState()
					local calm = npc(500, {hostile = false, relation = "neutral"})
					local alert = npc(GATE - 10, {hostile = false, relation = "neutral", state = NPC_STATE_COMBAT})
					expect(#step({calm, alert}, st, 0, always)).to.equal(0)
					st.tagged[calm.key] = true
					local list = step({calm}, st, 0, always)
					expect(#list).to.equal(1)
					expect(list[1].sub).to.equal(0)
					R.Mark(st, alert.key, 1)
					list = step({alert}, st, 1, always)
					expect(list[1].sub).to.equal(1)
					expect(list[1].marker).to.beTrue()
				end
			end
		},
		{
			name = "the marker of an ally (friendly fire) is blue and on the border like any marker",
			func = function(state)
				local st = newState()
				local d = ally(SCAN + 5000)
				R.Mark(st, d.key, 0)
				local list = step({d}, st, 1, true)
				expect(#list).to.equal(1)
				expect(list[1].marker).to.beTrue()
				expect(list[1].sub).to.equal(GryMod.RadarShared.SUB_ALLY)
			end
		},
		{
			name = "the switch is read from its convar when the rules are not told",
			func = function(state)
				local c = GetConVar("gry_radar_allies_always")
				c:SetString("1")
				expect(#step({ally(500)})).to.equal(1)
				c:SetString("0")
				expect(#step({ally(500)})).to.equal(0)
			end
		},
		{
		name = "a real rebel (ally) and seagull (neutral) near the player: the tick lists the rebel in the ally colour and not the seagull, when the switch is on",
		func = function(state)
			local p = ply()
			local c = GetConVar("gry_radar_allies_always")
			local rebel = spawnNPC("npc_citizen", p:GetPos() + Vector(300, 0, 0))
			rebel:AddEntityRelationship(p, D_LI, 99)
			local gull = spawnNPC("npc_seagull", p:GetPos() + Vector(300, 80, 60))
			gull:AddEntityRelationship(p, D_NU, 99)
			p.GryRadarWant = true

			local function contacts()
				local list, values = {}, sent[1].values

				for i = 1, values[1] do
					local at = 2 + (i - 1) * 9 -- id, type, sub, marker, big, x, y, z, yaw
					list[values[at]] = values[at + 2]
				end

				return list
			end

			c:SetString("1")
			startRecording()
			local ok, err = pcall(R.Tick, p, 50)
			stopRecording()

			if not ok then
				error(err, 0)
			end

			expect(#sent).to.equal(1)
			local list = contacts()
			expect(list[rebel:EntIndex()]).to.equal(GryMod.RadarShared.SUB_ALLY)
			expect(list[gull:EntIndex()]).to.beNil()

			-- switched off: the calm rebel is gone from the list
			c:SetString("0")
			startRecording()
			ok, err = pcall(R.Tick, p, 51)
			stopRecording()

			if not ok then
				error(err, 0)
			end

			list = contacts()
			expect(list[rebel:EntIndex()]).to.beNil()
		end
	},
		{
			name = "a hit on the player by an NPC marks the NPC, a hit by the world, a prop or the player does not",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				local dmg = DamageInfo()
				dmg:SetDamage(10)
				dmg:SetAttacker(e)
				R.Reset(p)
				hook.GetTable().EntityTakeDamage["GryMod radar"](p, dmg)
				expect(R.State(p).markers[e]).toNot.beNil()

				R.Reset(p)
				dmg:SetAttacker(game.GetWorld())
				hook.GetTable().EntityTakeDamage["GryMod radar"](p, dmg)
				expect(next(R.State(p).markers)).to.beNil()
				dmg:SetAttacker(p)
				hook.GetTable().EntityTakeDamage["GryMod radar"](p, dmg)
				expect(next(R.State(p).markers)).to.beNil()

				-- a hit the armor took all of (damage 0 by the time this hook runs) still marks the NPC
				dmg:SetAttacker(e)
				dmg:SetDamage(0)
				hook.GetTable().EntityTakeDamage["GryMod radar"](p, dmg)
				expect(R.State(p).markers[e]).toNot.beNil()
				R.Reset(p)

				-- an NPC hurt by the player is not a marker
				dmg:SetDamage(10)
				hook.GetTable().EntityTakeDamage["GryMod radar"](e, dmg)
				expect(next(R.State(p).markers)).to.beNil()
			end
		},
		{
			name = "a hit the armor takes all of marks the NPC whatever the order of the radar hook and the suit's",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				local hooks = hook.GetTable().EntityTakeDamage
				local mode, energy = p.Nanosuit_mode, p:GetNW2Float("GryEnergy")
				local orders = {{"Grymod damage handeling", "GryMod radar"}, {"GryMod radar", "Grymod damage handeling"}}

				startRecording()
				local ok, err = pcall(function()
					for _, order in ipairs(orders) do
						local dmg = DamageInfo()
						dmg:SetDamage(10)
						dmg:SetAttacker(e)
						p.Nanosuit_mode = GryMod.Modes.ARMOR
						p:SetNW2Float("GryEnergy", 100)
						R.Reset(p)

						for _, name in ipairs(order) do
							hooks[name](p, dmg)
						end

						expect(R.State(p).markers[e]).toNot.beNil()
					end
				end)
				stopRecording()
				p.Nanosuit_mode = mode
				p:SetNW2Float("GryEnergy", energy)
				R.Reset(p)
				assert(ok, err)
			end
		},
		{
			name = "a tick sends the list of a player who asked for it, and nothing when nothing changed",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				p.GryRadarWant = true
				e:SetNPCState(NPC_STATE_ALERT)
				e:AddEntityRelationship(p, D_HT, 99)
				expect(e:GetNPCState()).to.equal(NPC_STATE_ALERT)

				startRecording()
				local ok, err = pcall(R.Tick, p, 10)
				local first = #sent
				local ok2, err2 = pcall(R.Tick, p, 10.2)
				local second = #sent
				stopRecording()
				assert(ok, err)
				assert(ok2, err2)
				expect(first).to.equal(1)
				expect(sent[1].name).to.equal("gry_radar")
				expect(sent[1].to).to.equal(p)
				expect(sent[1].values[1]).to.equal(1) -- one contact
				expect(sent[1].values[2]).to.equal(e:EntIndex())
				expect(second).to.equal(1) -- same list: nothing new
			end
		},
		{
			name = "a tick sends nothing to a player who did not ask, is dead, or when the switch is off",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				e:SetNPCState(NPC_STATE_ALERT)
				e:AddEntityRelationship(p, D_HT, 99)

				startRecording()
				p.GryRadarWant = nil
				pcall(R.Tick, p, 10)
				p.GryRadarWant = true
				local convar = GetConVar("gry_radar_contacts")
				convar:SetInt(0)
				pcall(R.Tick, p, 11)
				convar:SetInt(1)
				stopRecording()
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "when the contacts end, an empty list is sent once, then nothing",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				p.GryRadarWant = true
				e:SetNPCState(NPC_STATE_ALERT)
				e:AddEntityRelationship(p, D_HT, 99)
				startRecording()
				pcall(R.Tick, p, 10)
				e:SetPos(p:GetPos() + Vector(30000, 0, 0)) -- far past the radar
				pcall(R.Tick, p, 10.2)
				pcall(R.Tick, p, 10.4)
				stopRecording()
				expect(#sent).to.equal(2)
				expect(sent[2].values[1]).to.equal(0)
			end
		},
		{
			name = "the player's death and respawn forget the tags and tell the client an empty list",
			func = function(state)
				local p = ply()
				local e = spawnNPC("npc_zombie", p:GetPos() + Vector(300, 0, 0))
				p.GryRadarWant = true
				e:SetNPCState(NPC_STATE_ALERT)
				e:AddEntityRelationship(p, D_HT, 99)
				startRecording()
				pcall(R.Tick, p, 10)
				hook.GetTable().PlayerSpawn["GryMod radar"](p)
				expect(next(R.State(p).tagged)).to.beNil()
				pcall(R.Tick, p, 10.2) -- the NPC is still alert near: tagged again
				stopRecording()
				expect(#sent).to.equal(3) -- the list, the empty list of the respawn, the list again
				expect(sent[2].values[1]).to.equal(0)
			end
		},
		{
			name = "the client's request is remembered, a missing player is ignored",
			func = function(state)
				local p = ply()
				local receiver = net.Receivers["gry_radar_want"]
				expect(receiver).toNot.beNil()
				local realRead = net.ReadBool
				net.ReadBool = function() return true end
				local ok, err = pcall(receiver, 1, p)
				net.ReadBool = function() return false end
				local ok2, err2 = pcall(receiver, 1, p)
				local wantAfter = p.GryRadarWant
				net.ReadBool = realRead
				assert(ok, err)
				assert(ok2, err2)
				expect(wantAfter).to.beFalse()
				expect(pcall(receiver, 1, nil)).to.beTrue()
			end
		},
		{
			name = "a scan from the binoculars tags the NPC for the player: the message exists, and the rule checks the NPC and its range",
			func = function(state)
				expect(util.NetworkStringToID("gry_radar_scan") ~= 0).to.beTrue()
				local p = ply()
				local near = spawnNPC("npc_combine_s", p:GetPos() + Vector(400, 0, 20))
				local far = spawnNPC("npc_combine_s", p:GetPos() + Vector(52.49 * 400, 0, 20))
				local st = R.State(p)

				expect(R.Scan(p, near)).to.beTrue()
				expect(st.tagged[near]).to.beTrue()
				-- 400 m is beyond the 300 m of the ray, with a margin for the lag
				expect(R.Scan(p, far)).to.beFalse()
				expect(st.tagged[far]).to.beNil()
			end
		},
		{
			name = "a scan tags nothing that is not an NPC that is alive, nothing for a dead player, and takes the marker's place",
			func = function(state)
				local p = ply()
				local st = R.State(p)
				local prop = ents.Create("prop_physics")
				prop:SetModel("models/props_junk/PopCan01a.mdl")
				prop:SetPos(p:GetPos() + Vector(200, 0, 20))
				prop:Spawn()
				spawned[#spawned + 1] = prop
				expect(R.Scan(p, prop)).to.beFalse()
				expect(R.Scan(p, NULL)).to.beFalse()
				expect(R.Scan(p, nil)).to.beFalse()
				expect(R.Scan(nil, prop)).to.beFalse()

				local npc = spawnNPC("npc_combine_s", p:GetPos() + Vector(300, 0, 20))
				st.markers[npc] = CurTime() + 10
				expect(R.Scan(p, npc)).to.beTrue()
				-- a tagged unit is not also a marker
				expect(st.markers[npc]).to.beNil()

				local dead = spawnNPC("npc_combine_s", p:GetPos() + Vector(300, 100, 20))
				dead:SetHealth(0)
				expect(R.Scan(p, dead)).to.beFalse()
			end
		},
		{
			name = "the scan message tags the entity of its index, and a missing player is ignored",
			func = function(state)
				local p = ply()
				local npc = spawnNPC("npc_combine_s", p:GetPos() + Vector(300, 0, 20))
				local receiver = net.Receivers["gry_radar_scan"]
				expect(receiver).toNot.beNil()
				local realRead = net.ReadUInt
				net.ReadUInt = function(bits) return npc:EntIndex() end
				local ok, err = pcall(receiver, 1, p)
				local ok2 = pcall(receiver, 1, nil)
				net.ReadUInt = realRead
				assert(ok, err)
				expect(ok2).to.beTrue()
				expect(R.State(p).tagged[npc]).to.beTrue()
			end
		},
		{
			name = "a tagged calm hostile NPC is on the radar's list (a scan is the same tag as the first detection)",
			func = function(state)
				local st = newState()
				local d = npc(500, {state = NPC_STATE_IDLE})
				expect(#step({d}, st, 0)).to.equal(0)
				st.tagged[d.key] = true
				local list = step({d}, st, 0.2)
				expect(#list).to.equal(1)
				expect(list[1].sub).to.equal(2)
			end
		}
	}
}
