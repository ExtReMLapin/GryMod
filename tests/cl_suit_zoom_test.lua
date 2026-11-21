-- Tests of the suit zoom (GryMod.SuitZoom), GLuaTest format, client realm. The binoculars have their own zoom key (gry_zoom_own):
-- one module owns "the player is zooming", every reason to stop goes through SuitZoom.Exit, and a situation (a plain table of
-- facts about the world) is turned into "must the zoom end, and why" by a pure function (SuitZoom.Reason). The tests give the module
-- a world of their own (SuitZoom.Read replaced) and never play a sound.

local OWN, KEY, MODE, TAP = "gry_zoom_own", "gry_zoom_key", "gry_zoom_mode", "gry_zoom_tap_ms"
local WEAPON = {}

-- a calm world: nothing prevents the zoom, and nothing ends it
local function calm()
	return {
		valid = true, alive = true, enabled = true, quickmenu = false, pause = false, console = false, cursor = false,
		focusPanel = false, typing = false, focus = true, malfunction = false, vehicle = false, thirdperson = false,
		viewother = false, observer = 0, frozen = false, water = 0, weapon = WEAPON, entered = WEAPON, keyUp = false,
		viewAge = 0
	}
end

local function setting(name)
	return GetConVar(name)
end

return {
	groupName = "GryMod suit zoom",
	beforeEach = function(state)
		-- (everything that is restored in afterEach is saved first, one line each: a failure here must not leave a stub behind)
		local Z = GryMod.SuitZoom
		local Bino = GryMod.FlashBinoculars
		state.saved = {
			own = setting(OWN) and setting(OWN):GetString(),
			key = setting(KEY) and setting(KEY):GetString(),
			mode = setting(MODE) and setting(MODE):GetString(),
			tap = setting(TAP) and setting(TAP):GetString(),
			clock = Z and Z.Clock,
			sway = setting("gry_binoculars_sway") and setting("gry_binoculars_sway"):GetString(),
			read = Z and Z.Read,
			lookupKey = input.LookupKeyBinding,
			drop = Bino and Bino.Drop,
			emit = GryMod.SoundMix.Emit,
			frame = FrameNumber
		}
		GryMod.SoundMix.Emit = function() end
		-- the frame number is the test's: two calls of Guard in one frame (Think and CalcView) are one frame of the poll
		state.frame = 1000
		FrameNumber = function() return state.frame end

		-- the clock of the zoom is the test's: a press lasts as long as the case says (seconds)
		state.now = 0
		-- the keys of the game: none bound, whatever the player's profile says (the cases bind what they need)
		state.binds = {}
		input.LookupKeyBinding = function(code) return state.binds[code] end
		state.world = calm()
		state.drops = 0
		state.events = {}

		if Bino then
			Bino.Drop = function() state.drops = state.drops + 1 end
		end

		if Z then
			Z.Read = function(sit)
				for k, v in pairs(state.world) do
					sit[k] = v
				end

				return sit
			end
			setting(OWN):SetString("1")
			setting(KEY):SetString(tostring(KEY_F7))
			-- (hold: the cases that do not care about the mode press and let go at once; the three modes have their own cases)
			if setting(MODE) then setting(MODE):SetString("0") end
			if setting(TAP) then setting(TAP):SetString("250") end
			Z.Clock = function() return state.now end
			-- (the view tests read the game's own angles: no sway, whatever the player has saved or the default is)
			if setting("gry_binoculars_sway") then setting("gry_binoculars_sway"):SetString("0") end
			Z.Reset()
		end

		hook.Add("GryMod_SuitZoom", "GRYTESTSUITZOOM", function(active, reason)
			state.events[#state.events + 1] = {active, reason}
		end)
	end,
	afterEach = function(state)
		hook.Remove("GryMod_SuitZoom", "GRYTESTSUITZOOM")

		local Z = GryMod.SuitZoom
		local Bino = GryMod.FlashBinoculars
		local saved = state.saved

		if saved then
			GryMod.SoundMix.Emit = saved.emit
			FrameNumber = saved.frame or FrameNumber

			input.LookupKeyBinding = saved.lookupKey

			if Z then
				Z.Read = saved.read
				Z.Clock = saved.clock
			end

			if Bino then
				Bino.Drop = saved.drop
			end

			if saved.own then setting(OWN):SetString(saved.own) end
			if saved.key then setting(KEY):SetString(saved.key) end
			if saved.mode then setting(MODE):SetString(saved.mode) end
			if saved.tap then setting(TAP):SetString(saved.tap) end
			if saved.sway then setting("gry_binoculars_sway"):SetString(saved.sway) end
		end

		if Z then
			Z.Reset()
		end
	end,
	cases = {
		{
			name = "the four settings are saved with the profile: the own zoom is on by default (it does nothing until a key is chosen or bound), no key chosen, the automatic mode (a short press toggles, a long one holds) with a 250 ms threshold between 100 and 600",
			func = function(state)
				local created = {}
				local realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, userinfo, help, min, max)
					created[name] = {default = default, save = shouldsave, min = min, max = max}

					return realCreate(name, default, shouldsave, userinfo, help, min, max)
				end

				local ok, err = pcall(include, "grymod/client/cl_suit_zoom.lua")
				CreateClientConVar = realCreate

				if not ok then
					error(err, 0)
				end

				-- the file made a new module table: what afterEach puts back is that one's own function
				state.saved.read = GryMod.SuitZoom.Read

				local defaults = {[OWN] = "1", [KEY] = "0", [MODE] = "2", [TAP] = "250"}

				for _, name in ipairs({OWN, KEY, MODE, TAP}) do
					expect(created[name]).toNot.beNil()
					expect(created[name].save).to.beTrue()
					expect(created[name].default).to.equal(defaults[name])
				end

				-- (the old on / off setting of the toggle is gone: its saved value is not read)
				expect(created["gry_zoom_toggle"]).to.beNil()
				expect(created[MODE].min).to.equal(0)
				expect(created[MODE].max).to.equal(2)
				expect(created[TAP].min).to.equal(100)
				expect(created[TAP].max).to.equal(600)
			end
		},
		{
			name = "Reason (pure): a calm world gives nothing, and each situation gives its reason, the first in the list of the design when several hold (death before the menus, the menus before the view, the view before the water)",
			func = function(state)
				local R = GryMod.SuitZoom.Reason
				local cases = {
					{"valid", false, "init"},
					{"alive", false, "death"},
					{"enabled", false, "disabled"},
					{"quickmenu", true, "quickmenu"},
					{"pause", true, "pause"},
					{"console", true, "console"},
					{"cursor", true, "ui"},
					{"focusPanel", true, "ui"},
					{"typing", true, "chat"},
					{"focus", false, "focus"},
					{"malfunction", true, "malfunction"},
					{"vehicle", true, "vehicle"},
					{"thirdperson", true, "thirdperson"},
					{"viewother", true, "viewentity"},
					{"observer", 4, "observer"},
					{"frozen", true, "frozen"},
					{"water", 3, "water"}
				}

				expect(R(calm(), true)).to.beNil()
				expect(R(calm(), false)).to.beNil()

				for _, case in ipairs(cases) do
					local sit = calm()
					sit[case[1]] = case[2]
					expect(R(sit, true)).to.equal(case[3])
					expect(R(sit, false)).to.equal(case[3])
				end

				-- each condition alone gives its reason; together the earlier one wins
				for i = 1, #cases - 1 do
					local sit = calm()
					sit[cases[i][1]] = cases[i][2]
					sit[cases[i + 1][1]] = cases[i + 1][2]
					expect(R(sit, true)).to.equal(cases[i][3])
				end

				-- standing in the water up to the waist does not end it
				local sit = calm()
				sit.water = 2
				expect(R(sit, true)).to.beNil()
			end
		},
		{
			name = "Reason (pure): a weapon that is not the one the zoom opened with, and a view that none of our hooks has run for 3 frames, end an open zoom; they are not reasons to refuse one",
			func = function(state)
				local R = GryMod.SuitZoom.Reason
				local sit = calm()
				sit.weapon = {}
				expect(R(sit, true)).to.equal("weapon")
				expect(R(sit, false)).to.beNil()

				sit = calm()
				sit.viewAge = 2
				expect(R(sit, true)).to.beNil()
				sit.viewAge = 3
				expect(R(sit, true)).to.equal("viewtaken")
				expect(R(sit, false)).to.beNil()

				-- the weapon comes before the view in the list
				sit.weapon = {}
				expect(R(sit, true)).to.equal("weapon")
			end
		},
		{
			name = "a held key opens the zoom and its release closes it; a down that repeats (the engine runs a prediction again) counts once",
			func = function(state)
				local Z = GryMod.SuitZoom
				expect(Z.IsActive()).to.beFalse()

				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				expect(#state.events).to.equal(1)
				expect(state.events[1][1]).to.beTrue()

				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
				expect(state.events[2][1]).to.beFalse()
				expect(state.events[2][2]).to.equal("release")
				expect(#state.events).to.equal(2)
			end
		},
		{
			name = "with the option off nothing opens, and nothing changes (the Half-Life 2 zoom is the player's)",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(OWN):SetString("0")
				expect(Z.HasKey()).to.beFalse()
				Z.Press("key", true)
				expect(Z.IsActive()).to.beFalse()
				expect(#state.events).to.equal(0)
			end
		},
		{
			name = "the two sources of the key (the chosen key, a +gry_zoom bind) are one press when both come: one open, and the zoom ends when both are up",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				Z.Press("bind", true)
				expect(#state.events).to.equal(1)
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Press("bind", false)
				expect(Z.IsActive()).to.beFalse()
				expect(#state.events).to.equal(2)
			end
		},
		{
			name = "toggle mode: a press opens, the next press closes, the release in between does nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("1")

				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Press("key", true)
				expect(Z.IsActive()).to.beFalse()
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				-- and a press that repeats is not a second press
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "a press does not open the zoom in a menu, a panel with the keyboard, the chat, with the suit down or in a vehicle, and the release of that key does not leave anything open",
			func = function(state)
				local Z = GryMod.SuitZoom

				for _, field in ipairs({{"pause", true}, {"cursor", true}, {"focusPanel", true}, {"typing", true}, {"malfunction", true}, {"vehicle", true},
					{"quickmenu", true}, {"console", true}, {"focus", false}, {"alive", false}, {"enabled", false}}) do
					state.world = calm()
					state.world[field[1]] = field[2]
					Z.Press("key", true)
					expect(Z.IsActive()).to.beFalse()
					Z.Press("key", false)
					expect(Z.IsActive()).to.beFalse()
				end

				-- no event: nothing was opened, nothing closed
				expect(#state.events).to.equal(0)
			end
		},
		{
			name = "a key that goes up always closes the zoom, whatever is on screen (the release is never lost to a menu)",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				state.world.cursor = true
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
			end
		},
		{
			name = "Exit is the one way to close and is idempotent: a second call does nothing (one event, the first reason kept)",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				Z.Exit("weaponkey")
				Z.Exit("death")
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("weaponkey")
				expect(#state.events).to.equal(2)
				expect(state.events[2][2]).to.equal("weaponkey")

				-- with nothing open it is still fine
				Z.Reset()
				Z.Exit("death")
				expect(Z.IsActive()).to.beFalse()
				expect(#state.events).to.equal(2)
			end
		},
		{
			name = "the hard reasons (death, vehicle, a menu, the suit down, another view, a map change) put the binoculars away at once; the soft ones (release, weapon, water) let them close with their animation",
			func = function(state)
				local Z = GryMod.SuitZoom
				local hard = {"death", "vehicle", "init", "shutdown", "quickmenu", "pause", "console", "ui", "chat", "focus", "malfunction", "thirdperson",
					"viewentity", "observer", "frozen", "viewtaken", "disabled"}
				local soft = {"release", "weapon", "weaponkey", "water", "toggle"}

				for _, reason in ipairs(hard) do
					state.drops = 0
					Z.Reset()
					Z.Press("key", true)
					Z.Exit(reason)
					expect(state.drops).to.equal(1)
				end

				for _, reason in ipairs(soft) do
					state.drops = 0
					Z.Reset()
					Z.Press("key", true)
					Z.Exit(reason)
					expect(state.drops).to.equal(0)
				end
			end
		},
		{
			name = "Guard ends the zoom, with the reason, for each situation of the design (and does nothing in a calm world)",
			func = function(state)
				local Z = GryMod.SuitZoom
				local cases = {
					{"alive", false, "death"}, {"valid", false, "init"}, {"enabled", false, "disabled"}, {"quickmenu", true, "quickmenu"},
					{"pause", true, "pause"}, {"console", true, "console"}, {"cursor", true, "ui"}, {"focusPanel", true, "ui"}, {"typing", true, "chat"},
					{"focus", false, "focus"}, {"malfunction", true, "malfunction"}, {"vehicle", true, "vehicle"}, {"thirdperson", true, "thirdperson"},
					{"viewother", true, "viewentity"}, {"observer", 5, "observer"}, {"frozen", true, "frozen"}, {"water", 3, "water"},
					{"weapon", {}, "weapon"}, {"viewAge", 3, "viewtaken"}
				}

				Z.Press("key", true)
				Z.Guard()
				expect(Z.IsActive()).to.beTrue()

				for _, case in ipairs(cases) do
					state.world = calm()
					state.events = {}
					Z.Reset()
					Z.Press("key", true)
					expect(Z.IsActive()).to.beTrue()

					state.world[case[1]] = case[2]
					Z.Guard()
					expect(Z.IsActive()).to.beFalse()
					expect(Z.State.reason).to.equal(case[3])
					expect(#state.events).to.equal(2)
					expect(state.events[2][2]).to.equal(case[3])
				end
			end
		},
		{
			name = "dying with the key held: the zoom ends, nothing reopens at the respawn while the key is still down, and a release then a new press opens it again",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				state.world.alive = false
				Z.Guard()
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.blocked).to.beTrue()

				state.world.alive = true
				Z.Guard()
				expect(Z.IsActive()).to.beFalse()
				Z.Press("key", true) -- the key repeats: still the same press
				expect(Z.IsActive()).to.beFalse()

				Z.Press("key", false)
				expect(Z.State.blocked).to.beFalse()
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "a release that never comes (the chat or a panel took the keyboard): the key is found up by the poll after two frames, the zoom closes, and the next press opens it",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				state.world.keyUp = true
				Z.Guard()
				expect(Z.IsActive()).to.beTrue() -- one frame: the key may not have been seen down yet
				Z.Guard() -- (Think and CalcView both ask in one frame: still that one frame)
				expect(Z.IsActive()).to.beTrue()
				state.frame = state.frame + 1
				Z.Guard()
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("release")
				expect(Z.State.held.key).to.beFalse()

				state.world.keyUp = false
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "a key that is up one frame and down the next is not a lost release",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				state.world.keyUp = true
				Z.Guard()
				state.frame = state.frame + 1
				state.world.keyUp = false
				Z.Guard()
				state.frame = state.frame + 1
				state.world.keyUp = true
				Z.Guard()
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "toggle mode: the poll clears a stale key but leaves the zoom open (it was opened by a press that is over)",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("1")
				Z.Press("key", true)
				state.world.keyUp = true
				Z.Guard()
				state.frame = state.frame + 1
				Z.Guard()
				expect(Z.IsActive()).to.beTrue()
				expect(Z.State.held.key).to.beFalse()
			end
		},
		{
			name = "a world where nothing is held and nothing is open costs nothing: Guard does not even read it",
			func = function(state)
				local Z = GryMod.SuitZoom
				local reads = 0
				local read = Z.Read
				Z.Read = function(sit) reads = reads + 1 return read(sit) end
				Z.Guard()
				Z.Read = read
				expect(reads).to.equal(0)
			end
		},
		{
			name = "the option switched off while the zoom is up ends it (the setting's own callback, and Guard)",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Press("key", true)
				setting(OWN):SetString("0")
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("disabled")
				expect(Z.State.held.key).to.beFalse()

				-- Guard alone also catches it (the callback is not run by every way of changing a setting)
				setting(OWN):SetString("1")
				Z.Press("key", true)
				Z.State.held.key = true
				local convar = setting(OWN)
				local real = Z.Wanted
				Z.Wanted = function() return false end
				Z.Guard()
				Z.Wanted = real
				expect(Z.IsActive()).to.beFalse()
				expect(convar:GetBool()).to.beTrue()
			end
		},
		{
			name = "the events that cannot be polled end the zoom at once: the chat opening, the Q and C menus, the main menu (and it does not stop the menu opening: nothing is returned), a map change, a level start, the HUD saying the suit is down",
			func = function(state)
				local Z = GryMod.SuitZoom
				local hooks = hook.GetTable()

				for _, event in ipairs({{"StartChat", "chat"}, {"OnSpawnMenuOpen", "spawnmenu"}, {"OnContextMenuOpen", "contextmenu"},
					{"OnPauseMenuShow", "pause"}, {"ShutDown", "shutdown"}, {"InitPostEntity", "init"}}) do
					local fn = hooks[event[1]] and hooks[event[1]]["GRYSUITZOOM"]
					expect(fn).toNot.beNil()

					Z.Reset()
					Z.Press("key", true)
					expect(Z.IsActive()).to.beTrue()
					expect(fn()).to.beNil()
					expect(Z.IsActive()).to.beFalse()
					expect(Z.State.reason).to.equal(event[2])
				end

				local status = hooks["GryMod_HUDStatus"]["GRYSUITZOOM"]
				Z.Reset()
				Z.Press("key", true)
				status(0)
				status(2)
				expect(Z.IsActive()).to.beTrue()
				status(1)
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("malfunction")
			end
		},
		{
			name = "a map change or a level start also forgets a key that was held and a block that was waiting for its release",
			func = function(state)
				local Z = GryMod.SuitZoom
				local hooks = hook.GetTable()
				Z.Press("key", true)
				Z.Exit("death")
				expect(Z.State.blocked).to.beTrue()
				hooks["InitPostEntity"]["GRYSUITZOOM"]()
				expect(Z.State.blocked).to.beFalse()
				expect(Z.State.held.key).to.beFalse()
				hooks["ShutDown"]["GRYSUITZOOM"]()
				expect(Z.State.held.bind).to.beFalse()
			end
		},
		{
			name = "+gry_zoom and -gry_zoom, bound by the player to any key, act like the key; they are real console commands; the key hooks only take the chosen key and only the first time a press is predicted",
			func = function(state)
				local Z = GryMod.SuitZoom
				Z.Command(nil, "+gry_zoom")
				expect(Z.IsActive()).to.beTrue()
				Z.Command(nil, "-gry_zoom")
				expect(Z.IsActive()).to.beFalse()

				local commands = concommand.GetTable()
				expect(commands["+gry_zoom"]).toNot.beNil()
				expect(commands["-gry_zoom"]).toNot.beNil()

				-- (the hooks of the engine are the key factory's: a second source, the poll is the first)
				local down = hook.GetTable().PlayerButtonDown["GRYKEYBINDER"]
				local up = hook.GetTable().PlayerButtonUp["GRYKEYBINDER"]
				local ply = LocalPlayer()
				local first = IsFirstTimePredicted
				-- (a calm world of the test's own: the real one has whatever panel another test left)
				local B = GryMod.KeyBinder
				local realRead = B.Read
				B.Read = function(sit) sit.pause, sit.console, sit.cursor, sit.focusPanel, sit.typing, sit.focus = false, false, false, false, false, true return sit end

				local ok, err = pcall(function()
					IsFirstTimePredicted = function() return false end
					down(ply, KEY_F7)
					expect(Z.IsActive()).to.beFalse()
					IsFirstTimePredicted = function() return true end
					down(ply, KEY_F8) -- not the chosen key
					expect(Z.IsActive()).to.beFalse()
					down(ply, KEY_F7)
					expect(Z.IsActive()).to.beTrue()
					IsFirstTimePredicted = function() return false end
					up(ply, KEY_F7)
					expect(Z.IsActive()).to.beTrue()
					IsFirstTimePredicted = function() return true end
					up(ply, KEY_F8)
					expect(Z.IsActive()).to.beTrue()
					up(ply, KEY_F7)
					expect(Z.IsActive()).to.beFalse()

					-- no key chosen: the hooks leave every button alone
					setting(KEY):SetString("0")
					down(ply, KEY_F7)
					expect(Z.IsActive()).to.beFalse()
					down(ply, 0)
					expect(Z.IsActive()).to.beFalse()
				end)

				IsFirstTimePredicted = first
				B.Read = realRead

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the wheel while the zoom is up: the notch is taken whatever the bind says when the button is the wheel's (113 / 112), and so are invprev / invnext; one notch steps the stage once (up zooms in), at an end it is still taken and plays nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local ply = LocalPlayer()
				local played = {}
				local playSound, sounds = GryMod.PlaySound, M.SoundsEnabled
				GryMod.PlaySound = function(path) played[#played + 1] = path return true end
				M.SoundsEnabled = function() return true end

				local ok, err = pcall(function()
					M.ZoomReset(M.ZoomState)
					M.ZoomState.stage, M.ZoomState.active = 1, true
					Z.Press("key", true)
					expect(Z.IsActive()).to.beTrue()

					expect(Z.BindPress(ply, "invprev", true, MOUSE_WHEEL_UP)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)
					expect(played[1]).to.equal(M.Sounds.zoom_in)

					-- the wheel re-bound to something else: still the wheel
					expect(Z.BindPress(ply, "+jump", true, MOUSE_WHEEL_UP)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(3)

					-- the end: taken, no step, no sound
					expect(Z.BindPress(ply, "invprev", true, MOUSE_WHEEL_UP)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(3)
					expect(#played).to.equal(2)

					expect(Z.BindPress(ply, "invnext", true, MOUSE_WHEEL_DOWN)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)
					expect(played[3]).to.equal(M.Sounds.zoom_out)
					expect(Z.BindPress(ply, "+jump", true, MOUSE_WHEEL_DOWN)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(1)

					-- a bind name alone (no button: a key bound to invprev)
					expect(Z.BindPress(ply, "invprev", true, KEY_F7)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)

					-- the release of a wheel bind is taken and steps nothing
					expect(Z.BindPress(ply, "invprev", false, MOUSE_WHEEL_UP)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)

					-- the zoom is still up: the wheel did not close it
					expect(Z.IsActive()).to.beTrue()
				end)

				GryMod.PlaySound, M.SoundsEnabled = playSound, sounds
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the wheel with no zoom up (nothing opened, or an Exit just happened) is the game's: weapon switching works, and nothing steps",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local ply = LocalPlayer()

				M.ZoomReset(M.ZoomState)
				expect(Z.BindPress(ply, "invprev", true, MOUSE_WHEEL_UP)).to.beNil()
				expect(Z.BindPress(ply, "invnext", true, MOUSE_WHEEL_DOWN)).to.beNil()
				expect(Z.BindPress(ply, "+jump", true, MOUSE_WHEEL_UP)).to.beNil()

				Z.Press("key", true)
				Z.Exit("death")
				expect(Z.BindPress(ply, "invprev", true, MOUSE_WHEEL_UP)).to.beNil()
				expect(M.ZoomState.stage).to.equal(0)
			end
		},
		{
			name = "the weapon keys (slotN, lastinv, use <weapon>) are not taken while the zoom is up: they end it (and the weapon changes); other binds do not",
			func = function(state)
				local Z = GryMod.SuitZoom
				local ply = LocalPlayer()

				for _, bind in ipairs({"slot1", "slot6", "lastinv", "use weapon_pistol"}) do
					Z.Reset()
					Z.Press("key", true)
					expect(Z.IsActive()).to.beTrue()
					expect(Z.BindPress(ply, bind, true, KEY_1)).to.beNil()
					expect(Z.IsActive()).to.beFalse()
					expect(Z.State.reason).to.equal("weaponkey")
				end

				-- a bind that has nothing to do with the weapon leaves it open
				Z.Reset()
				Z.Press("key", true)
				expect(Z.BindPress(ply, "+jump", true, KEY_SPACE)).to.beNil()
				expect(Z.BindPress(ply, "+attack", true, MOUSE_LEFT)).to.beNil()
				expect(Z.IsActive()).to.beTrue()

				-- with nothing up they are the game's and change nothing here
				Z.Reset()
				local before = #state.events
				expect(Z.BindPress(ply, "slot2", true, KEY_2)).to.beNil()
				expect(#state.events).to.equal(before)
			end
		},
		{
			name = "the wheel's delta in the command is zeroed only while the zoom is up (a weapon that reads it, the physgun, would scroll under the zoom)",
			func = function(state)
				local Z = GryMod.SuitZoom
				local wheel = 0
				local sets = 0
				local cmd = {
					RemoveKey = function() end,
					GetMouseWheel = function() return wheel end,
					SetMouseWheel = function(_, n) sets = sets + 1 wheel = n end
				}

				wheel = 1
				Z.StartCommand(LocalPlayer(), cmd)
				expect(wheel).to.equal(1)
				expect(sets).to.equal(0)

				Z.Press("key", true)
				Z.StartCommand(LocalPlayer(), cmd)
				expect(wheel).to.equal(0)
			end
		},
		{
			name = "the view: with the own zoom up CalcView gives the stage's field of view (the origin and angles are the game's), nothing when it is down, and nothing in a vehicle even if it is forced up; it stamps the frame so that a view taken by another addon is noticed; the sensitivity follows and is never -1",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local clock, enabled = M.Now, M.Enabled
				local now, inVehicle = 0, false
				local ply = {
					IsValid = function() return true end,
					Alive = function() return true end,
					KeyDown = function() return false end,
					InVehicle = function() return inVehicle end,
					GetInfoNum = function(_, name, default) return name == "fov_desired" and 100 or default end
				}
				local origin, angles = Vector(1, 2, 3), Angle(4, 5, 6)

				M.Now = function() return now end
				M.Enabled = function() return true end

				local ok, err = pcall(function()
					M.ZoomReset(M.ZoomState)

					-- down: nothing
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).to.beNil()
					expect(M.AdjustSensitivity(ply)).to.beNil()

					-- up
					Z.State.active = true
					Z.State.frame = -100
					local view = M.CalcView(ply, origin, angles, 100, 3, 8000)
					expect(view).toNot.beNil()
					expect(view.origin).to.equal(origin)
					expect(view.angles).to.equal(angles)
					expect(Z.State.frame).to.equal(FrameNumber())
					now = 0.2
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000).fov).to.aboutEqual(M.StageFov(100, 2), 1e-6)
					expect(M.AdjustSensitivity(ply)).to.aboutEqual(M.StageFov(100, 2) / 100, 1e-6)

					-- a vehicle: the game's own view, and the stages' state is gone
					inVehicle = true
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).to.beNil()
					expect(M.ZoomState.active).to.beFalse()
					expect(M.AdjustSensitivity(ply)).to.beNil()
					inVehicle = false

					-- the zoom down again: nothing, once the stages are back at the base
					Z.State.active = false
					now = 5
					M.CalcView(ply, origin, angles, 100, 3, 8000)
					now = 6
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).to.beNil()
				end)

				M.Now, M.Enabled = clock, enabled
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the Half-Life 2 zoom overlay (CHudZoom) is hidden while the own zoom is up, and only then",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local enabled = M.Enabled
				M.Enabled = function() return true end

				local ok, err = pcall(function()
					expect(hook.Run("HUDShouldDraw", "CHudZoom") == false).to.beFalse()
					Z.State.active = true
					expect(hook.Run("HUDShouldDraw", "CHudZoom") == false).to.beTrue()
					expect(hook.Run("HUDShouldDraw", "CHudCloseCaption") == false).to.beFalse()
				end)

				M.Enabled = enabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "a hard Exit puts the binoculars away at once: the stages, the sway, the scan, the outlines and the sound loop are all back at their start, and the picture is hidden with no closing animation",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local drop = state.saved.drop

				state.drops = 0
				M.Drop = drop

				M.ZoomState.stage, M.ZoomState.active, M.ZoomState.fov = 2, true, 40
				M.SwayState.t, M.SwayState.last = 1, 2
				M.ScanState.timer = 0.3
				M.Silhouettes[1] = {}
				M.Drop()
				expect(M.ZoomState.stage).to.equal(0)
				expect(M.ZoomState.active).to.beFalse()
				expect(M.SwayState.last).to.beNil()
				expect(M.ScanState.timer).to.equal(0)
				expect(#M.Silhouettes).to.equal(0)
				expect(M.IsUp()).to.beFalse()
			end
		},
		{
			name = "the zoom key refuses 0, Escape, the wheel and the quick menu's key; the quick menu key refuses the zoom's; any other key is saved",
			func = function(state)
				local Z = GryMod.SuitZoom
				local menu = GryMod.MenuKey
				local menuKey = menu.convar:GetString()

				local ok, err = pcall(function()
					menu.convar:SetInt(KEY_F8)
					expect(Z.Key.SetKey(0)).to.beFalse()
					expect(Z.Key.SetKey(KEY_ESCAPE)).to.beFalse()
					expect(Z.Key.SetKey(MOUSE_WHEEL_UP)).to.beFalse()
					expect(Z.Key.SetKey(MOUSE_WHEEL_DOWN)).to.beFalse()
					expect(Z.Key.SetKey(KEY_F8)).to.beFalse()
					expect(Z.Key.Chosen()).to.equal(KEY_F7) -- (set by beforeEach)

					expect(Z.Key.SetKey(KEY_F9)).to.beTrue()
					expect(Z.Key.Chosen()).to.equal(KEY_F9)

					-- and the other way round
					expect(menu.SetKey(KEY_F9)).to.beFalse()
					expect(menu.convar:GetInt()).to.equal(KEY_F8)
					expect(menu.SetKey(KEY_F10)).to.beTrue()
				end)

				menu.convar:SetString(menuKey)
				menu.HidePrompt()
				Z.Key.HidePrompt()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the spawn message of the server asks for the zoom key too, a little after the quick menu's prompt",
			func = function(state)
				local Z = GryMod.SuitZoom
				local receiver = net.Receivers and net.Receivers["gry_spawn"]
				expect(receiver).toNot.beNil()

				local scheduled = {}
				local simple = timer.Simple
				timer.Simple = function(delay, fn) scheduled[#scheduled + 1] = {delay, fn} end

				local ok, err = pcall(receiver, 0)
				timer.Simple = simple

				if not ok then
					error(err, 0)
				end

				local zoomDelay, menuDelay
				for _, entry in ipairs(scheduled) do
					if entry[2] == Z.MaybePrompt then zoomDelay = entry[1] end
					if entry[2] == GryMod.MenuKey.MaybePrompt then menuDelay = entry[1] end
				end

				expect(menuDelay).toNot.beNil()
				expect(zoomDelay).toNot.beNil()
				expect(zoomDelay >= menuDelay).to.beTrue()
			end
		},
		{
			name = "the options panel has the own zoom check box and a key picker for the zoom key that saves through SetKey (and refuses what it refuses); opening the panel writes nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				local menu = GryMod.MenuKey
				local writes = {}
				local realRun = RunConsoleCommand
				local found, binders = {}, {}
				local menuKey = menu.convar:GetString()
				local before = {setting(OWN):GetString(), setting(KEY):GetString(), setting(MODE):GetString(), setting(TAP):GetString()}
				local panel

				local ok, err = pcall(function()
					RunConsoleCommand = function(name) writes[#writes + 1] = tostring(name) end
					menu.convar:SetString(tostring(KEY_F8))
					panel = vgui.Create("ControlPanel")
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							elseif child.ClassName == "DBinder" then
								binders[child:GetValue()] = child
							end

							walk(child)
						end
					end

					walk(panel)
					RunConsoleCommand = realRun

					expect(found[OWN]).to.beTrue()
					-- (the mode selector and the threshold slider: see the case of the options panel for the zoom modes)
					expect(#writes).to.equal(0)
					expect(setting(OWN):GetString()).to.equal(before[1])
					expect(setting(KEY):GetString()).to.equal(before[2])
					expect(setting(MODE):GetString()).to.equal(before[3])
					expect(setting(TAP):GetString()).to.equal(before[4])

					-- the quick menu's picker is still there, and the zoom's is the one showing the zoom key (F7 from beforeEach)
					expect(binders[KEY_F8]).toNot.beNil()
					local binder = binders[KEY_F7]
					expect(binder).toNot.beNil()

					binder:OnChange(KEY_F9)
					expect(Z.Key.Chosen()).to.equal(KEY_F9)

					-- refused (the quick menu's key): not saved, and the picker shows the key that is saved
					binder:OnChange(KEY_F8)
					expect(Z.Key.Chosen()).to.equal(KEY_F9)
					expect(binder:GetValue()).to.equal(KEY_F9)
				end)

				RunConsoleCommand = realRun
				menu.convar:SetString(menuKey)

				if IsValid(panel) then
					panel:Remove()
				end

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the options panel has the zoom key behaviour selector (hold, toggle, automatic) and the threshold slider (100 to 600 ms) right under the zoom key picker; it shows the saved mode, writes the setting only when a line is picked, and opening the panel writes nothing",
			func = function(state)
				local realRun = RunConsoleCommand
				local writes = {}
				local order = {}
				local combo, slider, panel

				local ok, err = pcall(function()
					RunConsoleCommand = function(name, value) writes[#writes + 1] = tostring(name) .. "=" .. tostring(value) end
					setting(MODE):SetString("1")
					panel = vgui.Create("ControlPanel")
					GryMod.KeysOptions(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DBinder" then
								order[#order + 1] = "binder"
							elseif child.ClassName == "DComboBox" then
								order[#order + 1] = "combo"
								combo = child
							elseif child.ClassName == "DNumSlider" then
								order[#order + 1] = "slider"
								slider = child
							elseif child.ClassName == "DCheckBoxLabel" then
								order[#order + 1] = "box"
							end

							walk(child)
						end
					end

					walk(panel)

					expect(combo).toNot.beNil()
					expect(slider).toNot.beNil()

					-- the zoom key picker, then the selector, then the slider
					expect(order[1]).to.equal("binder")
					expect(order[2]).to.equal("binder")
					expect(order[3]).to.equal("combo")
					expect(order[4]).to.equal("slider")

					-- three lines, in the order of the modes, and the saved mode is the one shown; opening wrote nothing
					for mode = 0, 2 do
						expect(combo:GetOptionData(mode + 1)).to.equal(mode)
					end

					expect(combo:GetOptionText(4)).to.beNil()
					expect(string.find(combo:GetValue(), "Toggle", 1, true)).toNot.beNil()
					expect(#writes).to.equal(0)

					expect(slider:GetMin()).to.equal(100)
					expect(slider:GetMax()).to.equal(600)

					-- picking a line writes the mode
					combo:ChooseOptionID(3)
					expect(writes[1]).to.equal(MODE .. "=2")
					combo:ChooseOptionID(1)
					expect(writes[2]).to.equal(MODE .. "=0")
					expect(#writes).to.equal(2)
				end)

				RunConsoleCommand = realRun

				if IsValid(panel) then
					panel:Remove()
				end

				if not ok then
					error(err, 0)
				end
			end
		},
		-- ------------------------------------------------------------------------------------------------------------------
		-- The three modes of the key (gry_zoom_mode: 0 hold, 1 toggle, 2 automatic) and the threshold between a short and a long press
		-- ------------------------------------------------------------------------------------------------------------------
		{
			name = "PressAction (pure): hold opens at the press and closes at the release; toggle opens and closes at a press and never at a release; automatic toggles at a press, and at the release closes only what a long press held (the threshold itself is long)",
			func = function(state)
				local P = GryMod.SuitZoom.PressAction
				local TAPMS = 250

				-- a press: (mode, wasOpen)
				for mode = 0, 2 do
					expect(P(mode, false)).to.equal("open")
				end

				expect(P(0, true)).to.beNil()
				expect(P(1, true)).to.equal("close")
				expect(P(2, true)).to.equal("close")

				-- a release: (mode, wasOpen, heldMs, tapMs)
				for _, ms in ipairs({0, 100, 249, 250, 5000}) do
					expect(P(0, true, ms, TAPMS)).to.equal("close")
					expect(P(1, true, ms, TAPMS)).to.beNil()

					-- nothing open at the release: nothing to close, in every mode
					for mode = 0, 2 do
						expect(P(mode, false, ms, TAPMS)).to.beNil()
					end
				end

				expect(P(2, true, 0, TAPMS)).to.beNil()
				expect(P(2, true, 249, TAPMS)).to.beNil()
				expect(P(2, true, 250, TAPMS)).to.equal("close")
				expect(P(2, true, 5000, TAPMS)).to.equal("close")

				-- the threshold is the player's
				expect(P(2, true, 150, 100)).to.equal("close")
				expect(P(2, true, 150, 600)).to.beNil()
			end
		},
		{
			name = "Mode and TapMs read the settings: 0, 1 and 2 are the modes (a value out of range, which the setting itself holds back, is the automatic one), the threshold is held between 100 and 600 ms",
			func = function(state)
				local Z = GryMod.SuitZoom

				for _, case in ipairs({{"0", 0}, {"1", 1}, {"2", 2}, {"3", 2}, {"7", 2}}) do
					setting(MODE):SetString(case[1])
					expect(Z.Mode()).to.equal(case[2])
				end

				for _, case in ipairs({{"250", 250}, {"100", 100}, {"600", 600}, {"10", 100}, {"9000", 600}}) do
					setting(TAP):SetString(case[1])
					expect(Z.TapMs()).to.equal(case[2])
				end
			end
		},
		{
			name = "automatic mode, a short press: the zoom stays open after the release, the next press closes it, and the release of that press does nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("2")

				state.now = 10
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				state.now = 10.1
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				expect(#state.events).to.equal(1)

				-- later: the second press closes at once (a long wait in between changes nothing)
				state.now = 30
				Z.Press("key", true)
				expect(Z.IsActive()).to.beFalse()
				expect(state.events[2][1]).to.beFalse()

				-- and its release, short or long, leaves it closed
				state.now = 31
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
				expect(#state.events).to.equal(2)

				-- (a new short press opens it again)
				state.now = 40
				Z.Press("key", true)
				state.now = 40.05
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "automatic mode, a long press: the zoom is open while the key is down and closes at the release (a press of exactly the threshold is long, one millisecond less is short); the threshold is the setting's",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("2")

				state.now = 10
				Z.Press("key", true)
				state.now = 10.6
				expect(Z.IsActive()).to.beTrue()
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
				expect(state.events[2][2]).to.equal("release")

				-- the edge of the threshold (250 ms)
				Z.Reset()
				state.now = 20
				Z.Press("key", true)
				state.now = 20.249
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Reset()
				state.now = 30
				Z.Press("key", true)
				state.now = 30.25
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()

				-- another threshold
				setting(TAP):SetString("500")
				Z.Reset()
				state.now = 40
				Z.Press("key", true)
				state.now = 40.4
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Reset()
				state.now = 50
				Z.Press("key", true)
				state.now = 50.5
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()
			end
		},
		{
			name = "hold mode: a short press opens the zoom and its release closes it, however short; toggle mode: a long press does not close it at the release",
			func = function(state)
				local Z = GryMod.SuitZoom

				setting(MODE):SetString("0")
				state.now = 1
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
				state.now = 1.02
				Z.Press("key", false)
				expect(Z.IsActive()).to.beFalse()

				setting(MODE):SetString("1")
				Z.Reset()
				state.now = 2
				Z.Press("key", true)
				state.now = 9
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				state.now = 10
				Z.Press("key", true)
				expect(Z.IsActive()).to.beFalse()
			end
		},
		{
			name = "the modes with two sources of the key (the chosen key and a +gry_zoom bind): one press, timed from the first one down, ended when the last one is up",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("2")

				state.now = 5
				Z.Press("key", true)
				state.now = 5.1
				Z.Press("bind", true)
				state.now = 5.6
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Press("bind", false)
				expect(Z.IsActive()).to.beFalse()
			end
		},
		{
			name = "automatic mode and a forced exit: a zoom kept open by a short press ends with a death and the next short press opens it again; a death during a long press blocks the key until it is let go, and that release (long) does nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("2")

				-- opened by a short press, then the player dies
				state.now = 1
				Z.Press("key", true)
				state.now = 1.1
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				state.world.alive = false
				Z.Guard()
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("death")
				state.world.alive = true
				state.now = 5
				Z.Press("key", true)
				state.now = 5.1
				Z.Press("key", false)
				expect(Z.IsActive()).to.beTrue()
				Z.Reset()

				-- the player dies with the key down: nothing reopens, and the release is not a press
				state.events = {}
				state.now = 10
				Z.Press("key", true)
				state.world.alive = false
				Z.Guard()
				expect(Z.State.blocked).to.beTrue()
				state.world.alive = true
				state.now = 12
				Z.Press("key", false)
				expect(Z.State.blocked).to.beFalse()
				expect(Z.IsActive()).to.beFalse()
				expect(#state.events).to.equal(2)

				-- (and the next press works as usual)
				state.now = 13
				Z.Press("key", true)
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "automatic mode and a release that never came (found by the poll after two frames): a short press stays open, a long one closes",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(MODE):SetString("2")

				state.now = 1
				Z.Press("key", true)
				state.now = 1.1
				state.world.keyUp = true
				Z.Guard()
				state.frame = state.frame + 1
				Z.Guard()
				expect(Z.IsActive()).to.beTrue()
				expect(Z.State.held.key).to.beFalse()

				Z.Reset()
				state.frame = state.frame + 1
				state.world.keyUp = false
				state.now = 5
				Z.Press("key", true)
				state.now = 5.8
				state.world.keyUp = true
				Z.Guard()
				state.frame = state.frame + 1
				Z.Guard()
				expect(Z.IsActive()).to.beFalse()
				expect(Z.State.reason).to.equal("release")
			end
		},
		-- ------------------------------------------------------------------------------------------------------------------
		-- The zoom is a zoom of its own, apart from the Half-Life 2 suit zoom (+zoom): that one is never touched. Its key is the player's
		-- (gry_zoom_key, or `bind <key> +gry_zoom`), and until the player has chosen one a default is computed: the first of H, J, K, N
		-- that nothing is bound to. The default is never written to the player's settings.
		-- ------------------------------------------------------------------------------------------------------------------
		{
			name = "the Half-Life 2 zoom is never touched, whatever the own zoom has: +zoom (also an alias) and -zoom go on to the game, IN_ZOOM stays in the command, with the option on or off, a key chosen or not",
			func = function(state)
				local Z = GryMod.SuitZoom
				local ply = LocalPlayer()
				local removed = {}
				local cmd = {RemoveKey = function(_, key) removed[#removed + 1] = key end, SetMouseWheel = function() end}
				local translate = input.TranslateAlias
				input.TranslateAlias = function(command) return command == "myzoom" and "+zoom" or nil end

				local ok, err = pcall(function()
					for _, own in ipairs({"1", "0"}) do
						for _, key in ipairs({tostring(KEY_F7), "0"}) do
							setting(OWN):SetString(own)
							setting(KEY):SetString(key)
							Z.ForgetBinding()

							for _, bind in ipairs({"+zoom", "-zoom", "myzoom"}) do
								expect(Z.BindPress(ply, bind, true, KEY_B)).to.beNil()
								expect(Z.BindPress(ply, bind, false, KEY_B)).to.beNil()
							end

							-- (also with the zoom up: the wheel is ours, +zoom is not)
							Z.Reset()
							Z.Press("key", true)
							expect(Z.BindPress(ply, "+zoom", true, KEY_B)).to.beNil()
							Z.Reset()

							Z.StartCommand(ply, cmd)
						end
					end

					expect(#removed).to.equal(0)
				end)

				input.TranslateAlias = translate

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "StartCommand only zeroes the wheel's delta, and only while the own zoom is up: IN_ZOOM and every other button stay in the command, other players' commands are not touched",
			func = function(state)
				local Z = GryMod.SuitZoom
				local removed, wheel = {}, nil
				local cmd = {RemoveKey = function(_, key) removed[#removed + 1] = key end, SetMouseWheel = function(_, n) wheel = n end}

				Z.StartCommand(LocalPlayer(), cmd)
				expect(wheel).to.beNil()

				Z.Press("key", true)
				Z.StartCommand(LocalPlayer(), cmd)
				expect(wheel).to.equal(0)

				wheel = nil
				Z.StartCommand({}, cmd)
				expect(wheel).to.beNil()
				expect(#removed).to.equal(0)
			end
		},
		{
			name = "the binoculars follow the Half-Life 2 zoom key (IN_ZOOM) OR the own zoom, whatever the option says: either one asks, both ask one state (one view, one answer), closing one does not close the other; a dead player never zooms; the crosshair does the same",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local cross = GryMod.FlashCrosshair
				local zooming, alive = false, true
				local enabled = M.Enabled
				local ply = {
					IsValid = function() return true end,
					Alive = function() return alive end,
					KeyDown = function(_, key) return key == IN_ZOOM and zooming end
				}

				M.Enabled = function() return true end

				local ok, err = pcall(function()
					for _, own in ipairs({"1", "0"}) do
						setting(OWN):SetString(own)
						Z.Reset()
						zooming = false

						-- nothing asks
						expect(M.Wanted(ply)).to.beFalse()
						expect(cross == nil or cross.Zooming(ply)).to.beFalse()

						-- the game's key alone, as it always was
						zooming = true
						expect(M.Wanted(ply)).to.beTrue()
						expect(cross == nil or cross.Zooming(ply)).to.beTrue()
						zooming = false
					end

					-- the own zoom alone
					setting(OWN):SetString("1")
					Z.Reset()
					Z.State.active = true
					expect(M.Wanted(ply)).to.beTrue()
					expect(cross == nil or cross.Zooming(ply)).to.beTrue()

					-- both: one answer, and either one let go leaves the other
					zooming = true
					expect(M.Wanted(ply)).to.beTrue()
					Z.State.active = false
					expect(M.Wanted(ply)).to.beTrue()
					Z.State.active = true
					zooming = false
					expect(M.Wanted(ply)).to.beTrue()
					Z.State.active = false
					expect(M.Wanted(ply)).to.beFalse()

					-- a dead player never zooms, by either
					alive = false
					zooming = true
					Z.State.active = true
					expect(M.Wanted(ply)).to.beFalse()
					expect(cross == nil or cross.Zooming(ply)).to.beFalse()
				end)

				M.Enabled = enabled
				Z.Reset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "both zooms asked together make one view: the stage state is one (it is not opened twice), the view is the stage's, and when the own zoom ends while the game's key is held the binoculars stay up",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local clock, enabled = M.Now, M.Enabled
				local now, zooming = 0, false
				local ply = {
					IsValid = function() return true end,
					Alive = function() return true end,
					KeyDown = function(_, key) return key == IN_ZOOM and zooming end,
					InVehicle = function() return false end,
					GetInfoNum = function(_, name, default) return name == "fov_desired" and 100 or default end
				}
				local origin, angles = Vector(1, 2, 3), Angle(4, 5, 6)

				M.Now = function() return now end
				M.Enabled = function() return true end

				local ok, err = pcall(function()
					M.ZoomReset(M.ZoomState)

					-- the game's key alone: the binoculars (the stages are on by default)
					zooming = true
					local view = M.CalcView(ply, origin, angles, 100, 3, 8000)
					expect(view).toNot.beNil()
					expect(M.ZoomState.active).to.beTrue()

					-- the own zoom opens as well: the same state, the same view
					Z.Press("key", true)
					expect(Z.IsActive()).to.beTrue()
					state.frame = state.frame + 1
					now = 0.3
					local both = M.CalcView(ply, origin, angles, 100, 3, 8000)
					expect(both).toNot.beNil()
					expect(M.ZoomState.active).to.beTrue()
					expect(both.fov).to.aboutEqual(M.StageFov(100, 2), 1e-6)

					-- the own zoom ends (the key let go): the game's key still holds the binoculars up
					Z.Press("key", false)
					expect(Z.IsActive()).to.beFalse()
					state.frame = state.frame + 1
					now = 0.6
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).toNot.beNil()
					expect(M.ZoomState.active).to.beTrue()
					expect(M.Wanted(ply)).to.beTrue()

					-- and the other way round: the game's key let go, the own zoom stays
					Z.Press("key", true)
					zooming = false
					state.frame = state.frame + 1
					now = 0.9
					expect(M.Wanted(ply)).to.beTrue()
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).toNot.beNil()
					expect(M.ZoomState.active).to.beTrue()
				end)

				M.Now, M.Enabled = clock, enabled
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the own zoom on the stages are on whatever gry_binoculars_stages says as soon as the zoom has a key (the wheel is its interface); with the option off, or no key at all, they follow their own setting as before",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local stages = setting("gry_binoculars_stages")
				local saved = stages:GetString()

				local ok, err = pcall(function()
					stages:SetString("0")
					setting(OWN):SetString("0")
					expect(M.StagesEnabled()).to.beFalse()
					stages:SetString("1")
					expect(M.StagesEnabled()).to.beTrue()

					stages:SetString("0")
					setting(OWN):SetString("1")
					setting(KEY):SetString(tostring(KEY_F7))
					expect(M.StagesEnabled()).to.beTrue()

					-- no key, no default free: the game's zoom, as before
					setting(KEY):SetString("0")
					state.binds[KEY_H], state.binds[KEY_J], state.binds[KEY_K], state.binds[KEY_N] = "a", "b", "c", "d"
					Z.ForgetBinding()
					expect(M.StagesEnabled()).to.beFalse()
				end)

				stages:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "DefaultKey is the first of H, J, K, N that nothing is bound to in the game (a free key: LookupKeyBinding gives nothing), then none when they are all taken; the quick menu's chosen key is not free",
			func = function(state)
				local Z = GryMod.SuitZoom
				local menu = GryMod.MenuKey
				local menuKey = menu.convar:GetString()

				local ok, err = pcall(function()
					menu.convar:SetString(tostring(KEY_F8))
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_H)

					-- bound to something (any bind of the game: the Half-Life 2 zoom, ours, or another one)
					state.binds[KEY_H] = "+zoom"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_J)
					state.binds[KEY_H] = "+gry_zoom"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_J)
					state.binds[KEY_J] = "+crysishud"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_K)
					state.binds[KEY_K] = "kill"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_N)
					state.binds[KEY_N] = "+use"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.beNil()

					-- an empty bind is no bind
					state.binds = {[KEY_H] = ""}
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_H)

					-- the key of the quick menu (chosen in its options, not a bind of the game) is not ours to take
					state.binds = {}
					menu.convar:SetString(tostring(KEY_H))
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_J)
				end)

				menu.convar:SetString(menuKey)
				Z.ForgetBinding()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "DefaultKey is looked up once in half a second, not at every call; a key the player binds in the meantime is seen at the next look (the default moves to the next free key, or disappears)",
			func = function(state)
				local Z = GryMod.SuitZoom
				local lookup = input.LookupKeyBinding
				local asked = 0

				local ok, err = pcall(function()
					input.LookupKeyBinding = function(code) asked = asked + 1 return state.binds[code] end
					Z.ForgetBinding()
					state.now = 100

					for _ = 1, 50 do
						expect(Z.DefaultKey()).to.equal(KEY_H)
					end

					expect(asked).to.beLessThan(5)
					local first = asked

					-- the player binds H: not seen before the half second is over
					state.binds[KEY_H] = "+jump"
					state.now = 100.3
					expect(Z.DefaultKey()).to.equal(KEY_H)
					expect(asked).to.equal(first)
					state.now = 100.6
					expect(Z.DefaultKey()).to.equal(KEY_J)
					expect(asked).to.beGreaterThan(first)
				end)

				input.LookupKeyBinding = lookup
				Z.ForgetBinding()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "HasKey: the own zoom has a key when one is chosen, when +gry_zoom is bound, or when a default is free; with all of the default keys taken and nothing chosen it has none; with the option off never",
			func = function(state)
				local Z = GryMod.SuitZoom
				local lookup = input.LookupBinding

				local ok, err = pcall(function()
					input.LookupBinding = function() return nil end
					setting(OWN):SetString("1")

					-- a default is free
					setting(KEY):SetString("0")
					Z.ForgetBinding()
					expect(Z.HasKey()).to.beTrue()

					-- none free, none chosen
					state.binds[KEY_H], state.binds[KEY_J], state.binds[KEY_K], state.binds[KEY_N] = "a", "b", "c", "d"
					Z.ForgetBinding()
					expect(Z.HasKey()).to.beFalse()

					-- a key chosen
					setting(KEY):SetString(tostring(KEY_F7))
					expect(Z.HasKey()).to.beTrue()

					-- a +gry_zoom bind
					setting(KEY):SetString("0")
					input.LookupBinding = function(command) return command == "+gry_zoom" and "MOUSE4" or nil end
					Z.ForgetBinding()
					expect(Z.HasKey()).to.beTrue()

					-- the option off
					setting(OWN):SetString("0")
					setting(KEY):SetString(tostring(KEY_F7))
					expect(Z.HasKey()).to.beFalse()
				end)

				input.LookupBinding = lookup
				Z.ForgetBinding()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the default key opens the zoom with nothing chosen, by the poll, with the three modes (hold, toggle, automatic); the player's settings are not written, and a key held while the chat is open does not zoom",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local down = {}
				local realRead, realDown = B.Read, input.IsButtonDown
				local world = {pause = false, console = false, cursor = false, focusPanel = false, typing = false, focus = true}

				B.Read = function(sit) for k, v in pairs(world) do sit[k] = v end return sit end
				input.IsButtonDown = function(code) return down[code] == true end

				local ok, err = pcall(function()
					setting(KEY):SetString("0")
					Z.ForgetBinding()
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()

					-- hold
					setting(MODE):SetString("0")
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					down[KEY_H] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()

					-- toggle
					setting(MODE):SetString("1")
					state.now = 1
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					state.now = 2
					down[KEY_H] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					down[KEY_H] = false
					Z.Key.Poll()

					-- automatic: short press stays, long press holds
					setting(MODE):SetString("2")
					state.now = 10
					down[KEY_H] = true
					Z.Key.Poll()
					state.now = 10.1
					down[KEY_H] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					state.now = 11
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					state.now = 11.05
					down[KEY_H] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					state.now = 20
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					state.now = 20.5
					down[KEY_H] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()

					-- the chat has the keyboard: an H typed does not zoom
					world.typing = true
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					down[KEY_H] = false
					Z.Key.Poll()
					world.typing = false

					-- nothing was written for the player
					expect(setting(KEY):GetString()).to.equal("0")
					expect(Z.Key.Chosen()).to.equal(0)
				end)

				B.Read, input.IsButtonDown = realRead, realDown

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "a key bound to something else is not the default: the Half-Life 2 key (B, +zoom) never opens the own zoom, and when H is bound the default is the next free key; the zoom of the game on that key is the game's",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local down = {}
				local realRead, realDown = B.Read, input.IsButtonDown

				B.Read = function(sit) sit.pause, sit.console, sit.cursor, sit.focusPanel, sit.typing, sit.focus = false, false, false, false, false, true return sit end
				input.IsButtonDown = function(code) return down[code] == true end

				local ok, err = pcall(function()
					setting(KEY):SetString("0")
					state.binds[KEY_B] = "+zoom"
					state.binds[KEY_H] = "+zoom"
					Z.ForgetBinding()
					expect(Z.DefaultKey()).to.equal(KEY_J)

					Z.Key.Poll()
					down[KEY_B] = true
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					down[KEY_B], down[KEY_H] = false, false
					Z.Key.Poll()

					down[KEY_J] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					down[KEY_J] = false
					Z.Key.Poll()
				end)

				B.Read, input.IsButtonDown = realRead, realDown

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "a key chosen by the player, or a +gry_zoom bind, replaces the default: the default key does nothing any more",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local down = {}
				local realRead, realDown, lookup = B.Read, input.IsButtonDown, input.LookupBinding

				B.Read = function(sit) sit.pause, sit.console, sit.cursor, sit.focusPanel, sit.typing, sit.focus = false, false, false, false, false, true return sit end
				input.IsButtonDown = function(code) return down[code] == true end
				input.LookupBinding = function() return nil end

				local ok, err = pcall(function()
					Z.ForgetBinding()

					-- a key chosen: that one, not H
					setting(KEY):SetString(tostring(KEY_F7))
					Z.Key.Poll()
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					down[KEY_H] = false
					Z.Key.Poll()
					down[KEY_F7] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
					down[KEY_F7] = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()

					-- a +gry_zoom bind (the engine runs +gry_zoom itself): H does nothing
					setting(KEY):SetString("0")
					input.LookupBinding = function(command) return command == "+gry_zoom" and "MOUSE4" or nil end
					Z.ForgetBinding()
					Z.Key.IsBoundCached()
					Z.Key.Poll()
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					expect(Z.Key.Effective()).to.equal(0)
				end)

				B.Read, input.IsButtonDown, input.LookupBinding = realRead, realDown, lookup
				Z.ForgetBinding()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the option off the default key does nothing either",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local down = {}
				local realRead, realDown = B.Read, input.IsButtonDown

				B.Read = function(sit) sit.pause, sit.console, sit.cursor, sit.focusPanel, sit.typing, sit.focus = false, false, false, false, false, true return sit end
				input.IsButtonDown = function(code) return down[code] == true end

				local ok, err = pcall(function()
					setting(KEY):SetString("0")
					setting(OWN):SetString("0")
					Z.ForgetBinding()
					Z.Key.Poll()
					down[KEY_H] = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					expect(#state.events).to.equal(0)
				end)

				B.Read, input.IsButtonDown = realRead, realDown

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the prompt for the zoom key: only with the option on and no key chosen, no +gry_zoom bind and no free default; once per session; it does not sit on the quick menu's prompt",
			func = function(state)
				local Z = GryMod.SuitZoom
				local lookup = input.LookupBinding
				local menu = GryMod.MenuKey

				local ok, err = pcall(function()
					input.LookupBinding = function() return nil end
					setting(KEY):SetString("0")
					Z.Key.HidePrompt()

					-- the option off: nothing asked, and nothing counted as asked
					state.binds[KEY_H], state.binds[KEY_J], state.binds[KEY_K], state.binds[KEY_N] = "a", "b", "c", "d"
					Z.ForgetBinding()
					setting(OWN):SetString("0")
					Z.asked = false
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()
					expect(Z.asked).to.beFalse()

					-- a key already set, or a bind
					setting(OWN):SetString("1")
					setting(KEY):SetString(tostring(KEY_F7))
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()
					setting(KEY):SetString("0")
					input.LookupBinding = function(command) return command == "+gry_zoom" and "MOUSE4" or nil end
					Z.ForgetBinding()
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()

					-- a default key is free: the zoom works already, nothing to ask
					input.LookupBinding = function() return nil end
					state.binds = {}
					Z.ForgetBinding()
					Z.asked = false
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()

					-- nothing: asked, once
					state.binds[KEY_H], state.binds[KEY_J], state.binds[KEY_K], state.binds[KEY_N] = "a", "b", "c", "d"
					Z.ForgetBinding()
					Z.MaybePrompt()
					local panel = Z.Key.panel
					expect(IsValid(panel)).to.beTrue()
					expect(panel:GetTitle()).to.equal("GryMod binoculars zoom")
					expect(Z.asked).to.beTrue()
					Z.Key.HidePrompt()
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()

					-- the two prompts have their own places
					menu.ShowPrompt()
					Z.Key.ShowPrompt()
					expect(select(2, menu.panel:GetPos())).toNot.equal(select(2, Z.Key.panel:GetPos()))
				end)

				input.LookupBinding = lookup
				menu.HidePrompt()
				Z.Key.HidePrompt()
				Z.asked = false
				Z.ForgetBinding()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the Keys section tells the default key (\"Default: H\") while no key is chosen, says none is free when they are all taken, and warns under a key picker when the key picked is already bound in the game (the zoom's and the quick menu's), with what it is bound to; a free key has no warning",
			func = function(state)
				local Z = GryMod.SuitZoom
				local menu = GryMod.MenuKey
				local realRun = RunConsoleCommand
				local menuKey = menu.convar:GetString()
				local panel

				local function build()
					if IsValid(panel) then
						panel:Remove()
					end

					panel = vgui.Create("ControlPanel")
					GryMod.KeysOptions(panel)

					local binders, labels = {}, {}

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DBinder" then
								binders[#binders + 1] = child
							elseif child.ClassName == "DLabel" then
								labels[#labels + 1] = child
							end

							walk(child)
						end
					end

					walk(panel)

					return binders, labels
				end

				local function textOf(labels, fragment)
					for _, label in ipairs(labels) do
						if string.find(label:GetText(), fragment, 1, true) then
							return label:GetText()
						end
					end
				end

				local ok, err = pcall(function()
					RunConsoleCommand = function() end
					menu.convar:SetString(tostring(KEY_F8))
					setting(KEY):SetString("0")
					Z.ForgetBinding()

					-- a free default: said
					local binders, labels = build()
					expect(textOf(labels, "Default: H")).toNot.beNil()

					-- H taken: the next one
					state.binds[KEY_H] = "+zoom"
					Z.ForgetBinding()
					binders, labels = build()
					expect(textOf(labels, "Default: J")).toNot.beNil()

					-- none free
					state.binds[KEY_J], state.binds[KEY_K], state.binds[KEY_N] = "b", "c", "d"
					Z.ForgetBinding()
					binders, labels = build()
					expect(textOf(labels, "Default:")).to.beNil()
					expect(textOf(labels, "No default key is free")).toNot.beNil()

					-- the zoom's picker: a key bound in the game warns, with the command
					state.binds = {[KEY_B] = "+zoom"}
					Z.ForgetBinding()
					binders, labels = build()
					local zoomBinder = binders[2]
					zoomBinder:OnChange(KEY_B)
					expect(textOf(labels, "already bound to +zoom")).toNot.beNil()

					-- a free key: no warning (the label says the key is free)
					zoomBinder:OnChange(KEY_F9)
					expect(textOf(labels, "already bound")).to.beNil()
					expect(textOf(labels, "free in the game")).toNot.beNil()

					-- the quick menu's picker too
					binders, labels = build()
					binders[1]:OnChange(KEY_B)
					expect(textOf(labels, "already bound to +zoom")).toNot.beNil()
				end)

				RunConsoleCommand = realRun
				menu.convar:SetString(menuKey)
				menu.HidePrompt()
				Z.Key.HidePrompt()
				Z.ForgetBinding()

				if IsValid(panel) then
					panel:Remove()
				end

				if not ok then
					error(err, 0)
				end
			end
		},
		-- ------------------------------------------------------------------------------------------------------------------
		-- The key is polled (a single player game has cl_predict 0: the hooks PlayerButtonDown / Up are not called), and the zoom is on by
		-- default but does nothing, and takes nothing from the Half-Life 2 zoom, until the player has chosen or bound a key
		-- ------------------------------------------------------------------------------------------------------------------
		{
			name = "the chosen key is polled with input.IsButtonDown: held opens the zoom and let go closes it, with no hook of the engine called (a mouse button too); the press needs nothing else to have the keyboard or the mouse",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local down = false
				local world = {pause = false, console = false, cursor = false, focusPanel = false, typing = false, focus = true}
				local realRead, realDown = B.Read, input.IsButtonDown

				B.Read = function(sit) for k, v in pairs(world) do sit[k] = v end return sit end
				input.IsButtonDown = function() return down end

				local ok, err = pcall(function()
					for _, button in ipairs({KEY_F7, MOUSE_MIDDLE}) do
						setting(KEY):SetString(tostring(button))
						Z.Reset()
						down = false
						Z.Key.Poll()
						Z.Key.Poll()
						expect(Z.IsActive()).to.beFalse()
						down = true
						Z.Key.Poll()
						expect(Z.IsActive()).to.beTrue()
						Z.Key.Poll()
						expect(#state.events).to.equal(1)
						down = false
						Z.Key.Poll()
						expect(Z.IsActive()).to.beFalse()
						expect(state.events[#state.events][2]).to.equal("release")
						state.events = {}
					end

					-- a key typed in the chat does not zoom, and does not zoom either when it is still down as the chat closes
					setting(KEY):SetString(tostring(KEY_F7))
					Z.Reset()
					world.typing = true
					down = false
					Z.Key.Poll()
					down = true
					Z.Key.Poll()
					world.typing = false
					Z.Key.Poll()
					expect(Z.IsActive()).to.beFalse()
					down = false
					Z.Key.Poll()
					down = true
					Z.Key.Poll()
					expect(Z.IsActive()).to.beTrue()
				end)

				B.Read, input.IsButtonDown = realRead, realDown

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the hooks of the engine are a second source: the zoom key through the factory's hook opens and closes it once, and a poll of the same press adds nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				local B = GryMod.KeyBinder
				local realRead, realDown = B.Read, input.IsButtonDown
				local down = false

				B.Read = function(sit) sit.pause, sit.console, sit.cursor, sit.focusPanel, sit.typing, sit.focus = false, false, false, false, false, true return sit end
				input.IsButtonDown = function() return down end

				local ok, err = pcall(function()
					Z.Key.Poll()
					Z.Key.Hook(KEY_F7, true)
					expect(Z.IsActive()).to.beTrue()
					down = true
					Z.Key.Poll()
					expect(#state.events).to.equal(1)
					Z.Key.Hook(KEY_F7, false)
					expect(Z.IsActive()).to.beFalse()
					down = false
					Z.Key.Poll()
					expect(#state.events).to.equal(2)
					expect(hook.GetTable().PlayerButtonDown["GRYKEYBINDER"]).toNot.beNil()
				end)

				B.Read, input.IsButtonDown = realRead, realDown

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "Read (the real one, on a stand-in player): each fact of the world reaches its reason; a player at 0 health is dead even for the frame in which the engine still says alive (measured: health and the weapon go one frame before Alive)",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local read = state.saved.read
				local localPlayer, enabled = LocalPlayer, M.Enabled
				local cursor, keyboard, pauseMenu, console, hasFocus = vgui.CursorVisible, vgui.GetKeyboardFocus, gui.IsGameUIVisible, gui.IsConsoleVisible, system.HasFocus
				local weapon = {}
				local facts

				local function fresh()
					facts = {alive = true, health = 100, typing = false, malfunction = false, vehicle = false, third = false, view = true, observer = 0,
						frozen = false, water = 0, weapon = weapon, cursor = false, panel = false, pause = false, console = false, focus = true}
				end

				local ply = {
					IsValid = function() return true end,
					Alive = function() return facts.alive end,
					Health = function() return facts.health end,
					IsTyping = function() return facts.typing end,
					GetNWBool = function(_, name) return name == "GryMalfunction" and facts.malfunction end,
					InVehicle = function() return facts.vehicle end,
					ShouldDrawLocalPlayer = function() return facts.third end,
					GetViewEntity = function(self) return facts.view and self or {} end,
					GetObserverMode = function() return facts.observer end,
					IsFrozen = function() return facts.frozen end,
					WaterLevel = function() return facts.water end,
					GetActiveWeapon = function() return facts.weapon end
				}

				local ok, err = pcall(function()
					LocalPlayer = function() return ply end
					M.Enabled = function() return true end
					-- (a calm screen: panels removed by an earlier case are still on it until the next frame)
					vgui.CursorVisible = function() return facts.cursor end
					vgui.GetKeyboardFocus = function() return facts.panel and {IsValid = function() return true end} or nil end
					gui.IsGameUIVisible = function() return facts.pause end
					gui.IsConsoleVisible = function() return facts.console end
					system.HasFocus = function() return facts.focus end

					fresh()
					Z.State.weapon = weapon
					Z.State.frame = FrameNumber()
					local sit = read({})
					expect(sit.valid).to.beTrue()
					expect(Z.Reason(sit, true)).to.beNil()

					for _, case in ipairs({
						{"alive", false, "death"}, {"health", 0, "death"}, {"health", -20, "death"}, {"typing", true, "chat"},
						{"malfunction", true, "malfunction"}, {"vehicle", true, "vehicle"}, {"third", true, "thirdperson"}, {"view", false, "viewentity"},
						{"observer", 5, "observer"}, {"frozen", true, "frozen"}, {"water", 3, "water"}, {"weapon", {}, "weapon"},
						{"cursor", true, "ui"}, {"panel", true, "ui"}, {"pause", true, "pause"}, {"console", true, "console"}, {"focus", false, "focus"}
					}) do
						fresh()
						facts[case[1]] = case[2]
						expect(Z.Reason(read({}), true)).to.equal(case[3])
					end

					-- the HUD in its lost state is a suit that is down too
					fresh()
					local boot = GryMod.FlashBoot
					local lost = boot.IsLost
					boot.IsLost = function() return true end
					local reason = Z.Reason(read({}), true)
					boot.IsLost = lost
					expect(reason).to.equal("malfunction")
				end)

				LocalPlayer, M.Enabled = localPlayer, enabled
				vgui.CursorVisible, vgui.GetKeyboardFocus, gui.IsGameUIVisible, gui.IsConsoleVisible, system.HasFocus = cursor, keyboard, pauseMenu, console, hasFocus
				Z.State.weapon = nil

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "CalcView asks the suit zoom to look at the world first (Think does not run while a single player game is paused by the menu or the console, CalcView does: measured), so a zoom that must end gives no more view; with the option off it asks nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				local M = GryMod.FlashBinoculars
				local guard, clock, enabled = Z.Guard, M.Now, M.Enabled
				local calls = 0
				local ply = {
					IsValid = function() return true end,
					Alive = function() return true end,
					KeyDown = function() return false end,
					InVehicle = function() return false end,
					GetInfoNum = function(_, name, default) return name == "fov_desired" and 100 or default end
				}

				Z.Guard = function() calls = calls + 1 guard() end
				M.Now = function() return 0 end
				M.Enabled = function() return true end

				local ok, err = pcall(function()
					M.ZoomReset(M.ZoomState)
					M.CalcView(ply, Vector(), Angle(), 100, 3, 8000)
					expect(calls).to.equal(1)

					-- the world says the menu is up: the zoom ends in this very call and no view is given
					Z.State.active = true
					Z.State.frame = FrameNumber()
					state.world.pause = true
					expect(M.CalcView(ply, Vector(), Angle(), 100, 3, 8000)).to.beNil()
					expect(Z.IsActive()).to.beFalse()
					expect(Z.State.reason).to.equal("pause")
					expect(M.ZoomState.active).to.beFalse()

					setting(OWN):SetString("0")
					calls = 0
					M.CalcView(ply, Vector(), Angle(), 100, 3, 8000)
					expect(calls).to.equal(0)
				end)

				Z.Guard, M.Now, M.Enabled = guard, clock, enabled
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
