-- TFA (client): the attachments of a TFA weapon are models the weapon draws itself, so the suit's camouflage left them plain over a camouflaged gun (a reflex sight on a
-- TFA weapon, reported by the owner). TFA draws them in its own ViewModelDrawn, from the elements of its ViewModelElements: each element of type Model has a client side
-- model in `curmodel`. This patch tells GryMod which those models are, for a TFA weapon (GryMod.API.AddWeaponPartsProvider, docs/compat.md), from TFA's own tables at the moment it
-- is asked: nothing is kept, so an attachment that the player changes during the camouflage is the next frame's list. It applies TFA's own rule for which elements are drawn: type
-- Model, not hidden, a bone or an attachment point, and not switched off by the stat "ViewModelElements.<name>.active". Part of the compatibility patches: it only reads
-- TFA's tables, answers nothing for a weapon that is not TFA's, does nothing when TFA is not installed and never raises an error.

local API = GryMod.API

if not API or not API.AddWeaponPartsProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

-- the name of the stat that switches an element off, made once for each element name (a text built at every frame would be garbage)
local activeStats = {}

local function activeStat(name)
	local stat = activeStats[name]

	if not stat then
		stat = "ViewModelElements." .. name .. ".active"
		activeStats[name] = stat
	end

	return stat
end

API.AddWeaponPartsProvider("compat.tfa", function(weapon, out)
	if weapon.IsTFAWeapon ~= true or not isfunction(weapon.GetStatRawL) or not isfunction(weapon.GetStatL) then
		return
	end

	local order = weapon.vRenderOrder
	local elements = weapon:GetStatRawL("ViewModelElements")

	if not istable(order) or not istable(elements) then
		return
	end

	for i = 1, #order do
		local name = order[i]
		local element = elements[name]

		if istable(element) and element.type == "Model" and not element.hide and (element.bone or element.attachment) then
			local model = element.curmodel

			if IsValid(model) and weapon:GetStatL(activeStat(name)) ~= false then
				out[#out + 1] = model
			end
		end
	end
end)
