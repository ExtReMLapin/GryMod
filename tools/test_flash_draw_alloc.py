"""Tests of what Flash.Draw (lua/grymod/client/cl_flash_draw.lua) allocates and of its error handling, run outside the game
(needs `pip install lupa`: it carries LuaJIT, the Lua of the game).

Run from the repository root:  python -m unittest tools.test_flash_draw_alloc

Flash.Draw runs the drawing under pcall. It used to give pcall a function written in the call, which makes a new closure (about 280
bytes with its four captured values) at every call, for every film drawn, at every frame, whatever the clip does: 5 or 6 calls a frame
made 1.7 KB of garbage a frame for nothing. The drawing is now a function that exists once and pcall gets its arguments.

The render and mesh functions are stubs that only count their calls (counting allocates nothing).
"""
import os
import unittest

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # the CI installs lupa
    LuaRuntime = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")

SETUP = r"""
local REPO = ...

function include(path)
	local f = io.open(REPO .. "/lua/" .. path, "rb")
	if not f then return nil end
	local src = f:read("*a")
	f:close()
	return assert(loadstring(src, "@" .. path))()
end

file = {Exists = function(path)
	local f = io.open(REPO .. "/lua/" .. path, "rb")
	if f then f:close() return true end
	return false
end}

function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function math.Clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

CALLS = {Begin = 0, End = 0, Position = 0, AdvanceVertex = 0, SetMaterial = 0, OverrideBlend = 0}
FAIL = false
ERRORS = {}

local VectorMeta = {}
VectorMeta.__index = VectorMeta
function VectorMeta:SetUnpacked(x, y, z) self[1], self[2], self[3] = x, y, z end
function Vector(x, y, z) return setmetatable({x or 0, y or 0, z or 0}, VectorMeta) end

local MaterialMeta = {}
MaterialMeta.__index = MaterialMeta
function MaterialMeta:Width() return self.w end
function MaterialMeta:Height() return self.h end
function MaterialMeta:SetInt() end
function MaterialMeta:Recompute() end
function MaterialMeta:GetName() return self.name end
function Material(name) return setmetatable({name = name, w = 2048, h = 4096}, MaterialMeta) end
function CreateMaterial(name) return setmetatable({name = name, w = 1024, h = 1024}, MaterialMeta) end

local TextureMeta = {}
TextureMeta.__index = TextureMeta
function TextureMeta:GetName() return self.name end
function GetRenderTargetEx(name, w, h) return setmetatable({name = name, w = w, h = h}, TextureMeta) end
RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SEPARATE, IMAGE_FORMAT_RGBA16161616F = 0, 1, 2
BLEND_SRC_ALPHA, BLEND_ONE, BLEND_ONE_MINUS_SRC_ALPHA, BLENDFUNC_ADD, MATERIAL_TRIANGLES = 4, 1, 5, 0, 2

render = {
	SetMaterial = function() CALLS.SetMaterial = CALLS.SetMaterial + 1 end,
	OverrideBlend = function() CALLS.OverrideBlend = CALLS.OverrideBlend + 1 end,
	PushRenderTarget = function() end, PopRenderTarget = function() end, Clear = function() end
}
mesh = {
	Begin = function() CALLS.Begin = CALLS.Begin + 1 if FAIL then error("a failure while drawing") end end,
	Position = function() CALLS.Position = CALLS.Position + 1 end,
	TexCoord = function() end, Color = function() end,
	AdvanceVertex = function() CALLS.AdvanceVertex = CALLS.AdvanceVertex + 1 end,
	End = function() CALLS.End = CALLS.End + 1 end
}
cam = {Start2D = function() end, End2D = function() end}
surface = setmetatable({}, {__index = function() return function() end end})
function ErrorNoHalt(text) ERRORS[#ERRORS + 1] = text end

GryMod = {}
include("grymod/client/cl_flash.lua")
include("grymod/client/cl_flash_draw.lua")
Flash = GryMod.Flash

THEME = {Line = {68, 99, 62}, Over = {215, 140, 16}, Text = {189, 0, 161}}

-- a movie with a few shapes in two sprites, one of them a group (blend mode add)
MOVIE = {
	w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none"},
	chars = {
		[1] = {k = "shape", a = 1, x = 0, y = 0, w = 4, h = 4, ox = 0, oy = 0, dw = 1, dh = 1},
		[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "A"}, {d = 5, c = 1, n = "B", m = {1, 0, 0, 1, 100, 0}}}}},
		[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 2, n = "Group", bl = 8}}}}
	},
	root = {{{d = 1, c = 2, n = "Plain"}, {d = 2, c = 3, n = "Grouped"}}}
}

function Bytes(fn, calls)
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")

	for _ = 1, calls do fn() end

	local after = collectgarbage("count")
	collectgarbage("restart")

	return (after - before) * 1024 / calls
end
"""


@unittest.skipUnless(LuaRuntime, "lupa is not installed")
class FlashDrawAlloc(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.eval("function(src, repo) return assert(loadstring(src, '@setup'))(repo) end")(SETUP, ROOT)

    def test_a_call_of_draw_on_a_clip_at_rest_allocates_no_closure(self):
        measure = self.lua.eval(
            """function()
                local root = Flash.NewRoot(MOVIE, THEME)
                Flash.Draw(root, 0, 0, 1) -- the first call makes the group's image and its caches
                Flash.Draw(root, 0, 0, 1)
                local per = Bytes(function() Flash.Draw(root, 0, 0, 1) end, 200)
                return per, CALLS.AdvanceVertex
            end"""
        )
        per_call, vertices = measure()
        print("\n[flash draw] Flash.Draw at rest: %.1f bytes a call" % per_call)
        self.assertGreater(vertices, 0, "nothing was drawn: the test measures nothing")
        # the closure was 264 to 280 bytes: nothing of the sort may be made now
        self.assertLess(per_call, 50)

    def test_an_error_in_the_drawing_is_caught_reported_once_and_the_state_is_put_back(self):
        result = self.lua.eval(
            """function()
                local root = Flash.NewRoot(MOVIE, THEME)
                assert(Flash.Draw(root, 0, 0, 1) == true)
                FAIL = true
                local first = Flash.Draw(root, 0, 0, 1)
                local second = Flash.Draw(root, 0, 0, 1)
                FAIL = false
                local after = Flash.Draw(root, 0, 0, 1)
                local drawn = CALLS.AdvanceVertex
                local again = Flash.Draw(root, 0, 0, 1)

                return first, second, after, #ERRORS, ERRORS[1], again, CALLS.AdvanceVertex > drawn
            end"""
        )()
        first, second, after, errors, text, again, drew = result
        self.assertFalse(first)
        self.assertFalse(second)
        self.assertTrue(after)
        self.assertEqual(errors, 1, "the same error is printed once, not at every frame")
        self.assertIn("a failure while drawing", text)
        self.assertTrue(again)
        self.assertTrue(drew, "a drawing after the error draws again")


if __name__ == "__main__":
    unittest.main()
