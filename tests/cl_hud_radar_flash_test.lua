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
			name = "the stealth level comes from how many NPCs are near (16 fill the bar)",
			func = function(state)
				local R = GryMod.FlashRadar
				expect(R.StealthFromCount(0)).to.equal(0)
				expect(R.StealthFromCount(8)).to.equal(0.5)
				expect(R.StealthFromCount(16)).to.equal(1)
				expect(R.StealthFromCount(100)).to.equal(1)
				expect(R.StealthFromCount(nil)).to.equal(0)
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
			name = "a missing movie gives no panel instead of an error",
			func = function(state)
				expect(GryMod.FlashRadar.New(nil)).to.beNil()
			end
		}
	}
}
