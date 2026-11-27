-- DrGBase (server). Two things. (1) DrGBase's hearing only knows the sounds a player emits (EntityEmitSound); the noises of the suit (a strength jump, a sprint, a shot while camouflaged...)
-- are not sounds, GryMod tells them through the hook GryMod_SuitNoise, and this patch passes them on to the nextbots that can hear them, as the sound of the player (ENT:OnSound, which
-- spots him). A nextbot that ignores the player (DrGBase ignores a player with FL_NOTARGET: the camouflage) is not told: it could not act on it. (2) A player who is possessing a nextbot cannot
-- be hurt (DrGBase cancels that damage in its own EntityTakeDamage): the suit ignores those hits, so that the bar does not pay for damage that never comes (GryMod.API.AddHitFilter).
-- Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing happens when DrGBase is not installed. Read from DrGBase's source (detection.lua, possession.lua).

local API = GryMod.API

if not API or not API.AddHitFilter then
	return -- sv_api.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat drgbase"

-- Whether this nextbot hears a noise of `radius` units made at `pos` (DrGBase's own rule for a sound: the distance, scaled by the ear of the nextbot).
local function hears(nextbot, ply, pos, radius)
	if not IsValid(nextbot) or nextbot:IsDeaf() or nextbot:IsAIDisabled() or nextbot:IsIgnored(ply) then
		return false
	end

	local reach = radius * nextbot:GetHearingCoefficient()

	return nextbot:GetRangeSquaredTo(pos) <= reach * reach
end

hook.Add("GryMod_SuitNoise", KEY, function(ply, pos, radius, kind)
	local drg = _G.DrGBase

	if not istable(drg) or not isfunction(drg.GetNextbots) then
		return
	end

	for _, nextbot in ipairs(drg.GetNextbots()) do
		-- (a nextbot of a pack that raises an error must not stop the others, nor the hook of the suit that runs us)
		pcall(function()
			if hears(nextbot, ply, pos, radius) then
				nextbot:OnSound(ply, {Entity = ply, Pos = pos, SoundName = "", SoundLevel = 75, Volume = 1})
			end
		end)
	end
end)

API.AddHitFilter(KEY, function(ply)
	if isfunction(ply.DrG_IsPossessing) and ply:DrG_IsPossessing() == true then
		return "ignore"
	end

	return nil
end)
