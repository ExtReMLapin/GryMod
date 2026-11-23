"""Writes a map's data as Lua: tabs, one objective per block, the proofs and the evidence as comments above it."""


def lua_string(s):
    if not all(32 <= ord(c) < 127 for c in s):
        raise ValueError('only plain ASCII goes into the data files: %r' % s)
    return '"' + s.replace(chr(92), chr(92) * 2).replace('"', chr(92) + '"') + '"'


def lua_number(n):
    if isinstance(n, float) and n == int(n) and abs(n) < 1e15:
        return str(int(n))
    return repr(n)


def lua_value(v):
    """bool, int, float, str, tuple (a Vector), dict (a table, keys in the order given), list (an array)."""
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return lua_number(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, tuple):
        return 'Vector(%s)' % ', '.join(lua_number(a) for a in v)
    if isinstance(v, dict):
        return '{' + ', '.join('%s = %s' % (k, lua_value(x)) for k, x in v.items() if x is not None) + '}'
    if isinstance(v, list):
        return '{' + ', '.join(lua_value(x) for x in v) + '}'
    raise TypeError(v)


def comment(text):
    return '-- ' + text.replace('\n', ' ')


def emit_objective(o, indent='\t\t'):
    """o: {'fields': ordered dict, 'notes': [comment lines]}."""
    lines = [indent + comment(n) for n in o.get('notes', [])]
    f = o['fields']
    lines.append(indent + '{')
    first = ', '.join('%s = %s' % (k, lua_value(f[k])) for k in ('id', 'title', 'description', 'primary', 'secret', 'exit') if k in f and f[k] is not None)
    lines.append(indent + '\t' + first + ',')
    for k in ('pos', 'via', 'after', 'complete', 'fail'):
        if k in f and f[k] is not None:
            lines.append(indent + '\t%s = %s,' % (k, lua_value(f[k])))
    lines.append(indent + '},')
    return lines


def emit_map(header, objectives, fail_events):
    """header: comment lines. objectives: list of {'fields', 'notes'}. fail_events: list of {'fields': {entity, input}, 'note'}."""
    out = [comment(h) for h in header]
    out.append('return {')
    out.append('\tobjectives = {')
    for o in objectives:
        out.extend(emit_objective(o))
    out.append('\t},')
    out.append('\tfail_events = {')
    for f in fail_events:
        out.append('\t\t%s,%s' % (lua_value(f['fields']), ('  ' + comment(f['note'])) if f.get('note') else ''))
    out.append('\t},')
    out.append('}')

    return '\n'.join(out) + '\n'
