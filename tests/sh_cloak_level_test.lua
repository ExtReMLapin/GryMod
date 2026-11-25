-- Tests of the cloak level (lua/grymod/sh_cloak_level.lua), GLuaTest format, shared: run in the server AND the client realm.
-- The cloak is a switch for the player, but an AI that sees a cloaked player fade in or out needs a level from 0 to 1. GryMod
-- writes two stamps at each switch (the level at that moment and the time), and the level is computed from them: no Think.
-- Design: docs/superpowers/specs/2026-11-24-smart-soldier-design.md section 6.1.

local saved

return {
	groupName = "GryMod cloak level (shared)",
	beforeEach = function()
		local c = GetConVar("gry_cloak_fade_seconds")
		saved = c and c:GetString()
	end,
	afterEach = function()
		-- only the server may write a replicated convar; the client run never changes it
		if SERVER and saved then
			GetConVar("gry_cloak_fade_seconds"):SetString(saved)
		end
	end,
	cases = {
		{
			name = "CloakLevelFrom moves from level0 toward 1 (on) or 0 (off) at the given rate since t0, clamped",
			func = function()
				local f = GryMod.CloakLevelFrom

				expect(f(true, 0, 10, 10, 0.5)).to.equal(0)
				expect(f(true, 0, 10, 11, 0.5)).to.equal(0.5)
				expect(f(true, 0, 10, 13, 0.5)).to.equal(1)
				expect(f(false, 1, 10, 11, 0.5)).to.equal(0.5)
				expect(f(false, 1, 10, 12.5, 0.5)).to.equal(0)
			end
		},
		{
			name = "a re-cloak during the fade-out goes on from the level it had",
			func = function()
				expect(GryMod.CloakLevelFrom(true, 0.5, 11, 11.5, 0.5)).to.equal(0.75)
			end
		},
		{
			name = "a clock that went back never moves the level past level0",
			func = function()
				expect(GryMod.CloakLevelFrom(true, 0, 10, 9, 0.5)).to.equal(0)
				expect(GryMod.CloakLevelFrom(false, 1, 10, 9, 0.5)).to.equal(1)
			end
		},
		{
			name = "a rate of math.huge (fade of 0 s) is instant, a rate of 2 (fade of 0.5 s) is quick",
			func = function()
				expect(GryMod.CloakLevelFrom(true, 0, 10, 10, math.huge)).to.equal(1)
				expect(GryMod.CloakLevelFrom(false, 1, 10, 10, math.huge)).to.equal(0)
				expect(GryMod.CloakLevelFrom(true, 0, 10, 10.25, 2)).to.equal(0.5)
			end
		},
		{
			name = "CloakFadeRate follows gry_cloak_fade_seconds: 2 gives 0.5, 0.5 gives 2, 0 gives math.huge",
			when = SERVER,
			func = function()
				local c = GetConVar("gry_cloak_fade_seconds")
				expect(c).to.exist()

				c:SetString("2")
				expect(GryMod.CloakFadeRate()).to.equal(0.5)
				c:SetString("0.5")
				expect(GryMod.CloakFadeRate()).to.equal(2)
				c:SetString("0")
				expect(GryMod.CloakFadeRate()).to.equal(math.huge)
			end
		},
		{
			name = "the convar exists in both realms with a default of 2",
			func = function()
				local c = GetConVar("gry_cloak_fade_seconds")
				expect(c).to.exist()
				expect(c:GetDefault()).to.equal("2")
			end
		},
		{
			name = "the feature is announced",
			func = function()
				expect(GryMod.API.Has("cloaklevel")).to.beTrue()
				expect(isfunction(GryMod.API.CloakLevel)).to.beTrue()
			end
		}
	}
}
