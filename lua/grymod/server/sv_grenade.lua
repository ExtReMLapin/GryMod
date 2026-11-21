-- The dangerous projectiles of the grenade warning (client: cl_hud_grenade_flash.lua). The client cannot read the
-- engine's internal variables, so the server marks each projectile with the networked bool "GryArmed": true while
-- it is ACTIVE, that is really a danger coming (a grenade whose fuse runs, a mine in the air, a rocket in flight...),
-- false for an inert one lying around (the spawn menu makes them inert, a Half-Life 2 grenade is only armed when
-- thrown or picked up). What "active" means for each class was measured on live entities, see
-- docs/superpowers/plans/2026-11-21-grenade-entities.md.
--
-- The entities are followed from their creation (OnEntityCreated), so nothing is searched in the world: with no
-- projectile around, the five-times-a-second tick finds an empty list and returns.

GryMod = GryMod or {}

local Grenade = {}
GryMod.Grenade = Grenade

local armedOnly = CreateConVar("gry_grenade_armed_only", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
	"The grenade warning is only for a projectile that is active: a grenade whose fuse runs, a mine in the air... (0: any grenade lying around too, to debug)")

Grenade.ConVar = armedOnly

-- Units a second under which a projectile counts as at rest.
local MOVING = 50
local FALLING = 300 -- a bomb that is not ticking yet but falls this fast is coming at someone
local HOPPING = 100 -- a mine in the air (its hop is 300 and more, the clicking before it under 40)

-- The class -> the rule that says whether it is active, given the state read from the entity: detonate (seconds left
-- before the explosion: the engine tells minus the game time of an unarmed grenade), speed (units a second),
-- activated (the bomb), mineState (1 on the ground, 3 armed, 4 triggered: clicking, then jumping), launched, held.
local RULES = {
	-- npc_grenade_frag: the fuse runs. Measured: a grenade made at rest has -CurTime(), SetTimer 3 gives 3 counting down,
	-- a pick-up by the player arms it with 1.5.
	npc_grenade_frag = function(s)
		return (s.detonate or 0) > 0
	end,
	-- grenade_ar2 and rpg_missile are fired live (m_bIsLive is true from their creation) and have no other state: in flight
	grenade_ar2 = function(s)
		return (s.speed or 0) > MOVING
	end,
	rpg_missile = function(s)
		return (s.speed or 0) > MOVING
	end,
	-- grenade_helicopter: m_bActivated turns on at the first impact and the 5 seconds count down; before it, a bomb that
	-- falls fast is coming
	grenade_helicopter = function(s)
		return s.activated == true or (s.speed or 0) > FALLING
	end,
	-- combine_mine: m_iMineState 1 on the ground, 3 armed (a foe is near), 4 triggered (it clicks, then jumps)
	combine_mine = function(s)
		return s.mineState == 4 and (s.speed or 0) > HOPPING
	end,
	-- prop_combine_ball: m_bLaunched from the weapon's fire or a launcher, m_bHeld by a gravity gun
	prop_combine_ball = function(s)
		return s.launched == true and s.held ~= true
	end
}

-- The classes the warning knows (the client has their names).
Grenade.Classes = {}

for class in pairs(RULES) do
	Grenade.Classes[class] = true
end

function Grenade.IsActive(class, state)
	local rule = class and RULES[class]

	return rule ~= nil and rule(state or {}) == true
end

-- The values the rules read, from the entity itself.
function Grenade.ReadState(ent)
	local s = {speed = ent:GetVelocity():Length()}
	local class = ent:GetClass()

	if class == "npc_grenade_frag" then
		s.detonate = ent:GetInternalVariable("m_flDetonateTime")
	elseif class == "grenade_helicopter" then
		s.activated = ent:GetInternalVariable("m_bActivated") == true
	elseif class == "combine_mine" then
		s.mineState = ent:GetInternalVariable("m_iMineState")
	elseif class == "prop_combine_ball" then
		s.launched = ent:GetInternalVariable("m_bLaunched") == true
		s.held = ent:GetInternalVariable("m_bHeld") == true
	end

	return s
end

-- Marks one projectile (the bool is only sent when it changes).
function Grenade.Update(ent)
	if not IsValid(ent) then
		return
	end

	local armed = Grenade.IsActive(ent:GetClass(), Grenade.ReadState(ent))

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
	if IsValid(ent) and Grenade.Classes[ent:GetClass()] and not tracked[ent] then
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

hook.Add("OnEntityCreated", "GRYGRENADETRACK", function(ent)
	-- the class is known when the entity is made
	if IsValid(ent) and Grenade.Classes[ent:GetClass()] then
		Grenade.Track(ent)
	end
end)

timer.Create("GRYGRENADEMARK", 0.2, 0, Grenade.Tick)

-- The ones that exist when this file is loaded (a reload, or the module started late).
for class in pairs(Grenade.Classes) do
	for _, ent in ipairs(ents.FindByClass(class)) do
		Grenade.Track(ent)
	end
end
