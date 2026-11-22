"""Checks that every Lua file of the addon (and of its tests) parses, with LuaJIT (the Lua of Garry's Mod, carried by the `lupa` package).

    pip install lupa
    python tools/check_lua_syntax.py            every tracked lua/**/*.lua and tests/**/*.lua; exit 1 and `file:line: message` for each file that does not parse

It only parses: nothing is run. The one thing of Garry's Mod Lua that LuaJIT does not know and this code uses is `continue`: it is read as `do return end`
for the parse. (The other GLua operators, != && || and the C comments, are not used in this addon: a file that does would be reported.)
"""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CONTINUE = re.compile(r"(?<![\w.])continue(?![\w])")


def check_files(paths):
    """['path:line: message', ...] for the files that do not parse."""
    from lupa.luajit21 import LuaRuntime

    parse = LuaRuntime().eval("function(src, name) local _, err = loadstring(src, name) return err end")
    problems = []

    for path in paths:
        with open(path, "rb") as f:
            text = f.read().decode("utf-8", "replace").lstrip("\ufeff")

        err = parse(CONTINUE.sub("do return end", text), "@" + path)

        if err:
            problems.append(err if err.startswith(path) else f"{path}: {err}")

    return problems


def main():
    tracked = subprocess.check_output(["git", "ls-files", "lua/*.lua", "tests/*.lua"], cwd=ROOT, text=True).split("\n")
    problems = check_files([os.path.join(ROOT, p) for p in tracked if p])

    for problem in problems:
        print(f"::error::{problem}", file=sys.stderr)

    print(f"lua: {len(tracked) - 1} files, {len(problems)} that do not parse")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
