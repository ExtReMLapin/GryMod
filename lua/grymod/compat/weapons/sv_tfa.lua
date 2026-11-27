-- TFA (server): the attacks of TFA weapons that are not bullets end the camouflage. A TFA gun fires through the engine's bullets, which the server already sees (sv_system.lua).
-- A knife's stab, a bash and a grenade's low throw are not bullets: TFA tells them with hooks, and this patch passes them on to GryMod.API.ReportAttack. Part of the
-- compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses TFA's documented hooks and GryMod's public API, does nothing when TFA is not installed (the hooks
-- are never run) and never raises an error into TFA's attack code.
--
-- Which right clicks are attacks: TFA runs TFA_PostSecondaryAttack for a gun's right click even when it is only the iron sights, so the hook alone would end the
-- camouflage every time the player aims. The patch asks what TFA's own SecondaryAttack asks: a melee weapon (IsMelee) or a grenade (IsGrenade) attacks with it; a gun
-- attacks only when it has an AltAttack and its sights are not on the right click (Secondary.IronSightsEnabled is false).

local API = GryMod.API

if not API or not API.ReportAttack then
	return -- sv_api.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat tfa"

-- The player who holds the weapon, or nil.
local function holder(weapon)
	if not isentity(weapon) or not IsValid(weapon) then
		return nil
	end

	local owner = weapon:GetOwner()

	if IsValid(owner) and owner:IsPlayer() then
		return owner
	end

	return nil
end

-- Whether the right click of this TFA weapon really attacks (what its SecondaryAttack decides).
local function rightClickAttacks(weapon)
	if weapon.IsMelee == true or weapon.IsGrenade == true then
		return true
	end

	if not isfunction(weapon.AltAttack) then
		return false
	end

	local stat = weapon.GetStatL
	local sights = isfunction(stat) and stat(weapon, "Secondary.IronSightsEnabled", false)

	return not sights
end

-- TFA calls these from the weapon's own code: an error here would break the weapon, so everything runs under pcall.
hook.Add("TFA_PostSecondaryAttack", KEY, function(weapon)
	pcall(function()
		local owner = holder(weapon)

		if owner and rightClickAttacks(weapon) then
			API.ReportAttack(owner, true)
		end
	end)
end)

-- The quick melee of a gun (the bash key): not the right click.
hook.Add("TFA_PostBash", KEY, function(weapon)
	pcall(function()
		local owner = holder(weapon)

		if owner then
			API.ReportAttack(owner, false)
		end
	end)
end)
