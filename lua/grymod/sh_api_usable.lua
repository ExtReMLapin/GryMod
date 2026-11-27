-- The registry of usable entities of the extension API (for developers: docs/api.md). Shared: both realms read it. It says what the use
-- prompt under the crosshair (the movie HUD_InterActiveIcons, cl_hud_use_flash.lua) shows for an entity the player can use or take: an icon
-- (use, enter, pickup, grab or ladder) and a text ("TAKE %1", "ENTER VEHICLE", "CLIMB"...). The crosshair's test of what can be used
-- (GryMod.FlashCrosshair.UsableFor, which opens its "usable" state) asks this registry: an entity an entry names is usable, one that no entry
-- names is not. A "grab" entry only counts while the player can lift the entity (35 kg, 128 units), an "enter" entry not while he sits in a vehicle.
--
-- What an entry says besides its icon and text: `group` (an optional kind of prompt the player can switch off: the client convar gry_usehint_<group>
-- decides, see cl_hud_crosshair_flash.lua), `use` ("once", the default, for a use that changes the state of the thing: a grenade taken, a mounted gun,
-- a vehicle; "repeat" for one that can be done again at once: a door, a button, a charger), `cooldown` (seconds a repeatable use is dimmed after the key),
-- `ready(ent)` (false while the thing cannot be used again) and `busy(ent, ply)` (true: no prompt now, the thing is in use).
-- More fields say WHEN an entry applies: `spawnflags` (a rule over the entity's spawnflags, which the client can read: a door that "ignores +use", a
-- button that only reacts to touch, a func_door without "Use opens" never answer the key, so they get no prompt), `active` (a function, false while the
-- entry does not apply at all: the ladder only while sv_ladder_useonly is 1), `range` (units; the key reaches 80 by default, API.USE_REACH), `hold`
-- (the key must be kept down: one pulse at the press, not one for each repeat of the bind) and `nolimits` (a "grab" with no size or mass limit).
--
-- An entry is matched on a class (`class`, a name or a list), on a base class (`base`) or by a function (`match`), like the entries of the
-- tracked registry; the entries are tried by priority (the higher first), then in the order of registration. The stock Half-Life 2 entries
-- are at the bottom of this file, registered through the same call as an addon would, with a low priority: any addon's entry beats them.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local ICONS = {use = true, enter = true, pickup = true, grab = true, ladder = true}

API.UsableIcons = ICONS

local MAX_NAME, MAX_TEXT = 64, 64
local MAX_PRIORITY = 1000
local MAX_FLAGS = 0x7FFFFFFF
local MAX_RANGE = 1000

-- How far the use key reaches: PLAYER_USE_RADIUS of the Source SDK, the distance from the eye to the point hit. The crosshair used to test 110.
API.USE_REACH = 80

local band = bit.band

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

local function set(list)
	local result = {}

	for _, value in ipairs(list) do
		result[value] = true
	end

	return result
end

-- A rule over the spawnflags: a table {need = bits (all must be set), forbid = bits (none may be set)}, or a function(flags, ent) that says true to let the
-- entity through. Returns the rule, or nil when it is not valid.
local function flagBits(v)
	return isnumber(v) and v >= 0 and v <= MAX_FLAGS and v == math.floor(v)
end

local function flagsRule(v)
	if isfunction(v) then
		return v
	end

	if not istable(v) then
		return nil
	end

	local count = 0

	for key, bits in pairs(v) do
		if (key ~= "need" and key ~= "forbid") or not flagBits(bits) then
			return nil
		end

		count = count + 1
	end

	if count == 0 then
		return nil
	end

	return {need = v.need, forbid = v.forbid}
end

local CHECK = {
	class = names,
	base = names,
	match = function(v) if isfunction(v) then return v end end,
	icon = function(v) if isstring(v) and ICONS[v] then return v end end,
	text = function(v) if isfunction(v) or (isstring(v) and #v >= 1 and #v <= MAX_TEXT) then return v end end,
	name = function(v) if isfunction(v) or (isstring(v) and #v >= 1 and #v <= MAX_NAME) then return v end end,
	priority = function(v) if isnumber(v) and v >= -MAX_PRIORITY and v <= MAX_PRIORITY then return v end end,
	-- the thing is not solid (a ladder): the eye trace never hits it, so the crosshair looks for its classes along the aim ray (needs `class`)
	nonsolid = function(v) if isbool(v) then return v end end,
	-- a kind of prompt the player can switch off (gry_usehint_<group>): lower case letters, digits and underscores
	group = function(v) if isstring(v) and #v >= 1 and #v <= 24 and string.find(v, "^[a-z0-9_]+$") then return v end end,
	-- "once": the use changes the state of the thing (the prompt goes away); "repeat": it can be done again
	use = function(v) if v == "once" or v == "repeat" then return v end end,
	cooldown = function(v) if isnumber(v) and v >= 0 and v <= 60 then return v end end,
	ready = function(v) if isfunction(v) then return v end end,
	busy = function(v) if isfunction(v) then return v end end,
	-- what the spawnflags must say for the entry to apply (see flagsRule)
	spawnflags = flagsRule,
	-- false: the entry does not apply now (a rule of the server's settings, not of the entity)
	active = function(v) if isfunction(v) then return v end end,
	-- the name(s) the CLIENT gives these entities when the game has no client class of their name ("class C_BaseToggle"): what the nonsolid scan looks for
	netclass = names,
	-- how far the key reaches for this entry, in units (API.USE_REACH when missing)
	range = function(v) if isnumber(v) and v >= 1 and v <= MAX_RANGE then return v end end,
	-- the key must be kept down (a charger, a wheel): the feedback comes once, at the press
	hold = function(v) if isbool(v) then return v end end,
	-- a "grab" whose engine use has no size or mass limit (the floor turret)
	nolimits = function(v) if isbool(v) then return v end end
	}

	local FIELDS = {"class", "base", "match", "icon", "text", "name", "priority", "nonsolid", "group", "use", "cooldown", "ready", "busy", "spawnflags", "active", "range", "hold",
	"nolimits", "netclass"}

-- The entries by priority, then in the order of registration; they live through a reload of this file.
local order = API._usableOrder or {}
API._usableOrder = order

-- [class] = the entries that can match an entity of that class (and .static[entry] = the class or base matched), or false when none can.
local cache = {}
local nonSolidList -- the classes of the entries marked nonsolid (made when asked, forgotten at each change)
local maxRange -- the greatest range of the entries (made when asked, forgotten at each change)

local function changed()
	cache = {}
	nonSolidList = nil
	maxRange = nil
end

local function priorityOf(entry)
	return entry.priority or 0
end

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

-- Registers (or replaces, keeping its place) the entry `key`. `def`: class / base / match (at least one), icon ("use" by default),
-- text (a string, "%1" is the name of the entity, or function(ent, ply) -> string; "USE" by default), name (a string or function(ent) ->
-- string for the %1), priority. Returns true, or false and why (an invalid value refuses the whole definition).
function API.RegisterUsable(key, def)
	if not isstring(key) or key == "" then
		return false, "invalid key"
	end

	if not istable(def) then
		return false, "the definition must be a table"
	end

	local entry = {key = key, icon = "use", text = "USE", priority = 0, use = "once", matchId = "usable:" .. key .. "/match", textId = "usable:" .. key .. "/text",
		nameId = "usable:" .. key .. "/name", readyId = "usable:" .. key .. "/ready", busyId = "usable:" .. key .. "/busy",
				flagsId = "usable:" .. key .. "/flags", activeId = "usable:" .. key .. "/active"}

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

	if entry.nonsolid and not entry.class then
		return false, "nonsolid needs a class: the crosshair looks for the entities of those classes"
	end

	if entry.class then
		entry.classSet = set(entry.class)
	end

	API.SafeCallReset(entry.matchId)
	API.SafeCallReset(entry.textId)
	API.SafeCallReset(entry.nameId)
	API.SafeCallReset(entry.readyId)
	API.SafeCallReset(entry.busyId)
	API.SafeCallReset(entry.flagsId)
	API.SafeCallReset(entry.activeId)

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

function API.UnregisterUsable(key)
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

		if scripted_ents and scripted_ents.IsBasedOn then
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

-- The class the registry matches an entity on. It is ent:GetClass(), except for a name that is the game's NETWORK class ("class C_BaseToggle"): the
-- client has no class of the real name for a func_button, a func_rot_button or a momentary_rot_button, and says that. For those the resolver the client
-- installs (API.UsableClassResolver, cl_usable_class.lua: it asks the server) gives the real class, or nil while it is not known, and the generic name
-- stays (it matches no entry). A resolver that fails is ignored.
function API.UsableClassOf(ent)
	local class = API.ClassOf(ent) or ent:GetClass() -- the real class (SHARED-CLASS-1)
	local resolve = API.UsableClassResolver

	if resolve and string.find(class, "class C_", 1, true) == 1 then
		local ok, real = pcall(resolve, ent, class)

		if ok and isstring(real) and real ~= "" then
			return real
		end
	end

	return class
end

-- Whether the spawnflags of the entity let the entry apply: true when the entry has no rule, or when the entity cannot say its flags (a stand-in, a
-- client that cannot read them) or the rule's function fails: only a flag that clearly says no refuses. Pure over the flags (tests use fake entities).
function API.UsableFlagsAllow(entry, ent)
	if not entry or not entry.spawnflags or not ent or not isfunction(ent.GetSpawnFlags) then
		return true
	end

	local flags = ent:GetSpawnFlags()

	if not isnumber(flags) then
		return true
	end

	local rule = entry.spawnflags

	if isfunction(rule) then
		local ok, result = API.SafeCall(entry.flagsId, rule, flags, ent)

		return not ok or result == true
	end

	if rule.need and band(flags, rule.need) ~= rule.need then
		return false
	end

	return not (rule.forbid and band(flags, rule.forbid) ~= 0)
end

-- Whether an entry applies now: its `active` function (a failing one counts as "applies") and the spawnflags of the entity.
local function applies(entry, ent)
	if entry.active then
		local ok, result = API.SafeCall(entry.activeId, entry.active)

		if ok and not result then
			return false
		end
	end

	return API.UsableFlagsAllow(entry, ent)
end

-- The first entry that matches the entity, or nil (a stored entry: read it, do not change it). Fields: key, priority, icon, text, name,
-- class, base, match, and the others the entry was registered with. The match functions run under SafeCall. An entry whose `active` says no, or whose
-- `spawnflags` rule refuses the entity, does not match: the next entry is tried.
function API.GetUsable(ent)
	if order[1] == nil then
		return nil
	end

	if not isentity(ent) and not istable(ent) then
		return nil
	end

	if not IsValid(ent) or not isfunction(ent.GetClass) then
		return nil
	end

	local class = API.UsableClassOf(ent)
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
			if applies(entry, ent) then
				return entry
			end
		else
			local ok, result = API.SafeCall(entry.matchId, entry.match, ent)

			if ok and result == true and applies(entry, ent) then
				return entry
			end
		end
	end

	return nil
end

-- The classes of the entries marked `nonsolid`, in the order of the entries (a stored list: read it, do not change it). The crosshair looks for the
-- entities of these classes along the aim ray, since the eye trace passes through them.
function API.UsableNonSolidClasses()
	if nonSolidList then
		return nonSolidList
	end

	local list, seen, volatile = {}, {}, false

	for i = 1, #order do
		local entry = order[i]

		if entry.nonsolid and entry.class then
			-- an entry that applies only at times (the ladder) is asked again at each call, the others are kept
			volatile = volatile or entry.active ~= nil

			local ok, result = true, true

			if entry.active then
				ok, result = API.SafeCall(entry.activeId, entry.active)
			end

			if not ok or result then
				for _, class in ipairs(entry.class) do
					if not seen[class] then
						seen[class] = true
						list[#list + 1] = class
					end
				end

				-- the name the client gives them when the game has no client class of their name
				for _, class in ipairs(entry.netclass or {}) do
					if not seen[class] then
						seen[class] = true
						list[#list + 1] = class
					end
				end
			end
		end
	end

	if not volatile then
		nonSolidList = list
	end

	return list
end

-- How far the key reaches for an entry (its `range`, else the engine's 80 units); for no entry, the engine's.
function API.UsableRange(entry)
	return entry and entry.range or API.USE_REACH
end

-- The greatest range of all the entries: how far the crosshair has to look to see anything usable (80 for the stock entries).
function API.UsableMaxRange()
	if not maxRange then
		maxRange = API.USE_REACH

		for i = 1, #order do
			maxRange = math.max(maxRange, order[i].range or 0)
		end
	end

	return maxRange
end

-- Whether the thing can be used now, for an entry with a `ready` function (true when it has none, or when the function fails: a broken function must not
-- dim the prompt for ever). Runs under SafeCall.
function API.UsableReady(ent, entry)
	if not entry or not entry.ready then
		return true
	end

	local ok, result = API.SafeCall(entry.readyId, entry.ready, ent)

	return not ok or result ~= false
end

-- Whether the thing is in use and shows no prompt, for an entry with a `busy` function (false when it has none or the function fails).
function API.UsableBusy(ent, ply, entry)
	if not entry or not entry.busy then
		return false
	end

	local ok, result = API.SafeCall(entry.busyId, entry.busy, ent, ply)

	return ok and result == true
end

-- What the entity is called: the entry's name, else the name the weapon carries (its PrintName, translated when it is a "#" key), else
-- its class without the "weapon_" or "item_" start and with spaces for the underscores. Never empty.
function API.UsableName(ent, entry)
	local name = entry and entry.name

	if isfunction(name) then
		local ok, result = API.SafeCall(entry.nameId, name, ent)

		name = ok and isstring(result) and result ~= "" and result or nil
	end

	if not isstring(name) and isfunction(ent.GetPrintName) then
		local print = ent:GetPrintName()

		if isstring(print) and print ~= "" then
			if string.sub(print, 1, 1) == "#" and language and language.GetPhrase then
				print = language.GetPhrase(string.sub(print, 2))
			end

			name = print
		end
	end

	if not isstring(name) or name == "" then
		local class = ent:GetClass()

		name = string.gsub(string.gsub(string.gsub(class, "^weapon_", ""), "^item_", ""), "_", " ")
	end

	return name
end

-- The text of the prompt for the entity and the player: the entry's text (a function runs under SafeCall) with %1 replaced by the name,
-- in capitals (the movie's font is one). nil when no entry names the entity: the caller shows the plain default.
function API.UsableText(ent, ply, entry)
	entry = entry or API.GetUsable(ent)

	if not entry then
		return nil
	end

	local text = entry.text

	if isfunction(text) then
		local ok, result = API.SafeCall(entry.textId, text, ent, ply)

		text = ok and isstring(result) and result ~= "" and result or "USE"
	end

	if string.find(text, "%1", 1, true) then
		local name = API.UsableName(ent, entry)

		text = string.gsub(text, "%%1", function() return name end)
	end

	return string.upper(text)
end

-- The stock Half-Life 2 and Garry's Mod entries are data, registered through RegisterUsable like any addon's: lua/grymod/compat/hl2/sh_usable.lua.

API.AddFeature("usable")
