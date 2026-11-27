-- ARC9 (client): the attachments of an ARC9 weapon are models the weapon draws itself, so the suit's camouflage left them plain over a camouflaged gun (a scope, a
-- suppressor, a launcher under the barrel: measured with a real ARC9 weapon). ARC9 keeps them in the weapon's VModel, a list of client side models (one for each installed
-- attachment, and for each duplicate of it), drawn by its own DrawCustomModel inside the view model's draw. This patch tells GryMod which those models are, for an ARC9
-- weapon (GryMod.API.AddWeaponPartsProvider, docs/compat.md), from ARC9's own list at the moment it is asked: nothing is kept, so an attachment that the player changes during
-- the camouflage is the next frame's list. It applies ARC9's own rule for which models are drawn (not an animation proxy, not hidden by a bone, not switched off with NoDraw,
-- not the charm that hangs from another model) and adds the charm model of an attachment, which ARC9 draws on its own. Part of the compatibility patches: it only reads ARC9's
-- list, answers nothing for a weapon that is not ARC9's, does nothing when ARC9 is not installed and never raises an error.

local API = GryMod.API

if not API or not API.AddWeaponPartsProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

API.AddWeaponPartsProvider("compat.arc9", function(weapon, out)
	if weapon.ARC9 ~= true then
		return
	end

	local models = weapon.VModel

	if not istable(models) then
		return
	end

	for i = 1, #models do
		local model = models[i]

		if IsValid(model) and not model.IsAnimationProxy and not model.hidden and not model.NoDraw and not model.charmparent then
			out[#out + 1] = model

			local charm = model.charmmdl

			if IsValid(charm) then
				out[#out + 1] = charm
			end
		end
	end
end)
