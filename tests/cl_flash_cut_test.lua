-- Tests of the cut line of a group (Clip:SetCut, cl_flash.lua, and drawGroup in cl_flash_draw.lua), GLuaTest format, client realm: the player draws a clip
-- that is a group as one image, and with a cut line as two, the clip's own image on one side of the line and the image of its clone (the same clip at the
-- next frame) on the other. This is what the smooth bars use (cl_hud_bar_smooth.lua). The engine calls are replaced by recorders (no render context needed),
-- as in cl_flash_draw_test.lua.

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 40, dh = 10},
			-- the bar: its frame 2 has a second shape (at 40) so that the clone's image is told from the clip's
			[2] = {k = "sprite", n = 2, labels = {}, frames = {{{d = 1, c = 1, n = "Shape"}, a = {{"stop"}}}, {{d = 2, c = 1, m = {1, 0, 0, 1, 40, 0}}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Bar", bl = 8}}}}
		},
		root = {{{d = 1, c = 3, n = "Holder"}}}
	}
end

-- Draws with the engine calls replaced by recorders. Returns how many group images were made, the screen quads drawn as {minX, maxX} (the quads of the
-- images, not the content of a group), and the texture coordinates u of their corners.
local function draw(root, x, y, scale)
	local replaced = {}
	local function replace(library, name, fake)
		replaced[#replaced + 1] = {library, name, library[name]}
		library[name] = fake
	end

	local F = GryMod.Flash
	local renders = F.Stats.groupRenders
	local inside, targets = 0, 0
	local quads, vertices = {}, {}
	local current, u

	replace(_G, "GetRenderTargetEx", function()
		targets = targets + 1

		return {GetName = function() return "fake_cut_target_" .. targets end}
	end)
	replace(_G, "CreateMaterial", function() return {} end)
	replace(render, "PushRenderTarget", function() inside = inside + 1 end)
	replace(render, "PopRenderTarget", function() inside = inside - 1 end)
	replace(render, "Clear", function() end)
	replace(render, "SetMaterial", function() end)
	replace(render, "OverrideBlend", function() end)
	replace(cam, "Start2D", function() end)
	replace(cam, "End2D", function() end)
	replace(mesh, "Begin", function() vertices = {} end)
	replace(mesh, "Position", function(position) current = position.x end)
	replace(mesh, "TexCoord", function(_, uu) u = uu end)
	replace(mesh, "Color", function() end)
	replace(mesh, "AdvanceVertex", function()
		if inside == 0 then
			vertices[#vertices + 1] = {current, u}
		end
	end)
	replace(mesh, "End", function()
		if inside == 0 and #vertices > 0 then
			local lo, hi, ulo, uhi = math.huge, -math.huge, math.huge, -math.huge

			for _, v in ipairs(vertices) do
				lo, hi = math.min(lo, v[1]), math.max(hi, v[1])
				ulo, uhi = math.min(ulo, v[2]), math.max(uhi, v[2])
			end

			quads[#quads + 1] = {lo, hi, ulo, uhi}
		end

		vertices = {}
	end)

	local ok, err = pcall(F.Draw, root, x or 0, y or 0, scale or 1)

	for i = #replaced, 1, -1 do
		local r = replaced[i]
		r[1][r[2]] = r[3]
	end

	assert(ok and err ~= false, "the drawing failed: " .. tostring(err))

	return {renders = F.Stats.groupRenders - renders, quads = quads}
end

local function cleanup(root)
	pcall(GryMod.Flash.ReleaseClip, root)
	pcall(GryMod.Flash.ClearGroupCache)
end

return {
	groupName = "GryMod Flash group cut line (smooth bars)",
	cases = {
		{
			-- needs: Clip:SetCut / ClearCut as plain fields, and the drawing of a group without a cut unchanged
			name = "a group without a cut line draws one quad and makes one image",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(movie())
				local ok, err = pcall(function()
					local result = draw(root, 100, 0, 1)
					expect(result.renders).to.equal(1)
					expect(#result.quads).to.equal(1)
					expect(root:Child("Holder"):Child("Bar").cutClone).to.beNil()
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: drawGroup drawing two images with a cut: the clip's on the smaller x side when side is +1, the clone's on the larger
			name = "with a cut line the image of the clip is drawn up to the line and the image of its clone from it (side +1), both made once",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				local bar = root:Child("Holder"):Child("Bar")
				local clone = F.NewClip(m, 2)
				clone:GotoAndStop(2)

				local ok, err = pcall(function()
					bar:SetCut(25, 5, 1, clone)
					local result = draw(root, 100, 0, 1)
					expect(result.renders).to.equal(2) -- the clip's image and the clone's
					expect(#result.quads).to.equal(2)
					local a, b = result.quads[1], result.quads[2]
					-- the clip's image: the shape of 40 pixels (x 100 to 140, plus the group's margin), cut at the line 100 + 25
					expect(a[2]).to.equal(125)
					expect(a[1] < 125).to.beTrue()
					-- the clone's: from the line, to the end of its two shapes (100 to 180)
					expect(b[1]).to.equal(125)
					expect(b[2] > 125).to.beTrue()
					-- the texture coordinates follow the cut: an image drawn from the line starts inside it
					expect(b[3] > 0).to.beTrue()
					expect(a[4] < 1).to.beTrue()

					-- the line moves: nothing is made again, the quads move
					bar:SetCut(30, 5, 1, clone)
					result = draw(root, 100, 0, 1)
					expect(result.renders).to.equal(0)
					expect(result.quads[1][2]).to.equal(130)
					expect(result.quads[2][1]).to.equal(130)
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: side -1 swapping the sides
			name = "with side -1 the clip's image keeps the larger x side and the clone's the smaller",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				local bar = root:Child("Holder"):Child("Bar")
				local clone = F.NewClip(m, 2)
				clone:GotoAndStop(2)

				local ok, err = pcall(function()
					bar:SetCut(25, 5, -1, clone)
					local result = draw(root, 100, 0, 1)
					expect(#result.quads).to.equal(2)
					expect(result.quads[1][1]).to.equal(125) -- the clip's image from the line
					expect(result.quads[2][2]).to.equal(125) -- the clone's up to it
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: a line outside the image draws one side only (nothing for a quad with no width)
			name = "a line before the image or after it draws only the side that is there",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				local bar = root:Child("Holder"):Child("Bar")
				local clone = F.NewClip(m, 2)
				clone:GotoAndStop(2)

				local ok, err = pcall(function()
					bar:SetCut(-500, 5, 1, clone)
					local result = draw(root, 100, 0, 1)
					expect(#result.quads).to.equal(1) -- all of it is on the clone's side
					bar:SetCut(5000, 5, 1, clone)
					result = draw(root, 100, 0, 1)
					expect(#result.quads).to.equal(1) -- all of it is on the clip's side
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: ClearCut putting the single image back
			name = "clearing the cut draws the clip's own image whole again, without making it again",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				local bar = root:Child("Holder"):Child("Bar")
				local clone = F.NewClip(m, 2)
				clone:GotoAndStop(2)

				local ok, err = pcall(function()
					bar:SetCut(25, 5, 1, clone)
					draw(root, 100, 0, 1)
					bar:ClearCut()
					local result = draw(root, 100, 0, 1)
					expect(result.renders).to.equal(0)
					expect(#result.quads).to.equal(1)
					expect(bar.cutClone).to.beNil()
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: ReleaseEntry giving the clone's image back too
			name = "releasing the clip gives both images back to the pool",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				local bar = root:Child("Holder"):Child("Bar")
				local clone = F.NewClip(m, 2)
				clone:GotoAndStop(2)

				local ok, err = pcall(function()
					bar:SetCut(25, 5, 1, clone)
					draw(root, 100, 0, 1)
					local before = F.PoolSize()
					F.ReleaseClip(root)
					expect(F.PoolSize() - before).to.equal(2)
				end)
				cleanup(root)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: PointIn and ScaleX
			name = "PointIn maps a point to an ancestor's coordinates through the entry matrices, ScaleX multiplies their scale",
			func = function(state)
				local F = GryMod.Flash
				local m = {
					w = 1024, h = 768, fps = 30, atlases = {},
					chars = {
						[1] = {k = "sprite", n = 1, labels = {}, frames = {{}}},
						[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "In", m = {2, 0, 0, 2, 10, 20}}}}},
						[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Mid", m = {0.5, 0, 0, 0.5, 100, 0}}}}}
					},
					root = {{{d = 1, c = 3, n = "Top"}}}
				}
				local root = F.NewRoot(m)
				local top = root:Child("Top")
				local inner = top:Child("Mid"):Child("In")
				-- In -> Mid: (3, 4) -> (2*3+10, 2*4+20) = (16, 28); Mid -> Top: (0.5*16+100, 0.5*28) = (108, 14)
				local x, y = inner:PointIn(top, 3, 4)
				expect(x).to.equal(108)
				expect(y).to.equal(14)
				x, y = inner:PointIn(inner, 3, 4)
				expect(x).to.equal(3)
				expect(y).to.equal(4)
				expect(inner:ScaleX()).to.equal(2 * 0.5 * 1)
			end
		}
	}
}
