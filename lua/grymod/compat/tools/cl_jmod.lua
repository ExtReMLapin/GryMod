-- JMod (client): the armor of a camouflaged player. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it uses GryMod's public API
-- (AddPlayerPartsProvider, the hook GryMod_CloakChanged) and does nothing when JMod is not installed. Read in the public code of JMod (lua/jmod/cl_armor.lua of
-- github.com/Jackarunda/gmod), NOT tried in a game (not installed when this was written): check it with the real JMod, an armor on a camouflaged player in third person, in a
-- mirror and on another player.
--
-- What JMod does: each piece of armor is a client side model in `ply.EZarmorModels[id]`. A piece with the `merge` flag is bone merged to the player (SetParent + EF_BONEMERGE), so
-- the ENGINE draws it, as an entity of its own: when the camouflage hides the player (PrePlayerDraw) it stays in plain view around nobody. The other pieces are NoDraw: JMod draws
-- them by hand in its PostPlayerDraw hook, which GryMod's draw of the camouflaged player (ply:DrawModel() in its layers) runs again, inside the layers' render state, so they
-- already follow the player's refraction and need nothing here.
-- So: the bone merged pieces are given to GryMod (they get the layers and the fade of the body) and are kept out of the engine's draw while the camouflage lasts (SetNoDraw: a model
-- that GryMod draws by hand is drawn even so, as the weapon's proxy is); at the end of the camouflage the ones this patch hid are given back to the engine. A piece that JMod itself
-- put NoDraw (an armor that goes with a weapon it is put away for) is not touched.

local API = GryMod.API

if not API or not API.AddPlayerPartsProvider then
	return -- cl_api.lua is included first (grymod_shared.lua)
end

local KEY = "jmod_armor"
local HOOK = "GryMod compat jmod"

local hidden = setmetatable({}, {__mode = "k"}) -- [model] = true: the models this patch took out of the engine's draw

local function merged(model)
	return model ~= nil and IsValid(model) and isfunction(model.IsEffectActive) and model:IsEffectActive(EF_BONEMERGE)
end

API.AddPlayerPartsProvider(KEY, function(ply, out)
	local models = ply.EZarmorModels

	if not istable(models) or not istable(JMod) then
		return
	end

	for _, model in pairs(models) do
		if merged(model) then
			if hidden[model] then
				out[#out + 1] = model
			elseif not (isfunction(model.GetNoDraw) and model:GetNoDraw()) then
				hidden[model] = true
				model:SetNoDraw(true)
				out[#out + 1] = model
			end
		end
	end
end)

hook.Add("GryMod_CloakChanged", HOOK, function(ply, on)
	if on then
		return
	end

	local models = istable(ply) and ply.EZarmorModels

	if not istable(models) then
		return
	end

	for _, model in pairs(models) do
		if hidden[model] then
			hidden[model] = nil

			if IsValid(model) then
				model:SetNoDraw(false)
			end
		end
	end
end)
