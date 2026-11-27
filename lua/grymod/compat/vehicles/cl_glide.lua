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

-- The seat of the local player in his Glide vehicle (1 is the driver's), or nil (a field: the tests replace it).
function Compat.LocalSeat()
	local ply = LocalPlayer()

	if IsValid(ply) and isfunction(ply.GlideGetSeatIndex) then
		return ply:GlideGetSeatIndex()
	end

	return nil
end

-- The groups of controls Glide reads for this seat of this vehicle, as a set; nil when they are not known (every group then counts). ENT:GetInputGroups(seatIndex) is a SERVER function
-- (the clients never have it), so the client works the groups out from what the base classes answer: general + land for a car, a motorcycle, a tank or a boat, general + aircraft for a
-- helicopter or a plane, general only for a passenger. VehicleType: CAR 1, MOTORCYCLE 2, HELICOPTER 3, PLANE 4, TANK 5, BOAT 6 (autorun/sh_glide.lua).
local LAND_TYPES = {[1] = true, [2] = true, [5] = true, [6] = true}
local AIR_TYPES = {[3] = true, [4] = true}

local function readGroups(vehicle, seat)
	if not vehicle or not isnumber(seat) then
		return nil
	end

	if seat > 1 then
		return {general_controls = true}
	end

	local kind = vehicle.VehicleType

	if LAND_TYPES[kind] then
		return {general_controls = true, land_controls = true}
	end

	if AIR_TYPES[kind] then
		return {general_controls = true, aircraft_controls = true}
	end

	return nil
end

-- Whether Glide has an action on this button (Glide.Config.binds: group -> action -> button, lua/glide/client/events.lua reads it the same way), among the groups the seat reads when
-- the vehicle and the seat are given.
function Compat.GlideUsesKey(code, vehicle, seat)
	local binds = Glide and Glide.Config and Glide.Config.binds

	if not istable(binds) or not code or code <= 0 then
		return false
	end

	local groups = readGroups(vehicle, seat)

	for group, actions in pairs(binds) do
		if istable(actions) and (groups == nil or groups[group]) then
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

	local vehicle = Compat.LocalVehicle()

	if not vehicle then
		return
	end

	-- the keys Glide reads depend on the seat: N, the neutral gear, is a land control (the driver of a car), not an aircraft's or a passenger's
	if Compat.GlideUsesKey(Compat.NightVisionKey(), vehicle, Compat.LocalSeat()) then
		return false
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The use prompt of a trailer
-- ---------------------------------------------------------------------------------------------------------
-- A trailer has no seat, but Glide's override of Entity:IsVehicle makes it a vehicle for the stock "ENTER VEHICLE" entry: no prompt for it.

if API.AddUsableFilter then
	API.AddUsableFilter("glide", function(ent)
		if Compat.IsTrailer and IsValid(ent) and ent.IsGlideVehicle == true and Compat.IsTrailer(ent) then
			return false
		end

		return nil
	end)
end

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
