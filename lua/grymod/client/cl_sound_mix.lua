-- The mix of the GryMod sounds: the volume of each file, the one way a sound is played, and the limit of simultaneous
-- armor hits. The original game plays each suit and HUD event at its own level (-9 to -34 dB in its sound bank) and
-- stops an event from playing more than a few times at once (maxpb); played at full volume, as GryMod did, the sounds
-- were far too loud next to the game's own.
--
-- The volume of a file is min(1, 10^((original dB + gain) / 20)): the original level, raised by the gain (gry_sound_volume,
-- in dB, +6 by default, because the engine's 1.0 is already the loudest a sound can be). A sound with no level of the
-- original game (the voices) plays at 1.0.
GryMod.SoundMix = GryMod.SoundMix or {}

local Mix = GryMod.SoundMix

local GainConVar = CreateClientConVar("gry_sound_volume", "6", true, false,
	"Level of the GryMod suit and interface sounds, in dB (the original game's levels plus this gain)", -20, 12)

Mix.MinGain = -20
Mix.MaxGain = 12

-- the level of each file in the original game's sound bank (dB, first-person events). The cry_* ones are GryMod's own
-- interface sounds: the levels are those of the game's equivalent events (the menu appearing -16, disappearing -13, the
-- weapon modification beep -12; cry_error between the key error -30 and the usage error -15, as it is harsh).
Mix.Original = {
	["suit/suit_bullet_impact_01.mp3"] = -9,
	["suit/suit_bullet_impact_02.mp3"] = -9,
	["suit/suit_bullet_impact_03.mp3"] = -9,
	["suit/suit_bullet_impact_05.mp3"] = -9,
	["suit/suit_bullet_impact_06.mp3"] = -9,
	["suit/suit_bullet_impact_07.mp3"] = -9,
	["suit/suit_bullet_impact_09.mp3"] = -9,
	["suit/suit_bullet_impact_10.mp3"] = -9,
	["suit/suit_bullet_impact_11.mp3"] = -9,
	["suit/suit_bullet_impact_13.mp3"] = -9,
	["suit/suit_bullet_impact_14.mp3"] = -9,
	["suit/suit_bullet_impact_15.mp3"] = -9,
	["suit/suit_bullet_impact_16.mp3"] = -9,
	["suit/servo_speed_stop_fp_2.mp3"] = -34,
	["suit/servo_speed_stop_01_underwater.mp3"] = -27,
	["suit/servo_speed_loop_01c.mp3"] = -27,
	["suit/servo_speed_loop_01_underwater.mp3"] = -17,
	["suit/suit_speed_activate_07_good.wa.mp3"] = -23,
	["suit/suit_armor_108.mp3"] = -14,
	["suit/strengthmode.mp3"] = -18,
	["suit/suit_strength_101_r.mp3"] = -18,
	["suit/suit_cloak_chameleon_101_r.mp3"] = -16,
	["suit/strengthjump.mp3"] = -19,
	["suit/suit_medical_use_new.mp3"] = -18,
	["cry_hud_activate.wav"] = -18,
	["cry_hud_reboot.wav"] = -12,
	["cry_hud_malfunction.wav"] = -14,
	["cry_error.wav"] = -26,
	["cry_open.wav"] = -16,
	["cry_close.wav"] = -13,
	["cry_select.wav"] = -12,
	["cry_hover.wav"] = -16,
	-- the underwater sounds (cl_underwater.lua): the level of each event of the game's player foley bank, and for the dive
	-- sounds the level of the layer that plays (the slow dive in and the dive out sit at half their layer's level, -6 dB)
	["grymod/uw_underwater_feedback_01.mp3"] = -29,
	["grymod/uw_underwater_feedback_02.mp3"] = -29,
	["grymod/uw_underwater_feedback_03.mp3"] = -29,
	["grymod/uw_underwater_feedback_04.mp3"] = -29,
	["grymod/uw_underwater_feedback_05.mp3"] = -29,
	["grymod/uw_drown_feedback_01.mp3"] = -15,
	["grymod/uw_drown_feedback_02.mp3"] = -15,
	["grymod/uw_drown_feedback_03.mp3"] = -15,
	["grymod/uw_drown_feedback_04.mp3"] = -15,
	["grymod/uw_drown_feedback_05.mp3"] = -15,
	["grymod/uw_drown_feedback_06.mp3"] = -15,
	["grymod/uw_drown_feedback_07.mp3"] = -15,
	["grymod/uw_dive_in_slow_01.mp3"] = -15,
	["grymod/uw_dive_in_fast_01.mp3"] = -9,
	["grymod/uw_dive_in_fast_02.mp3"] = -9,
	["grymod/uw_dive_in_fast_03.mp3"] = -9,
	["grymod/uw_dive_out.mp3"] = -18,
	["grymod/uw_ambience_loop.wav"] = -16
}

-- how many plays of a kind may be heard together (max, as the game's maxpb), how soon after the last one (gap, s), and how
-- long a play is counted as playing (length, s: the longest file of the kind)
Mix.Limits = {
	armor_hit = {max = 2, gap = 0.06, length = 0.8}
}

local history = {}

-- the gain in dB as the convar holds it (the tests replace this)
function Mix.RawGain()
	return GainConVar:GetFloat()
end

-- the gain, kept in its bounds whatever the config file says
function Mix.Gain()
	return math.Clamp(Mix.RawGain(), Mix.MinGain, Mix.MaxGain)
end

-- the key of a path in the table: no sound/, no capitals, forward slashes
function Mix.Normalize(path)
	path = string.lower(tostring(path or "")):gsub("\\", "/")

	if string.sub(path, 1, 6) == "sound/" then
		path = string.sub(path, 7)
	end

	return path
end

-- the volume (0 to 1) of a file; gain is in dB, the convar's by default
function Mix.Volume(path, gain)
	local level = Mix.Original[Mix.Normalize(path)]

	if level == nil then
		return 1
	end

	return math.min(1, 10 ^ ((level + (gain or Mix.Gain())) / 20))
end

-- the clock of the limits (replaced by the tests)
function Mix.Now()
	return SysTime()
end

-- Whether a play of this kind may start now: it is counted if it does. At most limit.max plays at a time (a play lasts
-- limit.length) and limit.gap seconds after the last one. A kind with no limit always plays.
function Mix.MayPlay(name, now)
	local limit = Mix.Limits[name]

	if not limit then
		return true
	end

	local starts = history[name]

	if not starts then
		starts = {}
		history[name] = starts
	end

	-- the plays that are over (or that come from a clock that went back) are forgotten
	for i = #starts, 1, -1 do
		if now < starts[i] or now - starts[i] >= limit.length then
			table.remove(starts, i)
		end
	end

	if #starts >= limit.max then
		return false
	end

	local last = starts[#starts]

	if last and now - last < limit.gap then
		return false
	end

	starts[#starts + 1] = now

	return true
end

function Mix.ResetLimits()
	history = {}
end

-- the loops start with a short fade, so that they do not click in at full level
Mix.FadeInSeconds = 0.03

-- the share (0 to 1) of the volume of a loop that has been playing for this long
function Mix.FadeIn(elapsed)
	return math.Clamp(elapsed / Mix.FadeInSeconds, 0, 1)
end

-- Plays the file at this volume, from the player: with a level of 0 (SNDLVL_NONE) it is heard the same everywhere, it
-- takes no distance. surface.PlaySound has no volume. (sound.PlayFile would do, but it loads the file at every play.)
function Mix.Emit(path, volume)
	local ply = LocalPlayer()

	if IsValid(ply) then
		ply:EmitSound(path, 0, 100, volume, CHAN_STATIC)

		return true
	end

	-- no player yet: only a full volume sound (a voice) may be played this way
	if volume >= 1 then
		surface.PlaySound(path)

		return true
	end

	return false
end
