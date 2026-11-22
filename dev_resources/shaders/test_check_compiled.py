"""Tests of check_compiled.py: python -m unittest discover -s dev_resources/shaders (from the repository root)."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_compiled as cc  # noqa: E402


class Folder:
    def __init__(self):
        self.dir = tempfile.TemporaryDirectory()
        self.src = os.path.join(self.dir.name, "src")
        self.out = os.path.join(self.dir.name, "fxc")
        os.makedirs(self.src)
        os.makedirs(self.out)
        self.manifest = os.path.join(self.src, "compiled.sha256")

    def write(self, folder, name, content):
        with open(os.path.join(folder, name), "wb") as f:
            f.write(content if isinstance(content, bytes) else content.encode())

    def shader(self, base, source="float4 main() { return 0; }\n", compiled=b"\x01\x02\x03"):
        self.write(self.src, base + ".hlsl", source)
        self.write(self.out, base + ".vcs", compiled)

    def check(self):
        return cc.check(self.src, self.out, self.manifest)

    def update(self):
        return cc.update(self.src, self.out, self.manifest)

    def cleanup(self):
        self.dir.cleanup()


class CheckCompiled(unittest.TestCase):
    def setUp(self):
        self.f = Folder()
        self.f.shader("a_ps30")
        self.f.shader("b_vs30", "other\n", b"\x09")

    def tearDown(self):
        self.f.cleanup()

    def test_after_an_update_everything_is_in_order(self):
        self.f.update()
        self.assertEqual(self.f.check(), [])

    def test_without_a_manifest_it_says_so(self):
        self.assertTrue(any("manifest" in p for p in self.f.check()))

    def test_a_source_changed_after_the_compilation(self):
        self.f.update()
        self.f.write(self.f.src, "a_ps30.hlsl", "float4 main() { return 1; }\n")
        problems = self.f.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("a_ps30", problems[0])
        self.assertIn("changed", problems[0])

    def test_a_compiled_file_replaced_without_its_source_changing(self):
        self.f.update()
        self.f.write(self.f.out, "b_vs30.vcs", b"\x0a")
        problems = self.f.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("b_vs30", problems[0])

    def test_line_endings_of_the_source_do_not_matter(self):
        self.f.update()
        self.f.write(self.f.src, "b_vs30.hlsl", b"other\r\n")
        self.assertEqual(self.f.check(), [])

    def test_a_new_shader_that_the_manifest_does_not_know(self):
        self.f.update()
        self.f.shader("c_ps30")
        problems = self.f.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("c_ps30", problems[0])
        self.assertIn("not in the manifest", problems[0])

    def test_a_shader_in_the_manifest_that_was_removed(self):
        self.f.update()
        os.remove(os.path.join(self.f.src, "b_vs30.hlsl"))
        os.remove(os.path.join(self.f.out, "b_vs30.vcs"))
        problems = self.f.check()
        self.assertEqual(len(problems), 1)
        self.assertIn("b_vs30", problems[0])
        self.assertIn("no longer", problems[0])

    def test_a_source_without_its_compiled_file(self):
        self.f.update()
        os.remove(os.path.join(self.f.out, "a_ps30.vcs"))
        self.assertTrue(any("a_ps30" in p and "missing" in p for p in self.f.check()))

    def test_an_empty_compiled_file(self):
        self.f.shader("a_ps30", compiled=b"")
        with self.assertRaises(cc.ManifestError):
            self.f.update()

    def test_update_refuses_a_source_without_its_compiled_file(self):
        os.remove(os.path.join(self.f.out, "a_ps30.vcs"))
        with self.assertRaises(cc.ManifestError):
            self.f.update()

    def test_the_manifest_is_the_same_whatever_the_order_of_the_files(self):
        self.f.update()
        with open(self.f.manifest, "rb") as f:
            first = f.read()
        self.f.update()
        with open(self.f.manifest, "rb") as f:
            self.assertEqual(f.read(), first)
        self.assertEqual(first.splitlines()[1:], sorted(first.splitlines()[1:]))


if __name__ == "__main__":
    unittest.main()
