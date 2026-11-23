-- The objectives, SERVER side: the registry, the API (GryMod.API.RegisterObjective and the others, docs/api.md "Objectives"), the reporting hooks, the
-- network and the objectives that follow an entity. Nothing here draws: the displays (markers, radar, map) read the client's mirror (client/cl_objectives.lua).
--
-- The server keeps the truth. A client gets, in ONE message (gry_objectives, operations in sh_objectives.lua):
--   * the full list when it says it is ready (GryMod.AnswerReady is wrapped below): BEGIN, one SET for each objective it may see, END;
--   * then the changes as they happen: SET, REMOVE, CLEAR, MAIN, POS.
-- `filter(ply)` is asked here, so a player only receives what he may see.
-- Cost: nothing runs by itself. An objective that follows an entity adds a hook on EntityRemoved and a timer (twice a second) for as long as at least one
-- exists; the timer sends a new position only when the entity moved more than 32 units, because the client may not have the entity (out of its view).
-- The switch gry_objectives (the administrators' setting) turns the network and the reporting hooks off; the API keeps answering and keeps the objectives.

util.AddNetworkString("gry_objectives")

GryMod = GryMod or {}

local API = GryMod.API
local Obj = GryMod.Objectives

if not API or not Obj then
	return -- sh_api.lua and sh_objectives.lua are included first (grymod_shared.lua)
end

local S = GryMod.ObjectivesServer or {}
GryMod.ObjectivesServer = S

local NAME = "gry_objectives"
local HOOK_ID = "GryMod objectives"
local TIMER_ID = "GryMod objectives positions"
local POSITION_INTERVAL = 0.5 -- seconds
local MOVE_SQR = Obj.MoveDistance * Obj.MoveDistance
local Ops, Reasons, States, Limits = Obj.Ops, Obj.Reasons, Obj.States, Obj.Limits

local switch = CreateConVar("gry_objectives", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"1: the objectives are sent to the clients and told to the other addons; 0: the API keeps the objectives but nothing is sent", 0, 1)

-- The objectives by id, and the ids in the order of registration (they live through a reload of this file).
local items = S.items or {}
local order = S.order or {}
S.items, S.order = items, order

-- The players that said they are ready, and what each of them has been sent: seen[ply][id] = true. Weak: a player who left is forgotten.
local ready = S.ready or setmetatable({}, {__mode = "k"})
local seen = S.seen or setmetatable({}, {__mode = "k"})
S.ready, S.seen = ready, seen

local cleaning = false -- the map is being cleaned up: the entities that go are not an event

local function enabled()
	return switch:GetBool()
end

S.Enabled = enabled

-- ---------------------------------------------------------------------------------------------------------
-- What an objective is now
-- ---------------------------------------------------------------------------------------------------------

-- The entity it follows, when it is still there.
local function liveEnt(o)
	local e = o.ent

	if e ~= nil and IsValid(e) then
		return e
	end

	return nil
end

local function isBound(o)
	return o.ent ~= nil or o.entFn ~= nil
end

local function currentPos(o)
	local e = liveEnt(o)

	if e then
		return e:GetPos()
	end

	return o.pos
end

-- A copy of the waypoints (nil when there are none): nothing in a snapshot is the registry's own.
local function copyVia(via)
	if not via then
		return nil
	end

	local out = {}

	for i, v in ipairs(via) do
		out[i] = Vector(v)
	end

	return out
end

-- The copy that goes to the listeners of the hooks and to the readers of the API: nothing in it is the registry's own.
local function snapshot(o)
	return {
		id = o.id,
		title = o.title,
		description = o.description,
		primary = o.primary,
		main = S.mainId == o.id,
		state = o.state,
		pos = Vector(currentPos(o)),
		ent = liveEnt(o),
		radar = o.radar,
		marker = o.marker,
		onRemove = o.onRemove,
		via = copyVia(o.via)
	}
end

-- What the network carries (the position is the entity's now).
local function record(o)
	local e = liveEnt(o)

	return {
		id = o.id,
		title = o.title,
		description = o.description,
		primary = o.primary,
		state = o.state,
		main = S.mainId == o.id,
		radar = o.radar,
		marker = o.marker,
		pos = currentPos(o),
		entIndex = e and e:EntIndex() or 0,
		via = o.via
	}
end

-- Whether the player may see the objective. A filter that throws, or that answers nothing, hides it.
local function visible(o, ply)
	if not o.filter then
		return true
	end

	local ok, result = API.SafeCall(o.filterId, o.filter, ply)

	return (ok and result) and true or false
end

-- A report for the other addons; nothing is told while the switch is off.
local function fire(name, ...)
	if enabled() then
		Obj.Fire(name, ...)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The network
-- ---------------------------------------------------------------------------------------------------------

local function start(op)
	net.Start(NAME)
	net.WriteUInt(op, Obj.OpBits)
end

-- The players that are ready and still there.
local function readyPlayers()
	local list = {}

	for ply in pairs(ready) do
		if IsValid(ply) then
			list[#list + 1] = ply
		else
			ready[ply] = nil
			seen[ply] = nil
		end
	end

	return list
end

local function sendRemove(id, reason, players)
	start(Ops.REMOVE)
	net.WriteString(id)
	net.WriteUInt(Obj.ReasonIds[reason], Obj.ReasonBits)
	net.Send(players)
end

-- The new values of an objective to the ready players who may see it; the ones who may not any more are told it is gone.
local function pushSet(o)
	if not enabled() then
		return
	end

	local to, away = {}, {}

	for _, ply in ipairs(readyPlayers()) do
		local mine = seen[ply]

		if visible(o, ply) then
			mine[o.id] = true
			to[#to + 1] = ply
		elseif mine[o.id] then
			mine[o.id] = nil
			away[#away + 1] = ply
		end
	end

	if to[1] then
		start(Ops.SET)
		Obj.WriteRecord(record(o))
		net.Send(to)
	end

	if away[1] then
		sendRemove(o.id, Reasons.REMOVED, away)
	end
end

-- The objective is gone: to the players who had it.
local function pushRemove(id, reason)
	if not enabled() then
		return
	end

	local to = {}

	for _, ply in ipairs(readyPlayers()) do
		if seen[ply][id] then
			seen[ply][id] = nil
			to[#to + 1] = ply
		end
	end

	if to[1] then
		sendRemove(id, reason, to)
	end
end

-- Every objective is gone, for every ready player.
local function pushClear(reason)
	local to = readyPlayers()

	for _, ply in ipairs(to) do
		seen[ply] = {}
	end

	if to[1] then
		start(Ops.CLEAR)
		net.WriteUInt(Obj.ReasonIds[reason], Obj.ReasonBits)
		net.Send(to)
	end
end

-- The main objective changed: each player is told the id, or "" when he may not see it.
local function pushMain()
	if not enabled() then
		return
	end

	for _, ply in ipairs(readyPlayers()) do
		local id = S.mainId

		if not id or not seen[ply][id] then
			id = ""
		end

		start(Ops.MAIN)
		net.WriteString(id)
		net.Send(ply)
	end
end

-- The objectives of `moved` have a new position: each ready player gets the ones he sees.
local function pushPositions(moved)
	if not enabled() then
		return
	end

	for _, ply in ipairs(readyPlayers()) do
		local mine = {}

		for _, o in ipairs(moved) do
			if seen[ply][o.id] then
				mine[#mine + 1] = o
			end
		end

		if mine[1] then
			start(Ops.POS)
			net.WriteUInt(#mine, Obj.CountBits)

			for _, o in ipairs(mine) do
				net.WriteString(o.id)
				net.WriteVector(o.sentPos)
			end

			net.Send(ply)
		end
	end
end

-- The full list for one player, when his client says it is ready (or `force`: also when the list is empty, to take away what the client still has).
-- Only what the player may see; the client keeps what it receives and drops the rest at END.
function S.Sync(ply, force)
	if not IsValid(ply) then
		return false
	end

	ready[ply] = true
	seen[ply] = {}

	if not enabled() or (order[1] == nil and not force) then
		return true
	end

	start(Ops.BEGIN)
	net.Send(ply)

	for _, id in ipairs(order) do
		local o = items[id]

		if visible(o, ply) then
			seen[ply][id] = true
			start(Ops.SET)
			Obj.WriteRecord(record(o))
			net.Send(ply)
		end
	end

	start(Ops.END)
	net.Send(ply)

	return true
end

-- A player who left is not sent anything any more.
function S.Forget(ply)
	ready[ply] = nil
	seen[ply] = nil
end

hook.Add("PlayerDisconnected", HOOK_ID, function(ply)
	S.Forget(ply)
end)

-- The client says it is ready: GryMod.AnswerReady (sv_system.lua) answers it with the suit's mode, and now with the objectives too. Wrapped once (a
-- reload of this file finds its own wrapper and does not wrap it again). The same rate limit applies: one answer a second.
S.wrappers = S.wrappers or setmetatable({}, {__mode = "k"})

do
	local current = GryMod.AnswerReady

	if isfunction(current) and not S.wrappers[current] then
		local base = current

		local function answer(ply)
			local answered = base(ply)

			if answered then
				S.Sync(ply)
			end

			return answered
		end

		S.wrappers[answer] = true
		GryMod.AnswerReady = answer
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The watchers: only while an objective follows an entity
-- ---------------------------------------------------------------------------------------------------------

local function onEntityRemoved(ent)
	S.OnEntityRemoved(ent)
end

local function onTimer()
	S.RefreshPositions()
end

local function refreshWatchers()
	local bound = false

	for i = 1, #order do
		if isBound(items[order[i]]) then
			bound = true

			break
		end
	end

	-- the registry must stay right whatever the switch says: the hook stays while the switch is off, the timer (which only feeds the network) does not
	if bound then
		hook.Add("EntityRemoved", HOOK_ID, onEntityRemoved)
	else
		hook.Remove("EntityRemoved", HOOK_ID)
	end

	if bound and enabled() then
		if not timer.Exists(TIMER_ID) then
			timer.Create(TIMER_ID, POSITION_INTERVAL, 0, onTimer)
		end
	else
		timer.Remove(TIMER_ID)
	end
end

-- Reads the position of every objective that follows an entity and sends the ones that moved more than 32 units since the last time they were sent. An
-- objective whose function gives another entity now follows that one (the clients get its record again: the index of the entity changed).
function S.RefreshPositions()
	local ids = {}

	for i = 1, #order do
		ids[i] = order[i]
	end

	local moved, rebound = {}, {}

	for _, id in ipairs(ids) do
		local o = items[id]

		if o and isBound(o) then
			local e = liveEnt(o)

			if o.entFn then
				local ok, result = API.SafeCall(o.entId, o.entFn)

				if ok and Obj.IsValidEntity(result) and result ~= e then
					o.ent = result
					e = result
					o.pos = e:GetPos()
					o.sentPos = o.pos
					rebound[#rebound + 1] = o
					e = nil -- told as a whole below
				end
			end

			if e then
				local p = e:GetPos()

				if not o.sentPos or p:DistToSqr(o.sentPos) > MOVE_SQR then
					o.pos = p
					o.sentPos = p
					moved[#moved + 1] = o
				end
			end
		end
	end

	for _, o in ipairs(rebound) do
		pushSet(o)
	end

	if moved[1] then
		pushPositions(moved)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Adding, changing and removing
-- ---------------------------------------------------------------------------------------------------------

-- The objective is gone (the reason is one of Obj.Reasons).
local function drop(o, reason)
	local snap = snapshot(o)

	items[o.id] = nil
	table.RemoveByValue(order, o.id)

	if S.mainId == o.id then
		S.mainId = nil
	end

	refreshWatchers()
	pushRemove(o.id, reason)
	fire("GryMod_ObjectiveRemoved", o.id, snap, reason)
end

-- Every objective is gone. Returns how many there were.
local function clearAll(reason)
	local snaps = {}

	for i, id in ipairs(order) do
		snaps[i] = snapshot(items[id])
	end

	for id in pairs(items) do
		items[id] = nil
	end

	for i = #order, 1, -1 do
		order[i] = nil
	end

	S.mainId = nil
	refreshWatchers()

	if snaps[1] and enabled() then
		pushClear(reason)

		for _, snap in ipairs(snaps) do
			fire("GryMod_ObjectiveRemoved", snap.id, snap, reason)
		end
	end

	return #snaps
end

-- Whether what the hook GryMod_ObjectiveChanged reports differs between two objectives.
local function differs(a, b)
	return a.title ~= b.title or a.description ~= b.description or a.state ~= b.state or a.primary ~= b.primary
end

-- Registers (or updates) the objective `id`. `def`: title, description, primary (true), state ("active"), pos (a Vector) OR ent (an entity, or a function
-- that returns one), onRemove ("remove" | "complete" | "fail"), radar (true), marker (true), filter (function(ply) -> bool). Returns true, or false and why.
function API.RegisterObjective(id, def)
	local clean, reason = Obj.CheckDefinition(id, def)

	if not clean then
		return false, reason
	end

	local existing = items[id]

	if not existing and #order >= Limits.count then
		return false, "too many objectives (" .. Limits.count .. " at most)"
	end

	local entId, filterId = "objective:" .. id .. "/ent", "objective:" .. id .. "/filter"

	API.SafeCallReset(entId)
	API.SafeCallReset(filterId)

	local ent = clean.ent

	if clean.entFn then
		local ok, result = API.SafeCall(entId, clean.entFn)

		if not ok then
			return false, "invalid ent: the function failed: " .. tostring(result)
		end

		if not Obj.IsValidEntity(result) then
			return false, "invalid ent: the function did not return a valid entity"
		end

		ent = result
	end

	local o = {
		id = id, title = clean.title, description = clean.description, primary = clean.primary, state = clean.state, onRemove = clean.onRemove,
		radar = clean.radar, marker = clean.marker, via = clean.via, filter = clean.filter, filterId = filterId, ent = ent, entFn = clean.entFn, entId = entId,
		pos = ent and ent:GetPos() or clean.pos
	}

	o.sentPos = o.pos

	if existing then
		items[id] = o
	else
		items[id] = o
		order[#order + 1] = id
	end

	refreshWatchers()
	pushSet(o)

	if not existing then
		fire("GryMod_ObjectiveAdded", id, snapshot(o))
	elseif differs(existing, o) then
		fire("GryMod_ObjectiveChanged", id, snapshot(o), existing.state)
	end

	return true
end

-- Changes the state: "active", "done" or "failed". Returns true (also when the state is the one it has: nothing is told then), or false and why.
function API.SetObjectiveState(id, state)
	local o = isstring(id) and items[id] or nil

	if not o then
		return false, "unknown objective"
	end

	if not isstring(state) or not Obj.StateIds[state] then
		return false, "invalid state: active, done or failed"
	end

	if o.state == state then
		return true
	end

	local old = o.state

	o.state = state
	pushSet(o)
	fire("GryMod_ObjectiveChanged", id, snapshot(o), old)

	return true
end

-- Removes the objective. Returns true, or false and why.
function API.RemoveObjective(id)
	local o = isstring(id) and items[id] or nil

	if not o then
		return false, "unknown objective"
	end

	drop(o, Reasons.REMOVED)

	return true
end

-- The main objective (the one the displays stress): one at most. nil takes the main objective away. Returns true, or false and why.
function API.SetMainObjective(id)
	if id ~= nil and id ~= false then
		if not isstring(id) or not items[id] then
			return false, "unknown objective"
		end
	else
		id = nil
	end

	local old = S.mainId

	if old == id then
		return true
	end

	S.mainId = id
	pushMain()

	if old and items[old] then
		fire("GryMod_ObjectiveChanged", old, snapshot(items[old]), items[old].state)
	end

	if id then
		fire("GryMod_ObjectiveChanged", id, snapshot(items[id]), items[id].state)
	end

	return true
end

-- A copy of the objective {id, title, description, primary, main, state, pos, ent, radar, marker, onRemove}, or nil. The position is the entity's now.
function API.GetObjective(id)
	local o = isstring(id) and items[id] or nil

	if not o then
		return nil
	end

	return snapshot(o)
end

-- The copies of all the objectives, in the order of registration.
function API.GetObjectives()
	local list = {}

	for i, id in ipairs(order) do
		list[i] = snapshot(items[id])
	end

	return list
end

-- Removes all the objectives (the reason told is "cleared"). Returns how many there were.
function API.ClearObjectives()
	return clearAll(Reasons.CLEARED)
end

-- Sends the list again to `ply` (or to every ready player), asking the filters again: for an addon whose rule of who sees what changed. Returns
-- true, or false and why.
function API.RefreshObjectives(ply)
	if ply == nil then
		for _, p in ipairs(readyPlayers()) do
			S.Sync(p, true)
		end

		return true
	end

	if not isentity(ply) and not istable(ply) or not ready[ply] or not IsValid(ply) then
		return false, "the client of this player is not ready"
	end

	S.Sync(ply, true)

	return true
end

-- ---------------------------------------------------------------------------------------------------------
-- The entity of an objective is removed
-- ---------------------------------------------------------------------------------------------------------

-- The EntityRemoved hook (added only while an objective follows an entity). Each objective that follows this entity does what its onRemove says: "remove"
-- (the default) takes it away, "complete" and "fail" keep it where the entity was, with the state done or failed.
function S.OnEntityRemoved(ent)
	if cleaning then
		return -- the whole map is being cleaned up: every entity goes, none of them is an event (S.OnPostCleanup clears the objectives)
	end

	local hits = {}

	for _, id in ipairs(order) do
		local o = items[id]

		if o.ent ~= nil and o.ent == ent then
			hits[#hits + 1] = o
		end
	end

	for _, o in ipairs(hits) do
		if IsValid(ent) then
			o.pos = ent:GetPos()
		end

		if o.onRemove == "remove" then
			drop(o, Reasons.ENTITY_REMOVED)
		else
			local old = o.state

			o.ent, o.entFn = nil, nil
			o.sentPos = o.pos
			o.state = o.onRemove == "complete" and States.DONE or States.FAILED
			refreshWatchers()
			pushSet(o)

			if old ~= o.state then
				fire("GryMod_ObjectiveChanged", o.id, snapshot(o), old)
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- A cleaned up map, the switch
-- ---------------------------------------------------------------------------------------------------------

function S.OnPreCleanup()
	cleaning = true
end

-- The map is as new: the objectives of the old one are gone (the maps' own gry_objective entities were made again and register themselves).
function S.OnPostCleanup()
	cleaning = false
	clearAll(Reasons.MAP_CHANGED)
end

hook.Add("PreCleanupMap", HOOK_ID, function()
	S.OnPreCleanup()
end)

hook.Add("PostCleanupMap", HOOK_ID, function()
	S.OnPostCleanup()
end)

-- The administrators switch the objectives: off, the ready clients drop everything (the server keeps the objectives); on, they get the full list again.
function S.OnSwitch(_, new)
	refreshWatchers()

	if (tonumber(new) or 0) ~= 0 then
		for _, ply in ipairs(readyPlayers()) do
			S.Sync(ply)
		end
	else
		pushClear(Reasons.CLEARED)
	end
end

cvars.AddChangeCallback("gry_objectives", function(_, old, new)
	S.OnSwitch(old, new)
end, "GryMod_Objectives")

-- For the tests: forget everything without a word to anybody.
function S.Reset()
	for id in pairs(items) do
		items[id] = nil
	end

	for i = #order, 1, -1 do
		order[i] = nil
	end

	for ply in pairs(ready) do
		ready[ply] = nil
	end

	for ply in pairs(seen) do
		seen[ply] = nil
	end

	S.mainId = nil
	cleaning = false
	refreshWatchers()
end

refreshWatchers()
