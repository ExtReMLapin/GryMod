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

local function step(descs, st, now)
	return R.Step(ORIGIN, descs, st or newState(), now or 0)
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
	afterEach = function(state)
		if stopRecording then pcall(stopRecording) end

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

				-- an NPC hurt by the player is not a marker, and zero damage tells nothing
				dmg:SetAttacker(e)
				dmg:SetDamage(0)
				hook.GetTable().EntityTakeDamage["GryMod radar"](p, dmg)
				expect(next(R.State(p).markers)).to.beNil()
				dmg:SetDamage(10)
				hook.GetTable().EntityTakeDamage["GryMod radar"](e, dmg)
				expect(next(R.State(p).markers)).to.beNil()
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
		}
	}
}
