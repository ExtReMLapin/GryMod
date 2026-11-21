-- Tests of the sound mix (cl_sound_mix.lua), GLuaTest format, client realm: the volume of each sound (the original game's
-- levels plus a base gain), the single way a sound is played, the limit of simultaneous armor hits, the speed loops'
-- volume, and the delay of the voices after the sound of a mode change. Nothing is listened to: everything that could
-- make a sound is replaced by a recorder (and put back after each case).

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

	for _, name in ipairs({"Play", "Pause", "SetTime", "SetVolume"}) do
		channel[name] = function(self, value)
			self.calls[#self.calls + 1] = {name, value}
		end
	end

	channel.IsValid = function() return true end

	return channel
end

local function receive(name)
	local receiver = net.Receivers[name]
	assert(receiver, "no receiver for " .. name)
	receiver()
end

-- the volume of the sound at a gain of +6 dB (the default), 0.01 near
local function expectVolume(path, volume)
	expect(GryMod.SoundMix.Volume(path, 6)).to.aboutEqual(volume, 0.01)
end

-- every file the addon plays, with its volume at +6 dB (nil: no data, the voices, full volume)
local played = {
	["suit/servo_speed_stop_fp_2.mp3"] = 0.04,
	["suit/servo_speed_stop_01_underwater.mp3"] = 0.09,
	["suit/servo_speed_loop_01c.mp3"] = 0.09,
	["suit/servo_speed_loop_01_underwater.mp3"] = 0.28,
	["suit/suit_speed_activate_07_good.wa.mp3"] = 0.14,
	["suit/strengthmode.mp3"] = 0.25,
	["suit/suit_strength_101_r.mp3"] = 0.25,
	["suit/suit_armor_108.mp3"] = 0.40,
	["suit/suit_cloak_chameleon_101_r.mp3"] = 0.32,
	["suit/strengthjump.mp3"] = 0.22,
	["suit/suit_medical_use_new.mp3"] = 0.25,
	["cry_hud_activate.wav"] = 0.25,
	["cry_hud_reboot.wav"] = 0.50,
	["cry_hud_malfunction.wav"] = 0.40,
	["cry_error.wav"] = 0.10,
	["cry_open.wav"] = 0.32,
	["cry_close.wav"] = 0.45,
	["cry_select.wav"] = 0.50,
	["cry_hover.wav"] = 0.32
}

local voices = {
	"suit/suit_maximum_armor.mp3", "suit/suit_maximum_speed.mp3", "suit/suit_maximum_strength.mp3",
	"suit/suit_energy_critical.mp3", "suit/suit_modification_engaged.mp3"
}

local savedMode, savedLocalPlayer

return {
	groupName = "GryMod sound mix (client)",
	beforeEach = function(state)
		saved = {}
		savedMode = LocalPlayer().NanosuitMode
		savedLocalPlayer = LocalPlayer
		setConVar("gry_sounds", "1")
		setConVar("gry_sound_volume", "6")
		if GryMod.SoundMix then GryMod.SoundMix.ResetLimits() end
	end,
	afterEach = function(state)
		for i = #saved, 1, -1 do
			local entry = saved[i]
			entry[1][entry[2]] = entry[3]
		end

		LocalPlayer = savedLocalPlayer
		hook.Remove("Think", "GryModSoundhealthregenfadeaway")

		for name, value in pairs(savedConVars) do
			if GetConVar(name) then GetConVar(name):SetString(value) end
		end

		savedConVars = {}
		if GryMod.SoundMix then GryMod.SoundMix.ResetLimits() end

		-- the mode tests change the suit mode and the viewmodel's material
		if state.touchedMode then
			LocalPlayer().NanosuitMode = savedMode

			if IsValid(LocalPlayer():GetViewModel()) then LocalPlayer():GetViewModel():SetMaterial("") end
			if IsValid(LocalPlayer():GetHands()) then LocalPlayer():GetHands():SetMaterial("") end
		end

		timer.Remove("GryModModeVoice")
	end,
	cases = {
		{
			name = "gry_sound_volume exists: default 6 dB, saved like gry_sounds, bounded from -20 to +12",
			func = function(state)
				local convar = GetConVar("gry_sound_volume")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("6")
				expect(convar:GetFlags()).to.equal(GetConVar("gry_sounds"):GetFlags())
				expect(convar:GetMin()).to.equal(-20)
				expect(convar:GetMax()).to.equal(12)
			end
		},
		{
			name = "the volumes at +6 dB are the original game's levels (the armor hits -9 dB, the servo stop -34 dB...)",
			func = function(state)
				-- the 13 armor hits
				for _, path in ipairs(GryMod.ArmorHitSounds) do
					expectVolume(path, 0.71)
				end

				for path, volume in pairs(played) do
					expectVolume(path, volume)
				end
			end
		},
		{
			name = "the volume is min(1, 10^((original dB + gain) / 20)), the gain being an argument",
			func = function(state)
				local path = "suit/suit_bullet_impact_01.mp3" -- -9 dB
				expect(GryMod.SoundMix.Volume(path, 0)).to.aboutEqual(10 ^ (-9 / 20), 0.001)
				expect(GryMod.SoundMix.Volume(path, -20)).to.aboutEqual(10 ^ (-29 / 20), 0.001)
				expect(GryMod.SoundMix.Volume(path, 9)).to.equal(1) -- 0 dB
				expect(GryMod.SoundMix.Volume(path, 12)).to.equal(1) -- +3 dB: capped
				-- a quieter one: the servo stop, -34 dB
				expect(GryMod.SoundMix.Volume("suit/servo_speed_stop_fp_2.mp3", 12)).to.aboutEqual(10 ^ (-22 / 20), 0.001)
			end
		},
		{
			name = "no volume is above 1, whatever the gain",
			func = function(state)
				for _, gain in ipairs({-20, 0, 6, 12, 40}) do
					for path in pairs(played) do
						expect(GryMod.SoundMix.Volume(path, gain) <= 1).to.beTrue()
					end
				end
			end
		},
		{
			name = "a sound without data (the voices, an unknown file) plays at full volume, at any gain",
			func = function(state)
				for _, path in ipairs(voices) do
					expect(GryMod.SoundMix.Volume(path, 6)).to.equal(1)
					expect(GryMod.SoundMix.Volume(path, -20)).to.equal(1)
				end

				expect(GryMod.SoundMix.Volume("nothing/here.wav", 6)).to.equal(1)
				expect(GryMod.SoundMix.Volume("", 6)).to.equal(1)
				expect(GryMod.SoundMix.Volume(nil, 6)).to.equal(1)
			end
		},
		{
			name = "the path may come with sound/, in capitals or with backslashes",
			func = function(state)
				local volume = GryMod.SoundMix.Volume("suit/servo_speed_stop_fp_2.mp3", 6)
				expect(GryMod.SoundMix.Volume("sound/suit/servo_speed_stop_fp_2.mp3", 6)).to.equal(volume)
				expect(GryMod.SoundMix.Volume("SUIT\\Servo_Speed_Stop_FP_2.MP3", 6)).to.equal(volume)
				expect(volume < 1).to.beTrue()
			end
		},
		{
			name = "without a gain argument the volume follows gry_sound_volume, which is kept between -20 and +12",
			func = function(state)
				local path = "suit/suit_bullet_impact_01.mp3"
				setConVar("gry_sound_volume", "0")
				expect(GryMod.SoundMix.Gain()).to.equal(0)
				expect(GryMod.SoundMix.Volume(path)).to.aboutEqual(10 ^ (-9 / 20), 0.001)
				setConVar("gry_sound_volume", "-20")
				expect(GryMod.SoundMix.Volume(path)).to.aboutEqual(10 ^ (-29 / 20), 0.001)
				setConVar("gry_sound_volume", "12")
				expect(GryMod.SoundMix.Volume(path)).to.equal(1)
				-- a value out of the bounds written by hand in the config is brought back
				stub(GryMod.SoundMix, "RawGain", function() return 99 end)
				expect(GryMod.SoundMix.Gain()).to.equal(12)
				GryMod.SoundMix.RawGain = function() return -99 end
				expect(GryMod.SoundMix.Gain()).to.equal(-20)
			end
		},
		{
			name = "GryMod.PlaySound plays through the mix, at the volume of the file",
			func = function(state)
				local calls = {}
				stub(GryMod.SoundMix, "Emit", function(path, volume) calls[#calls + 1] = {path, volume} end)
				expect(GryMod.PlaySound("suit/servo_speed_stop_fp_2.mp3")).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal("suit/servo_speed_stop_fp_2.mp3")
				expect(calls[1][2]).to.aboutEqual(0.04, 0.01)

				setConVar("gry_sound_volume", "-6")
				GryMod.PlaySound("suit/servo_speed_stop_fp_2.mp3")
				expect(calls[2][2] < calls[1][2]).to.beTrue()

				-- a voice: full volume
				GryMod.PlaySound("suit/suit_maximum_speed.mp3")
				expect(calls[3][2]).to.equal(1)
			end
		},
		{
			name = "GryMod.PlaySound plays nothing with gry_sounds 0",
			func = function(state)
				local calls = 0
				stub(GryMod.SoundMix, "Emit", function() calls = calls + 1 end)
				setConVar("gry_sounds", "0")
				expect(GryMod.PlaySound("suit/strengthjump.mp3")).to.beFalse()
				expect(calls).to.equal(0)
			end
		},
		{
			name = "the sound is emitted from the player, without distance (level 0), at the volume, never with surface.PlaySound",
			func = function(state)
				local emitted, surfaced = {}, 0
				-- (a method of the entity's metatable: a function set on the entity itself does not take its place)
				stub(FindMetaTable("Entity"), "EmitSound", function(self, ...)
					if self == LocalPlayer() then emitted[#emitted + 1] = {...} end
				end)
				stub(surface, "PlaySound", function() surfaced = surfaced + 1 end)
				GryMod.SoundMix.Emit("suit/strengthjump.mp3", 0.22)
				expect(surfaced).to.equal(0)
				expect(#emitted).to.equal(1)
				expect(emitted[1][1]).to.equal("suit/strengthjump.mp3")
				expect(emitted[1][2]).to.equal(0) -- SNDLVL_NONE: heard everywhere at the same level
				expect(emitted[1][3]).to.equal(100)
				expect(emitted[1][4]).to.equal(0.22)
				expect(emitted[1][5]).to.equal(CHAN_STATIC)
			end
		},
		{
			name = "without a player the sound plays with surface.PlaySound if it is at full volume, and not at all if it is lower",
			func = function(state)
				local surfaced = {}
				stub(surface, "PlaySound", function(path) surfaced[#surfaced + 1] = path end)
				LocalPlayer = function() return NULL end
				GryMod.SoundMix.Emit("suit/suit_maximum_speed.mp3", 1)
				expect(#surfaced).to.equal(1)
				GryMod.SoundMix.Emit("suit/strengthjump.mp3", 0.22)
				expect(#surfaced).to.equal(1)
			end
		},
		{
			name = "the addon plays its sounds in one place: no surface.PlaySound, EmitSound or sound.Play outside the mix",
			func = function(state)
				local files = file.Find("grymod/client/*.lua", "LUA")
				expect(#files > 10).to.beTrue()

				for _, name in ipairs(files) do
					if name ~= "cl_sound_mix.lua" then
						local text = file.Read("grymod/client/" .. name, "LUA") or ""
						expect(text:find("surface.PlaySound", 1, true) == nil).to.beTrue()
						expect(text:find("EmitSound", 1, true) == nil).to.beTrue()
						expect(text:find("sound.Play(", 1, true) == nil).to.beTrue()
					end
				end
			end
		},
		{
			name = "armor hits: 2 at the most at a time, 60 ms apart at the least (the game's maxpb 2)",
			func = function(state)
				local limit = GryMod.SoundMix.Limits.armor_hit
				expect(limit.max).to.equal(2)
				expect(limit.gap).to.equal(0.06)
				-- the longest of the 13 files is 0.79 s
				expect(limit.length >= 0.79).to.beTrue()

				expect(GryMod.SoundMix.MayPlay("armor_hit", 10)).to.beTrue()
				-- too close
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.03)).to.beFalse()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.059)).to.beFalse()
				-- far enough: the second one
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.07)).to.beTrue()
				-- two are playing
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.2)).to.beFalse()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.5)).to.beFalse()
				-- the first one is over: a new one may start (and the next must wait for the gap, then for a free place)
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + limit.length + 0.001)).to.beTrue()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + limit.length + 0.03)).to.beFalse()
			end
		},
		{
			name = "a refused play is not counted, and the groups do not share their limits",
			func = function(state)
				expect(GryMod.SoundMix.MayPlay("armor_hit", 1)).to.beTrue()

				-- refused ones (too close) do not take a place
				for i = 1, 5 do
					expect(GryMod.SoundMix.MayPlay("armor_hit", 1 + i * 0.01)).to.beFalse()
				end

				expect(GryMod.SoundMix.MayPlay("armor_hit", 1.1)).to.beTrue()
				-- a name without a limit is always allowed
				for i = 1, 5 do
					expect(GryMod.SoundMix.MayPlay("something_else", 1)).to.beTrue()
				end

				GryMod.SoundMix.ResetLimits()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 1.1)).to.beTrue()
			end
		},
		{
			name = "the armor hit message obeys the limit, and a hit that is refused does not use up a file of the shuffle",
			func = function(state)
				local now = 100
				stub(GryMod.SoundMix, "Now", function() return now end)
				local plays, files = 0, 0
				stub(GryMod, "PlaySound", function() plays = plays + 1 end)
				local nextFile = GryMod.NextArmorHitSound
				stub(GryMod, "NextArmorHitSound", function() files = files + 1 return nextFile() end)

				receive("gry_armor_hit_sound") -- plays
				now = 100.01
				receive("gry_armor_hit_sound") -- too close
				now = 100.07
				receive("gry_armor_hit_sound") -- plays
				now = 100.14
				receive("gry_armor_hit_sound") -- two are playing
				now = 100.3
				receive("gry_armor_hit_sound") -- two are playing
				expect(plays).to.equal(2)
				expect(files).to.equal(2)
				now = 101
				receive("gry_armor_hit_sound") -- they are over
				expect(plays).to.equal(3)
			end
		},
		{
			name = "the ground loop volume is the mix's volume times the height above the ground, never above the mix's volume",
			func = function(state)
				local base = GryMod.SoundMix.Volume("suit/servo_speed_loop_01c.mp3")
				expect(base).to.aboutEqual(0.09, 0.01)
				expect(GryMod.GroundLoopVolume(0)).to.aboutEqual(base, 0.0001)
				expect(GryMod.GroundLoopVolume(150)).to.aboutEqual(base / 2, 0.0001)
				expect(GryMod.GroundLoopVolume(300)).to.equal(0)
				expect(GryMod.GroundLoopVolume(5000)).to.equal(0)

				for distance = 0, 400, 20 do
					expect(GryMod.GroundLoopVolume(distance) <= base + 0.0001).to.beTrue()
				end

				-- the gain moves it
				setConVar("gry_sound_volume", "12")
				expect(GryMod.GroundLoopVolume(0)).to.aboutEqual(10 ^ ((12 - 27) / 20), 0.001)
			end
		},
		{
			name = "the loops fade in over a few hundredths of a second: from 0 to the mix's volume",
			func = function(state)
				local fade = GryMod.SoundMix.FadeInSeconds
				expect(fade >= 0.005 and fade <= 0.05).to.beTrue()
				expect(GryMod.SoundMix.FadeIn(0)).to.equal(0)
				expect(GryMod.SoundMix.FadeIn(fade / 2)).to.aboutEqual(0.5, 0.001)
				expect(GryMod.SoundMix.FadeIn(fade)).to.equal(1)
				expect(GryMod.SoundMix.FadeIn(10)).to.equal(1)
				expect(GryMod.SoundMix.FadeIn(-1)).to.equal(0)

				local base = GryMod.SoundMix.Volume("suit/servo_speed_loop_01_underwater.mp3")
				expect(GryMod.UnderwaterLoopVolume(0)).to.equal(0)
				expect(GryMod.UnderwaterLoopVolume(fade)).to.aboutEqual(base, 0.0001)
				expect(GryMod.GroundLoopVolume(0, 0)).to.equal(0)
				expect(GryMod.GroundLoopVolume(0, 1)).to.aboutEqual(GryMod.SoundMix.Volume("suit/servo_speed_loop_01c.mp3"), 0.0001)
			end
		},
		{
			name = "a sprint starts the loop of the right water at volume 0, before Play, and the frame sets the mix's volume",
			func = function(state)
				local ground, underwater = fakeChannel(), fakeChannel()
				local previous1, previous2 = GryMod.SpeedLoops.Get()
				GryMod.SpeedLoops.Set(ground, underwater)

				local ok, err = pcall(function()
					stub(FindMetaTable("Entity"), "WaterLevel", function() return 0 end)
					hook.Run("GryModStartSprinting")
					expect(#ground.calls).to.equal(2)
					expect(ground.calls[1][1]).to.equal("SetVolume")
					expect(ground.calls[1][2]).to.equal(0)
					expect(ground.calls[2][1]).to.equal("Play")
					expect(#underwater.calls).to.equal(0)

					-- the frame: the volume goes on from the mix (the trace is given, not made)
					ground.calls = {}
					underwater.calls = {}
					GryMod.UpdateSpeedLoops(GryMod.SoundMix.Now() + 5, 0)
					local last = ground.calls[#ground.calls]
					expect(last[1]).to.equal("SetVolume")
					expect(last[2]).to.aboutEqual(GryMod.SoundMix.Volume("suit/servo_speed_loop_01c.mp3"), 0.0001)
				end)

				GryMod.SpeedLoops.Set(previous1, previous2)
				assert(ok, err)
			end
		},
		{
			name = "the voices of a mode change come 0.5 s after its sound (the game's delay), not with it",
			func = function(state)
				state.touchedMode = true
				local plays, timers = {}, {}
				stub(GryMod, "PlaySound", function(path) plays[#plays + 1] = path end)
				stub(timer, "Create", function(name, delay, reps, func) timers[#timers + 1] = {name = name, delay = delay, reps = reps, func = func} end)
				stub(timer, "Remove", function() end)

				local cases = {
					{GryMod.Modes.ARMOR, "suit/suit_armor_108.mp3", "suit/suit_maximum_armor.mp3"},
					{GryMod.Modes.SPEED, "suit/suit_speed_activate_07_good.wa.mp3", "suit/suit_maximum_speed.mp3"},
					{GryMod.Modes.STRENGTH, "suit/strengthmode.mp3", "suit/suit_maximum_strength.mp3"}
				}

				for _, entry in ipairs(cases) do
					plays, timers = {}, {}
					LocalPlayer().NanosuitMode = nil
					LocalPlayer():SetNanosuitMode(entry[1], false)
					expect(#plays).to.equal(1)
					expect(Sound(entry[2])).to.equal(plays[1])
					expect(#timers).to.equal(1)
					expect(timers[1].delay).to.equal(0.5)
					expect(timers[1].reps).to.equal(1)
					timers[1].func()
					expect(#plays).to.equal(2)
					expect(plays[2]).to.equal(Sound(entry[3]))
				end
			end
		},
		{
			name = "the cloak voice (modification engaged) comes 0.5 s after the cloak sound",
			func = function(state)
				state.touchedMode = true

				if not IsValid(LocalPlayer():GetViewModel()) then
					return
				end

				local plays, timers = {}, {}
				stub(GryMod, "PlaySound", function(path) plays[#plays + 1] = path end)
				stub(timer, "Create", function(name, delay, reps, func) timers[#timers + 1] = {name = name, delay = delay, func = func} end)
				stub(timer, "Remove", function() end)
				LocalPlayer().NanosuitMode = nil
				LocalPlayer():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(#plays).to.equal(1)
				expect(plays[1]).to.equal(Sound("suit/suit_cloak_chameleon_101_r.mp3"))
				expect(#timers).to.equal(1)
				expect(timers[1].delay).to.equal(0.5)
				timers[1].func()
				expect(plays[2]).to.equal(Sound("suit/suit_modification_engaged.mp3"))
			end
		},
		{
			name = "a mode change before the voice is heard cancels the first voice",
			func = function(state)
				state.touchedMode = true
				local removed, timers = {}, {}
				stub(GryMod, "PlaySound", function() end)
				stub(timer, "Create", function(name, delay, reps, func) timers[#timers + 1] = {name = name, func = func} end)
				stub(timer, "Remove", function(name) removed[#removed + 1] = name end)
				LocalPlayer().NanosuitMode = nil
				LocalPlayer():SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(#timers).to.equal(1)
				-- the next change removes the pending voice (by the name the new timer takes) before it starts its own
				LocalPlayer():SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				expect(#timers).to.equal(2)
				expect(timers[1].name).to.equal(timers[2].name)
				expect(table.HasValue(removed, timers[2].name)).to.beTrue()
			end
		},
		{
			name = "the repair sound and the interface sounds take their volume from the mix",
			func = function(state)
				local channel = fakeChannel()
				local previous = GryMod.RegenSound.GetChannel()
				GryMod.RegenSound.SetChannel(channel)
				receive("gry_start_health_regen")
				GryMod.RegenSound.SetChannel(previous)
				local volumes = {}

				for _, call in ipairs(channel.calls) do
					if call[1] == "SetVolume" then volumes[#volumes + 1] = call[2] end
				end

				expect(#volumes >= 1).to.beTrue()
				expect(volumes[#volumes]).to.aboutEqual(GryMod.SoundMix.Volume("suit/suit_medical_use_new.mp3"), 0.0001)
				expect(volumes[#volumes]).to.aboutEqual(0.25, 0.01)
			end
		},
		{
			name = "the options panel has a slider for the sound level in dB, wired to gry_sound_volume",
			func = function(state)
				local panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(panel)
				local found

				local function walk(p)
					for _, child in ipairs(p:GetChildren()) do
						if child.ClassName == "DNumSlider" and child.Scratch and child.Scratch.m_strConVar == "gry_sound_volume" then
							found = child
						end

						walk(child)
					end
				end

				walk(panel)
				local min, max
				if found then min, max = found:GetMin(), found:GetMax() end
				panel:Remove()
				expect(found ~= nil).to.beTrue()
				expect(min).to.equal(-20)
				expect(max).to.equal(12)
			end
		}
	}
}
