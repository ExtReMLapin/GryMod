-- Tests of the registry of usable entities (GryMod.API.RegisterUsable / GetUsable / UsableText, lua/grymod/sh_api_usable.lua), GLuaTest
-- format, runs in either realm: what the use prompt under the crosshair says about an entity (an icon and a text), the stock Half-Life 2
-- entries registered as data, the priority of an addon's entry over them, and the validation of a definition. Fake entities (tables) are
-- enough: the registry reads their class, their Base, IsWeapon, IsVehicle and GetPrintName. Every entry a case adds is removed afterwards.

local API = GryMod.API

local added = {}

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

local function register(key, def)
	added[#added + 1] = key

	return API.RegisterUsable(key, def)
end

return {
	groupName = "GryMod extension API: usable entities (the use prompt)",
	afterEach = function()
		for _, key in ipairs(added) do
			pcall(API.UnregisterUsable, key)
		end

		added = {}
	end,
	cases = {
		{
			-- fails without the stock entries
			name = "the stock entries say what the Half-Life 2 things are: weapon and item (TAKE), vehicle (ENTER VEHICLE), ladder (CLIMB), prop (PICK UP), door and button (USE)",
			func = function()
				local function describe(ent)
					local entry = API.GetUsable(ent)

					return entry and entry.icon, API.UsableText(ent, nil, entry)
				end

				local icon, text = describe(fake("weapon_smg1", {weapon = true, print = "Submachine gun"}))
				expect(icon).to.equal("pickup")
				expect(text).to.equal("TAKE SUBMACHINE GUN")

				icon, text = describe(fake("item_healthkit"))
				expect(icon).to.equal("pickup")
				expect(text).to.equal("TAKE HEALTHKIT")

				icon, text = describe(fake("item_ammo_smg1"))
				expect(text).to.equal("TAKE AMMO SMG1")

				icon, text = describe(fake("prop_vehicle_jeep", {vehicle = true}))
				expect(icon).to.equal("enter")
				expect(text).to.equal("ENTER VEHICLE")

				icon, text = describe(fake("func_useableladder"))
				expect(icon).to.equal("ladder")
				expect(text).to.equal("CLIMB")

				for _, class in ipairs({"prop_physics", "prop_physics_multiplayer", "prop_ragdoll"}) do
					icon, text = describe(fake(class))
					expect(icon).to.equal("grab")
					expect(text).to.equal("PICK UP")
				end

				for _, class in ipairs({"func_button", "prop_door_rotating", "func_door_rotating", "momentary_rot_button", "func_rot_button"}) do
					icon, text = describe(fake(class))
					expect(icon).to.equal("use")
					expect(text).to.equal("USE")
				end

				-- something no entry names: nothing (the prompt then shows the plain USE itself)
				expect(API.GetUsable(fake("func_brush"))).to.beNil()
				expect(API.UsableText(fake("func_brush"), nil)).to.beNil()
				expect(API.GetUsable(nil)).to.beNil()
				expect(API.GetUsable({})).to.beNil()
			end
		},
		{
			-- fails without the name rules
			name = "the %1 of a text is the name of the entry, else the name the weapon carries, else its class without the start and with spaces",
			func = function()
				expect(register("test_named", {class = "test_thing", text = "TAKE %1", name = "Blue key"})).to.beTrue()
				expect(API.UsableText(fake("test_thing"), nil)).to.equal("TAKE BLUE KEY")

				expect(register("test_func_name", {class = "test_thing2", text = "TAKE %1", name = function(ent) return "thing " .. ent.class end})).to.beTrue()
				expect(API.UsableText(fake("test_thing2"), nil)).to.equal("TAKE THING TEST_THING2")

				-- a name function that gives nothing usable falls back to the class
				expect(register("test_bad_name", {class = "weapon_test_gun", text = "TAKE %1", name = function() return 5 end})).to.beTrue()
				expect(API.UsableText(fake("weapon_test_gun"), nil)).to.equal("TAKE TEST GUN")

				-- a text without %1 does not ask for a name
				expect(register("test_plain", {class = "test_plain", text = "open it"})).to.beTrue()
				expect(API.UsableText(fake("test_plain"), nil)).to.equal("OPEN IT")
			end
		},
		{
			-- fails without the priority rule
			name = "an addon's entry beats the stock one for the same class, whatever the order; removing it gives the stock one back",
			func = function()
				expect(register("test_door", {class = "prop_door_rotating", icon = "enter", text = "OPEN THE DOOR"})).to.beTrue()

				local door = fake("prop_door_rotating")
				expect(API.GetUsable(door).icon).to.equal("enter")
				expect(API.UsableText(door, nil)).to.equal("OPEN THE DOOR")

				expect(API.UnregisterUsable("test_door")).to.beTrue()
				expect(API.GetUsable(door).icon).to.equal("use")
				expect(API.UsableText(door, nil)).to.equal("USE")
				expect(API.UnregisterUsable("test_door")).to.beFalse()
			end
		},
		{
			-- fails without the match function, the base class and the function of the text
			name = "an entry can match by a function or by a base class, and its text can be a function of the entity and the player",
			func = function()
				expect(register("test_match", {match = function(ent) return ent.special == true end, icon = "grab", text = "GRAB IT"})).to.beTrue()
				expect(API.GetUsable(fake("test_odd", {special = true})).icon).to.equal("grab")
				expect(API.GetUsable(fake("test_odd", {special = false}))).to.beNil()

				expect(register("test_base", {base = "base_test_usable", text = "BASED"})).to.beTrue()
				expect(API.UsableText(fake("test_child", {Base = "base_test_usable"}), nil)).to.equal("BASED")

				local got
				expect(register("test_text_fn", {class = "test_fn", text = function(ent, ply) got = {ent, ply} return "from a function" end})).to.beTrue()

				local ent = fake("test_fn")
				expect(API.UsableText(ent, "the player")).to.equal("FROM A FUNCTION")
				expect(got[1]).to.equal(ent)
				expect(got[2]).to.equal("the player")

				-- a function that gives no text falls back to the plain use text
				expect(register("test_text_bad", {class = "test_fn_bad", text = function() return nil end})).to.beTrue()
				expect(API.UsableText(fake("test_fn_bad"), nil)).to.equal("USE")
			end
		},
		{
			-- fails without the validation
			name = "a definition that is not valid is refused with a reason and keeps the previous entry",
			func = function()
				expect(register("test_valid", {class = "test_valid", text = "FIRST"})).to.beTrue()

				for _, def in ipairs({
					{class = "test_valid", icon = "fly"},
					{class = "test_valid", text = ""},
					{class = "test_valid", text = 5},
					{class = "test_valid", name = {}},
					{class = "test_valid", priority = 5000},
					{class = "test_valid", priority = "high"},
					{class = {}},
					{class = {"ok", 5}},
					{icon = "use"}
				}) do
					local ok, reason = API.RegisterUsable("test_valid", def)
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(API.UsableText(fake("test_valid"), nil)).to.equal("FIRST")

				for _, key in ipairs({"", 5, nil}) do
					expect((API.RegisterUsable(key, {class = "x"}))).to.beFalse()
				end

				expect((API.RegisterUsable("test_valid", "not a table"))).to.beFalse()
			end
		},
		{
			-- fails if the five icons were not the ones of the movie
			name = "the icons are the five frames of the movie: use, enter, pickup, grab, ladder",
			func = function()
				local count = 0

				for name in pairs(API.UsableIcons) do
					count = count + 1
					expect(isstring(name)).to.beTrue()
				end

				expect(count).to.equal(5)

				for _, icon in ipairs({"use", "enter", "pickup", "grab", "ladder"}) do
					expect(API.UsableIcons[icon]).to.beTrue()
				end
			end
		}
	}
}
