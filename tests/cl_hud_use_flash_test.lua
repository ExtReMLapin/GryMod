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
			-- fails if the crosshair's report were not made through the hook, or a failing listener broke it
			name = "the crosshair reports through the hook GryMod_UsableChanged, and a listener that fails does not stop the others",
			func = function()
				local told = {}
				local errors = {}

				stub(_G, "ErrorNoHalt", function(text) errors[#errors + 1] = text end)
				hook.Add("GryMod_UsableChanged", "gry_use_test_bad", function() error("boom") end)
				hook.Add("GryMod_UsableChanged", "gry_use_test_spy", function(ent, mode, ply) told[#told + 1] = {ent, mode, ply} end)

				local ok, err = pcall(function()
					local ent, ply = fake("func_button"), fakePlayer()

					Cross.ReportUsable(ent, 1, ply)
					expect(#errors).to.equal(1)
					expect(#told).to.equal(1)
					expect(told[1][1]).to.equal(ent)
					expect(told[1][2]).to.equal(1)
					expect(told[1][3]).to.equal(ply)
				end)

				hook.Remove("GryMod_UsableChanged", "gry_use_test_bad")
				hook.Remove("GryMod_UsableChanged", "gry_use_test_spy")
				assert(ok, tostring(err))
			end
		}
	}
}
