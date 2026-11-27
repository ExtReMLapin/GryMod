-- JMod (the Garry's Mod Additions Pack): the grenade warning for its grenades, bombs, rockets and mines, the radar contact of its mines, and the use prompts of what the +use key
-- does on its entities. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): data and small readers through the public API (RegisterTracked, RegisterUsable),
-- nothing when JMod is not there (an entry for a base or a class that does not exist matches nothing). The server part is sv_jmod.lua, the armor is cl_jmod.lua.
--
-- Read in the public code of JMod (github.com/Jackarunda/gmod, lua/entities/ and autorun/jmod_init.lua), NOT tried in a game (JMod was not installed when this was written).
-- What matters, and why it is written here:
--   * the state is the networked integer `State` (NetworkVar), but the NUMBERS are not the same for every entity. The grenades use the global constants JMod.EZ_STATE_* (OFF 0, ON 1,
--     PRIMED 2, ARMING 3, ARMED 4: the fuse is running at ARMED); the bombs (ezbomb) have their own local ones (OFF 0, ARMED 1), the rockets (ezherocket) too (ARMED 1, LAUNCHED 2),
--     the mines (ezlandmine, ezatmine, ezwarmine) too (OFF 0, ARMING 1, ARMED 2, WARNING 3). Each reader below says which table it reads.
--   * the owner is `ent.EZowner` through JMod.GetEZowner (sv_util.lua), never the engine's owner;
--   * a grenade in the hand (JMod picks it up with Player:PickupObject) is never a danger: GryMod's own rule for a held projectile.
-- Entries are by BASE (JMod has 208 entities, and other addons add more on the same bases): ent_jack_gmod_ezgrenade, ent_jack_gmod_ezbomb, ent_jack_gmod_ezherocket,
-- ent_jack_gmod_ezmachine_base and ent_jack_gmod_ezresource. No match function. The priority is above the stock entries (-100) and below the default (0).

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterUsable or not API.RegisterTracked then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local PRIORITY = -50

local function usable(key, def)
	def.priority = PRIORITY

	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the JMod entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

local function tracked(key, def)
	def.priority = PRIORITY

	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the JMod entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- The networked State of the entity, or nil when it has none (a stand-in, another version).
local function stateOf(ent)
	local fn = ent.GetState

	if isfunction(fn) then
		local state = fn(ent)

		if isnumber(state) then
			return state
		end
	end

	return nil
end

-- JMod.EZ_STATE_ARMED, 4 in the version read.
local function grenadeArmed()
	return istable(JMod) and isnumber(JMod.EZ_STATE_ARMED) and JMod.EZ_STATE_ARMED or 4
end

local BOMB_ARMED = 1 -- ezbomb.lua: local STATE_BROKEN, STATE_OFF, STATE_ARMED = -1, 0, 1
local ROCKET_LAUNCHED = 2 -- ezherocket.lua: local STATE_BROKEN, STATE_OFF, STATE_ARMED, STATE_LAUNCHED = -1, 0, 1, 2
local MINE_WARNING = 3 -- ezlandmine.lua: local STATE_BROKEN, STATE_OFF, STATE_ARMING, STATE_ARMED, STATE_WARNING = -1, 0, 1, 2, 3
local FALLING = 100 -- units a second: a bomb that moves faster than this is coming down

local function broken(ent)
	local state = stateOf(ent)

	return state ~= nil and state < 0
end

-- The player who owns the explosive for JMod (JMod.GetEZowner, which falls back on the world: not a player), or nil.
local function ownerOf(ent)
	local owner

	if istable(JMod) and isfunction(JMod.GetEZowner) then
		owner = JMod.GetEZowner(ent)
	else
		owner = ent.EZowner
	end

	if owner ~= nil and IsValid(owner) and isfunction(owner.IsPlayer) and owner:IsPlayer() then
		return owner
	end

	return nil
end

local function speedOf(ent)
	local fn = ent.GetVelocity

	if isfunction(fn) then
		local velocity = fn(ent)

		return velocity ~= nil and velocity:Length() or 0
	end

	return 0
end

-- ---------------------------------------------------------------------------------------------------------
-- The grenade warning
-- ---------------------------------------------------------------------------------------------------------

-- The grenades (ent_jack_gmod_ezgrenade and the thirteen built on it: the frag, the stick grenade, the impact, the sticky, the satchel charge...): the fuse runs from ARMED on.
-- Primed (the pin is out, the grenade is still in the hand or on the floor) is not coming at anybody.
tracked("jmod_grenades", {
	base = "ent_jack_gmod_ezgrenade",
	danger = {
		label = "GRENADE", type = "grenade",
		armed = function(ent)
			return stateOf(ent) == grenadeArmed()
		end,
		ownerOf = ownerOf
	}
})

-- The bombs (ent_jack_gmod_ezbomb and the heavy, the small, the cluster bomb...): armed on the way down.
tracked("jmod_bombs", {
	base = "ent_jack_gmod_ezbomb",
	danger = {
		label = "BOMB", type = "bomb",
		armed = function(ent)
			return stateOf(ent) == BOMB_ARMED and speedOf(ent) > FALLING
		end,
		ownerOf = ownerOf
	}
})

-- The rockets and missiles (ent_jack_gmod_ezherocket, the heat, heavy and fire works rockets, the missile): in flight once LAUNCHED. The player who fires one is never warned of it.
tracked("jmod_rockets", {
	base = "ent_jack_gmod_ezherocket",
	danger = {
		label = "MISSILE", type = "missile", ownMissile = true,
		armed = function(ent)
			return stateOf(ent) == ROCKET_LAUNCHED
		end,
		ownerOf = ownerOf
	}
})

-- The mines that lie in wait (the land mine, the anti tank mine, the war mine). A mine that waits armed is not "coming": it warns when it has been triggered (WARNING: the click
-- before it blows, as the Combine mine does at its hop). It is also a radar contact once the binoculars scanned it, like the Combine mine: an ally when the player laid it (JMod's
-- owner), hostile otherwise.
tracked("jmod_mines", {
	class = {"ent_jack_gmod_ezlandmine", "ent_jack_gmod_ezatmine", "ent_jack_gmod_ezwarmine"},
	type = "device", radar = "scan",
	relation = function(ply, ent)
		return ownerOf(ent) == ply and "ally" or "hostile"
	end,
	danger = {
		label = "MINE", type = "mine",
		armed = function(ent)
			return stateOf(ent) == MINE_WARNING
		end,
		ownerOf = ownerOf
	}
})

-- ---------------------------------------------------------------------------------------------------------
-- The use prompts
-- ---------------------------------------------------------------------------------------------------------

-- The grenades: +use takes the grenade in the hand (JMod.ThrowablePickup, sv_util.lua:294: Player:PickupObject, then the attack keys throw it); with the alternate key (JMod's
-- own, Alt by default) it is primed. It changes the state: one shot. No size or mass limit: JMod does the pick up itself. A broken one (State -1) is not taken.
usable("jmod_grenades", {
	base = "ent_jack_gmod_ezgrenade", icon = "grab", text = "PICK UP", use = "once", nolimits = true,
	busy = broken
})

-- The bombs (ezbomb.lua:268): a double tap of +use arms an off bomb, another disarms it. The text follows the networked state.
usable("jmod_bombs", {
	base = "ent_jack_gmod_ezbomb", icon = "use", use = "repeat", cooldown = 0.5,
	text = function(ent)
		return stateOf(ent) == BOMB_ARMED and "DISARM" or "ARM"
	end,
	busy = broken
})

-- The mines (ezlandmine.lua:167): +use picks an off mine up (or arms it with the alternate key), and disarms an armed one.
usable("jmod_mines", {
	class = {"ent_jack_gmod_ezlandmine", "ent_jack_gmod_ezatmine", "ent_jack_gmod_ezwarmine", "ent_jack_gmod_ezboundingmine", "ent_jack_gmod_eznavalmine"},
	icon = "use", text = "USE", use = "repeat", cooldown = 1, busy = broken
})

-- The machines (ent_jack_gmod_ezmachine_base, SIMPLE_USE: the fabricator, the generators, the sentry...): +use opens or switches the machine.
usable("jmod_machines", {base = "ent_jack_gmod_ezmachine_base", icon = "use", text = "USE", use = "repeat", cooldown = 0.5, busy = broken})

-- The resource boxes (ent_jack_gmod_ezresource, ezresource.lua:243, SIMPLE_USE): +use takes the box. The usual size and mass limit of a "grab" applies.
usable("jmod_resources", {base = "ent_jack_gmod_ezresource", icon = "grab", text = "PICK UP", use = "once"})
