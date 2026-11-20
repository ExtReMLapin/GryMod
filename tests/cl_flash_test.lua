-- Tests of the Flash timeline player (GryMod.Flash), GLuaTest format, client realm.
--
-- The player replays the display lists and frame actions of the Crysis HUD movies converted by
-- tools/flash2lua. Hand-built movies pin the rules; one test loads the real converted file.

local function movie()
	local I = {1, 0, 0, 1, 0, 0}
	return {
		w = 1024, h = 768, fps = 30, atlases = {},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			-- 3 frames with labels; frame 2 moves the shape, frame 3 removes it
			[2] = {k = "sprite", n = 3, labels = {intro = 1, mid = 2, fin = 3}, frames = {
				{{d = 1, c = 1, m = I}, l = "intro"},
				{{d = 1, mv = true, m = {1, 0, 0, 1, 10, 0}}, l = "mid"},
				{{rm = 1}, l = "fin"}
			}},
			-- 10 frames, nothing special
			[3] = {k = "sprite", n = 10, labels = {}, frames = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}}},
			-- stops itself on frame 2
			[4] = {k = "sprite", n = 3, labels = {}, frames = {{}, {a = {{"stop"}}}, {}}},
			-- 4 frames, loops
			[5] = {k = "sprite", n = 4, labels = {}, frames = {{}, {}, {}, {}}},
			-- jumps to its label on creation
			[6] = {k = "sprite", n = 4, labels = {home = 3}, frames = {{a = {{"gotol", "home"}}}, {}, {l = "home", a = {{"stop"}}}, {}}},
			-- contains named children
			[7] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 3, n = "Inner"}, {d = 2, c = 2, n = "Mover"}}}},
		},
		root = {{{d = 1, c = 7, n = "Outer"}}}
	}
end

local function clip(id)
	return GryMod.Flash.NewClip(movie(), id)
end

return {
	groupName = "GryMod Flash player",
	cases = {
		{
			name = "goto a label lands on that frame",
			func = function(state)
				local c = clip(2)
				c:GotoAndStop("mid")
				expect(c:CurrentFrame()).to.equal(2)
				expect(c:CurrentLabel()).to.equal("mid")
				c:GotoAndStop("fin")
				expect(c:CurrentLabel()).to.equal("fin")
			end
		},
		{
			name = "an unknown label does nothing",
			func = function(state)
				local c = clip(2)
				c:GotoAndStop("mid")
				c:GotoAndStop("nope")
				expect(c:CurrentFrame()).to.equal(2)
			end
		},
		{
			name = "the timeline advances at 30 fps with a float clock",
			func = function(state)
				local c = clip(3)
				c:Advance(0.1)
				expect(c:CurrentFrame()).to.equal(4)
				local d = clip(3)
				d:Advance(0.05)
				expect(d:CurrentFrame()).to.equal(2)
				expect(d.pos).to.aboutEqual(2.5, 0.0001)
			end
		},
		{
			name = "the same time gives the same frame whatever the frame rate",
			func = function(state)
				local slow, fast = clip(3), clip(3)
				for _ = 1, 30 do slow:Advance(1 / 30) end
				for _ = 1, 144 do fast:Advance(1 / 144) end
				-- one second at 30 fps on 10 frames is exactly three loops: back on frame 1 (+/- one frame of rounding)
				expect(math.abs(slow:CurrentFrame() - fast:CurrentFrame()) <= 1 or math.abs(slow:CurrentFrame() - fast:CurrentFrame()) == 9).to.beTrue()
			end
		},
		{
			name = "a stop action halts the timeline",
			func = function(state)
				local c = clip(4)
				c:Advance(1)
				expect(c:CurrentFrame()).to.equal(2)
				expect(c.playing).to.beFalse()
			end
		},
		{
			name = "the timeline loops at its last frame",
			func = function(state)
				local c = clip(5)
				c:Advance(4 / 30 + 0.001)
				expect(c:CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "a frame action can jump to a label when the clip is created",
			func = function(state)
				local c = clip(6)
				expect(c:CurrentFrame()).to.equal(3)
				expect(c.playing).to.beFalse()
			end
		},
		{
			name = "children are reachable by instance name, at any depth",
			func = function(state)
				local root = GryMod.Flash.NewRoot(movie())
				local outer = root:Child("Outer")
				expect(outer).to.exist()
				expect(outer:Child("Inner")).to.exist()
				expect(outer:Child("Mover")).to.exist()
				expect(outer:Child("Nothing")).to.beNil()
			end
		},
		{
			name = "a clip is visible by default",
			func = function(state)
				local c = clip(3)
				expect(c.visible).to.beTrue()
				c.visible = false
				expect(c.visible).to.beFalse()
			end
		},
		{
			name = "a remove operation clears the depth",
			func = function(state)
				local c = clip(2)
				expect(c:ChildCount()).to.equal(1)
				c:GotoAndStop("fin")
				expect(c:ChildCount()).to.equal(0)
			end
		},
		{
			name = "a move operation keeps the character and changes the matrix",
			func = function(state)
				local c = clip(2)
				c:GotoAndStop("mid")
				local entry = c:EntryAt(1)
				expect(entry.id).to.equal(1)
				expect(entry.m[5]).to.equal(10)
			end
		},
		{
			name = "going back to an earlier frame rebuilds the display list",
			func = function(state)
				local c = clip(2)
				c:GotoAndStop("fin")
				c:GotoAndStop("intro")
				expect(c:ChildCount()).to.equal(1)
				expect(c:EntryAt(1).m[5]).to.equal(0)
			end
		},
		{
			name = "a frame number past the ends is clamped, and NaN is the first frame",
			func = function(state)
				local c = clip(2)
				c:GotoAndStop(99)
				expect(c:CurrentFrame()).to.equal(3)
				c:GotoAndStop(0)
				expect(c:CurrentFrame()).to.equal(1)
				c:GotoAndStop(-5)
				expect(c:CurrentFrame()).to.equal(1)
				c:GotoAndStop(0 / 0)
				expect(c:CurrentFrame()).to.equal(1)
				c:GotoAndStop(2.9)
				expect(c:CurrentFrame()).to.equal(2)
			end
		},
		{
			name = "a colour action tints the named child with the theme colour",
			func = function(state)
				local m = movie()
				m.chars[8] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Colorset"}, a = {{"color", "Line", "Colorset"}}}}}
				local clip = GryMod.Flash.NewClip(m, 8, {Line = {10, 20, 30}})
				local cx = clip:Child("Colorset") and clip:EntryAt(1).cx
				expect(cx).to.exist()
				-- setRGB: the colour is replaced (multiplier 0, added colour), the alpha untouched
				expect(cx[1]).to.equal(0)
				expect(cx[4]).to.equal(1)
				expect(cx[5]).to.equal(10)
				expect(cx[6]).to.equal(20)
				expect(cx[7]).to.equal(30)
			end
		},
		{
			name = "a colour action keeps the alpha of the child's colour transform",
			func = function(state)
				local m = movie()
				m.chars[8] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Colorset", cx = {1, 1, 1, 0.5, 0, 0, 0, 0}}, a = {{"color", "Over", "Colorset"}}}}}
				local clip = GryMod.Flash.NewClip(m, 8, {Over = {1, 2, 3}})
				expect(clip:EntryAt(1).cx[4]).to.equal(0.5)
				expect(clip:EntryAt(1).cx[5]).to.equal(1) -- and it was tinted
			end
		},
		{
			name = "a colour action without that theme colour leaves the child alone",
			func = function(state)
				local m = movie()
				m.chars[8] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Colorset"}, a = {{"color", "Text", "Colorset"}}}}}
				local clip = GryMod.Flash.NewClip(m, 8, {Line = {1, 2, 3}})
				expect(clip:EntryAt(1).cx).to.beNil()
				local noTheme = GryMod.Flash.NewClip(m, 8)
				expect(noTheme:EntryAt(1).cx).to.beNil()
			end
		},
		{
			name = "children inherit the theme, and the colour action runs again when the frame changes",
			func = function(state)
				local m = movie()
				m.chars[8] = {k = "sprite", n = 2, labels = {}, frames = {{{d = 1, c = 1, n = "Colorset"}, a = {{"color", "Line", "Colorset"}, {"stop"}}}, {{d = 1, mv = true, cx = {1, 1, 1, 1, 0, 0, 0, 0}}, a = {{"color", "Line", "Colorset"}, {"stop"}}}}}
				m.chars[9] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 8, n = "Part"}}}}
				local root = GryMod.Flash.NewClip(m, 9, {Line = {7, 8, 9}})
				local part = root:Child("Part")
				expect(part:EntryAt(1).cx[5]).to.equal(7)
				part:GotoAndStop(2) -- the move operation replaced the transform; the script colours it again
				expect(part:EntryAt(1).cx[5]).to.equal(7)
			end
		},
		{
			name = "the version of a clip changes with its frame, its children and its visibility, and only then",
			func = function(state)
				local root = GryMod.Flash.NewRoot(movie())
				local outer = root:Child("Outer")
				local v0 = outer.version
				outer:Advance(0) -- time passes but nothing moves
				expect(outer.version).to.equal(v0)
				outer:Child("Mover"):GotoAndStop("mid")
				expect(outer.version).toNot.equal(v0)
				local v1 = outer.version
				outer:Child("Mover"):GotoAndStop("mid") -- same frame: nothing changed
				expect(outer.version).to.equal(v1)
				outer:Child("Mover"):SetVisible(false)
				expect(outer.version).toNot.equal(v1)
				expect(outer:Child("Mover").visible).to.beFalse()
				local v2 = outer.version
				outer:Child("Mover"):SetVisible(false)
				expect(outer.version).to.equal(v2)
			end
		},
		{
			name = "setting a text bumps the version of the clip that holds the field and of its parents",
			func = function(state)
				local m = movie()
				m.chars[10] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 11, n = "Field"}}}}
				m.chars[11] = {k = "text", ox = 0, oy = 0, w = 10, h = 10, fh = 10, t = "", col = {255, 255, 255, 255}, al = 0, f = 9}
				m.root = {{{d = 1, c = 10, n = "Holder"}}}
				local root = GryMod.Flash.NewRoot(m)
				local holder = root:Child("Holder")
				local before, rootBefore = holder.version, root.version
				holder:SetText("Field", "42")
				expect(holder.version).toNot.equal(before)
				expect(root.version).toNot.equal(rootBefore)
				local after = holder.version
				holder:SetText("Field", "42") -- the same text: nothing changed
				expect(holder.version).to.equal(after)
			end
		},
		{
			name = "a time step that is NaN, negative or huge does not break the clock",
			func = function(state)
				local c = clip(3)
				c:Advance(0 / 0)
				expect(c.frac == c.frac).to.beTrue() -- not NaN
				expect(c:CurrentFrame()).to.equal(1)
				c:Advance(-5)
				expect(c:CurrentFrame()).to.equal(1)
				c:Advance(1e9) -- clamped to one second: it returns, and the clock still works afterwards
				expect(c.frac == c.frac).to.beTrue()
				c:GotoAndStop(1)
				c:Play()
				c:Advance(0.1)
				expect(c:CurrentFrame()).to.equal(4)
			end
		},
		{
			name = "SetRotation turns a clip like Flash's _rotation (clockwise degrees, scale kept) and bumps the version",
			func = function(state)
				local outer = GryMod.Flash.NewClip(movie(), 7)
				local mover = outer:Child("Mover")
				local before = outer.version
				mover:SetRotation(90)
				local m = mover.entry.m
				expect(math.abs(m[1]) < 1e-9).to.beTrue()
				expect(math.abs(m[2] - 1) < 1e-9).to.beTrue()
				expect(math.abs(m[3] + 1) < 1e-9).to.beTrue()
				expect(math.abs(m[4]) < 1e-9).to.beTrue()
				expect(outer.version > before).to.beTrue()
				-- the translation stays, and turning again to the same angle changes nothing
				expect(m[5]).to.equal(0)
				local again = outer.version
				mover:SetRotation(90)
				expect(outer.version).to.equal(again)
			end
		},
		{
			name = "SetAlpha is Flash's _alpha: a percentage that replaces the alpha multiplier and keeps the colour terms",
			func = function(state)
				local outer = GryMod.Flash.NewClip(movie(), 7)
				local mover = outer:Child("Mover")
				local before = outer.version
				mover:SetAlpha(50)
				local cx = mover.entry.cx
				expect(math.abs(cx[4] - 0.5) < 1e-9).to.beTrue()
				expect(cx[1]).to.equal(1)
				expect(cx[5]).to.equal(0)
				expect(outer.version > before).to.beTrue()
				local again = outer.version
				mover:SetAlpha(50)
				expect(outer.version).to.equal(again)
				mover:SetAlpha(100)
				expect(math.abs(mover.entry.cx[4] - 1) < 1e-9).to.beTrue()
			end
		},
		{
			name = "SetY moves a clip vertically and SetScale scales it in percent, each keeping the rest of the matrix",
			func = function(state)
				local outer = GryMod.Flash.NewClip(movie(), 7)
				local mover = outer:Child("Mover")
				mover:SetX(30)
				mover:SetY(12)
				local m = mover.entry.m
				expect(m[5]).to.equal(30)
				expect(m[6]).to.equal(12)
				mover:SetScale(50, 25)
				m = mover.entry.m
				expect(math.abs(m[1] - 0.5) < 1e-9).to.beTrue()
				expect(math.abs(m[4] - 0.25) < 1e-9).to.beTrue()
				expect(m[5]).to.equal(30) -- the position stays
				expect(m[6]).to.equal(12)
				-- a rotation already there is kept
				mover:SetRotation(90)
				mover:SetScale(100, 100)
				m = mover.entry.m
				expect(math.abs(m[2] - 1) < 1e-9).to.beTrue()
				local before = outer.version
				mover:SetScale(100, 100)
				expect(outer.version).to.equal(before)
			end
		},
		{
			name = "a child action sends gotoAndPlay or gotoAndStop to the child clip with that name",
			func = function(state)
				local m = movie()
				-- clip 8 holds the child "Mover" (clip 2: frames intro / mid / fin); its frame 1 plays "fin"
				m.chars[8] = {k = "sprite", n = 2, labels = {}, frames = {
					{{d = 1, c = 2, n = "Mover"}, a = {{"child", "Mover", false, "intro"}}},
					{a = {{"child", "Mover", true, 2}}}
				}}
				local clip = GryMod.Flash.NewClip(m, 8)
				local mover = clip:Child("Mover")
				expect(mover:CurrentLabel()).to.equal("intro")
				expect(mover.playing).to.beFalse()
				clip:Advance(1 / 30 + 0.001) -- the parent reaches frame 2 and starts the child on "mid", which then ticks on
				expect(mover:CurrentLabel()).to.equal("fin")
				expect(mover.playing).to.beTrue()
				-- a name that is not there is ignored
				m.chars[9] = {k = "sprite", n = 1, labels = {}, frames = {{a = {{"child", "Nobody", true, 1}}}}}
				GryMod.Flash.NewClip(m, 9)
			end
		},
		{
			name = "loading a missing movie gives nil",
			func = function(state)
				expect(GryMod.Flash.Load("no_such_movie")).to.beNil()
			end
		},
		{
			name = "the converted ammo/health/energy/suit movie loads and its bars have 100 frames",
			func = function(state)
				local data = GryMod.Flash.Load("hud_ammohealthenergysuit")
				expect(data).to.exist()
				expect(data.w).to.equal(1024)
				local root = GryMod.Flash.NewRoot(data)
				local hud = root:Child("Root")
				expect(hud).to.exist()
				local bar = hud:Child("HealthBar")
				expect(bar).to.exist()
				bar:GotoAndStop(50)
				expect(bar:CurrentFrame()).to.equal(50)
				bar:GotoAndStop(1000)
				expect(bar:CurrentFrame()).to.equal(100)
			end
		}
	}
}
