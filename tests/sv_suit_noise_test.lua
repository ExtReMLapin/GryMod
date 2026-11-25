-- Tests of the suit noises (lua/grymod/server/sv_suit_noise.lua), GLuaTest format, server realm.
-- GryMod tells other addons (the smart soldier's hearing) about the noises only the suit knows of, with the hook
-- GryMod_SuitNoise(ply, pos, radius, kind): a strength jump, the start of a speed sprint, the cloak switching on or off, a shot fired while
-- the cloak level is above 0. GryMod.SuitNoiseRadius holds the radius of each kind, in units. Design: spec section 6.3.

local function ply()
	return player.GetAll()[1]
end

local calls = {}
local HOOK = "GryMod test suit noise recorder"

local function bullets()
	return hook.GetTable().EntityFireBullets["GryMod suit noise"]
end

return {
	groupName = "GryMod suit noises (server)",
	beforeEach = function()
		calls = {}
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNW2Float("GryEnergy", 100)
		p:SetNW2Float("GryCloakLvl0", 0)
		p:SetNW2Float("GryCloakT0", 0)
		calls = {}

		hook.Add("GryMod_SuitNoise", HOOK, function(who, pos, radius, kind)
			calls[#calls + 1] = {who = who, pos = pos, radius = radius, kind = kind}
		end)

		if GryMod.SuitNoiseReset then
			GryMod.SuitNoiseReset()
		end
	end,
	afterEach = function()
		hook.Remove("GryMod_SuitNoise", HOOK)
		local p = ply()

		if IsValid(p) then
			if not p:Alive() then p:Spawn() end
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end
	end,
	cases = {
		{
			name = "a strength jump is a noise of 1000 units at the player",
			func = function()
				local p = ply()

				hook.Run("GryMod_StrengthJump", p)

				expect(#calls).to.equal(1)
				expect(calls[1].who).to.equal(p)
				expect(calls[1].kind).to.equal("strength_jump")
				expect(calls[1].radius).to.equal(1000)
				expect(calls[1].pos).to.equal(p:GetPos())
			end
		},
		{
			name = "the start of a speed sprint is a noise of 800 units",
			func = function()
				hook.Run("GryMod_SprintStart", ply())

				expect(#calls).to.equal(1)
				expect(calls[1].kind).to.equal("speed_sprint")
				expect(calls[1].radius).to.equal(800)
			end
		},
		{
			name = "the cloak switching on then off gives cloak_on then cloak_off",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)

				expect(#calls).to.equal(2)
				expect(calls[1].kind).to.equal("cloak_on")
				expect(calls[2].kind).to.equal("cloak_off")
				expect(calls[1].radius).to.equal(300)
			end
		},
		{
			name = "a respawn gives no cloak noise",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				calls = {}
				p:KillSilent()
				p:Spawn()

				expect(#calls).to.equal(0)
			end
		},
		{
			name = "a shot of a cloaked player is cloak_fire, once per quarter second, and the hook changes nothing",
			func = function()
				local p = ply()
				local fn = bullets()
				expect(isfunction(fn)).to.beTrue()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 3)
				calls = {}

				expect(fn(p, {})).to.beNil()
				fn(p, {})

				expect(#calls).to.equal(1)
				expect(calls[1].kind).to.equal("cloak_fire")
				expect(calls[1].radius).to.equal(2000)
			end
		},
		{
			name = "the shot of an NPC or of a player that is not cloaked is no suit noise",
			func = function()
				local fn = bullets()
				expect(isfunction(fn)).to.beTrue()
				local npc = ents.Create("npc_combine_s")
				npc:SetPos(ply():GetPos() + Vector(300, 0, 10))
				npc:Spawn()

				local ok = pcall(function()
					fn(npc, {})
					fn(ply(), {})
				end)

				npc:Remove()
				expect(ok).to.beTrue()
				expect(#calls).to.equal(0)
			end
		},
		{
			name = "a GryMod_SuitNoise listener that throws does not break the bullet hook (final review, item 6)",
			func = function()
				local p = ply()
				local fn = bullets()
				local ok

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 3)
				hook.Add("GryMod_SuitNoise", "GryMod test throwing listener", function() error("a broken addon") end)
				ok = pcall(fn, p, {})
				hook.Remove("GryMod_SuitNoise", "GryMod test throwing listener")

				expect(ok).to.beTrue()
			end
		},
		{
			name = "EmitSuitNoise refuses an unknown kind and an invalid player",
			func = function()
				expect(GryMod.EmitSuitNoise(ply(), "nope")).to.beFalse()
				expect(GryMod.EmitSuitNoise(NULL, "cloak_on")).to.beFalse()
				expect(#calls).to.equal(0)
			end
		},
		{
			name = "the feature is announced",
			func = function()
				expect(GryMod.API.Has("suitnoise")).to.beTrue()
			end
		}
	}
}
