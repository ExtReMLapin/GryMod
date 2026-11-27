-- Draconic Base (server). Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it only uses GryMod's public API and the hooks of the game, does nothing when the base is
-- not installed and never raises an error into Draconic's code.
--
-- (1) The attacks that are not bullets end the camouflage. A Draconic gun that fires bullets is seen by the server (weapon:FireBullets, which GryMod hears), but a PROJECTILE (a grenade, a
-- rocket, a plasma bolt: an entity of draconic_projectile_base made with the player as owner) and a MELEE blow are not. The projectiles are seen when they are made (the owner is set a frame later
-- than the creation: one frame is waited), the blows when they hurt (Draconic marks the damage of a melee weapon with the custom type 2221208). A dropped magazine is a projectile of the base
-- too (ProjectileType "magazine"): not an attack.
-- (2) The EMP of the base (DRC:EMP, the Draconic EMP gun, an EMP projectile) only sets a flag on its target; for a player it puts the suit down for the same time (GryMod.API.StartMalfunction).
-- (3) A Draconic weapon in hand puts the player's field of view back to his own every 0.4 s (ShouldFixFOV, weapons/draconic_base/shared.lua), which undoes the suit's own zoom and the
-- binoculars as soon as the engine's field of view is set to the zoom. Each Draconic weapon a player takes gets its ShouldFixFOV answered "no" while the suit's zoom is held (the hook
-- GryMod_Zoom tells when), and its own answer otherwise.

local API = GryMod.API

if not API or not API.ReportAttack then
	return -- sv_api.lua is included first (grymod_shared.lua)
end

local KEY = "GryMod compat draconic"
local MELEE_CUSTOM = 2221208 -- Draconic's custom damage type for a melee blow (draconic/sv/library.lua, IsMeleeDamage)

local S = GryMod.DraconicSV or {}
GryMod.DraconicSV = S

-- ---------------------------------------------------------------------------------------------------------
-- Projectiles
-- ---------------------------------------------------------------------------------------------------------

S.ClassCache = S.ClassCache or {}

-- Whether the class is built on the projectile base (kept by class: the lookup is made once for each class of the map).
function S.IsProjectileClass(class)
	if not isstring(class) then
		return false
	end

	local known = S.ClassCache[class]

	if known == nil then
		local ok, based = pcall(scripted_ents.IsBasedOn, class, "draconic_projectile_base")

		known = ok and based == true
		S.ClassCache[class] = known
	end

	return known
end

-- A projectile that exists, with its owner set: an attack of the player when he is its owner.
function S.ReportProjectile(projectile)
	if not IsValid(projectile) or projectile.ProjectileType == "magazine" then
		return
	end

	local owner = projectile:GetOwner()

	if isentity(owner) and IsValid(owner) and owner:IsPlayer() then
		API.ReportAttack(owner, false)
	end
end

hook.Add("OnEntityCreated", KEY, function(ent)
	if S.IsProjectileClass(ent:GetClass()) then
		-- (a frame later: the owner is set after the creation, before the spawn)
		timer.Simple(0, function()
			pcall(S.ReportProjectile, ent)
		end)
	end
end)

-- A melee blow of a Draconic weapon (the inflictor wears the marker of the base, the damage the custom type of the melee).
hook.Add("EntityTakeDamage", KEY, function(_, dmginfo)
	if dmginfo:GetDamageCustom() ~= MELEE_CUSTOM then
		return
	end

	local inflictor = dmginfo:GetInflictor()
	local attacker = dmginfo:GetAttacker()

	if IsValid(inflictor) and inflictor.Draconic == true and IsValid(attacker) and attacker:IsPlayer() then
		pcall(API.ReportAttack, attacker, false)
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The EMP
-- ---------------------------------------------------------------------------------------------------------

S.wrappers = S.wrappers or setmetatable({}, {__mode = "k"})

local function emp(self, src, tgt, thyme, ...)
	local result = S.original(self, src, tgt, thyme, ...)

	if IsValid(tgt) and tgt:IsPlayer() and tgt.ResistsEMP ~= true then
		pcall(API.StartMalfunction, tgt, tonumber(thyme) or 5, "emp")
	end

	return result
end

S.wrappers[emp] = true

-- Puts the wrapper on DRC.EMP. True when it is there (also when it already was), false when Draconic is not installed.
function S.InstallEMP()
	local drc = _G.DRC

	if not istable(drc) or not isfunction(drc.EMP) then
		return false
	end

	local current = drc.EMP

	if current == emp then
		return true
	end

	if not S.wrappers[current] then
		S.original = current
	end

	drc.EMP = emp

	return true
end

-- ---------------------------------------------------------------------------------------------------------
-- The field of view
-- ---------------------------------------------------------------------------------------------------------

local zooming = setmetatable({}, {__mode = "k"}) -- [player] = true while the suit's zoom is held

hook.Add("GryMod_Zoom", KEY, function(ply, fov)
	zooming[ply] = fov ~= 0 and true or nil
end)

-- Answers "no" to ShouldFixFOV while the suit's zoom is held. Once for a weapon (a field of the weapon marks it), a Draconic weapon only.
function S.PatchWeapon(weapon)
	if weapon == nil or not IsValid(weapon) or weapon.Draconic ~= true or weapon.GryFovPatched == true then
		return
	end

	local original = weapon.ShouldFixFOV

	if not isfunction(original) then
		return
	end

	weapon.GryFovPatched = true

	weapon.ShouldFixFOV = function(self, ...)
		local owner = self:GetOwner()

		if owner ~= nil and zooming[owner] then
			return false
		end

		return original(self, ...)
	end
end

hook.Add("WeaponEquip", KEY, function(weapon)
	pcall(S.PatchWeapon, weapon)
end)

hook.Add("PlayerSwitchWeapon", KEY, function(_, _, weapon)
	pcall(S.PatchWeapon, weapon)
end)

-- Installed when the file loads (a reload in a running game: the weapons already in hands are patched too) and when the game is up (Draconic loads its library after this file).
local function install()
	S.InstallEMP()

	for _, ply in ipairs(player.GetAll()) do
		for _, weapon in ipairs(ply:GetWeapons()) do
			pcall(S.PatchWeapon, weapon)
		end
	end
end

install()
hook.Add("InitPostEntity", KEY, install)
