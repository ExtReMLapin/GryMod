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
	local class = ent:GetClass()
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

-- ---------------------------------------------------------------------------------------------------------
-- The stock Half-Life 2 and Garry's Mod entries, registered as data, with the original game's texts (game_text_messages.xml: pick_weapon,
-- pick_item, use_vehicle, use_ladder, grab_object, use_door) and its icons. Low priority: an entry of an addon for the same entity wins.
--
-- Every class here was checked in the public Source SDK 2013 code (the ObjectCaps of its class: FCAP_IMPULSE_USE or FCAP_CONTINUOUS_USE, which
-- is what makes the +use key act on it) or in the Lua of Garry's Mod (ENT:Use); the file and the maps where it can be seen are in each comment.
-- Maps: the stock Half-Life 2 ones, read from their entity lists (hl2/maps), and gm_construct. A class that is NOT here has no +use action:
-- combine_mine (only the gravity gun pulls it out), npc_kleiner / npc_eli / npc_breen / npc_dog (CAI_BaseActor: no use caps), item_item_crate
-- (a breakable crate), item_dynamic_resupply (it only spawns an item), func_physbox_multiplayer.
-- ---------------------------------------------------------------------------------------------------------

local STOCK = -100

-- A method of the entity, or false when it has none (a stand-in in a test, a reload): the stock matchers never raise an error, since five
-- errors in a row switch a matcher off.
local function ask(ent, method)
	local fn = ent[method]

	return isfunction(fn) and fn(ent) or false
end

local function register(key, def)
	def.priority = STOCK

	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the stock entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

-- (a hot reload of this file: the entries of the earlier versions are taken away)
for _, old in ipairs({"hl2_weapons", "hl2_items", "hl2_turrets", "hl2_doors", "hl2_floor_turret", "hl2_metropolice"}) do
	API.UnregisterUsable(old)
end

-- NOT HERE: what is taken by WALKING OVER it. A weapon on the floor and every item_* that is a plain pickup (health kit and vial, battery, HEV suit, the
-- ammo boxes and rounds) are picked up by touch (checked in game on gm_construct: a health kit, a battery and a pistol put at the player's feet were
-- taken without a key; the base gamemode's GM:PlayerCanPickupWeapon / PlayerCanPickupItem answer true). They have a +use action in the SDK too, but nobody
-- needs it, so they get no prompt. An addon whose weapon or item really needs the key registers it.

-- The ammo crate: CItem_AmmoCrate::ObjectCaps (item_ammo.cpp: FCAP_IMPULSE_USE, USE_IN_RADIUS), +use gives ammo, and again. d1_canals_05, d1_canals_07,
-- d2_coast_03, d2_coast_07.
register("hl2_ammo_crate", {class = "item_ammo_crate", icon = "pickup", text = "TAKE AMMO", use = "repeat", cooldown = 1})

-- The wall chargers: FCAP_CONTINUOUS_USE (func_recharge.cpp), held +use. item_healthcharger: d1_canals_01 (three), d1_canals_07, d2_coast_08;
-- item_suitcharger: d1_trainstation_01, d1_trainstation_05, d1_canals_08. (func_healthcharger and func_recharge are the old brush versions.)
-- The key is kept down while they work, so the text says it and the feedback comes once (hold).
register("hl2_chargers", {
	class = {"item_healthcharger", "item_suitcharger", "func_healthcharger", "func_recharge"}, icon = "use", text = "USE (HOLD)", use = "repeat", cooldown = 0.5, hold = true
})

-- The vehicles: CPropVehicleDriveable::ObjectCaps (vehicle_base.h), the airboat (USE_IN_RADIUS), the crane, the prisoner pod and the
-- choreographed seats all have FCAP_IMPULSE_USE. d2_coast_01 (prop_vehicle_jeep: the buggy, and the crane), d1_canals_05 and the other canal maps
-- (prop_vehicle_airboat), d1_canals_01a (prop_vehicle_apc), d3_breen_01 (prop_vehicle_prisoner_pod). The "jeep" class is also the scripted APC of
-- d1_trainstation_03 and 04: a driveable one only when its model is. Getting in changes the state: one-shot (the crosshair also drops it while the
-- player sits in a vehicle).
register("hl2_vehicles", {match = function(ent) return ask(ent, "IsVehicle") == true end, icon = "enter", text = "ENTER VEHICLE", use = "once"})

-- The ladder: func_useableladder. The player gets on it by WALKING INTO IT (the game's movement code, sv_ladder_useonly 0, the default): the use key is
-- optional, so there is no prompt, unless the server set sv_ladder_useonly 1 ("ladders can only be mounted by pressing +USE"). That variable is
-- replicated to the client. The class has no use cap of its own (ObjectCaps read in game: 2), the key is handled by the movement; its reach is 64 units.
-- d1_canals_01 (once), d1_canals_03 (five), gm_construct (once). A ladder is not solid: the eye trace never hits it, so the crosshair looks for it along
-- the aim ray (nonsolid). While the player climbs it there is no prompt.
local function ladderUseOnly()
	local var = GetConVar("sv_ladder_useonly")

	return var ~= nil and var:GetBool()
end

register("hl2_ladders", {
	class = "func_useableladder", icon = "ladder", text = "CLIMB", nonsolid = true, use = "once", active = ladderUseOnly, range = 64,
	busy = function(_, ply) return ply ~= nil and isfunction(ply.GetMoveType) and ply:GetMoveType() == MOVETYPE_LADDER end
})

-- What the player lifts: CPhysicsProp::ObjectCaps (props.cpp) and CPhysBox::ObjectCaps (physobj.cpp) give FCAP_IMPULSE_USE when
-- CBasePlayer::CanPickupObject(this, 35, 128) is true: at most 35 kg and 128 units on every side (the crosshair applies those limits to a
-- "grab" icon, see UsableFor, and asks the server for the mass), or whatever the spawnflags say. prop_physics in every stock map (d1_trainstation_01:
-- 178), func_physbox in d1_canals_02 (25). prop_ragdoll is NOT here: its ObjectCaps has no use bit (read in game, 0x40000002), the game does not lift it with
-- the key. "You can pick up almost anything": the owner is not sure the prompt is wanted on all of them, so they are the group "props", which the player
-- switches with gry_usehint_props (off by default).
--
-- The flags: prop_physics 512 "Prevent pickup" is never liftable, and a prop that starts frozen (8 "motion disabled") only with 64 "enable motion on
-- gravity gun grab". func_physbox 8192 "Ignore +USE for Pickup" is never, 32768 "motion disabled" only with 131072. (props_shared.h, physobj.h.)
register("hl2_props", {
	class = {"prop_physics", "prop_physics_multiplayer"}, icon = "grab", text = "PICK UP", group = "props", use = "once",
	spawnflags = function(flags) return band(flags, 512) == 0 and (band(flags, 8) == 0 or band(flags, 64) ~= 0) end
})

register("hl2_physbox", {
	class = "func_physbox", icon = "grab", text = "PICK UP", group = "props", use = "once",
	spawnflags = function(flags) return band(flags, 8192) == 0 and (band(flags, 32768) == 0 or band(flags, 131072) ~= 0) end
})

-- The floor turret: its Use is PickupObject with no limit (npc_turret_floor.h; read in game: after Use the player holds it, IsPlayerHolding). Not a toggle,
-- as the first list said. A carry like the props, so the same group; the limits of a prop do not apply to it. d2_prison_02 and d2_prison_03.
register("hl2_floor_turret", {class = "npc_turret_floor", icon = "grab", text = "PICK UP", group = "props", use = "once", nolimits = true})

-- The thrown frag grenade (npc_grenade_frag) has "Allow +USE pickup" (basegrenade_shared.h): it exists only at run time. Taking it changes the state
-- (it is in the hand, or it goes off), so one-shot; it is not a prop of the group (a grenade that is about to explode is worth a prompt).
register("hl2_grenade", {class = "npc_grenade_frag", icon = "grab", text = "PICK UP", use = "once"})

-- The doors: CBasePropDoor::ObjectCaps (props.cpp) answers the key unless 32768 "Ignore player +USE" is set (36 stock doors have it: barney_door_1 and _2 of
-- d1_trainstation_01 are the examples). CBaseDoor (func_door, func_door_rotating, doors.h) answers it ONLY with 256 "Use opens": 367 of the 492 stock
-- func_door have neither that nor 1024 "Touch opens" (a button or a trigger opens them), so they get no prompt. A door that "starts locked" (2048) still
-- takes the key (it plays the locked sound); whether it is locked NOW cannot be read on the client (checked: GetInternalVariable gives nothing), so the
-- prompt stays. A door can be used again once it has moved: a cooldown of a second. prop_door_rotating in d1_trainstation_01 (9) and d1_town_01 (4),
-- func_door in d1_canals_01 (-766 -7378 56), func_door_rotating in d1_trainstation_01.
register("hl2_prop_doors", {class = "prop_door_rotating", icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {forbid = 32768}})
register("hl2_func_doors", {class = {"func_door", "func_door_rotating"}, icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {need = 256}})

-- The buttons: CBaseButton (func_button, func_rot_button) answers the key only with 1024 "Use activates" (buttons.cpp); 10 stock buttons are touch or
-- damage only. A button waits before it works again (its `wait`, not readable on the client): a cooldown of a second. func_button in
-- d1_trainstation_01 (soda_machine_1) and d1_eli_01 (20), func_rot_button in d1_town_01 (5). The wheels (momentary_rot_button, d1_canals_05: four) turn
-- while the key is held (FCAP_CONTINUOUS_USE), with the same flag 1024.
register("hl2_buttons", {class = {"func_button", "func_rot_button"}, icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {need = 1024}})
-- Most wheels are "not solid" (flag 1): the eye trace goes through them and the key finds them by the radius search (USE_IN_RADIUS), so they are looked for
-- along the aim ray like the ladder (nonsolid), under the name the client gives them.
register("hl2_wheels", {
	class = "momentary_rot_button", netclass = "class C_BaseToggle", nonsolid = true, icon = "use", text = "USE (HOLD)", use = "repeat", cooldown = 1, hold = true,
	spawnflags = {need = 1024}
})

-- The mounted guns: CFuncTank::ObjectCaps (func_tank.h: FCAP_IMPULSE_USE, USE_IN_RADIUS, all func_tank* classes), but its Use does nothing unless 32
-- "Controllable" is set (13 maps have such a gun that is not). The control volume the player must stand in is a server trigger: not readable, the prompt
-- shows whatever the place. Taking the gun changes the state (the player now controls it): one-shot. func_tank in d1_canals_01a, d1_canals_07, d2_coast_01.
register("hl2_tanks", {
	class = {"func_tank", "func_tankairboatgun", "func_tankapcrocket", "func_tanklaser", "func_tankmortar", "func_tankphyscannister",
		"func_tankpulselaser", "func_tankrocket", "func_tank_combine_cannon"},
	icon = "use", text = "USE", use = "once", spawnflags = {need = 32}
})

-- The NPCs that answer +use while they live: CAI_PlayerAlly::ObjectCaps (ai_playerally.h) through UsableNPCObjectCaps, which gives
-- FCAP_IMPULSE_USE to an NPC that is alive. Only the ones whose Use does something: the citizen (follow me, or a question), Barney and Alyx (they speak)
-- and the vortigaunt (he heals, or speaks), all CNPC_PlayerCompanion. npc_citizen in d1_trainstation_01, npc_barney in d1_trainstation_01 and
-- d1_trainstation_05, npc_alyx in d1_eli_01, npc_vortigaunt in d1_canals_01 (boxcar) and d1_eli_01. NOT here, although the game gives them a use cap
-- (ObjectCaps read in game: 26): the Monk, Dr Mossman and G-Man have no Use function (the key does nothing), and the metropolice only gets
-- angry (PrecriminalUse adds a warning). Kleiner, Eli, Breen and the dog have no use cap at all. Talking can be done again.
local TALKERS = {npc_citizen = true, npc_barney = true, npc_alyx = true, npc_vortigaunt = true}

register("hl2_talkers", {
	match = function(ent) return ask(ent, "IsNPC") == true and TALKERS[ent:GetClass()] == true and (ask(ent, "Health") or 0) > 0 end,
	icon = "use", text = "TALK", use = "repeat", cooldown = 1
})

-- Garry's Mod's own: gmod_button (ENT:Use toggles it or presses it) in gamemodes/sandbox/entities/entities/gmod_button.lua, gmod_wheel
-- (ENT:Use reverses its motor), sent_ball (lua/entities/sent_ball.lua: ENT:Use eats it for 5 health, which changes the state). Spawned from the spawn menu
-- / the tools; none is in a stock map (gm_construct has a func_button and a func_useableladder). gmod_thruster has an ENT:Use with nothing in it: no prompt.
register("gmod_buttons", {class = {"gmod_button", "gmod_wheel"}, icon = "use", text = "USE", use = "repeat", cooldown = 0.5})
register("gmod_ball", {class = "sent_ball", icon = "pickup", text = "TAKE BALL", use = "once"})

API.AddFeature("usable")
