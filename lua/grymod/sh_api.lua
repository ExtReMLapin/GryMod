-- The extension API of GryMod: ONE surface (GryMod.API) for the addons that plug into the suit and the HUD.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md. For developers: docs/api.md.
--
-- This shared file holds what both realms need: the presence test (GRYMOD_INSTALLED, GryMod.API.Version,
-- GryMod.GetInterfaceVersion), the list of optional parts (GryMod.API.Has) and GryMod.API.SafeCall, through which every
-- callback of a third party goes: a broken one never breaks the HUD and never spams the console.

GryMod = GryMod or {}

GRYMOD_INSTALLED = true

-- The addon's version, informative only (the release does not write it yet: "dev" is what a repository checkout says).
GryMod.Version = GryMod.Version or "dev"

local API = GryMod.API or {}
GryMod.API = API

-- The interface version: an integer, bumped ONLY by a breaking change. Additive features never bump it: ask Has.
API.Version = 1

function GryMod.GetInterfaceVersion()
	return API.Version
end

-- The optional parts that exist. A later part adds itself with API.AddFeature("weapons") when its file is loaded.
local features = API._features or {suit = true, relation = true, hudevents = true, safecall = true}
API._features = features

function API.Has(feature)
	return isstring(feature) and features[feature] == true
end

function API.AddFeature(feature)
	features[feature] = true
end

-- ---------------------------------------------------------------------------------------------------------
-- Safe calls (lesson of the hook-spam incident of 2026-11-21)
-- ---------------------------------------------------------------------------------------------------------

-- In a row: the errors of an id since its last success, and the ids that are disabled.
local LIMIT = 5
API.SafeCallLimit = LIMIT

local failures = API._failures or {}
local disabled = API._disabled or {}
API._failures, API._disabled = failures, disabled

-- "provider:x" is told as: provider 'x'. An id with no kind is told as: 'plain'.
local function describe(id)
	local kind, name = string.match(tostring(id), "^(%w+):(.+)$")

	if kind then
		return kind .. " '" .. name .. "'"
	end

	return "'" .. tostring(id) .. "'"
end

function API.SafeCallDisabled(id)
	return disabled[id] == true
end

-- Registering the id again (a new provider, a new handler) re-arms it.
function API.SafeCallReset(id)
	failures[id] = nil
	disabled[id] = nil
end

local function finish(id, ok, ...)
	if ok then
		failures[id] = nil

		return true, ...
	end

	local err = ...
	local count = (failures[id] or 0) + 1
	failures[id] = count

	if count >= LIMIT then
		disabled[id] = true
		MsgN("GryMod API: " .. describe(id) .. " disabled after " .. count .. " errors: " .. tostring(err))
	end

	return false, err
end

-- Calls fn(...) under pcall for the callback `id`. Returns what pcall returns: true and the results, or false and the
-- message. A disabled callback is not run: false, "disabled". The fifth error in a row disables the callback, with one
-- console line that says which one and why.
function API.SafeCall(id, fn, ...)
	if disabled[id] then
		return false, "disabled"
	end

	if not isfunction(fn) then
		return false, "not a function"
	end

	return finish(id, pcall(fn, ...))
end

-- ---------------------------------------------------------------------------------------------------------
-- HUD events: the message the server sends and the client reads (gry_api_hud, sv_api.lua and cl_api.lua)
-- ---------------------------------------------------------------------------------------------------------

-- The payload is a name and a small table of numbers, strings and booleans, bounded in size.
local LIMITS = {name = 32, fields = 8, key = 24, string = 128}
API.HUDEventLimits = LIMITS

local TYPE_NUMBER, TYPE_STRING, TYPE_BOOL = 0, 1, 2

local function validName(name, max)
	return isstring(name) and #name >= 1 and #name <= max and string.find(name, "^[%w_]+$") ~= nil
end

local function validNumber(n)
	return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

-- Whether a name (letters, digits and underscore, at most 32) is a valid HUD event name.
function API.IsValidHUDEventName(name)
	return validName(name, LIMITS.name)
end

-- Whether name and data (nil, or a table of at most 8 fields: key -> number, string or boolean) can be sent. Returns true,
-- or false and why.
function API.CheckHUDEvent(name, data)
	if not validName(name, LIMITS.name) then
		return false, "invalid event name"
	end

	if data == nil then
		return true
	end

	if not istable(data) then
		return false, "the data must be a table"
	end

	local count = 0

	for key, value in pairs(data) do
		count = count + 1

		if count > LIMITS.fields then
			return false, "too many fields (" .. LIMITS.fields .. " at most)"
		end

		if not validName(key, LIMITS.key) then
			return false, "invalid field name"
		end

		if isstring(value) then
			if #value > LIMITS.string then
				return false, "string too long in field '" .. key .. "'"
			end
		elseif not isbool(value) and not validNumber(value) then
			return false, "field '" .. key .. "' must be a finite number, a string or a boolean"
		end
	end

	return true
end

-- Writes the message (the caller has started it and checked it with CheckHUDEvent).
function API.WriteHUDEvent(name, data)
	local count = 0

	for _ in pairs(data or {}) do
		count = count + 1
	end

	net.WriteString(name)
	net.WriteUInt(count, 4)

	for key, value in pairs(data or {}) do
		net.WriteString(key)

		if isstring(value) then
			net.WriteUInt(TYPE_STRING, 2)
			net.WriteString(value)
		elseif isbool(value) then
			net.WriteUInt(TYPE_BOOL, 2)
			net.WriteBool(value)
		else
			net.WriteUInt(TYPE_NUMBER, 2)
			net.WriteDouble(value)
		end
	end
end

-- Reads the message: the name and the table, or nil when it breaks the bounds (it is dropped, never trusted).
function API.ReadHUDEvent()
	local name = net.ReadString()
	local count = net.ReadUInt(4)

	if not validName(name, LIMITS.name) or count > LIMITS.fields then
		return nil
	end

	local data = {}

	for _ = 1, count do
		local key = net.ReadString()
		local kind = net.ReadUInt(2)
		local value

		if kind == TYPE_STRING then
			value = net.ReadString()

			if #value > LIMITS.string then
				return nil
			end
		elseif kind == TYPE_BOOL then
			value = net.ReadBool()
		elseif kind == TYPE_NUMBER then
			value = net.ReadDouble()

			if not validNumber(value) then
				return nil
			end
		else
			return nil
		end

		if not validName(key, LIMITS.key) then
			return nil
		end

		data[key] = value
	end

	return name, data
end
