-- Tests of the camouflage's refraction layer (cl_cloak_refract.lua), GLuaTest format, client realm. In the original game the cloak is a layer drawn
-- over the suit: the picture behind, bent by the suit's own relief and tinted at its edges, blended with the cloak's level as its alpha
-- (CloakRefrationPS, shaders/src: dev_resources/shaders/grymod_cloak_refract_*.hlsl). Source's own Refract material ignores alpha, so the layer is
-- a pixel shader of its own, drawn over the model the engine has drawn. Each part of a model gets its own relief map (its material's $bumpmap),
-- and the generic one when it has none. Nothing is shown on the screen by these cases: the render calls are recorders.

local OPTION = "gry_cloak_refract"

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

local function near(a, b, tolerance)
	return math.abs(a - b) < (tolerance or 1e-6)
end

local originalOption
local realLocalPlayer = LocalPlayer

-- The probe's wait: a Think hook that exists only until the test draw is made (or the option is off), and a callback on the option that puts it back.
local PROBE = "GryCloakRefractProbe"

local function probeHook()
	return hook.GetTable().Think and hook.GetTable().Think[PROBE]
end

-- The file loaded again, as a hot reload does it (and a new map: the client's Lua state starts over).
local function reloadFile()
	include("grymod/client/cl_cloak_refract.lua")
end

local function countCallbacks()
	local count = 0

	for _, entry in ipairs(cvars.GetConVarCallbacks(OPTION, false) or {}) do
		if entry[2] == PROBE then
			count = count + 1
		end
	end

	return count
end

return {
	groupName = "GryMod camouflage refraction layer (client)",
	beforeAll = function()
		originalOption = GetConVar(OPTION) and GetConVar(OPTION):GetString()
	end,
	afterEach = function()
		restore()

		if GetConVar(OPTION) and originalOption then
			GetConVar(OPTION):SetString(originalOption)
		end

		-- the game's own state: a layer whose test is made waits for nothing (whatever a case did while the test was pending)
		if GryMod.CloakFX.Refract.works ~= nil then
			hook.Remove("Think", PROBE)
		end
	end,
	cases = {
		{
			name = "the option exists, is on by default, and has a check box in the options panel",
			func = function()
				local c = GetConVar(OPTION)
				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
				expect(GryMod.CloakFX.Refract ~= nil).to.beTrue()

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
			name = "the bend is the original's bump scale: 2.75 at the start of the change, 0.25 once done (eleven times less)",
			func = function()
				local R = GryMod.CloakFX.Refract
				expect(near(R.BumpScale(0), 2.75 * R.BEND_GAIN)).to.beTrue()
				expect(near(R.BumpScale(1), 0.25 * R.BEND_GAIN)).to.beTrue()
				expect(near(R.BumpScale(0.5), 1.5 * R.BEND_GAIN)).to.beTrue()
				-- out of range levels are cut
				expect(near(R.BumpScale(-1), R.BumpScale(0))).to.beTrue()
				expect(near(R.BumpScale(2), R.BumpScale(1))).to.beTrue()
			end
		},
		{
			name = "the layer's alpha is what the plain model has lost, never out of 0 to 1",
			func = function()
				local R = GryMod.CloakFX.Refract
				expect(near(R.Alpha(1), 0)).to.beTrue()
				expect(near(R.Alpha(0.28), 0.72)).to.beTrue()
				expect(near(R.Alpha(0.03), 0.97)).to.beTrue()
				expect(R.Alpha(1.3)).to.equal(0)
				expect(R.Alpha(-0.2)).to.equal(1)
			end
		},
		{
			name = "the constants given to the shader: bump scale, alpha, rim light, rows to a period; the scan lines' offset and the half pixel; the units; the relief map's tiling",
			func = function()
				local R = GryMod.CloakFX.Refract
				local c = R.Constants(1.5, 0.7, 2.5, 1920, 1080, 2)
				expect(near(c[1][1], 1.5)).to.beTrue()
				expect(near(c[1][2], 0.7)).to.beTrue()
				expect(near(c[1][3], R.RIM_LIGHT)).to.beTrue()
				expect(c[1][4]).to.equal(4)

				expect(c[2][1]).to.equal(GryMod.CloakFX.Shader.RowOffset(2.5, 4))
				expect(near(c[2][2], 0.5 / 1920)).to.beTrue()
				expect(near(c[2][3], 0.5 / 1080)).to.beTrue()
				expect(near(c[2][4], 52.49)).to.beTrue()

				expect(near(c[3][1], 2)).to.beTrue()
				expect(near(c[3][2], R.RELIEF)).to.beTrue()

				-- the scan lines are as large on a taller screen as the sparks' are
				expect(R.Constants(1, 1, 0, 3840, 2160, 1)[1][4]).to.equal(8)
			end
		},
		{
			name = "a model's part gets its own relief map: the one of its material, or the generic one when it has none",
			func = function()
				local R = GryMod.CloakFX.Refract
				local part = R.Part("models/weapons/v_physcannon/v_physcannon_sheet")
				expect(part ~= nil).to.beTrue()
				expect(part.material:GetTexture("$texture1"):GetName()).to.equal("models/weapons/v_physcannon/v_physcannon_normal")
				expect(part.tiling).to.equal(1)

				-- a material with no relief map of its own, or that does not exist: the generic one, tiled over the model's coordinates
				local plain = R.Part("models/debug/debugwhite")
				expect(plain.material:GetTexture("$texture1"):GetName()).to.equal(R.BUMP)
				expect(plain.tiling).to.equal(R.GENERIC_TILING)

				local missing = R.Part("models/grymod_does_not_exist/nothing")
				expect(missing.material:GetTexture("$texture1"):GetName()).to.equal(R.BUMP)

				-- one material for each, made once
				expect(R.Part("models/weapons/v_physcannon/v_physcannon_sheet")).to.equal(part)
			end
		},
		{
			name = "the game runs the shader: the test draw of a plate shows the picture behind, not the engine's error colour nor nothing",
			func = function()
				local R = GryMod.CloakFX.Refract
				local ok, drawn = R.Probe()
				expect(ok).to.beTrue()
				expect(R.Works()).to.beTrue()
				expect(drawn >= 0.9).to.beTrue()
			end
		},
		{
			name = "a shader the game does not have is told apart: the layer is then not used",
			func = function()
				local R = GryMod.CloakFX.Refract
				stub(R, "PIXEL", "grymod_cloak_refract_missing_" .. math.random(1, 1e9) .. "_ps30")
				stub(R, "works", nil)

				local ok, drawn = R.Probe()
				expect(ok).to.beFalse()
				expect(drawn < 0.9).to.beTrue()
				expect(R.Works()).to.beFalse()
			end
		},
		{
			name = "it is used when the option is on and the test draw worked, and only then",
			func = function()
				local R = GryMod.CloakFX.Refract

				stub(R, "works", true)
				GetConVar(OPTION):SetString("1")
				expect(R.Active()).to.beTrue()

				GetConVar(OPTION):SetString("0")
				expect(R.Active()).to.beFalse()

				GetConVar(OPTION):SetString("1")
				stub(R, "works", false)
				expect(R.Active()).to.beFalse()
			end
		},
		{
			name = "Draw: every part of the model is overridden with its own material, the constants are set, and the overrides come off whatever happens",
			func = function()
				local R = GryMod.CloakFX.Refract
				stub(R, "works", true)
				GetConVar(OPTION):SetString("1")

				local sets = {}
				local material = {}
				function material:SetFloat(k, v) sets[#sets + 1] = k end
				stub(R, "Part", function(path) return {material = material, tiling = 1} end)

				local overrides = {}
				stub(render, "MaterialOverrideByIndex", function(index, m) overrides[#overrides + 1] = {index = index, material = m} end)

				local ent = {drawn = 0}
				function ent:IsValid() return true end
				function ent:GetMaterials() return {"a", "b", "c"} end
				local model = "models/test_" .. math.random(1, 1e9) .. ".mdl" -- the parts of a model are kept: each case has its own
				function ent:GetModel() return model end

				local seen
				local ok = R.Draw(ent, 1.5, 0.7, function(e) seen = #overrides end)

				expect(ok).to.beTrue()
				expect(seen).to.equal(3) -- all the parts were overridden before the draw
				expect(#overrides).to.equal(6) -- and all taken off again after it
				expect(overrides[4].material).to.beNil()
				expect(overrides[1].index).to.equal(0)
				expect(overrides[3].index).to.equal(2)
				expect(#sets > 0).to.beTrue()

				-- a draw that fails: the overrides still come off, and it is reported
				overrides = {}
				ok = R.Draw(ent, 1.5, 0.7, function() error("boom") end)
				expect(ok).to.beFalse()
				expect(#overrides).to.equal(6)
			end
		},
		{
			name = "Draw: a constant that has not changed is not set again (the same numbers a frame later set nothing, a new alpha sets only the alpha), each part keeps its own tiling, and everything is set again after a second",
			func = function()
				local R = GryMod.CloakFX.Refract
				stub(R, "works", true)
				GetConVar(OPTION):SetString("1")

				local function newMaterial()
					local m = {sets = {}, count = 0}
					function m:SetFloat(k, v) self.sets[k] = v self.count = self.count + 1 end

					return m
				end

				local a, b = newMaterial(), newMaterial()
				local byPath = {a = {material = a, tiling = 1}, b = {material = b, tiling = 2}}
				stub(R, "Part", function(path) return byPath[path] end)
				stub(render, "MaterialOverrideByIndex", function() end)

				local now = 500
				stub(_G, "CurTime", function() return 100 end)
				stub(_G, "RealTime", function() return now end)

				local ent = {}
				function ent:IsValid() return true end
				function ent:GetMaterials() return {"a", "b"} end
				local model = "models/test_" .. math.random(1, 1e9) .. ".mdl"
				function ent:GetModel() return model end

				local function noop() end

				R.Draw(ent, 1.5, 0.7, noop)
				expect(a.count).to.equal(12)
				expect(b.count).to.equal(12)
				expect(a.sets["$c2_x"]).to.equal(1)
				expect(b.sets["$c2_x"]).to.equal(2)

				-- the same numbers on the next frame: nothing to set
				R.Draw(ent, 1.5, 0.7, noop)
				expect(a.count).to.equal(12)
				expect(b.count).to.equal(12)

				-- the alpha moved (the change of the camouflage): that one constant, on each part
				R.Draw(ent, 1.5, 0.4, noop)
				expect(a.count).to.equal(13)
				expect(b.count).to.equal(13)
				expect(near(a.sets["$c0_y"], 0.4)).to.beTrue()
				expect(b.sets["$c2_x"]).to.equal(2)

				-- a material may be changed from outside (a reload): nothing stays wrong for more than a second
				now = now + 1.5
				R.Draw(ent, 1.5, 0.4, noop)
				expect(a.count).to.equal(25)
				expect(b.count).to.equal(25)
			end
		},
		{
			name = "Constants can fill the tables it is given (the draw makes no new table for each part of each model each frame): same numbers, same tables back",
			func = function()
				local R = GryMod.CloakFX.Refract
				local into = R.Constants(1, 0.5, 10, 1920, 1080, 1)
				local first = into[1]
				local again = R.Constants(2, 0.25, 11, 1280, 720, 2, into)
				local fresh = R.Constants(2, 0.25, 11, 1280, 720, 2)

				expect(again).to.equal(into)
				expect(again[1]).to.equal(first)

				for r = 1, 3 do
					for i = 1, 4 do
						expect(near(again[r][i], fresh[r][i])).to.beTrue()
					end
				end
			end
		},
		{
			name = "Draw: nothing when the layer is not used, when the alpha is nothing, or when the entity is gone",
			func = function()
				local R = GryMod.CloakFX.Refract
				stub(R, "Part", function() return {material = {SetFloat = function() end}, tiling = 1} end)
				stub(render, "MaterialOverrideByIndex", function() end)

				local ent = {}
				function ent:IsValid() return true end
				function ent:GetMaterials() return {"a"} end
				local model = "models/test_" .. math.random(1, 1e9) .. ".mdl" -- the parts of a model are kept: each case has its own
				function ent:GetModel() return model end
				local calls = 0
				local function draw() calls = calls + 1 end

				stub(R, "works", true)
				GetConVar(OPTION):SetString("1")
				expect(R.Draw(ent, 1, 0, draw)).to.beFalse()
				expect(R.Draw(ent, 1, 0.005, draw)).to.beFalse()

				local gone = {}
				function gone:IsValid() return false end
				expect(R.Draw(gone, 1, 0.9, draw)).to.beFalse()

				GetConVar(OPTION):SetString("0")
				expect(R.Draw(ent, 1, 0.9, draw)).to.beFalse()

				expect(calls).to.equal(0)
			end
		},
		{
			name = "the test draw is made on its own, once, 3.5 s after the map is up, and the Think hook that waits for it is gone the moment it is made (it ran every frame of the game for nothing; fails if the hook stays and only returns early)",
			func = function()
				local R = GryMod.CloakFX.Refract
				local now = 100
				local probes = 0
				stub(_G, "CurTime", function() return now end)
				stub(R, "works", nil)
				GetConVar(OPTION):SetString("1")

				-- the file loaded as it is on a new map: the test not made yet, so the hook waits
				reloadFile()
				stub(R, "Probe", function() probes = probes + 1 R.works = true return true, 1 end)
				local fn = probeHook()
				expect(fn).to.exist()

				-- the time starts at the first frame with a player; before 3.5 s nothing is drawn
				fn()
				now = 103.4
				fn()
				expect(probes).to.equal(0)
				expect(probeHook()).to.equal(fn)

				-- a map where the player is not there yet: the time does not start
				now = 500
				stub(_G, "LocalPlayer", function() return NULL end)
				fn()
				now = 504
				fn()
				expect(probes).to.equal(0)
				expect(probeHook()).to.equal(fn)
				stub(_G, "LocalPlayer", realLocalPlayer)

				-- the player is there: 3.5 s later the test draw is made, once, and the hook is gone
				now = 600
				fn()
				now = 603.5
				fn()
				expect(probes).to.equal(1)
				expect(probeHook() == nil).to.beTrue()

				-- an old reference to the hook (a frame already under way) draws nothing more
				now = 700
				fn()
				expect(probes).to.equal(1)
			end
		},
		{
			name = "a file loaded again (a hot reload) puts back no hook when the test is made, and one hook with the time started again when it is not; one callback on the option whatever the number of loads (fails if the hook is put back whatever the state, or a callback is added at each load)",
			func = function()
				local R = GryMod.CloakFX.Refract
				local now = 100
				local probes = 0
				stub(_G, "CurTime", function() return now end)
				GetConVar(OPTION):SetString("1")

				local function countProbe()
					stub(R, "Probe", function() probes = probes + 1 R.works = true return true, 1 end)
				end

				-- already made: no hook is put back
				stub(R, "works", true)
				reloadFile()
				expect(probeHook() == nil).to.beTrue()

				-- not made: a hook, and a reload in the middle of the wait starts the 3.5 s again
				R.works = nil
				reloadFile()
				countProbe()
				probeHook()()
				now = 103
				reloadFile()
				countProbe()
				local fn = probeHook()
				fn()
				now = 106.4
				fn()
				expect(probes).to.equal(0)
				now = 106.5
				fn()
				expect(probes).to.equal(1)
				expect(probeHook() == nil).to.beTrue()

				expect(countCallbacks()).to.equal(1)
			end
		},
		{
			name = "the option off takes the hook away, and on again puts it back when the test is not made (a callback on the option); when the test is made nothing comes back (fails without that callback: the test would never be made for a player who switched it on later)",
			func = function()
				local R = GryMod.CloakFX.Refract
				local now = 100
				local probes = 0
				stub(_G, "CurTime", function() return now end)
				stub(R, "works", nil)
				GetConVar(OPTION):SetString("1")
				reloadFile()
				stub(R, "Probe", function() probes = probes + 1 R.works = true return true, 1 end)
				expect(probeHook()).to.exist()

				-- wanted off: the hook leaves at once (or at the latest at its next frame), and nothing is drawn
				GetConVar(OPTION):SetString("0")
				local fn = probeHook()

				if fn then
					now = 101
					fn()
				end

				expect(probeHook() == nil).to.beTrue()
				now = 200
				expect(probes).to.equal(0)

				-- wanted again, test not made: the hook is back and the test draw is made after its delay
				GetConVar(OPTION):SetString("1")
				fn = probeHook()
				expect(fn).to.exist()
				now = 300
				fn()
				now = 303.5
				fn()
				expect(probes).to.equal(1)
				expect(probeHook() == nil).to.beTrue()

				-- test made: switching the option does not bring the hook back
				GetConVar(OPTION):SetString("0")
				GetConVar(OPTION):SetString("1")
				expect(probeHook() == nil).to.beTrue()
				expect(probes).to.equal(1)
			end
		},
		{
			name = "the picture behind is read through the sRGB conversion the engine applies to colours (read as it is the arms came out too bright and glassy): there is no option for the other way",
			func = function()
				local R = GryMod.CloakFX.Refract
				local part = R.Part("models/debug/debugwhite")
				expect(part.material:GetInt("$linearread_basetexture")).to.equal(0)

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

				expect(found["gry_cloak_refract_look"] == nil).to.beTrue()
			end
		}
	}
}
