"""Parse FFDec's `-swf2xml` output of a Flash (SWF) HUD file into a small timeline model.

Only what the GryMod HUD player needs is kept: character dictionary (shapes, sprites, texts,
bitmaps, morph shapes, fonts) and the sprite timelines (display-list operations per frame,
frame labels, the few frame actions the HUD uses). Lengths are converted from twips to pixels.
"""
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from html import unescape
from dataclasses import dataclass, field
from typing import Optional

from tools.flash2lua import scripts

TWIPS = 20.0
PLACE_TAGS = ("PlaceObject2Tag", "PlaceObject3Tag")
SHAPE_TAGS = ("DefineShapeTag", "DefineShape2Tag", "DefineShape3Tag", "DefineShape4Tag")
BITMAP_TAGS = ("DefineBitsLossless2Tag", "DefineBitsLosslessTag", "DefineBitsJPEG2Tag",
               "DefineBitsJPEG3Tag", "DefineBitsTag")


@dataclass
class Frame:
    label: Optional[str] = None
    ops: list = field(default_factory=list)
    actions: list = field(default_factory=list)


@dataclass
class Timeline:
    frames: list = field(default_factory=list)


@dataclass
class Character:
    id: int
    kind: str  # shape | sprite | text | statictext | bitmap | morph | font
    bounds: Optional[tuple] = None
    timeline: Optional[Timeline] = None
    # edit text
    font_height: Optional[float] = None
    initial_text: Optional[str] = None
    color: Optional[tuple] = None
    variable: Optional[str] = None
    align: Optional[int] = None
    font_id: Optional[int] = None
    # simple shapes: the outline as a pixel polygon (one contour, straight edges), else None
    polygon: Optional[list] = None
    # morph shapes
    end_bounds: Optional[tuple] = None
    end_polygon: Optional[list] = None
    # fonts
    name: Optional[str] = None


@dataclass
class Movie:
    width_px: int = 0
    height_px: int = 0
    frame_rate: float = 0.0
    root: Timeline = field(default_factory=Timeline)
    characters: dict = field(default_factory=dict)
    exports: dict = field(default_factory=dict)
    imports: dict = field(default_factory=dict)  # character id -> (swf url, exported name)


def swf_to_xml(ffdec, swf_path, xml_path):
    """Run FFDec's CLI to dump a SWF/GFX file as XML."""
    subprocess.run([ffdec, "-swf2xml", swf_path, xml_path], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def export_scripts(ffdec, swf_path, out_dir):
    """Export the ActionScript source of every frame script (FFDec), used to recognise the colour scripts."""
    subprocess.run([ffdec, "-export", "script", out_dir, swf_path], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


classify_script = scripts.classify_script  # see scripts.py


def _script_file(scripts_dir, sprite_id, frame_number, index):
    folder = os.path.join(scripts_dir, "scripts") if os.path.isdir(os.path.join(scripts_dir, "scripts")) else scripts_dir
    if sprite_id is not None:
        folder = os.path.join(folder, f"DefineSprite_{sprite_id}")
    name = "DoAction.as" if index == 1 else f"DoAction_{index}.as"
    return os.path.join(folder, f"frame_{frame_number}", name)


def _f(elem, name, default=0.0):
    value = elem.get(name)
    return float(value) if value is not None else default


def _rect(elem):
    """RECT element -> (xmin, ymin, xmax, ymax) in pixels."""
    if elem is None:
        return None
    return (_f(elem, "Xmin") / TWIPS, _f(elem, "Ymin") / TWIPS,
            _f(elem, "Xmax") / TWIPS, _f(elem, "Ymax") / TWIPS)


def _matrix(elem):
    """MATRIX element -> (a, b, c, d, tx, ty) with the translation in pixels.
    x' = a*x + c*y + tx ; y' = b*x + d*y + ty."""
    if elem is None:
        return None
    a = _f(elem, "scaleX", 1.0) if elem.get("hasScale") == "true" else 1.0
    d = _f(elem, "scaleY", 1.0) if elem.get("hasScale") == "true" else 1.0
    b = _f(elem, "rotateSkew0", 0.0) if elem.get("hasRotate") == "true" else 0.0
    c = _f(elem, "rotateSkew1", 0.0) if elem.get("hasRotate") == "true" else 0.0
    return (a, b, c, d, _f(elem, "translateX") / TWIPS, _f(elem, "translateY") / TWIPS)


def _cxform(elem):
    """CXFORM(WITHALPHA) -> (rm, gm, bm, am, ra, ga, ba, aa): multipliers as fractions, adds as 0..255."""
    if elem is None:
        return None
    if elem.get("hasMultTerms") == "true":
        mult = [_f(elem, n + "MultTerm", 256.0) / 256.0 for n in ("red", "green", "blue", "alpha")]
    else:
        mult = [1.0, 1.0, 1.0, 1.0]
    if elem.get("hasAddTerms") == "true":
        add = [_f(elem, n + "AddTerm", 0.0) for n in ("red", "green", "blue", "alpha")]
    else:
        add = [0.0, 0.0, 0.0, 0.0]
    return tuple(mult + add)


def decode_actions(hexstr):
    """Decode the few AVM1 actions the HUD timelines use. Anything else is returned as
    {"unsupported": <hex of the whole action block>} (the root scripts are ported by hand)."""
    data = bytes.fromhex(hexstr)
    out, i = [], 0
    while i < len(data):
        code = data[i]
        i += 1
        if code == 0:
            break
        payload = b""
        if code >= 0x80:
            length = int.from_bytes(data[i:i + 2], "little")
            payload = data[i + 2:i + 2 + length]
            i += 2 + length
        if code == 0x06:
            out.append({"do": "play"})
        elif code == 0x07:
            out.append({"do": "stop"})
        elif code == 0x81 and len(payload) == 2:
            out.append({"do": "goto", "frame": int.from_bytes(payload, "little") + 1})
        elif code == 0x8C:
            out.append({"do": "goto", "label": payload.split(b"\0")[0].decode("latin-1")})
        else:
            return [{"unsupported": hexstr}]
    return out


def _polygon(records_parent):
    """The outline of a one-contour shape made of straight edges as [(x, y)] in pixels (not closed
    twice), or None for anything else (curves, several contours, an open path)."""
    if records_parent is None:
        return None
    records = records_parent.find("shapeRecords")
    if records is None:
        return None
    x = y = 0
    points = []
    moves = 0
    for rec in records:
        kind = rec.get("type")
        if kind == "StyleChangeRecord":
            if rec.get("stateMoveTo") == "true":
                moves += 1
                if moves > 1:
                    return None
                x, y = int(rec.get("moveDeltaX")), int(rec.get("moveDeltaY"))
                points.append((x, y))
        elif kind == "StraightEdgeRecord":
            x += int(rec.get("deltaX", 0))
            y += int(rec.get("deltaY", 0))
            points.append((x, y))
        elif kind == "CurvedEdgeRecord":
            return None
    if len(points) < 4 or points[0] != points[-1]:
        return None
    return [(px / TWIPS, py / TWIPS) for px, py in points[:-1]]


def _place_op(item):
    has_char = item.get("placeFlagHasCharacter") == "true"
    blend = item.get("blendMode") if item.get("placeFlagHasBlendMode") == "true" else None
    return {
        "op": "place",
        "depth": int(item.get("depth")),
        "char": int(item.get("characterId")) if has_char else None,
        "move": item.get("placeFlagMove") == "true",
        "name": item.get("name") if item.get("placeFlagHasName") == "true" else None,
        "matrix": _matrix(item.find("matrix")) if item.get("placeFlagHasMatrix") == "true" else None,
        "cxform": _cxform(item.find("colorTransform")) if item.get("placeFlagHasColorTransform") == "true" else None,
        "ratio": int(item.get("ratio")) if item.get("placeFlagHasRatio") == "true" else None,
        "clip_depth": int(item.get("clipDepth")) if item.get("placeFlagHasClipDepth") == "true" else None,
        "blend": int(blend) if blend is not None else None,
    }


def _timeline(sub_tags, scripts_dir=None, sprite_id=None):
    timeline = Timeline()
    frame = Frame()
    scripts_in_frame = 0
    for item in sub_tags:
        kind = item.get("type")
        if kind in PLACE_TAGS:
            frame.ops.append(_place_op(item))
        elif kind == "RemoveObject2Tag" or kind == "RemoveObjectTag":
            frame.ops.append({"op": "remove", "depth": int(item.get("depth"))})
        elif kind == "FrameLabelTag":
            frame.label = item.get("name")
        elif kind == "DoActionTag":
            scripts_in_frame += 1
            actions = decode_actions(item.get("actionBytes") or "")
            if scripts_dir and actions and "unsupported" in actions[0]:
                path = _script_file(scripts_dir, sprite_id, len(timeline.frames) + 1, scripts_in_frame)
                if os.path.exists(path):
                    with open(path, encoding="utf8") as source:
                        actions = classify_script(source.read()) or actions
            frame.actions.extend(actions)
        elif kind == "ShowFrameTag":
            timeline.frames.append(frame)
            frame = Frame()
            scripts_in_frame = 0
    return timeline


def _color(elem):
    if elem is None:
        return None
    return (int(elem.get("red")), int(elem.get("green")), int(elem.get("blue")),
            int(elem.get("alpha", 255)))


_ALIGN = {"left": 0, "right": 1, "center": 2, "justify": 3}


def parse_html_text(html):
    """The plain text of an HTML text field, with the alignment (0 left, 1 right, 2 centre, 3 justify) and the
    colour its markup asks for (None when it does not)."""
    if not html:
        return "", None, None
    align = None
    color = None
    match = re.search(r'<p[^>]*\balign="(\w+)"', html)
    if match:
        align = _ALIGN.get(match.group(1).lower())
    match = re.search(r'<font[^>]*\bcolor="#([0-9a-fA-F]{6})"', html)
    if match:
        value = int(match.group(1), 16)
        color = ((value >> 16) & 255, (value >> 8) & 255, value & 255, 255)
    text = re.sub(r"</p>\s*<p", "</p>" + chr(10) + "<p", html, flags=re.IGNORECASE)
    text = re.sub(r"<br\s*/?>", chr(10), text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]*>", "", text)
    return unescape(text), align, color


def _read_character(item, movie, scripts_dir=None):
    kind = item.get("type")
    if kind in SHAPE_TAGS:
        cid = int(item.get("shapeId"))
        movie.characters[cid] = Character(cid, "shape", bounds=_rect(item.find("shapeBounds")),
                                          polygon=_polygon(item.find("shapes")))
    elif kind == "DefineSpriteTag":
        cid = int(item.get("spriteId"))
        movie.characters[cid] = Character(cid, "sprite", timeline=_timeline(item.find("subTags"), scripts_dir, cid))
    elif kind == "DefineEditTextTag":
        cid = int(item.get("characterID"))
        initial, align, color = item.get("initialText", ""), int(item.get("align", 0)), _color(item.find("textColor"))
        if item.get("html") == "true":
            initial, html_align, html_color = parse_html_text(initial)
            align = align if html_align is None else html_align
            color = color if html_color is None else html_color
        movie.characters[cid] = Character(
            cid, "text", bounds=_rect(item.find("bounds")),
            font_height=_f(item, "fontHeight") / TWIPS, initial_text=initial,
            color=color, variable=item.get("variableName") or None,
            align=align, font_id=int(item.get("fontId", 0)) or None)
    elif kind == "DefineTextTag":
        cid = int(item.get("characterID"))
        movie.characters[cid] = Character(cid, "statictext", bounds=_rect(item.find("textBounds")))
    elif kind in BITMAP_TAGS:
        cid = int(item.get("characterID"))
        movie.characters[cid] = Character(cid, "bitmap")
    elif kind == "DefineMorphShapeTag" or kind == "DefineMorphShape2Tag":
        cid = int(item.get("characterId"))
        movie.characters[cid] = Character(cid, "morph", bounds=_rect(item.find("startBounds")),
                                          end_bounds=_rect(item.find("endBounds")),
                                          polygon=_polygon(item.find("startEdges")),
                                          end_polygon=_polygon(item.find("endEdges")))
    elif kind in ("DefineFont3Tag", "DefineFont2Tag"):
        cid = int(item.get("fontID"))
        movie.characters[cid] = Character(cid, "font", name=(item.get("fontName") or "").strip("\0"))
    elif kind in ("ImportAssetsTag", "ImportAssets2Tag"):
        for tag, name in zip(item.find("tags"), item.find("names")):
            movie.imports[int(tag.text)] = (item.get("url"), name.text)
    elif kind == "ExportAssetsTag":
        for tag, name in zip(item.find("tags"), item.find("names")):
            movie.exports[name.text] = int(tag.text)


def parse_swf_xml(path, scripts_dir=None):
    root = ET.parse(path).getroot()
    movie = Movie(frame_rate=float(root.get("frameRate", "0")))
    display = root.find("displayRect")
    if display is not None:
        movie.width_px = int(round((_f(display, "Xmax") - _f(display, "Xmin")) / TWIPS))
        movie.height_px = int(round((_f(display, "Ymax") - _f(display, "Ymin")) / TWIPS))
    tags = root.find("tags")
    for item in tags:
        _read_character(item, movie, scripts_dir)
    # The root timeline is every top-level placement/remove/label/action tag.
    top_level = [i for i in tags if i.get("type") in PLACE_TAGS + (
        "RemoveObject2Tag", "RemoveObjectTag", "FrameLabelTag", "DoActionTag", "ShowFrameTag")]
    movie.root = _timeline(top_level, scripts_dir, None)
    return movie
