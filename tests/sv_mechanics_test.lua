-- Tests of the suit mechanics (GryMod.Mech), GLuaTest format, server realm. The default is the Crysis rules
-- (read from the demo's game code, research notes research-mech/NOTES.md and research-regen/FINDINGS.md, scaled
-- from its 200 energy to GryMod's 100); gry_mechanics classic gives the earlier GryMod numbers back.

local function ply()
	return player.GetAll()[1]
end

local function thinkHook(name)
	return hook.GetTable().Think[name]
end

local function takeDamage(p, amount)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(DMG_BULLET)
	hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, dmg)

	return dmg
end

local savedConfig

local function near(a, b)
	return math.abs(a - b) < 0.001
end

return {
	groupName = "GryMod suit mechanics",
	beforeAll = function(state)
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function(state)
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetHealth(p:GetMaxHealth())
		p:SetNWFloat("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.ps = nil
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.ShouldRegen = true
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "crysis"
	end,
	afterEach = function(state)
		local p = ply()
		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end
		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			name = "SpeedRunSpeed: the speed sprint runs at the top speed above a fifth of the bar, only a little above the plain sprint between 0 and a fifth (the game's x1.4 against the top x2.85), and a little less empty (x1.3); classic keeps the top speed until empty",
			func = function(state)
				local M = GryMod.Mech
				-- the game's multipliers of the plain sprint (1 = 400 here, 2.85 = 600 here): 1.4 -> 443.2, 1.3 -> 432.4
				local low = 400 + (1.4 - 1) / (2.85 - 1) * 200
				local empty = 400 + (1.3 - 1) / (2.85 - 1) * 200

				expect(M.SpeedRunSpeed(100)).to.equal(600)
				expect(M.SpeedRunSpeed(20.5)).to.equal(600)
				expect(near(M.SpeedRunSpeed(20), low)).to.beTrue()
				expect(near(M.SpeedRunSpeed(1), low)).to.beTrue()
				expect(near(M.SpeedRunSpeed(0), empty)).to.beTrue()
				expect(M.SpeedRunSpeed(0) < M.SpeedRunSpeed(1)).to.beTrue()
				expect(M.SpeedRunSpeed(1) < M.SpeedRunSpeed(21)).to.beTrue()
				-- it is always above the plain sprint (400)
				expect(M.SpeedRunSpeed(0) > 400).to.beTrue()

				GryMod.Config.Mechanics = "classic"
				expect(M.SpeedRunSpeed(100)).to.equal(600)
				expect(M.SpeedRunSpeed(5)).to.equal(600)
				expect(M.SpeedRunSpeed(0)).to.equal(400)
			end
		},
		{
			name = "in the speed mode the run speed follows the energy at every frame (top above a fifth, lower under it, a bit lower empty), and other modes keep the plain 400",
			func = function(state)
				local p = ply()
				local M = GryMod.Mech
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(thinkHook("GryMod run speed") ~= nil).to.beTrue()

				p:SetNWFloat("GryEnergy", 60)
				thinkHook("GryMod run speed")()
				expect(p:GetRunSpeed()).to.equal(600)

				p:SetNWFloat("GryEnergy", 10)
				thinkHook("GryMod run speed")()
				expect(near(p:GetRunSpeed(), M.SpeedRunSpeed(10))).to.beTrue()
				expect(p:GetRunSpeed() < 600).to.beTrue()
				expect(p:GetRunSpeed() > 400).to.beTrue()

				p:SetNWFloat("GryEnergy", 0)
				thinkHook("GryMod run speed")()
				expect(near(p:GetRunSpeed(), M.SpeedRunSpeed(0))).to.beTrue()

				-- back up: the top speed again
				p:SetNWFloat("GryEnergy", 80)
				thinkHook("GryMod run speed")()
				expect(p:GetRunSpeed()).to.equal(600)

				-- another mode: nothing of this
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				p:SetNWFloat("GryEnergy", 5)
				thinkHook("GryMod run speed")()
				expect(p:GetRunSpeed()).to.equal(400)
			end
		},
		{
			name = "the mechanics are the Crysis ones by default, and gry_mechanics classic brings the old numbers back",
			func = function(state)
				local convar = GetConVar("gry_mechanics")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("crysis")
				GryMod.Config.Mechanics = nil
				expect(GryMod.Mech.IsCrysis()).to.beTrue()
				GryMod.Config.Mechanics = "classic"
				expect(GryMod.Mech.IsCrysis()).to.beFalse()
				GryMod.Config.Mechanics = "crysis"
				expect(GryMod.Mech.IsCrysis()).to.beTrue()
			end
		},
		{
			name = "the energy recharges in 8 seconds, 6 in armor mode, 7 in armor mode on the move, after a delay of 1 second",
			func = function(state)
				local M = GryMod.Mech
				expect(near(M.EnergyRechargeRate(GryMod.Modes.SPEED, false), 100 / 8)).to.beTrue()
				expect(near(M.EnergyRechargeRate(GryMod.Modes.ARMOR, false), 100 / 6)).to.beTrue()
				expect(near(M.EnergyRechargeRate(GryMod.Modes.ARMOR, true), 100 / 7)).to.beTrue()
				expect(near(M.EnergyRechargeRate(GryMod.Modes.CLOAK, true), 100 / 8)).to.beTrue()
				expect(M.EnergyRechargeDelay()).to.equal(1)
				GryMod.Config.Mechanics = "classic"
				expect(M.EnergyRechargeRate(GryMod.Modes.ARMOR, false)).to.equal(7)
				expect(M.EnergyRechargeDelay()).to.equal(5)
			end
		},
		{
			name = "a speed sprint costs 42.5 a second above a fifth of the bar (the game's 110 of 200 less the 25 the bar gives back, as the notes say: 85 a second net), almost nothing under it",
			func = function(state)
				local M = GryMod.Mech
				expect(M.SpeedDrain(80)).to.equal(42.5)
				expect(M.SpeedDrain(20.5)).to.equal(42.5)
				expect(M.SpeedDrain(20)).to.equal(1.5)
				expect(M.SpeedDrain(1)).to.equal(1.5)
				expect(M.SpeedDrain(0)).to.equal(0)
				GryMod.Config.Mechanics = "classic"
				expect(M.SpeedDrain(80)).to.equal(GryMod.Config.speedEnergyDrain)
			end
		},
		{
			name = "the cloak costs half a point a second still, 2.5 per metre a second moving, and switches off under a tenth of the bar",
			func = function(state)
				local M = GryMod.Mech
				expect(near(M.CloakDrain(0), 0.5)).to.beTrue()
				expect(near(M.CloakDrain(3 * 52.49), 7.5)).to.beTrue() -- walking at 3 m/s
				expect(M.CloakFailsAt(10)).to.beFalse()
				expect(M.CloakFailsAt(9.9)).to.beTrue()
				GryMod.Config.Mechanics = "classic"
				expect(M.CloakFailsAt(9.9)).to.beFalse()
			end
		},
		{
			name = "jumps: strength needs and costs 35 (the game's 70 of 200), speed costs 5",
			func = function(state)
				local M = GryMod.Mech
				expect(M.JumpCost(GryMod.Modes.STRENGTH)).to.equal(35)
				expect(M.JumpCost(GryMod.Modes.SPEED)).to.equal(5)
				expect(M.JumpCost(GryMod.Modes.ARMOR)).to.equal(0)
				GryMod.Config.Mechanics = "classic"
				expect(M.JumpCost(GryMod.Modes.STRENGTH)).to.equal(40)
				expect(M.JumpCost(GryMod.Modes.SPEED)).to.equal(0)
			end
		},
		{
			name = "the strength jump works from 35 energy and takes 35",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetNWFloat("GryEnergy", 36)
				p:SetGroundEntity(game.GetWorld())
				GryMod.SuperJump(p, IN_JUMP)
				expect(near(p:GetNWFloat("GryEnergy"), 1)).to.beTrue()
			end
		},
		{
			name = "the armor takes at least 30 percent of a hit even with an empty bar",
			func = function(state)
				local p = ply()
				p:SetNWFloat("GryEnergy", 0)
				local dmg = takeDamage(p, 20)
				expect(near(dmg:GetDamage(), 14)).to.beTrue()
				GryMod.Config.Mechanics = "classic"
				p:SetNWFloat("GryEnergy", 0)
				dmg = takeDamage(p, 20)
				expect(near(dmg:GetDamage(), 20)).to.beTrue()
			end
		},
		{
			name = "the armor still absorbs one health point per energy point, and the rest goes through",
			func = function(state)
				local p = ply()
				p:SetNWFloat("GryEnergy", 10)
				local dmg = takeDamage(p, 25)
				expect(near(dmg:GetDamage(), 15)).to.beTrue()
				expect(p:GetNWFloat("GryEnergy")).to.equal(0)
			end
		},
		{
			name = "health returns in whole steps once a second, after 2.5 seconds without damage, and not twice in the same second",
			func = function(state)
				local M = GryMod.Mech
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				p:SetHealth(50)
				p.next_health_regen = CurTime() - 0.1
				p.next_health_tick = nil
				p:SetVelocity(Vector(0, 0, 0))
				thinkHook("GryMod health think")()
				local first = p:Health()
				expect(first).to.beGreaterThan(50)
				-- the full bar takes 20 seconds when standing still outside the armor: 5 a step of 100
				expect(near(first - 50, p:GetMaxHealth() / 20)).to.beTrue()
				thinkHook("GryMod health think")()
				expect(p:Health()).to.equal(first) -- the next step is a second away
				expect(M.HealthDelay()).to.equal(2.5)
			end
		},
		{
			name = "the time to regain all the health: 20 s standing, 27 moving, 10 in armor mode, 15 in armor mode moving",
			func = function(state)
				local M = GryMod.Mech
				expect(M.HealthRegenSeconds(GryMod.Modes.SPEED, false)).to.equal(20)
				expect(M.HealthRegenSeconds(GryMod.Modes.SPEED, true)).to.equal(27)
				expect(M.HealthRegenSeconds(GryMod.Modes.ARMOR, false)).to.equal(10)
				expect(M.HealthRegenSeconds(GryMod.Modes.ARMOR, true)).to.equal(15)
			end
		},
		{
			name = "the repair sound plays in armor mode under 90 percent of the health, at most every 30 seconds",
			func = function(state)
				local M = GryMod.Mech
				expect(M.RepairSoundDue(80, 100, GryMod.Modes.ARMOR, 100, 0)).to.beTrue()
				expect(M.RepairSoundDue(95, 100, GryMod.Modes.ARMOR, 100, 0)).to.beFalse()
				expect(M.RepairSoundDue(80, 100, GryMod.Modes.SPEED, 100, 0)).to.beFalse()
				expect(M.RepairSoundDue(80, 100, GryMod.Modes.ARMOR, 100, 80)).to.beFalse() -- 20 s ago
				expect(M.RepairSoundDue(80, 100, GryMod.Modes.ARMOR, 111, 80)).to.beTrue() -- 31 s ago
			end
		}
	}
}
