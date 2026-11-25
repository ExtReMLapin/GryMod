-- Tests of the objectives on the CLIENT (lua/grymod/client/cl_objectives.lua), GLuaTest format, client realm: the mirror of what the server sends, the read API
-- (GryMod.Objectives.List, Get, Main: the position is resolved when asked and follows the entity when the client has it) and the reporting hooks
-- GryMod_ObjectiveAdded / Changed / Removed told from the messages. The messages are given to the reader through a queue (the writer of the shared file
-- fills it), so what the server writes and what the client reads are checked together. The real network is never used; the real player is only read.
-- Each case names the production change whose absence makes it fail.

local Obj

local madeHooks = {}
local lines
local realMsgN
local bannerSetting, bannerBefore

-- the calls an event got
local function listen(event)
	local calls = {}
	local id = "gry_cl_objectives_test_" .. event .. "_" .. #madeHooks

	hook.Add(event, id, function(...)
		calls[#calls + 1] = {...}
	end)
	madeHooks[#madeHooks + 1] = {event, id}

	return calls
end

-- a record as the server sends it
local function rec(id, extra)
	local r = {id = id, title = "Title " .. id, description = "", primary = true, state = "active", main = false, radar = true, marker = true,
		pos = Vector(1, 2, 3), entIndex = 0}

	for k, v in pairs(extra or {}) do
		r[k] = v
	end

	return r
end

-- Gives `Obj.Receive` the message the server would send: `writer` writes it with the real writers of the shared file (net functions replaced by a recorder), then
-- the readers return what was written, in order. Everything is put back in a pcall.
local function receive(writer)
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
		assert(item ~= nil and item[1] == kind, "the reader asks for a " .. kind .. " where the server wrote " .. tostring(item and item[1]))

		if bits then
			assert(item[3] == bits, "the reader reads " .. bits .. " bits where the server wrote " .. tostring(item[3]))
		end

		return item[2]
	end

	net.ReadString = function() return pop("string") end
	net.ReadUInt = function(bits) return pop("uint", bits) end
	net.ReadBool = function() return pop("bool") end
	net.ReadVector = function() return pop("vector") end

	local ok, err = pcall(function()
		writer()
		Obj.Receive()
	end)

	for n, f in pairs(real) do
		net[n] = f
	end

	if not ok then
		error(err, 0)
	end
end

local function opStart(op)
	net.WriteUInt(op, Obj.OpBits)
end

return {
	groupName = "GryMod objectives (client)",
	beforeEach = function()
		Obj = GryMod.Objectives
		madeHooks = {}
		lines = {}
		realMsgN = MsgN
		MsgN = function(...)
			lines[#lines + 1] = table.concat({...}, "")
		end
		-- the objective banner (cl_objectives_banner.lua) listens to the same hooks: it must not show a line and play a sound for every test objective
		bannerSetting = GetConVar("gry_msg_objectives")
		bannerBefore = bannerSetting and bannerSetting:GetString()

		if bannerSetting then
			bannerSetting:SetString("0")
		end

		Obj.Reset()
	end,
	afterEach = function()
		pcall(function()
			for _, h in ipairs(madeHooks) do
				hook.Remove(h[1], h[2])
			end

			Obj.Reset()
		end)

		MsgN = realMsgN
		pcall(function()
			if bannerSetting and bannerBefore then
				bannerSetting:SetString(bannerBefore)
			end
		end)
	end,
	cases = {
		{
			-- breaks if: cl_objectives.lua is not loaded (grymod_shared.lua) or a function of the read API is missing
			name = "the read API and the receiver of gry_objectives exist",
			func = function()
				for _, name in ipairs({"List", "Get", "Main", "Receive", "ApplySet", "ApplyRemove", "ApplyClear", "ApplyMain", "ApplyPositions"}) do
					expect(isfunction(Obj[name])).to.beTrue()
				end

				expect(net.Receivers["gry_objectives"] ~= nil).to.beTrue()
				expect(#Obj.List()).to.equal(0)
				expect(Obj.Get("nope")).to.beNil()
				expect(Obj.Main()).to.beNil()
			end
		},
		{
			-- breaks if: the mirror does not keep a field of the record, or List / Get answer something else than the documented fields
			name = "a SET of a new objective: List and Get give it with every field, Added(id, obj) is told once",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")

				Obj.ApplySet(rec("a", {title = "Alpha", description = "First", primary = false, state = "done", radar = false, marker = true, pos = Vector(5, 6, 7)}))

				local list = Obj.List()
				expect(#list).to.equal(1)

				local o = Obj.Get("a")
				expect(o == list[1]).to.beTrue()
				expect(o.id).to.equal("a")
				expect(o.title).to.equal("Alpha")
				expect(o.description).to.equal("First")
				expect(o.primary).to.beFalse()
				expect(o.main).to.beFalse()
				expect(o.state).to.equal("done")
				expect(o.radar).to.beFalse()
				expect(o.marker).to.beTrue()
				expect(o.pos == Vector(5, 6, 7)).to.beTrue()
				expect(o.ent).to.beNil()

				expect(#added).to.equal(1)
				expect(added[1][1]).to.equal("a")
				expect(added[1][2].title).to.equal("Alpha")
				expect(added[1][2].state).to.equal("done")
				expect(added[1][2] ~= o).to.beTrue() -- a copy, not the mirror's own table
			end
		},
		{
			-- breaks if: List builds new tables at every call (the displays call it every frame: a garbage collector cost for nothing)
			name = "List gives the same array and the same objective tables at every call, in the order they came",
			func = function()
				Obj.ApplySet(rec("a"))
				Obj.ApplySet(rec("b"))

				local first = Obj.List()
				local second = Obj.List()

				expect(first == second).to.beTrue()
				expect(first[1].id).to.equal("a")
				expect(first[2].id).to.equal("b")
				expect(Obj.Get("a") == first[1]).to.beTrue()

				Obj.ApplyRemove("a", "removed")
				expect(#Obj.List()).to.equal(1)
				expect(Obj.List()[1].id).to.equal("b")
			end
		},
		{
			-- breaks if: a SET of a known id is told as Added again, or Changed is told for a change of position only, or lacks the old state
			name = "a SET of a known objective: Changed(id, obj, oldState) for a state, title, description or primary change; nothing for a new position",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")
				local changed = listen("GryMod_ObjectiveChanged")

				Obj.ApplySet(rec("a"))
				Obj.ApplySet(rec("a", {pos = Vector(100, 0, 0)}))
				expect(#added).to.equal(1)
				expect(#changed).to.equal(0)
				expect(Obj.Get("a").pos == Vector(100, 0, 0)).to.beTrue()

				Obj.ApplySet(rec("a", {state = "failed"}))
				expect(#changed).to.equal(1)
				expect(changed[1][1]).to.equal("a")
				expect(changed[1][2].state).to.equal("failed")
				expect(changed[1][3]).to.equal("active")

				Obj.ApplySet(rec("a", {state = "failed", title = "New title"}))
				expect(#changed).to.equal(2)
				expect(changed[2][3]).to.equal("failed")
				Obj.ApplySet(rec("a", {state = "failed", title = "New title", description = "More"}))
				expect(#changed).to.equal(3)
				Obj.ApplySet(rec("a", {state = "failed", title = "New title", description = "More", primary = false}))
				expect(#changed).to.equal(4)
				expect(#added).to.equal(1)
			end
		},
		{
			-- breaks if: two objectives can be main, Main() answers a stale one, or the objective that lost the flag is not told
			name = "the main objective: a SET with main moves the flag (Changed for the one that lost it), MAIN sets or clears it, an unknown id clears it",
			func = function()
				local changed = listen("GryMod_ObjectiveChanged")

				Obj.ApplySet(rec("a", {main = true}))
				Obj.ApplySet(rec("b"))
				expect(Obj.Main().id).to.equal("a")
				expect(Obj.Get("a").main).to.beTrue()
				expect(Obj.Get("b").main).to.beFalse()

				Obj.ApplySet(rec("b", {main = true}))
				expect(Obj.Main().id).to.equal("b")
				expect(Obj.Get("a").main).to.beFalse()
				expect(#changed >= 2).to.beTrue()

				local ids = {}
				for _, c in ipairs(changed) do
					ids[#ids + 1] = c[1] .. "=" .. tostring(c[2].main)
				end

				expect(table.concat(ids, ",")).to.equal("b=true,a=false")

				changed = listen("GryMod_ObjectiveChanged")
				Obj.ApplyMain("a")
				expect(Obj.Main().id).to.equal("a")
				expect(Obj.Get("b").main).to.beFalse()
				expect(#changed).to.equal(2)
				expect(changed[1][1]).to.equal("b")
				expect(changed[2][1]).to.equal("a")

				Obj.ApplyMain("")
				expect(Obj.Main()).to.beNil()
				expect(Obj.Get("a").main).to.beFalse()

				Obj.ApplyMain("a")
				Obj.ApplyMain("ghost")
				expect(Obj.Main()).to.beNil()

				-- a SET that takes the flag away from the main objective
				Obj.ApplyMain("a")
				Obj.ApplySet(rec("a", {main = false}))
				expect(Obj.Main()).to.beNil()
			end
		},
		{
			-- breaks if: the objective stays in the list after REMOVE, Removed lacks the reason or the last values, or the main flag outlives it
			name = "REMOVE: the objective is gone, Removed(id, obj, reason) tells why, the main objective is forgotten, an unknown id changes nothing",
			func = function()
				local removed = listen("GryMod_ObjectiveRemoved")

				Obj.ApplySet(rec("a", {title = "Alpha", main = true}))
				Obj.ApplySet(rec("b"))

				Obj.ApplyRemove("ghost", "removed")
				expect(#removed).to.equal(0)

				Obj.ApplyRemove("a", "entity_removed")
				expect(#removed).to.equal(1)
				expect(removed[1][1]).to.equal("a")
				expect(removed[1][2].title).to.equal("Alpha")
				expect(removed[1][3]).to.equal("entity_removed")
				expect(Obj.Get("a")).to.beNil()
				expect(Obj.Main()).to.beNil()
				expect(#Obj.List()).to.equal(1)
			end
		},
		{
			-- breaks if: CLEAR keeps one, tells nothing for some, or the reason is lost
			name = "CLEAR: every objective is gone and Removed is told for each with the reason",
			func = function()
				local removed = listen("GryMod_ObjectiveRemoved")

				Obj.ApplySet(rec("a", {main = true}))
				Obj.ApplySet(rec("b"))
				Obj.ApplyClear("map_changed")

				expect(#Obj.List()).to.equal(0)
				expect(Obj.Main()).to.beNil()
				expect(#removed).to.equal(2)
				expect(removed[1][3]).to.equal("map_changed")
				expect(removed[2][3]).to.equal("map_changed")
				expect(removed[1][1]).to.equal("a")
				expect(removed[2][1]).to.equal("b")
			end
		},
		{
			-- breaks if: END does not drop what the full list did not mention, drops what it did mention, or tells Added again for a known objective
			name = "a full list (BEGIN, SETs, END): what it did not mention is removed (\"removed\"), what it did stays without a new Added",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")
				local removed = listen("GryMod_ObjectiveRemoved")

				Obj.ApplySet(rec("keep"))
				Obj.ApplySet(rec("gone"))
				expect(#added).to.equal(2)

				Obj.ApplyBegin()
				Obj.ApplySet(rec("keep", {title = "Kept"}))
				Obj.ApplySet(rec("new"))
				Obj.ApplyEnd()

				expect(#Obj.List()).to.equal(2)
				expect(Obj.Get("gone")).to.beNil()
				expect(Obj.Get("keep").title).to.equal("Kept")
				expect(Obj.Get("new") ~= nil).to.beTrue()
				expect(#added).to.equal(3)
				expect(#removed).to.equal(1)
				expect(removed[1][1]).to.equal("gone")
				expect(removed[1][3]).to.equal("removed")

				-- an END with no BEGIN drops nothing
				Obj.ApplyEnd()
				expect(#Obj.List()).to.equal(2)
			end
		},
		{
			-- breaks if: the objective's pos is the server's even when the client has the entity (it would show an old place), or ent is not given
			name = "an objective that follows an entity the client has: pos is the entity's position now and ent is the entity",
			func = function()
				local me = LocalPlayer()

				expect(IsValid(me)).to.beTrue()
				Obj.ApplySet(rec("follow", {pos = Vector(99999, 99999, 99999), entIndex = me:EntIndex()}))

				local o = Obj.Get("follow")
				expect(o.ent == me).to.beTrue()
				expect(o.pos == me:GetPos()).to.beTrue()
				expect(Obj.List()[1].pos == me:GetPos()).to.beTrue()
			end
		},
		{
			-- breaks if: an entity the client does not have (out of its view, or an index that is nothing) makes pos nil or an error, or the sent position is ignored
			name = "an objective that follows an entity the client does not have: pos is the one the server sent, and a POS message moves it",
			func = function()
				local noEntity = 8000 -- nothing lives there in a test map

				Obj.ApplySet(rec("far", {pos = Vector(10, 20, 30), entIndex = noEntity}))
				Obj.ApplySet(rec("fixed", {pos = Vector(1, 1, 1)}))

				local o = Obj.Get("far")
				expect(o.ent).to.beNil()
				expect(o.pos == Vector(10, 20, 30)).to.beTrue()

				Obj.ApplyPositions({{id = "far", pos = Vector(50, 60, 70)}, {id = "ghost", pos = Vector(0, 0, 0)}})
				expect(Obj.Get("far").pos == Vector(50, 60, 70)).to.beTrue()
				expect(Obj.Get("fixed").pos == Vector(1, 1, 1)).to.beTrue()
			end
		},
		{
			-- breaks if: the mirror hands out its own Vector in a hook (a listener that changes it would move the objective)
			name = "the objective of a hook is a copy: changing it changes nothing in the mirror",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")

				Obj.ApplySet(rec("a", {pos = Vector(1, 2, 3)}))
				added[1][2].pos.x = 500
				added[1][2].title = "hacked"

				expect(Obj.Get("a").pos.x).to.equal(1)
				expect(Obj.Get("a").title).to.equal("Title a")
			end
		},
		{
			-- breaks if: a listener that throws breaks the mirror (the message half applied) or the returned value of a listener is read
			name = "a listener that throws or returns something changes nothing: the objective is in the mirror",
			func = function()
				hook.Add("GryMod_ObjectiveAdded", "gry_cl_objectives_test_throws", function() error("boom") end)
				madeHooks[#madeHooks + 1] = {"GryMod_ObjectiveAdded", "gry_cl_objectives_test_throws"}
				hook.Add("GryMod_ObjectiveChanged", "gry_cl_objectives_test_returns", function() return true end)
				madeHooks[#madeHooks + 1] = {"GryMod_ObjectiveChanged", "gry_cl_objectives_test_returns"}

				expect(function() Obj.ApplySet(rec("a")) end).to.succeed()
				expect(Obj.Get("a") ~= nil).to.beTrue()
				expect(function() Obj.ApplySet(rec("a", {state = "done"})) end).to.succeed()
				expect(Obj.Get("a").state).to.equal("done")
			end
		},
		{
			-- breaks if: the receiver does not read what the writer of the server writes, in the same order and widths
			name = "Receive: a SET message the shared writer made gives an Added; a REMOVE gives a Removed with the reason; a CLEAR, MAIN and POS are applied",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")
				local removed = listen("GryMod_ObjectiveRemoved")

				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("a", {title = "Alpha", pos = Vector(4, 5, 6)}))
				end)
				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("b", {main = false}))
				end)

				expect(#added).to.equal(2)
				expect(Obj.Get("a").title).to.equal("Alpha")
				expect(Obj.Get("a").pos == Vector(4, 5, 6)).to.beTrue()

				receive(function()
					opStart(Obj.Ops.MAIN)
					net.WriteString("b")
				end)
				expect(Obj.Main().id).to.equal("b")

				receive(function()
					opStart(Obj.Ops.POS)
					net.WriteUInt(1, Obj.CountBits)
					net.WriteString("a")
					net.WriteVector(Vector(7, 8, 9))
				end)
				expect(Obj.Get("a").pos == Vector(7, 8, 9)).to.beTrue()

				receive(function()
					opStart(Obj.Ops.REMOVE)
					net.WriteString("a")
					net.WriteUInt(Obj.ReasonIds[Obj.Reasons.ENTITY_REMOVED], Obj.ReasonBits)
				end)
				expect(#removed).to.equal(1)
				expect(removed[1][1]).to.equal("a")
				expect(removed[1][3]).to.equal("entity_removed")

				receive(function()
					opStart(Obj.Ops.CLEAR)
					net.WriteUInt(Obj.ReasonIds[Obj.Reasons.CLEARED], Obj.ReasonBits)
				end)
				expect(#Obj.List()).to.equal(0)
				expect(removed[2][3]).to.equal("cleared")

				-- BEGIN, a SET, END
				receive(function() opStart(Obj.Ops.BEGIN) end)
				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("c"))
				end)
				receive(function() opStart(Obj.Ops.END) end)
				expect(#Obj.List()).to.equal(1)
			end
		},
		{
			-- breaks if: a record that breaks the bounds (a title that is too long) is trusted
			name = "Receive: a SET that breaks the bounds is dropped, with no hook and no error",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")

				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("a", {title = string.rep("x", Obj.Limits.title + 1)}))
				end)

				expect(#Obj.List()).to.equal(0)
				expect(#added).to.equal(0)
			end
		},
		{
			-- breaks if: Obj.Syncing is missing or does not follow BEGIN / END: the objective banner needs it to stay silent for the list sent when the player joins
			name = "Syncing: true from BEGIN to END (a full list is arriving), false otherwise, and the hooks run while it is true",
			func = function()
				local seen = {}

				hook.Add("GryMod_ObjectiveAdded", "gry_cl_objectives_test_syncing", function(id)
					seen[#seen + 1] = {id, Obj.Syncing()}
				end)
				madeHooks[#madeHooks + 1] = {"GryMod_ObjectiveAdded", "gry_cl_objectives_test_syncing"}

				expect(Obj.Syncing()).to.beFalse()
				Obj.ApplySet(rec("live"))
				Obj.ApplyBegin()
				expect(Obj.Syncing()).to.beTrue()
				Obj.ApplySet(rec("listed"))
				Obj.ApplyEnd()
				expect(Obj.Syncing()).to.beFalse()
				Obj.ApplySet(rec("live2"))

				expect(seen[1][1]).to.equal("live")
				expect(seen[1][2]).to.beFalse()
				expect(seen[2][1]).to.equal("listed")
				expect(seen[2][2]).to.beTrue()
				expect(seen[3][1]).to.equal("live2")
				expect(seen[3][2]).to.beFalse()
			end
		},
		{
			-- breaks if: an operation the client does not know raises an error (a newer server, an older client)
			name = "Receive: an operation it does not know is ignored",
			func = function()
				expect(function()
					receive(function() net.WriteUInt(7, Obj.OpBits) end)
				end).to.succeed()
			end
		},
		{
			-- breaks if: the mirror does not keep the waypoints of the record, or the list gives none for an objective that has none, or the hook's copy shares the mirror's table
			name = "via: the waypoints of a record are in List() and Get() as an array of Vectors, nil when there are none; the hook's copy is its own",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")

				Obj.ApplySet(rec("with", {via = {Vector(1, 2, 3), Vector(4, 5, 6)}}))
				Obj.ApplySet(rec("without"))

				local list = Obj.List()

				expect(#list[1].via).to.equal(2)
				expect(list[1].via[2] == Vector(4, 5, 6)).to.beTrue()
				expect(list[2].via).to.beNil()
				expect(#Obj.Get("with").via).to.equal(2)

				-- the copy given to the hooks can be changed without changing the mirror
				added[1][2].via[1].x = 99
				expect(Obj.Get("with").via[1].x).to.equal(1)

				-- a new SET without waypoints takes them away
				Obj.ApplySet(rec("with"))
				expect(Obj.Get("with").via).to.beNil()
			end
		},
		{
			-- breaks if: ApplyOwn does not exist, the objective is not in List() and Get() marked own, or its hook (the radar, the markers and the big map follow it) is not told
			name = "own objectives: ApplyOwn puts a private objective in the list marked own, tells GryMod_ObjectiveAdded (the copy is marked too), and RemoveOwn takes it away and tells Removed",
			func = function()
				local added = listen("GryMod_ObjectiveAdded")
				local removed = listen("GryMod_ObjectiveRemoved")

				Obj.ApplyOwn(rec("gry_user_1", {primary = false}))

				expect(#Obj.List()).to.equal(1)
				expect(Obj.List()[1].own).to.beTrue()
				expect(Obj.Get("gry_user_1").own).to.beTrue()
				expect(Obj.List()[1].pos == Vector(1, 2, 3)).to.beTrue()
				expect(#added).to.equal(1)
				expect(added[1][2].own).to.beTrue()

				expect(Obj.RemoveOwn("gry_user_1")).to.beTrue()
				expect(#Obj.List()).to.equal(0)
				expect(#removed).to.equal(1)
				expect(removed[1][2].own).to.beTrue()

				-- a second time, and an id that is not there: nothing to remove
				expect(Obj.RemoveOwn("gry_user_1")).to.beFalse()
			end
		},
		{
			-- breaks if: a full list from the server (the one sent when the player joins, which removes what it does not mention) or a CLEAR takes the player's own points away
			name = "own objectives: the full list of the server and a CLEAR leave them alone, a server objective next to them still goes",
			func = function()
				Obj.ApplyOwn(rec("gry_user_1"))
				Obj.ApplySet(rec("mission"))

				-- Receive reads one message: the full list is three of them
				receive(function() opStart(Obj.Ops.BEGIN) end)
				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("other"))
				end)
				receive(function() opStart(Obj.Ops.END) end)

				expect(Obj.Get("gry_user_1") ~= nil).to.beTrue()
				expect(Obj.Get("mission")).to.beNil()
				expect(Obj.Get("other") ~= nil).to.beTrue()

				receive(function()
					opStart(Obj.Ops.CLEAR)
					net.WriteUInt(Obj.ReasonIds[Obj.Reasons.CLEARED], Obj.ReasonBits)
				end)

				expect(Obj.Get("gry_user_1") ~= nil).to.beTrue()
				expect(Obj.Get("other")).to.beNil()
				expect(#Obj.List()).to.equal(1)
			end
		},
		{
			-- breaks if: the server can overwrite, remove, or make main an objective that only this player owns (the server never knows them: an id of its own that
			-- collides with one must not touch the player's point)
			name = "own objectives: a SET, a REMOVE or a MAIN from the server with the id of an own objective changes nothing; RemoveOwn does not remove a server objective",
			func = function()
				Obj.ApplyOwn(rec("gry_user_1", {title = "Mine"}))
				Obj.ApplySet(rec("mission"))

				receive(function()
					opStart(Obj.Ops.SET)
					Obj.WriteRecord(rec("gry_user_1", {title = "Theirs", main = true}))
				end)

				expect(Obj.Get("gry_user_1").title).to.equal("Mine")
				expect(Obj.Get("gry_user_1").main).to.beFalse()

				receive(function()
					opStart(Obj.Ops.REMOVE)
					net.WriteString("gry_user_1")
					net.WriteUInt(Obj.ReasonIds[Obj.Reasons.REMOVED], Obj.ReasonBits)
				end)

				expect(Obj.Get("gry_user_1") ~= nil).to.beTrue()

				receive(function()
					opStart(Obj.Ops.MAIN)
					net.WriteString("gry_user_1")
				end)

				expect(Obj.Main()).to.beNil()
				expect(Obj.RemoveOwn("mission")).to.beFalse()
				expect(Obj.Get("mission") ~= nil).to.beTrue()
			end
		}
	}
}
