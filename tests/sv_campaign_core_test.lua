-- Tests of the PURE part of the campaign objectives (lua/grymod/server/sv_campaign_core.lua), GLuaTest format, server realm: the check of a map's list (what a
-- developer gives to GryMod.API.RegisterCampaignMap), the match of a map entity against a completion (the "name&0003" name of a point_template entity, a class
-- and a place for an entity without a name), the text lookup (English default, a table of translations), the chain (`after`: which step is shown, which one is the
-- main one), the merge of the saved progress with what the world proves, the merge of a third party's list (replace by id, remove with the chain mended) and the
-- store of the progress (a map's finished ids). Nothing here touches the game's world: the entities are tables that answer like one, and the store is tried
-- on an in-memory backend (the real sql backend gets one case, on a map name that no map has, cleaned in a pcall).
-- Each case names the production change whose absence makes it fail.

local C

-- a table that answers like a map entity
local function ent(t)
	return {
		IsValid = function() return true end,
		GetClass = function() return t.class or "" end,
		GetName = function() return t.name or "" end,
		GetPos = function() return t.pos or Vector(0, 0, 0) end,
		MapCreationID = function() return t.mapid or 0 end
	}
end

-- a clean objective, made by the checker itself (so the cases test the real shape)
local function obj(id, extra)
	local def = {
		id = id, title = "Title " .. id, pos = Vector(1, 2, 3), primary = true,
		complete = {kind = "input", entity = "relay_" .. id, input = "Trigger"}
	}

	for k, v in pairs(extra or {}) do
		def[k] = v
	end

	local clean, why = C.CheckObjective(def)

	assert(clean, "the test's own objective is refused: " .. tostring(why))

	return clean
end

local function ids(list)
	local out = {}

	for i, d in ipairs(list) do
		out[i] = d.id
	end

	return table.concat(out, ",")
end

local function set(...)
	local s = {}

	for _, id in ipairs({...}) do
		s[id] = true
	end

	return s
end

local function sorted(s)
	local out = {}

	for id in pairs(s) do
		out[#out + 1] = id
	end

	table.sort(out)

	return table.concat(out, ",")
end

-- an in-memory backend for the store; `rows` is what the "disk" holds
local function memoryBackend()
	local rows = {}

	return {
		rows = rows,
		get = function(map) return rows[map] end,
		set = function(map, text) rows[map] = text end,
		clear = function(map) rows[map] = nil end,
		clearAll = function() for k in pairs(rows) do rows[k] = nil end end
	}
end

return {
	groupName = "GryMod campaign objectives (pure part)",
	beforeAll = function()
		C = GryMod.Campaign
	end,
	cases = {
		{
			-- breaks if: sv_campaign_core.lua is not loaded, or one of its tables is missing
			name = "the pure part exists with its seven completion kinds",
			func = function()
				expect(C ~= nil).to.beTrue()

				for _, kind in ipairs({"input", "pickup", "enter_vehicle", "use", "changelevel", "removed", "killed"}) do
					expect(C.Kinds[kind]).to.beTrue()
				end

				-- what may fail an objective: an input, a death, a removal; never a pickup or a level change
				expect(C.FailKinds.input).to.beTrue()
				expect(C.FailKinds.killed).to.beTrue()
				expect(C.FailKinds.pickup).to.beNil()
			end
		},
		{
			-- breaks if: CheckCompletion does not ask the fields each kind needs (an input without its input name, a pickup without a class...)
			name = "a completion is refused with a reason when what its kind needs is missing",
			func = function()
				local good = {
					{kind = "input", entity = "door_a", input = "Open"},
					{kind = "pickup", class = "weapon_rpg"},
					{kind = "enter_vehicle", class = "prop_vehicle_jeep"},
					{kind = "enter_vehicle", entity = "jeep"},
					{kind = "use", entity = "soda_machine_1"},
					{kind = "use", mapid = 1500},
					{kind = "use", class = "item_healthcharger", at = Vector(576, -7776, -74)},
					{kind = "changelevel", target = "d1_canals_01a"},
					{kind = "removed", entity = "gunship1"},
					{kind = "killed", class = "npc_helicopter"}
				}

				for i, c in ipairs(good) do
					local clean, why = C.CheckCompletion(c)

					expect(clean ~= false).to.beTrue()
					expect(clean.kind).to.equal(c.kind)
					expect(why).to.beNil()
				end

				local bad = {
					{{kind = "input", entity = "door_a"}, "input"},
					{{kind = "input", input = "Open"}, "entity"},
					{{kind = "pickup"}, "class"},
					{{kind = "enter_vehicle"}, "class"},
					{{kind = "use"}, "entity"},
					{{kind = "use", class = "item_healthcharger"}, "entity"}, -- a class alone points at every charger of the map
					{{kind = "changelevel"}, "target"},
					{{kind = "removed"}, "entity"},
					{{kind = "teleport", entity = "x"}, "kind"},
					{{entity = "x"}, "kind"},
					{{kind = "input", entity = 5, input = "Open"}, "entity"},
					{{kind = "use", class = "item_healthcharger", at = 5}, "at"},
					{{kind = "use", mapid = -1}, "mapid"},
					{5, "table"}
				}

				for _, row in ipairs(bad) do
					local clean, why = C.CheckCompletion(row[1])

					expect(clean).to.beFalse()
					expect(isstring(why)).to.beTrue()
					expect(string.find(why, row[2], 1, true) ~= nil).to.beTrue()
				end
			end
		},
		{
			-- breaks if: `also` is not allowed once, or is allowed inside `also`
			name = "a completion may name one alternative (also), not a chain of them",
			func = function()
				local clean = C.CheckCompletion({kind = "removed", entity = "gunship1", also = {kind = "input", entity = "achievement_gunship", input = "FireEvent"}})

				expect(clean ~= false).to.beTrue()
				expect(clean.also.kind).to.equal("input")

				local nested = C.CheckCompletion({kind = "removed", entity = "g", also = {kind = "removed", entity = "h", also = {kind = "killed", entity = "i"}}})

				expect(nested).to.beFalse()
			end
		},
		{
			-- breaks if: the clean copy keeps the developer's Vector (a later change of it would change the objective)
			name = "CheckObjective gives a clean copy with the defaults: primary, not secret, the exit flag of a level change, the chain as a list",
			func = function()
				local pos = Vector(10, 20, 30)
				local def = {id = "a.b", title = "Reach it", pos = pos, complete = {kind = "changelevel", target = "d1_next"}, proof = "a comment", junk = 5, after = "a.prev"}
				local clean, why = C.CheckObjective(def)

				expect(why).to.beNil()
				expect(clean.id).to.equal("a.b")
				expect(clean.description).to.equal("")
				expect(clean.primary).to.beTrue()
				expect(clean.secret).to.beFalse()
				expect(clean.exit).to.beTrue()
				expect(#clean.after).to.equal(1)
				expect(clean.after[1]).to.equal("a.prev")
				expect(clean.junk).to.beNil()
				expect(clean.proof).to.beNil()

				pos.x = 99
				expect(clean.pos.x).to.equal(10)

				-- a story step that is not a level change is not an exit, unless it says so
				expect(obj("s1").exit).to.beFalse()
				expect(obj("s2", {exit = true}).exit).to.beTrue()
				expect(obj("s3", {secret = true}).secret).to.beTrue()
				expect(obj("s4", {after = {"x", "y"}}).after[2]).to.equal("y")
			end
		},
		{
			-- breaks if: a field is not checked (a title that is a number, a position that is junk, a chain that is not ids)
			name = "CheckObjective refuses a bad objective with a reason that names the field",
			func = function()
				local complete = {kind = "input", entity = "e", input = "Open"}
				local rows = {
					{nil, "id"},
					{{id = "", title = "T", pos = Vector(), complete = complete}, "id"},
					{{id = string.rep("x", 65), title = "T", pos = Vector(), complete = complete}, "id"},
					{{id = "a", pos = Vector(), complete = complete}, "title"},
					{{id = "a", title = "", pos = Vector(), complete = complete}, "title"},
					{{id = "a", title = string.rep("t", 129), pos = Vector(), complete = complete}, "title"},
					{{id = "a", title = "T", description = 5, pos = Vector(), complete = complete}, "description"},
					{{id = "a", title = "T", primary = "yes", pos = Vector(), complete = complete}, "primary"},
					{{id = "a", title = "T", complete = complete}, "pos"},
					{{id = "a", title = "T", pos = 5, complete = complete}, "pos"},
					{{id = "a", title = "T", pos = Vector(math.huge, 0, 0), complete = complete}, "pos"},
					{{id = "a", title = "T", follow = 5, complete = complete}, "follow"},
					{{id = "a", title = "T", pos = Vector()}, "complete"},
					{{id = "a", title = "T", pos = Vector(), complete = {kind = "nope"}}, "complete"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, after = 5}, "after"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, after = {5}}, "after"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, fail = {kind = "pickup", class = "weapon_rpg"}}, "fail"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, tr = 5}, "tr"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, tr = {fr = {title = 5}}}, "tr"},
					{{id = "a", title = "T", pos = Vector(), complete = complete, secret = "no"}, "secret"}
				}

				for i, row in ipairs(rows) do
					local clean, why = C.CheckObjective(row[1])

					expect(clean).to.beFalse()
					expect(isstring(why)).to.beTrue()
					expect(string.find(why, row[2], 1, true) ~= nil).to.beTrue()
				end

				-- a position OR the name of an entity to follow
				expect(C.CheckObjective({id = "a", title = "T", follow = "the_door", complete = complete}) ~= false).to.beTrue()
			end
		},
		{
			-- breaks if: CheckList lets a second objective with the same id through (the last one would silently win)
			name = "CheckList refuses a list with a bad objective or twice the same id, and says which",
			func = function()
				local list = {
					{id = "a", title = "A", pos = Vector(), complete = {kind = "changelevel", target = "m2"}},
					{id = "b", title = "B", pos = Vector(), complete = {kind = "changelevel", target = "m3"}}
				}
				local clean = C.CheckList(list)

				expect(#clean).to.equal(2)
				expect(clean[2].id).to.equal("b")

				local dup, why = C.CheckList({list[1], list[1]})

				expect(dup).to.beFalse()
				expect(string.find(why, "twice", 1, true) ~= nil).to.beTrue()

				local bad, why2 = C.CheckList({list[1], {id = "c", title = "C"}})

				expect(bad).to.beFalse()
				expect(string.find(why2, "#2", 1, true) ~= nil).to.beTrue()
				expect(string.find(why2, "\"c\"", 1, true) ~= nil).to.beTrue()
				expect(C.CheckList(5)).to.beFalse()
			end
		},
		{
			-- breaks if: Resolve keeps a step whose predecessor does not exist or that is part of a loop (it would never be shown)
			name = "Resolve drops the objectives whose chain cannot start (unknown predecessor, loop) and tells why",
			func = function()
				local list = {obj("a"), obj("b", {after = "a"}), obj("c", {after = "ghost"}), obj("d", {after = "e"}), obj("e", {after = "d"}), obj("f", {after = "c"})}
				local out, problems = C.Resolve(list)

				expect(ids(out)).to.equal("a,b")
				expect(#problems).to.equal(4)
				expect(string.find(problems[1], "ghost", 1, true) ~= nil).to.beTrue()
				expect(string.find(problems[1], "c", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			-- breaks if: NameMatches compares case-sensitively, or does not know the name a point_template gives ("name&0003"), or accepts any name that starts the same
			name = "NameMatches: same name in any case, the point_template suffix &digits, and nothing else",
			func = function()
				expect(C.NameMatches("jeep", "jeep")).to.beTrue()
				expect(C.NameMatches("Jeep", "jeep")).to.beTrue()
				expect(C.NameMatches("jeep&0003", "jeep")).to.beTrue()
				expect(C.NameMatches("JEEP&12", "jeep")).to.beTrue()
				expect(C.NameMatches("jeep&", "jeep")).to.beFalse()
				expect(C.NameMatches("jeep&abc", "jeep")).to.beFalse()
				expect(C.NameMatches("jeep2", "jeep")).to.beFalse()
				expect(C.NameMatches("my_jeep", "jeep")).to.beFalse()
				expect(C.NameMatches("", "jeep")).to.beFalse()
				expect(C.NameMatches(nil, "jeep")).to.beFalse()
				expect(C.NameMatches("jeep", nil)).to.beFalse()
			end
		},
		{
			-- breaks if: Matches ignores a criterion (a name, a class, a map id, a place), or says yes to a completion that names nothing
			name = "Matches: every criterion the completion names must hold; a vehicle or a weapon is found by its class alone when the class is given",
			func = function()
				local function m(c, e) return C.Matches(C.CheckCompletion(c), ent(e)) end

				expect(m({kind = "use", entity = "soda_machine_1"}, {name = "soda_machine_1"})).to.beTrue()
				expect(m({kind = "use", entity = "soda_machine_1"}, {name = "soda_machine_2"})).to.beFalse()
				expect(m({kind = "use", mapid = 1500}, {mapid = 1500})).to.beTrue()
				expect(m({kind = "use", mapid = 1500}, {mapid = 1501})).to.beFalse()
				expect(m({kind = "killed", class = "npc_helicopter"}, {class = "npc_helicopter"})).to.beTrue()
				expect(m({kind = "killed", class = "npc_helicopter"}, {class = "npc_combinegunship"})).to.beFalse()
				expect(m({kind = "removed", entity = "gunship1", class = "npc_combinegunship"}, {name = "gunship1", class = "npc_helicopter"})).to.beFalse()

				-- an entity without a name: its class and its place (within 8 units unless the completion says another radius)
				local charger = {kind = "use", class = "item_healthcharger", at = Vector(576, -7776, -74)}

				expect(m(charger, {class = "item_healthcharger", pos = Vector(580, -7776, -74)})).to.beTrue()
				expect(m(charger, {class = "item_healthcharger", pos = Vector(600, -7776, -74)})).to.beFalse()
				expect(m(charger, {class = "item_suitcharger", pos = Vector(576, -7776, -74)})).to.beFalse()
				expect(m({kind = "use", class = "item_healthcharger", at = Vector(576, -7776, -74), radius = 64}, {class = "item_healthcharger", pos = Vector(600, -7776, -74)})).to.beTrue()

				-- the weapon of a pickup may be named in the data only to place the marker: the class decides
				expect(m({kind = "pickup", class = "weapon_rpg", entity = "rpg_weapon"}, {class = "weapon_rpg", name = "another_name"})).to.beTrue()
				expect(m({kind = "enter_vehicle", class = "prop_vehicle_jeep", entity = "jeep"}, {class = "prop_vehicle_jeep", name = ""})).to.beTrue()
				expect(m({kind = "pickup", class = "weapon_rpg"}, {class = "weapon_smg1"})).to.beFalse()

				-- without a class, the vehicle is found by its name (with the template suffix)
				expect(m({kind = "enter_vehicle", entity = "jeep"}, {name = "jeep&0004"})).to.beTrue()
				expect(m({kind = "enter_vehicle", entity = "jeep"}, {name = "boat"})).to.beFalse()
			end
		},
		{
			-- breaks if: Text always answers the English text, or answers an empty string when the translation is empty
			name = "Text gives the player's language when the data has it, the English text otherwise",
			func = function()
				local def = {title = "Reach the exit", description = "Leave.", tr = {fr = {title = "Atteindre la sortie", description = ""}}}

				expect(C.Text(def, "title", "fr")).to.equal("Atteindre la sortie")
				expect(C.Text(def, "title", "en")).to.equal("Reach the exit")
				expect(C.Text(def, "title", "de")).to.equal("Reach the exit")
				expect(C.Text(def, "title", nil)).to.equal("Reach the exit")
				expect(C.Text(def, "description", "fr")).to.equal("Leave.")
				expect(C.Text({title = "T"}, "title", "fr")).to.equal("T")

				-- the texts of the system itself
				expect(C.String("secrets_title", "en")).to.equal("Secrets %d/%d")
				expect(C.String("secrets_title", "xx")).to.equal("Secrets %d/%d")
			end
		},
		{
			-- breaks if: Revealed shows a step whose predecessor is not done, hides the exit until the last step, or lists a finished step
			name = "Revealed: a step is listed when all its predecessors are done; the exit is always listed; a finished step is not",
			func = function()
				local list = {
					obj("a"), obj("b", {after = "a"}), obj("c", {after = "b"}),
					obj("exit", {after = "c", complete = {kind = "changelevel", target = "next"}}),
					obj("side", {primary = false}), obj("hidden", {secret = true})
				}

				expect(sorted(C.Revealed(list, set()))).to.equal("a,exit,side")
				expect(sorted(C.Revealed(list, set("a")))).to.equal("b,exit,side")
				expect(sorted(C.Revealed(list, set("a", "b")))).to.equal("c,exit,side")
				expect(sorted(C.Revealed(list, set("a", "b", "c", "side")))).to.equal("exit")
				expect(sorted(C.Revealed(list, set("a", "b", "c", "side", "exit")))).to.equal("")

				-- two predecessors: both must be done
				local two = {obj("p"), obj("q"), obj("r", {after = {"p", "q"}})}

				expect(sorted(C.Revealed(two, set("p")))).to.equal("q")
				expect(sorted(C.Revealed(two, set("p", "q")))).to.equal("r")
			end
		},
		{
			-- breaks if: CloseDone does not imply the earlier steps of a done step (a map reloaded in the middle of a chain would list steps already passed)
			name = "CloseDone: a step that is done means all the steps before it are done",
			func = function()
				local list = {obj("a"), obj("b", {after = "a"}), obj("c", {after = "b"}), obj("x"), obj("y", {after = {"a", "x"}})}
				local done = C.CloseDone(list, set("c"))

				expect(sorted(done)).to.equal("a,b,c")
				expect(sorted(C.CloseDone(list, set("y")))).to.equal("a,x,y")

				-- a copy: the argument is left alone
				local arg = set("c")

				C.CloseDone(list, arg)
				expect(sorted(arg)).to.equal("c")
			end
		},
		{
			-- breaks if: PickMain lets the exit or a secondary objective be the main one while a primary step is waiting, or answers an objective that is done
			name = "PickMain: the first primary step that is listed and not done, the exit only when nothing else is left, nil when all is done",
			func = function()
				local list = {
					obj("side", {primary = false}), obj("exit", {complete = {kind = "changelevel", target = "n"}}),
					obj("a"), obj("b", {after = "a"}), obj("hidden", {secret = true})
				}

				expect(C.PickMain(list, set(), set())).to.equal("a")
				expect(C.PickMain(list, set("a"), set())).to.equal("b")
				expect(C.PickMain(list, set("a"), set("b"))).to.equal("exit")
				expect(C.PickMain(list, set("a", "b"), set())).to.equal("exit")
				expect(C.PickMain(list, set("a", "b", "exit"), set())).to.beNil()
				expect(C.PickMain({obj("only", {primary = false})}, set(), set())).to.beNil()
			end
		},
		{
			-- breaks if: MergeProgress forgets the world's proof, forgets the saved progress, keeps an id the list does not have, or undoes what is saved when the world says nothing
			name = "MergeProgress: saved or proved done, the earlier steps implied, nothing invented, a proof that says no does not undo the save",
			func = function()
				local list = {obj("a"), obj("b", {after = "a"}), obj("c", {after = "b"}), obj("w"), obj("s", {secret = true})}
				local stored = {done = set("a", "old.removed"), secrets = {}}

				expect(sorted(C.MergeProgress(list, stored, {}))).to.equal("a")
				expect(sorted(C.MergeProgress(list, stored, {w = true}))).to.equal("a,w")
				expect(sorted(C.MergeProgress(list, stored, {w = false, a = false}))).to.equal("a")
				expect(sorted(C.MergeProgress(list, {done = {}, secrets = {}}, {c = true}))).to.equal("a,b,c")
				expect(sorted(C.MergeProgress(list, nil, nil))).to.equal("")

				-- a secret is counted apart, never as a step
				expect(sorted(C.MergeProgress(list, {done = set("s"), secrets = {}}, {}))).to.equal("")
			end
		},
		{
			-- breaks if: SecretsFound counts an id the map no longer has, or counts a secret twice
			name = "SecretsFound: how many of the map's secrets are found, and how many there are",
			func = function()
				local list = {obj("a"), obj("s1", {secret = true}), obj("s2", {secret = true}), obj("s3", {secret = true})}
				local found, total = C.SecretsFound(list, {done = {}, secrets = set("s1", "s3", "gone")})

				expect(found).to.equal(2)
				expect(total).to.equal(3)

				found, total = C.SecretsFound(list, nil)
				expect(found).to.equal(0)
				expect(total).to.equal(3)
			end
		},
		{
			-- breaks if: MergeLists puts a replaced objective at the end (its place in the chain and in the list is lost), or does not add a new one
			name = "MergeLists: an objective of the same id is replaced where it stood, a new one is added at the end",
			func = function()
				local base = {obj("a"), obj("b", {after = "a"}), obj("c", {after = "b"})}
				local merged = C.MergeLists(base, {obj("b", {title = "Replaced"}), obj("z")})

				expect(ids(merged)).to.equal("a,b,c,z")
				expect(merged[2].title).to.equal("Replaced")
				expect(base[2].title).to.equal("Title b")
				expect(ids(C.MergeLists(base, {}))).to.equal("a,b,c")
			end
		},
		{
			-- breaks if: RemoveId leaves the steps after the removed one waiting for it for ever, or drops them
			name = "RemoveId: the objective goes and the steps that came after it follow its predecessors (the chain is mended)",
			func = function()
				local base = {obj("a"), obj("b", {after = "a"}), obj("c", {after = "b"}), obj("d", {after = {"b", "a"}})}
				local out = C.RemoveId(base, "b")

				expect(ids(out)).to.equal("a,c,d")
				expect(#out[2].after).to.equal(1)
				expect(out[2].after[1]).to.equal("a")
				expect(#out[3].after).to.equal(1) -- "a" is not there twice
				expect(out[3].after[1]).to.equal("a")
				expect(#base[3].after).to.equal(1)
				expect(base[3].after[1]).to.equal("b") -- the argument is left alone
				expect(ids(C.RemoveId(base, "nope"))).to.equal("a,b,c,d")

				-- the first step removed: the next one becomes a first step
				local first = C.RemoveId(base, "a")

				expect(#first[1].after).to.equal(0)
			end
		},
		{
			-- breaks if: NearBox answers with the box alone (a player at the edge is out) or ignores the padding
			name = "NearBox: a point in a box grown by a margin",
			func = function()
				local mins, maxs = Vector(0, 0, 0), Vector(100, 100, 100)

				expect(C.NearBox(Vector(50, 50, 50), mins, maxs, 0)).to.beTrue()
				expect(C.NearBox(Vector(110, 50, 50), mins, maxs, 0)).to.beFalse()
				expect(C.NearBox(Vector(110, 50, 50), mins, maxs, 16)).to.beTrue()
				expect(C.NearBox(Vector(50, 50, -20), mins, maxs, 16)).to.beFalse()
				expect(C.NearBox(Vector(-16, -16, -16), mins, maxs, 16)).to.beTrue()
			end
		},
		{
			-- breaks if: Save/Load do not round-trip, the load of a corrupt row is not an empty progress, or a Reset reaches another map
			name = "the store: a map's progress is saved and loaded, a corrupt row is an empty progress, a reset takes one map or all of them",
			func = function()
				local Store = C.Store
				local real = Store.backend

				local backend = memoryBackend()

				Store.backend = backend

				local ok, err = pcall(function()
					expect(sorted(Store.Load("m1").done)).to.equal("")

					Store.Save("m1", {done = set("a", "b"), secrets = set("s1")})
					Store.Save("m2", {done = set("z"), secrets = {}})

					local p = Store.Load("m1")

					expect(sorted(p.done)).to.equal("a,b")
					expect(sorted(p.secrets)).to.equal("s1")
					expect(sorted(Store.Load("m2").done)).to.equal("z")

					backend.rows.m1 = "{{{ not json"
					expect(sorted(Store.Load("m1").done)).to.equal("")
					backend.rows.m1 = "[1, 2]"
					expect(sorted(Store.Load("m1").done)).to.equal("")
					backend.rows.m1 = nil

					Store.Save("m1", {done = set("a"), secrets = {}})
					Store.Reset("m1")
					expect(sorted(Store.Load("m1").done)).to.equal("")
					expect(sorted(Store.Load("m2").done)).to.equal("z")

					Store.Reset(nil)
					expect(sorted(Store.Load("m2").done)).to.equal("")
				end)

				Store.backend = real

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- breaks if: the default backend does not write to the game's own database, or writes the same map twice
			name = "the store's default backend keeps a map's progress in the server's sql database",
			func = function()
				local Store = C.Store
				local map = "gry_campaign_test_map_do_not_use"

				local ok, err = pcall(function()
					Store.Reset(map)
					expect(sorted(Store.Load(map).done)).to.equal("")
					Store.Save(map, {done = set("x1", "x2"), secrets = set("s")})
					Store.Save(map, {done = set("x1", "x2", "x3"), secrets = set("s")})
					expect(sorted(Store.Load(map).done)).to.equal("x1,x2,x3")
					expect(sorted(Store.Load(map).secrets)).to.equal("s")
				end)

				pcall(Store.Reset, map)

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
