-- The weapon registry of the extension API (part 4 of docs/superpowers/specs/2026-11-21-extension-api-design.md; for
-- developers: docs/api.md). Shared: both realms read it.
--
-- A weapon is described by a "definition" (a table of optional fields, see FIELDS below). The HUD never knows a weapon by
-- its class: it asks GryMod.API.ResolveWeapon(wep), which merges, field by field and in this order:
--   1. the registry entry of the weapon's class (or of the nearest base class that has one),
--   2. the SWEP.GryHUD table of the weapon (a third-party weapon can declare itself without calling us),
--   3. the adapters (GryMod.API.AddWeaponAdapter: function(wep) return partialDefinition end, through SafeCall),
--   4. the defaults read from the SWEP (Primary, Secondary, the engine's ammo ids) and from CustomAmmoDisplay.
-- The stock Half-Life 2 weapons are registered through RegisterWeapon like any other weapon, in sh_api_weapons_hl2.lua.

GryMod = GryMod or {}

local API = GryMod.API
local SafeCall = API.SafeCall

-- ---------------------------------------------------------------------------------------------------------
-- The vocabulary
-- ---------------------------------------------------------------------------------------------------------

local function set(list)
	local result = {}

	for _, value in ipairs(list) do
		result[value] = true
	end

	return result
end

local FIRE = set({"auto", "semi", "burst", "none"})
local COUNTER = set({"clip", "none"})
local ALT = set({"none", "grenade", "energy", "zoom", "doublebarrel", "shoot", "throwlow", "melee"})

-- The secondary fires that fire a shot (what the camouflage's right click needs to know).
local ALT_SHOOTS = set({"grenade", "energy", "doublebarrel", "shoot", "throwlow"})

-- The icons of the weapon slot of the HUD movie (the labels of its AmmoMode clip). The 12 that no Half-Life 2 weapon chooses
-- (Incendiary ... Claymore) are there to be chosen by the weapons of other addons.
API.WeaponIcons = set({"Single", "Burst", "Auto", "Grenade", "Incendiary", "Tranquilizer", "infinity", "Shotgun",
	"Narrow", "Mine", "Repairkit", "Moac", "Moar", "TACCannon", "C4", "Gauss", "Gunner", "Missle", "Mounted",
	"NoGun", "Claymore", "HandGrenade"})

local ICONS = API.WeaponIcons

local MAX_NAME, MAX_LABEL = 64, 24

-- The valid value of the field `name` (what the field says, or a function for fire and counter), or nil when it is not valid.
local CHECK = {
	fire = function(v) if isfunction(v) or (isstring(v) and FIRE[v]) then return v end end,
	burst = function(v) if isnumber(v) and v == math.floor(v) and v >= 2 and v <= 32 then return v end end,
	ammo = function(v) if isstring(v) and #v >= 1 and #v <= MAX_NAME then return v end end,
	counter = function(v) if isfunction(v) or (isstring(v) and COUNTER[v]) then return v end end,
	alt = function(v) if isstring(v) and ALT[v] then return v end end,
	altAmmo = function(v) if isstring(v) and #v >= 1 and #v <= MAX_NAME then return v end end,
	altShoots = function(v) if isbool(v) then return v end end,
	altLabel = function(v) if isstring(v) and #v >= 1 and #v <= MAX_LABEL then return v end end,
	altIcon = function(v) if isstring(v) and ICONS[v] then return v end end,
	icon = function(v) if isstring(v) and ICONS[v] then return v end end,
	slotIcon = function(v) if isstring(v) and ICONS[v] then return v end end,
	crosshair = function(v) if isbool(v) then return v end end
}

local FIELDS = {"fire", "burst", "ammo", "counter", "alt", "altAmmo", "altShoots", "altLabel", "altIcon", "icon", "slotIcon", "crosshair"}

-- ---------------------------------------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------------------------------------

local registry = API._weaponRegistry or {}
API._weaponRegistry = registry

local function functionId(class, field)
	return "weapon:" .. class .. "/" .. field
end

-- Registers (or replaces) the definition of the weapon class. Fields that are not known are ignored. Returns true, or false and
-- why (an invalid value refuses the whole definition and keeps the previous one).
function API.RegisterWeapon(class, def)
	if not isstring(class) or class == "" then
		return false, "invalid class"
	end

	if not istable(def) then
		return false, "the definition must be a table"
	end

	local clean = {}

	for _, field in ipairs(FIELDS) do
		local value = def[field]

		if value ~= nil then
			local valid = CHECK[field](value)

			if valid == nil then
				return false, "invalid " .. field .. ": " .. tostring(value)
			end

			clean[field] = valid
		end
	end

	registry[class] = clean
	API.SafeCallReset(functionId(class, "fire"))
	API.SafeCallReset(functionId(class, "counter"))

	return true
end

function API.UnregisterWeapon(class)
	if not isstring(class) or registry[class] == nil then
		return false
	end

	registry[class] = nil

	return true
end

-- A copy of the definition registered for this class (no base class, no defaults), or nil.
function API.GetWeapon(class)
	local entry = isstring(class) and registry[class]

	if not entry then
		return nil
	end

	return table.Copy(entry)
end

-- ---------------------------------------------------------------------------------------------------------
-- Adapters (weapon bases: later patches add theirs; there is none today)
-- ---------------------------------------------------------------------------------------------------------

local adapters = API.weaponAdapters or {}
API.weaponAdapters = adapters -- a list of {id = string, fn = function}, in the order they were added

function API.AddWeaponAdapter(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	API.SafeCallReset("adapter:" .. id)

	for _, adapter in ipairs(adapters) do
		if adapter.id == id then
			adapter.fn = fn

			return true
		end
	end

	adapters[#adapters + 1] = {id = id, fn = fn}

	return true
end

function API.RemoveWeaponAdapter(id)
	for i, adapter in ipairs(adapters) do
		if adapter.id == id then
			table.remove(adapters, i)
			API.SafeCallReset("adapter:" .. id)

			return true
		end
	end

	return false
end

-- ---------------------------------------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------------------------------------

local function stored(class)
	local get = weapons.GetStored or weapons.Get

	return get(class)
end

-- The registry entry of the class, else of the nearest base class that has one.
local function entryFor(class)
	if not isstring(class) then
		return nil
	end

	local entry = registry[class]

	if entry then
		return entry
	end

	local swep = stored(class)

	for _ = 1, 8 do
		local base = swep and swep.Base

		if not isstring(base) or base == "" then
			return nil
		end

		entry = registry[base]

		if entry then
			return entry
		end

		swep = stored(base)
	end

	return nil
end

-- What the resolution needs of a weapon: its class, the table that holds its fields (the SWEP) and whether it is an entity.
-- A class name gives the stored SWEP (nil for a weapon written in C++), an entity gives itself, anything invalid gives nil.
local function identify(wep)
	if isstring(wep) then
		return wep, stored(wep), false
	end

	if wep == nil or isnumber(wep) or isbool(wep) or isfunction(wep) then
		return nil
	end

	if wep.IsValid and not wep:IsValid() then
		return nil
	end

	local class = wep.GetClass and wep:GetClass()

	return isstring(class) and class or false, wep, true
end

-- The ammo type the engine gives a weapon (by id), as a name; nil for none.
local function engineAmmo(wep, getter)
	local fn = wep[getter]

	if not isfunction(fn) then
		return nil
	end

	local id = fn(wep)

	if not isnumber(id) or id < 0 then
		return nil
	end

	return game.GetAmmoName(id)
end

local function tableAmmo(source, key)
	local t = source and source[key]
	local ammo = istable(t) and t.Ammo

	if isstring(ammo) and ammo ~= "" and string.lower(ammo) ~= "none" then
		return ammo
	end

	return nil
end

-- The secondary ammo of a weapon, by the engine's id first and the Secondary table else.
local function secondaryAmmo(wep, source, entity)
	return (entity and engineAmmo(wep, "GetSecondaryAmmoType")) or tableAmmo(source, "Secondary")
end

-- The result of a CustomAmmoDisplay (the table holohud2 reads), or nil.
local function customDisplay(class, wep, entity)
	if not entity or not isfunction(wep.CustomAmmoDisplay) then
		return nil
	end

	local ok, result = SafeCall(functionId(class or "?", "display"), wep.CustomAmmoDisplay, wep)

	return ok and istable(result) and result or nil
end

-- The value that one layer gives for a field, nil when it says nothing (or something invalid).
local function layerValue(layer, field)
	local value = layer[field]

	if value == nil then
		return nil
	end

	return CHECK[field](value)
end

-- A function given for `fire` is called with the weapon: its answer must be one of the modes.
local function callFire(class, fn, wep, entity)
	if not entity then
		return nil
	end

	local ok, mode = SafeCall(functionId(class or "?", "fire"), fn, wep)

	if ok and isstring(mode) and FIRE[mode] then
		return mode
	end

	return nil
end

local function declaredValue(field, class, wep, source, entity)
	local entry = entryFor(class)
	local value = entry and entry[field]

	if value == nil and istable(source) and istable(source.GryHUD) then
		value = layerValue(source.GryHUD, field)
	end

	if value == nil and entity then
		for _, adapter in ipairs(adapters) do
			local ok, partial = SafeCall("adapter:" .. adapter.id, adapter.fn, wep)

			if ok and istable(partial) then
				value = layerValue(partial, field)

				if value ~= nil then
					break
				end
			end
		end
	end

	if isfunction(value) and field == "fire" then
		return callFire(class, value, wep, entity)
	end

	return value
end

local function defaultValue(field, class, wep, source, entity)
	if field == "fire" then
		local primary = istable(source) and source.Primary

		if istable(primary) and primary.Automatic ~= nil then
			return primary.Automatic and "auto" or "semi"
		end
	elseif field == "ammo" then
		return (entity and engineAmmo(wep, "GetPrimaryAmmoType")) or tableAmmo(source, "Primary")
	elseif field == "altAmmo" then
		return secondaryAmmo(wep, source, entity)
	elseif field == "counter" then
		local display = customDisplay(class, wep, entity)

		return display and display.Draw == false and "none" or "clip"
	end

	return nil
end

-- A grenade type of ammo that is not the hand grenade's: a launcher.
local function isLauncherAmmo(name)
	name = string.lower(name or "")

	return name ~= "grenade" and string.find(name, "grenade", 1, true) ~= nil
end

local resolveField

-- The value of one field of a weapon: declared (registry, GryHUD, adapters), else its default; nil when there is none.
-- explicit = true: no defaults. Does not allocate (the HUD asks every frame).
function API.WeaponValue(wep, field, explicit)
	local class, source, entity = identify(wep)

	if class == nil or not CHECK[field] then
		return nil
	end

	return resolveField(field, class, wep, source, entity, explicit)
end

resolveField = function(field, class, wep, source, entity, explicit)
	local value = declaredValue(field, class, wep, source, entity)

	if value ~= nil or explicit then
		return value
	end

	value = defaultValue(field, class, wep, source, entity)

	if value ~= nil then
		return value
	end

	if field == "alt" then
		return isLauncherAmmo(resolveField("altAmmo", class, wep, source, entity)) and "grenade" or "none"
	elseif field == "altShoots" then
		return ALT_SHOOTS[resolveField("alt", class, wep, source, entity)] == true
	elseif field == "crosshair" then
		return true -- the HUD's crosshair is shown unless the weapon says it is not
	end

	return nil
end

-- The final description of a weapon, the one the HUD uses: a table with the fields of a definition (fire, burst, ammo, counter,
-- alt, altAmmo, altShoots, altLabel, altIcon, icon, slotIcon, crosshair) plus `display` (the numbers of CustomAmmoDisplay, when it has them).
-- wep is the weapon entity, or its class name (then only what is declared or read from the stored SWEP counts). nil for an invalid
-- weapon. explicit = true: only what is declared (registry, GryHUD, adapters), no defaults, no alt/altShoots/counter fallbacks.
function API.ResolveWeapon(wep, explicit)
	local class, source, entity = identify(wep)

	if class == nil then
		return nil
	end

	local result = {}

	for _, field in ipairs(FIELDS) do
		if field ~= "counter" then
			result[field] = resolveField(field, class, wep, source, entity, explicit)
		end
	end

	result.counter = declaredValue("counter", class, wep, source, entity)

	if not explicit then
		-- CustomAmmoDisplay is called once: it gives the default counter and the numbers
		local display = customDisplay(class, wep, entity)

		if result.counter == nil then
			result.counter = display and display.Draw == false and "none" or "clip"
		end

		if display and display.Draw ~= false then
			local numbers = {}

			for key, name in pairs({PrimaryClip = "clip", PrimaryAmmo = "ammo", SecondaryAmmo = "altAmmo", SecondaryClip = "altClip"}) do
				if isnumber(display[key]) then
					numbers[name] = display[key]
				end
			end

			result.display = numbers
		end
	end

	return result
end

API.AddFeature("weapons")
