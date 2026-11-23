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
	["grymod/suit/servo_speed_stop_fp_2.wav"] = 0.04,
	["grymod/suit/servo_speed_stop_01_underwater.wav"] = 0.09,
	["grymod/suit/servo_speed_loop_01c.wav"] = 0.09,
	["grymod/suit/servo_speed_loop_01_underwater.wav"] = 0.28,
	["grymod/suit/suit_speed_activate_07_good.wav"] = 0.14,
	["grymod/suit/suit_strength_101_r.wav"] = 0.25,
	["grymod/suit/suit_armor_108.wav"] = 0.40,
	["grymod/suit/suit_cloak_chameleon_101_r.wav"] = 0.32,
	["grymod/suit/suit_sound_137.wav"] = 0.225,
	["grymod/suit/suit_medical_use_new.wav"] = 0.25,
	["grymod/suit/suit_usage_error.wav"] = 0.35,
	["grymod/hud/hud_activate_01.wav"] = 0.25,
	["grymod/hud/hud_reboot.wav"] = 0.56, -- the stored file is 1 dB under the sum of the event's two layers: -11 dB, not -12
	["grymod/hud/hud_malfunction_hit.wav"] = 0.41, -- the file was scaled down 0.26 dB: -13.74
	["grymod/menu/modification_menu_appear.wav"] = 0.32,
	["grymod/menu/modification_menu_dissapear.wav"] = 0.45,
	["grymod/menu/preset_navigation_beep_02.wav"] = 0.35,
	["grymod/menu/temperature_beep.wav"] = 0.50,
	["grymod/binoculars/binocular_select.wav"] = 0.32,
	["grymod/binoculars/binocular_deselect.wav"] = 0.32,
	["grymod/binoculars/binocular_ambience.wav"] = 0.056,
	["grymod/binoculars/binocular_zoom_in.wav"] = 0.22,
	["grymod/binoculars/binocular_zoom_out.wav"] = 0.28,
	["grymod/binoculars/binocular_tagged.wav"] = 0.10
}

local voices = {
	"grymod/suit/suit_maximum_armor.wav", "grymod/suit/suit_maximum_speed.wav", "grymod/suit/suit_maximum_strength.wav",
	"grymod/suit/suit_energy_critical.wav", "grymod/suit/suit_modification_engaged.wav"
}

-- The files that were resampled to a valid rate (11025, 22050 or 44100 Hz) and scaled down to stay under full scale
-- (dev_resources/sounds/extract_sounds.py): how many dB the mix's level was raised for them. The armor hits are -10 dB plus this.
local armorHeadroom = {
	["grymod/suit/suit_bullet_impact_fp_05.wav"] = 0.62,
	["grymod/suit/suit_bullet_impact_fp_06.wav"] = 1.27,
	["grymod/suit/suit_bullet_impact_fp_07.wav"] = 0.55,
	["grymod/suit/suit_bullet_impact_fp_09.wav"] = 0.51,
	["grymod/suit/suit_bullet_impact_fp_10.wav"] = 1.19,
	["grymod/suit/suit_bullet_impact_fp_11.wav"] = 1.07,
	["grymod/suit/suit_bullet_impact_fp_13.wav"] = 0.79,
	["grymod/suit/suit_bullet_impact_fp_14.wav"] = 0.36,
	["grymod/suit/suit_bullet_impact_fp_15.wav"] = 0.56,
	["grymod/suit/suit_bullet_impact_fp_16.wav"] = 0.56,
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
			name = "the volumes at +6 dB are the original game's levels (the armor hits -10 dB, the servo stop -34 dB...)",
			func = function(state)
				-- the 13 armor hits (the physics event mat_armor_fp, -10 dB)
				for _, path in ipairs(GryMod.ArmorHitSounds) do
					expectVolume(path, 10 ^ ((-10 + (armorHeadroom[path] or 0) + 6) / 20))
					expect(GryMod.SoundMix.Original[path]).to.aboutEqual(-10 + (armorHeadroom[path] or 0), 0.0051)
				end

				for path, volume in pairs(played) do
					expectVolume(path, volume)
				end
			end
		},
		{
			name = "the volume is min(1, 10^((original dB + gain) / 20)), the gain being an argument",
			func = function(state)
				local path = "grymod/suit/suit_bullet_impact_fp_02.wav" -- -10 dB
				expect(GryMod.SoundMix.Volume(path, 0)).to.aboutEqual(10 ^ (-10 / 20), 0.001)
				expect(GryMod.SoundMix.Volume(path, -20)).to.aboutEqual(10 ^ (-30 / 20), 0.001)
				expect(GryMod.SoundMix.Volume(path, 10)).to.equal(1) -- 0 dB
				expect(GryMod.SoundMix.Volume(path, 12)).to.equal(1) -- +2 dB: capped
				-- a quieter one: the servo stop, -34 dB
				expect(GryMod.SoundMix.Volume("grymod/suit/servo_speed_stop_fp_2.wav", 12)).to.aboutEqual(10 ^ (-22 / 20), 0.001)
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
				local volume = GryMod.SoundMix.Volume("grymod/suit/servo_speed_stop_fp_2.wav", 6)
				expect(GryMod.SoundMix.Volume("sound/grymod/suit/servo_speed_stop_fp_2.wav", 6)).to.equal(volume)
				expect(GryMod.SoundMix.Volume("GRYMOD\\Suit\\Servo_Speed_Stop_FP_2.WAV", 6)).to.equal(volume)
				expect(volume < 1).to.beTrue()
			end
		},
		{
			name = "without a gain argument the volume follows gry_sound_volume, which is kept between -20 and +12",
			func = function(state)
				local path = "grymod/suit/suit_bullet_impact_fp_02.wav"
				setConVar("gry_sound_volume", "0")
				expect(GryMod.SoundMix.Gain()).to.equal(0)
				expect(GryMod.SoundMix.Volume(path)).to.aboutEqual(10 ^ (-10 / 20), 0.001)
				setConVar("gry_sound_volume", "-20")
				expect(GryMod.SoundMix.Volume(path)).to.aboutEqual(10 ^ (-30 / 20), 0.001)
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
				expect(GryMod.PlaySound("grymod/suit/servo_speed_stop_fp_2.wav")).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal("grymod/suit/servo_speed_stop_fp_2.wav")
				expect(calls[1][2]).to.aboutEqual(0.04, 0.01)

				setConVar("gry_sound_volume", "-6")
				GryMod.PlaySound("grymod/suit/servo_speed_stop_fp_2.wav")
				expect(calls[2][2] < calls[1][2]).to.beTrue()

				-- a voice: full volume
				GryMod.PlaySound("grymod/suit/suit_maximum_speed.wav")
				expect(calls[3][2]).to.equal(1)
			end
		},
		{
			name = "GryMod.PlaySound plays nothing with gry_sounds 0",
			func = function(state)
				local calls = 0
				stub(GryMod.SoundMix, "Emit", function() calls = calls + 1 end)
				setConVar("gry_sounds", "0")
				expect(GryMod.PlaySound("grymod/suit/suit_sound_137.wav")).to.beFalse()
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
				GryMod.SoundMix.Emit("grymod/suit/suit_sound_137.wav", 0.22)
				expect(surfaced).to.equal(0)
				expect(#emitted).to.equal(1)
				expect(emitted[1][1]).to.equal("grymod/suit/suit_sound_137.wav")
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
				GryMod.SoundMix.Emit("grymod/suit/suit_maximum_speed.wav", 1)
				expect(#surfaced).to.equal(1)
				GryMod.SoundMix.Emit("grymod/suit/suit_sound_137.wav", 0.22)
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
			name = "armor hits: 8 at the most at a time (the physics event mat_armor_fp has maxpb 8), 60 ms apart at the least",
			func = function(state)
				local limit = GryMod.SoundMix.Limits.armor_hit
				expect(limit.max).to.equal(8)
				expect(limit.gap).to.equal(0.06)
				-- the longest of the 13 files is 0.68 s
				expect(limit.length >= 0.68).to.beTrue()

				expect(GryMod.SoundMix.MayPlay("armor_hit", 10)).to.beTrue()
				-- too close
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.03)).to.beFalse()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.059)).to.beFalse()
				-- far enough: the second one, then up to eight (a 0.07 s rhythm: the eighth comes at 10.49)
				for i = 1, 7 do
					expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + i * 0.07)).to.beTrue()
				end

				-- eight are playing
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10.56)).to.beFalse()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + limit.length - 0.001)).to.beFalse()
				-- the first one is over: a new one may start (and the next must wait for the gap, then for a free place)
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + limit.length + 0.001)).to.beTrue()
				expect(GryMod.SoundMix.MayPlay("armor_hit", 10 + limit.length + 0.01)).to.beFalse()
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
				expect(plays).to.equal(1)

				for i = 1, 7 do
					now = 100 + i * 0.07
					receive("gry_armor_hit_sound") -- plays
				end

				now = 100.56
				receive("gry_armor_hit_sound") -- eight are playing
				now = 100.6
				receive("gry_armor_hit_sound") -- eight are playing
				expect(plays).to.equal(8)
				expect(files).to.equal(8)
				now = 101
				receive("gry_armor_hit_sound") -- they are over
				expect(plays).to.equal(9)
			end
		},
		{
			name = "MayPlay also tells how many plays of the kind are going, the new one included",
			func = function(state)
				local ok, count = GryMod.SoundMix.MayPlay("armor_hit", 50)
				expect(ok).to.beTrue()
				expect(count).to.equal(1)
				ok, count = GryMod.SoundMix.MayPlay("armor_hit", 50.07)
				expect(count).to.equal(2)
				-- a refused play has no count; a kind without a limit counts nothing
				expect(GryMod.SoundMix.MayPlay("armor_hit", 50.08)).to.beFalse()
				ok, count = GryMod.SoundMix.MayPlay("something_else", 50)
				expect(ok).to.beTrue()
				expect(count).to.equal(1)
				-- the first two are over after length seconds: the next one is alone again
				ok, count = GryMod.SoundMix.MayPlay("armor_hit", 51)
				expect(count).to.equal(1)
			end
		},
		{
			name = "stacked armor hits are played quieter: the k-th at the same time at 1/k of the volume (8 at 0.63 peak up to 2.9 of full scale otherwise)",
			func = function(state)
				local limit = GryMod.SoundMix.Limits.armor_hit
				expect(limit.stack).to.equal(1)
				expect(GryMod.SoundMix.StackScale("armor_hit", 1)).to.equal(1)
				expect(GryMod.SoundMix.StackScale("armor_hit", 2)).to.equal(0.5)
				expect(GryMod.SoundMix.StackScale("armor_hit", 8)).to.equal(0.125)
				expect(GryMod.SoundMix.StackScale("something_else", 8)).to.equal(1)
				expect(GryMod.SoundMix.StackScale("armor_hit", nil)).to.equal(1)

				local now = 200
				stub(GryMod.SoundMix, "Now", function() return now end)
				local scales = {}
				stub(GryMod, "PlaySound", function(path, scale) scales[#scales + 1] = scale end)

				for i = 0, 7 do
					now = 200 + i * 0.07
					receive("gry_armor_hit_sound")
				end

				for i = 1, 8 do
					expect(scales[i]).to.aboutEqual(1 / i, 0.0001)
				end

				-- they are over: the next hit is full volume again
				now = 202
				receive("gry_armor_hit_sound")
				expect(scales[9]).to.equal(1)
			end
		},
		{
			name = "PlaySound takes a scale (default 1) that multiplies the volume of the mix",
			func = function(state)
				local calls = {}
				stub(GryMod.SoundMix, "Emit", function(path, volume) calls[#calls + 1] = volume end)
				GryMod.PlaySound("grymod/suit/suit_armor_108.wav")
				GryMod.PlaySound("grymod/suit/suit_armor_108.wav", 0.5)
				GryMod.PlaySound("grymod/suit/suit_armor_108.wav", nil)
				expect(calls[2]).to.aboutEqual(calls[1] / 2, 0.0001)
				expect(calls[3]).to.equal(calls[1])
				-- a voice (volume 1) is scaled too
				GryMod.PlaySound("grymod/suit/suit_maximum_armor.wav", 0.25)
				expect(calls[4]).to.equal(0.25)
			end
		},
		{
			name = "the short fade of the other loops (binoculars, underwater ambience) goes from 0 to the mix's volume in a few hundredths of a second",
			func = function(state)
				local fade = GryMod.SoundMix.FadeInSeconds
				expect(fade >= 0.005 and fade <= 0.05).to.beTrue()
				expect(GryMod.SoundMix.FadeIn(0)).to.equal(0)
				expect(GryMod.SoundMix.FadeIn(fade / 2)).to.aboutEqual(0.5, 0.001)
				expect(GryMod.SoundMix.FadeIn(fade)).to.equal(1)
				expect(GryMod.SoundMix.FadeIn(10)).to.equal(1)
				expect(GryMod.SoundMix.FadeIn(-1)).to.equal(0)
			end
		},
		{
			name = "the speed servo loops are at the mix's volume times the machine's gain (the sprint sound tests are in cl_sprint_sound_test.lua)",
			func = function(state)
				local ground, underwater = fakeChannel(), fakeChannel()
				GryMod.SprintSound.Apply({{type = "volume", loop = "ground", gain = 1}, {type = "volume", loop = "underwater", gain = 0.5}}, {ground = ground, underwater = underwater})
				expect(ground.calls[1][2]).to.aboutEqual(GryMod.SoundMix.Volume("grymod/suit/servo_speed_loop_01c.wav"), 0.0001)
				expect(underwater.calls[1][2]).to.aboutEqual(GryMod.SoundMix.Volume("grymod/suit/servo_speed_loop_01_underwater.wav") / 2, 0.0001)
				-- the gain moves it
				setConVar("gry_sound_volume", "12")
				ground.calls = {}
				GryMod.SprintSound.Apply({{type = "volume", loop = "ground", gain = 1}}, {ground = ground})
				expect(ground.calls[1][2]).to.aboutEqual(10 ^ ((12 - 27) / 20), 0.001)
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
					{GryMod.Modes.ARMOR, "grymod/suit/suit_armor_108.wav", "grymod/suit/suit_maximum_armor.wav"},
					{GryMod.Modes.SPEED, "grymod/suit/suit_speed_activate_07_good.wav", "grymod/suit/suit_maximum_speed.wav"},
					{GryMod.Modes.STRENGTH, "grymod/suit/suit_strength_101_r.wav", "grymod/suit/suit_maximum_strength.wav"}
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
				expect(plays[1]).to.equal(Sound("grymod/suit/suit_cloak_chameleon_101_r.wav"))
				expect(#timers).to.equal(1)
				expect(timers[1].delay).to.equal(0.5)
				timers[1].func()
				expect(plays[2]).to.equal(Sound("grymod/suit/suit_modification_engaged.wav"))
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
				expect(volumes[#volumes]).to.aboutEqual(GryMod.SoundMix.Volume("grymod/suit/suit_medical_use_new.wav"), 0.0001)
				expect(volumes[#volumes]).to.aboutEqual(0.25, 0.01)
			end
		},
		{
			name = "the pitch of a file is its event's pitch (octaves) as a percent: the quick menu +0.3 octave, the binocular lock +0.52, the others 100",
			func = function(state)
				expect(GryMod.SoundMix.Pitch("grymod/menu/modification_menu_appear.wav")).to.equal(123)
				expect(GryMod.SoundMix.Pitch("grymod/menu/modification_menu_dissapear.wav")).to.equal(123)
				expect(GryMod.SoundMix.Pitch("grymod/binoculars/binocular_tagged.wav")).to.equal(143)
				expect(GryMod.SoundMix.Pitch("grymod/suit/suit_armor_108.wav")).to.equal(100)
				expect(GryMod.SoundMix.Pitch("nothing/here.wav")).to.equal(100)
				expect(GryMod.SoundMix.Pitch("sound/GRYMOD/menu/modification_menu_appear.wav")).to.equal(123)

				-- the emit carries it
				local emitted = {}
				stub(FindMetaTable("Entity"), "EmitSound", function(self, ...)
					if self == LocalPlayer() then emitted[#emitted + 1] = {...} end
				end)
				GryMod.PlaySound("grymod/menu/modification_menu_appear.wav")
				expect(emitted[1][3]).to.equal(123)
				GryMod.PlaySound("grymod/suit/suit_armor_108.wav")
				expect(emitted[2][3]).to.equal(100)
			end
		},
		{
			name = "every sound file the Lua names exists; every file under sound/grymod is shipped (resource.AddFile); the first MP3 sounds are gone",
			func = function(state)
				local shared = file.Read("autorun/grymod_shared.lua", "LUA")
				expect(shared ~= nil).to.beTrue()
				local listed = {}

				for path in shared:gmatch('resource%.AddFile%(%s*"([^"]+)"%s*%)') do
					if path:sub(1, 6) == "sound/" then
						listed[path] = true
						expect(file.Exists(path, "GAME")).to.beTrue()
					end
				end

				local missing = {}

				local function walk(dir)
					local files, dirs = file.Find(dir .. "/*", "GAME")

					for _, name in ipairs(files) do
						if not listed[dir .. "/" .. name] then missing[#missing + 1] = dir .. "/" .. name end
					end

					for _, sub in ipairs(dirs) do walk(dir .. "/" .. sub) end
				end

				walk("sound/grymod")
				expect(table.concat(missing, ", ")).to.equal("")

				-- the mix's table and every path written in the client files
				for path in pairs(GryMod.SoundMix.Original) do
					expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
				end

				for _, name in ipairs(file.Find("grymod/client/*.lua", "LUA")) do
					local text = file.Read("grymod/client/" .. name, "LUA") or ""

					for path, ext in text:gmatch('"(grymod/[%w_/]+%.(%a+))"') do
						if ext == "wav" or ext == "mp3" or ext == "ogg" then
							expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
						end
					end
				end

				expect(file.Exists("sound/suit/suit_armor_108.mp3", "GAME")).to.beFalse()
				expect(file.Exists("sound/cry_open.wav", "GAME")).to.beFalse()
				expect(file.Exists("sound/cry_hud_reboot.wav", "GAME")).to.beFalse()
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
		},
		{
			name = "the sound moods: cryvision is the original's (priority 70, 500 ms in and out) and lowers only the categories SoundMoods.xml lowers",
			func = function(state)
				local mood = GryMod.SoundMix.Moods.cryvision
				expect(mood).toNot.beNil()
				expect(mood.priority).to.equal(70)
				expect(mood.fadeIn).to.equal(0.5)
				expect(mood.fadeOut).to.equal(0.5)

				-- the five categories that are not at 1 in the mood (the others are listed at their full volume)
				local expected = {["3rd_weapon_explos"] = 0.7, collision = 0.5, phys_lots = 0.5, veh_special = 0.6, vehicle_sounds = 0.5}
				local count = 0

				for category, volume in pairs(mood.volumes) do
					count = count + 1
					expect(expected[category]).to.aboutEqual(volume, 1e-6)
				end

				expect(count).to.equal(5)
			end
		},
		{
			name = "a mood fades in linearly over its time, from nothing, and the gain of a category is 1 + (volume - 1) * weight; the categories it does not lower stay at 1",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 100
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()
				expect(Mix.MoodGain("collision")).to.equal(1)
				Mix.MoodSet("cryvision", true)
				expect(Mix.MoodGain("collision")).to.equal(1)
				now = 100.25
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.75, 1e-6)
				expect(Mix.MoodGain("3rd_weapon_explos")).to.aboutEqual(0.85, 1e-6)
				expect(Mix.MoodGain("amb")).to.equal(1)
				expect(Mix.MoodGain(nil)).to.equal(1)
				now = 100.5
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.5, 1e-6)
				now = 160
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.5, 1e-6)
				expect(Mix.MoodGain("vehicle_sounds")).to.aboutEqual(0.5, 1e-6)
				expect(Mix.MoodGain("veh_special")).to.aboutEqual(0.6, 1e-6)
				Mix.MoodReset()
			end
		},
		{
			name = "setting a mood that is already going changes nothing (the fade does not start again); switching it off fades out from where it was, at the same rate",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 10
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()
				Mix.MoodSet("cryvision", true)
				now = 10.25
				Mix.MoodSet("cryvision", true)
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.75, 1e-6)
				-- off at half way: 0.25 s to come back to nothing, not 0.5
				Mix.MoodSet("cryvision", false)
				now = 10.375
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.875, 1e-6)
				now = 10.5
				expect(Mix.MoodGain("collision")).to.equal(1)
				now = 11
				expect(Mix.MoodGain("collision")).to.equal(1)
				-- and on again goes down from there
				Mix.MoodSet("cryvision", true)
				now = 11.25
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.75, 1e-6)
				Mix.MoodReset()
				expect(Mix.MoodGain("collision")).to.equal(1)
			end
		},
		{
			name = "of the moods that are on, the one of the highest priority decides; an unknown mood is refused",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 5
				stub(Mix, "Now", function() return now end)
				stub(Mix.Moods, "test_high", {priority = 90, fadeIn = 0.5, fadeOut = 0.5, volumes = {collision = 0.1}})
				stub(Mix.Moods, "test_low", {priority = 10, fadeIn = 0.5, fadeOut = 0.5, volumes = {collision = 0.9, amb = 0.2}})
				Mix.MoodReset()
				Mix.MoodSet("test_low", true)
				Mix.MoodSet("cryvision", true)
				now = 6
				-- cryvision (70) over test_low (10)
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.5, 1e-6)
				Mix.MoodSet("test_high", true)
				now = 7
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.1, 1e-6)
				Mix.MoodSet("test_high", false)
				now = 8
				expect(Mix.MoodGain("collision")).to.aboutEqual(0.5, 1e-6)
				expect(Mix.MoodSet("nope", true)).to.beFalse()
				Mix.MoodReset()
			end
		},
		{
			name = "the category of a sound the engine emits: impacts of the physics folder are collisions, explosions are explosions, the vehicles' own sounds are vehicle sounds; the addon's sounds and the others have none",
			func = function(state)
				local Mix = GryMod.SoundMix
				expect(Mix.CategoryOf("physics/concrete/concrete_impact_hard1.wav")).to.equal("collision")
				expect(Mix.CategoryOf("Physics/Wood/wood_box_impact_hard1.wav")).to.equal("collision")
				expect(Mix.CategoryOf("weapons/explode3.wav")).to.equal("3rd_weapon_explos")
				expect(Mix.CategoryOf("ambient/explosions/explode_4.wav")).to.equal("3rd_weapon_explos")
				expect(Mix.CategoryOf("vehicles/v8/v8_idle_loop1.wav")).to.equal("vehicle_sounds")
				expect(Mix.CategoryOf("weapons/smg1/smg1_fire1.wav")).to.beNil()
				expect(Mix.CategoryOf("grymod/suit/suit_armor_108.wav")).to.beNil()
				expect(Mix.CategoryOf("player/footsteps/concrete1.wav")).to.beNil()
				expect(Mix.CategoryOf(nil)).to.beNil()
			end
		},
		{
			name = "the engine's sound hook lowers the volume of a sound of a lowered category while a mood is on, and touches nothing otherwise",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 1
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				-- no mood: nothing changes, the hook returns nothing
				local data = {SoundName = "physics/concrete/concrete_impact_hard1.wav", Volume = 0.8}
				expect(Mix.DuckEmitted(data)).to.beNil()
				expect(data.Volume).to.equal(0.8)

				Mix.MoodSet("cryvision", true)
				now = 2
				expect(Mix.DuckEmitted(data)).to.beTrue()
				expect(data.Volume).to.aboutEqual(0.4, 1e-6)

				-- a sound script name that resolves to a file in a lowered folder is judged by the file
				local viaScript = {OriginalSoundName = "Physics.ImpactHard", SoundName = "physics/metal/metal_solid_impact_hard1.wav", Volume = 1}
				expect(Mix.DuckEmitted(viaScript)).to.beTrue()
				expect(viaScript.Volume).to.aboutEqual(0.5, 1e-6)

				-- a sound of no lowered category, the addon's own, or no name: untouched
				for _, name in ipairs({"weapons/smg1/smg1_fire1.wav", "grymod/suit/suit_armor_108.wav", ""}) do
					local other = {SoundName = name, Volume = 1}
					expect(Mix.DuckEmitted(other)).to.beNil()
					expect(other.Volume).to.equal(1)
				end

				expect(Mix.DuckEmitted({Volume = 1})).to.beNil()

				-- a sound of a vehicle is a vehicle sound whatever its file
				local car = {SoundName = "ambient/machines/engine1.wav", Volume = 1, Entity = {IsValid = function() return true end, IsVehicle = function() return true end}}
				expect(Mix.DuckEmitted(car)).to.beTrue()
				expect(car.Volume).to.aboutEqual(0.5, 1e-6)

				-- the hook is the game's EntityEmitSound, under one name
				local hooks = hook.GetTable().EntityEmitSound
				expect(hooks and hooks["GRYMODSOUNDMOOD"]).toNot.beNil()
				Mix.MoodReset()
			end
		},
		{
			-- fails without the `cloak` entry of Mix.Moods
			name = "the cloak mood is the original's (SoundMoods.xml: priority 30, one second in and out): the foley, the suit sounds and the first-person weapon handling at 70 %, nothing else",
			func = function(state)
				local mood = GryMod.SoundMix.Moods.cloak
				expect(mood).toNot.beNil()
				expect(mood.priority).to.equal(30)
				expect(mood.fadeIn).to.equal(1)
				expect(mood.fadeOut).to.equal(1)

				local expected = {player_foley = 0.7, hud_suit = 0.7, ["1st_weapon_foley"] = 0.7}
				local count = 0

				for category, volume in pairs(mood.volumes) do
					count = count + 1
					expect(expected[category]).to.aboutEqual(volume, 1e-6)
				end

				expect(count).to.equal(3)
			end
		},
		{
			-- fails without the cloak mood (the gain stays 1)
			name = "the cloak mood goes to 70 % over one second in a straight line, and back over one second from where it was",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 10
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				Mix.MoodSet("cloak", true)
				expect(Mix.MoodGain("player_foley")).to.equal(1)
				now = 10.5
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.85, 1e-6)
				expect(Mix.MoodGain("hud_suit")).to.aboutEqual(0.85, 1e-6)
				expect(Mix.MoodGain("collision")).to.equal(1) -- a category the mood does not lower
				now = 11
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.7, 1e-6)
				now = 30
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.7, 1e-6)

				-- out again: from 0.7 back to 1 in a second
				Mix.MoodSet("cloak", false)
				now = 30.5
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.85, 1e-6)
				now = 31
				expect(Mix.MoodGain("player_foley")).to.equal(1)

				-- out half way in: it goes back from where it was
				Mix.MoodSet("cloak", true)
				now = 31.4
				Mix.MoodSet("cloak", false)
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.88, 1e-6)
				Mix.MoodReset()
			end
		},
		{
			-- fails without Mix.IsFootstepName
			name = "the match rule of a footstep: the files of the game's footsteps and the sound scripts of the surfaces' steps; nothing else",
			func = function(state)
				local Mix = GryMod.SoundMix

				for _, name in ipairs({"player/footsteps/concrete1.wav", "Player/Footsteps/Wood3.wav", "player/pl_step2.wav", "*player/footsteps/grass4.wav",
					"Concrete.StepLeft", "Grass.StepRight", "Metal_Box.StepLeft", "Wood.Stepleft", "NPC_Citizen.FootstepLeft", "Gravel.StepRight"}) do
					expect(Mix.IsFootstepName(name)).to.beTrue()
				end

				for _, name in ipairs({"weapons/smg1/smg1_fire1.wav", "player/pl_fallpain1.wav", "physics/concrete/concrete_impact_hard1.wav", "grymod/suit/suit_armor_108.wav",
					"Concrete.ImpactHard", "Weapon_SMG1.Single", "ambient/footstep_machine.wav", "", nil, 5}) do
					expect(Mix.IsFootstepName(name)).to.beFalse()
				end
			end
		},
		{
			-- fails without the own-foley branch of DuckEmitted
			name = "while the cloak mood is on, the LOCAL player's own footsteps are lowered (and only they): another player's steps, a weapon shot and a sound of no entity are not, and nothing is lowered with no mood",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 1
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				local ply = LocalPlayer()
				local other = {IsValid = function() return true end}

				-- no mood: nothing changes
				local step = {SoundName = "player/footsteps/concrete1.wav", OriginalSoundName = "Concrete.StepLeft", Volume = 0.5, Entity = ply}
				expect(Mix.DuckEmitted(step)).to.beNil()
				expect(step.Volume).to.equal(0.5)

				Mix.MoodSet("cloak", true)
				now = 3
				expect(Mix.DuckEmitted(step)).to.beTrue() -- true only because the data was changed
				expect(step.Volume).to.aboutEqual(0.35, 1e-6)

				-- by the script name alone too
				local byScript = {SoundName = "", OriginalSoundName = "Grass.StepRight", Volume = 1, Entity = ply}
				expect(Mix.DuckEmitted(byScript)).to.beTrue()
				expect(byScript.Volume).to.aboutEqual(0.7, 1e-6)

				-- not the local player's: left alone
				local others = {SoundName = "player/footsteps/concrete1.wav", Volume = 0.5, Entity = other}
				expect(Mix.DuckEmitted(others)).to.beNil()
				expect(others.Volume).to.equal(0.5)
				expect(Mix.DuckEmitted({SoundName = "player/footsteps/concrete1.wav", Volume = 0.5})).to.beNil()

				-- the local player's, but not a footstep
				local shot = {SoundName = "weapons/smg1/smg1_fire1.wav", OriginalSoundName = "Weapon_SMG1.Single", Volume = 1, Entity = ply}
				expect(Mix.DuckEmitted(shot)).to.beNil()
				expect(shot.Volume).to.equal(1)

				-- the other moods' categories still work in the cloak
				local crash = {SoundName = "physics/concrete/concrete_impact_hard1.wav", Volume = 1}
				expect(Mix.DuckEmitted(crash)).to.beNil() -- the cloak mood does not lower collisions
				Mix.MoodReset()
			end
		},
		{
			-- fails without Mix.SuitGain and the factor in Mix.Emit
			name = "the suit's own sounds (grymod/suit, grymod/hud) are played at 70 % in the cloak; the menu, the binoculars and the water are not; a play after the cloak is at its own volume",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 1
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				expect(Mix.SuitCategoryOf("grymod/suit/suit_armor_108.wav")).to.equal("hud_suit")
				expect(Mix.SuitCategoryOf("sound/GryMod/HUD/hud_reboot.wav")).to.equal("hud_suit")
				expect(Mix.SuitCategoryOf("grymod/menu/temperature_beep.wav")).to.beNil()
				expect(Mix.SuitCategoryOf("grymod/binoculars/binocular_select.wav")).to.beNil()
				expect(Mix.SuitCategoryOf("grymod/water/dive_out.wav")).to.beNil()
				expect(Mix.SuitCategoryOf(nil)).to.beNil()

				local emitted = {}
				stub(FindMetaTable("Entity"), "EmitSound", function(self, ...)
					if self == LocalPlayer() then emitted[#emitted + 1] = {...} end
				end)

				expect(Mix.SuitGain("grymod/suit/suit_armor_108.wav")).to.equal(1)
				Mix.Emit("grymod/suit/suit_armor_108.wav", 0.4)
				expect(emitted[1][4]).to.equal(0.4)

				Mix.MoodSet("cloak", true)
				now = 3
				expect(Mix.SuitGain("grymod/suit/suit_armor_108.wav")).to.aboutEqual(0.7, 1e-6)
				expect(Mix.SuitGain("grymod/menu/temperature_beep.wav")).to.equal(1)
				Mix.Emit("grymod/suit/suit_armor_108.wav", 0.4)
				expect(emitted[2][4]).to.aboutEqual(0.28, 1e-6)
				Mix.Emit("grymod/menu/temperature_beep.wav", 0.5)
				expect(emitted[3][4]).to.equal(0.5)

				Mix.MoodSet("cloak", false)
				now = 5
				Mix.Emit("grymod/suit/suit_armor_108.wav", 0.4)
				expect(emitted[4][4]).to.equal(0.4)
				Mix.MoodReset()
			end
		},
		{
			-- fails without the listener of GryMod_ModeChanged and without gry_cloak_foley_quiet
			name = "the mood follows the LOCAL player's camouflage through GryMod_ModeChanged, and only while gry_cloak_foley_quiet is on (default on)",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 1
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				local convar = GetConVar("gry_cloak_foley_quiet")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				setConVar("gry_cloak_foley_quiet", "1") -- (the player's own saved value must not decide the test)
				expect(convar:GetBool()).to.beTrue()

				local listener = hook.GetTable().GryMod_ModeChanged["GRYCLOAKFOLEY"]
				expect(listener).toNot.beNil()

				-- the camouflage: the mood comes in
				listener(LocalPlayer(), GryMod.Modes.CLOAK)
				now = 1.5
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.85, 1e-6)

				-- another mode: it goes out
				listener(LocalPlayer(), GryMod.Modes.ARMOR)
				now = 2.5
				expect(Mix.MoodGain("player_foley")).to.equal(1)

				-- somebody else's suit: nothing
				listener({IsValid = function() return true end}, GryMod.Modes.CLOAK)
				now = 5
				expect(Mix.MoodGain("player_foley")).to.equal(1)

				-- the option off: the camouflage does not lower anything
				setConVar("gry_cloak_foley_quiet", "0")
				listener(LocalPlayer(), GryMod.Modes.CLOAK)
				now = 8
				expect(Mix.MoodGain("player_foley")).to.equal(1)
				expect(Mix.MoodGain("hud_suit")).to.equal(1)

				-- the option turned off while it is on: the mood goes out
				setConVar("gry_cloak_foley_quiet", "1")
				listener(LocalPlayer(), GryMod.Modes.CLOAK)
				now = 10
				expect(Mix.MoodGain("player_foley")).to.aboutEqual(0.7, 1e-6)
				setConVar("gry_cloak_foley_quiet", "0")
				now = 12
				expect(Mix.MoodGain("player_foley")).to.equal(1)
				Mix.MoodReset()
			end
		},
		{
			-- fails if the engine's sound hook stays when no mood is on (no permanent hook)
			name = "the EntityEmitSound hook exists only while a mood is on: added when it starts, removed when the last one is over (or reset)",
			func = function(state)
				local Mix = GryMod.SoundMix
				local now = 1
				stub(Mix, "Now", function() return now end)
				Mix.MoodReset()

				local function present()
					local hooks = hook.GetTable().EntityEmitSound

					return hooks ~= nil and hooks["GRYMODSOUNDMOOD"] ~= nil
				end

				expect(present()).to.beFalse()

				Mix.MoodSet("cloak", true)
				expect(present()).to.beTrue()

				now = 2 -- all the way in
				Mix.MoodSet("cloak", false)
				now = 2.5
				Mix.PruneMoods() -- still fading out: it stays
				expect(present()).to.beTrue()

				now = 3.1
				Mix.PruneMoods()
				expect(present()).to.beFalse()

				Mix.MoodSet("cloak", true)
				expect(present()).to.beTrue()
				Mix.MoodReset()
				expect(present()).to.beFalse()
			end
		}
	}
}
