-- Tests of the loops that go with a state of the suit (GryMod.SuitLoops, cl_sounds.lua), GLuaTest format, client realm: the failure sound goes on
-- while the suit is down, and the camouflage plays its loop (hud_cloak_feedback) while cloaked. The channels are recording stand-ins: nothing is played,
-- no file is loaded (the loops are given a channel before they begin, so the loader is never asked). Everything a case changes is put back in
-- afterEach AND in a pcall.

local L = GryMod.SuitLoops
local Modes = GryMod.Modes

-- a channel that records what it is asked
local function fakeChannel()
	local c = {calls = {}, volume = nil, valid = true}

	c.IsValid = function() return c.valid end
	c.SetTime = function(_, t) c.calls[#c.calls + 1] = "time:" .. tostring(t) end
	c.SetVolume = function(_, v) c.volume = v; c.calls[#c.calls + 1] = "volume" end
	c.Play = function() c.calls[#c.calls + 1] = "play" end
	c.Pause = function() c.calls[#c.calls + 1] = "pause" end
	c.EnableLooping = function() end

	return c
end

local function has(calls, name)
	for _, call in ipairs(calls) do
		if call == name then
			return true
		end
	end

	return false
end

local saved

local function restore()
	if not saved then
		return
	end

	for _, loop in pairs(L.State) do
		L.End(loop)
		loop.channel = nil
	end

	if GryMod.FlashBoot then
		GryMod.FlashBoot.Malfunctioning = saved.malfunctioning
	end

	LocalPlayer().NanosuitMode = saved.mode
	GetConVar("gry_sound_malfunction_loop"):SetString(saved.malfunctionOption)
	GetConVar("gry_sound_cloak_loop"):SetString(saved.cloakOption)
	GetConVar("gry_sounds"):SetString(saved.sounds)
	saved = nil
end

return {
	groupName = "GryMod suit loops (malfunction, camouflage)",
	beforeEach = function(state)
		saved = {
			malfunctioning = GryMod.FlashBoot and GryMod.FlashBoot.Malfunctioning,
			mode = LocalPlayer().NanosuitMode,
			malfunctionOption = GetConVar("gry_sound_malfunction_loop"):GetString(),
			cloakOption = GetConVar("gry_sound_cloak_loop"):GetString(),
			sounds = GetConVar("gry_sounds"):GetString()
		}

		GetConVar("gry_sound_malfunction_loop"):SetString("1")
		GetConVar("gry_sound_cloak_loop"):SetString("1")
		GetConVar("gry_sounds"):SetString("1")
	end,
	afterEach = function(state)
		pcall(restore)
	end,
	cases = {
		{
			-- fails without Loops.Phase, or with a branch of it changed
			name = "Phase: idle when nothing is wanted, stop when the state is over, run once started, start when its time has come and the channel is ready, else wait",
			func = function()
				local loop = {wanted = false, started = false, startAt = 10}
				expect(L.Phase(loop, 11, true, true)).to.equal("idle")

				loop.wanted = true
				expect(L.Phase(loop, 11, false, true)).to.equal("stop")
				expect(L.Phase(loop, 9, true, true)).to.equal("wait") -- not yet: the one-shot is still playing
				expect(L.Phase(loop, 11, true, false)).to.equal("wait") -- the channel is still loading
				expect(L.Phase(loop, 11, true, true)).to.equal("start")

				loop.started = true
				expect(L.Phase(loop, 11, true, true)).to.equal("run")
				expect(L.Phase(loop, 11, false, true)).to.equal("stop")
			end
		},
		{
			-- fails without the delay of the malfunction loop (it would play over the one-shot), or with a delay for the camouflage
			name = "the malfunction loop starts after the one-shot (1.97 s), the camouflage loop at once",
			func = function()
				expect(L.DELAY.malfunction).to.equal(1.97)
				expect(L.DELAY.cloak).to.equal(0)

				local loop = L.State.malfunction
				loop.channel = fakeChannel()
				local now = GryMod.SoundMix.Now()
				GryMod.FlashBoot.Malfunctioning = function() return true end

				expect(L.Begin(loop)).to.beTrue()
				expect(loop.wanted).to.beTrue()
				expect(loop.startAt >= now + 1.97 - 0.01).to.beTrue()
				expect(L.Begin(loop)).to.beFalse() -- already wanted: left as it is
			end
		},
		{
			-- fails without Loops.Step doing what each phase asks of the channel
			name = "Step plays the channel from its start at the time, raises its volume with the mix level, and pauses it at silence when the state ends",
			func = function()
				local loop = L.State.cloak
				local channel = fakeChannel()
				loop.channel = channel

				L.Begin(loop)
				local t0 = loop.startAt

				expect(L.Step(loop, t0 - 1, true)).to.equal("wait")
				expect(has(channel.calls, "play")).to.beFalse()

				expect(L.Step(loop, t0, true)).to.equal("start")
				expect(has(channel.calls, "play")).to.beTrue()
				expect(has(channel.calls, "time:0")).to.beTrue()
				expect(channel.volume).to.equal(0) -- it starts from silence

				expect(L.Step(loop, t0 + 1, true)).to.equal("run")
				expect(channel.volume).to.equal(GryMod.SoundMix.Volume(loop.path)) -- the fade-in is over
				expect(channel.volume > 0).to.beTrue()

				expect(L.Step(loop, t0 + 2, false)).to.equal("stop")
				expect(channel.volume).to.equal(0)
				expect(has(channel.calls, "pause")).to.beTrue()
				expect(loop.wanted).to.beFalse()
				expect(loop.started).to.beFalse()
			end
		},
		{
			-- fails without the suit gain in Loops.Step (the loop would stay at full level in the camouflage)
			name = "a suit loop is lowered with the cloak mood (70 % of its level, the mood's fade) and back to its own level when the mood is over",
			func = function()
				local Mix = GryMod.SoundMix
				local now = 50
				local realNow = Mix.Now
				Mix.Now = function() return now end

				local ok, err = pcall(function()
					Mix.MoodReset()

					local loop = L.State.cloak
					local channel = fakeChannel()
					loop.channel = channel
					L.Begin(loop)
					local t0 = loop.startAt
					L.Step(loop, t0, true)

					L.Step(loop, t0 + 1, true)
					expect(channel.volume).to.aboutEqual(Mix.Volume(loop.path), 1e-9)

					Mix.MoodSet("cloak", true)
					now = 51 -- a second: the mood is all the way in
					L.Step(loop, t0 + 2, true)
					expect(channel.volume).to.aboutEqual(Mix.Volume(loop.path) * 0.7, 1e-9)

					Mix.MoodSet("cloak", false)
					now = 53
					L.Step(loop, t0 + 3, true)
					expect(channel.volume).to.aboutEqual(Mix.Volume(loop.path), 1e-9)
				end)

				Mix.Now = realNow
				Mix.MoodReset()
				assert(ok, err)
			end
		},
		{
			-- fails if the loop keeps a hook with nothing playing, or has none while it plays
			name = "the Think hook of a loop exists from its beginning to its end, and not otherwise",
			func = function()
				local loop = L.State.cloak
				loop.channel = fakeChannel()
				local name = "GrySuitLoop_cloak"
				expect(hook.GetTable().Think[name]).to.beNil()

				L.Begin(loop)
				expect(hook.GetTable().Think[name]).to.beA("function")

				L.End(loop)
				expect(hook.GetTable().Think[name]).to.beNil()
			end
		},
		{
			-- fails if the malfunction loop does not follow the HUD's malfunction state, the player's life, the sounds or its own switch
			name = "KeepOn (malfunction): needs the HUD malfunction state, sounds on, its switch on",
			func = function()
				local boot = GryMod.FlashBoot
				boot.Malfunctioning = function() return true end
				expect(L.KeepOn("malfunction")).to.beTrue()

				boot.Malfunctioning = function() return false end
				expect(L.KeepOn("malfunction")).to.beFalse()

				boot.Malfunctioning = function() return true end
				GetConVar("gry_sound_malfunction_loop"):SetString("0")
				expect(L.KeepOn("malfunction")).to.beFalse()
				GetConVar("gry_sound_malfunction_loop"):SetString("1")

				GetConVar("gry_sounds"):SetString("0")
				expect(L.KeepOn("malfunction")).to.beFalse()
			end
		},
		{
			-- fails if the camouflage loop does not follow the player's mode, its switch or the sounds
			name = "KeepOn (cloak): needs the camouflage mode, sounds on, its switch on",
			func = function()
				local ply = LocalPlayer()
				ply.NanosuitMode = Modes.CLOAK
				expect(L.KeepOn("cloak")).to.beTrue()

				ply.NanosuitMode = Modes.ARMOR
				expect(L.KeepOn("cloak")).to.beFalse()

				ply.NanosuitMode = Modes.CLOAK
				GetConVar("gry_sound_cloak_loop"):SetString("0")
				expect(L.KeepOn("cloak")).to.beFalse()
				GetConVar("gry_sound_cloak_loop"):SetString("1")

				GetConVar("gry_sounds"):SetString("0")
				expect(L.KeepOn("cloak")).to.beFalse()
			end
		},
		{
			-- fails without the listener on GryMod_HUDEvent, or if it starts the loop when the HUD is not in malfunction
			name = "the events lost and malfunction begin the malfunction loop when the HUD is in malfunction; other events, or no malfunction, do not",
			func = function()
				local listener = hook.GetTable().GryMod_HUDEvent and hook.GetTable().GryMod_HUDEvent["GRYSUITLOOPS"]
				expect(listener).to.beA("function")
				local loop = L.State.malfunction
				loop.channel = fakeChannel()

				GryMod.FlashBoot.Malfunctioning = function() return false end
				listener("lost", {})
				expect(loop.wanted).to.beFalse()

				GryMod.FlashBoot.Malfunctioning = function() return true end
				listener("armor_hit", {})
				listener("reboot", {})
				expect(loop.wanted).to.beFalse()

				listener("lost", {})
				expect(loop.wanted).to.beTrue()
				L.End(loop)

				listener("malfunction", {seconds = 5})
				expect(loop.wanted).to.beTrue()
			end
		},
		{
			-- fails without the listener on GryMod_ModeChanged
			name = "going to the camouflage begins its loop; another mode, or another player's change, does not",
			func = function()
				local listener = hook.GetTable().GryMod_ModeChanged and hook.GetTable().GryMod_ModeChanged["GRYSUITLOOPS"]
				expect(listener).to.beA("function")
				local ply = LocalPlayer()
				local loop = L.State.cloak
				loop.channel = fakeChannel()

				ply.NanosuitMode = Modes.SPEED
				listener(ply, Modes.SPEED, Modes.ARMOR, "player")
				expect(loop.wanted).to.beFalse()

				ply.NanosuitMode = Modes.CLOAK
				listener({}, Modes.CLOAK, Modes.ARMOR, "player")
				expect(loop.wanted).to.beFalse()

				listener(ply, Modes.CLOAK, Modes.ARMOR, "player")
				expect(loop.wanted).to.beTrue()
			end
		},
		{
			-- fails if the loop goes on after the mode left the camouflage, with no event but the Think hook
			name = "the loop ends by itself when the state ends (the mode changes), from its own frame hook",
			func = function()
				local ply = LocalPlayer()
				local loop = L.State.cloak
				local channel = fakeChannel()
				loop.channel = channel
				ply.NanosuitMode = Modes.CLOAK
				L.Begin(loop)
				local frame = hook.GetTable().Think["GrySuitLoop_cloak"]
				expect(frame).to.beA("function")

				ply.NanosuitMode = Modes.ARMOR
				frame()
				expect(loop.wanted).to.beFalse()
				expect(has(channel.calls, "pause")).to.beTrue()
				expect(hook.GetTable().Think["GrySuitLoop_cloak"]).to.beNil()
			end
		},
		{
			-- fails without the ShutDown listener
			name = "the game closing ends both loops",
			func = function()
				local listener = hook.GetTable().ShutDown and hook.GetTable().ShutDown["GRYSUITLOOPS"]
				expect(listener).to.beA("function")

				for _, loop in pairs(L.State) do
					loop.channel = fakeChannel()
					L.Begin(loop)
				end

				listener()

				for _, loop in pairs(L.State) do
					expect(loop.wanted).to.beFalse()
				end
			end
		},
		{
			name = "the two switches are saved, on by default, and have a check box in the Sounds options; the cloak loop is in the mix at the event's level",
			func = function()
				for _, name in ipairs({"gry_sound_malfunction_loop", "gry_sound_cloak_loop"}) do
					local convar = GetConVar(name)
					expect(convar ~= nil).to.beTrue()
					expect(convar:GetDefault()).to.equal("1")
					expect(convar:GetFlags()).to.equal(GetConVar("gry_sound_regen"):GetFlags())
				end

				expect(GryMod.SoundMix.Original["grymod/hud/hud_cloak_feedback.wav"]).to.equal(-12)
				expect(file.Exists("sound/grymod/hud/hud_cloak_feedback.wav", "GAME")).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.SoundOptions(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_sound_malfunction_loop"]).to.beTrue()
				expect(found["gry_sound_cloak_loop"]).to.beTrue()
			end
		}
	}
}
