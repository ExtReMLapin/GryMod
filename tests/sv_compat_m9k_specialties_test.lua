-- Tests of the M9K Specialties patch, the server part (lua/grymod/compat/tools/sv_m9k_specialties.lua), GLuaTest format, server realm. M9K was not installed when this was
-- written; the stand-ins have what the patch reads in its public code (github.com/CFC-Servers/m9k_monorepo): the hook M9k_ProxyMineCanTrigger(mine, target, owner) of
-- entities/m9k_proxy.lua:38 (a false answer means the mine does not go off for that target), and the weapons' way of throwing (weapons/bobs_nade_base.lua, SWEP:Throw:
-- ents.Create, SetOwner, Spawn) and launching (weapons/m9k_m79gl.lua). Each case names the change whose absence makes it fail.

-- the patch's own function of an event (hook.Run would also run every other addon's hooks with these stand-ins)
local function fire(event, ...)
	local fn = hook.GetTable()[event] and hook.GetTable()[event]["GryMod compat m9k"]

	if fn then
		return fn(...)
	end

	return nil
end

local API
local realCloakLevel, realReport, reports
local realSimple, queue
local aiVar, aiWas

local function player(fields)
	local p = {IsValid = function() return true end, IsPlayer = function() return true end}

	for key, value in pairs(fields or {}) do
		p[key] = value
	end

	return p
end

local function projectile(class, owner, base)
	local e = {IsValid = function() return true end, GetClass = function() return class end, GetOwner = function() return owner or NULL end, Base = base}

	return e
end

-- timer.Simple of the patch is kept in a queue the case runs when it wants (the tick after the creation)
local function flush()
	local list = queue

	queue = {}

	for _, fn in ipairs(list) do
		fn()
	end
end

local function created(e)
	fire("OnEntityCreated", e)
	flush() -- the weapon sets the owner after ents.Create: the patch looks one tick later
end

local mine = {IsValid = function() return true end, GetClass = function() return "m9k_proxy" end}

return {
	groupName = "GryMod compat: M9K Specialties (server)",
	beforeEach = function()
		API = GryMod.API
		realCloakLevel, realReport = API.CloakLevel, API.ReportAttack
		reports = {}
		queue = {}
		realSimple = timer.Simple
		timer.Simple = function(_, fn) queue[#queue + 1] = fn end
		API.ReportAttack = function(ply, alt) reports[#reports + 1] = {ply, alt} return true end
		API.CloakLevel = function(ply) return ply.__cloak or 0 end
		aiVar = GetConVar("gry_cloak_ai") or CreateConVar("gry_cloak_ai", "1")
		aiWas = aiVar:GetBool()
		aiVar:SetBool(true)
		include("grymod/compat/tools/sh_m9k_specialties.lua")
		include("grymod/compat/tools/sv_m9k_specialties.lua")
	end,
	afterEach = function()
		API.CloakLevel, API.ReportAttack = realCloakLevel, realReport
		timer.Simple = realSimple
		aiVar:SetBool(aiWas)
	end,
	cases = {
		{
			-- fails when the proximity mine is kept from going off for a camouflaged player: it goes off under the feet whatever the player is seen as (the camouflage hides from the visible
			-- light only, not from a mine), so GryMod leaves the hook M9k_ProxyMineCanTrigger alone
			name = "a proximity mine goes off for a camouflaged player like for anybody: GryMod has no say in it",
			func = function()
				expect(hook.GetTable()["M9k_ProxyMineCanTrigger"] == nil or hook.GetTable()["M9k_ProxyMineCanTrigger"]["GryMod compat m9k"] == nil).to.beTrue()
				expect(fire("M9k_ProxyMineCanTrigger", mine, player({__cloak = 1}), nil)).to.beNil()
				expect(fire("M9k_ProxyMineCanTrigger", mine, player({__cloak = 0.6}), nil)).to.beNil()
			end
		},
		{
			-- fails when throwing a grenade or firing a launcher does not end the camouflage (neither is a bullet)
			name = "a grenade thrown, a 40 mm grenade and a rocket fired by a player end his camouflage",
			func = function()
				local me = player()

				created(projectile("m9k_thrown_m61", me))
				created(projectile("m9k_launched_m79", me, "m9k_launched_projectile_base"))
				created(projectile("m9k_m202_rocket", me))

				expect(#reports).to.equal(3)
				expect(reports[1][1]).to.equal(me)
				expect(reports[1][2]).to.equal(false)
			end
		},
		{
			-- fails when a projectile with no player owner (an NPC's, the world's) or a mine laid on the floor is told as an attack of a player, or when the owner is taken at the instant
			-- of the creation (the weapon sets it after ents.Create: the patch must look one tick later)
			name = "nothing is told for a projectile nobody owns, an NPC's, a mine or a C4 laid, or a grenade of another addon",
			func = function()
				local npc = {IsValid = function() return true end, IsPlayer = function() return false end}

				created(projectile("m9k_thrown_m61", nil))
				created(projectile("m9k_thrown_m61", npc))
				created(projectile("m9k_proxy", player()))
				created(projectile("m9k_mad_c4", player()))
				created(projectile("npc_grenade_frag", player()))

				expect(#reports).to.equal(0)
			end
		},
		{
			-- fails when the owner is read at the instant of the creation: M9K sets it after ents.Create
			name = "the owner is read one tick after the creation, not at it",
			func = function()
				local me = player()
				local late = {IsValid = function() return true end, GetClass = function() return "m9k_thrown_m61" end}
				local owner = NULL

				late.GetOwner = function() return owner end
				fire("OnEntityCreated", late)

				expect(#reports).to.equal(0)

				owner = me
				flush()

				expect(#reports).to.equal(1)
			end
		},
		{
			-- fails when an entity that is removed in the tick, or an error of the reader, breaks the creation of the entities of the game
			name = "an entity removed at once, or with no owner method, raises nothing",
			func = function()
				local gone = projectile("m9k_thrown_m61", player())

				fire("OnEntityCreated", gone)
				gone.IsValid = function() return false end
				flush()
				created({IsValid = function() return true end, GetClass = function() return "m9k_thrown_m61" end})

				expect(#reports).to.equal(0)
			end
		}
	}
}
