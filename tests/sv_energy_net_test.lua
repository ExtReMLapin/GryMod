-- The energy goes to the client at the tick rate (gry_energy message: value and rate of change), because the
-- networked float (SetNW2Float) only reaches the client about every 0.1 s: see
-- docs/superpowers/plans/2026-11-21-energy-smooth.md. GLuaTest format, server realm (one player, singleplayer is enough).

local savedConfig
local P = FindMetaTable("Player")
local saved = {}

local function ply()
	return player.GetAll()[1]
end

local function thinkHook(name)
	return hook.GetTable().Think[name]
end

-- every stub is restored in afterEach, even when a case fails
local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local TICK = 1 / 66

local function setUp(p, opts)
	opts = opts or {}
	p:SetNW2Float("GryEnergy", opts.energy or 60)
	p:SetNanosuitMode(opts.mode or GryMod.Modes.ARMOR, false)
	p.next_energy_regen = opts.regen or 0
	p.energy_on_use = p:GetNW2Float("GryEnergy")
	stub(_G, "FrameTime", function() return TICK end)
	stub(P, "IsSprinting", function() return opts.sprint or false end)
	stub(P, "GetVelocity", function() return Vector(opts.speed or 0, 0, 0) end)
	stub(P, "IsOnGround", function() return opts.ground ~= false end)
	stub(P, "WaterLevel", function() return 0 end)
end

-- the energy a tick really gives or takes, per second, once every hook of the Think has run
local function realRate(p)
	local before = p:GetNW2Float("GryEnergy")
	thinkHook("GrySpeedThink")()
	thinkHook("GryCloakThink")()
	thinkHook("GryMod health think")()

	return (p:GetNW2Float("GryEnergy") - before) / TICK
end

local function near(a, b)
	return math.abs(a - b) < 0.01
end

return {
	groupName = "GryMod energy net",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "crysis"
		p.gryEnergySent = nil
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			local s = saved[i]
			s[1][s[2]] = s[3]
		end
		saved = {}
		local p = ply()
		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNW2Float("GryEnergy", 100)
			p.next_energy_regen = 0
		end
		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			name = "the rate the server tells is the rate the Think hooks really apply: speed sprint above and below a fifth of the bar",
			func = function()
				local p = ply()
				setUp(p, {mode = GryMod.Modes.SPEED, sprint = true, speed = 600, energy = 60})
				expect(GryMod.EnergyRate ~= nil).to.beTrue()
				local rate = GryMod.EnergyRate(p)
				expect(near(rate, -42.5)).to.beTrue()
				expect(near(realRate(p), rate)).to.beTrue()
				p:SetNW2Float("GryEnergy", 15)
				rate = GryMod.EnergyRate(p)
				expect(near(rate, -1.5)).to.beTrue()
				expect(near(realRate(p), rate)).to.beTrue()
			end
		},
		{
			name = "an empty bar, a speed sprint that is too slow and a speed sprint in the air do not drain the bar (the recharge, once its delay is over, is what moves it)",
			func = function()
				local p = ply()
				setUp(p, {mode = GryMod.Modes.SPEED, sprint = true, speed = 600, energy = 0, regen = CurTime() + 1})
				expect(GryMod.EnergyRate(p)).to.equal(0)
				p:SetNW2Float("GryEnergy", 60)
				stub(P, "GetVelocity", function() return Vector(100, 0, 0) end)
				expect(GryMod.EnergyRate(p)).to.equal(0)
				stub(P, "GetVelocity", function() return Vector(600, 0, 0) end)
				stub(P, "IsOnGround", function() return false end)
				expect(GryMod.EnergyRate(p)).to.equal(0)
				-- the delay over, an empty bar under a sprint recharges, and the rate says so
				p:SetNW2Float("GryEnergy", 0)
				p.next_energy_regen = CurTime() - 0.1
				stub(P, "IsOnGround", function() return true end)
				local rate = GryMod.EnergyRate(p)
				expect(near(rate, 100 / 8)).to.beTrue()
				expect(near(realRate(p), rate)).to.beTrue()
			end
		},
		{
			name = "the cloak takes what its speed costs; it gives out below a tenth of the bar (no prediction then)",
			func = function()
				local p = ply()
				setUp(p, {mode = GryMod.Modes.CLOAK, speed = 300, energy = 60})
				local rate = GryMod.EnergyRate(p)
				expect(near(rate, -GryMod.Mech.CloakDrain(300))).to.beTrue()
				expect(near(realRate(p), rate)).to.beTrue()
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryEnergy", 5)
				expect(GryMod.EnergyRate(p)).to.equal(0)
			end
		},
		{
			name = "the recharge: nothing during the delay, then the rate of the mode (armor still, armor moving, others)",
			func = function()
				local p = ply()
				setUp(p, {mode = GryMod.Modes.ARMOR, energy = 40, regen = CurTime() + 1})
				expect(GryMod.EnergyRate(p)).to.equal(0)
				p.next_energy_regen = CurTime() - 0.1
				local rate = GryMod.EnergyRate(p)
				expect(near(rate, 100 / 6)).to.beTrue()
				expect(near(realRate(p), rate)).to.beTrue()
				stub(P, "GetVelocity", function() return Vector(200, 0, 0) end)
				expect(near(GryMod.EnergyRate(p), 100 / 7)).to.beTrue()
				expect(near(realRate(p), 100 / 7)).to.beTrue()
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				expect(near(GryMod.EnergyRate(p), 100 / 8)).to.beTrue()
				expect(near(realRate(p), 100 / 8)).to.beTrue()
			end
		},
		{
			name = "a full bar, a suit that is down, the infinite armor and a dead player: no movement, no prediction",
			func = function()
				local p = ply()
				setUp(p, {energy = 100, regen = CurTime() - 1})
				expect(GryMod.EnergyRate(p)).to.equal(0)
				p:SetNW2Float("GryEnergy", 40)
				expect(GryMod.EnergyRate(p) > 0).to.beTrue()
				p:SetNW2Bool("GryMalfunction", true)
				local ok, err = pcall(function()
					expect(GryMod.EnergyRate(p)).to.equal(0)
					expect(near(realRate(p), 0)).to.beTrue()
				end)
				p:SetNW2Bool("GryMalfunction", false)
				assert(ok, err)
				GryMod.Config.InfiniteArmor = true
				expect(GryMod.EnergyRate(p)).to.equal(0)
				GryMod.Config.InfiniteArmor = false
				stub(P, "Alive", function() return false end)
				expect(GryMod.EnergyRate(p)).to.equal(0)
			end
		},
		{
			name = "the classic rules: a recharge of 7 a second, the speed drain of the config",
			func = function()
				local p = ply()
				GryMod.Config.Mechanics = "classic"
				setUp(p, {mode = GryMod.Modes.ARMOR, energy = 40, regen = CurTime() - 0.5})
				p.energy_on_use = 40
				expect(near(GryMod.EnergyRate(p), 7)).to.beTrue()
				setUp(p, {mode = GryMod.Modes.SPEED, sprint = true, speed = 600, energy = 60})
				expect(near(GryMod.EnergyRate(p), -GryMod.Config.speedEnergyDrain)).to.beTrue()
				expect(near(realRate(p), -GryMod.Config.speedEnergyDrain)).to.beTrue()
			end
		},
		{
			name = "gry_energy_net exists and is on by default",
			func = function()
				local c = GetConVar("gry_energy_net")
				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
			end
		},
		{
			name = "every tick the energy changes, one unreliable gry_energy message goes to the player with the value and the rate; nothing when nothing changed",
			func = function()
				local p = ply()
				setUp(p, {mode = GryMod.Modes.SPEED, sprint = true, speed = 600, energy = 60, regen = CurTime() + 1})
				local sent = {}
				local current
				stub(net, "Start", function(name, unreliable) current = {name = name, unreliable = unreliable, floats = {}} end)
				stub(net, "WriteFloat", function(v) current.floats[#current.floats + 1] = v end)
				stub(net, "Send", function(target) current.target = target; sent[#sent + 1] = current end)
				local send = thinkHook("GryMod energy net")
				expect(send ~= nil).to.beTrue()
				send()
				expect(#sent).to.equal(1)
				expect(sent[1].name).to.equal("gry_energy")
				expect(sent[1].unreliable).to.beTrue()
				expect(sent[1].target).to.equal(p)
				expect(near(sent[1].floats[1], 60)).to.beTrue()
				expect(near(sent[1].floats[2], -42.5)).to.beTrue()
				send()
				expect(#sent).to.equal(1)
				p:SetNW2Float("GryEnergy", 59.4)
				send()
				expect(#sent).to.equal(2)
				expect(near(sent[2].floats[1], 59.4)).to.beTrue()
				-- the rate alone changes (the sprint stops): the client must know
				stub(P, "IsSprinting", function() return false end)
				send()
				expect(#sent).to.equal(3)
				expect(sent[3].floats[2]).to.equal(0)
			end
		},
		{
			name = "gry_energy_net 0 sends nothing (the networked float stays the only channel)",
			func = function()
				local p = ply()
				setUp(p, {energy = 60})
				local count = 0
				stub(net, "Start", function() count = count + 1 end)
				stub(net, "WriteFloat", function() end)
				stub(net, "Send", function() end)
				local c = GetConVar("gry_energy_net")
				c:SetBool(false)
				local ok, err = pcall(function()
					thinkHook("GryMod energy net")()
				end)
				c:SetBool(true)
				assert(ok, err)
				expect(count).to.equal(0)
			end
		}
	}
}
