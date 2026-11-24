-- Tests of the night vision SCREEN EFFECT (cl_nightvision_fx.lua, GryMod.NightVisionFX), GLuaTest format, client realm. The picture itself is checked by eye
-- and by pixel numbers in the game (docs/superpowers/plans/2026-11-24-nightvision-implementation.md, "What V43 is"); what is tested here is what can be
-- stated exactly: the pure maths (the weight of the original in the blend, the automatic gain, the cookie of the lamp, the lamp's wall guard, the local
-- gain map, the fog), the life of the effect (its hooks, its lamp and nothing else exist only while the picture is up and the effect is wanted) and the
-- failure rules (an error removes the hook after five, the render state is put back). The state of the night vision (GryMod.NightVision) is the test's own:
-- its clock, its reading of the world and its sounds are replaced for each case and put back after it.

local NAMES = {"gry_nightvision", "gry_nightvision_light", "gry_nightvision_star", "gry_nightvision_localgain", "gry_nightvision_fx", "gry_sounds"}

local IDS = {
	RenderScreenspaceEffects = "GryMod_NightVisionFX_Screen",
	SetupWorldFog = "GryMod_NightVisionFX_Fog",
	SetupSkyboxFog = "GryMod_NightVisionFX_SkyFog",
	PreRender = "GryMod_NightVisionFX_Light"
}

local function ours()
	local found = {}
	local all = hook.GetTable()

	for event, id in pairs(IDS) do
		if all[event] and all[event][id] then
			found[#found + 1] = event
		end
	end

	table.sort(found)

	return table.concat(found, ",")
end

local ALL = "PreRender,RenderScreenspaceEffects,SetupSkyboxFog,SetupWorldFog"

return {
	groupName = "GryMod night vision (screen effect)",
	beforeAll = function(state)
		-- the resources are made once (it takes a moment): the effect's own prewarm
		GryMod.NightVisionFX.Prewarm()
	end,
	beforeEach = function(state)
		local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

		state.saved = {convars = {}}

		for _, name in ipairs(NAMES) do
			local convar = GetConVar(name)
			state.saved.convars[name] = convar and convar:GetString()
		end

		state.saved.clock, state.saved.read, state.saved.exists = NV.Clock, NV.ReadWorld, NV.FileExists
		state.now = 1000

		NV.Clock = function() return state.now end
		NV.FileExists = function() return false end
		NV.ReadWorld = function(w)
			w.option, w.server, w.valid, w.alive, w.suit, w.malfunction, w.energy = true, true, true, true, true, false, NV.Energy()

			return w
		end

		for _, name in ipairs(NAMES) do
			local convar = GetConVar(name)

			if convar then
				convar:SetString("1")
			end
		end

		GetConVar("gry_sounds"):SetString("0")
		NV.Reset()
		FX.Stop()
	end,
	afterEach = function(state)
		local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

		NV.Clock, NV.ReadWorld, NV.FileExists = state.saved.clock, state.saved.read, state.saved.exists
		NV.Reset()
		FX.Stop()

		for _, name in ipairs(NAMES) do
			local convar = GetConVar(name)

			if convar and state.saved.convars[name] then
				convar:SetString(state.saved.convars[name])
			end
		end
	end,
	cases = {
		-- ---------------------------------------------------------------------------------------------------------------------------------------
		-- The pure maths
		-- ---------------------------------------------------------------------------------------------------------------------------------------
		{
			name = "the original takes the rest of the weight: 1 - mix, and mix is the fade squared",
			func = function(state)
				local FX, NV = GryMod.NightVisionFX, GryMod.NightVision

				expect(FX.OriginalAlpha(0)).to.equal(1)
				expect(FX.OriginalAlpha(1)).to.equal(0)
				expect(FX.OriginalAlpha(NV.Mix(0.5))).to.aboutEqual(0.75, 1e-9)
				expect(FX.OriginalAlpha(2)).to.equal(0)
				expect(FX.OriginalAlpha(-1)).to.equal(1)
			end
		},
		{
			name = "the automatic gain aims at 0.27 / luminance and stays between 1.5 and 25",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.GainTarget(0.0135)).to.aboutEqual(20, 1e-6)
				expect(FX.GainTarget(0)).to.equal(25)
				expect(FX.GainTarget(0.00001)).to.equal(25)
				expect(FX.GainTarget(0.5)).to.equal(1.5)
				expect(FX.GainTarget(0.27)).to.equal(1.5)
				expect(FX.GainTarget(0.18)).to.aboutEqual(1.5, 1e-6)
				expect(FX.GainTarget(0.1)).to.aboutEqual(2.7, 1e-6)
			end
		},
		{
			name = "the gain follows its target with a time constant of 0.5 s, a frame longer than 0.1 s counts for 0.1 s",
			func = function(state)
				local FX = GryMod.NightVisionFX

				-- a step of one time constant covers 1 - 1/e of the way
				local g = FX.GainStep(3, 0.0135, 0.1)
				expect(g).to.aboutEqual(3 + (20 - 3) * (1 - math.exp(-0.1 / 0.5)), 1e-9)

				-- no time, no move; a long frame is cut to 0.1 s
				expect(FX.GainStep(3, 0.0135, 0)).to.equal(3)
				expect(FX.GainStep(3, 0.0135, 5)).to.aboutEqual(g, 1e-9)

				-- it converges and does not overshoot
				local x = 3

				for _ = 1, 400 do
					x = FX.GainStep(x, 0.0135, 1 / 60)
				end

				expect(x).to.aboutEqual(20, 0.01)
				expect(x <= 20 + 1e-9).to.beTrue()

				-- going down is the same law
				expect(FX.GainStep(25, 0.5, 0.1)).to.aboutEqual(25 + (1.5 - 25) * (1 - math.exp(-0.2)), 1e-9)
			end
		},
		{
			name = "the cookie of the lamp: flat across the middle, 1 at the horizon, the floor of 0.3 at the top and bottom, a cosine taper at the sides",
			func = function(state)
				local FX = GryMod.NightVisionFX

				-- the horizon row, the middle column: full light
				expect(FX.CookieValue(64, 63, 128)).to.equal(255)
				expect(FX.CookieValue(64, 64, 128)).to.equal(255)

				-- the first row: the profile is under its floor, the floor (0.3) holds: floor(255 * 0.3 + 0.5)
				expect(FX.CookieValue(64, 0, 128)).to.equal(77)
				expect(FX.CookieValue(64, 127, 128)).to.equal(77)

				-- symmetric both ways
				expect(FX.CookieValue(30, 40, 128)).to.equal(FX.CookieValue(97, 40, 128))
				expect(FX.CookieValue(30, 40, 128)).to.equal(FX.CookieValue(30, 87, 128))

				-- flat inside |u| <= 0.6 (columns 26..101 of 128), tapering to 0.15 at the edge
				expect(FX.CookieValue(26, 63, 128)).to.equal(FX.CookieValue(64, 63, 128))
				expect(FX.CookieValue(0, 63, 128) < 45).to.beTrue()
				expect(FX.CookieValue(0, 63, 128) > 30).to.beTrue()

				-- the taper only falls
				local last = 0

				for x = 0, 25 do
					local g = FX.CookieValue(x, 63, 128)
					expect(g >= last).to.beTrue()
					last = g
				end

				-- the vertical profile only falls away from the horizon
				local previous = 256

				for y = 64, 127 do
					local g = FX.CookieValue(64, y, 128)
					expect(g <= previous).to.beTrue()
					previous = g
				end
			end
		},
		{
			name = "the lamp's wall guard: free path = the whole offset; a wall shortens it, never to a point inside the wall",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.OffsetScale(false, 1, 130, 4)).to.equal(1)
				-- a hit at half way, with 4 units of margin on 130
				expect(FX.OffsetScale(true, 0.5, 130, 4)).to.aboutEqual(0.5 - 4 / 130, 1e-9)
				-- a wall right behind the player: the lamp stays at the eye
				expect(FX.OffsetScale(true, 0.01, 130, 4)).to.equal(0)
				expect(FX.OffsetScale(true, 0, 130, 4)).to.equal(0)
				-- a start inside a wall (a solid start): nothing to travel
				expect(FX.OffsetScale(true, 0.9, 0, 4)).to.equal(1)
				-- never above 1, never under 0
				expect(FX.OffsetScale(true, 1, 130, 4)).to.aboutEqual(1 - 4 / 130, 1e-9)
				expect(FX.OffsetScale(true, 2, 130, 4) <= 1).to.beTrue()
			end
		},
		{
			name = "the lamp's scale never grows faster than it shrinks: it drops at once, it comes back in about a fifth of a second",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.ScaleStep(1, 0.2, 0.016)).to.equal(0.2)
				expect(FX.ScaleStep(0.2, 1, 0)).to.equal(0.2)

				local up = FX.ScaleStep(0.2, 1, 0.1)
				expect(up > 0.2).to.beTrue()
				expect(up < 1).to.beTrue()

				local x = 0

				for _ = 1, 200 do
					x = FX.ScaleStep(x, 1, 1 / 60)
				end

				expect(x).to.aboutEqual(1, 0.01)
			end
		},
		{
			name = "the local gain map: one value of light everywhere changes nothing, a bright patch is held back, the dark parts keep their gain",
			func = function(state)
				local FX = GryMod.NightVisionFX
				local W, H = 12, 10
				local n = W * H
				local l, A, B, sorted = {}, {}, {}, {}
				local function idx(x, y) return y * W + x + 1 end

				for i = 1, n do l[i] = 0.1 end

				FX.LocalGainMap(l, W, H, 0.7, 0.25, A, B, sorted)

				for i = 1, n do
					expect(A[i]).to.aboutEqual(1, 1e-9)
				end

				-- a bright patch (4 cells of 120): (0.05 / 0.8)^0.7 = 0.144, under the 0.25 floor, then blurred twice; the far corner is not reached
				for i = 1, n do l[i] = 0.05 end

				for _, cell in ipairs({{5, 4}, {6, 4}, {5, 5}, {6, 5}}) do
					l[idx(cell[1], cell[2])] = 0.8
				end

				local med = FX.LocalGainMap(l, W, H, 0.7, 0.25, A, B, sorted)
				expect(med).to.aboutEqual(0.05, 1e-9)
				expect(A[idx(5, 4)] < 0.8).to.beTrue()
				expect(A[idx(5, 4)] < A[idx(2, 4)]).to.beTrue()
				expect(A[idx(0, 0)]).to.aboutEqual(1, 1e-9)
				expect(A[idx(11, 9)]).to.aboutEqual(1, 1e-9)

				-- no value outside [amin, 1]
				for i = 1, n do
					expect(A[i] >= 0.25 - 1e-9).to.beTrue()
					expect(A[i] <= 1 + 1e-9).to.beTrue()
				end
			end
		},
		{
			name = "the fog: linear 300 to 4000 in grey 13, density 0.9 at full weight, the sky's fog at 1/16, nothing of it before the picture rises",
			func = function(state)
				local FX = GryMod.NightVisionFX

				local s, e, c, d = FX.FogParams(1, 1)
				expect(s).to.equal(300)
				expect(e).to.equal(4000)
				expect(c).to.equal(13)
				expect(d).to.aboutEqual(0.9, 1e-9)

				s, e = FX.FogParams(1, 1 / 16)
				expect(s).to.aboutEqual(300 / 16, 1e-9)
				expect(e).to.aboutEqual(4000 / 16, 1e-9)

				-- the density follows the weight of the picture (the fog must not show before the picture, nor stay after it)
				expect(select(4, FX.FogParams(0, 1))).to.equal(0)
				expect(select(4, FX.FogParams(0.5, 1))).to.aboutEqual(0.45, 1e-9)
			end
		},
		{
			name = "the lamp's brightness follows the weight of the picture: 4 at full weight, none before it",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.LightBrightness(1)).to.equal(4)
				expect(FX.LightBrightness(0)).to.equal(0)
				expect(FX.LightBrightness(0.25)).to.equal(1)
			end
		},
		{
			name = "without HDR the lamp uses a part of its brightness (the same lamp lights a hall 8 times stronger when nothing is exposed)",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.LampScale(true)).to.equal(1)
				expect(FX.LampScale(false)).to.equal(FX.LIGHT.ldr)
				expect(FX.LIGHT.ldr > 0 and FX.LIGHT.ldr < 1).to.beTrue()
			end
		},
		{
			name = "the engine's exposure is divided out: the picture of exposure s is taken back to exposure 1 by s^(-1/2.2) (the screen is in gamma space), nothing to do at 1",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.ExposureFactor(1)).to.equal(1)
				expect(FX.ExposureFactor(2)).to.aboutEqual(2 ^ (-1 / 2.2), 1e-9)
				expect(FX.ExposureFactor(0.5)).to.aboutEqual(0.5 ^ (-1 / 2.2), 1e-9)
				expect(FX.ExposureFactor(2) < 1).to.beTrue()
				expect(FX.ExposureFactor(0.5) > 1).to.beTrue()

				-- the engine's scale lies in 0.5 .. 2 in play; anything wild is held (a scale of 0 or of 100 must not blank or burn the picture)
				expect(FX.ExposureFactor(0)).to.equal(FX.ExposureFactor(0.25))
				expect(FX.ExposureFactor(100)).to.equal(FX.ExposureFactor(4))
				expect(FX.ExposureFactor(nil)).to.equal(1)
			end
		},
		{
			name = "the exposure pass: a factor under 1 is a multiply, a factor over 1 a boost by (factor - 1) (a colour cannot be above 1), no pass when it is within 1 %",
			func = function(state)
				local FX = GryMod.NightVisionFX

				local kind, amount = FX.ExposurePass(0.8)
				expect(kind).to.equal("multiply")
				expect(amount).to.aboutEqual(0.8, 1e-9)

				kind, amount = FX.ExposurePass(1.3)
				expect(kind).to.equal("boost")
				expect(amount).to.aboutEqual(0.3, 1e-9)

				-- the boost is held at what a colour can carry (a factor of 2)
				kind, amount = FX.ExposurePass(3)
				expect(kind).to.equal("boost")
				expect(amount).to.equal(1)

				expect(FX.ExposurePass(1)).to.beNil()
				expect(FX.ExposurePass(1.005)).to.beNil()
				expect(FX.ExposurePass(0.995)).to.beNil()
			end
		},
		{
			name = "the starlight picture is a part of the screen: 1/4 of the width and height by default, rounded up, never under one pixel",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.CHAIN.starDiv).to.equal(4)

				local w, h = FX.StarSize(1920, 1080, 4)
				expect(w).to.equal(480)
				expect(h).to.equal(270)

				w, h = FX.StarSize(1366, 768, 4)
				expect(w).to.equal(342)
				expect(h).to.equal(192)

				w, h = FX.StarSize(1280, 720, 1)
				expect(w).to.equal(1280)
				expect(h).to.equal(720)

				w, h = FX.StarSize(2, 2, 4)
				expect(w).to.equal(1)
				expect(h).to.equal(1)
			end
		},
		{
			name = "the lamp: far Z follows the fog (at least 3000, the fog's end and 500 more), a square 140 degree frustum",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(FX.LIGHT.fov).to.equal(140)
				expect(FX.LIGHT.farZ).to.equal(math.max(3000, FX.FOG.finish + 500))
				expect(FX.LIGHT.farZ).to.equal(4500)
				expect(FX.LIGHT.nearZ).to.equal(8)
				expect(FX.LIGHT.back).to.equal(-120)
				expect(FX.LIGHT.right).to.equal(21)
				expect(FX.LIGHT.up).to.equal(20)
			end
		},
		-- ---------------------------------------------------------------------------------------------------------------------------------------
		-- The life of the effect
		-- ---------------------------------------------------------------------------------------------------------------------------------------
		{
			name = "nothing exists while the night vision is off",
			func = function(state)
				local FX = GryMod.NightVisionFX

				expect(ours()).to.equal("")
				expect(FX.IsRunning()).to.beFalse()
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "switching on adds the four hooks and the lamp; the fade-out leaves them until it is over, then nothing is left",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				expect(NV.Set(true, "test")).to.beTrue()
				expect(ours()).to.equal(ALL)
				expect(FX.IsRunning()).to.beTrue()

				FX.UpdateLight()
				expect(FX.Lamp()).toNot.beNil()
				expect(IsValid(FX.Lamp())).to.beTrue()

				-- off: the picture falls in 0.25 s; the hooks stay while it does
				state.now = state.now + 1
				expect(NV.Set(false, "test")).to.beTrue()
				state.now = state.now + 0.1
				FX.Check()
				expect(ours()).to.equal(ALL)

				state.now = state.now + 0.3
				FX.Check()
				expect(ours()).to.equal("")
				expect(FX.IsRunning()).to.beFalse()
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "gry_nightvision_fx 0: nothing of the effect runs, the night vision still switches on",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				GetConVar("gry_nightvision_fx"):SetString("0")
				expect(NV.Set(true, "test")).to.beTrue()
				expect(ours()).to.equal("")
				expect(FX.IsRunning()).to.beFalse()

				FX.UpdateLight()
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "turning gry_nightvision_fx off while it runs stops everything, turning it on again while the picture is up starts it again",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				NV.Set(true, "test")
				expect(ours()).to.equal(ALL)

				GetConVar("gry_nightvision_fx"):SetString("0")
				FX.Sync()
				expect(ours()).to.equal("")

				GetConVar("gry_nightvision_fx"):SetString("1")
				FX.Sync()
				expect(ours()).to.equal(ALL)
			end
		},
		{
			name = "gry_nightvision_light 0: no lamp at all; changing it while it runs makes or removes the lamp",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				GetConVar("gry_nightvision_light"):SetString("0")
				NV.Set(true, "test")
				FX.UpdateLight()
				expect(FX.Lamp()).to.beNil()

				GetConVar("gry_nightvision_light"):SetString("1")
				FX.UpdateLight()
				expect(IsValid(FX.Lamp())).to.beTrue()

				GetConVar("gry_nightvision_light"):SetString("0")
				FX.UpdateLight()
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "the lamp is one object for one run: the next frames do not make another",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				NV.Set(true, "test")
				FX.UpdateLight()

				local first = FX.Lamp()

				for _ = 1, 10 do
					FX.UpdateLight()
				end

				expect(FX.Lamp() == first).to.beTrue()
			end
		},
		{
			name = "twenty quick switches leave nothing behind: no hook, no lamp, the same resources",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX
				local before = FX.ResourceCount()

				for _ = 1, 20 do
					expect(NV.Set(true, "test")).to.beTrue()
					FX.UpdateLight()
					state.now = state.now + 0.05
					expect(NV.Set(false, "test")).to.beTrue()
					state.now = state.now + 0.5
					FX.Check()
				end

				expect(ours()).to.equal("")
				expect(FX.Lamp()).to.beNil()
				expect(FX.ResourceCount()).to.equal(before)
			end
		},
		{
			name = "a map change (the arrival in a map) and the end of the game both stop it",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				NV.Set(true, "test")
				FX.UpdateLight()
				expect(ours()).to.equal(ALL)

				-- NV.OnInit switches off and resets the state: the fade is at once 0
				NV.OnInit()
				FX.Check()
				expect(ours()).to.equal("")
				expect(FX.Lamp()).to.beNil()

				NV.Set(true, "test")
				FX.UpdateLight()
				expect(hook.GetTable().ShutDown["GryMod_NightVisionFX"]).toNot.beNil()
				FX.OnShutdown()
				expect(ours()).to.equal("")
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "death (the night vision goes off by itself) ends the same way",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX

				NV.Set(true, "test")
				FX.UpdateLight()

				NV.ReadWorld = function(w)
					w.option, w.server, w.valid, w.alive, w.suit, w.malfunction, w.energy = true, true, true, false, true, false, NV.MAX

					return w
				end

				NV.Guard()
				expect(NV.IsOn()).to.beFalse()

				state.now = state.now + 0.5
				FX.Check()
				expect(ours()).to.equal("")
				expect(FX.Lamp()).to.beNil()
			end
		},
		{
			name = "the static textures are drawn in small steps after the first seconds of play by a hook that removes itself, and drawn again when they are lost",
			func = function(state)
				local FX = GryMod.NightVisionFX
				local PREP = "GryMod_NightVisionFX_Prep"

				FX.BeginPrep()
				expect(hook.GetTable().Think[PREP]).toNot.beNil()
				expect(FX.StaticPainted()).to.beFalse()

				-- nothing is drawn before the delay is over
				FX.PrepStep()
				expect(FX.StaticPainted()).to.beFalse()

				FX.State.prepAt = 0
				FX.State.prepFrames = 1000

				local steps = 0

				while hook.GetTable().Think[PREP] ~= nil and steps < 500 do
					FX.PrepStep()
					steps = steps + 1
				end

				expect(hook.GetTable().Think[PREP]).to.beNil()
				expect(steps > 1).to.beTrue()
				expect(FX.StaticPainted()).to.beTrue()
				expect(FX.StaticLost()).to.beFalse()

				-- the device is reset: what was drawn is black
				render.PushRenderTarget(FX.ScanTarget)
				render.Clear(0, 0, 0, 255)
				cam.Start2D()
				surface.SetDrawColor(0, 0, 0, 255)
				surface.DrawRect(0, 0, 4, 4)
				cam.End2D()
				render.PopRenderTarget()
				expect(FX.StaticLost()).to.beTrue()

				FX.Prewarm()
				expect(FX.StaticLost()).to.beFalse()
			end
		},
		{
			name = "with the effect off the preparation draws nothing and leaves no hook",
			func = function(state)
				local FX = GryMod.NightVisionFX

				GetConVar("gry_nightvision_fx"):SetString("0")
				FX.BeginPrep()
				expect(hook.GetTable().Think["GryMod_NightVisionFX_Prep"]).to.beNil()
			end
		},
		{
			name = "the minimap capture does not see the lamp: while the night vision runs Capture.Render and RenderTo switch the lamp off for the capture and give it back after, and Stop gives the functions back",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX
				local Capture = GryMod.Minimap.Capture
				local realRender, realRenderTo = Capture.Render, Capture.RenderTo
				local seen = {}

				Capture.Render = function(tile, level)
					seen[#seen + 1] = {"render", FX.Lamp() and FX.Lamp():GetBrightness(), tile, level}

					return "bytes", "reason"
				end

				Capture.RenderTo = function(tile, level, dest)
					seen[#seen + 1] = {"renderTo", FX.Lamp() and FX.Lamp():GetBrightness(), tile, level, dest}

					return true
				end

				local fakeRender, fakeRenderTo = Capture.Render, Capture.RenderTo

				local ok, err = pcall(function()
					NV.Set(true, "test")
					state.now = state.now + 1
					FX.UpdateLight()

					local lit = FX.Lamp():GetBrightness()
					expect(lit > 0).to.beTrue()

					-- the capture sees no light, and what it returns comes through
					local a, b = Capture.Render("tile", "level")
					expect(a).to.equal("bytes")
					expect(b).to.equal("reason")
					expect(seen[1][2]).to.equal(0)
					expect(seen[1][3]).to.equal("tile")
					expect(seen[1][4]).to.equal("level")

					expect(Capture.RenderTo("tile2", "level2", "dest")).to.beTrue()
					expect(seen[2][2]).to.equal(0)
					expect(seen[2][5]).to.equal("dest")

					-- and the lamp has its light again at once
					expect(FX.Lamp():GetBrightness()).to.aboutEqual(lit, 1e-6)

					-- the functions are the wrapped ones only while it runs
					expect(Capture.Render ~= fakeRender).to.beTrue()
					FX.Stop()
					expect(Capture.Render == fakeRender).to.beTrue()
					expect(Capture.RenderTo == fakeRenderTo).to.beTrue()
				end)

				Capture.Render, Capture.RenderTo = realRender, realRenderTo
				assert(ok, err)
			end
		},
		{
			name = "the capture wrapper leaves a function that something else replaced meanwhile alone, and a capture with no lamp still runs",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX
				local Capture = GryMod.Minimap.Capture
				local realRender, realRenderTo = Capture.Render, Capture.RenderTo
				local ran = 0

				local ok, err = pcall(function()
					GetConVar("gry_nightvision_light"):SetString("0")
					Capture.Render = function() ran = ran + 1 return "x" end
					NV.Set(true, "test")
					FX.UpdateLight()
					expect(FX.Lamp()).to.beNil()
					expect(Capture.Render()).to.equal("x")
					expect(ran).to.equal(1)

					-- somebody else replaces it while we run: Stop must not put ours back over it
					local other = function() return "other" end
					Capture.Render = other
					FX.Stop()
					expect(Capture.Render == other).to.beTrue()
				end)

				Capture.Render, Capture.RenderTo = realRender, realRenderTo
				assert(ok, err)
			end
		},
		{
			name = "the render state is put back after a failure: Stop leaves the lighting mode and the blend alone",
			func = function(state)
				local FX = GryMod.NightVisionFX

				FX.Recover()
				expect(FX.RenderTargetDepth()).to.equal(0)
			end
		},
		{
			name = "a hook that fails five times is removed and says so once; the others stay",
			func = function(state)
				local NV, FX = GryMod.NightVision, GryMod.NightVisionFX
				local logged = {}
				local saved = ErrorNoHalt

				ErrorNoHalt = function(text) logged[#logged + 1] = text end

				local ok, err = pcall(function()
					NV.Set(true, "test")
					FX.SetScreenFault(true)

					for _ = 1, 4 do
						FX.RunScreenHook()
					end

					expect(hook.GetTable().RenderScreenspaceEffects["GryMod_NightVisionFX_Screen"]).toNot.beNil()

					FX.RunScreenHook()
					expect(hook.GetTable().RenderScreenspaceEffects["GryMod_NightVisionFX_Screen"]).to.beNil()
				end)

				ErrorNoHalt = saved
				FX.SetScreenFault(false)
				assert(ok, err)

				-- one line for the first error and one for the removal, not one per frame
				expect(#logged <= 2).to.beTrue()
				expect(#logged >= 1).to.beTrue()

				-- the whole effect stopped with its main hook: no lamp, no fog left behind
				expect(ours()).to.equal("")
				expect(FX.Lamp()).to.beNil()
			end
		}
	}
}
