-- JMod (server): what the suit's camouflage means for JMod's devices, and the attacks of JMod that are not bullets. Part of the compatibility patches (lua/grymod/compat/,
-- docs/compat.md): it uses JMod's own hook and GryMod's public API (GryMod.API.CloakLevel, ReportAttack, GetDanger), does nothing when JMod is not installed (its hook is never run,
-- the key hook finds no JMod) and never raises an error into JMod's code or the game's. Read in the public code of JMod (github.com/Jackarunda/gmod), not tried in a game.
--
-- 1. A sentry, a turret... of JMod chooses its target with JMod.ShouldAttack (sv_util.lua:195), which first asks the hook JMod_ShouldAttack(self, ent, vehiclesOnly, peace): the first
--    answer that is not nil is the verdict. A camouflaged player is not a target of a SENTRY or a turret while the setting that makes the enemies forget him is on (`gry_cloak_ai`, the
--    administrators' switch of the camouflage's rule for the AI): they recognise by sight and do not see him. The half of the fade is the limit: during the first part he is still half
--    visible (GryMod.API.CloakLevel). A MINE (or a bomb) is not asked about: the camouflage hides from the visible light only, and a mine goes off under the feet.
-- 2. JMod throws what the player holds (JMod.ThrowablePickup, sv_util.lua:294: Player:PickupObject, then a KeyPress of the attack key applies a force). That is neither a bullet nor
--    a weapon: nothing ended the camouflage. A press of an attack key while the player holds an entity that has a danger entry (a grenade, a bomb) is an attack: the right
--    click is the soft throw. KeyPress runs only when a key is pressed: nothing runs between two presses.

local API = GryMod.API

if not API or not API.CloakLevel or not API.ReportAttack or not API.GetDanger then
	return -- sv_api.lua and the registries are included first (grymod_shared.lua)
end

local KEY = "GryMod compat jmod"
local HALF = 0.5

local function cloakRuleOn()
	local var = GetConVar("gry_cloak_ai")

	return var == nil or var:GetBool()
end

-- Only a device that recognises its target by sight is fooled: a sentry or a turret. A mine goes off under the feet, a bomb on contact: the camouflage hides the player from the visible
-- light and from nothing else, so it has no say in them.
local function seesByEye(device)
	if not istable(device) and not isentity(device) then
		return false
	end

	if not isfunction(device.GetClass) then
		return false
	end

	local ok, class = pcall(device.GetClass, device)

	if not ok or not isstring(class) then
		return false
	end

	class = string.lower(class)

	return string.find(class, "sentry", 1, true) ~= nil or string.find(class, "turret", 1, true) ~= nil
end

hook.Add("JMod_ShouldAttack", KEY, function(device, target)
	local ok, verdict = pcall(function()
		if not seesByEye(device) then
			return nil
		end

		if not istable(target) and not isentity(target) then
			return nil
		end

		if not isfunction(target.IsPlayer) or not target:IsPlayer() or not IsValid(target) then
			return nil
		end

		if API.CloakLevel(target) >= HALF and cloakRuleOn() then
			return false
		end

		return nil
	end)

	if ok then
		return verdict
	end

	return nil
end)

hook.Add("KeyPress", KEY, function(ply, key)
	if key ~= IN_ATTACK and key ~= IN_ATTACK2 then
		return
	end

	pcall(function()
		if not istable(JMod) or not isfunction(JMod.GetPlayerHeldEntity) then
			return
		end

		local held = JMod.GetPlayerHeldEntity(ply)

		if held ~= nil and IsValid(held) and API.GetDanger(held) then
			API.ReportAttack(ply, key == IN_ATTACK2)
		end
	end)
end)
