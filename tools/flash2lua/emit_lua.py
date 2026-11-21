"""Write a parsed movie plus its atlas rects as a Lua data file for the GryMod Flash player.

Format (`return {...}`):
  w, h, fps          stage size in pixels and frame rate
  atlases            { "<material_dir>/<atlas>.png", ... } (1-based, referenced by shape `a`)
  white              { [atlas index] = true }: shape atlases, each with an all-white twin "<atlas>_w.png" (same
                     alpha) used where a colour-set clip replaces the colour of the shapes (multiplier 0)
  fonts[char id]     {a=atlas index, em, asc, desc, g={[code]={x,y,w,h,ox,oy,adv}}}: glyph bitmaps of the font a
                     text field uses (pixels at size em; ox,oy = bitmap offset from the pen on the baseline)
  chars[id]          shape  {k="shape", a=atlas index, x,y,w,h = bitmap rect, ox,oy = offset, dw,dh = draw size}
                     sprite {k="sprite", n=frame count, labels={name=frame}, frames={ frame... }}
                     text   {k="text", ox,oy,w,h = bounds, fh = font height, t = initial text, col={r,g,b,a}, var, al, f}
                     stext  {k="stext", ox,oy,w,h}   (static text, not drawn yet)
                     morph  {k="morph", ox,oy,w,h, ex,ey,ew,eh, p, pe = start / end outline}
                     (shape and morph `p` = outline polygon {x1,y1,x2,y2,...} in stage px, only for one-contour
                      shapes: straight edges, or curves cut into pieces when the shape serves as a clip layer (mask))
  root               list of frames of the main timeline
  frame              { op, op, ..., l = "label", a = { action, ... } }
  op                 place  {d=depth, c=char, mv=true, n=name, m={a,b,c,d,tx,ty}, cx={rm,gm,bm,am,ra,ga,ba,aa},
                             r=ratio, cd=clip depth, bl=blend mode}
                     remove {rm=depth}
  action             {"play"} {"stop"} {"goto", frame} {"gotol", label} {"color", theme, target}
                     {"child", name, play, label|frame} (gotoAndPlay/Stop on the child clip with that instance name)
                     {"x"} (anything
                     else, not decoded). "color": copy the theme colour (Line, Over or Text) onto the child
                     clip named target ("" = the clip itself), the colour-set scripts of the HUD movies.
"""


def _num(value):
    if float(value) == int(value):
        return str(int(value))
    text = "%.6g" % value
    return "0" if text in ("-0", "0") else text


def _str(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\0", "\\000") + '"'


def _list(values):
    return "{" + ",".join(_num(v) for v in values) + "}"


def _op(op):
    if op["op"] == "remove":
        return "{rm=%d}" % op["depth"]
    parts = ["d=%d" % op["depth"]]
    if op["char"] is not None:
        parts.append("c=%d" % op["char"])
    if op["move"]:
        parts.append("mv=true")
    if op["name"] is not None:
        parts.append("n=" + _str(op["name"]))
    if op["matrix"] is not None:
        parts.append("m=" + _list(op["matrix"]))
    if op["cxform"] is not None:
        parts.append("cx=" + _list(op["cxform"]))
    if op["ratio"] is not None:
        parts.append("r=%d" % op["ratio"])
    if op["clip_depth"] is not None:
        parts.append("cd=%d" % op["clip_depth"])
    if op["blend"] is not None:
        parts.append("bl=%d" % op["blend"])
    return "{" + ",".join(parts) + "}"


def _action(action):
    if "unsupported" in action:
        return '{"x"}'
    if action["do"] in ("play", "stop"):
        return '{"%s"}' % action["do"]
    if action["do"] == "color":
        return '{"color",%s,%s}' % (_str(action["theme"]), _str(action["target"] or ""))
    if "label" in action:
        return '{"gotol",%s}' % _str(action["label"])
    return '{"goto",%d}' % action["frame"]


def _frame(frame):
    parts = [_op(op) for op in frame.ops]
    if frame.label:
        parts.append("l=" + _str(frame.label))
    if frame.actions:
        parts.append("a={" + ",".join(_action(a) for a in frame.actions) + "}")
    return "{" + ",".join(parts) + "}"


def _frames(timeline):
    return "{\n" + ",\n".join("\t\t" + _frame(f) for f in timeline.frames) + "\n\t}"


def _rect(bounds):
    x0, y0, x1, y1 = bounds
    return "ox=%s,oy=%s,w=%s,h=%s" % (_num(x0), _num(y0), _num(x1 - x0), _num(y1 - y0))


def _font(font, atlas_index):
    glyphs = []
    for code in sorted(font["glyphs"]):
        g = font["glyphs"][code]
        glyphs.append("[%d]={x=%d,y=%d,w=%d,h=%d,ox=%s,oy=%s,adv=%s}" % (
            code, g["x"], g["y"], g["w"], g["h"], _num(g["ox"]), _num(g["oy"]), _num(g["adv"])))
    return "{a=%d,em=%d,asc=%s,desc=%s,g={%s}}" % (
        atlas_index, font["em"], _num(font["asc"]), _num(font["desc"]), ",".join(glyphs))


def mask_characters(movie):
    """Ids of the characters that serve as clip layers: the ones placed with a clip depth, and what a clip among
    them places (the drawing code takes the first outline it finds in a clip used as a mask)."""
    timelines = [movie.root] + [c.timeline for c in movie.characters.values() if c.kind == "sprite"]
    pending = [op["char"] for timeline in timelines for frame in timeline.frames for op in frame.ops
               if op.get("clip_depth") is not None and op.get("char") is not None]
    masks = set()
    while pending:
        cid = pending.pop()
        if cid in masks:
            continue
        masks.add(cid)
        character = movie.characters.get(cid)
        if character is not None and character.kind == "sprite":
            pending.extend(op["char"] for frame in character.timeline.frames for op in frame.ops
                           if op.get("char") is not None)
    return masks


def emit_lua(movie, rects, material_dir, fonts=None):
    fonts = fonts or {}
    masks = mask_characters(movie)
    atlas_names = sorted({r["atlas"] for r in rects.values()} | {f["atlas"] for f in fonts.values()})
    atlas_index = {name: i + 1 for i, name in enumerate(atlas_names)}
    chars = []
    for cid in sorted(movie.characters):
        c = movie.characters[cid]
        if c.kind == "shape" and cid in rects:
            r = rects[cid]
            body = ('k="shape",a=%d,x=%d,y=%d,w=%d,h=%d,ox=%s,oy=%s,dw=%s,dh=%s'
                    % (atlas_index[r["atlas"]], r["x"], r["y"], r["w"], r["h"],
                       _num(r["ox"]), _num(r["oy"]), _num(r["dw"]), _num(r["dh"])))
            polygon = c.polygon or (c.mask_polygon if cid in masks else None)
            if polygon:
                body += ",p=" + _list([v for point in polygon for v in point])
        elif c.kind == "sprite":
            labels = {}
            for i, f in enumerate(c.timeline.frames):
                if f.label and f.label not in labels:
                    labels[f.label] = i + 1
            label_text = ",".join("[%s]=%d" % (_str(k), v) for k, v in sorted(labels.items()))
            body = 'k="sprite",n=%d,labels={%s},frames=%s' % (len(c.timeline.frames), label_text, _frames(c.timeline))
        elif c.kind == "text":
            body = 'k="text",%s,fh=%s,t=%s,col=%s,al=%d' % (
                _rect(c.bounds), _num(c.font_height), _str(c.initial_text), _list(c.color), c.align or 0)
            if c.variable:
                body += ",var=" + _str(c.variable)
            if c.font_id:
                body += ",f=%d" % c.font_id
        elif c.kind == "statictext":
            body = 'k="stext",' + _rect(c.bounds)
        elif c.kind == "morph":
            ex0, ey0, ex1, ey1 = c.end_bounds
            body = 'k="morph",%s,ex=%s,ey=%s,ew=%s,eh=%s' % (
                _rect(c.bounds), _num(ex0), _num(ey0), _num(ex1 - ex0), _num(ey1 - ey0))
            start, end = c.polygon, c.end_polygon
            if not (start and end) and cid in masks:
                start, end = c.mask_polygon, c.end_mask_polygon
            if start and end and len(start) == len(end):
                body += ",p=%s,pe=%s" % (_list([v for pt in start for v in pt]),
                                         _list([v for pt in end for v in pt]))
        else:
            continue
        chars.append("\t[%d]={%s}" % (cid, body))
    atlases = ",".join(_str(material_dir + "/" + n) for n in atlas_names)
    shape_atlases = sorted({atlas_index[r["atlas"]] for r in rects.values()})
    white = ",".join("[%d]=true" % i for i in shape_atlases)
    font_text = ",\n".join("\t\t[%d]=%s" % (cid, _font(f, atlas_index[f["atlas"]])) for cid, f in sorted(fonts.items()))
    return ("-- Generated by tools/flash2lua from the original Crysis Scaleform file. Do not edit.\n"
            "return {\n\tw=%d,h=%d,fps=%s,\n\tatlases={%s},\n\twhite={%s},\n\tfonts={\n%s\n\t},\n\tchars={\n%s\n\t},\n\troot=%s\n}\n"
            % (movie.width_px, movie.height_px, _num(movie.frame_rate), atlases, white, font_text,
               ",\n".join(chars), _frames(movie.root)))
