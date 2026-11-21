-- Tests of the compass and radar panel driven by the original Flash movie (GryMod.FlashRadar), GLuaTest
-- format, client realm. Needs the converted movie lua/grymod/flash/hud_radarcompassstealth.lua.

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

-- the text of every field in a clip, in any order
local function texts(clip)
	local found = {}

	local function walk(c)
		for _, entry in pairs(c.list) do
			if entry.kind == "text" then
				found[#found + 1] = entry.text
			elseif entry.clip then
				walk(entry.clip)
			end
		end
	end

	walk(clip)

	return found
end

return {
	groupName = "GryMod compass and radar (Flash)",
	cases = {
		{
			name = "the panel starts on its steady frames, with the helper clips hidden",
			func = function(state)
				local panel = newPanel()
				expect(panel.main:CurrentLabel()).to.equal("on")
				expect(panel.strip:CurrentLabel()).to.equal("normal")
				expect(panel.root:Child("Line").visible).to.beFalse()
				expect(panel.root:Child("Over").visible).to.beFalse()
				expect(panel.root:Child("Text").visible).to.beFalse()
				expect(panel.main:Child("Noise").visible).to.beFalse()
			end
		},
		{
			name = "the compass letters are the names, not the @ui_ keys",
			func = function(state)
				local panel = newPanel()
				local found = texts(panel.strip)
				expect(#found).to.beGreaterThan(20)
				local names = {}

				for _, text in ipairs(found) do
					expect(text:sub(1, 4)).toNot.equal("@ui_")
					names[text] = true
				end

				for _, name in ipairs({"N", "NE", "E", "SE", "S", "SW", "W", "NW"}) do
					expect(names[name]).to.beTrue()
				end
			end
		},
		{
			name = "the strip moves one pixel per degree and wraps every turn",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.StripX(0)).to.equal(0)
				expect(R.StripX(90)).to.aboutEqual(-90, 0.1)
				expect(R.StripX(360)).to.aboutEqual(R.StripX(0), 0.0001)
				expect(R.StripX(-90)).to.aboutEqual(R.StripX(270), 0.0001)
				local panel = newPanel()
				panel:SetHeading(45)
				expect(panel.strip.entry.m[5]).to.aboutEqual(R.StripX(45), 0.0001)
			end
		},
		{
			name = "GryMod's yaw gives a clockwise bearing with north at its map's north",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.BearingFromYaw(R.NORTH_YAW)).to.aboutEqual(0, 0.0001)
				expect(R.BearingFromYaw(R.NORTH_YAW - 90)).to.aboutEqual(90, 0.0001) -- turning right
				expect(R.BearingFromYaw(R.NORTH_YAW + 90)).to.aboutEqual(270, 0.0001)
				expect(R.BearingFromYaw(R.NORTH_YAW + 360)).to.aboutEqual(0, 0.0001)
			end
		},
		{
			name = "nil and NaN headings do not break the strip",
			func = function(state)
				local panel = newPanel()
				panel:SetHeading(nil)
				panel:SetHeading(0 / 0)
				expect(panel.strip.entry.m[5]).to.equal(0)
			end
		},
		{
			name = "the view cone frame follows the field of view, clamped to the movie's 100 frames",
			func = function(state)
				local panel = newPanel()
				local cone = panel.view:Find("View2.Pov")
				panel:SetFOV(75)
				expect(cone:CurrentFrame()).to.equal(75)
				panel:SetFOV(500)
				expect(cone:CurrentFrame()).to.equal(100)
				panel:SetFOV(0)
				expect(cone:CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "the view cone frame is half the vertical field of view of a 4:3 screen, in degrees",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.FovFrame).toNot.beNil()
				expect(R.FovFrame(75)).to.equal(30)
				expect(R.FovFrame(90)).to.equal(37)
				expect(R.FovFrame(20)).to.equal(8)
				expect(R.FovFrame(75) < R.FovFrame(90)).to.beTrue()
				expect(R.FovFrame(20) < R.FovFrame(75)).to.beTrue()
				expect(R.FovFrame(179) <= 100).to.beTrue()
				expect(R.FovFrame(0)).to.equal(1)
				expect(R.FovFrame(nil)).to.equal(1)
				expect(R.FovFrame(0 / 0)).to.equal(1)
			end
		},
		{
			name = "the stealth bar goes from the first to the last of its 101 frames",
			func = function(state)
				local panel = newPanel()
				local bar = panel.view:Child("StealthBar")
				panel:SetStealth(0)
				expect(bar:CurrentFrame()).to.equal(1)
				panel:SetStealth(1)
				expect(bar:CurrentFrame()).to.equal(101)
				panel:SetStealth(0.5)
				expect(bar:CurrentFrame()).to.equal(51)
				panel:SetStealth(3)
				expect(bar:CurrentFrame()).to.equal(101)
				panel:SetStealth(0 / 0)
				expect(bar:CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "the sector name is written in its field",
			func = function(state)
				local panel = newPanel()
				panel:SetSector("gm_construct")
				expect(panel.zone:Child("Zone").text).to.equal("gm_construct")
			end
		},
		{
			name = "a rebuilt strip gets its letters again after an update",
			func = function(state)
				local panel = newPanel()
				panel.main:GotoAndStop("normal") -- the clips are rebuilt
				panel:Update(0)
				for _, text in ipairs(texts(panel.strip)) do
					expect(text:sub(1, 4)).toNot.equal("@ui_")
				end
			end
		},
		{
			name = "a malfunction plays the original animation, shows the noise over dimmed units and stays red",
			func = function(state)
				local panel = newPanel()
				panel:Destroy(1)
				expect(panel.main:CurrentLabel()).to.equal("malfunction")

				for _ = 1, 90 do panel:Update(1 / 30) end

				expect(panel.main:CurrentLabel()).to.equal("malfunctionOn")
				expect(panel.main.playing).to.beFalse()
				local noise = panel.main:Child("Noise")
				expect(noise.visible).to.beTrue()
				expect(math.abs(noise.entry.cx[4] - 0.3) < 0.001).to.beTrue() -- 0.6 * 50 %
				expect(math.abs(panel.main:Child("Units").entry.cx[4] - 0.4) < 0.001).to.beTrue() -- (1 - 0.6) * 100 %
				-- the values are still written while it is down
				panel:SetStealth(0.5)
				expect(panel.view:Child("StealthBar"):CurrentFrame()).to.equal(51)
			end
		},
		{
			name = "a reboot goes back to the steady frames with the noise off and the units at full strength",
			func = function(state)
				local panel = newPanel()
				panel:Destroy(1)

				for _ = 1, 60 do panel:Update(1 / 30) end

				panel:Destroy(0)
				-- "to_normal" is one frame whose script sends the movie back to its start, which then plays on to "on"
				expect(panel.main.playing).to.beTrue()
				expect(panel.main:CurrentLabel() ~= "malfunctionOn").to.beTrue()

				for _ = 1, 90 do panel:Update(1 / 30) end

				expect(panel.main:CurrentLabel()).to.equal("on")
				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(math.abs(panel.main:Child("Units").entry.cx[4] - 1) < 0.001).to.beTrue()
			end
		},
		{
			name = "a missing movie gives no panel instead of an error",
			func = function(state)
				expect(GryMod.FlashRadar.New(nil)).to.beNil()
			end
		}
	}
}
