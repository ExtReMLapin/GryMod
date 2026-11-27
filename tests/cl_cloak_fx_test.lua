-- Tests of the camouflage rendering (cl_cloak_fx.lua), GLuaTest format, client realm: the curve of the transition,
-- how visible a camouflaged player is (a function of the level), the transition's screen effect, and the draw hooks
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

-- the log of the render calls being recorded (recordRender), read by the fake entities' DrawModel
local renderLog

-- The minimap's capture (lua/grymod/client/minimap/capture.lua) renders the map from above inside a render hook: the post effects must stay out of it.
-- The cases that need it say so through this stand-in, put back after each case (also when the case failed).
local realIsCapturing

local function standInCapturing(value)
	local capture = GryMod.Minimap.Capture

	if realIsCapturing == nil then
		realIsCapturing = capture.IsCapturing
	end

	capture.IsCapturing = function() return value end
end

local function putBackCapturing()
	if realIsCapturing ~= nil then
		pcall(function() GryMod.Minimap.Capture.IsCapturing = realIsCapturing end)
		realIsCapturing = nil
	end
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
	function ply:GetNW2Bool() return false end
	function ply:GetNW2Float(name, default) return default end -- the server's activation time is not there: F.StartAmount starts from the plain model
	function ply:EntIndex() return 99 end
	function ply:GetVelocity() return Vector(speed or 0, 0, 0) end
	function ply:GetModel() return "" end -- no world model to copy: the weapon itself is drawn (cases of the proxy give one)
	function ply:DrawModel()
		self.draws = self.draws + 1

		if renderLog then
			renderLog.drawn[#renderLog.drawn + 1] = {ent = self, material = renderLog.material, blend = renderLog.blendNow}
		end
	end
	function ply:GetActiveWeapon() return NULL end

	return ply
end

-- the render state the hooks touch, as a log
local function recordRender()
	local log = {override = {}, blend = {}, color = {}, refreshed = 0, drawn = {}, blendNow = 1}
	renderLog = log

	stub(render, "UpdateRefractTexture", function() log.refreshed = log.refreshed + 1 end)
	log.screenCopies = 0
	stub(render, "UpdateScreenEffectTexture", function() log.screenCopies = log.screenCopies + 1 end)

	stub(render, "MaterialOverride", function(mat)
		log.override[#log.override + 1] = mat or false
		log.material = mat
	end)
	stub(render, "SetBlend", function(value)
		log.blend[#log.blend + 1] = value
		log.blendNow = value
	end)
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


-- The real players' states are the game's own (somebody is camouflaged while the cases run, in a game that is being played): they are set aside before
-- each case and put back after it, so that running these cases never makes a real camouflage fall. The cases only ever see their own fake players.
local parked = {}

local function parkStates()
	local F = GryMod.CloakFX
	parked = {}

	if not F then return end

	for ply, s in pairs(F.States) do
		parked[ply] = s
	end

	for ply in pairs(parked) do
		F.States[ply] = nil
	end
end

local function unparkStates()
	local F = GryMod.CloakFX

	if not F then return end

	for ply in pairs(F.States) do
		F.States[ply] = nil
	end

	for ply, s in pairs(parked) do
		if IsValid(ply) then
			F.States[ply] = s
		end
	end

	parked = {}
end

return {
	groupName = "GryMod camouflage rendering",
	beforeEach = function(state)
		parkStates()

		-- the draw hooks only exist while somebody is camouflaged: the cases call them directly
		GryMod.CloakFX.SetDrawHooks(true)

		-- the scan lines (cl_cloak_lines.lua, tested in cl_cloak_lines_test.lua) need a real entity's box and the real stencil:
		-- the fake players here are only drawn through the layers
		stub(GryMod.CloakFX.Lines, "Draw", function() return true end)

		-- the pixel shader (cl_cloak_shader.lua, tested in cl_cloak_shader_test.lua) is not in use unless a case turns it on: the cases above
		-- are about the older layers, which stay as the fallback
		stub(GryMod.CloakFX.Shader, "Active", function() return false end)

		-- the refraction layer's own pixel shader (cl_cloak_refract.lua) likewise: the cases above are about the older Refract material
		stub(GryMod.CloakFX.Refract, "Active", function() return false end)
	end,
	afterAll = function(state)
		GryMod.CloakFX.SetDrawHooks(next(GryMod.CloakFX.States) ~= nil)
	end,
	afterEach = function(state)
		putBackCapturing()
		restore()
		renderLog = nil

		-- the cases' fake players go, the real ones come back (emptied in place: the module keeps its own reference to the table)
		unparkStates()
		GryMod.CloakFX.SetDrawHooks(next(GryMod.CloakFX.States) ~= nil) -- a case may have put them away: the real players' hooks come back with their states
	end,
	cases = {
		{
			name = "the module exists and the effect is on by default",
			func = function(state)
				expect(GryMod.CloakFX).to.exist()
				local convar = GetConVar("gry_cloak_fx")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				local transition = GetConVar("gry_cloak_transition")
				expect(transition ~= nil).to.beTrue()
				expect(transition:GetDefault()).to.equal("1")
				expect(GryMod.CloakFX.TransitionEnabled()).to.beTrue()
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
			name = "with gry_cloak_transition 0 the level goes to the switch at once, in both directions",
			func = function(state)
				local F = GryMod.CloakFX
				local convar = GetConVar("gry_cloak_transition")
				local before = convar:GetString()
				convar:SetString("0")
				local ok, err = pcall(function()
					expect(F.TransitionEnabled()).to.beFalse()
					expect(F.Step(0, true, 0.016)).to.equal(1)
					expect(F.Step(1, false, 0.016)).to.equal(0)
					expect(F.Step(0.4, true, 0.016)).to.equal(1)
				end)
				convar:SetString(before)
				assert(ok, err)
			end
		},
		{
			name = "the sparks curve is the original's transition texture: 0 at the start, full at about a tenth, then slowly down",
			func = function(state)
				local F = GryMod.CloakFX
				-- read in textures/defaults/palette/cloak_transition.dds (alpha, 256 samples): 0, 79 at 8, 191 at 16, 255 from 24 to 40, 55 at the end
				expect(F.TransitionCurve(0)).to.equal(0)
				expect(F.TransitionCurve(8 / 255)).to.aboutEqual(79 / 255, 0.01)
				expect(F.TransitionCurve(16 / 255)).to.aboutEqual(191 / 255, 0.01)
				expect(F.TransitionCurve(0.11)).to.aboutEqual(1, 0.01)
				expect(F.TransitionCurve(1)).to.aboutEqual(55 / 255, 0.01)
				expect(F.TransitionCurve(-1)).to.equal(0)
				expect(F.TransitionCurve(7)).to.aboutEqual(55 / 255, 0.01)
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
			name = "moving changes neither the plain model's opacity nor the bend: only the electricity, faintly (3 % at full speed) once the change is done; in the change it is the change's own, whatever the speed",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.MovingSpark).to.equal(0.03)
				expect(F.MovingVisibility).to.beNil()

				local refractStill, baseStill, sparkStill = F.Visibility(1, 0)
				local refractRun, baseRun, sparkRun = F.Visibility(1, F.FullSpeed)
				expect(refractRun).to.equal(refractStill)
				expect(baseRun).to.equal(baseStill)
				expect(sparkStill).to.equal(0)
				expect(sparkRun).to.aboutEqual(0.03, 0.000001)

				-- half the speed, half the strength; a higher speed is capped; a negative one counts for nothing
				expect(select(3, F.Visibility(1, F.FullSpeed / 2))).to.aboutEqual(0.015, 0.000001)
				expect(select(3, F.Visibility(1, 99999))).to.aboutEqual(0.03, 0.000001)
				expect(select(3, F.Visibility(1, -50))).to.equal(0)
				expect(select(3, F.Visibility(1))).to.equal(0)

				-- in the change: the change's own intensity, the same whether he moves or not (not added to)
				for _, speed in ipairs({0, 150, 300, 400}) do
					local refract, base, spark = F.Visibility(0.5, speed)
					expect(spark).to.equal(F.SparkRest)
					expect(refract).to.equal((F.Visibility(0.5, 0)))
					expect(base).to.equal(select(2, F.Visibility(0.5, 0)))
				end

				-- a plain player stays plain
				local refract, base, spark = F.Visibility(0, 400)
				expect(refract).to.equal(0)
				expect(base).to.equal(1)
				expect(spark).to.equal(0)
			end
		},
		{
			name = "SparkStrength takes the speed: the change's intensity in the change, the faint motion once done, nothing for a plain player; TransitionSpark (the scan lines) is the change's alone",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.SparkStrength(0, 300)).to.equal(0)
				expect(F.SparkStrength(0.5, 0)).to.equal(F.SparkRest)
				expect(F.SparkStrength(0.5, 300)).to.equal(F.SparkRest)
				expect(F.SparkStrength(1, 0)).to.equal(0)
				expect(F.SparkStrength(1, 300)).to.aboutEqual(0.03, 0.000001)
				expect(F.SparkStrength(1)).to.equal(0)

				expect(F.TransitionSpark(0.5)).to.equal(F.SparkRest)
				expect(F.TransitionSpark(1)).to.equal(0)
				expect(F.TransitionSpark(0)).to.equal(0)
			end
		},
		{
			name = "SmoothSpeed follows the real speed with a short delay, so that the faint sparks of a walk do not flicker at every step",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.SmoothSpeed(0, 300, 0)).to.equal(0)
				expect(F.SmoothSpeed(0, 300, F.SpeedDelay)).to.aboutEqual(300 * (1 - math.exp(-1)), 0.001)
				expect(F.SmoothSpeed(300, 300, 0.1)).to.aboutEqual(300, 0.0001)
				expect(F.SmoothSpeed(300, 0, 10)).to.aboutEqual(0, 0.01)
			end
		},
		{
			name = "in the middle of a transition the surface is distorted more than when fully camouflaged, and the faint sparks are there",
			func = function(state)
				local F = GryMod.CloakFX
				local refractFull = F.Visibility(1)
				local refractMid, _, sparkMid = F.Visibility(0.5)
				expect(refractMid > refractFull).to.beTrue()
				expect(sparkMid).to.equal(F.SparkRest)
			end
		},
		{
			name = "the surface is bent most at the start of the change and less and less after it (the original's bump scale 2.75 down to 0.25)",
			func = function(state)
				local F = GryMod.CloakFX
				local last = math.huge

				for i = 1, 20 do
					local refract = F.Visibility(i / 20)
					expect(refract <= last).to.beTrue()
					last = refract
				end

				expect(F.Visibility(0.05) > 3 * F.Visibility(1)).to.beTrue()
			end
		},
		{
			name = "the sparks: only while the cloak goes in or out, always at the owner's chosen intensity, 15 % (the original's still value was about 5 %, too faint to see); nothing when plain, nothing once done, moving or not",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.SparkRest).to.equal(0.15)
				expect(F.SparkStrength(0)).to.equal(0)
				expect(F.SparkStrength(1)).to.equal(0)
				expect(F.SparkStrength(-1)).to.equal(0)
				expect(F.SparkStrength(2)).to.equal(0)

				-- the same intensity at every level of the change: not the flash of its start, nor of its end
				for _, level in ipairs({0.001, 0.05, 0.1, 0.3, 0.5, 0.8, 0.95, 0.999}) do
					expect(F.SparkStrength(level)).to.equal(F.SparkRest)
				end

				-- what the layers' rules hand out is the same number
				local _, _, spark = F.Visibility(0.5)
				expect(spark).to.equal(F.SparkRest)
				_, _, spark = F.Visibility(1)
				expect(spark).to.equal(0)
			end
		},
		{
			name = "the plain model fades out linearly with the level, as the original's layer alpha (0.8 x level)",
			func = function(state)
				local F = GryMod.CloakFX
				local _, quarter = F.Visibility(0.25)
				local _, half = F.Visibility(0.5)
				local _, full = F.Visibility(1)
				expect(half).to.aboutEqual(1 - 0.5 * (1 - full), 0.001)
				expect(quarter).to.aboutEqual(1 - 0.25 * (1 - full), 0.001)
			end
		},
		{
			name = "the visibility never leaves its ranges, whatever the level and the speed",
			func = function(state)
				local F = GryMod.CloakFX

				for _, amount in ipairs({-3, 0, 0.01, 0.25, 0.5, 0.75, 0.99, 1, 4}) do
					for _, speed in ipairs({-50, 0, 100, 250, 600, 99999}) do
						local refract, base, spark = F.Visibility(amount)
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
					local _, base = F.Visibility(i / 20)
					expect(base <= last).to.beTrue()
					last = base
				end
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
				setState(ply, 1)
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
				setState(ply, 1)
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
				setState(ply, 0.4)
				translucent()
				expect(ply.draws).to.equal(3) -- refraction, sparks (the change has them), plain model
				local lowest = 1

				for _, v in ipairs(log.blend) do
					lowest = math.min(lowest, v)
				end

				-- the plain model's own blend is somewhere between all and nothing (the older sparks layer's is the faint rest)
				local found = false

				for _, v in ipairs(log.blend) do
					if v > 0.1 and v < 0.99 then found = true end
				end

				expect(found).to.beTrue()
				expect(lowest <= GryMod.CloakFX.SparkRest).to.beTrue() -- the older sparks layer is never stronger than the faint rest
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: in the change the sparks are drawn (the older outline layer), once the change is done they are not, still or moving",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 0.5)
				translucent()
				expect(ply.draws).to.equal(3) -- refraction, outline, plain model
				expect(#log.color).to.beGreaterThan(0)
				expect(leftClean(log)).to.beTrue()

				-- done and standing: the refraction only, no sparks; done and running: the faint sparks of a walk, here the older outline layer (3 %)
				GryMod.CloakFX.States[ply] = nil
				local still = fakePlayer(0)
				setState(still, 1)
				translucent()
				expect(still.draws).to.equal(1) -- the refraction only

				local running = fakePlayer(400)
				setState(running, 1, 400)
				translucent()
				expect(running.draws).to.equal(2) -- the refraction and the faint outline; the plain model is still nearly gone
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: the screen is copied once per frame, whatever the number of camouflaged players",
			func = function(state)
				local log = recordRender()
				local a, b = fakePlayer(0), fakePlayer(0)
				setState(a, 1)
				setState(b, 1)
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
				setState(ply, 1)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(true, false, false)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, true, false)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, true)
				expect(ply.draws).to.equal(0)
				expect(#log.override).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: in a render target (a mirror, the water's reflection, a camera) the camouflaged player is drawn too, not missing",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1)
				stub(render, "GetRenderTarget", function() return {} end)
				-- the engine's own draw is still switched off (PrePlayerDraw), so the reflection would show nothing
				-- if the layers were not drawn from here
				expect(hook.GetTable().PrePlayerDraw.GryCloakFX(ply)).to.beTrue()
				translucent()
				expect(ply.draws).to.beGreaterThan(0)
				expect(log.drawn[1].material).to.exist() -- through the refraction material
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: in a render target the layers follow the same curves as in the main view (same opacity)",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 0.4)
				stub(render, "GetRenderTarget", function() return {} end)
				translucent()
				local _, base = F.Visibility(0.4)
				expect(ply.draws).to.equal(3) -- refraction, sparks, plain model: as in the main view
				expect(log.blend[#log.blend - 1]).to.aboutEqual(base, 0.001) -- the plain model's opacity, then the reset
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "PlayerDraw: in a render target a drawing that fails does not leave the material or the opacity on",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				function ply:DrawModel() error("boom") end
				setState(ply, 0.5)
				stub(render, "GetRenderTarget", function() return {} end)
				pcall(translucent)
				expect(leftClean(log)).to.beTrue()
				expect(log.blendNow).to.equal(1)
			end
		},
		{
			name = "PlayerDraw: the local player's own body is only drawn in third person",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				setState(me, 1)
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
				setState(behind, 1)
				setState(far, 1)
				setState(near, 1)
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
				setState(near, 0.5) -- in the change: refraction, sparks, plain model
				setState(far, 0.5)
				translucent()
				expect(near.draws).to.equal(3)
				expect(far.draws).to.equal(2)
				expect(weapon.draws).to.equal(0)
			end
		},
		{
			name = "PlayerDraw: the weapon in the hand follows the body: the refraction and the plain model at the same opacity, no sparks",
			func = function(state)
				local log = recordRender()
				local ply = fakePlayer(0)
				local weapon = fakePlayer(0)
				weapon.center = Vector(300, 0, 0)
				function ply:GetActiveWeapon() return weapon end
				setState(ply, 0.5) -- in the change: sparks and the plain model on the body
				translucent()
				expect(ply.draws).to.equal(3)
				expect(weapon.draws).to.equal(2) -- refraction, plain model (no sparks)
				expect(leftClean(log)).to.beTrue()

				-- once done, only the refraction (the plain model is not worth drawing)
				weapon.draws = 0
				setState(ply, 1)
				translucent()
				expect(weapon.draws).to.equal(1)
			end
		},
		{
			name = "WeaponProxy: the weapon the server hides (EF_NODRAW: the engine then refuses to draw it, whoever asks) is drawn through a client model of its world model, bone-merged on the player, made once and kept while the weapon is the same, replaced when it changes, gone with the player's state",
			func = function(state)
				local F = GryMod.CloakFX
				local made, removed = {}, {}

				stub(_G, "ClientsideModel", function(model)
					local ent = {model = model, effects = 0}
					function ent:IsValid() return not self.gone end
					function ent:SetNoDraw(on) self.nodraw = on end
					function ent:SetParent(parent) self.parent = parent end
					function ent:AddEffects(flags) self.effects = bit.bor(self.effects, flags) end
					function ent:SetSkin(skin) self.skin = skin end
					function ent:SetBodygroup(group, value) self.groups = self.groups or {} self.groups[group] = value end
					function ent:Remove() self.gone = true removed[#removed + 1] = self end
					made[#made + 1] = ent

					return ent
				end)

				local ply = fakePlayer(0)
				local function weaponOf(model, skin)
					local w = fakePlayer(0)
					function w:GetModel() return model end
					function w:GetSkin() return skin or 0 end
					function w:GetNumBodyGroups() return 2 end
					function w:GetBodygroup(i) return i + 1 end

					return w
				end

				local a = weaponOf("models/weapons/w_pistol.mdl", 1)
				local proxy = F.WeaponProxy(ply, a)
				expect(proxy ~= nil).to.beTrue()
				expect(#made).to.equal(1)
				expect(proxy.model).to.equal("models/weapons/w_pistol.mdl")
				expect(proxy.nodraw).to.beTrue()
				expect(proxy.parent).to.equal(ply)
				expect(bit.band(proxy.effects, EF_BONEMERGE) ~= 0).to.beTrue()
				expect(proxy.skin).to.equal(1)
				expect(proxy.groups[0]).to.equal(1)
				expect(proxy.groups[1]).to.equal(2)

				-- the same weapon (or another of the same model) next frame: the same proxy
				expect(F.WeaponProxy(ply, a)).to.equal(proxy)
				expect(F.WeaponProxy(ply, weaponOf("models/weapons/w_pistol.mdl"))).to.equal(proxy)
				expect(#made).to.equal(1)

				-- another model: the old one is removed, a new one is made
				local other = F.WeaponProxy(ply, weaponOf("models/weapons/w_crossbow.mdl"))
				expect(other ~= proxy).to.beTrue()
				expect(#made).to.equal(2)
				expect(removed[1]).to.equal(proxy)

				-- no world model (or no weapon): nothing to draw through, and no proxy is kept
				expect(F.WeaponProxy(ply, weaponOf(""))).to.beNil()
				expect(removed[2]).to.equal(other)
				expect(F.WeaponProxy(ply, NULL)).to.beNil()

				-- ClearWeaponProxy takes it away, once
				local third = F.WeaponProxy(ply, weaponOf("models/weapons/w_smg1.mdl"))
				F.ClearWeaponProxy(ply)
				expect(third.gone).to.beTrue()
				F.ClearWeaponProxy(ply)
				expect(#removed).to.equal(3)
			end
		},
		{
			name = "PlayerDraw: the weapon is drawn through its proxy when there is one (the real one is not drawn), with the shader's sparks too; and the proxy goes when the player's state does",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local ply = fakePlayer(0)
				local weapon, proxy = fakePlayer(0), fakePlayer(0)
				weapon.center, proxy.center = Vector(300, 0, 0), Vector(300, 0, 0)
				function ply:GetActiveWeapon() return weapon end
				stub(F, "WeaponProxy", function(p, w) return proxy end)

				setState(ply, 0.5)
				translucent()
				expect(proxy.draws).to.equal(2) -- refraction, plain model
				expect(weapon.draws).to.equal(0)
				expect(leftClean(log)).to.beTrue()

				-- the sparks of the shader go on the proxy as well
				stub(F.Shader, "Active", function() return true end)
				local sparked = {}
				stub(F.Shader, "Draw", function(ent, strength) sparked[ent] = strength return true end)
				translucent()
				expect(sparked[proxy]).to.equal(F.SparkRest)
				expect(sparked[weapon]).to.beNil()

				-- when the player is plain again the proxy is taken away
				local cleared = {}
				stub(F, "ClearWeaponProxy", function(p) cleared[#cleared + 1] = p end)
				function ply:GetNW2Bool() return false end
				stub(_G, "FrameTime", function() return 10 end)
				F.Update(ply)
				expect(cleared[1]).to.equal(ply)
			end
		},
		{
			name = "DrawPhysgunBeam: the physgun draws its own glow sprites and beam (through this hook, which nothing drawn over the weapon can cover: a blue patch stayed in the camouflaged hand), so they are hidden while its owner is camouflaged, for whoever looks; nothing for a plain player, or with gry_cloak_fx 0",
			func = function(state)
				local F = GryMod.CloakFX
				local fn = hook.GetTable().DrawPhysgunBeam and hook.GetTable().DrawPhysgunBeam.GryCloakFX
				expect(fn).to.exist()

				local ply, other = fakePlayer(0), fakePlayer(0)
				local weapon = fakePlayer(0)

				-- no state: plain
				expect(fn(ply, weapon, false, NULL)).to.beNil()

				-- in the change and once done: hidden, whether he grabs something or not
				setState(ply, 0.4)
				expect(fn(ply, weapon, false, NULL)).to.beFalse()
				setState(ply, 1)
				expect(fn(ply, weapon, true, NULL)).to.beFalse()

				-- somebody else's physgun is not touched; a state that has gone back to nothing neither
				expect(fn(other, weapon, true, NULL)).to.beNil()
				setState(other, 0)
				expect(fn(other, weapon, true, NULL)).to.beNil()

				-- the old look (gry_cloak_fx 0): the hook does nothing
				stub(F, "Enabled", function() return false end)
				expect(fn(ply, weapon, true, NULL)).to.beNil()
			end
		},
		{
			name = "PlayerDraw: with the effect off (gry_cloak_fx 0) the hooks do nothing: the old material does the job",
			func = function(state)
				local convar = GetConVar("gry_cloak_fx")
				local before = convar:GetString()
				local log = recordRender()
				local ply = fakePlayer(0)
				setState(ply, 1)
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
				setState(ply, 0.5)
				pcall(translucent)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "the draw hooks exist only while somebody is camouflaged: nobody, and the engine does not call them",
			func = function(state)
				local F = GryMod.CloakFX
				local events = {"PrePlayerDraw", "PostDrawTranslucentRenderables", "PreDrawViewModel", "PostDrawViewModel", "PreDrawPlayerHands", "PostDrawPlayerHands", "DrawPhysgunBeam"}
				local ply = fakePlayer(0)
				local flag = true
				function ply:GetNW2Bool() return flag end
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
				function ply:GetNW2Bool() return flag end
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
			name = "the view model and the hands: nothing for a player who is not camouflaged, nor for another player",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end

				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(vm, vm, me, NULL)
				expect(#log.override).to.equal(0)
				expect(#log.blend).to.equal(0)
				expect(vm.draws).to.equal(0)

				-- somebody else is camouflaged: not the local view model
				local other = fakePlayer(0)
				setState(other, 1)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, other, NULL)
				expect(#log.blend).to.equal(0)
				expect(vm.draws).to.equal(0)
			end
		},
		{
			name = "first person, half way through the change: the refraction is drawn by hand, then the engine's own draw is made part transparent over it",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				setState(me, 0.4)

				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(1) -- the refraction
				expect(log.drawn[1].material).to.exist()
				expect(log.refreshed).to.equal(1) -- the screen is copied for it
				expect(log.override[#log.override]).to.equal(false) -- the engine's draw has no override
				local _, base = F.Visibility(0.4)
				expect(log.blend[#log.blend]).to.aboutEqual(base, 0.001) -- and is part transparent
				expect(base).to.beBetween(0.1, 0.99)

				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(2) -- the outline (sparks are strong in the change)
				expect(leftClean(log)).to.beTrue()
				expect(log.blendNow).to.equal(1)
			end
		},
		{
			name = "first person, at the very start of the change: the arms are still almost opaque (no jump to the refraction)",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				setState(me, 0.06)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(log.blend[#log.blend]).to.beGreaterThan(0.9)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "first person, at the very end of the change: with the plain model nearly all there the engine's draw stays OPAQUE (a translucent model is drawn flat and dark: the gun was a black shape for a frame)",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end

				-- a level whose plain opacity is above the threshold: no refraction, and no translucent draw
				setState(me, 0.003)
				local _, base = F.Visibility(0.003)
				expect(base >= F.NearlyPlain).to.beTrue()
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(0)
				for _, value in ipairs(log.blend) do
					expect(value).to.equal(1)
				end
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(leftClean(log)).to.beTrue()

				-- just under the threshold it is still the old way: the refraction, then the model part transparent
				vm.draws = 0 -- (the faint sparks layer of the first draw is not what is looked at here)
				setState(me, 0.03)
				_, base = F.Visibility(0.03)
				expect(base < F.NearlyPlain).to.beTrue()
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(1)
				expect(log.blend[#log.blend]).to.aboutEqual(base, 0.001)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "first person, camouflaged and still: only the refraction shows, the engine's draw is switched off, the state comes back at the end",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				setState(me, 1)

				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(1)
				expect(log.blend[#log.blend]).to.equal(0)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
				expect(log.blendNow).to.equal(1)
			end
		},
		{
			name = "first person: the hands get the same treatment as the view model, and the screen is copied once for both",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				function me:GetViewModel() return vm end
				setState(me, 0.5)

				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				expect(hands.draws).to.equal(1)
				expect(log.blend[#log.blend] < 1).to.beTrue()
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
				expect(log.blendNow).to.equal(1)
				expect(log.refreshed).to.equal(1)
			end
		},
		{
			-- fails when the models a weapon draws itself (the attachments of a weapon base: a sight, a laser) are left plain over a camouflaged weapon: the effect only knew
			-- the view model. They are asked at each frame (no list is kept: an attachment changed during the camouflage is the next frame's), they get the layers the view model
			-- gets, after it, and only with the view model (the hands are not the weapon's)
			name = "first person: the extra models of the weapon get the same layers as the view model, after it, asked at each frame; the hands do not draw them",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				local sight, laser = fakePlayer(0), fakePlayer(0)
				local gun = {IsValid = function() return true end}
				local attached = {sight}

				function me:GetViewModel() return vm end
				function me:GetActiveWeapon() return gun end
				setState(me, 0.5)
				GryMod.API.AddWeaponPartsProvider("test.cloak", function(_, out)
					for _, ent in ipairs(attached) do
						out[#out + 1] = ent
					end
				end)

				local ok, err = pcall(function()
					hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
					expect(sight.draws).to.equal(0) -- not before the weapon has drawn them
					hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)

					local sightDraws = sight.draws

					expect(sightDraws > 0).to.beTrue()
					expect(leftClean(log)).to.beTrue()

					-- the layers of the view model and of the part are the same kind: one layer drawn for the view model has one for the part
					expect(sightDraws).to.equal(vm.draws - 1) -- (the refraction of the Pre hook is the view model's alone)

					-- the player puts a laser on during the camouflage: the next frame draws it too, with no refresh of anything
					attached[#attached + 1] = laser
					hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
					hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
					expect(laser.draws > 0).to.beTrue()
					expect(sight.draws > sightDraws).to.beTrue()

					-- and takes the sight off: it is not drawn any more
					table.remove(attached, 1)

					local before = sight.draws

					hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
					hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
					expect(sight.draws).to.equal(before)

					-- the hands: no part drawn for them
					local lasers = laser.draws

					hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
					hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
					expect(laser.draws).to.equal(lasers)
					expect(leftClean(log)).to.beTrue()
				end)

				GryMod.API.RemoveWeaponPartsProvider("test.cloak")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when the first person layers cover everything of the weapon: the picture of a scope and the dot of a sight are what the player aims with and were blurred away
			-- (reported by the owner with a scope and a red dot sight on a TFA weapon). The layers are told to keep them for the view model, the hands and each part of the weapon
			name = "first person: the refraction and the sparks layers are told to keep the optics (the view model, the hands and the parts of the weapon)",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands, sight = fakePlayer(0), fakePlayer(0), fakePlayer(0)
				local gun = {IsValid = function() return true end}
				local refractCalls, shaderCalls = {}, {}

				function me:GetViewModel() return vm end
				function me:GetActiveWeapon() return gun end
				setState(me, 0.5)
				stub(F.Refract, "Active", function() return true end)
				stub(F.Refract, "Draw", function(ent, bump, alpha, draw, keep) refractCalls[#refractCalls + 1] = {ent = ent, keep = keep} return true end)
				stub(F.Shader, "Active", function() return true end)
				stub(F.Shader, "Draw", function(ent, strength, amount, draw, keep) shaderCalls[#shaderCalls + 1] = {ent = ent, keep = keep} return true end)
				GryMod.API.AddWeaponPartsProvider("test.cloak", function(_, out) out[#out + 1] = sight end)

				local ok, err = pcall(function()
					hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
					hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
					hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
					hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)

					-- the view model, its part, and the hands: all three, every time with keep
					expect(#refractCalls).to.equal(3)

					for _, call in ipairs(refractCalls) do
						expect(call.keep).to.beTrue()
					end

					expect(refractCalls[1].ent).to.equal(vm)
					expect(refractCalls[2].ent).to.equal(sight)
					expect(refractCalls[3].ent).to.equal(hands)

					for _, call in ipairs(shaderCalls) do
						expect(call.keep).to.beTrue()
					end

					expect(#shaderCalls > 0).to.beTrue()
				end)

				GryMod.API.RemoveWeaponPartsProvider("test.cloak")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when a part that cannot be drawn (a model that raises an error) leaves the material or the opacity on for what is drawn next, or stops the other parts
			name = "first person: a part whose drawing fails leaves nothing on and does not stop the next part",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, bad, good = fakePlayer(0), fakePlayer(0), fakePlayer(0)
				local gun = {IsValid = function() return true end}

				function bad:DrawModel() error("boom") end
				function me:GetViewModel() return vm end
				function me:GetActiveWeapon() return gun end
				setState(me, 0.5)
				GryMod.API.AddWeaponPartsProvider("test.cloak", function(_, out)
					out[#out + 1] = bad
					out[#out + 1] = good
				end)

				local ok, err = pcall(function()
					hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
					expect(pcall(hook.GetTable().PostDrawViewModel.GryCloakFX, vm, me, NULL)).to.beTrue()
					expect(good.draws > 0).to.beTrue()
					expect(leftClean(log)).to.beTrue()
					expect(log.blendNow).to.equal(1)
				end)

				GryMod.API.RemoveWeaponPartsProvider("test.cloak")

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "first person: a drawing that fails does not leave the material or the opacity on",
			func = function(state)
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function vm:DrawModel() error("boom") end
				function me:GetViewModel() return vm end
				setState(me, 0.5)
				pcall(hook.GetTable().PreDrawViewModel.GryCloakFX, vm, me, NULL)
				pcall(hook.GetTable().PostDrawViewModel.GryCloakFX, vm, me, NULL)
				expect(leftClean(log)).to.beTrue()
				expect(log.blendNow).to.equal(1)
			end
		},
		{
			name = "first person: with the transition off the arms go to the refraction at once, as before",
			func = function(state)
				local F = GryMod.CloakFX
				local convar = GetConVar("gry_cloak_transition")
				local before = convar:GetString()
				local me = fakePlayer(0)
				local flag = true
				function me:GetNW2Bool() return flag end
				stub(_G, "FrameTime", function() return 0.016 end)
				convar:SetString("0")
				local ok, err = pcall(function()
					F.Update(me)
					expect(F.States[me].amount).to.equal(1)
				end)
				convar:SetString(before)
				assert(ok, err)
			end
		},
		{
			name = "Update: a player who dies in the middle of the change is forgotten once it is over, the hooks go, and the render state is put back",
			func = function(state)
				local log = recordRender()
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				local alive = true
				function me:GetNW2Bool() return true end
				function me:Alive() return alive end
				stub(_G, "FrameTime", function() return 0.1 end)
				stub(F, "DrawScreenFx", function() end) -- the local player's screen effect is not the point here
				F.Update(me)
				hook.Remove("RenderScreenspaceEffects", "GryCloakFXScreen")
				F.Update(me)
				expect(F.States[me]).to.exist()
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL) -- the view model is drawn once, then the player dies
				alive = false

				for i = 1, 30 do
					F.Update(me)
				end

				expect(F.States[me]).to.beNil()
				expect(log.blendNow).to.equal(1)
				expect(log.override[#log.override]).to.equal(false)
				expect(hook.GetTable().PreDrawViewModel == nil or hook.GetTable().PreDrawViewModel.GryCloakFX == nil).to.beTrue()
			end
		},
		{
			name = "no scan: a player is followed when the game says his switch changed (the hook EntityNetworkedVarChanged, also for every player at a full update: somebody who joins), or that he came back into view; the Think hook does not look at the players",
			func = function(state)
				local F = GryMod.CloakFX
				expect(F.ScanInterval).to.beNil()

				local changed = hook.GetTable().EntityNetworkedVarChanged and hook.GetTable().EntityNetworkedVarChanged.GryCloakFX
				local transmit = hook.GetTable().NotifyShouldTransmit and hook.GetTable().NotifyShouldTransmit.GryCloakFX
				local think = hook.GetTable().Think and hook.GetTable().Think.GryCloakFX
				expect(changed).to.exist()
				expect(transmit).to.exist()
				expect(think).to.exist()

				-- the Think hook must not go through the players when nothing is waiting
				local looked = 0
				stub(player, "GetAll", function() looked = looked + 1 return {} end)
				stub(_G, "FrameTime", function() return 0.1 end)
				think()
				think()
				expect(looked).to.equal(0)

				-- the game says that somebody's switch changed (the value is not updated yet in the hook: the next frame reads it)
				local ply = fakePlayer(0)
				local flag = true
				function ply:GetNW2Bool(name) return name == "GryCloak" and flag end
				F.States[ply] = nil

				changed(ply, "GryCloak", nil, true)
				expect(F.States[ply]).to.beNil() -- not at once
				think()
				expect(F.States[ply]).to.exist()

				-- another variable, a thing that is not a player: nothing is waiting
				local other = fakePlayer(0)
				function other:GetNW2Bool() return true end
				changed(other, "GryEnergy", 0, 50)
				local prop = {IsPlayer = function() return false end, IsValid = function() return true end}
				function prop:GetNW2Bool() return true end
				changed(prop, "GryCloak", nil, true)
				think()
				expect(F.States[other]).to.beNil()
				expect(F.States[prop]).to.beNil()

				-- a player who comes back into view while camouflaged; one who leaves is not looked at
				local back, gone = fakePlayer(0), fakePlayer(0)
				function back:GetNW2Bool() return true end
				function gone:GetNW2Bool() return true end
				transmit(back, true)
				transmit(gone, false)
				think()
				expect(F.States[back]).to.exist()
				expect(F.States[gone]).to.beNil()

				F.States[ply], F.States[back] = nil, nil
				F.SetDrawHooks(false)
			end
		},
		{
			name = "CatchUp: once, at the load of the level and when the file is loaded again in a running game, the players already camouflaged are followed (the full update may have come before the hooks)",
			func = function(state)
				local F = GryMod.CloakFX
				local a, b = fakePlayer(0), fakePlayer(0)
				function a:GetNW2Bool() return true end
				function b:GetNW2Bool() return false end
				stub(player, "GetAll", function() return {a, b} end)
				stub(_G, "FrameTime", function() return 0.1 end)
				F.States[a], F.States[b] = nil, nil

				F.CatchUp()
				hook.GetTable().Think.GryCloakFX()

				expect(F.States[a]).to.exist()
				expect(F.States[b]).to.beNil()
				expect(hook.GetTable().InitPostEntity.GryCloakFX).to.exist()

				F.States[a] = nil
				F.SetDrawHooks(false)
			end
		},
		{
			name = "Update: the level of a player follows the server's switch, and a player who is not seen camouflaged costs nothing",
			func = function(state)
				local F = GryMod.CloakFX
				local ply = fakePlayer(0)
				local flag = false
				function ply:GetNW2Bool(name) return name == "GryCloak" and flag end
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

				-- the speed it keeps follows the player's, smoothed
				local runner = fakePlayer(300)
				function runner:GetNW2Bool(name) return name == "GryCloak" end
				F.Update(runner)
				local first = F.States[runner].speed
				expect(first > 0 and first < 300).to.beTrue()

				for i = 1, 30 do
					F.Update(runner)
				end

				expect(F.States[runner].speed).to.aboutEqual(300, 0.5)
			end
		},
		{
			-- would fail if: F.StartAmount or F.JoinMargin was removed, or the margin was made smaller than the clock's and the network's error
			name = "StartAmount: a player first seen already camouflaged starts done when his activation is older than the change plus a margin, else from the plain model (the activation is going on and is seen as usual); the margin covers the two clocks' difference and the network's delay",
			func = function(state)
				local F = GryMod.CloakFX
				local limit = F.ActivateTime + F.JoinMargin

				-- the margin is real: the client's clock may be ahead of the server's by about the ping, and the message takes as long to come (a bad
				-- connection is a quarter of a second each way); a fresh activation must never be read as an old one
				expect(F.JoinMargin >= 0.3).to.beTrue()
				expect(F.JoinMargin <= 1).to.beTrue() -- and not so large that somebody who joins sees much of a change that is already over

				expect(F.StartAmount(1000 - 5, 1000)).to.equal(1) -- camouflaged for five seconds
				expect(F.StartAmount(1000 - limit - 0.01, 1000)).to.equal(1)
				expect(F.StartAmount(1000 - limit + 0.01, 1000)).to.equal(0) -- the margin is not over yet
				expect(F.StartAmount(1000 - 0.1, 1000)).to.equal(0) -- just started
				expect(F.StartAmount(1000 - F.ActivateTime, 1000)).to.equal(0) -- the change has just ended on the server: still inside the margin

				-- the client's clock behind the server's (the activation looks to be in the future), or a time that is not there (nobody wrote it)
				expect(F.StartAmount(1000 + 0.3, 1000)).to.equal(0)
				expect(F.StartAmount(-1, 1000)).to.equal(0)
			end
		},
		{
			-- would fail if: F.Update made a new state from 0 whatever the server's activation time (the false activation of a client that joins)
			name = "Update: another player seen already camouflaged long ago (a client that joins in the middle of a game) is done at once: no fade, no sparks of a change that is not happening",
			func = function(state)
				local F = GryMod.CloakFX
				local ply = fakePlayer(0)
				stub(_G, "CurTime", function() return 1000 end)
				stub(_G, "FrameTime", function() return 0.1 end)
				function ply:GetNW2Bool(name) return name == "GryCloak" end
				function ply:GetNW2Float(name, default) return name == "GryCloakSince" and 970 or default end

				F.Update(ply)

				expect(F.States[ply]).to.exist()
				expect(F.States[ply].amount).to.equal(1)

				local refract, base, spark = F.Visibility(F.States[ply].amount, F.States[ply].speed)
				expect(spark).to.equal(0)
				expect(base).to.aboutEqual(F.BaseStill, 0.001)
				expect(ply.shadow).to.beFalse() -- done means no shadow, as for a player who has been camouflaged for a while

				F.States[ply] = nil
				F.SetDrawHooks(false)
			end
		},
		{
			-- would fail if: the start were always 1 for another player (the activation that happens in front of him would not fade)
			name = "Update: another player who has just switched the camouflage on is seen fading in from the plain model, as before (also with the clocks a little apart)",
			func = function(state)
				local F = GryMod.CloakFX
				stub(_G, "FrameTime", function() return 0.1 end)

				-- the delay the network and the clocks add to the time between the activation and the first frame that sees it
				for _, elapsed in ipairs({0, 0.1, 0.4, -0.2}) do
					local ply = fakePlayer(0)
					stub(_G, "CurTime", function() return 1000 end)
					function ply:GetNW2Bool(name) return name == "GryCloak" end
					function ply:GetNW2Float(name, default) return name == "GryCloakSince" and (1000 - elapsed) or default end

					F.Update(ply)

					expect(F.States[ply].amount).to.aboutEqual(0.1 / F.ActivateTime, 0.001)
					F.States[ply] = nil
				end

				F.SetDrawHooks(false)
			end
		},
		{
			-- would fail if: the check was not limited to the other players (the owner of the suit would see his own activation done at once on a reload)
			name = "Update: the local player's own camouflage always starts from the plain model: he sees his own change, whatever the time written",
			func = function(state)
				local F = GryMod.CloakFX
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				stub(_G, "CurTime", function() return 1000 end)
				stub(_G, "FrameTime", function() return 0.1 end)
				stub(F, "DrawScreenFx", function() end) -- his screen effect is not the point here
				function me:GetNW2Bool(name) return name == "GryCloak" end
				function me:GetNW2Float(name, default) return name == "GryCloakSince" and 900 or default end

				F.Update(me)
				hook.Remove("RenderScreenspaceEffects", "GryCloakFXScreen")

				expect(F.States[me].amount).to.aboutEqual(0.1 / F.ActivateTime, 0.001)

				F.States[me] = nil
				F.SetDrawHooks(false)
			end
		},
		{
			-- would fail if: only one of the three ways a player is followed (the full update, the player coming back into view, CatchUp) read the time
			name = "a player already camouflaged long ago is done at once whichever way the game tells us of him: the switch's event (a full update), coming back into view, CatchUp",
			func = function(state)
				local F = GryMod.CloakFX
				local changed = hook.GetTable().EntityNetworkedVarChanged.GryCloakFX
				local transmit = hook.GetTable().NotifyShouldTransmit.GryCloakFX
				local think = hook.GetTable().Think.GryCloakFX
				stub(_G, "CurTime", function() return 1000 end)
				stub(_G, "FrameTime", function() return 0.1 end)

				local function old()
					local ply = fakePlayer(0)
					function ply:GetNW2Bool(name) return name == "GryCloak" end
					function ply:GetNW2Float(name, default) return name == "GryCloakSince" and 800 or default end

					return ply
				end

				local a, b, c = old(), old(), old()
				stub(player, "GetAll", function() return {c} end)

				changed(a, "GryCloak", nil, true)
				transmit(b, true)
				F.CatchUp()
				think()

				for _, ply in ipairs({a, b, c}) do
					expect(F.States[ply]).to.exist()
					expect(F.States[ply].amount).to.equal(1)
					F.States[ply] = nil
				end

				F.SetDrawHooks(false)
			end
		},
		{
			name = "pixel shader, third person: a camouflaged player whose change is done gets no sparks, whoever moves (him, or the camera)",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local ply = fakePlayer(0)
				stub(F.Shader, "Active", function() return true end)

				local strengths = {}
				stub(F.Shader, "Draw", function(ent, strength) strengths[#strengths + 1] = strength return true end)

				setState(ply, 1)
				stub(_G, "EyePos", function() return Vector(0, 0, 0) end)
				stub(_G, "EyeVector", function() return Vector(1, 0, 0) end)

				for i = 1, 5 do
					ply.center = Vector(300, 4 * i, 0) -- he runs across the view
					hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, false)
				end

				expect(#strengths).to.equal(0)
			end
		},
		{
			name = "pixel shader, third person: a camouflaged player who has finished and moves gets the faint sparks of a walk (3 % at full speed, none when he stands, none far away)",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local running, walking, far = fakePlayer(0), fakePlayer(0), fakePlayer(0)
				far.center = Vector(F.DetailDistance + 500, 0, 0)
				stub(F.Shader, "Active", function() return true end)

				local strengths = {}
				stub(F.Shader, "Draw", function(ent, strength) strengths[ent] = strength return true end)

				setState(running, 1, F.FullSpeed)
				setState(walking, 1, F.FullSpeed / 2)
				setState(far, 1, F.FullSpeed)
				stub(_G, "EyePos", function() return Vector(0, 0, 0) end)
				stub(_G, "EyeVector", function() return Vector(1, 0, 0) end)
				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, false)

				expect(strengths[running]).to.aboutEqual(0.03, 0.000001)
				expect(strengths[walking]).to.aboutEqual(0.015, 0.000001)
				expect(strengths[far]).to.beNil()
			end
		},
		{
			name = "pixel shader, third person: refraction and plain model, then the shader added at the faint intensity while the change lasts, whoever moves",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local ply = fakePlayer(0)
				stub(F.Shader, "Active", function() return true end)

				local calls = {}
				stub(F.Shader, "Draw", function(ent, strength, amount, draw) calls[#calls + 1] = {ent = ent, strength = strength, amount = amount, draw = draw} return true end)

				setState(ply, 0.5)
				translucent()

				expect(ply.draws).to.equal(2) -- refraction, plain model: no edge layer
				expect(#calls).to.equal(1)
				expect(calls[1].ent).to.equal(ply)
				expect(calls[1].strength).to.equal(F.SparkRest)
				expect(calls[1].amount).to.equal(0.5)
				expect(leftClean(log)).to.beTrue()

				-- the function it is given draws the entity through the player's own draw hook
				calls[1].draw(ply)
				expect(ply.draws).to.equal(3)
			end
		},
		{
			name = "pixel shader, third person: the scan lines are not drawn on the screen (the shader has them), the strength is the same all the change long",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local ply = fakePlayer(0)
				stub(F.Shader, "Active", function() return true end)

				local strengths = {}
				stub(F.Shader, "Draw", function(ent, s) strengths[#strengths + 1] = s return true end)

				local linesDrawn = 0
				stub(F.Lines, "Draw", function() linesDrawn = linesDrawn + 1 return true end)

				for _, level in ipairs({0.05, 0.12, 0.6, 0.95}) do
					setState(ply, level)
					translucent()
				end

				expect(#strengths).to.equal(4)
				for _, strength in ipairs(strengths) do
					expect(strength).to.equal(F.SparkRest)
				end
				expect(linesDrawn).to.equal(0)
			end
		},
		{
			name = "pixel shader, third person: far away nothing is added, the weapon in the hand gets the shader too, nearby",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local ply = fakePlayer(0)
				local weapon = fakePlayer(0)
				function ply:GetActiveWeapon() return weapon end
				stub(_G, "FrameNumber", function() return 1 end)
				stub(_G, "EyeAngles", function() return Angle(0, 0, 0) end)
				stub(_G, "ScrW", function() return 1920 end)
				stub(_G, "ScrH", function() return 1080 end)
				stub(F, "FieldOfView", function() return 90 end)
				stub(F.Shader, "Active", function() return true end)

				local drawn = {}
				stub(F.Shader, "Draw", function(ent, s) drawn[#drawn + 1] = {ent = ent, s = s} return true end)

				setState(ply, 0.5)
				translucent()
				expect(#drawn).to.equal(2)
				expect(drawn[1].ent).to.equal(ply)
				expect(drawn[2].ent).to.equal(weapon)
				expect(drawn[2].s).to.aboutEqual(drawn[1].s, 0.0001)
				expect(weapon.draws).to.equal(2) -- refraction and plain model, as without the shader

				drawn = {}
				ply.center = Vector(F.DetailDistance + 500, 0, 0)
				translucent()
				expect(#drawn).to.equal(0)
			end
		},
		{
			name = "pixel shader: when it is not in use the edge layer and the scan lines are drawn as before",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local ply = fakePlayer(0)
				-- Active is false (beforeEach)

				local shaderDrawn = 0
				stub(F.Shader, "Draw", function() shaderDrawn = shaderDrawn + 1 return true end)

				setState(ply, 0.5)
				translucent()

				expect(shaderDrawn).to.equal(0)
				expect(ply.draws).to.equal(3) -- refraction, edge, plain model
			end
		},
		{
			name = "pixel shader, first person: the arms and the gun get the shader instead of the outline at the faint intensity while the change lasts, and nothing once it is done",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(F.Shader, "Active", function() return true end)

				local calls = {}
				stub(F.Shader, "Draw", function(ent, strength, amount, draw) calls[#calls + 1] = {ent = ent, strength = strength, amount = amount} return true end)

				local linesDrawn = 0
				stub(F.Lines, "Draw", function() linesDrawn = linesDrawn + 1 return true end)

				setState(me, 0.4)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)

				expect(vm.draws).to.equal(1) -- the refraction only: no outline layer
				expect(#calls).to.equal(1)
				expect(calls[1].ent).to.equal(vm)
				expect(calls[1].amount).to.equal(0.4)
				expect(calls[1].strength).to.equal(F.SparkRest)
				expect(linesDrawn).to.equal(0)
				expect(leftClean(log)).to.beTrue()

				-- done and standing: no sparks
				calls = {}
				setState(me, 1)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(#calls).to.equal(0)

				-- done and moving: the faint sparks of a walk
				calls = {}
				setState(me, 1, F.FullSpeed)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(#calls).to.equal(1)
				expect(calls[1].strength).to.aboutEqual(0.03, 0.000001)
			end
		},
		{
			name = "refraction layer, third person: the plain model is drawn opaque by the engine's way, the layer is blended over it with the alpha the model has lost, and the screen is copied once before",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local ply = fakePlayer(0)
				stub(F.Refract, "Active", function() return true end)

				local calls = {}
				stub(F.Refract, "Draw", function(ent, bump, alpha, draw) calls[#calls + 1] = {ent = ent, bump = bump, alpha = alpha} draw(ent) return true end)

				setState(ply, 0.5)
				translucent()

				local _, base = F.Visibility(0.5)
				expect(#calls).to.equal(1)
				expect(calls[1].ent).to.equal(ply)
				expect(calls[1].bump).to.aboutEqual(F.Refract.BumpScale(0.5), 0.0001)
				expect(calls[1].alpha).to.aboutEqual(F.Refract.Alpha(base), 0.0001)
				expect(log.screenCopies).to.equal(1)
				expect(log.refreshed).to.equal(0) -- the older Refract layer is not used

				-- the model came first, opaque and with no override, then the layer's draw
				expect(log.drawn[1].material).to.beNil()
				expect(log.drawn[1].blend).to.equal(1)
				expect(ply.draws).to.equal(3) -- the plain model, the layer's own draw, and the outline of the sparks (the flash of the change)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "refraction layer, third person: fully camouflaged and still the plain model is left out (the layer covers it), and a failing draw leaves nothing on",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local ply = fakePlayer(0)
				stub(F.Refract, "Active", function() return true end)

				local drawn = 0
				stub(F.Refract, "Draw", function(ent, bump, alpha, draw) drawn = drawn + 1 draw(ent) return true end)

				setState(ply, 1)
				translucent()
				expect(drawn).to.equal(1)
				expect(ply.draws).to.equal(1) -- only the layer's own draw: the model is not worth a draw under it
				expect(leftClean(log)).to.beTrue()

				function ply:DrawModel() error("boom") end
				pcall(translucent)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			name = "refraction layer, third person: the weapon in the hand gets it too, and nothing far away",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local ply = fakePlayer(0)
				local weapon = fakePlayer(0)
				function ply:GetActiveWeapon() return weapon end
				stub(F.Refract, "Active", function() return true end)

				local drawn = {}
				stub(F.Refract, "Draw", function(ent, bump, alpha, draw) drawn[#drawn + 1] = ent draw(ent) return true end)

				setState(ply, 0.5)
				translucent()
				expect(#drawn).to.equal(2)
				expect(drawn[1]).to.equal(ply)
				expect(drawn[2]).to.equal(weapon)

				drawn = {}
				ply.center = Vector(F.DetailDistance + 500, 0, 0)
				translucent()
				expect(#drawn).to.equal(1) -- the weapon is not drawn that far; the body still is
				expect(drawn[1]).to.equal(ply)
			end
		},
		{
			name = "refraction layer, first person: the engine draws the arms opaque, the layer is blended over them in the Post hooks, and the screen is copied once for both",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(F.Refract, "Active", function() return true end)

				local calls = {}
				stub(F.Refract, "Draw", function(ent, bump, alpha, draw) calls[#calls + 1] = {ent = ent, bump = bump, alpha = alpha} return true end)

				setState(me, 0.4)
				local _, base = F.Visibility(0.4)

				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(vm.draws).to.equal(0)
				expect(#log.blend).to.equal(0) -- the engine's draw stays opaque
				expect(log.screenCopies).to.equal(1)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)

				expect(#calls).to.equal(2)
				expect(calls[1].ent).to.equal(vm)
				expect(calls[2].ent).to.equal(hands)
				expect(calls[1].alpha).to.aboutEqual(F.Refract.Alpha(base), 0.0001)
				expect(calls[1].bump).to.aboutEqual(F.Refract.BumpScale(0.4), 0.0001)
				expect(log.screenCopies).to.equal(1) -- once for both
				expect(log.refreshed).to.equal(0)
				expect(leftClean(log)).to.beTrue()
			end
		},
		{
			-- fails when the first person copy is the engine's shared one (a weapon base that copies the screen again while the layer draws its view model, ARC9, makes the layer show
			-- the plain gun it should hide), or when it is made for the hands too or at the wrong time
			name = "refraction layer, first person: the picture behind is copied into the layer's own copy once, before the view model, never through the engine's shared copy",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(F.Refract, "Active", function() return true end)
				stub(F.Refract, "Draw", function() return true end)

				local captures = 0
				stub(F.Refract, "CaptureScreen", function() captures = captures + 1 end)

				setState(me, 0.4)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(captures).to.equal(1)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)

				expect(captures).to.equal(1) -- the hands come right after the view model: no second copy
				expect(log.screenCopies).to.equal(0) -- and the shared copy is not what the layer reads
			end
		},
		{
			-- fails when the depth range is not set before the layers of the first person view: ARC9 draws the view model in its own depth range, and the draw the layer makes of the view
			-- model runs ARC9's own end of draw, which puts the whole range back; the layer over the hands that came after was then hidden by the hands (measured)
			name = "refraction layer, first person: the depth range is the engine's view model range (0 to 0.1) before each layer, so that what a weapon base left behind does not hide it",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(F.Refract, "Active", function() return true end)
				stub(F.Refract, "CaptureScreen", function() end)

				local order = {}
				stub(render, "DepthRange", function(near, far) order[#order + 1] = "range " .. near .. " " .. far end)
				stub(F.Refract, "Draw", function(ent) order[#order + 1] = ent == vm and "vm" or "hands" return true end)

				setState(me, 0.4)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)

				expect(table.concat(order, ",")).to.equal("range 0 0.1,vm,range 0 0.1,hands")
			end
		},
		{
			-- fails when a weapon whose own screen has the view (a customization menu) is covered by the layer anyway, or when the view model is made part transparent / copied for it
			name = "first person: a weapon that says its view is a screen of its own (a plain view) is left to the engine: no layer, no copy, no blend, for the view model and for the hands",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				local weapon = fakePlayer(0)
				function me:GetViewModel() return vm end
				function me:GetActiveWeapon() return weapon end
				stub(F.Refract, "Active", function() return true end)

				local drawn, captures = 0, 0
				stub(F.Refract, "Draw", function() drawn = drawn + 1 return true end)
				stub(F.Refract, "CaptureScreen", function() captures = captures + 1 end)

				local plain = true
				stub(GryMod.API, "IsPlainView", function(w) return plain and w == weapon end)

				setState(me, 0.4)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, weapon)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, weapon)
				hook.GetTable().PreDrawPlayerHands.GryCloakFX(hands, vm, me, weapon)
				hook.GetTable().PostDrawPlayerHands.GryCloakFX(hands, vm, me, weapon)

				expect(drawn).to.equal(0)
				expect(captures).to.equal(0)
				expect(#log.blend).to.equal(0)
				expect(log.screenCopies).to.equal(0)

				-- the menu is closed: the layer is back, at once
				plain = false
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, weapon)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, weapon)
				expect(drawn).to.equal(1)
				expect(captures).to.equal(1)
			end
		},
		{
			name = "refraction layer, first person: at the very end of the change (the plain model nearly all there) no layer and no copy, and the engine's draw is the plain one",
			func = function(state)
				local F = GryMod.CloakFX
				local log = recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(F.Refract, "Active", function() return true end)

				local drawn = 0
				stub(F.Refract, "Draw", function() drawn = drawn + 1 return true end)

				setState(me, 0.003)
				hook.GetTable().PreDrawViewModel.GryCloakFX(vm, me, NULL)
				hook.GetTable().PostDrawViewModel.GryCloakFX(vm, me, NULL)
				expect(drawn).to.equal(0)
				expect(log.screenCopies).to.equal(0)
				for _, value in ipairs(log.blend) do
					-- the engine's draw is the plain one; only the older sparks layer, at its faint intensity, is under 1
					expect(value == 1 or value <= F.SparkRest).to.beTrue()
				end
			end
		},
		{
			-- fails if: the hook function does not ask the minimap's capture, or asks it after the first draw
			name = "the transition's screen effect draws nothing while the minimap captures the map from above, and draws the colour grade as before otherwise",
			func = function(state)
				local F = GryMod.CloakFX
				recordRender()
				local me = fakePlayer(0)
				stub(_G, "LocalPlayer", function() return me end)
				local vm = fakePlayer(0)
				function me:GetViewModel() return vm end
				function me:GetNW2Bool() return true end
				stub(_G, "FrameTime", function() return 0.1 end)

				local grades = 0
				stub(_G, "DrawColorModify", function() grades = grades + 1 end)

				-- the local player's camouflage starts, which adds the real screen effect (no stand-in for DrawScreenFx here)
				F.Update(me)

				local ok, err = pcall(function()
					local screenFx = hook.GetTable().RenderScreenspaceEffects.GryCloakFXScreen

					expect(isfunction(screenFx)).to.beTrue()

					-- capturing: nothing drawn, and the hook stays (the effect goes on after the capture)
					standInCapturing(true)
					screenFx()
					expect(grades).to.equal(0)
					expect(isfunction(hook.GetTable().RenderScreenspaceEffects.GryCloakFXScreen)).to.beTrue()

					-- not capturing: the colour grade of the moment
					standInCapturing(false)
					screenFx()
					expect(grades).to.equal(1)
				end)

				hook.Remove("RenderScreenspaceEffects", "GryCloakFXScreen")

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
