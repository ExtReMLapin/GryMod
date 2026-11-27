-- Tests of the radar ring for a blast made by util.BlastDamage (sv_radar_pings.lua: Radar.InstallBlast, Radar.OnBlast; the option gry_radar_blast_rings), GLuaTest format, server realm.
-- Many addons (simfphys, Glide, LVS, VJ Base, the tools) blow things up with util.BlastDamage and no env_explosion: the radar never rang for them. The core wraps util.BlastDamage ONCE, tells
-- the hook GryMod_Explosion(pos, radius, inflictor, attacker), and rings the radar for a blast of 150 units or more, once even when an env_explosion is made at the same place and tick.
-- The wrapper never breaks the blast: the original runs first and its results are returned, and only GryMod's own code is under pcall. Each case names the change whose absence makes it fail.

local R, S

local TAG = "t_blast"
local seen
local real = {}

local function ring(radius)
	return S.PingSizeOfRadius(radius)
end

local function recordPings()
	seen = {}
	hook.Add("GryMod_RadarPing", TAG, function(pos, size, automatic) seen[#seen + 1] = {pos = pos, size = size, automatic = automatic} end)
end

-- an env_explosion stand-in at a place
local function explosionAt(pos)
	return {
		IsValid = function() return true end,
		GetClass = function() return "env_explosion" end,
		GetPos = function() return pos end,
		GetInternalVariable = function(_, name) return ({m_iMagnitude = 100, m_iRadiusOverride = 0})[name] end
	}
end

-- Runs body with `stub` as the util.BlastDamage that GryMod wraps (the real wrapper is put back whatever happens)
local function withOriginal(stub, body)
	R.UninstallBlast()

	local saved = util.BlastDamage

	util.BlastDamage = stub
	R.InstallBlast()

	local ok, err = pcall(body)

	R.UninstallBlast()
	util.BlastDamage = saved
	R.InstallBlast()
	assert(ok, err)
end

local function setConvar(name, value)
	local c = GetConVar(name)

	if c then
		c:SetString(value)
	end
end

return {
	groupName = "GryMod radar rings for util.BlastDamage (server)",
	beforeAll = function()
		R, S = GryMod.Radar, GryMod.RadarShared
	end,
	beforeEach = function()
		real.pings = GetConVar("gry_radar_pings") and GetConVar("gry_radar_pings"):GetString()
		real.rings = GetConVar("gry_radar_blast_rings") and GetConVar("gry_radar_blast_rings"):GetString()
		real.players = R.PingPlayers
		R.PingPlayers = function() return {} end
		R.ResetPingRate()

		if R.ResetBlastMemory then
			R.ResetBlastMemory()
		end

		setConvar("gry_radar_pings", "1")
		setConvar("gry_radar_blast_rings", "1")
		recordPings()
	end,
	afterEach = function()
		hook.Remove("GryMod_RadarPing", TAG)
		hook.Remove("GryMod_Explosion", TAG)
		R.PingPlayers = real.players
		R.ResetPingRate()

		if real.pings then
			setConvar("gry_radar_pings", real.pings)
		end

		if real.rings then
			setConvar("gry_radar_blast_rings", real.rings)
		end

		if real.timer then
			timer.Simple = real.timer
			real.timer = nil
		end
	end,
	cases = {
		{
			-- fails without the setting, if it is not a server option of the white list, if it does not default to on, or is not archived and replicated like the other server options
			name = "gry_radar_blast_rings exists, is on by default, replicated, saved like its sibling, and is a boolean of the administrators' white list",
			func = function()
				local c = GetConVar("gry_radar_blast_rings")

				expect(c).to.exist()
				expect(c:GetDefault()).to.equal("1")
				expect(bit.band(c:GetFlags(), FCVAR_REPLICATED)).to.equal(FCVAR_REPLICATED)
				-- (GetFlags does not report FCVAR_ARCHIVE for Lua-created convars in this build: the same flags as a saved sibling)
				expect(c:GetFlags()).to.equal(GetConVar("gry_radar_pings"):GetFlags())
				expect(GryMod.ServerSettings.Find("gry_radar_blast_rings").kind).to.equal("bool")
			end
		},
		{
			-- fails when util.BlastDamage is not wrapped, or when installing again stacks a second wrapper (two rings for one blast) or loses the original
			name = "util.BlastDamage is wrapped once: installing again does not stack, and the original is kept",
			func = function()
				expect(isfunction(R.BlastOriginal)).to.beTrue()
				expect(util.BlastDamage ~= R.BlastOriginal).to.beTrue()

				local wrapper = util.BlastDamage
				local original = R.BlastOriginal

				R.InstallBlast()
				R.InstallBlast()
				expect(util.BlastDamage).to.equal(wrapper)
				expect(R.BlastOriginal).to.equal(original)

				-- one blast, one ring
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 300, 1)
				expect(#seen).to.equal(1)
			end
		},
		{
			-- fails when the wrapper does not run the original with the very arguments, or does not return what it returns
			name = "the original runs with the arguments it was given and its results are returned",
			func = function()
				local got
				local inflictor, attacker = {}, {}

				withOriginal(function(...)
					got = {...}

					return "a", 7
				end, function()
					local x, y = util.BlastDamage(inflictor, attacker, Vector(1, 2, 3), 200, 55)

					expect(x).to.equal("a")
					expect(y).to.equal(7)
				end)

				expect(got[1]).to.equal(inflictor)
				expect(got[2]).to.equal(attacker)
				expect(got[3]).to.equal(Vector(1, 2, 3))
				expect(got[4]).to.equal(200)
				expect(got[5]).to.equal(55)
			end
		},
		{
			-- fails when the ring is not sent for a big blast, is sent for a small one, or has not the size of the radius
			name = "a blast of 150 units or more rings the radar, with the size of its radius; a smaller one does not",
			func = function()
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 149, 1)
				expect(#seen).to.equal(0)

				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 150, 1)
				expect(#seen).to.equal(1)
				expect(seen[1].size).to.equal(ring(150))
				expect(seen[1].automatic).to.beTrue()

				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5100, 5000), 600, 1)
				expect(#seen).to.equal(2)
				expect(seen[2].size).to.equal(ring(600))
			end
		},
		{
			-- fails when the option gry_radar_blast_rings or its parent gry_radar_pings does not turn the ring off, or when the hook then goes silent too
			name = "gry_radar_blast_rings 0, or gry_radar_pings 0, send no ring; the hook GryMod_Explosion is told anyway, with the arguments of the blast",
			func = function()
				local told = {}

				hook.Add("GryMod_Explosion", TAG, function(pos, radius, inflictor, attacker) told[#told + 1] = {pos, radius, inflictor, attacker} end)

				setConvar("gry_radar_blast_rings", "0")
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 300, 1)
				expect(#seen).to.equal(0)

				setConvar("gry_radar_blast_rings", "1")
				setConvar("gry_radar_pings", "0")
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 300, 1)
				expect(#seen).to.equal(0)

				expect(#told).to.equal(2)
				expect(told[1][1]).to.equal(Vector(5000, 5000, 5000))
				expect(told[1][2]).to.equal(300)
				expect(told[1][3]).to.equal(player.GetAll()[1])
				expect(told[1][4]).to.equal(player.GetAll()[1])
			end
		},
		{
			-- fails when a handler of GryMod_Explosion that raises an error breaks the blast: the original must have run and its result must be returned
			name = "a handler that raises an error, and a position that is not a vector, never break the blast",
			func = function()
				hook.Add("GryMod_Explosion", TAG, function() error("handler failure") end)

				local realNoHalt = ErrorNoHalt
				local result

				ErrorNoHalt = function() end

				local ok, err = pcall(withOriginal, function() return "done" end, function()
					local a = util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), 300, 1)
					local b = util.BlastDamage(player.GetAll()[1], player.GetAll()[1], "nowhere", 300, 1)
					local c = util.BlastDamage(player.GetAll()[1], player.GetAll()[1], Vector(5000, 5000, 5000), "big", 1)

					result = {a, b, c}
				end)

				ErrorNoHalt = realNoHalt
				assert(ok, err)
				expect(result[1]).to.equal("done")
				expect(result[2]).to.equal("done")
				expect(result[3]).to.equal("done")
				-- the radar still rang for the first one although a handler failed
				expect(#seen).to.equal(1)
			end
		},
		{
			-- fails when the blast and an env_explosion of the same place and the same moment ring twice, in either order, or when two env_explosions (a chain) are merged
			name = "a blast and an env_explosion at the same place and tick give ONE ring, whichever comes first; two explosions at the same place still ring twice",
			func = function()
				local at = Vector(6000, 6000, 6000)

				-- the blast first
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], at, 300, 1)
				R.ExplosionPing(explosionAt(at))
				expect(#seen).to.equal(1)

				-- the env_explosion first
				R.ResetBlastMemory()
				seen = {}
				R.ExplosionPing(explosionAt(at))
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], at, 300, 1)
				expect(#seen).to.equal(1)

				-- far away: a different explosion, its own ring
				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], at + Vector(2000, 0, 0), 300, 1)
				expect(#seen).to.equal(2)

				-- two env_explosions at the same place are what they were: two rings
				R.ResetBlastMemory()
				seen = {}
				R.ExplosionPing(explosionAt(at))
				R.ExplosionPing(explosionAt(at))
				expect(#seen).to.equal(2)
			end
		},
		{
			-- fails when the memory of the blast stays for ever (a second blast at the same place a second later must ring again)
			name = "the same place a moment later rings again",
			func = function()
				local at = Vector(6000, 6000, 6000)
				local now = CurTime()
				local realCurTime = CurTime

				util.BlastDamage(player.GetAll()[1], player.GetAll()[1], at, 300, 1)
				expect(#seen).to.equal(1)

				CurTime = function() return now + 1 end

				local ok, err = pcall(function()
					R.ResetPingRate()
					util.BlastDamage(player.GetAll()[1], player.GetAll()[1], at, 300, 1)
				end)

				CurTime = realCurTime
				assert(ok, err)
				expect(#seen).to.equal(2)
			end
		},
		{
			-- fails when the real util.BlastDamage no longer hurts: a real blast with the real original on a prop that stands next to it
			name = "with the real original: a blast still damages what is around it",
			func = function()
				local p = player.GetAll()[1]
				local prop = ents.Create("prop_physics")

				prop:SetModel("models/props_junk/PopCan01a.mdl")
				prop:SetPos(p:GetPos() + Vector(300, 0, 40))
				prop:Spawn()

				local hurt = 0
				local ok, err = pcall(function()
					hook.Add("EntityTakeDamage", TAG, function(victim) if victim == prop then hurt = hurt + 1 end end)
					util.BlastDamage(p, p, prop:GetPos(), 200, 50)
				end)

				hook.Remove("EntityTakeDamage", TAG)
				prop:Remove()
				assert(ok, err)
				expect(hurt >= 1).to.beTrue()
			end
		}
	}
}
