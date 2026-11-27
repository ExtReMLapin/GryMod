-- Tests of the simfphys adapter, client half (lua/grymod/compat/vehicles/cl_simfphys.lua), GLuaTest format, client realm. simfphys is NOT installed where these cases were written: the cars
-- and the seats are stand-ins that answer what simfphys' own code answers (simfphys_base 8d4b1ad: `car:GetIsVehicleLocked()` is networked, `car:GetDriverSeat()` and
-- `car:GetPassengerSeats()` are shared, `sv_simfphys_teampassenger` is replicated and refuses a player of another team than the occupants'). Each case names the change that makes it fail.

local API
local S

local NULL_ENT = {IsValid = function() return false end}

local function occupant(team)
	local ply = {}

	function ply:IsValid() return true end
	function ply:Team() return team end

	return ply
end

local function seat(driver)
	local pod = {}

	function pod:IsValid() return true end
	function pod:GetDriver() return driver or NULL_ENT end

	return pod
end

local function car(fields)
	local c = {locked = false, passengers = {}}

	for k, v in pairs(fields or {}) do
		c[k] = v
	end

	function c:IsValid() return true end
	function c:GetClass() return "gmod_sent_vehicle_fphysics_base" end
	function c:GetIsVehicleLocked() return self.locked end
	function c:GetDriver() return self.driver or NULL_ENT end
	function c:GetPassengerSeats() return self.passengers end

	return c
end

local function wheel(base)
	local w = {}

	function w:IsValid() return true end
	function w:GetClass() return "gmod_sent_vehicle_fphysics_wheel" end
	function w:GetBaseEnt() return base or NULL_ENT end

	return w
end

local teamOnly = false
local savedConVar

return {
	groupName = "GryMod compat: simfphys (client)",
	beforeEach = function()
		API = GryMod.API
		S = GryMod.CompatSimfphys
		teamOnly = false
		savedConVar = GetConVar
		GetConVar = function(name)
			if name == "sv_simfphys_teampassenger" then
				return {GetBool = function() return teamOnly end}
			end

			return savedConVar(name)
		end
	end,
	afterEach = function()
		GetConVar = savedConVar
	end,
	cases = {
		{
			-- fails when a locked car still shows "ENTER VEHICLE" (its use plays the locked sound and does nothing), when the wheel of a locked car does (the wheel's use is the car's), or when an
			-- open car loses its prompt
			name = "use filter: no prompt on a locked car or on its wheel; an open car and its wheel keep it",
			func = function()
				expect(S).notTo.beNil()
				expect(S.UsableFilter(car({locked = true}), occupant(1))).to.equal(false)
				expect(S.UsableFilter(wheel(car({locked = true})), occupant(1))).to.equal(false)
				expect(S.UsableFilter(car(), occupant(1))).to.beNil()
				expect(S.UsableFilter(wheel(car()), occupant(1))).to.beNil()
			end
		},
		{
			-- fails when the team rule is ignored (sv_simfphys_teampassenger 1: a player of another team than the driver, or than a passenger, is refused and hears the locked sound), when it
			-- applies with the setting off, or when the same team is refused
			name = "use filter: with sv_simfphys_teampassenger on, a car with an occupant of another team gets no prompt",
			func = function()
				local jeep = car({driver = occupant(2)})

				expect(S.UsableFilter(jeep, occupant(1))).to.beNil()

				teamOnly = true
				expect(S.UsableFilter(jeep, occupant(1))).to.equal(false)
				expect(S.UsableFilter(jeep, occupant(2))).to.beNil()

				local withPassenger = car({driver = occupant(1), passengers = {seat(occupant(3))}})
				expect(S.UsableFilter(withPassenger, occupant(1))).to.equal(false)
				expect(S.UsableFilter(car(), occupant(1))).to.beNil()
			end
		},
		{
			-- fails when the filter says something about what is not a simfphys car or wheel (it never adds a prompt and must not remove another addon's), or raises an error on a stand-in
			-- with no methods
			name = "use filter: no opinion for any other entity, and no error",
			func = function()
				expect(S.UsableFilter({IsValid = function() return true end, GetClass = function() return "prop_vehicle_jeep" end}, occupant(1))).to.beNil()
				expect(S.UsableFilter({IsValid = function() return true end, GetClass = function() return "gmod_sent_vehicle_fphysics_base"; end}, occupant(1))).to.beNil()
				expect(S.UsableFilter(nil, occupant(1))).to.beNil()
				expect(S.UsableFilter(5, occupant(1))).to.beNil()
			end
		}
	}
}
