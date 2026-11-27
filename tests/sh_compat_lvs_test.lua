-- Tests of the LVS patch (lua/grymod/compat/vehicles/sh_lvs.lua), GLuaTest format, runs in the server AND in the client realm. LVS is not installed in the test game: the stand-ins
-- are tables that answer like the entities LVS makes, with the methods and the fields read in its code (lvs_base: ENT.LVS, GetDriver, GetAITEAM, GetEveryone, GetVehicleType,
-- IsDestroyed, GetAI, _LastAITarget; lvs_missile: GetActive, GetNWTarget, GetAttacker; Player:lvsGetVehicle, lvsGetAITeam). The registry of the extension API is the real one.
-- Each case names the production change whose absence makes it fail.

local API
local L
local realLVS
local realIsBasedOn
local bases

-- a stand-in entity
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

-- an LVS vehicle of the given class, base and team (the fields of lvs_base)
local function vehicle(class, kind, team, fields)
	local v = ent(class, {
		LVS = true,
		_team = team or 0,
		_occupants = {},
		GetVehicleType = function() return kind end,
		GetAITEAM = function(self) return self._team end,
		GetEveryone = function(self) return self._occupants end,
		GetDriver = function(self) return self._driver or NULL end,
		GetAI = function(self) return self._ai == true end,
		GetForward = function() return Vector(1, 0, 0) end,
		GetHP = function(self) return self._hp or 100 end,
		GetlvsLockedStatus = function(self) return self._locked == true end
	})

	for key, value in pairs(fields or {}) do
		v[key] = value
	end

	return v
end

-- a player; `veh` is the vehicle he sits in (nil on foot), `team` his own AI team
local function player(veh, team)
	local p = ent("player", {
		lvsGetVehicle = function() return veh or NULL end,
		lvsGetAITeam = function() return team or 0 end
	})

	return p
end

local function missile(class, fields)
	local m = ent(class, {
		GetActive = function(self) return self._active == true end,
		GetVelocity = function(self) return self._velocity or Vector(0, 0, 0) end,
		GetPos = function(self) return self._pos or Vector(0, 0, 0) end
	})

	for key, value in pairs(fields or {}) do
		m[key] = value
	end

	return m
end

local function uninstall()
	L.Uninstall()
end

return {
	groupName = "GryMod compat: LVS (shared)",
	beforeEach = function()
		API = GryMod.API
		L = GryMod.CompatLVS
		realLVS = LVS
		realIsBasedOn = scripted_ents.IsBasedOn
		bases = {}
		scripted_ents.IsBasedOn = function(class, base)
			local step = 0

			while class and step < 10 do
				if class == base then
					return true
				end

				class, step = bases[class], step + 1
			end

			return false
		end

		uninstall()
		LVS = {}
	end,
	afterEach = function()
		uninstall()
		scripted_ents.IsBasedOn = realIsBasedOn
		LVS = realLVS

		if realLVS ~= nil then
			L.Install()
		end
	end,
	cases = {
		{
			-- fails when Install registers something without LVS (the patch must do nothing then), or when Present answers yes for no LVS table
			name = "without LVS nothing is registered: Present and Install say no, no entry, no provider, no prompt",
			func = function()
				LVS = nil

				expect(L.Present()).to.beFalse()
				expect(L.Install()).to.beFalse()

				local v = vehicle("lvs_wheeldrive_x", "car")
				bases["lvs_wheeldrive_x"] = "lvs_base"

				expect(API.GetTracked(v)).to.beNil()
				expect(API.GetUsable(v)).to.beNil()
				expect(API.GetWeapon("weapon_lvsrepair")).to.beNil()
				expect(API.GetVehicleOf(player(v))).to.beNil()
			end
		},
		{
			-- fails when the hooks that install the patch late (LVS loaded after GryMod: its hook, then InitPostEntity) are not there, or do not install
			name = "LVS announcing itself after GryMod installs the patch: the hooks \"LVS:Initialize\" and InitPostEntity",
			func = function()
				local hooks = hook.GetTable()

				expect(isfunction(hooks["LVS:Initialize"]["GryMod compat LVS"])).to.beTrue()
				expect(isfunction(hooks["InitPostEntity"]["GryMod compat LVS"])).to.beTrue()
				expect(API.GetUsable(vehicle("lvs_x", "car"))).to.beNil()

				bases["lvs_x"] = "lvs_base"
				hooks["LVS:Initialize"]["GryMod compat LVS"]()

				expect(API.GetUsable(vehicle("lvs_x", "car"))).notTo.beNil()
			end
		},
		{
			-- fails when the provider answers the seat, answers for a player on foot, or when GetVehicleDriver / GetVehicleKind do not use LVS's driver and vehicle type
			name = "the vehicle provider: the LVS vehicle of a seated player, its driver, air / water / ground from GetVehicleType",
			func = function()
				expect(L.Install()).to.beTrue()

				local driver = player()
				local car = vehicle("lvs_car", "car", 0, {_driver = driver})
				local plane = vehicle("lvs_plane", "plane", 0, {_driver = driver})
				local heli = vehicle("lvs_heli", "helicopter", 0, {_driver = driver})
				local fighter = vehicle("lvs_fighter", "starfighter", 0, {_driver = driver})
				local boat = vehicle("lvs_boat", "boat", 0, {_driver = driver})
				local tank = vehicle("lvs_tank", "tank", 0, {_driver = driver})

				expect(API.GetVehicleOf(player(car))).to.equal(car)
				expect(API.GetVehicleOf(player())).to.beNil()
				expect(API.GetVehicleDriver(car)).to.equal(driver)
				expect(API.GetVehicleKind(car)).to.equal("ground")
				expect(API.GetVehicleKind(tank)).to.equal("ground")
				expect(API.GetVehicleKind(plane)).to.equal("air")
				expect(API.GetVehicleKind(heli)).to.equal("air")
				expect(API.GetVehicleKind(fighter)).to.equal("air")
				expect(API.GetVehicleKind(boat)).to.equal("water")
			end
		},
		{
			-- fails when a player without the LVS methods, an engine vehicle with a GetDriver of its own, or a vehicle nobody drives is mistaken for an LVS answer
			name = "the provider answers nothing for what is not LVS: a player without lvsGetVehicle, an engine vehicle's driver, an empty vehicle",
			func = function()
				expect(L.Install()).to.beTrue()

				local engine = ent("prop_vehicle_jeep", {GetDriver = function() return player() end})
				local plain = ent("player")

				expect(L.DriverOf(engine)).to.beNil()
				expect(L.VehicleOf(plain)).to.beNil()
				expect(L.DriverOf(vehicle("lvs_car", "car"))).to.beNil()
				expect(L.VehicleOf(nil)).to.beNil()
			end
		},
		{
			-- fails when the flying bases are not before the generic one (a plane would be a machine), when the icon types are wrong, or when an entity that is not built on lvs_base is taken
			name = "the radar entries: planes, helicopters and starfighters are flying units, every other LVS vehicle a machine, a seat or a missile is neither",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_plane_x"], bases["lvs_base_fighterplane"] = "lvs_base_fighterplane", "lvs_base"
				bases["lvs_heli_x"], bases["lvs_base_helicopter"] = "lvs_base_helicopter", "lvs_base"
				bases["lvs_tank_x"], bases["lvs_tank_wheeldrive"], bases["lvs_base_wheeldrive"] = "lvs_tank_wheeldrive", "lvs_base_wheeldrive", "lvs_base"

				local plane = API.GetTracked(vehicle("lvs_plane_x", "plane"))
				local heli = API.GetTracked(vehicle("lvs_heli_x", "helicopter"))
				local tank = API.GetTracked(vehicle("lvs_tank_x", "tank"))

				expect(plane).notTo.beNil()
				expect(plane.type).to.equal(2)
				expect(heli.type).to.equal(2)
				expect(tank.type).to.equal(3)
				expect(plane.radar).to.equal("hostile")
				expect(API.GetTracked(ent("prop_vehicle_prisoner_pod"))).to.beNil()
				expect(API.GetTracked(ent("lvs_missile"))).to.beNil()
			end
		},
		{
			-- fails when a team 0 or 3 is mishandled (0: no opinion and the occupants decide; 3: hostile to everyone), when the player's own team is not the one of his vehicle,
			-- or when the same team is not an ally
			name = "the relation by LVS team: same team ally, other team hostile, team 3 hostile, team 0 no opinion; a seated player has the team of his vehicle",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_a"] = "lvs_base"

				local entry = API.GetTracked(vehicle("lvs_a", "car", 1))
				local ownTeam2 = vehicle("lvs_mine", "car", 2)

				expect(entry.relation(player(nil, 1), vehicle("lvs_a", "car", 1))).to.equal("ally")
				expect(entry.relation(player(nil, 1), vehicle("lvs_a", "car", 2))).to.equal("hostile")
				expect(entry.relation(player(nil, 2), vehicle("lvs_a", "car", 3))).to.equal("hostile")
				expect(entry.relation(player(nil, 3), vehicle("lvs_a", "car", 1))).to.equal("hostile")
				expect(entry.relation(player(nil, 0), vehicle("lvs_a", "car", 1))).to.beNil()
				expect(entry.relation(player(nil, 1), vehicle("lvs_a", "car", 0))).to.beNil()
				expect(entry.relation(player(ownTeam2, 1), vehicle("lvs_a", "car", 2))).to.equal("ally")
				expect(entry.relation(player(ownTeam2, 1), vehicle("lvs_a", "car", 1))).to.equal("hostile")
			end
		},
		{
			-- fails when a wreck is not dead (it would stay on the radar), when a living vehicle is dead, when the client (no IsDestroyed) raises an error, or when crew and facing do not
			-- read LVS's occupants and forward vector
			name = "dead, crew and facing: IsDestroyed, GetEveryone and GetForward; a vehicle without IsDestroyed (the client) is not dead",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_a"] = "lvs_base"

				local a, b = player(), player()
				local wreck = vehicle("lvs_a", "car", 0, {IsDestroyed = function() return true end, _occupants = {a, b}})
				local alive = vehicle("lvs_a", "car", 0, {IsDestroyed = function() return false end})
				local entry = API.GetTracked(wreck)

				expect(entry.dead(wreck)).to.beTrue()
				expect(entry.dead(alive)).to.beFalse()
				expect(entry.dead(vehicle("lvs_a", "car"))).to.beFalse()
				expect(#entry.crew(wreck)).to.equal(2)
				expect(entry.crew(wreck)[1]).to.equal(a)
				expect(entry.facing(alive).x).to.equal(1)
			end
		},
		{
			-- fails when an AI vehicle that targets the player (or the vehicle he sits in) is calm, when one that targets somebody else, has no target, is not an AI or whose target is
			-- gone says anything, or when the exposure and the seen flag are not those of a vehicle that is shooting at him
			name = "awareness: an AI vehicle whose target is the player or his vehicle is fighting him (2, 1, seen); every other case is calm",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_a"] = "lvs_base"

				local mine = vehicle("lvs_mine", "car")
				local me = player(mine)
				local onFoot = player()
				local other = player()
				local entry = API.GetTracked(vehicle("lvs_a", "car"))

				local function ai(target, isAi)
					return vehicle("lvs_a", "plane", 1, {_ai = isAi ~= false, _LastAITarget = target})
				end

				local level, exposure, seen, heard = entry.awareness(ai(me), me)

				expect(level).to.equal(2)
				expect(exposure).to.equal(1)
				expect(seen).to.beTrue()
				expect(heard).to.beFalse()
				expect((entry.awareness(ai(mine), me))).to.equal(2)
				expect((entry.awareness(ai(onFoot), onFoot))).to.equal(2)
				expect((entry.awareness(ai(other), me))).to.equal(0)
				expect((entry.awareness(ai(nil), me))).to.equal(0)
				expect((entry.awareness(ai(NULL), me))).to.equal(0)
				expect((entry.awareness(ai(me, false), me))).to.equal(0)
			end
		},
		{
			-- fails when a missile or a bomb class is not a danger, when a pack's class built on lvs_missile / lvs_bomb is missed, when the labels are wrong, or when an entity of another
			-- class is taken
			name = "the grenade warning covers the five projectile classes and any class built on lvs_missile or lvs_bomb: MISSILE and BOMB",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["t_pack_missile"], bases["t_pack_bomb"] = "lvs_missile", "lvs_bomb"

				for _, class in ipairs({"lvs_missile", "lvs_protontorpedo", "lvs_concussionmissile", "t_pack_missile"}) do
					expect(API.GetDanger(ent(class)).danger.label).to.equal("MISSILE")
				end

				for _, class in ipairs({"lvs_bomb", "lvs_helicopter_combine_bomb", "t_pack_bomb"}) do
					expect(API.GetDanger(ent(class)).danger.label).to.equal("BOMB")
				end

				expect(API.GetDanger(ent("lvs_item_mine"))).to.beNil()
				expect(API.GetDanger(ent("npc_grenade_frag"))).to.beNil()
			end
		},
		{
			-- fails when a projectile hanging under its vehicle (not launched) is armed, when a flying one is not, or when ownerOf answers a vehicle (an AI's missile) as a player
			name = "danger.armed is GetActive; danger.ownerOf is the player attacker of the projectile, nothing for an AI vehicle or nobody",
			func = function()
				expect(L.Install()).to.beTrue()

				local entry = API.GetDanger(ent("lvs_missile"))
				local shooter = ent("player", {IsPlayer = function() return true end})
				local aiVehicle = vehicle("lvs_a", "plane", 1, {IsPlayer = function() return false end})

				expect(entry.danger.armed(missile("lvs_missile", {_active = true}))).to.beTrue()
				expect(entry.danger.armed(missile("lvs_missile", {_active = false}))).to.beFalse()
				expect(entry.danger.ownMissile).to.beTrue()
				expect(entry.danger.ownerOf(missile("lvs_missile", {GetAttacker = function() return shooter end}))).to.equal(shooter)
				expect(entry.danger.ownerOf(missile("lvs_missile", {GetAttacker = function() return aiVehicle end}))).to.beNil()
				expect(entry.danger.ownerOf(missile("lvs_missile", {GetAttacker = function() return NULL end}))).to.beNil()
				expect(entry.danger.ownerOf(missile("lvs_missile"))).to.beNil()
			end
		},
		{
			-- fails when a missile locked on another vehicle warns this player, when one locked on the player or on his vehicle does not, or when the lock is ignored for the heading
			name = "danger.warnFor with a lock: only the player who is the target, or sits in the target, is warned",
			func = function()
				expect(L.Install()).to.beTrue()

				local entry = API.GetDanger(ent("lvs_missile"))
				local mine = vehicle("lvs_mine", "plane")
				local theirs = vehicle("lvs_theirs", "plane")
				local me = player(mine)
				local onFoot = player()

				-- the missile flies AT the player in every case: the lock decides
				local function locked(target)
					return missile("lvs_missile", {
						GetNWTarget = function() return target end,
						_velocity = Vector(100, 0, 0), _pos = Vector(-1000, 0, 0)
					})
				end

				expect(entry.danger.warnFor(locked(mine), me)).to.beTrue()
				expect(entry.danger.warnFor(locked(me), me)).to.beTrue()
				expect(entry.danger.warnFor(locked(onFoot), onFoot)).to.beTrue()
				expect(entry.danger.warnFor(locked(theirs), me)).to.beFalse()
				expect(entry.danger.warnFor(locked(onFoot), me)).to.beFalse()
			end
		},
		{
			-- fails when a projectile with no target warns a player it flies away from, a standing one warns, or one that flies at the player (or his vehicle) does not
			name = "danger.warnFor without a lock (a bomb, an unguided missile): the player it flies at, not the one it flies away from, not while it stands",
			func = function()
				expect(L.Install()).to.beTrue()

				local entry = API.GetDanger(ent("lvs_bomb"))
				local mine = vehicle("lvs_mine", "plane", 0, {WorldSpaceCenter = function() return Vector(0, 0, 0) end})
				local me = player(mine)
				local onFoot = ent("player", {
					lvsGetVehicle = function() return NULL end,
					GetPos = function() return Vector(0, 0, 0) end
				})

				local function bomb(pos, velocity)
					return missile("lvs_bomb", {_pos = pos, _velocity = velocity})
				end

				expect(entry.danger.warnFor(bomb(Vector(0, 0, 1000), Vector(0, 0, -900)), me)).to.beTrue()
				expect(entry.danger.warnFor(bomb(Vector(0, 0, 1000), Vector(0, 0, -900)), onFoot)).to.beTrue()
				expect(entry.danger.warnFor(bomb(Vector(0, 0, 1000), Vector(0, 0, 900)), me)).to.beFalse()
				expect(entry.danger.warnFor(bomb(Vector(0, 0, 1000), Vector(900, 0, 0)), me)).to.beFalse()
				expect(entry.danger.warnFor(bomb(Vector(0, 0, 1000), Vector(0, 0, 0)), me)).to.beFalse()
			end
		},
		{
			-- fails when a vehicle has no prompt, when the prompt is the wrong icon, when a seat or a prop gets one, or when the tools of LVS keep the gun icon
			name = "the use prompt of an LVS vehicle (enter, repeated: the doors of a car need two presses); LVS's tools have no gun icon",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_a"] = "lvs_base"

				local entry = API.GetUsable(vehicle("lvs_a", "car"))

				expect(entry).notTo.beNil()
				expect(entry.icon).to.equal("enter")
				expect(entry.use).to.equal("repeat")
				expect(API.GetUsable(ent("prop_physics"))).to.beNil()

				for _, class in ipairs({"weapon_lvsrepair", "weapon_lvsfuelfiller", "weapon_lvsmines", "weapon_lvsspikestrip"}) do
					expect(API.GetWeapon(class).fire).to.equal("none")
				end
			end
		},
		{
			-- fails when Uninstall leaves an entry, the provider, the prompt or a tool behind
			name = "Uninstall takes every registration away",
			func = function()
				expect(L.Install()).to.beTrue()

				bases["lvs_a"], bases["lvs_missile_x"] = "lvs_base", "lvs_missile"

				L.Uninstall()

				expect(API.GetTracked(vehicle("lvs_a", "car"))).to.beNil()
				expect(API.GetDanger(ent("lvs_missile"))).to.beNil()
				expect(API.GetUsable(vehicle("lvs_a", "car"))).to.beNil()
				expect(API.GetWeapon("weapon_lvsrepair")).to.beNil()
				expect(API.GetVehicleOf(player(vehicle("lvs_a", "car")))).to.beNil()
			end
		}
	}
}
