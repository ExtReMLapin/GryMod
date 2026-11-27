-- Third person cameras of other addons (client): the camera owners (GryMod.API.AddCameraOwner, docs/api.md "The view") of the addons that put the camera of the player somewhere else.
-- While one of them has the view GryMod's binoculars give no view (no zoom stage, no sway: their CalcView would otherwise replace the camera by the eye's, or lose to it without a
-- word), do not read the game's zoom key, and the radar and the compass follow the view that is drawn. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing
-- happens, and no owner is put (an owner is asked at every frame), for an addon that is not installed.
--
-- What each reader looks at was READ in the addon's public source (none of them is installed here; the checks are made with stand-ins of what was read, tests/cl_compat_view_test.lua).
-- Each reads the addon's own switch and the same conditions its CalcView has before it returns a view, and answers exactly true or false:
--   Simple ThirdPerson   convar simple_thirdperson_enabled, hook CalcView "SimpleTP.Camera.View"            (simplethirdperson lua/autorun/thirdperson.lua:897-1030)
--   Enhanced ThirdPerson convar thirdperson_etp, not in a vehicle, alive; hook "ThirdpersonEnhanced_CalcView" (thirdperson_enhanced/thirdperson.lua:98-127)
--   DarkFated            convar third_person, not in a vehicle; hook "DarkFated.ThirdPerson"                 (lua/autorun/client/cl_thirdperson.lua:13)
--   tpcgm                convar tpc_enabled, not in a vehicle, dead only with tpc_deathcam, its disable hook "fortnite-camera-disable" (lua/autorun/sh_fortnite.lua:176-181)
--   Customisable Thirdperson  ctp:IsEnabled() (it also REMOVES every other CalcView hook, ours included, while it is on: ctp.lua:371-382)
--   ARC9 third person    ARC9.ShouldThirdPerson(), not in sights that force the first person (IronSights.ForceFP)  (arc9 cl_thirdperson.lua:16-35,258)
--   PAC                  the active camera part (pac.active_camera, shown and active), the editor's camera (pace.IsActive() and its hook "pac_editor"), and the camera a server imposes
--                        (LocalPlayer().has_calcview renewed in the last half second, hook "PAC_lockpart_calcview")   (pac3 camera.lua:284-366, editor/view.lua:512, net_combat.lua:2867)
-- A convar alone is not enough for the ones whose convar has a generic name: the addon's own hook must be there too.
--
-- The owners are put when the game is up (the addons define their convars and hooks when their own files load, which may be after this one), and once more a few seconds later for
-- an addon that sets itself up late. Nothing runs by itself: no Think, no timer that repeats.
--
-- A second thing, for Enhanced ThirdPerson: its HUDShouldDraw hook (thirdperson.lua:368-380) answers TRUE for CHudCrosshair as soon as its third person or its crosshair is off, so in
-- first person, if its hook is asked before ours (the hooks of an event are walked with pairs: no order), the game's crosshair comes back next to GryMod's. The hook is replaced once by a
-- wrapper that keeps the addon's answer except that one: it gives no answer when GryMod's own hook says to hide the crosshair and the player is not in third person (where GryMod's
-- crosshair is not drawn and the addon's own is the one to show).

GryMod = GryMod or {}

local T = GryMod.CompatThirdPerson or {}
GryMod.CompatThirdPerson = T

local function convar(name)
	return GetConVar(name)
end

local function on(name)
	local cv = convar(name)

	return cv ~= nil and cv:GetBool() == true
end

local function hasHook(event, id)
	local hooks = hook.GetTable()[event]

	return hooks ~= nil and hooks[id] ~= nil
end

local function inVehicle(ply)
	return IsValid(ply) and ply:InVehicle() == true
end

-- the readers: key -> {present = function() -> bool, active = function(ply) -> bool}
T.Readers = {
	["compat.simple_thirdperson"] = {
		present = function() return convar("simple_thirdperson_enabled") ~= nil and hasHook("CalcView", "SimpleTP.Camera.View") end,
		active = function() return on("simple_thirdperson_enabled") end
	},
	["compat.enhanced_thirdperson"] = {
		present = function() return convar("thirdperson_etp") ~= nil and hasHook("CalcView", "ThirdpersonEnhanced_CalcView") end,
		active = function(ply) return on("thirdperson_etp") and not inVehicle(ply) and ply:Alive() == true end
	},
	["compat.darkfated_thirdperson"] = {
		present = function() return convar("third_person") ~= nil and hasHook("CalcView", "DarkFated.ThirdPerson") end,
		active = function(ply) return on("third_person") and not inVehicle(ply) end
	},
	["compat.tpcgm"] = {
		present = function() return convar("tpc_enabled") ~= nil and hasHook("CalcView", "fortnite-camera") end,
		active = function(ply)
			if not on("tpc_enabled") or inVehicle(ply) then
				return false
			end

			if ply:Alive() ~= true and not on("tpc_deathcam") then
				return false
			end

			return hook.Run("fortnite-camera-disable") ~= true
		end
	},
	["compat.customisable_thirdperson"] = {
		present = function() return istable(ctp) and isfunction(ctp.IsEnabled) end,
		active = function() return ctp:IsEnabled() == true end
	},
	["compat.arc9_thirdperson"] = {
		present = function() return istable(ARC9) and isfunction(ARC9.ShouldThirdPerson) end,
		active = function(ply)
			if ARC9.ShouldThirdPerson() ~= true then
				return false
			end

			-- ARC9's own CalcView gives the first person back in sights that ask for it
			local weapon = ply:GetActiveWeapon()

			if IsValid(weapon) and isfunction(weapon.GetInSights) and weapon:GetInSights() and istable(weapon.IronSights) and weapon.IronSights["ForceFP"] then
				return false
			end

			return true
		end
	},
	["compat.pac_camera"] = {
		present = function() return istable(pac) end,
		active = function(ply)
			-- a camera part that is shown and active (HandleCameraPart gives its view while one is chosen)
			local part = pac.active_camera

			if part ~= nil and IsValid(part) and not part:IsHidden() and not part.inactive then
				return true
			end

			-- the editor's camera
			if istable(pace) and isfunction(pace.IsActive) and pace.IsActive() and hasHook("CalcView", "pac_editor") then
				return true
			end

			-- a camera a server imposes: the addon lets it go half a second after the last message
			if ply.has_calcview == true and isnumber(ply.last_calcview) and ply.last_calcview + 0.5 > CurTime() and hasHook("CalcView", "PAC_lockpart_calcview") then
				return true
			end

			return false
		end
	}
}

-- an answer that is exactly true or false, whatever the addon's switch is
local function strict(reader)
	return function(ply)
		return reader.active(ply) == true
	end
end

-- Puts the owner of each addon that is there, takes away the owner of one that is not. Safe to call again (the same key replaces the owner).
function T.Install()
	local api = GryMod.API

	if not api or not api.AddCameraOwner then
		return
	end

	for key, reader in pairs(T.Readers) do
		local ok, present = pcall(reader.present)

		if ok and present == true then
			api.AddCameraOwner(key, strict(reader))
		else
			api.RemoveCameraOwner(key)
		end
	end

	T.FixEnhancedCrosshair()
end

-- ---------------------------------------------------------------------------------------------------------
-- Enhanced ThirdPerson: the game's crosshair
-- ---------------------------------------------------------------------------------------------------------

local ETP_ID = "ThirdpersonEnhanced_HUDShouldDraw"

-- the wrappers of this file and of its earlier loads (a file loaded again must not take a wrapper for the addon's own hook)
T.wrappers = T.wrappers or setmetatable({}, {__mode = "k"})

local function wrapper(name)
	local answer = T.original(name)

	if answer == true and name == "CHudCrosshair" then
		local ply = LocalPlayer()
		local ours = hook.GetTable().HUDShouldDraw
		local ourHook = ours and ours.GRYCROSSHAIRHIDE

		if IsValid(ply) and not ply:ShouldDrawLocalPlayer() and isfunction(ourHook) and ourHook(name) == false then
			return nil
		end
	end

	return answer
end

T.wrappers[wrapper] = true

-- Puts the wrapper on the addon's HUDShouldDraw hook. True when it is there, false when the addon is not installed.
function T.FixEnhancedCrosshair()
	local hooks = hook.GetTable().HUDShouldDraw
	local current = hooks and hooks[ETP_ID]

	if not isfunction(current) then
		-- Enhanced ThirdPerson is there (its convar) but not the hook the patch replaces (it changed): the patch is off, the owner is told once the game is up
		if convar("thirdperson_etp") ~= nil and GryMod.API and GryMod.API.WarnPatchMissing then
			GryMod.API.WarnPatchMissing("Enhanced ThirdPerson", "the hook HUDShouldDraw " .. ETP_ID, function()
				local list = hook.GetTable().HUDShouldDraw

				return convar("thirdperson_etp") ~= nil and not (list and isfunction(list[ETP_ID]))
			end)
		end

		return false
	end

	if current == wrapper then
		return true
	end

	-- the wrapper of an earlier load is the current hook: the original is the one it kept
	if not T.wrappers[current] then
		T.original = current
	end

	hook.Add("HUDShouldDraw", ETP_ID, wrapper)

	return true
end

-- The addons define what the readers look at when their own files load, which may be after this one: asked again when the game is up, and once more a little later for an addon that
-- sets itself up late (a one-shot timer, nothing repeats).
hook.Add("InitPostEntity", "GryMod compat third person", function()
	T.Install()
	timer.Simple(10, T.Install)
end)

-- (this file loaded in a running game: the addons are there already)
if IsValid(LocalPlayer()) then
	T.Install()
end
