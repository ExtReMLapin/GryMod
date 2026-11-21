-- Tests of the scan lines of the camouflage (cl_cloak_lines.lua), GLuaTest format, client realm. In the original game the
-- sparks of a camouflaged suit are blotches of electric blue crossed by fine horizontal lines that move every frame. Here
-- the lines are drawn in SCREEN space, only where the camouflaged player's silhouette is (the stencil buffer), with a tiled
-- picture of lines and blotches, so that they stay horizontal on the screen whatever the model's texture coordinates are.
-- Nothing is drawn by these cases: the render calls are recorders, put back after every case.

local OPTION = "gry_cloak_lines"

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

local function option()
	return GetConVar(OPTION)
end

-- every render, cam and surface call the drawing makes, in order, with what the stencil state was at that moment
local function record()
	local log = {calls = {}, stencil = false, colorWrite = true, compare = nil}
	local function add(name, ...) log.calls[#log.calls + 1] = {name = name, args = {...}, stencil = log.stencil, colorWrite = log.colorWrite, compare = log.compare} end

	stub(render, "SetStencilEnable", function(on) log.stencil = on add("SetStencilEnable", on) end)
	stub(render, "SetStencilWriteMask", function(v) add("SetStencilWriteMask", v) end)
	stub(render, "SetStencilTestMask", function(v) add("SetStencilTestMask", v) end)
	stub(render, "SetStencilReferenceValue", function(v) add("SetStencilReferenceValue", v) end)
	stub(render, "SetStencilCompareFunction", function(v) log.compare = v add("SetStencilCompareFunction", v) end)
	stub(render, "SetStencilPassOperation", function(v) add("SetStencilPassOperation", v) end)
	stub(render, "SetStencilFailOperation", function(v) add("SetStencilFailOperation", v) end)
	stub(render, "SetStencilZFailOperation", function(v) add("SetStencilZFailOperation", v) end)
	stub(render, "ClearStencilBufferRectangle", function(...) add("ClearStencilBufferRectangle", ...) end)
	stub(render, "OverrideColorWriteEnable", function(on, value) log.colorWrite = not on or value add("OverrideColorWriteEnable", on, value) end)
	stub(cam, "Start2D", function() add("Start2D") end)
	stub(cam, "End2D", function() add("End2D") end)
	stub(surface, "SetMaterial", function(m) add("SetMaterial", m) end)
	stub(surface, "SetDrawColor", function(...) add("SetDrawColor", ...) end)
	stub(surface, "DrawTexturedRectUV", function(...) add("DrawTexturedRectUV", ...) end)

	return log
end

local function count(log, name)
	local n = 0

	for _, c in ipairs(log.calls) do
		if c.name == name then n = n + 1 end
	end

	return n
end

local function first(log, name)
	for _, c in ipairs(log.calls) do
		if c.name == name then return c end
	end
end

-- a player that is only an entity for the lines (its corners on the screen are given by ScreenPoints, replaced below)
local function fakePlayer(speed)
	local ply = {draws = 0, center = Vector(300, 0, 0)}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:Alive() return true end
	function ply:IsDormant() return false end
	function ply:WorldSpaceCenter() return self.center end
	function ply:ShouldDrawLocalPlayer() return true end
	function ply:DrawShadow() end
	function ply:GetViewModel() return NULL end
	function ply:GetNWBool() return false end
	function ply:EntIndex() return 99 end
	function ply:GetVelocity() return Vector(speed or 0, 0, 0) end
	function ply:DrawModel() self.draws = self.draws + 1 end
	function ply:GetActiveWeapon() return NULL end

	return ply
end

local boxOnScreen = {{x = 400, y = 200, visible = true}, {x = 560, y = 200, visible = true}, {x = 400, y = 640, visible = true}, {x = 560, y = 640, visible = true}}

return {
	groupName = "GryMod camouflage scan lines",
	beforeEach = function(state)
		state.optionBefore = option() and option():GetString()

		if option() then
			option():SetString("1")
		end
	end,
	afterEach = function(state)
		restore()

		if state.optionBefore and option() then
			option():SetString(state.optionBefore)
		end

		local F = GryMod.CloakFX

		if F then
			F.SetDrawHooks(next(F.States) ~= nil)

			for ply in pairs(F.States) do
				F.States[ply] = nil
			end
		end
	end,
	cases = {
		{
			name = "the option exists (saved, on by default) and has a check box in the options panel",
			func = function()
				expect(GryMod.CloakFX.Lines).to.exist()
				expect(option() ~= nil).to.beTrue()
				expect(option():GetDefault()).to.equal("1")

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
			name = "Rect: the box that holds the corners on the screen, with a margin, kept inside the screen; nothing when no corner is in front of the camera or the box is off screen or tiny",
			func = function()
				local L = GryMod.CloakFX.Lines
				local x, y, w, h = L.Rect(boxOnScreen, 1920, 1080)

				expect(x).to.equal(400 - L.MARGIN)
				expect(y).to.equal(200 - L.MARGIN)
				expect(w).to.equal(160 + 2 * L.MARGIN)
				expect(h).to.equal(440 + 2 * L.MARGIN)

				-- partly outside: cut at the screen's edges
				local x2, y2, w2, h2 = L.Rect({{x = -100, y = -50, visible = true}, {x = 100, y = 100, visible = true}}, 1920, 1080)
				expect(x2).to.equal(0)
				expect(y2).to.equal(0)
				expect(w2).to.equal(100 + L.MARGIN)
				expect(h2).to.equal(100 + L.MARGIN)

				-- corners behind the camera are ignored; the ones in front still count
				local x3 = L.Rect({{x = 500, y = 500, visible = false}, {x = 600, y = 300, visible = true}, {x = 700, y = 400, visible = true}}, 1920, 1080)
				expect(x3).to.equal(600 - L.MARGIN)

				expect(L.Rect({{x = 500, y = 500, visible = false}}, 1920, 1080)).to.beNil()
				expect(L.Rect({}, 1920, 1080)).to.beNil()
				expect(L.Rect({{x = 3000, y = 100, visible = true}, {x = 3100, y = 200, visible = true}}, 1920, 1080)).to.beNil()
				expect(L.Rect({{x = 500, y = 500, visible = true}, {x = 501, y = 501, visible = true}}, 1920, 1080) ~= nil).to.beTrue()
			end
		},
		{
			name = "Offset: the lines jump to another place every frame (a whole number of lines), the blotches drift slowly; the same frame gives the same offset",
			func = function()
				local L = GryMod.CloakFX.Lines
				local u1, v1 = L.Offset(10, 2)
				local u1b, v1b = L.Offset(10, 2)
				expect(u1).to.equal(u1b)
				expect(v1).to.equal(v1b)

				local seen = {}

				for frame = 1, 40 do
					local u, v = L.Offset(frame, 2)
					expect(u >= 0 and u < 1).to.beTrue()
					expect(v >= 0 and v < 1).to.beTrue()

					-- a whole number of line periods in the texture
					local lines = v * L.TEXTURE / L.PERIOD
					expect(math.abs(lines - math.floor(lines + 0.5)) < 0.0001).to.beTrue()
					seen[math.floor(v * 1000)] = true
				end

				local distinct = 0

				for _ in pairs(seen) do distinct = distinct + 1 end

				expect(distinct).to.beGreaterThan(5)

				-- the drift of the blotches: later in time, further along
				local ua = L.Offset(5, 1)
				local ub = L.Offset(5, 1.5)
				expect(ua ~= ub).to.beTrue()
			end
		},
		{
			name = "UV: one texel is one pixel of a 1080 screen; the picture is bigger on a bigger screen and smaller on a smaller one (the lines keep their look)",
			func = function()
				local L = GryMod.CloakFX.Lines
				local u0, v0, u1, v1 = L.UV(512, 256, 1080, 0.25, 0.5)

				expect(u0).to.equal(0.25)
				expect(v0).to.equal(0.5)
				expect(u1 - u0).to.aboutEqual(512 / L.TEXTURE, 0.0001)
				expect(v1 - v0).to.aboutEqual(256 / L.TEXTURE, 0.0001)

				-- twice the height: half the texture covers the same box
				local _, _, a1 = L.UV(512, 256, 2160, 0, 0)
				expect(a1).to.aboutEqual(256 / L.TEXTURE, 0.0001)
			end
		},
		{
			name = "Alpha: follows the sparks' strength, never above 1, 0 when there are none",
			func = function()
				local L = GryMod.CloakFX.Lines

				expect(L.Alpha(0)).to.equal(0)
				expect(L.Alpha(-1)).to.equal(0)
				expect(L.Alpha(1)).to.beBetween(0.5, 1)
				expect(L.Alpha(5)).to.equal(1)
				expect(L.Alpha(0.5) < L.Alpha(1)).to.beTrue()
			end
		},
		{
			name = "Draw does nothing with the option off, with no strength, or when the player's box is not on the screen",
			func = function()
				local L = GryMod.CloakFX.Lines
				local log = record()
				local ply = fakePlayer()
				stub(L, "ScreenPoints", function() return boxOnScreen end)
				local drew = 0
				local function draw() drew = drew + 1 end

				option():SetString("0")
				L.Draw(ply, 1, draw)
				option():SetString("1")
				L.Draw(ply, 0, draw)
				stub(L, "ScreenPoints", function() return {} end)
				L.Draw(ply, 1, draw)

				expect(#log.calls).to.equal(0)
				expect(drew).to.equal(0)
			end
		},
		{
			name = "Draw: the silhouette goes into the stencil with no colour written, then the lines are drawn only where the stencil says so, in the box, and the state is put back",
			func = function()
				local L = GryMod.CloakFX.Lines
				local log = record()
				local ply = fakePlayer()
				stub(L, "ScreenPoints", function() return boxOnScreen end)
				local drawnWhile

				local ok = L.Draw(ply, 1, function(ent)
					drawnWhile = {stencil = log.stencil, colorWrite = log.colorWrite, compare = log.compare, ent = ent}
				end)

				expect(ok).to.beTrue()
				expect(drawnWhile.ent).to.equal(ply)
				expect(drawnWhile.stencil).to.beTrue()
				expect(drawnWhile.colorWrite).to.beFalse()
				expect(drawnWhile.compare).to.equal(STENCIL_ALWAYS)

				-- the lines: one textured quad, with the stencil tested (equal) and the colours written, in the box
				expect(count(log, "DrawTexturedRectUV")).to.equal(1)
				local quad = first(log, "DrawTexturedRectUV")
				expect(quad.stencil).to.beTrue()
				expect(quad.colorWrite).to.beTrue()
				expect(quad.compare).to.equal(STENCIL_EQUAL)
				expect(quad.args[1]).to.equal(400 - L.MARGIN)
				expect(quad.args[2]).to.equal(200 - L.MARGIN)
				expect(count(log, "Start2D")).to.equal(1)
				expect(count(log, "End2D")).to.equal(1)

				-- the end: stencil off, colours written
				expect(log.stencil).to.beFalse()
				expect(log.colorWrite).to.beTrue()
			end
		},
		{
			name = "Draw puts the render state back even when the drawing of the model fails, and reports it",
			func = function()
				local L = GryMod.CloakFX.Lines
				local log = record()
				stub(L, "ScreenPoints", function() return boxOnScreen end)

				local ok, err = L.Draw(fakePlayer(), 1, function() error("boom", 0) end)

				expect(ok).to.beFalse()
				expect(tostring(err)).to.contain("boom")
				expect(log.stencil).to.beFalse()
				expect(log.colorWrite).to.beTrue()
				-- a 2D context that was opened is closed
				expect(count(log, "Start2D")).to.equal(count(log, "End2D"))
			end
		},
		{
			name = "the camouflage's draw hook adds the lines for a camouflaged player in range with sparks, hands them a draw that the player's own hook lets through, and not for a far or still one",
			func = function()
				local F = GryMod.CloakFX
				local L = F.Lines
				F.SetDrawHooks(true)
				stub(render, "UpdateRefractTexture", function() end)
				stub(render, "MaterialOverride", function() end)
				stub(render, "SetBlend", function() end)
				stub(render, "SetColorModulation", function() end)
				stub(_G, "EyePos", function() return Vector(0, 0, 0) end)
				stub(_G, "EyeVector", function() return Vector(1, 0, 0) end)

				local calls = {}
				stub(L, "Draw", function(ent, strength, draw)
					calls[#calls + 1] = {ent = ent, strength = strength}
					-- the player's own draw hook must let this draw through
					draw(ent)

					return true
				end)

				local moving, still, far = fakePlayer(300), fakePlayer(0), fakePlayer(300)
				far.center = Vector(F.DetailDistance + 500, 0, 0)

				for _, p in ipairs({moving, still, far}) do
					F.States[p] = {amount = 1, speed = p:GetVelocity():Length(), cloaked = true}
				end

				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, false)

				expect(#calls).to.equal(1)
				expect(calls[1].ent).to.equal(moving)
				expect(calls[1].strength > 0.5).to.beTrue()
				-- the model was drawn by the lines' draw (the player's draws: 3 layers + the lines for this one)
				expect(moving.draws).to.equal(4)
			end
		}
	}
}
