"""Every file of GryMod that draws a model through a material override must be one that was looked at for the engine's dynamic vertex buffer. No game needed.

A model drawn with render.MaterialOverride (or MaterialOverrideByIndex) goes through the engine's dynamic vertex buffer, which holds 32768 vertices for one mesh: a model with a bigger mesh
makes the engine retry for ever and the game freezes (the sonar grenade of ARC9's CS:GO pack under the camouflage, 2026-11-27). GryMod measures the size of a model before it draws it
that way (GryMod.CloakFX.ModelTooHeavy, cl_cloak_fx.lua) and draws it plain, or not at all, when it is too big.

This test keeps a new draw from slipping in unguarded. The files below draw with an override and were checked: each one must mention the guard (ModelTooHeavy, heavyEntity,
Holo.Drawable or shaderDraw/linesDraw, which carry it). A file that is not in the list and draws with an override fails: look at what it draws, make it ask the guard, then add it
here with a line saying how.

Run: python -m unittest tools.test_override_guard
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "lua")

# file -> how it is guarded
CHECKED = {
    "grymod/client/cl_cloak_fx.lua": "the layers go through heavyEntity / ModelTooHeavy before any override (drawLayers, startFirstPerson, firstPersonOver, shaderDraw, linesDraw)",
    "grymod/client/cl_cloak_refract.lua": "only reached through cl_cloak_fx.lua, which asks the guard first",
    "grymod/client/cl_cloak_shader.lua": "only reached through cl_cloak_fx.lua (shaderDraw), which asks the guard first",
    "grymod/client/cl_hud_binoculars_holo.lua": "Holo.Resolve leaves an entity out when Holo.Drawable says its model is too big",
}

GUARD_WORDS = ("ModelTooHeavy", "heavyEntity", "Holo.Drawable", "shaderDraw", "linesDraw")

# an override that sets a material (nil, false or no argument puts the engine's own back)
OVERRIDE = re.compile(r"render\.MaterialOverride(?:ByIndex)?\(\s*(?!nil\b|false\b|\))")


def lua_files():
    for folder, _, names in os.walk(os.path.join(LUA, "grymod")):
        for name in names:
            if name.endswith(".lua"):
                path = os.path.join(folder, name)

                yield os.path.relpath(path, LUA).replace(os.sep, "/"), path


def code_of(path):
    """The file without its comments (a `--` line comment may name the function)."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    return "\n".join(line.split("--", 1)[0] for line in lines)


class OverrideGuard(unittest.TestCase):
    def test_drawing_with_an_override_is_only_done_in_checked_files(self):
        unchecked = []

        for relative, path in lua_files():
            if OVERRIDE.search(code_of(path)) and relative not in CHECKED:
                unchecked.append(relative)

        self.assertEqual(
            unchecked, [],
            "These files draw a model with render.MaterialOverride and are not in the list of checked files (tools/test_override_guard.py): the engine freezes on a model with a mesh "
            "bigger than its dynamic vertex buffer. Make them ask GryMod.CloakFX.ModelTooHeavy first, then add them to CHECKED.")

    def test_a_checked_file_still_draws_with_an_override_and_mentions_the_guard(self):
        for relative, why in CHECKED.items():
            path = os.path.join(LUA, relative.replace("/", os.sep))

            self.assertTrue(os.path.exists(path), relative + " is in the list of checked files but does not exist (moved or renamed?)")

            code = code_of(path)

            self.assertTrue(OVERRIDE.search(code), relative + " no longer draws with an override: take it off the list of checked files")

            # the files that are only reached through the camouflage's layers carry no guard of their own: their line says so
            if "only reached through" in why:
                continue

            self.assertTrue(any(word in code for word in GUARD_WORDS), relative + " draws with an override and does not mention the guard any more (" + why + ")")


if __name__ == "__main__":
    unittest.main()
