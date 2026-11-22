-- GryMod server-side tests, GLuaTest format (run with gmod-mcp: tests_run realm=server).
-- Needs a loaded map with one player (singleplayer is enough).

local savedConfig
-- the two toggles are real (archived) settings now: the cases that flip them put the convars back
local TOGGLE_CONVARS = {"gry_health_regen", "gry_infinite_armor"}
local savedConvars = {}

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

return {
	groupName = "GryMod server",
	beforeAll = function(state)
		savedConfig = table.Copy(GryMod.Config)

		for _, name in ipairs(TOGGLE_CONVARS) do
			savedConvars[name] = GetConVar(name):GetString()
		end
	end,
	afterAll = function(state)
		for _, name in ipairs(TOGGLE_CONVARS) do
			GetConVar(name):SetString(savedConvars[name])
		end
	end,
	beforeEach = function(state)
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.ps = nil
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.ShouldRegen = true
		GryMod.Config.InfiniteArmor = false
		-- these tests pin the earlier numbers; the Crysis ones are in sv_mechanics_test.lua
		GryMod.Config.Mechanics = "classic"
	end,
	afterEach = function(state)
		if state.realGetHands then
			FindMetaTable("Player").GetHands = state.realGetHands
			state.realGetHands = nil
		end

		local p = ply()
		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end
		for _, name in ipairs(TOGGLE_CONVARS) do
			GetConVar(name):SetString(savedConvars[name])
		end

		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			name = "health regeneration is regenerating when enabled",
			func = function(state)
				local p = ply()
				p:SetHealth(50)
				p.health_on_dmg = 50
				p.next_health_regen = CurTime() - 2
				thinkHook("GryMod health think")()
				expect(p:Health()).to.beGreaterThan(50)
			end
		},
		{
			name = "health regeneration never lowers the health (medkit during the delay)",
			func = function(state)
				local p = ply()
				p:SetHealth(90)
				p.health_on_dmg = 50
				p.next_health_regen = CurTime() - 0.1
				thinkHook("GryMod health think")()
				expect(p:Health()).to.beGreaterThan(89)
			end
		},
		{
			name = "gry_Health off really stops the health regeneration",
			func = function(state)
				local p = ply()
				GryMod.Config.ShouldRegen = false
				p:SetHealth(50)
				p.health_on_dmg = 50
				p.next_health_regen = CurTime() - 2
				thinkHook("GryMod health think")()
				expect(p:Health()).to.equal(50)
			end
		},
		{
			name = "infinite armor: armor mode absorbs a hit bigger than the energy bar",
			func = function(state)
				local p = ply()
				GryMod.Config.InfiniteArmor = true
				local dmg = takeDamage(p, 500)
				expect(dmg:GetDamage()).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
			end
		},
		{
			name = "armor mode without infinite armor still spends energy",
			func = function(state)
				local p = ply()
				local dmg = takeDamage(p, 30)
				expect(dmg:GetDamage()).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(70)
			end
		},
		{
			name = "super jump costs 40 energy",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetGroundEntity(game.GetWorld())
				GryMod.SuperJump(p, IN_JUMP)
				expect(p:GetNW2Float("GryEnergy")).to.equal(60)
			end
		},
		{
			name = "infinite armor: super jump is free but still happens",
			func = function(state)
				local p = ply()
				GryMod.Config.InfiniteArmor = true
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetGroundEntity(game.GetWorld())
				GryMod.SuperJump(p, IN_JUMP)
				expect(p.ps).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
			end
		},
		{
			name = "the very first jump with an empty bar is a small jump",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetNW2Float("GryEnergy", 10)
				p.ps = nil
				GryMod.SuperJump(p, IN_JUMP)
				expect(p:GetJumpPower()).to.equal(200)
			end
		},
		{
			name = "leaving the cloak by attacking keeps the energy at zero",
			func = function(state)
				local p = ply()
				p:SetNW2Float("GryEnergy", 80)
				hook.Run("GryUseEnergy", p) -- what a drain tick does
				net.Receivers["gry_empty_energy"](0, p)
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				p.next_energy_regen = CurTime() - 1
				thinkHook("GryMod health think")()
				expect(p:GetNW2Float("GryEnergy")).to.beLessThan(20)
			end
		},
		{
			name = "a client cannot put the player in a mode that does not exist",
			func = function(state)
				local p = ply()
				GryMod.SetModeFromClient(p, 99)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				GryMod.SetModeFromClient(p, GryMod.Modes.DROP)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
			end
		},
		{
			name = "a client can pick a real mode",
			func = function(state)
				local p = ply()
				GryMod.SetModeFromClient(p, GryMod.Modes.SPEED)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.SPEED)
				expect(p:GetRunSpeed()).to.equal(600)
			end
		},
		{
			name = "cloak does not error when the player has no hands entity",
			func = function(state)
				local p = ply()
				local meta = FindMetaTable("Player")
				state.realGetHands = meta.GetHands
				meta.GetHands = function() return NULL end -- gamemodes without c_arms
				expect(function() p:SetNanosuitMode(GryMod.Modes.CLOAK, false) end).to.succeed()
			end
		},
		{
			name = "the admin toggles work from the server console (no player)",
			func = function(state)
				expect(function() GryMod.ToggleHealthRegen(NULL) end).to.succeed()
				expect(GryMod.Config.ShouldRegen).to.beFalse()
				expect(function() GryMod.ToggleInfiniteArmor(NULL) end).to.succeed()
				expect(GryMod.Config.InfiniteArmor).to.beTrue()
			end
		},
		{
			name = "the admin toggles work for an admin",
			func = function(state)
				local p = ply()
				expect(p:IsAdmin()).to.beTrue() -- singleplayer host
				GryMod.ToggleHealthRegen(p)
				expect(GryMod.Config.ShouldRegen).to.beFalse()
				GryMod.ToggleHealthRegen(p)
				expect(GryMod.Config.ShouldRegen).to.beTrue()
			end
		},
	}
}
