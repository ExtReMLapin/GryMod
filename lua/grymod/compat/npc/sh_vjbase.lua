-- VJ Base (the most used NPC base of Garry's Mod, and the packs built on it: Half-Life Resurgence, the official collection...), shared part of the adapter. Part
-- of the compatibility patches (lua/grymod/compat/, docs/compat.md): it uses only the public API of GryMod (RegisterTracked, RegisterUsable, RegisterWeapon,
-- AddCameraOwner), it is data and small readers, and it does nothing when VJ Base is not installed (no VJ table: Setup returns at once, never an error).
-- Every fact about VJ Base below was read in its code (VJ-Base/lua/..., version 3.3.0 and the 3.2.0 release) and tried in a real game; the names of the
-- tags (VJ_ID_*) are the ones VJ Base documents (docs revamp-dev.md, "Entity Tags").
--
-- What it says (what the entities ARE, nothing more):
--   * the dangerous projectiles of the grenade warning: every class VJ tags as a grenade or a danger (VJ_ID_Grenade, VJ_ID_Danger, set in the SHARED part of each
--     projectile file) that is a grenade, a rocket, a shell or a bomb. The server follows them from their creation, they need no armed reader (the fuse and the
--     flight start at once);
--   * the icons of the radar: the tanks are machines, the aircraft flying units; the bullseye (an "ai" entity of VJ that every NPC controller makes) is never a
--     contact and the binoculars do not tag it;
--   * the use prompts: a weapon on the floor is taken with the use key (VJ asks for it, unless vj_wep_autopickup), an ally follows when used;
--   * the weapon slot: a melee weapon has no gun icon;
--   * the camera of VJ's NPC controller (the player possesses an NPC) owns the view.
-- It runs at InitPostEntity: the autorun of GryMod comes before the one of VJ Base, and the classes of the packs exist only after every addon was read.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked then
	return -- sh_api.lua and sh_api_tracked.lua are included first (grymod_shared.lua)
end

local VJBase = GryMod.VJBase or {}
GryMod.VJBase = VJBase

-- The words of a class name that make a tagged danger an explosive of that kind. VJ tags other things as dangers (a hornet, an orb, a stomp): not these.
local KIND_WORDS = {
	{"grenade", "grenade"},
	{"rocket", "missile"},
	{"missile", "missile"},
	{"shell", "missile"},
	{"mortar", "bomb"},
	{"bomb", "bomb"},
	{"combineball", "energy"}
}

local KIND_LABEL = {grenade = "GRENADE", missile = "MISSILE", bomb = "BOMB", energy = "ENERGY BALL"}
local KEYS = {grenade = "vjbase_grenades", missile = "vjbase_missiles", bomb = "vjbase_bombs", energy = "vjbase_energy"}
-- what the player fires himself never warns him
local OWN = {missile = true, energy = true}

-- "grenade", "missile", "bomb", "energy" or nil for a projectile class. `member(class, key)` says what the class declares (scripted_ents.GetMember by default: it walks the
-- base classes). A tagged grenade is a grenade whatever its name; a tagged danger is told by its name; an NPC is never one.
function VJBase.ProjectileKind(class, member)
	member = member or scripted_ents.GetMember

	if not isstring(class) then
		return nil
	end

	local grenade, danger = member(class, "VJ_ID_Grenade"), member(class, "VJ_ID_Danger")

	if not grenade and not danger then
		return nil
	end

	if member(class, "Type") == "ai" then
		return nil
	end

	if grenade then
		return "grenade"
	end

	local name = string.lower(class)

	for _, pair in ipairs(KIND_WORDS) do
		if string.find(name, pair[1], 1, true) then
			return pair[2]
		end
	end

	return nil
end

-- The classes of every kind: {grenade = {...}, missile = {...}, bomb = {...}}, from the scripted entities that exist now (the same on both realms: the tags are in
-- the shared part of the files).
function VJBase.ScanProjectiles()
	local found = {grenade = {}, missile = {}, bomb = {}, energy = {}}

	for class in pairs(scripted_ents.GetList()) do
		local kind = VJBase.ProjectileKind(class)

		if kind then
			found[kind][#found[kind] + 1] = class
		end
	end

	for _, list in pairs(found) do
		table.sort(list)
	end

	return found
end

-- A weapon on the floor that VJ lets the player take only with the use key: the weapon is VJ's and nobody holds it. (An autopickup setting of the player
-- turns it off: the entry's `active`.)
function VJBase.IsFloorWeapon(ent)
	if not istable(ent) and not isentity(ent) then
		return false
	end

	if ent.IsVJBaseWeapon ~= true then
		return false
	end

	local owner = ent:GetOwner()

	return not (isentity(owner) and IsValid(owner))
end

-- Whether the use key makes this VJ NPC follow the player: VJ marks the NPCs that follow (the server writes GryVJFollow, see sv_vjbase.lua: VJ keeps this only
-- on the server), it is alive and the server says it is an ally. `relation` is GryMod.API.ClientRelation's answer (nil: not known yet).
function VJBase.IsFollowCandidate(ent, relation)
	if relation ~= "ally" or not ent or ent.IsVJBaseSNPC ~= true then
		return false
	end

	if not ent:GetNW2Bool("GryVJFollow", false) then
		return false
	end

	return ent:Health() > 0
end

local function register(key, def)
	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the VJ Base entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- Puts the adapter in the registries. Safe to run again (the same keys replace the earlier entries). Nothing without VJ Base.
function VJBase.Setup()
	if not VJ then
		return false
	end

	-- the relation provider (server): see sv_vjbase.lua
	if SERVER and VJBase.SetupServer then
		VJBase.SetupServer()
	end

	-- the dangerous projectiles. The classes are a list because the warning's client looks for entities by class; a pack that loads later is in the next Setup
	for kind, classes in pairs(VJBase.ScanProjectiles()) do
		if #classes > 0 then
			register(KEYS[kind], {
				class = classes,
				priority = -50,
				danger = {label = KIND_LABEL[kind], type = kind, ownMissile = OWN[kind] == true}
			})
		end
	end

	-- the radar: below the stock entries of Half-Life 2 (-100), which win for their classes; the tanks and the aircraft are VJ's own
	register("vjbase_tanks", {base = {"npc_vj_tank_base", "npc_vj_tankg_base"}, type = "machine", size = "big", priority = -200})
	register("vjbase_aircraft", {
		match = function(ent) return ent.VJ_ID_Aircraft == true end,
		type = "flying", priority = -200
	})
	register("vjbase_bullseye", {class = "obj_vj_bullseye", radar = "never", scan = false, priority = -200})

	-- the weapon slot: a melee weapon is no gun; a gun is what its Primary says
	if API.RegisterWeapon then
		API.RegisterWeapon("weapon_vj_base", {
			fire = function(weapon)
				if weapon.IsMeleeWeapon == true then
					return "none"
				end

				local primary = weapon.Primary

				return istable(primary) and primary.Automatic == true and "auto" or "semi"
			end
		})
	end

	-- the use prompts
	if API.RegisterUsable then
		API.RegisterUsable("vjbase_weapon", {
			match = VJBase.IsFloorWeapon,
			icon = "pickup", text = "TAKE %1", use = "once",
			priority = -50,
			-- VJ's own setting of the player: with it a weapon is taken by walking over it, no key needed
			active = function()
				if SERVER then
					return true
				end

				local autopickup = GetConVar("vj_wep_autopickup")

				return not (autopickup and autopickup:GetBool())
			end
		})

		API.RegisterUsable("vjbase_follow", {
			match = function(ent)
				if SERVER then
					return false
				end

				return ent.IsVJBaseSNPC == true and VJBase.IsFollowCandidate(ent, API.ClientRelation and API.ClientRelation(ent))
			end,
			icon = "use", text = "FOLLOW", use = "repeat", cooldown = 1,
			priority = -50,
			active = function()
				if SERVER then
					return true
				end

				local follow = GetConVar("vj_npc_ply_follow")

				return not follow or follow:GetBool()
			end
		})
	end

	-- the NPC controller: the player possesses an NPC and VJ draws the view (VJ sets ply.VJ_Controlling on the client itself)
	if CLIENT and API.AddCameraOwner then
		API.AddCameraOwner("vjbase_controller", function(ply)
			return ply.VJ_Controlling == true
		end)
	end

	return true
end

VJBase.Runs = VJBase.Runs or 0

local function setup()
	local ok, err = pcall(VJBase.Setup)

	VJBase.Runs = VJBase.Runs + 1

	if not ok then
		ErrorNoHalt("[GryMod] the VJ Base adapter failed: " .. tostring(err) .. "\n")
	end
end

hook.Add("InitPostEntity", "GryMod VJ Base adapter", setup)

-- The client's InitPostEntity does not always come after the file is loaded (measured: it never ran this hook on a client started with the map): the first frame comes
-- after every autorun file has run, those of VJ Base included, and after the entities exist. Setup is safe to run twice.
timer.Simple(0, setup)

if VJ then
	setup() -- a hot reload, or VJ Base started before this file
end
