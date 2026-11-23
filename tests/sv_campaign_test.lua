-- Tests of the campaign objectives RUNTIME (lua/grymod/server/sv_campaign.lua), GLuaTest format, server realm: a map's list is read only for the map being played,
-- the first steps and the exit are listed, the hooks that finish a step (AcceptInput by input name then entity name, WeaponEquip, PlayerEnteredVehicle, PlayerUse,
-- OnNPCKilled, EntityRemoved, ShutDown for the exit) exist only while a step of their kind waits, a done step lists the next one and is saved, the map's own "game
-- over" fails the primary steps, the progress comes back when the map starts again (and what the world proves is added), the secrets are a counter that is off by
-- default, a third party adds or replaces objectives, and the switches and the reset command.
--
-- Nothing here uses the real map, the real players or the real save: the list of a made-up map "gry_campaign_test_map" is given through the API, the store is an
-- in-memory backend, the players, the entities of the map and the timers are replaced for the length of a case (`scene`: all put back inside a pcall, whatever
-- happens), and the hooks are called the way the engine calls them. When the game that runs the tests is on a campaign map, its own objectives are started again
-- after every case. Each case names the production change whose absence makes it fail.

local S, C, API
local MAP = "gry_campaign_test_map"
local HOOK_ID = "GryMod campaign"

local saved, timers, players, mapEnts, store

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a table that answers like a map entity
local function ent(t)
	return {
		IsValid = function() return true end,
		IsPlayer = function() return false end,
		GetClass = function() return t.class or "" end,
		GetName = function() return t.name or "" end,
		GetPos = function() return t.pos or Vector(0, 0, 0) end,
		MapCreationID = function() return t.mapid or 0 end,
		GetKeyValues = function() return t.kv or {} end,
		WorldSpaceAABB = function() return t.mins or Vector(0, 0, 0), t.maxs or Vector(0, 0, 0) end
	}
end

local function ply(t)
	t = t or {}

	return {
		IsValid = function() return true end,
		IsPlayer = function() return true end,
		Alive = function() return true end,
		IsAdmin = function() return t.admin == true end,
		GetPos = function() return t.pos or Vector(0, 0, 0) end,
		HasWeapon = function(_, class) return t.weapons ~= nil and t.weapons[class] == true end,
		GetVehicle = function() return t.vehicle or NULL end,
		IsSuitEquipped = function() return t.suit == true end,
		PrintMessage = function() end
	}
end

-- a raw objective as a developer writes it
local function def(id, extra)
	local d = {id = id, title = "Title " .. id, pos = Vector(1, 2, 3), complete = {kind = "input", entity = "relay_" .. id, input = "Trigger"}}

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

local function give(list, opts)
	local ok, why = API.RegisterCampaignMap(MAP, list, opts or {replace = true})

	assert(ok, "the test's own list is refused: " .. tostring(why))
end

local function start()
	assert(S.Start(MAP), "the test map did not start")
end

local function hookFn(event)
	local t = hook.GetTable()[event]

	return t and t[HOOK_ID]
end

-- the engine's hooks, called the way the engine calls them
local function input(name, target)
	hookFn("AcceptInput")(ent({name = target}), name, NULL, NULL, "")
end

local function state(id)
	local o = API.GetObjective(id)

	return o and o.state
end

local function listed()
	local out = {}

	for _, o in ipairs(API.GetObjectives()) do
		out[#out + 1] = o.id
	end

	table.sort(out)

	return table.concat(out, ",")
end

local function flushTimers()
	local list = timers

	timers = {}

	for _, t in ipairs(list) do
		t.fn()
	end
end

-- a case: the store in memory, the disk, the players and the timers replaced, nothing of the campaign saved; all put back in a pcall afterwards
local function scene(body)
	return function()
		saved, timers, players, mapEnts, store = {}, {}, {}, {}, {}

		local before = S.run and S.run.map
		local wasInit = S.initialized
		local sw, sec = GetConVar("gry_campaign_objectives"):GetString(), GetConVar("gry_campaign_secrets"):GetString()
		local backend = {
			get = function(map) return store[map] end,
			set = function(map, text) store[map] = text end,
			clear = function(map) store[map] = nil end,
			clearAll = function() for k in pairs(store) do store[k] = nil end end
		}

		S.Stop()
		S.Forget(MAP)
		stub(C.Store, "backend", backend)
		stub(S, "ReadShippedFile", function(map)
			S.readCalls[#S.readCalls + 1] = map

			return S.disk[map]
		end)
		S.readCalls, S.disk = {}, {}
		stub(player, "GetAll", function() return players end)
		stub(ents, "FindByClass", function(class) return class == "trigger_changelevel" and mapEnts or {} end)
		stub(ents, "FindByName", function(name)
			local out = {}

			for _, e in ipairs(mapEnts) do
				if e:GetName() == name then
					out[#out + 1] = e
				end
			end

			return out
		end)
		stub(timer, "Simple", function(delay, fn) timers[#timers + 1] = {delay = delay, fn = fn} end)
		stub(game, "GetMap", function() return MAP end)
		GetConVar("gry_campaign_objectives"):SetString("1")
		GetConVar("gry_campaign_secrets"):SetString("0")
		S.initialized = true

		local ok, err = pcall(body)

		pcall(function()
			S.Stop()
			S.Forget(MAP)
			S.readCalls, S.disk = nil, nil
		end)

		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		pcall(function()
			GetConVar("gry_campaign_objectives"):SetString(sw)
			GetConVar("gry_campaign_secrets"):SetString(sec)
			S.initialized = wasInit
			S.Stop()

			if before and before ~= MAP then
				S.Start(before) -- the game that runs the tests is on a campaign map: its objectives come back
			end
		end)

		if not ok then
			error(err, 0)
		end
	end
end

return {
	groupName = "GryMod campaign objectives (runtime)",
	beforeAll = function()
		S, C, API = GryMod.CampaignServer, GryMod.Campaign, GryMod.API
	end,
	cases = {
		{
			-- breaks if: sv_campaign.lua is not loaded, an API function or the command is missing, or a switch is not a replicated yes / no setting of the administrators' list
			name = "the API, the command and the two switches exist; the switches are administrators' settings, the secrets one off by default",
			func = function()
				for _, name in ipairs({"RegisterCampaignMap", "OverrideCampaignObjective", "ResetCampaignProgress"}) do
					expect(isfunction(API[name])).to.beTrue()
				end

				expect(API.Has("campaign")).to.beTrue()
				expect(concommand.GetTable()["gry_campaign_reset"] ~= nil).to.beTrue()

				for _, name in ipairs({"gry_campaign_objectives", "gry_campaign_secrets"}) do
					local convar = GetConVar(name)

					expect(convar ~= nil).to.beTrue()
					expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
					expect(GryMod.ServerSettings.Find(name).kind).to.equal("bool")
					expect(GryMod.ServerSettings.Validate(name, "1")).to.equal("1")
					expect(GryMod.ServerSettings.Validate(name, "2")).to.beNil()
				end

				expect(GetConVar("gry_campaign_secrets"):GetDefault()).to.equal("0")
				expect(GetConVar("gry_campaign_objectives"):GetDefault()).to.equal("1")
			end
		},
		{
			-- breaks if: the shipped file of the map is read for another map, or read when a third party replaced it, or read again at every start
			name = "the data of a map is read only for the map being played, once, and not at all when a list replaces it",
			func = scene(function()
				S.disk.gry_campaign_map_a = {objectives = {def("a1")}}
				S.disk.gry_campaign_map_b = {objectives = {def("b1")}}

				expect(S.Start("gry_campaign_map_a")).to.beTrue()
				expect(#S.readCalls).to.equal(1)
				expect(S.readCalls[1]).to.equal("gry_campaign_map_a")
				expect(listed()).to.equal("a1")

				S.Start("gry_campaign_map_a")
				expect(#S.readCalls).to.equal(1) -- read once

				-- a map with no data is not an error: nothing runs, nothing is listed
				expect(S.Start("gry_campaign_map_none")).to.beFalse()
				expect(listed()).to.equal("")

				-- a replacing list: the shipped file is not even read
				give({def("t1")}, {replace = true})
				S.Forget("gry_campaign_map_b")
				API.RegisterCampaignMap("gry_campaign_map_b", {def("t2")}, {replace = true})
				S.Start("gry_campaign_map_b")
				expect(listed()).to.equal("t2")

				for _, map in ipairs(S.readCalls) do
					expect(map ~= "gry_campaign_map_b").to.beTrue()
				end

				S.Forget("gry_campaign_map_a")
				S.Forget("gry_campaign_map_b")
				S.Forget("gry_campaign_map_none")
			end)
		},
		{
			-- breaks if: shipped data that does not pass the check is run anyway
			name = "a shipped file that is wrong is refused as a whole: nothing is listed",
			func = scene(function()
				S.disk[MAP] = {objectives = {def("ok"), {id = "bad", title = "No place and no completion"}}}
				expect(S.Start(MAP)).to.beFalse()
				expect(listed()).to.equal("")

				S.Forget(MAP)
				S.disk[MAP] = {objectives = {def("ok")}, fail_events = {{entity = "msg"}}} -- a fail event without its input
				expect(S.Start(MAP)).to.beFalse()
			end)
		},
		{
			-- breaks if: every step of a chain is listed at the start, or an exit that has an `after` is listed before its steps are done (the owner saw the far exit arrow in the radar's
			-- corner from the first second), or the main objective is the exit / a secondary one
			name = "Start lists the first step of the chain and the independent steps; the later steps and an exit that has an `after` wait; the main objective is the first primary step",
			func = scene(function()
				give({
					def("side", {primary = false}),
					def("exit", {complete = {kind = "changelevel", target = "next_map"}, after = "c"}),
					def("a"), def("b", {after = "a"}), def("c", {after = "b"})
				})
				start()

				expect(listed()).to.equal("a,side")
				expect(state("a")).to.equal("active")
				expect(API.GetObjective("a").main).to.beTrue()
				expect(API.GetObjective("exit")).to.beNil()
				expect(API.GetObjective("side").primary).to.beFalse()
				expect(API.GetObjective("a").title).to.equal("Title a")
			end)
		},
		{
			-- breaks if: the waypoints of a campaign objective are not handed to RegisterObjective (the route guidance would have nothing to follow)
			name = "the waypoints (via) of an objective are given to the objectives API",
			func = scene(function()
				give({def("a", {via = {Vector(10, 0, 0), Vector(20, 0, 0)}}), def("b")})
				start()
				expect(#API.GetObjective("a").via).to.equal(2)
				expect(API.GetObjective("a").via[2] == Vector(20, 0, 0)).to.beTrue()
				expect(API.GetObjective("b").via).to.beNil()
			end)
		},
		{
			-- breaks if: the language of the server is not asked for the texts
			name = "the texts come in the server's language when the data has them",
			func = scene(function()
				give({def("a", {title = "Reach it", description = "Go.", tr = {fr = {title = "Atteindre", description = "Allez."}}})})
				stub(S, "Language", function() return "fr" end)
				start()
				expect(API.GetObjective("a").title).to.equal("Atteindre")
				expect(API.GetObjective("a").description).to.equal("Allez.")
			end)
		},
		{
			-- breaks if: the AcceptInput hook is not installed for an input completion, is not found by input name, ignores a name that differs only by case, or finishes a step for another entity
			name = "an input completion: the right entity receiving the right input finishes the step (any case); another input or another entity does not",
			func = scene(function()
				give({def("a", {complete = {kind = "input", entity = "door_a", input = "Open"}})})
				start()

				expect(hookFn("AcceptInput") ~= nil).to.beTrue()

				input("Close", "door_a")
				input("Open", "door_b")
				input("Open", "")
				expect(state("a")).to.equal("active")

				input("open", "DOOR_A")
				expect(state("a")).to.equal("done")
			end)
		},
		{
			-- breaks if: the entity of a point_template ("name&0003") is not recognised
			name = "an entity renamed by a point_template (name&0003) finishes the step too",
			func = scene(function()
				give({def("a", {complete = {kind = "input", entity = "gordon_cop", input = "ForceSpawn"}})})
				start()
				input("ForceSpawn", "gordon_cop&0007")
				expect(state("a")).to.equal("done")
			end)
		},
		{
			-- breaks if: a later step is listened for before its predecessor is done, or is not listed when it is
			name = "a done step lists the next step of its chain, which was not listened for before; the main objective moves on",
			func = scene(function()
				give({
					def("a", {complete = {kind = "input", entity = "relay_a", input = "Trigger"}}),
					def("b", {after = "a", complete = {kind = "input", entity = "relay_b", input = "Trigger"}}),
					def("exit", {complete = {kind = "changelevel", target = "next_map"}})
				})
				start()

				input("Trigger", "relay_b") -- the second step's event, too early: nobody waits for it
				expect(state("b")).to.beNil()
				expect(state("a")).to.equal("active")

				input("Trigger", "relay_a")
				expect(state("a")).to.equal("done")
				expect(state("b")).to.equal("active")
				expect(API.GetObjective("b").main).to.beTrue()

				input("Trigger", "relay_b")
				expect(state("b")).to.equal("done")
				expect(API.GetObjective("exit").main).to.beTrue()
			end)
		},
		{
			-- breaks if: a done objective stays in the list for ever, or is taken off at once, or is taken off after the runtime was started again
			name = "a done objective stays in the list for a few seconds, then it is taken off (only if it is the same run)",
			func = scene(function()
				give({def("a"), def("b")})
				start()
				input("Trigger", "relay_a")

				expect(#timers).to.equal(1)
				expect(timers[1].delay).to.equal(S.LINGER)
				expect(state("a")).to.equal("done")

				flushTimers()
				expect(state("a")).to.beNil()
				expect(state("b")).to.equal("active")

				-- the run was restarted before the delay: the old timer touches nothing
				input("Trigger", "relay_b")
				S.Start(MAP)
				expect(listed()).to.equal("") -- both were done, and a done step is not listed again

				flushTimers()
				expect(listed()).to.equal("")
			end)
		},
		{
			-- breaks if: a hook stays installed when nothing waits for its kind, or is not installed when something does
			name = "each hook exists only while a step of its kind waits, and all of ours are gone when everything is done",
			func = scene(function()
				local events = {"AcceptInput", "WeaponEquip", "PlayerEnteredVehicle", "PlayerUse", "OnNPCKilled", "EntityRemoved", "PlayerCanPickupItem", "ShutDown"}

				for _, event in ipairs(events) do
					expect(hookFn(event) == nil).to.beTrue()
				end

				give({
					def("w", {complete = {kind = "pickup", class = "weapon_rpg"}}),
					def("v", {complete = {kind = "enter_vehicle", class = "prop_vehicle_jeep"}}),
					def("u", {complete = {kind = "use", entity = "soda"}}),
					def("k", {complete = {kind = "killed", entity = "gunship1"}}),
					def("r", {complete = {kind = "removed", entity = "crate"}}),
					def("i", {complete = {kind = "pickup", class = "item_battery"}}),
					def("x", {complete = {kind = "input", entity = "e", input = "Go"}})
				})

				start()

				for _, event in ipairs(events) do
					expect(hookFn(event) ~= nil).to.beTrue()
				end

				-- done one by one: the hook goes with its last step
				hookFn("WeaponEquip")(ent({class = "weapon_rpg"}), ply())
				expect(hookFn("WeaponEquip") == nil).to.beTrue()
				expect(hookFn("PlayerUse") ~= nil).to.beTrue()

				hookFn("PlayerEnteredVehicle")(ply(), ent({class = "prop_vehicle_jeep"}))
				hookFn("PlayerUse")(ply(), ent({name = "soda"}))
				hookFn("OnNPCKilled")(ent({name = "gunship1"}), NULL, NULL)
				hookFn("PlayerCanPickupItem")(ply(), ent({class = "item_battery"}))
				expect(hookFn("ShutDown") ~= nil).to.beTrue() -- the removal still waits
				hookFn("EntityRemoved")(ent({name = "crate"}))
				input("Go", "e")

				for _, event in ipairs(events) do
					expect(hookFn(event) == nil).to.beTrue()
				end

				-- and Stop takes them all away too
				give({def("y", {complete = {kind = "input", entity = "e", input = "Go"}})}) -- (the other ones are saved as done)
				start()
				expect(hookFn("AcceptInput") ~= nil).to.beTrue()
				S.Stop()
				expect(hookFn("AcceptInput") == nil).to.beTrue()
			end)
		},
		{
			-- breaks if: the weapon of an NPC finishes the step, or the class is not what decides
			name = "a pickup completion: a player taking the weapon of that class finishes it, an NPC or another weapon does not; an item goes through PlayerCanPickupItem",
			func = scene(function()
				give({def("w", {complete = {kind = "pickup", class = "weapon_rpg", entity = "rpg_weapon"}}), def("i", {complete = {kind = "pickup", class = "item_suit"}})})
				start()

				hookFn("WeaponEquip")(ent({class = "weapon_rpg"}), ent({class = "npc_citizen"})) -- an NPC, not a player
				hookFn("WeaponEquip")(ent({class = "weapon_smg1"}), ply())
				expect(state("w")).to.equal("active")

				hookFn("WeaponEquip")(ent({class = "weapon_rpg", name = "another_name"}), ply())
				expect(state("w")).to.equal("done")

				expect(state("i")).to.equal("active")
				hookFn("PlayerCanPickupItem")(ply(), ent({class = "item_suit"}))
				expect(state("i")).to.equal("done")
			end)
		},
		{
			-- breaks if: the vehicle is not found by its class alone, or the player's entering is not what is listened to
			name = "an enter_vehicle completion is finished by a player getting into a vehicle of that class",
			func = scene(function()
				give({def("v", {complete = {kind = "enter_vehicle", class = "prop_vehicle_jeep", entity = "jeep"}})})
				start()
				hookFn("PlayerEnteredVehicle")(ply(), ent({class = "prop_vehicle_airboat"}))
				expect(state("v")).to.equal("active")
				hookFn("PlayerEnteredVehicle")(ply(), ent({class = "prop_vehicle_jeep", name = "jeep&0002"}))
				expect(state("v")).to.equal("done")
			end)
		},
		{
			-- breaks if: the use key on an entity is not listened to, or the class and the place of an entity without a name do not decide
			name = "a use completion: the named entity, or the class at the place of an entity that has no name",
			func = scene(function()
				give({
					def("soda", {complete = {kind = "use", entity = "soda_machine_1"}}),
					def("charger", {complete = {kind = "use", class = "item_healthcharger", at = Vector(576, -7776, -74)}})
				})
				start()

				hookFn("PlayerUse")(ply(), ent({name = "soda_machine_2"}))
				hookFn("PlayerUse")(ply(), ent({class = "item_healthcharger", pos = Vector(0, 0, 0)}))
				expect(state("soda")).to.equal("active")
				expect(state("charger")).to.equal("active")

				hookFn("PlayerUse")(ply(), ent({name = "soda_machine_1"}))
				hookFn("PlayerUse")(ply(), ent({class = "item_healthcharger", pos = Vector(576, -7776, -74)}))
				expect(state("soda")).to.equal("done")
				expect(state("charger")).to.equal("done")
			end)
		},
		{
			-- breaks if: a death is not listened to, or the alternative (also) is not another way to finish
			name = "a killed completion; and a removed completion with an alternative: either one finishes the step",
			func = scene(function()
				give({
					def("k", {complete = {kind = "killed", class = "npc_helicopter"}}),
					def("g", {complete = {kind = "removed", entity = "gunship1", also = {kind = "input", entity = "achievement_gunship", input = "FireEvent"}}}),
					def("g2", {complete = {kind = "removed", entity = "gunship2", also = {kind = "input", entity = "achievement_gunship2", input = "FireEvent"}}})
				})
				start()

				hookFn("OnNPCKilled")(ent({class = "npc_combine_s"}), NULL, NULL)
				expect(state("k")).to.equal("active")
				hookFn("OnNPCKilled")(ent({class = "npc_helicopter"}), NULL, NULL)
				expect(state("k")).to.equal("done")

				hookFn("EntityRemoved")(ent({name = "gunship1"}))
				expect(state("g")).to.equal("done")

				input("FireEvent", "achievement_gunship2")
				expect(state("g2")).to.equal("done")
			end)
		},
		{
			-- breaks if: an entity that goes because the map is cleaned up, or because the level ends, finishes a "removed" step
			name = "a removal during a map cleanup or when the level ends is not an event",
			func = scene(function()
				give({def("r", {complete = {kind = "removed", entity = "crate"}}), def("r2", {complete = {kind = "removed", entity = "crate2"}})})
				start()

				hookFn("PreCleanupMap")()
				hookFn("EntityRemoved")(ent({name = "crate"}))
				expect(state("r")).to.equal("active")
				hookFn("PostCleanupMap")()
				flushTimers() -- the restart after the cleanup (below)

				hookFn("ShutDown")()
				hookFn("EntityRemoved")(ent({name = "crate2"}))
				expect(state("r2")).to.equal("active")
			end)
		},
		{
			-- breaks if: the exit is finished by anybody, anywhere, when the level ends, or not by a player standing in the exit trigger of that map
			name = "a changelevel completion: when the level ends and a living player stands in the exit trigger that leads to the target",
			func = scene(function()
				mapEnts[#mapEnts + 1] = ent({class = "trigger_changelevel", kv = {map = "d1_next"}, mins = Vector(0, 0, 0), maxs = Vector(100, 100, 100)})
				mapEnts[#mapEnts + 1] = ent({class = "trigger_changelevel", kv = {map = "d1_back"}, mins = Vector(1000, 0, 0), maxs = Vector(1100, 100, 100)})
				give({def("exit", {complete = {kind = "changelevel", target = "d1_next"}})})
				start()

				-- far away from the trigger of the target (but in the box of another exit): nothing
				players[1] = ply({pos = Vector(1050, 50, 10)})
				hookFn("ShutDown")()
				expect(state("exit")).to.equal("active")

				S.Start(MAP)
				players[1] = ply({pos = Vector(50, 50, 10)})
				hookFn("ShutDown")()
				expect(state("exit")).to.equal("done")
			end)
		},
		{
			-- breaks if: the "game over" message of the map does not fail the primary steps, fails the secondary ones, or is saved as progress
			name = "failures: a step's own fail input fails that step; the map's game over fails every primary step that waits, not the secondary ones; none is saved",
			func = scene(function()
				give({
					def("a", {fail = {kind = "input", entity = "jeep_lost", input = "ShowMessage"}}),
					def("b", {after = "a"}), def("c"),
					def("side", {primary = false})
				}, {replace = true, fail_events = {{entity = "ally_dead", input = "ShowMessage"}}})
				start()

				input("ShowMessage", "jeep_lost")
				expect(state("a")).to.equal("failed")
				expect(state("c")).to.equal("active")

				input("ShowMessage", "ally_dead")
				expect(state("c")).to.equal("failed")
				expect(state("side")).to.equal("active")

				-- nothing failed was saved: the map started again waits for them all
				S.Start(MAP)
				expect(state("a")).to.equal("active")
				expect(state("c")).to.equal("active")

				-- nobody listens for the "game over" when no primary step waits (only a secondary one is left)
				give({def("only_side", {primary = false, complete = {kind = "pickup", class = "weapon_crossbow"}})}, {replace = true, fail_events = {{entity = "ally_dead", input = "ShowMessage"}}})
				start()
				expect(hookFn("WeaponEquip") ~= nil).to.beTrue()
				expect(hookFn("AcceptInput") == nil).to.beTrue()
			end)
		},
		{
			-- breaks if: the done steps are not saved, are saved but not read back, or come back listed
			name = "the progress is saved when a step is done and read back when the map starts again: the done step is not listed, the next one is",
			func = scene(function()
				give({def("a"), def("b", {after = "a"}), def("c", {after = "b"})})
				start()
				input("Trigger", "relay_a")
				expect(store[MAP] ~= nil).to.beTrue()
				expect(string.find(store[MAP], "\"a\"", 1, true) ~= nil).to.beTrue()

				-- the quickload: the Lua state is new, the store is what is left
				S.Stop()
				start()
				expect(listed()).to.equal("b")
				expect(API.GetObjective("b").main).to.beTrue()

				-- the player began again: the reset forgets it
				API.ResetCampaignProgress(MAP)
				expect(listed()).to.equal("a")
			end)
		},
		{
			-- breaks if: the world's proof is not asked (a weapon the player already has is listed as to find), or is not kept
			name = "a weapon the player already has and a vehicle he is already in are done when the map starts, and the steps before them; what the world proves is kept",
			func = scene(function()
				players[1] = ply({weapons = {weapon_rpg = true}, vehicle = ent({class = "prop_vehicle_jeep"})})
				give({
					def("first"), def("rpg", {after = "first", complete = {kind = "pickup", class = "weapon_rpg"}}),
					def("buggy", {complete = {kind = "enter_vehicle", class = "prop_vehicle_jeep"}}),
					def("other", {complete = {kind = "pickup", class = "weapon_crossbow"}})
				})
				start()

				expect(listed()).to.equal("other") -- "first" is implied by "rpg"; "buggy" is proved
				expect(string.find(store[MAP], "buggy", 1, true) ~= nil).to.beTrue()
				expect(string.find(store[MAP], "first", 1, true) ~= nil).to.beTrue()

				-- the world no longer proves it (the weapon was lost): what was saved stays
				players[1] = ply()
				S.Start(MAP)
				expect(listed()).to.equal("other")
			end)
		},
		{
			-- breaks if: a secret is listed one by one, or the counter exists while the setting is off, or a hook waits for the secrets while it is off
			name = "secrets: not mentioned by default (nothing is listened for); with the setting on, one counter that counts, is not on the radar, and is done at the last one",
			func = scene(function()
				give({
					def("a"),
					def("s1", {secret = true, complete = {kind = "input", entity = "ach_1", input = "FireEvent"}}),
					def("s2", {secret = true, complete = {kind = "input", entity = "ach_2", input = "FireEvent"}})
				})
				start()
				expect(listed()).to.equal("a")
				input("FireEvent", "ach_1")
				expect(string.find(store[MAP] or "", "s1", 1, true) == nil).to.beTrue()

				-- switched on while the map runs
				GetConVar("gry_campaign_secrets"):SetString("1")
				expect(listed()).to.equal("a," .. C.SecretsId)

				local counter = API.GetObjective(C.SecretsId)

				expect(counter.title).to.equal("Secrets 0/2")
				expect(counter.primary).to.beFalse()
				expect(counter.radar).to.beFalse()
				expect(counter.marker).to.beFalse()

				input("FireEvent", "ach_1")
				expect(API.GetObjective(C.SecretsId).title).to.equal("Secrets 1/2")
				input("FireEvent", "ach_1") -- twice: counted once
				expect(API.GetObjective(C.SecretsId).title).to.equal("Secrets 1/2")

				-- saved, and back after a restart
				S.Start(MAP)
				expect(API.GetObjective(C.SecretsId).title).to.equal("Secrets 1/2")

				input("FireEvent", "ach_2")
				expect(state(C.SecretsId)).to.equal("done")
				expect(#timers > 0).to.beTrue()
				flushTimers()
				expect(API.GetObjective(C.SecretsId)).to.beNil()

				-- switched off: no counter, and nothing waits for the secrets
				S.Start(MAP)
				GetConVar("gry_campaign_secrets"):SetString("0")
				expect(listed()).to.equal("a")
			end)
		},
		{
			-- breaks if: a map without secrets gets a counter "Secrets 0/0"
			name = "no counter on a map that has no secret, whatever the setting",
			func = scene(function()
				GetConVar("gry_campaign_secrets"):SetString("1")
				give({def("a")})
				start()
				expect(listed()).to.equal("a")
			end)
		},
		{
			-- breaks if: a third party's list replaces the shipped one when it should add to it, or does not replace an objective of the same id, or does not remove with false
			name = "a third party adds to the shipped list, replaces an objective by id, or removes one (the chain is mended)",
			func = scene(function()
				S.disk[MAP] = {objectives = {def("a"), def("b", {after = "a"}), def("c", {after = "b"})}}

				expect(API.RegisterCampaignMap(MAP, {def("z")}, {})).to.beTrue()
				expect(API.OverrideCampaignObjective(MAP, "a", def("ignored", {title = "My first step", complete = {kind = "input", entity = "relay_a", input = "Trigger"}}))).to.beTrue()
				start()
				expect(listed()).to.equal("a,z")
				expect(API.GetObjective("a").title).to.equal("My first step") -- the id of the call wins over the id in the table

				expect(API.OverrideCampaignObjective(MAP, "b", false)).to.beTrue() -- start again: the map runs now, the API reloads it
				input("Trigger", "relay_a")
				expect(state("a")).to.equal("done")

				-- the chain was mended: c follows a now, and is listed
				expect(listed()).to.equal("a,c,z")
			end)
		},
		{
			-- breaks if: a bad list or a bad override is stored, or answered with true, or raises
			name = "a bad list, a bad override or a bad map name is refused with false and a reason, and nothing is stored",
			func = scene(function()
				local ok, why = API.RegisterCampaignMap("bad map!", {def("a")})

				expect(ok).to.beFalse()
				expect(string.find(why, "map", 1, true) ~= nil).to.beTrue()
				expect(API.RegisterCampaignMap(5, {def("a")})).to.beFalse()
				expect(API.RegisterCampaignMap(MAP, 5)).to.beFalse()
				expect(API.RegisterCampaignMap(MAP, {def("a"), {id = "b", title = "x"}})).to.beFalse()
				expect(API.RegisterCampaignMap(MAP, {def("a")}, 5)).to.beFalse()
				expect(API.RegisterCampaignMap(MAP, {def("a")}, {fail_events = {{entity = "x"}}})).to.beFalse()
				expect(API.OverrideCampaignObjective(MAP, "", def("a"))).to.beFalse()
				expect(API.OverrideCampaignObjective(MAP, "a", 5)).to.beFalse()
				expect(API.OverrideCampaignObjective(MAP, "a", {title = "No place"})).to.beFalse()

				expect(S.Start(MAP)).to.beFalse() -- nothing was stored for the map
			end)
		},
		{
			-- breaks if: a listener that raises breaks the hook, or the error is not caught
			name = "an error while the hooks check an entity breaks nothing: the step stays as it was",
			func = scene(function()
				give({def("a", {complete = {kind = "input", entity = "door", input = "Open"}})})
				start()

				local broken = ent({name = "door"})

				broken.GetName = function() error("boom") end
				expect(pcall(hookFn("AcceptInput"), broken, "Open")).to.beTrue()
				expect(state("a")).to.equal("active")
			end)
		},
		{
			-- breaks if: the objectives stay when the setting goes off, or do not come back when it goes on
			name = "the switch: off takes the objectives and the hooks away, on starts the map again; with it off nothing starts",
			func = scene(function()
				give({def("a")})
				start()
				expect(listed()).to.equal("a")

				GetConVar("gry_campaign_objectives"):SetString("0")
				expect(listed()).to.equal("")
				expect(hookFn("AcceptInput") == nil).to.beTrue()
				expect(S.Start(MAP)).to.beFalse()

				GetConVar("gry_campaign_objectives"):SetString("1")
				expect(listed()).to.equal("a")
				expect(hookFn("AcceptInput") ~= nil).to.beTrue()
			end)
		},
		{
			-- breaks if: the cleanup of the map (which clears every objective) is not followed by a new start
			name = "after a map cleanup the objectives are started again, once every hook of the event has run",
			func = scene(function()
				give({def("a")})
				start()
				API.ClearObjectives() -- what sv_objectives.lua does at PostCleanupMap
				expect(listed()).to.equal("")

				hookFn("PostCleanupMap")()
				expect(listed()).to.equal("") -- not yet: after the other hooks
				flushTimers()
				expect(listed()).to.equal("a")
			end)
		},
		{
			-- breaks if: a player who is not an administrator can reset, or the console cannot, or the reset takes another map
			name = "gry_campaign_reset: administrators and the console only; the running map, or all with `all`",
			func = scene(function()
				give({def("a"), def("b", {after = "a"})})
				start()
				input("Trigger", "relay_a")
				store.other_map = "{\"done\":[\"x\"],\"secrets\":[]}"

				local command = concommand.GetTable()["gry_campaign_reset"]

				command(ply({admin = false}), "gry_campaign_reset", {})
				expect(store[MAP] ~= nil).to.beTrue()

				command(ply({admin = true}), "gry_campaign_reset", {})
				expect(store[MAP] == nil or string.find(store[MAP], "\"a\"", 1, true) == nil).to.beTrue()
				expect(store.other_map ~= nil).to.beTrue()
				expect(listed()).to.equal("a")

				command(NULL, "gry_campaign_reset", {"all"})
				expect(store.other_map).to.beNil()
			end)
		}
	}
}
