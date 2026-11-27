-- Tests of the simfphys adapter, server half (lua/grymod/compat/vehicles/sv_simfphys.lua), GLuaTest format, server realm. simfphys is NOT installed where these cases were written: the
-- cars, the seats, the players and the damage are stand-ins that answer what simfphys' own code answers (simfphys_base 8d4b1ad and simfphys_armed 53f709f, read in their source). The
-- cases pin what the adapter says and what it calls; the check against the real addon comes at the merge. Each case names the change that makes it fail.

local API
local S
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local NULL_ENT = {IsValid = function() return false end}

local function seat()
	local pod = {}

	function pod:IsValid() return true end
	function pod:GetClass() return "prop_vehicle_prisoner_pod" end
	function pod:GetDriver() return NULL_ENT end

	return pod
end

local function car(fields)
	local c = {destroyed = false, RemoteDriver = nil}

	for k, v in pairs(fields or {}) do
		c[k] = v
	end

	function c:IsValid() return true end
	function c:GetClass() return "gmod_sent_vehicle_fphysics_base" end

	return c
end

-- a player; `base` is the car Player:GetSimfphys answers (NULL on foot), `seated` what InVehicle says
local function player(base, fields)
	local ply = {health = 100, group = COLLISION_GROUP_IN_VEHICLE, cloak = 0}

	for k, v in pairs(fields or {}) do
		ply[k] = v
	end

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:InVehicle() return base ~= nil end
	function ply:GetSimfphys() return base or NULL_ENT end
	function ply:Health() return self.health end
	function ply:GetCollisionGroup() return self.group end

	return ply
end

-- the damage: its amount and its type
local function damage(amount, dmgType)
	local info = {amount = amount, kind = dmgType}

	function info:GetDamage() return self.amount end
	function info:GetDamageType() return self.kind end
	function info:IsDamageType(t) return bit.band(self.kind, t) ~= 0 end

	return info
end

local FIX = "!!!_simfphys_fix_vehicle_explosion_damage"

local function withFixHook(present, fn)
	local events = hook.GetTable()
	local before = events.EntityTakeDamage and events.EntityTakeDamage[FIX]

	if present then
		hook.Add("EntityTakeDamage", FIX, function() end)
	else
		hook.Remove("EntityTakeDamage", FIX)
	end

	local ok, err = pcall(fn)

	hook.Remove("EntityTakeDamage", FIX)

	if before then
		hook.Add("EntityTakeDamage", FIX, before)
	end

	if not ok then
		error(err, 0)
	end
end

local attacks, noises

local function recordAttacks()
	attacks, noises = {}, {}
	stub(API, "ReportAttack", function(ply, right) attacks[#attacks + 1] = {ply, right} return true end)
	stub(GryMod, "EmitSuitNoise", function(ply, kind) noises[#noises + 1] = {ply, kind} return true end)
	stub(API, "CloakLevel", function(ply) return ply.cloak or 0 end)
end

local function shell(fields)
	local e = {Attacker = nil, AttackingEnt = nil}

	for k, v in pairs(fields or {}) do
		e[k] = v
	end

	function e:IsValid() return true end
	function e:GetClass() return "simfphys_tankprojectile" end

	return e
end

local function thrownMine(fields)
	local e = {Thrown = true, CreatedBy = nil}

	for k, v in pairs(fields or {}) do
		e[k] = v
	end

	function e:IsValid() return true end
	function e:GetClass() return "simfphys_antitankmine" end

	return e
end

return {
	groupName = "GryMod compat: simfphys (server)",
	beforeEach = function()
		API = GryMod.API
		S = GryMod.CompatSimfphys
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the adapter is not loaded, when it registers no hit filter, or when its filter is not under the id "simfphys"
			name = "the adapter registers its hit filter with the API",
			func = function()
				expect(S).notTo.beNil()
				expect(API.Has("hitfilter")).to.beTrue()
				expect(S.HitFilterId).to.equal("simfphys")
			end
		},
		{
			-- fails when the destroyed car's damage to its occupants (Health + Armor, DMG_DIRECT, set by ExplodeVehicle, which wants them dead) is not let through whole: the armor would
			-- absorb a lethal hit and the occupant would live in his exploding car
			name = "hit filter: the damage of a car that exploded to an occupant that it would kill is bypassed (the armor does not absorb it)",
			func = function()
				local wreck = car({destroyed = true})
				local ply = player(wreck)

				expect(S.HitVerdict(ply, damage(100, DMG_DIRECT))).to.equal("bypass")
				expect(S.HitVerdict(ply, damage(140, DMG_DIRECT))).to.equal("bypass")
			end
		},
		{
			-- fails when a hit that is not the explosion's is bypassed: a crash damage (2 or 5, DMG_DIRECT, the car has not exploded) and a small hit of a car that has exploded must keep
			-- going through the armor
			name = "hit filter: a crash, or a hit that would not kill, is left to the armor",
			func = function()
				local ply = player(car())

				expect(S.HitVerdict(ply, damage(5, DMG_DIRECT))).to.beNil()
				expect(S.HitVerdict(ply, damage(100, DMG_DIRECT))).to.beNil()

				local wreck = player(car({destroyed = true}))
				expect(S.HitVerdict(wreck, damage(30, DMG_DIRECT))).to.beNil()
			end
		},
		{
			-- fails when the damage that simfphys cancels itself ("!!!_simfphys_fix_vehicle_explosion_damage": a seated player takes no damage that is not DMG_DIRECT) is not ignored by the
			-- suit (the bar would pay a hit that never comes, in the order of the hooks where the suit runs first), or when it is ignored while that hook is not there
			name = "hit filter: a bullet or a blast on a seated player is ignored while simfphys cancels it, and only then",
			func = function()
				local ply = player(car())

				withFixHook(true, function()
					expect(S.HitVerdict(ply, damage(30, DMG_BULLET))).to.equal("ignore")
					expect(S.HitVerdict(ply, damage(60, DMG_BLAST))).to.equal("ignore")
				end)

				withFixHook(false, function()
					expect(S.HitVerdict(ply, damage(30, DMG_BULLET))).to.beNil()
				end)

				-- simfphys leaves the damage alone when the player's collision group is the player's (not seated for the engine)
				withFixHook(true, function()
					local standing = player(car(), {group = COLLISION_GROUP_PLAYER})
					expect(S.HitVerdict(standing, damage(30, DMG_BULLET))).to.beNil()
				end)
			end
		},
		{
			-- fails when a player on foot, or in a vehicle that is not simfphys', or a stand-in with no GetSimfphys, is given a verdict
			name = "hit filter: nothing for a player on foot, in another vehicle, or when simfphys is not there",
			func = function()
				withFixHook(true, function()
					expect(S.HitVerdict(player(nil), damage(30, DMG_BULLET))).to.beNil()

					local pod = player(nil)
					function pod:InVehicle() return true end
					expect(S.HitVerdict(pod, damage(30, DMG_BULLET))).to.beNil()

					local bare = {IsValid = function() return true end, InVehicle = function() return true end}
					expect(S.HitVerdict(bare, damage(30, DMG_BULLET))).to.beNil()

					-- a stand-in that cannot even say whether it sits (another addon's test double): no answer, no error (five errors in a row would switch the filter off)
					expect(S.HitVerdict({IsValid = function() return true end}, damage(30, DMG_BULLET))).to.beNil()
				end)
			end
		},
		{
			-- fails when a shell fired from a car by the player who sits in it does not end the camouflage (the shell hurts later, at its impact, and the cannon's bullets are not seen at the
			-- shot), when it makes no noise, or when the camouflage is reported twice
			name = "shell: the cannon's shot ends the camouflage of the player who sits in the car, and makes the noise of a shot",
			func = function()
				recordAttacks()

				local jeep = car()
				local ply = player(jeep, {cloak = 1})

				S.OnCreated(shell({Attacker = ply, AttackingEnt = jeep}))

				expect(#attacks).to.equal(1)
				expect(attacks[1][1]).to.equal(ply)
				expect(attacks[1][2]).to.equal(false)
				expect(#noises).to.equal(1)
				expect(noises[1][2]).to.equal("cloak_fire")
			end
		},
		{
			-- fails when a shell that the player did not fire from where he sits (a turret that he owns, a car he left, another car) ends his camouflage, or when a shell with no attacker raises
			name = "shell: no report for a turret's shell, a car the player is not in, or a shell with no attacker",
			func = function()
				recordAttacks()

				local jeep, other = car(), car()
				local ply = player(jeep, {cloak = 1})

				S.OnCreated(shell({Attacker = ply, AttackingEnt = other}))
				S.OnCreated(shell({Attacker = ply, AttackingEnt = {IsValid = function() return true end, GetClass = function() return "simfphys_turret" end}}))
				S.OnCreated(shell({Attacker = nil, AttackingEnt = jeep}))
				S.OnCreated(shell({Attacker = player(nil), AttackingEnt = jeep}))

				expect(#attacks).to.equal(0)
				expect(#noises).to.equal(0)
			end
		},
		{
			-- fails when the remote driver (weapon_simremote: he stays outside, the car answers to him) cannot end his camouflage by firing the car's cannon, or when the noise is made for a
			-- player who is not camouflaged (the bullets' own rule: only above a cloak level of 0)
			name = "shell: the remote driver's shot counts, and the noise is only for a camouflaged player",
			func = function()
				recordAttacks()

				local jeep = car()
				local remote = player(nil, {cloak = 0})
				jeep.RemoteDriver = remote

				S.OnCreated(shell({Attacker = remote, AttackingEnt = jeep}))

				expect(#attacks).to.equal(1)
				expect(#noises).to.equal(0)
			end
		},
		{
			-- fails when a mine thrown by a player (weapon_simmines) does not end his camouflage like a thrown grenade, or when a mine that was only put down (spawn menu: Thrown is not set)
			-- or whose thrower is not a player does
			name = "mine: a thrown mine ends the thrower's camouflage; a mine put down by a tool or with no player does not",
			func = function()
				recordAttacks()

				local ply = player(nil, {cloak = 1})

				S.OnCreated(thrownMine({CreatedBy = ply}))
				expect(#attacks).to.equal(1)
				expect(attacks[1][1]).to.equal(ply)
				expect(attacks[1][2]).to.equal(false)

				S.OnCreated(thrownMine({CreatedBy = ply, Thrown = false}))
				S.OnCreated(thrownMine({CreatedBy = nil}))
				S.OnCreated(thrownMine({CreatedBy = {IsValid = function() return true end, IsPlayer = function() return false end}}))
				expect(#attacks).to.equal(1)
			end
		},
		{
			-- fails when the hook that sees the entities made does something for any other class (it runs for every entity of the map) or raises an error for a stand-in with no class
			name = "OnCreated: only the shell and the mine, and an error never gets out",
			func = function()
				recordAttacks()

				S.OnCreated({IsValid = function() return true end, GetClass = function() return "prop_physics" end})
				S.OnCreated({IsValid = function() return false end})
				S.OnCreated(nil)
				S.OnCreated(5)

				expect(#attacks).to.equal(0)
			end
		},
		{
			-- fails when the adapter keeps a permanent Think hook (the owner's rule: no permanent Think; everything is an event)
			name = "no Think hook",
			func = function()
				local events = hook.GetTable()
				local think = events.Think or {}

				for id in pairs(think) do
					expect(string.find(tostring(id), "simfphys", 1, true)).to.beNil()
				end
			end
		}
	}
}
