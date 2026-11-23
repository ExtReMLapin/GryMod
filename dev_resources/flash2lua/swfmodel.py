"""Parse FFDec's `-swf2xml` output of a Flash (SWF) HUD file into a small timeline model.

Only what the GryMod HUD player needs is kept: character dictionary (shapes, sprites, texts,
bitmaps, morph shapes, fonts) and the sprite timelines (display-list operations per frame,
frame labels, the few frame actions the HUD uses). Lengths are converted from twips to pixels.
"""
import math
import os
import re
import subprocess
import xml.etree.ElementTree as ET
from html import unescape
from dataclasses import dataclass, field
from typing import Optional

from dev_resources.flash2lua import scripts

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
    # how the text is laid out in the field: wrapped inside the width (multiline + word wrap), field resized to fit
    # the text (auto size), extra space between two lines (leading, pixels)
    multiline: bool = False
    word_wrap: bool = False
    auto_size: bool = False
    leading: float = 0
    # simple shapes: the outline as a pixel polygon (one contour, straight edges), else None
    polygon: Optional[list] = None
    # the same for a shape used as a clip layer, one polygon per contour (there can be several: the bars of a signal
    # meter): curves cut into straight pieces
    mask_polygons: Optional[list] = None
    # morph shapes
    end_bounds: Optional[tuple] = None
    end_polygon: Optional[list] = None
    end_mask_polygons: Optional[list] = None
    # a morph that is seen (not a clip layer): its visible layers, see _morph_layers
    layers: Optional[list] = None
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


# A contour smaller than this (square pixels) is a speck left by the drawing tool, not part of the outline.
SPECK_AREA = 1.0


def _contour_area(points):
    """Absolute area of a closed contour (twips squared)."""
    area = 0
    for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
        area += x1 * y2 - x2 * y1
    return abs(area) / 2


# Features of a mask outline smaller than this (pixels) are dropped: a jog of a twip or two in a long edge would
# only cost the game extra pieces to clip against.
SIMPLIFY_TOLERANCE = 0.25


def _distance_to_segment(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0 if length2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / length2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _chain(points, tolerance):
    """Douglas-Peucker on an open chain: the first point, the ones that stay, the last point."""
    if len(points) < 3:
        return list(points)
    far, index = max((_distance_to_segment(p, points[0], points[-1]), i) for i, p in enumerate(points[1:-1], 1))
    if far <= tolerance:
        return [points[0], points[-1]]
    return _chain(points[:index + 1], tolerance)[:-1] + _chain(points[index:], tolerance)


def simplify_polygon(points, tolerance=SIMPLIFY_TOLERANCE):
    """A closed polygon [(x, y)] without the features smaller than `tolerance` (Douglas-Peucker from the point
    farthest from the first one). A polygon that would collapse under 3 points is returned as it is."""
    if len(points) <= 3:
        return list(points)
    first = max(range(len(points)), key=lambda i: math.hypot(points[i][0] - points[0][0], points[i][1] - points[0][1]))
    a = _chain(points[:first + 1], tolerance)
    b = _chain(points[first:] + points[:1], tolerance)
    result = a[:-1] + b[:-1]
    return result if len(result) >= 3 else list(points)


# A curve of a mask outline is cut into this many straight pieces (each one a quadratic Bezier of at most a quarter
# turn: eight pieces keep a 65 pixel radius circle within a third of a pixel of the original).
CURVE_STEPS = 8


def _outline_contours(records_parent):
    """The contours of a shape as [(start, edges)] in twips: `start` = (x, y), `edges` = [(control, anchor)] where
    control is None for a straight edge. A contour starts at a move; an edge without one (the first records of a
    shape, or the ones after a closed contour) starts it at the pen, which begins at the origin. None for a shape
    without records."""
    if records_parent is None:
        return None
    records = records_parent.find("shapeRecords")
    if records is None:
        return None
    x = y = 0
    contours = []

    def pen_down():
        if not contours or (contours[-1][1] and contours[-1][0] == contours[-1][1][-1][1]):
            contours.append(((x, y), []))

    for rec in records:
        kind = rec.get("type")
        if kind == "StyleChangeRecord":
            if rec.get("stateMoveTo") == "true":
                x, y = int(rec.get("moveDeltaX")), int(rec.get("moveDeltaY"))
                contours.append(((x, y), []))
        elif kind == "StraightEdgeRecord":
            pen_down()
            x += int(rec.get("deltaX", 0))
            y += int(rec.get("deltaY", 0))
            contours[-1][1].append((None, (x, y)))
        elif kind == "CurvedEdgeRecord":
            pen_down()
            cx, cy = x + int(rec.get("controlDeltaX", 0)), y + int(rec.get("controlDeltaY", 0))
            x, y = cx + int(rec.get("anchorDeltaX", 0)), cy + int(rec.get("anchorDeltaY", 0))
            contours[-1][1].append(((cx, cy), (x, y)))
    return contours


def _flatten(contour, cut):
    """A contour as a list of (x, y), a closed one ending on its first point. `cut[i]` says whether edge i is cut
    into CURVE_STEPS straight pieces (a straight edge is cut into equal ones, as the curve with its control point
    in the middle would be); the others are kept as one segment."""
    (x, y), edges = contour
    points = [(x, y)]
    for (control, anchor), cutting in zip(edges, cut):
        if cutting:
            cx, cy = control if control is not None else ((x + anchor[0]) / 2, (y + anchor[1]) / 2)
            for i in range(1, CURVE_STEPS):
                t = i / CURVE_STEPS
                points.append(((1 - t) ** 2 * x + 2 * t * (1 - t) * cx + t * t * anchor[0],
                               (1 - t) ** 2 * y + 2 * t * (1 - t) * cy + t * t * anchor[1]))
        points.append(anchor)
        x, y = anchor
    return points


def _contours(records_parent, curves=False):
    """The contours of a shape as lists of (x, y) in twips, a closed one ending on its first point, or None for a
    shape without records, or with a curve when `curves` is false (a curve is cut into CURVE_STEPS straight pieces
    when it is true)."""
    outlines = _outline_contours(records_parent)
    if outlines is None:
        return None
    if not curves and any(control is not None for _, edges in outlines for control, _ in edges):
        return None
    return [_flatten(contour, [control is not None for control, _ in contour[1]]) for contour in outlines]


def _real_contours(contours):
    """The closed contours that are more than a speck (under a square pixel)."""
    return [c for c in contours
            if len(c) >= 4 and c[0] == c[-1] and _contour_area(c[:-1]) >= SPECK_AREA * TWIPS * TWIPS]


def _pixels(points):
    return [(px / TWIPS, py / TWIPS) for px, py in points[:-1]]


def _polygon(records_parent, simplify=False):
    """The outline of a one-contour shape made of straight edges as [(x, y)] in pixels (not closed
    twice), or None for anything else (curves, several contours, an open path). Contours that are
    specks (under a square pixel) do not count: a shape can carry a stray one next to its real outline."""
    contours = _contours(records_parent)
    if contours is None:
        return None
    real = _real_contours(contours)
    if len(real) != 1:
        return None
    polygon = _pixels(real[0])
    return simplify_polygon(polygon) if simplify else polygon


def _mask_polygons(records_parent, simplify=True):
    """The outlines of the contours of a shape that serves as a clip layer, as lists of [(x, y)] in pixels, curves
    cut into straight pieces; [] for a shape without a closed contour of real size. With `simplify` false the
    number of points does not depend on the sizes (a morph needs the same count at both ends)."""
    contours = _contours(records_parent, curves=True)
    if contours is None:
        return []
    polygons = [_pixels(c) for c in _real_contours(contours)]
    return [simplify_polygon(p) for p in polygons] if simplify else polygons


def _mask_polygon(records_parent, simplify=True):
    """_mask_polygons for a shape of one contour, else None (the drawing code takes one outline per mask)."""
    polygons = _mask_polygons(records_parent, simplify)
    return polygons[0] if len(polygons) == 1 else None


def _morph_mask_polygons(start_parent, end_parent):
    """The two ends of a morph shape that serves as a clip layer, as (starts, ends): lists of polygons [(x, y)] in
    pixels that pair up contour by contour and point by point. An edge that is straight at one end and curved at the
    other is cut into pieces at both, so the counts agree; ([], []) when the ends do not pair up (different numbers
    of contours or edges). A contour counts when it is closed at both ends and more than a speck at one of them."""
    start, end = _outline_contours(start_parent), _outline_contours(end_parent)
    if not start or not end or len(start) != len(end) or any(len(a[1]) != len(b[1]) for a, b in zip(start, end)):
        return [], []
    starts, ends = [], []
    for a, b in zip(start, end):
        cut = [ca is not None or cb is not None for (ca, _), (cb, _) in zip(a[1], b[1])]
        pa, pb = _flatten(a, cut), _flatten(b, cut)
        if not (len(pa) >= 4 and pa[0] == pa[-1] and pb[0] == pb[-1]):
            continue
        if max(_contour_area(pa[:-1]), _contour_area(pb[:-1])) >= SPECK_AREA * TWIPS * TWIPS:
            starts.append(_pixels(pa))
            ends.append(_pixels(pb))
    return starts, ends


def _styled_contours(records_parent):
    """_outline_contours with the styles in force on every edge: [(start, edges, styles)] where styles[i] is the
    (fill0, fill1, line) of edge i (0 = none). The splitting into contours is the same."""
    if records_parent is None:
        return None
    records = records_parent.find("shapeRecords")
    if records is None:
        return None
    x = y = 0
    fill0 = fill1 = line = 0
    contours = []

    def pen_down():
        if not contours or (contours[-1][1] and contours[-1][0] == contours[-1][1][-1][1]):
            contours.append(((x, y), [], []))

    for rec in records:
        kind = rec.get("type")
        if kind == "StyleChangeRecord":
            if rec.get("stateFillStyle0") == "true":
                fill0 = int(rec.get("fillStyle0", 0))
            if rec.get("stateFillStyle1") == "true":
                fill1 = int(rec.get("fillStyle1", 0))
            if rec.get("stateLineStyle") == "true":
                line = int(rec.get("lineStyle", 0))
            if rec.get("stateMoveTo") == "true":
                x, y = int(rec.get("moveDeltaX")), int(rec.get("moveDeltaY"))
                contours.append(((x, y), [], []))
        elif kind == "StraightEdgeRecord":
            pen_down()
            x += int(rec.get("deltaX", 0))
            y += int(rec.get("deltaY", 0))
            contours[-1][1].append((None, (x, y)))
            contours[-1][2].append((fill0, fill1, line))
        elif kind == "CurvedEdgeRecord":
            pen_down()
            cx, cy = x + int(rec.get("controlDeltaX", 0)), y + int(rec.get("controlDeltaY", 0))
            x, y = cx + int(rec.get("anchorDeltaX", 0)), cy + int(rec.get("anchorDeltaY", 0))
            contours[-1][1].append(((cx, cy), (x, y)))
            contours[-1][2].append((fill0, fill1, line))
    return contours


def _end_contours(records_parent, sizes):
    """The end of a morph cut into contours of the given numbers of edges (the ones of its start): the end of a morph
    shape does not always repeat the moves of the start (a shape that collapses to a point has none), so it is
    the edges that pair up, a contour starting at its move when it has one, else at the pen. [(start, edges)], or
    None when the edges do not pair up (another number of them, a move in the middle of a contour)."""
    records = records_parent.find("shapeRecords") if records_parent is not None else None
    if records is None:
        return None
    x = y = 0
    events = []
    for rec in records:
        kind = rec.get("type")
        if kind == "StyleChangeRecord" and rec.get("stateMoveTo") == "true":
            x, y = int(rec.get("moveDeltaX")), int(rec.get("moveDeltaY"))
            events.append(("move", (x, y)))
        elif kind == "StraightEdgeRecord":
            x += int(rec.get("deltaX", 0))
            y += int(rec.get("deltaY", 0))
            events.append(("edge", None, (x, y)))
        elif kind == "CurvedEdgeRecord":
            cx, cy = x + int(rec.get("controlDeltaX", 0)), y + int(rec.get("controlDeltaY", 0))
            x, y = cx + int(rec.get("anchorDeltaX", 0)), cy + int(rec.get("anchorDeltaY", 0))
            events.append(("edge", (cx, cy), (x, y)))
    contours = []
    pen = (0, 0)
    index = 0
    for size in sizes:
        start = pen
        if index < len(events) and events[index][0] == "move":
            start = events[index][1]
            index += 1
        edges = []
        while len(edges) < size:
            if index >= len(events) or events[index][0] != "edge":
                return None
            edges.append((events[index][1], events[index][2]))
            index += 1
        pen = edges[-1][1] if edges else start
        contours.append((start, edges))
    if any(event[0] == "edge" for event in events[index:]):
        return None
    return contours


def _rgba(elem):
    return (int(elem.get("red")), int(elem.get("green")), int(elem.get("blue")), int(elem.get("alpha", 255)))


def _morph_fill_styles(parent):
    """[(start colour, end colour)] of the solid fill styles of a morph shape, None in the place of any other kind
    (gradient, bitmap): the styles are numbered from 1 by the records."""
    result = []
    fills = parent.find("fillStyles") if parent is not None else None
    for item in (fills if fills is not None else []):
        if item.get("fillStyleType") == "0" and item.find("startColor") is not None and item.find("endColor") is not None:
            result.append((_rgba(item.find("startColor")), _rgba(item.find("endColor"))))
        else:
            result.append(None)
    return result


def _morph_line_styles(parent):
    """[{"widths": (start, end) in pixels, "colors": (start, end), "cap": 0 round | 1 none | 2 square}] of the line
    styles of a morph shape, None in the place of a style that is filled with a gradient or a bitmap."""
    result = []
    if parent is None:
        return result
    lines = parent.find("lineStyles2")
    if lines is None:
        lines = parent.find("lineStyles")
    for item in (lines if lines is not None else []):
        if item.get("hasFillFlag") == "true" or item.find("startColor") is None or item.find("endColor") is None:
            result.append(None)
            continue
        result.append({"widths": (int(item.get("startWidth", 0)) / TWIPS, int(item.get("endWidth", 0)) / TWIPS),
                       "colors": (_rgba(item.find("startColor")), _rgba(item.find("endColor"))),
                       "cap": int(item.get("startCapStyle", 0))})
    return result


def _unit(dx, dy):
    length = math.hypot(dx, dy)
    return (dx / length, dy / length) if length > 1e-9 else None


def _joint(before, after, half):
    """How far the two segments that meet at a joint must run past it so that the corner is filled: half the width
    times tan(turn / 2), at most half the width (a smooth curve cut into short pieces adds almost nothing)."""
    cosine = max(-1.0, min(1.0, before[0] * after[0] + before[1] * after[1]))
    turn = math.acos(cosine)
    if turn >= math.pi / 2 - 1e-6:
        return half
    return half * math.tan(turn / 2)


def _stroke_quads(points, directions, width, cap, closed):
    """A stroke as one rectangle per segment (pixels), in the order of the segments, None for a segment that has
    no direction (no length at either end of the morph). `directions[i]` is the unit direction of segment i, from
    point i to point i + 1. A rectangle runs past the end it shares with a neighbour so that the corner is filled;
    a free end of the stroke gets half the width when the cap is not "none"."""
    half = width / 2
    count = len(directions)
    quads = []
    for i in range(count):
        if directions[i] is None:
            continue
        before = directions[i - 1] if (i > 0 or closed) else None
        after = directions[(i + 1) % count] if (i < count - 1 or closed) else None
        run_in = _joint(before, directions[i], half) if before else (half if cap != 1 else 0)
        run_out = _joint(directions[i], after, half) if after else (half if cap != 1 else 0)
        (ax, ay), (bx, by) = points[i], points[i + 1]
        dx, dy = directions[i]
        nx, ny = -dy * half, dx * half
        ax, ay, bx, by = ax - dx * run_in, ay - dy * run_in, bx + dx * run_out, by + dy * run_out
        quads.append([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)])
    return quads


def _stroke_pair(start_points, end_points, widths, cap):
    """The rectangles of a stroke at the two ends of a morph: ([start quads], [end quads]) with the same count (a
    segment with no length at one end takes the direction of the other; one with none at both is dropped)."""
    count = len(start_points) - 1
    first = [_unit(start_points[i + 1][0] - start_points[i][0], start_points[i + 1][1] - start_points[i][1]) for i in range(count)]
    last = [_unit(end_points[i + 1][0] - end_points[i][0], end_points[i + 1][1] - end_points[i][1]) for i in range(count)]
    closed = count > 2 and start_points[0] == start_points[-1] and end_points[0] == end_points[-1]
    sides = []
    for points, own, other, width in ((start_points, first, last, widths[0]), (end_points, last, first, widths[1])):
        directions = [own[i] or other[i] for i in range(count)]
        sides.append(_stroke_quads(points, directions, width, cap, closed))
    return sides[0], sides[1]


def _morph_layers(item):
    """The visible parts of a morph shape that is not a clip layer, as a list of layers drawn in this order, the
    fills (by style number) then the strokes: {"color": (r, g, b, a) at the start, "end_color": at the end, "starts":
    [polygon, ...], "ends": [polygon, ...]} with polygons in pixels pairing up point by point (curves are cut into
    straight pieces, a stroke becomes one rectangle per segment). [] when the two ends do not pair up."""
    start = _styled_contours(item.find("startEdges"))
    end = _end_contours(item.find("endEdges"), [len(c[1]) for c in start]) if start else None
    if not start or not end:
        return []
    fills = _morph_fill_styles(item.find("morphFillStyles"))
    lines = _morph_line_styles(item.find("morphLineStyles"))
    filled, stroked = {}, {}
    for (s_point, s_edges, styles), (e_point, e_edges) in zip(start, end):
        if not s_edges:
            continue
        cut = [ca is not None or cb is not None for (ca, _), (cb, _) in zip(s_edges, e_edges)]
        index = next((f for style in styles for f in (style[0], style[1]) if f), 0)
        if index and index <= len(fills) and fills[index - 1]:
            pa, pb = _flatten((s_point, s_edges), cut), _flatten((e_point, e_edges), cut)
            if pa[0] == pa[-1]:
                pa, pb = pa[:-1], pb[:-1]
            if len(pa) >= 3 and max(_contour_area(pa), _contour_area(pb)) >= SPECK_AREA * TWIPS * TWIPS:
                polygons = filled.setdefault(index, ([], []))
                polygons[0].append([(px / TWIPS, py / TWIPS) for px, py in pa])
                polygons[1].append([(px / TWIPS, py / TWIPS) for px, py in pb])
        position = 0
        while position < len(styles):
            line = styles[position][2]
            stop = position
            while stop < len(styles) and styles[stop][2] == line:
                stop += 1
            if line and line <= len(lines) and lines[line - 1] and max(lines[line - 1]["widths"]) > 0:
                run = slice(position, stop)
                s_from = s_edges[position - 1][1] if position else s_point
                e_from = e_edges[position - 1][1] if position else e_point
                pa = _flatten((s_from, s_edges[run]), cut[run])
                pb = _flatten((e_from, e_edges[run]), cut[run])
                pa = [(x / TWIPS, y / TWIPS) for x, y in pa]
                pb = [(x / TWIPS, y / TWIPS) for x, y in pb]
                quads_a, quads_b = _stroke_pair(pa, pb, lines[line - 1]["widths"], lines[line - 1]["cap"])
                if quads_a:
                    polygons = stroked.setdefault(line, ([], []))
                    polygons[0].extend(quads_a)
                    polygons[1].extend(quads_b)
            position = stop
    layers = []
    for kind, groups, styles in (("fill", filled, fills), ("stroke", stroked, lines)):
        for index in sorted(groups):
            style = styles[index - 1]
            colors = style if kind == "fill" else style["colors"]
            if colors[0][3] == 0 and colors[1][3] == 0:
                continue
            layers.append({"color": colors[0], "end_color": colors[1], "starts": groups[index][0], "ends": groups[index][1]})
    return layers


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
                                          polygon=_polygon(item.find("shapes"), simplify=True),
                                          mask_polygons=_mask_polygons(item.find("shapes")))
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
            align=align, font_id=int(item.get("fontId", 0)) or None,
            multiline=item.get("multiline") == "true", word_wrap=item.get("wordWrap") == "true",
            auto_size=item.get("autoSize") == "true", leading=_f(item, "leading") / TWIPS)
    elif kind == "DefineTextTag":
        cid = int(item.get("characterID"))
        movie.characters[cid] = Character(cid, "statictext", bounds=_rect(item.find("textBounds")))
    elif kind in BITMAP_TAGS:
        cid = int(item.get("characterID"))
        movie.characters[cid] = Character(cid, "bitmap")
    elif kind == "DefineMorphShapeTag" or kind == "DefineMorphShape2Tag":
        cid = int(item.get("characterId"))
        mask_starts, mask_ends = _morph_mask_polygons(item.find("startEdges"), item.find("endEdges"))
        movie.characters[cid] = Character(cid, "morph", bounds=_rect(item.find("startBounds")),
                                          end_bounds=_rect(item.find("endBounds")),
                                          polygon=_polygon(item.find("startEdges")),
                                          end_polygon=_polygon(item.find("endEdges")),
                                          mask_polygons=mask_starts, end_mask_polygons=mask_ends,
                                          layers=_morph_layers(item))
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
