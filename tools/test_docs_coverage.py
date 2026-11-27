"""The reference documentation and the code must agree. No game needed.

What the code exposes to other addons is read from the Lua files, and each of them must have an entry in the reference pages:

  * the hooks GryMod fires (hook.Run / hook.Call of a name that starts with Gry)       -> a heading in docs/hooks.md
  * the networked variables (SetNW2Bool, SetNW2Int, SetNW2Float, SetNW2Entity...)      -> the name in backticks in docs/networking.md
  * the network messages (util.AddNetworkString)                                       -> the name in backticks in docs/networking.md
  * the functions and the constants of the extension API (GryMod.API, and GryMod.Radar for the marker sources) -> a heading `GryMod.API.Name` in a page of docs/reference/

The other way round, a heading of the reference pages that names a hook or a function that the code does not have is refused: a page that
describes what was removed or renamed is worse than no page.

Run: python -m unittest tools.test_docs_coverage
"""

import glob
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "lua")
DOCS = os.path.join(ROOT, "docs")
HOOKS_PAGE = os.path.join(DOCS, "hooks.md")
NETWORK_PAGE = os.path.join(DOCS, "networking.md")
REFERENCE_PAGES = sorted(glob.glob(os.path.join(DOCS, "reference", "*.md")))

# hooks that a helper fires with the name in a variable (a search for hook.Run finds only the helper): listed here, documented in the last table of docs/hooks.md,
# and each must still be written as a string somewhere in the code
INDIRECT_HOOKS = (
    "GryMod_MapOpened",
    "GryMod_MapClosed",
    "GryMod_MapZoomed",
    "GryMod_MinimapBelowReady",
    "GryMod_MinimapOutsideReady",
    "GryMod_ObjectiveAdded",
    "GryMod_ObjectiveChanged",
    "GryMod_ObjectiveRemoved",
)

# a name that starts with "_" is private; the other names that the files assign to GryMod.API without being part of the interface are listed here
INTERNAL_API = set()


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def lua_sources():
    for folder, _, names in os.walk(LUA):
        for name in sorted(names):
            if name.endswith(".lua"):
                path = os.path.join(folder, name)
                yield os.path.relpath(path, ROOT).replace(os.sep, "/"), read(path)


def code_hooks():
    """The hooks the code fires for other addons to listen to."""
    found = set()

    for _, text in lua_sources():
        for line in text.splitlines():
            # every Gry name on a line that runs a hook: hook.Run("Name"), pcall(hook.Run, "Name", ...), hook.Run(ok and "A" or "B")
            if re.search(r"hook\.(?:Run|Call)\b", line) and not line.lstrip().startswith("--"):
                found.update(re.findall(r'"(Gry[A-Za-z0-9_]+)"', line))

    return found


def code_network_variables():
    found = set()

    for _, text in lua_sources():
        found.update(re.findall(r'Set(?:NW2|NW|Networked)[A-Za-z]*\(\s*"([A-Za-z0-9_]+)"', text))

    return found


def code_network_messages():
    found = set()

    for _, text in lua_sources():
        found.update(re.findall(r'util\.AddNetworkString\(\s*"([A-Za-z0-9_]+)"', text))

    return found


def code_api():
    """{full name: kind} of what the extension API holds: 'function' for a `function API.Name(`, 'value' for the constants and tables it is given.

    A file says what its local `API` is (`local API = GryMod.API`): the radar's marker sources are defined by a file whose `API` is `GryMod.Radar`, and they
    are documented under that name."""
    found = {}

    for _, text in lua_sources():
        alias = re.search(r"^local API = (GryMod\.[A-Za-z]+)(?:\s+or\s+\{\})?\s*$", text, re.M)
        namespace = alias.group(1) if alias else None

        for name in re.findall(r"^function GryMod\.API\.([A-Za-z][A-Za-z0-9_]*)\s*\(", text, re.M):
            found["GryMod.API." + name] = "function"

        if namespace:
            for name in re.findall(r"^function API\.([A-Za-z][A-Za-z0-9_]*)\s*\(", text, re.M):
                found["%s.%s" % (namespace, name)] = "function"

            for name in re.findall(r"^API\.([A-Z][A-Za-z0-9_]*)\s*=", text, re.M):
                found.setdefault("%s.%s" % (namespace, name), "value")

        for name in re.findall(r"^GryMod\.API\.([A-Z][A-Za-z0-9_]*)\s*=", text, re.M):
            found.setdefault("GryMod.API." + name, "value")

    return {name: kind for name, kind in found.items() if name.rsplit(".", 1)[1] not in INTERNAL_API}


def headings(path):
    if not os.path.exists(path):
        return []

    return [line for line in read(path).splitlines() if re.match(r"^#{2,4} ", line)]


def reference_headings():
    out = []

    for path in REFERENCE_PAGES:
        out.extend(headings(path))

    return out


def reference_text():
    return "\n".join(read(path) for path in REFERENCE_PAGES)


def mentioned(name, lines):
    return any(re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(name), line) for line in lines)


class ExtractionTest(unittest.TestCase):
    """The readers find what is known to exist (if they find nothing, the coverage below proves nothing)."""

    def test_hooks_are_found(self):
        hooks = code_hooks()
        self.assertGreaterEqual(len(hooks), 15)
        self.assertIn("GryMod_ModeChanged", hooks)

    def test_network_names_are_found(self):
        self.assertIn("GryEnergy", code_network_variables())
        self.assertIn("GryMode", code_network_variables())
        self.assertIn("gry_radar", code_network_messages())
        self.assertGreaterEqual(len(code_network_messages()), 30)

    def test_api_is_found(self):
        api = code_api()
        self.assertGreaterEqual(len(api), 100)
        self.assertEqual(api.get("GryMod.API.SetMode"), "function")
        self.assertEqual(api.get("GryMod.API.Version"), "value")
        self.assertEqual(api.get("GryMod.Radar.AddSource"), "function")
        self.assertNotIn("GryMod.API._TrackedRelation", api)


class CoverageTest(unittest.TestCase):
    def test_every_hook_has_a_heading(self):
        lines = headings(HOOKS_PAGE)
        missing = sorted(name for name in code_hooks() if not mentioned(name, lines))
        self.assertEqual(missing, [], "docs/hooks.md has no heading for these hooks")

    def test_every_network_variable_is_described(self):
        text = read(NETWORK_PAGE) if os.path.exists(NETWORK_PAGE) else ""
        missing = sorted(name for name in code_network_variables() if "`%s`" % name not in text)
        self.assertEqual(missing, [], "docs/networking.md does not describe these networked variables")

    def test_every_network_message_is_described(self):
        text = read(NETWORK_PAGE) if os.path.exists(NETWORK_PAGE) else ""
        missing = sorted(name for name in code_network_messages() if "`%s`" % name not in text)
        self.assertEqual(missing, [], "docs/networking.md does not describe these network messages")

    def test_every_api_function_and_constant_has_a_heading(self):
        lines = reference_headings()
        missing = sorted(name for name in code_api() if not mentioned(name, lines))
        self.assertEqual(missing, [], "no heading with the full name in docs/reference/ for these")


class IndirectHookTest(unittest.TestCase):
    def test_indirect_hooks_exist_in_the_code(self):
        text = "\n".join(source for _, source in lua_sources())
        missing = [name for name in INDIRECT_HOOKS if '"%s"' % name not in text]
        self.assertEqual(missing, [], "these hooks are not written anywhere in the code any more: update INDIRECT_HOOKS and docs/hooks.md")

    def test_indirect_hooks_are_described(self):
        text = read(HOOKS_PAGE) if os.path.exists(HOOKS_PAGE) else ""
        missing = [name for name in INDIRECT_HOOKS if "`%s`" % name not in text]
        self.assertEqual(missing, [], "docs/hooks.md does not describe these hooks")


class OrphanTest(unittest.TestCase):
    """A heading must name something that exists."""

    def test_no_hook_heading_without_a_hook(self):
        known = code_hooks()
        named = set()

        for line in headings(HOOKS_PAGE):
            named.update(re.findall(r"(?<![A-Za-z0-9_])(Gry[A-Za-z0-9_]+)", line))

        self.assertEqual(sorted(named - known), [], "docs/hooks.md names hooks that the code does not fire")

    def test_no_api_heading_without_a_function(self):
        known = set(code_api())
        named = set()

        for line in reference_headings():
            named.update(re.findall(r"GryMod\.(?:API|Radar)\.[A-Za-z][A-Za-z0-9_]*", line))

        self.assertEqual(sorted(named - known), [], "docs/reference/ names API entries that the code does not have")


if __name__ == "__main__":
    unittest.main()
