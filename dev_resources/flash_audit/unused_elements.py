"""Inventory of the elements of the converted Crysis HUD films that our port never reaches (static analysis, no game).

Question behind it (the owner's): "what can the images (shapes, atlas) show that our HUD never uses? if some HUD elements
are not used, maybe we did not implement everything". For every converted film (lua/grymod/flash/hud_*.lua) the tool lists

  * the NAMED CLIPS (instance names of the placements: `Tank`, `OverheatBar`, `Blink`...),
  * the FRAME LABELS of every clip (`open`, `malfunction`, `reboot`...),
  * the PUBLIC FUNCTIONS of the original ActionScript (the functions defined on the root timeline: what the game's C++ calls),
  * the SHAPES (the pictures of the atlas) that no reachable state draws,

and says which of them OUR Lua module (lua/grymod/client/cl_hud_*.lua) mentions, with file:line. For what it does not mention:

  a  played by the film's own timeline (a label reached by normal play, a clip placed on a frame that plays by itself, a
     jump a frame script of the film makes): nothing to do
  b  the original's scripts or C++ reach it through a function of the film's API (or a script of the film) that our module
     does not call, or ports without this element: a FEATURE POSSIBLY MISSING
  c  orphan: nothing in the film or in the notes about the C++ reaches it (never called in the original either)
  d  undecided (dynamic target, or evidence missing)

Facts come from the data, the ActionScript dump and the module sources; the verdicts that need a reading of the notes (what the game
does with a function, how big the work is) are in unused_verdicts.py, each with the file that says it.

Usage (from the repository root):
  python dev_resources/flash_audit/unused_elements.py --scripts-root D:/dev/crysis-hud-research/research-ui/scripts [--json] [--film hud_binoculars]

`--scripts-root` is the folder that holds `HUD_<Name>/scripts` (what FFDec writes with `-export script`). No game code is copied.
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FLASH_DIR = os.path.join(ROOT, "lua", "grymod", "flash")
CLIENT_DIR = os.path.join(ROOT, "lua", "grymod", "client")

# the converted film -> the original's folder name, and the Lua modules that drive it
FILMS = {
    "hud_ammohealthenergysuit": ("HUD_AmmoHealthEnergySuit", ["cl_hud_flash.lua"]),
    "hud_quickmenu": ("HUD_QuickMenu", ["cl_hud_quickmenu_flash.lua"]),
    "hud_radarcompassstealth": ("HUD_RadarCompassStealth", ["cl_hud_radar_flash.lua", "cl_hud_radar_units.lua"]),
    "hud_crosshair": ("HUD_Crosshair", ["cl_hud_crosshair_flash.lua"]),
    "hud_friendlycross": ("HUD_FriendlyCross", ["cl_hud_crosshair_flash.lua"]),
    "hud_binoculars": ("HUD_Binoculars", ["cl_hud_binoculars_flash.lua"]),
    "hud_grenadedetect": ("HUD_GrenadeDetect", ["cl_hud_grenade_flash.lua"]),
    "hud_initialize": ("HUD_Initialize", ["cl_hud_boot_flash.lua"]),
    "hud_reboot": ("HUD_Reboot", ["cl_hud_boot_flash.lua"]),
    "hud_lost": ("HUD_Lost", ["cl_hud_boot_flash.lua"]),
}


# ---------------------------------------------------------------------------------------------------------------------
# the data files: a Lua table literal

class T:
    """A Lua table: `arr` (positional values) and `kv` (keyed values)."""

    __slots__ = ("arr", "kv")

    def __init__(self):
        self.arr = []
        self.kv = {}

    def get(self, key, default=None):
        return self.kv.get(key, default)


_TOKEN = re.compile(
    r'\s+|--[^\n]*|(?P<str>"(?:[^"\\]|\\.)*")|(?P<num>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?P<id>[A-Za-z_]\w*)|(?P<p>[{}\[\]=,])')
_ESCAPE = re.compile(r'\\(\d{1,3}|.)', re.S)


def _unescape(text):
    def one(match):
        code = match.group(1)

        if code.isdigit():
            return chr(int(code))

        return {"n": "\n", "r": "\r", "t": "\t"}.get(code, code)

    return _ESCAPE.sub(one, text[1:-1])


def _tokens(text):
    position = 0
    length = len(text)

    while position < length:
        match = _TOKEN.match(text, position)

        if not match:
            raise ValueError("bad Lua data at %d: %r" % (position, text[position:position + 30]))

        position = match.end()

        if match.group("str") is not None:
            yield "s", _unescape(match.group("str"))
        elif match.group("num") is not None:
            number = float(match.group("num"))
            yield "n", int(number) if number == int(number) and "." not in match.group("num") and "e" not in match.group("num").lower() else number
        elif match.group("id") is not None:
            yield "i", match.group("id")
        elif match.group("p") is not None:
            yield "p", match.group("p")


def parse_lua_table(text):
    """The table of a `return {...}` data file (strings, numbers, booleans, nested tables)."""
    tokens = list(_tokens(text))
    index = 0

    # skip `return`
    if tokens[0] == ("i", "return"):
        index = 1

    def value(i):
        kind, content = tokens[i]

        if kind in ("s", "n"):
            return content, i + 1

        if kind == "i":
            return {"true": True, "false": False, "nil": None}.get(content, content), i + 1

        return table(i)

    def table(i):
        assert tokens[i] == ("p", "{"), tokens[i]
        i += 1
        result = T()

        while tokens[i] != ("p", "}"):
            if tokens[i] == ("p", "["):
                key, i = value(i + 1)
                assert tokens[i] == ("p", "]")
                assert tokens[i + 1] == ("p", "=")
                item, i = value(i + 2)
                result.kv[key] = item
            elif tokens[i][0] == "i" and tokens[i + 1] == ("p", "="):
                key = tokens[i][1]
                item, i = value(i + 2)
                result.kv[key] = item
            else:
                item, i = value(i)
                result.arr.append(item)

            if tokens[i] == ("p", ","):
                i += 1

        return result, i + 1

    parsed, _ = table(index)

    return parsed


class Film:
    """A converted film: chars (shapes, sprites, texts, morphs), the main timeline, the atlas data."""

    def __init__(self, name, data):
        self.name = name
        self.w = data.get("w")
        self.h = data.get("h")
        self.atlases = list(data.get("atlases").arr) if data.get("atlases") else []
        self.white = {int(k) for k in (data.get("white").kv if data.get("white") else {})}
        self.chars = {}
        self.fonts = {int(k) for k in (data.get("fonts").kv if data.get("fonts") else {})}

        for char_id, raw in data.get("chars").kv.items():
            self.chars[char_id] = self._char(raw)

        self.root = self._frames(data.get("root"))

    @staticmethod
    def _op(raw):
        op = dict(raw.kv)

        for key in ("m", "cx", "p", "pe"):
            if isinstance(op.get(key), T):
                op[key] = list(op[key].arr)

        return op

    def _frames(self, raw):
        frames = []

        for frame in raw.arr:
            actions = [list(a.arr) for a in frame.get("a").arr] if frame.get("a") else []
            frames.append({"ops": [self._op(o) for o in frame.arr], "l": frame.get("l"), "a": actions})

        return frames

    def _char(self, raw):
        kind = raw.get("k")
        char = {"k": kind}

        if kind == "sprite":
            char["n"] = raw.get("n")
            char["labels"] = dict(raw.get("labels").kv) if raw.get("labels") else {}
            char["frames"] = self._frames(raw.get("frames"))
        elif kind == "shape":
            for key in ("a", "x", "y", "w", "h", "dw", "dh"):
                char[key] = raw.get(key)
        elif kind == "text":
            for key in ("t", "var", "w", "h"):
                char[key] = raw.get(key)
        elif kind in ("morph", "stext"):
            for key in ("w", "h"):
                char[key] = raw.get(key)

        return char

    def data_line(self, owner, needle=None):
        """'file:line' in the data file: the line of the clip `owner`'s definition, or (with `needle`) the first line of its
        frames that holds that text."""
        start = self.char_lines.get(owner)

        if start is None:
            return None

        if needle is None:
            return "%s:%d" % (self.file, start)

        later = sorted(n for n in self.char_lines.values() if n > start)
        end = later[0] if later else len(self.lines) + 1

        for number in range(start, end):
            if needle in self.lines[number - 1]:
                return "%s:%d" % (self.file, number)

        return "%s:%d" % (self.file, start)

    def timeline(self, owner):
        """The frames of a sprite id, or of the main timeline (owner 0)."""
        if owner == 0:
            return self.root

        return self.chars[owner]["frames"]

    def timelines(self):
        """[(owner id, frames)] with 0 for the main timeline."""
        result = [(0, self.root)]

        for char_id, char in sorted(self.chars.items()):
            if char["k"] == "sprite":
                result.append((char_id, char["frames"]))

        return result

    def labels_of(self, owner):
        """{label: frame} of a timeline (the first frame with each label, 1-based)."""
        labels = {}

        for index, frame in enumerate(self.timeline(owner), 1):
            if frame["l"] and frame["l"] not in labels:
                labels[frame["l"]] = index

        if owner != 0:
            labels = dict(self.chars[owner]["labels"]) or labels

        return labels


CHAR_LINE = re.compile(r'^\t\[(\d+)\]=\{k="')


def load_film(path):
    with open(path, encoding="utf8", newline="") as handle:
        text = handle.read()

    name = os.path.splitext(os.path.basename(path))[0]
    film = Film(name, parse_lua_table(text))
    film.file = os.path.basename(path)
    film.lines = text.split(chr(10))
    film.char_lines = {}

    for number, line in enumerate(film.lines, 1):
        match = CHAR_LINE.match(line)

        if match:
            film.char_lines[int(match.group(1))] = number
        elif line.startswith(chr(9) + "root="):
            film.char_lines[0] = number

    return film


# ---------------------------------------------------------------------------------------------------------------------
# display lists and natural play

def display_lists(frames):
    """[ {depth: (char, name, cx)} ] one per frame: what the display list holds after the frame (replays the frames from 1 as
    the player does, an op that replaces a character keeps the name of the one it replaces)."""
    state = {}
    result = []

    for frame in frames:
        for op in frame["ops"]:
            depth = op.get("d")

            if op.get("rm") is not None:
                state.pop(op["rm"], None)
                continue

            entry = state.get(depth)

            if op.get("c") is not None and not (op.get("mv") and entry and entry[0] == op["c"]):
                name = op.get("n") if op.get("n") is not None else (entry[1] if entry else None)
                cx = op.get("cx") if op.get("cx") is not None else (entry[2] if entry else None)
                state[depth] = (op["c"], name, cx)
            elif entry:
                state[depth] = (entry[0], entry[1], op.get("cx") if op.get("cx") is not None else entry[2])

        result.append(dict(state))

    return result


MAX_JUMPS = 8


# ---------------------------------------------------------------------------------------------------------------------
# what our Lua modules mention

def _scan_lua(text):
    """(strings, words, concat, members): strings = [(value, line)] of the string literals outside comments; words = [(identifier, line)];
    concat = [(value, line)] of the string literals that a `..` follows (a name built from a prefix: "Crosshair" .. i),
    members = [(identifier, line)] of the identifiers that follow a dot (`labels.explosivegrenade`)."""
    strings, words, concat = [], [], []
    members = []
    calls = []
    defs = []
    i, line, length = 0, 1, len(text)

    while i < length:
        char = text[i]

        if char == "\n":
            line += 1
            i += 1
        elif text.startswith("--[[", i):
            end = text.find("]]", i + 4)
            end = length if end < 0 else end + 2
            line += text.count("\n", i, end)
            i = end
        elif text.startswith("--", i):
            end = text.find("\n", i)
            i = length if end < 0 else end
        elif char in "\"'":
            j = i + 1

            while j < length and text[j] != char and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1

            value = text[i + 1:j]
            strings.append((value, line))
            tail = text[j + 1:j + 6].lstrip()

            if tail.startswith(".."):
                concat.append((value, line))

            i = j + 1
        elif char.isalpha() or char == "_":
            j = i

            while j < length and (text[j].isalnum() or text[j] == "_"):
                j += 1

            words.append((text[i:j], line))

            if i > 0 and text[i - 1] == ".":
                members.append((text[i:j], line))

            after = text[j:j + 40].lstrip(" \t")
            line_start = text.rfind("\n", 0, i) + 1

            if after.startswith("("):
                if re.search(r"function\s+[\w.:]*$", text[line_start:i]):
                    defs.append((text[i:j], line))
                else:
                    calls.append((text[i:j], line))

            i = j
        else:
            i += 1

    return strings, words, concat, members, calls, defs


class ModuleRefs:
    """The names, labels and words the module files mention, each with its file:line list."""

    def __init__(self, paths, callers=()):
        self.names = {}  # a string literal (or a segment of a dotted one) -> ["file:line"]
        self.prefixes = {}  # a literal followed by `..` -> ["file:line"]
        self.patterns = {}  # a Lua pattern literal "^TargetIcon" -> ["file:line"]
        self.words = {}  # identifier (lower case) -> ["file:line"]
        self.members = {}  # identifier that follows a dot -> ["file:line"]
        self.lines = {}  # file -> [text of each line]
        self.callsites = {}  # identifier (lower case) -> ["file:line"] where it is called (not defined)
        self.defs = {}  # identifier (lower case) -> ["file:line"] where the module defines a function of that name

        # the files that only call the module (cl_hud_flash.lua feeds the radar panel): their call sites count, nothing else
        for path in callers:
            with open(path, encoding="utf8", newline="") as handle:
                text = handle.read()

            base = os.path.basename(path)
            self.lines[base] = text.split("\n")

            for word, line in _scan_lua(text)[4]:
                self.callsites.setdefault(word.lower(), []).append("%s:%d" % (base, line))

        for path in paths:
            with open(path, encoding="utf8", newline="") as handle:
                text = handle.read()

            base = os.path.basename(path)
            self.lines[base] = text.split("\n")
            strings, words, concat, members, calls, defs = _scan_lua(text)

            for value, line in strings:
                where = "%s:%d" % (base, line)
                pieces = [value] + (value.split(".") if "." in value else [])

                for piece in pieces:
                    if piece:
                        self.names.setdefault(piece, []).append(where)

            for value, line in strings:
                if value.startswith("^") and len(value) > 2:
                    self.patterns.setdefault(value[1:], []).append("%s:%d" % (base, line))

            for value, line in concat:
                self.prefixes.setdefault(value, []).append("%s:%d" % (base, line))

                if "." in value and value.rsplit(".", 1)[1]:
                    self.prefixes.setdefault(value.rsplit(".", 1)[1], []).append("%s:%d" % (base, line))

            for word, line in words:
                self.words.setdefault(word.lower(), []).append("%s:%d" % (base, line))

            for word, line in members:
                self.members.setdefault(word, []).append("%s:%d" % (base, line))

            for word, line in calls:
                self.callsites.setdefault(word.lower(), []).append("%s:%d" % (base, line))

            for word, line in defs:
                self.defs.setdefault(word.lower(), []).append("%s:%d" % (base, line))

    def name(self, name):
        """(where list, how): how = 'literal', 'prefix' (a built name: "Crosshair" .. i) or None."""
        if name in self.names:
            return self.names[name], "literal"

        for prefix, where in self.prefixes.items():
            if name.startswith(prefix) and re.fullmatch(r"\d*", name[len(prefix):]):
                return where, "prefix"

        for pattern, where in self.patterns.items():
            if name.startswith(pattern):
                return where, "pattern"

        return [], None

    def composed(self, name):
        """(where list, how) when `name` can be built from two string literals of the module ("low" .. "green")."""
        for i in range(2, len(name) - 1):
            left, right = name[:i], name[i:]

            if left in self.names and right in self.names:
                return self.names[left][:1] + self.names[right][:1], "composed"

        return [], None

    def line_text(self, where):
        """The source line of a 'file:line' location."""
        base, number = where.rsplit(":", 1)
        lines = self.lines.get(base, [])

        return lines[int(number) - 1].strip() if 0 < int(number) <= len(lines) else ""

    def function(self, name):
        """Where a module has something called like the film's function (setHealth -> SetHealth, or the same without the `set`)."""
        lowered = name.lower()
        candidates = [lowered]

        if lowered.startswith("set") and len(lowered) > 3:
            candidates.append(lowered[3:])

        for candidate in candidates:
            if candidate in self.words:
                return self.words[candidate]

        return []

    def function_defs(self, name):
        """Where the module defines a function called like the film's (setHealth -> HUD:SetHealth, or without the `set`)."""
        lowered = name.lower()
        found = []

        for candidate in [lowered] + ([lowered[3:]] if lowered.startswith("set") and len(lowered) > 3 else []):
            found += self.defs.get(candidate, [])

        return found

    def function_calls(self, name):
        """Where a module calls something called like the film's function (a definition is not a call)."""
        lowered = name.lower()
        candidates = [lowered] + ([lowered[3:]] if lowered.startswith("set") and len(lowered) > 3 else [])
        found = []

        for candidate in candidates:
            found += self.callsites.get(candidate, [])

        return found


# ---------------------------------------------------------------------------------------------------------------------
# the ActionScript dump

FUNCTION_HEADER = re.compile(r"([A-Za-z_][\w.]*)\s*=\s*function\s*\([^)]*\)\s*\{")
STATEMENT_PATH = re.compile(r"(?<![\w.])((?:_root|_parent|this|[A-Za-z_]\w*)(?:\.[A-Za-z_]\w*|\[[^\]\n]*\])+)(\s*\()?")
ALIAS = re.compile(r"^\s*(?:var\s+)?([A-Za-z_]\w*)\s*=\s*((?:_root|this)(?:\.[A-Za-z_]\w*|\[[^\]\n]*\])+)\s*;", re.M)
BRACKET = re.compile(r"\[[^\]\n]*\]")


def _frame_scripts(scripts_dir):
    """[(owner id, frame number, file text)] of every DoAction file (owner 0 = the main timeline)."""
    scripts = []

    if not os.path.isdir(scripts_dir):
        return scripts

    def folder_scripts(owner, folder, frame_name):
        number = int(frame_name.split("_")[1])

        for name in sorted(os.listdir(folder)):
            if name.startswith("DoAction") and name.endswith(".as"):
                with open(os.path.join(folder, name), encoding="utf8", errors="replace") as handle:
                    scripts.append((owner, number, handle.read()))

    for entry in sorted(os.listdir(scripts_dir)):
        path = os.path.join(scripts_dir, entry)

        if entry.startswith("DefineSprite_") and os.path.isdir(path):
            owner = int(entry.split("_")[1])

            for frame in sorted(os.listdir(path)):
                if frame.startswith("frame_") and os.path.isdir(os.path.join(path, frame)):
                    folder_scripts(owner, os.path.join(path, frame), frame)
        elif entry.startswith("frame_") and os.path.isdir(path):
            folder_scripts(0, path, entry)

    return scripts


def _function_spans(text):
    """[(name, start, end)] of the `name = function(...) {...}` blocks of a script (nested ones too)."""
    spans = []

    for match in FUNCTION_HEADER.finditer(text):
        depth, i = 1, match.end()

        while i < len(text) and depth:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1

            i += 1

        spans.append((match.group(1).split(".")[-1], match.start(), i))

    return spans


def _enclosing(spans, position):
    """The innermost function that holds `position`, or None."""
    best = None

    for name, start, end in spans:
        if start <= position < end and (best is None or start >= best[1]):
            best = (name, start)

    return best[0] if best else None


CONDITION_HEADER = re.compile(r"^(?:else\s+)?if\s*\((.*)\)\s*$", re.S)
ASSIGNMENT = re.compile(r"(?<![\w.])(?:_root\.|this\.|_global\.)?([A-Za-z_]\w*)\s*=(?!=)(?!\s*function)")
CALL = re.compile(r"(?<![\w.])([A-Za-z_]\w*)\s*\(")
KEYWORDS = {"if", "for", "while", "function", "switch", "return", "else", "var", "new", "typeof", "parseInt", "parseFloat",
            "Math", "String", "Number", "Color", "random", "getTimer", "fscommand", "int", "isNaN", "Array", "Object"}


def _tokens_of(path):
    """'_root.Root[curHUD].Bar' -> ['_root', 'Root', '*', 'Bar'] (a bracket stands for any child clip)."""
    return [t for t in BRACKET.sub(lambda m: ".*", path).split(".") if t]


def _block_headers(text, position):
    """The headers of the blocks that hold `position` (outermost first): the text before each opening brace, back to the
    previous statement end."""
    stack = []
    start = 0

    for i in range(position):
        char = text[i]

        if char == "{":
            stack.append(text[start:i].strip())
            start = i + 1
        elif char == "}":
            if stack:
                stack.pop()

            start = i + 1
        elif char == ";":
            start = i + 1

    return stack


def _conditions(text, position):
    """The `if (...)` / `else` conditions that guard `position` inside its script."""
    conditions = []

    for header in _block_headers(text, position):
        match = CONDITION_HEADER.match(header)

        if match:
            conditions.append(" ".join(match.group(1).split()))
        elif header.startswith("else"):
            conditions.append("else")

    return conditions


class Scripts:
    """What the film's ActionScript does, as far as the unused-element question needs: the functions it defines (the root's are
    the game's API), the jumps it makes to labels, the clips it touches (by resolved path), the call graph between functions and
    the variables the functions set, each with where it happens."""

    def __init__(self, film, scripts_dir):
        self.film = film
        self.functions = []  # {name, owner, frame}
        self.jumps = []  # {owner, frame, function, conditions, path, call, arg, targets, unresolved}
        self.touches = []  # {owner, frame, function, conditions, path, placed, rest}
        self.parents = {}
        self.names_in = {}  # owner -> {name: set(char ids)}
        self.setters = {}  # variable -> set of function names that assign it
        self._raw_calls = {}  # caller ("function name" or "frame:owner:n") -> set of called names
        self.alias = {}  # `g_pCurrent = this.Root["Crosshair" + n]` -> {"g_pCurrent": ["this", "Root", "*"]}
        self._index()
        all_scripts = _frame_scripts(scripts_dir)

        for owner, frame, text in all_scripts:
            for match in ALIAS.finditer(text):
                self.alias[match.group(1)] = _tokens_of(match.group(2))

        for owner, frame, text in all_scripts:
            spans = _function_spans(text)

            for name, start, _ in spans:
                self.functions.append({"name": name, "owner": owner, "frame": frame})

            self._statements(owner, frame, text, spans)
            self._variables(owner, frame, text, spans)

        defined = {f["name"] for f in self.functions}
        self.calls = {caller: {n for n in names if n in defined} for caller, names in self._raw_calls.items()}

    def _index(self):
        film = self.film

        for owner, frames in film.timelines():
            names = {}

            for frame in frames:
                for op in frame["ops"]:
                    if op.get("n") is not None and op.get("c") is not None:
                        names.setdefault(op["n"], set()).add(op["c"])

                    if op.get("c") is not None and film.chars.get(op["c"], {}).get("k") == "sprite":
                        self.parents.setdefault(op["c"], set()).add(owner)

            # a name given by a placement is inherited by the characters that replace it at the same depth
            for lists in display_lists(frames):
                for char, name, _ in lists.values():
                    if name is not None:
                        names.setdefault(name, set()).add(char)

            self.names_in[owner] = names

    def resolve(self, owner, tokens):
        """Follows `tokens` (names of clips) from `owner`: returns (list of (parent owner, name) placements passed, the sprite ids
        the last name stands for, the tokens that were not clips)."""
        current = {owner}
        placed = []
        i = 0

        while i < len(tokens):
            token = tokens[i]

            if token == "_root":
                current = {0}
            elif token == "this":
                pass
            elif token == "_parent":
                current = set().union(*[self.parents.get(c, set()) for c in current]) if current else set()
            elif token == "*":
                found = set()

                for c in current:
                    for chars in self.names_in.get(c, {}).values():
                        found |= {x for x in chars if self.film.chars.get(x, {}).get("k") == "sprite"}

                if not found:
                    break

                current = found
            else:
                found = set()

                for c in current:
                    found |= self.names_in.get(c, {}).get(token, set())

                if not found:
                    break

                placed.extend((c, token) for c in current if token in self.names_in.get(c, {}))
                current = {c for c in found if self.film.chars.get(c, {}).get("k") == "sprite"} or {0xFFFFFF}

            i += 1

        return placed, current, tokens[i:]

    def _statements(self, owner, frame, text, spans):
        caller_of = lambda function: function if function else "frame:%d:%d" % (owner, frame)

        for match in CALL.finditer(text):
            function = _enclosing(spans, match.start())

            if match.group(1) not in KEYWORDS:
                self._raw_calls.setdefault(caller_of(function), set()).add(match.group(1))

        for match in STATEMENT_PATH.finditer(text):
            chain = _tokens_of(match.group(1))

            if chain[0] in self.alias and len(chain) > 1:
                chain = self.alias[chain[0]] + chain[1:]

            position = match.start()
            function = _enclosing(spans, position)
            conditions = _conditions(text, position)

            if chain[-1] in ("gotoAndPlay", "gotoAndStop") and match.group(2):
                clip_tokens, call = chain[:-1], chain[-1]
                argument = re.match(r"\s*\(\s*([^)]*?)\s*\)", text[match.end() - 1:])
                argument = argument.group(1) if argument else ""
                placed, current, rest = self.resolve(owner, clip_tokens) if clip_tokens else ([], {owner}, [])

                if placed and not rest:
                    self.touches.append({"owner": owner, "frame": frame, "function": function, "conditions": conditions,
                                         "path": chain, "placed": placed, "rest": [call]})

                # a function called on a clip (`Player.setAmmo(...)`) is a call; a bare `gotoAndPlay(..)` is the clip itself
                self.jumps.append({"owner": owner, "frame": frame, "function": function, "conditions": conditions,
                                   "path": clip_tokens, "call": call, "arg": argument, "targets": sorted(current),
                                   "unresolved": rest})
            else:
                placed, current, rest = self.resolve(owner, chain)

                if placed:
                    self.touches.append({"owner": owner, "frame": frame, "function": function, "conditions": conditions,
                                         "path": chain, "placed": placed, "rest": rest})

        # a bare gotoAndPlay("x") / gotoAndStop(n) is the clip itself (the dotted pattern above misses it)
        for match in re.finditer(r"(?<![\w.])gotoAnd(Play|Stop)\(\s*([^)]*?)\s*\)", text):
            function = _enclosing(spans, match.start())
            self.jumps.append({"owner": owner, "frame": frame, "function": function, "conditions": _conditions(text, match.start()),
                               "path": [], "call": "gotoAnd" + match.group(1), "arg": match.group(2), "targets": [owner],
                               "unresolved": []})

    def _variables(self, owner, frame, text, spans):
        for match in ASSIGNMENT.finditer(text):
            function = _enclosing(spans, match.start())

            if function:
                self.setters.setdefault(match.group(1), set()).add(function)

    def api(self):
        """The public functions: those defined on the main timeline's frames."""
        names = []

        for item in self.functions:
            if item["owner"] == 0 and item["name"] not in names:
                names.append(item["name"])

        return names

    def api_reaching(self, function):
        """The API functions from which `function` can be called (itself included when it is one)."""
        api = set(self.api())
        found = set()

        if function in api:
            found.add(function)

        for name in api:
            seen, queue = {name}, [name]

            while queue:
                current = queue.pop()

                for called in self.calls.get(current, ()):
                    if called not in seen:
                        seen.add(called)
                        queue.append(called)

            if function in seen:
                found.add(name)

        return found


# ---------------------------------------------------------------------------------------------------------------------
# reachability

def natural_play_from(frames, labels, start, playing):
    """natural_play, from any frame (a jump to it, with or without play)."""
    count = len(frames)
    visited = set()

    if count == 0:
        return visited

    def run(frame, playing, jumps):
        visited.add(frame)

        for action in frames[frame - 1]["a"]:
            what = action[0] if action else None

            if what == "stop":
                playing = False
            elif what == "play":
                playing = True
            elif what in ("goto", "gotol") and jumps < MAX_JUMPS:
                target = action[1] if what == "goto" else labels.get(action[1])

                if target is not None:
                    target = min(max(int(target), 1), count)
                    frame, playing = run(target, playing, jumps + 1)

        return frame, playing

    frame, playing = run(min(max(start, 1), count), playing, 0)
    seen = set()

    while playing and count > 1 and (frame, playing) not in seen:
        seen.add((frame, playing))
        frame, playing = run(frame + 1 if frame < count else 1, True, 0)

    return visited


def label_ranges(frames_count, labels):
    """{label: (first frame, last frame)}: a label's range runs to the frame before the next label."""
    starts = sorted(set(labels.values()))
    ranges = {}

    for label, frame in labels.items():
        later = [s for s in starts if s > frame]
        ranges[label] = (frame, (later[0] - 1) if later else frames_count)

    return ranges


class Reach:
    """What the film shows by itself: the frames each clip visits when nobody drives it (natural play from frame 1 and the jumps
    of the film's own frame scripts), starting at the main timeline and following every clip placed on a frame that is visited."""

    def __init__(self, film, scripts):
        self.film = film
        self.visited = {}
        self.lists = {owner: display_lists(frames) for owner, frames in film.timelines()}
        self.labels = {owner: film.labels_of(owner) for owner, _ in film.timelines()}
        self._entered = set()
        self._enter(0, 1, True)

        # jumps of frame scripts that no condition guards: they run when the frame is entered
        changed = True

        while changed:
            changed = False

            for jump in scripts.jumps:
                if jump["function"] is not None or jump.get("conditions"):
                    continue

                if jump["frame"] not in self.visited.get(jump["owner"], ()):
                    continue

                for target in jump["targets"]:
                    where = self._frame_of(target, jump["arg"])

                    if where is None or target not in self.lists:
                        continue

                    key = (target, where, jump["call"] == "gotoAndPlay")

                    if key not in self._entered:
                        self._enter(target, where, jump["call"] == "gotoAndPlay")
                        changed = True

    def _frame_of(self, owner, argument):
        argument = argument.strip()

        if re.fullmatch(r"\d+", argument):
            return int(argument)

        if len(argument) >= 2 and argument[0] in "\"'" and argument[-1] == argument[0]:
            return self.labels.get(owner, {}).get(argument[1:-1])

        return None

    def _enter(self, owner, frame, playing):
        key = (owner, frame, playing)

        if key in self._entered:
            return

        self._entered.add(key)
        frames = self.film.timeline(owner)
        was = set(self.visited.get(owner, ()))
        got = natural_play_from(frames, self.labels[owner], frame, playing)
        self.visited[owner] = was | got

        for index in got - was:
            for char, _, _ in self.lists[owner][index - 1].values():
                if self.film.chars.get(char, {}).get("k") == "sprite" and (char, 1, True) not in self._entered:
                    self._enter(char, 1, True)


# ---------------------------------------------------------------------------------------------------------------------
# the inventory

def clip_paths(film):
    """{owner: [names from the root]}: the shortest chain of instance names that leads to a clip (BFS over every frame's
    placements). An unnamed step is written '?'."""
    paths = {0: []}
    queue = [0]
    lists = {owner: display_lists(frames) for owner, frames in film.timelines()}

    while queue:
        owner = queue.pop(0)

        for state in lists[owner]:
            for char, name, _ in state.values():
                if film.chars.get(char, {}).get("k") == "sprite" and char not in paths:
                    paths[char] = paths[owner] + [name or "?"]
                    queue.append(char)

    return paths


def _auto_names(reach, owner):
    """The instance names displayed on the frames that `owner` visits by itself."""
    names = set()

    for frame in reach.visited.get(owner, ()):
        for _, name, _ in reach.lists[owner][frame - 1].values():
            if name:
                names.add(name)

    return names


def label_hit(refs, label):
    """Where the module says this label: as a string, or as a word (`labels.explosivegrenade`)."""
    where, how = refs.name(label)

    if where:
        return where, how

    where, how = refs.composed(label)

    if where:
        return where, how

    members = refs.members.get(label, [])

    return (members, "member") if members else ([], None)


class Inventory:
    """The raw facts about one film and our module: nothing here is a verdict (see classify)."""

    def __init__(self, film_name, scripts_root, flash_dir=FLASH_DIR, client_dir=CLIENT_DIR):
        folder, modules = FILMS[film_name]
        self.name = film_name
        self.modules = modules
        self.film = load_film(os.path.join(flash_dir, film_name + ".lua"))
        self.scripts = Scripts(self.film, os.path.join(scripts_root, folder, "scripts"))
        others = [os.path.join(client_dir, f) for f in sorted(os.listdir(client_dir)) if f.endswith(".lua") and f not in modules]
        self.refs = ModuleRefs([os.path.join(client_dir, m) for m in modules], others)
        self.reach = Reach(self.film, self.scripts)
        self.paths = clip_paths(self.film)
        self.structural = set(self.paths)

    def ink(self, owner, _seen=None):
        """Whether clip `owner` draws something (a shape, a morph, a text field with text or a variable) on the frames it visits by
        itself, an entry with a zero alpha multiplier not counting."""
        cache = self.__dict__.setdefault("_ink", {})

        if owner in cache:
            return cache[owner]

        seen = _seen or set()

        if owner in seen:
            return False

        seen = seen | {owner}
        found = False

        for frame in self.reach.visited.get(owner, ()):
            for char, _, cx in self.reach.lists[owner][frame - 1].values():
                if cx is not None and cx[3] <= 0:
                    continue

                kind = self.film.chars.get(char, {}).get("k")

                if kind in ("shape", "morph"):
                    found = True
                elif kind == "text":
                    found = found or bool(self.film.chars[char].get("t") or self.film.chars[char].get("var"))
                elif kind == "sprite":
                    found = found or self.ink(char, seen)

                if found:
                    break

            if found:
                break

        cache[owner] = found

        return found

    def named_clips(self):
        """{name: {'placements': [(owner, char)], 'in_structure': bool, 'auto': bool, 'ink': bool, 'offstage': text or absent}}.
        `auto` and `ink` count only the placements on the stage; `offstage` is set when every placement is off it."""
        result = {}
        offstage = offstage_roots(self)

        for owner, names in self.scripts.names_in.items():
            for name, chars in names.items():
                entry = result.setdefault(name, {"placements": [], "in_structure": False, "auto": False, "ink": False, "off": 0})
                away = owner == 0 and name in offstage

                for char in sorted(chars):
                    entry["placements"].append((owner, char))

                    if away:
                        entry["off"] += 1
                        entry["offstage"] = offstage[name]
                        continue

                    kind = self.film.chars.get(char, {}).get("k")
                    shown = name in _auto_names(self.reach, owner)

                    if shown and ((kind == "sprite" and self.ink(char)) or kind in ("shape", "morph", "text")):
                        entry["ink"] = True

                if not away and owner in self.structural:
                    entry["in_structure"] = True

                if not away and name in _auto_names(self.reach, owner):
                    entry["auto"] = True

        for entry in result.values():
            if entry["off"] != len(entry["placements"]):
                entry.pop("offstage", None)

        return result

    def label_facts(self):
        """[{owner, label, frame, auto}] for every label of every clip."""
        facts = []

        for owner, _ in self.film.timelines():
            for label, frame in sorted(self.reach.labels[owner].items(), key=lambda item: item[1]):
                facts.append({"owner": owner, "label": label, "frame": frame,
                              "in_structure": owner in self.structural,
                              "auto": frame in self.reach.visited.get(owner, ())})

        return facts


# ---------------------------------------------------------------------------------------------------------------------
# classification

COVERED_STATUS = ("ported", "name-match")


def _literal(argument):
    argument = argument.strip()

    if len(argument) >= 2 and argument[0] in "\"'" and argument[-1] == argument[0]:
        return argument[1:-1]

    return None


def _condition_apis(inv, conditions):
    """The API functions that set a variable a condition reads (`_root.Malfunction == 1` -> destroy)."""
    apis = set()

    for condition in conditions:
        for variable in re.findall(r"[A-Za-z_]\w*", condition):
            for function in inv.scripts.setters.get(variable, ()):
                apis |= inv.scripts.api_reaching(function)

    return apis


def function_rows(inv, verdicts):
    rows = []

    for name in inv.scripts.api():
        where = inv.refs.function(name)
        verdict = verdicts.get((inv.name, "function", name))
        row = {"film": inv.name, "kind": "function", "name": name, "refs": where[:3]}

        if verdict:
            row.update(verdict)
            row.setdefault("status", "ported" if verdict.get("cls") in ("used", "a") else "missing")
        elif inv.refs.function_defs(name) and inv.refs.function_calls(name):
            row["status"] = "name-match"
            row["cls"] = "used"
            row["refs"] = inv.refs.function_defs(name)[:1] + inv.refs.function_calls(name)[:2]
        elif inv.refs.function_defs(name):
            row["status"] = "defined-not-called"
            row["cls"] = "d"
            row["refs"] = inv.refs.function_defs(name)[:1]
            row["reason"] = "the module defines a function like it and nothing calls it"
        else:
            row["status"] = "missing"
            row["cls"] = "d"

        rows.append(row)

    return rows


def covered_apis(function_rows_):
    return {r["name"] for r in function_rows_ if r.get("cls") == "used" or r.get("status") in COVERED_STATUS}


def _jump_reaches(jump, owner, label, start, end):
    """Whether a gotoAnd* statement of the film lands in the range of `label` (start..end) of clip `owner`: by its name, or by a
    frame number inside the range (the targets must then be known)."""
    if _literal(jump["arg"]) == label:
        return owner in jump["targets"] or not jump["targets"]

    if re.fullmatch(r"\d+", jump["arg"].strip()) and owner in jump["targets"]:
        return start <= int(jump["arg"]) <= end

    return False


def played_on(inv):
    """{owner: {frame: label}}: the frames a clip plays on through after our module sends it to a label with GotoAndPlay (the
    film's own actions decide where it stops)."""
    result = {}

    for owner, _ in inv.film.timelines():
        labels = inv.reach.labels[owner]

        for label, frame in labels.items():
            where, how = label_hit(inv.refs, label)

            if not any("GotoAndPlay" in inv.refs.line_text(w) or "Play(" in inv.refs.line_text(w) for w in where):
                continue

            for reached in natural_play_from(inv.film.timeline(owner), labels, frame, True):
                result.setdefault(owner, {}).setdefault(reached, label)

    return result


def label_rows(inv, verdicts, covered):
    rows = []
    scripts = inv.scripts
    plays_on = played_on(inv)

    for fact in inv.label_facts():
        owner, label = fact["owner"], fact["label"]
        where, how = label_hit(inv.refs, label)
        row = {"film": inv.name, "kind": "label", "name": label, "owner": owner, "frame": fact["frame"],
               "path": ".".join(inv.paths.get(owner, ["?"])) or "(root)", "refs": where[:3], "how": how,
               "data": inv.film.data_line(owner, "l=" + chr(34) + label + chr(34))}
        start, end = label_ranges(len(inv.film.timeline(owner)), inv.reach.labels[owner])[label]
        jumps = [j for j in scripts.jumps if _jump_reaches(j, owner, label, start, end)]
        row["jumps"] = [{"owner": j["owner"], "frame": j["frame"], "function": j["function"], "conditions": j["conditions"]}
                        for j in jumps]

        if where:
            row["cls"] = "used"
        elif not fact["in_structure"]:
            row["cls"] = "c"
            row["reason"] = "clip never placed under the root"
        elif fact["auto"]:
            row["cls"] = "a"
            row["reason"] = "played by the film's own timeline"
        elif fact["frame"] in plays_on.get(owner, {}):
            row["cls"] = "a"
            row["reason"] = "played on from the label %s, which our module plays" % plays_on[owner][fact["frame"]]
        else:
            apis, internal = set(), False

            for j in jumps:
                if j["function"]:
                    reaching = scripts.api_reaching(j["function"])
                    apis |= reaching
                    internal = internal or not reaching
                elif j["conditions"]:
                    apis |= _condition_apis(inv, j["conditions"])
                else:
                    internal = True

            row["apis"] = sorted(apis)

            if apis and apis <= covered:
                row["cls"] = "d"
                row["reason"] = "reached by %s, which our module ports without naming this label" % ", ".join(sorted(apis))
            elif apis:
                row["cls"] = "b"
                row["reason"] = "reached by " + ", ".join(sorted(apis - covered)) + " (not ported)" + (
                    "; also " + ", ".join(sorted(apis & covered)) + " (ported)" if apis & covered else "")
            elif internal:
                row["cls"] = "a"
                row["reason"] = "jump made by a script of the film itself"
            elif jumps:
                row["cls"] = "d"
                row["reason"] = "jumped to by a script whose caller is not known"
            else:
                row["cls"] = "c"
                row["reason"] = "no script of the film reaches it"

        verdict = verdicts.get((inv.name, "label", "%s@%d" % (label, owner))) or verdicts.get((inv.name, "label", label))

        if verdict:
            row.update(verdict)

        rows.append(row)

    return rows


def clip_rows(inv, verdicts, covered, hidden):
    rows = []
    scripts = inv.scripts
    reach = inv.reach

    for name, info in sorted(inv.named_clips().items()):
        where, how = inv.refs.name(name)

        if not where:
            where, how = inv.refs.composed(name)

        kinds = sorted({inv.film.chars[c]["k"] for _, c in info["placements"] if c in inv.film.chars})
        example = None

        for owner, char in info["placements"]:
            if owner in inv.paths:
                example = ".".join(inv.paths[owner] + [name]) if inv.paths[owner] or True else name
                break

        hides = []

        for o, _ in info["placements"]:
            chain = inv.paths.get(o, []) + [name] if o in inv.paths else []
            # a clip is hidden when it, or a clip above it, is
            found = [hidden[".".join(chain[:i])] for i in range(1, len(chain) + 1) if ".".join(chain[:i]) in hidden]

            if found:
                hides.append(found[0])

        row = {"film": inv.name, "kind": "clip", "name": name, "chars": sorted({c for _, c in info["placements"]}),
               "placements": len(info["placements"]), "types": kinds, "path": example, "refs": where[:3], "how": how,
               "hidden_by_module": hides[0] if hides and len(hides) == len(info["placements"]) else None,
               "data": inv.film.data_line(info["placements"][0][0], "n=" + chr(34) + name + chr(34)) if info["placements"] else None}
        touches = [t for t in scripts.touches if any(p == (o, name) for o, _ in info["placements"] for p in t["placed"]
                                                       if p[1] == name)]
        # a touch counts for this name when the last placed step is this name
        touches = [t for t in scripts.touches if t["placed"] and t["placed"][-1][1] == name]
        apis, frame_scripts = set(), []

        for t in touches:
            rest = ".".join(t["rest"])

            if t["function"]:
                apis |= scripts.api_reaching(t["function"])
            elif t["conditions"]:
                apis |= _condition_apis(inv, t["conditions"])
            else:
                frame_scripts.append((t["owner"], t["frame"], rest))

        row["apis"] = sorted(apis)

        if info.get("offstage"):
            row["cls"] = "a" if not where else "used"
            row["reason"] = "off the stage: " + info["offstage"]
        elif where and not row["hidden_by_module"]:
            row["cls"] = "used"
        elif row["hidden_by_module"]:
            row["cls"] = "b"
            row["reason"] = "hidden: %s" % row["hidden_by_module"]
        elif not info["in_structure"]:
            row["cls"] = "c"
            row["reason"] = "placed only in clips that are never placed under the root"
        elif apis - covered:
            row["cls"] = "b"
            row["reason"] = "touched by " + ", ".join(sorted(apis - covered)) + " (not ported)"
        elif info["auto"] and info["ink"]:
            row["cls"] = "a"
            row["reason"] = "drawn on frames the film plays by itself"
        elif apis:
            row["cls"] = "a"
            row["reason"] = "touched by ported function(s) " + ", ".join(sorted(apis))
        elif frame_scripts:
            row["cls"] = "d"
            row["reason"] = "touched only by frame scripts of frames the film does not play by itself"
        elif info["auto"]:
            row["cls"] = "c"
            row["reason"] = "placed on a frame played by itself but draws nothing there (empty or alpha 0), no script touches it"
        else:
            row["cls"] = "c"
            row["reason"] = "not placed on a frame played by itself, no script touches it"

        verdict = verdicts.get((inv.name, "clip", name))

        if verdict:
            row.update(verdict)

        rows.append(row)

    return rows


# ---------------------------------------------------------------------------------------------------------------------
# shapes and the atlas

def reachable_frames(inv, covered, hidden, reached_labels=None):
    """{owner: set(frames)}: the frames our port can show. The film's own play (natural play from frame 1 and the jumps of its
    frame scripts); the frames of every label our module names (and what plays on from them); the labels an API function our
    module ports jumps to; and, for a clip our module drives by name (a bar it moves frame by frame), every frame that is not
    inside the range of a label nobody names or plays. `hidden` = names our module only hides."""
    film, scripts, reach, refs = inv.film, inv.scripts, inv.reach, inv.refs
    api_labels = {}

    for jump in scripts.jumps:
        label = _literal(jump["arg"])

        if label is None or not jump["function"]:
            continue

        if scripts.api_reaching(jump["function"]) & covered:
            for target in jump["targets"]:
                api_labels.setdefault(target, set()).add(label)

    named_by_char = {}

    for owner, names in scripts.names_in.items():
        for name, chars in names.items():
            for char in chars:
                named_by_char.setdefault(char, set()).add(name)

    result = {}

    for owner, frames_list in film.timelines():
        labels = reach.labels[owner]
        count = len(frames_list)
        frames = set(reach.visited.get(owner, ()))
        named = {l for l in labels if label_hit(refs, l)[0] or l in api_labels.get(owner, ())}

        if reached_labels is not None:
            named |= reached_labels.get(owner, set())

        for label in named:
            frames |= natural_play_from(frames_list, labels, labels[label], True)

        names = named_by_char.get(owner, set())
        driven = owner == 0 or any(inv.refs.name(n)[0] and ".".join(inv.paths.get(owner, []) + [n]) not in hidden for n in names)

        if driven:
            ranges = label_ranges(count, labels)
            ok = set(named) | {l for l, f in labels.items() if f in reach.visited.get(owner, ())}

            for frame in range(1, count + 1):
                holders = [l for l, (a, b) in ranges.items() if a <= frame <= b]

                if not holders or any(l in ok for l in holders):
                    frames.add(frame)

        result[owner] = frames

    return result


def live_shapes(inv, frames, hidden):
    """The shapes some reachable state draws: (live set, why-not info for the dead ones).
    Walks from the main timeline; a clip named in `hidden` is not entered."""
    film = inv.film
    live = set()
    seen_owner = set()
    queue = [0]

    while queue:
        owner = queue.pop()

        if owner in seen_owner:
            continue

        seen_owner.add(owner)
        # a clip put on the display list starts on its frame 1 and plays by itself
        own = frames.get(owner, set()) | natural_play_from(film.timeline(owner), inv.reach.labels[owner], 1, True)

        for frame in own:
            for char, name, _ in inv.reach.lists[owner][frame - 1].values():
                kind = film.chars.get(char, {}).get("k")

                if kind == "sprite" and ".".join(inv.paths.get(owner, []) + [name or "#%d" % char]) in hidden:
                    continue

                if kind == "shape":
                    live.add(char)
                elif kind == "sprite":
                    queue.append(char)

    return live


def placed_anywhere(inv):
    """The shape ids that some display list holds (a library shape nobody places is dead whatever is driven)."""
    placed = set()

    for owner, states in inv.reach.lists.items():
        if owner not in inv.structural:
            continue

        for state in states:
            for char, _, _ in state.values():
                if inv.film.chars.get(char, {}).get("k") == "shape":
                    placed.add(char)

    return placed


def twin_needs(inv):
    """(white, colour): the shape ids that can be drawn in white mode (some clip above multiplies the colour by 0, or a colour-set
    action recolours a child of that name) and those drawn with their own colours. Conservative: every frame of every clip."""
    film = inv.film
    colored = {}

    for owner, frames in film.timelines():
        names = set()

        for frame in frames:
            for action in frame["a"]:
                if action and action[0] == "color" and action[2]:
                    names.add(action[2])

        colored[owner] = names

    white, colour = set(), set()
    memo = set()

    def visit(owner, in_white):
        if (owner, in_white) in memo:
            return

        memo.add((owner, in_white))

        for state in inv.reach.lists[owner]:
            for char, name, cx in state.values():
                is_white = in_white or (cx is not None and cx[0] + cx[1] + cx[2] < 0.001) or (name in colored[owner])
                kind = film.chars.get(char, {}).get("k")

                if kind == "shape":
                    (white if is_white else colour).add(char)
                elif kind == "sprite":
                    visit(char, is_white)

    visit(0, False)

    return white, colour


def atlas_bytes(film_name, materials_dir=None):
    """The size on disk of the film's colour sheets and white twins (the VTF files)."""
    materials_dir = materials_dir or os.path.join(ROOT, "materials", "grymod", "flash")
    colour, twin = 0, 0

    for entry in os.listdir(materials_dir) if os.path.isdir(materials_dir) else []:
        if entry.startswith(film_name + "_") and entry.endswith(".vtf"):
            size = os.path.getsize(os.path.join(materials_dir, entry))

            if entry.endswith("_w.vtf"):
                twin += size
            else:
                colour += size

    return colour, twin


def shape_report(inv, covered, hidden, reached_labels=None):
    film = inv.film
    shapes = {i: c for i, c in film.chars.items() if c["k"] == "shape"}
    frames = reachable_frames(inv, covered, hidden, reached_labels)
    live = live_shapes(inv, frames, hidden)
    placed = placed_anywhere(inv)
    white, colour = twin_needs(inv)
    pixels = lambda ids: sum(shapes[i]["w"] * shapes[i]["h"] for i in ids)
    all_ids = set(shapes)
    dead = all_ids - live
    never_placed = all_ids - placed
    sheet_colour, sheet_twin = atlas_bytes(inv.name)
    # the twin sheets hold the same layout as the colour sheets: only the shapes of the atlases that have a twin
    twinned = {i for i, c in shapes.items() if c["a"] in film.white}
    live_white = (white & live) & twinned

    return {
        "film": inv.name,
        "shapes": len(shapes),
        "pixels": pixels(all_ids),
        "dead": sorted(dead),
        "dead_never_placed": sorted(never_placed),
        "dead_pixels": pixels(dead),
        "dead_by_hidden": sorted(dead - never_placed),
        "white_needed": len(live_white),
        "white_pixels_needed": pixels(live_white),
        "twinned_pixels": pixels(twinned),
        "twinned_pixels_live": pixels(twinned & live),
        "sheet_bytes": sheet_colour,
        "twin_bytes": sheet_twin,
        # DXT5 is one byte a pixel, and the mip levels add a third: what the dead shapes take in the colour sheets and in the twins,
        # and what a twin holding only the white-mode shapes would save on top (the live shapes that never draw in white mode)
        "dead_bytes": int(pixels(dead) * 4 / 3) * (2 if film.white else 1),
        "twin_by_use_bytes": int((pixels(twinned & live) - pixels(live_white)) * 4 / 3) if film.white else 0,
        "dead_details": [{"id": i, "px": shapes[i]["w"] * shapes[i]["h"], "draw": [shapes[i]["dw"], shapes[i]["dh"]],
                          "reason": "never placed" if i in never_placed else "only in states our port cannot reach"}
                         for i in sorted(dead)],
    }


# ---------------------------------------------------------------------------------------------------------------------
# the report

def load_verdicts():
    """(VERDICTS, HIDDEN) of unused_verdicts.py, or empty ones."""
    sys.path.insert(0, HERE)

    try:
        import unused_verdicts
    except ImportError:
        return {}, {}
    finally:
        sys.path.pop(0)

    return unused_verdicts.VERDICTS, unused_verdicts.HIDDEN


def dangling_actions(film):
    """[(owner, frame, action)]: `gotol` actions whose label does not exist in their own clip. The converter writes a call on another clip
    (`this._parent.gotoAndPlay("close")`, `this.Blink.gotoAndPlay("play")`) as a jump of the clip itself (emit_lua._action); with no such
    label the player ignores it, with one it would jump wrongly."""
    found = []

    for owner, frames in film.timelines():
        labels = film.labels_of(owner)

        for index, frame in enumerate(frames, 1):
            for action in frame["a"]:
                if action and action[0] == "gotol" and action[1] not in labels:
                    found.append({"owner": owner, "frame": index, "label": action[1], "data": film.data_line(owner)})

    return found


def analyse(film_name, scripts_root, verdicts=None, hidden_all=None, flash_dir=FLASH_DIR, client_dir=CLIENT_DIR):
    """The report of one film (a JSON-serialisable dict): rows of clips, labels and functions, counts by class, shapes."""
    if verdicts is None or hidden_all is None:
        loaded_verdicts, loaded_hidden = load_verdicts()
        verdicts = loaded_verdicts if verdicts is None else verdicts
        hidden_all = loaded_hidden if hidden_all is None else hidden_all

    inv = Inventory(film_name, scripts_root, flash_dir, client_dir)
    hidden = dict(hidden_all.get(film_name, {}))

    for name, evidence in offstage_roots(inv).items():
        hidden.setdefault(name, "off the stage in the film itself: " + evidence)

    functions = function_rows(inv, verdicts)
    covered = covered_apis(functions)
    labels = label_rows(inv, verdicts, covered)
    clips = clip_rows(inv, verdicts, covered, hidden)
    reached = {}

    for row in labels:
        # a label our port reaches (named, or ported by number), one the film plays by itself, or one nobody could judge
        if row["cls"] in ("used", "a", "d"):
            reached.setdefault(row["owner"], set()).add(row["name"])

    shapes = shape_report(inv, covered, hidden, reached)

    def counts(rows):
        result = {"total": len(rows), "used": 0, "a": 0, "b": 0, "c": 0, "d": 0}

        for row in rows:
            result["used" if row["cls"] == "used" else row["cls"]] += 1

        return result

    return {
        "film": film_name,
        "modules": inv.modules,
        "counts": {"clips": counts(clips), "labels": counts(labels), "functions": counts(functions)},
        "clips": clips,
        "labels": labels,
        "functions": functions,
        "shapes": shapes,
        "dangling_actions": dangling_actions(inv.film),
    }


PRIORITY_ORDER = {"high": 0, "medium": 1, "low": 2, "none": 3, None: 4}


def missing_features(reports):
    """The class b rows of every film, one entry per feature: a function when the film has one (its labels and clips that carry the same
    `what` are folded into it), else the label or clip. Ordered by what a player would see (priority), then by effort."""
    entries = {}

    for report in reports:
        for kind in ("functions", "labels", "clips"):
            for row in report[kind]:
                if row["cls"] != "b":
                    continue

                what = row.get("feature") or row.get("what") or row["name"]
                key = (report["film"], what)
                entry = entries.setdefault(key, {"film": report["film"], "what": what, "names": [],
                                                 "game": row.get("game"), "source": row.get("source"), "effort": row.get("effort"),
                                                 "priority": row.get("priority"), "missed": row.get("missed")})
                name = "%s %s" % (kind[:-1] if kind != "labels" else "label", row["name"])

                if name not in entry["names"]:
                    entry["names"].append(name)

                # a feature is as visible as its most visible part, and as big as the first part says
                if PRIORITY_ORDER.get(row.get("priority"), 4) < PRIORITY_ORDER.get(entry["priority"], 4):
                    entry["priority"], entry["effort"] = row.get("priority"), row.get("effort")

    return sorted(entries.values(), key=lambda e: (PRIORITY_ORDER.get(e["priority"], 4), (e["effort"] or "Z")[:1], e["film"], e["what"]))


def format_report(reports):
    lines = []
    lines.append("%-26s %-27s %-27s %-27s %s" % ("film", "clips: all used/a/b/c/d", "labels", "functions", "dead shapes"))

    def cell(c):
        return "%3d: %3d %2d/%2d/%2d/%2d" % (c["total"], c["used"], c["a"], c["b"], c["c"], c["d"])

    for r in reports:
        c = r["counts"]
        s = r["shapes"]
        lines.append("%-26s %s | %s | %s | %d of %d (%d px)" % (
            r["film"], cell(c["clips"]), cell(c["labels"]), cell(c["functions"]), len(s["dead"]), s["shapes"], s["dead_pixels"]))

    lines.append("")
    lines.append("Possibly missing features (class b), by what a player would see:")

    for entry in missing_features(reports):
        lines.append("  %-6s %-14s %-24s %s" % (entry["priority"] or "?", entry["effort"] or "?", entry["film"], entry["what"]))
        lines.append("         %s%s" % (", ".join(entry["names"][:6]) + (" ..." if len(entry["names"]) > 6 else ""),
                                        ("  [" + entry["missed"] + "]") if entry["missed"] else ""))

    lines.append("")

    for r in reports:
        lines.append("== %s (module: %s)" % (r["film"], ", ".join(r["modules"])))
        lines.append("  functions:")

        for row in r["functions"]:
            lines.append("    %-4s %-22s %s" % (row["cls"], row["name"], row.get("what") or ", ".join(row["refs"][:2]) or row.get("reason", "")))

        lines.append("  labels not named by the module (grouped by name and class):")
        grouped = {}

        for row in r["labels"]:
            if row["cls"] != "used":
                grouped.setdefault((row["cls"], row["name"], row.get("what") or row.get("reason") or ""), []).append(row["owner"])

        for (cls, name, reason), owners in sorted(grouped.items(), key=lambda item: (item[0][0], item[0][1])):
            lines.append("    %-4s %-18s in %-3d clip(s) %s" % (cls, name, len(owners), reason))

        lines.append("  named clips not used by the module:")

        for row in r["clips"]:
            if row["cls"] != "used":
                lines.append("    %-4s %-22s x%-2d %s" % (row["cls"], row["name"], row["placements"], row.get("what") or row.get("reason") or ""))

        s = r["shapes"]
        lines.append("  shapes: %d, dead %d (%d of %d px); the white twin needs %d px of %d" % (
            s["shapes"], len(s["dead"]), s["dead_pixels"], s["pixels"], s["white_pixels_needed"], s["twinned_pixels"]))

        if r["dangling_actions"]:
            lines.append("  converter: %d frame action(s) jump to a label their own clip does not have (a call on another clip written as a jump)" %
                         len(r["dangling_actions"]))

        lines.append("")

    dead = sum(r["shapes"]["dead_bytes"] for r in reports)
    twin = sum(r["shapes"]["twin_by_use_bytes"] for r in reports)
    sheets = sum(r["shapes"]["sheet_bytes"] + r["shapes"]["twin_bytes"] for r in reports)
    lines.append("Atlas: %.1f MB of sheets and twins in the VTF files; dead shapes %.1f MB (colour sheet and twin); a twin holding only the "
                 "white-mode shapes %.1f MB more (shape pixels x 4/3 for the mip levels, one byte a pixel; repacking rounds up)" % (
                     sheets / 1e6, dead / 1e6, twin / 1e6))

    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scripts-root", required=True, help="folder with HUD_<Name>/scripts (FFDec -export script)")
    parser.add_argument("--film", action="append", help="a film to analyse (default: all of them)")
    parser.add_argument("--json", action="store_true", help="the whole report as JSON")
    args = parser.parse_args(argv)
    names = args.film or list(FILMS)
    reports = [analyse(name, args.scripts_root) for name in names]

    if args.json:
        print(json.dumps(reports, indent=1, default=sorted))
    else:
        print(format_report(reports))

    return 0



# ---------------------------------------------------------------------------------------------------------------------
# what the film places off the stage

def _transform(matrix, box):
    """The bounding box of `box` = (x0, y0, x1, y1) under the placement matrix [a, b, c, d, tx, ty]."""
    a, b, c, d, tx, ty = matrix
    xs, ys = [], []

    for x, y in ((box[0], box[1]), (box[2], box[1]), (box[2], box[3]), (box[0], box[3])):
        xs.append(a * x + c * y + tx)
        ys.append(b * x + d * y + ty)

    return (min(xs), min(ys), max(xs), max(ys))


def _union(first, second):
    if first is None:
        return second

    if second is None:
        return first

    return (min(first[0], second[0]), min(first[1], second[1]), max(first[2], second[2]), max(first[3], second[3]))


def extent(film, owner, _seen=None):
    """The bounding box of everything clip `owner` can draw on any frame (placement matrices applied, rotation by its box), or
    None when it draws nothing."""
    cache = film.__dict__.setdefault("_extent", {})

    if owner in cache:
        return cache[owner]

    seen = (_seen or set()) | {owner}
    box = None

    for frame in film.timeline(owner):
        for op in frame["ops"]:
            char = film.chars.get(op.get("c"))

            if char is None:
                continue

            matrix = op.get("m") or [1, 0, 0, 1, 0, 0]

            if char["k"] == "shape":
                inner = (0, 0, char["dw"], char["dh"])
            elif char["k"] == "text":
                inner = (0, 0, char.get("w") or 0, char.get("h") or 0)
            elif char["k"] == "sprite" and op["c"] not in seen:
                inner = extent(film, op["c"], seen)
            else:
                inner = None

            if inner is not None:
                box = _union(box, _transform(matrix, inner))

    cache[owner] = box

    return box


def offstage_roots(inv):
    """{'Name': 'file:line'}: the clips and fields the main timeline places entirely outside the stage (the colour holders `Line`,
    `Over`, `Text`, the text fields that hold the movie's strings): the original never shows them either."""
    film = inv.film
    found = {}

    for frame in film.root:
        for op in frame["ops"]:
            char = film.chars.get(op.get("c"))

            if char is None or op.get("m") is None:
                continue

            if char["k"] == "sprite":
                inner = extent(film, op["c"])
            elif char["k"] == "text":
                inner = (0, 0, char.get("w") or 0, char.get("h") or 0)
            else:
                inner = None

            if inner is None:
                continue

            x0, y0, x1, y1 = _transform(op["m"], inner)

            if x1 <= 0 or y1 <= 0 or x0 >= film.w or y0 >= film.h:
                key = op.get("n") or "#%d" % op["c"]
                found[key] = "%s (placed at x %.0f..%.0f, y %.0f..%.0f of a %dx%d stage)" % (
                    film.data_line(0, "c=%d" % op["c"]), x0, x1, y0, y1, film.w, film.h)

    return found


if __name__ == "__main__":
    sys.exit(main())
