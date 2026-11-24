-- Tests of the big map's zoom rules (lua/grymod/client/map/zoom.lua), GLuaTest format, client realm. Pure maths: no engine call. The numbers
-- are the original game's (CryGame.dll, read by the research of the project): zoom from 1 to 8, a wheel notch is z' = 1.35 z - 0.25 in and
-- z' = z / (1.35 - 0.25 / z) out, the analog zoom is z - dy * 0.03. The closest zoom is 8 for a call that is given none; a view brings its own limit (MaxFor).

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
		-- fails when MaxFor does not turn a number of centimetres a pixel into a zoom, or goes under 8 / over the absolute limit
		{
			name = "MaxFor: the closest zoom is where a pixel covers the centimetres asked, never under 8, never over 1024, garbage gives 8",
			func = function()
				local zoom = Z()
				-- 4 km map in a 1000 pixel window: k1 = 1000 / (4000 / 0.01905) = 0.0047625 pixel a unit; 7 cm a pixel is 0.01905 / 0.07 = 0.2721 pixel a unit
				local k1 = 1000 / (4000 / 0.01905)

				expect(zoom.MaxFor(k1, 7)).to.aboutEqual((0.01905 / 0.07) / k1, 1e-9)
				expect(zoom.MaxFor(k1, 7) > 50).to.beTrue()
				-- a closer setting (1 cm) allows more, a looser one (50 cm) less
				expect(zoom.MaxFor(k1, 1) > zoom.MaxFor(k1, 7)).to.beTrue()
				expect(zoom.MaxFor(k1, 50) < zoom.MaxFor(k1, 7)).to.beTrue()
				-- a small map keeps the original's 8
				expect(zoom.MaxFor(0.5, 7)).to.equal(8)
				-- a huge map stops at the absolute limit
				expect(zoom.MaxFor(1e-9, 7)).to.equal(zoom.ABSOLUTE_MAX)
				expect(zoom.MaxFor(nil, 7)).to.equal(8)
				expect(zoom.MaxFor(k1, nil)).to.equal(8)
				expect(zoom.MaxFor(0, 7)).to.equal(8)
				expect(zoom.MaxFor(k1, 0 / 0)).to.equal(8)
			end
		},
		-- fails when the functions ignore the limit they are given
		{
			name = "Clamp, the wheel, the middle button and Auto take the view's limit as their last argument",
			func = function()
				local zoom = Z()

				expect(zoom.Clamp(40, 57)).to.equal(40)
				expect(zoom.Clamp(80, 57)).to.equal(57)
				expect(zoom.Clamp(80, 5000)).to.equal(zoom.ABSOLUTE_MAX > 80 and 80 or zoom.ABSOLUTE_MAX)
				-- a garbage limit is the default 8
				expect(zoom.Clamp(20, "x")).to.equal(8)
				expect(zoom.Clamp(20, 0.2)).to.equal(8)

				expect(zoom.StepIn(30, 57)).to.aboutEqual(1.35 * 30 - 0.25, 1e-9)
				expect(zoom.StepIn(50, 57)).to.equal(57)
				expect(zoom.StepIn(57, 57)).to.equal(57)
				expect(zoom.StepOut(57, 57) < 57).to.beTrue()
				expect(zoom.Step(20, 1, 57)).to.equal(zoom.StepIn(20, 57))
				expect(zoom.Step(20, -1, 57)).to.equal(zoom.StepOut(20, 57))
				expect(zoom.Step(90, 0, 57)).to.equal(57)

				-- from 1 to the limit of a big map in a reasonable number of notches
				local z, notches = 1, 0

				while z < 57 and notches < 60 do
					z = zoom.StepIn(z, 57)
					notches = notches + 1
				end

				expect(z).to.equal(57)
				expect(notches <= 25).to.beTrue()

				expect(zoom.Analog(30, -10, 57) > 30).to.beTrue()
				expect(zoom.Analog(56.9, -1000, 57)).to.equal(57)

				-- the automatic zoom is held by the limit it is given
				expect(zoom.Auto(100000, 57)).to.equal(57)
				expect(zoom.Auto(100000, 5000)).to.aboutEqual(100000 / 800, 1e-9)
			end
		},
		-- fails when the smooth zoom keeps 0.03 a pixel above 8 (two thousand pixels of mouse to reach 60) or changes the original's rate up to 8
		{
			name = "the middle button grows its step with the zoom above 8, and is the original's 0.03 a pixel up to 8",
			func = function()
				local zoom = Z()

				expect(zoom.Analog(8, -10, 100)).to.aboutEqual(8.3, 1e-9)
				expect(zoom.Analog(16, -10, 100)).to.aboutEqual(16 + 10 * 0.03 * 2, 1e-9)
				expect(zoom.Analog(40, 10, 100)).to.aboutEqual(40 - 10 * 0.03 * 5, 1e-9)

				-- from 8 to 60 in at most 700 pixels of mouse (0.03 a pixel all the way would take 1733)
				local z, pixels = 8, 0

				while z < 60 and pixels < 5000 do
					z = zoom.Analog(z, -1, 100)
					pixels = pixels + 1
				end

				expect(pixels <= 700).to.beTrue()
			end
		},
		-- fails when the setting is not read inside 1 to 100 with 7 by default
		{
			name = "the centimetres a pixel covers: 1 to 100, 7 by default, a text that is no number gives 7",
			func = function()
				local zoom = Z()

				expect(zoom.ParseCentimetres("7")).to.equal(7)
				expect(zoom.ParseCentimetres("2.5")).to.equal(2.5)
				expect(zoom.ParseCentimetres("0")).to.equal(1)
				expect(zoom.ParseCentimetres("-4")).to.equal(1)
				expect(zoom.ParseCentimetres("5000")).to.equal(100)
				expect(zoom.ParseCentimetres("abc")).to.equal(7)
				expect(zoom.ParseCentimetres("")).to.equal(7)
				expect(zoom.ParseCentimetres(nil)).to.equal(7)
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
			name = "the saved zoom text is read inside 1 to the absolute limit (the view puts it inside its own), a text that is no number gives 1",
			func = function()
				local zoom = Z()

				expect(zoom.ParseSaved("3.5")).to.equal(3.5)
				expect(zoom.ParseSaved("0")).to.equal(1)
				expect(zoom.ParseSaved("99")).to.equal(99)
				expect(zoom.ParseSaved("99999")).to.equal(zoom.ABSOLUTE_MAX)
				expect(zoom.ParseSaved("abc")).to.equal(1)
				expect(zoom.ParseSaved("")).to.equal(1)
				expect(zoom.ParseSaved(nil)).to.equal(1)
			end
		}
	}
}
