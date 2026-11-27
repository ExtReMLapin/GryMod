-- Glide, the client part (see sh_glide.lua): the camera Glide puts on its vehicles, the name it writes over a player, its dashboard and a key it uses too. Public API and hooks only:
-- GryMod.API.AddCameraOwner, CloakLevel, GetVehicleOf, the hook GryMod_CanUseView, and the hooks of Glide named below (READ in its code: Glide documents its functions in the wiki, not
-- its hooks). Nothing here changes anything while the player is not in a Glide vehicle, and the settings are the player's, each one optional.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local Compat = GryMod.GlideCompat or {}
GryMod.GlideCompat = Compat

local hideHud = CreateClientConVar("gry_glide_hide_hud", "0", true, false, "1: Glide's dashboard (the dial of a car, the list of the seats) is not drawn while GryMod's HUD is up")
local nvKey = CreateClientConVar("gry_glide_nv_key", "1", true, false, "1: in a Glide vehicle the night vision key does nothing when Glide uses that key too (N is its neutral gear)")

-- The Glide vehicle the local player sits in, or nil (a field: the tests replace it).
function Compat.LocalVehicle()
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return nil
	end

	local vehicle = Compat.VehicleOf and Compat.VehicleOf(ply)

	if IsValid(vehicle) then
		return vehicle
	end

	return nil
end

-- The key of the night vision, a button code, or nil (a field: the tests replace it).
function Compat.NightVisionKey()
	local nv = GryMod.NightVision

	if nv and nv.Key and nv.Key.Effective then
		return nv.Key.Effective()
	end

	return nil
end

-- Whether Glide has an action on this button (Glide.Config.binds: group -> action -> button, lua/glide/client/events.lua reads it the same way).
function Compat.GlideUsesKey(code)
	local binds = Glide and Glide.Config and Glide.Config.binds

	if not istable(binds) or not code or code <= 0 then
		return false
	end

	for _, actions in pairs(binds) do
		if istable(actions) then
			for _, button in pairs(actions) do
				if button == code then
					return true
				end
			end
		end
	end

	return false
end

-- ---------------------------------------------------------------------------------------------------------
-- Glide's camera
-- ---------------------------------------------------------------------------------------------------------
-- In a Glide vehicle Glide has the view (hooks CalcView, CreateMove...: lua/glide/client/camera.lua). GryMod then gives no view of its own, does not read the game's zoom key for the
-- binoculars (Glide zooms on it itself) and reads the heading of the radar, the compass and the damage arrows from the view really drawn.

if API.AddCameraOwner then
	API.AddCameraOwner("glide", function(ply)
		return IsValid(Compat.VehicleOf and Compat.VehicleOf(ply))
	end)
end

-- ---------------------------------------------------------------------------------------------------------
-- Glide's dashboard
-- ---------------------------------------------------------------------------------------------------------
-- Glide asks Glide_CanDrawHUD(vehicle) before it draws its HUD: the dial of a car in the bottom right corner (a third of the screen's height), the list of the seats... A player who finds it
-- crowds GryMod's HUD says so in the menu: nothing is hidden until he does.

hook.Add("Glide_CanDrawHUD", "GryModGlide", function(vehicle)
	if hideHud:GetBool() then
		return false
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The night vision key
-- ---------------------------------------------------------------------------------------------------------
-- N is the default key of the night vision and Glide's neutral gear. GryMod reads its keys on the buttons (the engine does not call a bind for them), so a press of N would do both. In a Glide
-- vehicle the night vision refuses the press of a key that Glide uses (the veto GryMod_CanUseView of the view API). A bind (+gry_nightvision) is blocked by Glide itself; the zoom
-- is closed in a vehicle by GryMod.

hook.Add("GryMod_CanUseView", "GryModGlide", function(kind, reason)
	if kind ~= "nightvision" or reason ~= "key" or not nvKey:GetBool() then
		return
	end

	if not Compat.LocalVehicle() then
		return
	end

	if Compat.GlideUsesKey(Compat.NightVisionKey()) then
		return false
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The settings (the Compatibility page, a tab for the base)
-- ---------------------------------------------------------------------------------------------------------

if GryMod.AddOptionTab then
	GryMod.AddOptionTab("compat", "Glide", function(root)
		GryMod.OptionNote(root, "Glide is a vehicle base. In its vehicles GryMod's suit works as on foot, and the radar lists the vehicles once the binoculars scanned them. A missile of Glide that follows your vehicle shows in the grenade warning.")
		GryMod.OptionBox(root, "Hide Glide's dashboard", "gry_glide_hide_hud", "Glide draws a dial in the bottom right corner of the screen (a third of its height) and the list of the seats. Hidden while you are in one of its vehicles; Glide's own settings are not changed.")
		GryMod.OptionBox(root, "Night vision key: not the one of Glide", "gry_glide_nv_key", "In a Glide vehicle the night vision key does nothing when Glide uses the same key (N is its neutral gear).")
	end, 60)
end
