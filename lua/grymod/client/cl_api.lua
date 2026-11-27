-- The extension API, client side (GryMod.API, see sh_api.lua and docs/api.md): the HUD events. A HUD event is a named effect
-- the HUD plays (the start-up log, the emergency shutdown, the reboot...). The built-in ones (boot, reboot, lost, malfunction)
-- are registered by the Flash module that draws them (cl_hud_boot_flash.lua); another addon registers its own with
-- RegisterHUDEvent. The server asks a client to play one with GryMod.API.HUDEvent(players, name, data) (sv_api.lua), which sends
-- the gry_api_hud message read here. Every handler goes through SafeCall: a broken one never breaks the HUD.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local handlers = {}
local infos = {}

-- What a tool (the debug window) may know of an event, from the optional third argument of RegisterHUDEvent:
--   label    the text of its button (the name by default)
--   variants {{label = "...", data = {...}}, ...}: one button each, playing the event with that data (mode: the four modes)
--   follows  {{"convar", "what this option switches off"}, ...}: the player's options that cut the effect
-- A badly formed piece is left out, never an error.
local MAX_LABEL = 64

local function cleanInfo(name, info)
	local clean = {label = name}

	if not istable(info) then
		return clean
	end

	if isstring(info.label) and info.label ~= "" and #info.label <= MAX_LABEL then
		clean.label = info.label
	end

	if istable(info.variants) then
		local variants = {}

		for _, variant in ipairs(info.variants) do
			if istable(variant) and isstring(variant.label) and variant.label ~= "" and #variant.label <= MAX_LABEL
				and (variant.data == nil or istable(variant.data)) then
				variants[#variants + 1] = {label = variant.label, data = variant.data and table.Copy(variant.data) or nil}
			end
		end

		if #variants > 0 then
			clean.variants = variants
		end
	end

	if istable(info.follows) then
		local follows = {}

		for _, option in ipairs(info.follows) do
			if istable(option) and isstring(option[1]) and option[1] ~= "" and isstring(option[2]) then
				follows[#follows + 1] = {option[1], option[2]}
			end
		end

		if #follows > 0 then
			clean.follows = follows
		end
	end

	return clean
end

-- Declares the HUD event `name` (letters, digits, underscore, at most 32): fn(data) is called each time it plays, with the table
-- of the payload (empty when there is none). Registering the name again replaces the handler and re-arms it if it was disabled.
-- info (optional) describes the event for tools, see above. Returns true, or false and why not.
function API.RegisterHUDEvent(name, fn, info)
	if not API.IsValidHUDEventName(name) then
		return false, "invalid event name"
	end

	if not isfunction(fn) then
		return false, "invalid function"
	end

	API.SafeCallReset("hudevent:" .. name)
	handlers[name] = fn
	infos[name] = cleanInfo(name, info)

	return true
end

-- Removes a HUD event; returns whether there was one.
function API.UnregisterHUDEvent(name)
	if handlers[name] == nil then
		return false
	end

	handlers[name] = nil
	infos[name] = nil

	return true
end

-- The names of the registered HUD events, sorted.
function API.ListHUDEvents()
	local names = {}

	for name in pairs(handlers) do
		names[#names + 1] = name
	end

	table.sort(names)

	return names
end

-- A copy of what an event says of itself: {label = ..., variants = ..., follows = ...} (variants and follows only when it gave
-- some; the label is the name by default), or nil when there is no such event.
function API.GetHUDEventInfo(name)
	if handlers[name] == nil or infos[name] == nil then
		return nil
	end

	return table.Copy(infos[name])
end

-- Plays the HUD event `name` on this client. Returns true when the handler ran, false and why otherwise ("unknown event", or the
-- error of the handler). The hook GryMod_HUDEvent(name, data) is fired after the handler, when it ran without error.
function API.HUDEvent(name, data)
	local handler = handlers[name]

	if not handler then
		return false, "unknown event"
	end

	data = data or {}

	local ok, err = API.SafeCall("hudevent:" .. name, handler, data)

	if not ok then
		return false, err
	end

	hook.Run("GryMod_HUDEvent", name, data)

	return true
end

-- The message of the server: read with the shared bounds (a message that breaks them is dropped), then played.
function API.ReceiveHUDEvent()
	local name, data = API.ReadHUDEvent()

	if name then
		API.HUDEvent(name, data)
	end
end

net.Receive("gry_api_hud", API.ReceiveHUDEvent)

-- Whether the suit of this player is on (the server's GryMod.API.SetSuitEnabled): the HUD is hidden when it is off.
function API.IsSuitEnabled(ply)
	if not isentity(ply) or not IsValid(ply) then
		return false
	end

	return not ply:GetNW2Bool("GryDisabled", false)
end

-- The built-in events are registered by the module that draws them: this file may load first or last.
if GryMod.FlashBoot and GryMod.FlashBoot.RegisterEvents then
	GryMod.FlashBoot.RegisterEvents()
end

-- ---------------------------------------------------------------------------------------------------------
-- Weapon parts: the models a weapon draws itself
-- ---------------------------------------------------------------------------------------------------------

-- A weapon can draw models of its own that are not its view model: the attachments of a weapon base (a sight, a silencer, a laser). The engine does not know them, so
-- the suit's effects (the camouflage of the arms and the gun in first person) would leave them plain. A provider says which they are, for a weapon, at the moment it
-- is asked: GryMod keeps no list, so an attachment that is changed while the effect runs is the next frame's list. The weapon bases that need this have their provider
-- in lua/grymod/compat/weapons/ (docs/compat.md); an addon with its own weapons registers its own.
--
--   GryMod.API.AddWeaponPartsProvider(id, function(weapon, out) ... end)   the function appends the entities (client side models) to `out`
--   GryMod.API.RemoveWeaponPartsProvider(id)
--   GryMod.API.GetWeaponParts(weapon, out)                                 fills `out` (the caller's table, reused) and returns it with the count
--
-- A provider runs under SafeCall (five errors in a row switch it off; adding it again re-arms it), what it gives is checked (valid entities only) and the list holds
-- MAX_WEAPON_PARTS at most. The same id replaces the provider, so a file that is loaded twice does not make every part twice.
API.MAX_WEAPON_PARTS = 16

local partsProviders = API._weaponPartsProviders or {} -- {{id, fn, callId}, ...} in the order they were added
API._weaponPartsProviders = partsProviders

function API.AddWeaponPartsProvider(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	local callId = "parts:" .. id

	API.SafeCallReset(callId)

	for _, provider in ipairs(partsProviders) do
		if provider.id == id then
			provider.fn = fn

			return true
		end
	end

	partsProviders[#partsProviders + 1] = {id = id, fn = fn, callId = callId}

	return true
end

function API.RemoveWeaponPartsProvider(id)
	for i, provider in ipairs(partsProviders) do
		if provider.id == id then
			table.remove(partsProviders, i)
			API.SafeCallReset(provider.callId)

			return true
		end
	end

	return false
end

-- Something the effects may draw: an entity that is valid (a table that answers IsValid is accepted for the tests' stand-ins).
local function drawable(ent)
	return (isentity(ent) or istable(ent)) and IsValid(ent)
end

function API.GetWeaponParts(weapon, out)
	out = out or {}

	for i = #out, 1, -1 do
		out[i] = nil
	end

	if not drawable(weapon) then
		return out, 0
	end

	local count, max = 0, API.MAX_WEAPON_PARTS

	for i = 1, #partsProviders do
		local provider = partsProviders[i]
		local ok = API.SafeCall(provider.callId, provider.fn, weapon, out)
		local top = #out

		-- what the provider appended is checked and compacted onto the parts kept so far; a provider that failed gives nothing
		local kept = count

		for j = count + 1, top do
			local ent = out[j]

			out[j] = nil

			if ok and kept < max and drawable(ent) then
				kept = kept + 1
				out[kept] = ent
			end
		end

		count = kept
	end

	return out, count
end

API.AddFeature("weaponparts")

-- ---------------------------------------------------------------------------------------------------------
-- Weapon menus (client)
-- ---------------------------------------------------------------------------------------------------------
-- Some weapon bases have a menu of their own to inspect and change the weapon in hand (the attachments, the ammunition). The weapon icon of the suit's quick menu opens
-- it, and only for a weapon that has one. GryMod knows none of them: a provider answers, for a weapon, with the function that opens its menu, or with nothing when the
-- weapon is not its own or has no menu to open. The weapon bases that need this have their provider in lua/grymod/compat/weapons/ (docs/compat.md); an addon with its
-- own weapons registers its own.
--
--   GryMod.API.AddWeaponMenuProvider(id, function(weapon) return function(weapon) ... end end)   answers the opener of the weapon's menu, or nil
--   GryMod.API.RemoveWeaponMenuProvider(id)
--   GryMod.API.GetWeaponMenu(weapon)                                                            the opener of the first provider that has one, or nil
--   GryMod.API.OpenWeaponMenu(weapon)                                                           runs it; true when a menu was there to open
--
-- A provider runs under SafeCall (five errors in a row switch it off; adding it again re-arms it) and must be cheap: the quick menu asks it while it is open. The same id
-- replaces the provider. An opener that raises an error is caught: the player's input never breaks.
local menuProviders = API._weaponMenuProviders or {} -- {{id, fn, callId}, ...} in the order they were added
API._weaponMenuProviders = menuProviders

function API.AddWeaponMenuProvider(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	local callId = "weaponmenu:" .. id

	API.SafeCallReset(callId)

	for _, provider in ipairs(menuProviders) do
		if provider.id == id then
			provider.fn = fn

			return true
		end
	end

	menuProviders[#menuProviders + 1] = {id = id, fn = fn, callId = callId}

	return true
end

function API.RemoveWeaponMenuProvider(id)
	for i, provider in ipairs(menuProviders) do
		if provider.id == id then
			table.remove(menuProviders, i)
			API.SafeCallReset(provider.callId)

			return true
		end
	end

	return false
end

function API.GetWeaponMenu(weapon)
	if not (isentity(weapon) or istable(weapon)) or not IsValid(weapon) then
		return nil
	end

	for i = 1, #menuProviders do
		local provider = menuProviders[i]
		local ok, opener = API.SafeCall(provider.callId, provider.fn, weapon)

		if ok and isfunction(opener) then
			return opener
		end
	end

	return nil
end

function API.OpenWeaponMenu(weapon)
	local opener = API.GetWeaponMenu(weapon)

	if not opener then
		return false
	end

	return pcall(opener, weapon)
end

API.AddFeature("weaponmenu")
