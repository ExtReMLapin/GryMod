-- DrGBase (client): a player who possesses a nextbot sees through the nextbot's camera (DrGBase's own CalcView, in the third person): another camera has the view, so the suit's own zoom
-- and the binoculars must not take it (GryMod.API.AddCameraOwner). Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): the owner answers no when DrGBase is not installed
-- (a player has no DrG_IsPossessing then). Read from DrGBase's source (drgbase/possession.lua: the CalcView hook "DrGBasePossessionCalcView").

local API = GryMod.API

if not API or not API.AddCameraOwner then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

API.AddCameraOwner("compat.drgbase", function(ply)
	return isfunction(ply.DrG_IsPossessing) and ply:DrG_IsPossessing() == true
end)
