-- Tests of the optional fields `dead`, `awareness`, `crew` and `facing` of the registry of tracked entities, and of the vehicle providers in the radar (GryMod.Radar Describe /
-- Step / Scan / Detect / Sits / DriverOf / IsObject, lua/grymod/server/sv_radar.lua, lua/grymod/sh_api_tracked.lua), GLuaTest format, server realm. Real entities (a
-- can on the floor) stand for the vehicles and the crew: the registry matches them by a function that knows the can. Each case names the change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

local R, S, API

local KEY = "t_fields"
local PROVIDER = "t_fields_provider"

local spawned = {}

local function can(offset)
	local e = ents.Create("prop_physics")

	e:SetModel("models/props_junk/PopCan01a.mdl")
	e:SetPos(ply():GetPos() + Vector(400 + (offset or 0), 0, 30))
	e:Spawn()
	spawned[#spawned + 1] = e

	return e
end

-- registers the entry for this one entity
local function track(target, fields)
	local def = {match = function(e) return e == target end, radar = "scan", type = "machine"}

	for k, v in pairs(fields or {}) do
		def[k] = v
	end

	local ok, why = API.RegisterTracked(KEY, def)

	assert(ok, tostring(why))
end

local function newState()
	return {tagged = setmetatable({}, {__mode = "k"}), markers = setmetatable({}, {__mode = "k"})}
end

local function desc(extra)
	local d = {key = {}, id = 900, class = "prop_physics", relation = "neutral", hostile = false, ally = false, state = NPC_STATE_NONE,
		enemyIsPlayer = false, health = 50, maxHealth = 50, x = 100, y = 0, z = 0, yaw = 0, radar = "always"}

	for k, v in pairs(extra or {}) do
		d[k] = v
	end

	return d
end

-- the relation of the entities that stand for the crew, by the provider chain
local relations = {}

return {
	groupName = "GryMod radar: tracked fields dead, awareness, crew, facing; vehicle providers (server)",
	beforeAll = function()
		R, S, API = GryMod.Radar, GryMod.RadarShared, GryMod.API
	end,
	beforeEach = function()
		relations = {}
		API.AddRelationProvider(PROVIDER, function(_, e) return relations[e] end, 1000)

		if not ply():Alive() then
			ply():Spawn()
		end
	end,
	afterEach = function()
		API.UnregisterTracked(KEY)
		API.RemoveRelationProvider(PROVIDER)
		API.RemoveVehicleProvider(PROVIDER)
		API.SafeCallReset("tracked:" .. KEY .. "/dead")
		API.SafeCallReset("tracked:" .. KEY .. "/awareness")
		API.SafeCallReset("tracked:" .. KEY .. "/crew")
		API.SafeCallReset("tracked:" .. KEY .. "/facing")

		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:Remove()
			end
		end

		spawned = {}

		if IsValid(ply()) then
			R.Reset(ply())
		end
	end,
	cases = {
		{
			-- fails when RegisterTracked refuses the four new fields, or accepts something else than a function for them
			name = "RegisterTracked accepts dead, awareness, crew and facing as functions and refuses anything else",
			func = function()
				local fn = function() end

				expect(API.RegisterTracked(KEY, {class = "t_x", dead = fn, awareness = fn, crew = fn, facing = fn})).to.beTrue()

				for _, field in ipairs({"dead", "awareness", "crew", "facing"}) do
					local ok, why = API.RegisterTracked(KEY, {class = "t_x", [field] = "nope"})

					expect(ok).to.beFalse()
					expect(string.find(why, field, 1, true) ~= nil).to.beTrue()
				end

				-- the entry keeps them
				API.RegisterTracked(KEY, {class = "t_x", dead = fn, awareness = fn, crew = fn, facing = fn})
				expect(API.GetTrackedByClass("t_x").dead).to.equal(fn)
				expect(API.GetTrackedByClass("t_x").facing).to.equal(fn)
			end
		},
		{
			-- fails when a destroyed entity (its `dead` says so) is still a contact, or when a live one is dropped, or when the tag of a dead one stays
			name = "dead: a description that is dead is not a contact and its tag is forgotten; Describe asks the entry's function",
			func = function()
				local st = newState()
				local alive, dead = desc({id = 901}), desc({id = 902, dead = true})

				st.tagged[dead.key] = true

				local list = R.Step(Vector(0, 0, 0), {alive, dead}, st, 0, false)

				expect(#list).to.equal(1)
				expect(list[1].id).to.equal(901)
				expect(st.tagged[dead.key]).to.beNil()

				local car = can()
				local wrecked = false

				track(car, {dead = function() return wrecked end})
				expect(R.Describe(car, ply()).dead).to.beFalse()
				wrecked = true
				expect(R.Describe(car, ply()).dead).to.beTrue()
			end
		},
		{
			-- fails when the binoculars can tag a destroyed vehicle, or the danger bar still counts a dead hostile
			name = "dead: the binoculars cannot tag it (Scan) and the danger bar does not count it (Detect)",
			func = function()
				local car = can()

				track(car, {dead = function() return true end})

				ply():SetPos(car:GetPos() - Vector(300, 0, 30))
				expect(R.Scan(ply(), car)).to.beFalse()

				local d = desc({hostile = true, relation = "hostile", dead = true, awareLevel = 2, exposure = 1, radar = nil})
				local puppet, vehicle, exposure = R.Detect({d}, {})

				expect(puppet).to.equal(0)
				expect(vehicle).to.equal(0)
				expect(exposure).to.equal(0)
			end
		},
		{
			-- fails when the awareness field is not read, when the entity's own GetGryAwareness no longer wins over it, or when its values are not clamped
			name = "awareness: Describe takes the entry's level, exposure, seen and heard, clamped; the entity's own method wins; an error leaves today's rule",
			func = function()
				local car = can()

				track(car, {awareness = function(e, p) return 7, 3, "x", nil end})

				local d = R.Describe(car, ply())

				expect(d.awareLevel).to.equal(2)
				expect(d.exposure).to.equal(1)
				expect(d.seen).to.beTrue()
				expect(d.heard).to.beFalse()

				-- the entity's own method wins over the registry's
				car.GetGryAwareness = function() return 1, 0.25, false, true end
				d = R.Describe(car, ply())
				expect(d.awareLevel).to.equal(1)
				expect(d.exposure).to.equal(0.25)
				expect(d.heard).to.beTrue()
				car.GetGryAwareness = nil

				-- an entry that raises an error: no awareness, and no error
				track(car, {awareness = function() error("awareness failure") end})
				expect(function() d = R.Describe(car, ply()) end).to.succeed()
				expect(d.awareLevel).to.beNil()
				expect(d.exposure).to.beNil()
			end
		},
		{
			-- fails when the awareness function is not given the entity and the player
			name = "awareness: the function is given the entity and the player",
			func = function()
				local car = can()
				local gotEnt, gotPly

				track(car, {awareness = function(e, p) gotEnt, gotPly = e, p return 0, 0, false, false end})
				R.Describe(car, ply())
				expect(gotEnt).to.equal(car)
				expect(gotPly).to.equal(ply())
			end
		},
		{
			-- fails when a vehicle with a hostile occupant is not hostile, an allied crew is not an ally, an empty one is not neutral, or when the entry's own `relation` is
			-- overridden by the crew
			name = "crew: hostile if an occupant is, else allied if one is, else neutral; the player himself does not count; a `relation` of the entry is not overridden",
			func = function()
				local car, foe, friend, other = can(), can(60), can(120), can(180)

				relations[foe], relations[friend], relations[other] = "hostile", "ally", "neutral"

				local crew = {}

				track(car, {crew = function() return crew end})

				crew = {}
				expect(R.Describe(car, ply()).relation).to.equal("neutral")

				crew = {other}
				expect(R.Describe(car, ply()).relation).to.equal("neutral")

				crew = {other, friend}
				expect(R.Describe(car, ply()).relation).to.equal("ally")

				crew = {friend, foe, other}
				expect(R.Describe(car, ply()).relation).to.equal("hostile")
				expect(R.Describe(car, ply()).hostile).to.beTrue()

				-- the player in his own crew is nobody's enemy
				crew = {ply()}
				expect(R.Describe(car, ply()).relation).to.equal("neutral")

				-- a crew function that fails: neutral
				track(car, {crew = function() error("crew failure") end})
				expect(R.Describe(car, ply()).relation).to.equal("neutral")

				-- the entry says what the vehicle is: the crew does not change it
				track(car, {relation = "ally", crew = function() return {foe} end})
				expect(R.Describe(car, ply()).relation).to.equal("ally")
			end
		},
		{
			-- fails when the vehicle's heading is not the one of the entry's `facing`, when a null or invalid vector is believed, or when the default rule is lost
			name = "facing: the yaw of Describe is the one of the entry's forward vector; nothing, an invalid vector and an error keep today's rule",
			func = function()
				local car = can()

				car:SetAngles(Angle(0, 30, 0))

				local default = R.Describe(car, ply()).yaw

				track(car, {facing = function() return Vector(0, 1, 0) end})
				expect(math.abs(math.AngleDifference(R.Describe(car, ply()).yaw, 90)) < 0.01).to.beTrue()

				track(car, {facing = function() return Vector(-1, 0, 0) end})
				expect(math.abs(math.AngleDifference(R.Describe(car, ply()).yaw, 180)) < 0.01).to.beTrue()

				for _, bad in ipairs({function() return Vector(0, 0, 0) end, function() return "north" end, function() return nil end, function() error("facing failure") end}) do
					track(car, {facing = bad})
					expect(R.Describe(car, ply()).yaw).to.equal(default)
				end
			end
		},
		{
			-- fails when the player is not taken as sitting in the vehicle a provider says (the radar would list the car he drives), or when the engine's own vehicle stops counting
			name = "Sits: the vehicle a provider says counts, whatever the engine says; a vehicle he is not in does not",
			func = function()
				local car, other = can(), can(60)

				expect(R.Sits(ply(), car)).to.beFalse()

				API.AddVehicleProvider(PROVIDER, {ofPlayer = function() return car end})
				expect(R.Sits(ply(), car)).to.beTrue()
				expect(R.Sits(ply(), other)).to.beFalse()
				expect(R.Sits(nil, car)).to.beFalse()
			end
		},
		{
			-- fails when a vehicle that the player sits in (through a provider) is listed as a contact, when one he does not sit in stops being one
			name = "IsObject: not the vehicle the player sits in (through a provider), but another one is",
			func = function()
				local car, other = can(), can(60)

				API.RegisterTracked(KEY, {match = function(e) return e == car or e == other end, radar = "scan", type = "machine"})
				expect(R.IsObject(car, ply())).to.beTrue()

				API.AddVehicleProvider(PROVIDER, {ofPlayer = function() return car end})
				expect(R.IsObject(car, ply())).to.beFalse()
				expect(R.IsObject(other, ply())).to.beTrue()
			end
		},
		{
			-- fails when the driver is not the one a provider says (a vehicle that is not an engine vehicle has no GetDriver), or when the engine's GetDriver stops being the fallback
			name = "DriverOf: the driver a provider says, nothing for a vehicle nobody drives",
			func = function()
				local car = can()
				local driver = can(60)

				expect(R.DriverOf(car)).to.beNil()

				API.AddVehicleProvider(PROVIDER, {ofPlayer = function() end, driver = function(v) if v == car then return driver end end})
				expect(R.DriverOf(car)).to.equal(driver)
				expect(R.DriverOf(driver)).to.beNil()
			end
		},
		{
			-- fails when the colour of a vehicle is not the one of the driver a provider names (the vehicle is not an engine vehicle: IsVehicle is false), or when a neutral driver
			-- changes it
			name = "Describe: a vehicle that is not an engine vehicle takes the colour of the driver a provider names",
			func = function()
				local car, foe, friend = can(), can(60), can(120)

				relations[foe], relations[friend] = "hostile", "ally"
				track(car, {})

				local driver

				API.AddVehicleProvider(PROVIDER, {ofPlayer = function() end, driver = function(v) if v == car then return driver end end})

				driver = nil
				expect(R.Describe(car, ply()).relation).to.equal("neutral")
				driver = foe
				expect(R.Describe(car, ply()).relation).to.equal("hostile")
				driver = friend
				expect(R.Describe(car, ply()).relation).to.equal("ally")
				driver = ply()
				expect(R.Describe(car, ply()).relation).to.equal("neutral")
			end
		}
	}
}
