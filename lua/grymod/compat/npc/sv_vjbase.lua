-- VJ Base (server part of the adapter, see sh_vjbase.lua): what only the server can do. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md):
-- the public API of GryMod only (AddRelationProvider, ReportAttack, GryMod_ModeChanged, GryMod.Radar.ExplosiveClasses, which the API guide names for the explosives
-- that make no env_explosion), nothing runs without VJ Base (every hook returns at once when there is no VJ table), no Think, no timer.
-- Every fact about VJ Base was read in its code and tried in a real game (version 3.3.0, VJ-Base/lua/vj_base/ai/core.lua).
--
--   1. The RELATION. GryMod asks the engine (Disposition: like, hate, anything else is neutral). VJ Base keeps its own view and says it to the engine late: a hostile
--      NPC that has not seen the player has D_VJ_INTEREST (100) or nothing, and a player with FL_NOTARGET (the camouflage) is D_NU to everybody, friends too. So the
--      radar and the danger bar would hear "neutral" from every VJ enemy until it fights, and the friends would stop being allies at the first camouflage. The
--      provider answers from VJ's own rules (its memory, its classes, its behaviour); what the engine says now wins when it is clear (D_HT, D_LI).
--   2. The FOLLOWERS. A VJ NPC that follows the player asks `Disposition(player) == D_LI` at each Think, and VJ writes D_NU for a player with FL_NOTARGET at its next
--      pass: the follower stops (measured: within a quarter of a second; a priority of 99 does not hold, VJ overwrites it after 0.75 s). While the player is camouflaged the
--      NPCs that follow him are told D_LI when they ask (only when the engine says D_NU: what the notarget made), through the NPC metatable's Disposition, which is
--      replaced only while somebody holds companions and put back after.
--   3. The weapon in the hands: VJ's melee weapons and launchers do not fire a bullet, so the camouflage would not end (GryMod.API.ReportAttack).
--   4. The explosions: VJ's projectiles blast with VJ.ApplyRadiusDamage and draw the explosion as an effect (no env_explosion, no util.BlastDamage): they ring the radar
--      through Radar.ExplosiveClasses, with the radius the projectile declares.
--   5. The slow of a melee hit (MeleeAttackPlayerSpeed) gives the player's old speeds back after some seconds: they are the new mode's if the mode changed meanwhile.
--   6. The prompt of an ally that follows: VJ keeps `FollowPlayer` on the server only, the server marks the NPCs that follow when used (GryVJFollow).

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.AddRelationProvider then
	return -- sh_api.lua and sv_api.lua are included first (grymod_shared.lua)
end

local VJBase = GryMod.VJBase or {}
GryMod.VJBase = VJBase

local KEY = "GryMod VJ Base adapter"
local weak = {__mode = "k"}

-- ---------------------------------------------------------------------------------------------------------
-- 1. The relation
-- ---------------------------------------------------------------------------------------------------------

-- The names VJ Base uses (enums.lua), with the numbers it gives them when the table is not there yet.
local function behavior(name, default)
	local value = _G["VJ_BEHAVIOR_" .. name]

	return isnumber(value) and value or default
end

local function sharesClass(ply, npc)
	local mine, theirs = npc.VJ_NPC_Class, ply.VJ_NPC_Class

	if not istable(mine) or not istable(theirs) then
		return false
	end

	for _, class in ipairs(mine) do
		for _, other in ipairs(theirs) do
			if class == other then
				return true
			end
		end
	end

	return false
end

-- "ally", "neutral" or "hostile" for a VJ Base NPC and a player, or nil (no opinion: not a VJ NPC, or the game ignores the players). Not kept: see CachedRelation.
function VJBase.Relation(ply, npc)
	if not npc or npc.IsVJBaseSNPC ~= true or VJ_CVAR_IGNOREPLAYERS == true then
		return nil
	end

	-- what the engine says now, when it is clear: VJ wrote D_HT when it saw the player, D_LI for a friend
	local live = npc:Disposition(ply)

	if live == D_LI then
		return "ally"
	end

	if live == D_HT then
		return "hostile"
	end

	-- what VJ keeps: the memory of this player (the properties menu, a betrayal), then the classes, then the behaviour
	local memory = istable(npc.RelationshipMemory) and npc.RelationshipMemory[ply]
	local override = istable(memory) and memory[VJ and VJ.MEM_OVERRIDE_DISPOSITION or "override_disposition"]

	if override == D_LI then
		return "ally"
	elseif override == D_HT then
		return "hostile"
	elseif override == D_NU then
		return "neutral"
	end

	if npc.CanAlly ~= false and sharesClass(ply, npc) then
		return "ally"
	end

	local mode = npc.Behavior

	if mode == behavior("NEUTRAL", 2) or mode == behavior("PASSIVE", 3) or mode == behavior("PASSIVE_NATURE", 4) then
		return "neutral"
	end

	return "hostile"
end

-- The answer kept for a fifth of a second, per player and NPC: the radar asks it for every NPC five times a second and the binoculars' hologram for sixteen.
local TTL = 0.2
local cache = setmetatable({}, weak) -- [player] = {[npc] = {time, word or false}}

function VJBase.ForgetRelations()
	cache = setmetatable({}, weak)
end

function VJBase.CachedRelation(ply, npc)
	if not npc or npc.IsVJBaseSNPC ~= true then
		return nil
	end

	local now = CurTime()
	local perPlayer = cache[ply]

	if not perPlayer then
		perPlayer = setmetatable({}, weak)
		cache[ply] = perPlayer
	end

	local kept = perPlayer[npc]

	if kept and now - kept[1] < TTL then
		return kept[2] or nil
	end

	local word = VJBase.Relation(ply, npc)

	perPlayer[npc] = {now, word or false}

	return word
end

-- Put in the chain only when VJ Base is there (Setup, sh_vjbase.lua): the chain asks every provider about every NPC, so a machine without VJ Base pays nothing.
function VJBase.SetupServer()
	VJBase.ProviderAdded = API.AddRelationProvider(KEY, function(ply, ent)
		return VJBase.CachedRelation(ply, ent)
	end, 0)
end

function VJBase.TeardownServer()
	API.RemoveRelationProvider(KEY)
	VJBase.ProviderAdded = false
end

-- ---------------------------------------------------------------------------------------------------------
-- 2. The followers of a camouflaged player
-- ---------------------------------------------------------------------------------------------------------

-- What a follower is told when it asks how it stands with the player: D_LI instead of the D_NU (or D_ER) the notarget made, only for this player and only while
-- he is camouflaged. Anything else is the engine's answer.
function VJBase.CompanionDisposition(real, asked, ply, cloaked)
	if cloaked and asked == ply and (real == D_NU or real == D_ER) then
		return D_LI
	end

	return real
end

local held = setmetatable({}, weak) -- [player] = {[npc] = true}
local following = setmetatable({}, weak) -- [npc] = the player it follows while he is camouflaged

local function isCloaked(ply)
	return IsValid(ply) and ply:Alive() and API.GetMode(ply) == GryMod.Modes.CLOAK
end

local function eachNPC(fn)
	if ents.Iterator then
		for _, ent in ents.Iterator() do
			if ent.IsVJBaseSNPC == true then
				fn(ent)
			end
		end

		return
	end

	for _, ent in ipairs(ents.GetAll()) do
		if ent.IsVJBaseSNPC == true then
			fn(ent)
		end
	end
end

-- The NPCs that follow this player now.
function VJBase.Followers(ply)
	local list = {}

	eachNPC(function(npc)
		local data = npc.FollowData

		if npc.IsFollowing and not npc.Dead and istable(data) and data.Target == ply then
			list[#list + 1] = npc
		end
	end)

	return list
end

-- The follower asks `self:Disposition(player)` at every Think. The entity's own table does NOT take the place of an engine method (measured: a Disposition set on the
-- NPC is never called), so the answer is changed where it is made: the NPC metatable's Disposition, replaced only while somebody holds companions, put back when the
-- last one is let go (and left alone, as a plain pass-through, if another addon wrapped it on top of ours).
local metaNPC = FindMetaTable("NPC")
local engineDisposition = metaNPC.Disposition
local wrapper

local function installWrapper()
	if metaNPC.Disposition == wrapper then
		return
	end

	engineDisposition = metaNPC.Disposition

	wrapper = function(self, asked)
		local real = engineDisposition(self, asked)
		local ply = following[self]

		if ply then
			return VJBase.CompanionDisposition(real, asked, ply, isCloaked(ply))
		end

		return real
	end

	metaNPC.Disposition = wrapper
end

local function removeWrapper()
	if next(following) == nil and metaNPC.Disposition == wrapper then
		metaNPC.Disposition = engineDisposition
	end
end

function VJBase.IsHeld(npc)
	return following[npc] ~= nil
end

function VJBase.HoldCompanions(ply)
	local mine = held[ply] or setmetatable({}, weak)

	held[ply] = mine

	for _, npc in ipairs(VJBase.Followers(ply)) do
		mine[npc] = true
		following[npc] = ply
		installWrapper()
	end
end

function VJBase.ReleaseCompanions(ply)
	local mine = held[ply]

	if not mine then
		return
	end

	held[ply] = nil

	for npc in pairs(mine) do
		following[npc] = nil

		-- VJ writes the real answer itself at its next pass; the follower asks at every Think, so it is given back now
		if IsValid(npc) and IsValid(ply) and VJBase.Relation(ply, npc) == "ally" then
			npc:AddEntityRelationship(ply, D_LI, 0)
		end
	end

	removeWrapper()
end

-- ---------------------------------------------------------------------------------------------------------
-- 5. The slow of a melee hit
-- ---------------------------------------------------------------------------------------------------------

-- VJ stores the speeds to give back in ply.VJ_SlowDownPlayerWalkSpeed / RunSpeed at the hit and writes them 5 seconds later. A change of mode meanwhile put the new mode's
-- speeds on the player (sv_movement.lua): these are the ones to give back.
function VJBase.RefreshSlowSpeeds(ply)
	if ply.VJ_SpeedModified then
		ply.VJ_SlowDownPlayerWalkSpeed = ply:GetWalkSpeed()
		ply.VJ_SlowDownPlayerRunSpeed = ply:GetRunSpeed()
	end
end

hook.Add("GryMod_ModeChanged", KEY, function(ply, mode)
	if not VJ then
		return
	end

	local ok, err = pcall(function()
		if mode == GryMod.Modes.CLOAK then
			VJBase.HoldCompanions(ply)
		else
			VJBase.ReleaseCompanions(ply)
		end

		VJBase.RefreshSlowSpeeds(ply)
	end)

	if not ok then
		ErrorNoHalt("[GryMod] VJ Base adapter (mode change): " .. tostring(err) .. "\n")
	end
end)

local function letGo(ply)
	if VJ and held[ply] then
		pcall(VJBase.ReleaseCompanions, ply)
	end
end

hook.Add("PostPlayerDeath", KEY, letGo)
hook.Add("PlayerDisconnected", KEY, letGo)

-- ---------------------------------------------------------------------------------------------------------
-- 3. The weapon in the hands
-- ---------------------------------------------------------------------------------------------------------

-- A VJ melee weapon and a launcher (Primary.DisableBulletCode) fire no bullet: the server does not see the attack, the camouflage does not end. The wrapper is put on the
-- weapon ENTITY (once), so VJ's own table stays as it is; it reports after the weapon's own code ran, under pcall, and returns what the weapon returned.
function VJBase.WrapWeapon(weapon)
	if weapon.GryVJWrapped or not isfunction(weapon.PrimaryAttack) then
		return false
	end

	local original = weapon.PrimaryAttack

	weapon.GryVJWrapped = true
	weapon.PrimaryAttack = function(self, ...)
		local before = self:Clip1()
		local result = original(self, ...)

		pcall(function()
			local owner = self:GetOwner()

			if not (isentity(owner) and IsValid(owner) and owner:IsPlayer()) then
				return
			end

			local primary = self.Primary

			if self.IsMeleeWeapon == true or (istable(primary) and primary.DisableBulletCode == true and self:Clip1() < before) then
				API.ReportAttack(owner, false)
			end
		end)

		return result
	end

	return true
end

hook.Add("WeaponEquip", KEY, function(weapon, owner)
	if VJ and weapon.IsVJBaseWeapon == true and isentity(owner) and IsValid(owner) and owner:IsPlayer() then
		pcall(VJBase.WrapWeapon, weapon)
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- 4. The explosions of VJ's projectiles
-- ---------------------------------------------------------------------------------------------------------

-- A VJ projectile that blasts (DoesRadiusDamage with DMG_BLAST) is told to the radar's list of explosives the first time one is made: the ring comes when it is removed,
-- with the radius it declares (Radar.OnEntityRemoved, sv_radar_pings.lua). The fields are VJ's: RadiusDamageRadius, RadiusDamageType.
hook.Add("OnEntityCreated", KEY, function(ent)
	if ent.IsVJBaseProjectile ~= true or not VJ then
		return
	end

	local explosives = GryMod.Radar and GryMod.Radar.ExplosiveClasses
	local class = ent:GetClass()

	if not explosives or explosives[class] then
		return
	end

	local radius, kind = ent.RadiusDamageRadius, ent.RadiusDamageType

	if ent.DoesRadiusDamage == true and isnumber(radius) and radius > 0 and bit.band(isnumber(kind) and kind or DMG_BLAST, DMG_BLAST) ~= 0 then
		explosives[class] = {radius = radius}
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- 6. The prompt of an ally that follows
-- ---------------------------------------------------------------------------------------------------------

-- VJ Base writes no network variable of its own: whether the use key makes this NPC follow (ENT.FollowPlayer: true for the humans and the creatures, false for a tank)
-- is on the server only. It is a property of the class: written once for the NPC when it is made.
function VJBase.MarkFollower(npc)
	npc:SetNW2Bool("GryVJFollow", npc.FollowPlayer == true)
end

hook.Add("OnEntityCreated", KEY .. " follower", function(ent)
	if ent.IsVJBaseSNPC == true and VJ then
		timer.Simple(0.1, function()
			if IsValid(ent) then
				VJBase.MarkFollower(ent)
			end
		end)
	end
end)
