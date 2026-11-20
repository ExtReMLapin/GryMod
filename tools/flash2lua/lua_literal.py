"""Minimal reader for the Lua table literals emit_lua writes (tables, strings, numbers, booleans).
Test utility: it lets the converter tests inspect the generated Lua without a Lua runtime."""
import re

_TOKEN = re.compile(
    r"\s*(?:"
    r"(?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"
    r'|(?P<str>"(?:[^"\\]|\\.)*")'
    r"|(?P<name>[A-Za-z_]\w*)"
    r"|(?P<sym>[{}\[\]=,])"
    r")")


def parse(text):
    text = re.sub(r"--[^\n]*", "", text).strip()
    assert text.startswith("return"), "expected a `return` chunk"
    tokens = []
    pos = len("return")
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            if text[pos:].strip() == "":
                break
            raise ValueError(f"bad token at {pos}: {text[pos:pos + 30]!r}")
        pos = m.end()
        kind = m.lastgroup
        tokens.append((kind, m.group(kind)))
    value, index = _value(tokens, 0)
    assert index == len(tokens), "trailing tokens"
    return value


def _value(tokens, i):
    kind, tok = tokens[i]
    if kind == "num":
        return (float(tok) if any(c in tok for c in ".eE") else int(tok)), i + 1
    if kind == "str":
        return bytes(tok[1:-1], "utf8").decode("unicode_escape"), i + 1
    if kind == "name" and tok in ("true", "false"):
        return tok == "true", i + 1
    if (kind, tok) == ("sym", "{"):
        return _table(tokens, i + 1)
    raise ValueError(f"unexpected token {tok!r}")


def _table(tokens, i):
    """Returns (dict with int keys for the array part and keyed entries, next index)."""
    out, array_index = {}, 1
    while tokens[i] != ("sym", "}"):
        kind, tok = tokens[i]
        if kind == "name" and tokens[i + 1] == ("sym", "="):
            value, i = _value(tokens, i + 2)
            out[tok] = value
        elif (kind, tok) == ("sym", "["):
            key, i = _value(tokens, i + 1)
            assert tokens[i] == ("sym", "]") and tokens[i + 1] == ("sym", "=")
            value, i = _value(tokens, i + 2)
            out[key] = value
        else:
            value, i = _value(tokens, i)
            out[array_index] = value
            array_index += 1
        if tokens[i] == ("sym", ","):
            i += 1
    return out, i + 1
