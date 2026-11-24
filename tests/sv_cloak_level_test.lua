-- Tests of the cloak level stamps written by the server (lua/grymod/server/sv_system.lua, SetNanosuitMode) and read by
-- GryMod.API.CloakLevel (lua/grymod/sh_cloak_level.lua), GLuaTest format, server realm. Uses the player of the test instance.
-- At each real switch of the cloak (on to off or off to on) the server writes the level of that moment (GryCloakLvl0) and the
-- time (GryCloakT0): the level then moves from there at 1 / gry_cloak_fade_seconds per second.

local function ply()
	return player.GetAll()[1]
end

local saved

return {
	groupName = "GryMod cloak level stamps (server)",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNW2Float("GryEnergy", 100)
		-- every case runs in the same frame: without this, a case would start in the fade-out of the one before
		p:SetNW2Float("GryCloakLvl0", 0)
		p:SetNW2Float("GryCloakT0", 0)
		saved =GetConVar("gry_cloak_fade_seconds") and GetConVar("gry_cloak_fade_seconds"):GetString()

		if saved then
			GetConVar("gry_cloak_fade_seconds"):SetString("2")
		end
	end,
	afterEach = function()
		local p = ply()

		if IsValid(p) then
			if not p:Alive() then p:Spawn() end
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end

		if saved then
			GetConVar("gry_cloak_fade_seconds"):SetString(saved)
		end
	end,
	cases = {
		{
			name = "cloaking writes the stamps: level 0 and the time of the switch",
			func = function()
				local p = ply()
				local now = CurTime()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)

				expect(p:GetNW2Float("GryCloakT0", -1)).to.aboutEqual(now, 0.001)
				expect(p:GetNW2Float("GryCloakLvl0", -1)).to.equal(0)
				expect(GryMod.API.CloakLevel(p)).to.aboutEqual(0, 0.001)
			end
		},
		{
			name = "one second after the switch (stamp moved back by 1 s) the level is 0.5",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 1)

				expect(GryMod.API.CloakLevel(p)).to.aboutEqual(0.5, 0.01)
			end
		},
		{
			name = "leaving the cloak at level 0.5 stamps 0.5, so the level does not jump",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 1)
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)

				expect(p:GetNW2Float("GryCloakLvl0", -1)).to.aboutEqual(0.5, 0.01)
				expect(GryMod.API.CloakLevel(p)).to.aboutEqual(0.5, 0.01)
			end
		},
		{
			name = "the same mode asked again does not touch the stamps",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", 123)
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)

				expect(p:GetNW2Float("GryCloakT0", -1)).to.equal(123)
			end
		},
		{
			name = "a dead player has level 0",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 5)
				p:KillSilent()

				expect(GryMod.API.CloakLevel(p)).to.equal(0)
			end
		},
		{
			name = "a respawn during the fade-out of a cloak already switched off starts at 0 (final review, item 1)",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 5)
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 0.1)
				expect(GryMod.API.CloakLevel(p) > 0.5).to.beTrue()
				p:KillSilent()
				p:Spawn()

				expect(GryMod.API.CloakLevel(p)).to.equal(0)
			end
		},
		{
			name = "after a respawn the level is 0 at once (no fade-out from the old life)",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 5)
				p:KillSilent()
				p:Spawn()

				expect(GryMod.API.CloakLevel(p)).to.equal(0)
			end
		}
	}
}
