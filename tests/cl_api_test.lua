-- Tests of the HUD events on the client (GryMod.API.RegisterHUDEvent, HUDEvent, the gry_api_hud message and the built-in events
-- boot, reboot, lost and malfunction; lua/grymod/client/cl_api.lua), GLuaTest format, client realm. Also: a suit that is off
-- (GryMod.API.SetSuitEnabled on the server) hides the HUD of that client. Third-party handlers go through SafeCall: a broken
-- one raises nothing and is disabled after 5 errors. Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, part 2.

local Boot

local played
local realPlay
local savedBoot
local registered = {}
local hooks = {}
local lines, realMsgN

local function register(name, fn)
	registered[#registered + 1] = name

	return GryMod.API.RegisterHUDEvent(name, fn)
end

local function listen(fn)
	local id = "gry_api_cl_test_" .. #hooks
	hook.Add("GryMod_HUDEvent", id, fn)
	hooks[#hooks + 1] = id
end

-- Runs fn with the net readers replaced by a queue holding the message the server would send, then puts them back.
local function withMessage(items, fn)
	local head = 0
	local names = {"ReadString", "ReadUInt", "ReadBool", "ReadDouble"}
	local real = {}

	for _, n in ipairs(names) do real[n] = net[n] end

	local function nextItem() head = head + 1 return items[head] end
	net.ReadString, net.ReadUInt, net.ReadBool, net.ReadDouble = nextItem, nextItem, nextItem, nextItem

	local ok, err = pcall(fn)

	for n, f in pairs(real) do net[n] = f end

	assert(ok, err)
end

local function lastSound()
	return played[#played]
end

return {
	groupName = "GryMod extension API: HUD events (client)",
	beforeAll = function()
		Boot = GryMod.FlashBoot
		savedBoot = GetConVar("gry_hud_boot"):GetString()
	end,
	beforeEach = function()
		played = {}
		realPlay = GryMod.PlaySound
		GryMod.PlaySound = function(path)
			played[#played + 1] = path

			return true
		end

		lines = {}
		realMsgN = MsgN
		MsgN = function(...) lines[#lines + 1] = table.concat({...}, "") end

		GetConVar("gry_hud_boot"):SetString("1")
		Boot.Reset()
		Boot.ResetSpawn()
		timer.Remove("GryApiMalfunction")
	end,
	afterEach = function()
		GryMod.PlaySound = realPlay
		MsgN = realMsgN
		GetConVar("gry_hud_boot"):SetString(savedBoot)

		for _, name in ipairs(registered) do
			GryMod.API.UnregisterHUDEvent(name)
			GryMod.API.SafeCallReset("hudevent:" .. name)
		end

		registered = {}

		for _, id in ipairs(hooks) do
			hook.Remove("GryMod_HUDEvent", id)
		end

		hooks = {}
		timer.Remove("GryApiMalfunction")
		Boot.Reset()
		Boot.ResetSpawn()
	end,
	cases = {
		{
			name = "the functions and the net receiver exist",
			func = function()
				local A = GryMod.API

				expect(isfunction(A.RegisterHUDEvent)).to.beTrue()
				expect(isfunction(A.UnregisterHUDEvent)).to.beTrue()
				expect(isfunction(A.HUDEvent)).to.beTrue()
				expect(net.Receivers["gry_api_hud"] ~= nil).to.beTrue()
			end
		},
		{
			name = "a registered event runs its handler with the data, returns true, then the client hook GryMod_HUDEvent(name, data) fires AFTER the handler",
			func = function()
				local order = {}
				local seen

				expect(register("t_event", function(data) order[#order + 1] = "handler"; seen = data end)).to.beTrue()
				listen(function(name, data) order[#order + 1] = "hook:" .. name; expect(data.level).to.equal(3) end)

				expect(GryMod.API.HUDEvent("t_event", {level = 3})).to.beTrue()
				expect(table.concat(order, ",")).to.equal("handler,hook:t_event")
				expect(seen.level).to.equal(3)
			end
		},
		{
			name = "an event with no data gives the handler an empty table, never nil",
			func = function()
				local seen

				register("t_nodata", function(data) seen = data end)
				GryMod.API.HUDEvent("t_nodata")

				expect(istable(seen)).to.beTrue()
				expect(next(seen)).to.beNil()
			end
		},
		{
			name = "an event nobody registered answers false and a reason, and fires no hook",
			func = function()
				local fired = 0
				listen(function() fired = fired + 1 end)

				local ok, reason = GryMod.API.HUDEvent("t_missing", {})

				expect(ok).to.beFalse()
				expect(reason).to.equal("unknown event")
				expect(fired).to.equal(0)
			end
		},
		{
			name = "registering again replaces the handler; UnregisterHUDEvent removes it and says whether there was one; a bad registration is refused",
			func = function()
				local A = GryMod.API
				local first, second = 0, 0

				register("t_swap", function() first = first + 1 end)
				register("t_swap", function() second = second + 1 end)
				A.HUDEvent("t_swap")
				expect(first).to.equal(0)
				expect(second).to.equal(1)

				expect(A.UnregisterHUDEvent("t_swap")).to.beTrue()
				expect(A.UnregisterHUDEvent("t_swap")).to.beFalse()
				expect(A.HUDEvent("t_swap")).to.beFalse()

				for _, args in ipairs({{nil, function() end}, {"", function() end}, {"bad name", function() end}, {42, function() end}, {"t_nofn", nil}, {"t_nofn", "x"}}) do
					local ok, reason = A.RegisterHUDEvent(args[1], args[2])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end
			end
		},
		{
			name = "a handler that raises an error raises nothing for the caller, fires no hook, and is disabled after 5 errors in a row with one console line; registering it again re-arms it",
			func = function()
				local A = GryMod.API
				local fired, runs = 0, 0
				listen(function() fired = fired + 1 end)

				register("t_broken", function() runs = runs + 1; error("broken handler") end)

				for _ = 1, 8 do
					local ok = A.HUDEvent("t_broken", {})
					expect(ok).to.beFalse()
				end

				expect(runs).to.equal(5)
				expect(fired).to.equal(0)
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "hudevent 't_broken' disabled after 5 errors", 1, true) ~= nil).to.beTrue()

				register("t_broken", function() return true end)
				expect(A.HUDEvent("t_broken", {})).to.beTrue()
				expect(fired).to.equal(1)
			end
		},
		{
			name = "the message from the server plays the event: it is read with the shared bounds and goes to the handler; a message that breaks them is dropped",
			func = function()
				local got

				register("t_net", function(data) got = data end)

				-- name, field count, then key, type (0 number, 1 string, 2 boolean), value
				withMessage({"t_net", 2, "amount", 0, 12.5, "label", 1, "hello"}, function()
					GryMod.API.ReceiveHUDEvent()
				end)

				expect(got.amount).to.equal(12.5)
				expect(got.label).to.equal("hello")

				got = nil
				withMessage({"t_net", 9}, function() GryMod.API.ReceiveHUDEvent() end) -- too many fields
				withMessage({"bad name", 0}, function() GryMod.API.ReceiveHUDEvent() end)
				expect(got).to.beNil()
			end
		},
		-- the built-in events, on the existing Flash modules
		{
			name = "the four built-in events exist: boot, reboot, lost, malfunction",
			func = function()
				for _, name in ipairs({"boot", "reboot", "lost", "malfunction"}) do
					local ok = GryMod.API.HUDEvent(name, {seconds = 1})
					expect(ok).to.beTrue()
					Boot.Reset()
				end
			end
		},
		{
			name = "boot plays the start-up log of the HUD (HUD_Initialize) with its reboot sound",
			func = function()
				expect(GryMod.API.HUDEvent("boot")).to.beTrue()

				expect(Boot.Current()).to.equal("initialize")
				expect(string.find(lastSound(), "hud_reboot", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			name = "lost plays the emergency shutdown animation (HUD_Lost) with the malfunction sound; reboot then plays the reboot sequence, silent",
			func = function()
				expect(GryMod.API.HUDEvent("lost")).to.beTrue()

				expect(Boot.Current()).to.equal("lost")
				expect(Boot.IsLost()).to.beTrue()
				expect(string.find(lastSound(), "hud_malfunction_hit", 1, true) ~= nil).to.beTrue()

				local sounds = #played
				expect(GryMod.API.HUDEvent("reboot")).to.beTrue()

				expect(Boot.Current()).to.equal("reboot")
				expect(#played).to.equal(sounds)
			end
		},
		{
			name = "reboot alone (no malfunction before it) still plays the reboot sequence",
			func = function()
				expect(GryMod.API.HUDEvent("reboot")).to.beTrue()
				expect(Boot.Current()).to.equal("reboot")
			end
		},
		{
			name = "malfunction plays the shutdown animation for the given seconds (default 5, from 0.1 to 60), then the reboot",
			func = function()
				expect(GryMod.API.HUDEvent("malfunction", {seconds = 3})).to.beTrue()

				expect(Boot.Current()).to.equal("lost")
				expect(timer.Exists("GryApiMalfunction")).to.beTrue()
				expect(math.abs(timer.TimeLeft("GryApiMalfunction") - 3) < 0.5).to.beTrue()

				-- the end of the time (the timer's function)
				Boot.EndApiMalfunction()
				expect(Boot.Current()).to.equal("reboot")
				expect(timer.Exists("GryApiMalfunction")).to.beFalse()

				Boot.Reset()
				GryMod.API.HUDEvent("malfunction")
				expect(math.abs(timer.TimeLeft("GryApiMalfunction") - 5) < 0.5).to.beTrue()

				Boot.Reset()
				GryMod.API.HUDEvent("malfunction", {seconds = 1000})
				expect(math.abs(timer.TimeLeft("GryApiMalfunction") - 60) < 0.5).to.beTrue()

				Boot.Reset()
				GryMod.API.HUDEvent("malfunction", {seconds = -4})
				expect(timer.TimeLeft("GryApiMalfunction") <= 0.6).to.beTrue()
			end
		},
		{
			name = "the player's own choice holds: with the HUD boot sequences off (gry_hud_boot 0) the built-in events play nothing",
			func = function()
				GetConVar("gry_hud_boot"):SetString("0")

				GryMod.API.HUDEvent("boot")
				expect(Boot.Current()).to.beNil()
				GryMod.API.HUDEvent("lost")
				expect(Boot.Current()).to.beNil()
				GryMod.API.HUDEvent("reboot")
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(0)
			end
		},
		-- a suit that is off hides the HUD
		{
			name = "IsSuitEnabled on the client reads the network flag of the server: a normal player has the suit on",
			func = function()
				local ply = LocalPlayer()

				expect(IsValid(ply)).to.beTrue()
				expect(GryMod.API.IsSuitEnabled(ply)).to.equal(not ply:GetNWBool("GryDisabled", false))
				expect(GryMod.API.IsSuitEnabled(nil)).to.beFalse()
			end
		},
		{
			name = "a suit that is off hides the HUD: FlashHUD.Enabled is false and the paint draws nothing; back on, both panels are drawn again",
			func = function()
				local Flash, A = GryMod.Flash, GryMod.API
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local saved = {GetConVar("gry_hud"):GetString(), GetConVar("gry_hud_status"):GetString(), GetConVar("gry_hud_radar"):GetString()}
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_status"):SetString("1")
				GetConVar("gry_hud_radar"):SetString("1")

				local realDraw, realEnabled = Flash.Draw, A.IsSuitEnabled
				local drawn = 0
				Flash.Draw = function() drawn = drawn + 1 end

				local function paint()
					GryMod.FlashHUD.Reset()
					drawn = 0
					GryMod.FlashHUD.Paint()

					return drawn
				end

				local ok, err = pcall(function()
					local on = paint()
					expect(GryMod.FlashHUD.Enabled()).to.beTrue()

					A.IsSuitEnabled = function() return false end
					local off = paint()
					expect(GryMod.FlashHUD.Enabled()).to.beFalse()

					A.IsSuitEnabled = realEnabled
					local back = paint()

					expect(on).to.equal(2)
					expect(off).to.equal(0)
					expect(back).to.equal(2)
				end)

				Flash.Draw, A.IsSuitEnabled = realDraw, realEnabled
				GetConVar("gry_hud"):SetString(saved[1])
				GetConVar("gry_hud_status"):SetString(saved[2])
				GetConVar("gry_hud_radar"):SetString(saved[3])
				GryMod.FlashHUD.Reset()
				assert(ok, err)
			end
		}
	}
}
