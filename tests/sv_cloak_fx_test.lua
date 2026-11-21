-- Tests of what the server tells the clients about the camouflage (the look itself is made by each client, see
-- cl_cloak_fx.lua), GLuaTest format, server realm: the network switch "GryCloak", and that the gameplay of the mode
-- (nobody targets the player) is as before. Needs a loaded map with one player.

local function ply()
	return player.GetAll()[1]
end

return {
	groupName = "GryMod camouflage, server side",
	beforeEach = function(state)
		local p = ply()

		if not p:Alive() then p:Spawn() end

		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
	end,
	afterAll = function(state)
		ply():SetNanosuitMode(GryMod.Modes.ARMOR, false)
	end,
	cases = {
		{
			name = "the camouflage is a network switch the other players can read",
			func = function(state)
				local p = ply()
				expect(p:GetNW2Bool("GryCloak", false)).to.beFalse()
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(p:GetNW2Bool("GryCloak", false)).to.beTrue()
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(p:GetNW2Bool("GryCloak", false)).to.beFalse()
			end
		},
		{
			name = "every other mode puts the switch off",
			func = function(state)
				local p = ply()

				for _, mode in ipairs({GryMod.Modes.SPEED, GryMod.Modes.STRENGTH, GryMod.Modes.ARMOR}) do
					p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
					expect(p:GetNW2Bool("GryCloak", false)).to.beTrue()
					p:SetNanosuitMode(mode, false)
					expect(p:GetNW2Bool("GryCloak", false)).to.beFalse()
				end
			end
		},
		{
			name = "the server no longer puts a material on the player: each client draws the camouflage",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(p:GetMaterial()).to.equal("")

				local hands = p:GetHands()

				if IsValid(hands) then
					expect(hands:GetMaterial()).to.equal("")
				end
			end
		},
		{
			name = "the gameplay of the mode is unchanged: the NPCs do not target the player",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(p:IsFlagSet(FL_NOTARGET)).to.beTrue()
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(p:IsFlagSet(FL_NOTARGET)).to.beFalse()
			end
		},
	}
}
