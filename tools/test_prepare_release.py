"""Tests of tools/prepare_release.py: python -m unittest tools.test_prepare_release (from the repository root).

Every test builds a small addon in a temporary folder and gives the list of tracked files itself (no git needed), so what is checked is the rule, not this repository.
"""
import json
import os
import shutil
import tempfile
import unittest

from tools import prepare_release as pr

SHARED = (
    "if not GryMod then\n\tGryMod = {}\nend\n\nGryMod.WSID = 153963150\nGryMod.Workshop = false\n\nGryMod.Modes = {\n\tARMOR = 0\n}\n"
)
ADDON = {"title": "T", "type": "tool", "tags": ["fun", "realism"], "ignore": ["*.md", "tests/*", "dev_resources/*", ".git*", ".github/*"]}


class Addon:
    """A temporary addon folder: files = {path: text or bytes}."""

    def __init__(self, files=None, addon=None, shared=SHARED):
        self.dir = tempfile.TemporaryDirectory()
        self.root = self.dir.name
        base = {
            "addon.json": json.dumps(addon if addon is not None else ADDON),
            "lua/autorun/grymod_shared.lua": shared,
            "lua/grymod/a.lua": "print(1)\n",
            "materials/grymod/a.vmt": "x",
            "shaders/fxc/s_ps30.vcs": b"\x01\x02",
            "dev_resources/shaders/s_ps30.hlsl": "float4 main() { return 0; }",
            "README.md": "doc",
            "tests/t.lua": "x",
        }
        base.update(files or {})
        self.tracked = []

        for path, content in base.items():
            if content is None:
                continue
            full = os.path.join(self.root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "wb") as f:
                f.write(content if isinstance(content, bytes) else content.encode())
            self.tracked.append(path)

    def out(self):
        return os.path.join(self.root, "_out")

    def prepare(self, **kw):
        kw.setdefault("version", "1.2")
        return pr.prepare(self.root, self.out(), tracked=self.tracked, **kw)

    def read(self, path):
        with open(os.path.join(self.out(), path), "rb") as f:
            return f.read().decode()

    def cleanup(self):
        self.dir.cleanup()


class IgnoreRules(unittest.TestCase):
    def test_the_patterns_of_addon_json_match_the_whole_path_or_the_name(self):
        patterns = ["*.md", "tests/*", ".git*", "LICENSE"]
        self.assertTrue(pr.is_ignored("README.md", patterns))
        self.assertTrue(pr.is_ignored("docs/deep/x.md", patterns))
        self.assertTrue(pr.is_ignored("tests/a/b.lua", patterns))
        self.assertTrue(pr.is_ignored(".gitattributes", patterns))
        self.assertTrue(pr.is_ignored("LICENSE", patterns))
        self.assertFalse(pr.is_ignored("lua/grymod/a.lua", patterns))
        self.assertFalse(pr.is_ignored("materials/tests.vmt", patterns))


class Prepare(unittest.TestCase):
    def setUp(self):
        self.addon = Addon()

    def tearDown(self):
        self.addon.cleanup()

    def test_the_package_has_what_the_players_need_and_nothing_else(self):
        report = self.addon.prepare()
        self.assertEqual(
            sorted(report["files"]),
            ["addon.json", "lua/autorun/grymod_shared.lua", "lua/grymod/a.lua", "materials/grymod/a.vmt", "shaders/fxc/s_ps30.vcs"],
        )
        self.assertFalse(os.path.exists(os.path.join(self.addon.out(), "README.md")))
        self.assertFalse(os.path.exists(os.path.join(self.addon.out(), "tests")))

    def test_a_file_that_git_does_not_track_is_not_in_the_package(self):
        with open(os.path.join(self.addon.root, "lua", "grymod", "junk.lua"), "w") as f:
            f.write("x")
        self.assertNotIn("lua/grymod/junk.lua", self.addon.prepare()["files"])

    def test_the_version_is_written_after_the_workshop_line_and_a_leading_v_goes(self):
        self.addon.prepare(version="v4.3")
        text = self.addon.read("lua/autorun/grymod_shared.lua")
        self.assertIn('GryMod.Workshop = false\nGryMod.Version = "4.3"\n', text)
        self.assertEqual(text.count("GryMod.Version"), 1)

    def test_the_workshop_flavour_turns_the_flag_on_and_the_plain_one_leaves_it_off(self):
        self.addon.prepare(workshop=True)
        self.assertIn("GryMod.Workshop = true\n", self.addon.read("lua/autorun/grymod_shared.lua"))
        self.assertNotIn("GryMod.Workshop = false", self.addon.read("lua/autorun/grymod_shared.lua"))

    def test_the_source_tree_is_never_changed(self):
        self.addon.prepare(workshop=True)
        with open(os.path.join(self.addon.root, "lua/autorun/grymod_shared.lua")) as f:
            self.assertEqual(f.read(), SHARED)

    def test_windows_line_endings_are_kept(self):
        self.addon.cleanup()
        self.addon = Addon(shared=SHARED.replace("\n", "\r\n"))
        self.addon.prepare(workshop=True)
        text = self.addon.read("lua/autorun/grymod_shared.lua")
        self.assertIn('GryMod.Workshop = true\r\nGryMod.Version = "1.2"\r\n', text)
        self.assertNotIn("\n\n\r", text)

    def test_the_report_gives_the_size_and_the_workshop_id_found(self):
        report = self.addon.prepare()
        self.assertEqual(report["wsid"], 153963150)
        self.assertGreater(report["bytes"], 0)


class Refusals(unittest.TestCase):
    def check(self, message, files=None, addon=None, shared=SHARED, **kw):
        a = Addon(files=files, addon=addon, shared=shared)
        try:
            with self.assertRaises(pr.ReleaseError) as caught:
                a.prepare(**kw)
            self.assertIn(message, str(caught.exception))
        finally:
            a.cleanup()

    def test_a_version_that_is_not_a_version(self):
        for bad in ("", "latest", "4", "4.2.", '4.2"x', "4.2 beta"):
            self.check("version", version=bad)

    def test_a_version_like_the_tags_of_the_repository_is_fine(self):
        a = Addon()
        try:
            for good in ("4.2", "v4.3", "4.3.1", "5.0-rc1"):
                shutil.rmtree(a.out(), ignore_errors=True)
                a.prepare(version=good)
        finally:
            a.cleanup()

    def test_the_workshop_line_missing_or_twice(self):
        self.check("GryMod.Workshop", shared=SHARED.replace("GryMod.Workshop = false", "-- nothing"))
        self.check("GryMod.Workshop", shared=SHARED + "GryMod.Workshop = false\n")

    def test_the_repository_must_ship_the_plain_flavour(self):
        self.check("GryMod.Workshop", shared=SHARED.replace("GryMod.Workshop = false", "GryMod.Workshop = true"))

    def test_a_version_already_written_in_the_source(self):
        self.check("GryMod.Version", shared=SHARED + 'GryMod.Version = "x"\n')

    def test_the_workshop_id_of_the_code_must_be_the_one_given(self):
        self.check("153963150", expect_wsid=111)

    def test_the_workshop_id_given_must_be_a_number(self):
        self.check("workshop id", expect_wsid="")
        self.check("workshop id", expect_wsid="abc")

    def test_the_workshop_id_of_the_code_is_read_not_assumed(self):
        self.check("GryMod.WSID", shared=SHARED.replace("GryMod.WSID = 153963150\n", ""), expect_wsid=153963150)

    def test_a_matching_workshop_id_passes(self):
        a = Addon()
        try:
            self.assertEqual(a.prepare(expect_wsid="153963150")["wsid"], 153963150)
        finally:
            a.cleanup()

    def test_a_final_release_refuses_the_id_of_the_old_item(self):
        # GryMod Remastered is a new Workshop item: the code must not still point at the old GryMod item (the servers would ask their players to subscribe to it)
        self.check("old GryMod item", final=True)

    def test_a_final_release_with_the_new_id_passes(self):
        a = Addon(shared=SHARED.replace("153963150", "3500000001"))
        try:
            self.assertEqual(a.prepare(final=True, expect_wsid="3500000001")["wsid"], 3500000001)
        finally:
            a.cleanup()

    def test_without_final_the_old_id_is_allowed_(self):
        a = Addon()
        try:
            self.assertEqual(a.prepare()["wsid"], 153963150)
        finally:
            a.cleanup()

    def test_too_big(self):
        self.check("MB", files={"materials/grymod/big.vtf": b"0" * 3_000_000}, max_mb=2)

    def test_a_file_type_the_workshop_would_refuse(self):
        for path in ("lua/x.py", "shaders/fxc/x.hlsl", "materials/x.psd", "lua/x.exe"):
            self.check(path, files={path: "x"})

    def test_a_dev_file_that_the_ignore_list_forgot(self):
        self.check("tools/x.py", files={"tools/x.py": "x"})

    def test_two_paths_that_differ_by_case_only(self):
        self.check("lower case", files={"materials/grymod/A.vmt": "x"})

    def test_a_path_with_a_character_the_workshop_refuses(self):
        self.check("characters", files={"lua/grymod/my file.lua": "x"})

    def test_the_addon_json_must_be_complete(self):
        self.check("title", addon={"type": "tool", "tags": ["fun"]})
        self.check("type", addon={"title": "T", "type": "nonsense", "tags": ["fun"]})
        self.check("tag", addon={"title": "T", "type": "tool", "tags": ["fun", "realism", "water"]})
        self.check("tag", addon={"title": "T", "type": "tool", "tags": ["notatag"]})

    def test_a_shader_source_without_its_compiled_file(self):
        self.check("s2_ps30", files={"dev_resources/shaders/s2_ps30.hlsl": "x"})

    def test_a_compiled_shader_that_is_empty(self):
        self.check("empty", files={"shaders/fxc/s_ps30.vcs": b""})

    def test_the_shared_file_missing(self):
        self.check("grymod_shared.lua", files={"lua/autorun/grymod_shared.lua": None})


if __name__ == "__main__":
    unittest.main()
