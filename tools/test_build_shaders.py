"""Tests of tools/build_shaders.py (the shader compiler is replaced by a small script that writes the files the real one would)."""
import os
import sys
import tempfile
import unittest

from tools import build_shaders as bs

FAKE_COMPILER = r'''
import os, sys
args = sys.argv[1:]
version = args[args.index("-ver") + 1]
shaderpath = args[args.index("-shaderpath") + 1]
source = args[-1]
name = os.path.splitext(os.path.basename(source))[0]
assert os.path.exists(os.path.join(shaderpath, os.path.basename(source))), "the source must be in the shader path"
assert os.path.exists(os.path.join(shaderpath, "common_ps_fxc.h")), "the SDK headers must be next to the sources"
os.makedirs(os.path.join(shaderpath, "shaders", "fxc"), exist_ok=True)
with open(os.path.join(shaderpath, "shaders", "fxc", name + ".vcs"), "w") as out:
    out.write("compiled %s with model %s" % (name, version))
'''


class VersionTest(unittest.TestCase):
    def test_the_model_comes_from_the_file_name(self):
        self.assertEqual(bs.shader_model("grymod_cloak_ps30.hlsl"), "30")
        self.assertEqual(bs.shader_model("grymod_cloak_vs30.hlsl"), "30")
        self.assertEqual(bs.shader_model("thing_ps20b.hlsl"), "20b")
        self.assertEqual(bs.shader_model("thing_ps2x.hlsl"), "20b")

    def test_a_name_without_a_stage_and_model_is_refused(self):
        for name in ("thing.hlsl", "thing_ps.hlsl", "thing_ps40.hlsl", "readme.txt"):
            with self.assertRaises(ValueError, msg=name):
                bs.shader_model(name)


class BuildTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.src = os.path.join(root, "src")
        self.headers = os.path.join(root, "headers")
        self.out = os.path.join(root, "out")
        os.makedirs(self.src)
        os.makedirs(self.headers)
        for name in ("a_ps30.hlsl", "a_vs30.hlsl"):
            with open(os.path.join(self.src, name), "w") as f:
                f.write("// " + name)
        with open(os.path.join(self.src, "notes.txt"), "w") as f:
            f.write("not a shader")
        for name in ("common_ps_fxc.h", "common_vs_fxc.h"):
            with open(os.path.join(self.headers, name), "w") as f:
                f.write("// header")
        self.compiler = os.path.join(root, "fake_compiler.py")
        with open(self.compiler, "w") as f:
            f.write(FAKE_COMPILER)

    def tearDown(self):
        self.tmp.cleanup()

    def run_build(self, **kwargs):
        return bs.build(self.src, self.out, [sys.executable, self.compiler], self.headers, **kwargs)

    def test_every_shader_of_the_source_folder_is_compiled_into_the_output_folder(self):
        built = self.run_build()
        self.assertEqual(sorted(built), ["a_ps30.vcs", "a_vs30.vcs"])
        self.assertEqual(sorted(os.listdir(self.out)), ["a_ps30.vcs", "a_vs30.vcs"])
        with open(os.path.join(self.out, "a_ps30.vcs")) as f:
            self.assertEqual(f.read(), "compiled a_ps30 with model 30")

    def test_the_source_folder_is_left_as_it_was(self):
        self.run_build()
        self.assertEqual(sorted(os.listdir(self.src)), ["a_ps30.hlsl", "a_vs30.hlsl", "notes.txt"])

    def test_a_missing_header_folder_is_an_error_that_names_it(self):
        with self.assertRaises(FileNotFoundError) as ctx:
            bs.build(self.src, self.out, [sys.executable, self.compiler], os.path.join(self.tmp.name, "nowhere"))
        self.assertIn("nowhere", str(ctx.exception))

    def test_a_compiler_that_fails_stops_the_build(self):
        with open(self.compiler, "w") as f:
            f.write("import sys; sys.exit(3)")
        with self.assertRaises(RuntimeError):
            self.run_build()

    def test_a_compiler_that_writes_nothing_is_an_error(self):
        with open(self.compiler, "w") as f:
            f.write("pass")
        with self.assertRaises(RuntimeError) as ctx:
            self.run_build()
        self.assertIn("a_ps30", str(ctx.exception))

    def test_the_names_can_get_a_suffix_for_a_game_that_keeps_the_old_code(self):
        built = self.run_build(suffix="_r2")
        self.assertEqual(sorted(built), ["a_ps30_r2.vcs", "a_vs30_r2.vcs"])


class PackagingTest(unittest.TestCase):
    def test_the_workshop_package_leaves_the_shader_sources_out_but_ships_the_compiled_ones(self):
        """gmad's white list takes shaders/fxc/*.vcs and not .hlsl: the sources stay in the repository, the .vcs go to the players."""
        import json

        root = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        with open(os.path.join(root, "addon.json"), encoding="utf8") as f:
            ignore = json.load(f)["ignore"]
        self.assertIn("shaders/src/*", ignore)
        self.assertFalse(any(pattern.startswith("shaders/fxc") or pattern == "*.vcs" for pattern in ignore))
        self.assertTrue(any(name.endswith(".vcs") for name in os.listdir(os.path.join(root, "shaders", "fxc"))))


if __name__ == "__main__":
    unittest.main()
