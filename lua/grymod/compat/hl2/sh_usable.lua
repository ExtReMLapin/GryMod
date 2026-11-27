-- The stock Half-Life 2 and Garry's Mod entries of the registry of usable entities (the use prompt, see sh_api_usable.lua), registered as DATA through the
-- public API (GryMod.API.RegisterUsable), exactly as an addon would register its own: no private table, no special path. They live here, apart from the
-- registry, so that what GryMod knows about the stock game is in one place (lua/grymod/compat/) and the registry file is only the rules.
-- Loaded after sh_api_usable.lua, in both realms.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterUsable then
	return -- sh_api.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local band = bit.band

-- ---------------------------------------------------------------------------------------------------------
-- The stock Half-Life 2 and Garry's Mod entries, registered as data, with the original game's texts (game_text_messages.xml: pick_weapon,
-- pick_item, use_vehicle, use_ladder, grab_object, use_door) and its icons. Low priority: an entry of an addon for the same entity wins.
--
-- Every class here was checked in the public Source SDK 2013 code (the ObjectCaps of its class: FCAP_IMPULSE_USE or FCAP_CONTINUOUS_USE, which
-- is what makes the +use key act on it) or in the Lua of Garry's Mod (ENT:Use); the file and the maps where it can be seen are in each comment.
-- Maps: the stock Half-Life 2 ones, read from their entity lists (hl2/maps), and gm_construct. A class that is NOT here has no +use action:
-- combine_mine (only the gravity gun pulls it out), npc_kleiner / npc_eli / npc_breen / npc_dog (CAI_BaseActor: no use caps), item_item_crate
-- (a breakable crate), item_dynamic_resupply (it only spawns an item), func_physbox_multiplayer.
-- ---------------------------------------------------------------------------------------------------------

local STOCK = -100

-- A method of the entity, or false when it has none (a stand-in in a test, a reload): the stock matchers never raise an error, since five
-- errors in a row switch a matcher off.
local function ask(ent, method)
	local fn = ent[method]

	return isfunction(fn) and fn(ent) or false
end

local function register(key, def)
	def.priority = STOCK

	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the stock entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

-- (a hot reload of this file: the entries of the earlier versions are taken away)
for _, old in ipairs({"hl2_weapons", "hl2_items", "hl2_turrets", "hl2_doors", "hl2_floor_turret", "hl2_metropolice"}) do
	API.UnregisterUsable(old)
end

-- NOT HERE: what is taken by WALKING OVER it. A weapon on the floor and every item_* that is a plain pickup (health kit and vial, battery, HEV suit, the
-- ammo boxes and rounds) are picked up by touch (checked in game on gm_construct: a health kit, a battery and a pistol put at the player's feet were
-- taken without a key; the base gamemode's GM:PlayerCanPickupWeapon / PlayerCanPickupItem answer true). They have a +use action in the SDK too, but nobody
-- needs it, so they get no prompt. An addon whose weapon or item really needs the key registers it.

-- The ammo crate: CItem_AmmoCrate::ObjectCaps (item_ammo.cpp: FCAP_IMPULSE_USE, USE_IN_RADIUS), +use gives ammo, and again. d1_canals_05, d1_canals_07,
-- d2_coast_03, d2_coast_07.
register("hl2_ammo_crate", {class = "item_ammo_crate", icon = "pickup", text = "TAKE AMMO", use = "repeat", cooldown = 1})

-- The wall chargers: FCAP_CONTINUOUS_USE (func_recharge.cpp), held +use. item_healthcharger: d1_canals_01 (three), d1_canals_07, d2_coast_08;
-- item_suitcharger: d1_trainstation_01, d1_trainstation_05, d1_canals_08. (func_healthcharger and func_recharge are the old brush versions.)
-- The key is kept down while they work, so the text says it and the feedback comes once (hold).
register("hl2_chargers", {
	class = {"item_healthcharger", "item_suitcharger", "func_healthcharger", "func_recharge"}, icon = "use", text = "USE (HOLD)", use = "repeat", cooldown = 0.5, hold = true
})

-- The vehicles: CPropVehicleDriveable::ObjectCaps (vehicle_base.h), the airboat (USE_IN_RADIUS), the crane, the prisoner pod and the
-- choreographed seats all have FCAP_IMPULSE_USE. d2_coast_01 (prop_vehicle_jeep: the buggy, and the crane), d1_canals_05 and the other canal maps
-- (prop_vehicle_airboat), d1_canals_01a (prop_vehicle_apc), d3_breen_01 (prop_vehicle_prisoner_pod). The "jeep" class is also the scripted APC of
-- d1_trainstation_03 and 04: a driveable one only when its model is. Getting in changes the state: one-shot (the crosshair also drops it while the
-- player sits in a vehicle).
register("hl2_vehicles", {match = function(ent) return ask(ent, "IsVehicle") == true end, icon = "enter", text = "ENTER VEHICLE", use = "once"})

-- The ladder: func_useableladder. The player gets on it by WALKING INTO IT (the game's movement code, sv_ladder_useonly 0, the default): the use key is
-- optional, so there is no prompt, unless the server set sv_ladder_useonly 1 ("ladders can only be mounted by pressing +USE"). That variable is
-- replicated to the client. The class has no use cap of its own (ObjectCaps read in game: 2), the key is handled by the movement; its reach is 64 units.
-- d1_canals_01 (once), d1_canals_03 (five), gm_construct (once). A ladder is not solid: the eye trace never hits it, so the crosshair looks for it along
-- the aim ray (nonsolid). While the player climbs it there is no prompt.
local function ladderUseOnly()
	local var = GetConVar("sv_ladder_useonly")

	return var ~= nil and var:GetBool()
end

register("hl2_ladders", {
	class = "func_useableladder", icon = "ladder", text = "CLIMB", nonsolid = true, use = "once", active = ladderUseOnly, range = 64,
	busy = function(_, ply) return ply ~= nil and isfunction(ply.GetMoveType) and ply:GetMoveType() == MOVETYPE_LADDER end
})

-- What the player lifts: CPhysicsProp::ObjectCaps (props.cpp) and CPhysBox::ObjectCaps (physobj.cpp) give FCAP_IMPULSE_USE when
-- CBasePlayer::CanPickupObject(this, 35, 128) is true: at most 35 kg and 128 units on every side (the crosshair applies those limits to a
-- "grab" icon, see UsableFor, and asks the server for the mass), or whatever the spawnflags say. prop_physics in every stock map (d1_trainstation_01:
-- 178), func_physbox in d1_canals_02 (25). prop_ragdoll is NOT here: its ObjectCaps has no use bit (read in game, 0x40000002), the game does not lift it with
-- the key. "You can pick up almost anything": the owner is not sure the prompt is wanted on all of them, so they are the group "props", which the player
-- switches with gry_usehint_props (off by default).
--
-- The flags: prop_physics 512 "Prevent pickup" is never liftable, and a prop that starts frozen (8 "motion disabled") only with 64 "enable motion on
-- gravity gun grab". func_physbox 8192 "Ignore +USE for Pickup" is never, 32768 "motion disabled" only with 131072. (props_shared.h, physobj.h.)
register("hl2_props", {
	class = {"prop_physics", "prop_physics_multiplayer"}, icon = "grab", text = "PICK UP", group = "props", use = "once",
	spawnflags = function(flags) return band(flags, 512) == 0 and (band(flags, 8) == 0 or band(flags, 64) ~= 0) end
})

register("hl2_physbox", {
	class = "func_physbox", icon = "grab", text = "PICK UP", group = "props", use = "once",
	spawnflags = function(flags) return band(flags, 8192) == 0 and (band(flags, 32768) == 0 or band(flags, 131072) ~= 0) end
})

-- The floor turret: its Use is PickupObject with no limit (npc_turret_floor.h; read in game: after Use the player holds it, IsPlayerHolding). Not a toggle,
-- as the first list said. A carry like the props, so the same group; the limits of a prop do not apply to it. d2_prison_02 and d2_prison_03.
register("hl2_floor_turret", {class = "npc_turret_floor", icon = "grab", text = "PICK UP", group = "props", use = "once", nolimits = true})

-- The thrown frag grenade (npc_grenade_frag) has "Allow +USE pickup" (basegrenade_shared.h): it exists only at run time. Taking it changes the state
-- (it is in the hand, or it goes off), so one-shot; it is not a prop of the group (a grenade that is about to explode is worth a prompt).
register("hl2_grenade", {class = "npc_grenade_frag", icon = "grab", text = "PICK UP", use = "once"})

-- The doors: CBasePropDoor::ObjectCaps (props.cpp) answers the key unless 32768 "Ignore player +USE" is set (36 stock doors have it: barney_door_1 and _2 of
-- d1_trainstation_01 are the examples). CBaseDoor (func_door, func_door_rotating, doors.h) answers it ONLY with 256 "Use opens": 367 of the 492 stock
-- func_door have neither that nor 1024 "Touch opens" (a button or a trigger opens them), so they get no prompt. A door that "starts locked" (2048) still
-- takes the key (it plays the locked sound); whether it is locked NOW cannot be read on the client (checked: GetInternalVariable gives nothing), so the
-- prompt stays. A door can be used again once it has moved: a cooldown of a second. prop_door_rotating in d1_trainstation_01 (9) and d1_town_01 (4),
-- func_door in d1_canals_01 (-766 -7378 56), func_door_rotating in d1_trainstation_01.
register("hl2_prop_doors", {class = "prop_door_rotating", icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {forbid = 32768}})
register("hl2_func_doors", {class = {"func_door", "func_door_rotating"}, icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {need = 256}})

-- The buttons: CBaseButton (func_button, func_rot_button) answers the key only with 1024 "Use activates" (buttons.cpp); 10 stock buttons are touch or
-- damage only. A button waits before it works again (its `wait`, not readable on the client): a cooldown of a second. func_button in
-- d1_trainstation_01 (soda_machine_1) and d1_eli_01 (20), func_rot_button in d1_town_01 (5). The wheels (momentary_rot_button, d1_canals_05: four) turn
-- while the key is held (FCAP_CONTINUOUS_USE), with the same flag 1024.
register("hl2_buttons", {class = {"func_button", "func_rot_button"}, icon = "use", text = "USE", use = "repeat", cooldown = 1, spawnflags = {need = 1024}})
-- Most wheels are "not solid" (flag 1): the eye trace goes through them and the key finds them by the radius search (USE_IN_RADIUS), so they are looked for
-- along the aim ray like the ladder (nonsolid), under the name the client gives them.
register("hl2_wheels", {
	class = "momentary_rot_button", netclass = "class C_BaseToggle", nonsolid = true, icon = "use", text = "USE (HOLD)", use = "repeat", cooldown = 1, hold = true,
	spawnflags = {need = 1024}
})

-- The mounted guns: CFuncTank::ObjectCaps (func_tank.h: FCAP_IMPULSE_USE, USE_IN_RADIUS, all func_tank* classes), but its Use does nothing unless 32
-- "Controllable" is set (13 maps have such a gun that is not). The control volume the player must stand in is a server trigger: not readable, the prompt
-- shows whatever the place. Taking the gun changes the state (the player now controls it): one-shot. func_tank in d1_canals_01a, d1_canals_07, d2_coast_01.
register("hl2_tanks", {
	class = {"func_tank", "func_tankairboatgun", "func_tankapcrocket", "func_tanklaser", "func_tankmortar", "func_tankphyscannister",
		"func_tankpulselaser", "func_tankrocket", "func_tank_combine_cannon"},
	icon = "use", text = "USE", use = "once", spawnflags = {need = 32}
})

-- The NPCs that answer +use while they live: CAI_PlayerAlly::ObjectCaps (ai_playerally.h) through UsableNPCObjectCaps, which gives
-- FCAP_IMPULSE_USE to an NPC that is alive. Only the ones whose Use does something: the citizen (follow me, or a question), Barney and Alyx (they speak)
-- and the vortigaunt (he heals, or speaks), all CNPC_PlayerCompanion. npc_citizen in d1_trainstation_01, npc_barney in d1_trainstation_01 and
-- d1_trainstation_05, npc_alyx in d1_eli_01, npc_vortigaunt in d1_canals_01 (boxcar) and d1_eli_01. NOT here, although the game gives them a use cap
-- (ObjectCaps read in game: 26): the Monk, Dr Mossman and G-Man have no Use function (the key does nothing), and the metropolice only gets
-- angry (PrecriminalUse adds a warning). Kleiner, Eli, Breen and the dog have no use cap at all. Talking can be done again.
local TALKERS = {npc_citizen = true, npc_barney = true, npc_alyx = true, npc_vortigaunt = true}

register("hl2_talkers", {
	match = function(ent) return ask(ent, "IsNPC") == true and TALKERS[GryMod.API.ClassOf(ent) or ent:GetClass()] == true and (ask(ent, "Health") or 0) > 0 end,
	icon = "use", text = "TALK", use = "repeat", cooldown = 1
})

-- Garry's Mod's own: gmod_button (ENT:Use toggles it or presses it) in gamemodes/sandbox/entities/entities/gmod_button.lua, gmod_wheel
-- (ENT:Use reverses its motor), sent_ball (lua/entities/sent_ball.lua: ENT:Use eats it for 5 health, which changes the state). Spawned from the spawn menu
-- / the tools; none is in a stock map (gm_construct has a func_button and a func_useableladder). gmod_thruster has an ENT:Use with nothing in it: no prompt.
register("gmod_buttons", {class = {"gmod_button", "gmod_wheel"}, icon = "use", text = "USE", use = "repeat", cooldown = 0.5})
register("gmod_ball", {class = "sent_ball", icon = "pickup", text = "TAKE BALL", use = "once"})
