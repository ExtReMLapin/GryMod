-- Tests of the client state of the night vision (GryMod.NightVision, cl_nightvision.lua), GLuaTest format, client realm. Nothing here draws: the
-- screen effect and the energy bar are other modules that READ this state. What is tested: the pure maths (energy, fade), the lazy state (nothing runs
-- by itself: energy and fade are worked out from stored times when they are read, and one timer fires at the second the energy reaches zero), the key
-- (hold and toggle), every reason that switches it off, the refusals to switch it on, the HUD event `night_vision` with its sounds and the hook
-- GryMod_NightVision. The world is the test's own: the clock, what the module reads of the player, the server's switch, the files and the loop channel
-- are replaced for each case and put back after it.

local NAMES = {
	"gry_nightvision", "gry_nightvision_hold", "gry_nightvision_key", "gry_nightvision_energy", "gry_nightvision_drain", "gry_nightvision_recharge",
	"gry_nightvision_light", "gry_nightvision_star", "gry_nightvision_localgain", "gry_nightvision_fx", "gry_sounds"
}

local TIMER = "GryMod_NightVisionEmpty"
local SELECT, LOOP, DESELECT = "grymod/suit/night_vision_select.wav", "grymod/suit/night_vision_ambience.wav", "grymod/suit/night_vision_deselect.wav"

-- the per-frame hooks: none of the module's may exist while it is off
local FRAME_HOOKS = {"Think", "Tick", "HUDPaint", "HUDPaintBackground", "PreRender", "PostRender", "RenderScreenspaceEffects", "PostDrawTranslucentRenderables", "PostDrawOpaqueRenderables", "SetupWorldFog", "SetupSkyboxFog"}

local function frameHooksOfTheModule()
	local found = {}
	local all = hook.GetTable()

	for _, event in ipairs(FRAME_HOOKS) do
		for name in pairs(all[event] or {}) do
			if string.find(tostring(name), "^GRYNIGHTVISION") then
				found[#found + 1] = event .. ":" .. tostring(name)
			end
		end
	end

	table.sort(found)

	return table.concat(found, ",")
end

local function fakeChannel(log)
	return {
		IsValid = function() return true end,
		SetTime = function() log[#log + 1] = "time" end,
		SetVolume = function(_, v) log[#log + 1] = "volume" end,
		Play = function() log[#log + 1] = "play" end,
		Pause = function() log[#log + 1] = "pause" end,
		EnableLooping = function() end
	}
end

return {
	groupName = "GryMod night vision (client state)",
	beforeEach = function(state)
		local NV = GryMod.NightVision

		state.saved = {convars = {}}

		for _, name in ipairs(NAMES) do
			local convar = GetConVar(name)
			state.saved.convars[name] = convar and convar:GetString()
		end

		-- (everything replaced is saved first, one line each)
		state.saved.emit = GryMod.SoundMix.Emit
		state.saved.lookupKey = input.LookupKeyBinding

		if NV then
			state.saved.clock, state.saved.read, state.saved.server, state.saved.exists = NV.Clock, NV.ReadWorld, NV.ServerAllowed, NV.FileExists
			state.saved.channel = NV.Loop and NV.Loop.GetChannel()
		end

		GryMod.SoundMix.Emit = function(path) state.played[#state.played + 1] = path end
		input.LookupKeyBinding = function(code) return state.binds[code] end

		state.played, state.binds, state.hooks, state.events, state.channelLog = {}, {}, {}, {}, {}
		state.now = 1000
		state.world = {valid = true, alive = true, suit = true, malfunction = false}
		state.server = true

		-- the defaults of the settings, whatever the player's profile says
		local defaults = {
			gry_nightvision = "1", gry_nightvision_hold = "0", gry_nightvision_key = "0", gry_nightvision_energy = "1", gry_nightvision_drain = "0.5",
			gry_nightvision_recharge = "2", gry_sounds = "1"
		}

		for name, value in pairs(defaults) do
			local convar = GetConVar(name)

			if convar then
				convar:SetString(value)
			end
		end

		if NV then
			NV.Clock = function() return state.now end
			NV.ServerAllowed = function() return state.server end
			NV.FileExists = function() return true end

			local real = state.saved.read

			NV.ReadWorld = function(w)
				real(w)
				w.valid, w.alive, w.suit = state.world.valid, state.world.alive, state.world.suit
				-- (the module's own memory of the HUD status stays in the answer)
				w.malfunction = w.malfunction or state.world.malfunction

				return w
			end

			NV.Loop.SetChannel(fakeChannel(state.channelLog))
			NV.Reset()
		end

		hook.Add("GryMod_NightVision", "GRYTESTNV", function(on, reason)
			state.hooks[#state.hooks + 1] = {on, reason}
		end)

		hook.Add("GryMod_HUDEvent", "GRYTESTNV", function(name, data)
			if name == "night_vision" then
				state.events[#state.events + 1] = {data.on, data.reason}
			end
		end)
	end,
	afterEach = function(state)
		hook.Remove("GryMod_NightVision", "GRYTESTNV")
		hook.Remove("GryMod_HUDEvent", "GRYTESTNV")

		local NV = GryMod.NightVision
		local saved = state.saved

		if not saved then
			return
		end

		GryMod.SoundMix.Emit = saved.emit
		input.LookupKeyBinding = saved.lookupKey

		if NV then
			-- (the player's settings come back first: the module is reset with its own clock, then the real ones return)
			for name, value in pairs(saved.convars) do
				if value then
					GetConVar(name):SetString(value)
				end
			end

			NV.Reset()
			NV.Clock, NV.ReadWorld, NV.ServerAllowed, NV.FileExists = saved.clock, saved.read, saved.server, saved.exists

			if saved.channel then
				NV.Loop.SetChannel(saved.channel)
			end

			NV.Reset()
		else
			for name, value in pairs(saved.convars) do
				if value then
					GetConVar(name):SetString(value)
				end
			end
		end
	end,
	cases = {
		{
			name = "the settings are saved with the profile and start as the design says: on, toggle, no key, energy limited at 0.5 a second used and 2 a second recovered, light, starlight, local gain and the whole effect on",
			func = function(state)
				local created = {}
				local realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, ...)
					created[name] = {default = default, save = shouldsave}

					return realCreate(name, default, shouldsave, ...)
				end

				local ok, err = pcall(include, "grymod/client/cl_nightvision.lua")
				CreateClientConVar = realCreate

				if not ok then
					error(err, 0)
				end

				-- the file made its functions again: what afterEach puts back are the new ones
				local NV = GryMod.NightVision
				state.saved.clock, state.saved.read, state.saved.server, state.saved.exists = NV.Clock, NV.ReadWorld, NV.ServerAllowed, NV.FileExists
				state.saved.channel = nil

				local defaults = {
					gry_nightvision = "1", gry_nightvision_hold = "0", gry_nightvision_key = "0", gry_nightvision_energy = "1", gry_nightvision_drain = "0.5",
					gry_nightvision_recharge = "2", gry_nightvision_light = "1", gry_nightvision_star = "1", gry_nightvision_localgain = "1", gry_nightvision_fx = "1"
				}

				for name, value in pairs(defaults) do
					expect(created[name]).toNot.beNil()
					expect(created[name].save).to.beTrue()
					expect(created[name].default).to.equal(value)
				end
			end
		},
		{
			name = "Advance (pure): 0.5 a second from 30 lasts 60 seconds and says so when it reaches zero; 2 a second brings 0 back to 30 in 15; never below 0 nor above 30; a clock that goes back changes nothing",
			func = function()
				local NV = GryMod.NightVision
				local cfg = {max = 30, drain = 0.5, recharge = 2}

				local e, zero = NV.Advance({energy = 30, on = true}, 30, cfg)
				expect(e).to.aboutEqual(15, 1e-9)
				expect(zero).to.beFalse()

				e, zero = NV.Advance({energy = 30, on = true}, 59.9, cfg)
				expect(e).to.aboutEqual(0.05, 1e-6)
				expect(zero).to.beFalse()

				e, zero = NV.Advance({energy = 30, on = true}, 60, cfg)
				expect(e).to.equal(0)
				expect(zero).to.beTrue()

				e, zero = NV.Advance({energy = 30, on = true}, 100000, cfg)
				expect(e).to.equal(0)
				expect(zero).to.beTrue()

				e, zero = NV.Advance({energy = 0, on = false}, 7.5, cfg)
				expect(e).to.aboutEqual(15, 1e-9)
				expect(zero).to.beFalse()

				e = NV.Advance({energy = 0, on = false}, 15, cfg)
				expect(e).to.aboutEqual(30, 1e-9)

				e = NV.Advance({energy = 12, on = false}, 100000, cfg)
				expect(e).to.equal(30)

				-- a clock that went back (a map load, a pause): no time has passed
				e, zero = NV.Advance({energy = 10, on = true}, -5, cfg)
				expect(e).to.equal(10)
				expect(zero).to.beFalse()

				e = NV.Advance({energy = 10, on = false}, -5, cfg)
				expect(e).to.equal(10)

				-- no drain: it never reaches zero
				e, zero = NV.Advance({energy = 30, on = true}, 1000, {max = 30, drain = 0, recharge = 2})
				expect(e).to.equal(30)
				expect(zero).to.beFalse()
			end
		},
		{
			name = "FadeStep and Mix (pure): the picture rises and falls by 4 a second, so 0.25 s each way, held between 0 and 1; the mix is the fade squared",
			func = function()
				local NV = GryMod.NightVision

				expect(NV.FadeStep(0, true, 0.25)).to.aboutEqual(1, 1e-9)
				expect(NV.FadeStep(0, true, 0.125)).to.aboutEqual(0.5, 1e-9)
				expect(NV.FadeStep(0, true, 10)).to.equal(1)
				expect(NV.FadeStep(1, false, 0.25)).to.aboutEqual(0, 1e-9)
				expect(NV.FadeStep(1, false, 0.125)).to.aboutEqual(0.5, 1e-9)
				expect(NV.FadeStep(1, false, 10)).to.equal(0)
				expect(NV.FadeStep(0.5, true, 0.0625)).to.aboutEqual(0.75, 1e-9)
				expect(NV.FadeStep(0.5, false, 0.0625)).to.aboutEqual(0.25, 1e-9)
				expect(NV.FadeStep(0.3, true, 0)).to.aboutEqual(0.3, 1e-9)
				expect(NV.FadeStep(0.3, true, -1)).to.aboutEqual(0.3, 1e-9)

				expect(NV.Mix(0)).to.equal(0)
				expect(NV.Mix(0.5)).to.aboutEqual(0.25, 1e-9)
				expect(NV.Mix(1)).to.equal(1)
			end
		},
		{
			name = "a new state: off, full energy (30, bar 100), no fade, nothing playing, no timer",
			func = function(state)
				local NV = GryMod.NightVision

				expect(NV.IsOn()).to.beFalse()
				expect(NV.Energy()).to.equal(30)
				expect(NV.Bar()).to.aboutEqual(100, 1e-9)
				expect(NV.Fade()).to.equal(0)
				expect(NV.Mix()).to.equal(0)
				expect(timer.Exists(TIMER)).to.beFalse()
				expect(#state.played).to.equal(0)
			end
		},
		{
			-- fails when no handler of GryMod_CanUseView is asked, when the kind or the reason is not told, when a refusal does not stop the key, or when it also switches off a night vision that is on
			name = "the hook GryMod_CanUseView(\"nightvision\", reason): a handler that returns false refuses the switching on (Refusal gives \"veto\", the key does nothing), any other answer or another kind is no opinion, and one that is already on stays on",
			func = function(state)
				local NV = GryMod.NightVision
				local asked = {}

				hook.Add("GryMod_CanUseView", "GRYTESTNVVETO", function(kind, reason) asked[#asked + 1] = {kind, reason} if kind == "nightvision" then return false end end)

				local ok, err = pcall(function()
					expect(NV.CanTurnOn()).to.beFalse()
					expect(NV.Refusal("key")).to.equal("veto")
					expect(asked[#asked][1]).to.equal("nightvision")
					expect(asked[#asked][2]).to.equal("key")
					expect(NV.Set(true, "key")).to.beFalse()
					expect(select(2, NV.Set(true, "toggle"))).to.equal("veto")
					expect(NV.IsOn()).to.beFalse()
					NV.Press(true)
					expect(NV.IsOn()).to.beFalse()

					-- no opinion: another kind, nothing returned, true
					hook.Add("GryMod_CanUseView", "GRYTESTNVVETO", function(kind) if kind == "zoom" then return false end return true end)
					expect(NV.Set(true, "key")).to.beTrue()

					-- on: a veto that comes later does not switch it off
					hook.Add("GryMod_CanUseView", "GRYTESTNVVETO", function() return false end)
					NV.Guard()
					expect(NV.IsOn()).to.beTrue()
				end)

				hook.Remove("GryMod_CanUseView", "GRYTESTNVVETO")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the energy is lazy: on for 10 seconds it reads 25 (bar 83.3) at the time it is asked, nothing ticks; off again it recovers 2 a second from where it was, and a long rest gives it back whole",
			func = function(state)
				local NV = GryMod.NightVision

				expect(NV.Set(true, "key")).to.beTrue()
				state.now = state.now + 10
				expect(NV.Energy()).to.aboutEqual(25, 1e-6)
				expect(NV.Bar()).to.aboutEqual(25 * 100 / 30, 1e-6)

				expect(NV.Set(false, "key")).to.beTrue()
				expect(NV.Energy()).to.aboutEqual(25, 1e-6)
				state.now = state.now + 2
				expect(NV.Energy()).to.aboutEqual(29, 1e-6)
				state.now = state.now + 1000
				expect(NV.Energy()).to.equal(30)
				expect(NV.Bar()).to.aboutEqual(100, 1e-9)
			end
		},
		{
			name = "the drain and the recharge follow their settings",
			func = function(state)
				local NV = GryMod.NightVision

				GetConVar("gry_nightvision_drain"):SetString("1")
				GetConVar("gry_nightvision_recharge"):SetString("5")
				expect(NV.Set(true, "key")).to.beTrue()
				state.now = state.now + 10
				expect(NV.Energy()).to.aboutEqual(20, 1e-6)
				expect(NV.Set(false, "key")).to.beTrue()
				state.now = state.now + 1
				expect(NV.Energy()).to.aboutEqual(25, 1e-6)
				expect(timer.Exists(TIMER)).to.beFalse()
			end
		},
		{
			name = "the fade is lazy too: 0.25 s to rise, 0.25 s to fall, and a switch in the middle of a fade goes on from where the picture is",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				expect(NV.Fade()).to.equal(0)
				state.now = state.now + 0.125
				expect(NV.Fade()).to.aboutEqual(0.5, 1e-6)
				expect(NV.Mix()).to.aboutEqual(0.25, 1e-6)
				state.now = state.now + 5
				expect(NV.Fade()).to.equal(1)
				expect(NV.Mix()).to.equal(1)

				NV.Set(false, "key")
				state.now = state.now + 0.125
				expect(NV.Fade()).to.aboutEqual(0.5, 1e-6)
				-- on again at half: it rises from 0.5
				NV.Set(true, "key")
				expect(NV.Fade()).to.aboutEqual(0.5, 1e-6)
				state.now = state.now + 0.0625
				expect(NV.Fade()).to.aboutEqual(0.75, 1e-6)
				NV.Set(false, "key")
				state.now = state.now + 10
				expect(NV.Fade()).to.equal(0)
			end
		},
		{
			name = "switching on and off tells the hook GryMod_NightVision(on, reason) and the event night_vision once each, and a switch to the state it is already in tells nothing",
			func = function(state)
				local NV = GryMod.NightVision

				expect(NV.Set(true, "key")).to.beTrue()
				expect(NV.Set(true, "key")).to.beFalse()
				expect(#state.hooks).to.equal(1)
				expect(state.hooks[1][1]).to.beTrue()
				expect(state.hooks[1][2]).to.equal("key")
				expect(#state.events).to.equal(1)
				expect(state.events[1][1]).to.beTrue()

				expect(NV.Set(false, "toggle")).to.beTrue()
				expect(NV.Set(false, "toggle")).to.beFalse()
				expect(#state.hooks).to.equal(2)
				expect(state.hooks[2][1]).to.beFalse()
				expect(state.hooks[2][2]).to.equal("toggle")
				expect(#state.events).to.equal(2)
				expect(state.events[2][1]).to.beFalse()
			end
		},
		{
			name = "a listener of the hook that fails does not stop the night vision",
			func = function(state)
				local NV = GryMod.NightVision

				hook.Add("GryMod_NightVision", "GRYTESTNVBAD", function() error("a listener that fails") end)

				local ok = pcall(function()
					expect(NV.Set(true, "key")).to.beTrue()
				end)

				hook.Remove("GryMod_NightVision", "GRYTESTNVBAD")
				expect(ok).to.beTrue()
				expect(NV.IsOn()).to.beTrue()
			end
		},
		{
			name = "the timer: switched on, one timer is set for the exact second the energy reaches zero (60 s from full, 20 s from 10), and it goes when the night vision does",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				expect(timer.Exists(TIMER)).to.beTrue()
				expect(timer.TimeLeft(TIMER)).to.aboutEqual(60, 0.5)
				NV.Set(false, "key")
				expect(timer.Exists(TIMER)).to.beFalse()

				-- 10 left: 20 seconds
				state.now = state.now + 0.5
				NV.Set(true, "key")
				state.now = state.now + 40
				NV.Set(false, "key")
				expect(NV.Energy()).to.aboutEqual(10, 1e-6)
				NV.Set(true, "key")
				expect(timer.TimeLeft(TIMER)).to.aboutEqual(20, 0.5)
				NV.Set(false, "key")
				expect(timer.Exists(TIMER)).to.beFalse()
			end
		},
		{
			name = "the timer fires at zero: it switches off with the reason energy, tells the hook and the event once, empties the bar; a timer that comes a moment early waits for the rest; the picture is gone 0.25 s later",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				state.now = state.now + 59
				NV.Expire()
				expect(NV.IsOn()).to.beTrue()
				expect(timer.Exists(TIMER)).to.beTrue()
				expect(timer.TimeLeft(TIMER)).to.aboutEqual(1, 0.5)

				state.now = state.now + 1
				NV.Expire()
				expect(NV.IsOn()).to.beFalse()
				expect(NV.Energy()).to.equal(0)
				expect(NV.Bar()).to.equal(0)
				expect(#state.hooks).to.equal(2)
				expect(state.hooks[2][1]).to.beFalse()
				expect(state.hooks[2][2]).to.equal("energy")
				expect(#state.events).to.equal(2)
				expect(timer.Exists(TIMER)).to.beFalse()

				state.now = state.now + 0.25
				expect(NV.Fade()).to.aboutEqual(0, 1e-6)
			end
		},
		{
			name = "no limit (gry_nightvision_energy 0): no timer, the energy is whole whatever the time, and it can always be switched on",
			func = function(state)
				local NV = GryMod.NightVision

				GetConVar("gry_nightvision_energy"):SetString("0")
				expect(NV.Unlimited()).to.beTrue()
				expect(NV.Set(true, "key")).to.beTrue()
				expect(timer.Exists(TIMER)).to.beFalse()
				state.now = state.now + 100000
				expect(NV.Energy()).to.equal(30)
				expect(NV.IsOn()).to.beTrue()
				NV.Expire()
				expect(NV.IsOn()).to.beTrue()
				expect(NV.Set(false, "key")).to.beTrue()
				GetConVar("gry_nightvision_energy"):SetString("1")
				expect(NV.Unlimited()).to.beFalse()
			end
		},
		{
			name = "toggle mode: every press switches, the release does nothing; hold mode: the press switches on, the release switches off",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Press(true)
				expect(NV.IsOn()).to.beTrue()
				NV.Press(false)
				expect(NV.IsOn()).to.beTrue()
				NV.Press(true)
				expect(NV.IsOn()).to.beFalse()
				NV.Press(false)
				expect(NV.IsOn()).to.beFalse()
				expect(#state.hooks).to.equal(2)

				GetConVar("gry_nightvision_hold"):SetString("1")
				NV.Press(true)
				expect(NV.IsOn()).to.beTrue()
				NV.Press(false)
				expect(NV.IsOn()).to.beFalse()
				-- a release with nothing on tells nothing
				NV.Press(false)
				expect(#state.hooks).to.equal(4)
				expect(state.hooks[3][2]).to.equal("key")
			end
		},
		{
			name = "hold mode with the energy gone: the night vision stops by itself while the key is down, and it does not come back until the key is let go and pressed again",
			func = function(state)
				local NV = GryMod.NightVision

				GetConVar("gry_nightvision_hold"):SetString("1")
				NV.Press(true)
				state.now = state.now + 60
				NV.Expire()
				expect(NV.IsOn()).to.beFalse()
				state.now = state.now + 30
				expect(NV.IsOn()).to.beFalse()
				expect(timer.Exists(TIMER)).to.beFalse()
				NV.Press(false)
				expect(NV.IsOn()).to.beFalse()
				NV.Press(true)
				expect(NV.IsOn()).to.beTrue()
				NV.Press(false)
			end
		},
		{
			name = "it is refused (nothing changes, nothing is told) when the option is off, the server forbids it, the player is dead or not there, the suit is off or down, or the energy is zero; Refusal says which",
			func = function(state)
				local NV = GryMod.NightVision

				expect(NV.CanTurnOn()).to.beTrue()
				expect(NV.Refusal()).to.beNil()

				local cases = {
					{"option", function() GetConVar("gry_nightvision"):SetString("0") end, function() GetConVar("gry_nightvision"):SetString("1") end},
					{"server", function() state.server = false end, function() state.server = true end},
					{"invalid", function() state.world.valid = false end, function() state.world.valid = true end},
					{"dead", function() state.world.alive = false end, function() state.world.alive = true end},
					{"suit", function() state.world.suit = false end, function() state.world.suit = true end},
					{"malfunction", function() state.world.malfunction = true end, function() state.world.malfunction = false end}
				}

				for _, case in ipairs(cases) do
					case[2]()
					expect(NV.CanTurnOn()).to.beFalse()
					expect(NV.Refusal()).to.equal(case[1])

					local ok, why = NV.Set(true, "key")
					expect(ok).to.beFalse()
					expect(why).to.equal(case[1])
					expect(NV.IsOn()).to.beFalse()
					expect(timer.Exists(TIMER)).to.beFalse()
					case[3]()
				end

				-- the energy at zero
				NV.SetEnergy(0)
				expect(NV.CanTurnOn()).to.beFalse()
				expect(NV.Refusal()).to.equal("empty")
				expect(NV.Set(true, "key")).to.beFalse()
				-- a little comes back: it can be switched on
				state.now = state.now + 1
				expect(NV.CanTurnOn()).to.beTrue()

				expect(#state.hooks).to.equal(0)
				expect(#state.events).to.equal(0)
			end
		},
		{
			name = "Refuse (pure) gives the first reason in the order option, server, invalid, dead, suit, malfunction, empty",
			func = function()
				local NV = GryMod.NightVision
				local function world(over)
					local w = {option = true, server = true, valid = true, alive = true, suit = true, malfunction = false, energy = 10}

					for k, v in pairs(over or {}) do
						w[k] = v
					end

					return w
				end

				expect(NV.Refuse(world())).to.beNil()
				expect(NV.Refuse(world({energy = 0}))).to.equal("empty")
				expect(NV.Refuse(world({energy = 0, malfunction = true}))).to.equal("malfunction")
				expect(NV.Refuse(world({malfunction = true, suit = false}))).to.equal("suit")
				expect(NV.Refuse(world({suit = false, alive = false}))).to.equal("dead")
				expect(NV.Refuse(world({alive = false, valid = false}))).to.equal("invalid")
				expect(NV.Refuse(world({valid = false, server = false}))).to.equal("server")
				expect(NV.Refuse(world({server = false, option = false}))).to.equal("option")
			end
		},
		{
			name = "it goes off by itself when the player dies (the guard that exists only while it is on), with the reason death",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				NV.Guard()
				expect(NV.IsOn()).to.beTrue()
				state.world.alive = false
				NV.Guard()
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[2][2]).to.equal("dead")
			end
		},
		{
			name = "it goes off when the suit goes down: the HUD status 1 (malfunction, or death with its second argument), the suit flag turned off and the event disabled",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				NV.OnHUDStatus(2)
				expect(NV.IsOn()).to.beTrue()
				NV.OnHUDStatus(1)
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[2][2]).to.equal("malfunction")
				-- the status stays down: it cannot be switched on until the HUD is back
				expect(NV.CanTurnOn()).to.beFalse()
				expect(NV.Refusal()).to.equal("malfunction")
				NV.OnHUDStatus(0, "respawn")
				expect(NV.CanTurnOn()).to.beTrue()

				NV.Set(true, "key")
				NV.OnHUDStatus(1, "death")
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[4][2]).to.equal("death")
				NV.OnHUDStatus(0, "respawn")

				NV.Set(true, "key")
				NV.OnHUDEvent("disabled")
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[6][2]).to.equal("disabled")

				NV.Set(true, "key")
				state.world.suit = false
				NV.Guard()
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[8][2]).to.equal("suit")
			end
		},
		{
			name = "it goes off when the option is turned off, when the server forbids it, at the end of the game (disconnect) and at a new map, which also gives the energy back whole",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				NV.OnSettingChanged("gry_nightvision")
				expect(NV.IsOn()).to.beTrue()
				GetConVar("gry_nightvision"):SetString("0")
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[2][2]).to.equal("option")
				GetConVar("gry_nightvision"):SetString("1")

				NV.Set(true, "key")
				state.server = false
				NV.OnSettingChanged("gry_sv_nightvision")
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[4][2]).to.equal("server")
				state.server = true

				NV.Set(true, "key")
				NV.OnShutdown()
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[6][2]).to.equal("shutdown")

				NV.Set(true, "key")
				state.now = state.now + 20
				NV.OnInit()
				expect(NV.IsOn()).to.beFalse()
				expect(state.hooks[8][2]).to.equal("init")
				expect(NV.Energy()).to.equal(30)
				expect(NV.Fade()).to.equal(0)

				-- the hooks of the engine are there
				expect(hook.GetTable().ShutDown.GRYNIGHTVISION).toNot.beNil()
				expect(hook.GetTable().InitPostEntity.GRYNIGHTVISION).toNot.beNil()
				expect(hook.GetTable().GryMod_HUDStatus.GRYNIGHTVISION).toNot.beNil()
				expect(hook.GetTable().GryMod_HUDEvent.GRYNIGHTVISION).toNot.beNil()
			end
		},
		{
			name = "it never comes back by itself: after every kind of switch off, a long time later it is still off, with no timer",
			func = function(state)
				local NV = GryMod.NightVision

				for _, how in ipairs({"energy", "dead", "malfunction", "server"}) do
					NV.Reset()
					NV.Set(true, "key")

					if how == "energy" then
						state.now = state.now + 60
						NV.Expire()
					elseif how == "dead" then
						state.world.alive = false
						NV.Guard()
					elseif how == "malfunction" then
						NV.OnHUDStatus(1)
					else
						state.server = false
						NV.OnSettingChanged("gry_sv_nightvision")
					end

					expect(NV.IsOn()).to.beFalse()
					state.world.alive, state.server = true, true
					NV.OnHUDStatus(0, "respawn")
					state.now = state.now + 500
					expect(NV.IsOn()).to.beFalse()
					expect(timer.Exists(TIMER)).to.beFalse()
					expect(NV.Fade()).to.equal(0)
				end
			end
		},
		{
			name = "nothing runs by itself: while it is off and the fade is over, none of the module's per-frame hooks exists; while it is on only the guard does; off again, none",
			func = function(state)
				local NV = GryMod.NightVision

				expect(frameHooksOfTheModule()).to.equal("")
				NV.Set(true, "key")
				expect(frameHooksOfTheModule()).to.equal("Think:GRYNIGHTVISIONGUARD")
				NV.Set(false, "key")
				expect(frameHooksOfTheModule()).to.equal("")
				expect(timer.Exists(TIMER)).to.beFalse()
			end
		},
		{
			name = "Reset puts everything back silently: off, whole energy, no fade, no timer, no guard, nothing told",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				state.now = state.now + 10
				local told = #state.hooks
				NV.Reset()
				expect(NV.IsOn()).to.beFalse()
				expect(NV.Energy()).to.equal(30)
				expect(NV.Fade()).to.equal(0)
				expect(timer.Exists(TIMER)).to.beFalse()
				expect(frameHooksOfTheModule()).to.equal("")
				expect(#state.hooks).to.equal(told)
			end
		},
		{
			name = "the HUD event night_vision is registered with a label, a variant for on and one for off, and the options that cut it; the debug window lists it from the registry",
			func = function()
				local API = GryMod.API
				local names = API.ListHUDEvents()

				expect(table.HasValue(names, "night_vision")).to.beTrue()

				local info = API.GetHUDEventInfo("night_vision")

				expect(info.label).to.equal("Night vision")
				expect(#info.variants).to.equal(2)
				expect(info.variants[1].data.on).to.beTrue()
				expect(info.variants[2].data.on).to.beFalse()

				local follows = {}

				for _, option in ipairs(info.follows) do
					follows[option[1]] = true
				end

				expect(follows.gry_nightvision).to.beTrue()
				expect(follows.gry_sounds).to.beTrue()
			end
		},
		{
			name = "playing the event does what the state does: night_vision {on = true} switches it on (once, one hook), {on = false} switches it off; a malformed payload does nothing; the option off refuses it",
			func = function(state)
				local NV = GryMod.NightVision
				local API = GryMod.API

				expect(API.HUDEvent("night_vision", {on = true})).to.beTrue()
				expect(NV.IsOn()).to.beTrue()
				expect(#state.hooks).to.equal(1)
				expect(#state.events).to.equal(1)

				-- the same state again: nothing more
				API.HUDEvent("night_vision", {on = true})
				expect(#state.hooks).to.equal(1)

				API.HUDEvent("night_vision", {on = "yes"})
				API.HUDEvent("night_vision", {})
				expect(NV.IsOn()).to.beTrue()
				expect(#state.hooks).to.equal(1)

				API.HUDEvent("night_vision", {on = false})
				expect(NV.IsOn()).to.beFalse()
				expect(#state.hooks).to.equal(2)

				GetConVar("gry_nightvision"):SetString("0")
				API.HUDEvent("night_vision", {on = true})
				expect(NV.IsOn()).to.beFalse()
				expect(#state.hooks).to.equal(2)
				expect(#state.played).to.equal(2)
			end
		},
		{
			name = "the sounds: select when it goes on with the ambience loop started, the loop stopped and deselect when it goes off; nothing at the end of a game or a map change but the loop stops",
			func = function(state)
				local NV = GryMod.NightVision

				NV.Set(true, "key")
				expect(#state.played).to.equal(1)
				expect(state.played[1]).to.equal(SELECT)
				expect(string.find(table.concat(state.channelLog, ","), "play", 1, true) ~= nil).to.beTrue()
				expect(NV.Loop.IsPlaying()).to.beTrue()

				NV.Set(false, "key")
				expect(#state.played).to.equal(2)
				expect(state.played[2]).to.equal(DESELECT)
				expect(NV.Loop.IsPlaying()).to.beFalse()
				expect(state.channelLog[#state.channelLog]).to.equal("pause")

				NV.Set(true, "key")
				NV.OnShutdown()
				expect(#state.played).to.equal(3)
				expect(NV.Loop.IsPlaying()).to.beFalse()
				expect(state.channelLog[#state.channelLog]).to.equal("pause")

				NV.Set(true, "key")
				NV.OnInit()
				expect(#state.played).to.equal(4)
				expect(NV.Loop.IsPlaying()).to.beFalse()
			end
		},
		{
			name = "gry_sounds 0 silences all of it (no select, no loop, no deselect) while the state still works; a loop going when the sounds are turned off stops, and starts again when they come back",
			func = function(state)
				local NV = GryMod.NightVision

				GetConVar("gry_sounds"):SetString("0")
				NV.Set(true, "key")
				expect(NV.IsOn()).to.beTrue()
				expect(#state.played).to.equal(0)
				expect(NV.Loop.IsPlaying()).to.beFalse()
				NV.Set(false, "key")
				expect(#state.played).to.equal(0)

				GetConVar("gry_sounds"):SetString("1")
				NV.Set(true, "key")
				expect(NV.Loop.IsPlaying()).to.beTrue()
				GetConVar("gry_sounds"):SetString("0")
				expect(NV.Loop.IsPlaying()).to.beFalse()
				GetConVar("gry_sounds"):SetString("1")
				expect(NV.Loop.IsPlaying()).to.beTrue()
				NV.Set(false, "key")
			end
		},
		{
			name = "a sound file that is not there plays nothing and raises no error (the state and the hook still work)",
			func = function(state)
				local NV = GryMod.NightVision

				NV.FileExists = function() return false end
				NV.Loop.SetChannel(nil)

				local ok = pcall(function()
					NV.Set(true, "key")
					NV.Set(false, "key")
				end)

				expect(ok).to.beTrue()
				expect(#state.played).to.equal(0)
				expect(#state.hooks).to.equal(2)
				expect(NV.Loop.IsPlaying()).to.beFalse()
			end
		},
		{
			name = "the key: made by the key factory (setting gry_nightvision_key, command +gry_nightvision), default N when nothing is bound on it and the other keys are not N, none when N is taken, and the console command works as a press",
			func = function(state)
				local NV = GryMod.NightVision
				local Key = NV.Key

				expect(Key.convar:GetName()).to.equal("gry_nightvision_key")
				expect(Key.Chosen()).to.equal(0)
				expect(GryMod.KeyBinder.Keys.gry_nightvision_key).to.equal(Key)

				NV.ForgetBinding()
				expect(Key.Effective()).to.equal(KEY_N)

				-- N is bound to something in the game: no default
				state.binds[KEY_N] = "+duck"
				NV.ForgetBinding()
				expect(Key.Effective()).to.equal(0)
				state.binds[KEY_N] = nil

				-- the player's own key wins, and the default is never saved
				NV.ForgetBinding()
				expect(Key.Effective()).to.equal(KEY_N)
				expect(Key.Chosen()).to.equal(0)
				Key.convar:SetInt(KEY_G)
				expect(Key.Effective()).to.equal(KEY_G)
				Key.convar:SetInt(0)

				-- a key picked for the zoom or the quick menu is refused here, and the binoculars' wheel
				expect(Key.SetKey(MOUSE_WHEEL_UP)).to.beFalse()
				expect(Key.SetKey(KEY_ESCAPE)).to.beFalse()

				-- the console command is a press and a release
				concommand.Run(LocalPlayer(), "+gry_nightvision", {}, "")
				expect(NV.IsOn()).to.beTrue()
				concommand.Run(LocalPlayer(), "-gry_nightvision", {}, "")
				expect(NV.IsOn()).to.beTrue()
				concommand.Run(LocalPlayer(), "+gry_nightvision", {}, "")
				expect(NV.IsOn()).to.beFalse()
				concommand.Run(LocalPlayer(), "-gry_nightvision", {}, "")
			end
		}
	}
}
