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

-- Runs the providers of a list on `subject` and gathers what they give into `out` (the caller's table, emptied first): a provider that failed gives nothing, what it
-- gave is checked (valid entities only) and compacted onto the parts kept so far, and `max` parts at most are kept. Returns out and the count.
local function gatherParts(providers, subject, out, max)
	out = out or {}

	for i = #out, 1, -1 do
		out[i] = nil
	end

	if not drawable(subject) then
		return out, 0
	end

	local count = 0

	for i = 1, #providers do
		local provider = providers[i]
		local ok = API.SafeCall(provider.callId, provider.fn, subject, out)
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

function API.GetWeaponParts(weapon, out)
	return gatherParts(partsProviders, weapon, out, API.MAX_WEAPON_PARTS)
end

API.AddFeature("weaponparts")

-- ---------------------------------------------------------------------------------------------------------
-- Player parts: the models a player wears
-- ---------------------------------------------------------------------------------------------------------

-- A player can wear models of his own that the engine does not know as part of him (armor, a backpack, an outfit of a mod): the camouflage of another player (or of the local
-- player in third person) would leave them plain. A provider says which they are, for a player, at the moment it is asked, exactly like the weapon parts above: the camouflage
-- lays its layers on them, with the same fade as on the body, for a player who is camouflaged, close enough to be drawn in detail. An addon that draws its parts itself hides
-- them instead, at the hook GryMod_CloakChanged(ply, on, level) (cl_cloak_fx.lua), which is run for every player at each change of his camouflage.
--
--   GryMod.API.AddPlayerPartsProvider(id, function(ply, out) ... end)   the function appends the entities (client side models) to `out`
--   GryMod.API.RemovePlayerPartsProvider(id)
--   GryMod.API.GetPlayerParts(ply, out)                                 fills `out` (the caller's table, reused) and returns it with the count
--
-- A provider runs under SafeCall (five errors in a row switch it off; adding it again re-arms it), what it gives is checked (valid entities only) and the list holds
-- MAX_PLAYER_PARTS at most. It is asked at every frame for each camouflaged player that is drawn in detail, and only when there is one: keep it cheap. The same id replaces the provider.
API.MAX_PLAYER_PARTS = 16

local playerProviders = API._playerPartsProviders or {} -- {{id, fn, callId}, ...} in the order they were added
API._playerPartsProviders = playerProviders

function API.AddPlayerPartsProvider(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	local callId = "playerparts:" .. id

	API.SafeCallReset(callId)

	for _, provider in ipairs(playerProviders) do
		if provider.id == id then
			provider.fn = fn

			return true
		end
	end

	playerProviders[#playerProviders + 1] = {id = id, fn = fn, callId = callId}

	return true
end

function API.RemovePlayerPartsProvider(id)
	for i, provider in ipairs(playerProviders) do
		if provider.id == id then
			table.remove(playerProviders, i)
			API.SafeCallReset(provider.callId)

			return true
		end
	end

	return false
end

function API.GetPlayerParts(ply, out)
	return gatherParts(playerProviders, ply, out, API.MAX_PLAYER_PARTS)
end

API.AddFeature("playerparts")

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

-- ---------------------------------------------------------------------------------------------------------
-- Plain views (client)
-- ---------------------------------------------------------------------------------------------------------
-- Some weapon bases show the weapon on a screen of their own: ARC9's customization menu turns the gun towards the player over a dark and blurred picture of the world.
-- The camouflage of the first person view copies the picture behind the gun before the weapon draws, so there it would show a world that is not the one on the screen,
-- and the player needs to see the parts he picks. A provider says, for a weapon, that its view is such a screen: the effects then draw the weapon plain. The weapon bases
-- that need this have their provider in lua/grymod/compat/weapons/ (docs/compat.md); an addon with its own weapons registers its own.
--
--   GryMod.API.AddPlainViewProvider(id, function(weapon) return true end)   true while the weapon's own screen has the view; anything else is a no
--   GryMod.API.RemovePlainViewProvider(id)
--   GryMod.API.IsPlainView(weapon)                                          true when a provider says so
--
-- A provider runs under SafeCall (five errors in a row switch it off; adding it again re-arms it) and must be cheap: it is asked at every frame the camouflage is on, in first
-- person. The same id replaces the provider.
local plainProviders = API._plainViewProviders or {} -- {{id, fn, callId}, ...} in the order they were added
API._plainViewProviders = plainProviders

function API.AddPlainViewProvider(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	local callId = "plainview:" .. id

	API.SafeCallReset(callId)

	for _, provider in ipairs(plainProviders) do
		if provider.id == id then
			provider.fn = fn

			return true
		end
	end

	plainProviders[#plainProviders + 1] = {id = id, fn = fn, callId = callId}

	return true
end

function API.RemovePlainViewProvider(id)
	for i, provider in ipairs(plainProviders) do
		if provider.id == id then
			table.remove(plainProviders, i)
			API.SafeCallReset(provider.callId)

			return true
		end
	end

	return false
end

function API.IsPlainView(weapon)
	if not (isentity(weapon) or istable(weapon)) or not IsValid(weapon) then
		return false
	end

	for i = 1, #plainProviders do
		local provider = plainProviders[i]
		local ok, plain = API.SafeCall(provider.callId, provider.fn, weapon)

		if ok and plain == true then
			return true
		end
	end

	return false
end

API.AddFeature("plainview")

-- ---------------------------------------------------------------------------------------------------------
-- Camera owners (client)
-- ---------------------------------------------------------------------------------------------------------
-- Some addons give the player a camera of their own (a drone, a security camera, a cinematic, a vehicle's special view). GryMod must leave such a view alone: the binoculars
-- and the suit's own zoom give no view (no field of view, no sway) and do not read the game's zoom key, and the heading of the radar, the compass and the damage arrows is
-- the one of the view that is really drawn. An owner says, for the local player, whether its camera has the view now.
--
--   GryMod.API.AddCameraOwner(key, function(ply) return true end)   true while this addon's camera has the view; anything else is a no
--   GryMod.API.RemoveCameraOwner(key)
--   GryMod.API.IsCameraOwned(ply)                                   true while any owner says so
--
-- An owner runs under SafeCall (five errors in a row switch it off; adding it again re-arms it) and must be cheap. It is asked once per frame and player (the answer is kept
-- for the frame), and only when there is one: with no owner this costs a table length. The same key replaces the owner.
local cameraOwners = API._cameraOwners or {} -- {{key, fn, callId}, ...} in the order they were added
API._cameraOwners = cameraOwners

local cameraFrame, cameraPly, cameraAnswer = -1, nil, false

local function forgetCamera()
	cameraFrame, cameraPly = -1, nil
end

function API.AddCameraOwner(key, fn)
	if not isstring(key) or key == "" or not isfunction(fn) then
		return false
	end

	local callId = "camera:" .. key

	API.SafeCallReset(callId)
	forgetCamera()

	for _, owner in ipairs(cameraOwners) do
		if owner.key == key then
			owner.fn = fn

			return true
		end
	end

	cameraOwners[#cameraOwners + 1] = {key = key, fn = fn, callId = callId}

	return true
end

function API.RemoveCameraOwner(key)
	for i, owner in ipairs(cameraOwners) do
		if owner.key == key then
			table.remove(cameraOwners, i)
			API.SafeCallReset(owner.callId)
			forgetCamera()

			return true
		end
	end

	return false
end

-- Whether another addon's camera has the view of this player. `fresh` (tests) asks the owners again in the same frame.
function API.IsCameraOwned(ply, fresh)
	local count = #cameraOwners

	if count == 0 then
		return false
	end

	local frame = FrameNumber()

	if not fresh and frame == cameraFrame and ply == cameraPly then
		return cameraAnswer
	end

	local owned = false

	for i = 1, count do
		local owner = cameraOwners[i]
		local ok, answer = API.SafeCall(owner.callId, owner.fn, ply)

		if ok and answer == true then
			owned = true

			break
		end
	end

	cameraFrame, cameraPly, cameraAnswer = frame, ply, owned

	return owned
end

API.AddFeature("cameraowner")

-- ---------------------------------------------------------------------------------------------------------
-- HUD suppressors (client)
-- ---------------------------------------------------------------------------------------------------------
-- An addon that draws a HUD of its own (a vehicle's dashboard, a drone's screen, a cinematic) can hide an element of GryMod's HUD while its own is up. A suppressor says,
-- for an element, whether to hide it now. The names are the ones of GryMod.HUDOptions.List ("radar", "crosshair", "status"...). A hidden element is not drawn and does nothing;
-- the player's own switch (gry_hud_<name>) is never written, so the element is back as soon as the suppressor says no. A suppressor cannot show what the player switched off.
--
--   GryMod.API.AddHudSuppressor(key, function(element, ply) return true end)   true hides the element; anything else leaves it
--   GryMod.API.RemoveHudSuppressor(key)
--   GryMod.API.IsHudSuppressed(element)                                        true while any suppressor hides it (what GryMod.HUDOptions.Enabled asks)
--
-- A suppressor runs under SafeCall (five errors in a row switch it off; adding it again re-arms it) and must be cheap. It is asked once per frame and element (the answer is kept
-- for the frame), and only when there is one: with no suppressor this costs a table length. The same key replaces the suppressor.
local hudSuppressors = API._hudSuppressors or {} -- {{key, fn, callId}, ...} in the order they were added
API._hudSuppressors = hudSuppressors

local hudFrame, hudAnswers = -1, {}

local function forgetHud()
	hudFrame = -1
end

function API.AddHudSuppressor(key, fn)
	if not isstring(key) or key == "" or not isfunction(fn) then
		return false
	end

	local callId = "hudsuppress:" .. key

	API.SafeCallReset(callId)
	forgetHud()

	for _, suppressor in ipairs(hudSuppressors) do
		if suppressor.key == key then
			suppressor.fn = fn

			return true
		end
	end

	hudSuppressors[#hudSuppressors + 1] = {key = key, fn = fn, callId = callId}

	return true
end

function API.RemoveHudSuppressor(key)
	for i, suppressor in ipairs(hudSuppressors) do
		if suppressor.key == key then
			table.remove(hudSuppressors, i)
			API.SafeCallReset(suppressor.callId)
			forgetHud()

			return true
		end
	end

	return false
end

-- Whether a suppressor hides this element. `fresh` (tests) asks them again in the same frame.
function API.IsHudSuppressed(element, fresh)
	local count = #hudSuppressors

	if count == 0 then
		return false
	end

	local frame = FrameNumber()

	if frame ~= hudFrame or fresh then
		hudFrame = frame

		for name in pairs(hudAnswers) do
			hudAnswers[name] = nil
		end
	elseif hudAnswers[element] ~= nil then
		return hudAnswers[element]
	end

	local ply, hidden = LocalPlayer(), false

	for i = 1, count do
		local suppressor = hudSuppressors[i]
		local ok, answer = API.SafeCall(suppressor.callId, suppressor.fn, element, ply)

		if ok and answer == true then
			hidden = true

			break
		end
	end

	hudAnswers[element] = hidden

	return hidden
end

API.AddFeature("hudsuppress")

-- ---------------------------------------------------------------------------------------------------------
-- The relation of an entity, as the client knows it
-- ---------------------------------------------------------------------------------------------------------
-- The relation chain (GryMod.API.Relation) only exists on the server: an NPC's attitude (Disposition) and the providers of the addons are not known to a client. The
-- crosshair's friendly cross already asks the server about the NPC it aims at; this is the same question for an addon's client code (a prompt that must not show on an
-- enemy, a marker). It goes through the crosshair's own rate limits, and the answers are kept for two seconds.
--
--   GryMod.API.ClientRelation(ent)   "ally", "neutral" or "hostile", or nil while the server has not answered yet (the question goes out in the background, at most five a second
--                                    in all, and the next call finds the answer; nil also for what is not an entity)
--
-- A player is answered at once, from the teams (the server's built-in rule). A client side entity that the server does not know (an index of 0 or less) is "neutral". Ask it
-- for the entity under the crosshair or a few at a time, not for a whole map in one frame: one question leaves every 0.2 s. Announced by Has("clientrelation").
function API.ClientRelation(ent)
	if not (isentity(ent) or istable(ent)) or not IsValid(ent) then
		return nil
	end

	local Cross = GryMod.FlashCrosshair

	if not Cross then
		return nil
	end

	if ent:IsPlayer() then
		return Cross.PlayerRelation(ent, LocalPlayer())
	end

	local index = ent:EntIndex()

	if index <= 0 or index > 8191 then
		return "neutral"
	end

	return Cross.RelationName(ent, RealTime())
end

API.AddFeature("clientrelation")

-- ---------------------------------------------------------------------------------------------------------
-- Usable filters (client)
-- ---------------------------------------------------------------------------------------------------------
-- The registry of usable entities (GryMod.API.RegisterUsable) says what the use key does, not who may use it: a prop protection (FPP, NADMOD), a locked vehicle, a door that only
-- its owner opens. The crosshair opens its "usable" state, and the use prompt comes up, for what the registry names. A filter lets an addon take the prompt away for an entity
-- this player may not use. It never adds one: an entity the registry does not call usable stays not usable.
--
--   GryMod.API.AddUsableFilter(id, function(ent, ply) return false end)   false: no prompt for this entity; anything else (nil, true...) is no opinion
--   GryMod.API.RemoveUsableFilter(id)
--   GryMod.API.UsableFiltered(ent, ply)                                   true when a filter says false (what the crosshair asks)
--
-- A filter runs under SafeCall (an error is no opinion; five errors in a row switch it off; adding it again re-arms it) and must be cheap: it is asked ten times a second at
-- most, for the one entity the player aims at, and only when the registry already calls it usable. The same id replaces the filter.
local usableFilters = API._usableFilters or {} -- {{id, fn, callId}, ...} in the order they were added
API._usableFilters = usableFilters

function API.AddUsableFilter(id, fn)
	if not isstring(id) or id == "" or not isfunction(fn) then
		return false
	end

	local callId = "usablefilter:" .. id

	API.SafeCallReset(callId)

	for _, filter in ipairs(usableFilters) do
		if filter.id == id then
			filter.fn = fn

			return true
		end
	end

	usableFilters[#usableFilters + 1] = {id = id, fn = fn, callId = callId}

	return true
end

function API.RemoveUsableFilter(id)
	for i, filter in ipairs(usableFilters) do
		if filter.id == id then
			table.remove(usableFilters, i)
			API.SafeCallReset(filter.callId)

			return true
		end
	end

	return false
end

function API.UsableFiltered(ent, ply)
	for i = 1, #usableFilters do
		local filter = usableFilters[i]
		local ok, answer = API.SafeCall(filter.callId, filter.fn, ent, ply)

		if ok and answer == false then
			return true
		end
	end

	return false
end

API.AddFeature("usablefilter")

-- ---------------------------------------------------------------------------------------------------------
-- The field of view of the view that is really drawn
-- ---------------------------------------------------------------------------------------------------------
-- Player:GetFOV is the player's own field of view: it does not follow what an addon's CalcView gives (a vehicle's zoom, a drone's camera, the binoculars' stages). The render
-- knows the one that is drawn. Measured: with a CalcView that gives 33, render.GetViewSetup().fov_unscaled is 33 (and .fov 43.1, scaled for the width of the screen).
--
--   GryMod.API.GetViewFov()   the horizontal field of view in degrees as CalcView gives it (4:3, like Player:GetFOV), of the view drawn at the last render; nil when the render
--                             does not know it yet (the first frames of a map)
--
-- Valid in any hook (it is the setup of the last main render). Used by the radar's view cone.
function API.GetViewFov()
	local setup = render.GetViewSetup()
	local fov = istable(setup) and setup.fov_unscaled

	if isnumber(fov) and fov == fov and fov > 0 then
		return fov
	end

	return nil
end

API.AddFeature("viewfov")

-- The hook GryMod_CanUseView(kind, reason) lets an addon whose own view must not be disturbed (a camera, a cinematic, a scripted scene) refuse the player's night vision (kind
-- "nightvision", cl_nightvision.lua) and the suit's own zoom (kind "zoom", cl_suit_zoom.lua) when they are about to switch on or open: a handler that returns false refuses; any
-- other answer is no opinion. `reason` is what asks ("key", "bind", "toggle", "api", "event", or "query" for a question that changes nothing). It is only asked at the moment of
-- switching on. For a view that is already there use GryMod.API.AddCameraOwner, which also closes them. Announced by Has("viewveto").
API.AddFeature("viewveto")
