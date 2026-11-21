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

-- Declares the HUD event `name` (letters, digits, underscore, at most 32): fn(data) is called each time it plays, with the table
-- of the payload (empty when there is none). Registering the name again replaces the handler and re-arms it if it was disabled.
-- Returns true, or false and why not.
function API.RegisterHUDEvent(name, fn)
	if not API.IsValidHUDEventName(name) then
		return false, "invalid event name"
	end

	if not isfunction(fn) then
		return false, "invalid function"
	end

	API.SafeCallReset("hudevent:" .. name)
	handlers[name] = fn

	return true
end

-- Removes a HUD event; returns whether there was one.
function API.UnregisterHUDEvent(name)
	if handlers[name] == nil then
		return false
	end

	handlers[name] = nil

	return true
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

	return not ply:GetNWBool("GryDisabled", false)
end

-- The built-in events are registered by the module that draws them: this file may load first or last.
if GryMod.FlashBoot and GryMod.FlashBoot.RegisterEvents then
	GryMod.FlashBoot.RegisterEvents()
end
