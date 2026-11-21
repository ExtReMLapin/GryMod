-- The dangerous projectiles of the grenade warning (client: cl_hud_grenade_flash.lua). The client cannot read the
-- engine's internal variables, so the server marks each projectile with the networked bool "GryArmed": true while
-- it is ACTIVE, that is really a danger coming (a grenade whose fuse runs, a mine in the air, a rocket in flight...),
-- false for an inert one lying around (the spawn menu makes them inert, a Half-Life 2 grenade is only armed when
-- thrown or picked up). Which classes are dangerous and what "active" means for each one is the registry's (the `danger`
-- field of an entry of GryMod.API.RegisterTracked, sh_api_tracked.lua): the Half-Life 2 ones are registered as data in
-- sh_api_tracked_hl2.lua (what "active" means for each class was measured on live entities, see
-- docs/superpowers/plans/2026-11-21-grenade-entities.md), an addon's mine or missile is registered the same way and goes
-- through the same code here. An entry without an `armed` reader is dangerous as soon as it exists.
--
-- The entities are followed from their creation (OnEntityCreated), so nothing is searched in the world: with no
-- projectile around, the five-times-a-second tick finds an empty list and returns.

GryMod = GryMod or {}

local Grenade = {}
GryMod.Grenade = Grenade

local armedOnly = CreateConVar("gry_grenade_armed_only", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The grenade warning is only for a projectile that is active: a grenade whose fuse runs, a mine in the air... (0: any grenade lying around too, to debug)")

Grenade.ConVar = armedOnly

-- The registry entry with a danger for an entity (or a class name), or nil: none, or no registry (a hot reload of this file).
local function dangerOf(ent)
	local API = GryMod.API

	return API and API.GetDanger and API.GetDanger(ent) or nil
end

-- Whether the projectile is a danger coming now: its class has a danger entry, no player holds it (a grenade held in the hands has
-- its fuse running, picked up with the use key it is armed with 1.5 s: no warning; the gravity gun too), and the entry's `armed`
-- reader says so (a reader that raises an error is no danger: it runs under SafeCall).
function Grenade.IsActive(ent)
	local entry = dangerOf(ent)

	if not entry then
		return false
	end

	if ent:IsPlayerHolding() then
		return false
	end

	local armed = entry.danger.armed

	if armed == nil then
		return true
	end

	local ok, answer = GryMod.API.SafeCall(entry.armedId, armed, ent)

	return ok and answer == true
end

-- The first player among the values given (an owner, a thrower, an owner entity: any of them may be missing, not be a
-- player, or be NULL). Measured on live entities: a missile fired by weapon_rpg has the player as its owner and as its
-- owner entity, a rifle grenade or a thrown frag also as its thrower, an energy ball of the AR2 as its owner.
function Grenade.PlayerOf(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)

		if isentity(value) and IsValid(value) and value:IsPlayer() then
			return value
		end
	end

	return nil
end

-- Who threw or fired the projectile: a player, or nil. The entry's `ownerOf` (an addon's projectile that keeps its owner in
-- its own field) comes first, then what the engine knows.
function Grenade.ThrowerOf(ent)
	local entry = dangerOf(ent)
	local owner

	if entry and entry.danger.ownerOf then
		local ok, answer = GryMod.API.SafeCall(entry.ownerId, entry.danger.ownerOf, ent)

		if ok then
			owner = answer
		end
	end

	return Grenade.PlayerOf(owner, ent:GetOwner(), (ent:GetInternalVariable("m_hThrower")), (ent:GetInternalVariable("m_hOwnerEntity")))
end

-- Marks one projectile (the values are only sent when they change). The thrower is written first, so a client that sees
-- the projectile active already knows whose it is (a player's own missile must not warn that player).
function Grenade.Update(ent)
	if not IsValid(ent) then
		return
	end

	local thrower = Grenade.ThrowerOf(ent) or NULL

	if ent:GetNWEntity("GryThrower") ~= thrower then
		ent:SetNWEntity("GryThrower", thrower)
	end

	local armed = Grenade.IsActive(ent)

	if ent:GetNWBool("GryArmed") ~= armed then
		ent:SetNWBool("GryArmed", armed)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The projectiles followed
-- ---------------------------------------------------------------------------------------------------------

local tracked = {}
local count = 0

function Grenade.Track(ent)
	if IsValid(ent) and dangerOf(ent) and not tracked[ent] then
		tracked[ent] = true
		count = count + 1
	end
end

function Grenade.TrackedCount()
	return count
end

function Grenade.Clear()
	tracked = {}
	count = 0
end

-- Every 0.2 s: the entities that are gone are forgotten, the others marked.
function Grenade.Tick()
	if count == 0 then
		return
	end

	for ent in pairs(tracked) do
		if IsValid(ent) then
			Grenade.Update(ent)
		else
			tracked[ent] = nil
			count = count - 1
		end
	end
end

-- The player picks one up or throws it: marked at once (the state of the hands changes after the hook, so one frame on)
local function markSoon(_, ent)
	if IsValid(ent) and dangerOf(ent) then
		Grenade.Track(ent)

		timer.Simple(0, function()
			Grenade.Update(ent)
		end)
	end
end

hook.Add("OnPlayerPhysicsPickup", "GRYGRENADEHELD", markSoon)
hook.Add("OnPlayerPhysicsDrop", "GRYGRENADEHELD", markSoon)

hook.Add("OnEntityCreated", "GRYGRENADETRACK", function(ent)
	-- the class is known when the entity is made
	if IsValid(ent) and dangerOf(ent) then
		Grenade.Track(ent)
	end
end)

timer.Create("GRYGRENADEMARK", 0.2, 0, Grenade.Tick)

-- The ones that exist when this file is loaded (a reload, or the module started late). An entry registered later follows the
-- entities made after it: the ones that already stand are not looked for again.
local API = GryMod.API

if API and API.DangerClasses then
	for _, class in ipairs(API.DangerClasses()) do
		for _, ent in ipairs(ents.FindByClass(class)) do
			Grenade.Track(ent)
		end
	end
end
