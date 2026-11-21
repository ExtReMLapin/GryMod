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
