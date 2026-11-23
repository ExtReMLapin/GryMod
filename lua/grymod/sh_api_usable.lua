-- The registry of usable entities of the extension API (for developers: docs/api.md). Shared: both realms read it. It says what the use
-- prompt under the crosshair (the movie HUD_InterActiveIcons, cl_hud_use_flash.lua) shows for an entity the player can use or take: an icon
-- (use, enter, pickup, grab or ladder) and a text ("TAKE %1", "ENTER VEHICLE", "CLIMB"...). The crosshair's test of what can be used
-- (GryMod.FlashCrosshair.UsableFor, which opens its "usable" state) asks this registry: an entity an entry names is usable, one that no entry
-- names is not. A "grab" entry only counts while the player can lift the entity (35 kg, 128 units), an "enter" entry not while he sits in a vehicle.
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

local CHECK = {
	class = names,
	base = names,
	match = function(v) if isfunction(v) then return v end end,
	icon = function(v) if isstring(v) and ICONS[v] then return v end end,
	text = function(v) if isfunction(v) or (isstring(v) and #v >= 1 and #v <= MAX_TEXT) then return v end end,
	name = function(v) if isfunction(v) or (isstring(v) and #v >= 1 and #v <= MAX_NAME) then return v end end,
	priority = function(v) if isnumber(v) and v >= -MAX_PRIORITY and v <= MAX_PRIORITY then return v end end
}

local FIELDS = {"class", "base", "match", "icon", "text", "name", "priority"}

-- The entries by priority, then in the order of registration; they live through a reload of this file.
local order = API._usableOrder or {}
API._usableOrder = order

-- [class] = the entries that can match an entity of that class (and .static[entry] = the class or base matched), or false when none can.
local cache = {}

local function changed()
	cache = {}
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

	local entry = {key = key, icon = "use", text = "USE", priority = 0, matchId = "usable:" .. key .. "/match", textId = "usable:" .. key .. "/text",
		nameId = "usable:" .. key .. "/name"}

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
	API.SafeCallReset(entry.textId)
	API.SafeCallReset(entry.nameId)

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

-- The first entry that matches the entity, or nil (a stored entry: read it, do not change it). Fields: key, priority, icon, text, name,
-- class, base, match. The match functions run under SafeCall.
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

-- A weapon on the ground: CBaseCombatWeapon::ObjectCaps (FCAP_IMPULSE_USE unless the weapon refuses the player's pickup). Every weapon_*
-- of the stock maps, for example weapon_pistol and weapon_crowbar in d1_canals_01a, weapon_357 in d1_eli_01, weapon_frag and
-- weapon_physcannon in d1_town_01, weapon_shotgun / weapon_ar2 in d2_coast_01.
register("hl2_weapons", {match = function(ent) return ask(ent, "IsWeapon") == true end, icon = "pickup", text = "TAKE %1"})

-- The items. CItem::ObjectCaps has FCAP_IMPULSE_USE (items.h): +use picks the item up as it would a prop. The names are the ones of the
-- level editor's list (halflife2.fgd). Maps: item_healthkit and item_battery in d1_canals_01, item_healthvial in d1_canals_02, item_ammo_pistol
-- in d1_canals_01, item_ammo_smg1 / item_ammo_357 in d1_canals_03 and d1_canals_08, item_box_buckshot in d1_town_02, item_rpg_round in
-- d2_coast_03, item_ammo_crossbow in d2_coast_05, item_ammo_ar2 in d1_town_05. Not the things the item_ prefix also names but that are no
-- CItem: the chargers and the ammo crate (below), the item crate and the dynamic resupply.
local ITEM_NAMES = {
	item_healthkit = "health kit", item_healthvial = "health vial", item_battery = "battery", item_suit = "HEV suit",
	item_ammo_pistol = "pistol ammo", item_ammo_pistol_large = "large pistol ammo", item_ammo_smg1 = "SMG1 ammo",
	item_ammo_smg1_large = "large SMG1 ammo", item_ammo_ar2 = "AR2 ammo", item_ammo_ar2_large = "large AR2 ammo",
	item_ammo_357 = "357 ammo", item_ammo_357_large = "large 357 ammo", item_ammo_crossbow = "crossbow bolts",
	item_box_buckshot = "buckshot", item_rpg_round = "RPG round", item_ammo_smg1_grenade = "SMG1 grenade",
	item_ammo_ar2_altfire = "AR2 alt-fire round"
}

local NOT_ITEMS = {item_healthcharger = true, item_suitcharger = true, item_ammo_crate = true, item_item_crate = true, item_dynamic_resupply = true}

register("hl2_items", {
	match = function(ent)
		local class = ent:GetClass()

		return string.sub(class, 1, 5) == "item_" and not NOT_ITEMS[class]
	end,
	name = function(ent) return ITEM_NAMES[ent:GetClass()] end,
	icon = "pickup", text = "TAKE %1"
})

-- The ammo crate: CItem_AmmoCrate::ObjectCaps (item_ammo.cpp: FCAP_IMPULSE_USE, USE_IN_RADIUS), +use gives ammo. d1_canals_05, d1_canals_07,
-- d2_coast_03, d2_coast_07.
register("hl2_ammo_crate", {class = "item_ammo_crate", icon = "pickup", text = "TAKE AMMO"})

-- The wall chargers: FCAP_CONTINUOUS_USE (func_recharge.cpp), held +use. item_healthcharger: d1_canals_01 (three), d1_canals_07, d2_coast_08;
-- item_suitcharger: d1_trainstation_01, d1_trainstation_05, d1_canals_08. (func_healthcharger and func_recharge are the old brush versions.)
register("hl2_chargers", {class = {"item_healthcharger", "item_suitcharger", "func_healthcharger", "func_recharge"}, icon = "use", text = "USE"})

-- The vehicles: CPropVehicleDriveable::ObjectCaps (vehicle_base.h), the airboat (USE_IN_RADIUS), the crane, the prisoner pod and the
-- choreographed seats all have FCAP_IMPULSE_USE. d2_coast_01 (prop_vehicle_jeep: the buggy, and the crane), d1_canals_05 and the other canal maps
-- (prop_vehicle_airboat), d1_canals_01a (prop_vehicle_apc), d3_breen_01 (prop_vehicle_prisoner_pod). The "jeep" class is also the scripted APC of
-- d1_trainstation_03 and 04: a driveable one only when its model is.
register("hl2_vehicles", {match = function(ent) return ask(ent, "IsVehicle") == true end, icon = "enter", text = "ENTER VEHICLE"})

-- The ladder: func_useableladder, +use gets on (func_ladder.h). d1_canals_01 (once), d1_canals_03 (five), gm_construct (once).
register("hl2_ladders", {class = "func_useableladder", icon = "ladder", text = "CLIMB"})

-- What the player lifts: CPhysicsProp::ObjectCaps (props.cpp) and CPhysBox::ObjectCaps (physobj.cpp) give FCAP_IMPULSE_USE when
-- CBasePlayer::CanPickupObject(this, 35, 128) is true: at most 35 kg and 128 units on every side (the crosshair applies those limits to a
-- "grab" icon, see UsableFor). prop_physics in every stock map (d1_trainstation_01: 178), func_physbox in d1_canals_02 (25),
-- prop_ragdoll in d1_town_01 (36; the HL2 SDK gives ragdolls no use caps: this one is Garry's Mod's carry of a ragdoll and is to be checked in
-- game). The thrown frag grenade (npc_grenade_frag) has "Allow +USE pickup" (basegrenade_shared.h): it exists only at run time.
register("hl2_props", {
	class = {"prop_physics", "prop_physics_multiplayer", "prop_ragdoll", "func_physbox", "npc_grenade_frag"},
	icon = "grab", text = "PICK UP"
})

-- The doors and the buttons: CBasePropDoor::ObjectCaps (props.cpp, unless "ignore +use"), CBaseDoor with the "use opens" flag (doors.h),
-- CBaseButton with "use activates" (buttons.cpp), CMomentaryRotButton (continuous use). The server's flags are not readable on the client: a
-- door or a button that ignores +use also shows the prompt. prop_door_rotating in d1_trainstation_01 (9) and d1_town_01 (4), func_door in
-- d1_trainstation_01 (7), func_door_rotating in d1_trainstation_01 (9), func_button in d1_trainstation_01 (3) and d1_eli_01 (20),
-- func_rot_button in d1_town_01 (5), momentary_rot_button (the wheels) in d1_canals_05 (4).
register("hl2_doors", {
	class = {"prop_door_rotating", "func_door", "func_door_rotating", "func_button", "func_rot_button", "momentary_rot_button"},
	icon = "use", text = "USE"
})

-- The turrets you man: CFuncTank::ObjectCaps (func_tank.h: FCAP_IMPULSE_USE, USE_IN_RADIUS, all func_tank* classes), and the floor turret
-- (npc_turret_floor.h: +use toggles it). func_tank in d1_canals_01a, d1_canals_07, d2_coast_01; npc_turret_floor in d2_prison_02.
register("hl2_turrets", {
	class = {"func_tank", "func_tankairboatgun", "func_tankapcrocket", "func_tanklaser", "func_tankmortar", "func_tankphyscannister",
		"func_tankpulselaser", "func_tankrocket", "func_tank_combine_cannon", "npc_turret_floor"},
	icon = "use", text = "USE"
})

-- The NPCs that answer +use while they live: CAI_PlayerAlly::ObjectCaps (ai_playerally.h) through UsableNPCObjectCaps, which gives
-- FCAP_IMPULSE_USE to an NPC that is alive. The citizen, Barney, Alyx and the vortigaunt (CNPC_PlayerCompanion), Dr Mossman and the Monk
-- (CAI_PlayerAlly). npc_citizen in d1_trainstation_01, npc_barney in d1_trainstation_01 and d1_trainstation_05, npc_alyx in d1_eli_01,
-- npc_vortigaunt in d1_canals_01 (boxcar) and d1_eli_01, npc_monk in d1_town_01, npc_mossman in d1_eli_01. The metropolice also answers
-- +use (npc_metropolice.h, PrecriminalUse): d1_trainstation_01.
local TALKERS = {npc_citizen = true, npc_barney = true, npc_alyx = true, npc_vortigaunt = true, npc_mossman = true, npc_monk = true}

register("hl2_talkers", {
	match = function(ent) return ask(ent, "IsNPC") == true and TALKERS[ent:GetClass()] == true and (ask(ent, "Health") or 0) > 0 end,
	icon = "use", text = "TALK"
})

register("hl2_metropolice", {
	match = function(ent) return ask(ent, "IsNPC") == true and ent:GetClass() == "npc_metropolice" and (ask(ent, "Health") or 0) > 0 end,
	icon = "use", text = "USE"
})

-- Garry's Mod's own: gmod_button (ENT:Use toggles it or presses it) in gamemodes/sandbox/entities/entities/gmod_button.lua, gmod_wheel
-- (ENT:Use reverses its motor), sent_ball (lua/entities/sent_ball.lua: ENT:Use eats it for 5 health). Spawned from the spawn menu / the
-- tools; none is in a stock map (gm_construct has a func_button and a func_useableladder).
register("gmod_buttons", {class = {"gmod_button", "gmod_wheel"}, icon = "use", text = "USE"})
register("gmod_ball", {class = "sent_ball", icon = "pickup", text = "TAKE BALL"})

API.AddFeature("usable")
