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
			-- fails without Use.Describe
			name = "Describe: a weapon or an item is TAKE with the pickup icon, a vehicle ENTER, a ladder CLIMB, the rest the plain USE; nothing for a mode that is not 1",
			func = function()
				local player = fakePlayer()
				local weapon = Use.Describe(fake("weapon_smg1", {weapon = true, print = "SMG"}), 1, player)
				expect(weapon.icon).to.equal("pickup")
				expect(weapon.text).to.equal("TAKE SMG")

				local vehicle = Use.Describe(fake("prop_vehicle_jeep", {vehicle = true}), 1, player)
				expect(vehicle.icon).to.equal("enter")
				expect(vehicle.text).to.equal("ENTER VEHICLE")

				local ladder = Use.Describe(fake("func_useableladder"), 1, player)
				expect(ladder.icon).to.equal("ladder")
				expect(ladder.text).to.equal("CLIMB")

				local plain = Use.Describe(fake("func_something_unknown"), 1, player)
				expect(plain.icon).to.equal("use")
				expect(plain.text).to.equal("USE")

				-- the crosshair is red for what can not be used: no prompt for it, nor for nothing
				expect(Use.Describe(fake("weapon_smg1", {weapon = true}), 2, player)).to.beNil()
				expect(Use.Describe(fake("weapon_smg1", {weapon = true}), 0, player)).to.beNil()
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
					{"func_door", nil, 1}, {"prop_door_rotating", nil, 1}, {"func_tank", nil, 1}, {"npc_turret_floor", nil, 1},
					{"npc_citizen", {npc = true, health = 40}, 1}, {"npc_citizen", {npc = true, health = 0}, 0},
					{"npc_kleiner", {npc = true, health = 40}, 0}, {"npc_zombie", {npc = true, health = 40}, 0},
					{"item_healthkit", nil, 1}, {"item_healthcharger", nil, 1}, {"item_ammo_crate", nil, 1},
					{"item_item_crate", nil, 0}, {"combine_mine", nil, 0}, {"func_brush", nil, 0}, {"gmod_button", nil, 1}
				}) do
					expect(Cross.UsableFor(fake(row[1], row[2]), player)).to.equal(row[3])
				end

				-- the same vehicle is not usable from inside one
				expect(Cross.UsableFor(fake("prop_vehicle_jeep", {vehicle = true}), fakePlayer(true))).to.equal(0)
			end
		},
		{
			-- fails without the player's pickup limits (the Source SDK's CanPickupObject(ent, 35, 128))
			name = "a prop is usable only when the player can lift it: 35 kg and 128 units on every side at most (the size is read, the mass when the client has it)",
			func = function()
				local player = fakePlayer(false)

				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 40)}), player)).to.equal(1)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(128, 128, 128)}), player)).to.equal(1)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(129, 20, 20)}), player)).to.equal(0)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 200)}), player)).to.equal(0)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 20), mass = 35}), player)).to.equal(1)
				expect(Cross.UsableFor(fake("prop_physics", {size = Vector(20, 20, 20), mass = 36}), player)).to.equal(0)
				expect(Cross.UsableFor(fake("func_physbox", {size = Vector(20, 20, 20), mass = 300}), player)).to.equal(0)
				-- no size and no mass to read: usable (the client cannot tell)
				expect(Cross.UsableFor(fake("prop_physics"), player)).to.equal(1)
				-- a door is not a prop: the limits are for the grab icon only
				expect(Cross.UsableFor(fake("prop_door_rotating", {size = Vector(10, 100, 300)}), player)).to.equal(1)
				expect(Cross.PICKUP_MASS).to.equal(35)
				expect(Cross.PICKUP_SIZE).to.equal(128)
			end
		},
		{
			-- fails without the listener of the crosshair's hook, or if the paint hook were permanent
			name = "the crosshair's report shows the prompt (and adds the paint hook), the next report with nothing takes it away (and removes the hook)",
			func = function()
				expect(Use.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHUSE"]).to.beNil()

				listener()(fake("weapon_smg1", {weapon = true, print = "SMG"}), 1, fakePlayer())
				expect(Use.Shown().icon).to.equal("pickup")
				expect(Use.Shown().text).to.equal("TAKE SMG")
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
		}
	}
}
