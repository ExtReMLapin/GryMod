-- Tests of the vehicle providers of the extension API (GryMod.API.AddVehicleProvider, GetVehicleOf, GetVehicleDriver, GetVehicleKind; lua/grymod/sh_api_vehicles.lua),
-- GLuaTest format, runs in the server AND in the client realm. Each case names the production change whose absence makes it fail.

local API
local KEYS = {"t_veh_a", "t_veh_b", "t_veh_c"}

-- an entity of the tests: a table that answers like one
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

local function cleanUp()
	for _, key in ipairs(KEYS) do
		API.RemoveVehicleProvider(key)

		for _, suffix in ipairs({"/ofPlayer", "/driver", "/kind"}) do
			API.SafeCallReset("vehicle:" .. key .. suffix)
		end
	end
end

return {
	groupName = "GryMod extension API: vehicle providers (shared)",
	beforeEach = function()
		API = GryMod.API
		cleanUp()
	end,
	afterEach = function()
		cleanUp()
	end,
	cases = {
		{
			-- fails when the functions do not exist (or the feature is not announced), or when a bad key, spec, driver or kind is accepted
			name = "AddVehicleProvider checks its arguments, announces the feature, and RemoveVehicleProvider says whether there was one",
			func = function()
				expect(API.Has("vehicles")).to.beTrue()
				expect((API.AddVehicleProvider("", {ofPlayer = function() end}))).to.beFalse()
				expect((API.AddVehicleProvider(5, {ofPlayer = function() end}))).to.beFalse()
				expect((API.AddVehicleProvider("t_veh_a", "nope"))).to.beFalse()
				expect((API.AddVehicleProvider("t_veh_a", {}))).to.beFalse()
				expect((API.AddVehicleProvider("t_veh_a", {ofPlayer = function() end, driver = 3}))).to.beFalse()
				expect((API.AddVehicleProvider("t_veh_a", {ofPlayer = function() end, kind = "submarine"}))).to.beFalse()

				expect(API.AddVehicleProvider("t_veh_a", {ofPlayer = function() end})).to.beTrue()
				expect(API.AddVehicleProvider("t_veh_b", {ofPlayer = function() end, driver = function() end, kind = "air"})).to.beTrue()
				expect(API.RemoveVehicleProvider("t_veh_a")).to.beTrue()
				expect(API.RemoveVehicleProvider("t_veh_a")).to.beFalse()
			end
		},
		{
			-- fails when the first provider that answers does not win, when a provider that errors or answers nothing stops the search, or when an answer that is not a valid entity
			-- is taken for a vehicle
			name = "GetVehicleOf: the first provider that answers wins, one that errors, answers nil or answers junk is skipped",
			func = function()
				local car = ent("t_car")
				local other = ent("t_other")
				local ply = ent("player")

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() error("provider failure") end})
				API.AddVehicleProvider("t_veh_b", {ofPlayer = function() return "not an entity" end})
				API.AddVehicleProvider("t_veh_c", {ofPlayer = function() return {IsValid = function() return false end} end})
				expect(API.GetVehicleOf(ply)).to.beNil()

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() return nil end})
				API.AddVehicleProvider("t_veh_b", {ofPlayer = function() return car end})
				API.AddVehicleProvider("t_veh_c", {ofPlayer = function() return other end})
				expect(API.GetVehicleOf(ply)).to.equal(car)
			end
		},
		{
			-- fails when the engine's own vehicle (Player:GetVehicle, the Half-Life 2 vehicles) is no longer the fallback, or when it wins over a provider that knows better (a
			-- simfphys car: the engine only knows its seat)
			name = "GetVehicleOf falls back on the engine's Player:GetVehicle, and a provider's answer beats it",
			func = function()
				local seat = ent("prop_vehicle_prisoner_pod")
				local car = ent("t_car")
				local ply = ent("player", {GetVehicle = function() return seat end})

				expect(API.GetVehicleOf(ply)).to.equal(seat)

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() return car end})
				expect(API.GetVehicleOf(ply)).to.equal(car)

				expect(API.GetVehicleOf(nil)).to.beNil()
				expect(API.GetVehicleOf(5)).to.beNil()
				expect(API.GetVehicleOf(ent("player", {IsValid = function() return false end}))).to.beNil()
			end
		},
		{
			-- fails when the driver of a provider is not read, when the entity's own GetDriver stops being the fallback, or when a driver that is not valid counts
			name = "GetVehicleDriver: a provider's driver first, then the entity's own GetDriver, nil when none is valid",
			func = function()
				local driver = ent("player")
				local own = ent("player")
				local car = ent("t_car")
				local jeep = ent("prop_vehicle_jeep", {GetDriver = function() return own end})

				expect(API.GetVehicleDriver(car)).to.beNil()
				expect(API.GetVehicleDriver(jeep)).to.equal(own)

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() end, driver = function(v) if v == car then return driver end end})
				expect(API.GetVehicleDriver(car)).to.equal(driver)
				expect(API.GetVehicleDriver(jeep)).to.equal(own)

				-- a provider without a driver function, and one whose driver errors, do not stop the search
				API.AddVehicleProvider("t_veh_b", {ofPlayer = function() end})
				API.AddVehicleProvider("t_veh_c", {ofPlayer = function() end, driver = function() error("driver failure") end})
				expect(API.GetVehicleDriver(car)).to.equal(driver)
				expect(API.GetVehicleDriver(5)).to.beNil()
			end
		},
		{
			-- fails when the kind of the provider that found the vehicle is not the one reported, when "ground" is not the default, or when a vehicle of a flying registry entry
			-- is not "air"
			name = "GetVehicleKind: the kind of the provider that found the vehicle; ground by default; air for a flying entry of the registry",
			func = function()
				local plane = ent("t_plane")
				local boat = ent("t_boat")
				local car = ent("t_car")
				local pilot, skipper = ent("player"), ent("player")

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() end, driver = function(v) if v == plane then return pilot end end, kind = "air"})
				API.AddVehicleProvider("t_veh_b", {ofPlayer = function(p) if p == skipper then return boat end end, kind = "water"})

				-- found through the player: that provider's kind (it was asked first); found through the driver of another: the same
				expect(API.GetVehicleKind(plane)).to.equal("air")
				expect(API.GetVehicleOf(skipper)).to.equal(boat)
				expect(API.GetVehicleKind(boat)).to.equal("water")
				expect(API.GetVehicleKind(car)).to.equal("ground")
				expect(API.GetVehicleKind(nil)).to.equal("ground")

				-- a kind that is a function is asked the vehicle
				API.AddVehicleProvider("t_veh_c", {ofPlayer = function() end, driver = function(v) if v.fast then return pilot end end, kind = function(v) return v.fast and "air" or "ground" end})

				local jet = ent("t_jet", {fast = true})

				expect(API.GetVehicleKind(jet)).to.equal("air")

				-- the registry's flying icon makes a vehicle that no provider knows an aircraft
				local key = "t_veh_reg"

				API.RegisterTracked(key, {class = "t_heli", type = "flying"})

				local ok, err = pcall(function()
					expect(API.GetVehicleKind(ent("t_heli"))).to.equal("air")
				end)

				API.UnregisterTracked(key)
				assert(ok, err)
			end
		},
		{
			-- fails when the same key adds a second provider next to the first (both are asked), or when a removed provider is still asked
			name = "the same key replaces the provider, a removed provider is no longer asked",
			func = function()
				local first, second = ent("t_first"), ent("t_second")
				local ply = ent("player")

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() return first end})
				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() return second end})
				expect(API.GetVehicleOf(ply)).to.equal(second)

				API.RemoveVehicleProvider("t_veh_a")
				expect(API.GetVehicleOf(ply)).to.beNil()
			end
		},
		{
			-- fails when a provider that keeps raising errors is never switched off (SafeCall), or when adding it again does not arm it again
			name = "a provider function that fails five times in a row is switched off; adding the provider again arms it again",
			func = function()
				local ply = ent("player")
				local calls = 0

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() calls = calls + 1 error("provider failure") end})

				for _ = 1, API.SafeCallLimit + 3 do
					API.GetVehicleOf(ply)
				end

				expect(calls).to.equal(API.SafeCallLimit)
				expect(API.SafeCallDisabled("vehicle:t_veh_a/ofPlayer")).to.beTrue()

				local car = ent("t_car")

				API.AddVehicleProvider("t_veh_a", {ofPlayer = function() return car end})
				expect(API.GetVehicleOf(ply)).to.equal(car)
			end
		}
	}
}
