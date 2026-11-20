"""Recognise the few frame scripts of the HUD movies that follow a fixed pattern (see classify_script)."""
import re

COLOR_SCRIPT = re.compile(
    r"var color1 = new Color\(_root\.(Line|Over|Text)\.Colorset\);\s*"
    r"var color2 = new Color\(this(?:\.(\w+))?\);\s*"
    r"color2\.setRGB\(color1\.getRGB\(\)\);")

_CALL = re.compile(
    r"^(?:(?:this\.)?(?P<child>[A-Za-z_]\w*)\.)?(?P<call>stop|play|gotoAndStop|gotoAndPlay)\((?P<arg>[^()]*)\)$")
_RETURN = re.compile(r"\breturn\b")
_BACKSLASH = chr(92)


def top_level_statements(text):
    """The statements of an ActionScript text that are not inside braces, comments or strings. What comes before
    a `{` is a block header (if, else, function, loop): it is dropped together with its block."""
    statements = []
    depth = 0
    current = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c in ('"', "'"):
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == _BACKSLASH else 1
            if depth == 0:
                current.append(text[i:j + 1])  # kept whole: a ";" inside it does not end the statement
            i = j + 1
            continue
        if c == "{":
            if depth == 0:
                current = []
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                current = []
        elif depth == 0:
            if c == ";":
                statements.append("".join(current).strip())
                current = []
            else:
                current.append(c)
        i += 1
    return statements


def _target(arg):
    arg = arg.strip()
    if len(arg) >= 2 and arg[0] in ('"', "'") and arg[-1] == arg[0]:
        return {"label": arg[1:-1]}
    if re.fullmatch(r"\d+", arg):
        return {"frame": int(arg)}
    return None


def classify_script(text):
    """A colour-set script copies the theme colour (Line, Over or Text) onto a child clip; stop(), play(),
    gotoAndStop/Play(label or frame) and the same calls on a named child clip (`this.Player.gotoAndPlay("x")`)
    are kept when they are at the top level of the script. play and goto are dropped when the script can return
    early (what follows may never run); stop is kept. Everything else (calls on _root, function definitions,
    conditions) is not an action. Returns None when nothing is left."""
    actions = []
    color = COLOR_SCRIPT.search(text)
    if color:
        actions.append({"do": "color", "theme": color.group(1), "target": color.group(2)})
    can_return = _RETURN.search(text) is not None
    for statement in top_level_statements(text):
        match = _CALL.match(statement)
        if not match:
            continue
        child, call, arg = match.group("child"), match.group("call"), match.group("arg")
        if call == "stop":
            if child is None:
                actions.append({"do": "stop"})
            continue
        if can_return:
            continue
        if call == "play":
            if child is None:
                actions.append({"do": "play"})
            continue
        target = _target(arg)
        if target is None:
            continue
        playing = call == "gotoAndPlay"
        if child:
            actions.append({"do": "child", "name": child, "play": playing, **target})
        else:
            actions.append({"do": "play" if playing else "stop"})
            actions.append({"do": "goto", **target})
    return actions or None
