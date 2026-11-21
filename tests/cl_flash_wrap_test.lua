-- Tests of the line layout of the text fields of the Flash player (GryMod.Flash.LayoutLines and the drawing of a
-- field): a field of the original is multiline (the lines are broken at spaces inside its width, ml / ww / ld in the
-- converted data) and clips what does not fit, unless it resizes itself (as). GLuaTest format, client realm.

-- Font: "0" is 10 px wide at a text height of 20 (advance 50 of 100), "1" 6 px, the space 5 px; the line is
-- (90 + 20) / 100 * 20 = 22 px high.
local function font()
	return {a = 1, em = 100, asc = 90, desc = 20, g = {
		[48] = {x = 0, y = 0, w = 40, h = 70, ox = 2, oy = -70, adv = 50},
		[49] = {x = 0, y = 0, w = 20, h = 70, ox = 2, oy = -70, adv = 30},
		[32] = {x = 0, y = 0, w = 0, h = 0, ox = 0, oy = 0, adv = 25}
	}}
end

local function field(fields)
	local f = {k = "text", ox = 0, oy = 0, w = 100, h = 100, fh = 20, t = "", col = {255, 255, 255, 255}, al = 0, f = 9}

	for key, value in pairs(fields or {}) do
		f[key] = value
	end

	return f
end

local function lines(f, text)
	return GryMod.Flash.LayoutLines(font(), f, text)
end

local function texts(list)
	local out = {}

	for i, line in ipairs(list) do
		out[i] = line.text
	end

	return table.concat(out, "|")
end

-- Draws a movie with one field with the mesh calls replaced by recorders; returns the quads, one per six
-- vertices, as {minX, minY, maxX, maxY} (stage pixels, the scale is 1 and the origin 0).
local function drawnQuads(f, text)
	local m = {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"}, fonts = {[9] = font()},
		chars = {
			[1] = f,
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Field"}}}}
		},
		root = {{{d = 1, c = 2, n = "Box"}}}
	}
	local root = GryMod.Flash.NewRoot(m)
	root:Child("Box"):SetText("Field", text)

	local originals = {mesh = {}, render = {}}
	local names = {mesh = {"Begin", "Position", "TexCoord", "Color", "AdvanceVertex", "End"}, render = {"SetMaterial", "OverrideBlend"}}
	local vertices, current = {}, nil
	local fakes = {
		mesh = {
			Begin = function() end,
			Position = function(position) current = {position.x, position.y} end,
			TexCoord = function() end,
			Color = function() end,
			AdvanceVertex = function() vertices[#vertices + 1] = current end,
			End = function() end
		},
		render = {SetMaterial = function() end, OverrideBlend = function() end}
	}

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			originals[library][name] = _G[library][name]
			_G[library][name] = fakes[library][name]
		end
	end

	local ignored = GryMod.Flash.IgnoreBlendModes
	GryMod.Flash.IgnoreBlendModes = true
	local ok, err = pcall(GryMod.Flash.Draw, root, 0, 0, 1)
	GryMod.Flash.IgnoreBlendModes = ignored

	for library, list in pairs(names) do
		for _, name in ipairs(list) do
			_G[library][name] = originals[library][name]
		end
	end

	assert(ok and err ~= false, "the drawing failed")
	local quads = {}

	for i = 1, #vertices, 6 do
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge

		for k = i, i + 5 do
			x0, y0 = math.min(x0, vertices[k][1]), math.min(y0, vertices[k][2])
			x1, y1 = math.max(x1, vertices[k][1]), math.max(y1, vertices[k][2])
		end

		quads[#quads + 1] = {x0, y0, x1, y1}
	end

	return quads
end

return {
	groupName = "GryMod Flash text wrapping and clipping",
	cases = {
		{
			name = "a multiline field with word wrap breaks its lines at spaces inside its width (minus the 2 px margins)",
			func = function(state)
				-- 34 px wide: 30 px of text; "00" is 20, "00 00" 45
				local f = field({w = 34, ml = true, ww = true})
				expect(texts(lines(f, "00 00 00"))).to.equal("00|00|00")
				-- "0 0" = 25 fits, "0 0 0" = 40 does not
				expect(texts(lines(f, "0 0 0"))).to.equal("0 0|0")
				f.w = 54 -- 50 px of text
				expect(texts(lines(f, "00 00 00"))).to.equal("00 00|00")
			end
		},
		{
			name = "the lines are one line height apart (ascent + descent of the font + the leading of the field)",
			func = function(state)
				local f = field({w = 34, ml = true, ww = true})
				local list = lines(f, "00 00 00")
				expect(list[1].baseline).to.equal(2 + 90 * 20 / 100)
				expect(list[2].baseline - list[1].baseline).to.equal(22)
				expect(list[3].baseline - list[2].baseline).to.equal(22)
				f.ld = 3
				list = lines(f, "00 00 00")
				expect(list[2].baseline - list[1].baseline).to.equal(25)
			end
		},
		{
			name = "a field that is not multiline stays on one line: it never wraps and the line breaks of its text count for nothing",
			func = function(state)
				local f = field({w = 34})
				expect(texts(lines(f, "00 00 00"))).to.equal("00 00 00")
				expect(texts(lines(f, "0\n1"))).to.equal("01")
				-- word wrap without multiline: the original wraps nothing either (Flash needs both)
				f.ww = true
				expect(texts(lines(f, "00 00 00"))).to.equal("00 00 00")
			end
		},
		{
			name = "a multiline field without word wrap breaks its lines at the line breaks of its text only",
			func = function(state)
				local f = field({w = 34, ml = true})
				expect(texts(lines(f, "00 00 00\n1"))).to.equal("00 00 00|1")
			end
		},
		{
			name = "a word wider than the field is cut between two characters, the next characters go on the next line",
			func = function(state)
				local f = field({w = 34, ml = true, ww = true})
				-- 30 px of text: three zeros, then two
				expect(texts(lines(f, "00000"))).to.equal("000|00")
				-- a word that does not fit after the previous word goes to the next line first, then it is cut there
				expect(texts(lines(f, "1 00000"))).to.equal("1|000|00")
			end
		},
		{
			name = "the spaces at a break are dropped: they neither start the next line nor widen the line they end",
			func = function(state)
				local f = field({w = 34, ml = true, ww = true, al = 1})
				local list = lines(f, "00   00")
				expect(texts(list)).to.equal("00|00")
				expect(list[1].width).to.equal(20)
				expect(list[1].x).to.equal(34 - 2 - 20) -- right aligned on its own width
				f.al = 2
				list = lines(f, "00 00")
				expect(list[2].x).to.equal((34 - 20) / 2) -- centred line by line
			end
		},
		{
			name = "an empty text is one empty line, whatever the field",
			func = function(state)
				local f = field({w = 34, ml = true, ww = true})
				expect(#lines(f, "")).to.equal(1)
				expect(lines(f, "")[1].width).to.equal(0)
			end
		},
		{
			name = "LayoutText gives the first line: the same x, baseline and width as before for a single line",
			func = function(state)
				local f = field({w = 34, ml = true, ww = true})
				local x, baseline, width = GryMod.Flash.LayoutText(font(), f, "00 00 00")
				expect(x).to.equal(2)
				expect(baseline).to.equal(2 + 18)
				expect(width).to.equal(20)
			end
		},
		{
			name = "a field clips its text to its rectangle unless it resizes itself (autoSize)",
			func = function(state)
				local _, clips = lines(field({w = 34}), "00")
				expect(clips).to.beTrue()
				_, clips = lines(field({w = 34, as = true}), "00")
				expect(clips).to.beFalse()
			end
		},
		{
			name = "drawing: the glyphs of a line that is longer than its field stop at the field's edge",
			func = function(state)
				-- "0000" is 40 px wide in a field of 30: the third glyph (x 22.4 to 30.4) is cut at 30, the fourth is gone
				local quads = drawnQuads(field({w = 30, h = 30}), "0000")
				expect(#quads).to.equal(3)
				local maxX = 0

				for _, q in ipairs(quads) do
					maxX = math.max(maxX, q[3])
				end

				expect(math.abs(maxX - 30) < 1e-6).to.beTrue()
			end
		},
		{
			name = "drawing: a field with auto size draws all its glyphs",
			func = function(state)
				expect(#drawnQuads(field({w = 30, h = 30, as = true}), "0000")).to.equal(4)
			end
		},
		{
			name = "drawing: the lines of a wrapped field are drawn one under the other, and what falls below the field is cut",
			func = function(state)
				-- baselines 20, 42, 64 in a field 60 high: the third line (glyphs from 50 to 64) is cut at 60
				local quads = drawnQuads(field({w = 34, h = 60, ml = true, ww = true}), "00 00 00")
				expect(#quads).to.equal(6) -- three lines of two glyphs
				local maxY = 0

				for _, q in ipairs(quads) do
					maxY = math.max(maxY, q[4])
				end

				expect(math.abs(maxY - 60) < 1e-6).to.beTrue()
			end
		}
	}
}
