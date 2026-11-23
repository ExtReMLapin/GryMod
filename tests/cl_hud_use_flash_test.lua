-- Tests of the use prompt under the crosshair (GryMod.FlashUse, lua/grymod/client/cl_hud_use_flash.lua), GLuaTest format, client realm.
-- Needs the converted movie lua/grymod/flash/hud_interactiveicons.lua. The rule: WHETHER something can be used is the crosshair's own test
-- (UsableFor, run by its scan); the crosshair reports each change with the hook GryMod_UsableChanged and this module says WHAT it is (an
-- icon and a text from the registry of usable entities). Nothing runs between two changes. The live game is replaced where a case needs it
-- (the HUD state, the crosshair's switches, the drawing, the player) and put back in afterEach inside a pcall.

local Use = GryMod.FlashUse
local Cross = GryMod.FlashCrosshair
local Flash = GryMod.Flash

local saved = {}
local convarsSaved = {}
local drawn

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	if convarsSaved[name] == nil then
		convarsSaved[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}

	for name, value in pairs(convarsSaved) do
		GetConVar(name):SetString(value)
	end

	convarsSaved = {}
end

local function fake(class, fields)
	local ent = {class = class}

	for k, v in pairs(fields or {}) do
		ent[k] = v
	end

	function ent:IsValid() return true end
	function ent:GetClass() return self.class end
	function ent:IsWeapon() return self.weapon == true end
	function ent:IsVehicle() return self.vehicle == true end
	function ent:IsNPC() return self.npc == true end
	function ent:Health() return self.health or 0 end

	if fields and fields.size then
		function ent:OBBMins() return Vector(0, 0, 0) end
		function ent:OBBMaxs() return self.size end
	end

	if fields and fields.mass then
		function ent:GetPhysicsObject()
			local mass = self.mass

			return {IsValid = function() return true end, GetMass = function() return mass end}
		end
	end

	if fields and fields.print then
		function ent:GetPrintName() return self.print end
	end

	return ent
end

-- The stock ladder entry applies only while the replicated variable sv_ladder_useonly is 1 (otherwise walking into a ladder climbs it): the case that needs a
-- CLIMB prompt puts a stand-in GetConVar in front of the game's, restored with the other stubs.
local function ladderUseOnly(value)
	local real = GetConVar

	stub(_G, "GetConVar", function(name)
		if name == "sv_ladder_useonly" then
			return {GetBool = function() return value == "1" end, GetInt = function() return tonumber(value) end}
		end

		return real(name)
	end)
end

local function fakePlayer(inVehicle)
	return {
		IsValid = function() return true end,
		Alive = function() return true end,
		InVehicle = function() return inVehicle == true end,
		HasWeapon = function() return false end
	}
end

local function listener()
	return hook.GetTable()["GryMod_UsableChanged"]["GryUsePrompt"]
end

local function promptText()
	local holder = Use.Icons():Find("InterActiveText.Colorset")

	return holder:Child("InterActiveText").text
end

return {
	groupName = "GryMod use prompt (HUD_InterActiveIcons)",
	beforeEach = function()
		Use.Reset()
		drawn = 0

		stub(GryMod.FlashHUD, "Enabled", function() return true end)
		stub(Flash, "Draw", function() drawn = drawn + 1 return true end)
		setConVar("gry_hud_usehint", "1")
	end,
	afterEach = function()
		pcall(Use.Reset)
		pcall(restore)
	end,
	cases = {
		{
			name = "Describe: a vehicle is ENTER, a ladder CLIMB, a door USE, an ammo crate TAKE AMMO, a unknown thing the plain USE; nothing for a mode that is not 1; the entry comes back as the second value",
			func = function()
				local player = fakePlayer()

				local vehicle, entry = Use.Describe(fake("prop_vehicle_jeep", {vehicle = true}), 1, player)
				expect(vehicle.icon).to.equal("enter")
				expect(vehicle.text).to.equal("ENTER VEHICLE")
				expect(entry.key).to.equal("hl2_vehicles")

				ladderUseOnly("1")

				local ladder = Use.Describe(fake("func_useableladder"), 1, player)
				expect(ladder.icon).to.equal("ladder")
				expect(ladder.text).to.equal("CLIMB")

				local crate = Use.Describe(fake("item_ammo_crate"), 1, player)
				expect(crate.icon).to.equal("pickup")
				expect(crate.text).to.equal("TAKE AMMO")

				local plain, plainEntry = Use.Describe(fake("func_something_unknown"), 1, player)
				expect(plain.icon).to.equal("use")
				expect(plain.text).to.equal("USE")
				expect(plainEntry).to.beNil()

				-- the crosshair is red for what can not be used: no prompt for it, nor for nothing
				expect(Use.Describe(fake("func_button"), 2, player)).to.beNil()
				expect(Use.Describe(fake("func_button"), 0, player)).to.beNil()
				expect(Use.Describe(nil, 1, player)).to.beNil()
				expect(Use.Describe({IsValid = function() return false end}, 1, player)).to.beNil()
			end
		},
		{
			-- fails if the vehicle were not usable for the crosshair: the prompt would never come
			name = "the crosshair's own test counts a vehicle as usable, unless the player already sits in one",
			func = function()
				local jeep = fake("prop_vehicle_jeep", {vehicle = true})

				expect(Cross.UsableFor(jeep, fakePlayer(false))).to.equal(1)
				expect(Cross.UsableFor(jeep, fakePlayer(true))).to.equal(0)
				expect(Cross.UsableFor(fake("func_brush"), fakePlayer(false))).to.equal(0)
			end
		},
		{
			-- fails if the crosshair kept its own list of classes instead of asking the registry
			name = "the crosshair's test follows the registry: doors, talking NPCs, turrets are usable; a crate, a dead NPC, a mine are not; a vehicle not from inside one",
			func = function()
				local player = fakePlayer(false)

				for _, row in ipairs({
					{"func_door", nil, 1}, {"prop_door_rotating", nil, 1}, {"func_tank", nil, 1},
					{"npc_citizen", {npc = true, health = 40}, 1}, {"npc_citizen", {npc = true, health = 0}, 0},
					{"npc_kleiner", {npc = true, health = 40}, 0}, {"npc_zombie", {npc = true, health = 40}, 0},
					{"item_healthkit", nil, 0}, {"weapon_pistol", nil, 0}, {"item_healthcharger", nil, 1}, {"item_ammo_crate", nil, 1},
					{"item_item_crate", nil, 0}, {"combine_mine", nil, 0}, {"func_brush", nil, 0}, {"gmod_button", nil, 1}
				}) do
					expect(Cross.UsableFor(fake(row[1], row[2]), player)).to.equal(row[3])
				end

				-- the same vehicle is not usable from inside one
				expect(Cross.UsableFor(fake("prop_vehicle_jeep", {vehicle = true}), fakePlayer(true))).to.equal(0)
			end
		},
		{
			name = "a prop is usable only when the player can lift it by size (128 units on every side at most; the mass comes from the server, see the crosshair's tests), and only with the props group on",
			func = function()
				local player = fakePlayer(false)

				setConVar("gry_usehint_props", "1")
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 40)}), player)).to.equal(1)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(128, 128, 128)}), player)).to.equal(1)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(129, 20, 20)}), player)).to.equal(0)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 200)}), player)).to.equal(0)
				-- no size to read: usable
				expect(Cross.UsableFor(fake("prop_physics"), player)).to.equal(1)
				-- a door is not a prop: the limits are for the grab icon only
				expect(Cross.UsableFor(fake("prop_door_rotating", {size = Vector(10, 100, 300)}), player)).to.equal(1)
				expect(Cross.PICKUP_MASS).to.equal(35)
				expect(Cross.PICKUP_SIZE).to.equal(128)

				setConVar("gry_usehint_props", "0")
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 40)}), player)).to.equal(0)
			end
		},
		{
			-- fails without the listener of the crosshair's hook, or if the paint hook were permanent
			name = "the crosshair's report shows the prompt (and adds the paint hook), the next report with nothing takes it away (and removes the hook)",
			func = function()
				expect(Use.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHUSE"]).to.beNil()

				ladderUseOnly("1")
				listener()(fake("func_useableladder"), 1, fakePlayer())
				expect(Use.Shown().icon).to.equal("ladder")
				expect(Use.Shown().text).to.equal("CLIMB")
				expect(Use.Active()).to.beTrue()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHUSE"]).to.exist()

				listener()(nil, 0, fakePlayer())
				expect(Use.Shown()).to.beNil()
				expect(Use.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHUSE"]).to.beNil()
			end
		},
		{
			-- fails without the switch
			name = "the use prompt off (gry_hud_usehint 0) or the HUD off: the report shows nothing",
			func = function()
				setConVar("gry_hud_usehint", "0")
				listener()(fake("func_button"), 1, fakePlayer())
				expect(Use.Shown()).to.beNil()
				expect(Use.Active()).to.beFalse()

				setConVar("gry_hud_usehint", "1")
				GryMod.FlashHUD.Enabled = function() return false end
				listener()(fake("func_button"), 1, fakePlayer())
				expect(Use.Shown()).to.beNil()
			end
		},
		{
			-- fails if the text were written before the frame: going back in the clip makes it again, and its text with it
			name = "the movie shows the icon's frame and the text, and a prompt after a later frame still has its text",
			func = function()
				Use.Set({icon = "ladder", text = "CLIMB"})
				expect(Use.Icons():CurrentFrame()).to.equal(5)
				expect(promptText()).to.equal("CLIMB")

				Use.Set({icon = "use", text = "USE"}) -- back to the first frame
				expect(Use.Icons():CurrentFrame()).to.equal(1)
				expect(promptText()).to.equal("USE")

				Use.Set({icon = "enter", text = "ENTER VEHICLE"})
				expect(Use.Icons():CurrentFrame()).to.equal(2)
				expect(promptText()).to.equal("ENTER VEHICLE")

				Use.Set({icon = "pickup", text = "TAKE A LONG NAME OF A WEAPON"})
				expect(Use.Icons():CurrentFrame()).to.equal(3)
				Use.Set({icon = "grab", text = "PICK UP"})
				expect(Use.Icons():CurrentFrame()).to.equal(4)
				expect(promptText()).to.equal("PICK UP")
			end
		},
		{
			-- fails without the conditions of the paint
			name = "the prompt is drawn only with the crosshair: not when it is off or hidden, not for a dead player, not when nothing is shown",
			func = function()
				local crossOn, hidden, alive = true, false, true

				stub(Cross, "Enabled", function() return crossOn end)
				stub(Cross, "IsHidden", function() return hidden end)
				stub(_G, "LocalPlayer", function()
					return {IsValid = function() return true end, Alive = function() return alive end}
				end)

				Use.Paint()
				expect(drawn).to.equal(0) -- nothing shown

				Use.Set({icon = "use", text = "USE"})
				Use.Paint()
				expect(drawn).to.equal(1)

				hidden = true
				Use.Paint()
				expect(drawn).to.equal(1)

				hidden, crossOn = false, false
				Use.Paint()
				expect(drawn).to.equal(1)

				crossOn, alive = true, false
				Use.Paint()
				expect(drawn).to.equal(1)

				alive = true
				Use.Paint()
				expect(drawn).to.equal(2)
			end
		},
		{
			-- fails if the crosshair's report were not made through the hook, or a failing listener broke the crosshair's frame
			name = "the crosshair reports through the hook GryMod_UsableChanged, and a listener that fails does not break the crosshair (its error is printed)",
			func = function()
				local told = {}
				local errors = {}

				stub(_G, "ErrorNoHalt", function(text) errors[#errors + 1] = text end)
				hook.Add("GryMod_UsableChanged", "gry_use_test_spy", function(ent, mode, ply) told[#told + 1] = {ent, mode, ply} end)

				local ent, ply = fake("func_button"), fakePlayer()
				local ok, err = pcall(function()
					Cross.ReportUsable(ent, 1, ply)
					expect(#errors).to.equal(0)
					expect(#told).to.equal(1)
					expect(told[1][1]).to.equal(ent)
					expect(told[1][2]).to.equal(1)
					expect(told[1][3]).to.equal(ply)

					-- a listener that fails: no error reaches the caller, one line is printed (hook.Run does not protect the listeners from each other)
					hook.Add("GryMod_UsableChanged", "gry_use_test_bad", function() error("boom") end)
					Cross.ReportUsable(ent, 1, ply)
					expect(#errors).to.equal(1)
				end)

				hook.Remove("GryMod_UsableChanged", "gry_use_test_bad")
				hook.Remove("GryMod_UsableChanged", "gry_use_test_spy")
				assert(ok, tostring(err))
			end
		},
		{
			-- fails without Use.OnUsePressed hiding a one-shot prompt ("a mounted gun, if I press E I use it so it changes state, so stop showing")
			name = "a one-shot use (a mounted gun): the key takes the prompt away at once; it stays away while the same thing is aimed and comes back after the player looked away or at another thing",
			func = function()
				local tank, other, ply = fake("func_tank"), fake("func_tank"), fakePlayer()

				listener()(tank, 1, ply)
				expect(Use.Shown()).to.exist()
				expect(Use.OnUsePressed(10)).to.beTrue()
				expect(Use.Shown()).to.beNil()
				expect(Use.Active()).to.beFalse()

				-- the crosshair reports the same thing again (its mode changed): still hidden
				listener()(tank, 1, ply)
				expect(Use.Shown()).to.beNil()

				-- another thing, or nothing: the hide is over
				listener()(other, 1, ply)
				expect(Use.Shown()).to.exist()
				listener()(nil, 0, ply)
				listener()(tank, 1, ply)
				expect(Use.Shown()).to.exist()

				-- nothing on show: the key does nothing
				listener()(nil, 0, ply)
				expect(Use.OnUsePressed(11)).to.beFalse()
			end
		},
		{
			-- fails without the repeatable use: the pulse (one HUD event, picture and sound together), the cooldown, the dimming
			name = "a repeatable use (a door): the key makes ONE use_feedback event, the prompt is dimmed for the cooldown (1 s for a door) and a second key in it does nothing",
			func = function()
				local events = {}
				local door, ply = fake("prop_door_rotating"), fakePlayer()

				setConVar("gry_usehint_feedback", "1")
				stub(GryMod.API, "HUDEvent", function(name) events[#events + 1] = name return true end)
				listener()(door, 1, ply)

				expect(Use.Dimmed(10)).to.beFalse()
				expect(Use.OnUsePressed(10)).to.beTrue()
				expect(#events).to.equal(1)
				expect(events[1]).to.equal("use_feedback")
				expect(Use.Shown()).to.exist() -- a door stays on show: it can be used again

				expect(Use.Dimmed(10.5)).to.beTrue()
				expect(Use.OnUsePressed(10.5)).to.beFalse()
				expect(#events).to.equal(1)

				expect(Use.Dimmed(11.01)).to.beFalse()
				expect(Use.OnUsePressed(11.01)).to.beTrue()
				expect(#events).to.equal(2)

				-- looking at another door starts clean
				listener()(fake("prop_door_rotating"), 1, ply)
				expect(Use.Dimmed(11.02)).to.beFalse()
			end
		},
		{
			-- fails without the hold rule: the key is kept down on a charger, and the pulse and the beep came again at each repeat of the bind
			name = "a thing used by holding the key (a charger, a wheel): ONE use_feedback at the start, none while the key stays down (repeats of the bind), no dimming; a new press after the release, or on another thing, gives one again",
			func = function()
				local events = {}
				local ply = fakePlayer()
				local charger = fake("item_healthcharger")

				setConVar("gry_usehint_feedback", "1")
				stub(GryMod.API, "HUDEvent", function(name) events[#events + 1] = name return true end)
				listener()(charger, 1, ply)
				expect(Use.Shown().text).to.equal("USE (HOLD)")

				expect(Use.OnUsePressed(10)).to.beTrue()
				expect(#events).to.equal(1)
				expect(Use.Dimmed(10.1)).to.beFalse() -- a held use is not a use "done": no dimming
				expect(Use.OnUsePressed(10.2)).to.beFalse() -- the bind repeating while the key is down
				expect(Use.OnUsePressed(11)).to.beFalse()
				expect(#events).to.equal(1)
				expect(Use.Shown()).to.exist()

				-- the release, then a new press: one more
				expect(isfunction(Use.OnUseReleased)).to.beTrue()
				Use.OnUseReleased()
				expect(Use.OnUsePressed(12)).to.beTrue()
				expect(#events).to.equal(2)

				-- looking away while the key is down ends the hold for the prompt (the release may never be seen): the next thing gets its pulse
				listener()(nil, 0, ply)
				listener()(fake("item_suitcharger"), 1, ply)
				expect(Use.OnUsePressed(13)).to.beTrue()
				expect(#events).to.equal(3)

				-- the game's bind hook drives it: +use down, down again (a repeat), up
				local bind = hook.GetTable()["PlayerBindPress"]["GryUseFeedback"]

				Use.OnUseReleased()
				bind(ply, "+use", true)
				bind(ply, "+use", true)
				expect(#events).to.equal(4)
				bind(ply, "+use", false)
				bind(ply, "+use", true)
				expect(#events).to.equal(5)
				-- another bind does not count
				bind(ply, "+jump", true)
				bind(ply, "+jump", false)
				expect(#events).to.equal(5)
			end
		},
		{
			-- fails if the floor turret were still a "USE" without limits, or if the props group did not hold it
			name = "the floor turret is a carry: PICK UP in the props group, with no size or mass limit (the engine gives none), nothing without the group",
			func = function()
				local player = fakePlayer(false)
				local asked = 0
				local turret = fake("npc_turret_floor", {size = Vector(300, 300, 300), mass = 500})

				turret.EntIndex = function() return 777 end
				stub(Cross, "AskMass", function() asked = asked + 1 end)
				setConVar("gry_usehint_props", "0")
				expect(Cross.UsableFor(turret, player)).to.equal(0)

				setConVar("gry_usehint_props", "1")
				expect(Cross.UsableFor(turret, player)).to.equal(1)
				expect(asked).to.equal(0)

				local info = Use.Describe(turret, 1, player)

				expect(info.icon).to.equal("grab")
				expect(info.text).to.equal("PICK UP")
			end
		},
		{
			-- fails when an entry's own cooldown or ready function is not read
			name = "the entry's cooldown (0.5 s for a gmod button, 0.5 s when it gives none) and its ready(ent) function decide when the prompt is dimmed",
			func = function()
				local events = {}
				local ready = true
				local ply = fakePlayer()

				stub(GryMod.API, "HUDEvent", function(name) events[#events + 1] = name return true end)
				setConVar("gry_usehint_feedback", "1")

				listener()(fake("gmod_button"), 1, ply)
				expect(Use.OnUsePressed(20)).to.beTrue()
				expect(Use.Dimmed(20.4)).to.beTrue()
				expect(Use.Dimmed(20.6)).to.beFalse()

				-- a repeatable entry with no cooldown: the default of half a second
				GryMod.API.RegisterUsable("test_use_repeat", {class = "test_use_thing", use = "repeat"})
				GryMod.API.RegisterUsable("test_use_ready", {class = "test_use_ready_thing", use = "repeat", cooldown = 0, ready = function() return ready end})

				local ok, err = pcall(function()
					listener()(fake("test_use_thing"), 1, ply)
					expect(Use.OnUsePressed(30)).to.beTrue()
					expect(Use.Dimmed(30.4)).to.beTrue()
					expect(Use.Dimmed(30.6)).to.beFalse()

					-- ready(ent) false: dimmed, and the key does nothing, whatever the clock says
					events = {}
					listener()(fake("test_use_ready_thing"), 1, ply)
					ready = false
					expect(Use.Dimmed(40)).to.beTrue()
					expect(Use.OnUsePressed(40)).to.beFalse()
					expect(#events).to.equal(0)

					ready = true
					expect(Use.Dimmed(40.1)).to.beFalse()
					expect(Use.OnUsePressed(40.1)).to.beTrue()
					expect(#events).to.equal(1)
				end)

				GryMod.API.UnregisterUsable("test_use_repeat")
				GryMod.API.UnregisterUsable("test_use_ready")
				assert(ok, tostring(err))
			end
		},
		{
			-- fails without the switch gry_usehint_feedback
			name = "with gry_usehint_feedback 0 a repeatable use makes no event and no dimming (a one-shot use still takes the prompt away)",
			func = function()
				local events = {}
				local ply = fakePlayer()

				stub(GryMod.API, "HUDEvent", function(name) events[#events + 1] = name return true end)
				expect(GetConVar("gry_usehint_feedback")).toNot.beNil()
				expect(GetConVar("gry_usehint_feedback"):GetDefault()).to.equal("1")
				setConVar("gry_usehint_feedback", "0")

				listener()(fake("prop_door_rotating"), 1, ply)
				Use.OnUsePressed(50)
				expect(#events).to.equal(0)
				expect(Use.Dimmed(50.1)).to.beFalse()

				listener()(fake("func_tank"), 1, ply)
				expect(Use.OnUsePressed(51)).to.beTrue()
				expect(Use.Shown()).to.beNil()
			end
		},
		{
			-- fails without the HUD event: the picture and the sound are ONE call (docs/events.md)
			name = "the HUD event use_feedback is registered, plays one sound and pulses the icon for a moment",
			func = function()
				local played = {}

				stub(GryMod, "PlaySound", function(path) played[#played + 1] = path return true end)
				setConVar("gry_sounds", "1")

				expect(GryMod.API.ListHUDEvents()).to.contain("use_feedback")

				listener()(fake("prop_door_rotating"), 1, fakePlayer())
				expect(Use.Pulse(0)).to.equal(0)

				expect(GryMod.API.HUDEvent("use_feedback")).to.beTrue()
				expect(#played).to.equal(1)
				expect(played[1]).to.equal(Use.FEEDBACK_SOUND)

				-- the pulse is on for a quarter of a second, strongest at the start
				local now = RealTime()
				expect(Use.Pulse(now) > 0.5).to.beTrue()
				expect(Use.Pulse(now + 1)).to.equal(0)
			end
		},
		{
			-- fails without the listener of the bind: the key must be seen when pressed (not polled), and never swallowed
			name = "the use key is seen through PlayerBindPress (a press of +use only, nothing returned so the game still gets it) and nothing runs in between",
			func = function()
				local seen = {}
				local bind = hook.GetTable()["PlayerBindPress"] and hook.GetTable()["PlayerBindPress"]["GryUseFeedback"]

				expect(bind).to.exist()
				stub(Use, "OnUsePressed", function(now) seen[#seen + 1] = now return true end)

				expect(bind(fakePlayer(), "+use", true)).to.beNil()
				expect(#seen).to.equal(1)
				expect(bind(fakePlayer(), "+use", false)).to.beNil() -- the release
				expect(bind(fakePlayer(), "+attack", true)).to.beNil() -- another key
				expect(bind(fakePlayer(), "+use; +speed", true)).to.beNil()
				expect(#seen).to.equal(2) -- a bind that holds +use counts
			end
		}
	}
}
