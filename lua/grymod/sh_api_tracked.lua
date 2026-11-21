-- The registry of tracked entities of the extension API (part 5 of docs/superpowers/specs/2026-11-21-extension-api-design.md; for
-- developers: docs/api.md). Shared: both realms read it. It says what an entity is for the radar (and the binoculars' scan):
-- the icon, how it is listed, whether the binoculars may tag it, and what it is to the player (the `relation` field is step 2
-- of the relation chain, GryMod.API.Relation in server/sv_api.lua).
--
-- An entry is matched on a class (`class`, a name or a list), on a base class (`base`) or by a function (`match`), in that order
-- of cost: the first two are looked up in a cache by class, built when a class is first asked about and dropped at every
-- RegisterTracked / UnregisterTracked. GetTracked is asked for every NPC at every tick of the radar: it allocates nothing and
-- does nothing at all while the registry is empty.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local function set(list)
	local result = {}

	for _, value in ipairs(list) do
		result[value] = true
	end

	return result
end

local RADAR = set({"always", "hostile", "scan", "never"})
local RELATION = set({"auto", "ally", "neutral", "hostile"})
local VALID_RELATION = set({"ally", "neutral", "hostile"})
local SHAPE = set({"unit", "rect"})
local SIZE = set({"normal", "big"})

-- The icons of the radar's movie: 1 ground units (infantry), 2 flying, 3 machines.
local TYPE_NAMES = {human = 1, flying = 2, machine = 3}

local MAX_NAME = 64

-- A non-empty name, or a non-empty list of them: the list of names, nil when it is not valid.
local function names(v)
	if isstring(v) then
		if #v >= 1 and #v <= MAX_NAME then
			return {v}
		end

		return nil
	end

	if not istable(v) or #v == 0 then
		return nil
	end

	local list = {}

	for i = 1, #v do
		local name = v[i]

		if not isstring(name) or #name < 1 or #name > MAX_NAME then
			return nil
		end

		list[i] = name
	end

	return list
end

-- The valid value of the field (normalised: names become lists, a type name its index), or nil when it is not valid.
local CHECK = {
	class = names,
	base = names,
	match = function(v) if isfunction(v) then return v end end,
	scan = function(v) if isbool(v) then return v end end,
	radar = function(v) if isstring(v) and RADAR[v] then return v end end,
	relation = function(v) if isfunction(v) or (isstring(v) and RELATION[v]) then return v end end,
	type = function(v)
		if isstring(v) then
			return TYPE_NAMES[v]
		end

		if isnumber(v) and v == math.floor(v) and v >= 1 and v <= 3 then
			return v
		end
	end,
	label = function(v) if isfunction(v) or (isstring(v) and #v >= 1) then return v end end,
	shape = function(v) if isstring(v) and SHAPE[v] then return v end end,
	size = function(v) if isstring(v) and SIZE[v] then return v end end
}

local FIELDS = {"class", "base", "match", "scan", "radar", "relation", "type", "label", "shape", "size"}

-- ---------------------------------------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------------------------------------

-- The entries in the order of registration (the first that matches wins); they live through a reload of this file.
local order = API._trackedOrder or {}
API._trackedOrder = order

-- [class] = the entries that can match an entity of that class, in order (and .static[entry] = the class or base matched), or
-- false when none can. Dropped at every change of the registry.
local cache = {}

-- Registers (or replaces, keeping its place) the entry `key`. Returns true, or false and why (an invalid value refuses the whole
-- definition and keeps the previous one). Fields that are not known are ignored.
function API.RegisterTracked(key, def)
	if not isstring(key) or key == "" then
		return false, "invalid key"
	end

	if not istable(def) then
		return false, "the definition must be a table"
	end

	local entry = {key = key, scan = true, shape = "unit", relation = "auto", matchId = "tracked:" .. key .. "/match",
		relationId = "tracked:" .. key .. "/relation"}

	for _, field in ipairs(FIELDS) do
		local value = def[field]

		if value ~= nil then
			local valid = CHECK[field](value)

			if valid == nil then
				return false, "invalid " .. field .. ": " .. tostring(value)
			end

			entry[field] = valid
		end
	end

	if not entry.class and not entry.base and not entry.match then
		return false, "nothing to match on: give a class, a base or a match function"
	end

	if entry.class then
		entry.classSet = set(entry.class)
	end

	API.SafeCallReset(entry.matchId)
	API.SafeCallReset(entry.relationId)

	for i = 1, #order do
		if order[i].key == key then
			order[i] = entry
			cache = {}

			return true
		end
	end

	order[#order + 1] = entry
	cache = {}

	return true
end

function API.UnregisterTracked(key)
	if not isstring(key) then
		return false
	end

	for i = 1, #order do
		if order[i].key == key then
			table.remove(order, i)
			cache = {}

			return true
		end
	end

	return false
end

-- Whether the class (and the entity's Base field) is the base class of an entry, or built on it.
local function hasBase(entry, class, ent)
	local bases = entry.base

	if not bases then
		return false
	end

	for i = 1, #bases do
		local base = bases[i]

		if class == base or ent.Base == base then
			return true
		end

		if scripted_ents.IsBasedOn then
			local ok, based = pcall(scripted_ents.IsBasedOn, class, base)

			if ok and based then
				return true
			end
		end
	end

	return false
end

local function build(class, ent)
	local list

	for i = 1, #order do
		local entry = order[i]
		local static = (entry.classSet and entry.classSet[class] or hasBase(entry, class, ent)) and true or false

		if static or entry.match then
			list = list or {static = {}}
			list[#list + 1] = entry
			list.static[entry] = static
		end
	end

	return list or false
end

-- The first entry that matches the entity, or nil. The entry is the stored one, not a copy: read it, do not change it. Its fields:
-- key, scan (bool), radar, relation, type (the radar's icon, 1 to 3), label, shape, size (nil when not given), class, base, match.
function API.GetTracked(ent)
	if order[1] == nil then
		return nil
	end

	if not isentity(ent) and not istable(ent) then
		return nil
	end

	if not IsValid(ent) or not isfunction(ent.GetClass) then
		return nil
	end

	local class = ent:GetClass()
	local list = cache[class]

	if list == nil then
		list = build(class, ent)
		cache[class] = list
	end

	if not list then
		return nil
	end

	for i = 1, #list do
		local entry = list[i]

		if list.static[entry] then
			return entry
		end

		local ok, result = API.SafeCall(entry.matchId, entry.match, ent)

		if ok and result == true then
			return entry
		end
	end

	return nil
end

-- Step 2 of the relation chain (GryMod.API.Relation, server/sv_api.lua): the `relation` field of the entry that matches the
-- entity, "ally", "neutral" or "hostile"; nil when no entry matches, when it says "auto", or when its function has no valid
-- answer (the chain goes on to the built-in rule). A function runs under SafeCall.
function API._TrackedRelation(ply, ent)
	local entry = API.GetTracked(ent)

	if not entry then
		return nil
	end

	local relation = entry.relation

	if relation == "auto" then
		return nil
	end

	if isfunction(relation) then
		local ok, answer = API.SafeCall(entry.relationId, relation, ply, ent)

		if ok and VALID_RELATION[answer] then
			return answer
		end

		return nil
	end

	return relation
end

API.AddFeature("tracked")
