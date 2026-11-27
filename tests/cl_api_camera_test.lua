-- Tests of the camera owners (GryMod.API.AddCameraOwner / RemoveCameraOwner / IsCameraOwned, lua/grymod/client/cl_api.lua) and of what GryMod does with the view
-- while another addon owns it (the binoculars' CalcView and their zoom key, the suit's own zoom), GLuaTest format, client realm. Some addons have a camera of their
-- own (a drone, a security camera, a vehicle's special view, a cinematic): GryMod must not zoom, sway or turn that view, and must not read the game's zoom key for it.
-- The same CalcView never gives a view in a vehicle, in third person or while another entity has the view. Each case names the production change whose absence makes
-- it fail.

local API = GryMod.API
local ids

local function owner(id, fn)
	ids[#ids + 1] = id

	return API.AddCameraOwner(id, fn)
end

-- a player stand-in for the binoculars' CalcView and Wanted
local function player(facts)
	facts = facts or {}

	local ply = {
		IsValid = function() return true end,
		Alive = function() return true end,
		KeyDown = function(_, key) return facts.zoomKey == true and key == IN_ZOOM end,
		InVehicle = function() return facts.vehicle == true end,
		ShouldDrawLocalPlayer = function() return facts.thirdperson == true end,
		GetInfoNum = function(_, name, default) return name == "fov_desired" and 100 or default end
	}

	ply.GetViewEntity = function(self) return facts.viewEntity or self end

	return ply
end

-- runs fn with the binoculars' hooks into the world standing in (the clock, the switches), and puts everything back whatever happens
local function withBinoculars(fn)
	local M = GryMod.FlashBinoculars
	local now, enabled, stages = M.Now, M.Enabled, M.StagesEnabled

	M.Now = function() return 0 end
	M.Enabled = function() return true end
	M.StagesEnabled = function() return true end
	M.ZoomReset(M.ZoomState)

	local ok, err = pcall(fn, M)

	M.Now, M.Enabled, M.StagesEnabled = now, enabled, stages
	M.ZoomReset(M.ZoomState)

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod extension API: camera owners (client)",
	beforeEach = function(state)
		ids = {}

		-- the player's own sway would move the angles the view cases read
		local sway = GetConVar("gry_binoculars_sway")
		state.savedSway = sway and sway:GetString()

		if sway then
			sway:SetString("0")
		end
	end,
	afterEach = function(state)
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemoveCameraOwner(id)
			end
		end)

		pcall(function()
			local sway = GetConVar("gry_binoculars_sway")

			if sway and state.savedSway ~= nil then
				sway:SetString(state.savedSway)
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad key or function is accepted, or the feature is not announced
			name = "AddCameraOwner takes a text key and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("cameraowner")).to.beTrue()
				expect(owner("test.a", function() return false end)).to.beTrue()
				expect(API.AddCameraOwner("", function() end)).to.beFalse()
				expect(API.AddCameraOwner(5, function() end)).to.beFalse()
				expect(API.AddCameraOwner("test.b", "no")).to.beFalse()
				expect(API.AddCameraOwner("test.b")).to.beFalse()
			end
		},
		{
			-- fails when no owner means owned, when one true owner is not enough, or when the player is not given to the owner
			name = "IsCameraOwned: false with no owner or only owners that say no; true as soon as one says yes; the owner is asked about the player",
			func = function()
				local ply = player()
				local seen

				expect(API.IsCameraOwned(ply)).to.beFalse()

				owner("test.no", function() return false end)
				owner("test.nothing", function() return nil end)
				expect(API.IsCameraOwned(ply)).to.beFalse()

				owner("test.yes", function(given) seen = given return true end)
				expect(API.IsCameraOwned(ply)).to.beTrue()
				expect(seen).to.equal(ply)
			end
		},
		{
			-- fails when only the value true counts is not respected (a truthy junk value would take the camera from the player), or Remove does not take the owner away
			name = "only the answer true is a camera owner (a number or a text is not); RemoveCameraOwner takes the owner away and says whether there was one",
			func = function()
				local ply = player()

				owner("test.junk", function() return 1 end)
				expect(API.IsCameraOwned(ply)).to.beFalse()

				owner("test.junk", function() return true end) -- the same key replaces the owner
				expect(API.IsCameraOwned(ply)).to.beTrue()
				expect(API.RemoveCameraOwner("test.junk")).to.beTrue()
				expect(API.RemoveCameraOwner("test.junk")).to.beFalse()
				expect(API.IsCameraOwned(ply)).to.beFalse()
			end
		},
		{
			-- fails when an owner that raises an error stops the others, or is asked again after the fifth error, or cannot be re-armed by adding it again
			name = "an owner that raises an error is skipped and the next one still answers; five errors in a row switch it off (one frame each); adding it again re-arms it",
			func = function()
				local calls = 0
				local ply = player()

				owner("test.bad", function() calls = calls + 1 error("broken owner") end)
				owner("test.good", function() return true end)

				for _ = 1, 8 do
					expect(API.IsCameraOwned(ply, true)).to.beTrue()
				end

				expect(calls).to.equal(5)

				owner("test.bad", function() calls = calls + 1 return false end)
				API.IsCameraOwned(ply, true)
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when the owners are asked at every call: the binoculars ask many times a frame, the owner's code would run at each of them
			name = "the owners are asked once per frame and player (the answer is kept for the frame); a new owner or a removed one is asked at once",
			func = function()
				local ply = player()
				local calls, answer = 0, false

				owner("test.count", function() calls = calls + 1 return answer end)

				for _ = 1, 5 do
					API.IsCameraOwned(ply)
				end

				expect(calls).to.equal(1)

				-- the same key added again: the kept answer is dropped
				answer = true
				owner("test.count", function() calls = calls + 1 return answer end)
				expect(API.IsCameraOwned(ply)).to.beTrue()
				expect(calls).to.equal(2)

				API.RemoveCameraOwner("test.count")
				expect(API.IsCameraOwned(ply)).to.beFalse()
			end
		},
		{
			-- fails when Wanted still reads the game's zoom key (IN_ZOOM) while an owner has the camera, or when it does not read it again after the owner is gone
			name = "Bino.Wanted: the game's zoom key does not put the binoculars up while a camera owner has the view, and does again when it is gone",
			func = function()
				local M = GryMod.FlashBinoculars
				local ply = player({zoomKey = true})

				expect(M.Wanted(ply)).to.beTrue()

				owner("test.camera", function() return true end)
				expect(M.Wanted(ply)).to.beFalse()

				API.RemoveCameraOwner("test.camera")
				expect(M.Wanted(ply)).to.beTrue()
			end
		},
		{
			-- fails when CalcView still gives the zoom's view with an owner on the camera: the addon's camera would be zoomed and its state kept
			name = "Bino.CalcView gives no view while a camera owner has the view, drops the zoom state, and gives the stage's view again when it is gone",
			func = function()
				local ply = player({zoomKey = true})
				local origin, angles = Vector(1, 2, 3), Angle(4, 5, 6)

				withBinoculars(function(M)
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).toNot.beNil()
					expect(M.ZoomState.active).to.beTrue()

					owner("test.camera", function() return true end)
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).to.beNil()
					expect(M.ZoomState.active).to.beFalse()

					API.RemoveCameraOwner("test.camera")
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).toNot.beNil()
				end)
			end
		},
		{
			-- fails when a vehicle with the game's zoom key held (IN_ZOOM) gets the zoom's view: the vehicle's camera would be lost (COMMON.md, internal fix 5)
			name = "Bino.CalcView never gives a view in a vehicle, even with the game's zoom key held",
			func = function()
				withBinoculars(function(M)
					local ply = player({zoomKey = true, vehicle = true})

					expect(M.CalcView(ply, Vector(), Angle(), 100, 3, 8000)).to.beNil()
					expect(M.ZoomState.active).to.beFalse()
				end)
			end
		},
		{
			-- fails when the third person view or a view held by another entity (a camera, a spectated player) is zoomed by the binoculars (view-2, J1)
			name = "Bino.CalcView gives no view in third person or while another entity has the view (the zoom key held)",
			func = function()
				withBinoculars(function(M)
					expect(M.CalcView(player({zoomKey = true, thirdperson = true}), Vector(), Angle(), 100, 3, 8000)).to.beNil()
					expect(M.CalcView(player({zoomKey = true, viewEntity = {}}), Vector(), Angle(), 100, 3, 8000)).to.beNil()
					expect(M.CalcView(player({zoomKey = true}), Vector(), Angle(), 100, 3, 8000)).toNot.beNil()
				end)
			end
		},
		{
			-- fails when the nested call of an addon that passes a boolean for znear (VManip) is answered with a view (our table ends the hook chain)
			name = "Bino.CalcView ignores a nested call whose znear is not a number (VManip's call), and gives its view for a real one",
			func = function()
				withBinoculars(function(M)
					local ply = player({zoomKey = true})

					expect(M.CalcView(ply, Vector(), Angle(), 100, true, 8000)).to.beNil()
					expect(M.CalcView(ply, Vector(), Angle(), 100, nil, nil)).to.beNil()
					expect(M.CalcView(ply, Vector(), Angle(), 100, 3, 8000)).toNot.beNil()
				end)
			end
		},
		{
			-- fails when the heading of the radar, the compass and the arrows is still the eye angles (a camera owner's view, a vehicle's camera or the binoculars' sway would not turn them),
			-- or when another player is read from the main view
			name = "Flash.ViewYaw: the local player's heading is the yaw of the view really drawn (MainEyeAngles), read once per frame; another player (or no MainEyeAngles) keeps the old rule",
			func = function()
				local Flash = GryMod.Flash
				local real, calls = MainEyeAngles, 0
				local other = {InVehicle = function() return false end, EyeAngles = function() return Angle(5, 40, 0) end}

				local ok, err = pcall(function()
					MainEyeAngles = function() calls = calls + 1 return Angle(0, 77, 0) end
					Flash.ViewYawFrame = -1

					expect(Flash.ViewYaw(LocalPlayer())).to.equal(77)
					expect(Flash.ViewYaw(LocalPlayer())).to.equal(77)
					expect(calls).to.equal(1)

					-- another player: his eye angles
					expect(Flash.ViewYaw(other)).to.equal(40)
					expect(calls).to.equal(1)

					-- a game with no MainEyeAngles
					MainEyeAngles = nil
					expect(Flash.ViewYaw(other)).to.equal(40)
				end)

				MainEyeAngles = real
				Flash.ViewYawFrame = -1

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when the own zoom of the suit can open or stay open while a camera owner has the view (it would zoom the owner's camera)
			name = "the suit's own zoom: a camera owner is a hard reason to close it (cameraowner), and the situation tells it",
			func = function()
				local Z = GryMod.SuitZoom
				local sit = {
					valid = true, alive = true, enabled = true, quickmenu = false, pause = false, console = false, cursor = false, focusPanel = false, typing = false,
					focus = true, malfunction = false, vehicle = false, thirdperson = false, viewother = false, observer = 0, frozen = false, water = 0,
					weapon = nil, entered = nil, viewAge = 0
				}

				expect(Z.Reason(sit, false)).to.beNil()

				sit.cameraowner = true
				expect(Z.Reason(sit, false)).to.equal("cameraowner")
				expect(Z.Reason(sit, true)).to.equal("cameraowner")
				expect(Z.HARD.cameraowner).to.beTrue()

				owner("test.camera", function() return true end)
				expect(Z.Read({}).cameraowner).to.beTrue()
				API.RemoveCameraOwner("test.camera")
				expect(Z.Read({}).cameraowner).to.beFalse()
			end
		}
	}
}
