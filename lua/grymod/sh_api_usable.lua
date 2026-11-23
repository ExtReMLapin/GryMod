-- The registry of usable entities of the extension API (for developers: docs/api.md). Shared: both realms read it. It says what the use
-- prompt under the crosshair (the movie HUD_InterActiveIcons, cl_hud_use_flash.lua) shows for an entity the player can use or take: an icon
-- (use, enter, pickup, grab or ladder) and a text ("TAKE %1", "ENTER VEHICLE", "CLIMB"...). WHETHER something can be used at all is the
-- crosshair's own test (GryMod.FlashCrosshair.UsableFor, the same one that opens its "usable" state); this registry only says WHAT it is.
-- An entity that no entry names shows the plain "USE".
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
-- The stock Half-Life 2 entries, registered as data, with the original game's texts (game_text_messages.xml: pick_weapon, pick_item,
-- use_vehicle, use_ladder, grab_object, use_door) and its icons. Low priority: an entry of an addon for the same entity wins.
-- ---------------------------------------------------------------------------------------------------------

local STOCK = -100

local function register(key, def)
	def.priority = STOCK

	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the stock entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

-- The weapons lying on the ground, and the items (ammo boxes, health kits, batteries): "TAKE <name>".
register("hl2_weapons", {match = function(ent) return ent:IsWeapon() end, icon = "pickup", text = "TAKE %1"})
register("hl2_items", {match = function(ent) return string.sub(ent:GetClass(), 1, 5) == "item_" end, icon = "pickup", text = "TAKE %1"})

-- A vehicle to get into.
register("hl2_vehicles", {match = function(ent) return ent:IsVehicle() end, icon = "enter", text = "ENTER VEHICLE"})

-- The ladder, and the objects that are lifted (the original's grab icon, its text "PICK UP").
register("hl2_ladders", {class = "func_useableladder", icon = "ladder", text = "CLIMB"})
register("hl2_props", {class = {"prop_physics", "prop_physics_multiplayer", "prop_ragdoll"}, icon = "grab", text = "PICK UP"})

-- The doors and the buttons: the plain "USE" (and the icon of the plain use).
register("hl2_doors", {
	class = {"func_button", "func_rot_button", "momentary_rot_button", "prop_door_rotating", "func_door_rotating"},
	icon = "use", text = "USE"
})

API.AddFeature("usable")
