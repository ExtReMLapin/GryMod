-- Tests of the radar's explosion pings the server sends (GryMod.API.ReportRadarPing and the env_explosion hook, server/sv_radar_pings.lua), GLuaTest format,
-- server realm. The numbers (250 m reach, size held to 8) are the original's, see tests/sh_radar_ping_test.lua.

local U = 0.01905

local function metres(m)
	return m / U
end

local R -- GryMod.Radar, set in beforeAll

-- a stand-in for a player: where it is and whether it is alive
local function fakePlayer(at, alive)
	local p = {}
	p.IsValid = function() return true end
	p.GetPos = function() return at end
	p.Alive = function() return alive ~= false end
	p.IsPlayer = function() return true end

	return p
end

-- what the server sent: records net.Start / Send / Write*, puts them back
local sent
local real = {}

local function startRecording()
	sent = {}
	real.Start, real.Send, real.WriteVector, real.WriteUInt = net.Start, net.Send, net.WriteVector, net.WriteUInt
	net.Start = function(name) sent[#sent + 1] = {name = name, values = {}} return true end
	net.WriteVector = function(v) local m = sent[#sent] m.values[#m.values + 1] = v end
	net.WriteUInt = function(v, bits) local m = sent[#sent] m.values[#m.values + 1] = v m.bits = bits end
	net.Send = function(p) sent[#sent].to = p end
end

local function stopRecording()
	if real.Start then
		net.Start, net.Send, net.WriteVector, net.WriteUInt = real.Start, real.Send, real.WriteVector, real.WriteUInt
		real.Start = nil
	end
end

return {
	groupName = "GryMod radar pings (server)",
	beforeAll = function(state)
		R = GryMod.Radar
	end,
	beforeEach = function(state)
		state.autoValue = GetConVar("gry_radar_pings") and GetConVar("gry_radar_pings"):GetString()
		state.realPlayers = R.PingPlayers
		R.ResetPingRate()
	end,
	afterEach = function(state)
		pcall(stopRecording)
		R.PingPlayers = state.realPlayers
		R.ResetPingRate()

		if state.autoValue and GetConVar("gry_radar_pings") then
			GetConVar("gry_radar_pings"):SetString(state.autoValue)
		end

		if state.realTimer then
			timer.Simple = state.realTimer
			state.realTimer = nil
		end

		hook.Remove("GryMod_RadarPing", "test_radar_ping")
	end,
	cases = {
		-- fails without sv_radar_pings.lua
		{
			name = "the message, the two switches and the API function exist",
			func = function(state)
				expect(util.NetworkStringToID("gry_radar_ping") ~= 0).to.beTrue()
				expect(GetConVar("gry_radar_pings")).toNot.beNil()
				expect(GetConVar("gry_radar_pings"):GetInt()).to.equal(1)
				expect(isfunction(GryMod.API.ReportRadarPing)).to.beTrue()
			end
		},
		{
			name = "ReportRadarPing refuses a position that is not a Vector or not a number, and a kind that is not one, with a reason; it takes a name, a number or nothing",
			func = function(state)
				R.PingPlayers = function() return {} end
				local ok, reason = GryMod.API.ReportRadarPing(nil, "big")
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				expect((GryMod.API.ReportRadarPing(Vector(0 / 0, 0, 0)))).to.beFalse()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0), "huge"))).to.beFalse()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0), {}))).to.beFalse()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0)))).to.beTrue()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0), "small"))).to.beTrue()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0), 5))).to.beTrue()
			end
		},
		-- fails when the message goes to everyone, or to nobody
		{
			name = "the ping goes to the living players within 250 m of it, and to nobody else: one message, the position then the size in half metres in 5 bits",
			func = function(state)
				local near, far, dead = fakePlayer(Vector(metres(100), 0, 0)), fakePlayer(Vector(metres(300), 0, 0)), fakePlayer(Vector(0, 0, 0), false)
				R.PingPlayers = function() return {near, far, dead} end
				startRecording()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0), "big"))).to.beTrue()
				stopRecording()
				expect(#sent).to.equal(1)
				expect(sent[1].name).to.equal("gry_radar_ping")
				expect(#sent[1].to).to.equal(1)
				expect(sent[1].to[1]).to.equal(near)
				expect(sent[1].values[2]).to.equal(16) -- size 8 in half metres
				expect(sent[1].bits).to.equal(5)
				expect(sent[1].values[1].x).to.equal(0)
			end
		},
		{
			name = "nobody in reach: nothing is sent (and it is not an error)",
			func = function(state)
				R.PingPlayers = function() return {fakePlayer(Vector(metres(900), 0, 0))} end
				startRecording()
				expect((GryMod.API.ReportRadarPing(Vector(0, 0, 0)))).to.beTrue()
				stopRecording()
				expect(#sent).to.equal(0)
			end
		},
		-- fails without the rate limit
		{
			name = "no more than 20 pings a second are sent: the 21st in the same second is refused (a chain of explosions must not flood the net)",
			func = function(state)
				R.PingPlayers = function() return {} end

				for i = 1, 20 do
					expect((GryMod.API.ReportRadarPing(Vector(i, 0, 0)))).to.beTrue()
				end

				local ok, reason = GryMod.API.ReportRadarPing(Vector(21, 0, 0))
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
			end
		},
		-- fails without the reporting hook
		{
			name = "the hook GryMod_RadarPing(pos, size, automatic) tells that a ping was accepted (the API call is not automatic)",
			func = function(state)
				R.PingPlayers = function() return {} end
				local seen
				hook.Add("GryMod_RadarPing", "test_radar_ping", function(pos, size, automatic) seen = {pos = pos, size = size, automatic = automatic} end)
				GryMod.API.ReportRadarPing(Vector(1, 2, 3), "small")
				expect(seen.pos.y).to.equal(2)
				expect(seen.size).to.equal(2)
				expect(seen.automatic).to.beFalse()
			end
		},
		-- fails without ExplosionSize
		{
			name = "the size of an env_explosion comes from its radius override, or from its magnitude times 2.5 units (the engine's rule), 100 when it cannot be read",
			func = function(state)
				local function explosion(vars)
					return {GetInternalVariable = function(_, name) return vars[name] end}
				end

				expect(R.ExplosionSize(explosion({m_iMagnitude = 100, m_iRadiusOverride = 0}))).to.aboutEqual(250 * U, 0.001)
				expect(R.ExplosionSize(explosion({m_iMagnitude = 100, m_iRadiusOverride = 100}))).to.aboutEqual(100 * U, 0.001)
				expect(R.ExplosionSize(explosion({m_iMagnitude = 400}))).to.equal(8) -- held
				expect(R.ExplosionSize(explosion({}))).to.aboutEqual(250 * U, 0.001)
			end
		},
		-- fails without the OnEntityCreated hook of sv_radar_pings.lua
		{
			name = "an env_explosion that is created becomes a ping at its place on the next tick; another entity does not, and the switch gry_radar_pings 0 turns it off",
			func = function(state)
				R.PingPlayers = function() return {} end
				local seen = {}
				hook.Add("GryMod_RadarPing", "test_radar_ping", function(pos, size, automatic) seen[#seen + 1] = {pos = pos, size = size, automatic = automatic} end)
				local later = {}
				state.realTimer = timer.Simple
				timer.Simple = function(delay, fn) later[#later + 1] = fn end
				local explosion = {
					IsValid = function() return true end,
					GetClass = function() return "env_explosion" end,
					GetPos = function() return Vector(10, 20, 30) end,
					GetInternalVariable = function(_, name) return ({m_iMagnitude = 100, m_iRadiusOverride = 0})[name] end
				}
				local other = {IsValid = function() return true end, GetClass = function() return "prop_physics" end, GetPos = function() return Vector(0, 0, 0) end}

				R.OnEntityCreated(other)
				expect(#later).to.equal(0)

				R.OnEntityCreated(explosion)
				expect(#later).to.equal(1)
				later[1]()
				expect(#seen).to.equal(1)
				expect(seen[1].pos.z).to.equal(30)
				expect(seen[1].automatic).to.beTrue()

				GetConVar("gry_radar_pings"):SetString("0")
				later = {}
				R.OnEntityCreated(explosion)
				expect(#later).to.equal(0)
				expect(#seen).to.equal(1)

				-- the switch turned off between the creation and the tick: still nothing
				GetConVar("gry_radar_pings"):SetString("1")
				R.OnEntityCreated(explosion)
				GetConVar("gry_radar_pings"):SetString("0")
				later[1]()
				expect(#seen).to.equal(1)
			end
		},
		{
			name = "the engine's hook is the one that runs it: OnEntityCreated has the handler of GryMod's radar pings",
			func = function(state)
				expect(hook.GetTable().OnEntityCreated["GryMod radar pings"]).toNot.beNil()
			end
		},
		-- fails without Radar.OnEntityRemoved / ExplosiveClasses: measured on 2026-11-24, the frag grenade, the SMG grenade, the satchel and the AR2 ball explode with
		-- NO env_explosion (the engine draws their blast as an effect), so the radar never pinged for them; only the RPG, barrels, mines... made one
		{
			name = "a grenade, an SMG grenade, a satchel and an AR2 ball that go off (they are removed) ping the radar at the place where they were, with no env_explosion; any other entity does not, and neither does a removal that is only a cleanup",
			func = function(state)
				R.PingPlayers = function() return {} end
				local seen = {}
				hook.Add("GryMod_RadarPing", "test_radar_ping", function(pos, size, automatic) seen[#seen + 1] = {pos = pos, size = size, automatic = automatic} end)

				local function entity(class, health)
					return {
						IsValid = function() return true end,
						GetClass = function() return class end,
						GetPos = function() return Vector(10, 20, 30) end,
						Health = function() return health or 0 end
					}
				end

				for _, class in ipairs({"npc_grenade_frag", "grenade_ar2", "npc_satchel", "prop_combine_ball"}) do
					seen = {}
					R.ResetPingRate()
					R.OnEntityRemoved(entity(class), false)
					expect(#seen).to.equal(1)
					expect(seen[1].pos.z).to.equal(30)
					expect(seen[1].automatic).to.beTrue()
					expect(seen[1].size > 1).to.beTrue()
				end

				seen = {}
				R.ResetPingRate()
				R.OnEntityRemoved(entity("prop_physics"), false)
				R.OnEntityRemoved(entity("crossbow_bolt"), false)
				R.OnEntityRemoved(entity("npc_grenade_frag"), true) -- the map is being cleaned
				expect(#seen).to.equal(0)

				GetConVar("gry_radar_pings"):SetString("0")
				R.OnEntityRemoved(entity("npc_grenade_frag"), false)
				expect(#seen).to.equal(0)
			end
		},
		-- fails if a manhack pings when it is only removed, or never pings when it dies
		{
			name = "a manhack pings (small) when it is destroyed, not when it is removed alive",
			func = function(state)
				R.PingPlayers = function() return {} end
				local seen = {}
				hook.Add("GryMod_RadarPing", "test_radar_ping", function(pos, size, automatic) seen[#seen + 1] = size end)
				local function manhack(health)
					return {
						IsValid = function() return true end,
						GetClass = function() return "npc_manhack" end,
						GetPos = function() return Vector(0, 0, 0) end,
						Health = function() return health end
					}
				end

				R.OnEntityRemoved(manhack(25), false)
				expect(#seen).to.equal(0)
				R.OnEntityRemoved(manhack(0), false)
				expect(#seen).to.equal(1)
				expect(seen[1]).to.equal(2)
			end
		},
		{
			name = "EntityRemoved has the handler of the radar pings",
			func = function(state)
				expect(hook.GetTable().EntityRemoved["GryMod radar pings"]).toNot.beNil()
			end
		}
	}
}
