"""Tests of tools/check_lua_syntax.py (needs `pip install lupa`: it carries LuaJIT, the Lua of the game): python -m unittest tools.test_check_lua_syntax"""
import os
import tempfile
import unittest

try:
    import lupa  # noqa: F401
except ImportError:  # the check itself needs it: the CI installs it
    lupa = None

from tools import check_lua_syntax as cls


@unittest.skipUnless(lupa, "lupa is not installed")
class Syntax(unittest.TestCase):
    def errors(self, text):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "x.lua")
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)

            return cls.check_files([path])

    def test_a_good_file_has_no_error(self):
        self.assertEqual(self.errors("local a = 1\nprint(a)\n"), [])

    def test_a_broken_file_is_reported_with_its_line(self):
        problems = self.errors("local a = 1\nif a then\nprint(a)\n")
        self.assertEqual(len(problems), 1)
        self.assertRegex(problems[0], r"x\.lua:\d+:")

    def test_continue_is_garrys_mod_lua_and_is_taken(self):
        self.assertEqual(self.errors("for i = 1, 3 do\n\tif i == 2 then continue end\n\tprint(i)\nend\n"), [])

    def test_the_word_continue_in_a_comment_or_a_name_is_not_touched(self):
        self.assertEqual(self.errors("-- continue\nlocal continued = 1\nprint(continued)\n"), [])

    def test_a_byte_order_mark_does_not_matter(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "x.lua")
            with open(path, "wb") as f:
                f.write(b"\xef\xbb\xbflocal a = 1\n")
            self.assertEqual(cls.check_files([path]), [])


if __name__ == "__main__":
    unittest.main()
