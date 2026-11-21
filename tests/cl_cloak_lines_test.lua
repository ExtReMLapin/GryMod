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
			name = "Offset: the lines jump by a whole number of rows (0 to 3: the interlation has four rows to a period) at every frame, the picture drifts slowly sideways; the same frame gives the same offset",
			func = function()
				local L = GryMod.CloakFX.Lines
				local ox1, oy1 = L.Offset(10, 2)
				local ox2, oy2 = L.Offset(10, 2)
				expect(ox1).to.equal(ox2)
				expect(oy1).to.equal(oy2)

				local seen = {}

				for frame = 1, 40 do
					local ox, oy = L.Offset(frame, 2)
					expect(oy >= 0 and oy < L.PERIOD).to.beTrue()
					expect(oy).to.equal(math.floor(oy))
					expect(ox >= 0 and ox < L.CELL).to.beTrue()
					seen[oy] = true
				end

				local distinct = 0

				for _ in pairs(seen) do distinct = distinct + 1 end

				-- every phase of the lines comes up
				expect(distinct).to.equal(L.PERIOD)

				-- the drift: later in time, further along
				local oa = L.Offset(5, 1)
				local ob = L.Offset(5, 1.5)
				expect(oa ~= ob).to.beTrue()
			end
		},
		{
			name = "Cell: the picture of the sparks changes at RATE a second, through every cell of the atlas in turn (the sparks never stand still), never out of the atlas",
			func = function()
				local L = GryMod.CloakFX.Lines

				expect(L.RATE >= 24).to.beTrue()
				expect(L.Cell(0)).to.equal(0)
				expect(L.Cell(0.5 / L.RATE)).to.equal(0)
				expect(L.Cell(1.5 / L.RATE)).to.equal(1)

				local seen = {}

				for i = 0, 40 do
					local cell = L.Cell(i / L.RATE + 0.001)
					expect(cell >= 0 and cell < L.FRAMES).to.beTrue()
					expect(cell).to.equal(math.floor(cell))
					seen[cell] = true
				end

				local n = 0

				for _ in pairs(seen) do n = n + 1 end

				expect(n).to.equal(L.FRAMES)
				-- and it loops
				expect(L.Cell(L.FRAMES / L.RATE + 0.001)).to.equal(0)
			end
		},
		{
			name = "Tiles: the cells of the picture laid side by side over the box cover it exactly, once, each quad reading inside the cell of its frame; the cell is as many pixels as the screen's height says (one texel a pixel at 1080)",
			func = function()
				local L = GryMod.CloakFX.Lines
				local frame = 3

				for _, case in ipairs({
					{x = 100, y = 50, w = 700, h = 400, ox = 0, oy = 0, sh = 2160},
					{x = 13, y = 7, w = 1000, h = 900, ox = 100, oy = 3, sh = 1080},
					{x = 0, y = 0, w = 3840, h = 2160, ox = 77, oy = 2, sh = 2160},
					{x = 500, y = 500, w = 40, h = 40, ox = 5, oy = 1, sh = 720}
				}) do
					local quads = L.Tiles(case.x, case.y, case.w, case.h, case.sh, case.ox, case.oy, frame)
					local area = 0
					local u0 = frame * L.CELL / (L.CELL * L.FRAMES)
					local u1 = (frame + 1) * L.CELL / (L.CELL * L.FRAMES)

					for _, q in ipairs(quads) do
						expect(q.x >= case.x and q.y >= case.y).to.beTrue()
						expect(q.x + q.w <= case.x + case.w + 0.001 and q.y + q.h <= case.y + case.h + 0.001).to.beTrue()
						expect(q.w > 0 and q.h > 0).to.beTrue()
						expect(q.u0 >= u0 - 0.0001 and q.u1 <= u1 + 0.0001 and q.u0 < q.u1).to.beTrue()
						expect(q.v0 >= -0.0001 and q.v1 <= 1.0001 and q.v0 < q.v1).to.beTrue()
						area = area + q.w * q.h
					end

					-- no hole, no overlap: the areas add up to the box
					expect(math.abs(area - case.w * case.h) < 1).to.beTrue()
				end

				-- one texel is one pixel at 2160 (the 4K screen: the lines are four pixels to a period, as in the original) and half a
				-- pixel at 1080: a box smaller than a tile, away from its edge, is one quad
				local one = L.Tiles(10, 10, 100, 100, 2160, 0, 0, 0)
				expect(#one).to.equal(1)
				expect(one[1].u1 - one[1].u0).to.aboutEqual(100 / (L.CELL * L.FRAMES), 0.0001)
				expect(one[1].v1 - one[1].v0).to.aboutEqual(100 / L.CELL, 0.0001)

				local small = L.Tiles(10, 10, 100, 100, 1080, 0, 0, 0)
				expect(small[1].u1 - small[1].u0).to.aboutEqual(200 / (L.CELL * L.FRAMES), 0.0001)
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

				-- the lines: textured quads, with the stencil tested (equal) and the colours written, together the box
				expect(count(log, "DrawTexturedRectUV") >= 1).to.beTrue()
				local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge

				for _, c in ipairs(log.calls) do
					if c.name == "DrawTexturedRectUV" then
						expect(c.stencil).to.beTrue()
						expect(c.colorWrite).to.beTrue()
						expect(c.compare).to.equal(STENCIL_EQUAL)
						minX, minY = math.min(minX, c.args[1]), math.min(minY, c.args[2])
						maxX, maxY = math.max(maxX, c.args[1] + c.args[3]), math.max(maxY, c.args[2] + c.args[4])
					end
				end

				expect(minX).to.equal(400 - L.MARGIN)
				expect(minY).to.equal(200 - L.MARGIN)
				expect(math.abs(maxX - (560 + L.MARGIN)) < 0.01).to.beTrue()
				expect(math.abs(maxY - (640 + L.MARGIN)) < 0.01).to.beTrue()
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
			name = "Draw with the screen flag covers the whole screen and does not need the entity's box (the view model is drawn with another field of view: its box would be wrong)",
			func = function()
				local L = GryMod.CloakFX.Lines
				local log = record()
				stub(L, "ScreenPoints", function() error("no box wanted", 0) end)

				local ok = L.Draw(fakePlayer(), 1, function() end, true)

				expect(ok).to.beTrue()
				expect(count(log, "DrawTexturedRectUV") >= 1).to.beTrue()

				local area = 0

				for _, c in ipairs(log.calls) do
					if c.name == "DrawTexturedRectUV" then
						area = area + c.args[3] * c.args[4]
					end
				end

				expect(math.abs(area - ScrW() * ScrH()) < 2).to.beTrue()
				expect(log.stencil).to.beFalse()
				expect(log.colorWrite).to.beTrue()
			end
		},
		{
			name = "first person: the view model and the hands get the scan lines (whole screen) in the electric flash of the start of the change, and nothing once it is done",
			func = function()
				local F = GryMod.CloakFX
				local L = F.Lines
				F.SetDrawHooks(true)
				stub(render, "UpdateRefractTexture", function() end)
				stub(render, "MaterialOverride", function() end)
				stub(render, "SetBlend", function() end)
				stub(render, "SetColorModulation", function() end)

				local me = fakePlayer(0)
				local vm, hands = fakePlayer(0), fakePlayer(0)
				function me:GetViewModel() return vm end
				stub(_G, "LocalPlayer", function() return me end)

				local calls = {}
				stub(L, "Draw", function(ent, strength, draw, screen)
					calls[#calls + 1] = {ent = ent, strength = strength, screen = screen}
					draw(ent)

					return true
				end)

				local function frame()
					local t = hook.GetTable()
					t.PreDrawViewModel.GryCloakFX(vm, me, NULL)
					t.PostDrawViewModel.GryCloakFX(vm, me, NULL)
					t.PreDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
					t.PostDrawPlayerHands.GryCloakFX(hands, vm, me, NULL)
				end

				F.States[me] = {amount = 0.12, speed = 0, cloaked = true}
				frame()

				expect(#calls).to.equal(2)
				expect(calls[1].ent).to.equal(vm)
				expect(calls[2].ent).to.equal(hands)
				expect(calls[1].screen).to.beTrue()
				expect(calls[1].strength > 0.5).to.beTrue()

				-- done, and moving: no flash, no lines
				calls = {}
				F.States[me] = {amount = 1, speed = 300, cloaked = true}
				frame()

				expect(#calls).to.equal(0)
			end
		},
		{
			name = "TransitionSpark: the flash of the start of the change only (0 at the start, strong at a tenth, 0 once done), whatever the speed",
			func = function()
				local F = GryMod.CloakFX

				expect(F.TransitionSpark(0)).to.equal(0)
				expect(F.TransitionSpark(0.12) > 0.5).to.beTrue()
				expect(F.TransitionSpark(0.12) <= 1).to.beTrue()
				expect(F.TransitionSpark(1)).to.equal(0)
				expect(F.TransitionSpark(-1)).to.equal(0)
				expect(F.TransitionSpark(2)).to.equal(0)
			end
		},
		{
			name = "the camouflage's draw hook adds the lines only for a player in range at the start of the change (the electric flash), hands them a draw that the player's own hook lets through, and not for a far one or one that is done, moving or not",
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

				local starting, movingDone, stillDone, farStarting = fakePlayer(0), fakePlayer(300), fakePlayer(0), fakePlayer(0)
				farStarting.center = Vector(F.DetailDistance + 500, 0, 0)

				F.States[starting] = {amount = 0.12, speed = 0, cloaked = true}
				F.States[movingDone] = {amount = 1, speed = 300, cloaked = true}
				F.States[stillDone] = {amount = 1, speed = 0, cloaked = true}
				F.States[farStarting] = {amount = 0.12, speed = 0, cloaked = true}

				hook.GetTable().PostDrawTranslucentRenderables.GryCloakFX(false, false, false)

				expect(#calls).to.equal(1)
				expect(calls[1].ent).to.equal(starting)
				expect(calls[1].strength > 0.5).to.beTrue()
				-- the model was drawn by the lines' draw (the player's draws: 3 layers + the lines)
				expect(starting.draws).to.equal(4)
			end
		}
	}
}
