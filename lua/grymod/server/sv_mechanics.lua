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
