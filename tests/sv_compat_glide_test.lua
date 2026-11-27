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
local CHAIN = {glide_missile = "base_anim", glide_projectile = "base_anim", t_glide_firework = "glide_missile", t_glide_shell = "glide_projectile", t_other_rocket = "base_anim",
	base_glide = "base_anim", base_glide_car = "base_glide", t_glide_car = "base_glide_car"}
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

		-- the engine's IsBasedOn(class, base) is false for a class and itself (found with the real Glide: the plain glide_missile and glide_projectile were never looked at)
		scripted_ents.IsBasedOn = function(class, base)
			local at, guard = CHAIN[class], 0

			while at and guard < 20 do
				if at == base then
					return true
				end

				at, guard = CHAIN[at], guard + 1
			end

			local ok, answer = pcall(realIsBasedOn, class, base)

			return ok and answer or false
		end

		-- what the adapter learned about the classes with the real IsBasedOn must not decide for the stand-in's
		GryMod.GlideCompat.ForgetClasses()

		saved.CloakLevel, saved.ReportAttack, saved.ReportShot = API.CloakLevel, API.ReportAttack, API.ReportShot

		API.CloakLevel = function(ply) return ply.cloak or 0 end
		API.ReportAttack = function(ply, right)
			reports[#reports + 1] = {ply = ply, right = right, via = "attack"}

			return true
		end
		-- the core's report of a shot that leaves no bullet: the same tell, with the noise of a shot (sv_suit_noise.lua)
		API.ReportShot = function(ply, right)
			reports[#reports + 1] = {ply = ply, right = right, via = "shot"}

			return true
		end
	end,
	afterEach = function()
		scripted_ents.IsBasedOn = realIsBasedOn
		GryMod.GlideCompat.ForgetClasses()
		API.CloakLevel, API.ReportAttack, API.ReportShot = saved.CloakLevel, saved.ReportAttack, saved.ReportShot

		for name, value in pairs(saved) do
			if name ~= "CloakLevel" and name ~= "ReportAttack" and name ~= "ReportShot" and GetConVar(name) then
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
			-- fails when GryMod refuses the lock-on of a missile to a camouflaged driver: the lock-on is a radar or infrared lock, not an eye, and the camouflage hides from the visible light only (a player
			-- in a vehicle is never invisible anyway)
			name = "no lock-on veto: a missile of Glide locks on a vehicle whose driver is camouflaged like on any other",
			func = function()
				local hooks = hook.GetTable().Glide_CanLockOn

				expect(hooks == nil or hooks.GryModGlide == nil).to.beTrue()
				expect(hook.Run("Glide_CanLockOn", vehicle(player("driver", {cloak = 1})), player("attacker"))).to.beNil()
				expect(GetConVar("gry_glide_cloak_lockon")).to.beNil()
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
		},
		{
			-- fails when a missile or a shell fired from a vehicle makes no noise: a shot that leaves no bullet is told with GryMod.API.ReportShot (the core's, with the noise of a shot for the
			-- AI that listens), as LVS's and simfphys's are
			name = "a missile or a shell is told with the noise of a shot (ReportShot), not as a silent attack",
			func = function()
				local shooter = player("shooter")

				created(missile("glide_missile", shooter, shooter))
				created(missile("glide_projectile", shooter, shooter))

				expect(#reports).to.equal(2)
				expect(reports[1].via).to.equal("shot")
				expect(reports[2].via).to.equal("shot")
			end
		},
		{
			-- fails when the explosive cannon of an aircraft (VSWEP explosive_cannon: Glide.FireBullet only blasts the impact, no FireBullets, so no bullet for the engine's hook) does not end
			-- the camouflage of the player who sits in the vehicle that fires, when a normal bullet is told twice, when a player elsewhere is told, when the original is not called with the same
			-- arguments, or when a vehicle wrapped twice tells twice (found with the real Glide, gtav_lazer, 2026-11-27)
			name = "the explosive cannon of a Glide vehicle ends the camouflage of its gunner (once a quarter second); a bullet, or another player named as attacker, tells nothing",
			func = function()
				local calls = {}
				local car = vehicle(nil, {FireBullet = function(self, params) calls[#calls + 1] = {self, params} return "fired" end})
				local original = car.FireBullet
				local gunner = player("gunner", {GlideGetVehicle = function() return car end})
				local walker = player("walker", {GlideGetVehicle = function() return nil end})

				created(car)
				created(car)

				expect(car.FireBullet).notTo.equal(original)

				local params = {isExplosive = true, attacker = gunner}

				expect(car:FireBullet(params)).to.equal("fired")
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(car)
				expect(calls[1][2]).to.equal(params)
				expect(#reports).to.equal(1)
				expect(reports[1].ply).to.equal(gunner)
				expect(reports[1].via).to.equal("shot")

				-- twelve shots a second: one tell in a quarter second
				car:FireBullet({isExplosive = true, attacker = gunner})
				expect(#reports).to.equal(1)

				gunner.gryGlideShotAt = nil
				car:FireBullet({isExplosive = true, attacker = gunner})
				expect(#reports).to.equal(2)

				-- a machine gun's bullet goes through FireBullets: the engine's hook tells it, not the adapter
				gunner.gryGlideShotAt = nil
				car:FireBullet({attacker = gunner})
				expect(#reports).to.equal(2)

				-- the creator of the vehicle (the attacker when nobody drives it) is not the one who shoots
				car:FireBullet({isExplosive = true, attacker = walker})
				car:FireBullet({isExplosive = true})
				car:FireBullet()
				expect(#reports).to.equal(2)
				expect(#calls).to.equal(7)
			end
		},
		{
			-- fails when a blast on a player in a Glide vehicle pays the suit's bar (Glide sets that damage to 0 itself, events.lua Glide.OverrideDamage: the energy went down for nothing, found
			-- with the real Glide), when another kind of hit is ignored, or when a player on foot is
			name = "hit verdict: a blast on a player who sits in a Glide vehicle is ignored by the suit (Glide cancels it); any other hit, and a player on foot, are the suit's business",
			func = function()
				local car = vehicle(nil)
				local seated = player("rider", {GlideGetVehicle = function() return car end})
				local walker = player("walker", {GlideGetVehicle = function() return nil end})

				expect(API.HitVerdict(seated, {GetDamage = function() return 20 end, IsDamageType = function(_, flag) return bit.band(DMG_BLAST, flag) ~= 0 end})).to.equal("ignore")
				expect(API.HitVerdict(seated, {GetDamage = function() return 20 end, IsDamageType = function(_, flag) return bit.band(DMG_BULLET, flag) ~= 0 end})).to.beNil()
				expect(API.HitVerdict(walker, {GetDamage = function() return 20 end, IsDamageType = function(_, flag) return bit.band(DMG_BLAST, flag) ~= 0 end})).to.beNil()
				expect(API.HitVerdict(player("no glide function"), {GetDamage = function() return 20 end, IsDamageType = function() return true end})).to.beNil()
			end
		},
		{
			-- fails when the kill of an exploding vehicle (Glide: ply:TakeDamage(999) after hasExploded is set, then the vehicle is removed) is left to the bar: with infinite armor the occupant
			-- lived in the explosion of his vehicle (found with the real Glide); or when a whole vehicle, another player's vehicle, or a blast, gets that verdict
			name = "hit verdict: the kill of a vehicle that exploded goes through the bar (bypass); a whole vehicle's hit, or a blast, does not",
			func = function()
				local car = vehicle(nil, {hasExploded = true})
				local whole = vehicle(nil)
				local seated = player("rider", {GlideGetVehicle = function() return car end})
				local safe = player("rider in a whole one", {GlideGetVehicle = function() return whole end})
				local kind = function(flag) return function(_, f) return bit.band(flag, f) ~= 0 end end

				expect(API.HitVerdict(seated, {GetDamage = function() return 999 end, IsDamageType = kind(DMG_GENERIC)})).to.equal("bypass")
				expect(API.HitVerdict(seated, {GetDamage = function() return 999 end, IsDamageType = kind(DMG_CRUSH)})).to.equal("bypass")
				expect(API.HitVerdict(safe, {GetDamage = function() return 999 end, IsDamageType = kind(DMG_GENERIC)})).to.beNil()
				-- the blast of the explosion is cancelled by Glide: still ignored, not paid
				expect(API.HitVerdict(seated, {GetDamage = function() return 200 end, IsDamageType = kind(DMG_BLAST)})).to.equal("ignore")
			end
		}
	}
}
