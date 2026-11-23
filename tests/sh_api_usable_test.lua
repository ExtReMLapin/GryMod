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
	function ent:IsNPC() return self.npc == true end
	function ent:Health() return self.health or 0 end

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
			name = "the stock entries say what the Half-Life 2 things are: ammo crate (TAKE AMMO), vehicle (ENTER VEHICLE), ladder (CLIMB), prop (PICK UP), door and button (USE); a weapon or an item that is taken by walking over it is not one",
			func = function()
				local function describe(ent)
					local entry = API.GetUsable(ent)

					return entry and entry.icon, API.UsableText(ent, nil, entry)
				end

				-- what is taken by WALKING OVER it needs no key, so it gets no prompt (checked in game: a health kit, a battery and a pistol on the floor were taken
				-- by touch, the base gamemode's PlayerCanPickupWeapon says yes)
				expect(API.GetUsable(fake("weapon_smg1", {weapon = true, print = "Submachine gun"}))).to.beNil()
				expect(API.GetUsable(fake("item_healthkit"))).to.beNil()
				expect(API.GetUsable(fake("item_ammo_smg1"))).to.beNil()

				local icon, text = describe(fake("item_ammo_crate"))
				expect(icon).to.equal("pickup")
				expect(text).to.equal("TAKE AMMO")

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
			-- fails when a class that the Source SDK or the Lua of Garry's Mod gives a +use action is missing, when one that has none is named, or when a text or an
			-- icon is not the one of the original game
			name = "every class that has a +use action is registered with its text and icon, and the ones that have none are not",
			func = function()
				local function describe(class, fields)
					local ent = fake(class, fields)
					local entry = API.GetUsable(ent)

					return entry and entry.icon, API.UsableText(ent, nil, entry)
				end

				local table_ = {
					-- {class, fields, icon, text}
					{"item_ammo_crate", nil, "pickup", "TAKE AMMO"},
					{"item_healthcharger", nil, "use", "USE"},
					{"item_suitcharger", nil, "use", "USE"},
					{"func_healthcharger", nil, "use", "USE"},
					{"func_recharge", nil, "use", "USE"},
					{"prop_vehicle_airboat", {vehicle = true}, "enter", "ENTER VEHICLE"},
					{"prop_vehicle_prisoner_pod", {vehicle = true}, "enter", "ENTER VEHICLE"},
					{"func_physbox", nil, "grab", "PICK UP"},
					{"npc_grenade_frag", nil, "grab", "PICK UP"},
					{"func_door", nil, "use", "USE"},
					{"func_rot_button", nil, "use", "USE"},
					{"momentary_rot_button", nil, "use", "USE"},
					{"func_tank", nil, "use", "USE"},
					{"func_tankrocket", nil, "use", "USE"},
					{"npc_turret_floor", nil, "use", "USE"},
					{"npc_citizen", {npc = true, health = 40}, "use", "TALK"},
					{"npc_barney", {npc = true, health = 40}, "use", "TALK"},
					{"npc_alyx", {npc = true, health = 40}, "use", "TALK"},
					{"npc_vortigaunt", {npc = true, health = 40}, "use", "TALK"},
					{"npc_mossman", {npc = true, health = 40}, "use", "TALK"},
					{"npc_monk", {npc = true, health = 40}, "use", "TALK"},
					{"npc_metropolice", {npc = true, health = 40}, "use", "USE"},
					{"gmod_button", nil, "use", "USE"},
					{"gmod_wheel", nil, "use", "USE"},
					{"sent_ball", nil, "pickup", "TAKE BALL"}
				}

				for _, row in ipairs(table_) do
					local icon, text = describe(row[1], row[2])
					expect(icon).to.equal(row[3])
					expect(text).to.equal(row[4])
				end

				-- no +use action: no entry
				for _, row in ipairs({
					{"weapon_crowbar", {weapon = true, print = "Crowbar"}}, {"weapon_pistol", {weapon = true}}, {"item_healthkit"}, {"item_healthvial"}, {"item_battery"},
					{"item_suit"}, {"item_ammo_pistol"}, {"item_ammo_357_large"}, {"item_box_buckshot"}, {"item_rpg_round"}, {"item_ammo_smg1_grenade"}, {"item_some_new_thing"},
					{"combine_mine"}, {"npc_kleiner", {npc = true, health = 40}}, {"npc_eli", {npc = true, health = 40}}, {"npc_breen", {npc = true, health = 40}},
					{"npc_dog", {npc = true, health = 40}}, {"item_item_crate"}, {"item_dynamic_resupply"}, {"npc_combine_s", {npc = true, health = 40}},
					{"npc_zombie", {npc = true, health = 40}}, {"prop_dynamic"}, {"func_brush"}
				}) do
					expect(API.GetUsable(fake(row[1], row[2]))).to.beNil()
				end

				-- an NPC that is dead answers no +use
				expect(API.GetUsable(fake("npc_citizen", {npc = true, health = 0}))).to.beNil()
				expect(API.GetUsable(fake("npc_metropolice", {npc = true, health = 0}))).to.beNil()
				-- a stand-in without the methods is no error and no entry (five errors in a row would switch a matcher off)
				for _ = 1, 8 do
					expect(API.GetUsable({IsValid = function() return true end, GetClass = function() return "mystery" end})).to.beNil()
				end

				expect(API.GetUsable(fake("npc_citizen", {npc = true, health = 40}))).to.exist()
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
			-- fails without the group / use / cooldown / ready / busy fields and the stock values
			name = "an entry can say its group, whether its use repeats or changes the state (once, the default), its cooldown, a ready function and a busy function; a bad one is refused; the stock entries carry them",
			func = function()
				expect(register("test_fields", {class = "test_f", group = "things", use = "repeat", cooldown = 2, ready = function() return true end, busy = function() return false end})).to.beTrue()

				local entry = API.GetUsable(fake("test_f"))

				expect(entry.group).to.equal("things")
				expect(entry.use).to.equal("repeat")
				expect(entry.cooldown).to.equal(2)
				expect(isfunction(entry.ready) and isfunction(entry.busy)).to.beTrue()

				-- the defaults: no group, a one-shot use, no cooldown
				expect(register("test_defaults", {class = "test_g"})).to.beTrue()

				local plain = API.GetUsable(fake("test_g"))

				expect(plain.group).to.beNil()
				expect(plain.use).to.equal("once")
				expect(plain.cooldown).to.beNil()

				for _, bad in ipairs({
					{class = "test_h", use = "sometimes"}, {class = "test_h", use = 5}, {class = "test_h", cooldown = -1}, {class = "test_h", cooldown = 61},
					{class = "test_h", cooldown = "1"}, {class = "test_h", group = ""}, {class = "test_h", group = 7}, {class = "test_h", group = "Bad Group"},
					{class = "test_h", ready = "yes"}, {class = "test_h", busy = 3}
				}) do
					expect((register("test_bad_field", bad))).to.beFalse()
				end

				-- the stock values: what repeats (a door, a button, a charger, the ammo crate, a talker) and what changes the state (a vehicle, a tank, a ladder, a prop)
				local function stock(class, fields) return API.GetUsable(fake(class, fields)) end

				for class, cooldown in pairs({prop_door_rotating = 1, func_door = 1, func_button = 1, func_rot_button = 1, momentary_rot_button = 1, item_healthcharger = 0.5,
					item_suitcharger = 0.5, item_ammo_crate = 1}) do
					expect(stock(class).use).to.equal("repeat")
					expect(stock(class).cooldown).to.equal(cooldown)
				end

				expect(stock("npc_citizen", {npc = true, health = 40}).use).to.equal("repeat")

				for _, class in ipairs({"func_tank", "func_useableladder", "npc_grenade_frag", "prop_physics"}) do
					expect(stock(class).use).to.equal("once")
				end

				expect(stock("prop_vehicle_jeep", {vehicle = true}).use).to.equal("once")

				-- the props are the optional group; the grenade, the ladder, the tank and the doors are not in it
				for _, class in ipairs({"prop_physics", "prop_physics_multiplayer", "prop_ragdoll", "func_physbox"}) do
					expect(stock(class).group).to.equal("props")
				end

				for _, class in ipairs({"npc_grenade_frag", "func_useableladder", "func_tank", "prop_door_rotating", "item_ammo_crate"}) do
					expect(stock(class).group).to.beNil()
				end

				-- the ladder is busy while the player climbs it
				expect(isfunction(stock("func_useableladder").busy)).to.beTrue()
				expect(stock("func_useableladder").busy(nil, {GetMoveType = function() return MOVETYPE_LADDER end})).to.equal(true)
				expect(stock("func_useableladder").busy(nil, {GetMoveType = function() return MOVETYPE_WALK end})).to.equal(false)
			end
		},
		{
			-- fails without the nonsolid field and API.UsableNonSolidClasses (a ladder is not solid: the eye trace cannot find it, the crosshair looks for these classes)
			name = "an entry can be marked nonsolid (it needs a class): its classes are listed for the crosshair to look for, the stock ladder is one",
			func = function()
				expect(isfunction(API.UsableNonSolidClasses)).to.beTrue()

				local list = API.UsableNonSolidClasses()
				local found = false

				for _, class in ipairs(list) do
					found = found or class == "func_useableladder"
				end

				expect(found).to.beTrue()

				expect(register("test_nonsolid", {class = {"test_ghost_a", "test_ghost_b"}, nonsolid = true, icon = "use", text = "USE"})).to.beTrue()

				local seen = {}

				for _, class in ipairs(API.UsableNonSolidClasses()) do
					seen[class] = true
				end

				expect(seen.test_ghost_a and seen.test_ghost_b).to.beTrue()
				expect(API.GetUsable(fake("test_ghost_a")).nonsolid).to.equal(true)

				-- removing the entry removes its classes
				API.UnregisterUsable("test_nonsolid")
				seen = {}

				for _, class in ipairs(API.UsableNonSolidClasses()) do
					seen[class] = true
				end

				expect(seen.test_ghost_a).to.beNil()

				-- nonsolid needs a class, and must be a boolean
				local ok, why = register("test_nonsolid_match", {match = function() return true end, nonsolid = true})

				expect(ok).to.beFalse()
				expect(isstring(why)).to.beTrue()
				expect((register("test_nonsolid_bad", {class = "test_ghost_c", nonsolid = "yes"}))).to.beFalse()
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
