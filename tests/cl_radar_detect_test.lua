-- Tests of the detection the client takes from the server for the danger bar and the hexagon (Radar.Detected, Radar.DetectTargets, the message gry_radar_detect in
-- cl_hud_radar_units.lua), GLuaTest format, client realm. The server sends two numbers 0 to 2 (the soldiers and the machines) for the hostiles that see or hear
-- the player and are not contacts; the feed takes the higher of them and of what the contacts say.

return {
	groupName = "GryMod radar detection (client)",
	cases = {
		-- fails without Radar.DetectTargets
		{
			name = "the numbers 0, 1, 2 are the targets 0, 0.5 and 1 of the bar and the hexagon; a number outside them is held",
			func = function(state)
				local R = GryMod.FlashRadar
				local bar, hex = R.DetectTargets(2, 1)
				expect(bar).to.equal(1)
				expect(hex).to.equal(0.5)
				bar, hex = R.DetectTargets(0, 0)
				expect(bar).to.equal(0)
				expect(hex).to.equal(0)
				bar, hex = R.DetectTargets(9, -3)
				expect(bar).to.equal(1)
				expect(hex).to.equal(0)
				bar, hex = R.DetectTargets(nil, nil)
				expect(bar).to.equal(0)
				expect(hex).to.equal(0)
			end
		},
		-- fails without the receiver
		{
			name = "the message sets what the feed reads, and Radar.ResetDetect puts it to zero",
			func = function(state)
				local R = GryMod.FlashRadar
				local real = {ReadUInt = net.ReadUInt}
				local queue, head = {2, 1, 63}, 0
				net.ReadUInt = function(bits) head = head + 1 return queue[head] end
				local ok, err = pcall(R.ReadDetect)
				net.ReadUInt = real.ReadUInt
				assert(ok, err)
				expect(R.Detected.puppet).to.equal(2)
				expect(R.Detected.vehicle).to.equal(1)
				expect(R.Detected.exposure).to.equal(1)
				R.ResetDetect()
				expect(R.Detected.puppet).to.equal(0)
				expect(R.Detected.vehicle).to.equal(0)
				expect(R.Detected.exposure).to.equal(0)
			end
		},
		-- fails when Feed ignores Detected
		{
			name = "the HUD's feed raises the bar to the soldiers' number and the hexagon to the machines' one although the list of contacts is empty; with the contacts off both are forgotten",
			func = function(state)
				local R = GryMod.FlashRadar
				local panel = GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
				local options = GryMod.HUDOptions
				local realSnapshot, realFind, realEnabled, realZoom, realStealth = R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom, R.Stealth
				local real = {Start = net.Start, WriteBool = net.WriteBool, WriteUInt = net.WriteUInt, SendToServer = net.SendToServer}
				net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = function() end, function() end, function() end, function() end
				local ply = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end, InVehicle = function() return false end}
				local ok, err = pcall(function()
					options.Enabled = function() return true end
					GryMod.RadarZoom = nil
					R.Snapshot, R.FindEntity = {}, function() return nil end
					R.Stealth = 0
					R.Detected.puppet, R.Detected.vehicle = 2, 0
					R.Feed(panel, ply, 1) -- one second: the bar rises by its speed (1 a second)
					expect(R.Stealth).to.aboutEqual(1, 0.01)

					R.Detected.puppet = 0
					R.Stealth = 0

					for _ = 1, 30 do R.Feed(panel, ply, 1 / 30) end

					expect(R.Stealth).to.equal(0)

					options.Enabled = function(name) return name ~= "radarunits" end
					R.Detected.puppet = 2
					R.Stealth = 1

					for _ = 1, 150 do R.Feed(panel, ply, 1 / 30) end

					expect(R.Stealth).to.equal(0)
				end)
				R.Detected.puppet, R.Detected.vehicle = 0, 0
				R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom, R.Stealth = realSnapshot, realFind, realEnabled, realZoom, realStealth
				net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when Feed ignores Detected.exposure
		{
			name = "the bar rises to the exposure the server sends (a bot that is 60 % aware of the player), with no contact and no detected number",
			func = function(state)
				local R = GryMod.FlashRadar
				local panel = GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
				local options = GryMod.HUDOptions
				local realSnapshot, realFind, realEnabled, realZoom, realStealth = R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom, R.Stealth
				local real = {Start = net.Start, WriteBool = net.WriteBool, WriteUInt = net.WriteUInt, SendToServer = net.SendToServer}
				net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = function() end, function() end, function() end, function() end
				local ply = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end, InVehicle = function() return false end}
				local ok, err = pcall(function()
					options.Enabled = function() return true end
					GryMod.RadarZoom = nil
					R.Snapshot, R.FindEntity = {}, function() return nil end
					R.Stealth = 0
					R.Detected.puppet, R.Detected.vehicle, R.Detected.exposure = 0, 0, 0.6

					for _ = 1, 60 do R.Feed(panel, ply, 1 / 30) end

					expect(R.Stealth).to.aboutEqual(0.6, 0.01)
				end)
				R.Detected.puppet, R.Detected.vehicle, R.Detected.exposure = 0, 0, 0
				R.Snapshot, R.FindEntity, options.Enabled, GryMod.RadarZoom, R.Stealth = realSnapshot, realFind, realEnabled, realZoom, realStealth
				net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer

				if not ok then
					error(err, 0)
				end
			end
		},
		-- fails when the server's list of machine types and the hexagon's drift apart
		{
			name = "the types the server counts as machines are the ones the hexagon follows (sh_radar.lua and Hex.VEHICLE_TYPES)",
			func = function(state)
				local mine, theirs = GryMod.RadarShared.VEHICLE_TYPES, GryMod.FlashRadar.Hex.VEHICLE_TYPES

				for kind = 1, 7 do
					expect(mine[kind] == true).to.equal(theirs[kind] == true)
				end
			end
		},
		{
			name = "CombineTargets takes, for the bar and for the hexagon, the higher of what the contacts say and what the server's numbers say",
			func = function(state)
				local R = GryMod.FlashRadar
				local bar, hex = R.CombineTargets(0, 0, 0, 1)
				expect(bar).to.equal(0)
				expect(hex).to.equal(1)
				bar, hex = R.CombineTargets(0.5, 0, 1, 0)
				expect(bar).to.equal(1)
				expect(hex).to.equal(0)
				-- the contacts' and the server's numbers: the higher
				bar, hex = R.CombineTargets(0.5, 0.5, 0.5, 0.5)
				expect(bar).to.equal(0.5)
				expect(hex).to.equal(0.5)
			end
		}
	}
}
