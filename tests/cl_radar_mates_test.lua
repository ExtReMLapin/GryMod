-- Tests of the team mates as the radar draws them (contacts of type 7, Radar.Contacts in cl_hud_radar_units.lua), GLuaTest format, client realm. The original
-- clamps a mate to the circle of the range instead of dropping it past the frame, draws it at alpha 100 and at 100 times the height factor in percent
-- (4 times a unit's size). The numbers are in docs/superpowers/plans/status/radar.md of the project.

local U = 0.01905

local function metres(m)
	return m / U
end

local PX = 110 / 94
local CX, CY = 64.1, 52.3

local function mate(ahead, right, extra)
	local c = {id = 7, x = metres(ahead or 0), y = -metres(right or 0), z = 0, yaw = 0, type = 7, sub = 0}

	for k, v in pairs(extra or {}) do
		c[k] = v
	end

	return c
end

local function one(c, yaw)
	return GryMod.FlashRadar.Contacts(Vector(0, 0, 0), yaw or 0, {c}, 0)[1]
end

return {
	groupName = "GryMod radar team mates (client)",
	cases = {
		-- fails when Contacts drops a mate that is past the frame
		{
			name = "a mate far ahead sticks to the circle of the range (43 radar pixels) instead of vanishing, in the frame 35 icon",
			func = function(state)
				local e = one(mate(500, 0))
				expect(e).toNot.beNil()
				expect(e.frame).to.equal(35)
				expect(e.x).to.aboutEqual(CX, 0.01)
				expect(e.y).to.aboutEqual(CY - 43 * PX, 0.01)
				-- in the direction of the mate: 300 m to the right and 300 m ahead is on the diagonal
				local d = one(mate(300, 300))
				expect(d.x).to.aboutEqual(CX + 43 * math.sqrt(0.5) * PX, 0.01)
				expect(d.y).to.aboutEqual(CY - 43 * math.sqrt(0.5) * PX, 0.01)
			end
		},
		{
			name = "a mate inside the range is where it is, drawn at alpha 100 (a unit is 85) and 4 times the unit's size by height (190 level with the player)",
			func = function(state)
				local e = one(mate(37.5, 0))
				expect(e.y).to.aboutEqual(CY - 21.5 * PX, 0.01)
				expect(e.alpha).to.aboutEqual(100, 0.01)
				expect(e.scale).to.aboutEqual(190, 0.01)
				-- a unit of the same place keeps its own look
				local unit = one(mate(37.5, 0, {type = 1, sub = 0}))
				expect(unit.alpha).to.aboutEqual(85, 0.01)
				expect(unit.scale).to.aboutEqual(47.5, 0.01)
				expect(unit.frame).to.equal(5)
			end
		},
		{
			name = "a unit past the frame is still dropped (only the mates are held on the circle), and a mate never raises the danger bar",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(#R.Contacts(Vector(0, 0, 0), 0, {mate(500, 0, {type = 1, sub = 4})}, 0)).to.equal(0)
				expect(R.Awareness(mate(10, 0))).to.equal(0)
			end
		}
	}
}
