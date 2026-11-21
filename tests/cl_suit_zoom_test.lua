-- Tests of the suit zoom (GryMod.SuitZoom), GLuaTest format, client realm. The binoculars have their own zoom key (gry_zoom_own):
-- one module owns "the player is zooming", every reason to stop goes through SuitZoom.Exit, and a situation (a plain table of
-- facts about the world) is turned into "must the zoom end, and why" by a pure function (SuitZoom.Reason). The tests give the module
-- a world of their own (SuitZoom.Read replaced) and never play a sound.

local OWN, KEY, TOGGLE = "gry_zoom_own", "gry_zoom_key", "gry_zoom_toggle"
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
			toggle = setting(TOGGLE) and setting(TOGGLE):GetString(),
			read = Z and Z.Read,
			drop = Bino and Bino.Drop,
			emit = GryMod.SoundMix.Emit
		}
		GryMod.SoundMix.Emit = function() end

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
			setting(TOGGLE):SetString("0")
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

			if Z then
				Z.Read = saved.read
			end

			if Bino then
				Bino.Drop = saved.drop
			end

			if saved.own then setting(OWN):SetString(saved.own) end
			if saved.key then setting(KEY):SetString(saved.key) end
			if saved.toggle then setting(TOGGLE):SetString(saved.toggle) end
		end

		if Z then
			Z.Reset()
		end
	end,
	cases = {
		{
			name = "the three settings are saved with the profile and start at 0: the own zoom key off (the Half-Life 2 zoom key drives the binoculars as before), no key chosen, hold (not toggle)",
			func = function(state)
				local created = {}
				local realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, ...)
					created[name] = {default = default, save = shouldsave}

					return realCreate(name, default, shouldsave, ...)
				end

				local ok, err = pcall(include, "grymod/client/cl_suit_zoom.lua")
				CreateClientConVar = realCreate

				if not ok then
					error(err, 0)
				end

				-- the file made a new module table: what afterEach puts back is that one's own function
				state.saved.read = GryMod.SuitZoom.Read

				for _, name in ipairs({OWN, KEY, TOGGLE}) do
					expect(created[name]).toNot.beNil()
					expect(created[name].save).to.beTrue()
					expect(created[name].default).to.equal("0")
				end
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
				expect(Z.Owns()).to.beFalse()
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
				setting(TOGGLE):SetString("1")

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
				state.world.keyUp = false
				Z.Guard()
				state.world.keyUp = true
				Z.Guard()
				expect(Z.IsActive()).to.beTrue()
			end
		},
		{
			name = "toggle mode: the poll clears a stale key but leaves the zoom open (it was opened by a press that is over)",
			func = function(state)
				local Z = GryMod.SuitZoom
				setting(TOGGLE):SetString("1")
				Z.Press("key", true)
				state.world.keyUp = true
				Z.Guard()
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
				local real = Z.Owns
				Z.Owns = function() return false end
				Z.Guard()
				Z.Owns = real
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

				local down = hook.GetTable().PlayerButtonDown["GRYSUITZOOM"]
				local up = hook.GetTable().PlayerButtonUp["GRYSUITZOOM"]
				local ply = LocalPlayer()
				local first = IsFirstTimePredicted

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

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the option off, the Half-Life 2 zoom is left alone: +zoom goes on to the game, IN_ZOOM stays in the command, and the wheel is nobody's",
			func = function(state)
				local Z = GryMod.SuitZoom
				local ply = LocalPlayer()
				local removed = {}
				local cmd = {RemoveKey = function(_, key) removed[#removed + 1] = key end, SetMouseWheel = function() removed.wheel = true end}

				setting(OWN):SetString("0")
				expect(Z.BindPress(ply, "+zoom", true, KEY_F7)).to.beNil()
				expect(Z.BindPress(ply, "invprev", true, MOUSE_WHEEL_UP)).to.beNil()
				Z.StartCommand(ply, cmd)
				expect(#removed).to.equal(0)
				expect(removed.wheel).to.beNil()
			end
		},
		{
			name = "with the option on, +zoom is taken (also through an alias, even one that runs several commands) so the Half-Life 2 zoom never starts; -zoom and other binds go on",
			func = function(state)
				local Z = GryMod.SuitZoom
				local ply = LocalPlayer()
				local translate = input.TranslateAlias
				input.TranslateAlias = function(command)
					if command == "myzoom" then return "+zoom" end
					if command == "both" then return "+jump; +zoom" end
					if command == "harmless" then return "+attack" end

					return nil
				end

				local ok, err = pcall(function()
					expect(Z.BindPress(ply, "+zoom", true, KEY_F7)).to.beTrue()
					expect(Z.BindPress(ply, "myzoom", true, KEY_F7)).to.beTrue()
					expect(Z.BindPress(ply, "both", true, KEY_F7)).to.beTrue()
					expect(Z.BindPress(ply, "-zoom", true, KEY_F7)).to.beNil()
					expect(Z.BindPress(ply, "harmless", true, KEY_F7)).to.beNil()
					expect(Z.BindPress(ply, "+attack", true, MOUSE_LEFT)).to.beNil()
					expect(Z.BindPress(ply, "+gry_zoom", true, KEY_F7)).to.beNil()
				end)

				input.TranslateAlias = translate

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the option on, StartCommand removes IN_ZOOM from the player's own command (the keys PlayerBindPress cannot see: F1 to F12, aliases), and does not touch other buttons or other players' commands",
			func = function(state)
				local Z = GryMod.SuitZoom
				local removed = {}
				local cmd = {RemoveKey = function(_, key) removed[#removed + 1] = key end, SetMouseWheel = function() end}

				Z.StartCommand(LocalPlayer(), cmd)
				expect(#removed).to.equal(1)
				expect(removed[1]).to.equal(IN_ZOOM)

				Z.StartCommand({}, cmd)
				expect(#removed).to.equal(1)

				local registered = hook.GetTable().StartCommand and hook.GetTable().StartCommand["GRYSUITZOOM"]
				expect(registered).toNot.beNil()
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
			name = "the binoculars follow the own zoom when it is on (IN_ZOOM is no longer read) and the Half-Life 2 key when it is off; a dead player never zooms; the crosshair does the same",
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
					-- off: the Half-Life 2 key
					setting(OWN):SetString("0")
					Z.State.active = true -- (nothing to do with it)
					expect(M.Wanted(ply)).to.beFalse()
					zooming = true
					expect(M.Wanted(ply)).to.beTrue()
					expect(cross == nil or cross.Zooming(ply)).to.beTrue()
					alive = false
					expect(M.Wanted(ply)).to.beFalse()
					alive = true
					Z.Reset()

					-- on: only the own zoom
					setting(OWN):SetString("1")
					zooming = true
					expect(M.Wanted(ply)).to.beFalse()
					expect(cross == nil or cross.Zooming(ply)).to.beFalse()
					zooming = false
					Z.State.active = true
					expect(M.Wanted(ply)).to.beTrue()
					expect(cross == nil or cross.Zooming(ply)).to.beTrue()
					alive = false
					expect(M.Wanted(ply)).to.beFalse()
					alive = true
					Z.State.active = false
					expect(M.Wanted(ply)).to.beFalse()
				end)

				M.Enabled = enabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the own zoom on the stages are on whatever gry_binoculars_stages says (the wheel is the zoom's interface); with it off they follow their own setting as before",
			func = function(state)
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
					expect(M.StagesEnabled()).to.beTrue()
				end)

				stages:SetString(saved)

				if not ok then
					error(err, 0)
				end
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
			name = "the prompt for the zoom key: only with the own zoom on and nothing bound, once per session, with a key set or a +gry_zoom bind it does not come, and it does not sit on the quick menu's prompt",
			func = function(state)
				local Z = GryMod.SuitZoom
				local lookup = input.LookupBinding
				local menu = GryMod.MenuKey

				local ok, err = pcall(function()
					input.LookupBinding = function() return nil end
					setting(KEY):SetString("0")
					Z.Key.HidePrompt()

					-- the option off: nothing asked, and nothing counted as asked
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
					Z.MaybePrompt()
					expect(IsValid(Z.Key.panel)).to.beFalse()

					-- nothing: asked, once
					input.LookupBinding = function() return nil end
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
			name = "the options panel has the own zoom check box, the toggle check box and a key picker for the zoom key that saves through SetKey (and refuses what it refuses); opening the panel writes nothing",
			func = function(state)
				local Z = GryMod.SuitZoom
				local menu = GryMod.MenuKey
				local writes = {}
				local realRun = RunConsoleCommand
				local found, binders = {}, {}
				local menuKey = menu.convar:GetString()
				local before = {setting(OWN):GetString(), setting(KEY):GetString(), setting(TOGGLE):GetString()}
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
					expect(found[TOGGLE]).to.beTrue()
					expect(#writes).to.equal(0)
					expect(setting(OWN):GetString()).to.equal(before[1])
					expect(setting(KEY):GetString()).to.equal(before[2])
					expect(setting(TOGGLE):GetString()).to.equal(before[3])

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
		}
	}
}
