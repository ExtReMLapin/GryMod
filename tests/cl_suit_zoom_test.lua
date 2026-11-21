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
		}
	}
}
