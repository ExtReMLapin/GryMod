-- Tests of the client half of the LVS patch (lua/grymod/compat/vehicles/cl_lvs.lua), GLuaTest format, client realm: the camera owner (LVS owns the view of a player who sits in
-- its vehicle) and the use prompt of a vehicle the key does nothing for (locked, wrecked, kept to another team: lvs_base's IsUseAllowed). LVS is not installed in the test game:
-- stand-ins that answer like what was read in its code. The API is the real one. Each case names the production change whose absence makes it fail.

local API
local L
local realLVS

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

local function vehicle(fields)
	local v = ent("lvs_x", {
		LVS = true, _team = 0, _hp = 100, _locked = false,
		GetAITEAM = function(self) return self._team end,
		GetHP = function(self) return self._hp end,
		GetlvsLockedStatus = function(self) return self._locked end
	})

	for key, value in pairs(fields or {}) do
		v[key] = value
	end

	return v
end

-- a player who sits in `veh` (nil: on foot) and looks through `view` (nil: his own eyes)
local function player(veh, team, view)
	local p = ent("player", {
		lvsGetVehicle = function() return veh or NULL end,
		lvsGetAITeam = function() return team or 0 end
	})

	p.GetViewEntity = function() return view or p end

	return p
end

return {
	groupName = "GryMod compat: LVS (client)",
	beforeEach = function()
		API = GryMod.API
		L = GryMod.CompatLVS
		realLVS = LVS

		L.UninstallClient()
		LVS = {}
	end,
	afterEach = function()
		L.UninstallClient()
		LVS = realLVS

		if realLVS ~= nil then
			L.InstallClient()
		end
	end,
	cases = {
		{
			-- fails when InstallClient registers without LVS, or when the camera owner or the prompt filter is not registered with LVS, or is left after UninstallClient
			name = "InstallClient registers the camera owner and the prompt filter only when LVS is there; UninstallClient takes them away",
			func = function()
				local seated = player(vehicle())

				LVS = nil
				expect(L.InstallClient()).to.beFalse()
				expect(API.IsCameraOwned(seated)).to.beFalse()

				LVS = {}
				expect(L.InstallClient()).to.beTrue()
				expect(API.IsCameraOwned(seated)).to.beTrue()
				expect(API.UsableFiltered(vehicle({_locked = true}), seated)).to.beTrue()

				L.UninstallClient()

				expect(API.IsCameraOwned(seated)).to.beFalse()
				expect(API.UsableFiltered(vehicle({_locked = true}), seated)).to.beFalse()
			end
		},
		{
			-- fails when a player on foot, one who looks through another entity (a camera: LVS's CalcView gives up) or one in an engine vehicle is taken for an LVS view
			name = "OwnsView: a player in an LVS vehicle who sees through his own eyes; not on foot, not through another entity's view",
			func = function()
				local car = vehicle()
				local camera = ent("gmod_cameraprop")

				expect(L.OwnsView(player(car))).to.beTrue()
				expect(L.OwnsView(player())).to.beFalse()
				expect(L.OwnsView(player(car, 0, camera))).to.beFalse()
				expect(L.OwnsView(ent("player"))).to.beFalse()
				expect(L.OwnsView(nil)).to.beFalse()
			end
		},
		{
			-- fails when a locked vehicle, a wreck (health 0), or a vehicle of another team under lvs_teampassenger gets a prompt, when a free vehicle loses it, or when the team rule
			-- is applied while the server does not use it
			name = "UseRefused: locked, wrecked, or another team's vehicle when the server keeps teams out; a free vehicle is not refused",
			func = function()
				local me = player(nil, 1)

				expect(L.UseRefused(vehicle(), me)).to.beFalse()
				expect(L.UseRefused(vehicle({_locked = true}), me)).to.beTrue()
				expect(L.UseRefused(vehicle({_hp = 0}), me)).to.beTrue()
				expect(L.UseRefused(vehicle({_hp = -50}), me)).to.beTrue()

				-- another team: only when lvs_teampassenger is on
				expect(L.UseRefused(vehicle({_team = 2}), me)).to.beFalse()

				LVS.TeamPassenger = true

				expect(L.UseRefused(vehicle({_team = 2}), me)).to.beTrue()
				expect(L.UseRefused(vehicle({_team = 1}), me)).to.beFalse()
				expect(L.UseRefused(vehicle({_team = 0}), me)).to.beFalse()
				expect(L.UseRefused(vehicle({_team = 2}), player(nil, 0))).to.beFalse()
			end
		},
		{
			-- fails when the filter answers something other than false (it would hide a prompt it must not, or show one), or answers for an entity that is not an LVS vehicle
			name = "UsableFilter: false (no prompt) for a vehicle the key does nothing for, no opinion for everything else",
			func = function()
				local me = player()

				expect(L.UsableFilter(vehicle({_locked = true}), me)).to.equal(false)
				expect(L.UsableFilter(vehicle(), me)).to.beNil()
				expect(L.UsableFilter(ent("prop_door_rotating"), me)).to.beNil()
				expect(L.UsableFilter(ent("prop_vehicle_jeep", {GetlvsLockedStatus = function() return true end}), me)).to.beNil()
			end
		}
	}
}
