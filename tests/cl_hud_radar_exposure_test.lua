-- Tests of the radar's alert hexagon (cl_hud_radar_exposure.lua), GLuaTest format, client realm. The hexagon of the original radar shows the detection
-- level of the VEHICLES and machines (the AI's "vehicle" pair of numbers) while the danger bar shows the soldiers and aliens (the "puppet" pair); its
-- picture is the movie HUD_SP_HexIcons, driven by one number from 0 to 100. The numbers and where they come from are in
-- docs/superpowers/plans/2026-11-22-radar-exposure-ai-research.md and 2026-11-22-radar-alert-hexagon-research.md. Needs the converted movies
-- lua/grymod/flash/hud_radarcompassstealth.lua and hud_sp_hexicons.lua.

local function newPanel()
	return GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
end

local U = 0.01905 -- metres per Source unit

local function metres(m)
	return m / U
end

-- a contact 10 m ahead of a player at the origin; type 1 ground, 2 flying, 3 machine, 4 mine; sub 3 alerted, 4 fighting
local function contact(kind, sub, extra)
	local c = {id = 1, x = metres(10), y = 0, z = 0, yaw = 0, type = kind, sub = sub}

	for k, v in pairs(extra or {}) do
		c[k] = v
	end

	return c
end

-- the stealth model after `seconds` of a constant target, in steps of 1/30 s
local function run(state, target, seconds)
	local value

	for _ = 1, math.floor(seconds * 30 + 0.5) do
		value = GryMod.FlashRadar.Hex.Step(state, target, 1 / 30)
	end

	return value
end

local function hexFrame(panel)
	return panel.hex.clip:Child("Icons"):Child("StealthExposure"):CurrentFrame()
end

-- the player the feed looks at: the real one when there is one (the automatic zoom, if the player has it on, asks it things a fake one cannot answer: that
-- would be an error printed at every test), else a stand-in. Where the contacts are does not matter here: only their kind and their state do.
local standIn = {GetPos = function() return Vector(0, 0, 0) end, EyeAngles = function() return Angle(0, 0, 0) end, InVehicle = function() return true end}

local function feedPly()
	local ply = LocalPlayer()

	return IsValid(ply) and ply or standIn
end

-- Runs fn with the radar's feed set up the way the feed tests do: no net message sent, no entity found, the options as given. Everything put back after.
local function withFeed(options, fn)
	local R = GryMod.FlashRadar
	local O = GryMod.HUDOptions
	local realSnapshot, realFind, realEnabled, realStealth = R.Snapshot, R.FindEntity, O.Enabled, R.Stealth
	local real = {Start = net.Start, WriteBool = net.WriteBool, WriteUInt = net.WriteUInt, SendToServer = net.SendToServer}
	net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = function() end, function() end, function() end, function() end
	R.FindEntity = function() return nil end
	O.Enabled = function(name)
		if options[name] ~= nil then
			return options[name]
		end

		return true
	end

	local ok, err = pcall(fn)

	R.Snapshot, R.FindEntity, O.Enabled, R.Stealth = realSnapshot, realFind, realEnabled, realStealth
	net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer
	R.Hex.Reset()

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod radar alert hexagon",
	cases = {
		{
			name = "the movie of the icons is converted: one clip of 101 frames for the exposure, 15 frames for the pulse",
			func = function(state)
				local movie = GryMod.Flash.Load("hud_sp_hexicons")
				expect(movie).toNot.beNil()
				expect(movie.chars[6].n).to.equal(101)
				expect(movie.chars[5].n).to.equal(15)
			end
		},
		{
			name = "the danger bar follows the soldiers and the hexagon the vehicles and machines: icon types 2 (flying) and 3 (machines) go to the hexagon, the others to the bar",
			func = function(state)
				local R = GryMod.FlashRadar
				local bar, hex = R.SplitTargets({contact(1, 4)})
				expect(bar).to.equal(1)
				expect(hex).to.equal(0)

				bar, hex = R.SplitTargets({contact(3, 4)})
				expect(bar).to.equal(0)
				expect(hex).to.equal(1)

				bar, hex = R.SplitTargets({contact(2, 3)})
				expect(bar).to.equal(0)
				expect(hex).to.equal(0.5)

				-- a Combine mine is a device, not a vehicle: it stays with the bar
				bar, hex = R.SplitTargets({contact(4, 4)})
				expect(bar).to.equal(1)
				expect(hex).to.equal(0)

				-- each has its own highest, a crowd does not add up
				bar, hex = R.SplitTargets({contact(1, 3), contact(1, 3), contact(3, 4), contact(2, 3), contact(1, 0)})
				expect(bar).to.equal(0.5)
				expect(hex).to.equal(1)
			end
		},
		{
			name = "the split counts what the bar counted: markers, calm hostiles, friends and nothing",
			func = function(state)
				local R = GryMod.FlashRadar
				local S = GryMod.RadarShared
				local bar, hex = R.SplitTargets(nil)
				expect(bar).to.equal(0)
				expect(hex).to.equal(0)
				bar, hex = R.SplitTargets({})
				expect(bar + hex).to.equal(0)
				-- a vehicle that shot the player (its marker) is aware of him, a calm one is not, a friend never
				bar, hex = R.SplitTargets({contact(3, 2, {marker = true})})
				expect(hex).to.equal(1)
				bar, hex = R.SplitTargets({contact(3, 2)})
				expect(hex).to.equal(0)
				bar, hex = R.SplitTargets({contact(3, S.SUB_ALLY), contact(3, S.SUB_ALLY, {marker = true}), contact(1, S.SUB_ALLY)})
				expect(bar + hex).to.equal(0)
				-- a hostile past the message's limit is not looked at
				local many = {}

				for i = 1, S.MAX_CONTACTS + 5 do
					many[i] = contact(1, 0)
				end

				many[S.MAX_CONTACTS + 1] = contact(3, 4)
				bar, hex = R.SplitTargets(many)
				expect(hex).to.equal(0)
			end
		},
		{
			name = "exposure rises like the AI's stealth-o-meter: dt / ((1 - target / 2) * 1.5 s) when relaxed",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				expect(Hex.SOM_RELAXED).to.equal(1.5)
				expect(Hex.SOM_COMBAT).to.equal(4.5)

				-- a target of 1: 0.75 s for a whole unit while relaxed
				local s = Hex.NewState()
				Hex.Step(s, 1, 0.1)
				expect(s.exposure).to.aboutEqual(0.1 / 0.75, 1e-6)

				-- a target of 0.8: (1 - 0.4) * 1.5 = 0.9 s for a whole unit
				s = Hex.NewState()
				Hex.Step(s, 0.8, 0.09)
				expect(s.exposure).to.aboutEqual(0.1, 1e-6)

				-- a target of one half: (1 - 0.25) * 1.5 = 1.125 s for a whole unit, and it stops at the target
				s = Hex.NewState()
				Hex.Step(s, 0.5, 0.1125)
				expect(s.exposure).to.aboutEqual(0.1, 1e-6)
				run(s, 0.5, 2)
				expect(s.exposure).to.equal(0.5)
				expect(s.alert).to.equal(0) -- a half never reaches the top level
			end
		},
		{
			name = "once a vehicle is in alert (it reached the top level, for the next 36 s) the meter rises 3 times slower: 4.5 s instead of 1.5",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				local s = Hex.NewState()
				s.alert = 10
				Hex.Step(s, 1, 1)
				expect(s.exposure).to.aboutEqual(1 / (0.5 * 4.5), 1e-6)

				-- reaching the top level starts the alert: 16 s of the target forget time plus 20 of the memory
				s = Hex.NewState()
				run(s, 1, 1)
				expect(s.alert).to.aboutEqual(36, 0.2)
			end
		},
		{
			name = "exposure falls in 2 s when relaxed and 4 s when in alert (the forget time of 16 s over 8 or over 4)",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				local s = Hex.NewState()
				s.exposure = 1
				Hex.Step(s, 0, 1)
				expect(s.exposure).to.aboutEqual(0.5, 1e-6)
				Hex.Step(s, 0, 1)
				expect(s.exposure).to.equal(0)

				s = Hex.NewState()
				s.exposure, s.alert = 1, 20
				Hex.Step(s, 0, 1)
				expect(s.exposure).to.aboutEqual(0.75, 1e-6)
			end
		},
		{
			name = "the threat is a memory: 0.3 / 0.6 / 0.9 at the exposure steps, held 16 / 20 / 20 s, so the hexagon falls in two times (fast, then slowly) and is gone after 56 s",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				expect(Hex.FORGET_TARGET).to.equal(16)
				expect(Hex.FORGET_SEEK).to.equal(20)
				expect(Hex.FORGET_MEMORY).to.equal(20)

				-- the top level held, nothing seen any more: 0.9 falling to 0.6 in 16 s, 0.6 to 0.3 in 20 s, 0.3 to 0 in 20 s
				local s = Hex.NewState()
				s.level, s.timeout = 3, 16
				expect(Hex.Step(s, 0, 0.001)).to.aboutEqual(0.9, 0.001)
				expect(Hex.Step(s, 0, 7.999)).to.aboutEqual(0.75, 0.001)

				s = Hex.NewState()
				s.level, s.timeout = 2, 20
				expect(Hex.Step(s, 0, 10)).to.aboutEqual(0.45, 0.001)

				s = Hex.NewState()
				s.level, s.timeout = 1, 20
				expect(Hex.Step(s, 0, 10)).to.aboutEqual(0.15, 0.001)

				-- the whole fall from a full exposure
				s = Hex.NewState()
				run(s, 1, 2)
				expect(s.level).to.equal(3)
				run(s, 0, 4)
				expect(s.exposure < 0.01).to.beTrue()
				expect(Hex.Step(s, 0, 1 / 30) > 0.5).to.beTrue()
				expect(run(s, 0, 40) > 0.1).to.beTrue()
				expect(run(s, 0, 16) > 0).to.beFalse() -- 2 + 4 + 40 + 16 = 62 s after the start: past the 56 s of memory
				expect(s.level).to.equal(0)
			end
		},
		{
			name = "the threat of the top level is 0.9 at most, and it is held for as long as the exposure keeps above 0.9",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				local s = Hex.NewState()
				local peak = 0

				for _ = 1, 30 * 30 do
					peak = math.max(peak, s.level == 3 and (s.timeout / 16) * 0.3 + 0.6 or 0)
					Hex.Step(s, 1, 1 / 30)
				end

				expect(peak <= 0.9 + 1e-9).to.beTrue()
				expect(s.level).to.equal(3)
				expect(s.timeout).to.aboutEqual(16, 0.1)
			end
		},
		{
			name = "an alerted vehicle (a target of one half) lights the hexagon amber, a fighting one reaches the pulsing red, and neither goes past the frames of the movie",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				local s = Hex.NewState()
				local value = run(s, 0.5, 3)
				expect(Hex.Frame(value)).to.equal(50) -- 49 to 54: amber
				expect(value < 0.55).to.beTrue()

				s = Hex.NewState()
				value = run(s, 1, 2)
				expect(Hex.Frame(value)).to.equal(100) -- 95 and up: red, pulsing
			end
		},
		{
			name = "the frame is the exposure times 100, cut like Flash does (94.9 is 94), at least 1 (frame 1 is the value 0), at most 100",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				expect(Hex.Frame(0)).to.equal(1)
				expect(Hex.Frame(0.005)).to.equal(1)
				expect(Hex.Frame(0.48)).to.equal(48)
				expect(Hex.Frame(0.5)).to.equal(50)
				expect(Hex.Frame(0.54)).to.equal(54)
				expect(Hex.Frame(0.55)).to.equal(55)
				expect(Hex.Frame(0.94)).to.equal(94)
				expect(Hex.Frame(0.949)).to.equal(94)
				expect(Hex.Frame(0.95)).to.equal(95)
				expect(Hex.Frame(1)).to.equal(100)
				expect(Hex.Frame(5)).to.equal(100)
				expect(Hex.Frame(-1)).to.equal(1)
				expect(Hex.Frame(nil)).to.equal(1)
				expect(Hex.Frame(0 / 0)).to.equal(1)

				expect(Hex.Quantise(0)).to.equal(0)
				expect(Hex.Quantise(0.949)).to.equal(94)
				expect(Hex.Quantise(1)).to.equal(100)
				expect(Hex.Quantise(7)).to.equal(100)
				expect(Hex.Quantise(0 / 0)).to.equal(0)
			end
		},
		{
			name = "the model is safe with bad numbers: a bad step changes nothing, a bad target is nothing",
			func = function(state)
				local Hex = GryMod.FlashRadar.Hex
				local s = Hex.NewState()
				s.exposure = 0.4
				expect(Hex.Step(s, 1, 0 / 0)).to.aboutEqual(0.4, 1e-9)
				expect(Hex.Step(s, 1, -1)).to.aboutEqual(0.4, 1e-9)
				expect(Hex.Step(s, 1, nil)).to.aboutEqual(0.4, 1e-9)
				Hex.Step(s, nil, 1)
				expect(s.exposure < 0.4).to.beTrue()
				Hex.Step(s, 0 / 0, 1)
				expect(s.exposure == s.exposure).to.beTrue()
			end
		},
		{
			name = "the panel's hexagon is the movie of the icons at the radar's place: SetExposure goes to the frame of the clip, only when it changes",
			func = function(state)
				local panel = newPanel()
				expect(panel.hex).toNot.beNil()
				expect(panel.hex.clip:Child("Icons"):CurrentLabel()).to.equal("stealth")
				expect(hexFrame(panel)).to.equal(1)

				panel:SetExposure(0.5)
				expect(hexFrame(panel)).to.equal(50)
				panel:SetExposure(0.65)
				expect(hexFrame(panel)).to.equal(65)
				panel:SetExposure(1)
				expect(hexFrame(panel)).to.equal(100)
				panel:SetExposure(0)
				expect(hexFrame(panel)).to.equal(1)
				panel:SetExposure(nil)
				expect(hexFrame(panel)).to.equal(1)

				-- its rebuilt clips keep the level (the radar movie rebuilding itself does not touch this one, but a destroy does)
				panel:SetExposure(0.8)
				panel:Destroy(0)
				expect(hexFrame(panel)).to.equal(80)
			end
		},
		{
			name = "the icon sits in the radar's hexagon: the same origin as the radar's Root clip, and the pulse of the top frames plays on its own",
			func = function(state)
				local panel = newPanel()
				local radar = panel.root:EntryAt(1)
				local hex = panel.hex.root:EntryAt(1)
				expect(math.abs(radar.m[5] - hex.m[5]) < 0.5 and math.abs(radar.m[6] - hex.m[6]) < 0.5).to.beTrue()

				panel:SetExposure(0.97)
				local icon = panel.hex.clip:Child("Icons"):Child("StealthExposure")
				expect(icon:CurrentFrame()).to.equal(97)
				expect(icon:ChildCount() > 0).to.beTrue()
				-- the pulse is a clip of 15 frames at 30 a second: half a second a turn
				local pulse = icon.list[1] and icon.list[1].clip
				expect(pulse).toNot.beNil()
				local before = pulse:CurrentFrame()
				panel:Update(0.2)
				expect(pulse:CurrentFrame()).toNot.equal(before)
			end
		},
		{
			name = "the hexagon is off when its movie is missing: no error, no hexagon, the radar goes on",
			func = function(state)
				local R = GryMod.FlashRadar
				local movie = R.HEX_MOVIE
				R.HEX_MOVIE = "no_such_movie"
				local ok, panel = pcall(newPanel)
				R.HEX_MOVIE = movie
				expect(ok).to.beTrue()
				expect(panel.hex).to.beNil()
				panel:SetExposure(0.9)
				panel:Update(0.03)
				expect(panel.exposure).to.equal(0.9)
				panel:Release()
			end
		},
		{
			name = "the feed: a fighting machine raises the hexagon to the pulsing red and leaves the bar alone, a fighting soldier raises the bar and leaves the hexagon alone",
			func = function(state)
				local R = GryMod.FlashRadar
				withFeed({}, function()
					local panel = newPanel()
					local bar = panel.view:Child("StealthBar")
					R.Stealth = 0
					R.Snapshot = {contact(3, 4)}

					for _ = 1, 90 do R.Feed(panel, feedPly(), 1 / 30) end

					expect(hexFrame(panel)).to.equal(100)
					expect(bar:CurrentFrame()).to.equal(1)
					expect(R.Stealth).to.equal(0)

					-- he is gone: the exposure falls fast, the memory slowly
					R.Snapshot = {}

					for _ = 1, 150 do R.Feed(panel, feedPly(), 1 / 30) end -- 5 s

					expect(hexFrame(panel) < 100).to.beTrue()
					expect(hexFrame(panel) > 55).to.beTrue()

					R.Hex.Reset()
					panel = newPanel()
					bar = panel.view:Child("StealthBar")
					R.Snapshot = {contact(1, 4)}

					for _ = 1, 90 do R.Feed(panel, feedPly(), 1 / 30) end

					expect(bar:CurrentFrame()).to.equal(101)
					expect(hexFrame(panel)).to.equal(1)
				end)
			end
		},
		{
			name = "the switch gry_hud_radarhex off: nothing changes from before, the bar follows every hostile (machines too) and the hexagon stays at rest and is not drawn",
			func = function(state)
				local R = GryMod.FlashRadar
				withFeed({radarhex = false}, function()
					local panel = newPanel()
					local bar = panel.view:Child("StealthBar")
					R.Stealth = 0
					R.Snapshot = {contact(3, 4)}

					for _ = 1, 90 do R.Feed(panel, feedPly(), 1 / 30) end

					expect(bar:CurrentFrame()).to.equal(101)
					expect(hexFrame(panel)).to.equal(1)
					expect(panel.hexShown).to.beFalse()
					expect(R.Hex.State.exposure).to.equal(0)

					-- and a forced level (the event of an addon) shows nothing either
					R.Hex.Force(90, 5)
					R.Feed(panel, feedPly(), 1 / 30)
					expect(hexFrame(panel)).to.equal(1)
				end)

				-- on: the hexagon is drawn at rest, small and green, as in the original
				withFeed({}, function()
					local panel = newPanel()
					R.Snapshot = {}
					R.Feed(panel, feedPly(), 1 / 30)
					expect(panel.hexShown).to.beTrue()
					expect(hexFrame(panel)).to.equal(1)
				end)
			end
		},
		{
			name = "no contacts (the radar's contacts are off): the hexagon is forgotten, no stale level",
			func = function(state)
				local R = GryMod.FlashRadar
				withFeed({radarunits = false}, function()
					local panel = newPanel()
					R.Hex.State.exposure, R.Hex.State.level, R.Hex.State.timeout = 1, 3, 16
					R.Snapshot = {contact(3, 4)}
					R.Feed(panel, feedPly(), 1 / 30)

					-- nothing feeds the meter any more: it is forgotten at once, not held for the 56 s of the memory
					expect(hexFrame(panel)).to.equal(1)
					expect(R.Hex.State.level).to.equal(0)
				end)
			end
		},
		{
			name = "an addon's hexagon: Force raises the level for its seconds (the highest of it and the model), then it falls like the exposure; the HUD event radar_exposure does it",
			func = function(state)
				local R = GryMod.FlashRadar
				withFeed({}, function()
					local panel = newPanel()
					R.Snapshot = {}
					R.Hex.Force(80, 1)
					R.Feed(panel, feedPly(), 1 / 30)
					expect(hexFrame(panel)).to.equal(80)

					for _ = 1, 20 do R.Feed(panel, feedPly(), 1 / 30) end

					expect(hexFrame(panel)).to.equal(80)

					for _ = 1, 30 do R.Feed(panel, feedPly(), 1 / 30) end -- past its second

					expect(hexFrame(panel) < 80).to.beTrue()
					R.Hex.Reset()

					-- the model's level is not lowered by a smaller forced one
					R.Snapshot = {contact(3, 4)}

					for _ = 1, 60 do R.Feed(panel, feedPly(), 1 / 30) end

					R.Hex.Force(20, 5)
					R.Feed(panel, feedPly(), 1 / 30)
					expect(hexFrame(panel)).to.equal(100)

					R.Hex.Reset()
					R.Snapshot = {}
					expect(GryMod.API.HUDEvent("radar_exposure", {level = 70, seconds = 2})).to.beTrue()
					R.Feed(panel, feedPly(), 1 / 30)
					expect(hexFrame(panel)).to.equal(70)

					-- bad data: a level out of range is cut, the seconds are bounded
					R.Hex.Reset()
					GryMod.API.HUDEvent("radar_exposure", {level = 9999, seconds = 99999})
					expect(R.Hex.Forced <= 1).to.beTrue()
					expect(R.Hex.ForcedLeft <= 60).to.beTrue()
					R.Hex.Reset()
					GryMod.API.HUDEvent("radar_exposure")
					expect(R.Hex.Forced > 0).to.beTrue() -- the default is a clear alert, shown for a few seconds
				end)
			end
		},
		{
			name = "the hook GryMod_RadarExposure(value, previous) is called with the level 0 to 100 when it changes, and not when it stays",
			func = function(state)
				local R = GryMod.FlashRadar
				local calls = {}
				hook.Add("GryMod_RadarExposure", "zz_hex_test", function(value, previous)
					calls[#calls + 1] = {value, previous}
				end)
				local ok, err = pcall(function()
					withFeed({}, function()
						local panel = newPanel()
						R.Snapshot = {}
						R.Feed(panel, feedPly(), 1 / 30)
						expect(#calls).to.equal(0) -- 0 stays 0

						R.Hex.Force(60, 5)
						R.Feed(panel, feedPly(), 1 / 30)
						expect(#calls).to.equal(1)
						expect(calls[1][1]).to.equal(60)
						expect(calls[1][2]).to.equal(0)
						R.Feed(panel, feedPly(), 1 / 30)
						expect(#calls).to.equal(1)

						R.Hex.Force(75, 5)
						R.Feed(panel, feedPly(), 1 / 30)
						expect(#calls).to.equal(2)
						expect(calls[2][1]).to.equal(75)
						expect(calls[2][2]).to.equal(60)
					end)
				end)
				hook.Remove("GryMod_RadarExposure", "zz_hex_test")

				if not ok then error(err, 0) end
			end
		},
		{
			name = "a malfunction of the suit: the hexagon follows the radar's destroy (the icon goes with the radar, the movie's own malfunction frame)",
			func = function(state)
				local panel = newPanel()
				panel:SetExposure(0.6)
				panel:Destroy(1)
				expect(panel.hex.clip:CurrentLabel()).to.equal("malfunction")
				panel:Destroy(0)
				panel:Update(0.2)
				expect(panel.hex.clip:Child("Icons")).toNot.beNil()
				expect(hexFrame(panel)).to.equal(60)
			end
		},
		{
			name = "no memory is allocated in a steady frame: the split, the model, the frame and the panel's call",
			func = function(state)
				local R = GryMod.FlashRadar
				local Hex = R.Hex
				local panel = newPanel()
				local contacts = {contact(1, 3), contact(3, 4), contact(2, 3), contact(4, 0)}
				local s = Hex.NewState()

				-- a steady state: a vehicle that keeps fighting (the meter stays at the top). A change of the frame of the movie's clip makes some
				-- garbage in the clip engine, a hundred times at most in a whole rise.
				local function work()
					for _ = 1, 200 do
						local _, hex = R.SplitTargets(contacts)
						local value = Hex.Step(s, hex, 1 / 30)
						panel:SetExposure(value)
						Hex.Quantise(value)
						Hex.Frame(value)
					end
				end

				work()
				work()

				local grown = math.huge

				-- the runner's own step hook allocates a few KB whenever it fires (how often depends on the JIT): it is off while the memory is measured
				local hookFn, mask, count = debug.gethook()
				debug.sethook()

				local ok, err = pcall(function()
					for _ = 1, 5 do
						collectgarbage("collect")
						collectgarbage("stop")
						local before = collectgarbage("count")
						work()
						grown = math.min(grown, collectgarbage("count") - before)
						collectgarbage("restart")
					end
				end)

				collectgarbage("restart")

				if hookFn then
					debug.sethook(hookFn, mask, count)
				end

				if not ok then
					error(err, 0)
				end

				-- 200 frames: any allocation each frame would be several KB
				expect(grown < 1).to.beTrue()
			end
		},
		{
			name = "the option: gry_hud_radarhex is a saved HUD switch, on by default, in the list after the radar contacts, with a short label and a help",
			func = function(state)
				local convar = GetConVar("gry_hud_radarhex")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				-- saved like the other HUD switches (made by the same code: CreateClientConVar with shouldsave)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_hud_radarunits"):GetFlags())

				local list = GryMod.HUDOptions.List
				local found

				for i, option in ipairs(list) do
					if option.name == "radarhex" then
						found = i
						expect(list[i - 1].name).to.equal("radarunits")
						expect(#option.label <= 46).to.beTrue()
						expect(isstring(option.help) and #option.help > 20).to.beTrue()
						expect(GryMod.RadarHUDElements.radarhex).to.beTrue()
					end
				end

				expect(found).toNot.beNil()
			end
		},
		{
			name = "the event radar_exposure is registered with a label, variants for the four looks of the icon, and follows the switch",
			func = function(state)
				local info = GryMod.API.GetHUDEventInfo("radar_exposure")
				expect(info).toNot.beNil()
				expect(info.label).toNot.equal("radar_exposure")
				expect(#info.variants).to.equal(4)
				expect(info.follows[1][1]).to.equal("gry_hud_radarhex")
			end
		}
	}
}
