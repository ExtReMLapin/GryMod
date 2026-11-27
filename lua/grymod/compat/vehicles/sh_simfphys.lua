-- simfphys (the physics vehicle base of Garry's Mod, "simple fphys": the base and its armed pack), shared half of the compatibility patch (docs/compat.md). What GryMod knows about it:
--   * the CAR is one class, `gmod_sent_vehicle_fphysics_base`, for every vehicle of every pack; its name is the networked string `car:GetSpawn_List()`, its data `list.Get("simfphys_vehicles")`.
--   * the player does not sit in the car: he sits on a `prop_vehicle_prisoner_pod` that is a child of it, so `Player:GetVehicle()` is the SEAT. `Player:GetSimfphys()` is the car (or NULL).
--   * `car:GetDriver()` is the remote driver (weapon_simremote: a player who stands outside) when there is one: the driver who SITS is the one of `car:GetDriverSeat()`.
--   * the wheels are entities of their own (`gmod_sent_vehicle_fphysics_wheel`) with a +use that enters the car; the anti-tank mine of the armed pack (`simfphys_antitankmine`) is defused with
--     +use held.
-- Read in the source of simfphys_base 8d4b1ad and simfphys_armed 53f709f (2026-05-05); simfphys was NOT installed when this file was written, it is tested with stand-ins (tests/*_compat_simfphys_test.lua).
-- Everything here is the public API (GryMod.API.AddVehicleProvider, RegisterTracked, RegisterUsable): data and small readers, nothing runs by itself, and nothing happens when simfphys is not there (its
-- methods are asked under the API's SafeCall, and a stand-in that has none answers nil). The server half is sv_simfphys.lua, the client half cl_simfphys.lua.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterTracked or not API.RegisterUsable then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local S = GryMod.CompatSimfphys or {}
GryMod.CompatSimfphys = S

local CAR = "gmod_sent_vehicle_fphysics_base"
local WHEEL = "gmod_sent_vehicle_fphysics_wheel"
local MINE = "simfphys_antitankmine"

S.Car, S.Wheel, S.Mine = CAR, WHEEL, MINE

-- The mass from which a simfphys vehicle is a heavy machine, one whose hits can put the suit down: the tanks of the armed pack weigh 8000 to 20000, the armored cars 4800 and less.
S.HEAVY_MASS = 8000

-- ---------------------------------------------------------------------------------------------------------
-- The car of a player, the driver, the crew
-- ---------------------------------------------------------------------------------------------------------

-- The simfphys car the player sits in (driver or passenger), or nil: not the seat, which is what the engine answers.
function S.CarOf(ply)
	local ask = ply ~= nil and ply.GetSimfphys

	if not isfunction(ask) then
		return nil
	end

	local car = ask(ply)

	if IsValid(car) then
		return car
	end

	return nil
end

-- The player who SITS at the wheel of the car, or nil: never a passenger, never the remote driver (the player who commands the car from outside).
function S.Driver(car)
	if not istable(car) and not isentity(car) then
		return nil
	end

	local ask = car.GetDriverSeat

	if not isfunction(ask) then
		return nil
	end

	local pod = ask(car)

	if not IsValid(pod) then
		return nil
	end

	local driver = pod:GetDriver()

	if IsValid(driver) then
		return driver
	end

	return nil
end

-- Everybody who sits in the car: the driver, then the passengers. The remote driver is not in it.
function S.Crew(car)
	local crew = {}
	local driver = S.Driver(car)

	if driver then
		crew[1] = driver
	end

	local ask = car.GetPassengerSeats
	local seats = isfunction(ask) and ask(car) or nil

	if istable(seats) then
		for i = 1, #seats do
			local pod = seats[i]
			local passenger = IsValid(pod) and pod:GetDriver() or nil

			if IsValid(passenger) then
				crew[#crew + 1] = passenger
			end
		end
	end

	return crew
end

-- ---------------------------------------------------------------------------------------------------------
-- What the radar needs to know about a car
-- ---------------------------------------------------------------------------------------------------------

local heavy = setmetatable({}, {__mode = "k"})

-- Whether this car is a heavy machine (a tank), by the mass its model's table gives. A car whose name is not known (the networked string has not arrived, the vehicle is not in the list)
-- is not heavy and is asked again.
function S.Heavy(car)
	local known = heavy[car]

	if known ~= nil then
		return known
	end

	local name = car:GetSpawn_List()

	if not isstring(name) or name == "" then
		return false
	end

	local entry = list.Get("simfphys_vehicles")[name]
	local mass = entry and entry.Members and entry.Members.Mass

	if not isnumber(mass) then
		return false
	end

	known = mass >= S.HEAVY_MASS
	heavy[car] = known

	return known
end

-- The world forward of the car, or nil (the radar then keeps its own rule). The car works its own forward out of its wheels at every tick (`car.Forward`, server only); a model's local forward
-- is `car.VehicleData.LocalAngForward`. The 90 degrees of the engine vehicles are no rule here: simfphys models do not agree on their front.
function S.Facing(car)
	local forward = car.Forward

	if isvector(forward) and forward:Length() > 0 then
		return forward
	end

	local data = car.VehicleData
	local local_ = istable(data) and data.LocalAngForward or nil

	if local_ ~= nil and isfunction(car.LocalToWorldAngles) then
		local vector = car:LocalToWorldAngles(local_):Forward()

		if isvector(vector) and vector:Length() > 0 then
			return vector
		end
	end

	return nil
end

-- A car that exploded (`car.destroyed`, set before the removal), or that has no health left, is a wreck: not a contact.
function S.Dead(car)
	if car.destroyed == true then
		return true
	end

	return isfunction(car.GetCurHealth) and car:GetCurHealth() <= 0 or false
end

-- What an anti-tank mine is to a player: his own when he threw it (the armed pack keeps the thrower in `Attacker` and `CreatedBy`), a danger otherwise.
function S.MineRelation(ply, mine)
	if ply ~= nil and (mine.Attacker == ply or mine.CreatedBy == ply) then
		return "ally"
	end

	return "hostile"
end

-- ---------------------------------------------------------------------------------------------------------
-- Registrations
-- ---------------------------------------------------------------------------------------------------------

-- The vehicle of a player: the car, not the seat. `GetVehicleDriver` is the player who sits at the wheel (the remote driver is not asked about: the crew below gives the radar the colour).
if API.AddVehicleProvider then
	local ok, reason = API.AddVehicleProvider("simfphys", {ofPlayer = S.CarOf, driver = function(car) if car:GetClass() == CAR then return S.Driver(car) or false end end, kind = "ground"})

	if not ok then
		MsgN("GryMod: the simfphys vehicle provider was refused: " .. tostring(reason))
	end
end

local function register(key, def)
	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the simfphys entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- The cars: a vehicle once the binoculars scanned it (as the stock vehicles), a rectangle on the radar in the colour of its crew, the icon turned the way the car faces, a wreck is no
-- contact. The heavy ones come first (the first entry that matches wins): a hit of a tank that breaks the armor puts the suit down, as a Strider's does.
local function car(def)
	def.type, def.radar = "machine", "scan"
	def.crew, def.facing, def.dead = S.Crew, S.Facing, S.Dead

	return def
end

register("simfphys_heavy", car({match = function(ent) return ent:GetClass() == CAR and S.Heavy(ent) end, heavy = true, priority = 10}))
register("simfphys_cars", car({class = CAR}))

-- The anti-tank mine: a device on the radar once scanned (the thrower's own is his friend).
register("simfphys_mine", {class = MINE, type = "device", radar = "scan", relation = S.MineRelation})

-- The prompt. The car is the stock "ENTER VEHICLE" entry already (the car answers `IsVehicle`); its wheels have a +use of their own that enters the car, and the mine is defused with the key held.
local function usable(key, def)
	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the simfphys entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

usable("simfphys_wheels", {class = WHEEL, icon = "enter", text = "ENTER VEHICLE", use = "once"})
usable("simfphys_mine", {class = MINE, icon = "use", text = "DEFUSE (HOLD)", use = "repeat", cooldown = 0.5, hold = true})
