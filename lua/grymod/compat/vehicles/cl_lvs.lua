-- LVS (client): the camera and the use prompt. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing when LVS is not installed. The shared half is
-- sh_lvs.lua (read its header for what was read in LVS's code).
--
-- The camera: LVS owns the view of a player who sits in one of its vehicles (its CalcView hook "!!!!LVS_calcview", with its own third person, mouse aim and optics; the final view
-- is in `Player:lvsGetView()`), so the binoculars give no view there, do not read the game's zoom key, and the radar's heading is the one of the view that is drawn
-- (GryMod.API.AddCameraOwner).
--
-- The prompt: a vehicle that is locked, wrecked or kept to another team (LVS's IsUseAllowed) answers the key with a sound and nothing else: no "ENTER VEHICLE"
-- (GryMod.API.AddUsableFilter).

GryMod = GryMod or {}

local API = GryMod.API
local L = GryMod.CompatLVS

if not API or not L or not API.AddCameraOwner or not API.AddUsableFilter then
	return -- sh_lvs.lua and cl_api.lua are included first (grymod_shared.lua)
end

-- True while LVS drives the view of this player: he sits in one of its vehicles and no other entity has the view (LVS's CalcView gives up when GetViewEntity is not the player).
function L.OwnsView(ply)
	if not IsValid(ply) or not isfunction(ply.GetViewEntity) or ply:GetViewEntity() ~= ply then
		return false
	end

	return L.VehicleOf(ply) ~= nil
end

-- false (no prompt) for a vehicle the key does nothing for; no opinion for everything else.
function L.UsableFilter(ent, ply)
	if L.UseRefused(ent, ply) then
		return false
	end

	return nil
end

-- Idempotent; false when LVS is not installed.
function L.InstallClient()
	if not L.Present() then
		return false
	end

	API.AddCameraOwner("lvs", L.OwnsView)
	API.AddUsableFilter("lvs", L.UsableFilter)

	return true
end

function L.UninstallClient()
	API.RemoveCameraOwner("lvs")
	API.RemoveUsableFilter("lvs")
end

if L.Present() then
	L.InstallClient()
end

hook.Add("LVS:Initialize", "GryMod compat LVS client", function()
	L.InstallClient()
end)

hook.Add("InitPostEntity", "GryMod compat LVS client", function()
	L.InstallClient()
end)
