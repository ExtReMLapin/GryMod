-- What Flash.Draw allocates (cl_flash_draw.lua), GLuaTest format, client realm. It runs the drawing under pcall, and used to give pcall a function written in the
-- call: a new closure (264 to 280 bytes with its four captured values) at every call, 5 or 6 calls a frame. The engine calls are replaced by recorders that only
-- count (counting allocates nothing), as in cl_flash_draw_test.lua; tools/test_flash_draw_alloc.py is the same test outside the game.

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		chars = {
			[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "A"}, {d = 5, c = 1, n = "B", m = {1, 0, 0, 1, 100, 0}}}}}
		},
		root = {{{d = 1, c = 2, n = "Plain"}}}
	}
end

return {
	groupName = "GryMod Flash drawing: what Flash.Draw allocates",
	cases = {
		{
			name = "a call of Flash.Draw on a clip at rest allocates no closure",
			timing = true, -- no count hook: under it the interpreter allocates for its own sake
			func = function(state)
				local F = GryMod.Flash
				local root = F.NewRoot(movie())
				local names = {mesh = {"Begin", "Position", "TexCoord", "Color", "AdvanceVertex", "End"}, render = {"SetMaterial", "OverrideBlend"}}
				local originals = {mesh = {}, render = {}}
				local drawn = 0
				local function nothing() end

				for library, list in pairs(names) do
					for _, name in ipairs(list) do
						originals[library][name] = _G[library][name]
						_G[library][name] = name == "AdvanceVertex" and function() drawn = drawn + 1 end or nothing
					end
				end

				-- the memory used by n calls; a part of it is the same whatever n is (the engine's compiler warming up), so two runs are compared
				local function used(n)
					collectgarbage("collect")
					collectgarbage("stop")
					local before = collectgarbage("count")

					for _ = 1, n do
						F.Draw(root, 0, 0, 1)
					end

					local after = collectgarbage("count")
					collectgarbage("restart")

					return (after - before) * 1024
				end

				local ok, err = pcall(function()
					F.Draw(root, 0, 0, 1)
					used(1000)
					local few, many = used(1000), used(5000)
					state.perCall = (many - few) / 4000
				end)

				collectgarbage("restart")

				for library, list in pairs(names) do
					for _, name in ipairs(list) do
						_G[library][name] = originals[library][name]
					end
				end

				assert(ok, err)
				expect(drawn > 0).to.beTrue()
				-- the closure was 264 to 280 bytes
				expect(state.perCall < 50).to.beTrue()
			end
		}
	}
}
