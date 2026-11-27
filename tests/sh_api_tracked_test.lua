-- Tests of the registry of tracked entities of the extension API (lua/grymod/sh_api_tracked.lua), GLuaTest format, runs in the
-- server AND in the client realm: RegisterTracked / UnregisterTracked / GetTracked, the validation of a definition, the matching
-- (class, base, match function, in that order of cost), the cache by class and the safe call of the match function.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, part 5.

local API
local realMsgN
local lines
local realIsBasedOn

local KEYS = {"t_trk_a", "t_trk_b", "t_trk_c", "t_trk_d"}

-- an entity of the tests: a table that answers like one
local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

return {
	groupName = "GryMod extension API: tracked entity registry (shared)",
	beforeEach = function()
		API = GryMod.API
		lines = {}
		realMsgN = MsgN
		MsgN = function(...)
			lines[#lines + 1] = table.concat({...}, "")
		end
		realIsBasedOn = scripted_ents.IsBasedOn
	end,
	afterEach = function()
		MsgN = realMsgN
		scripted_ents.IsBasedOn = realIsBasedOn

		for _, key in ipairs(KEYS) do
			if API.UnregisterTracked then
				API.UnregisterTracked(key)
			end

			API.SafeCallReset("tracked:" .. key .. "/match")
		end
	end,
	cases = {
		{
			name = "Has tells that the tracked entity registry exists",
			func = function()
				expect(API.Has("tracked")).to.beTrue()
				expect(isfunction(API.RegisterTracked)).to.beTrue()
				expect(isfunction(API.UnregisterTracked)).to.beTrue()
				expect(isfunction(API.GetTracked)).to.beTrue()
			end
		},
		{
			name = "RegisterTracked by class: GetTracked gives the entry of an entity of that class, nothing for another class; UnregisterTracked removes it",
			func = function()
				expect(API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "always"})).to.beTrue()

				local found = API.GetTracked(ent("t_npc_one"))
				expect(found).toNot.beNil()
				expect(found.radar).to.equal("always")
				expect(API.GetTracked(ent("t_npc_two"))).to.beNil()

				expect(API.UnregisterTracked("t_trk_a")).to.beTrue()
				expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
				expect(API.UnregisterTracked("t_trk_a")).to.beFalse()
				expect(API.UnregisterTracked(42)).to.beFalse()
			end
		},
		{
			name = "class may be a list of classes",
			func = function()
				expect(API.RegisterTracked("t_trk_a", {class = {"t_npc_one", "t_npc_two"}})).to.beTrue()

				expect(API.GetTracked(ent("t_npc_one"))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_two"))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_three"))).to.beNil()
			end
		},
		{
			name = "GetTracked never raises on junk: nothing, a number, a string, an invalid entity, a table that is not an entity",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one"})

				expect(API.GetTracked(nil)).to.beNil()
				expect(API.GetTracked(5)).to.beNil()
				expect(API.GetTracked("t_npc_one")).to.beNil()
				expect(API.GetTracked(true)).to.beNil()
				expect(API.GetTracked(NULL)).to.beNil()
				expect(API.GetTracked({})).to.beNil()
				expect(API.GetTracked({IsValid = function() return false end, GetClass = function() return "t_npc_one" end})).to.beNil()
			end
		},
		{
			name = "the defaults: scan true, shape unit, relation auto; no radar, type, size or label unless given (the class decides the type and the size, the radar's own rules decide when it is listed)",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one"})
				local found = API.GetTracked(ent("t_npc_one"))

				expect(found.scan).to.beTrue()
				expect(found.shape).to.equal("unit")
				expect(found.relation).to.equal("auto")
				expect(found.size).to.beNil()
				expect(found.radar).to.beNil()
				expect(found.type).to.beNil()
				expect(found.label).to.beNil()
				expect(found.key).to.equal("t_trk_a")
			end
		},
		{
			name = "every field is stored: scan, radar, relation, type (a name becomes the index of the radar's icon), label, shape, size",
			func = function()
				local labelFn = function() return "x" end

				expect(API.RegisterTracked("t_trk_a", {class = "t_npc_one", scan = false, radar = "scan", relation = "ally", type = "flying", label = "Drone", shape = "rect", size = "big"})).to.beTrue()
				local found = API.GetTracked(ent("t_npc_one"))

				expect(found.scan).to.beFalse()
				expect(found.radar).to.equal("scan")
				expect(found.relation).to.equal("ally")
				expect(found.type).to.equal(2)
				expect(found.label).to.equal("Drone")
				expect(found.shape).to.equal("rect")
				expect(found.size).to.equal("big")

				expect(API.RegisterTracked("t_trk_a", {class = "t_npc_one", label = labelFn, relation = labelFn})).to.beTrue()
				found = API.GetTracked(ent("t_npc_one"))
				expect(found.label).to.equal(labelFn)
				expect(found.relation).to.equal(labelFn)
			end
		},
		{
			name = "the type by name or by index: human 1, flying 2, machine 3",
			func = function()
				local expected = {{"human", 1}, {"flying", 2}, {"machine", 3}, {1, 1}, {2, 2}, {3, 3}}

				for _, pair in ipairs(expected) do
					expect(API.RegisterTracked("t_trk_a", {class = "t_npc_one", type = pair[1]})).to.beTrue()
					expect(API.GetTracked(ent("t_npc_one")).type).to.equal(pair[2])
				end
			end
		},
		{
			name = "GetTracked gives the stored entry itself, not a copy (it is asked for every NPC at every tick of the radar)",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one"})

				expect(API.GetTracked(ent("t_npc_one"))).to.equal(API.GetTracked(ent("t_npc_one")))
			end
		},
		{
			name = "the definition the caller gave is not kept (changing it later changes nothing), unknown fields are ignored",
			func = function()
				local mine = {class = "t_npc_one", radar = "always", rocket = 12}

				expect(API.RegisterTracked("t_trk_a", mine)).to.beTrue()
				mine.radar = "never"
				mine.class = "t_npc_two"

				local found = API.GetTracked(ent("t_npc_one"))
				expect(found).toNot.beNil()
				expect(found.radar).to.equal("always")
				expect(found.rocket).to.beNil()
				expect(API.GetTracked(ent("t_npc_two"))).to.beNil()
			end
		},
		{
			name = "an invalid key or definition is refused with a reason",
			func = function()
				for _, key in ipairs({"", 5, true}) do
					local ok, reason = API.RegisterTracked(key, {class = "t_npc_one"})
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				local ok, reason = API.RegisterTracked(nil, {class = "t_npc_one"})
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()

				for _, def in ipairs({"x", 5, true}) do
					ok, reason = API.RegisterTracked("t_trk_a", def)
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				ok, reason = API.RegisterTracked("t_trk_a", nil)
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
			end
		},
		{
			name = "a definition that says nothing to match on (no class, base or match) is refused",
			func = function()
				local ok, reason = API.RegisterTracked("t_trk_a", {radar = "always"})

				expect(ok).to.beFalse()
				expect(string.find(reason, "match", 1, true) ~= nil).to.beTrue()
				expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
			end
		},
		{
			name = "invalid values are refused with the name of the field: class, base, match, scan, radar, relation, type, label, shape, size",
			func = function()
				local bad = {
					class = {5, "", {}, {5}, {""}, true},
					base = {5, "", {}, true},
					match = {"x", 5, true},
					scan = {"yes", 1},
					radar = {"sometimes", 5, true, "ALWAYS"},
					relation = {"enemy", 5, true, "Ally"},
					type = {"alien", 0, 5, 1.5, true}, -- 4 is the "device" type (mines), valid since the radar got its objects
					label = {5, true, ""},
					shape = {"circle", 5},
					size = {"huge", 5, true}
				}

				for field, values in pairs(bad) do
					for _, value in ipairs(values) do
						local def = {class = "t_npc_one"}
						def[field] = value
						local ok, reason = API.RegisterTracked("t_trk_a", def)

						expect(ok).to.beFalse()
						expect(string.find(reason, field, 1, true) ~= nil).to.beTrue()
					end
				end

				expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
			end
		},
		{
			name = "a refused definition keeps the previous one",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "always"})

				local ok = API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "sometimes"})

				expect(ok).to.beFalse()
				expect(API.GetTracked(ent("t_npc_one")).radar).to.equal("always")
			end
		},
		{
			name = "registering a key again replaces its entry (the old class no longer matches)",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one"})
				API.RegisterTracked("t_trk_a", {class = "t_npc_two"})

				expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
				expect(API.GetTracked(ent("t_npc_two"))).toNot.beNil()
			end
		},
		{
			name = "the first entry that matches wins, in the order of registration; replacing a key keeps its place",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "always"})
				API.RegisterTracked("t_trk_b", {class = "t_npc_one", radar = "never"})

				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_a")

				API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "scan"})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_a")
				expect(API.GetTracked(ent("t_npc_one")).radar).to.equal("scan")

				API.UnregisterTracked("t_trk_a")
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_b")
			end
		},
		{
			name = "base matches the entity's Base field, a class built on the base (scripted_ents.IsBasedOn), and the base itself",
			func = function()
				scripted_ents.IsBasedOn = function(class, base)
					return class == "t_npc_derived" and base == "t_base_ai"
				end

				API.RegisterTracked("t_trk_a", {base = "t_base_ai"})

				expect(API.GetTracked(ent("t_npc_by_field", {Base = "t_base_ai"}))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_derived"))).toNot.beNil()
				expect(API.GetTracked(ent("t_base_ai"))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_other", {Base = "t_other_base"}))).to.beNil()
			end
		},
		{
			name = "base may be a list",
			func = function()
				API.RegisterTracked("t_trk_a", {base = {"t_base_one", "t_base_two"}})

				expect(API.GetTracked(ent("t_npc_x", {Base = "t_base_one"}))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_y", {Base = "t_base_two"}))).toNot.beNil()
				expect(API.GetTracked(ent("t_npc_z", {Base = "t_base_three"}))).to.beNil()
			end
		},
		{
			name = "match(ent) decides for an entity the class and the base did not; it is asked with the entity",
			func = function()
				local asked = {}

				API.RegisterTracked("t_trk_a", {match = function(e)
					asked[#asked + 1] = e

					return e.special == true
				end})

				local special, plain = ent("t_npc_one", {special = true}), ent("t_npc_one")

				expect(API.GetTracked(special)).toNot.beNil()
				expect(API.GetTracked(plain)).to.beNil()
				expect(asked[1]).to.equal(special)
				expect(asked[2]).to.equal(plain)
			end
		},
		{
			name = "the order of cost: when the class matches, the match function of the same entry is not called",
			func = function()
				local calls = 0

				API.RegisterTracked("t_trk_a", {class = "t_npc_one", match = function() calls = calls + 1 return true end})

				expect(API.GetTracked(ent("t_npc_one"))).toNot.beNil()
				expect(calls).to.equal(0)

				-- another class: the match function is asked
				expect(API.GetTracked(ent("t_npc_two"))).toNot.beNil()
				expect(calls).to.equal(1)
			end
		},
		{
			name = "registration order holds between a match entry and a class entry: the earlier one is asked first, a later class entry is not hidden by a match that says no",
			func = function()
				local calls = 0

				API.RegisterTracked("t_trk_a", {match = function() calls = calls + 1 return false end})
				API.RegisterTracked("t_trk_b", {class = "t_npc_one"})

				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_b")
				expect(calls).to.equal(1)

				API.UnregisterTracked("t_trk_a")
				API.UnregisterTracked("t_trk_b")
				calls = 0

				API.RegisterTracked("t_trk_b", {class = "t_npc_one"})
				API.RegisterTracked("t_trk_a", {match = function() calls = calls + 1 return true end})

				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_b")
				expect(calls).to.equal(0) -- the earlier class entry won before the match function was needed
			end
		},
		{
			name = "the cache: the base of a class is worked out once, not at every call; Register and Unregister empty it",
			func = function()
				local calls = 0

				-- (only the base of this test is counted: the entries that GryMod registers for another addon, when it is there, name bases too)
				scripted_ents.IsBasedOn = function(class, base)
					if base == "t_base_ai" then
						calls = calls + 1
					end

					return false
				end

				API.RegisterTracked("t_trk_a", {base = "t_base_ai"})
				local e = ent("t_npc_cached")

				for _ = 1, 20 do
					expect(API.GetTracked(e)).to.beNil()
				end

				expect(calls).to.equal(1)

				-- a new registration is seen at once (the cache of the class is dropped)
				API.RegisterTracked("t_trk_b", {class = "t_npc_cached"})
				expect(API.GetTracked(e).key).to.equal("t_trk_b")

				API.UnregisterTracked("t_trk_b")
				expect(API.GetTracked(e)).to.beNil()
			end
		},
		{
			name = "an empty registry answers nothing without asking the entity for anything",
			func = function()
				local asked = 0

				local e = {IsValid = function() return true end, GetClass = function() asked = asked + 1 return "t_npc_one" end}

				-- the stock entries (compat/hl2/sh_tracked.lua) are in the registry: it is emptied for this test and filled again
				local order = API._trackedOrder
				local saved = {}

				for i = 1, #order do saved[i] = order[i] end
				for i = #order, 1, -1 do order[i] = nil end

				local ok, err = pcall(function()
					expect(API.GetTracked(e)).to.beNil()
					expect(asked).to.equal(0)
				end)

				for i = 1, #saved do order[i] = saved[i] end

				if not ok then error(err, 0) end
			end
		},
		{
			name = "a match function that raises an error is no match and never reaches the caller; 5 errors in a row disable it with one console line; registering again re-arms it",
			func = function()
				local runs = 0

				API.RegisterTracked("t_trk_a", {match = function() runs = runs + 1 error("broken match") end})

				for _ = 1, 8 do
					expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
				end

				expect(runs).to.equal(5)
				expect(API.SafeCallDisabled("tracked:t_trk_a/match")).to.beTrue()
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "tracked 't_trk_a/match' disabled after 5 errors", 1, true) ~= nil).to.beTrue()

				API.RegisterTracked("t_trk_a", {match = function() return true end})
				expect(API.GetTracked(ent("t_npc_one"))).toNot.beNil()
			end
		},
		{
			name = "a match function that answers something that is not true counts as no match",
			func = function()
				local answer

				API.RegisterTracked("t_trk_a", {match = function() return answer end})

				for _, junk in ipairs({"yes", 1, {}}) do
					answer = junk
					expect(API.GetTracked(ent("t_npc_one"))).to.beNil()
				end

				answer = true
				expect(API.GetTracked(ent("t_npc_one"))).toNot.beNil()
			end
		},
		-- wave B3: dangers (the grenade warning), indicators, shapes, priority, lookups by class
		{
			name = "danger is stored: label, type, armed, range, ownerOf, ownMissile; the indicator defaults to warning for an entry with danger and stays nil without",
			func = function()
				local armed, owner = function() return true end, function() return NULL end

				expect(API.RegisterTracked("t_trk_a", {class = "t_mine", danger = {label = "TRAP", type = "mine", armed = armed, range = 12.5, ownerOf = owner, ownMissile = true}})).to.beTrue()
				local d = API.GetTracked(ent("t_mine")).danger

				expect(d.label).to.equal("TRAP")
				expect(d.type).to.equal("mine")
				expect(d.armed).to.equal(armed)
				expect(d.range).to.equal(12.5)
				expect(d.ownerOf).to.equal(owner)
				expect(d.ownMissile).to.beTrue()
				expect(API.GetTracked(ent("t_mine")).indicator).to.equal("warning")

				API.RegisterTracked("t_trk_b", {class = "t_plain"})
				expect(API.GetTracked(ent("t_plain")).danger).to.beNil()
				expect(API.GetTracked(ent("t_plain")).indicator).to.beNil()
			end
		},
		{
			name = "an entry with an empty danger table is a danger as soon as it exists: no armed function, ownMissile false, the label falls back to the entry's label, then DANGER",
			func = function()
				expect(API.RegisterTracked("t_trk_a", {class = "t_mine", danger = {}})).to.beTrue()
				local d = API.GetTracked(ent("t_mine")).danger
				expect(d.armed).to.beNil()
				expect(d.ownMissile).to.beFalse()
				expect(d.label).to.equal("DANGER")

				expect(API.RegisterTracked("t_trk_a", {class = "t_mine", label = "Claymore", danger = {}})).to.beTrue()
				expect(API.GetTracked(ent("t_mine")).danger.label).to.equal("Claymore")
			end
		},
		{
			name = "the indicator is warning, marker or none, the shape unit, dot, rect or triangle (a shape the HUD cannot draw yet is stored, never an error)",
			func = function()
				for _, indicator in ipairs({"warning", "marker", "none"}) do
					expect(API.RegisterTracked("t_trk_a", {class = "t_mine", danger = {}, indicator = indicator})).to.beTrue()
					expect(API.GetTracked(ent("t_mine")).indicator).to.equal(indicator)
				end

				for _, shape in ipairs({"unit", "dot", "rect", "triangle"}) do
					expect(API.RegisterTracked("t_trk_a", {class = "t_mine", shape = shape})).to.beTrue()
					expect(API.GetTracked(ent("t_mine")).shape).to.equal(shape)
				end

				-- an indicator without danger is kept as given
				API.RegisterTracked("t_trk_a", {class = "t_mine", indicator = "none"})
				expect(API.GetTracked(ent("t_mine")).indicator).to.equal("none")
			end
		},
		{
			name = "invalid danger values are refused with the name of the field: danger itself, label, type, armed, range, ownerOf, ownMissile; and an invalid indicator or priority",
			func = function()
				local bad = {
					{{danger = "yes"}, "danger"}, {{danger = 5}, "danger"}, {{danger = true}, "danger"},
					{{danger = {label = ""}}, "label"}, {{danger = {label = 5}}, "label"}, {{danger = {label = string.rep("x", 33)}}, "label"},
					{{danger = {type = ""}}, "type"}, {{danger = {type = 5}}, "type"},
					{{danger = {armed = "yes"}}, "armed"}, {{danger = {armed = true}}, "armed"},
					{{danger = {range = 0}}, "range"}, {{danger = {range = -3}}, "range"}, {{danger = {range = "far"}}, "range"}, {{danger = {range = 201}}, "range"},
					{{danger = {ownerOf = "me"}}, "ownerOf"},
					{{danger = {ownMissile = "yes"}}, "ownMissile"}, {{danger = {ownMissile = 1}}, "ownMissile"},
					{{danger = {}, indicator = "loud"}, "indicator"}, {{indicator = 5}, "indicator"},
					{{shape = "circle"}, "shape"},
					{{priority = "high"}, "priority"}, {{priority = 0 / 0}, "priority"}, {{priority = math.huge}, "priority"}
				}

				for _, case in ipairs(bad) do
					local def = {class = "t_mine"}

					for key, value in pairs(case[1]) do def[key] = value end

					local ok, reason = API.RegisterTracked("t_trk_a", def)

					expect(ok).to.beFalse()
					expect(string.find(reason, case[2], 1, true) ~= nil).to.beTrue()
				end

				expect(API.GetTracked(ent("t_mine"))).to.beNil()
			end
		},
		{
			-- fails while a danger still needs a class (SHARED-DANGER-1: a vehicle weapon's missile is a class of a base, found by base or by a function)
			name = "a danger needs something to match on, a class, a base or a match function (a danger with none is refused)",
			func = function()
				local ok, reason = API.RegisterTracked("t_trk_a", {danger = {}})

				expect(ok).to.beFalse()
				expect(string.find(reason, "nothing to match", 1, true) ~= nil).to.beTrue()
				expect(API.RegisterTracked("t_trk_a", {base = "t_base", danger = {}})).to.beTrue()
				expect(API.RegisterTracked("t_trk_a", {match = function() return true end, danger = {}})).to.beTrue()
				expect(API.RegisterTracked("t_trk_a", {class = "t_mine", match = function() return true end, danger = {}})).to.beTrue()
			end
		},
		{
			name = "GetDanger gives the first entry with danger of a class (a class name or an entity), an entry without danger is skipped, nothing for an unknown class; DangerClasses lists the classes",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_mine", radar = "always"}) -- no danger: not the one
				API.RegisterTracked("t_trk_b", {class = {"t_mine", "t_bomb"}, danger = {label = "FIRST"}})
				API.RegisterTracked("t_trk_c", {class = "t_mine", danger = {label = "SECOND"}})

				expect(API.GetDanger("t_mine").key).to.equal("t_trk_b")
				expect(API.GetDanger("t_mine").danger.label).to.equal("FIRST")
				expect(API.GetDanger(ent("t_bomb")).key).to.equal("t_trk_b")
				expect(API.GetDanger("t_unknown")).to.beNil()
				expect(API.GetDanger(nil)).to.beNil()
				expect(API.GetDanger(5)).to.beNil()
				expect(API.GetDanger({})).to.beNil()

				local seen = {}
				for _, class in ipairs(API.DangerClasses()) do seen[class] = (seen[class] or 0) + 1 end
				expect(seen.t_mine).to.equal(1)
				expect(seen.t_bomb).to.equal(1)

				API.UnregisterTracked("t_trk_b")
				expect(API.GetDanger("t_mine").key).to.equal("t_trk_c")
				expect(API.GetDanger("t_bomb")).to.beNil()
			end
		},
		{
			name = "GetTrackedByClass gives the first entry that names the class (class lists only, no base, no match function); it follows Register and Unregister",
			func = function()
				API.RegisterTracked("t_trk_a", {class = {"t_npc_one", "t_npc_two"}, type = "flying"})
				API.RegisterTracked("t_trk_b", {class = "t_npc_one", type = "machine"})
				API.RegisterTracked("t_trk_c", {base = "t_base_ai"})
				API.RegisterTracked("t_trk_d", {match = function() return true end})

				expect(API.GetTrackedByClass("t_npc_one").key).to.equal("t_trk_a")
				expect(API.GetTrackedByClass("t_npc_two").key).to.equal("t_trk_a")
				expect(API.GetTrackedByClass("t_base_ai")).to.beNil()
				expect(API.GetTrackedByClass("t_npc_other")).to.beNil()
				expect(API.GetTrackedByClass(nil)).to.beNil()
				expect(API.GetTrackedByClass(5)).to.beNil()

				API.UnregisterTracked("t_trk_a")
				expect(API.GetTrackedByClass("t_npc_one").key).to.equal("t_trk_b")
				expect(API.GetTrackedByClass("t_npc_two")).to.beNil()
			end
		},
		{
			name = "priority: the higher comes first whatever the registration order (a stock entry registered with a low one is beaten by any later entry), ties keep the registration order, replacing a key with the same priority keeps its place",
			func = function()
				API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "never", priority = -100})
				API.RegisterTracked("t_trk_b", {class = "t_npc_one", radar = "always"})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_b")
				expect(API.GetTrackedByClass("t_npc_one").key).to.equal("t_trk_b")

				API.RegisterTracked("t_trk_c", {class = "t_npc_one", radar = "scan", priority = 5})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_c")

				API.RegisterTracked("t_trk_d", {class = "t_npc_one", radar = "hostile", priority = 5})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_c") -- the tie: registered first

				API.RegisterTracked("t_trk_c", {class = "t_npc_one", radar = "scan", priority = 5})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_c") -- same place

				-- a new priority moves it
				API.RegisterTracked("t_trk_a", {class = "t_npc_one", radar = "never", priority = 10})
				expect(API.GetTracked(ent("t_npc_one")).key).to.equal("t_trk_a")
				expect(API.GetTracked(ent("t_npc_one")).priority).to.equal(10)

				-- the default is 0
				API.UnregisterTracked("t_trk_a")
				API.UnregisterTracked("t_trk_c")
				API.UnregisterTracked("t_trk_d")
				expect(API.GetTracked(ent("t_npc_one")).priority).to.equal(0)
			end
		}
	}
}
