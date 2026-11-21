import os
import tempfile
import unittest

import unused_elements as ue
import unused_verdicts

FILM = """return {
	w=1000,h=800,fps=30,
	atlases={"grymod/flash/hud_test_1"},
	white={[1]=true},
	chars={
	[1]={k="shape",a=1,x=0,y=0,w=10,h=10,ox=0,oy=0,dw=10,dh=10},
	[2]={k="shape",a=1,x=10,y=0,w=20,h=10,ox=0,oy=0,dw=20,dh=10},
	[3]={k="shape",a=1,x=0,y=10,w=30,h=10,ox=0,oy=0,dw=30,dh=10},
	[4]={k="sprite",n=3,labels={["extra"]=2,["never"]=3},frames={
		{{d=1,c=1,n="Dot"},a={{"stop"}}},
		{{d=1,c=2},l="extra",a={{"stop"}}},
		{{d=1,c=3},l="never",a={{"stop"}}}
	}},
	[5]={k="sprite",n=1,labels={},frames={
		{{d=1,c=1,cx={0,0,0,1,255,0,0,0}}}
	}},
	[6]={k="sprite",n=1,labels={},frames={
		{{d=1,c=5,n="Tinted"}}
	}}
	},
	root={
		{{d=1,c=4,n="Root"},{d=2,c=6,n="Holder"},{d=3,c=5,n="Away",m={1,0,0,1,-500,0}},a={{"stop"}}}
	}
}
"""

SCRIPT = """var cur = _root.Root;
setHealth = function(v)
{
   _root.Root.gotoAndStop("extra");
};
setSecret = function()
{
   _root.Root.gotoAndStop("never");
};
setIndex = function(n)
{
   cur.gotoAndPlay(3);
};
setIdle = function()
{
};
"""

MODULE = """local Module = {}

-- setIdle is only written here, in a comment
function Module:SetHealth(v)
	self.root:Child("Root"):GotoAndStop("extra")
end

function Module.Feed(m)
	m:SetHealth(1)
end
"""


class Workspace:
    """A film, its ActionScript dump and a module in a temporary folder, registered as the film `hud_test`."""

    def __init__(self, film=FILM, script=SCRIPT, module=MODULE):
        self.folder = tempfile.TemporaryDirectory()
        base = self.folder.name
        self.flash = os.path.join(base, "flash")
        self.client = os.path.join(base, "client")
        self.scripts = os.path.join(base, "scripts")
        frame = os.path.join(self.scripts, "HUD_Test", "scripts", "frame_1")

        for path in (self.flash, self.client, frame):
            os.makedirs(path)

        self._write(os.path.join(self.flash, "hud_test.lua"), film)
        self._write(os.path.join(self.client, "cl_test.lua"), module)
        self._write(os.path.join(frame, "DoAction.as"), script)
        ue.FILMS["hud_test"] = ("HUD_Test", ["cl_test.lua"])

    @staticmethod
    def _write(path, text):
        with open(path, "w", newline="") as handle:
            handle.write(text)

    def analyse(self, verdicts=None, hidden=None):
        return ue.analyse("hud_test", self.scripts, verdicts or {}, hidden or {}, self.flash, self.client)

    def close(self):
        del ue.FILMS["hud_test"]
        self.folder.cleanup()


class DataTest(unittest.TestCase):
    def test_a_lua_table_with_strings_numbers_and_keys_is_read(self):
        table = ue.parse_lua_table('return {a=1,b="x\\"y",[2]=true,labels={["go"]=3},{1,2.5},"s"}')
        self.assertEqual(table.get("a"), 1)
        self.assertEqual(table.get("b"), 'x"y')
        self.assertIs(table.get(2), True)
        self.assertEqual(table.get("labels").get("go"), 3)
        self.assertEqual(table.arr[0].arr, [1, 2.5])
        self.assertEqual(table.arr[1], "s")

    def test_a_display_list_keeps_the_name_of_what_a_new_character_replaces(self):
        frames = [
            {"ops": [{"d": 1, "c": 7, "n": "Bar"}], "l": None, "a": []},
            {"ops": [{"d": 1, "c": 8}], "l": None, "a": []},
            {"ops": [{"rm": 1}], "l": None, "a": []},
        ]
        lists = ue.display_lists(frames)
        self.assertEqual(lists[0][1], (7, "Bar", None))
        self.assertEqual(lists[1][1], (8, "Bar", None))
        self.assertEqual(lists[2], {})

    def test_natural_play_stops_where_the_film_says_and_follows_its_jumps(self):
        stop = {"ops": [], "l": None, "a": [["stop"]]}
        plain = {"ops": [], "l": None, "a": []}
        self.assertEqual(ue.natural_play_from([plain, stop, plain], {}, 1, True), {1, 2})
        loop = {"ops": [], "l": None, "a": [["goto", 1]]}
        self.assertEqual(ue.natural_play_from([plain, loop, plain], {}, 1, True), {1, 2})
        self.assertEqual(ue.natural_play_from([plain, plain, stop], {"end": 3}, 3, False), {3})

    def test_the_real_data_files_load_and_every_shape_is_found(self):
        for name in ue.FILMS:
            path = os.path.join(ue.FLASH_DIR, name + ".lua")
            film = ue.load_film(path)

            with open(path, encoding="utf8", newline="") as handle:
                self.assertEqual(sum(1 for c in film.chars.values() if c["k"] == "shape"), handle.read().count('k="shape"'), name)


class ModuleTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.folder.name, "cl_x.lua")

    def tearDown(self):
        self.folder.cleanup()

    def refs(self, text):
        with open(self.path, "w", newline="") as handle:
            handle.write(text)

        return ue.ModuleRefs([self.path])

    def test_strings_count_but_comments_do_not(self):
        refs = self.refs('-- "Hidden" in a comment\nlocal a = x:Child("Shown")\n')
        self.assertEqual(refs.name("Shown"), (["cl_x.lua:2"], "literal"))
        self.assertEqual(refs.name("Hidden"), ([], None))

    def test_a_dotted_path_names_every_clip_on_it(self):
        refs = self.refs('root:Find("Root.Texts.Colorset")')
        self.assertEqual(refs.name("Texts")[1], "literal")

    def test_a_name_built_from_a_prefix_a_pattern_or_two_pieces_is_found(self):
        refs = self.refs('a("Crosshair" .. i)\nb("^TargetIcon")\nc("low", "green")\n')
        self.assertEqual(refs.name("Crosshair12")[1], "prefix")
        self.assertEqual(refs.name("TargetIconTL")[1], "pattern")
        self.assertEqual(refs.composed("lowgreen")[1], "composed")
        self.assertEqual(refs.name("Crosshairs"), ([], None))

    def test_a_function_is_defined_and_called_or_only_defined(self):
        refs = self.refs("function Panel:SetDamage(v) end\nfunction Panel:SetFov(v) end\nlocal p = Panel.New()\np:SetFov(3)\n")
        self.assertTrue(refs.function_defs("setDamage"))
        self.assertFalse(refs.function_calls("setDamage"))
        self.assertTrue(refs.function_calls("setFOV"))

    def test_a_label_can_be_said_as_a_member(self):
        refs = self.refs("if definition.labels.explosivegrenade then end")
        self.assertEqual(ue.label_hit(refs, "explosivegrenade")[1], "member")


class ScriptTest(unittest.TestCase):
    def setUp(self):
        self.work = Workspace()
        self.film = ue.load_film(os.path.join(self.work.flash, "hud_test.lua"))
        self.scripts = ue.Scripts(self.film, os.path.join(self.work.scripts, "HUD_Test", "scripts"))

    def tearDown(self):
        self.work.close()

    def test_the_functions_of_the_root_are_the_api(self):
        self.assertEqual(self.scripts.api(), ["setHealth", "setSecret", "setIndex", "setIdle"])

    def test_a_jump_names_the_clip_it_reaches_and_the_function_that_makes_it(self):
        jump = [j for j in self.scripts.jumps if j["arg"] == '"never"'][0]
        self.assertEqual((jump["function"], jump["targets"]), ("setSecret", [4]))

    def test_a_variable_that_holds_a_clip_and_a_frame_number_are_followed(self):
        jump = [j for j in self.scripts.jumps if j["function"] == "setIndex"][0]
        self.assertEqual((jump["targets"], jump["arg"]), ([4], "3"))

    def test_the_api_that_reaches_a_function_includes_the_function_itself(self):
        self.assertEqual(self.scripts.api_reaching("setSecret"), {"setSecret"})

    def test_a_script_text_is_cut_into_its_conditions(self):
        text = "setX = function()\n{\n   if(_root.A == 1)\n   {\n      gotoAndStop(2);\n   }\n};\n"
        self.assertEqual(ue._conditions(text, text.index("gotoAndStop")), ["_root.A == 1"])


class InventoryTest(unittest.TestCase):
    def setUp(self):
        self.work = Workspace()
        self.report = self.work.analyse()

    def tearDown(self):
        self.work.close()

    def row(self, kind, name):
        return [r for r in self.report[kind] if r["name"] == name][0]

    def test_a_function_the_module_defines_and_calls_is_used_and_one_it_lacks_is_not(self):
        self.assertEqual(self.row("functions", "setHealth")["cls"], "used")
        self.assertEqual(self.row("functions", "setSecret")["cls"], "d")

    def test_a_comment_does_not_port_a_function(self):
        self.assertEqual(self.row("functions", "setIdle")["status"], "missing")

    def test_a_label_the_module_names_is_used_and_one_only_an_unported_function_reaches_is_a_missing_feature(self):
        self.assertEqual(self.row("labels", "extra")["cls"], "used")
        never = self.row("labels", "never")
        self.assertEqual(never["cls"], "b")
        self.assertEqual(never["apis"], ["setIndex", "setSecret"])

    def test_a_clip_the_film_draws_by_itself_or_off_the_stage_needs_nothing(self):
        self.assertEqual(self.row("clips", "Dot")["cls"], "a")
        self.assertEqual(self.row("clips", "Tinted")["cls"], "a")
        away = self.row("clips", "Away")
        self.assertEqual(away["cls"], "a")
        self.assertIn("off the stage", away["reason"])

    def test_a_clip_the_module_names_is_used(self):
        self.assertEqual(self.row("clips", "Root")["cls"], "used")

    def test_a_shape_only_a_missing_feature_draws_is_dead_and_the_twin_follows_the_colour_actions(self):
        shapes = self.report["shapes"]
        self.assertEqual(shapes["dead"], [3])
        self.assertEqual(shapes["dead_pixels"], 300)
        self.assertEqual(shapes["white_needed"], 1)
        # the twin would hold shape 1 only: shape 2 (200 pixels, live) never draws in white mode; shape 3 is dead (counted apart)
        self.assertEqual(shapes["twin_by_use_bytes"], int(200 * 4 / 3))
        self.assertEqual(shapes["dead_bytes"], int(300 * 4 / 3) * 2)

    def test_a_verdict_replaces_the_automatic_class_and_a_hidden_path_hides_a_clip(self):
        verdicts = {("hud_test", "function", "setSecret"): {"cls": "c", "what": "never called"}}
        report = self.work.analyse(verdicts, {"hud_test": {"Root": "cl_test.lua:1"}})
        row = [r for r in report["functions"] if r["name"] == "setSecret"][0]
        self.assertEqual((row["cls"], row["what"]), ("c", "never called"))
        root = [r for r in report["clips"] if r["name"] == "Root"][0]
        self.assertEqual(root["cls"], "b")

    def test_a_label_verdict_can_name_one_clip(self):
        verdicts = {("hud_test", "label", "never@4"): {"cls": "c", "what": "orphan"}}
        report = self.work.analyse(verdicts)
        self.assertEqual([r["cls"] for r in report["labels"] if r["name"] == "never"], ["c"])


class DanglingTest(unittest.TestCase):
    def test_a_jump_to_a_label_the_clip_does_not_have_is_found(self):
        film = ue.Film.__new__(ue.Film)
        film.root = [{"ops": [], "l": None, "a": []}]
        film.chars = {5: {"k": "sprite", "n": 1, "labels": {"here": 1},
                          "frames": [{"ops": [], "l": None, "a": [["gotol", "here"], ["gotol", "close"]]}]}}
        film.file, film.char_lines = "x.lua", {5: 3}
        film.lines = []
        self.assertEqual([d["label"] for d in ue.dangling_actions(film)], ["close"])


class VerdictsTest(unittest.TestCase):
    def test_every_verdict_is_well_formed_and_names_a_film_we_have(self):
        for (film, kind, name), verdict in unused_verdicts.VERDICTS.items():
            self.assertIn(film, ue.FILMS)
            self.assertIn(kind, ("function", "label", "clip"))
            self.assertIn(verdict["cls"], ("used", "a", "b", "c", "d"), (film, name))
            self.assertTrue(verdict.get("what"), (film, name))
            self.assertTrue(verdict.get("source"), (film, name))

            if verdict["cls"] == "b":
                self.assertTrue(verdict.get("effort") and verdict.get("priority"), (film, name))

    def test_every_hidden_path_is_a_placement_of_its_film(self):
        for film_name, paths in unused_verdicts.HIDDEN.items():
            film = ue.load_film(os.path.join(ue.FLASH_DIR, film_name + ".lua"))
            known = set()
            scripts = ue.Scripts(film, "no-such-folder")
            chains = ue.clip_paths(film)

            for owner, frames in film.timelines():
                for state in ue.display_lists(frames):
                    for char, name, _ in state.values():
                        if film.chars.get(char, {}).get("k") == "sprite" and owner in chains:
                            known.add(".".join(chains[owner] + [name or "#%d" % char]))

            for path in paths:
                self.assertIn(path, known, (film_name, path))


if __name__ == "__main__":
    unittest.main()
