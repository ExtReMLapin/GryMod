-- ARC9 (server): the attacks of ARC9 weapons that are not bullets end the camouflage. An ARC9 gun fires through the engine's bullets, which the server already sees
-- (sv_system.lua; checked with a real weapon, with ARC9's physical bullets on). A bash (a knife's swing, a stab, the butt stroke of a gun), a shot of the launcher under the
-- barrel or of a weapon that fires an entity (a rocket, a grenade) and a thrown grenade are not bullets: ARC9 tells them with global hooks, and this patch passes them on to
-- GryMod.API.ReportAttack. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses ARC9's own hooks and GryMod's public API, does nothing when ARC9
-- is not installed (the hooks are never run) and never raises an error into ARC9's attack code.
--   * "Hook_Bash" runs at the moment of the blow of a bash (MeleeAttackShoot), hit or miss.
--   * "Hook_PrimaryAttack" runs for each shot about to be fired: a gun's bullets are seen by the server, so only the launcher (GetUBGL) and the weapons with a ShootEnt report.
--   * "Hook_GrenadeThrown" runs when a grenade leaves the hand.
-- The right click of an ARC9 gun is the sights: it is never an attack here (the launcher's is use + right click and fires a shot, which is reported as a shot).

local API = GryMod.API

if not API or not API.ReportAttack then
	return -- sv_api.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat arc9"

-- The player who holds the ARC9 weapon, or nil.
local function holder(weapon)
	if (not istable(weapon) and not isentity(weapon)) or weapon.ARC9 ~= true or not isfunction(weapon.GetOwner) then
		return nil
	end

	local owner = weapon:GetOwner()

	if IsValid(owner) and owner:IsPlayer() then
		return owner
	end

	return nil
end

local function report(weapon)
	local owner = holder(weapon)

	if owner then
		API.ReportAttack(owner, false)
	end
end

-- ARC9 runs these from the weapon's own code: an error here would break the weapon, so everything runs under pcall.
hook.Add("ARC9_Hook_Bash", KEY, function(weapon)
	pcall(report, weapon)

	return nil
end)

hook.Add("ARC9_Hook_GrenadeThrown", KEY, function(weapon)
	pcall(report, weapon)

	return nil
end)

hook.Add("ARC9_Hook_PrimaryAttack", KEY, function(weapon)
	pcall(function()
		if not holder(weapon) then
			return
		end

		local launcher = isfunction(weapon.GetUBGL) and weapon:GetUBGL()
		local entity = isfunction(weapon.GetProcessedValue) and weapon:GetProcessedValue("ShootEnt")

		if launcher or entity then
			report(weapon)
		end
	end)

	return nil
end)
