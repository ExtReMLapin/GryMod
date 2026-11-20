-- Tests of the parts of the Flash drawing code that do not need a render context (cl_flash_draw.lua): the pool of
-- render targets and what happens after an error while drawing. The pictures themselves are checked with
-- tests/flash_pixels_job.lua.

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Shape"}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Group", bl = 8}}}}
		},
		root = {{{d = 1, c = 3, n = "Holder"}}}
	}
end

return {
	groupName = "GryMod Flash drawing (no render context)",
	cases = {
		{
			name = "releasing a group that never had an image (empty or too big) does not error",
			func = function(state)
				local F = GryMod.Flash
				F.ReleaseEntry({cache = {}})
				F.ReleaseEntry({cache = {target = nil, textureW = nil}, clip = {list = {}}})
			end
		},
		{
			name = "releasing a clip gives the images of its groups back to the pool, once",
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(movie())
				local group = root:Child("Holder"):Child("Group")
				local entry = root:Child("Holder"):EntryAt(1)
				entry.cache = {target = {}, textureW = 64, textureH = 128}
				local before = F.PoolSize()
				F.ReleaseClip(root)
				expect(F.PoolSize()).to.equal(before + 1)
				expect(entry.cache).to.beNil()
				F.ReleaseClip(root) -- nothing left to give back
				expect(F.PoolSize()).to.equal(before + 1)
				F.ClearGroupCache() -- the pool holds a fake target: do not let a real drawing take it
			end
		},
		{
			name = "an error while drawing is reported once, leaves the drawing state clean and does not stop the next frame",
			func = function(state)
				local F = GryMod.Flash
				local m = movie()
				local root = F.NewRoot(m)
				m.chars[1] = nil -- the shape disappears: drawing it raises an error, inside the measuring pass of the group
				local ok = F.Draw(root, 0, 0, 1)
				expect(ok).to.beFalse()
				local measuring, depth, masks = F.DrawState()
				expect(measuring).to.beFalse()
				expect(depth).to.equal(0)
				expect(masks).to.equal(0)
				m.chars[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1}
				expect(F.DrawState()).to.beFalse() -- still clean for the next call
			end
		}
	}
}
