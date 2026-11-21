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

-- the level of each file in the original game's sound banks (dB, first-person events), the files being the game's own
-- samples at their own level (tools/extract_sounds.py; sound/grymod/{suit,hud,menu,binoculars}). The armor hits are the
-- physics event mat_armor_fp (-10 dB) that Client:OnHit plays in the single-player game, the quick menu sounds the HUD's
-- own events (modification_menu_appear -16, disappear -13, preset_navigation_beep -15, temperature_beep -12) and the
-- error beep suit_usage_error (-15). hud_reboot.wav is the sum of the event's two layers stored 1 dB lower (its peak
-- would pass full scale): -11 dB instead of the event's -12.
Mix.Original = {
	["grymod/suit/suit_bullet_impact_fp_02.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_03.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_04.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_05.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_06.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_07.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_09.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_10.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_11.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_13.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_14.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_15.wav"] = -10,
	["grymod/suit/suit_bullet_impact_fp_16.wav"] = -10,
	["grymod/suit/servo_speed_stop_fp_2.wav"] = -34,
	["grymod/suit/servo_speed_stop_01_underwater.wav"] = -27,
	["grymod/suit/servo_speed_loop_01c.wav"] = -27,
	["grymod/suit/servo_speed_loop_01_underwater.wav"] = -17,
	["grymod/suit/suit_speed_activate_07_good.wav"] = -23,
	["grymod/suit/suit_armor_108.wav"] = -14,
	["grymod/suit/suit_strength_101_r.wav"] = -18,
	["grymod/suit/suit_cloak_chameleon_101_r.wav"] = -16,
	["grymod/suit/suit_sound_137.wav"] = -19,
	["grymod/suit/suit_medical_use_new.wav"] = -18,
	["grymod/suit/suit_usage_error.wav"] = -15,
	["grymod/hud/hud_activate_01.wav"] = -18,
	["grymod/hud/hud_reboot.wav"] = -11,
	["grymod/hud/hud_malfunction_hit.wav"] = -14,
	["grymod/menu/modification_menu_appear.wav"] = -16,
	["grymod/menu/modification_menu_dissapear.wav"] = -13,
	["grymod/menu/preset_navigation_beep_02.wav"] = -15,
	["grymod/menu/temperature_beep.wav"] = -12,
	-- the binoculars (not played yet): binocular_select / deselect -16, ambience (loop) -31, zoom in -19, zoom out -17,
	-- binocular_target_locked (the tagged file) -26
	["grymod/binoculars/binocular_select.wav"] = -16,
	["grymod/binoculars/binocular_deselect.wav"] = -16,
	["grymod/binoculars/binocular_ambience.wav"] = -31,
	["grymod/binoculars/binocular_zoom_in.wav"] = -19,
	["grymod/binoculars/binocular_zoom_out.wav"] = -17,
	["grymod/binoculars/binocular_tagged.wav"] = -26,
	-- the underwater sounds (cl_underwater.lua): the level of each event of the game's player foley bank, and for the dive
	-- sounds the level of the layer that plays (the slow dive in and the dive out sit at half their layer's level, -6 dB)
	["grymod/water/underwater_feedback_01.wav"] = -29,
	["grymod/water/underwater_feedback_02.wav"] = -29,
	["grymod/water/underwater_feedback_03.wav"] = -29,
	["grymod/water/underwater_feedback_04.wav"] = -29,
	["grymod/water/underwater_feedback_05.wav"] = -29,
	["grymod/water/drown_feedback_01.wav"] = -15,
	["grymod/water/drown_feedback_02.wav"] = -15,
	["grymod/water/drown_feedback_03.wav"] = -15,
	["grymod/water/drown_feedback_04.wav"] = -15,
	["grymod/water/drown_feedback_05.wav"] = -15,
	["grymod/water/drown_feedback_06.wav"] = -15,
	["grymod/water/drown_feedback_07.wav"] = -15,
	["grymod/water/dive_in_slow_01.wav"] = -15,
	["grymod/water/dive_in_fast_01.wav"] = -9,
	["grymod/water/dive_in_fast_02.wav"] = -9,
	["grymod/water/dive_in_fast_03.wav"] = -9,
	["grymod/water/dive_out.wav"] = -17.9,
	["grymod/water/ambience_underwater_loop_02.wav"] = -16
}

-- the pitch of the events that are not at the sample's own pitch, in octaves (the game's event property): the quick menu's
-- appear and disappear +0.3, the binocular lock +0.52. EmitSound takes it as a percent (2^octaves).
Mix.PitchOctaves = {
	["grymod/menu/modification_menu_appear.wav"] = 0.3,
	["grymod/menu/modification_menu_dissapear.wav"] = 0.3,
	["grymod/binoculars/binocular_tagged.wav"] = 0.52,
	-- the underwater ambience loop (event ambience_underwater): a loop channel, see GryMod.Underwater
	["grymod/water/ambience_underwater_loop_02.wav"] = -0.75
}

-- how many plays of a kind may be heard together (max, as the game's maxpb: mat_armor_fp has 8), how soon after the last
-- one (gap, s), how long a play is counted as playing (length, s: the longest file of the kind, 0.68 s) and how much
-- quieter the plays that stack are (stack: the k-th play going at once is played at k^-stack of its volume).
-- The armor hits peak at 0 dBFS and the mix plays them at 0.63: measured on the 13 files, two hits at once reach 1.26 of
-- full scale, four 1.7 to 2.5, eight 2 to 2.9 (clipped by the engine). With 1/k the sum of a dense burst stays at about
-- 1.0 (its median) and a hit alone, or after the others are over, is at its own volume.
Mix.Limits = {
	armor_hit = {max = 8, gap = 0.06, length = 0.7, stack = 1}
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

-- the pitch of a file as EmitSound takes it (percent, 100 = the sample's own)
function Mix.Pitch(path)
	local octaves = Mix.PitchOctaves[Mix.Normalize(path)]

	if octaves == nil then
		return 100
	end

	return math.Round(100 * 2 ^ octaves)
end

-- the playback rate of a file (1 = the sample's own), for the channels that are not played with EmitSound (the loops)
function Mix.Rate(path)
	local octaves = Mix.PitchOctaves[Mix.Normalize(path)]

	if octaves == nil then
		return 1
	end

	return 2 ^ octaves
end

-- the clock of the limits (replaced by the tests)
function Mix.Now()
	return SysTime()
end

-- Whether a play of this kind may start now: it is counted if it does, and the second result is how many plays of the
-- kind are going, this one included. At most limit.max plays at a time (a play lasts limit.length) and limit.gap seconds
-- after the last one. A kind with no limit always plays (and counts as 1).
function Mix.MayPlay(name, now)
	local limit = Mix.Limits[name]

	if not limit then
		return true, 1
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

	return true, #starts
end

-- the volume factor of the k-th play of a kind going at once (1 for a kind without a stack rule)
function Mix.StackScale(name, count)
	local limit = Mix.Limits[name]

	if not limit or not limit.stack or not count or count < 1 then
		return 1
	end

	return count ^ -limit.stack
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
		ply:EmitSound(path, 0, Mix.Pitch(path), volume, CHAN_STATIC)

		return true
	end

	-- no player yet: only a full volume sound (a voice) may be played this way
	if volume >= 1 then
		surface.PlaySound(path)

		return true
	end

	return false
end
