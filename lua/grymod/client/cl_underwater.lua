-- The underwater sounds of the original game (docs/superpowers/plans/2026-11-21-underwater-notes.md): the splash when
-- the head goes under and comes out, the breathing under water (a 4 s cycle), the gasps of a drowning player (the server
-- sends a tick each time it hurts, sv_underwater.lua) and the ambience loop that plays while the head is under. The
-- original has no oxygen gauge and neither does GryMod.
--
-- Nothing runs while the player is on dry land but one check of the water level per frame; under water a timer of a tenth
-- of a second drives the breathing cycle and the loop. Every sound goes through GryMod.PlaySound (the mix, cl_hud.lua),
-- the loop through its own channel at the mix's volume. gry_underwater_fx (client, saved) turns it all off.
GryMod.Underwater = GryMod.Underwater or {}

local U = GryMod.Underwater

local FxConVar = CreateClientConVar("gry_underwater_fx", "1", true, false,
	"Play the original game's underwater sounds (dive in and out, breathing, gasps, ambience loop)")

-- the files (under sound/), in the mix with the levels of the original's events (cl_sound_mix.lua)
U.Files = {
	breath = {
		"grymod/uw_underwater_feedback_01.mp3", "grymod/uw_underwater_feedback_02.mp3", "grymod/uw_underwater_feedback_03.mp3",
		"grymod/uw_underwater_feedback_04.mp3", "grymod/uw_underwater_feedback_05.mp3"
	},
	drown = {
		"grymod/uw_drown_feedback_01.mp3", "grymod/uw_drown_feedback_02.mp3", "grymod/uw_drown_feedback_03.mp3",
		"grymod/uw_drown_feedback_04.mp3", "grymod/uw_drown_feedback_05.mp3", "grymod/uw_drown_feedback_06.mp3",
		"grymod/uw_drown_feedback_07.mp3"
	},
	diveSlow = "grymod/uw_dive_in_slow_01.mp3",
	diveFast = {"grymod/uw_dive_in_fast_01.mp3", "grymod/uw_dive_in_fast_02.mp3", "grymod/uw_dive_in_fast_03.mp3"},
	diveOut = "grymod/uw_dive_out.mp3",
	ambience = "grymod/uw_ambience_loop.wav"
}

-- The breathing cycle of the original (the signed timer of its drowning update): it counts up from 0 and the breath
-- sound plays at 2 s, then it counts down from -0.01 to -2 s where the bubbles come out, then up again from 0.01.
-- So the breath is heard at 2, 6, 10... s and the bubbles are at 4, 8... s.
U.CycleHalf = 2
U.CycleStart = 0.01

-- The state is {t = 0}; returns "breath" or "bubbles" when the step reaches one, nil otherwise.
function U.BreathStep(cycle, dt)
	if cycle.t >= 0 then
		cycle.t = cycle.t + dt

		if cycle.t >= U.CycleHalf then
			cycle.t = -U.CycleStart

			return "breath"
		end
	else
		cycle.t = cycle.t - dt

		if cycle.t <= -U.CycleHalf then
			cycle.t = U.CycleStart

			return "bubbles"
		end
	end

	return nil
end

-- "dive_in" when the head goes under, "dive_out" when it comes out; the first look (nil before) plays nothing, as the
-- original does for a player that loads into the water.
function U.Transition(before, now)
	if before == nil or before == now then
		return nil
	end

	return now and "dive_in" or "dive_out"
end

-- The original plays the slow layer of its dive in event; the fast layers are GryMod's choice for a hard fall (the
-- downward speed in units per second, this or more).
U.FastDiveSpeed = 500

-- fall: the downward speed (positive); chance: a random number from 0 to 1
function U.DiveInFile(fall, chance)
	if fall < U.FastDiveSpeed then
		return U.Files.diveSlow
	end

	local list = U.Files.diveFast

	return list[math.Clamp(math.floor(chance * #list) + 1, 1, #list)]
end

-- A file of the list at random, never the one that played last (the original's "shuffle"): returns the path.
function U.Pick(list, last, chance)
	local index = math.Clamp(math.floor(chance * #list) + 1, 1, #list)

	if list[index] == last then
		index = index % #list + 1
	end

	return list[index]
end

-- the loop's channel (created at the first dive; the tests replace it)
local channel
local loading = false

U.Ambience = {
	Get = function() return channel end,
	Set = function(value) channel = value end
}

-- the volume of the loop: the mix's level, brought up over the first hundredths of a second (a loop that starts at once
-- at its level clicks)
function U.AmbienceVolume(elapsed)
	return GryMod.SoundMix.Volume(U.Files.ambience) * GryMod.SoundMix.FadeIn(elapsed)
end

function U.Enabled()
	return FxConVar:GetBool()
end

local TICK = 0.1
local TIMER = "GryUnderwater"

local state = {submerged = nil, cycle = {t = 0}, since = 0, lastBreath = nil, lastDrown = nil, now = 0}

local function stopLoop()
	if IsValid(channel) then
		channel:SetVolume(0)
		channel:Pause()
	end
end

local function startLoop()
	if not GryMod.SoundsEnabled() then
		return
	end

	if IsValid(channel) then
		channel:SetTime(0)
		channel:SetVolume(0)
		channel:Play()

		return
	end

	if loading then
		return
	end

	-- the channel is created asynchronously: it starts when it is there, if the head is still under
	loading = true

	sound.PlayFile("sound/" .. U.Files.ambience, "noblock noplay", function(created)
		loading = false

		if not IsValid(created) then
			return
		end

		channel = created
		created:EnableLooping(true)

		if state.submerged and U.Enabled() then
			created:SetVolume(0)
			created:Play()
		end
	end)
end

-- Ends the underwater state: the loop and the timer stop (nothing runs on dry land).
local function leave()
	timer.Remove(TIMER)
	stopLoop()
	state.cycle = {t = 0}
	state.since = 0
end

local function enter()
	state.cycle = {t = 0}
	state.since = 0
	startLoop()
	timer.Create(TIMER, TICK, 0, function() U.Tick(TICK) end)
end

-- Once per tick under water: brings the loop up and runs the breathing cycle (no calm breathing while the server is
-- drowning the player: the gasps replace it).
function U.Tick(dt)
	if not state.submerged or not U.Enabled() then
		return
	end

	state.since = state.since + dt

	if IsValid(channel) then
		channel:SetVolume(U.AmbienceVolume(state.since))
	end

	local ply = LocalPlayer()

	if IsValid(ply) and ply:GetNWBool("GryDrowning", false) then
		return
	end

	if U.BreathStep(state.cycle, dt) == "breath" then
		state.lastBreath = U.Pick(U.Files.breath, state.lastBreath, math.random())
		GryMod.PlaySound(Sound(state.lastBreath))
	end
end

-- Looks at the water level (once per frame, from the Think hook below): acts only when the head goes under or comes out.
function U.Poll()
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return
	end

	local alive = ply:Alive()
	local submerged = alive and ply:WaterLevel() >= 3

	if not U.Enabled() then
		if timer.Exists(TIMER) then
			leave()
		end

		-- remembered, so that turning the option on in the water does not play a dive in
		state.submerged = submerged

		return
	end

	local before = state.submerged

	if before == submerged then
		-- the option turned on while the head is under: the loop and the cycle start, without a dive in sound
		if submerged and not timer.Exists(TIMER) then
			enter()
		end

		return
	end

	state.submerged = submerged
	local change = U.Transition(before, submerged)

	if submerged then
		if change == "dive_in" then
			local fall = math.max(0, -ply:GetVelocity().z)
			GryMod.PlaySound(Sound(U.DiveInFile(fall, math.random())))
		end

		enter()

		return
	end

	-- the head is out (or the player died: no splash then)
	if before then
		leave()
	end

	if change == "dive_out" and alive then
		GryMod.PlaySound(Sound(U.Files.diveOut))
	end
end

-- the state back to its start (the tests; a map change keeps the module but not the water)
function U.Reset()
	timer.Remove(TIMER)
	state = {submerged = nil, cycle = {t = 0}, since = 0, lastBreath = nil, lastDrown = nil}
end

-- the server hurt the drowning player: a gasp
net.Receive("gry_drown_tick", function()
	if not U.Enabled() then
		return
	end

	state.lastDrown = U.Pick(U.Files.drown, state.lastDrown, math.random())
	GryMod.PlaySound(Sound(state.lastDrown))
end)

hook.Add("Think", "GryModUnderwater", U.Poll)
