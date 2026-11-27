-- Gbombs 5 (GB5): the grenade warning for its bombs and rockets, and the ARM prompt of its bombs. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): data and
-- small readers through the public API (RegisterTracked, RegisterUsable), nothing when GB5 is not there (nothing matches). Read in the public code of GB5
-- (github.com/SCI-Revived/gbombs-5, a copy of the Workshop code: the original has no public repository), NOT tried in a game (not installed when this was written).
--
-- GB5 has 163 entities. Its bombs, rockets and missiles share three bases (gb5_base_advanced, gb5_base_dumb, gb5_base_rocket_), but the entity files set no ENT.Base (they
-- say DEFINE_BASECLASS only), so no entry can name a base. What they do share are the methods ENT:Arm and ENT:Explode, which the shockwaves, the gases and the radiation entities
-- (also named gb5_...) do not have. The entries use a `match` with that test: a danger's match is judged once per entity, at its creation, and kept; the prompt's match is asked
-- only about the entity the player aims at, and checks the class name first.
--
-- The state is in server fields: `Armed` (the arming delay is over), `Exploded`, `Fired` (a rocket whose motor runs) and the class field `Timed` (a fuse that ends in a blast);
-- the owner is `GBOWNER` (set by the spawn function, not the engine's owner). The blasts ring the radar through GryMod's wrap of util.BlastDamage where GB5 uses it, and GB5 has its
-- own shockwave system elsewhere: nothing to do here for them.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterUsable or not API.RegisterTracked then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local PRIORITY = -50
local FALLING = 100 -- units a second: an armed bomb that moves faster than this is coming down

-- A bomb of GB5: a gb5_ class that has the arming and the explosion of the bases.
local function isBomb(ent)
	return string.StartWith(ent:GetClass(), "gb5_") and isfunction(ent.Arm) and isfunction(ent.Explode)
end

local function speedOf(ent)
	local fn = ent.GetVelocity

	if isfunction(fn) then
		local velocity = fn(ent)

		return velocity ~= nil and velocity:Length() or 0
	end

	return 0
end

-- Dangerous now: a rocket whose motor runs; an armed bomb whose fuse runs (Timed) or that falls. A bomb that lies armed and waits for an impact is not coming at anybody.
local function coming(ent)
	if ent.Exploded == true then
		return false
	end

	if ent.Fired == true then
		return true
	end

	if ent.Armed ~= true then
		return false
	end

	return ent.Timed == true or speedOf(ent) > FALLING
end

-- The player who owns it (GBOWNER), or nil.
local function ownerOf(ent)
	local owner = ent.GBOWNER

	if owner ~= nil and IsValid(owner) and isfunction(owner.IsPlayer) and owner:IsPlayer() then
		return owner
	end

	return nil
end

local ok, reason = API.RegisterTracked("gb5_bombs", {
	match = isBomb, priority = PRIORITY,
	danger = {label = "BOMB", type = "bomb", armed = coming, ownerOf = ownerOf}
})

if not ok then
	MsgN("GryMod: the GB5 entry 'gb5_bombs' of the tracked registry was refused: " .. tostring(reason))
end

-- ENT:Use of gb5_base_advanced.lua arms the bomb, and only when the replicated setting gb5_easyuse is 1 ("Should bombs be easily armed?"); it does nothing once the bomb is armed or
-- used. The prompt is taken away when GryMod has marked the bomb armed (GryArmed, which it networks for the danger entries). It changes the state: one shot.
ok, reason = API.RegisterUsable("gb5_bombs", {
	match = isBomb, priority = PRIORITY, icon = "use", text = "ARM", use = "once",
	active = function()
		local var = GetConVar("gb5_easyuse")

		return var == nil or var:GetBool()
	end,
	busy = function(ent)
		return ent:GetNW2Bool("GryArmed") == true
	end
})

if not ok then
	MsgN("GryMod: the GB5 entry 'gb5_bombs' of the usable registry was refused: " .. tostring(reason))
end
