-- Tests of the crosshair drawn from the original Scaleform movie (GryMod.FlashCrosshair), GLuaTest format, client
-- realm. Needs the converted movie lua/grymod/flash/hud_crosshair.lua. The rules are those of the movie's
-- ActionScript (setCrossHair, setRecoil, setUsable, indicateHit, setDamageDirection), see research-ui/NOTES.md.

local function newCrosshair()
	return GryMod.FlashCrosshair.New(GryMod.Flash.Load("hud_crosshair"))
end

local function run(c, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		c:Update(1 / 30)
	end
end

local function near(a, b)
	return math.abs(a - b) < 0.001
end

-- the x or y of the placement of the clip at this path of the current crosshair
local function posOf(c, path)
	local clip = c.current:Find(path)

	return clip.entry.m[5], clip.entry.m[6]
end

local function scaleOf(c, path)
	local clip = c.current:Find(path)
	local m = clip.entry.m

	return math.sqrt(m[1] * m[1] + m[2] * m[2]) * 100
end

return {
	groupName = "GryMod crosshair (Flash)",
	cases = {
		{
			name = "a missing movie gives no crosshair instead of an error",
			func = function(state)
				expect(GryMod.FlashCrosshair.New(nil)).to.equal(nil)
			end
		},
		{
			name = "the crosshair starts on the original's default, number 10",
			func = function(state)
				local c = newCrosshair()
				expect(c.index).to.equal(10)
				expect(c.current).to.exist()
				expect(c.current:Find("Line")).to.exist()
				expect(c.current:Find("Line2")).to.exist()
			end
		},
		{
			name = "choosing a number shows that crosshair, 0 shows none, an unknown number changes nothing",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				expect(c.index).to.equal(1)
				expect(c.current:Find("LineL")).to.exist()
				c:SetCrosshair(4)
				expect(c.current:Find("LineU")).to.exist()
				c:SetCrosshair(0)
				expect(c.index).to.equal(0)
				expect(c.current).to.beNil()
				expect(c.root:Child("Root"):CurrentLabel()).to.equal("empty")
				c:SetCrosshair(99)
				expect(c.index).to.equal(0)
				c:SetCrosshair(nil)
				expect(c.index).to.equal(0)
				c:SetCrosshair(3)
				expect(c.index).to.equal(3)
			end
		},
		{
			name = "the recoil spreads the four lines of crosshair 1: 9.5 plus 42 a unit",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetRecoil(0)
				expect(near(posOf(c, "LineL"), -9.5)).to.beTrue()
				expect(near(posOf(c, "LineR"), 9.5)).to.beTrue()
				local _, y = posOf(c, "LineD")
				expect(near(y, 9.5)).to.beTrue()
				c:SetRecoil(0.5)
				expect(near(posOf(c, "LineL"), -(9.5 + 21))).to.beTrue()
				expect(near(posOf(c, "LineR"), 9.5 + 21)).to.beTrue()
			end
		},
		{
			name = "the recoil of the other crosshairs follows each one's own formula",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(2)
				c:SetRecoil(0.5)
				expect(near(scaleOf(c, "Line"), 200)).to.beTrue()
				c:SetCrosshair(3)
				c:SetRecoil(0.5)
				local x, y = posOf(c, "LineTR")
				expect(near(x, 11 + 21)).to.beTrue()
				expect(near(y, -11 - 21)).to.beTrue()
				c:SetCrosshair(4)
				c:SetRecoil(0.5)
				local _, up = posOf(c, "LineU")
				expect(near(up, -(8 + 26))).to.beTrue()
				c:SetCrosshair(5)
				c:SetRecoil(0.5)
				expect(near(scaleOf(c, "Line2"), 50 + 2.5 * (20 + 16))).to.beTrue()
				c:SetCrosshair(6)
				c:SetRecoil(0.5)
				local bx, by = posOf(c, "LineBL")
				expect(near(bx, -(10 + 24))).to.beTrue()
				expect(near(by, 10 + 24)).to.beTrue()
				c:SetCrosshair(7)
				c:SetRecoil(0.5)
				expect(near(posOf(c, "LineR"), 9.5 + 28)).to.beTrue()
			end
		},
		{
			name = "crosshairs 11, 12 and 13 take their spread in pixels, never under their own minimum",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(11)
				c:SetRecoil(30)
				local x, y = posOf(c, "Lines.Colorset.Line1")
				expect(near(x, -30)).to.beTrue()
				expect(near(y, -25)).to.beTrue()
				c:SetRecoil(3)
				x = posOf(c, "Lines.Colorset.Line2")
				expect(near(x, 22)).to.beTrue()
				c:SetCrosshair(12)
				c:SetRecoil(1)
				local _, top = posOf(c, "Lines.Colorset.LineTop")
				expect(near(top, -10)).to.beTrue()
				c:SetCrosshair(13)
				c:SetRecoil(40)
				expect(near(posOf(c, "Lines.Colorset.Line2"), 40)).to.beTrue()
			end
		},
		{
			name = "the recoil is applied again when the crosshair rebuilds its clips, and after a change of number",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetRecoil(0.5)
				c:SetUsable(1)
				run(c, 1)
				expect(near(posOf(c, "LineR"), 9.5 + 21)).to.beTrue()
				c:SetCrosshair(4)
				expect(near(select(1, posOf(c, "LineR")), 8 + 26)).to.beTrue()
			end
		},
		{
			name = "a hit plays the hit animation of the lines of the shown crosshair",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:Hit()
				expect(c.current:Find("LineL"):CurrentLabel()).to.equal("hit")
				expect(c.current:Find("Pointer"):CurrentLabel()).to.equal("hit")
				c:SetCrosshair(11)
				c:Hit()
				expect(c.current:Find("Lines.Colorset.Line3"):CurrentLabel()).to.equal("hit")
				c:SetCrosshair(0)
				c:Hit() -- nothing shown: no error
			end
		},
		{
			name = "usable: 1 opens the crosshair on frame 2, 0 closes it by the way back, 2 plays the second animation",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetUsable(1)
				expect(c.current:CurrentFrame()).to.equal(2)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(12)
				c:SetCrosshair(3)
				expect(c.current:CurrentFrame()).to.equal(1)
				c:SetUsable(2)
				expect(c.current:CurrentFrame()).to.equal(14)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(20)
			end
		},
		{
			name = "usable keeps the same mode as it was, in the middle of an animation, the original's way",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetUsable(1)
				c.current:GotoAndStop(4)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(10)
				c.current:GotoAndStop(7)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(8)
			end
		},
		{
			name = "the damage arcs: each plays from its own start and a clear stops all four",
			func = function(state)
				local c = newCrosshair()
				local dd = c.root:Child("DamageDirection")
				c:SetDamageDirection(2)
				expect(dd:Child("Damage2"):CurrentLabel()).to.equal("play")
				expect(dd:Child("Damage1"):CurrentLabel()).to.equal("stop")
				c:SetDamageDirection(4)
				expect(dd:Child("Damage4"):CurrentLabel()).to.equal("play")
				c:ClearDamageDirection()

				for i = 1, 4 do
					expect(dd:Child("Damage" .. i):CurrentLabel()).to.equal("stop")
				end

				c:SetDamageDirection(7) -- not an arc: nothing happens, no error
			end
		},
		{
			name = "an arc plays for 1.2 seconds and goes back to rest on its own",
			func = function(state)
				local c = newCrosshair()
				c:SetDamageDirection(1)
				run(c, 0.5)
				expect(c.root:Child("DamageDirection"):Child("Damage1"):CurrentLabel()).to.equal(nil)
				run(c, 1.5)
				expect(c.root:Child("DamageDirection"):Child("Damage1"):CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "the visibility and the opacity of the whole crosshair",
			func = function(state)
				local c = newCrosshair()
				c:SetVisible(false)
				expect(c:IsShown()).to.beFalse()
				c:SetVisible(true)
				expect(c:IsShown()).to.beTrue()
				c:SetOpacity(0.5)
				expect(near(c.root:Child("Root").entry.cx[4], 0.5)).to.beTrue()
			end
		}
	}
}
