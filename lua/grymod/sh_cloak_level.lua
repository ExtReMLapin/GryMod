-- The cloak level: how far the camouflage has faded in, from 0 (not cloaked) to 1 (fully cloaked), for the AI of other addons
-- (an enemy that sees a cloaked player fade out, or a guard that half sees him while it fades back in).
--
-- The cloak itself is a switch (the network switch GryCloak, sv_system.lua). At each real switch the server writes two stamps on the
-- player: GryCloakLvl0, the level at that moment, and GryCloakT0, the time. The level then moves from there toward 1 (cloaked) or 0
-- at 1 / gry_cloak_fade_seconds per second. Nothing runs between two switches: the level is computed when it is asked.
-- A re-cloak during the fade-out goes on from where the level was. A dead player is 0.

GryMod = GryMod or {}
GryMod.API = GryMod.API or {}

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)
local fade = CreateConVar("gry_cloak_fade_seconds", "2", flags,
	"Seconds the camouflage takes to fade in and out for the AI (0 = instant)", 0, 10)

-- The speed of the level, per second: 1 / the fade time, or math.huge for a fade of 0 s (an instant switch).
function GryMod.CloakFadeRate()
	local seconds = fade:GetFloat()

	if not (seconds > 0) then
		return math.huge
	end

	return 1 / seconds
end

-- The level at `now` for a switch that is `on` (cloaked) or off, that had `level0` at the time `t0`, moving at `rate` per second.
-- A clock that went back (now before t0) leaves level0 as it was.
function GryMod.CloakLevelFrom(on, level0, t0, now, rate)
	-- a fade of 0 s: the level is the switch itself
	if rate == math.huge then
		return on and 1 or 0
	end

	local elapsed = now - t0

	if not (elapsed > 0) then
		return level0
	end

	local step = rate * elapsed

	if on then
		if step >= 1 - level0 then
			return 1
		end

		return level0 + step
	end

	if step >= level0 then
		return 0
	end

	return level0 - step
end

-- How cloaked the player is now, 0 to 1. Server and client (the stamps and the switch are networked).
function GryMod.API.CloakLevel(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then
		return 0
	end

	return GryMod.CloakLevelFrom(ply:GetNW2Bool("GryCloak", false), ply:GetNW2Float("GryCloakLvl0", 0),
		ply:GetNW2Float("GryCloakT0", 0), CurTime(), GryMod.CloakFadeRate())
end

if GryMod.API.AddFeature then
	GryMod.API.AddFeature("cloaklevel")
end
