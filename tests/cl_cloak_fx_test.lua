-- Tests of the camouflage rendering (cl_cloak_fx.lua), GLuaTest format, client realm: the curve of the transition,
-- how visible a camouflaged player is (a function of the speed), the transition's screen effect, and the draw hooks
-- (which players get the material, and that the render state is always put back). Nothing is drawn: the render
-- calls are replaced by recorders (and put back after each case).

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

-- a fake player: only what the hooks ask for
local function fakePlayer(speed)
	local ply = {draws = 0, center = Vector(300, 0, 0)}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:Alive() return true end
	function ply:IsDormant() return false end
	function ply:WorldSpaceCenter() return self.center end
	function ply:ShouldDrawLocalPlayer() return true end
	function ply:DrawShadow(on) self.shadow = on end
	function ply:GetViewModel() return NULL end
	function ply:GetNWBool() return false end
	function ply:EntIndex() return 99 end
	function ply:GetVelocity() return Vector(speed or 0, 0, 0) end
	function ply:DrawModel() self.draws = self.draws + 1 end
	function ply:GetActiveWeapon() return NULL end

	return ply
end

-- the render state the hooks touch, as a log
local function recordRender()
	local log = {override = {}, blend = {}, color = {}, refreshed = 0}

	stub(render, "UpdateRefractTexture", function() log.refreshed = log.refreshed + 1 end)

	stub(render, "MaterialOverride", function(mat) log.override[#log.override + 1] = mat or false end)
	stub(render, "SetBlend", function(value) log.blend[#log.blend + 1] = value end)
	stub(render, "SetColorModulation", function(r, g, b) log.color[#log.color + 1] = {r, g, b} end)
	stub(render, "GetBlend", function() return 1 end)
	stub(render, "GetColorModulation", function() return 1, 1, 1 end)

	return log
end

local function setState(ply, amount, speed)
	local F = GryMod.CloakFX
	F.States[ply] = {amount = amount, speed = speed or 0, cloaked = amount > 0}
end

-- what the engine calls after the translucent things
local function translucent()
	-- the camera is at the origin and looks along x
	stub(_G, "EyePos", function() return Vector(0, 0, 0) end)
	stub(_G, "EyeVector", function() return Vector(1, 0, 0) end)
	hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, false)
end

local function leftClean(log)
	-- the last override is nil (false in the log) and the last blend is back to 1
	return log.override[#log.override] == false and (log.blend[#log.blend] == nil or log.blend[#log.blend] == 1)
end

return {
	groupName = "GryMod camouflage rendering",
	beforeEach = function(state)
		-- the draw hooks only exist while somebody is camouflaged: the cases call them directly
		GryMod.CloakFX.SetDrawHooks(true)
	end,
	afterAll = function(state)
		GryMod.CloakFX.SetDrawHooks(next(GryMod.CloakFX.States) ~= nil)
	end,
	afterEach = function(state)
		restore()

		-- emptied in place: the module keeps its own reference to the table
		if GryMod.CloakFX then
			for ply in pairs(GryMod.CloakFX.States) do
				GryMod.CloakFX.States[ply] = nil
			end
		end
	end,
	cases = {
		{
			name = "the module exists and the effect is on by default",
			func = function(state)
				expect(GryMod.CloakFX).to.exist()
				local convar = GetConVar("gry_cloak_fx")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
			end
		},
		{
			name = "Step moves the level towards the target at the pace of the transition, and stops at the ends",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.Step(0, true, F.ActivateTime / 2)).to.aboutEqual(0.5, 0.001)
				expect(F.Step(0.9, true, 10)).to.equal(1)
				expect(F.Step(1, false, F.DeactivateTime / 2)).to.aboutEqual(0.5, 0.001)
				expect(F.Step(0.1, false, 10)).to.equal(0)
				expect(F.Step(0, false, 1)).to.equal(0)
				expect(F.Step(1, true, 1)).to.equal(1)
			end
		},
		{
			name = "the transition lasts a bit under a second, and is quicker to leave than to enter",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.ActivateTime).to.beBetween(0.5, 1.2)
				expect(F.DeactivateTime).to.beBetween(0.3, F.ActivateTime)
			end
		},
		{
			name = "Ease is 0 and 1 at the ends, smooth in between, and never goes backwards",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.Ease(0)).to.equal(0)
				expect(F.Ease(1)).to.equal(1)
				expect(F.Ease(0.5)).to.aboutEqual(0.5, 0.001)
				expect(F.Ease(0.1)).to.beLessThan(0.1) -- slow start

				local last = 0

				for i = 1, 20 do
					local v = F.Ease(i / 20)
					expect(v >= last).to.beTrue()
					last = v
				end

				expect(F.Ease(-1)).to.equal(0)
				expect(F.Ease(2)).to.equal(1)
			end
		},
		{
			name = "a player who is not camouflaged is drawn as usual: no distortion, fully opaque, no sparks",
			func = function(state)
				local refract, base, spark = GryMod.CloakFX.Visibility(0, 600)
				expect(refract).to.equal(0)
				expect(base).to.equal(1)
				expect(spark).to.equal(0)
			end
		},
		{
			name = "a camouflaged player standing still is nearly invisible: faint outline, no sparks",
			func = function(state)
				local refract, base, spark = GryMod.CloakFX.Visibility(1, 0)
				expect(base).to.beBetween(0.01, 0.08)
				expect(refract).to.beGreaterThan(0)
				expect(spark).to.equal(0)
			end
		},
		{
			name = "the faster a camouflaged player moves, the more visible, up to a ceiling",
			func = function(state)
				local F = GryMod.CloakFX
				local _, still, sparkStill = F.Visibility(1, 0)
				local refractStill = F.Visibility(1, 0)
				local refractWalk, walk, sparkWalk = F.Visibility(1, 200)
				local refractRun, run, sparkRun = F.Visibility(1, 400)
				local _, fast = F.Visibility(1, 4000)

				expect(walk > still).to.beTrue()
				expect(run > walk).to.beTrue()
				expect(refractWalk > refractStill).to.beTrue()
				expect(refractRun >= refractWalk).to.beTrue()
				expect(sparkWalk > sparkStill).to.beTrue()
				expect(sparkRun >= sparkWalk).to.beTrue()
				expect(fast).to.aboutEqual(select(2, F.Visibility(1, 800)), 0.0001) -- the effect saturates
				expect(fast).to.beLessThan(0.5) -- still hard to see when moving
			end
		},
		{
			name = "in the middle of a transition the surface is distorted more than when fully camouflaged, and sparks fly",
			func = function(state)
				local F = GryMod.CloakFX
				local refractFull = F.Visibility(1, 0)
				local refractMid, _, sparkMid = F.Visibility(0.5, 0)
				expect(refractMid > refractFull).to.beTrue()
				expect(sparkMid).to.beGreaterThan(0.3)
			end
		},
		{
			name = "the visibility never leaves its ranges, whatever the level and the speed",
			func = function(state)
				local F = GryMod.CloakFX

				for _, amount in ipairs({-3, 0, 0.01, 0.25, 0.5, 0.75, 0.99, 1, 4}) do
					for _, speed in ipairs({-50, 0, 100, 250, 600, 99999}) do
						local refract, base, spark = F.Visibility(amount, speed)
						expect(refract >= 0).to.beTrue()
						expect(base >= 0 and base <= 1).to.beTrue()
						expect(spark >= 0 and spark <= 1).to.beTrue()
					end
				end
			end
		},
		{
			name = "the opacity of the plain model only goes down as the level goes up",
			func = function(state)
				local F = GryMod.CloakFX
				local last = 2

				for i = 0, 20 do
					local _, base = F.Visibility(i / 20, 300)
					expect(base <= last).to.beTrue()
					last = base
				end
			end
		},
		{
			name = "SmoothSpeed follows the real speed with a delay, so the sparks do not flicker at every step",
			func = function(state)
				local F = GryMod.CloakFX
				local v = F.SmoothSpeed(0, 400, 0.016)
				expect(v > 0 and v < 400).to.beTrue()
				expect(F.SmoothSpeed(0, 400, 10)).to.aboutEqual(400, 1)
				expect(F.SmoothSpeed(400, 0, 0)).to.equal(400)
			end
		},
		{
			name = "the screen effect of the activation follows the original's graph: grey and fringes for under two seconds",
			func = function(state)
				local F = GryMod.CloakFX
				local sat0, chroma0 = F.ScreenFx(0)
				local satMid, chromaMid = F.ScreenFx(0.7)
				local satEnd, chromaEnd = F.ScreenFx(1.7)
				expect(sat0).to.equal(1)
				expect(chroma0).to.equal(0)
				expect(satMid).to.aboutEqual(0.5, 0.01)
				expect(chromaMid).to.aboutEqual(0.4, 0.01)
				expect(satEnd).to.aboutEqual(1, 0.01)
				expect(chromaEnd).to.aboutEqual(0, 0.01)
				expect(F.ScreenFxDuration).to.aboutEqual(1.7, 0.01)
				expect(F.ScreenFx(5)).to.equal(1)
				expect(select(2, F.ScreenFx(5))).to.equal(0)
				expect(select(2, F.ScreenFx(-1))).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: a player who is not camouflaged is left to the engine, and nothing is drawn for him",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				expect(hook.GetTable().PrePlayerDraw.GryCloakFX(ply)).to.beNil()
				translucent()
				expect(#log.override).to.equal(0)
				expect(#log.blend).to.equal(0)
				expect(log.refreshed).to.equal(0)
				expect(ply.draws).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: the engine does not draw a camouflaged player, he is drawn later through the refraction material",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 0)
				expect(hook.GetTable().PrePlayerDraw.GryCloakFX(ply)).to.beTrue()
				translucent()
				expect(ply.draws).to.beGreaterThan(0)
				expect(log.override[1]).to.exist() -- the material
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: fully camouflaged and still, only the refraction is drawn, not the plain model",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 0)
				translucent()
				expect(ply.draws).to.equal(1)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: half way through the transition the plain model is drawn over it, part transparent",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 0.4, 0)
				translucent()
				expect(ply.draws).to.equal(3) -- refraction, sparks (the change has them), plain model
				local lowest = 1

				for _, v in ipairs(log.blend) do
					lowest = math.min(lowest, v)
				end

				expect(lowest).to.beBetween(0.1, 0.99)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: moving fast, the sparks are drawn too",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 400)
				translucent()
				expect(ply.draws).to.equal(3) -- refraction, sparks, plain model
				expect(#log.color).to.beGreaterThan(0)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: the screen is copied once per frame, whatever the number of camouflaged players",
			func = function(state)
				local log = recordRender()
				local a, b = fakePlayer(0), fakePlayer(0)
				setState(a, 1, 0)
				setState(b, 1, 0)
				translucent()
				expect(a.draws + b.draws).to.equal(2)
				expect(log.refreshed).to.equal(1)
			end
		},
		{
			name = "PlayerDraw: nothing in the depth or the sky passes",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 0)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(true, false, false)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, true, false)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, true)
				expect(ply.draws).to.equal(0)
				expect(#log.override).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: nothing in a render target (the water's reflection and refraction, cameras)",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 0)
				stub(render, "GetRenderTarget", function() return {} end)
				translucent()
				expect(ply.draws).to.equal(0)
				expect(log.refreshed).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: the local player's own body is only drawn in third person",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				setState(me, 1, 0)
				local third = false
				function me:ShouldDrawLocalPlayer() return third end
				translucent()
				expect(me.draws).to.equal(0)
				third = true
				translucent()
				expect(me.draws).to.equal(1)
			end
		},
		{
			name = "PlayerDraw: a player behind the camera, or farther than the maximum distance, is not drawn",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local behind, far, near = fakePlayer(0), fakePlayer(0), fakePlayer(0)
				behind.center = Vector(-300, 0, 0)
				far.center = Vector(F.MaxDistance + 100, 0, 0)
				near.center = Vector(50, 0, 0)
				setState(behind, 1, 0)
				setState(far, 1, 0)
				setState(near, 1, 0)
				translucent()
				expect(behind.draws).to.equal(0)
				expect(far.draws).to.equal(0)
				expect(near.draws).to.equal(1)
			end
		},
		{
			name = "PlayerDraw: far away there are no sparks (a layer less), and no weapon",
			func = function(state)
				recordRender()
				local F = GryMod.CloakFX
				local near, far = fakePlayer(0), fakePlayer(0)
				local weapon = fakePlayer(0)
				function far:GetActiveWeapon() return weapon end
				far.center = Vector(F.DetailDistance + 100, 0, 0)
				setState(near, 1, 400) -- running: refraction, sparks, plain model
				setState(far, 1, 400)
				translucent()
				expect(near.draws).to.equal(3)
				expect(far.draws).to.equal(2)
				expect(weapon.draws).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: the weapon in the hand gets the refraction only",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				local weapon = fakePlayer(0)
				weapon.center = Vector(300, 0, 0)
				function ply:GetActiveWeapon() return weapon end
				setState(ply, 1, 400) -- running: sparks and the plain model on the body
				translucent()
				expect(ply.draws).to.equal(3)
				expect(weapon.draws).to.equal(1)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: with the effect off (gry_cloak_fx 0) the hooks do nothing: the old material does the job",
			func = function(state)
				local convar = GetConVar("gry_cloak_fx")
				local before = convar:GetString()
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1, 0)
				convar:SetString("0")
				local ok, err = pcall(function()
					expect(hook.GetTable().PrePlayerDraw.GryCloakFX(ply)).to.beNil()
					translucent()
				end)
				convar:SetString(before)
				assert(ok, err)
				expect(#log.override).to.equal(0)
				expect(ply.draws).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: a drawing that fails does not leave the material on for the next thing drawn",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				function ply:DrawModel() error("boom") end
				setState(ply, 0.5, 0)
				pcall(translucent)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "the draw hooks exist only while somebody is camouflaged: nobody, and the engine does not call them",
			func = function(state)
				local F = GryMod.CloakFX
				local events = {"PrePlayerDraw", "PostDrawTranslucentRenderables", "PreDrawViewModel", "PostDrawViewModel", "PreDrawPlayerHands", "PostDrawPlayerHands"}
				local ply = fakePlayer(0)
				local flag = true
				function ply:GetNWBool() return flag end
				stub(_G, "FrameTime", function() return 1 end)

				-- start from nothing
				F.SetDrawHooks(false)

				for _, event in ipairs(events) do
					expect(hook.GetTable()[event] == nil or hook.GetTable()[event].GryCloakFX == nil).to.beTrue()
				end

				F.Update(ply)

				for _, event in ipairs(events) do
					expect(hook.GetTable()[event].GryCloakFX).to.exist()
				end

				flag = false

				for i = 1, 3 do
					F.Update(ply)
				end

				for _, event in ipairs(events) do
					expect(hook.GetTable()[event] == nil or hook.GetTable()[event].GryCloakFX == nil).to.beTrue()
				end
			end
		},
		{
			name = "Update: a camouflaged player casts no shadow, and gets it back when plain again",
			func = function(state)
				local F = GryMod.CloakFX
				local ply = fakePlayer(0)
				local flag = true
				function ply:GetNWBool() return flag end
				stub(_G, "FrameTime", function() return 1 end)
				F.Update(ply)
				expect(ply.shadow).to.equal(false)
				flag = false

				for i = 1, 3 do
					F.Update(ply)
				end

				expect(ply.shadow).to.equal(true)
			end
		},
		{
			name = "the view model and the hands: material for the local player's camouflage only, and put back",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end

				-- not camouflaged: nothing
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				expect(#log.override).to.equal(0)

				-- camouflaged: the material, then nil
				setState(me, 1, 0)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(log.override[#log.override]).to.exist()
				expect(log.refreshed).to.equal(1) -- the screen is copied for the refraction
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(leftClean(log)).to.beTrue()

				log.override = {}
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				expect(log.override[#log.override]).to.exist()
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
				expect(F.States[me]).to.exist()
			end
		},
		{
			name = "Update: the level of a player follows the server's switch, and a player who is not seen camouflaged costs nothing",
			func = function(state)
				local F = GryMod.CloakFX
				local ply = fakePlayer(0)
				local flag = false
				function ply:GetNWBool(name) return name == "GryCloak" and flag end
				stub(_G, "FrameTime", function() return 0.1 end)

				F.Update(ply) -- never camouflaged: no state is made
				expect(F.States[ply]).to.beNil()

				flag = true
				F.Update(ply)
				expect(F.States[ply]).to.exist()
				expect(F.States[ply].amount).to.aboutEqual(0.1 / F.ActivateTime, 0.001)

				flag = false

				for i = 1, 30 do
					F.Update(ply)
				end

				expect(F.States[ply]).to.beNil() -- back to plain: forgotten
			end
		},
	}
}
