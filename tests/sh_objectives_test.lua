-- Tests of the shared part of the objectives (lua/grymod/sh_objectives.lua), GLuaTest format, runs in the server AND in the client realm: the
-- check of a definition (what a developer may give to GryMod.API.RegisterObjective), the record that goes through the network (written by the
-- server, read by the client), and the safe run of the reporting hooks. Nothing here touches the real network: the net functions are replaced for
-- the length of a call and put back whatever happens inside.
-- Each case names the production change whose absence makes it fail.

local Obj

-- a fake entity: a table that answers like one
local function fakeEnt()
	return {
		IsValid = function() return true end,
		GetPos = function() return Vector(1, 2, 3) end,
		EntIndex = function() return 7 end
	}
end

-- runs fn with the net writers and readers replaced by a recorder (writes) and a queue (reads); the real ones are put back in any case
local function withNet(fn)
	local names = {"WriteString", "WriteUInt", "WriteBool", "WriteVector", "ReadString", "ReadUInt", "ReadBool", "ReadVector"}
	local real = {}

	for _, n in ipairs(names) do
		real[n] = net[n]
	end

	local log, head = {}, 0

	net.WriteString = function(v) log[#log + 1] = {"string", v} end
	net.WriteUInt = function(v, bits) log[#log + 1] = {"uint", v, bits} end
	net.WriteBool = function(v) log[#log + 1] = {"bool", v} end
	net.WriteVector = function(v) log[#log + 1] = {"vector", v} end

	local function pop(kind, bits)
		head = head + 1
		local item = log[head]
		assert(item ~= nil and item[1] == kind, "the reader asks for a " .. kind .. " where the writer wrote " .. tostring(item and item[1]))

		if bits then
			assert(item[3] == bits, "the reader reads " .. bits .. " bits where the writer wrote " .. tostring(item[3]))
		end

		return item[2]
	end

	net.ReadString = function() return pop("string") end
	net.ReadUInt = function(bits) return pop("uint", bits) end
	net.ReadBool = function() return pop("bool") end
	net.ReadVector = function() return pop("vector") end

	local ok, err = pcall(fn, log, function() head = 0 end)

	for n, f in pairs(real) do
		net[n] = f
	end

	if not ok then
		error(err, 0)
	end
end

local function goodDef(extra)
	local def = {title = "Find the key", pos = Vector(10, 20, 30)}

	for k, v in pairs(extra or {}) do
		def[k] = v
	end

	return def
end

local realMsgN
local lines

return {
	groupName = "GryMod objectives: shared part",
	beforeEach = function()
		Obj = GryMod.Objectives
		lines = {}
		realMsgN = MsgN
		MsgN = function(...)
			lines[#lines + 1] = table.concat({...}, "")
		end
	end,
	afterEach = function()
		MsgN = realMsgN
	end,
	cases = {
		{
			-- breaks if: sh_objectives.lua is not loaded (grymod_shared.lua) or does not declare its feature
			name = "the module exists in both realms and says so through API.Has",
			func = function()
				expect(istable(Obj)).to.beTrue()
				expect(GryMod.API.Has("objectives")).to.beTrue()
				expect(isfunction(Obj.CheckDefinition)).to.beTrue()
				expect(isfunction(Obj.Fire)).to.beTrue()
				expect(isfunction(Obj.WriteRecord)).to.beTrue()
				expect(isfunction(Obj.ReadRecord)).to.beTrue()
			end
		},
		{
			-- breaks if: a default of the model changes (primary true, state active, onRemove remove, radar and marker on, empty description)
			name = "a definition with only a title and a position gets every default of the model",
			func = function()
				local clean, reason = Obj.CheckDefinition("k", goodDef())

				expect(reason).to.beNil()
				expect(clean.id).to.equal("k")
				expect(clean.title).to.equal("Find the key")
				expect(clean.description).to.equal("")
				expect(clean.primary).to.beTrue()
				expect(clean.state).to.equal("active")
				expect(clean.onRemove).to.equal("remove")
				expect(clean.radar).to.beTrue()
				expect(clean.marker).to.beTrue()
				expect(clean.pos == Vector(10, 20, 30)).to.beTrue()
				expect(clean.ent).to.beNil()
				expect(clean.entFn).to.beNil()
				expect(clean.filter).to.beNil()
			end
		},
		{
			-- breaks if: a field given by the developer is dropped or replaced by its default
			name = "every field the developer gives is kept",
			func = function()
				local filter = function() return true end
				local clean = Obj.CheckDefinition("k", goodDef({
					description = "In the cellar.", primary = false, state = "failed", onRemove = "complete", radar = false, marker = false, filter = filter,
					unknownField = 12
				}))

				expect(clean.description).to.equal("In the cellar.")
				expect(clean.primary).to.beFalse()
				expect(clean.state).to.equal("failed")
				expect(clean.onRemove).to.equal("complete")
				expect(clean.radar).to.beFalse()
				expect(clean.marker).to.beFalse()
				expect(clean.filter == filter).to.beTrue()
				expect(clean.unknownField).to.beNil()
			end
		},
		{
			-- breaks if: the clean definition keeps the developer's own Vector (a later change of it would move the objective behind our back)
			name = "the position is copied: changing the developer's vector later changes nothing",
			func = function()
				local pos = Vector(1, 1, 1)
				local clean = Obj.CheckDefinition("k", {title = "T", pos = pos})

				pos.x = 999
				expect(clean.pos.x).to.equal(1)
			end
		},
		{
			-- breaks if: ent is not accepted as an entity or as a function, or the function is run during the check
			name = "an entity, or a function that gives one, is accepted in place of a position",
			func = function()
				local e = fakeEnt()
				local clean = Obj.CheckDefinition("k", {title = "T", ent = e})

				expect(clean.ent == e).to.beTrue()
				expect(clean.pos).to.beNil()

				local ran = false
				local fn = function() ran = true return e end
				clean = Obj.CheckDefinition("k", {title = "T", ent = fn})

				expect(clean.entFn == fn).to.beTrue()
				expect(clean.ent).to.beNil()
				expect(ran).to.beFalse()
			end
		},
		{
			-- breaks if: one of the checks is missing: each bad definition is refused with false and a reason that names the field, and never raises
			name = "bad definitions are refused with a reason that names the field, and nothing is raised",
			func = function()
				local cases = {
					{"k", nil, "definition"},
					{"k", "text", "definition"},
					{"k", 5, "definition"},
					{nil, goodDef(), "id"},
					{"", goodDef(), "id"},
					{12, goodDef(), "id"},
					{string.rep("a", 65), goodDef(), "id"},
					{"k", goodDef({title = false}), "title"},
					{"k", {pos = Vector(0, 0, 0)}, "title"},
					{"k", goodDef({title = ""}), "title"},
					{"k", goodDef({title = 5}), "title"},
					{"k", goodDef({title = string.rep("a", 129)}), "title"},
					{"k", goodDef({description = 5}), "description"},
					{"k", goodDef({description = string.rep("a", 513)}), "description"},
					{"k", goodDef({primary = "yes"}), "primary"},
					{"k", goodDef({primary = 1}), "primary"},
					{"k", goodDef({state = "secondary"}), "state"},
					{"k", goodDef({state = 1}), "state"},
					{"k", goodDef({onRemove = "explode"}), "onRemove"},
					{"k", goodDef({onRemove = true}), "onRemove"},
					{"k", goodDef({radar = "on"}), "radar"},
					{"k", goodDef({marker = 0}), "marker"},
					{"k", goodDef({filter = "all"}), "filter"},
					{"k", goodDef({pos = {x = 1, y = 2, z = 3}}), "pos"},
					{"k", goodDef({pos = 5}), "pos"},
					{"k", goodDef({pos = Vector(0, 0, 0 / 0)}), "pos"},
					{"k", goodDef({pos = Vector(math.huge, 0, 0)}), "pos"},
					{"k", {title = "T"}, "pos"},
					{"k", {title = "T", pos = Vector(0, 0, 0), ent = fakeEnt()}, "ent"},
					{"k", {title = "T", ent = NULL}, "ent"},
					{"k", {title = "T", ent = 5}, "ent"},
					{"k", {title = "T", ent = "prop_physics"}, "ent"}
				}

				for i, row in ipairs(cases) do
					local clean, reason
					expect(function() clean, reason = Obj.CheckDefinition(row[1], row[2]) end).to.succeed()
					expect(clean).to.beFalse()
					expect(isstring(reason)).to.beTrue()
					expect(string.find(reason, row[3], 1, true) ~= nil).to.beTrue()
				end
			end
		},
		{
			-- breaks if: the state names or the reason names of the model change (they are in the public docs)
			name = "the names of the states, the reasons and the removal rules are the documented ones, each id a number the wire can carry",
			func = function()
				expect(Obj.States.ACTIVE).to.equal("active")
				expect(Obj.States.DONE).to.equal("done")
				expect(Obj.States.FAILED).to.equal("failed")
				expect(Obj.Reasons.REMOVED).to.equal("removed")
				expect(Obj.Reasons.CLEARED).to.equal("cleared")
				expect(Obj.Reasons.ENTITY_REMOVED).to.equal("entity_removed")
				expect(Obj.Reasons.MAP_CHANGED).to.equal("map_changed")

				for _, state in ipairs(Obj.StateList) do
					expect(Obj.StateList[Obj.StateIds[state] + 1]).to.equal(state)
					expect(Obj.StateIds[state] < 2 ^ Obj.StateBits).to.beTrue()
				end

				for _, reason in ipairs(Obj.ReasonList) do
					expect(Obj.ReasonList[Obj.ReasonIds[reason] + 1]).to.equal(reason)
					expect(Obj.ReasonIds[reason] < 2 ^ Obj.ReasonBits).to.beTrue()
				end

				expect(#Obj.StateList).to.equal(3)
				expect(#Obj.ReasonList).to.equal(4)
			end
		},
		{
			-- breaks if: the writer and the reader of the record do not agree on the order or the width of a field (the client would read garbage)
			name = "a record that is written is read back the same, with the reader asking for exactly what the writer wrote",
			func = function()
				withNet(function(log, rewind)
					local rec = {
						id = "my_map.find_key", title = "Find the key", description = "It is in the cellar.", primary = false, state = "done", main = true,
						radar = false, marker = true, pos = Vector(5, 6, 7), entIndex = 12
					}

					Obj.WriteRecord(rec)
					expect(#log > 0).to.beTrue()
					rewind()

					local read = Obj.ReadRecord()

					expect(read.id).to.equal(rec.id)
					expect(read.title).to.equal(rec.title)
					expect(read.description).to.equal(rec.description)
					expect(read.primary).to.beFalse()
					expect(read.state).to.equal("done")
					expect(read.main).to.beTrue()
					expect(read.radar).to.beFalse()
					expect(read.marker).to.beTrue()
					expect(read.pos == Vector(5, 6, 7)).to.beTrue()
					expect(read.entIndex).to.equal(12)
				end)
			end
		},
		{
			-- breaks if: the reader trusts the network: a title that is too long or a state id that does not exist must give nil, not a record
			name = "a record that breaks the bounds is dropped, never trusted",
			func = function()
				withNet(function(log, rewind)
					local rec = {id = "k", title = "T", description = "", primary = true, state = "active", main = false, radar = true, marker = true,
						pos = Vector(0, 0, 0), entIndex = 0}

					Obj.WriteRecord(rec)

					-- the title is the second item written
					log[2][2] = string.rep("a", Obj.Limits.title + 1)
					rewind()
					expect(Obj.ReadRecord()).to.beNil()

					log[2][2] = "T"
					-- the state is the first uint after the three strings and the bool of primary
					for i, item in ipairs(log) do
						if item[1] == "uint" and item[3] == Obj.StateBits then
							item[2] = 3
						end
					end

					rewind()
					expect(Obj.ReadRecord()).to.beNil()
				end)
			end
		},
		{
			-- breaks if: Fire calls hook.Run without protection (a listener that throws would break the server's objective code) or reports nothing
			name = "a reporting hook runs its listeners, a listener that throws breaks nothing and is reported on the console",
			func = function()
				local name = "GryMod_ObjTest_" .. os.time() .. "_" .. math.random(1, 1000000)
				local got = {}

				hook.Add(name, "good", function(...) got[#got + 1] = {...} end) -- returns nothing: hook.Call stops at the first listener that returns a value, and "bad" could then never run
				hook.Add(name, "bad", function() error("boom") end)

				local ok, err = pcall(function() Obj.Fire(name, "a", 2) end)

				hook.Remove(name, "good")
				hook.Remove(name, "bad")

				expect(ok).to.beTrue()
				expect(err).to.beNil()
				expect(#lines >= 1).to.beTrue()
				expect(string.find(lines[1], name, 1, true) ~= nil).to.beTrue()
			end
		},
		{
			-- breaks if: Fire returns what a listener returned (the hooks are reports: no value is ever read)
			name = "a reporting hook returns nothing, whatever its listeners return",
			func = function()
				local name = "GryMod_ObjTest_ret_" .. os.time() .. "_" .. math.random(1, 1000000)

				hook.Add(name, "ret", function() return false end)
				local result = Obj.Fire(name)
				hook.Remove(name, "ret")

				expect(result).to.beNil()
			end
		},
		{
			-- breaks if: a listener that throws on every event can fill the console without end
			name = "the errors of a hook are reported at most five times, then silently",
			func = function()
				local name = "GryMod_ObjTest_spam_" .. os.time() .. "_" .. math.random(1, 1000000)

				hook.Add(name, "bad", function() error("boom") end)

				for _ = 1, 9 do
					Obj.Fire(name)
				end

				hook.Remove(name, "bad")
				expect(#lines).to.equal(5)
			end
		}
	}
}
