-- The suit's noises, for the hearing of other addons' AI (the smart soldier). GryMod tells them about the noises only the suit knows of:
--   GryMod_SuitNoise(ply, pos, radius, kind)
-- kinds: "strength_jump", "speed_sprint" (the start of a sprint), "cloak_on", "cloak_off", "cloak_fire" (a shot while the cloak level is
-- above 0, at most once a quarter second per player). `radius` is in units (GryMod.SuitNoiseRadius, which an addon may change); `pos` is the
-- player's position. A heavy landing, footsteps and the weapons' own sounds are generic: the listening addon hears those by itself.
--
-- Cost: listeners on GryMod's own report hooks, plus one cheap check on every server bullet. Nothing is returned anywhere: no sound, no
-- bullet and no mode is changed.

GryMod = GryMod or {}

GryMod.SuitNoiseRadius = GryMod.SuitNoiseRadius or {
	cloak_fire = 2000,
	strength_jump = 1000,
	speed_sprint = 800,
	cloak_on = 300,
	cloak_off = 300
}

local FIRE_GAP = 0.25

-- [player] = the time of the last cloak_fire
local lastFire = setmetatable({}, {__mode = "k"})

function GryMod.SuitNoiseReset()
	lastFire = setmetatable({}, {__mode = "k"})
end

-- Tells the addons about one noise of the suit. False for a kind that has no radius or a player that is not valid.
function GryMod.EmitSuitNoise(ply, kind)
	if not IsValid(ply) or not ply:IsPlayer() then
		return false
	end

	local radius = GryMod.SuitNoiseRadius[kind]

	if not radius then
		return false
	end

	hook.Run("GryMod_SuitNoise", ply, ply:GetPos(), radius, kind)

	return true
end

hook.Add("GryMod_StrengthJump", "GryMod suit noise", function(ply)
	GryMod.EmitSuitNoise(ply, "strength_jump")
end)

hook.Add("GryMod_SprintStart", "GryMod suit noise", function(ply)
	GryMod.EmitSuitNoise(ply, "speed_sprint")
end)

hook.Add("GryMod_ModeChanged", "GryMod suit noise", function(ply, mode, oldMode, reason)
	-- a respawn, or the client learning its real mode, makes no noise in the world
	if reason == GryMod.ModeReasons.SPAWN or reason == GryMod.ModeReasons.SYNC then
		return
	end

	if mode == GryMod.Modes.CLOAK and oldMode ~= GryMod.Modes.CLOAK then
		GryMod.EmitSuitNoise(ply, "cloak_on")
	elseif oldMode == GryMod.Modes.CLOAK and mode ~= GryMod.Modes.CLOAK then
		GryMod.EmitSuitNoise(ply, "cloak_off")
	end
end)

-- Whose shot: the player's, or the scripted weapon's whose owner is a player.
local function shooter(ent)
	if not IsValid(ent) then
		return nil
	end

	if ent:IsWeapon() then
		ent = ent:GetOwner()
	end

	if IsValid(ent) and ent:IsPlayer() then
		return ent
	end

	return nil
end

hook.Add("EntityFireBullets", "GryMod suit noise", function(ent, data)
	local ply = shooter(ent)

	if not ply or GryMod.API.CloakLevel(ply) <= 0 then
		return
	end

	local now = CurTime()
	local last = lastFire[ply]

	if last and now >= last and now - last < FIRE_GAP then
		return
	end

	lastFire[ply] = now
	GryMod.EmitSuitNoise(ply, "cloak_fire")
end)

GryMod.API.AddFeature("suitnoise")
