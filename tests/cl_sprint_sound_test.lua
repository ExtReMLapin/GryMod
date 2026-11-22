-- Tests of the speed-sprint sound (cl_sprint_sound.lua and its wiring in cl_sounds.lua), GLuaTest format, client realm. The
-- machine GryMod.SprintSound.Step(state, input, dt) is pure: a table of scenarios feeds it frames and checks the actions it
-- asks for (start, stop, crossfade, volume, halt, stopsound) against what the original game does (the research is in
-- docs/superpowers/plans/2026-11-21-sprint-sound.md). The wiring is tested with recording channels: nothing is listened to.

local saved = {}
local savedConVars = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	if not convar then return end

	if savedConVars[name] == nil then
		savedConVars[name] = convar:GetString()
	end

	convar:SetString(value)
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

-- the frames of a scenario ----------------------------------------------------------------------------------------

local function input(overrides)
	local frame = {speed = true, sprint = true, onGround = true, jumped = false, waterLevel = 0, energy = 80, alive = true, suit = true}

	for key, value in pairs(overrides or {}) do
		frame[key] = value
	end

	return frame
end

-- feeds n frames of dt seconds; returns the new state and every action, each with the frame (1..n) it came at
local function run(state, frame, dt, n)
	local all = {}

	for i = 1, n or 1 do
		local actions
		state, actions = GryMod.SprintSound.Step(state, frame, dt)

		for _, action in ipairs(actions) do
			action.frame = i
			all[#all + 1] = action
		end
	end

	return state, all
end

local function ofType(actions, kind, field, value)
	local found = {}

	for _, action in ipairs(actions) do
		if action.type == kind and (field == nil or action[field] == value) then
			found[#found + 1] = action
		end
	end

	return found
end

-- a state of a player that stands on the ground and has been for a while, not sprinting
local function settled()
	local state = GryMod.SprintSound.New()
	state = run(state, input({sprint = false}), 0.5, 1)

	return state
end

-- a state that has sprinted for a second on the ground (the ground loop at full level)
local function sprinting(overrides)
	local state = settled()
	state = run(state, input(overrides), 0.05, 20)

	return state
end

local function lastVolume(actions, loop)
	local last

	for _, action in ipairs(actions) do
		if action.type == "volume" and action.loop == loop then
			last = action.gain
		end
	end

	return last
end

local function sameTable(a, b)
	if type(a) ~= type(b) then return false end

	if type(a) ~= "table" then return a == b end

	for key, value in pairs(a) do
		if not sameTable(value, b[key]) then return false end
	end

	for key in pairs(b) do
		if a[key] == nil then return false end
	end

	return true
end

return {
	groupName = "GryMod sprint sound (client)",
	beforeEach = function(state)
		setConVar("gry_sounds", "1")
	end,
	afterEach = function(state)
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}

		for name, value in pairs(savedConVars) do
			GetConVar(name):SetString(value)
		end

		savedConVars = {}
	end,
	cases = {
		{
			name = "the module exists with the original's numbers: fades 500/150 ms on the ground loop, none under water, 20 % of the bar",
			func = function(state)
				local SS = GryMod.SprintSound
				expect(SS).toNot.beNil()
				expect(SS.GROUND_FADE_IN).to.equal(0.5)
				expect(SS.GROUND_FADE_OUT).to.equal(0.15)
				expect(SS.UNDERWATER_FADE_IN).to.equal(0)
				expect(SS.UNDERWATER_FADE_OUT).to.equal(0)
				-- 40 of the game's 200 is 20 of GryMod's 100
				expect(SS.ENERGY_MIN).to.equal(20)
				expect(SS.GROUND_SETTLE).to.equal(0.1)
				expect(SS.AIR_GRACE).to.equal(0.5)
				expect(SS.STOP_LENGTH.ground).to.aboutEqual(2.45, 0.01)
				expect(SS.STOP_LENGTH.underwater).to.aboutEqual(2.15, 0.01)
				expect(SS.Quirks.startUnderwaterSwitchesToGround).to.beTrue()
			end
		},
		{
			name = "start on the ground: the ground loop starts, from silence, and fades in over 500 ms",
			func = function(state)
				local s = settled()
				local actions
				s, actions = run(s, input(), 0.05, 1)
				local starts = ofType(actions, "start")
				expect(#starts).to.equal(1)
				expect(starts[1].loop).to.equal("ground")
				expect(starts[1].fadeIn).to.equal(0.5)
				expect(lastVolume(actions, "ground")).to.equal(0)
				expect(#ofType(actions, "stopsound")).to.equal(0)

				-- 5 frames later (0.25 s): half; at 0.5 s: full; no other action while it holds
				local _, more = run(s, input(), 0.05, 5)
				expect(lastVolume(more, "ground")).to.aboutEqual(0.5, 0.001)
				_, more = run(select(1, run(s, input(), 0.05, 5)), input(), 0.05, 5)
				expect(lastVolume(more, "ground")).to.equal(1)

				for _, action in ipairs(more) do
					expect(action.type).to.equal("volume")
				end

				expect(#more).to.equal(5)
			end
		},
		{
			name = "the first sprint frame needs the ground for 0.1 s: no start the instant the player lands",
			func = function(state)
				local s = settled()
				-- a player that was in the air for a second and lands: 0.05 s, 0.1 s on the ground: nothing; 0.15 s: the loop
				s = run(s, input({sprint = false, onGround = false, jumped = true}), 0.05, 1)
				s = run(s, input({sprint = false, onGround = false}), 0.05, 20)
				local actions
				s, actions = run(s, input(), 0.05, 2)
				expect(#ofType(actions, "start")).to.equal(0)
				s, actions = run(s, input(), 0.05, 1)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)
			end
		},
		{
			name = "the loop needs the speed mode, the sprint, and more than 20 of 100 energy: 20 does not start it, 20.5 does",
			func = function(state)
				local _, actions = run(settled(), input({speed = false}), 0.05, 5)
				expect(#ofType(actions, "start")).to.equal(0)
				_, actions = run(settled(), input({sprint = false}), 0.05, 5)
				expect(#ofType(actions, "start")).to.equal(0)
				_, actions = run(settled(), input({energy = 20}), 0.05, 5)
				expect(#ofType(actions, "start")).to.equal(0)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				_, actions = run(settled(), input({energy = 0}), 0.05, 5)
				expect(#ofType(actions, "start")).to.equal(0)
				_, actions = run(settled(), input({energy = 20.5}), 0.05, 5)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)
			end
		},
		{
			name = "end of the sprint: the loop fades out over 150 ms, then is halted once; one stop sound, not repeated",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({sprint = false}), 0.05, 1)
				local stops = ofType(actions, "stop")
				expect(#stops).to.equal(1)
				expect(stops[1].loop).to.equal("ground")
				expect(stops[1].fadeOut).to.equal(0.15)
				local sounds = ofType(actions, "stopsound")
				expect(#sounds).to.equal(1)
				expect(sounds[1].sound).to.equal("ground")
				expect(#ofType(actions, "halt")).to.equal(0)

				-- 0.15 s: down to 0 and halted exactly once
				local more
				s, more = run(s, input({sprint = false}), 0.05, 5)
				expect(#ofType(more, "halt", "loop", "ground")).to.equal(1)
				expect(#ofType(more, "stopsound")).to.equal(0)
				expect(#ofType(more, "stop")).to.equal(0)
				expect(lastVolume(more, "ground")).to.equal(0)
				-- the fade is linear: a third of the way (one frame after the stop) is two thirds of the level
				local _, first = run(sprinting(), input({sprint = false}), 0.05, 2)
				expect(lastVolume(first, "ground")).to.aboutEqual(1 - 0.05 / 0.15, 0.01)

				-- nothing more once it is over
				local _, quiet = run(s, input({sprint = false}), 0.05, 10)
				expect(#quiet).to.equal(0)
			end
		},
		{
			name = "stopping during the fade in fades the level it had reached to 0 over 150 ms (not a full second)",
			func = function(state)
				local s = settled()
				s = run(s, input(), 0.05, 6) -- 0.25 s of the 500 ms: half
				local actions
				s, actions = run(s, input({sprint = false}), 0.05, 1)
				expect(#ofType(actions, "stop")).to.equal(1)
				local more
				s, more = run(s, input({sprint = false}), 0.05, 4)
				expect(#ofType(more, "halt")).to.equal(1)
				expect(lastVolume(more, "ground")).to.equal(0)
			end
		},
		{
			name = "no stop sound when the loop never started (low energy, other mode, no sprint)",
			func = function(state)
				local s = run(settled(), input({energy = 10}), 0.05, 5)
				local _, actions = run(s, input({energy = 10, sprint = false}), 0.05, 3)
				expect(#actions).to.equal(0)
				s = run(settled(), input({speed = false}), 0.05, 5)
				_, actions = run(s, input({speed = false, sprint = false}), 0.05, 3)
				expect(#actions).to.equal(0)
			end
		},
		{
			name = "a jump while sprinting stops the loop at once, with the stop sound; it does not come back in the air",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({onGround = false, jumped = true}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
				local more
				s, more = run(s, input({onGround = false}), 0.05, 40)
				expect(#ofType(more, "start")).to.equal(0)
				expect(#ofType(more, "stopsound")).to.equal(0)
			end
		},
		{
			name = "landing with the key held: the loop starts again 0.1 s after the first frame on the ground, and fades in again",
			func = function(state)
				local s = sprinting()
				s = run(s, input({onGround = false, jumped = true}), 0.05, 1)
				s = run(s, input({onGround = false}), 0.05, 20)
				local actions
				s, actions = run(s, input(), 0.05, 4)
				local starts = ofType(actions, "start")
				expect(#starts).to.equal(1)
				expect(starts[1].frame).to.equal(3)
				expect(starts[1].fadeIn).to.equal(0.5)
				expect(#ofType(actions, "stopsound")).to.equal(0)
			end
		},
		{
			name = "walking off an edge keeps the sound for 0.5 s of air, then stops it",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({onGround = false}), 0.1, 5)
				expect(#ofType(actions, "stop")).to.equal(0)
				s, actions = run(s, input({onGround = false}), 0.1, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound")).to.equal(1)
			end
		},
		{
			name = "there is no fade with the height: in the air the ground loop is never at a level between 0 and its full level except in its fades",
			func = function(state)
				local s = sprinting()
				local _, actions = run(s, input({onGround = true}), 0.05, 10)

				for _, action in ipairs(actions) do
					if action.type == "volume" then
						expect(action.gain).to.equal(1)
					end
				end
			end
		},
		{
			name = "diving during a sprint: the ground loop fades out (150 ms) while the underwater loop starts at once, no fade",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 1)
				local cross = ofType(actions, "crossfade")
				expect(#cross).to.equal(1)
				expect(cross[1].from).to.equal("ground")
				expect(cross[1].to).to.equal("underwater")
				expect(cross[1].fadeOut).to.equal(0.15)
				expect(cross[1].fadeIn).to.equal(0)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				local more
				s, more = run(s, input({waterLevel = 3, onGround = false}), 0.05, 6)
				expect(#ofType(more, "halt", "loop", "ground")).to.equal(1)
				expect(#ofType(more, "crossfade")).to.equal(0)
				expect(lastVolume(more, "underwater")).to.equal(1)
				expect(lastVolume(more, "ground")).to.equal(0)
			end
		},
		{
			name = "the underwater loop reaches its level within the technical ramp, not after 500 ms",
			func = function(state)
				local SS = GryMod.SprintSound
				expect(SS.MIN_RAMP > 0 and SS.MIN_RAMP <= 0.02).to.beTrue()
				local s = sprinting()
				local _, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 2)
				expect(lastVolume(actions, "underwater")).to.equal(1)
			end
		},
		{
			name = "coming back to the surface during a sprint changes nothing: the underwater loop stays",
			func = function(state)
				local s = sprinting()
				s = run(s, input({waterLevel = 3, onGround = false}), 0.05, 10)
				local actions
				s, actions = run(s, input({waterLevel = 2, onGround = false}), 0.05, 10)
				expect(#ofType(actions, "crossfade")).to.equal(0)
				expect(#ofType(actions, "start")).to.equal(0)
				expect(#ofType(actions, "stop")).to.equal(0)
				expect(lastVolume(actions, "underwater")).to.equal(1)
			end
		},
		{
			name = "the stop sound follows the head at the moment of the stop: underwater stop with the head under, ground stop out of it",
			func = function(state)
				local s = sprinting()
				s = run(s, input({waterLevel = 3, onGround = false}), 0.05, 10)
				-- stop with the head still under
				local _, actions = run(s, input({sprint = false, waterLevel = 3, onGround = false}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "underwater")).to.equal(1)
				expect(ofType(actions, "stop", "loop", "underwater")[1].fadeOut).to.equal(0)
				expect(#ofType(actions, "stopsound", "sound", "underwater")).to.equal(1)
				-- stop after the head came out
				_, actions = run(s, input({sprint = false, waterLevel = 2, onGround = false}), 0.05, 1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound", "sound", "underwater")).to.equal(0)
				expect(#ofType(actions, "stop", "loop", "underwater")).to.equal(1)
				-- and on the ground, stopping with the head under (after a dive from a ground start)
				s = sprinting({waterLevel = 0})
				s = run(s, input({waterLevel = 3}), 0.05, 5)
				_, actions = run(s, input({sprint = false, waterLevel = 3}), 0.05, 1)
				expect(#ofType(actions, "stopsound", "sound", "underwater")).to.equal(1)
			end
		},
		{
			name = "a sprint started under water: the underwater loop, then (the original's oddity) the ground loop one frame later",
			func = function(state)
				local SS = GryMod.SprintSound
				local s = settled()
				local actions
				s, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 1)
				-- swimming: no ground needed
				expect(#ofType(actions, "start", "loop", "underwater")).to.equal(1)
				s, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 1)
				local cross = ofType(actions, "crossfade")
				expect(#cross).to.equal(1)
				expect(cross[1].from).to.equal("underwater")
				expect(cross[1].to).to.equal("ground")
				expect(cross[1].fadeIn).to.equal(0.5)
				s, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 10)
				expect(#ofType(actions, "crossfade")).to.equal(0)
				expect(#ofType(actions, "start")).to.equal(0)

				-- with the quirk off: the underwater loop stays
				stub(SS.Quirks, "startUnderwaterSwitchesToGround", false)
				s = settled()
				s, actions = run(s, input({waterLevel = 3, onGround = false}), 0.05, 12)
				expect(#ofType(actions, "start", "loop", "underwater")).to.equal(1)
				expect(#ofType(actions, "crossfade")).to.equal(0)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(0)
			end
		},
		{
			name = "swimming at the surface (head out) sprints without the ground, with the ground loop",
			func = function(state)
				local s = settled()
				local _, actions = run(s, input({waterLevel = 2, onGround = false}), 0.05, 3)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)
			end
		},
		{
			name = "energy falling to 20 during a sprint cuts the loop, plays one stop sound, and the loop stays off while the sprint goes on",
			func = function(state)
				local s = sprinting({energy = 60})
				local actions
				s, actions = run(s, input({energy = 20}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
				s, actions = run(s, input({energy = 12}), 0.05, 40)
				expect(#ofType(actions, "start")).to.equal(0)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				-- the sprint is released, then pressed again with energy: it starts
				s, actions = run(s, input({sprint = false, energy = 50}), 0.05, 2)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				s, actions = run(s, input({energy = 50}), 0.05, 2)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)
			end
		},
		{
			name = "nothing happens at 10 %: the loop plays at 15 and cuts only at 20 (of 100)",
			func = function(state)
				local s = sprinting({energy = 15 + 6})
				local _, actions = run(s, input({energy = 15}), 0.05, 1)
				expect(#ofType(actions, "stop")).to.equal(1)
				s = sprinting({energy = 60})
				_, actions = run(s, input({energy = 25}), 0.05, 5)
				expect(#ofType(actions, "stop")).to.equal(0)
				_, actions = run(s, input({energy = 20.1}), 0.05, 5)
				expect(#ofType(actions, "stop")).to.equal(0)
				_, actions = run(s, input({energy = 10.1 + 20}), 0.05, 5)
				expect(#ofType(actions, "stop")).to.equal(0)
			end
		},
		{
			name = "resuming before the fade out is over restarts the loop from silence (a new playback), with no halt of it",
			func = function(state)
				local s = sprinting()
				s = run(s, input({sprint = false}), 0.05, 1)
				local actions
				s, actions = run(s, input(), 0.05, 1)
				local starts = ofType(actions, "start", "loop", "ground")
				expect(#starts).to.equal(1)
				expect(starts[1].restart).to.beTrue()
				expect(lastVolume(actions, "ground")).to.equal(0)
				local more
				s, more = run(s, input(), 0.05, 12)
				expect(#ofType(more, "halt")).to.equal(0)
				expect(lastVolume(more, "ground")).to.equal(1)
			end
		},
		{
			name = "leaving the speed mode while sprinting stops the loop and plays the stop sound once",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({speed = false}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
				s, actions = run(s, input({speed = false}), 0.05, 20)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				expect(#ofType(actions, "start")).to.equal(0)
			end
		},
		{
			name = "a stop sound that is still playing is not played again; after its length it is (ground and underwater apart)",
			func = function(state)
				local s = sprinting()
				s = run(s, input({sprint = false}), 0.1, 1) -- the first stop sound
				local sounds = 0
				-- a second sprint and stop 1 s later: nothing
				s = run(s, input(), 0.1, 5)
				local actions
				s, actions = run(s, input({sprint = false}), 0.1, 1)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				-- 2.5 s after the first: allowed again
				s = run(s, input({sprint = false}), 0.1, 20)
				s = run(s, input(), 0.1, 5)
				s, actions = run(s, input({sprint = false}), 0.1, 1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
			end
		},
		{
			name = "death: the loop stops with the stop sound of its variant; after the respawn a sprint starts the loop again",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({alive = false}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound", "sound", "ground")).to.equal(1)
				s, actions = run(s, input({alive = false}), 0.05, 20)
				expect(#ofType(actions, "start")).to.equal(0)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				s, actions = run(s, input(), 0.05, 5)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)

				-- an underwater variant plays the underwater stop sound even when the head is out
				s = settled()
				s = run(s, input({waterLevel = 3, onGround = false}), 0.05, 1)
				stub(GryMod.SprintSound.Quirks, "startUnderwaterSwitchesToGround", false)
				_, actions = run(s, input({alive = false, waterLevel = 0}), 0.05, 1)
				expect(#ofType(actions, "stopsound", "sound", "underwater")).to.equal(1)
			end
		},
		{
			name = "the suit going down (panne) stops the loop without a stop sound; it plays again when the suit is back and the sprint goes on",
			func = function(state)
				local s = sprinting()
				local actions
				s, actions = run(s, input({suit = false}), 0.05, 1)
				expect(#ofType(actions, "stop", "loop", "ground")).to.equal(1)
				expect(#ofType(actions, "stopsound")).to.equal(0)
				s, actions = run(s, input({suit = false}), 0.05, 20)
				expect(#ofType(actions, "start")).to.equal(0)
				s, actions = run(s, input(), 0.05, 3)
				expect(#ofType(actions, "start", "loop", "ground")).to.equal(1)
			end
		},
		{
			name = "while the loop holds, each frame asks for one volume per playing loop and nothing else",
			func = function(state)
				local s = sprinting()
				local _, actions = run(s, input(), 0.05, 30)
				expect(#actions).to.equal(30)

				for _, action in ipairs(actions) do
					expect(action.type).to.equal("volume")
					expect(action.loop).to.equal("ground")
				end
			end
		},
		{
			name = "Step is pure: it does not change the state it is given",
			func = function(state)
				local s = sprinting()
				local copy = table.Copy(s)
				local frame = input({sprint = false})
				local frameCopy = table.Copy(frame)
				GryMod.SprintSound.Step(s, frame, 0.05)
				expect(sameTable(s, copy)).to.beTrue()
				expect(sameTable(frame, frameCopy)).to.beTrue()
				local a = select(1, GryMod.SprintSound.Step(s, frame, 0.05))
				local b = select(1, GryMod.SprintSound.Step(s, frame, 0.05))
				expect(sameTable(a, b)).to.beTrue()
			end
		},
		{
			name = "Step with a scratch table advances the state it is given and reuses the action list, with the same result as the pure Step on every frame of a long scenario (the Think hook made about a kilobyte of tables a frame for nothing)",
			func = function(state)
				local SS = GryMod.SprintSound
				local pure = SS.New()
				local inPlace = SS.New()
				local reuse = {actions = {}}
				local actionList = reuse.actions

				-- a scenario with every kind of frame: sprint, jump, dive, energy falling, death, suit down, the mode left
				local frames = {}
				local function add(n, overrides) for _ = 1, n do frames[#frames + 1] = input(overrides) end end

				add(10, {speed = false, sprint = false})
				add(20)
				add(5, {onGround = false})
				add(5, {onGround = false, jumped = true})
				add(20)
				add(10, {waterLevel = 3})
				add(10, {waterLevel = 1})
				add(15, {energy = 18})
				add(10, {energy = 90})
				add(10, {suit = false})
				add(10)
				add(5, {alive = false})
				add(10)
				add(10, {speed = false})
				add(10, {sprint = false})

				for index, frame in ipairs(frames) do
					local dt = 0.01 + (index % 7) * 0.01
					local nextPure, pureActions = SS.Step(pure, frame, dt)
					pure = nextPure

					local returnedState, returnedActions = SS.Step(inPlace, frame, dt, reuse)
					expect(returnedState).to.equal(inPlace)
					expect(returnedActions).to.equal(actionList)
					expect(sameTable(inPlace, pure)).to.beTrue()
					expect(sameTable(returnedActions, pureActions)).to.beTrue()
				end
			end
		},
		{
			name = "Sample fills the table it is given (the Think hook keeps one) with the same frame as a fresh one",
			func = function(state)
				local SS = GryMod.SprintSound
				local ply = {
					NanosuitMode = GryMod.Modes.SPEED,
					IsSprinting = function() return true end,
					GetVelocity = function() return Vector(500, 0, 200) end,
					IsOnGround = function() return false end,
					WaterLevel = function() return 2 end,
					Alive = function() return true end,
					GetNW2Bool = function() return false end,
					IsValid = function() return true end
				}
				local into = {}
				local again = SS.Sample(ply, 55, true, into)
				expect(again).to.equal(into)
				expect(sameTable(into, SS.Sample(ply, 55, true))).to.beTrue()

				-- a second call gives the new facts, none of the old stays
				ply.IsOnGround = function() return true end
				ply.WaterLevel = function() return 0 end
				SS.Sample(ply, 30, true, into)
				expect(sameTable(into, SS.Sample(ply, 30, true))).to.beTrue()
			end
		},
		{
			name = "Sample builds the frame from a player: sprint needs speed over 412 u/s, the mode, the ground and the water",
			func = function(state)
				local SS = GryMod.SprintSound
				local ply = {
					NanosuitMode = GryMod.Modes.SPEED,
					IsSprinting = function() return true end,
					GetVelocity = function() return Vector(500, 0, 0) end,
					IsOnGround = function() return true end,
					WaterLevel = function() return 3 end,
					Alive = function() return true end,
					GetNW2Bool = function() return false end,
					IsValid = function() return true end
				}
				local frame = SS.Sample(ply, 55, true)
				expect(frame.speed).to.beTrue()
				expect(frame.sprint).to.beTrue()
				expect(frame.onGround).to.beTrue()
				expect(frame.jumped).to.beFalse()
				expect(frame.waterLevel).to.equal(3)
				expect(frame.energy).to.equal(55)
				expect(frame.alive).to.beTrue()
				expect(frame.suit).to.beTrue()

				ply.GetVelocity = function() return Vector(100, 0, 0) end
				expect(SS.Sample(ply, 55, true).sprint).to.beFalse()
				ply.GetVelocity = function() return Vector(500, 0, 200) end
				ply.IsOnGround = function() return false end
				-- left the ground going up: a jump; going down: an edge
				expect(SS.Sample(ply, 55, true).jumped).to.beTrue()
				ply.GetVelocity = function() return Vector(500, 0, -50) end
				expect(SS.Sample(ply, 55, true).jumped).to.beFalse()
				expect(SS.Sample(ply, 55, false).jumped).to.beFalse()
				ply.NanosuitMode = GryMod.Modes.ARMOR
				expect(SS.Sample(ply, 55, true).speed).to.beFalse()
				ply.GetNW2Bool = function(self, name) return name == "GryMalfunction" end
				expect(SS.Sample(ply, 55, true).suit).to.beFalse()
			end
		},
		{
			name = "Apply: start sets the volume to 0, rewinds if asked, then plays; volume uses the mix; halt pauses and rewinds",
			func = function(state)
				local SS = GryMod.SprintSound
				local ground, underwater = fakeChannel(), fakeChannel()
				local loops = {ground = ground, underwater = underwater}
				SS.Apply({{type = "start", loop = "ground", fadeIn = 0.5, restart = true}}, loops)
				expect(ground.calls[1][1]).to.equal("SetVolume")
				expect(ground.calls[1][2]).to.equal(0)
				expect(ground.calls[2][1]).to.equal("SetTime")
				expect(ground.calls[2][2]).to.equal(0)
				expect(ground.calls[3][1]).to.equal("Play")
				expect(#underwater.calls).to.equal(0)

				ground.calls = {}
				SS.Apply({{type = "volume", loop = "ground", gain = 0.5}, {type = "volume", loop = "underwater", gain = 1}}, loops)
				expect(ground.calls[1][2]).to.aboutEqual(GryMod.SoundMix.Volume("grymod/suit/servo_speed_loop_01c.wav") * 0.5, 0.0001)
				expect(underwater.calls[1][2]).to.aboutEqual(GryMod.SoundMix.Volume("grymod/suit/servo_speed_loop_01_underwater.wav"), 0.0001)

				ground.calls = {}
				SS.Apply({{type = "halt", loop = "ground"}}, loops)
				expect(ground.calls[1][1]).to.equal("Pause")
				expect(ground.calls[2][1]).to.equal("SetTime")

				-- a crossfade starts the new loop (the old one fades through its volume actions)
				ground.calls, underwater.calls = {}, {}
				SS.Apply({{type = "crossfade", from = "ground", to = "underwater", fadeOut = 0.15, fadeIn = 0}}, loops)
				expect(#ground.calls).to.equal(0)
				expect(underwater.calls[#underwater.calls][1]).to.equal("Play")
				-- a stop is carried by the volume actions: it touches nothing itself
				underwater.calls = {}
				SS.Apply({{type = "stop", loop = "underwater", fadeOut = 0}}, loops)
				expect(#underwater.calls).to.equal(0)
			end
		},
		{
			name = "Apply: with gry_sounds 0 the loops are at volume 0 and the stop sound is not played",
			func = function(state)
				local SS = GryMod.SprintSound
				local ground = fakeChannel()
				local plays = {}
				stub(GryMod, "PlaySound", function(path) plays[#plays + 1] = path end)
				setConVar("gry_sounds", "0")
				SS.Apply({{type = "volume", loop = "ground", gain = 1}}, {ground = ground})
				expect(ground.calls[1][2]).to.equal(0)
			end
		},
		{
			name = "Apply: the stop sounds go through GryMod.PlaySound (the mix), with the files of the game's events",
			func = function(state)
				local SS = GryMod.SprintSound
				local plays = {}
				stub(GryMod, "PlaySound", function(path, scale) plays[#plays + 1] = path end)
				SS.Apply({{type = "stopsound", sound = "ground"}, {type = "stopsound", sound = "underwater"}}, {})
				expect(plays[1]).to.equal(Sound("grymod/suit/servo_speed_stop_fp_2.wav"))
				expect(plays[2]).to.equal(Sound("grymod/suit/servo_speed_stop_01_underwater.wav"))
				expect(file.Exists("sound/grymod/suit/servo_speed_stop_fp_2.wav", "GAME")).to.beTrue()
				expect(file.Exists("sound/grymod/suit/servo_speed_stop_01_underwater.wav", "GAME")).to.beTrue()
			end
		},
		{
			name = "the Think hook runs the machine once a frame and applies its actions; the old start/end hooks are gone",
			func = function(state)
				local SS = GryMod.SprintSound
				local hookFunc = hook.GetTable().Think["GryModSounds"]
				expect(hookFunc).toNot.beNil()
				local steps, applied = {}, {}
				stub(SS, "Step", function(machine, frame, dt)
					steps[#steps + 1] = {frame, dt}

					return machine, {{type = "volume", loop = "ground", gain = 0}}
				end)
				stub(SS, "Apply", function(actions, loops) applied[#applied + 1] = actions end)
				stub(GryMod, "PlaySound", function() end)
				hookFunc()
				expect(#steps).to.equal(1)
				expect(type(steps[1][1].energy)).to.equal("number")
				expect(steps[1][2] >= 0).to.beTrue()
				expect(#applied).to.equal(1)
				expect(hook.GetTable().GryModStartSprinting).to.beNil()
				expect(hook.GetTable().GryModEndSprinting).to.beNil()
			end
		},
		{
			name = "the sprint sound module is sent to the clients and included before cl_sounds.lua; no sound call outside the mix",
			func = function(state)
				local shared = file.Read("autorun/grymod_shared.lua", "LUA")
				expect(shared).toNot.beNil()
				expect(shared:find('AddCSLuaFile("grymod/client/cl_sprint_sound.lua")', 1, true) ~= nil).to.beTrue()
				local a = shared:find('include("grymod/client/cl_sprint_sound.lua")', 1, true)
				local b = shared:find('include("grymod/client/cl_sounds.lua")', 1, true)
				expect(a ~= nil and b ~= nil and a < b).to.beTrue()
				local text = file.Read("grymod/client/cl_sprint_sound.lua", "LUA") or ""
				expect(text:find("surface.PlaySound", 1, true) == nil).to.beTrue()
				expect(text:find("sound.Play(", 1, true) == nil).to.beTrue()
			end
		}
	}
}
