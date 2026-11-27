-- Draconic Base (client): the binoculars' zoom key works with a Draconic gun in hand. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only reads GryMod's own
-- state and replaces one hook of the base by a wrapper (like the EMP of sv_draconic.lua), does nothing when the base is not installed and never raises an error into Draconic's code.
--
-- What went wrong: the base adds a CalcView hook "!DrcLerp" (the drag of the camera with the weapon's animations, drc_viewdrag) that returns a view EVERY frame while a non-melee Draconic
-- weapon is in hand. The first CalcView hook that returns a view ends the chain, so GryMod's own hook (GRYBINOCULARSZOOM, cl_hud_binoculars_flash.lua) never ran: the suit zoom saw that
-- "another addon took the view" (SuitZoom.Reason "viewtaken") and closed at once, and the key, short or long, did nothing. Measured in the game with a Halo gun (drc_m6s): that hook
-- returned a table, the other CalcView hooks of the base and ours returned nil.
--
-- The wrapper gives no view while the binoculars have the view (the zoom is open, or the picture is on screen: opening, up, closing), so the chain goes on to ours. The drag of the camera
-- is only left out for that time; the base's own function runs as before the rest of the time.

local API = GryMod.API

if not API or not API.WarnPatchMissing then
	return -- sv_api.lua / cl_api.lua are included first (grymod_shared.lua)
end

local ID = "!DrcLerp"

local V = GryMod.DraconicView or {}
GryMod.DraconicView = V

V.wrappers = V.wrappers or setmetatable({}, {__mode = "k"})

-- Whether the binoculars have the view now.
function V.Yield()
	local zoom, bino = GryMod.SuitZoom, GryMod.FlashBinoculars

	return (zoom ~= nil and zoom.IsActive() == true) or (bino ~= nil and bino.IsUp() == true)
end

-- Puts the wrapper on the hook of the base. True when it is there (also when it already was), false when Draconic is not installed or its hook is not there.
function V.Install()
	if not istable(_G.DRC) then
		return false
	end

	local calc = hook.GetTable().CalcView
	local current = calc ~= nil and calc[ID] or nil

	if not isfunction(current) then
		-- Draconic is there but its hook is not (Draconic changed): the patch is off, the owner is told once the game is up
		API.WarnPatchMissing("Draconic Base", "the CalcView hook " .. ID, function()
			local t = hook.GetTable().CalcView

			return istable(_G.DRC) and not (t ~= nil and isfunction(t[ID]))
		end)

		return false
	end

	if V.wrappers[current] then
		return true
	end

	local original = current

	local function wrapper(...)
		if V.Yield() then
			return nil
		end

		return original(...)
	end

	V.wrappers[wrapper] = true
	hook.Add("CalcView", ID, wrapper)

	return true
end

-- Installed when the file loads (a reload in a running game) and when the game is up (Draconic adds its hook when its own files load, which is before this one: alphabetical order of the
-- autorun files, but the check costs nothing).
V.Install()

hook.Add("InitPostEntity", "GryMod compat draconic view", function()
	V.Install()
end)
