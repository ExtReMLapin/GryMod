-- Live checks of the DrGBase adapter (lua/grymod/compat/npc/*drgbase.lua) with the REAL DrGBase and its real nextbots, run with lua_job (server realm, one job at a time, a map loaded; the player
-- is put in god mode and left that way: restart the map after). DrGBase is not part of the game: mount it with the Lua of GryMod (one lua_mount folder holding both lua/ folders, see docs/compat.md).
-- Returns a table of named results; every `ok` must be true. The same checks were run by hand on 2026-11-27 (compat.md, "How it was checked").

local ply = player.GetAll()[1]
local results = {}

local function check(name, ok, detail)
	results[#results + 1] = {name = name, ok = ok == true, detail = detail}
end

if not DrGBase then
	return {skipped = "DrGBase is not mounted"}
end

ply:GodEnable()
ply:StripWeapons()
GryMod.API.RefillEnergy(ply)
GryMod.API.SetMode(ply, GryMod.Modes.ARMOR)
ply:SetPos(Vector(0, 0, -130))

local function dmg()
	local d = DamageInfo()

	d:SetDamage(20)
	d:SetDamageType(DMG_BULLET)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())

	return d
end

-- 1. the zombie: a creature, tracked, hostile to the player; its alert level follows what it knows
local z = ents.Create("npc_drg_zombie")

z:SetPos(ply:GetPos() + Vector(300, 0, 0))
z:Spawn()
job:sleep(0.5)
check("a nextbot is a creature", GryMod.API.IsCreature(z))
check("its entry is the adapter's", (GryMod.API.GetTracked(z) or {}).key == "compat.drgbase")
check("hostile to the player (D_HT by default)", GryMod.API.Relation(ply, z) == "hostile")

-- in front of it: it sees the player and fights him
ply:SetPos(z:GetPos() + z:GetForward() * 250 + Vector(0, 0, 4))
job:sleep(2)
local aware = GryMod.Radar.AwarenessOf(z, ply)

check("fighting (level 2) and seen once it has the player as enemy", aware and aware.level == 2 and aware.seen == true, aware)

-- camouflaged: DrGBase ignores the player (its own relation turns neutral) but GryMod keeps it hostile (the absolute relation)
GryMod.API.SetMode(ply, GryMod.Modes.CLOAK)
job:sleep(0.5)
check("DrGBase's own relation is neutral for a camouflaged player", z:GetRelationship(ply) == D_NU)
check("GryMod's relation stays hostile", GryMod.API.Relation(ply, z) == "hostile")

-- possession: camera owner (client), hit ignored, the camouflage is back after the end
check("not a camera owner before", job:call("client", "return GryMod.API.IsCameraOwned(LocalPlayer(), true)") == false)
z:Possess(ply)
job:sleep(0.5)
check("a possessing player's hits are ignored", GryMod.API.HitVerdict(ply, dmg()) == "ignore")
check("a possessing player's camera is another's", job:call("client", "return GryMod.API.IsCameraOwned(LocalPlayer(), true)") == true)
z:Dispossess()
job:sleep(1.6)
check("the camouflage's notarget flag is back after the possession", ply:IsFlagSet(FL_NOTARGET))
GryMod.API.SetMode(ply, GryMod.Modes.ARMOR)
z:Remove()

-- 2. the grenades
ply:SetPos(Vector(0, 0, -130))
local frag = ents.Create("proj_drg_grenade")
local smoke = ents.Create("proj_drg_smoke_grenade")

frag:SetPos(ply:GetPos() + Vector(150, 0, 80))
frag:Spawn()
smoke:SetPos(ply:GetPos() + Vector(150, 60, 80))
smoke:Spawn()
job:sleep(0.5)
check("a grenade lying around is a danger entry but not armed", GryMod.API.GetDanger(frag) ~= nil and frag:GetNW2Bool("GryArmed") == false)
frag:Unpin()
smoke:Unpin()
job:sleep(0.6)
check("armed once the pin is out", frag:GetNW2Bool("GryArmed") == true)
check("the smoke grenade is no danger", GryMod.API.GetDanger(smoke) == nil and smoke:GetNW2Bool("GryArmed") == false)
frag:Remove()
smoke:Remove()

-- 3. the noises of the suit reach a nextbot that does not see the player
local z2 = ents.Create("npc_drg_zombie")

z2:SetPos(ply:GetPos() + Vector(600, 0, 0))
z2:SetAngles(Angle(0, 0, 0))
z2:Spawn()
z2:SetSightFOV(60)
job:sleep(0.7)
check("it does not see the player first", z2:HasSpotted(ply) == false and z2:IsInSight(ply) == false)
GryMod.EmitSuitNoise(ply, "speed_sprint")
check("a sprint noise spots him", z2:HasSpotted(ply) == true)
z2:Remove()

local failed = {}

for _, r in ipairs(results) do
	if not r.ok then
		failed[#failed + 1] = r.name
	end
end

return {ok = #failed == 0, failed = failed, results = results}
