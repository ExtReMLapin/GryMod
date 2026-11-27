"""The loader (lua/autorun/grymod_shared.lua) and the files of lua/grymod must agree. No game needed.

A file that is moved or renamed and not changed in the loader is not loaded, and the game says nothing: a feature is simply missing. A new file that
nobody includes is the same. This checks, for every file under lua/grymod (the campaign data are loaded by the campaign code, not here):

  * every path the loader names exists (a typo, a file that was moved);
  * every file is named by the loader: AddCSLuaFile for what the client runs, include for what a realm runs;
  * a file included by another file (`local Math = include("grymod/sh_flash_bar.lua")`) counts as run in the realms of the file that includes it;
  * a file of client/ is sent to the client and run there, never on the server; a file of server/ is run on the server and never sent; a shared file
    (sh_ prefix, compat/ included) is sent to the client and run by at least one realm; the converted movies (flash/) are sent, and loaded by the Flash player.

Run: python -m unittest tools.test_loader_coverage
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOADER = os.path.join(ROOT, "lua", "autorun", "grymod_shared.lua")
LUA = os.path.join(ROOT, "lua")

# loaded by their own code, not by the loader
DYNAMIC_DIRS = ("grymod/campaign/",)


def blocks(text):
    """The text of the `if SERVER then ... end` and of the `if CLIENT then ... end` blocks of the loader (they start and end at column 0)."""
    found = {}

    for realm in ("SERVER", "CLIENT"):
        match = re.search(r"^if %s then\n(.*?)^end\n" % realm, text, re.S | re.M)
        found[realm] = match.group(1) if match else ""

    return found


def named(block, call):
    return re.findall(r'^\s*%s\("([^"]+)"\)' % call, block, re.M)


def lua_files():
    base = os.path.join(LUA, "grymod")
    out = []

    for folder, _, names in os.walk(base):
        for name in names:
            if name.endswith(".lua"):
                rel = os.path.relpath(os.path.join(folder, name), LUA).replace(os.sep, "/")

                if not rel.startswith(DYNAMIC_DIRS):
                    out.append(rel)

    return sorted(out)


def nested_includes():
    """{path: set of realms} for the files that other files of grymod/ include with include("grymod/...")."""
    found = {}

    for path in lua_files():
        with open(os.path.join(LUA, path), encoding="utf-8") as f:
            text = f.read()

        realm = realm_of(path)
        realms = {"client", "server"} if realm in ("shared", "data") else {realm}

        for target in re.findall(r'include\("(grymod/[^"]+\.lua)"\)', text):
            found.setdefault(target, set()).update(realms)

    return found


def realm_of(path):
    """'client', 'server', 'shared' or 'data' (a converted movie) for a path under grymod/."""
    if path.startswith("grymod/flash/"):
        return "data"

    if path.startswith("grymod/client/"):
        return "client"

    if path.startswith("grymod/server/"):
        return "server"

    name = os.path.basename(path)

    if name.startswith("cl_"):
        return "client"

    if name.startswith("sv_"):
        return "server"

    return "shared"


class LoaderCoverage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(LOADER, encoding="utf-8") as f:
            text = f.read()

        cls.blocks = blocks(text)
        cls.server_send = named(cls.blocks["SERVER"], "AddCSLuaFile")
        cls.server_run = named(cls.blocks["SERVER"], "include")
        cls.client_run = named(cls.blocks["CLIENT"], "include")
        cls.files = lua_files()

    def test_the_loader_was_read(self):
        self.assertGreater(len(self.server_send), 50)
        self.assertGreater(len(self.server_run), 40)
        self.assertGreater(len(self.client_run), 50)
        self.assertGreater(len(self.files), 100)

    def test_every_path_the_loader_names_exists(self):
        missing = []

        for path in set(self.server_send + self.server_run + self.client_run):
            if not os.path.isfile(os.path.join(LUA, path)):
                missing.append(path)

        self.assertEqual([], sorted(missing), "the loader names files that do not exist (moved? misspelled?)")

    def test_every_file_is_sent_to_the_client_when_the_client_runs_it(self):
        sent = set(self.server_send)
        wrong = []

        for path in self.files:
            realm = realm_of(path)

            if realm in ("client", "shared", "data") and path not in sent:
                wrong.append(path)

        self.assertEqual([], wrong, "files the client runs but the server does not AddCSLuaFile: the client never gets them")

    def test_server_files_are_never_sent(self):
        wrong = [p for p in set(self.server_send) if realm_of(p) == "server"]

        self.assertEqual([], sorted(wrong), "server files must not be sent to the clients")

    def test_every_file_is_run_by_the_realms_that_need_it(self):
        server, client = set(self.server_run), set(self.client_run)
        wrong = []

        for target, realms in nested_includes().items():
            if "server" in realms:
                server.add(target)

            if "client" in realms:
                client.add(target)

        for path in self.files:
            realm = realm_of(path)

            if realm == "client" and (path not in client or path in server):
                wrong.append("%s: a client file must be included by the CLIENT block only" % path)
            elif realm == "server" and (path not in server or path in client):
                wrong.append("%s: a server file must be included by the SERVER block only" % path)
            elif realm == "shared" and path not in server and path not in client:
                # (a shared file may be a pure module that only one realm uses, like sh_flash_bar.lua: but somebody has to run it)
                wrong.append("%s: a shared file is included by nobody" % path)

        self.assertEqual([], sorted(wrong))


if __name__ == "__main__":
    unittest.main()
