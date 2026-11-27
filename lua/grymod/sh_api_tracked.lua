-- The registry of tracked entities of the extension API (part 5 of docs/superpowers/specs/2026-11-21-extension-api-design.md; for
-- developers: docs/api.md). Shared: both realms read it. It says what an entity is for the radar (and the binoculars' scan):
-- the icon, how it is listed, whether the binoculars may tag it, and what it is to the player (the `relation` field is step 2
-- of the relation chain, GryMod.API.Relation in server/sv_api.lua). It also says which entities are a DANGER the player must be
-- warned about (the grenade warning: a grenade, a mine, a missile...): the `danger` field, and how the warning shows (`indicator`).
--
-- An entry is matched on a class (`class`, a name or a list), on a base class (`base`) or by a function (`match`), in that order
-- of cost: the first two are looked up in a cache by class, built when a class is first asked about and dropped at every
-- RegisterTracked / UnregisterTracked. GetTracked is asked for every NPC at every tick of the radar: it allocates nothing and
-- does nothing at all while the registry is empty. The entries are tried by priority (the higher first), then in the order of
-- registration; the stock Half-Life 2 entries (compat/hl2/sh_tracked.lua) have a low one, so that any addon's entry beats them.
--
-- The same file of declarations runs in both realms: the server decides (the radar, the relation, which projectile is armed) and
-- the client draws. A field that a realm does not use is stored and ignored there (docs/api.md has the table of who uses what).

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
-- Only "unit" is drawn today; the others are accepted and stored (a shape the HUD cannot draw yet is never an error).
local SHAPE = set({"unit", "dot", "rect", "triangle"})
local SIZE = set({"normal", "big"})
local INDICATOR = set({"warning", "marker", "none"})
local SHOCK = set({"light", "strong"})

-- The icons of the radar's movie: 1 ground units (infantry), 2 flying, 3 machines and vehicles (the rectangles), 4 devices (a rectangle
-- with a disc: the original's HUD code never produces it, GryMod uses it for the Combine mine).
local TYPE_NAMES = {human = 1, flying = 2, machine = 3, device = 4}

local MAX_NAME = 64
local MAX_LABEL = 32 -- the text of the warning's movie is short
local MAX_KIND = 24
local MAX_RANGE = 200 -- metres: the bound of the player's setting gry_grenade_range
local MAX_PRIORITY = 1000

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

-- The `danger` table: nil and the name of the field that is not valid, or the normalised copy. `armed` and `ownerOf` run under
-- SafeCall, on the server only. label is left nil when it is not given: RegisterTracked then takes the entry's label.
local function danger(v)
	if not istable(v) then
		return nil, "danger"
	end

	local d = {ownMissile = false}

	if v.label ~= nil then
		if not isstring(v.label) or #v.label < 1 or #v.label > MAX_LABEL then
			return nil, "danger.label"
		end

		d.label = v.label
	end

	if v.type ~= nil then
		if not isstring(v.type) or #v.type < 1 or #v.type > MAX_KIND then
			return nil, "danger.type"
		end

		d.type = v.type
	end

	if v.armed ~= nil then
		if not isfunction(v.armed) then
			return nil, "danger.armed"
		end

		d.armed = v.armed
	end

	if v.range ~= nil then
		if not isnumber(v.range) or not (v.range > 0) or v.range > MAX_RANGE then
			return nil, "danger.range"
		end

		d.range = v.range
	end

	if v.ownerOf ~= nil then
		if not isfunction(v.ownerOf) then
			return nil, "danger.ownerOf"
		end

		d.ownerOf = v.ownerOf
	end

	if v.ownMissile ~= nil then
		if not isbool(v.ownMissile) then
			return nil, "danger.ownMissile"
		end

		d.ownMissile = v.ownMissile
	end

	return d
end

-- The valid value of the field (normalised: names become lists, a type name its index), or nil when it is not valid (and then
-- maybe the name of the part that is not, for the reason RegisterTracked gives).
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

		if isnumber(v) and v == math.floor(v) and v >= 1 and v <= 4 then
			return v
		end
	end,
	label = function(v) if isfunction(v) or (isstring(v) and #v >= 1) then return v end end,
	shape = function(v) if isstring(v) and SHAPE[v] then return v end end,
	size = function(v) if isstring(v) and SIZE[v] then return v end end,
	danger = danger,
	indicator = function(v) if isstring(v) and INDICATOR[v] then return v end end,
	heavy = function(v) if isbool(v) then return v end end,
	shock = function(v) if isstring(v) and SHOCK[v] then return v end end,
	cloakBlind = function(v) if isbool(v) then return v end end,
	-- functions of the entry (SafeCall): `dead(ent) -> bool` a destroyed entity is not a contact; `awareness(ent, ply) -> level, exposure, seen, heard` the registry's
	-- equivalent of ENT:GetGryAwareness; `crew(ent) -> {ply or npc, ...}` the occupants of a vehicle (its relation follows theirs); `facing(ent) -> Vector` the world
	-- forward of the entity (the radar's heading). All of them are server-side readers; the client may read `facing` too.
	dead = function(v) if isfunction(v) then return v end end,
	awareness = function(v) if isfunction(v) then return v end end,
	crew = function(v) if isfunction(v) then return v end end,
	facing = function(v) if isfunction(v) then return v end end,
	priority = function(v) if isnumber(v) and v >= -MAX_PRIORITY and v <= MAX_PRIORITY then return v end end
}

local FIELDS = {"class", "base", "match", "scan", "radar", "relation", "type", "label", "shape", "size", "danger", "indicator", "heavy", "shock", "cloakBlind", "priority", "dead", "awareness", "crew", "facing"}

-- ---------------------------------------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------------------------------------

-- The entries by priority (the higher first), then in the order of registration (the first that matches wins); they live through a
-- reload of this file.
local order = API._trackedOrder or {}
API._trackedOrder = order

-- [class] = the entries that can match an entity of that class, in order (and .static[entry] = the class or base matched), or
-- false when none can. Dropped at every change of the registry, with the indexes by class below.
local cache = {}

-- Built when first asked, dropped at every change: [class] = the first entry that names the class (byClass), the first with a
-- danger (dangerByClass), and the list of the classes that have one (dangerList).
local byClass, dangerByClass, dangerList

-- [field] = the list of the classes whose entry has that field set (TrackedClasses); dropped at every change too.
local fieldClasses = {}

local function changed()
	cache = {}
	byClass, dangerByClass, dangerList = nil, nil, nil
	fieldClasses = {}
end

local function priorityOf(entry)
	return entry.priority or 0 -- an entry of an older copy of this file has none
end

-- Puts the entry after the ones of the same or a higher priority.
local function insert(entry)
	local at = #order + 1

	for i = 1, #order do
		if priorityOf(order[i]) < entry.priority then
			at = i

			break
		end
	end

	table.insert(order, at, entry)
end

-- Registers (or replaces, keeping its place) the entry `key`. Returns true, or false and why (an invalid value refuses the whole
-- definition and keeps the previous one). Fields that are not known are ignored.
function API.RegisterTracked(key, def)
	if not isstring(key) or key == "" then
		return false, "invalid key"
	end

	if not istable(def) then
		return false, "the definition must be a table"
	end

	local entry = {key = key, scan = true, shape = "unit", relation = "auto", priority = 0, matchId = "tracked:" .. key .. "/match",
		relationId = "tracked:" .. key .. "/relation", armedId = "tracked:" .. key .. "/armed", ownerId = "tracked:" .. key .. "/owner",
		deadId = "tracked:" .. key .. "/dead", awarenessId = "tracked:" .. key .. "/awareness", crewId = "tracked:" .. key .. "/crew", facingId = "tracked:" .. key .. "/facing"}

	for _, field in ipairs(FIELDS) do
		local value = def[field]

		if value ~= nil then
			local valid, part = CHECK[field](value)

			if valid == nil then
				return false, "invalid " .. (part or field) .. ": " .. tostring(value)
			end

			entry[field] = valid
		end
	end

	if not entry.class and not entry.base and not entry.match then
		return false, "nothing to match on: give a class, a base or a match function"
	end

	if entry.danger then
		if not entry.class then
			return false, "a danger needs a class (the client looks for these entities by class)"
		end

		entry.danger.label = entry.danger.label or (isstring(entry.label) and entry.label) or "DANGER"
		entry.indicator = entry.indicator or "warning"
	end

	if entry.cloakBlind and not entry.class then
		return false, "a cloakBlind needs a class (the cloak looks for these NPCs by class)"
	end

	if entry.class then
		entry.classSet = set(entry.class)
	end

	API.SafeCallReset(entry.matchId)
	API.SafeCallReset(entry.relationId)
	API.SafeCallReset(entry.armedId)
	API.SafeCallReset(entry.ownerId)
	API.SafeCallReset(entry.deadId)
	API.SafeCallReset(entry.awarenessId)
	API.SafeCallReset(entry.crewId)
	API.SafeCallReset(entry.facingId)

	for i = 1, #order do
		if order[i].key == key then
			if priorityOf(order[i]) == entry.priority then
				order[i] = entry
			else
				table.remove(order, i)
				insert(entry)
			end

			changed()

			return true
		end
	end

	insert(entry)
	changed()

	return true
end

function API.UnregisterTracked(key)
	if not isstring(key) then
		return false
	end

	for i = 1, #order do
		if order[i].key == key then
			table.remove(order, i)
			changed()

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
-- key, priority, scan (bool), radar, relation, type (the radar's icon, 1 to 4), label, shape, size (nil when not given), danger
-- (a table: label, type, armed, range, ownerOf, ownMissile), indicator, heavy, shock, cloakBlind (nil when not given), class, base,
-- match.
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

	-- the real class (SHARED-CLASS-1: an addon may replace Entity:GetClass)
	local class = API.ClassOf and API.ClassOf(ent) or ent:GetClass()
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

local function index()
	if byClass then
		return
	end

	byClass, dangerByClass, dangerList = {}, {}, {}

	for i = 1, #order do
		local entry = order[i]

		if entry.class then
			for _, class in ipairs(entry.class) do
				byClass[class] = byClass[class] or entry

				if entry.danger and not dangerByClass[class] then
					dangerByClass[class] = entry
					dangerList[#dangerList + 1] = class
				end
			end
		end
	end
end

-- The first entry that NAMES the class (`class` lists only: no base, no match function, which need an entity), or nil. Read only.
-- For what is asked about a class and not an entity (the radar's icon of a class).
function API.GetTrackedByClass(class)
	if not isstring(class) or order[1] == nil then
		return nil
	end

	index()

	return byClass[class]
end

-- The first entry with a `danger` that names the class (a class name, or an entity: its class), or nil. Read only. Both realms ask
-- it for every projectile: the server to follow and mark it, the client to say what to warn about.
function API.GetDanger(class)
	if not isstring(class) then
		if not isentity(class) and not istable(class) then
			return nil
		end

		if not IsValid(class) or not isfunction(class.GetClass) then
			return nil
		end

		class = API.ClassOf and API.ClassOf(class) or class:GetClass()
	end

	if order[1] == nil then
		return nil
	end

	index()

	return dangerByClass[class]
end

-- The classes that have a danger entry, in the order of the entries (a list that is kept: read it, do not change it).
function API.DangerClasses()
	index()

	return dangerList
end

local NO_CLASSES = {}

-- The classes whose entry has the field set (true, or a text such as shock's): a class counts when the entry is the first to NAME
-- it (an entry above it that names the same class without the field takes it away), in the order of the entries. `field` is a field
-- of a definition; any other name gives an empty list. For what a server system searches by class (the NPCs the camouflage hides
-- from). The list is kept: read it, do not change it.
function API.TrackedClasses(field)
	if not isstring(field) or not CHECK[field] or order[1] == nil then
		return NO_CLASSES
	end

	local list = fieldClasses[field]

	if list then
		return list
	end

	index()

	list = {}

	for i = 1, #order do
		local entry = order[i]

		if entry.class and entry[field] then
			for _, class in ipairs(entry.class) do
				if byClass[class] == entry then
					list[#list + 1] = class
				end
			end
		end
	end

	fieldClasses[field] = list

	return list
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
