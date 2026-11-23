-- Tests of the big map's zoom rules (lua/grymod/client/map/zoom.lua), GLuaTest format, client realm. Pure maths: no engine call. The numbers
-- are the original game's (CryGame.dll, read by the research of the project): zoom from 1 to 8, a wheel notch is z' = 1.35 z - 0.25 in and
-- z' = z / (1.35 - 0.25 / z) out, the analog zoom is z - dy * 0.03.

local function Z()
	local zoom = GryMod and GryMod.Map and GryMod.Map.Zoom

	expect(zoom ~= nil).to.beTrue()

	return zoom
end

return {
	groupName = "GryMod big map zoom",
	cases = {
		-- fails without Zoom.Clamp (the module is missing)
		{
			name = "the zoom is kept from 1 to 8; garbage gives 1",
			func = function()
				local zoom = Z()

				expect(zoom.Clamp(0.2)).to.equal(1)
				expect(zoom.Clamp(3.5)).to.equal(3.5)
				expect(zoom.Clamp(80)).to.equal(8)
				expect(zoom.Clamp(0 / 0)).to.equal(1)
				expect(zoom.Clamp(nil)).to.equal(1)
				expect(zoom.Clamp("5")).to.equal(1)
				expect(zoom.Clamp(math.huge)).to.equal(8)
			end
		},
		-- fails when StepIn is not the original's 1.35 z - 0.25
		{
			name = "a wheel notch in follows the original's rule: 1, 1.10, 1.235, 1.417 ... 8 in eleven notches",
			func = function()
				local zoom = Z()
				local z = 1
				local seen = {}

				for i = 1, 11 do
					z = zoom.StepIn(z)
					seen[i] = z
				end

				expect(seen[1]).to.aboutEqual(1.10, 1e-9)
				expect(seen[2]).to.aboutEqual(1.235, 1e-9)
				expect(seen[3]).to.aboutEqual(1.35 * 1.235 - 0.25, 1e-9)
				expect(seen[11]).to.equal(8)
				expect(seen[10] < 8).to.beTrue()
				-- 8 stays 8
				expect(zoom.StepIn(8)).to.equal(8)
			end
		},
		-- fails when StepOut is not z / (1.35 - 0.25 / z), or when it can go under 1
		{
			name = "a wheel notch out divides by (1.35 - 0.25 / z), never goes under 1 and always goes down above 1",
			func = function()
				local zoom = Z()

				expect(zoom.StepOut(2)).to.aboutEqual(2 / (1.35 - 0.125), 1e-9)
				expect(zoom.StepOut(1)).to.equal(1)
				expect(zoom.StepOut(1.05)).to.equal(1)

				local z = 8
				local count = 0

				while z > 1 and count < 50 do
					local nextZ = zoom.StepOut(z)

					expect(nextZ < z).to.beTrue()
					z = nextZ
					count = count + 1
				end

				expect(z).to.equal(1)
				expect(count < 20).to.beTrue()
			end
		},
		-- fails when Step does not choose by the sign
		{
			name = "Step(z, direction) goes in for a positive direction and out for a negative one; zero changes nothing",
			func = function()
				local zoom = Z()

				expect(zoom.Step(2, 1)).to.equal(zoom.StepIn(2))
				expect(zoom.Step(2, -3)).to.equal(zoom.StepOut(2))
				expect(zoom.Step(2, 0)).to.equal(2)
				expect(zoom.Step(2, nil)).to.equal(2)
			end
		},
		-- fails when the analog zoom does not move 0.03 a pixel, up zooms in
		{
			name = "the middle button zooms continuously: 0.03 per pixel, mouse up (negative dy) zooms in, clamped",
			func = function()
				local zoom = Z()

				expect(zoom.Analog(2, -10)).to.aboutEqual(2.3, 1e-9)
				expect(zoom.Analog(2, 10)).to.aboutEqual(1.7, 1e-9)
				expect(zoom.Analog(7.9, -100)).to.equal(8)
				expect(zoom.Analog(1.1, 100)).to.equal(1)
				expect(zoom.Analog(3, nil)).to.equal(3)
			end
		},
		-- fails when Auto does not fit a small map whole or does not frame 800 m on a big one
		{
			name = "the automatic zoom fits the whole bounds up to 1000 m on the long side, else it frames a window of about 800 m",
			func = function()
				local zoom = Z()

				expect(zoom.Auto(600)).to.equal(1)
				expect(zoom.Auto(1000)).to.equal(1)
				expect(zoom.Auto(1600)).to.aboutEqual(2, 1e-9)
				expect(zoom.Auto(100000)).to.equal(8)
				expect(zoom.Auto(nil)).to.equal(1)
				expect(zoom.Auto(-5)).to.equal(1)
			end
		},
		-- fails when the saved zoom is read without the clamp
		{
			name = "the saved zoom text is read inside 1 to 8, a text that is no number gives 1",
			func = function()
				local zoom = Z()

				expect(zoom.ParseSaved("3.5")).to.equal(3.5)
				expect(zoom.ParseSaved("0")).to.equal(1)
				expect(zoom.ParseSaved("99")).to.equal(8)
				expect(zoom.ParseSaved("abc")).to.equal(1)
				expect(zoom.ParseSaved("")).to.equal(1)
				expect(zoom.ParseSaved(nil)).to.equal(1)
			end
		}
	}
}
