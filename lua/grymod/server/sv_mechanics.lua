-- The suit mechanics' numbers. By default (gry_mechanics crysis) they are the ones the original game's code uses
-- (research notes: research-mech/NOTES.md and research-regen/FINDINGS.md), scaled from its 200 energy and 200
-- health to GryMod's 100 energy and the player's maximum health; gry_mechanics classic gives the earlier GryMod
-- numbers back. Every rule is a function here so that the hooks (sv_health.lua, sv_system.lua) only ask.

GryMod = GryMod or {}

local Mech = {}
GryMod.Mech = Mech

local convar = CreateConVar("gry_mechanics", "crysis", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Suit rules: crysis (the original game's numbers) or classic (GryMod's earlier ones)")

-- GryMod.Config.Mechanics wins over the convar (the tests use it, and so can another addon)
function Mech.IsCrysis()
	local choice = GryMod.Config and GryMod.Config.Mechanics or convar:GetString()

	return choice ~= "classic"
end

-- Energy per second given back, and the wait after the last use (re-armed at every drop of the energy).
function Mech.EnergyRechargeRate(mode, moving)
	if not Mech.IsCrysis() then
		return 7
	end

	if mode == GryMod.Modes.ARMOR then
		return 100 / (moving and 7 or 6)
	end

	return 100 / 8
end

function Mech.EnergyRechargeDelay()
	return Mech.IsCrysis() and 1 or 5
end

-- Energy per second of a speed sprint: the game takes 110 of 200 above a fifth of the bar and the bar still gives back
-- its 25 a second, so the net loss is 85 of 200 (research-mech/NOTES.md: about 1.9 s from full to a fifth); almost
-- nothing under it (the servo loop stops and the sprint goes on), none with an empty bar.
function Mech.SpeedDrain(energy)
	if not Mech.IsCrysis() then
		return GryMod.Config.speedEnergyDrain
	end

	if energy > 20 then
		return 42.5
	elseif energy > 0 then
		return 1.5
	end

	return 0
end

-- Energy per second of the cloak: half of 10 per metre a second moving (speed in units a second), at least 0.5.
function Mech.CloakDrain(speed)
	if not Mech.IsCrysis() then
		return GryMod.Config.cloakEnergyDrain * (speed / 100 + 0.6)
	end

	return math.max(2.5 * speed / 52.49, 0.5)
end

-- Whether the cloak gives out at this energy: under a tenth of the bar (the old rule: when one tick cannot be paid).
function Mech.CloakFailsAt(energy)
	return Mech.IsCrysis() and energy < 10
end

-- What a jump takes (and, for the strength jump, what must be in the bar).
function Mech.JumpCost(mode)
	if mode == GryMod.Modes.STRENGTH then
		return Mech.IsCrysis() and 35 or 40
	elseif mode == GryMod.Modes.SPEED and Mech.IsCrysis() then
		return 5
	end

	return 0
end

-- The least part of a hit the armor takes, even with an empty bar.
function Mech.ArmorMinimumAbsorption()
	return Mech.IsCrysis() and 0.3 or 0
end

-- Health: the wait after a hit, the seconds to regain everything (the game's Normal difficulty), the length of a
-- step (health comes back in whole steps once a second; the old rule was continuous).
function Mech.HealthDelay()
	return Mech.IsCrysis() and 2.5 or 3
end

function Mech.HealthRegenSeconds(mode, moving)
	if mode == GryMod.Modes.ARMOR then
		return moving and 15 or 10
	end

	return moving and 27 or 20
end

function Mech.HealthStepSeconds()
	return Mech.IsCrysis() and 1 or 0
end

-- The repair sound (not tied to the steps): armor mode, under 90 percent of the health, 30 seconds apart.
function Mech.RepairSoundDue(health, maxHealth, mode, now, last)
	return Mech.IsCrysis() and mode == GryMod.Modes.ARMOR and health < 0.9 * maxHealth and now - (last or -1000) >= 30
end

-- Whether a player is on the move (the game's threshold: 0.1 metre a second on the flat).
function Mech.IsMoving(ply)
	local velocity = ply:GetVelocity()

	return velocity:Length2D() > 0.1 * 52.49
end


-- ---------------------------------------------------------------------------------------------------------
-- Malfunctions (sv_malfunction.lua): the suit goes down. The original game's only cause is the EMP, and its
-- downtime is g_emp_nanosuit_downtime = 10 s (research-mech/NOTES.md); the shock rules are GryMod's own choices
-- (docs/superpowers/plans/2026-11-21-suit-malfunction-notes.md).
-- ---------------------------------------------------------------------------------------------------------

-- Seconds the suit stays down, by cause.
local MALFUNCTION_SECONDS = {emp = 10, shock = 5, overload = 5, impact = 3}

function Mech.MalfunctionSeconds(kind)
	return MALFUNCTION_SECONDS[kind] or MALFUNCTION_SECONDS.shock
end

-- After a restart the suit cannot be shocked down again for this long (a rollermine would lock it for ever).
function Mech.MalfunctionGrace()
	return 3
end

-- How long the HUD flickers on a light shock.
function Mech.ShockFlickerSeconds()
	return 0.8
end

local SHOCK_TYPES = bit.bor(DMG_SHOCK, DMG_ENERGYBEAM, DMG_PLASMA)
local STRONG_SHOCK = 25

-- "light" or "strong" for an electric hit (nil when it is not one). The combine ball is always strong.
function Mech.ShockClass(damageType, damage, inflictorClass)
	if inflictorClass == "prop_combine_ball" then
		return "strong"
	end

	if bit.band(damageType, SHOCK_TYPES) == 0 then
		return nil
	end

	return damage >= STRONG_SHOCK and "strong" or "light"
end

-- The energy a light shock burns on top of what the armor absorbs: 1.5 per point of damage, from 5 to 30.
function Mech.ShockEnergyDrain(damage)
	return math.Clamp(damage * 1.5, 5, 30)
end

local HEAVY_MACHINES = {npc_hunter = true, npc_strider = true, npc_combinegunship = true, npc_helicopter = true}

-- A hit from one of these that breaks the armor puts the suit down.
function Mech.IsHeavyMachine(class)
	return HEAVY_MACHINES[class] == true
end

function Mech.HeavyImpactDamage()
	return 25
end
