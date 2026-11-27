-- Tests of the Glide adapter, the server part (compat/vehicles/sv_glide.lua): the veto of the reset at the spawn that Glide makes when a player gets up from a ragdoll, the
-- refusal of a missile's lock-on to a camouflaged driver, and the camouflage that ends on a missile or a shell fired from a vehicle. GLuaTest format, server realm.
--
-- Glide is NOT installed in the test game: the players, vehicles and missiles are STAND-INS that answer the way the code of Glide does (lua/glide/server/ragdoll.lua keeps
-- ply.GlideSpawnData while it calls ply:Spawn(); lua/glide/server/weaponry.lua asks the hook Glide_CanLockOn(ent, attacker); entities/glide_missile/init.lua keeps the player in
-- the field attacker and the vehicle as the engine owner). The functions of GryMod that the adapter calls (CloakLevel, ReportAttack) are replaced and put back after each case.
-- Each case names the production change whose absence makes it fail.

local API
local saved = {}
local reports
local pending

-- class -> base for the stand-in missiles (put in scripted_ents.IsBasedOn for the case)
local CHAIN = {glide_missile = "base_anim", glide_projectile = "base_anim", t_glide_firework = "glide_missile", t_glide_shell = "glide_projectile", t_other_rocket = "base_anim"}
local realIsBasedOn

local function player(name, extra)
	local p = {
		IsValid = function() return true end,
		GetClass = function() return "player" end,
		IsPlayer = function() return true end,
		name = name,
		cloak = 0
	}

	for key, value in pairs(extra or {}) do
		p[key] = value
	end

	return p
end

local function vehicle(driver, fields)
	local v = {
		IsValid = function() return true end,
		GetClass = function() return "t_glide_car" end,
		IsPlayer = function() return false end,
		IsGlideVehicle = true,
		GetDriver = function() return driver end
	}

	for key, value in pairs(fields or {}) do
		v[key] = value
	end

	return v
end

local function missile(class, attacker, owner)
	return {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetOwner = function() return owner end,
		attacker = attacker
	}
end

local function setConVar(name, value)
	local cv = GetConVar(name)

	assert(cv, "the convar " .. name .. " does not exist")

	saved[name] = saved[name] or cv:GetString()
	cv:SetString(value)
end

-- what the hook of the adapter does for a missile, run now (the hook asks a timer for the tick after: the case takes the timer's function and runs it)
local function created(ent)
	local handler = hook.GetTable().OnEntityCreated and hook.GetTable().OnEntityCreated["GryModGlideAttack"]

	assert(handler, "the hook OnEntityCreated of the adapter is not there")

	local realSimple = timer.Simple

	timer.Simple = function(_, fn) pending[#pending + 1] = fn end

	local ok, err = pcall(handler, ent)

	timer.Simple = realSimple
	assert(ok, err)

	for _, fn in ipairs(pending) do
		fn()
	end

	pending = {}
end

return {
	groupName = "GryMod Glide adapter: the respawn, the lock-on and the attacks (server)",
	beforeEach = function()
		API = GryMod.API
		reports = {}
		pending = {}
		saved = {}
		realIsBasedOn = scripted_ents.IsBasedOn

		scripted_ents.IsBasedOn = function(class, base)
			local at, guard = class, 0

			while at and guard < 20 do
				if at == base then
					return true
				end

				at, guard = CHAIN[at], guard + 1
			end

			local ok, answer = pcall(realIsBasedOn, class, base)

			return ok and answer or false
		end

		saved.CloakLevel, saved.ReportAttack = API.CloakLevel, API.ReportAttack

		API.CloakLevel = function(ply) return ply.cloak or 0 end
		API.ReportAttack = function(ply, right)
			reports[#reports + 1] = {ply = ply, right = right}

			return true
		end
	end,
	afterEach = function()
		scripted_ents.IsBasedOn = realIsBasedOn
		API.CloakLevel, API.ReportAttack = saved.CloakLevel, saved.ReportAttack

		for name, value in pairs(saved) do
			if name ~= "CloakLevel" and name ~= "ReportAttack" and GetConVar(name) then
				GetConVar(name):SetString(value)
			end
		end
	end,
	cases = {
		{
			-- fails when the adapter does not answer the veto, or answers it for a spawn that Glide does not make
			name = "a spawn inside the getting up of a Glide ragdoll is vetoed: the suit keeps its state",
			func = function()
				local p = player("rider", {GlideSpawnData = {health = 80}})

				-- Glide: UnRagdollPlayer runs the hook, then Spawn() (PlayerSpawn runs now, in the same tick)
				hook.Run("Glide_PrePlayerUnRagdoll", p)

				expect(hook.Run("GryMod_CanResetOnSpawn", p)).to.equal(false)
			end
		},
		{
			-- fails when the stored spawn data alone is taken for a restoration: a player killed while ragdolled keeps GlideSpawnData (UnRagdollPlayer returns at once for a dead player), and his
			-- real respawn, later, must reset the suit
			name = "the respawn of a player who died while ragdolled is a real one: it is not vetoed",
			func = function()
				local p = player("dead rider", {GlideSpawnData = {health = 80}})

				hook.Run("Glide_PrePlayerUnRagdoll", p)

				-- the getting up was a few seconds ago (the adapter stamps the player with the time of the hook, ply.GryGlideUnragdollAt)
				p.GryGlideUnragdollAt = CurTime() - 5

				expect(hook.Run("GryMod_CanResetOnSpawn", p)).to.beNil()
			end
		},
		{
			-- fails when a spawn of a player Glide never touched is vetoed
			name = "an ordinary spawn is not vetoed, with or without Glide's data",
			func = function()
				expect(hook.Run("GryMod_CanResetOnSpawn", player("walker"))).to.beNil()
				expect(hook.Run("GryMod_CanResetOnSpawn", player("rider", {GlideSpawnData = {}}))).to.beNil()
				hook.Run("Glide_PrePlayerUnRagdoll", player("other"))
				expect(hook.Run("GryMod_CanResetOnSpawn", player("other2"))).to.beNil()
			end
		},
		{
			-- fails when the lock-on is not refused for the driver of a vehicle whose camouflage is more than half on
			name = "Glide_CanLockOn refuses a vehicle whose driver is camouflaged",
			func = function()
				local driver = player("driver", {cloak = 1})
				local attacker = player("attacker")

				expect(hook.Run("Glide_CanLockOn", vehicle(driver), attacker)).to.equal(false)
			end
		},
		{
			-- fails when the refusal ignores the fade (a camouflage that just began, or just ended, is still half seen) or when a plain driver is refused
			name = "the lock-on is refused from half of the camouflage on, never for a driver who is not camouflaged",
			func = function()
				local attacker = player("attacker")

				expect(hook.Run("Glide_CanLockOn", vehicle(player("a", {cloak = 0.6})), attacker)).to.equal(false)
				expect(hook.Run("Glide_CanLockOn", vehicle(player("b", {cloak = 0.4})), attacker)).to.beNil()
				expect(hook.Run("Glide_CanLockOn", vehicle(player("c", {cloak = 0})), attacker)).to.beNil()
				expect(hook.Run("Glide_CanLockOn", vehicle(nil), attacker)).to.beNil()
			end
		},
		{
			-- fails when a player is refused the lock-on of his own vehicle (the homing launcher asks with the attacker), or a seat or a player is not read
			name = "the refusal does not apply to the driver himself, and a camouflaged player or a seat with one in it is refused too",
			func = function()
				local driver = player("driver", {cloak = 1})
				local attacker = player("attacker")

				expect(hook.Run("Glide_CanLockOn", vehicle(driver), driver)).to.beNil()
				expect(hook.Run("Glide_CanLockOn", driver, attacker)).to.equal(false)
				expect(hook.Run("Glide_CanLockOn", {IsValid = function() return true end, GetClass = function() return "prop_vehicle_prisoner_pod" end, GetDriver = function() return driver end}, attacker)).to.equal(false)
			end
		},
		{
			-- fails when the server setting does not switch the refusal off, or does not exist (default 1)
			name = "gry_glide_cloak_lockon 0 gives the lock-on back, and the setting is on by default",
			func = function()
				expect(GetConVar("gry_glide_cloak_lockon")).to.exist()
				expect(GetConVar("gry_glide_cloak_lockon"):GetDefault()).to.equal("1")

				setConVar("gry_glide_cloak_lockon", "0")
				expect(hook.Run("Glide_CanLockOn", vehicle(player("driver", {cloak = 1})), player("attacker"))).to.beNil()
			end
		},
		{
			-- fails when the missile of the homing launcher (a SWEP, no bullet: the engine's bullet hook never sees it) does not end the camouflage of the player who fired it
			name = "a missile that a player fires from his hands (owner = the player) ends his camouflage",
			func = function()
				local shooter = player("shooter")

				created(missile("glide_missile", shooter, shooter))

				expect(#reports).to.equal(1)
				expect(reports[1].ply).to.equal(shooter)
				expect(reports[1].right).to.beFalse()
			end
		},
		{
			-- fails when a missile fired by the vehicle the player sits in is not reported (its engine owner is the vehicle), or a missile built on glide_missile by another addon is skipped
			name = "a missile or a shell fired by the vehicle the player sits in ends his camouflage, and so does one of another addon built on a Glide missile",
			func = function()
				local car = vehicle(nil)
				local shooter = player("gunner", {GlideGetVehicle = function() return car end})

				created(missile("glide_missile", shooter, car))
				created(missile("t_glide_firework", shooter, car))
				created(missile("t_glide_shell", shooter, car))

				expect(#reports).to.equal(3)
			end
		},
		{
			-- fails when a launcher a player placed (the tool: attacker = its creator, owner = the launcher) ends the camouflage of the creator who stands somewhere else
			name = "a missile of a launcher the player only owns, or of nobody, or of a class that is not a Glide missile, reports nothing",
			func = function()
				local owner = player("owner")
				local launcher = vehicle(nil)

				created(missile("glide_missile", owner, launcher))
				created(missile("glide_missile", nil, launcher))
				created(missile("glide_missile", "not a player", nil))
				created(missile("t_other_rocket", owner, owner))

				expect(#reports).to.equal(0)
			end
		}
	}
}
