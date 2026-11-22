-- The suit mechanics' numbers. By default (gry_mechanics crysis) they are the ones the original game's code uses
-- (research notes: research-mech/NOTES.md and research-regen/FINDINGS.md), scaled from its 200 energy and 200
-- health to GryMod's 100 energy and the player's maximum health; gry_mechanics classic gives the earlier GryMod
-- numbers back. Every rule is a function here so that the hooks (sv_health.lua, sv_system.lua) only ask.

GryMod = GryMod or {}

local Mech = {}
GryMod.Mech = Mech

local convar = CreateConVar("gry_mechanics", "crysis", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"Suit rules: crysis (the original game's numbers) or classic (GryMod's earlier ones)")

-- GryMod.Config.Mechanics wins over the convar (the tests use it, and so can another addon). The base speeds option on 1 or 2 (gry_movement, sh_movement.lua)
-- means the original's rules too: its speeds and its energy go together.
function Mech.IsCrysis()
	if GryMod.Movement and GryMod.Movement.Enabled() then
		return true
	end

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

-- The run speed of the speed mode, which follows the energy (the game's speed multiplier of the plain sprint: x2.85 at the top
-- above a fifth of the bar, x1.4 from empty to a fifth, x1.3 empty; research-mech/SPEEDS.md). The plain sprint is 400 and the
-- top is 600 here, so the multipliers are put on that line (1 -> 400, 2.85 -> 600): x1.4 is 443.2 and x1.3 is 432.4, always
-- above the plain sprint. The earlier rule kept the top speed until the bar was empty, then fell back to 400.
-- With the base speeds option (gry_movement 1 or 2, sh_movement.lua) the line is the original's own (or its ratios on GMod's 400) and, above a fifth of
-- the bar, the multiplier CLIMBS from x1.3 to x2.85 in the first second of the sprint (`seconds`; without it the climb is taken as done).
local function bounds()
	if GryMod.Movement then
		return GryMod.Movement.Bounds()
	end

	return 400, 600
end

local function multiplierSpeed(multiplier)
	local plain, top = bounds()

	return plain + (multiplier - 1) / (2.85 - 1) * (top - plain)
end

function Mech.SpeedRunSpeed(energy, seconds)
	local plain, top = bounds()

	if not Mech.IsCrysis() then
		return energy > 0 and top or plain
	end

	if energy > 20 then
		if GryMod.Movement and GryMod.Movement.Enabled() and seconds then
			return multiplierSpeed(GryMod.Movement.SprintMultiplier(seconds))
		end

		return top
	elseif energy > 0 then
		return multiplierSpeed(1.4)
	end

	return multiplierSpeed(1.3)
end

-- Whether the player holds the sprint key and moves (a field so that a test can say it): the climb of the speed mode's sprint counts from there.
function Mech.SprintHeld(ply)
	return ply:KeyDown(IN_SPEED) and ply:GetVelocity():Length2DSqr() > 100
end

-- The run speed of a player in the speed mode follows the energy at every frame (the one place that sets it while in the mode:
-- the mode change sets the top speed, see SetNanosuitMode).
hook.Add("Think", "GryMod run speed", function()
	local movement = GryMod.Movement and GryMod.Movement.Enabled()

	for _, ply in ipairs(player.GetAll()) do
		if ply.Nanosuit_mode == GryMod.Modes.SPEED then
			-- the seconds of the sprint (only the base speeds option climbs): the start is stamped when the key is held, forgotten when it is let go
			local seconds

			if movement then
				if Mech.SprintHeld(ply) then
					ply.gry_sprint_since = ply.gry_sprint_since or CurTime()
					seconds = CurTime() - ply.gry_sprint_since
				else
					ply.gry_sprint_since = nil
					seconds = 0
				end
			end

			local run = Mech.SpeedRunSpeed(ply:GetNW2Float("GryEnergy"), seconds)

			if ply:GetRunSpeed() ~= run then
				ply:SetRunSpeed(run)
			end
		end
	end
end)

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

-- The registry entry (GryMod.API.RegisterTracked) of a class name or of an entity, or nil. The facts about the entities of the
-- game (the heavy machines, the electric inflictors) are fields of these entries, not tables of this file.
local function trackedOf(who)
	local API = GryMod.API

	if not API or not API.GetTracked then
		return nil
	end

	if isstring(who) then
		return API.GetTrackedByClass(who)
	end

	return API.GetTracked(who)
end

-- "light" or "strong" for an electric hit (nil when it is not one). An inflictor (a class name or an entity) whose entry says `shock`
-- gives that class whatever the damage type: the combine ball is "strong" in the stock entries.
function Mech.ShockClass(damageType, damage, inflictor)
	local entry = inflictor ~= nil and trackedOf(inflictor)

	if entry and entry.shock then
		return entry.shock
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

-- A hit from one of these that breaks the armor puts the suit down: a class name or an entity whose registry entry says `heavy`
-- (the hunter, strider, gunship and helicopter in the stock entries, any machine of another addon that registers one).
function Mech.IsHeavyMachine(who)
	local entry = who ~= nil and trackedOf(who)

	return entry and entry.heavy == true or false
end

function Mech.HeavyImpactDamage()
	return 25
end
