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

	-- the spawnflags only when the case gives them: an entity that says nothing about them (a stand-in, a client that cannot read them) must pass
	if fields and fields.flags ~= nil then
		function ent:GetSpawnFlags() return self.flags end
	end

	if fields and fields.print then
		function ent:GetPrintName() return self.print end
	end

	return ent
end

local function register(key, def)
	added[#added + 1] = key

	return API.RegisterUsable(key, def)
end

-- Runs fn with the replicated variable sv_ladder_useonly set to `value` ("0" or "1", or nil for a variable that does not exist), and puts the game's
-- GetConVar back whatever happens: the stock ladder entry reads it through GetConVar at each question.
local function withLadderUseOnly(value, fn)
	local saved = GetConVar

	GetConVar = function(name)
		if name == "sv_ladder_useonly" then
			if value == nil then
				return nil
			end

			return {GetBool = function() return value == "1" end, GetInt = function() return tonumber(value) end}
		end

		return saved(name)
	end

	local ok, err = pcall(fn)

	GetConVar = saved

	if not ok then
		error(err, 0)
	end
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

				-- the ladder (CLIMB) is climbed by walking into it unless sv_ladder_useonly is 1: it has its own case below

				for _, class in ipairs({"prop_physics", "prop_physics_multiplayer", "func_physbox"}) do
					icon, text = describe(fake(class))
					expect(icon).to.equal("grab")
					expect(text).to.equal("PICK UP")
				end

				-- (with the flags that make them react to the key, see the spawnflags case)
				for class, flags in pairs({func_button = 1024, prop_door_rotating = 0, func_door_rotating = 256, func_rot_button = 1024}) do
					icon, text = describe(fake(class, {flags = flags}))
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
					{"item_healthcharger", nil, "use", "USE (HOLD)"},
					{"item_suitcharger", nil, "use", "USE (HOLD)"},
					{"func_healthcharger", nil, "use", "USE (HOLD)"},
					{"func_recharge", nil, "use", "USE (HOLD)"},
					{"prop_vehicle_airboat", {vehicle = true}, "enter", "ENTER VEHICLE"},
					{"prop_vehicle_prisoner_pod", {vehicle = true}, "enter", "ENTER VEHICLE"},
					{"func_physbox", nil, "grab", "PICK UP"},
					{"npc_grenade_frag", nil, "grab", "PICK UP"},
					{"func_door", {flags = 256}, "use", "USE"},
					{"func_rot_button", {flags = 1024}, "use", "USE"},
					{"momentary_rot_button", {flags = 1024}, "use", "USE (HOLD)"},
					{"func_tank", {flags = 32}, "use", "USE"},
					{"func_tankrocket", {flags = 32}, "use", "USE"},
					-- the floor turret is carried (checked in game: its Use makes the player hold it), so it is a "PICK UP", with the props
					{"npc_turret_floor", nil, "grab", "PICK UP"},
					{"npc_citizen", {npc = true, health = 40}, "use", "TALK"},
					{"npc_barney", {npc = true, health = 40}, "use", "TALK"},
					{"npc_alyx", {npc = true, health = 40}, "use", "TALK"},
					{"npc_vortigaunt", {npc = true, health = 40}, "use", "TALK"},
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
					{"npc_zombie", {npc = true, health = 40}}, {"prop_dynamic"}, {"func_brush"},
					-- a use cap in the engine but nothing happens (table B of the catalogue; the ObjectCaps of the monk, Dr Mossman, G-Man and the metropolice were read in
					-- game: 26, a use cap, and their Use does nothing or only annoys the cop)
					{"npc_monk", {npc = true, health = 40}}, {"npc_mossman", {npc = true, health = 40}}, {"npc_gman", {npc = true, health = 40}},
					{"npc_metropolice", {npc = true, health = 40}}, {"cycler"}, {"cycler_actor"}, {"func_pushable"}, {"gib"}, {"func_tracktrain"},
					-- a ragdoll has no use cap in the game (ObjectCaps read in game: no +use bit)
					{"prop_ragdoll"}
					}) do
					expect(API.GetUsable(fake(row[1], row[2]))).to.beNil()
				end

				-- an NPC that is dead answers no +use
				expect(API.GetUsable(fake("npc_citizen", {npc = true, health = 0}))).to.beNil()
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

				for _, class in ipairs({"func_tank", "npc_grenade_frag", "prop_physics"}) do
					expect(stock(class).use).to.equal("once")
				end

				expect(stock("prop_vehicle_jeep", {vehicle = true}).use).to.equal("once")

				-- the props are the optional group; the grenade, the ladder, the tank and the doors are not in it
				for _, class in ipairs({"prop_physics", "prop_physics_multiplayer", "npc_turret_floor", "func_physbox"}) do
					expect(stock(class).group).to.equal("props")
				end

				for _, class in ipairs({"npc_grenade_frag", "func_tank", "prop_door_rotating", "item_ammo_crate"}) do
					expect(stock(class).group).to.beNil()
				end

				-- the ladder (when sv_ladder_useonly is 1) is a one-shot use and busy while the player climbs it
				withLadderUseOnly("1", function()
					expect(stock("func_useableladder").use).to.equal("once")
					expect(isfunction(stock("func_useableladder").busy)).to.beTrue()
					expect(stock("func_useableladder").busy(nil, {GetMoveType = function() return MOVETYPE_LADDER end})).to.equal(true)
					expect(stock("func_useableladder").busy(nil, {GetMoveType = function() return MOVETYPE_WALK end})).to.equal(false)
				end)
			end
		},
		{
			-- fails without the nonsolid field and API.UsableNonSolidClasses (a ladder is not solid: the eye trace cannot find it, the crosshair looks for these classes)
			name = "an entry can be marked nonsolid (it needs a class): its classes are listed for the crosshair to look for, the stock ladder is one",
			func = function()
				expect(isfunction(API.UsableNonSolidClasses)).to.beTrue()

				local found = false

				withLadderUseOnly("1", function()
					for _, class in ipairs(API.UsableNonSolidClasses()) do
						found = found or class == "func_useableladder"
					end
				end)

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
			-- fails without the spawnflags rule of the stock entries and of the `spawnflags` field (the flags are in the game's data: GetSpawnFlags is readable on the client)
			name = "the spawnflags decide what reacts to the key: a door that ignores +use, a func_door without 'Use opens', a button that is touch or damage only, a gun that is not controllable and a prop that cannot be lifted get no entry",
			func = function()
				local function usable(class, flags)
					return API.GetUsable(fake(class, {flags = flags})) ~= nil
				end

				-- prop_door_rotating: 32768 "Ignore player +USE" (not 256: that is the func_door's); locked at start (2048) and 'Use closes' (8192) still react
				expect(usable("prop_door_rotating", 0)).to.beTrue()
				expect(usable("prop_door_rotating", 8192)).to.beTrue()
				expect(usable("prop_door_rotating", 2048)).to.beTrue()
				expect(usable("prop_door_rotating", 34816)).to.beFalse() -- barney_door_2 of d1_trainstation_01 (32768 + 2048)
				expect(usable("prop_door_rotating", 34817)).to.beFalse() -- barney_door_1
				expect(usable("prop_door_rotating", 256)).to.beTrue() -- 256 means nothing for a prop door

				-- func_door, func_door_rotating: 256 "Use opens" is needed
				for _, class in ipairs({"func_door", "func_door_rotating"}) do
					expect(usable(class, 256)).to.beTrue()
					expect(usable(class, 2312)).to.beTrue() -- the door at -766 -7378 56 of d1_canals_01 (locked at start, 'Use opens')
					expect(usable(class, 0)).to.beFalse()
					expect(usable(class, 1024)).to.beFalse() -- "Touch opens" alone
					expect(usable(class, 2048)).to.beFalse()
					expect(usable(class, 32)).to.beFalse() -- a train gate with 'Toggle' only
				end

				-- func_button, func_rot_button, momentary_rot_button: 1024 "Use activates" is needed
				for _, class in ipairs({"func_button", "func_rot_button", "momentary_rot_button"}) do
					expect(usable(class, 1025)).to.beTrue() -- soda_machine_1 of d1_trainstation_01
					expect(usable(class, 3073)).to.beTrue() -- motor_button (locked + use)
					expect(usable(class, 1024)).to.beTrue()
					expect(usable(class, 512)).to.beFalse() -- damage only
					expect(usable(class, 513)).to.beFalse()
					expect(usable(class, 256)).to.beFalse() -- touch only
					expect(usable(class, 0)).to.beFalse()
				end

				-- the mounted guns: 32 "Controllable"
				for _, class in ipairs({"func_tank", "func_tankairboatgun", "func_tankrocket", "func_tank_combine_cannon"}) do
					expect(usable(class, 1312)).to.beTrue() -- turret_2 of d1_canals_01a
					expect(usable(class, 32)).to.beTrue()
					expect(usable(class, 5120)).to.beFalse() -- turret_1 of d2_coast_01: not controllable
					expect(usable(class, 0)).to.beFalse()
				end

				-- the props: 512 "Prevent pickup" never; a frozen prop (8) only with "enable motion on gravity gun grab" (64); the default 256 does not matter
				expect(usable("prop_physics", 256)).to.beTrue()
				expect(usable("prop_physics", 0)).to.beTrue()
				expect(usable("prop_physics", 256 + 512)).to.beFalse()
				expect(usable("prop_physics", 8)).to.beFalse()
				expect(usable("prop_physics", 8 + 64)).to.beTrue()
				expect(usable("prop_physics_multiplayer", 512)).to.beFalse()
				-- the physbox: 8192 "Ignore +USE for Pickup", 32768 motion disabled (131072 lets the gravity gun free it)
				expect(usable("func_physbox", 524288)).to.beTrue()
				expect(usable("func_physbox", 524288 + 8192)).to.beFalse()
				expect(usable("func_physbox", 32768)).to.beFalse()
				expect(usable("func_physbox", 32768 + 131072)).to.beTrue()

				-- an entity that cannot say its flags (no GetSpawnFlags) is not refused for them
				expect(API.GetUsable(fake("func_door"))).to.exist()
				expect(API.GetUsable(fake("prop_door_rotating"))).to.exist()
			end
		},
		{
			-- fails without API.UsableClassOf: on the client a func_button is "class C_BaseToggle", so no button was ever found
			name = "the class the registry matches on is the server's: a network class name (class C_...) goes through the resolver the client installs, nothing else does",
			func = function()
				local savedResolver = API.UsableClassResolver
				local asked = {}

				local ok, err = pcall(function()
					expect(isfunction(API.UsableClassOf)).to.beTrue()

					-- no resolver: the class stays what the entity says
					API.UsableClassResolver = nil
					expect(API.UsableClassOf(fake("class C_BaseToggle"))).to.equal("class C_BaseToggle")
					expect(API.GetUsable(fake("class C_BaseToggle", {flags = 1024}))).to.beNil()

					API.UsableClassResolver = function(ent, class) asked[#asked + 1] = class return "func_button" end
					expect(API.UsableClassOf(fake("class C_BaseToggle"))).to.equal("func_button")
					expect(API.UsableClassOf(fake("func_door"))).to.equal("func_door")
					expect(#asked).to.equal(1)

					expect(API.GetUsable(fake("class C_BaseToggle", {flags = 1025})).key).to.equal("hl2_buttons")
					expect(API.GetUsable(fake("class C_BaseToggle", {flags = 513}))).to.beNil()

					-- a resolver that answers nothing, or fails: the generic class, no entry, no error
					API.UsableClassResolver = function() return nil end
					expect(API.GetUsable(fake("class C_BaseToggle", {flags = 1024}))).to.beNil()
					API.UsableClassResolver = function() error("broken") end
					expect(API.UsableClassOf(fake("class C_BaseToggle"))).to.equal("class C_BaseToggle")
				end)

				API.UsableClassResolver = savedResolver

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without the `spawnflags` field (a table need / forbid, or a function) and its validation
			name = "an entry can carry a spawnflags rule: all the bits of `need`, none of `forbid`, or a function of the flags and the entity; a bad one is refused",
			func = function()
				expect(register("test_flags_table", {class = "test_fl", spawnflags = {need = 4 + 16, forbid = 2}})).to.beTrue()

				local function usable(flags) return API.GetUsable(fake("test_fl", {flags = flags})) ~= nil end

				expect(usable(4 + 16)).to.beTrue()
				expect(usable(4 + 16 + 64)).to.beTrue()
				expect(usable(4)).to.beFalse() -- one needed bit missing
				expect(usable(4 + 16 + 2)).to.beFalse() -- a forbidden bit

				local got
				expect(register("test_flags_fn", {class = "test_fl2", spawnflags = function(flags, ent) got = ent return flags == 7 end})).to.beTrue()

				local ent = fake("test_fl2", {flags = 7})
				expect(API.GetUsable(ent)).to.exist()
				expect(got).to.equal(ent)
				expect(API.GetUsable(fake("test_fl2", {flags = 6}))).to.beNil()

				-- a function that fails does not keep the thing from being usable for ever: the flags are then taken as unreadable
				expect(register("test_flags_err", {class = "test_fl3", spawnflags = function() error("broken") end})).to.beTrue()
				expect(API.GetUsable(fake("test_fl3", {flags = 1}))).to.exist()

				-- the API tells whether the flags let an entity through (for an addon that wants the same test)
				expect(isfunction(API.UsableFlagsAllow)).to.beTrue()
				expect(API.UsableFlagsAllow(API.GetUsable(fake("test_fl", {flags = 20})), fake("test_fl", {flags = 20}))).to.beTrue()
				expect(API.UsableFlagsAllow(nil, fake("test_fl"))).to.beTrue()

				for _, bad in ipairs({{need = "1"}, {forbid = -1}, {need = 1.5}, {need = 2 ^ 40}, {other = 1}, "flags", 5}) do
					local ok, why = register("test_flags_bad", {class = "test_fl4", spawnflags = bad})

					expect(ok).to.beFalse()
					expect(isstring(why)).to.beTrue()
				end
			end
		},
		{
			-- fails without the ladder's `active` gate: the ladder is climbed by walking into it unless the server set sv_ladder_useonly
			name = "the ladder prompt (CLIMB) exists only while sv_ladder_useonly is 1; an entry's `active` function says when it applies; the nonsolid classes follow",
			func = function()
				local ladder = fake("func_useableladder")

				-- the default (0): no prompt, and the crosshair does not even look for the ladder
				withLadderUseOnly("0", function()
					expect(API.GetUsable(ladder)).to.beNil()

					for _, class in ipairs(API.UsableNonSolidClasses()) do
						expect(class).toNot.equal("func_useableladder")
					end
				end)

				withLadderUseOnly("1", function()
					local entry = API.GetUsable(ladder)

					expect(entry).to.exist()
					expect(entry.icon).to.equal("ladder")
					expect(API.UsableText(ladder, nil, entry)).to.equal("CLIMB")

					local listed = false

					for _, class in ipairs(API.UsableNonSolidClasses()) do
						listed = listed or class == "func_useableladder"
					end

					expect(listed).to.beTrue()
				end)

				-- the variable is not there at all (a server that never defined it): no prompt, no error
				withLadderUseOnly(nil, function()
					expect(API.GetUsable(ladder)).to.beNil()
				end)

				-- the `active` field: a function, a bad one refused, and a failing one counts as "applies" (the entry must not vanish for ever)
				local on = false

				expect(register("test_active", {class = "test_act", active = function() return on end})).to.beTrue()
				expect(API.GetUsable(fake("test_act"))).to.beNil()
				on = true
				expect(API.GetUsable(fake("test_act"))).to.exist()
				expect((register("test_active_bad", {class = "test_act2", active = "yes"}))).to.beFalse()
				expect(register("test_active_err", {class = "test_act3", active = function() error("broken") end})).to.beTrue()
				expect(API.GetUsable(fake("test_act3"))).to.exist()
			end
		},
		{
			-- fails without the real reach of the key (80 units) and the `range` field
			name = "the reach of the use key is 80 units, an entry can say its own range (the stock ladder 64), and the greatest range tells how far to look",
			func = function()
				expect(API.USE_REACH).to.equal(80)
				expect(API.UsableRange(API.GetUsable(fake("item_ammo_crate")))).to.equal(80)
				expect(API.UsableRange(API.GetUsable(fake("func_tank", {flags = 32})))).to.equal(80)
				expect(API.UsableRange(nil)).to.equal(80)
				expect(API.UsableMaxRange()).to.equal(80)

				expect(register("test_range", {class = "test_rng", range = 150})).to.beTrue()
				expect(API.UsableRange(API.GetUsable(fake("test_rng")))).to.equal(150)
				expect(API.UsableMaxRange()).to.equal(150)

				-- it goes back when the entry goes
				API.UnregisterUsable("test_range")
				expect(API.UsableMaxRange()).to.equal(80)

				for _, bad in ipairs({0, -5, "far", 5000}) do
					expect((register("test_range_bad", {class = "test_rng2", range = bad}))).to.beFalse()
				end

				-- the ladder: its prompt is for the +use mode of the engine, within 64 units
				withLadderUseOnly("1", function()
					expect(API.UsableRange(API.GetUsable(fake("func_useableladder")))).to.equal(64)
				end)
			end
		},
		{
			-- fails without the `hold` field and the text of the things that must be held
			name = "what needs the key held (the chargers and the wheels) says USE (HOLD) and is marked hold; nothing else is",
			func = function()
				for _, class in ipairs({"item_healthcharger", "item_suitcharger", "func_healthcharger", "func_recharge", "momentary_rot_button"}) do
					local ent = fake(class, {flags = 1024})
					local entry = API.GetUsable(ent)

					expect(entry.hold).to.equal(true)
					expect(API.UsableText(ent, nil, entry)).to.equal("USE (HOLD)")
				end

				for _, class in ipairs({"func_button", "func_rot_button", "prop_door_rotating", "func_door", "item_ammo_crate", "gmod_button"}) do
					local entry = API.GetUsable(fake(class, {flags = 1024 + 256}))

					expect(entry.hold).toNot.equal(true)
					expect(API.UsableText(fake(class, {flags = 1024 + 256}), nil, entry)).to.equal(string.upper(entry.text))
				end

				expect(register("test_hold", {class = "test_hold", hold = true, text = "KEEP PRESSED"})).to.beTrue()
				expect(API.GetUsable(fake("test_hold")).hold).to.equal(true)
				expect((register("test_hold_bad", {class = "test_hold2", hold = "yes"}))).to.beFalse()
			end
		},
		{
			-- fails if the entries kept their wrong claims about the NPCs, ragdolls and the turret (table B / C of the catalogue)
			name = "the people: the citizen, Barney, Alyx and the vortigaunt talk (alive); the monk, Dr Mossman, G-Man, the metropolice and the dead ones do not",
			func = function()
				for _, class in ipairs({"npc_citizen", "npc_barney", "npc_alyx", "npc_vortigaunt"}) do
					expect(API.GetUsable(fake(class, {npc = true, health = 40}))).to.exist()
					expect(API.GetUsable(fake(class, {npc = true, health = 0}))).to.beNil()
				end

				for _, class in ipairs({"npc_monk", "npc_mossman", "npc_gman", "npc_metropolice", "npc_kleiner", "npc_eli", "npc_breen", "npc_dog"}) do
					expect(API.GetUsable(fake(class, {npc = true, health = 40}))).to.beNil()
				end

				-- the floor turret is part of the props group (a carry)
				local turret = API.GetUsable(fake("npc_turret_floor"))

				expect(turret.group).to.equal("props")
				expect(turret.icon).to.equal("grab")
				expect(turret.nolimits).to.equal(true)
				expect(API.GetUsable(fake("prop_ragdoll"))).to.beNil()
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
