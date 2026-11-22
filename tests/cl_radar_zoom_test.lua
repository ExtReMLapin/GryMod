-- Tests of the radar's automatic zoom on the client (cl_hud_radar_zoom.lua), GLuaTest format, client realm. An option (off by default) that moves the
-- radar's range between three modes: in a vehicle, on foot outside, indoors (under a ceiling AND in a narrow place). The three ranges are the player's
-- sliders, nothing ties one to another; a mode has to hold for a delay (a slider too) before the radar goes there; the change of range is an
-- effect (the range DISPLAYED glides to the TARGET), and the definition of the map and the server's request follow the target at once.

local NAMES = {"gry_radar_autozoom", "gry_radar_zoom_vehicle", "gry_radar_zoom_foot", "gry_radar_zoom_indoor", "gry_radar_zoom_delay", "gry_radar_range"}

local real = {}

local function restoreNet()
	if real.Start then
		net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer
		real.Start = nil
	end
end

local function set(name, value)
	GetConVar(name):SetString(tostring(value))
end

local function close(a, b)
	return math.abs(a - b) < 0.0001
end

return {
	groupName = "GryMod radar automatic zoom (client)",
	beforeEach = function(state)
		state.saved = {}

		for _, name in ipairs(NAMES) do
			local c = GetConVar(name)

			state.saved[name] = c and c:GetString()
		end

		local Z = GryMod.RadarZoom

		if Z then
			set("gry_radar_autozoom", 1)
			set("gry_radar_zoom_vehicle", 100)
			set("gry_radar_zoom_foot", 75)
			set("gry_radar_zoom_indoor", 25)
			set("gry_radar_zoom_delay", 0.7)
			Z.Reset()
		end
	end,
	afterEach = function(state)
		pcall(restoreNet)

		for name, value in pairs(state.saved) do
			local c = GetConVar(name)

			if value and c then
				c:SetString(value)
			end
		end

		if GryMod.RadarZoom then
			GryMod.RadarZoom.Reset()
		end

		if GryMod.FlashRadar and GryMod.FlashRadar.ResetWant then
			GryMod.FlashRadar.ResetWant()
		end
	end,
	cases = {
		{
			name = "the options exist and are saved: automatic zoom off, ranges 100 / 75 / 25 metres from 5 to 100, delay 0.7 s from 0.1 to 5",
			func = function()
				local auto = GetConVar("gry_radar_autozoom")

				expect(auto ~= nil).to.beTrue()
				expect(auto:GetDefault()).to.equal("0")

				for name, default in pairs({gry_radar_zoom_vehicle = "100", gry_radar_zoom_foot = "75", gry_radar_zoom_indoor = "25"}) do
					local c = GetConVar(name)

					expect(c ~= nil).to.beTrue()
					expect(c:GetDefault()).to.equal(default)
					expect(c:GetMin()).to.equal(5)
					expect(c:GetMax()).to.equal(100)
				end

				local delay = GetConVar("gry_radar_zoom_delay")

				expect(delay ~= nil).to.beTrue()
				expect(delay:GetDefault()).to.equal("0.7")
				-- the engine keeps the bounds as 32 bit floats
				expect(math.abs(delay:GetMin() - 0.1) < 0.000001).to.beTrue()
				expect(delay:GetMax()).to.equal(5)
			end
		},
		{
			name = "the module starts on foot, and the first observation sets the mode at once (no delay, no glide)",
			func = function()
				local Z = GryMod.RadarZoom

				expect(Z.Mode()).to.equal("foot")
				Z.Observe(10, true, false)
				expect(Z.Mode()).to.equal("vehicle")
				expect(Z.TargetRange()).to.equal(100)
				expect(close(Z.Displayed(10), 100)).to.beTrue()
			end
		},
		{
			name = "a mode is accepted only after it has held for the delay (0.7 s): 0.69 s is not enough, 0.7 s is",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, false, false)
				expect(Z.Mode()).to.equal("foot")
				Z.Observe(1, true, false)
				expect(Z.Mode()).to.equal("foot")
				Z.Observe(1.69, true, false)
				expect(Z.Mode()).to.equal("foot")
				Z.Observe(1.7, true, false)
				expect(Z.Mode()).to.equal("vehicle")
			end
		},
		{
			name = "a mode that was left before the delay is forgotten: the timer starts again from the next time",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, false, false)
				Z.Observe(1, false, true)
				Z.Observe(1.5, false, false)
				Z.Observe(1.9, false, true)
				expect(Z.Mode()).to.equal("foot")
				Z.Observe(2.6, false, true)
				expect(Z.Mode()).to.equal("indoor")
			end
		},
		{
			name = "the delay is the player's: 0.1 s and 5 s",
			func = function()
				local Z = GryMod.RadarZoom

				set("gry_radar_zoom_delay", 0.1)
				Z.Observe(0, false, false)
				Z.Observe(1, false, true)
				Z.Observe(1.1, false, true)
				expect(Z.Mode()).to.equal("indoor")

				Z.Reset()
				set("gry_radar_zoom_delay", 5)
				Z.Observe(0, false, false)
				Z.Observe(1, false, true)
				Z.Observe(5.9, false, true)
				expect(Z.Mode()).to.equal("foot")
				Z.Observe(6, false, true)
				expect(Z.Mode()).to.equal("indoor")
			end
		},
		{
			name = "the vehicle wins over indoors (a vehicle ignores the ceiling), and leaving it goes back to what the place says",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, true, true)
				expect(Z.Mode()).to.equal("vehicle")
				Z.Observe(1, false, true)
				Z.Observe(1.7, false, true)
				expect(Z.Mode()).to.equal("indoor")
			end
		},
		{
			name = "the three ranges are free: an indoor range bigger than the vehicle's is taken as it is",
			func = function()
				local Z = GryMod.RadarZoom

				set("gry_radar_zoom_vehicle", 10)
				set("gry_radar_zoom_foot", 40)
				set("gry_radar_zoom_indoor", 90)
				Z.Observe(0, false, true)
				expect(Z.TargetRange()).to.equal(90)
				Z.Reset()
				Z.Observe(0, true, false)
				expect(Z.TargetRange()).to.equal(10)
				Z.Reset()
				Z.Observe(0, false, false)
				expect(Z.TargetRange()).to.equal(40)
			end
		},
		{
			name = "the range DISPLAYED glides to the target in 0.8 s, never going back, and holds there",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, false, false)
				Z.Observe(1, false, true)
				Z.Observe(1.7, false, true)
				expect(Z.Mode()).to.equal("indoor")
				expect(close(Z.Displayed(1.7), 75)).to.beTrue()

				local last = 75

				for i = 1, 16 do
					local d = Z.Displayed(1.7 + i * 0.05)

					expect(d <= last + 0.0001).to.beTrue()
					expect(d >= 25 - 0.0001).to.beTrue()
					last = d
				end

				expect(close(Z.Displayed(2.5), 25)).to.beTrue()
				expect(close(Z.Displayed(9), 25)).to.beTrue()
				-- in the middle the glide is between the two (the shape: smooth in the logarithm of the range)
				local mid = Z.Displayed(2.1)

				expect(mid < 75 and mid > 25).to.beTrue()
			end
		},
		{
			name = "a new target in the middle of a glide starts from the range shown: no jump",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, false, false)
				Z.Observe(1, false, true)
				Z.Observe(1.7, false, true)

				local before = Z.Displayed(2.0)

				-- leaving the indoor mode: the foot mode is accepted at 3.0 s, so check the continuity at the moment of the change
				Z.Observe(2.0, false, false)
				Z.Observe(2.7, false, false)
				local at = Z.Displayed(2.7)
				local justBefore = Z.Displayed(2.7 - 0.0001)

				expect(Z.Mode()).to.equal("foot")
				expect(math.abs(at - justBefore) < 0.05).to.beTrue()
				expect(before < 75 and before > 25).to.beTrue()
			end
		},
		{
			name = "moving the slider of the mode in use glides to the new range too (no mode change)",
			func = function()
				local Z = GryMod.RadarZoom

				Z.Observe(0, false, false)
				set("gry_radar_zoom_foot", 40)
				Z.Observe(1, false, false)
				expect(Z.TargetRange()).to.equal(40)
				expect(close(Z.Displayed(1), 75)).to.beTrue()
				expect(close(Z.Displayed(1.8), 40)).to.beTrue()
			end
		},
		{
			name = "Radar.Range and Radar.TargetRange: with the option off both are the manual range (whole metres); on, the range shown and the target of the mode",
			func = function()
				local R = GryMod.FlashRadar
				local Z = GryMod.RadarZoom

				set("gry_radar_autozoom", 0)
				set("gry_radar_range", 40)
				expect(R.Range()).to.equal(40)
				expect(R.TargetRange()).to.equal(40)

				set("gry_radar_autozoom", 1)
				Z.Reset()
				Z.Observe(RealTime(), false, true)
				expect(R.TargetRange()).to.equal(25)
				expect(close(R.Range(), 25)).to.beTrue()
			end
		},
		{
			name = "the narrow place: the median of the eight free distances (capped at 20 m) goes in under 12 m and out over 18 m, and keeps its state between",
			func = function()
				local Z = GryMod.RadarZoom

				expect(Z.NARROW_IN).to.equal(12)
				expect(Z.NARROW_OUT).to.equal(18)
				-- 5 m on four sides, open on the other four (capped at 20): the median is 12.5, between the two thresholds
				local mixed = {5, 5, 5, 5, 90, 90, 90, 90}

				expect(Z.Narrow(mixed, false)).to.beFalse()
				expect(Z.Narrow(mixed, true)).to.beTrue()
				expect(Z.Narrow({5, 6, 7, 8, 9, 10, 11, 12}, false)).to.beTrue()
				expect(Z.Narrow({30, 40, 50, 60, 70, 80, 90, 25}, true)).to.beFalse()
				expect(Z.Narrow({}, true)).to.beFalse()
			end
		},
		{
			name = "indoors is under a ceiling AND narrow",
			func = function()
				local Z = GryMod.RadarZoom

				expect(Z.IsIndoor(true, true)).to.beTrue()
				expect(Z.IsIndoor(true, false)).to.beFalse()
				expect(Z.IsIndoor(false, true)).to.beFalse()
				expect(Z.IsIndoor(false, false)).to.beFalse()
			end
		},
		{
			name = "Update does nothing and probes nothing while the option is off; on, it reads the vehicle and the probe and observes",
			func = function()
				local Z = GryMod.RadarZoom
				local probed = 0
				local realProbe = Z.Probe

				Z.Probe = function() probed = probed + 1 return true end

				local ply = {InVehicle = function() return false end, GetPos = function() return Vector(0, 0, 0) end}
				local ok, err = pcall(function()
					set("gry_radar_autozoom", 0)
					Z.Update(ply, 0)
					expect(probed).to.equal(0)

					set("gry_radar_autozoom", 1)
					Z.Update(ply, 0)
					expect(probed).to.equal(1)
					expect(Z.Mode()).to.equal("indoor")
				end)

				Z.Probe = realProbe

				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if the probe still casts rays (or asks the level) when the zone map of the server knows the place, or if an unknown place does not fall back on the rays
			name = "the zone map decides when it knows the place (true or false: no ray, no level asked); when it says nothing (nil) the probe falls back on the level and the eight rays",
			func = function()
				local Z = GryMod.RadarZoom
				local realZone, realTrace, realFloors = GryMod.ZoneMapClient, util.TraceLine, GryMod.Minimap.Floors
				local rays, levels = 0, 0
				local ply = {GetPos = function() return Vector(100, 200, 0) end}
				local answer

				local ok, err = pcall(function()
					util.TraceLine = function() rays = rays + 1 return {Hit = false} end
					GryMod.Minimap.Floors = {CurrentAt = function() levels = levels + 1 return {open = false} end}
					GryMod.ZoneMapClient = {Indoor = function() return answer end}

					answer = true
					Z.Reset()
					expect(Z.Probe(ply, 5000)).to.beTrue()
					answer = false
					Z.Reset()
					expect(Z.Probe(ply, 6000)).to.beFalse()
					expect(rays).to.equal(0)
					expect(levels).to.equal(0)

					answer = nil
					Z.Reset()
					Z.Probe(ply, 7000)
					expect(levels).to.equal(1)
					expect(rays).to.equal(8)
				end)

				util.TraceLine, GryMod.Minimap.Floors, GryMod.ZoneMapClient = realTrace, realFloors, realZone
				Z.Reset()

				if not ok then error(err, 0) end
			end
		},
		{
			name = "a change of mode tells the server the TARGET range at once (not the one shown, not after the one second timer), and nothing is sent while the mode holds",
			func = function()
				local R = GryMod.FlashRadar
				local Z = GryMod.RadarZoom
				local sent = {}
				real.Start, real.WriteBool, real.WriteUInt, real.SendToServer = net.Start, net.WriteBool, net.WriteUInt, net.SendToServer

				local ok, err = pcall(function()
					net.Start = function(name) sent[#sent + 1] = {name = name} return true end
					net.WriteBool = function(v) sent[#sent].want = v end
					net.WriteUInt = function(v, bits) sent[#sent].range, sent[#sent].bits = v, bits end
					net.SendToServer = function() end

					R.ResetWant()
					Z.Observe(0, false, false)
					R.TellServer(true)
					expect(#sent).to.equal(1)
					expect(sent[1].range).to.equal(75)

					Z.Observe(1, false, true)
					expect(#sent).to.equal(1)
					Z.Observe(1.7, false, true)
					expect(#sent).to.equal(2)
					expect(sent[2].range).to.equal(25)
					expect(sent[2].bits).to.equal(8)
					Z.Observe(1.8, false, true)
					Z.Observe(2.5, false, true)
					expect(#sent).to.equal(2)
				end)

				pcall(restoreNet)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the options panel has the Automatic zoom section: a check box, three range sliders from 5 to 100 and the delay slider from 0.1 to 5",
			func = function()
				local found = {}
				local box = false
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DNumSlider" and child.Scratch and child.Scratch.m_strConVar then
								found[child.Scratch.m_strConVar] = {min = child:GetMin(), max = child:GetMax()}
							elseif child.ClassName == "DCheckBoxLabel" and child.Button and child.Button:GetTable().m_strConVar == "gry_radar_autozoom" then
								box = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then error(err, 0) end

				expect(box).to.beTrue()

				for _, name in ipairs({"gry_radar_zoom_vehicle", "gry_radar_zoom_foot", "gry_radar_zoom_indoor"}) do
					expect(found[name] ~= nil).to.beTrue()
					expect(found[name].min).to.equal(5)
					expect(found[name].max).to.equal(100)
				end

				expect(found.gry_radar_zoom_delay ~= nil).to.beTrue()
				expect(math.abs(found.gry_radar_zoom_delay.min - 0.1) < 0.000001).to.beTrue()
				expect(found.gry_radar_zoom_delay.max).to.equal(5)
			end
		}
	}
}
