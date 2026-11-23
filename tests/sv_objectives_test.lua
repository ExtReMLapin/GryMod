-- Tests of the objectives on the SERVER (lua/grymod/server/sv_objectives.lua), GLuaTest format, server realm: the API (RegisterObjective, SetObjectiveState,
-- RemoveObjective, SetMainObjective, GetObjective, GetObjectives, ClearObjectives), the reporting hooks, an objective that follows an entity, the
-- network (a full list when a client is ready, then deltas, the filter of each player), the cleaning of a map and the administrators' switch gry_objectives.
--
-- Nothing here uses the real network or a real player: the net functions are replaced by a recorder for the length of each case (`scene`: put back in a pcall
-- whatever happens inside), the players are fakes (a table that answers IsValid), and the entities are real info_target points made here and removed after.
-- Every hook a case adds is removed after it. Each case names the production change whose absence makes it fail.

local S, Obj, API, Reasons

local NET = {"Start", "WriteString", "WriteUInt", "WriteBool", "WriteVector", "Send"}
local sent, current
local madeHooks, madeEnts

-- a player of the tests
local function fakePly(label)
	return {isFake = true, label = label, IsValid = function() return true end, IsPlayer = function() return true end}
end

-- a real point entity at `pos`
local function point(pos)
	local e = ents.Create("info_target")

	e:SetPos(pos or Vector(0, 0, 0))
	e:Spawn()
	madeEnts[#madeEnts + 1] = e

	return e
end

-- the messages the code sent, as {name, items = {{kind, value, bits}, ...}, to = target}
local function installNet()
	sent, current = {}, nil

	net.Start = function(name)
		current = {name = name, items = {}}

		return true
	end
	net.WriteString = function(v) current.items[#current.items + 1] = {"string", v} end
	net.WriteUInt = function(v, bits) current.items[#current.items + 1] = {"uint", v, bits} end
	net.WriteBool = function(v) current.items[#current.items + 1] = {"bool", v} end
	net.WriteVector = function(v) current.items[#current.items + 1] = {"vector", v} end
	net.Send = function(target)
		current.to = target
		sent[#sent + 1] = current
		current = nil
	end
end

-- the players a message went to
local function targets(msg)
	if msg.to.isFake then
		return {msg.to}
	end

	return msg.to
end

-- a message of gry_objectives as the client reads it
local function decode(msg)
	local it = msg.items
	local out = {op = it[1][2]}

	if out.op == Obj.Ops.SET then
		out.id, out.title, out.description, out.primary = it[2][2], it[3][2], it[4][2], it[5][2]
		out.state = Obj.StateList[it[6][2] + 1]
		out.main, out.radar, out.marker, out.pos, out.entIndex = it[7][2], it[8][2], it[9][2], it[10][2], it[11][2]
	elseif out.op == Obj.Ops.REMOVE then
		out.id, out.reason = it[2][2], Obj.ReasonList[it[3][2] + 1]
	elseif out.op == Obj.Ops.CLEAR then
		out.reason = Obj.ReasonList[it[2][2] + 1]
	elseif out.op == Obj.Ops.MAIN then
		out.id = it[2][2]
	elseif out.op == Obj.Ops.POS then
		out.list = {}

		for i = 1, it[2][2] do
			out.list[i] = {id = it[1 + i * 2][2], pos = it[2 + i * 2][2]}
		end
	end

	return out
end

-- what `ply` received on gry_objectives, decoded, in order
local function received(ply)
	local list = {}

	for _, msg in ipairs(sent) do
		if msg.name == "gry_objectives" then
			for _, target in ipairs(targets(msg)) do
				if target == ply then
					list[#list + 1] = decode(msg)
				end
			end
		end
	end

	return list
end

local function opsOf(list)
	local ops = {}

	for i, m in ipairs(list) do
		ops[i] = m.op
	end

	return ops
end

local function ofGryObjectives()
	local n = 0

	for _, msg in ipairs(sent) do
		if msg.name == "gry_objectives" then
			n = n + 1
		end
	end

	return n
end

-- the calls an event got
local function listen(event)
	local calls = {}
	local id = "gry_sv_objectives_test_" .. event .. "_" .. #madeHooks

	hook.Add(event, id, function(...)
		calls[#calls + 1] = {...}
	end)
	madeHooks[#madeHooks + 1] = {event, id}

	return calls
end

-- the engine's hook for a removed entity, called the way the engine calls it (not through hook.Run: the other addons' listeners are none of this test's business)
local function entityRemoved(e)
	hook.GetTable().EntityRemoved["GryMod objectives"](e)
end

local function pos(x, y, z)
	return Vector(x or 0, y or 0, z or 0)
end

-- one case: the net recorder, the switch on, nothing registered; everything is put back in a pcall, whatever happens inside
local function scene(body)
	return function()
		local real = {}

		for _, n in ipairs(NET) do
			real[n] = net[n]
		end

		local convar = GetConVar("gry_objectives")
		local savedSwitch = convar:GetString()

		madeHooks, madeEnts = {}, {}
		installNet()
		convar:SetString("1")
		S.Reset()

		local ok, err = pcall(body)

		pcall(function()
			for _, h in ipairs(madeHooks) do
				hook.Remove(h[1], h[2])
			end

			S.Reset()

			for _, e in ipairs(madeEnts) do
				if IsValid(e) then
					e:Remove()
				end
			end
		end)

		for n, f in pairs(real) do
			net[n] = f
		end

		pcall(function() convar:SetString(savedSwitch) end)
		pcall(S.Reset)

		if not ok then
			error(err, 0)
		end
	end
end

return {
	groupName = "GryMod objectives (server)",
	beforeAll = function()
		S, Obj, API = GryMod.ObjectivesServer, GryMod.Objectives, GryMod.API
		Reasons = Obj and Obj.Reasons
	end,
	cases = {
		{
			-- breaks if: sv_objectives.lua is not loaded, a function of the API is missing, or the switch is not a replicated yes / no setting of the administrators' list
			name = "the API, the network message and the switch gry_objectives exist; the switch is an administrators' setting",
			func = function()
				for _, name in ipairs({"RegisterObjective", "SetObjectiveState", "RemoveObjective", "SetMainObjective", "GetObjective", "GetObjectives", "ClearObjectives", "RefreshObjectives"}) do
					expect(isfunction(API[name])).to.beTrue()
				end

				expect(util.NetworkStringToID("gry_objectives") ~= 0).to.beTrue()

				local convar = GetConVar("gry_objectives")
				expect(convar ~= nil).to.beTrue()
				expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				expect(GryMod.ServerSettings.Find("gry_objectives").kind).to.equal("bool")
				expect(GryMod.ServerSettings.Validate("gry_objectives", "0")).to.equal("0")
				expect(GryMod.ServerSettings.Validate("gry_objectives", "2")).to.beNil()
			end
		},
		{
			-- breaks if: RegisterObjective does not store the definition, does not copy it for the reader, or answers something else than true
			name = "RegisterObjective stores an objective with the defaults, GetObjective gives a copy of it, GetObjectives lists them in the order of registration",
			func = scene(function()
				expect(API.RegisterObjective("a", {title = "Alpha", pos = pos(1, 2, 3)})).to.beTrue()
				expect(API.RegisterObjective("b", {title = "Beta", description = "Second", primary = false, pos = pos(4, 5, 6), radar = false})).to.beTrue()

				local a = API.GetObjective("a")

				expect(a.id).to.equal("a")
				expect(a.title).to.equal("Alpha")
				expect(a.description).to.equal("")
				expect(a.primary).to.beTrue()
				expect(a.state).to.equal("active")
				expect(a.main).to.beFalse()
				expect(a.radar).to.beTrue()
				expect(a.marker).to.beTrue()
				expect(a.pos == pos(1, 2, 3)).to.beTrue()
				expect(a.ent).to.beNil()

				-- a copy: what the reader changes is not the objective
				a.title = "changed"
				a.pos.x = 99
				expect(API.GetObjective("a").title).to.equal("Alpha")
				expect(API.GetObjective("a").pos.x).to.equal(1)

				local list = API.GetObjectives()
				expect(#list).to.equal(2)
				expect(list[1].id).to.equal("a")
				expect(list[2].id).to.equal("b")
				expect(list[2].primary).to.beFalse()
				expect(list[2].radar).to.beFalse()
				expect(API.GetObjective("nope")).to.beNil()
				expect(API.GetObjective(5)).to.beNil()
			end)
		},
		{
			-- breaks if: a bad definition raises, is stored anyway, or comes back without a reason
			name = "a bad definition is refused with false and a reason, nothing is stored, nothing is raised",
			func = scene(function()
				for _, args in ipairs({{nil, nil}, {"k", nil}, {"k", {}}, {"k", {title = "T"}}, {"k", {title = "T", pos = 5}}, {"", {title = "T", pos = pos()}}}) do
					local ok, reason
					expect(function() ok, reason = API.RegisterObjective(args[1], args[2]) end).to.succeed()
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(#API.GetObjectives()).to.equal(0)
			end)
		},
		{
			-- breaks if: the limit of 256 objectives is not enforced (the full list must stay small), or a known id counts as new
			name = "at most 256 objectives, and registering a known id again is not a new one",
			func = scene(function()
				for i = 1, Obj.Limits.count do
					expect(API.RegisterObjective("o" .. i, {title = "T", pos = pos(i)})).to.beTrue()
				end

				local ok, reason = API.RegisterObjective("one more", {title = "T", pos = pos()})
				expect(ok).to.beFalse()
				expect(string.find(reason, "256", 1, true) ~= nil).to.beTrue()
				expect(API.RegisterObjective("o7", {title = "T again", pos = pos()})).to.beTrue()
				expect(#API.GetObjectives()).to.equal(256)
			end)
		},
		{
			-- breaks if: re-registering an id adds a second objective, loses its place, or does not tell the listeners what changed
			name = "registering an id again updates it in place: the same place in the list, Changed for what changed (with the old state), Added only once",
			func = scene(function()
				local added = listen("GryMod_ObjectiveAdded")
				local changed = listen("GryMod_ObjectiveChanged")

				API.RegisterObjective("a", {title = "Alpha", pos = pos()})
				API.RegisterObjective("b", {title = "Beta", pos = pos()})
				expect(#added).to.equal(2)
				expect(#changed).to.equal(0)

				-- nothing the hooks report changed: only the position
				API.RegisterObjective("a", {title = "Alpha", pos = pos(50)})
				expect(#changed).to.equal(0)
				expect(API.GetObjective("a").pos.x).to.equal(50)

				API.RegisterObjective("a", {title = "Alpha 2", state = "done", pos = pos(50)})
				expect(#added).to.equal(2)
				expect(#changed).to.equal(1)
				expect(changed[1][1]).to.equal("a")
				expect(changed[1][2].title).to.equal("Alpha 2")
				expect(changed[1][2].state).to.equal("done")
				expect(changed[1][3]).to.equal("active")

				local list = API.GetObjectives()
				expect(#list).to.equal(2)
				expect(list[1].id).to.equal("a")
				expect(list[1].title).to.equal("Alpha 2")
			end)
		},
		{
			-- breaks if: SetObjectiveState accepts a state that does not exist, does not refuse an unknown id, or reports a change that is none
			name = "SetObjectiveState changes the state and tells Changed(id, obj, oldState); a state it already has is true and silent; bad input is false with a reason",
			func = scene(function()
				local changed = listen("GryMod_ObjectiveChanged")

				API.RegisterObjective("a", {title = "Alpha", pos = pos()})

				expect(API.SetObjectiveState("a", "done")).to.beTrue()
				expect(API.GetObjective("a").state).to.equal("done")
				expect(#changed).to.equal(1)
				expect(changed[1][1]).to.equal("a")
				expect(changed[1][2].state).to.equal("done")
				expect(changed[1][3]).to.equal("active")

				expect(API.SetObjectiveState("a", "done")).to.beTrue()
				expect(#changed).to.equal(1)

				expect(API.SetObjectiveState("a", "failed")).to.beTrue()
				expect(changed[2][3]).to.equal("done")

				local ok, reason = API.SetObjectiveState("a", "secondary")
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				ok, reason = API.SetObjectiveState("nope", "done")
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				expect(API.SetObjectiveState(nil, "done")).to.beFalse()
				expect(API.GetObjective("a").state).to.equal("failed")
				expect(#changed).to.equal(2)
			end)
		},
		{
			-- breaks if: the hooks are not told on this realm, the arguments are not (id, obj), or a returned value changes what happens
			name = "Added(id, obj) and Removed(id, obj, \"removed\") are told with a copy of the objective; the values the listeners return change nothing",
			func = scene(function()
				local added = listen("GryMod_ObjectiveAdded")
				local removed = listen("GryMod_ObjectiveRemoved")

				hook.Add("GryMod_ObjectiveAdded", "gry_sv_objectives_test_returns", function() return false end)
				madeHooks[#madeHooks + 1] = {"GryMod_ObjectiveAdded", "gry_sv_objectives_test_returns"}

				expect(API.RegisterObjective("a", {title = "Alpha", pos = pos(1, 1, 1)})).to.beTrue()
				expect(#added).to.equal(1)
				expect(added[1][1]).to.equal("a")
				expect(added[1][2].title).to.equal("Alpha")
				expect(added[1][2].state).to.equal("active")

				expect(API.RemoveObjective("a")).to.beTrue()
				expect(#removed).to.equal(1)
				expect(removed[1][1]).to.equal("a")
				expect(removed[1][2].title).to.equal("Alpha")
				expect(removed[1][3]).to.equal("removed")
				expect(API.GetObjective("a")).to.beNil()
				expect(#API.GetObjectives()).to.equal(0)

				local ok, reason = API.RemoveObjective("a")
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				expect(#removed).to.equal(1)
			end)
		},
		{
			-- breaks if: a listener that throws stops the API call (the objective half done, the clients not told)
			name = "a listener that throws does not break RegisterObjective, SetObjectiveState or RemoveObjective",
			func = scene(function()
				local realMsgN = MsgN
				MsgN = function() end

				local ok, err = pcall(function()
					for _, event in ipairs({"GryMod_ObjectiveAdded", "GryMod_ObjectiveChanged", "GryMod_ObjectiveRemoved"}) do
						hook.Add(event, "gry_sv_objectives_test_throws", function() error("boom") end)
						madeHooks[#madeHooks + 1] = {event, "gry_sv_objectives_test_throws"}
					end

					expect(API.RegisterObjective("a", {title = "Alpha", pos = pos()})).to.beTrue()
					expect(API.SetObjectiveState("a", "done")).to.beTrue()
					expect(API.GetObjective("a").state).to.equal("done")
					expect(API.RemoveObjective("a")).to.beTrue()
					expect(API.GetObjective("a")).to.beNil()
				end)

				MsgN = realMsgN

				if not ok then
					error(err, 0)
				end
			end)
		},
		{
			-- breaks if: SetMainObjective keeps two main objectives, accepts an unknown id, or the removed main stays main
			name = "there is one main objective at most: SetMainObjective moves it (Changed for both), nil clears it, removing it clears it, an unknown id is refused",
			func = scene(function()
				local changed = listen("GryMod_ObjectiveChanged")

				API.RegisterObjective("a", {title = "Alpha", pos = pos()})
				API.RegisterObjective("b", {title = "Beta", pos = pos()})

				expect(API.SetMainObjective("a")).to.beTrue()
				expect(API.GetObjective("a").main).to.beTrue()
				expect(API.GetObjective("b").main).to.beFalse()
				expect(#changed).to.equal(1)
				expect(changed[1][1]).to.equal("a")
				expect(changed[1][2].main).to.beTrue()
				expect(changed[1][3]).to.equal("active")

				expect(API.SetMainObjective("a")).to.beTrue()
				expect(#changed).to.equal(1)

				expect(API.SetMainObjective("b")).to.beTrue()
				expect(API.GetObjective("a").main).to.beFalse()
				expect(API.GetObjective("b").main).to.beTrue()
				expect(#changed).to.equal(3)
				expect(changed[2][1]).to.equal("a")
				expect(changed[2][2].main).to.beFalse()
				expect(changed[3][1]).to.equal("b")

				local ok, reason = API.SetMainObjective("nope")
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
				expect(API.GetObjective("b").main).to.beTrue()

				expect(API.SetMainObjective(nil)).to.beTrue()
				expect(API.GetObjective("b").main).to.beFalse()

				API.SetMainObjective("a")
				API.RemoveObjective("a")
				expect(API.GetObjective("b").main).to.beFalse()
				API.RegisterObjective("a", {title = "Alpha", pos = pos()})
				expect(API.GetObjective("a").main).to.beFalse()
			end)
		},
		{
			-- breaks if: ClearObjectives leaves one, tells no Removed with the reason "cleared", or forgets the main objective
			name = "ClearObjectives removes all of them, tells Removed with the reason \"cleared\" for each, and returns how many",
			func = scene(function()
				local removed = listen("GryMod_ObjectiveRemoved")

				API.RegisterObjective("a", {title = "Alpha", pos = pos()})
				API.RegisterObjective("b", {title = "Beta", pos = pos()})
				API.SetMainObjective("b")

				expect(API.ClearObjectives()).to.equal(2)
				expect(#API.GetObjectives()).to.equal(0)
				expect(#removed).to.equal(2)
				expect(removed[1][3]).to.equal("cleared")
				expect(removed[2][3]).to.equal("cleared")
				expect(removed[2][2].main).to.beTrue()

				API.RegisterObjective("b", {title = "Beta", pos = pos()})
				expect(API.GetObjective("b").main).to.beFalse()
				expect(API.ClearObjectives()).to.equal(1)
				expect(API.ClearObjectives()).to.equal(0)
			end)
		},
		{
			-- breaks if: an objective that follows an entity does not know the entity, or its position is not the entity's
			name = "an objective that follows an entity: ent and pos come from the entity, a function for ent is run, a function with no valid entity is refused",
			func = scene(function()
				local e = point(pos(100, 200, 300))

				expect(API.RegisterObjective("a", {title = "Alpha", ent = e})).to.beTrue()
				expect(API.GetObjective("a").ent == e).to.beTrue()
				expect(API.GetObjective("a").pos == pos(100, 200, 300)).to.beTrue()

				-- the position is the entity's now, not the one of the registration
				e:SetPos(pos(1, 2, 3))
				expect(API.GetObjective("a").pos == pos(1, 2, 3)).to.beTrue()

				expect(API.RegisterObjective("b", {title = "Beta", ent = function() return e end})).to.beTrue()
				expect(API.GetObjective("b").ent == e).to.beTrue()

				local ok, reason = API.RegisterObjective("c", {title = "Gamma", ent = function() return NULL end})
				expect(ok).to.beFalse()
				expect(string.find(reason, "ent", 1, true) ~= nil).to.beTrue()
				ok, reason = API.RegisterObjective("d", {title = "Delta", ent = function() error("boom") end})
				expect(ok).to.beFalse()
				expect(string.find(reason, "ent", 1, true) ~= nil).to.beTrue()
				expect(API.GetObjective("c")).to.beNil()
				expect(API.GetObjective("d")).to.beNil()
			end)
		},
		{
			-- breaks if: the EntityRemoved hook is added for nothing (a permanent cost on every removed entity) or is not removed when the last entity objective is gone
			name = "the EntityRemoved hook exists only while an objective follows an entity, and the position timer only while the switch is on",
			func = scene(function()
				local function watching()
					return hook.GetTable().EntityRemoved ~= nil and hook.GetTable().EntityRemoved["GryMod objectives"] ~= nil
				end

				expect(watching()).to.beFalse()
				expect(timer.Exists("GryMod objectives positions")).to.beFalse()

				API.RegisterObjective("p", {title = "Position", pos = pos()})
				expect(watching()).to.beFalse()
				expect(timer.Exists("GryMod objectives positions")).to.beFalse()

				API.RegisterObjective("a", {title = "Alpha", ent = point()})
				expect(watching()).to.beTrue()
				expect(timer.Exists("GryMod objectives positions")).to.beTrue()

				GetConVar("gry_objectives"):SetString("0")
				expect(watching()).to.beTrue() -- the registry stays right while the switch is off
				expect(timer.Exists("GryMod objectives positions")).to.beFalse()
				GetConVar("gry_objectives"):SetString("1")
				expect(timer.Exists("GryMod objectives positions")).to.beTrue()

				API.RemoveObjective("a")
				expect(watching()).to.beFalse()
				expect(timer.Exists("GryMod objectives positions")).to.beFalse()
			end)
		},
		{
			-- breaks if: onRemove "remove" is not the default or the Removed hook does not carry the reason "entity_removed"
			name = "the entity of an objective is removed (onRemove \"remove\", the default): the objective is removed, Removed(id, obj, \"entity_removed\")",
			func = scene(function()
				local removed = listen("GryMod_ObjectiveRemoved")
				local e = point(pos(7, 8, 9))

				API.RegisterObjective("a", {title = "Alpha", ent = e})
				API.RegisterObjective("keep", {title = "Keep", ent = point()})
				entityRemoved(e)

				expect(API.GetObjective("a")).to.beNil()
				expect(API.GetObjective("keep") ~= nil).to.beTrue()
				expect(#removed).to.equal(1)
				expect(removed[1][1]).to.equal("a")
				expect(removed[1][3]).to.equal("entity_removed")
				expect(removed[1][2].pos == pos(7, 8, 9)).to.beTrue()
			end)
		},
		{
			-- breaks if: "complete" or "fail" is not applied, the objective keeps pointing at a dead entity, or it forgets where the entity was
			name = "onRemove \"complete\" and \"fail\": the objective stays, with the state done or failed, at the last place of the entity, and follows nothing any more",
			func = scene(function()
				local changed = listen("GryMod_ObjectiveChanged")
				local removed = listen("GryMod_ObjectiveRemoved")
				local e1, e2 = point(pos(10, 0, 0)), point(pos(20, 0, 0))

				API.RegisterObjective("c", {title = "Kill it", ent = e1, onRemove = "complete"})
				API.RegisterObjective("f", {title = "Protect it", ent = e2, onRemove = "fail"})
				entityRemoved(e1)
				entityRemoved(e2)

				local c, f = API.GetObjective("c"), API.GetObjective("f")

				expect(c.state).to.equal("done")
				expect(f.state).to.equal("failed")
				expect(c.ent).to.beNil()
				expect(f.ent).to.beNil()
				expect(c.pos == pos(10, 0, 0)).to.beTrue()
				expect(f.pos == pos(20, 0, 0)).to.beTrue()
				expect(#removed).to.equal(0)
				expect(#changed).to.equal(2)
				expect(changed[1][1]).to.equal("c")
				expect(changed[1][3]).to.equal("active")
				expect(changed[2][2].state).to.equal("failed")
				-- nothing follows an entity any more: the watchers are gone
				expect(hook.GetTable().EntityRemoved == nil or hook.GetTable().EntityRemoved["GryMod objectives"] == nil).to.beTrue()
			end)
		},
		{
			-- breaks if: the hook reacts to an entity that no objective follows, or an objective is lost when another entity goes
			name = "the removal of an entity that no objective follows changes nothing",
			func = scene(function()
				local e, other = point(), point()

				API.RegisterObjective("a", {title = "Alpha", ent = e})
				entityRemoved(other)
				expect(API.GetObjective("a") ~= nil).to.beTrue()
				expect(API.GetObjective("a").state).to.equal("active")
			end)
		},
		{
			-- breaks if: the cleaning of the map counts as the death of every entity (onRemove would complete or remove everything one by one) or leaves the old objectives
			name = "a map cleanup: the entities that go during it are not an event, after it every objective is gone with the reason \"map_changed\"; the hooks are registered",
			func = scene(function()
				local removed = listen("GryMod_ObjectiveRemoved")
				local changed = listen("GryMod_ObjectiveChanged")
				local e = point()

				API.RegisterObjective("a", {title = "Alpha", ent = e, onRemove = "complete"})
				API.RegisterObjective("b", {title = "Beta", pos = pos()})

				S.OnPreCleanup()
				entityRemoved(e)
				expect(#changed).to.equal(0)
				expect(API.GetObjective("a").state).to.equal("active")

				S.OnPostCleanup()
				expect(#API.GetObjectives()).to.equal(0)
				expect(#removed).to.equal(2)
				expect(removed[1][3]).to.equal("map_changed")
				expect(removed[2][3]).to.equal("map_changed")

				-- after the cleanup the removal of an entity is an event again
				local e2 = point()
				API.RegisterObjective("c", {title = "Gamma", ent = e2, onRemove = "complete"})
				entityRemoved(e2)
				expect(API.GetObjective("c").state).to.equal("done")

				-- the engine's hooks reach these two functions
				local called = {}
				local realPre, realPost = S.OnPreCleanup, S.OnPostCleanup

				S.OnPreCleanup = function() called[#called + 1] = "pre" end
				S.OnPostCleanup = function() called[#called + 1] = "post" end

				local ok, err = pcall(function()
					hook.GetTable().PreCleanupMap["GryMod objectives"]()
					hook.GetTable().PostCleanupMap["GryMod objectives"]()
				end)

				S.OnPreCleanup, S.OnPostCleanup = realPre, realPost

				if not ok then
					error(err, 0)
				end

				expect(table.concat(called, ",")).to.equal("pre,post")
			end)
		},
		{
			-- breaks if: a client that is not ready receives something, or the full list is not BEGIN, one SET per objective, END
			name = "a client that is ready gets the full list: BEGIN, one SET for each objective with every field, END; a client that is not ready gets nothing",
			func = scene(function()
				local a, b = fakePly("a"), fakePly("b")
				local e = point(pos(5, 5, 5))

				API.RegisterObjective("one", {title = "One", description = "First", primary = false, state = "done", pos = pos(1, 2, 3), radar = false, marker = true})
				API.RegisterObjective("two", {title = "Two", ent = e})
				API.SetMainObjective("two")
				expect(#received(a)).to.equal(0)

				expect(S.Sync(a)).to.beTrue()

				local list = received(a)
				expect(table.concat(opsOf(list), ",")).to.equal(table.concat({Obj.Ops.BEGIN, Obj.Ops.SET, Obj.Ops.SET, Obj.Ops.END}, ","))
				expect(list[2].id).to.equal("one")
				expect(list[2].title).to.equal("One")
				expect(list[2].description).to.equal("First")
				expect(list[2].primary).to.beFalse()
				expect(list[2].state).to.equal("done")
				expect(list[2].main).to.beFalse()
				expect(list[2].radar).to.beFalse()
				expect(list[2].marker).to.beTrue()
				expect(list[2].pos == pos(1, 2, 3)).to.beTrue()
				expect(list[2].entIndex).to.equal(0)
				expect(list[3].id).to.equal("two")
				expect(list[3].main).to.beTrue()
				expect(list[3].entIndex).to.equal(e:EntIndex())
				expect(list[3].pos == pos(5, 5, 5)).to.beTrue()
				expect(#received(b)).to.equal(0)
			end)
		},
		{
			-- breaks if: the answer to "client ready" (GryMod.AnswerReady) does not send the objectives, or sends them when the server has none (an empty list is no message)
			name = "GryMod.AnswerReady (the answer to a client that says it is ready) also sends the objectives, once a second at most; with no objective it sends none",
			func = scene(function()
				local a = fakePly("a")

				expect(GryMod.AnswerReady(a)).to.beTrue()
				expect(ofGryObjectives()).to.equal(0)

				local b = fakePly("b")
				API.RegisterObjective("one", {title = "One", pos = pos()})
				expect(GryMod.AnswerReady(b)).to.beTrue()
				expect(table.concat(opsOf(received(b)), ",")).to.equal(table.concat({Obj.Ops.BEGIN, Obj.Ops.SET, Obj.Ops.END}, ","))

				-- a second answer inside the interval is refused, and nothing more is sent
				local before = #received(b)
				expect(GryMod.AnswerReady(b)).to.beFalse()
				expect(#received(b)).to.equal(before)

				-- the player a, who was ready first (its answer marked it ready), got the new objective as a delta, and gets the next change too
				expect(table.concat(opsOf(received(a)), ",")).to.equal(tostring(Obj.Ops.SET))
				API.SetObjectiveState("one", "done")
				expect(table.concat(opsOf(received(a)), ",")).to.equal(table.concat({Obj.Ops.SET, Obj.Ops.SET}, ","))
			end)
		},
		{
			-- breaks if: a change is not sent as it happens, or the clients are not told of a removal, a clear or a new main objective
			name = "the changes go to the ready clients as they happen: SET (new, state), REMOVE with the reason, CLEAR with the reason, MAIN",
			func = scene(function()
				local a = fakePly("a")

				S.Sync(a)

				API.RegisterObjective("one", {title = "One", pos = pos()})
				API.RegisterObjective("two", {title = "Two", pos = pos()})
				API.SetObjectiveState("one", "failed")
				API.SetMainObjective("two")
				API.RemoveObjective("one")
				API.ClearObjectives()

				local list = received(a)

				expect(table.concat(opsOf(list), ",")).to.equal(table.concat({
					Obj.Ops.SET, Obj.Ops.SET, Obj.Ops.SET, Obj.Ops.MAIN, Obj.Ops.REMOVE, Obj.Ops.CLEAR
				}, ","))
				expect(list[1].id).to.equal("one")
				expect(list[3].state).to.equal("failed")
				expect(list[4].id).to.equal("two")
				expect(list[5].id).to.equal("one")
				expect(list[5].reason).to.equal("removed")
				expect(list[6].reason).to.equal("cleared")
			end)
		},
		{
			-- breaks if: the main objective is announced to a player who cannot see it, or a player who can does not get it
			name = "SetMainObjective with nil tells the clients \"no main objective\" (an empty id)",
			func = scene(function()
				local a = fakePly("a")

				API.RegisterObjective("one", {title = "One", pos = pos()})
				S.Sync(a)
				sent = {}

				API.SetMainObjective("one")
				API.SetMainObjective(nil)

				local list = received(a)
				expect(#list).to.equal(2)
				expect(list[1].op).to.equal(Obj.Ops.MAIN)
				expect(list[1].id).to.equal("one")
				expect(list[2].id).to.equal("")
			end)
		},
		{
			-- breaks if: the filter is not evaluated on the server (every player gets everything), is evaluated once for everybody, or an error in it hides nothing
			name = "filter(ply): a player only receives the objectives he may see, in the full list and in the deltas; a filter that throws hides the objective",
			func = scene(function()
				local a, b = fakePly("a"), fakePly("b")
				local realMsgN = MsgN

				MsgN = function() end

				local ok, err = pcall(function()
					S.Sync(a)
					S.Sync(b)

					API.RegisterObjective("only_a", {title = "A only", pos = pos(), filter = function(ply) return ply == a end})
					API.RegisterObjective("all", {title = "All", pos = pos()})
					API.RegisterObjective("broken", {title = "Broken", pos = pos(), filter = function() error("boom") end})

					local ids = function(list)
						local out = {}

						for _, m in ipairs(list) do
							if m.op == Obj.Ops.SET then
								out[#out + 1] = m.id
							end
						end

						return table.concat(out, ",")
					end

					expect(ids(received(a))).to.equal("only_a,all")
					expect(ids(received(b))).to.equal("all")

					-- a player who is ready later gets the same rule in the full list
					local c = fakePly("c")
					S.Sync(c)
					expect(ids(received(c))).to.equal("all")

					-- the state of an objective that b may not see is not sent to b; the removal is not sent to b either
					sent = {}
					API.SetObjectiveState("only_a", "done")
					API.RemoveObjective("only_a")
					expect(#received(a)).to.equal(2)
					expect(#received(b)).to.equal(0)
					expect(API.GetObjective("only_a")).to.beNil()
				end)

				MsgN = realMsgN

				if not ok then
					error(err, 0)
				end
			end)
		},
		{
			-- breaks if: RefreshObjectives does not re-evaluate the filters (a player whose rights changed would see the old list for ever)
			name = "RefreshObjectives(ply) asks the filters again and sends the list again: what the player may now see arrives, what he may not any more goes away",
			func = scene(function()
				local a = fakePly("a")
				local allowed = false

				S.Sync(a)
				API.RegisterObjective("gated", {title = "Gated", pos = pos(), filter = function() return allowed end})
				expect(#received(a)).to.equal(0)

				allowed = true
				expect(API.RefreshObjectives(a)).to.beTrue()

				local list = received(a)
				expect(table.concat(opsOf(list), ",")).to.equal(table.concat({Obj.Ops.BEGIN, Obj.Ops.SET, Obj.Ops.END}, ","))

				-- a player the server has not heard from is refused
				local ok, reason = API.RefreshObjectives(fakePly("stranger"))
				expect(ok).to.beFalse()
				expect(isstring(reason)).to.beTrue()
			end)
		},
		{
			-- breaks if: a small move is sent (the client would be flooded), a big one is not, or the position the clients know is not updated
			name = "the position of an entity objective is sent only after it moved more than 32 units, and only to the players who see the objective",
			func = scene(function()
				local a, b = fakePly("a"), fakePly("b")
				local e = point(pos(0, 0, 0))

				S.Sync(a)
				S.Sync(b)
				API.RegisterObjective("follow", {title = "Follow", ent = e, filter = function(ply) return ply == a end})
				sent = {}

				S.RefreshPositions()
				expect(ofGryObjectives()).to.equal(0)

				e:SetPos(pos(20, 0, 0))
				S.RefreshPositions()
				expect(ofGryObjectives()).to.equal(0)

				e:SetPos(pos(40, 0, 0))
				S.RefreshPositions()

				local list = received(a)
				expect(#list).to.equal(1)
				expect(list[1].op).to.equal(Obj.Ops.POS)
				expect(#list[1].list).to.equal(1)
				expect(list[1].list[1].id).to.equal("follow")
				expect(list[1].list[1].pos == pos(40, 0, 0)).to.beTrue()
				expect(#received(b)).to.equal(0)

				-- the next step is counted from the last position sent
				e:SetPos(pos(60, 0, 0))
				S.RefreshPositions()
				expect(#received(a)).to.equal(1)
				e:SetPos(pos(75, 0, 0))
				S.RefreshPositions()
				expect(#received(a)).to.equal(2)
			end)
		},
		{
			-- breaks if: a function for ent that gives another entity later keeps the old one on the clients
			name = "an objective whose ent function gives another entity later follows the new one and the clients get a new SET (the index of the entity changed)",
			func = scene(function()
				local a = fakePly("a")
				local e1, e2 = point(pos(0, 0, 0)), point(pos(500, 0, 0))
				local current = e1

				S.Sync(a)
				API.RegisterObjective("follow", {title = "Follow", ent = function() return current end})
				expect(API.GetObjective("follow").ent == e1).to.beTrue()
				sent = {}

				current = e2
				S.RefreshPositions()

				expect(API.GetObjective("follow").ent == e2).to.beTrue()

				local list = received(a)
				expect(#list).to.equal(1)
				expect(list[1].op).to.equal(Obj.Ops.SET)
				expect(list[1].entIndex).to.equal(e2:EntIndex())
			end)
		},
		{
			-- breaks if: the full list carries an old position of an entity that moved while no timer ran (the switch was off)
			name = "the full list carries the position of the entity now",
			func = scene(function()
				local a = fakePly("a")
				local e = point(pos(0, 0, 0))

				API.RegisterObjective("follow", {title = "Follow", ent = e})
				e:SetPos(pos(300, 0, 0))
				S.Sync(a)

				expect(received(a)[2].pos == pos(300, 0, 0)).to.beTrue()
			end)
		},
		{
			-- breaks if: the switch off still sends or fires, the API stops answering, or the objectives are lost by the switch
			name = "gry_objectives 0: the API still answers and keeps the objectives, but nothing is sent and no hook is told",
			func = scene(function()
				local a = fakePly("a")
				local added = listen("GryMod_ObjectiveAdded")
				local changed = listen("GryMod_ObjectiveChanged")
				local removed = listen("GryMod_ObjectiveRemoved")

				S.Sync(a)
				GetConVar("gry_objectives"):SetString("0")
				sent = {}

				expect(API.RegisterObjective("one", {title = "One", pos = pos()})).to.beTrue()
				expect(API.SetObjectiveState("one", "done")).to.beTrue()
				expect(API.SetMainObjective("one")).to.beTrue()
				expect(API.GetObjective("one").state).to.equal("done")
				expect(API.RegisterObjective("two", {title = "Two", pos = pos()})).to.beTrue()
				expect(API.RemoveObjective("two")).to.beTrue()

				expect(ofGryObjectives()).to.equal(0)
				expect(#added).to.equal(0)
				expect(#changed).to.equal(0)
				expect(#removed).to.equal(0)

				-- a client that becomes ready now gets nothing either
				S.Sync(fakePly("late"))
				expect(ofGryObjectives()).to.equal(0)
			end)
		},
		{
			-- breaks if: the switch is not wired to the change callback: the clients keep an objective list the administrators turned off, or never get it back
			name = "turning gry_objectives off tells the ready clients to drop everything (CLEAR \"cleared\"); turning it on sends them the full list again",
			func = scene(function()
				local a = fakePly("a")

				API.RegisterObjective("one", {title = "One", pos = pos()})
				S.Sync(a)
				sent = {}

				GetConVar("gry_objectives"):SetString("0")
				local list = received(a)
				expect(#list).to.equal(1)
				expect(list[1].op).to.equal(Obj.Ops.CLEAR)
				expect(list[1].reason).to.equal("cleared")
				expect(#API.GetObjectives()).to.equal(1)

				sent = {}
				GetConVar("gry_objectives"):SetString("1")
				expect(table.concat(opsOf(received(a)), ",")).to.equal(table.concat({Obj.Ops.BEGIN, Obj.Ops.SET, Obj.Ops.END}, ","))
			end)
		},
		{
			-- breaks if: a player who left stays in the list of the ready players (the server would keep sending to a name that is gone)
			name = "a player who leaves is forgotten: nothing is sent to him any more",
			func = scene(function()
				local a = fakePly("a")

				S.Sync(a)
				hook.GetTable().PlayerDisconnected["GryMod objectives"](a)
				sent = {}
				API.RegisterObjective("one", {title = "One", pos = pos()})
				expect(#received(a)).to.equal(0)
			end)
		}
	}
}
