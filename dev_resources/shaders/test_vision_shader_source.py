"""Tests of the binoculars hologram's pixel shader source (grymod_vision_ps20b.hlsl): what the Lua gives it (cl_hud_binoculars_holo.lua) and what model 2.0b allows."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "grymod_vision_ps20b.hlsl"


def code_only():
    with open(os.path.join(HERE, NAME), encoding="utf-8") as handle:
        return re.sub(r"//[^\n]*", "", handle.read())


class VisionPixelShaderTest(unittest.TestCase):
    def test_it_reads_the_four_registers_and_two_samplers_the_lua_fills(self):
        # The Lua writes $c0..$c3 (four floats each) and binds the vision buffer to s0 and the glow to s1.
        code = code_only()
        for register in ("c0", "c1", "c2", "c3", "s0", "s1"):
            self.assertIn("register(%s)" % register, code)

    def test_it_has_no_branch_model_2_0b_has_none(self):
        # The two modes (the shape alone, the final result) are chosen with a conditional value, not an if.
        code = code_only()
        self.assertIsNone(re.search(r"\bif\s*\(", code))
        self.assertIsNone(re.search(r"\b(for|while)\s*\(", code))

    def test_the_mode_is_the_third_component_of_the_second_register(self):
        code = code_only()
        self.assertIn("C1.z", code)

    def test_the_outline_looks_at_three_neighbours_through_the_alpha(self):
        # The boundary is the difference of the ALPHA of the pixel and of three neighbours (up, down-left, down-right): one read of the pixel, three of the others.
        code = code_only()
        self.assertEqual(len(re.findall(r"tex2D\(VISION", code)), 4)
        self.assertIn("float2(0.0, -1.0)", code)
        self.assertIn("float2(-1.0, 1.0)", code)
        self.assertIn("float2(1.0, 1.0)", code)

    def test_the_edge_is_a_presence_mask_not_a_raw_alpha_difference(self):
        # Measured in the game: the alpha the engine writes for a flat model is not 1 but 0.92 to 0.97, changing smoothly over the body; a raw difference of two alphas
        # then drew contour lines inside a close soldier. The alpha is turned into present / absent (step) before the neighbours are compared.
        code = code_only()
        self.assertRegex(code, r"step\(0\.5,\s*around\)")
        self.assertRegex(code, r"step\(0\.5,\s*c\.a\)")

    def test_the_glow_source_has_no_fill(self):
        # The glow is made from the boundary alone: with the fill in it the blurred glow turned the whole body milky (seen in the game).
        code = code_only()
        self.assertIn("float3 rim = c.rgb * (edge * C0.y)", code)
        self.assertIn("(C1.z < 0.5) ? rim : final", code)

    def test_the_variable_is_not_called_like_an_intrinsic(self):
        # `step` is an HLSL function: a variable of that name stops the compilation.
        code = code_only()
        self.assertIsNone(re.search(r"\bfloat[234]?\s+step\b", code))

    def test_the_file_name_tells_the_model(self):
        self.assertTrue(re.match(r"^.+_ps20b\.hlsl$", NAME))


if __name__ == "__main__":
    unittest.main()
