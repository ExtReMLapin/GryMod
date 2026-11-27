-- Tests of the server half of the LVS patch (lua/grymod/compat/vehicles/sv_lvs.lua), GLuaTest format, server realm: what the suit does with the hits an occupant takes (the filter
-- "lvs"), the shots LVS fires without telling the engine (LVS:FireBullet wrapped, the missiles and bombs one frame after they are made) and the relation of two players by LVS team.
-- LVS is not installed in the test game: stand-ins that answer like what was read in its code (lvs_hookers.lua: EntityTakeDamage zeroes a non DMG_DIRECT hit on an occupant unless
-- his collision group is COLLISION_GROUP_PLAYER; sv_damagesystem.lua: Explode hurts the occupants with DMG_DIRECT and Health() + Armor(); lvs_bulletsystem.lua: LVS:FireBullet(data)
-- with data.Attacker). The API is the real one, its report (ReportAttack) is counted. Each case names the production change whose absence makes it fail.

local API
local L
local realLVS
local realReport
local realSimple
local realIsBasedOn
local reports
local scheduled

local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function vehicle(team)
	return ent("lvs_x", {LVS = true, GetAITEAM = function() return team or 0 end})
end

-- a player: health, armor, the group of collision, the LVS vehicle he sits in (nil on foot), his own AI team
local function player(fields)
	local p = ent("player", {
		_health = 100, _armor = 0, _group = COLLISION_GROUP_IN_VEHICLE, _team = 0,
		IsPlayer = function() return true end,
		Health = function(self) return self._health end,
		Armor = function(self) return self._armor end,
		GetCollisionGroup = function(self) return self._group end,
		lvsGetVehicle = function(self) return self._vehicle or NULL end,
		lvsGetAITeam = function(self) return self._team end
	})

	for key, value in pairs(fields or {}) do
		p[key] = value
	end

	return p
end

-- the hook of the projectiles, or nil
local function projectileHook()
	return (hook.GetTable().OnEntityCreated or {})["GryMod compat LVS projectiles"]
end

local function damage(amount, kind)
	return {
		GetDamage = function() return amount end,
		IsDamageType = function(_, flag) return bit.band(kind, flag) ~= 0 end
	}
end

return {
	groupName = "GryMod compat: LVS (server)",
	beforeEach = function()
		API = GryMod.API
		L = GryMod.CompatLVS
		realLVS, realReport, realSimple, realIsBasedOn = LVS, API.ReportAttack, timer.Simple, scripted_ents.IsBasedOn
		reports, scheduled = {}, {}

		API.ReportAttack = function(ply, rightClick)
			reports[#reports + 1] = {ply, rightClick}

			return true
		end

		timer.Simple = function(delay, fn)
			scheduled[#scheduled + 1] = {delay, fn}
		end

		L.UninstallServer()
		LVS = {}
	end,
	afterEach = function()
		L.UninstallServer()
		API.ReportAttack, timer.Simple, scripted_ents.IsBasedOn = realReport, realSimple, realIsBasedOn
		LVS = realLVS

		if realLVS ~= nil then
			L.InstallServer()
		end
	end,
	cases = {
		{
			-- fails when InstallServer does something without LVS, or when the hit filter, the relation provider or the projectile hook are not registered with LVS
			name = "InstallServer registers the hit filter, the relation provider and the projectile hook only when LVS is there; UninstallServer takes them away",
			func = function()
				LVS = nil
				expect(L.InstallServer()).to.beFalse()
				expect(projectileHook()).to.beNil()

				LVS = {}
				expect(L.InstallServer()).to.beTrue()
				expect(isfunction(projectileHook())).to.beTrue()

				local seated = player({_vehicle = vehicle(1)})

				expect(API.HitVerdict(seated, damage(20, DMG_BULLET))).to.equal("ignore")

				L.UninstallServer()

				expect(projectileHook()).to.beNil()
				expect(API.HitVerdict(seated, damage(20, DMG_BULLET))).to.beNil()
			end
		},
		{
			-- fails when a hit on a player who is not in an LVS vehicle gets a verdict (the suit must work as always on foot)
			name = "hit verdict: a player on foot is the suit's business, whatever the damage type",
			func = function()
				local onFoot = player()

				expect(L.HitVerdict(onFoot, damage(30, DMG_BULLET))).to.beNil()
				expect(L.HitVerdict(onFoot, damage(1000, DMG_DIRECT))).to.beNil()
				expect(L.HitVerdict(onFoot, damage(30, DMG_BLAST))).to.beNil()
			end
		},
		{
			-- fails when a hit that LVS sets to 0 is not ignored (the bar would be paid for nothing), when the DMG_DIRECT exception is lost, or when the collision group test is not LVS's
			name = "hit verdict: a hit LVS sets to 0 on an occupant (not DMG_DIRECT, not the normal collision group) is ignored by the suit",
			func = function()
				local seated = player({_vehicle = vehicle(1)})

				for _, kind in ipairs({DMG_BULLET, DMG_BLAST, DMG_AIRBOAT, DMG_SONIC, DMG_BURN, DMG_CRUSH + DMG_VEHICLE}) do
					expect(L.HitVerdict(seated, damage(40, kind))).to.equal("ignore")
				end

				seated._group = COLLISION_GROUP_PLAYER

				expect(L.HitVerdict(seated, damage(40, DMG_BULLET))).to.beNil()
			end
		},
		{
			-- fails when the explosion's kill (exactly Health + Armor, or a car's 1000) is left to the bar, when a smaller DMG_DIRECT hit (a bullet through the window) is not the
			-- suit's, or when the limit is not the player's own Health + Armor
			name = "hit verdict: the explosion's DMG_DIRECT kill goes through the bar (bypass); a DMG_DIRECT hit that does not kill is the suit's business",
			func = function()
				local seated = player({_vehicle = vehicle(1), _health = 100, _armor = 20})

				expect(L.HitVerdict(seated, damage(120, DMG_DIRECT))).to.equal("bypass")
				expect(L.HitVerdict(seated, damage(1000, DMG_DIRECT))).to.equal("bypass")
				expect(L.HitVerdict(seated, damage(119, DMG_DIRECT))).to.beNil()
				expect(L.HitVerdict(seated, damage(35, DMG_DIRECT))).to.beNil()

				seated._health, seated._armor = 40, 0

				expect(L.HitVerdict(seated, damage(40, DMG_DIRECT))).to.equal("bypass")
				expect(L.HitVerdict(seated, damage(39, DMG_DIRECT))).to.beNil()
			end
		},
		{
			-- fails when ReportShot tells for a vehicle (an AI's shot), for nobody, or when a machine gun's ten bullets a second tell the suit ten times
			name = "ReportShot tells the suit once for a player (at most every quarter second) and never for an AI vehicle, NULL or nil",
			func = function()
				local shooter = player()

				expect(L.ReportShot(shooter)).to.beTrue()
				expect(#reports).to.equal(1)
				expect(reports[1][1]).to.equal(shooter)
				expect(reports[1][2]).to.beFalse()
				expect(L.ReportShot(shooter)).to.beFalse()
				expect(#reports).to.equal(1)

				shooter.gryLvsShotAt = shooter.gryLvsShotAt - L.SHOT_INTERVAL - 0.01

				expect(L.ReportShot(shooter)).to.beTrue()
				expect(#reports).to.equal(2)

				expect(L.ReportShot(vehicle(1))).to.beFalse()
				expect(L.ReportShot(NULL)).to.beFalse()
				expect(L.ReportShot(nil)).to.beFalse()
				expect(#reports).to.equal(2)
			end
		},
		{
			-- fails when the wrapper changes what LVS:FireBullet receives or returns, loses `self`, tells nothing for a player's bullet, tells for an AI's, or when wrapping twice
			-- fires the bullet (or the report) twice
			name = "LVS:FireBullet wrapped: the original runs once with the same arguments and answers, the attacker's shot is told, wrapping twice changes nothing",
			func = function()
				local calls = {}
				local original = function(self, data, extra)
					calls[#calls + 1] = {self, data, extra}

					return "bullet", 7
				end

				LVS = {FireBullet = original}

				expect(L.WrapFireBullet()).to.beTrue()
				expect(LVS.FireBullet).notTo.equal(original)
				expect(L.WrapFireBullet()).to.beTrue()

				local shooter = player()
				local data = {Attacker = shooter}
				local a, b = LVS:FireBullet(data, "x")

				expect(a).to.equal("bullet")
				expect(b).to.equal(7)
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(LVS)
				expect(calls[1][2]).to.equal(data)
				expect(calls[1][3]).to.equal("x")
				expect(#reports).to.equal(1)
				expect(reports[1][1]).to.equal(shooter)

				LVS:FireBullet({Attacker = vehicle(1)})

				expect(#calls).to.equal(2)
				expect(#reports).to.equal(1)
			end
		},
		{
			-- fails when a failure of the report stops LVS's bullet, when a call without data raises an error, or when UninstallServer does not give LVS its own function back
			name = "LVS:FireBullet wrapped: a report that fails, or a call without data, never stops the bullet; UninstallServer gives the original back",
			func = function()
				local count = 0
				local original = function()
					count = count + 1

					return count
				end

				LVS = {FireBullet = original}
				L.WrapFireBullet()

				local broken = ent("player", {IsValid = function() error("broken entity") end})

				expect(LVS:FireBullet({Attacker = broken})).to.equal(1)
				expect(LVS:FireBullet()).to.equal(2)
				expect(LVS:FireBullet("not a table")).to.equal(3)

				L.UninstallServer()

				expect(LVS.FireBullet).to.equal(original)
			end
		},
		{
			-- fails when LVS without FireBullet (a version that has none) raises an error
			name = "WrapFireBullet does nothing when LVS has no FireBullet",
			func = function()
				LVS = {}

				expect(L.WrapFireBullet()).to.beFalse()
				expect(LVS.FireBullet).to.beNil()
			end
		},
		{
			-- fails when a missile or a bomb (or a pack's class built on them) is not looked at, when another entity is, when the look is not one frame later (the attacker is set after
			-- Spawn), or when the shooter is not told
			name = "a projectile is looked at one frame after it is made: the player who fired it is told; other entities cost nothing",
			func = function()
				local bases = {t_pack_missile = "lvs_missile"}

				scripted_ents.IsBasedOn = function(class, base)
					return class == base or bases[class] == base
				end

				local shooter = player()

				L.OnEntityCreated(ent("prop_physics"))
				L.OnEntityCreated(ent("lvs_missile_countermeasure"))
				expect(#scheduled).to.equal(0)

				local rocket = ent("lvs_missile", {GetAttacker = function() return shooter end})
				local bomb = ent("lvs_bomb", {GetAttacker = function() return shooter end})
				local custom = ent("t_pack_missile", {GetAttacker = function() return shooter end})

				L.OnEntityCreated(rocket)
				L.OnEntityCreated(bomb)
				L.OnEntityCreated(custom)

				expect(#scheduled).to.equal(3)
				expect(scheduled[1][1]).to.equal(0)
				expect(#reports).to.equal(0)

				scheduled[1][2]()

				expect(#reports).to.equal(1)
				expect(reports[1][1]).to.equal(shooter)
			end
		},
		{
			-- fails when the missile of an AI vehicle (attacker: the vehicle), of a spawn with no attacker, or a projectile removed before the frame, tells the suit or raises an error
			name = "a projectile whose attacker is no player, or that is gone one frame later, tells nobody",
			func = function()
				local gone = {valid = true}

				gone.IsValid = function() return gone.valid end
				gone.GetClass = function() return "lvs_missile" end
				gone.GetAttacker = function() return player() end

				L.OnEntityCreated(ent("lvs_missile", {GetAttacker = function() return vehicle(1) end}))
				L.OnEntityCreated(ent("lvs_missile"))
				L.OnEntityCreated(gone)

				gone.valid = false

				for _, job in ipairs(scheduled) do
					job[2]()
				end

				expect(#scheduled).to.equal(3)
				expect(#reports).to.equal(0)
			end
		},
		{
			-- fails when two players of different LVS teams are not enemies, two of the same team are not friends, a team 0 has an opinion, or something that is not a player is answered
			name = "PlayerRelation: two players of different LVS teams are hostile, of the same team ally, a team 0 or a non player has no opinion",
			func = function()
				local function member(team, veh)
					return player({_team = team, _vehicle = veh})
				end

				expect(L.PlayerRelation(member(1), member(2))).to.equal("hostile")
				expect(L.PlayerRelation(member(1), member(1))).to.equal("ally")
				expect(L.PlayerRelation(member(1), member(3))).to.equal("hostile")
				expect(L.PlayerRelation(member(0), member(1))).to.beNil()
				expect(L.PlayerRelation(member(1), member(0))).to.beNil()
				-- the team of a player in a vehicle is the vehicle's
				expect(L.PlayerRelation(member(0), member(0, vehicle(2)))).to.beNil()
				expect(L.PlayerRelation(member(1, vehicle(1)), member(0, vehicle(2)))).to.equal("hostile")
				expect(L.PlayerRelation(member(1), vehicle(2))).to.beNil()
				expect(L.PlayerRelation(member(1), nil)).to.beNil()
			end
		}
	}
}
