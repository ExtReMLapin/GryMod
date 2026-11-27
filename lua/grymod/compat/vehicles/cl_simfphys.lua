-- simfphys (the physics vehicle base of Garry's Mod and its armed pack), client half of the compatibility patch (docs/compat.md, sh_simfphys.lua says what GryMod knows about it).
-- The prompt "ENTER VEHICLE" is taken away where the +use does nothing: a car that is locked (`car:GetIsVehicleLocked()`, networked; the use plays the locked sound), its wheels (their +use is the
-- car's), and a car that a player of another team sits in when the server's `sv_simfphys_teampassenger` is on (simfphys refuses him the same way). Public API: GryMod.API.AddUsableFilter.

local API = GryMod.API
local S = GryMod.CompatSimfphys

if not API or not API.AddUsableFilter or not S then
	return -- cl_api.lua and sh_simfphys.lua are included first (grymod_shared.lua)
end

-- Whether the server only lets players of one team share a car (replicated).
local function teamOnly()
	local var = GetConVar("sv_simfphys_teampassenger")

	return var ~= nil and var:GetBool()
end

-- Whether a player of another team than `team` sits in the car (the driver, or a passenger).
local function otherTeamInside(car, team)
	local driver = car:GetDriver()

	if IsValid(driver) and driver:Team() ~= team then
		return true
	end

	local seats = car:GetPassengerSeats()

	if istable(seats) then
		for i = 1, #seats do
			local pod = seats[i]
			local passenger = IsValid(pod) and pod:GetDriver() or nil

			if IsValid(passenger) and passenger:Team() ~= team then
				return true
			end
		end
	end

	return false
end

-- false: no prompt; nil: no opinion (never a prompt that was not there).
function S.UsableFilter(ent, ply)
	local ok, answer = pcall(function()
		if not IsValid(ent) then
			return nil
		end

		local class = ent:GetClass()
		local car = ent

		if class == S.Wheel then
			car = ent:GetBaseEnt()
		elseif class ~= S.Car then
			return nil
		end

		if not IsValid(car) or car:GetClass() ~= S.Car then
			return nil
		end

		if car:GetIsVehicleLocked() then
			return false
		end

		if IsValid(ply) and teamOnly() and otherTeamInside(car, ply:Team()) then
			return false
		end

		return nil
	end)

	if ok and answer == false then
		return false
	end

	return nil
end

API.AddUsableFilter("simfphys", S.UsableFilter)
