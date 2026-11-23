-- The objectives, CLIENT side: the mirror of what the server sends (server/sv_objectives.lua) and the read API the displays use (the on-screen markers, the
-- radar, the maps: they come later and only READ here). Nothing is drawn by this file and nothing runs by itself: it works when a message arrives.
--
--   GryMod.Objectives.List()   the objectives, in the order they were registered: {id, title, description, primary, main, state, pos, ent, radar, marker}
--   GryMod.Objectives.Get(id)  one of them, or nil
--   GryMod.Objectives.Main()   the main objective, or nil
-- `pos` is resolved when you ask: the entity's position when this client has the entity (it is "awake": in view), the position the server sent when it does not
-- (the server refreshes it twice a second while the entity moves). `ent` is the entity when the client has it, else nil. The tables are the mirror's own and are
-- REUSED at every call (no garbage for a display that asks every frame): read them, do not keep or change them; the hooks get copies.
--
-- The hooks GryMod_ObjectiveAdded(id, obj), GryMod_ObjectiveChanged(id, obj, oldState) and GryMod_ObjectiveRemoved(id, obj, reason) are told here too, as
-- the messages arrive (sh_objectives.lua, Obj.Fire: a listener that throws breaks nothing). No return value is read.

GryMod = GryMod or {}

local API = GryMod.API
local Obj = GryMod.Objectives

if not API or not Obj then
	return -- sh_api.lua and sh_objectives.lua are included first (grymod_shared.lua)
end

local Ops, Reasons = Obj.Ops, Obj.Reasons

-- The mirror lives through a reload of this file: the objectives by id, the ids in order, the id of the main objective.
local store = Obj._store or {}
local order = Obj._order or {}
local list = Obj._list or {}
Obj._store, Obj._order, Obj._list = store, order, list

-- While a full list arrives (BEGIN ... END): the ids it mentioned.
local mentioned = nil

-- Puts `pos` and `ent` of the objective as they are now.
local function resolve(o)
	local index = o.entIndex

	if index and index > 0 then
		local ent = Entity(index)

		if IsValid(ent) then
			o.ent = ent
			o.pos = ent:IsDormant() and o.serverPos or ent:GetPos()

			return o
		end
	end

	o.ent = nil
	o.pos = o.serverPos

	return o
end

-- The copy the hooks get: the public fields, with a Vector of its own.
local function snapshot(o)
	resolve(o)

	return {
		id = o.id,
		title = o.title,
		description = o.description,
		primary = o.primary,
		main = o.main,
		state = o.state,
		pos = Vector(o.pos),
		ent = o.ent,
		radar = o.radar,
		marker = o.marker
	}
end

function Obj.List()
	local count = #order

	for i = 1, count do
		list[i] = resolve(store[order[i]])
	end

	for i = #list, count + 1, -1 do
		list[i] = nil
	end

	return list
end

function Obj.Get(id)
	local o = isstring(id) and store[id] or nil

	if o then
		resolve(o)
	end

	return o
end

function Obj.Main()
	return Obj.Get(Obj._main)
end

-- ---------------------------------------------------------------------------------------------------------
-- What the messages do (each one is a function, the receiver below only reads and calls)
-- ---------------------------------------------------------------------------------------------------------

-- A new objective, or the new values of one the client has. `rec` is what Obj.ReadRecord gives.
function Obj.ApplySet(rec)
	local o = store[rec.id]
	local isNew = o == nil
	local before

	if isNew then
		o = {id = rec.id}
		store[rec.id] = o
		order[#order + 1] = rec.id
	else
		before = {title = o.title, description = o.description, state = o.state, primary = o.primary, main = o.main}
	end

	o.title, o.description, o.primary, o.state = rec.title, rec.description, rec.primary, rec.state
	o.radar, o.marker = rec.radar, rec.marker
	o.entIndex, o.serverPos = rec.entIndex, rec.pos

	-- one main objective: the one that had the flag loses it
	local lost

	if rec.main then
		if Obj._main ~= rec.id then
			lost = store[Obj._main]
			Obj._main = rec.id
		end
	elseif Obj._main == rec.id then
		Obj._main = nil
	end

	o.main = Obj._main == rec.id

	if lost then
		lost.main = false
	end

	if mentioned then
		mentioned[rec.id] = true
	end

	if isNew then
		Obj.Fire("GryMod_ObjectiveAdded", rec.id, snapshot(o))
	elseif before.title ~= o.title or before.description ~= o.description or before.state ~= o.state or before.primary ~= o.primary or before.main ~= o.main then
		Obj.Fire("GryMod_ObjectiveChanged", rec.id, snapshot(o), before.state)
	end

	if lost then
		Obj.Fire("GryMod_ObjectiveChanged", lost.id, snapshot(lost), lost.state)
	end
end

local function forget(id)
	store[id] = nil
	table.RemoveByValue(order, id)

	if Obj._main == id then
		Obj._main = nil
	end
end

-- The objective is gone; `reason` is one of Obj.Reasons.
function Obj.ApplyRemove(id, reason)
	local o = store[id]

	if not o then
		return
	end

	local snap = snapshot(o)

	forget(id)
	Obj.Fire("GryMod_ObjectiveRemoved", id, snap, reason or Reasons.REMOVED)
end

-- Every objective is gone.
function Obj.ApplyClear(reason)
	local snaps = {}

	for i, id in ipairs(order) do
		snaps[i] = snapshot(store[id])
	end

	for id in pairs(store) do
		store[id] = nil
	end

	for i = #order, 1, -1 do
		order[i] = nil
	end

	Obj._main = nil

	for _, snap in ipairs(snaps) do
		Obj.Fire("GryMod_ObjectiveRemoved", snap.id, snap, reason or Reasons.CLEARED)
	end
end

-- The main objective is `id` ("" or an objective the client does not have: none).
function Obj.ApplyMain(id)
	if not isstring(id) or not store[id] then
		id = nil
	end

	local old = Obj._main

	if old == id then
		return
	end

	Obj._main = id

	local oldObj, newObj = store[old or ""], store[id or ""]

	if oldObj then
		oldObj.main = false
	end

	if newObj then
		newObj.main = true
	end

	if oldObj then
		Obj.Fire("GryMod_ObjectiveChanged", oldObj.id, snapshot(oldObj), oldObj.state)
	end

	if newObj then
		Obj.Fire("GryMod_ObjectiveChanged", newObj.id, snapshot(newObj), newObj.state)
	end
end

-- The positions the server sent for the objectives that follow an entity: {{id = , pos = }, ...}. Used when the client does not have the entity.
function Obj.ApplyPositions(positions)
	for _, entry in ipairs(positions) do
		local o = store[entry.id]

		if o then
			o.serverPos = entry.pos
		end
	end
end

-- A full list begins: the objectives it does not mention are removed at its end.
function Obj.ApplyBegin()
	mentioned = {}
end

function Obj.ApplyEnd()
	if not mentioned then
		return
	end

	local seen = mentioned
	local gone = {}

	mentioned = nil

	for _, id in ipairs(order) do
		if not seen[id] then
			gone[#gone + 1] = id
		end
	end

	for _, id in ipairs(gone) do
		Obj.ApplyRemove(id, Reasons.REMOVED)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The message gry_objectives
-- ---------------------------------------------------------------------------------------------------------

function Obj.Receive()
	local op = net.ReadUInt(Obj.OpBits)

	if op == Ops.SET then
		local rec = Obj.ReadRecord()

		if rec then
			Obj.ApplySet(rec)
		end
	elseif op == Ops.REMOVE then
		local id = net.ReadString()
		local reason = Obj.ReasonList[net.ReadUInt(Obj.ReasonBits) + 1] or Reasons.REMOVED

		Obj.ApplyRemove(id, reason)
	elseif op == Ops.CLEAR then
		Obj.ApplyClear(Obj.ReasonList[net.ReadUInt(Obj.ReasonBits) + 1] or Reasons.CLEARED)
	elseif op == Ops.MAIN then
		Obj.ApplyMain(net.ReadString())
	elseif op == Ops.POS then
		local positions = {}

		for i = 1, net.ReadUInt(Obj.CountBits) do
			positions[i] = {id = net.ReadString(), pos = net.ReadVector()}
		end

		Obj.ApplyPositions(positions)
	elseif op == Ops.BEGIN then
		Obj.ApplyBegin()
	elseif op == Ops.END then
		Obj.ApplyEnd()
	end
end

net.Receive("gry_objectives", function()
	Obj.Receive()
end)

-- For the tests: forget everything without a word to anybody.
function Obj.Reset()
	for id in pairs(store) do
		store[id] = nil
	end

	for i = #order, 1, -1 do
		order[i] = nil
	end

	for i = #list, 1, -1 do
		list[i] = nil
	end

	Obj._main = nil
	mentioned = nil
end
