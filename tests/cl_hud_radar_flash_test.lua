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

-- the alpha multiplier (0..1) of a clip's colour transform, 1 when it has none
local function alphaOf(clip)
	local cx = clip.entry and clip.entry.cx

	return cx and cx[4] or 1
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
		},
		-- SetNoise: the port of the movie's setNoiseValue(v) (the minimap's progress veil uses it). Each case names the change that breaks it.
		{
			name = "SetNoise(v) shows the noise clip looping at alpha v * 50 % and dims the units to (1 - v) * 100 % (no SetNoise)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.4)
				local noise = panel.main:Child("Noise")
				expect(noise.visible).to.beTrue()
				expect(noise.playing).to.beTrue()
				expect(noise:CurrentLabel()).to.equal("loop")
				expect(alphaOf(noise)).to.aboutEqual(0.2, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(0.6, 0.001)
				expect(panel.noise).to.aboutEqual(0.4, 0.0001)
			end
		},
		{
			name = "SetNoise(v, true) leaves the units at 100 % (the keepUnits argument is ignored)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.6, true)
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(alphaOf(panel.main:Child("Noise"))).to.aboutEqual(0.3, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
			end
		},
		{
			name = "SetNoise(0) hides the noise, stops its loop and puts the units back to 100 % (v = 0 does not restore)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.8)
				panel:SetNoise(0)
				local noise = panel.main:Child("Noise")
				expect(noise.visible).to.beFalse()
				expect(noise.playing).to.beFalse()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
				expect(panel.noise).to.equal(0)
			end
		},
		{
			name = "SetNoise clamps v to 0..1 and reads nil and NaN as 0 (no clamp)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(3)
				expect(panel.noise).to.equal(1)
				expect(alphaOf(panel.main:Child("Noise"))).to.aboutEqual(0.5, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(0, 0.001)
				panel:SetNoise(-2)
				expect(panel.noise).to.equal(0)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				panel:SetNoise(0.5)
				panel:SetNoise(0 / 0)
				expect(panel.noise).to.equal(0)
				expect(panel.main:Child("Noise").visible).to.beFalse()
				panel:SetNoise(0.5)
				panel:SetNoise(nil)
				expect(panel.noise).to.equal(0)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
			end
		},
		{
			name = "the noise survives a change of frame of the movie, _resolve applies it again (_resolve resets the noise to the malfunction's)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.4)
				panel.main:GotoAndStop("normal") -- the clips are rebuilt
				panel:Update(0)
				local noise = panel.main:Child("Noise")
				expect(noise.visible).to.beTrue()
				expect(alphaOf(noise)).to.aboutEqual(0.2, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(0.6, 0.001)
				expect(noise.playing).to.beTrue()
			end
		},
		{
			name = "the keepUnits choice survives a change of frame too",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.6, true)
				panel.main:GotoAndStop("normal")
				panel:Update(0)
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
			end
		},
		{
			name = "a malfunction and SetNoise give the stronger of the two noises (_resolve takes the malfunction's alone)",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.2)
				panel:Destroy(1)
				local noise, units = panel.main:Child("Noise"), panel.main:Child("Units")
				expect(noise.visible).to.beTrue()
				expect(alphaOf(noise)).to.aboutEqual(0.3, 0.001) -- the malfunction's fixed 0.6 is stronger than 0.2
				expect(alphaOf(units)).to.aboutEqual(0.4, 0.001)

				panel:SetNoise(0.9)
				expect(alphaOf(noise)).to.aboutEqual(0.45, 0.001)
				expect(alphaOf(units)).to.aboutEqual(0.1, 0.001)

				panel:SetNoise(0.1)
				expect(alphaOf(noise)).to.aboutEqual(0.3, 0.001)
				expect(alphaOf(units)).to.aboutEqual(0.4, 0.001)
			end
		},
		{
			name = "with keepUnits a malfunction still dims the units, and the end of the malfunction leaves SetNoise's noise",
			func = function(state)
				local panel = newPanel()
				panel:SetNoise(0.5, true)
				panel:Destroy(1)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(0.4, 0.001)
				panel:Destroy(0)

				for _ = 1, 90 do panel:Update(1 / 30) end

				expect(panel.main:CurrentLabel()).to.equal("on")
				expect(panel.main:Child("Noise").visible).to.beTrue()
				expect(alphaOf(panel.main:Child("Noise"))).to.aboutEqual(0.25, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
			end
		},
		{
			name = "Destroy(1) keeps its fixed 0.6 when SetNoise was never used, and Destroy(0) with no SetNoise hides the noise",
			func = function(state)
				local panel = newPanel()
				panel:Destroy(1)
				expect(panel.noise or 0).to.equal(0)
				expect(alphaOf(panel.main:Child("Noise"))).to.aboutEqual(0.3, 0.001)
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(0.4, 0.001)
				expect(panel.main:Child("Noise").playing).to.beTrue()

				panel:Destroy(0)

				for _ = 1, 90 do panel:Update(1 / 30) end

				expect(panel.main:Child("Noise").visible).to.beFalse()
				expect(alphaOf(panel.main:Child("Units"))).to.aboutEqual(1, 0.001)
			end
		},
		-- the text of the zone field: the progress text wins over the sector name, neither erases the other
		{
			name = "the progress text shows in the Zone field instead of the sector, and the sector comes back when it goes (no progressText)",
			func = function(state)
				local panel = newPanel()
				panel:SetSector("gm_construct")
				panel:SetProgressText("40%")
				expect(panel.progressText).to.equal("40%")
				expect(panel.zone:Child("Zone").text).to.equal("40%")
				expect(panel.sector).to.equal("gm_construct")
				panel:SetProgressText(nil)
				expect(panel.progressText).to.beNil()
				expect(panel.zone:Child("Zone").text).to.equal("gm_construct")
			end
		},
		{
			name = "SetSector does not erase the progress text (SetSector writes the field unconditionally)",
			func = function(state)
				local panel = newPanel()
				panel:SetProgressText("7%")
				panel:SetSector("gm_bigcity")
				expect(panel.zone:Child("Zone").text).to.equal("7%")
				expect(panel.sector).to.equal("gm_bigcity")
				panel:SetProgressText(nil)
				expect(panel.zone:Child("Zone").text).to.equal("gm_bigcity")
			end
		},
		{
			name = "the progress text alone leaves the field empty when it goes and there is no sector",
			func = function(state)
				local panel = newPanel()
				panel:SetProgressText("50%")
				expect(panel.zone:Child("Zone").text).to.equal("50%")
				panel:SetProgressText(nil)
				expect(panel.zone:Child("Zone").text).to.equal("")
			end
		},
		{
			name = "_refresh writes the progress text again after the movie rebuilt the field, else the sector (_refresh only knows the sector)",
			func = function(state)
				local panel = newPanel()
				panel:SetSector("gm_construct")
				panel:SetProgressText("12%")
				panel.zone:SetText("Zone", "rebuilt") -- what a rebuilt clip would show
				panel:_refresh()
				expect(panel.zone:Child("Zone").text).to.equal("12%")
				panel:SetProgressText(nil)
				panel.zone:SetText("Zone", "rebuilt")
				panel:_refresh()
				expect(panel.zone:Child("Zone").text).to.equal("gm_construct")
			end
		}
	}
}
