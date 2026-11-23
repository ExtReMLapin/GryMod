-- The objectives of GryMod: the SHARED part (both realms). GMod has no objective system, so GryMod brings a small one for the addons and the
-- maps (docs/api.md, section "Objectives"). An objective has a title, a description, a primary or secondary flag, a state (active, done,
-- failed) and a place in the world: a position, or an entity it follows. This file holds what both sides need and nothing that draws:
--   * the names and limits of the model (states, removal reasons, sizes);
--   * the check of a definition (CheckDefinition: used by GryMod.API.RegisterObjective on the server);
--   * the record that goes through the network, written by the server (WriteRecord) and read by the client (ReadRecord);
--   * Fire, the way the three reporting hooks are run (a listener that throws breaks nothing).
-- The server keeps the truth (server/sv_objectives.lua); the client keeps a mirror and answers GryMod.Objectives.List() (client/cl_objectives.lua).

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local Obj = GryMod.Objectives or {}
GryMod.Objectives = Obj

-- The state of an objective. Plain strings, so a log or a print is readable. The position in the list is the id on the network: ONLY ADD AT THE END.
Obj.States = {ACTIVE = "active", DONE = "done", FAILED = "failed"}
Obj.StateList = {Obj.States.ACTIVE, Obj.States.DONE, Obj.States.FAILED}
Obj.StateIds = {}

for i, state in ipairs(Obj.StateList) do
	Obj.StateIds[state] = i - 1
end

Obj.StateBits = 2

-- Why an objective is gone: the 3rd argument of the hook GryMod_ObjectiveRemoved. Same rule for the list: ONLY ADD AT THE END.
Obj.Reasons = {
	REMOVED = "removed", -- RemoveObjective, or the objective is no longer for this player
	CLEARED = "cleared", -- ClearObjectives, or the administrators switched the objectives off
	ENTITY_REMOVED = "entity_removed", -- the entity it followed is gone (onRemove = "remove")
	MAP_CHANGED = "map_changed" -- the map was cleaned up: every objective of the old map is gone
}
Obj.ReasonList = {Obj.Reasons.REMOVED, Obj.Reasons.CLEARED, Obj.Reasons.ENTITY_REMOVED, Obj.Reasons.MAP_CHANGED}
Obj.ReasonIds = {}

for i, reason in ipairs(Obj.ReasonList) do
	Obj.ReasonIds[reason] = i - 1
end

Obj.ReasonBits = 2

-- What happens to an objective that follows an entity when the entity is removed.
Obj.OnRemoveValues = {remove = true, complete = true, fail = true}

Obj.Limits = {id = 64, title = 128, description = 512, count = 256}
Obj.MoveDistance = 32 -- units: the server tells a new position of an entity only when it moved more than this
Obj.EntBits = 14 -- an entity index on the network (0 = none)
Obj.CountBits = 9 -- how many positions one POS message holds (256 objectives at most)

local LIMITS = Obj.Limits

-- ---------------------------------------------------------------------------------------------------------
-- The check of a definition
-- ---------------------------------------------------------------------------------------------------------

local function finite(n)
	return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

local function validVector(v)
	return isvector(v) and finite(v.x) and finite(v.y) and finite(v.z)
end

local function validId(id)
	return isstring(id) and #id >= 1 and #id <= LIMITS.id
end

-- An entity, or a table that answers like one (the tests): IsValid raises an error on a number, and a number is junk.
local function validEntity(v)
	return (isentity(v) or istable(v)) and IsValid(v) and true or false
end

Obj.IsValidEntity = validEntity

-- Checks the definition `def` of the objective `id`. Returns a clean copy (the values the developer gave and the defaults for the rest: the position is a
-- copy of the Vector, the fields that are not known are left out), or false and why not. The reason names the field. Nothing is raised, whatever is given.
-- A function for `ent` is only kept (entFn): the server runs it.
function Obj.CheckDefinition(id, def)
	if not validId(id) then
		return false, "invalid id: a text of 1 to " .. LIMITS.id .. " characters"
	end

	if not istable(def) then
		return false, "invalid definition: it must be a table"
	end

	local clean = {id = id}

	if not isstring(def.title) or #def.title < 1 or #def.title > LIMITS.title then
		return false, "invalid title: a text of 1 to " .. LIMITS.title .. " characters"
	end

	clean.title = def.title

	if def.description == nil then
		clean.description = ""
	elseif isstring(def.description) and #def.description <= LIMITS.description then
		clean.description = def.description
	else
		return false, "invalid description: a text of " .. LIMITS.description .. " characters at most"
	end

	if def.primary == nil then
		clean.primary = true
	elseif isbool(def.primary) then
		clean.primary = def.primary
	else
		return false, "invalid primary: true or false"
	end

	if def.state == nil then
		clean.state = Obj.States.ACTIVE
	elseif isstring(def.state) and Obj.StateIds[def.state] then
		clean.state = def.state
	else
		return false, "invalid state: active, done or failed"
	end

	if def.onRemove == nil then
		clean.onRemove = "remove"
	elseif isstring(def.onRemove) and Obj.OnRemoveValues[def.onRemove] then
		clean.onRemove = def.onRemove
	else
		return false, "invalid onRemove: remove, complete or fail"
	end

	for _, field in ipairs({"radar", "marker"}) do
		if def[field] == nil then
			clean[field] = true
		elseif isbool(def[field]) then
			clean[field] = def[field]
		else
			return false, "invalid " .. field .. ": true or false"
		end
	end

	if def.filter ~= nil then
		if not isfunction(def.filter) then
			return false, "invalid filter: a function(ply) that returns true for the players who may see the objective"
		end

		clean.filter = def.filter
	end

	if def.pos ~= nil and def.ent ~= nil then
		return false, "give a pos or an ent, not both"
	end

	if def.pos ~= nil then
		if not validVector(def.pos) then
			return false, "invalid pos: a Vector with finite numbers"
		end

		clean.pos = Vector(def.pos.x, def.pos.y, def.pos.z)
	elseif def.ent ~= nil then
		if isfunction(def.ent) then
			clean.entFn = def.ent
		elseif validEntity(def.ent) then
			clean.ent = def.ent
		else
			return false, "invalid ent: a valid entity, or a function that returns one"
		end
	else
		return false, "give a pos (a Vector) or an ent (an entity, or a function that returns one)"
	end

	return clean
end

-- ---------------------------------------------------------------------------------------------------------
-- The record on the network: ONE objective, as the server tells it and the client reads it
-- ---------------------------------------------------------------------------------------------------------

-- Writes the record (the caller has started the message). Fields: id, title, description (strings), primary (bool), state (the name), main, radar, marker
-- (bools), pos (a Vector: where the objective is now), entIndex (the index of the entity it follows, 0 for none).
function Obj.WriteRecord(rec)
	net.WriteString(rec.id)
	net.WriteString(rec.title)
	net.WriteString(rec.description)
	net.WriteBool(rec.primary)
	net.WriteUInt(Obj.StateIds[rec.state] or 0, Obj.StateBits)
	net.WriteBool(rec.main)
	net.WriteBool(rec.radar)
	net.WriteBool(rec.marker)
	net.WriteVector(rec.pos)
	net.WriteUInt(rec.entIndex or 0, Obj.EntBits)
end

-- Reads the record: the table, or nil when it breaks the bounds (it is dropped, never trusted).
function Obj.ReadRecord()
	local rec = {}

	rec.id = net.ReadString()
	rec.title = net.ReadString()
	rec.description = net.ReadString()
	rec.primary = net.ReadBool()

	local stateId = net.ReadUInt(Obj.StateBits)

	rec.state = Obj.StateList[stateId + 1]
	rec.main = net.ReadBool()
	rec.radar = net.ReadBool()
	rec.marker = net.ReadBool()
	rec.pos = net.ReadVector()
	rec.entIndex = net.ReadUInt(Obj.EntBits)

	if not validId(rec.id) or #rec.title < 1 or #rec.title > LIMITS.title or #rec.description > LIMITS.description or not rec.state or not validVector(rec.pos) then
		return nil
	end

	return rec
end

-- The operations of the message gry_objectives (the first value of every message). ONLY ADD AT THE END.
--   SET     one record: a new objective, or the new values of one the client has
--   REMOVE  id, reason: one objective is gone
--   CLEAR   reason: all of them are gone
--   MAIN    id ("" for none): the main objective changed
--   POS     count, then count times (id, Vector): objectives that follow an entity moved
--   BEGIN   a full list follows (a SET for each objective), then END: what the list did not mention is gone
--   END     the end of the full list
Obj.Ops = {SET = 0, REMOVE = 1, CLEAR = 2, MAIN = 3, POS = 4, BEGIN = 5, END = 6}
Obj.OpBits = 3

-- ---------------------------------------------------------------------------------------------------------
-- The reporting hooks
-- ---------------------------------------------------------------------------------------------------------

-- How many failures of one hook are told on the console: after that a listener that throws on every event stays quiet.
Obj.MaxReports = 5

local failures = Obj._failures or {}
Obj._failures = failures

-- Runs the hook `name` (GryMod_ObjectiveAdded, ...) for the other addons. It is a report: nothing is returned and no listener's value is read. A listener that
-- throws breaks nothing here (the code that reports goes on); the first errors are written on the console, with the name of the hook.
function Obj.Fire(name, ...)
	local ok, err = pcall(hook.Run, name, ...)

	if ok then
		return
	end

	local count = (failures[name] or 0) + 1
	failures[name] = count

	if count <= Obj.MaxReports then
		MsgN("GryMod objectives: a listener of " .. name .. " failed: " .. tostring(err))
	end
end

API.AddFeature("objectives")
