-- Tests of the simfphys adapter (lua/grymod/compat/vehicles/sh_simfphys.lua), GLuaTest format, runs in the server AND in the client realm. simfphys is NOT installed on the
-- machines where these cases were written: every entity below is a stand-in that answers what simfphys' own code answers (simfphys_base 8d4b1ad, 2026-05-05, read in its source:
-- the car is `gmod_sent_vehicle_fphysics_base`, its seats are `prop_vehicle_prisoner_pod` children, `Player:GetSimfphys()` gives the car or NULL, `car:GetDriver()` is the
-- RemoteDriver when there is one, `car.destroyed` is set by ExplodeVehicle). The cases pin what the adapter answers and what it registers; the check against the real addon comes at
-- the merge. Each case names the change that makes it fail.

local API
local S
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local NULL_ENT = {IsValid = function() return false end}

-- a seat of the car: a prop_vehicle_prisoner_pod child that answers who sits in it
local function seat(driver)
	local pod = {}

	function pod:IsValid() return true end
	function pod:GetClass() return "prop_vehicle_prisoner_pod" end
	function pod:GetDriver() return driver or NULL_ENT end

	return pod
end

-- a simfphys car: its spawn name, the seats, the remote driver (weapon_simremote), the health and the lock
local function car(fields)
	local c = {spawn = "sim_fphys_jeep", health = 1000, locked = false, passengers = {}}

	for k, v in pairs(fields or {}) do
		c[k] = v
	end

	function c:IsValid() return true end
	function c:GetClass() return "gmod_sent_vehicle_fphysics_base" end
	function c:IsVehicle() return true end
	function c:GetSpawn_List() return self.spawn end
	function c:GetDriverSeat() return self.driverSeat or NULL_ENT end
	function c:GetPassengerSeats() return self.passengers end
	function c:GetDriver() return self.remote or (IsValid(self.driverSeat) and self.driverSeat:GetDriver()) or NULL_ENT end
	function c:GetCurHealth() return self.health end
	function c:GetIsVehicleLocked() return self.locked end

	return c
end

-- a player: sitting in `pod` of `base` (what Player:GetSimfphys answers), or standing
local function player(base, pod)
	local ply = {}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:InVehicle() return pod ~= nil end
	function ply:GetVehicle() return pod or NULL_ENT end
	function ply:GetSimfphys() return base or NULL_ENT end

	return ply
end

local function mine(fields)
	local m = {}

	function m:IsValid() return true end
	function m:GetClass() return "simfphys_antitankmine" end

	for k, v in pairs(fields or {}) do
		m[k] = v
	end

	return m
end

local function listEntry(name, mass)
	saved[#saved + 1] = {list.Get("simfphys_vehicles"), name, list.Get("simfphys_vehicles")[name]}
	list.Get("simfphys_vehicles")[name] = {Members = {Mass = mass}}
end

return {
	groupName = "GryMod compat: simfphys (shared)",
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
			-- fails when the adapter is not loaded (no GryMod.CompatSimfphys), when the provider answers the SEAT (the engine's own Player:GetVehicle answer: the radar would not know the
			-- car the player sits in), when a passenger is not given his car, or when a player on foot or in another base's vehicle is given a simfphys car
			name = "vehicle provider: the player in a simfphys seat (driver or passenger) is in the CAR, not in the seat; on foot or in another vehicle: no car",
			func = function()
				expect(S).notTo.beNil()

				local driverSeat, passengerSeat = seat(), seat()
				local jeep = car({driverSeat = driverSeat, passengers = {passengerSeat}})
				local driver, passenger = player(jeep, driverSeat), player(jeep, passengerSeat)

				expect(API.GetVehicleOf(driver)).to.equal(jeep)
				expect(API.GetVehicleOf(passenger)).to.equal(jeep)

				-- on foot: nothing; in a seat of another base (the engine's pod, no simfphys car): the engine's answer, the pod itself
				expect(API.GetVehicleOf(player(nil, nil))).to.beNil()
				local other = seat()
				expect(API.GetVehicleOf(player(nil, other))).to.equal(other)

				-- a player stand-in that has no GetSimfphys at all (simfphys is not installed): the engine's answer, no error
				local bare = {IsValid = function() return true end, GetVehicle = function() return other end}
				expect(API.GetVehicleOf(bare)).to.equal(other)
			end
		},
		{
			-- fails when the driver is read from car:GetDriver (it answers the RemoteDriver, a player who stands outside with weapon_simremote), when the passengers are taken for the driver,
			-- or when the driver seat is not read
			name = "vehicle driver: the player sitting in the driver seat, never a passenger and never the remote driver",
			func = function()
				local ply, passenger, remote = player(), player(), player()
				local driverSeat = seat(ply)
				local jeep = car({driverSeat = driverSeat, passengers = {seat(passenger)}})

				expect(S.Driver(jeep)).to.equal(ply)

				-- nobody at the wheel, a passenger behind, a remote driver outside: no driver
				local empty = car({driverSeat = seat(), passengers = {seat(passenger)}, remote = remote})
				expect(S.Driver(empty)).to.beNil()
				expect(S.Driver(nil)).to.beNil()
				expect(S.Driver({IsValid = function() return true end})).to.beNil()
			end
		},
		{
			-- fails when the car is not a radar contact once scanned (the registry gives it no radar rule), when the entry is not a vehicle icon, when the tank is not heavy, when a light car is,
			-- or when a car whose spawn name is not known yet (the networked string has not arrived) is taken for a tank
			name = "tracked: every simfphys car is a vehicle contact once scanned; the heavy ones (mass 8000 and up, the tanks) put the suit down; the others do not",
			func = function()
				listEntry("sim_fphys_jeep", 1700)
				listEntry("sim_fphys_tank", 10000)
				listEntry("sim_fphys_tank2", 8000)

				local jeep, tank, edge = car({spawn = "sim_fphys_jeep"}), car({spawn = "sim_fphys_tank"}), car({spawn = "sim_fphys_tank2"})
				local unknown, noSpawn = car({spawn = "sim_fphys_never_listed"}), car({spawn = ""})

				for _, vehicle in ipairs({jeep, tank, edge, unknown, noSpawn}) do
					local entry = API.GetTracked(vehicle)

					expect(entry).notTo.beNil()
					expect(entry.radar).to.equal("scan")
					expect(entry.type).to.equal(3)
				end

				expect(API.GetTracked(tank).heavy).to.equal(true)
				expect(API.GetTracked(edge).heavy).to.equal(true)
				expect(API.GetTracked(jeep).heavy).to.beNil()
				expect(API.GetTracked(unknown).heavy).to.beNil()
				expect(API.GetTracked(noSpawn).heavy).to.beNil()
			end
		},
		{
			-- fails when the adapter takes over a stock vehicle (its entries beat the stock ones at priority 0): the Buggy must keep its own entry
			name = "tracked: the Half-Life 2 vehicles keep their stock entry",
			func = function()
				local buggy = {IsValid = function() return true end, GetClass = function() return "prop_vehicle_jeep" end}
				local entry = API.GetTracked(buggy)

				expect(entry).notTo.beNil()
				expect(entry.key).to.equal("hl2_vehicles")
			end
		},
		{
			-- fails when the crew lists the remote driver, forgets a passenger or the driver, lists an empty seat, or raises an error for a car with no seat table
			name = "tracked crew: the driver and the passengers who sit in the car, not the remote driver, no empty seat",
			func = function()
				local a, b, c, remote = player(), player(), player(), player()
				local jeep = car({driverSeat = seat(a), passengers = {seat(b), seat(), seat(c)}, remote = remote})
				local crew = API.GetTracked(jeep).crew(jeep)

				expect(#crew).to.equal(3)
				expect(crew[1]).to.equal(a)
				expect(crew[2]).to.equal(b)
				expect(crew[3]).to.equal(c)

				expect(#API.GetTracked(car({driverSeat = seat()})).crew(car({driverSeat = seat()}))).to.equal(0)

				local noSeats = car({driverSeat = seat(a)})
				noSeats.GetPassengerSeats = function() return nil end
				expect(#API.GetTracked(noSeats).crew(noSeats)).to.equal(1)
			end
		},
		{
			-- fails when the heading is not the car's own forward (GryMod's 90 degrees from the yaw is the Buggy's: a simfphys model has its own forward, found from its wheels), when the
			-- model's local forward is not used, or when an unknown forward does not leave the default rule
			name = "tracked facing: the forward the car computes (server), else its model's local forward, else nothing (the default rule)",
			func = function()
				local jeep = car({Forward = Vector(0, 1, 0)})
				local facing = API.GetTracked(jeep).facing

				expect(facing(jeep).y).to.equal(1)

				local local_ = car({VehicleData = {LocalAngForward = Angle(0, 90, 0)}})
				function local_:LocalToWorldAngles(ang)
					return {Forward = function() return Vector(0, 1, 0) end}
				end
				expect(facing(local_).y).to.equal(1)

				expect(facing(car())).to.beNil()
				expect(facing(car({Forward = Vector(0, 0, 0)}))).to.beNil()
			end
		},
		{
			-- fails when a car that exploded (destroyed is set before the removal) or has no health left still shows on the radar
			name = "tracked dead: a destroyed car, or one with no health left, is not a contact",
			func = function()
				local dead = API.GetTracked(car()).dead

				expect(dead(car())).to.equal(false)
				expect(dead(car({destroyed = true}))).to.equal(true)
				expect(dead(car({health = 0}))).to.equal(true)
			end
		},
		{
			-- fails when the anti-tank mine is not a device contact once scanned, when the player who threw it does not see it as his own, or when a mine nobody owns is not hostile
			name = "tracked: the anti-tank mine is a device contact, the thrower's own is an ally, any other is hostile",
			func = function()
				local owner, other = player(), player()
				local m = mine({Attacker = owner})
				local entry = API.GetTracked(m)

				expect(entry).notTo.beNil()
				expect(entry.type).to.equal(4)
				expect(entry.radar).to.equal("scan")
				expect(entry.relation(owner, m)).to.equal("ally")
				expect(entry.relation(other, m)).to.equal("hostile")
				expect(entry.relation(other, mine())).to.equal("hostile")
			end
		},
		{
			-- fails when the wheels of a car (they have their own +use and enter the car) get no prompt, when the mine's defusing is not a held use, or when the stock vehicle entry stops
			-- covering the car
			name = "usable: the car keeps the stock prompt, its wheels enter it too, the mine is defused with the key held",
			func = function()
				local jeep = car()
				local wheel = {IsValid = function() return true end, GetClass = function() return "gmod_sent_vehicle_fphysics_wheel" end}

				expect(API.GetUsable(jeep).icon).to.equal("enter")

				local entry = API.GetUsable(wheel)
				expect(entry).notTo.beNil()
				expect(entry.icon).to.equal("enter")

				local defuse = API.GetUsable(mine())
				expect(defuse).notTo.beNil()
				expect(defuse.hold).to.equal(true)
			end
		}
	}
}
