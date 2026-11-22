-- The sound of the speed-mode sprint, one-to-one with the original game (research and sources:
-- docs/superpowers/plans/2026-11-21-sprint-sound.md). The decision is a pure machine, Step(state, input, dt): it takes the
-- frame of the player (mode, sprint, ground, water, energy) and says what the two loops and the stop sounds must do.
-- cl_sounds.lua feeds it once a frame and applies the actions (Apply) to the BASS channels and to GryMod.PlaySound.
--
-- The original (CNanoSuit, once a frame):
--  * the servo loop is on while the speed mode is active, the sprint flag is set and the energy is above a fifth of the bar;
--  * the sprint flag needs the ground for 0.1 s (or swimming), so a jump (or 0.5 s of air) stops it, and the drain with it;
--  * the ground loop fades in over 500 ms and out over 150 ms; the underwater loop and the stop sounds have no fade;
--  * the variant is chosen by the head: under water at the start the underwater loop, a dive during the sprint switches
--    ground to underwater, coming up changes nothing;
--  * ending the sprint (release, jump, mode change, energy at 20 %) plays ONE stop sound (by the head at that moment).
GryMod.SprintSound = GryMod.SprintSound or {}

local SS = GryMod.SprintSound

-- 40 of the game's 200 energy is 20 of GryMod's 100: at or under it the loop is cut, and it needs more to start
SS.ENERGY_MIN = 20

-- the event fades of the game (suit_speed_use_fp: 500 / 150 ms; the underwater events and the stop sounds have none)
SS.GROUND_FADE_IN = 0.5
SS.GROUND_FADE_OUT = 0.15
SS.UNDERWATER_FADE_IN = 0
SS.UNDERWATER_FADE_OUT = 0

-- BASS does not smooth a change of volume: a loop that starts or stops at once clicks, so a fade of 0 is this long
SS.MIN_RAMP = 0.01

-- the sprint flag of the game: the ground timer must be above 0.1 s; it is reset by a jump and after 0.5 s in the air
SS.GROUND_SETTLE = 0.1
SS.AIR_GRACE = 0.5

-- how long the stop sounds play (a sound that is still playing is not played again, as in the game)
SS.STOP_LENGTH = {ground = 2.45, underwater = 2.15}

-- the speed (squared, units/s) the client counts as moving for the sprint: the server's rule (GryMod.IsSpeedSprinting), which follows the base speeds
-- option (GryMod.Movement.SprintSpeedSqr, sh_movement.lua); this is the old rule's value, kept as the fallback
SS.SPRINT_SPEED_SQR = 170000

-- Quirks of the original that are kept because they are what the game does (set to false to leave them out):
-- a sprint that STARTS under water plays the underwater loop for one frame, then the ground loop (the original's test
-- of the head is on the same side for both loops).
SS.Quirks = SS.Quirks or {startUnderwaterSwitchesToGround = true}

SS.Files = {
	loop = {
		ground = "grymod/suit/servo_speed_loop_01c.wav",
		underwater = "grymod/suit/servo_speed_loop_01_underwater.wav"
	},
	stop = {
		ground = "grymod/suit/servo_speed_stop_fp_2.wav",
		underwater = "grymod/suit/servo_speed_stop_01_underwater.wav"
	}
}

local FADE_IN = {ground = SS.GROUND_FADE_IN, underwater = SS.UNDERWATER_FADE_IN}
local FADE_OUT = {ground = SS.GROUND_FADE_OUT, underwater = SS.UNDERWATER_FADE_OUT}
local LOOPS = {"ground", "underwater"}

local function newLoop()
	return {gain = 0, phase = "off", ramp = 1, rate = 0}
end

-- a new machine: nothing plays, the player stands on the ground
function SS.New()
	return {
		on = false, -- the servo sound is on (the game's flag)
		variant = false, -- the variant that was started is the underwater one (the game's second flag)
		playing = nil, -- the loop that plays now
		groundTime = 0,
		airTime = 0,
		now = 0,
		loops = {ground = newLoop(), underwater = newLoop()},
		stopUntil = {ground = -1, underwater = -1}
	}
end

local function copyState(s)
	local copy = {
		on = s.on, variant = s.variant, playing = s.playing, groundTime = s.groundTime, airTime = s.airTime, now = s.now,
		loops = {}, stopUntil = {ground = s.stopUntil.ground, underwater = s.stopUntil.underwater}
	}

	for _, name in ipairs(LOOPS) do
		local loop = s.loops[name]
		copy.loops[name] = {gain = loop.gain, phase = loop.phase, ramp = loop.ramp, rate = loop.rate}
	end

	return copy
end

-- one loop begins its fade out: it goes from its level to 0 in the event's fade (the level it had reached, in the full time)
local function fadeOut(s, name, halted)
	local loop = s.loops[name]

	if loop.phase ~= "in" and loop.phase ~= "hold" then return false end

	if loop.gain <= 0 then
		loop.phase = "off"
		halted[name] = true
	else
		loop.phase = "out"
		loop.rate = loop.gain / math.max(FADE_OUT[name], SS.MIN_RAMP)
	end

	return true
end

local function startLoop(s, name, actions)
	local loop = s.loops[name]
	loop.phase = "in"
	loop.gain = 0
	loop.ramp = math.max(FADE_IN[name], SS.MIN_RAMP)
	s.playing = name
	actions[#actions + 1] = {type = "start", loop = name, fadeIn = FADE_IN[name], restart = true}
end

-- stops every loop that plays (one "stop" action each); returns whether one did
local function stopLoops(s, actions, halted)
	local any = false

	for _, name in ipairs(LOOPS) do
		if fadeOut(s, name, halted) then
			actions[#actions + 1] = {type = "stop", loop = name, fadeOut = FADE_OUT[name]}
			any = true
		end
	end

	s.playing = nil

	return any
end

-- the stop sound, once, unless the same one is still playing
local function stopSound(s, kind, actions)
	if s.now < s.stopUntil[kind] then return end

	s.stopUntil[kind] = s.now + SS.STOP_LENGTH[kind]
	actions[#actions + 1] = {type = "stopsound", sound = kind}
end

local function switchLoop(s, from, to, actions, halted)
	fadeOut(s, from, halted)
	startLoop(s, to, actions)
	-- startLoop put the action in last place: the crossfade replaces it
	actions[#actions] = {type = "crossfade", from = from, to = to, fadeOut = FADE_OUT[from], fadeIn = FADE_IN[to], restart = true}
end

-- The machine. input: speed (the speed mode is active), sprint (the sprint key is held and the player moves), onGround,
-- jumped (the frame the player left the ground going up), waterLevel (0..3, 3 = the head under), energy (GryMod's 0..100),
-- energyMin (optional, ENERGY_MIN), alive and suit (the suit is up) which default to true. dt in seconds.
-- Returns the new state (the given one is not touched) and the list of actions:
--   {type = "start", loop, fadeIn, restart}   the loop plays from its beginning, from silence
--   {type = "stop", loop, fadeOut}            the loop begins to fade out (its volume actions carry the fade)
--   {type = "crossfade", from, to, fadeOut, fadeIn}   a stop of `from` and a start of `to` at once
--   {type = "volume", loop, gain}             the level of the loop (0..1, times the mix's volume) this frame
--   {type = "halt", loop}                     the loop is silent: pause it and rewind
--   {type = "stopsound", sound}               the one-shot stop sound of the variant ("ground" or "underwater")
-- With `reuse` (a table {actions = {}} that the caller keeps) the given state is advanced in place and the list of actions is `reuse.actions`, emptied
-- first: the Think hook runs this every frame and made a kilobyte of tables each time for nothing. The state and the actions are the same numbers either way.
local scratchHalted = {}

function SS.Step(state, input, dt, reuse)
	local s, actions, halted

	if reuse then
		s, actions, halted = state, reuse.actions, scratchHalted

		for i = #actions, 1, -1 do
			actions[i] = nil
		end

		for i = 1, #LOOPS do
			halted[LOOPS[i]] = nil
		end
	else
		s, actions, halted = copyState(state), {}, {}
	end

	dt = math.max(dt or 0, 0)
	s.now = s.now + dt

	-- the fades that are running
	for _, name in ipairs(LOOPS) do
		local loop = s.loops[name]

		if loop.phase == "in" then
			loop.gain = loop.gain + dt / loop.ramp

			if loop.gain >= 1 - 1e-9 then
				loop.gain = 1
				loop.phase = "hold"
			end
		elseif loop.phase == "out" then
			loop.gain = loop.gain - loop.rate * dt

			if loop.gain <= 1e-9 then
				loop.gain = 0
				loop.phase = "off"
				halted[name] = true
			end
		end
	end

	-- the ground timers of the player (CPlayer::UpdateStats): the time on the ground, reset by a jump or by 0.5 s of air
	if input.onGround then
		s.groundTime = s.groundTime + dt
		s.airTime = 0
	else
		s.airTime = s.airTime + dt

		if s.airTime > SS.AIR_GRACE or input.jumped then
			s.groundTime = 0
		end
	end

	local waterLevel = input.waterLevel or 0
	local headUnder = waterLevel >= 3
	local swimming = waterLevel >= 2
	local flag = input.sprint == true and (s.groundTime > SS.GROUND_SETTLE or swimming)
	local minimum = input.energyMin or SS.ENERGY_MIN
	local energy = input.energy or 0

	if input.alive == false then
		-- death: the loop stops, with the stop sound of the variant that was started
		if s.on then
			stopLoops(s, actions, halted)
			stopSound(s, s.variant and "underwater" or "ground", actions)
			s.on = false
		end
	elseif input.suit == false then
		-- the suit is down: silent stop (the original returns at once and says nothing: choice)
		if s.on then
			stopLoops(s, actions, halted)
			s.on = false
		end
	elseif not (input.speed and flag) or energy <= minimum then
		-- the sprint is over (key, jump, mode change) or the energy is at 20 %: the loop stops, once, with the stop sound
		-- chosen by the head at this moment
		if s.on then
			stopLoops(s, actions, halted)
			stopSound(s, headUnder and "underwater" or "ground", actions)
			s.on = false
		end
	elseif not s.on then
		s.on = true
		s.variant = headUnder

		startLoop(s, headUnder and "underwater" or "ground", actions)
	elseif headUnder then
		if not s.variant then
			-- a dive during the sprint: the ground loop goes, the underwater one starts
			if s.playing ~= "underwater" then
				switchLoop(s, "ground", "underwater", actions, halted)
			end
		elseif SS.Quirks.startUnderwaterSwitchesToGround and s.playing ~= "ground" then
			-- the oddity of the original: started under water, the loop goes back to the ground one a frame later
			switchLoop(s, "underwater", "ground", actions, halted)
		end
	end

	-- the level of every loop that plays or has just stopped
	for _, name in ipairs(LOOPS) do
		local loop = s.loops[name]

		if loop.phase ~= "off" or halted[name] then
			actions[#actions + 1] = {type = "volume", loop = name, gain = loop.gain}
		end

		if halted[name] then
			actions[#actions + 1] = {type = "halt", loop = name}
		end
	end

	return s, actions
end

-- the frame of the player for the machine; wasOnGround: whether the previous frame was on the ground (a jump leaves it going up)
-- `into` (optional) is a table of an earlier call, filled again instead of making a new one.
function SS.Sample(ply, energy, wasOnGround, into)
	local velocity = ply:GetVelocity()
	local onGround = ply:IsOnGround()
	local minimum = GryMod.SprintLoopMinimum and GryMod.SprintLoopMinimum() or SS.ENERGY_MIN
	local frame = into or {}

	frame.speed = ply.NanosuitMode == GryMod.Modes.SPEED
	frame.sprint = ply:IsSprinting() == true and velocity:LengthSqr() > (GryMod.Movement and GryMod.Movement.SprintSpeedSqr() or SS.SPRINT_SPEED_SQR)
	frame.onGround = onGround
	frame.jumped = wasOnGround == true and not onGround and velocity.z > 0
	frame.waterLevel = ply:WaterLevel()
	frame.energy = energy
	frame.energyMin = minimum
	frame.alive = ply:Alive()
	frame.suit = not ply:GetNW2Bool("GryMalfunction", false)

	return frame
end

-- Applies the actions to the channels of the loops ({ground = channel, underwater = channel}; a missing or invalid one is
-- skipped: they are created a moment after the start) and plays the stop sounds through the mix.
function SS.Apply(actions, loops)
	local enabled = GryMod.SoundsEnabled()

	for _, action in ipairs(actions) do
		local kind = action.type
		local channel = loops and loops[action.loop or action.to]

		if kind == "start" or kind == "crossfade" then
			if IsValid(channel) then
				channel:SetVolume(0)

				if action.restart then
					channel:SetTime(0)
				end

				channel:Play()
			end
		elseif kind == "volume" then
			if IsValid(channel) then
				channel:SetVolume(enabled and GryMod.SoundMix.Volume(SS.Files.loop[action.loop]) * action.gain or 0)
			end
		elseif kind == "halt" then
			if IsValid(channel) then
				channel:Pause()
				channel:SetTime(0)
			end
		elseif kind == "stopsound" then
			GryMod.PlaySound(Sound(SS.Files.stop[action.sound]))
		end
	end
end
