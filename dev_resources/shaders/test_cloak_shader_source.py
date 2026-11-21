"""Tests of the camouflage sparks' pixel shader source (grymod_cloak_ps30.hlsl): what the Lua gives it, and what it must not read from the world."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def source(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return handle.read()


def code_only(text):
    """The source without its comments."""
    return re.sub(r"//[^\n]*", "", text)


class SparksPixelShaderTest(unittest.TestCase):
    def test_the_pattern_does_not_follow_the_players_place_in_the_world(self):
        # The original shifted the green lookup by the distance to the world origin in METRES. In the game's units that is 52 times
        # more: walking made the pattern run 25 times faster, one way or the other. The drift is given by the Lua (capped), through c2.w.
        code = code_only(source("grymod_cloak_ps30.hlsl"))
        self.assertNotIn("objPos.w", code)

    def test_the_pattern_is_worked_out_in_the_entitys_own_space(self):
        # The vertex position the engine hands over is in the WORLD (measured: a plate moved elsewhere shows another pattern, a plate turned a
        # quarter shows the same one): a pattern read from it stays put in the world and a walking player slides through it. The Lua gives the
        # entity's origin (c3.xyz) and angles (c2.xyz), and the pattern is read from the position relative to them.
        code = code_only(source("grymod_cloak_ps30.hlsl"))
        self.assertNotIn("frag.objPos.xyz / C0.x", code)
        self.assertIn("C3.xyz", code)
        self.assertIn("sincos", code)

    def test_the_drift_comes_from_the_fourth_component_of_the_colour_register(self):
        code = code_only(source("grymod_cloak_ps30.hlsl"))
        self.assertIn("C2.w", code)
        green = [line for line in code.splitlines() if "n * 1.53" in line]
        self.assertEqual(len(green), 1)
        self.assertIn("C2.w", green[0])


if __name__ == "__main__":
    unittest.main()
