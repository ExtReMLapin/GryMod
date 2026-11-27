-- The player's LOGICAL vehicle, for the extension API (GryMod.API.AddVehicleProvider, docs/api.md). Shared: both realms ask it.
--
-- Vehicles of other addons are not one engine entity with a seat: a simfphys car is a scripted entity and the player sits on a separate seat, an LVS or a Glide vehicle
-- has its own seats too, and Player:GetVehicle answers the SEAT (or nothing). The radar must not list the car the player sits in, the driver's colour is read from
-- the real driver, the binoculars must not scan what you sit in. An adapter tells GryMod how to find the vehicle of a player, and who drives it, once:
--
--     GryMod.API.AddVehicleProvider("my_addon", {
--         ofPlayer = function(ply) return the vehicle entity or nil end,   -- required
--         driver = function(vehicle) return the player or NPC at the wheel or nil end, -- optional
--         kind = "ground"                                                 -- optional: "ground" (default), "air" or "water"
--     })
--
-- Every function of a provider runs under GryMod.API.SafeCall (an error counts as "no answer"; the fifth in a row switches the function off).

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local KINDS = {ground = true, air = true, water = true}

-- The providers, in the order of registration (kept through a reload of this file).
local providers = API._vehicleProviders or {}
API._vehicleProviders = providers

-- [vehicle] = the provider that answered for it last (for GetVehicleKind), weak on the entities
local owners = setmetatable({}, {__mode = "k"})

-- An entity, or a table (a stand-in with an IsValid method): IsValid raises an error on a number or a string.
local function validObject(value)
	return (isentity(value) or istable(value)) and IsValid(value)
end

local function indexOf(key)
	for i = 1, #providers do
		if providers[i].key == key then
			return i
		end
	end

	return nil
end

-- Adds (or replaces, with the same key, keeping its place) a provider. Returns true, or false and why not.
function API.AddVehicleProvider(key, spec)
	if not isstring(key) or key == "" then
		return false, "invalid key"
	end

	if not istable(spec) then
		return false, "the spec must be a table"
	end

	if not isfunction(spec.ofPlayer) then
		return false, "ofPlayer must be a function"
	end

	if spec.driver ~= nil and not isfunction(spec.driver) then
		return false, "driver must be a function"
	end

	if spec.kind ~= nil and not (isstring(spec.kind) and KINDS[spec.kind]) and not isfunction(spec.kind) then
		return false, "kind must be \"ground\", \"air\" or \"water\""
	end

	local provider = {
		key = key, ofPlayer = spec.ofPlayer, driver = spec.driver, kind = spec.kind,
		ofId = "vehicle:" .. key .. "/ofPlayer", driverId = "vehicle:" .. key .. "/driver", kindId = "vehicle:" .. key .. "/kind"
	}

	API.SafeCallReset(provider.ofId)
	API.SafeCallReset(provider.driverId)
	API.SafeCallReset(provider.kindId)

	local at = indexOf(key)

	if at then
		providers[at] = provider
	else
		providers[#providers + 1] = provider
	end

	return true
end

-- Removes a provider; returns whether there was one.
function API.RemoveVehicleProvider(key)
	local at = isstring(key) and indexOf(key)

	if not at then
		return false
	end

	table.remove(providers, at)

	return true
end

-- The vehicle the player is in: the first provider that answers a valid entity, else the engine's Player:GetVehicle (the Half-Life 2 vehicles), else nil.
function API.GetVehicleOf(ply)
	if not validObject(ply) then
		return nil
	end

	for i = 1, #providers do
		local provider = providers[i]
		local ok, vehicle = API.SafeCall(provider.ofId, provider.ofPlayer, ply)

		if ok and validObject(vehicle) then
			owners[vehicle] = provider

			return vehicle
		end
	end

	if isfunction(ply.GetVehicle) then
		local vehicle = ply:GetVehicle()

		if validObject(vehicle) then
			return vehicle
		end
	end

	return nil
end

-- Who is at the wheel of the vehicle: the first provider with a `driver` function that answers a valid player or NPC, else the entity's own GetDriver (the
-- Half-Life 2 vehicles), else nil.
function API.GetVehicleDriver(vehicle)
	if not validObject(vehicle) then
		return nil
	end

	for i = 1, #providers do
		local provider = providers[i]

		if provider.driver then
			local ok, driver = API.SafeCall(provider.driverId, provider.driver, vehicle)

			if ok and validObject(driver) then
				owners[vehicle] = owners[vehicle] or provider

				return driver
			end
		end
	end

	if isfunction(vehicle.GetDriver) then
		local ok, driver = pcall(vehicle.GetDriver, vehicle)

		if ok and validObject(driver) then
			return driver
		end
	end

	return nil
end

-- "ground", "air" or "water". The kind of the provider that found this vehicle (through GetVehicleOf or GetVehicleDriver; a `kind` that is a function is asked the
-- vehicle); a vehicle no provider found yet is claimed by the first provider that has a `kind` and a `driver` that answers for it. Without any kind: the registry's
-- flying icon (`type = "flying"`) is "air", anything else "ground".
function API.GetVehicleKind(vehicle)
	if not validObject(vehicle) then
		return "ground"
	end

	local provider = owners[vehicle]

	if not provider then
		for i = 1, #providers do
			local candidate = providers[i]

			if candidate.driver and candidate.kind then
				local ok, driver = API.SafeCall(candidate.driverId, candidate.driver, vehicle)

				if ok and validObject(driver) then
					provider = candidate
					owners[vehicle] = candidate

					break
				end
			end
		end
	end

	local kind = provider and provider.kind

	if isfunction(kind) then
		local ok, answer = API.SafeCall(provider.kindId, kind, vehicle)

		kind = ok and answer or nil
	end

	if isstring(kind) and KINDS[kind] then
		return kind
	end

	local entry = API.GetTracked and API.GetTracked(vehicle)

	if entry and entry.type == 2 then
		return "air"
	end

	return "ground"
end

API.AddFeature("vehicles")
