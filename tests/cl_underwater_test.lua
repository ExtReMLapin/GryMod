-- Tests of the underwater sounds (GryMod.Underwater, cl_underwater.lua), GLuaTest format, client realm: what plays and
-- when (the dive in and out, the breathing cycle, the drowning gasps, the ambience loop), the volumes in the mix and the
-- switches. The numbers are in docs/superpowers/plans/2026-11-21-underwater-notes.md. Nothing is listened to: the
-- sounds, the player's water level and the loop channel are replaced by recorders (and put back after each case).

local savedConVars = {}
local saved = {}

local function setConVar(name, value)
	local convar = GetConVar(name)

	if not convar then return end

	if savedConVars[name] == nil then
		savedConVars[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function fakeChannel()
	local channel = {calls = {}}

	for _, name in ipairs({"Play", "Pause", "SetTime", "SetVolume", "EnableLooping"}) do
		channel[name] = function(self, value)
			self.calls[#self.calls + 1] = {name, value}
		end
	end

	channel.IsValid = function() return true end

	return channel
end

local function countCalls(channel, name)
	local count = 0

	for _, call in ipairs(channel.calls) do
		if call[1] == name then count = count + 1 end
	end

	return count
end

-- a player that is under water (level 3) or not, alive, with a velocity and a drowning flag
local function fakePlayer(fields)
	local ply = {level = 0, alive = true, velocity = Vector(0, 0, 0), drowning = false}

	for k, v in pairs(fields or {}) do ply[k] = v end

	function ply:IsValid() return true end
	function ply:WaterLevel() return self.level end
	function ply:Alive() return self.alive end
	function ply:GetVelocity() return self.velocity end
	function ply:GetNW2Bool(name) return name == "GryDrowning" and self.drowning end

	return ply
end

local function receive(name)
	local receiver = net.Receivers[name]
	assert(receiver, "no receiver for " .. name)
	receiver()
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

local U

-- records every sound the module asks for; returns the list of paths
local function recordSounds()
	local played = {}

	stub(GryMod, "PlaySound", function(path)
		played[#played + 1] = path

		return true
	end)

	return played
end

local function lastOf(list)
	return list[#list]
end

local function isOneOf(list, path)
	for _, candidate in ipairs(list) do
		if candidate == path then return true end
	end

	return false
end

local function contains(path, text)
	return string.find(string.lower(tostring(path)), text, 1, true) ~= nil
end

return {
	groupName = "GryMod underwater sounds (client)",
	beforeEach = function(state)
		saved = {}
		U = GryMod.Underwater
		setConVar("gry_sounds", "1")
		setConVar("gry_underwater_fx", "1")
		setConVar("gry_sound_volume", "6")

		if U then U.Reset() end
	end,
	afterEach = function(state)
		if U then
			U.Reset()
			U.Ambience.Set(nil)
		end

		for i = #saved, 1, -1 do
			local entry = saved[i]
			entry[1][entry[2]] = entry[3]
		end

		for name, value in pairs(savedConVars) do
			if GetConVar(name) then GetConVar(name):SetString(value) end
		end

		savedConVars = {}
		timer.Remove("GryUnderwater")
	end,
	cases = {
		{
			name = "gry_underwater_fx exists: client, saved, 1 by default",
			func = function(state)
				local convar = GetConVar("gry_underwater_fx")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				expect(convar:GetFlags()).to.equal(GetConVar("gry_sounds"):GetFlags())
			end
		},
		{
			name = "the breathing cycle: a breath at 2, 6 and 10 s, the bubbles at 4 and 8 s, in 11 s (the original's 4 s cycle)",
			func = function(state)
				local cycle = {t = 0}
				local breaths, bubbles = {}, {}
				local now = 0

				for _ = 1, 220 do
					now = now + 0.05
					local event = U.BreathStep(cycle, 0.05)

					if event == "breath" then breaths[#breaths + 1] = now end
					if event == "bubbles" then bubbles[#bubbles + 1] = now end
				end

				expect(#breaths).to.equal(3)
				expect(#bubbles).to.equal(2)
				expect(near(breaths[1], 2, 0.06)).to.beTrue()
				expect(near(breaths[2], 6, 0.12)).to.beTrue()
				expect(near(breaths[3], 10, 0.2)).to.beTrue()
				expect(near(bubbles[1], 4, 0.12)).to.beTrue()
				expect(near(bubbles[2], 8, 0.2)).to.beTrue()
			end
		},
		{
			name = "no breath before 2 s under water",
			func = function(state)
				local cycle = {t = 0}

				for _ = 1, 38 do
					expect(U.BreathStep(cycle, 0.05)).to.beNil()
				end
			end
		},
		{
			name = "the water transitions: dive in when the head goes under, dive out when it comes out, nothing otherwise or on the first look",
			func = function(state)
				expect(U.Transition(false, true)).to.equal("dive_in")
				expect(U.Transition(true, false)).to.equal("dive_out")
				expect(U.Transition(false, false)).to.beNil()
				expect(U.Transition(true, true)).to.beNil()
				expect(U.Transition(nil, true)).to.beNil()
				expect(U.Transition(nil, false)).to.beNil()
			end
		},
		{
			name = "the dive in sound: the slow one for a gentle entry, one of the three fast ones for a hard fall",
			func = function(state)
				expect(U.DiveInFile(0, 0.5)).to.equal(U.Files.diveSlow)
				expect(U.DiveInFile(U.FastDiveSpeed - 1, 0.5)).to.equal(U.Files.diveSlow)
				expect(U.DiveInFile(U.FastDiveSpeed + 1, 0)).to.equal(U.Files.diveFast[1])
				expect(U.DiveInFile(U.FastDiveSpeed + 1, 0.5)).to.equal(U.Files.diveFast[2])
				expect(U.DiveInFile(U.FastDiveSpeed + 1, 0.999)).to.equal(U.Files.diveFast[3])
			end
		},
		{
			name = "the shuffle never plays the same file twice in a row and reaches every file",
			func = function(state)
				local list = U.Files.breath
				expect(#list).to.equal(5)
				local seen = {}
				local last

				for i = 1, 200 do
					local path = U.Pick(list, last, math.random())
					expect(path ~= last).to.beTrue()
					seen[path] = true
					last = path
				end

				for _, path in ipairs(list) do
					expect(seen[path]).to.beTrue()
				end
			end
		},
		{
			name = "the files the sounds use are the 17 decoded ones plus the loop (WAV at the bank's own quality, under grymod/water), all in the mix with the original's level",
			func = function(state)
				expect(#U.Files.breath).to.equal(5)
				expect(#U.Files.drown).to.equal(7)
				expect(#U.Files.diveFast).to.equal(3)

				local all = {U.Files.diveSlow, U.Files.diveOut, U.Files.ambience}

				for _, list in ipairs({U.Files.breath, U.Files.drown, U.Files.diveFast}) do
					for _, path in ipairs(list) do all[#all + 1] = path end
				end

				expect(#all).to.equal(18)

				for _, path in ipairs(all) do
					expect(path:find("^grymod/water/[%w_]+%.wav$") ~= nil).to.beTrue()
					expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
				end

				-- the original: underwater_feedback -29 dB, drown_feedback -15, dive_in -9 (the slow layer at half its level:
				-- -15), dive_out -12 (layer at half: -18), the ambience loop -16; the volume at +6 dB is 10^((level+6)/20)
				for _, path in ipairs(U.Files.breath) do
					expect(GryMod.SoundMix.Volume(path, 6)).to.aboutEqual(0.071, 0.005)
				end

				for _, path in ipairs(U.Files.drown) do
					expect(GryMod.SoundMix.Volume(path, 6)).to.aboutEqual(0.355, 0.01)
				end

				expect(GryMod.SoundMix.Volume(U.Files.diveSlow, 6)).to.aboutEqual(0.355, 0.01)

				for _, path in ipairs(U.Files.diveFast) do
					expect(GryMod.SoundMix.Volume(path, 6)).to.aboutEqual(0.708, 0.01)
				end

				-- the dive out layer is at 0.507874 (-5.9 dB) of the event's -12
				expect(GryMod.SoundMix.Original[GryMod.SoundMix.Normalize(U.Files.diveOut)]).to.equal(-17.88) -- -17.9, the file scaled down 0.02 dB
				expect(GryMod.SoundMix.Volume(U.Files.diveOut, 6)).to.aboutEqual(0.254, 0.001)
				expect(GryMod.SoundMix.Volume(U.Files.ambience, 6)).to.aboutEqual(0.316, 0.01)
			end
		},
		{
			name = "the ambience loop plays at the event's pitch, -0.75 octave: the channel gets that playback rate once it is created",
			func = function(state)
				expect(GryMod.SoundMix.Rate(U.Files.ambience)).to.aboutEqual(2 ^ -0.75, 0.0001)
				expect(GryMod.SoundMix.Pitch(U.Files.ambience)).to.equal(59)
				expect(GryMod.SoundMix.Rate("grymod/suit/suit_armor_108.wav")).to.equal(1)

				local callback
				stub(sound, "PlayFile", function(path, flags, func)
					expect(path).to.equal("sound/" .. U.Files.ambience)
					callback = func
				end)
				U.Ambience.Set(nil)
				local ply = fakePlayer({level = 3})
				stub(_G, "LocalPlayer", function() return ply end)
				recordSounds()
				U.Poll()
				expect(callback ~= nil).to.beTrue()

				local channel = fakeChannel()
				local rates = {}
				channel.SetPlaybackRate = function(self, rate) rates[#rates + 1] = rate end
				callback(channel)
				expect(#rates).to.equal(1)
				expect(rates[1]).to.aboutEqual(2 ^ -0.75, 0.0001)
				expect(countCalls(channel, "EnableLooping")).to.equal(1)
			end
		},
		{
			name = "on dry land nothing plays, no timer runs and no loop starts",
			func = function(state)
				local played = recordSounds()
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)

				for _ = 1, 20 do U.Poll() end

				expect(#played).to.equal(0)
				expect(#channel.calls).to.equal(0)
				expect(timer.Exists("GryUnderwater")).to.beFalse()
			end
		},
		{
			name = "going under: the dive in sound, the loop starts and the breathing timer starts; coming out: the dive out sound, the loop stops, the timer goes",
			func = function(state)
				local played = recordSounds()
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()

				expect(#played).to.equal(1)
				expect(played[1]).to.equal(U.Files.diveSlow)
				expect(countCalls(channel, "Play")).to.equal(1)
				expect(timer.Exists("GryUnderwater")).to.beTrue()

				-- still under: no second dive sound
				U.Poll()
				U.Poll()
				expect(#played).to.equal(1)

				ply.level = 0
				U.Poll()

				expect(#played).to.equal(2)
				expect(played[2]).to.equal(U.Files.diveOut)
				expect(countCalls(channel, "Pause")).to.equal(1)
				expect(timer.Exists("GryUnderwater")).to.beFalse()
			end
		},
		{
			name = "a hard fall into the water plays a fast dive in sound",
			func = function(state)
				local played = recordSounds()
				U.Ambience.Set(fakeChannel())
				local ply = fakePlayer({level = 0, velocity = Vector(0, 0, -(U.FastDiveSpeed + 100))})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()

				expect(isOneOf(U.Files.diveFast, played[1])).to.beTrue()
			end
		},
		{
			name = "the ambience loop's volume is the mix's level, brought up over the first hundredths of a second",
			func = function(state)
				expect(U.AmbienceVolume(0)).to.equal(0)
				expect(U.AmbienceVolume(1)).to.aboutEqual(GryMod.SoundMix.Volume(U.Files.ambience), 0.001)

				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 3})
				stub(_G, "LocalPlayer", function() return ply end)
				recordSounds()
				-- the first look at the water: already under (a map loaded in the water), no dive in sound
				U.Poll()
				U.Tick(0.1)
				U.Tick(0.1)
				local volume

				for _, call in ipairs(channel.calls) do
					if call[1] == "SetVolume" then volume = call[2] end
				end

				expect(volume).to.aboutEqual(GryMod.SoundMix.Volume(U.Files.ambience), 0.001)
			end
		},
		{
			name = "the first look at the water from under it plays no dive in sound",
			func = function(state)
				local played = recordSounds()
				U.Ambience.Set(fakeChannel())
				local ply = fakePlayer({level = 3})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()

				expect(#played).to.equal(0)
			end
		},
		{
			name = "under water the breathing plays at 2 s, then every 4 s, a different file each time",
			func = function(state)
				local played = recordSounds()
				U.Ambience.Set(fakeChannel())
				local ply = fakePlayer({level = 3})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()

				for _ = 1, 19 do U.Tick(0.1) end
				expect(#played).to.equal(0)

				U.Tick(0.1)
				U.Tick(0.1)
				expect(#played).to.equal(1)
				expect(isOneOf(U.Files.breath, played[1])).to.beTrue()

				for _ = 1, 40 do U.Tick(0.1) end
				expect(#played).to.equal(2)
				expect(played[2] ~= played[1]).to.beTrue()
			end
		},
		{
			name = "while drowning the calm breathing stops (the gasps replace it)",
			func = function(state)
				local played = recordSounds()
				U.Ambience.Set(fakeChannel())
				local ply = fakePlayer({level = 3, drowning = true})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()

				for _ = 1, 100 do U.Tick(0.1) end

				expect(#played).to.equal(0)
			end
		},
		{
			name = "the server's drowning tick plays one of the seven gasps, never the same twice in a row",
			func = function(state)
				local played = recordSounds()
				local ply = fakePlayer({level = 3})
				stub(_G, "LocalPlayer", function() return ply end)
				local last

				for _ = 1, 30 do
					receive("gry_drown_tick")
					local path = lastOf(played)
					expect(isOneOf(U.Files.drown, path)).to.beTrue()
					expect(path ~= last).to.beTrue()
					last = path
				end

				expect(#played).to.equal(30)
			end
		},
		{
			name = "gry_underwater_fx 0: no sound, no loop, no timer, even under water and on a drowning tick",
			func = function(state)
				setConVar("gry_underwater_fx", "0")
				local played = recordSounds()
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()
				U.Tick(5)
				receive("gry_drown_tick")
				ply.level = 0
				U.Poll()

				expect(#played).to.equal(0)
				expect(#channel.calls).to.equal(0)
				expect(timer.Exists("GryUnderwater")).to.beFalse()
			end
		},
		{
			name = "turning the option off under water stops the loop and the timer at once",
			func = function(state)
				local played = recordSounds()
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()
				expect(timer.Exists("GryUnderwater")).to.beTrue()
				setConVar("gry_underwater_fx", "0")
				U.Poll()

				expect(timer.Exists("GryUnderwater")).to.beFalse()
				expect(countCalls(channel, "Pause")).to.equal(1)
			end
		},
		{
			name = "dying under water ends the sounds like coming out, without the dive out sound",
			func = function(state)
				local played = recordSounds()
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()
				local before = #played
				ply.alive = false
				U.Poll()

				expect(#played).to.equal(before)
				expect(countCalls(channel, "Pause")).to.equal(1)
				expect(timer.Exists("GryUnderwater")).to.beFalse()
			end
		},
		{
			name = "gry_sounds 0 silences everything (the sounds go through GryMod.PlaySound, the loop checks the switch)",
			func = function(state)
				setConVar("gry_sounds", "0")
				local channel = fakeChannel()
				U.Ambience.Set(channel)
				local ply = fakePlayer({level = 0})
				stub(_G, "LocalPlayer", function() return ply end)
				U.Poll()
				ply.level = 3
				U.Poll()

				expect(countCalls(channel, "Play")).to.equal(0)
			end
		},
		{
			name = "the module plays only through the mix: no EmitSound, surface.PlaySound or sound.Play outside it",
			func = function(state)
				local text = file.Read("grymod/client/cl_underwater.lua", "LUA")
				expect(text ~= nil).to.beTrue()
				expect(text:find("surface.PlaySound", 1, true) == nil).to.beTrue()
				expect(text:find("EmitSound", 1, true) == nil).to.beTrue()
				expect(text:find("sound.Play(", 1, true) == nil).to.beTrue()
			end
		}
	}
}
