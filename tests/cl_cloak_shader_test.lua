-- Tests of the camouflage's pixel shader (cl_cloak_shader.lua), GLuaTest format, client realm. The shader is the original's own sparks
-- pass (CloakSparksPS), ported to the Source engine (dev_resources/shaders/grymod_cloak_*.hlsl): the 3D noise read three times in a chain, the spark
-- profile, the scan lines calculated from the pixel row. The Lua gives it the time, the variation, the strength; if the game cannot run it,
-- a test draw tells and the older approximation (cl_cloak_lines.lua, the edge layer) stays. Nothing is shown on the screen by these cases.

local OPTION = "gry_cloak_shader"

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

local function near(a, b)
	return math.abs(a - b) < 1e-6
end

local function fakeEntity(index)
	local ent = {draws = {}}
	function ent:IsValid() return true end
	function ent:EntIndex() return index or 5 end
	function ent:GetPos() return ent.pos or Vector(0, 0, 0) end
	function ent:GetAngles() return ent.ang or Angle(0, 0, 0) end
	function ent:DrawModel() ent.draws[#ent.draws + 1] = ent.override end

	return ent
end

local originalOption

return {
	groupName = "GryMod camouflage pixel shader (client)",
	beforeAll = function()
		originalOption = GetConVar(OPTION) and GetConVar(OPTION):GetString()
	end,
	afterEach = function()
		restore()

		if GetConVar(OPTION) and originalOption then
			GetConVar(OPTION):SetString(originalOption)
		end
	end,
	cases = {
		{
			name = "the option exists and is on by default (a check box in the options panel)",
			func = function()
				local c = GetConVar(OPTION)
				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
				expect(GryMod.CloakFX.Shader ~= nil).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = child:GetText()
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

				expect(found[OPTION] ~= nil).to.beTrue()
			end
		},
		{
			name = "the variation follows the original: the first part moves with the frac of the time and goes down to nothing as the camouflage completes",
			func = function()
				local S = GryMod.CloakFX.Shader
				local x, y = S.Variation(0.5, 0)
				expect(near(x, 0.1)).to.beTrue()
				expect(near(y, 0.02)).to.beTrue()

				x, y = S.Variation(0.25, 0.5)
				expect(near(x, 0.025)).to.beTrue()
				expect(near(y, 0.01)).to.beTrue()

				x, y = S.Variation(0.75, 1)
				expect(near(x, 0)).to.beTrue()
				expect(near(y, 0.01)).to.beTrue()

				-- the frac: a whole number of time units is the same as none
				local a = S.Variation(3.25, 0)
				local b = S.Variation(0.25, 0)
				expect(near(a, b)).to.beTrue()
			end
		},
		{
			name = "the shader's time is the game's time times 0.4 (the original's), shifted a little for each entity, and wraps where every lookup repeats",
			func = function()
				local S = GryMod.CloakFX.Shader
				expect(near(S.Time(1, 0), 0.4)).to.beTrue()
				expect(S.Time(1, 1) ~= S.Time(1, 0)).to.beTrue()
				-- 5 time units is a whole number of periods of the three lookups (1, 0.5 and 1 / 1.4)
				expect(near(S.Time(5 / 0.4 + 1, 0), S.Time(1, 0))).to.beTrue()

				for _, t in ipairs({0, 7.3, 1000.77, 123456.789}) do
					local v = S.Time(t, 17)
					expect(v >= 0 and v < 5).to.beTrue()
				end
			end
		},
		{
			name = "the scan lines are four rows to a period at 1080 lines, and larger on a taller screen so that they look the same",
			func = function()
				local S = GryMod.CloakFX.Shader
				expect(S.RowPeriod(1080)).to.equal(4)
				expect(S.RowPeriod(720)).to.equal(4)
				expect(S.RowPeriod(2160)).to.equal(8)
			end
		},
		{
			name = "the lines jump to another place 30 times a second, by whole rows inside one period",
			func = function()
				local S = GryMod.CloakFX.Shader
				local seen = {}

				for frame = 0, 59 do
					local offset = S.RowOffset(frame / 30 + 0.001, 4)
					expect(offset >= 0 and offset < 4).to.beTrue()
					expect(offset == math.floor(offset)).to.beTrue()
					seen[offset] = true
				end

				local n = 0
				for _ in pairs(seen) do n = n + 1 end
				expect(n >= 3).to.beTrue()
				-- the same frame, the same offset
				expect(S.RowOffset(1.001, 4)).to.equal(S.RowOffset(1.01, 4))
			end
		},
		{
			name = "the constants given to the shader: units per volume, time, strength, rows to a period; the variation; the entity's angles and drift; its origin",
			func = function()
				local S = GryMod.CloakFX.Shader
				local c = S.Constants(2.5, 0.5, 0.8, 1080, 3)
				expect(near(c[1][1], 52.49)).to.beTrue()
				expect(near(c[1][2], S.Time(2.5, 3))).to.beTrue()
				expect(near(c[1][3], 0.8)).to.beTrue()
				expect(c[1][4]).to.equal(4)

				local vx, vy = S.Variation(S.Time(2.5, 3), 0.5)
				expect(near(c[2][1], vx)).to.beTrue()
				expect(near(c[2][2], vy)).to.beTrue()
				expect(c[2][3]).to.equal(S.RowOffset(2.5, 4))

				-- the entity's angles in radians (pitch, yaw, roll) and the drift; then its origin: the pattern is worked out in the entity's own space
				expect(near(c[3][1], 0)).to.beTrue()
				expect(near(c[3][2], 0)).to.beTrue()
				expect(near(c[3][3], 0)).to.beTrue()
				expect(c[3][4]).to.equal(0)
				expect(c[4][1]).to.equal(0)

				local placed = S.Constants(2.5, 0.5, 0.8, 1080, 3, 0.37, Vector(100, -200, 30), Angle(10, 90, -45))
				expect(near(placed[3][1], math.rad(10))).to.beTrue()
				expect(near(placed[3][2], math.rad(90))).to.beTrue()
				expect(near(placed[3][3], math.rad(-45))).to.beTrue()
				expect(near(placed[3][4], 0.37)).to.beTrue()
				expect(near(placed[4][1], 100)).to.beTrue()
				expect(near(placed[4][2], -200)).to.beTrue()
				expect(near(placed[4][3], 30)).to.beTrue()
			end
		},
		{
			name = "the game runs the shader: the test draw of a plate lights pixels",
			func = function()
				local S = GryMod.CloakFX.Shader
				local ok, lit = S.Probe()
				expect(ok).to.beTrue()
				expect(S.Works()).to.beTrue()
				expect(lit >= 20).to.beTrue()
			end
		},
		{
			name = "a shader the game does not have is told apart from the real one, and the shader is then not used: the engine draws its flat magenta the first time, nothing the next times",
			func = function()
				local S = GryMod.CloakFX.Shader
				local missing = "grymod_cloak_missing_" .. math.random(1, 1e9) .. "_ps30"
				stub(S, "PIXEL", missing)
				stub(S, "material", nil)
				stub(S, "works", nil)

				-- first material with a shader name the game cannot find: the engine's error colour fills the plate (measured: 194, 0, 194 and the like)
				stub(S, "materialName", "GryCloakSparksShaderMissingA" .. math.random(1, 1e9))
				local ok, lit = S.Probe()
				expect(ok).to.beFalse()
				expect(lit < 20).to.beTrue()
				expect(S.Works()).to.beFalse()

				-- a second material with the same missing name: nothing is drawn (measured)
				S.material = nil
				S.works = nil
				S.materialName = "GryCloakSparksShaderMissingB" .. math.random(1, 1e9)
				ok, lit = S.Probe()
				expect(ok).to.beFalse()
				expect(lit < 20).to.beTrue()
				expect(S.Works()).to.beFalse()
			end
		},
		{
			name = "it is used when the option is on and the test draw worked, and only then",
			func = function()
				local S = GryMod.CloakFX.Shader

				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")
				expect(S.Active()).to.beTrue()

				GetConVar(OPTION):SetString("0")
				expect(S.Active()).to.beFalse()

				GetConVar(OPTION):SetString("1")
				stub(S, "works", false)
				expect(S.Active()).to.beFalse()
			end
		},
		{
			name = "Draw: the entity is drawn through the shader's material, which is taken off again, and the constants are set before",
			func = function()
				local S = GryMod.CloakFX.Shader
				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")

				local material = {sets = {}}
				function material:SetFloat(k, v) self.sets[k] = v end
				stub(S, "Material", function() return material end)

				local override = {}
				stub(render, "MaterialOverride", function(m) override.current = m end)

				local ent = fakeEntity()
				local drawn = {}
				local ok = S.Draw(ent, 0.7, 0.5, function(e) drawn[#drawn + 1] = override.current e:DrawModel() end)

				expect(ok).to.beTrue()
				expect(#drawn).to.equal(1)
				expect(drawn[1]).to.equal(material)
				expect(override.current).to.beNil()
				expect(near(material.sets["$c0_z"], 0.7)).to.beTrue()
				expect(material.sets["$c0_x"]).to.exist()
				expect(material.sets["$c2_z"]).to.exist()
			end
		},
		{
			name = "Draw: nothing when the strength is nothing, when the shader is not used, or when the entity is gone",
			func = function()
				local S = GryMod.CloakFX.Shader
				local material = {}
				function material:SetFloat() end
				stub(S, "Material", function() return material end)
				stub(render, "MaterialOverride", function() end)

				local ent = fakeEntity()
				local calls = 0
				local function draw(e) calls = calls + 1 end

				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")
				expect(S.Draw(ent, 0, 0.5, draw)).to.beFalse()
				expect(S.Draw(ent, 0.005, 0.5, draw)).to.beFalse()

				local gone = fakeEntity()
				function gone:IsValid() return false end
				expect(S.Draw(gone, 0.9, 0.5, draw)).to.beFalse()

				GetConVar(OPTION):SetString("0")
				expect(S.Draw(ent, 0.9, 0.5, draw)).to.beFalse()

				expect(calls).to.equal(0)
			end
		},
		{
			name = "Draw: whatever happens while drawing, the material override comes off and the draw is reported as failed",
			func = function()
				local S = GryMod.CloakFX.Shader
				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")

				local material = {}
				function material:SetFloat() end
				stub(S, "Material", function() return material end)

				local current = "untouched"
				stub(render, "MaterialOverride", function(m) current = m end)

				local ok = S.Draw(fakeEntity(), 0.9, 0.5, function() error("boom") end)

				expect(ok).to.beFalse()
				expect(current).to.beNil()
			end
		},
		{
			name = "DriftRate: the pattern's drift while the player moves is the original's scale (0.1 of a profile length per metre a second), never more than the rest rate of its animation: the sparks run twice as fast at most",
			func = function()
				local S = GryMod.CloakFX.Shader
				expect(S.DriftRate(0)).to.equal(0)
				expect(S.DriftRate(-50)).to.equal(0)

				-- a walk (200 units a second) and a run (400): the original's metres, not the game's units
				expect(near(S.DriftRate(200), 200 / 52.49 * 0.1)).to.beTrue()
				expect(S.DriftRate(200) < S.DriftRate(400)).to.beTrue()

				-- the cap: the rate of the green lookup at rest (2 x the time's scale) added once, so twice as fast in all
				expect(near(S.DRIFT_CAP, 2 * S.TIME_SCALE)).to.beTrue()
				expect(S.DriftRate(400) <= S.DRIFT_CAP).to.beTrue()
				expect(S.DriftRate(99999)).to.equal(S.DRIFT_CAP)
				expect(S.DriftRate(1 / 0)).to.equal(S.DRIFT_CAP)
			end
		},
		{
			name = "Drift: the phase of the pattern grows with the owner's movement at the capped rate, once per frame whatever the number of draws, wraps at a whole period, and is nothing for a player who stands",
			func = function()
				local S = GryMod.CloakFX.Shader
				local frame, now = 100, 50
				stub(_G, "FrameNumber", function() return frame end)
				stub(_G, "CurTime", function() return now end)

				local owner = {speed = 0}
				function owner:IsValid() return true end
				function owner:IsPlayer() return true end
				function owner:GetVelocity() return Vector(owner.speed, 0, 0) end

				-- the weapon in his hand, and the view model, draw with the owner's movement
				local weapon = fakeEntity()
				function weapon:GetOwner() return owner end

				expect(S.Drift(owner)).to.equal(0)
				frame, now = frame + 1, now + 0.1
				expect(S.Drift(owner)).to.equal(0) -- standing: no drift at all

				owner.speed = 200
				frame, now = frame + 1, now + 0.05
				local first = S.Drift(owner)
				expect(near(first, S.DriftRate(200) * 0.05)).to.beTrue()

				-- the same frame again (the body, the weapon, a mirror): nothing more
				expect(S.Drift(owner)).to.equal(first)
				expect(S.Drift(weapon)).to.equal(first)

				-- a very long frame is cut (a pause or a loading screen is no movement)
				owner.speed = 400
				frame, now = frame + 1, now + 30
				local second = S.Drift(owner)
				expect(near((second - first) % 1, S.DriftRate(400) * 0.1)).to.beTrue()

				-- always in a whole period: the profile repeats
				for _ = 1, 40 do
					frame, now = frame + 1, now + 0.1
					local phase = S.Drift(owner)
					expect(phase >= 0 and phase < 1).to.beTrue()
				end
			end
		},
		{
			name = "the drift goes to the shader's fourth component of the colour register, and Draw gives the owner's",
			func = function()
				local S = GryMod.CloakFX.Shader
				expect(near(S.Constants(1, 0.5, 0.8, 1080, 3, 0.37)[3][4], 0.37)).to.beTrue()
				expect(S.Constants(1, 0.5, 0.8, 1080, 3)[3][4]).to.equal(0)

				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")
				local material = {sets = {}}
				function material:SetFloat(k, v) self.sets[k] = v end
				stub(S, "Material", function() return material end)
				stub(render, "MaterialOverride", function() end)
				stub(S, "Drift", function() return 0.25 end)

				S.Draw(fakeEntity(), 0.7, 0.5, function() end)
				expect(near(material.sets["$c2_w"], 0.25)).to.beTrue()
			end
		},
		{
			name = "Draw gives the shader the entity's own origin and angles",
			func = function()
				local S = GryMod.CloakFX.Shader
				stub(S, "works", true)
				GetConVar(OPTION):SetString("1")
				local material = {sets = {}}
				function material:SetFloat(k, v) self.sets[k] = v end
				stub(S, "Material", function() return material end)
				stub(render, "MaterialOverride", function() end)

				local ent = fakeEntity()
				ent.pos, ent.ang = Vector(11, 22, 33), Angle(0, 90, 0)
				S.Draw(ent, 0.7, 0.5, function() end)

				expect(near(material.sets["$c3_x"], 11)).to.beTrue()
				expect(near(material.sets["$c3_y"], 22)).to.beTrue()
				expect(near(material.sets["$c3_z"], 33)).to.beTrue()
				expect(near(material.sets["$c2_y"], math.rad(90))).to.beTrue()
			end
		},
		{
			name = "the pattern sticks to the entity (measured with the real shader): the same plate moved to another place shows the same sparks when it is given its own origin and not when it is not, and a plate turned a quarter shows them turned when it is given its angles (the pattern was fixed to the world, and a walking player slid through it)",
			func = function()
				local S = GryMod.CloakFX.Shader
				local material = S.Material()
				local size = 64
				local target = GetRenderTarget("GryCloakShaderStickProbe", size, size)
				local plate = ClientsideModel(S.PROBE_MODEL)
				plate:SetNoDraw(true)

				-- somewhere in front of the player: a model drawn far from the view is culled, and a model that is not in the scene is drawn where it was
				-- until its bones are made again
				local me = LocalPlayer()
				local base = me:EyePos() + me:EyeAngles():Forward() * 150

				-- the blue of the plate's middle (48 x 48 pixels), one row to a period so that the scan lines are even
				local function shoot(pos, ang, given)
					plate:SetPos(pos)
					plate:SetAngles(ang)
					plate:SetupBones()
					plate:InvalidateBoneCache()
					local c = S.Constants(0.37 / S.TIME_SCALE, 0.5, 1, 1080, 0, 0, given and pos or Vector(0, 0, 0), given and ang or Angle(0, 0, 0))
					c[1][4] = 1
					c[2][3] = 0

					for r = 1, 4 do
						for i, k in ipairs({"x", "y", "z", "w"}) do
							material:SetFloat("$c" .. (r - 1) .. "_" .. k, c[r][i])
						end
					end

					local pixels = {}
					render.PushRenderTarget(target)
					local ok, err = pcall(function()
						render.Clear(0, 0, 0, 255, true, true)
						cam.Start({type = "3D", origin = pos + Vector(0, 0, 100), angles = Angle(90, 0, 0), x = 0, y = 0, w = size, h = size,
							ortho = {left = -24, right = 24, top = -24, bottom = 24}, znear = 1, zfar = 300})
						render.MaterialOverride(material)
						plate:DrawModel()
						render.MaterialOverride(nil)
						cam.End3D()
						render.CapturePixels()

						for y = 8, 55 do
							for x = 8, 55 do
								local _, _, b = render.ReadPixel(x, y)
								pixels[#pixels + 1] = b
							end
						end
					end)
					render.PopRenderTarget()
					render.MaterialOverride(nil)

					if not ok then
						error(err, 0)
					end

					return pixels
				end

				local function diff(a, b)
					local sum = 0

					for i = 1, #a do
						sum = sum + math.abs(a[i] - b[i])
					end

					return sum / #a
				end

				-- 6 x 6 blocks of 8 x 8 pixels, each its mean: a turn puts the pixels half a pixel off, which a pattern this fine does not forgive
				local function blocks(pixels)
					local out = {}

					for by = 0, 5 do
						for bx = 0, 5 do
							local sum = 0

							for y = 1, 8 do
								for x = 1, 8 do
									sum = sum + pixels[(by * 8 + y - 1) * 48 + bx * 8 + x]
								end
							end

							out[by * 6 + bx + 1] = sum / 64
						end
					end

					return out
				end

				local function turned(b, quarters)
					local out = {}

					for y = 1, 6 do
						for x = 1, 6 do
							local sx, sy = x, y

							for _ = 1, quarters do
								sx, sy = sy, 7 - sx
							end

							out[(y - 1) * 6 + x] = b[(sy - 1) * 6 + sx]
						end
					end

					return out
				end

				local ok, err = pcall(function()
					local here = shoot(base, Angle(0, 0, 0), true)
					local lit = 0

					for i = 1, #here do
						if here[i] > 20 then lit = lit + 1 end
					end

					expect(lit > 50).to.beTrue() -- the sparks are there at all

					-- moved: the same picture when it is given its place, another one when it is not
					expect(diff(here, shoot(base + Vector(30, 0, 0), Angle(0, 0, 0), true)) < 1).to.beTrue()
					expect(diff(here, shoot(base + Vector(30, 0, 0), Angle(0, 0, 0), false)) > 5).to.beTrue()
					expect(diff(here, shoot(base + Vector(0, 0, 30), Angle(0, 0, 0), true)) < 1).to.beTrue()
					expect(diff(here, shoot(base + Vector(0, 0, 30), Angle(0, 0, 0), false)) > 5).to.beTrue()

					-- turned a quarter: with its angles one of the four turns of the first picture matches, and the others do not
					local rotated = blocks(shoot(base, Angle(0, 90, 0), true))
					local first = blocks(here)
					local best, worst = math.huge, 0

					for quarters = 0, 3 do
						local d = diff(first, turned(rotated, quarters))
						best, worst = math.min(best, d), math.max(worst, d)
					end

					expect(best < 6).to.beTrue()
					expect(worst > 12).to.beTrue()

					-- without its angles the pattern does not turn with it (it stays as the world has it)
					local fixed = blocks(shoot(base, Angle(0, 90, 0), false))
					local sticks = math.huge

					for quarters = 1, 3 do
						sticks = math.min(sticks, diff(first, turned(fixed, quarters)))
					end

					expect(sticks > 12).to.beTrue()
				end)

				plate:Remove()

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
