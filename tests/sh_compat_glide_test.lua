-- Tests of the Glide adapter, the shared part (compat/vehicles/sh_glide.lua): the vehicle provider, the registry of tracked entities (the radar's vehicles, the heavy
-- ones, the missiles of the grenade warning) and the use prompt. GLuaTest format, runs in the server AND in the client realm.
--
-- Glide is NOT installed in the test game: every Glide entity here is a STAND-IN, a table that answers the way the code of Glide (lua/entities/base_glide/*,
-- glide_missile/*, lua/glide/sh_player.lua) answers, and the class chain is given to the registries through a replaced scripted_ents.IsBasedOn (put back after each case).
-- Each case names the production change whose absence makes it fail.

local API

-- class -> base, the chain of the classes of Glide (lua/entities/*/shared.lua) and of two addons built on it
local CHAIN = {
	base_glide = "base_anim",
	base_glide_car = "base_glide",
	base_glide_motorcycle = "base_glide_car",
	base_glide_aircraft = "base_glide",
	base_glide_heli = "base_glide_aircraft",
	base_glide_plane = "base_glide_aircraft",
	base_glide_boat = "base_glide",
	base_glide_tank = "base_glide",
	base_glide_trailer = "base_glide",
	t_glide_sedan = "base_glide_car",
	t_glide_bike = "base_glide_motorcycle",
	t_glide_heli = "base_glide_heli",
	t_glide_plane = "base_glide_plane",
	t_glide_boat = "base_glide_boat",
	t_glide_tank = "base_glide_tank",
	t_glide_trailer = "base_glide_trailer",
	glide_missile = "base_anim",
	t_glide_firework = "glide_missile",
	t_other_missile = "base_anim"
}

local realIsBasedOn

-- A Glide vehicle: IsVehicle() is false (a scripted entity), IsGlideVehicle and VehicleType say what it is (autorun/sh_glide.lua: CAR 1, MOTORCYCLE 2, HELICOPTER 3, PLANE 4, TANK 5, BOAT 6).
local function vehicle(class, vehicleType, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end,
		IsVehicle = function() return false end,
		IsGlideVehicle = true,
		VehicleType = vehicleType,
		health = 1000,
		locked = false,
		driver = nil,
		passengers = {}
	}

	function e:GetDriver() return self.driver end
	function e:GetAllPlayers() return self.passengers end
	function e:GetChassisHealth() return self.health end
	function e:GetIsLocked() return self.locked end
	function e:GetForward() return Vector(1, 0, 0) end

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function player(name, vehicleOf)
	local p = {
		IsValid = function() return true end,
		GetClass = function() return "player" end,
		IsPlayer = function() return true end,
		name = name
	}

	if vehicleOf ~= nil then
		function p:GlideGetVehicle() return vehicleOf or nil end
	end

	return p
end

local function missile(class, attacker)
	return {
		IsValid = function() return true end,
		GetClass = function() return class end,
		attacker = attacker,
		GetVelocity = function() return Vector(600, 0, 0) end
	}
end

-- The registries keep their answers by class: forget them after a stand-in chain went in or out.
local function flush()
	API.RegisterTracked("t_glide_flush", {class = "t_glide_flush_class"})
	API.UnregisterTracked("t_glide_flush")
	API.RegisterUsable("t_glide_flush", {class = "t_glide_flush_class", icon = "use", text = "X"})
	API.UnregisterUsable("t_glide_flush")
end

return {
	groupName = "GryMod Glide adapter: the vehicles, the registry and the use prompt (shared)",
	beforeEach = function()
		API = GryMod.API
		realIsBasedOn = scripted_ents.IsBasedOn

		scripted_ents.IsBasedOn = function(class, base)
			local at = class
			local guard = 0

			while at and guard < 20 do
				if at == base then
					return true
				end

				at = CHAIN[at]
				guard = guard + 1
			end

			local ok, answer = pcall(realIsBasedOn, class, base)

			return ok and answer or false
		end

		flush()
	end,
	afterEach = function()
		scripted_ents.IsBasedOn = realIsBasedOn
		flush()
	end,
	cases = {
		{
			-- fails when the adapter file is not loaded, or when it registers no provider named glide
			name = "the provider finds the vehicle of a player in Glide (not the seat), and nothing for a player Glide does not know",
			func = function()
				local car = vehicle("t_glide_sedan", 1)
				local inside = player("driver", car)
				local walking = player("walker", false)
				local noGlide = player("no glide function")

				expect(API.GetVehicleOf(inside)).to.equal(car)
				expect(API.GetVehicleOf(walking)).to.beNil()
				expect(API.GetVehicleOf(noGlide)).to.beNil()
			end
		},
		{
			-- fails when the driver is not read from ent:GetDriver() (the NetworkVar of the first seat), or when a thing that is not a Glide vehicle is answered
			name = "the provider gives the driver of a Glide vehicle, and nobody for an empty one",
			func = function()
				local driver = player("pilot")
				local car = vehicle("t_glide_sedan", 1, {driver = driver})
				local empty = vehicle("t_glide_sedan", 1)

				expect(API.GetVehicleDriver(car)).to.equal(driver)
				expect(API.GetVehicleDriver(empty)).to.beNil()
			end
		},
		{
			-- fails when the kind is not read from VehicleType: 3 helicopter and 4 plane are air, 6 boat is water, the rest ground
			name = "the kind of a Glide vehicle follows its VehicleType: helicopters and planes are air, boats are water, the rest is ground",
			func = function()
				local function kind(class, vehicleType)
					local driver = player("pilot")
					local v = vehicle(class, vehicleType, {driver = driver})

					-- asked through the provider that found it, as the radar does
					API.GetVehicleOf(player("p", v))

					return API.GetVehicleKind(v)
				end

				expect(kind("t_glide_sedan", 1)).to.equal("ground")
				expect(kind("t_glide_bike", 2)).to.equal("ground")
				expect(kind("t_glide_heli", 3)).to.equal("air")
				expect(kind("t_glide_plane", 4)).to.equal("air")
				expect(kind("t_glide_tank", 5)).to.equal("ground")
				expect(kind("t_glide_boat", 6)).to.equal("water")
			end
		},
		{
			-- fails when the entry for the vehicles is missing, is not a rectangle contact scanned by the binoculars, or when a car, an aircraft, a boat or a motorcycle is a heavy machine for the
			-- suit (only the tanks are: a hit of a car that breaks the armor does not put the suit down, as simfphys' armored cars and its cars do not), or when a tank is not
			name = "a car is a radar contact once scanned (the machine icon) and not a heavy machine; only a tank is heavy for the suit",
			func = function()
				local car = API.GetTracked(vehicle("t_glide_sedan", 1))
				local bike = API.GetTracked(vehicle("t_glide_bike", 2))
				local tank = API.GetTracked(vehicle("t_glide_tank", 5))

				expect(car).to.exist()
				expect(car.radar).to.equal("scan")
				expect(car.type).to.equal(3)
				expect(car.heavy).to.beNil()
				expect(bike).to.exist()
				expect(bike.radar).to.equal("scan")
				expect(bike.heavy).to.beNil()
				expect(tank).to.exist()
				expect(tank.radar).to.equal("scan")
				expect(tank.type).to.equal(3)
				expect(tank.heavy).to.beTrue()

				for _, aircraft in ipairs({API.GetTracked(vehicle("t_glide_heli", 3)), API.GetTracked(vehicle("t_glide_plane", 4)), API.GetTracked(vehicle("t_glide_boat", 6))}) do
					expect(aircraft.heavy).to.beNil()
				end
			end
		},
		{
			-- fails when an aircraft keeps the rectangle of a car instead of the flying unit's icon
			name = "helicopters and planes are the flying unit icon",
			func = function()
				expect(API.GetTracked(vehicle("t_glide_heli", 3)).type).to.equal(2)
				expect(API.GetTracked(vehicle("t_glide_plane", 4)).type).to.equal(2)
				expect(API.GetTracked(vehicle("t_glide_boat", 6)).type).to.equal(3)
			end
		},
		{
			-- fails when a trailer (no seat, nobody in it) is listed on the radar
			name = "a trailer is never a radar contact, and not a heavy machine either",
			func = function()
				local trailer = API.GetTracked(vehicle("t_glide_trailer", 0))

				expect(trailer).to.exist()
				expect(trailer.radar).to.equal("never")
				expect(trailer.heavy).to.beNil()
			end
		},
		{
			-- fails when a thing that is not a Glide vehicle is taken by the adapter (a base class name that matches too much), or the prop of the engine vehicle changes
			name = "nothing else is touched: an entity that is not built on a Glide class has no entry, and the stock vehicles keep theirs",
			func = function()
				local plain = {IsValid = function() return true end, GetClass = function() return "prop_physics" end}
				local jeep = {IsValid = function() return true end, GetClass = function() return "prop_vehicle_jeep" end}

				expect(API.GetTracked(plain)).to.beNil()
				expect(API.GetTracked(jeep).key).to.equal("hl2_vehicles")
			end
		},
		{
			-- fails when the wreck is still a contact: dead must say true for a vehicle with no chassis health left
			name = "a vehicle with no chassis health left is dead for the radar, one that stands is not",
			func = function()
				local entry = API.GetTracked(vehicle("t_glide_sedan", 1))
				local wreck = vehicle("t_glide_sedan", 1, {health = 0})
				local exploded = vehicle("t_glide_sedan", 1, {hasExploded = true})

				expect(entry.dead(vehicle("t_glide_sedan", 1))).to.beFalse()
				expect(entry.dead(wreck)).to.beTrue()
				expect(entry.dead(exploded)).to.beTrue()
			end
		},
		{
			-- fails when the facing is not the forward of the vehicle (an engine vehicle gets +90 degrees from its yaw, a Glide vehicle faces +X)
			name = "the icon of a Glide vehicle faces its forward vector, and the crew is the players in all its seats",
			func = function()
				local a, b = player("a"), player("b")
				local entry = API.GetTracked(vehicle("t_glide_sedan", 1))
				local v = vehicle("t_glide_sedan", 1, {passengers = {a, b}})
				local forward = entry.facing(v)

				expect(forward.x).to.equal(1)
				expect(forward.y).to.equal(0)
				expect(entry.crew(v)[2]).to.equal(b)
				expect(entry.crew(vehicle("t_glide_sedan", 1, {passengers = false}))).to.beNil()
			end
		},
		{
			-- fails when the missile is not a danger by its BASE (a missile of another addon built on glide_missile is not warned about), or the warning has no label
			name = "a Glide missile and one built on it are dangers of the grenade warning, a missile of another base is not",
			func = function()
				local own = API.GetDanger(missile("glide_missile"))
				local sub = API.GetDanger(missile("t_glide_firework"))
				local other = API.GetDanger(missile("t_other_missile"))

				expect(own).to.exist()
				expect(own.danger.label).to.equal("MISSILE")
				expect(own.danger.ownMissile).to.beTrue()
				expect(sub).to.exist()
				expect(other).to.beNil()
			end
		},
		{
			-- fails when the owner is not read from the field attacker of the missile (the engine owner of a Glide missile is the VEHICLE, never the player)
			name = "the owner of a Glide missile is the player in its field attacker",
			func = function()
				local shooter = player("shooter")
				local entry = API.GetDanger(missile("glide_missile"))

				expect(entry.danger.ownerOf(missile("glide_missile", shooter))).to.equal(shooter)
				expect(entry.danger.ownerOf(missile("glide_missile"))).to.beNil()
			end
		},
		{
			-- fails when the missile is a danger for everybody: it must be armed as soon as it flies, and say so
			name = "a missile that flies is armed, and the armed reader leaves the target on the entity for the clients",
			func = function()
				local entry = API.GetDanger(missile("glide_missile"))
				local target = vehicle("t_glide_sedan", 1)
				local m = missile("glide_missile")
				local published

				m.target = target
				m.SetNW2Entity = function(_, name, value) published = {name, value} end

				expect(entry.danger.armed(m)).to.beTrue()
				expect(published[1]).to.equal("GryGlideTarget")
				expect(published[2]).to.equal(target)
			end
		},
		{
			-- fails when the entry for the vehicles is missing from the use registry, or says something else than the prompt of the stock vehicles
			name = "a Glide vehicle has the ENTER VEHICLE prompt, once; a trailer has none",
			func = function()
				local entry = API.GetUsable(vehicle("t_glide_sedan", 1))

				expect(entry).to.exist()
				expect(entry.icon).to.equal("enter")
				expect(entry.use).to.equal("once")
				expect(API.UsableText(vehicle("t_glide_sedan", 1), nil, entry)).to.equal("ENTER VEHICLE")
				expect(API.GetUsable(vehicle("t_glide_trailer", 0))).to.beNil()
				expect(API.GetUsable(vehicle("t_glide_heli", 3))).to.exist()
			end
		},
		{
			-- fails when a locked vehicle is offered as usable (ready must say no while GetIsLocked is true)
			name = "the prompt is dimmed while the vehicle is locked",
			func = function()
				local locked = vehicle("t_glide_sedan", 1, {locked = true})
				local open = vehicle("t_glide_sedan", 1)
				local entry = API.GetUsable(open)

				expect(API.UsableReady(open, entry)).to.beTrue()
				expect(API.UsableReady(locked, entry)).to.beFalse()
			end
		},
		{
			-- fails when the adapter breaks on an entity that has none of the functions of Glide (a class that only looks like one)
			name = "the readers do not raise on a thing that only has the name: a missing method answers no, not an error",
			func = function()
				local odd = {IsValid = function() return true end, GetClass = function() return "t_glide_sedan" end}
				local entry = API.GetTracked(odd)

				expect(entry).to.exist()
				expect(entry.dead(odd)).to.beFalse()
				expect(entry.crew(odd)).to.beNil()
				expect(entry.facing(odd)).to.beNil()
				expect(API.GetVehicleDriver(odd)).to.beNil()
			end
		}
	}
}
