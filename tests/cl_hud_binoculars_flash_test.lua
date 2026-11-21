-- Tests of the binoculars drawn from the original Scaleform movie (GryMod.FlashBinoculars), GLuaTest format,
-- client realm. Needs the converted movie lua/grymod/flash/hud_binoculars.lua.

local function newBinoculars()
	return GryMod.FlashBinoculars.New(GryMod.Flash.Load("hud_binoculars"))
end

local function run(b, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		b:Update(1 / 30)
	end
end

-- the text of the field called `name` held directly by `clip`
local function field(clip, name)
	local entry = clip.names[name]

	return entry and entry.text
end

return {
	groupName = "GryMod binoculars (Flash)",
	cases = {
		{
			name = "the binoculars are hidden until shown, and the colour holders never show",
			func = function(state)
				local b = newBinoculars()
				expect(b:IsShown()).to.beFalse()
				b:Show()
				expect(b:IsShown()).to.beTrue()

				for _, name in ipairs({"Line", "Over", "Text"}) do
					expect(b.root:Child(name).visible).to.beFalse()
				end
			end
		},
		{
			name = "the target lock icons (brackets drawn at the corner of the stage when nothing is locked) stay hidden, during the intro and after",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				local seen = 0

				for _, seconds in ipairs({0, 0.1, 1.5}) do
					run(b, seconds)

					for _, entry in ipairs(b.bino:Entries()) do
						if entry.clip and ((entry.name and string.find(entry.name, "^TargetIcon")) or entry.id == 51) then
							seen = seen + 1
							expect(entry.clip.visible).to.beFalse()
						end
					end
				end

				expect(seen > 0).to.beTrue()
			end
		},
		{
			name = "showing plays the intro to its resting frame",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				expect(b.bino:CurrentFrame()).to.equal(25)
				expect(b.bino.playing).to.beFalse()
			end
		},
		{
			name = "the zoom reads X0 and twice the mode",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetZoomMode(2)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X04")
				b:SetZoomMode(0)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X00")
			end
		},
		{
			name = "the position strings are written in the two degree fields",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetPosition("045° 12.34 N", "010° 05.00 W")
				expect(field(b.bino:Find("DegreeN.Colorset"), "DegreeN")).to.equal("045° 12.34 N")
				expect(field(b.bino:Find("DegreeW.Colorset"), "DegreeW")).to.equal("010° 05.00 W")
			end
		},
		{
			name = "the distance shows its digits, the dim zeros for the missing hundreds, the dot and the M",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetDistance(34, 56)
				local d = b.bino:Find("TargetDistance.Colorset")
				-- 034: the hundreds are a dim zero (frame 2), the others are plain digits (frame 1)
				expect(d:Child("ObjNumber0"):CurrentFrame()).to.equal(2)
				expect(field(d:Child("ObjNumber0"):Child("Low"), "ObjNumber0")).to.equal("0")
				expect(d:Child("ObjNumber1"):CurrentFrame()).to.equal(1)
				expect(field(d:Child("ObjNumber1"), "ObjNumber1")).to.equal("3")
				expect(field(d:Child("ObjNumber2"), "ObjNumber2")).to.equal("4")
				expect(field(d, "ObjNumber4")).to.equal("5")
				expect(field(d, "ObjNumber5")).to.equal("6")
				expect(field(d, "Dot")).to.equal(".")
				expect(field(d, "MTEXT")).to.equal("M")
				expect(d:Child("Icon").visible).to.beFalse()
			end
		},
		{
			name = "no distance (nothing aimed at) blanks the digits and shows the icon",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetDistance(34, 56)
				b:SetDistance(0, 0)
				local d = b.bino:Find("TargetDistance.Colorset")
				expect(field(d, "ObjNumber4")).to.equal("")
				expect(field(d, "ObjNumber5")).to.equal("")
				expect(field(d, "Dot")).to.equal("")
				expect(field(d, "MTEXT")).to.equal("")
				expect(d:Child("Icon").visible).to.beTrue()
			end
		},
		{
			name = "the values stay while the intro still rebuilds the clips",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				b:SetZoomMode(3)
				b:SetPosition("001° 00.00 N", "002° 00.00 W")
				run(b, 1.5)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X06")
				expect(field(b.bino:Find("DegreeN.Colorset"), "DegreeN")).to.equal("001° 00.00 N")
			end
		},
		{
			name = "closing plays the original close animation and hides the binoculars at its end",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:Close()
				expect(b.bino:CurrentLabel()).to.equal("close")
				run(b, 2)
				expect(b:IsShown()).to.beFalse()
				b:Show()
				expect(b:IsShown()).to.beTrue()
			end
		},
		{
			name = "the zoom factor of a field of view gives the mode: 1 under 4x, 2 under 6x, 3 under 8x, 4 above",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.ZoomModeFor(90, 90)).to.equal(1)
				expect(M.ZoomModeFor(90, 45)).to.equal(1) -- about 2.4x
				expect(M.ZoomModeFor(90, 22)).to.equal(2) -- about 5x
				expect(M.ZoomModeFor(90, 16)).to.equal(3) -- about 7x
				expect(M.ZoomModeFor(90, 14)).to.equal(4) -- about 8x
				expect(M.ZoomModeFor(90, 5)).to.equal(4)
				expect(M.ZoomModeFor(nil, 20)).to.equal(1)
				expect(M.ZoomModeFor(90, 0 / 0)).to.equal(1)
			end
		},
		{
			name = "a distance in world units gives the metres and hundredths the movie wants, and nothing when nothing is hit",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local int, frac = M.MetresFrom(52.49 * 34.56)
				expect(int).to.equal(34)
				expect(frac).to.equal(56)
				int, frac = M.MetresFrom(0)
				expect(int).to.equal(0)
				expect(frac).to.equal(0)
				int, frac = M.MetresFrom(nil)
				expect(int).to.equal(0)
				expect(frac).to.equal(0)
				int, frac = M.MetresFrom(52.49 * 5000) -- past the three digits of the display
				expect(int).to.equal(999)
				expect(frac).to.equal(99)
			end
		},
		{
			name = "the position strings: degrees and minutes of the world position, hemisphere letters from the sign",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local n, w = M.PositionStrings(Vector(-52.49 * 70, 52.49 * 125.5, 0))
				expect(n).to.equal("002° 05.50 N")
				expect(w).to.equal("001° 10.00 W")
				n, w = M.PositionStrings(Vector(52.49 * 10, -52.49 * 10, 0))
				expect(n).to.equal("000° 10.00 S")
				expect(w).to.equal("000° 10.00 E")
			end
		},
		{
			name = "a missing movie gives no binoculars instead of an error",
			func = function(state)
				expect(GryMod.FlashBinoculars.New(nil)).to.equal(nil)
			end
		}
	}
}
