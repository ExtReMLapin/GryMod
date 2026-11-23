-- Tests of the damage feedback of the original game (GryMod.DamageFx), GLuaTest format, client realm. The rules are in
-- docs/superpowers/plans/2026-11-21-damage-feedback-notes.md: a heavy armor hit makes the HUD jump (the interference
-- effect) and flashes the screen, and the health falling through 25 % and 20 % starts a red tint and a radial blur.

local FX = GryMod.DamageFx

local realShake
local realEmit
local savedDecloak

local function sample(health, energy, armor, max)
	return {health = health, max = max or 100, energy = energy, armor = armor ~= false}
end

local ON = {hud = true, screen = true}

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

-- a state that has seen one sample already (the first sample only sets the reference)
local function seen(health, energy, armor, max)
	local state = FX.NewState()
	FX.Observe(state, sample(health, energy, armor, max), 0, ON)

	return state
end

return {
	groupName = "GryMod damage feedback",
	beforeAll = function(state)
		realShake = FX.Shake
		realEmit = FX.Emit
		savedDecloak = GetConVar("gry_decloak_glitch"):GetString()
	end,
	beforeEach = function(state)
		-- the observer says what it saw through FX.Emit (the HUD event, played on the live state): here the event runs on the state under test
		FX.Emit = function(name, data, st, now, options)
			FX.Events[name](st, now, data, options)
		end
	end,
	afterEach = function(state)
		putBackCapturing()
		FX.Shake = realShake
		FX.Emit = realEmit
		hook.Remove("RenderScreenspaceEffects", "GryDamageFx")
		pcall(function() GetConVar("gry_decloak_glitch"):SetString(savedDecloak) end)
	end,
	cases = {
		{
			name = "ArmorShake: an armor hit that costs a fifth of the bar or more (40 of the original 200 energy)",
			func = function(state)
				expect(FX.ArmorShake(19.9)).to.equal(0)
				expect(FX.ArmorShake(0)).to.equal(0)
				expect(FX.ArmorShake(-5)).to.equal(0)
				expect(FX.ArmorShake(20)).to.equal(0.5)
				expect(FX.ArmorShake(100)).to.equal(0.5)
				expect(FX.ArmorShake(nil)).to.equal(0)
				expect(FX.ArmorShake(0 / 0)).to.equal(0)
			end
		},
		{
			name = "LowHealthLevel: 2 when the health falls through 20 %, 1 when it lands in the 20-25 % band from above, 0 otherwise",
			func = function(state)
				expect(FX.LowHealthLevel(15, 100, 50)).to.equal(2)
				expect(FX.LowHealthLevel(20, 100, 21)).to.equal(2)
				expect(FX.LowHealthLevel(24, 100, 60)).to.equal(1)
				expect(FX.LowHealthLevel(22, 100, 30)).to.equal(1)
				-- the same rule at 200 health (the original's 40 and 50)
				expect(FX.LowHealthLevel(40, 200, 41)).to.equal(2)
				expect(FX.LowHealthLevel(49, 200, 80)).to.equal(1)
			end
		},
		{
			name = "LowHealthLevel: nothing when the health rises, stays inside a zone, or has no previous value",
			func = function(state)
				expect(FX.LowHealthLevel(30, 100, 20)).to.equal(0)
				expect(FX.LowHealthLevel(24, 100, 22)).to.equal(0)
				expect(FX.LowHealthLevel(10, 100, 18)).to.equal(0)
				expect(FX.LowHealthLevel(22, 100, 24)).to.equal(0)
				expect(FX.LowHealthLevel(10, 100, nil)).to.equal(0)
				expect(FX.LowHealthLevel(60, 100, 90)).to.equal(0)
				expect(FX.LowHealthLevel(10, 0, 50)).to.equal(0)
				expect(FX.LowHealthLevel(0 / 0, 100, 50)).to.equal(0)
			end
		},
		{
			name = "the interference falls by its decay (4 a second) each step and is gone under the floor",
			func = function(state)
				expect(FX.InterferenceStep(20, 0.05)).to.aboutEqual(16, 0.0001)
				expect(FX.InterferenceStep(0.6, 0.05)).to.equal(0)
				expect(FX.InterferenceStep(0, 0.05)).to.equal(0)
				-- a long frame cannot push it negative or back up
				expect(FX.InterferenceStep(20, 1)).to.equal(0)

				local strength, frames = FX.INTERFERENCE_DISTORTION, 0

				while strength > 0 and frames < 1000 do
					strength = FX.InterferenceStep(strength, 1 / 60)
					frames = frames + 1
				end

				-- about 0.9 s at 60 frames a second
				expect(frames).to.beBetween(45, 70)
			end
		},
		{
			name = "the interference offsets spread over plus and minus half the strength, and nothing when it is 0",
			func = function(state)
				local x, y = FX.InterferenceOffsets(20, 0.5, 0.5)
				expect(x).to.aboutEqual(0, 0.0001)
				expect(y).to.aboutEqual(0, 0.0001)
				x, y = FX.InterferenceOffsets(20, 1, 0)
				expect(x).to.aboutEqual(10, 0.0001)
				expect(y).to.aboutEqual(-10, 0.0001)
				x, y = FX.InterferenceOffsets(0, 1, 0)
				expect(x).to.equal(0)
				expect(y).to.equal(0)
			end
		},
		{
			name = "ArmorFlash follows the flow graph: dark and red for 0.2 s, glitch for 0.4 s, over at 0.5 s",
			func = function(state)
				local f = FX.ArmorFlash(0)
				expect(f.brightness).to.aboutEqual(0.3, 0.0001)
				expect(f.tint).to.aboutEqual(0.5, 0.0001)
				expect(f.glitch).to.aboutEqual(1, 0.0001)

				f = FX.ArmorFlash(0.1)
				expect(f.brightness).to.aboutEqual(0.65, 0.0001)
				expect(f.tint).to.aboutEqual(0.25, 0.0001)
				expect(f.glitch).to.aboutEqual(0.75, 0.0001)

				f = FX.ArmorFlash(0.3)
				expect(f.brightness).to.equal(1)
				expect(f.tint).to.equal(0)
				expect(f.glitch).to.aboutEqual(0.25, 0.0001)

				expect(FX.ArmorFlash(0.5)).to.beNil()
				expect(FX.ArmorFlash(-1)).to.beNil()
			end
		},
		{
			name = "LowHealthFx follows the flow graphs: blur over 6 s, red tint over 4 s",
			func = function(state)
				local f = FX.LowHealthFx(1, 0)
				expect(f.blur).to.aboutEqual(1, 0.0001)
				expect(f.tint).to.aboutEqual(0.5, 0.0001)

				f = FX.LowHealthFx(2, 3)
				expect(f.blur).to.aboutEqual(0.5, 0.0001)
				expect(f.tint).to.aboutEqual(0.125, 0.0001)

				f = FX.LowHealthFx(1, 5)
				expect(f.tint).to.equal(0)
				expect(f.blur).to.aboutEqual(1 / 6, 0.0001)

				expect(FX.LowHealthFx(1, 6)).to.beNil()
				expect(FX.LowHealthFx(0, 1)).to.beNil()
			end
		},
		{
			name = "an armor hit of 25 energy makes the HUD jump and shakes the screen",
			func = function(state)
				local shakes = {}
				FX.Shake = function(amplitude, frequency, seconds)
					shakes[#shakes + 1] = {amplitude, frequency, seconds}
				end

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 55), 1, ON)
				expect(s.jolt).to.equal(FX.INTERFERENCE_DISTORTION)
				expect(s.armorAt).to.equal(1)
				expect(#shakes).to.equal(1)
				expect(shakes[1][3]).to.equal(0.5)
				expect(shakes[1][2]).to.equal(20)
			end
		},
		{
			name = "no effect for a small armor hit, a drop outside armor mode, a rise, or the first sample",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 61), 1, ON)
				expect(s.jolt).to.equal(0)
				expect(s.armorAt).to.beNil()

				-- 30 lost but not in armor mode (the strength jump, the sprint)
				s = seen(100, 80, false)
				FX.Observe(s, sample(100, 50, false), 1, ON)
				expect(s.armorAt).to.beNil()

				s = seen(100, 20)
				FX.Observe(s, sample(100, 90), 1, ON)
				expect(s.armorAt).to.beNil()

				-- the reference is only taken by the first sample
				s = FX.NewState()
				FX.Observe(s, sample(5, 5), 1, ON)
				expect(s.armorAt).to.beNil()
				expect(s.lowAt).to.beNil()
				expect(shakes).to.equal(0)
			end
		},
		{
			name = "each effect has its own switch: the HUD jump (gry_hud_damagefx) and the screen (gry_screenfx)",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 40), 1, {hud = true, screen = false})
				expect(s.jolt).to.equal(FX.INTERFERENCE_DISTORTION)
				expect(s.armorAt).to.beNil()
				expect(shakes).to.equal(0)
				expect(hook.GetTable().RenderScreenspaceEffects.GryDamageFx).to.beNil()

				s = seen(100, 80)
				FX.Observe(s, sample(100, 40), 1, {hud = false, screen = true})
				expect(s.jolt).to.equal(0)
				expect(s.armorAt).to.equal(1)
				expect(shakes).to.equal(1)
			end
		},
		{
			name = "the health falling through the low zones starts the screen effect, with a shake only at 20 %",
			func = function(state)
				local shakes = {}
				FX.Shake = function(amplitude, frequency, seconds)
					shakes[#shakes + 1] = {amplitude, frequency, seconds}
				end

				local s = seen(80, 100, false)
				FX.Observe(s, sample(23, 100, false), 2, ON)
				expect(s.lowLevel).to.equal(1)
				expect(s.lowAt).to.equal(2)
				expect(#shakes).to.equal(0)

				FX.Observe(s, sample(18, 100, false), 3, ON)
				expect(s.lowLevel).to.equal(2)
				expect(s.lowAt).to.equal(3)
				expect(#shakes).to.equal(1)
				expect(shakes[1][3]).to.equal(0.4)
				expect(shakes[1][2]).to.equal(40)

				-- healing and hurting inside the zone start nothing new
				FX.Observe(s, sample(10, 100, false), 4, ON)
				expect(s.lowAt).to.equal(3)
			end
		},
		{
			name = "ScreenParams: nothing while nothing runs, the armor flash and the low health tint together, nothing once over",
			func = function(state)
				local s = FX.NewState()
				expect(FX.ScreenParams(s, 0)).to.beNil()

				s.armorAt = 10
				local p = FX.ScreenParams(s, 10)
				expect(p.brightness).to.aboutEqual(0.3, 0.0001)
				expect(p.tint).to.aboutEqual(0.5, 0.0001)
				expect(p.blur).to.equal(0)

				s.lowAt, s.lowLevel = 10, 2
				p = FX.ScreenParams(s, 10.1)
				expect(p.blur).to.aboutEqual(1 - 0.1 / 6, 0.0001)
				expect(p.tint).to.aboutEqual(math.max(0.25, 0.5 * (1 - 0.1 / 4)), 0.0001)

				expect(FX.ScreenParams(s, 17)).to.beNil()
			end
		},
		{
			name = "the screen hook is added with the effect and removes itself when it is over (no cost otherwise)",
			func = function(state)
				FX.Shake = function() end
				expect(hook.GetTable().RenderScreenspaceEffects.GryDamageFx).to.beNil()

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 40), 5, ON)
				expect(isfunction(hook.GetTable().RenderScreenspaceEffects.GryDamageFx)).to.beTrue()

				FX.Sync(s, 5.2)
				expect(isfunction(hook.GetTable().RenderScreenspaceEffects.GryDamageFx)).to.beTrue()

				FX.Sync(s, 5.6)
				expect(hook.GetTable().RenderScreenspaceEffects.GryDamageFx).to.beNil()
			end
		},
		{
			name = "HudOffset: nothing at rest, a bounded jump after a hit, and it dies out by itself",
			func = function(state)
				local s = FX.NewState()
				local x, y = FX.HudOffset(s, 1 / 60, 1, 0)
				expect(x).to.equal(0)
				expect(y).to.equal(0)

				FX.Shake = function() end
				s = seen(100, 80)
				FX.Observe(s, sample(100, 40), 1, ON)
				x, y = FX.HudOffset(s, 1 / 60, 1, 0)
				expect(math.abs(x)).to.beGreaterThan(5)
				expect(math.abs(x)).to.beLessThan(10.01)

				local frames = 0

				while s.jolt > 0 and frames < 1000 do
					FX.HudOffset(s, 1 / 60)
					frames = frames + 1
				end

				expect(s.jolt).to.equal(0)
				x, y = FX.HudOffset(s, 1 / 60, 1, 0)
				expect(x).to.equal(0)
			end
		},
		{
			name = "Reset forgets what the state held (a respawn)",
			func = function(state)
				FX.Shake = function() end
				local s = seen(100, 80)
				FX.Observe(s, sample(100, 40), 1, ON)
				FX.Reset(s)
				expect(s.jolt).to.equal(0)
				expect(s.armorAt).to.beNil()
				expect(s.health).to.beNil()
				expect(hook.GetTable().RenderScreenspaceEffects.GryDamageFx).to.beNil()
			end
		},
		{
			name = "Observe: a real armor hit of 25 triggers the effect and one of 10 does not (non-regression)",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local hit = seen(100, 80)
				FX.Observe(hit, sample(100, 55), 1, ON)
				expect(hit.armorAt).to.equal(1)

				local small = seen(100, 80)
				FX.Observe(small, sample(100, 70), 1, ON)
				expect(small.armorAt).to.beNil()
				expect(shakes).to.equal(1)
			end
		},
		{
			name = "Decloak: the effect of an armor hit plays at ANY energy, once, and the emptied bar is not read as a hit",
			func = function(state)
				GetConVar("gry_decloak_glitch"):SetString("1")
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				for _, energy in ipairs({15, 40, 100, 3}) do
					shakes = 0
					local s = seen(100, energy)
					FX.Decloak(s, 1, ON)
					expect(s.armorAt).to.equal(1)
					expect(s.jolt).to.equal(FX.INTERFERENCE_DISTORTION)
					expect(shakes).to.equal(1)

					-- the server empties the bar a few frames later: the same effect is not played again
					FX.Observe(s, sample(100, 0), 1.1, ON)
					expect(s.armorAt).to.equal(1)
					expect(shakes).to.equal(1)
				end
			end
		},
		{
			name = "Decloak: the slow drain of the camouflage before the server empties the bar does not use up the marker (measured live)",
			func = function(state)
				GetConVar("gry_decloak_glitch"):SetString("1")
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 40)
				FX.Decloak(s, 1, ON)
				expect(shakes).to.equal(1)

				-- frames where the energy only falls a little (the camouflage's drain), the suit already in armor mode
				FX.Observe(s, sample(100, 39.9), 1.02, ON)
				FX.Observe(s, sample(100, 39.8), 1.04, ON)
				expect(s.emptiedUntil ~= nil).to.beTrue()

				-- then the bar is emptied: still no hit
				FX.Observe(s, sample(100, 0), 1.06, ON)
				expect(shakes).to.equal(1)
				expect(s.emptiedUntil).to.beNil()
			end
		},
		{
			name = "Decloak: the marker is consumed by the drop, and a real hit after it triggers again; it also expires",
			func = function(state)
				GetConVar("gry_decloak_glitch"):SetString("1")
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 60)
				FX.Decloak(s, 1, ON)
				FX.Observe(s, sample(100, 0), 1.05, ON)
				expect(s.emptiedUntil).to.beNil()

				-- the bar refills a little, then a hit of 25 is a real one
				FX.Observe(s, sample(100, 50), 2, ON)
				FX.Observe(s, sample(100, 25), 2.1, ON)
				expect(s.armorAt).to.equal(2.1)
				expect(shakes).to.equal(2)

				-- a marker whose drop never comes (the bar was empty already) expires: a hit long after is real
				local late = seen(100, 0)
				FX.Decloak(late, 5, ON)
				FX.Observe(late, sample(100, 0), 5.5, ON)
				expect(late.emptiedUntil).to.equal(6)
				FX.Observe(late, sample(100, 0), 6.5, ON)
				expect(late.emptiedUntil).to.beNil()
				FX.Observe(late, sample(100, 90), 7, ON)
				FX.Observe(late, sample(100, 60), 7.1, ON)
				expect(late.armorAt).to.equal(7.1)
			end
		},
		{
			name = "with gry_decloak_glitch 0 firing out of the camouflage plays nothing, and the emptied bar is still no hit",
			func = function(state)
				GetConVar("gry_decloak_glitch"):SetString("0")
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 60)
				FX.Decloak(s, 1, ON)
				FX.Observe(s, sample(100, 0), 1.05, ON)
				expect(s.armorAt).to.beNil()
				expect(s.jolt).to.equal(0)
				expect(shakes).to.equal(0)
			end
		},
		{
			name = "Decloak follows the two effect switches: the HUD jump and the screen",
			func = function(state)
				GetConVar("gry_decloak_glitch"):SetString("1")
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 50)
				FX.Decloak(s, 1, {hud = true, screen = false})
				expect(s.jolt).to.equal(FX.INTERFERENCE_DISTORTION)
				expect(s.armorAt).to.beNil()

				s = seen(100, 50)
				FX.Decloak(s, 1, {hud = false, screen = true})
				expect(s.jolt).to.equal(0)
				expect(s.armorAt).to.equal(1)
				expect(shakes).to.equal(1)
			end
		},
		{
			name = "a malfunction that empties the bar is not an armor hit (the flag comes with the empty bar)",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 60)
				local down = sample(100, 0)
				down.malfunction = true
				FX.Observe(s, down, 1, ON)
				expect(s.armorAt).to.beNil()
				expect(s.jolt).to.equal(0)
				expect(shakes).to.equal(0)
			end
		},
		{
			name = "an energy drop of the same size and no cause is still a hit: the marker belongs to the decloak only",
			func = function(state)
				FX.Shake = function() end
				local s = seen(100, 60)
				FX.Observe(s, sample(100, 0), 1, ON)
				expect(s.armorAt).to.equal(1)
			end
		},
		{
			name = "gry_decloak_glitch is a saved setting, on by default, with a check box in the options; Reset forgets the marker",
			func = function(state)
				local convar = GetConVar("gry_decloak_glitch")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				-- saved like the other switch of this file (the flag values of client convars are not the FCVAR_ constants)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_screenfx"):GetFlags())

				FX.Shake = function() end
				local s = seen(100, 60)
				FX.Decloak(s, 1, ON)
				FX.Reset(s)
				expect(s.emptiedUntil).to.beNil()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_decloak_glitch"]).to.beTrue()
			end
		},
		{
			name = "both switches are saved settings, on by default; the HUD one is in the HUD options list",
			func = function(state)
				local screen = GetConVar("gry_screenfx")
				expect(screen ~= nil).to.beTrue()
				expect(screen:GetDefault()).to.equal("1")
				local hudfx = GetConVar("gry_hud_damagefx")
				expect(hudfx ~= nil).to.beTrue()
				expect(hudfx:GetDefault()).to.equal("1")
				expect(GryMod.HUDOptions.Find("damagefx")).to.exist()
			end
		},
		{
			name = "the radar's damage ring keeps the movie's rule: frame = value * 100 + 1 (at most the last), hidden above 1",
			func = function(state)
				local panel = GryMod.FlashRadar.New(GryMod.Flash.Load("hud_radarcompassstealth"))
				local ring = panel.view:Child("Indicator")
				expect(ring.visible).to.beFalse()

				panel:SetDamage(0.1)
				expect(ring.visible).to.beTrue()
				expect(ring:CurrentFrame()).to.equal(11)

				-- past the end of the clip (22 frames) it lands on the last frame, whose script sends it back to frame 1
				panel:SetDamage(0.5)
				expect(ring:CurrentFrame()).to.equal(1)

				panel:SetDamage(0)
				expect(ring:CurrentFrame()).to.equal(1)

				panel:SetDamage(2)
				expect(ring.visible).to.beFalse()
			end
		},
		{
			-- fails if: the post hook does not ask the minimap's capture before it draws (colour grade, copies of the frame, glitch strips)
			name = "the post hook draws nothing while the minimap captures the map from above (and stays), and draws as before otherwise",
			func = function(state)
				local names = {"UpdateScreenEffectTexture", "GetScreenEffectTexture", "SetScissorRect", "DrawTextureToScreenRect"}
				local savedRender, savedGrade, savedSurface = {}, DrawColorModify, {surface.SetMaterial, surface.SetDrawColor, surface.DrawTexturedRect}
				local drawn = 0

				for _, name in ipairs(names) do
					savedRender[name] = render[name]
				end

				local ok, err = pcall(function()
					DrawColorModify = function() drawn = drawn + 1 end

					for _, name in ipairs(names) do
						render[name] = function() drawn = drawn + 1 end
					end

					surface.SetMaterial = function() end
					surface.SetDrawColor = function() end
					surface.DrawTexturedRect = function() drawn = drawn + 1 end

					FX.Shake = function() end

					-- a heavy armor hit of this very moment (the hook reads the real time): the flash is at its start
					local s = seen(100, 80)
					FX.Observe(s, sample(100, 40), RealTime(), ON)
					FX.Sync(s, RealTime())

					local paint = hook.GetTable().RenderScreenspaceEffects.GryDamageFx

					expect(isfunction(paint)).to.beTrue()

					standInCapturing(true)
					paint()
					expect(drawn).to.equal(0)
					expect(isfunction(hook.GetTable().RenderScreenspaceEffects.GryDamageFx)).to.beTrue()

					standInCapturing(false)
					paint()
					expect(drawn > 0).to.beTrue()
				end)

				for _, name in ipairs(names) do
					render[name] = savedRender[name]
				end

				DrawColorModify = savedGrade
				surface.SetMaterial, surface.SetDrawColor, surface.DrawTexturedRect = savedSurface[1], savedSurface[2], savedSurface[3]

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without FX.SmallHitShake
			name = "SmallHitShake: 0.35 s for a hit that costs from 1 up to (not including) a fifth of the bar, nothing otherwise",
			func = function(state)
				expect(FX.SmallHitShake(10)).to.equal(0.35)
				expect(FX.SmallHitShake(1)).to.equal(0.35)
				expect(FX.SmallHitShake(19.9)).to.equal(0.35)
				expect(FX.SmallHitShake(0.5)).to.equal(0)
				expect(FX.SmallHitShake(20)).to.equal(0) -- a heavy hit has its own effect
				expect(FX.SmallHitShake(0)).to.equal(0)
				expect(FX.SmallHitShake(nil)).to.equal(0)
				expect(FX.SmallHitShake(0 / 0)).to.equal(0)
			end
		},
		{
			-- fails without the small hit branch of Observe (nothing shakes) or if it also plays the flash / the jump of a heavy hit
			name = "a light armor hit (10 energy) gives the small shake only: no flash, no jump of the HUD; a heavy one gives the heavy effect and not both",
			func = function(state)
				local shakes = {}
				FX.Shake = function(amplitude, frequency, seconds) shakes[#shakes + 1] = {amplitude, frequency, seconds} end
				local options = {hud = true, screen = true, hit = true}

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 70), 1, options)
				expect(#shakes).to.equal(1)
				expect(shakes[1][3]).to.equal(FX.SMALL_SECONDS)
				expect(s.armorAt).to.beNil()
				expect(s.jolt).to.equal(0)

				-- 25 lost: the heavy effect, one shake of 0.5 s (not the small one besides)
				shakes = {}
				s = seen(100, 80)
				FX.Observe(s, sample(100, 55), 1, options)
				expect(#shakes).to.equal(1)
				expect(shakes[1][3]).to.equal(FX.ARMOR_SECONDS)
				expect(s.armorAt).to.equal(1)
			end
		},
		{
			-- fails if the small shake ignores its own switch or the screen switch
			name = "the small shake follows its own switch and the screen switch; without the switch given nothing changes (the old behaviour)",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end

				local s = seen(100, 80)
				FX.Observe(s, sample(100, 70), 1, {hud = true, screen = true, hit = false})
				expect(shakes).to.equal(0)

				s = seen(100, 80)
				FX.Observe(s, sample(100, 70), 1, {hud = true, screen = false, hit = true})
				expect(shakes).to.equal(0)

				s = seen(100, 80)
				FX.Observe(s, sample(100, 70), 1, ON)
				expect(shakes).to.equal(0)
			end
		},
		{
			-- fails if the small shake is played for what is not a hit
			name = "no small shake outside armor mode, for a rise, a drop under 1, a malfunction, the emptied bar of a decloak, or the first sample",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end
				local options = {hud = true, screen = true, hit = true}

				local s = seen(100, 80, false)
				FX.Observe(s, sample(100, 70, false), 1, options)

				s = seen(100, 70)
				FX.Observe(s, sample(100, 80), 1, options)

				s = seen(100, 70)
				FX.Observe(s, sample(100, 69.5), 1, options)

				s = seen(100, 70)
				local down = sample(100, 60)
				down.malfunction = true
				FX.Observe(s, down, 1, options)

				s = FX.NewState()
				FX.Observe(s, sample(100, 5), 1, options)

				GetConVar("gry_decloak_glitch"):SetString("0")
				s = seen(100, 5)
				FX.Decloak(s, 1, options)
				FX.Observe(s, sample(100, 0), 1.05, options)

				expect(shakes).to.equal(0)
			end
		},
		{
			-- fails without the small branch of the armor_hit event (data.small)
			name = "the armor_hit event with small = true shakes and nothing else; with the screen or the hit switch off, or visual = false, it shakes nothing",
			func = function(state)
				local shakes = 0
				FX.Shake = function() shakes = shakes + 1 end
				local s = FX.NewState()

				FX.Events.armor_hit(s, 1, {small = true, sound = false}, {hud = true, screen = true, hit = true})
				expect(shakes).to.equal(1)
				expect(s.armorAt).to.beNil()
				expect(s.jolt).to.equal(0)

				FX.Events.armor_hit(s, 1, {small = true, sound = false}, {hud = true, screen = false, hit = true})
				FX.Events.armor_hit(s, 1, {small = true, sound = false}, {hud = true, screen = true, hit = false})
				FX.Events.armor_hit(s, 1, {small = true, sound = false, visual = false}, {hud = true, screen = true, hit = true})
				expect(shakes).to.equal(1)
			end
		},
		{
			-- fails without gry_hit_shake in FX.Options and a check box for it
			name = "gry_hit_shake is a saved setting, on by default, read by FX.Options, with a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_hit_shake")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				expect(convar:GetFlags()).to.equal(GetConVar("gry_screenfx"):GetFlags())

				local saved = convar:GetString()
				convar:SetString("0")
				local off = FX.Options().hit
				convar:SetString("1")
				local on = FX.Options().hit
				convar:SetString(saved)
				expect(off).to.beFalse()
				expect(on).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.SuitOptions(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_hit_shake"]).to.beTrue()
			end
		},
		{
			-- fails without the listener GRYDAMAGEFXCLEAR
			name = "the HUD going down (status 1) clears the arcs of the damage direction around the crosshair, once; other statuses do not; no crosshair is no error",
			func = function(state)
				local listener = hook.GetTable().GryMod_HUDStatus and hook.GetTable().GryMod_HUDStatus["GRYDAMAGEFXCLEAR"]
				expect(listener).to.beA("function")
				local Cross = GryMod.FlashCrosshair
				local real = Cross.Current
				local cleared = 0
				local fake = {ClearDamageDirection = function() cleared = cleared + 1 end}
				Cross.Current = function() return fake end

				local ok, err = pcall(function()
					listener(1)
					expect(cleared).to.equal(1)
					listener(0)
					listener(2)
					expect(cleared).to.equal(1)

					Cross.Current = function() return nil end
					listener(1)
					expect(cleared).to.equal(1)
				end)

				Cross.Current = real

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
