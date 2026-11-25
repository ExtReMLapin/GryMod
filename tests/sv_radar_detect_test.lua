-- Tests of the detection the server adds to the danger bar and the hexagon (server/sv_radar.lua: Radar.Detect, Radar.SendDetect and the message gry_radar_detect),
-- GLuaTest format, server realm. The contacts only list a hostile that is alerted within 26 m (or scanned), so a soldier that sees the player from 60 m never
-- raised the bar. The original's AI counts what the observers see and hear (research note 2026-11-22): here a hostile NPC counts when it has the player as
-- enemy or sees him (level 2) or hears him (level 1), wherever it is in the radar's search sphere and whether it is a contact or not; only the NPCs that are
-- not already contacts are sent (the contacts carry their own state). Descriptions (what Radar.Describe gives) are used: no real NPC is needed.

local R -- GryMod.Radar, set in beforeAll

local nextId = 0

local function npc(extra)
	nextId = nextId + 1
	local d = {key = {}, id = 500 + nextId, class = "npc_combine_s", hostile = true, ally = false, state = NPC_STATE_IDLE, enemyIsPlayer = false, seen = false,
		heard = false, health = 50, maxHealth = 50, x = 0, y = 0, z = 0, yaw = 0}

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

return {
	groupName = "GryMod radar detection (server)",
	beforeAll = function(state)
		R = GryMod.Radar
	end,
	beforeEach = function(state)
		state.value = GetConVar("gry_radar_detect") and GetConVar("gry_radar_detect"):GetString()
	end,
	afterEach = function(state)
		pcall(function()
			if state.realStart then
				net.Start, net.WriteUInt, net.Send = state.realStart, state.realWriteUInt, state.realSend
				state.realStart = nil
			end
		end)

		if state.value and GetConVar("gry_radar_detect") then
			GetConVar("gry_radar_detect"):SetString(state.value)
		end
	end,
	cases = {
		-- fails without the convar and the message in sv_radar.lua
		{
			name = "the message and the switch exist, the switch on by default",
			func = function(state)
				expect(util.NetworkStringToID("gry_radar_detect") ~= 0).to.beTrue()
				expect(GetConVar("gry_radar_detect")).toNot.beNil()
				expect(GetConVar("gry_radar_detect"):GetDefault()).to.equal("1")
			end
		},
		-- fails without Radar.Detect
		{
			name = "a hostile that has the player as enemy counts 2 (seen), one that sees him counts 2, one that only hears him counts 1, a calm one nothing",
			func = function(state)
				local p = R.Detect({npc({enemyIsPlayer = true, state = NPC_STATE_COMBAT})}, {})
				expect(p).to.equal(2)
				expect((R.Detect({npc({seen = true})}, {}))).to.equal(2)
				expect((R.Detect({npc({heard = true})}, {}))).to.equal(1)
				expect((R.Detect({npc()}, {}))).to.equal(0)
				-- a lost player (ALERT keeps the last enemy) is the looking-for-him level, 1
				expect((R.Detect({npc({enemyIsPlayer = true, state = NPC_STATE_ALERT})}, {}))).to.equal(1)
				-- the highest of several wins, they do not add up
				expect((R.Detect({npc({heard = true}), npc({seen = true}), npc({heard = true})}, {}))).to.equal(2)
			end
		},
		{
			name = "the soldiers and the machines are counted apart (the bar and the hexagon): a flying or machine type goes to the second number",
			func = function(state)
				local soldier, machine = R.Detect({npc({seen = true, type = 1}), npc({heard = true, type = 3})}, {})
				expect(soldier).to.equal(2)
				expect(machine).to.equal(1)
				soldier, machine = R.Detect({npc({seen = true, class = "npc_combinegunship", type = 2})}, {})
				expect(soldier).to.equal(0)
				expect(machine).to.equal(2)
				-- the type of the class when the registry gives none of its own
				soldier, machine = R.Detect({npc({seen = true, class = "npc_strider"})}, {})
				expect(machine).to.equal(2)
			end
		},
		{
			name = "friends, neutrals, the dead and the entries that say never or scan do not count; a radar = hostile entry counts whatever its relation, an ally never",
			func = function(state)
				expect((R.Detect({npc({seen = true, hostile = false})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, hostile = false, ally = true})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, health = 0})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, state = NPC_STATE_DEAD})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, radar = "never"})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, radar = "scan"})}, {}))).to.equal(0)
				expect((R.Detect({npc({seen = true, hostile = false, radar = "hostile"})}, {}))).to.equal(2)
				expect((R.Detect({npc({seen = true, hostile = false, ally = true, radar = "hostile"})}, {}))).to.equal(0)
			end
		},
		-- fails when the contacts are counted twice (the client takes the highest of both anyway, but the message must say what the contacts do not)
		{
			name = "an NPC that is already a contact is not counted (its state travels in the contact list): only the others are",
			func = function(state)
				local listed = npc({seen = true})
				local other = npc({heard = true})
				local p = R.Detect({listed, other}, {[listed.id] = true})
				expect(p).to.equal(1)
			end
		},
		-- fails without the switch
		{
			name = "with gry_radar_detect 0 nothing is counted",
			func = function(state)
				GetConVar("gry_radar_detect"):SetString("0")
				local p, v = R.Detect({npc({seen = true}), npc({seen = true, type = 3})}, {})
				expect(p).to.equal(0)
				expect(v).to.equal(0)
			end
		},
		-- fails without SendDetect
		{
			name = "the two numbers are sent when they change and not otherwise, 2 bits each; zero is sent once when they go back down, nothing at all for a player that never had any",
			func = function(state)
				local sent = {}
				state.realStart, state.realWriteUInt, state.realSend = net.Start, net.WriteUInt, net.Send
				net.Start = function(name) sent[#sent + 1] = {name = name, values = {}} return true end
				net.WriteUInt = function(v, bits) local m = sent[#sent] m.values[#m.values + 1] = v m.bits = m.bits or bits end
				net.Send = function(p) sent[#sent].to = p end
				local ply = {}
				local st = {}

				R.SendDetect(ply, st, 0, 0)
				expect(#sent).to.equal(0)
				R.SendDetect(ply, st, 2, 1)
				expect(#sent).to.equal(1)
				expect(sent[1].name).to.equal("gry_radar_detect")
				expect(sent[1].values[1]).to.equal(2)
				expect(sent[1].values[2]).to.equal(1)
				expect(sent[1].bits).to.equal(2)
				expect(sent[1].to).to.equal(ply)
				R.SendDetect(ply, st, 2, 1)
				expect(#sent).to.equal(1)
				R.SendDetect(ply, st, 0, 1)
				expect(#sent).to.equal(2)
				R.SendDetect(ply, st, 0, 0)
				expect(#sent).to.equal(3)
				R.SendDetect(ply, st, 0, 0)
				expect(#sent).to.equal(3)
			end
		}
	}
}
