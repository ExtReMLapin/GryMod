-- Suit malfunctions: the suit goes down for a few seconds (the original game's EMP: the suit is forced to armor
-- mode and deactivated, the HUD is destroyed, then it reboots; research-mech/NOTES.md and
-- research-ui2/crosshair-reboot.md). While down: the energy is 0 and does not recharge, the mode is ARMOR and cannot
-- change, the armor takes its minimum share only. At the end the suit restarts with an empty bar that recharges
-- normally, and the HUD plays its Reboot sequence (the client reads the state from the player's network values).
-- The causes (EMP, electric hits, heavy impacts) and the numbers are in sv_mechanics.lua and in
-- docs/superpowers/plans/2026-11-21-suit-malfunction-notes.md. Nothing here runs in Think: one timer per player that
-- is down, the damage call of sv_health.lua and the EMP hook.

GryMod = GryMod or {}

local Malfunction = {}
GryMod.Malfunction = Malfunction

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local master = CreateConVar("gry_malfunction", "1", flags, "Suit malfunctions: EMP, electric hits and heavy impacts put the suit down (0 turns them all off)")
local categories = {
	shock = CreateConVar("gry_malfunction_shock", "1", flags, "Electric hits (shock, energy beam, plasma, combine ball) drain the energy and can put the suit down"),
	impact = CreateConVar("gry_malfunction_impact", "1", flags, "A heavy machine (hunter, strider...) breaking the armor puts the suit down"),
	emp = CreateConVar("gry_malfunction_emp", "1", flags, "GryMod_EMP and gry_emp put the suits in range down")
}

-- Whether malfunctions are on (and, with a category, whether that cause is on).
function Malfunction.Enabled(category)
	if not master:GetBool() then
		return false
	end

	local convar = category and categories[category]

	return not convar or convar:GetBool()
end

function Malfunction.IsActive(ply)
	return IsValid(ply) and ply:GetNW2Bool("GryMalfunction", false)
end

-- Seconds left (0 when the suit works).
function Malfunction.Remaining(ply)
	if not Malfunction.IsActive(ply) or not ply.gryMalfunctionEnd then
		return 0
	end

	return math.max(0, ply.gryMalfunctionEnd - CurTime())
end

local function timerName(ply)
	return "GryMalfunction" .. ply:EntIndex()
end

-- The suit goes down (or stays down longer) for `seconds`. The reason ("emp", "shock", "overload", "impact") goes to
-- the GryMod_MalfunctionStart hook. Returns whether the suit is down after the call.
function Malfunction.Start(ply, seconds, reason)
	-- a suit that is off (GryMod.API.SetSuitEnabled) has nothing to put down
	if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) or not Malfunction.Enabled() or GryMod.Config.InfiniteArmor or ply:GetNW2Bool("GryDisabled", false) then
		return false
	end

	seconds = math.Clamp(tonumber(seconds) or GryMod.Mech.MalfunctionSeconds("emp"), 0.1, 60)

	local endTime = CurTime() + seconds
	local was = Malfunction.IsActive(ply)

	if was and ply.gryMalfunctionEnd and ply.gryMalfunctionEnd >= endTime then
		return true
	end

	ply.gryMalfunctionEnd = endTime
	ply.gryMalfunctionReason = reason

	if not was then
		ply:SetNW2Bool("GryMalfunction", true)

		-- the suit is forced to armor mode and the bar is empty
		if ply.Nanosuit_mode ~= GryMod.Modes.ARMOR then
			ply:SetNanosuitMode(GryMod.Modes.ARMOR, true)
		end

		ply:SetNW2Float("GryEnergy", 0)
		hook.Run("GryUseEnergy", ply)
		hook.Run("GryMod_MalfunctionStart", ply, seconds, reason)
	end

	timer.Create(timerName(ply), seconds, 1, function()
		Malfunction.End(ply)
	end)

	return true
end

-- The suit restarts: an empty bar that recharges after the usual delay, and a few seconds in which shocks cannot put
-- it down again.
function Malfunction.End(ply)
	if not Malfunction.IsActive(ply) then
		return
	end

	timer.Remove(timerName(ply))
	ply:SetNW2Bool("GryMalfunction", false)
	ply.gryMalfunctionEnd = nil
	ply.gryMalfunctionGrace = CurTime() + GryMod.Mech.MalfunctionGrace()
	ply:SetNW2Float("GryEnergy", 0)
	ply.energy_on_use = 0
	ply.next_energy_regen = CurTime() + GryMod.Mech.EnergyRechargeDelay()
	hook.Run("GryMod_MalfunctionEnd", ply)
end

-- Death, respawn and leaving: everything is forgotten, with no grace.
function Malfunction.Clear(ply)
	if not IsValid(ply) then
		return
	end

	timer.Remove(timerName(ply))
	ply:SetNW2Bool("GryMalfunction", false)
	ply:SetNW2Float("GryFlicker", 0)
	ply.gryMalfunctionEnd = nil
	ply.gryMalfunctionGrace = nil
	ply.gryMalfunctionPending = nil
end

function Malfunction.InGrace(ply)
	return (ply.gryMalfunctionGrace or 0) > CurTime()
end

-- The malfunction a hit asked for, started one frame later: the armor handler of sv_health.lua works on the energy
-- of this hit first, so the hit is absorbed as usual.
function Malfunction.Resolve(ply)
	local pending = IsValid(ply) and ply.gryMalfunctionPending

	if not pending then
		return
	end

	ply.gryMalfunctionPending = nil

	if not ply:Alive() or Malfunction.IsActive(ply) then
		return
	end

	-- an overload only happens if the bar really ended at 0
	if pending == "overload" and ply:GetNW2Float("GryEnergy") > 0 then
		return
	end

	Malfunction.Start(ply, GryMod.Mech.MalfunctionSeconds(pending), pending)
end

local function ask(ply, kind)
	ply.gryMalfunctionPending = kind

	timer.Simple(0, function()
		Malfunction.Resolve(ply)
	end)
end

-- Called first thing by the damage handler of sv_health.lua, before the armor works on the hit: electric hits burn
-- energy and may put the suit down, a heavy machine breaking the armor does too.
function Malfunction.OnDamage(ply, dmginfo)
	if not Malfunction.Enabled() or Malfunction.IsActive(ply) or not ply:Alive() or GryMod.Config.InfiniteArmor or ply:GetNW2Bool("GryDisabled", false) then
		return
	end

	local amt = dmginfo:GetDamage()

	if amt <= 0 then
		return
	end

	local Mech = GryMod.Mech
	local shock = Mech.ShockClass(dmginfo:GetDamageType(), amt, dmginfo:GetInflictor())
	local energy = ply:GetNW2Float("GryEnergy")
	local armor = ply.Nanosuit_mode == GryMod.Modes.ARMOR

	if shock and Malfunction.Enabled("shock") then
		local grace = Malfunction.InGrace(ply)

		if shock == "strong" then
			if not grace then
				ask(ply, "shock")
			end

			return
		end

		-- a light shock: the HUD flickers and the bar loses more than the armor takes
		local extra = Mech.ShockEnergyDrain(amt)
		ply:SetNW2Float("GryFlicker", CurTime() + Mech.ShockFlickerSeconds())
		ply:SetNW2Float("GryEnergy", math.max(0, energy - extra))
		hook.Run("GryUseEnergy", ply)

		if not grace and energy - extra - (armor and amt or 0) <= 0 then
			ask(ply, "overload")
		end

		return
	end

	if armor and amt >= Mech.HeavyImpactDamage() and amt >= energy and Malfunction.Enabled("impact") and not Malfunction.InGrace(ply) then
		local attacker = dmginfo:GetAttacker()

		if Mech.IsHeavyMachine(attacker) or Mech.IsHeavyMachine(dmginfo:GetInflictor()) then
			ask(ply, "impact")
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- EMP: hook.Run("GryMod_EMP", pos, radius, seconds) from any addon, or gry_emp to try it
-- ---------------------------------------------------------------------------------------------------------

local DEFAULT_RADIUS = 400

-- Every living player within `radius` units of `pos` (math.huge: everyone) goes down for `seconds` (the game's 10 s
-- by default). The grace does not protect from an EMP. Returns how many suits went down.
function Malfunction.EMP(pos, radius, seconds)
	if not Malfunction.Enabled("emp") then
		return 0
	end

	radius = tonumber(radius) or DEFAULT_RADIUS
	seconds = tonumber(seconds) or GryMod.Mech.MalfunctionSeconds("emp")

	local count = 0

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and (radius == math.huge or ply:WorldSpaceCenter():DistToSqr(pos) <= radius * radius) and Malfunction.Start(ply, seconds, "emp") then
			count = count + 1
		end
	end

	return count
end

hook.Add("GryMod_EMP", "GryMod malfunction", function(pos, radius, seconds)
	Malfunction.EMP(pos, radius, seconds)
end)

-- The server console, a superadmin, a game with sv_cheats 1 and single player may use gry_emp.
function Malfunction.MayTest(ply)
	if not IsValid(ply) then
		return true
	end

	local cheats = GetConVar("sv_cheats")

	return ply:IsSuperAdmin() or (cheats and cheats:GetBool()) or game.SinglePlayer()
end

-- gry_emp [seconds] [radius]: an EMP where the player stands (from the console: on everyone).
function Malfunction.RunTestCommand(ply, args)
	if not Malfunction.MayTest(ply) then
		return false
	end

	local seconds, radius = tonumber(args[1]), tonumber(args[2])

	if IsValid(ply) then
		hook.Run("GryMod_EMP", ply:GetPos(), radius or DEFAULT_RADIUS, seconds)
	else
		hook.Run("GryMod_EMP", vector_origin, math.huge, seconds)
	end

	return true
end

concommand.Add("gry_emp", function(ply, _, args)
	Malfunction.RunTestCommand(ply, args)
end)

-- ---------------------------------------------------------------------------------------------------------
-- Clean-up
-- ---------------------------------------------------------------------------------------------------------

-- PostPlayerDeath: Player:KillSilent skips PlayerDeath
hook.Add("PostPlayerDeath", "GryMod malfunction death", function(ply)
	Malfunction.Clear(ply)
end)

hook.Add("PlayerSpawn", "GryMod malfunction spawn", function(ply)
	Malfunction.Clear(ply)
end)

hook.Add("PlayerDisconnected", "GryMod malfunction leave", function(ply)
	Malfunction.Clear(ply)
end)
