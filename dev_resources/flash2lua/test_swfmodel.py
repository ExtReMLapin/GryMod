"""Tests for the SWF model parser. They need FFDec and the demo's HUD SWF files:
set FFDEC and SWF_DIR, or keep the research dump at its default place. Skipped otherwise."""
import os
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from dev_resources.flash2lua import swfmodel

FFDEC = os.environ.get("FFDEC", r"D:\dev\crysis-hud-research\ffdec\ffdec-cli.exe")
SWF_DIR = os.environ.get("SWF_DIR", r"D:\dev\crysis-hud-research\extracted\Libs\UI")
SWF = os.path.join(SWF_DIR, "HUD_AmmoHealthEnergySuit.swf")


def find_named(movie, name):
    """Depth-first search of the first placed child with this instance name."""
    seen = set()

    def walk(timeline):
        for frame in timeline.frames:
            for op in frame.ops:
                if op["op"] != "place":
                    continue
                if op["name"] == name:
                    return op["char"]
                ch = movie.characters.get(op["char"]) if op["char"] else None
                if ch is not None and ch.kind == "sprite" and ch.id not in seen:
                    seen.add(ch.id)
                    found = walk(ch.timeline)
                    if found:
                        return found
        return None

    return find_named_result(movie, walk(movie.root))


def find_named_result(movie, char_id):
    return movie.characters.get(char_id) if char_id else None


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(SWF), "FFDec / demo SWF not available")
class SwfModelTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        xml = os.path.join(cls.tmp, "hud.xml")
        swfmodel.swf_to_xml(FFDEC, SWF, xml)
        scripts = os.path.join(cls.tmp, "scripts")
        swfmodel.export_scripts(FFDEC, SWF, scripts)
        cls.movie = swfmodel.parse_swf_xml(xml, scripts)

    def test_stage_is_1024x768_30fps(self):
        self.assertEqual(self.movie.width_px, 1024)
        self.assertEqual(self.movie.height_px, 768)
        self.assertEqual(self.movie.frame_rate, 30.0)

    def test_root_places_clip_241_named_Root(self):
        op = self.movie.root.frames[0].ops[0]
        self.assertEqual((op["op"], op["depth"], op["char"], op["name"]), ("place", 1, 241, "Root"))
        a, b, c, d, tx, ty = op["matrix"]
        self.assertAlmostEqual(a, 0.79889, places=4)
        self.assertAlmostEqual(d, 0.79999, places=4)
        self.assertAlmostEqual(b, 0.04187, places=4)
        self.assertAlmostEqual(tx, 16146 / 20)
        self.assertAlmostEqual(ty, 12333 / 20)

    def test_sprite_6_has_one_frame_with_char_5_at_depth_2(self):
        sprite = self.movie.characters[6]
        self.assertEqual(sprite.kind, "sprite")
        self.assertEqual(len(sprite.timeline.frames), 1)
        op = sprite.timeline.frames[0].ops[0]
        self.assertEqual((op["depth"], op["char"]), (2, 5))
        self.assertEqual(op["matrix"], (1.0, 0.0, 0.0, 1.0, 0.0, 0.0))

    def test_shape_5_has_bounds_in_pixels(self):
        shape = self.movie.characters[5]
        self.assertEqual(shape.kind, "shape")
        self.assertEqual(shape.bounds, (-56 / 20, 144 / 20, 4828 / 20, 2732 / 20))

    def test_labels_found(self):
        cloak = self.movie.characters[38]
        labels = [f.label for f in cloak.timeline.frames if f.label]
        self.assertIn("normal", labels)
        self.assertEqual(cloak.timeline.frames[0].label, "normal")

    def test_bar_sprites_have_100_frames(self):
        self.assertEqual(len(find_named(self.movie, "HealthBar").timeline.frames), 100)
        self.assertEqual(len(find_named(self.movie, "EnergyBar").timeline.frames), 100)

    def test_colour_transform_mult_terms_are_fractions(self):
        cloak = self.movie.characters[38]
        cx = [op["cxform"] for f in cloak.timeline.frames for op in f.ops
              if op["op"] == "place" and op["cxform"]]
        self.assertTrue(cx)
        self.assertAlmostEqual(cx[0][3], 228 / 256)  # alpha multiplier
        self.assertEqual(cx[0][:3], (1.0, 1.0, 1.0))

    def test_remove_object_op(self):
        removes = [op for ch in self.movie.characters.values() if ch.kind == "sprite"
                   for f in ch.timeline.frames for op in f.ops if op["op"] == "remove"]
        self.assertTrue(removes)
        self.assertIn("depth", removes[0])

    def test_simple_actions_are_decoded(self):
        cloak = self.movie.characters[38]
        self.assertEqual(cloak.timeline.frames[0].actions, [{"do": "play"}])

    def test_unknown_action_is_flagged_not_dropped(self):
        flagged = [a for ch in self.movie.characters.values() if ch.kind == "sprite"
                   for f in ch.timeline.frames for a in f.actions if "unsupported" in a]
        for a in flagged:
            self.assertIsInstance(a["unsupported"], str)

    def test_rectangle_shape_has_a_polygon(self):
        shape = self.movie.characters[15]
        px = lambda *v: tuple(c / 20 for c in v)
        self.assertEqual(shape.polygon, [px(29, -58), px(29, 318), px(2829, 318), px(2829, -58)])

    def test_curved_shape_has_no_polygon(self):
        self.assertIsNone(self.movie.characters[100].polygon)

    def test_morph_shape_has_start_and_end_polygons(self):
        morph = self.movie.characters[8]
        px = lambda *v: tuple(c / 20 for c in v)
        self.assertEqual(morph.polygon, [px(2673, -73), px(2687, -73), px(2687, 303), px(2673, 303)])
        self.assertEqual(morph.end_polygon, [px(30, -58), px(2790, -58), px(2790, 318), px(30, 318)])

    def test_colour_scripts_become_actions(self):
        # sprite 102 sets the colour of its Colorset child from the Line theme colour when it starts
        actions = self.movie.characters[102].timeline.frames[0].actions
        self.assertIn({"do": "color", "theme": "Line", "target": "Colorset"}, actions)

    def test_digit_scripts_colour_the_number_and_stop(self):
        actions = self.movie.characters[91].timeline.frames[0].actions
        self.assertIn({"do": "color", "theme": "Text", "target": "NumberText"}, actions)
        self.assertIn({"do": "stop"}, actions)

    def test_the_root_script_keeps_only_its_top_level_stop(self):
        """The root script is mostly function definitions and _root calls (ported by hand); only its stop() is an action."""
        self.assertEqual(self.movie.root.frames[0].actions, [{"do": "stop"}])

    def test_imported_font_is_recorded(self):
        self.assertEqual(self.movie.imports[63], ("HUD_Font_LocFont.swf", "Font_Body"))

    def test_edit_text_fields(self):
        text = self.movie.characters[64]
        self.assertEqual(text.kind, "text")
        self.assertEqual(text.font_height, 360 / 20)
        self.assertEqual(text.initial_text, "0")
        self.assertEqual(text.color, (255, 255, 255, 255))


RADAR_SWF = os.path.join(SWF_DIR, "HUD_RadarCompassStealth.swf")


@unittest.skipUnless(os.path.exists(FFDEC) and os.path.exists(RADAR_SWF), "FFDec / demo SWF not available")
class SwfModelRadarTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        xml = os.path.join(cls.tmp, "radar.xml")
        swfmodel.swf_to_xml(FFDEC, RADAR_SWF, xml)
        scripts = os.path.join(cls.tmp, "scripts")
        swfmodel.export_scripts(FFDEC, RADAR_SWF, scripts)
        cls.movie = swfmodel.parse_swf_xml(xml, scripts)

    def test_a_shape_with_a_stray_speck_still_has_the_polygon_of_its_real_contour(self):
        """Shape 84 (the radar's noise mask, a concave outline) has a second contour of three tiny edges (a speck
        of 0.002 square pixels): it must not hide the outline, or the mask is dropped and the noise covers the stage.
        The jogs of a fraction of a pixel along its top edge are simplified away."""
        shape = self.movie.characters[84]
        self.assertEqual(shape.polygon, [(178.75, 0.2), (24.65, 0.15), (24.65, 67.7), (55.25, 87.15), (55.25, 111.4),
                                         (178.65, 112.45), (198.05, 96.3), (198.05, 0.2)])


class PolygonContoursTest(unittest.TestCase):
    """_polygon on hand-written shape records (no FFDec needed)."""

    @staticmethod
    def shape(*contours):
        """contours: lists of (dx, dy) twip steps; each one starts with a move to its first point."""
        records = ""
        for start, steps in contours:
            records += '<item type="StyleChangeRecord" stateMoveTo="true" moveDeltaX="%d" moveDeltaY="%d"/>' % start
            for dx, dy in steps:
                records += '<item type="StraightEdgeRecord" deltaX="%d" deltaY="%d"/>' % (dx, dy)
        return ET.fromstring("<shapes><shapeRecords>%s</shapeRecords></shapes>" % records)

    SQUARE = ((0, 0), [(400, 0), (0, 400), (-400, 0), (0, -400)])

    def test_one_contour_is_its_polygon(self):
        self.assertEqual(swfmodel._polygon(self.shape(self.SQUARE)), [(0, 0), (20, 0), (20, 20), (0, 20)])

    def test_a_tiny_second_contour_is_ignored(self):
        speck = ((1000, 1000), [(0, -1), (-7, 3), (7, -2)])
        self.assertEqual(swfmodel._polygon(self.shape(self.SQUARE, speck)), [(0, 0), (20, 0), (20, 20), (0, 20)])

    def test_simplify_drops_jogs_under_the_tolerance_and_keeps_corners(self):
        jogged = [(0, 0), (10, 0.1), (20, 0), (20, 20), (0, 20)]
        self.assertEqual(swfmodel.simplify_polygon(jogged, 0.25), [(0, 0), (20, 0), (20, 20), (0, 20)])
        self.assertEqual(swfmodel.simplify_polygon(jogged, 0.01), jogged)

    def test_simplify_keeps_a_concave_corner(self):
        ell = [(0, 0), (20, 0), (20, 10), (10, 10), (10, 20), (0, 20)]
        self.assertEqual(swfmodel.simplify_polygon(ell), ell)

    def test_a_second_contour_of_real_size_means_no_polygon(self):
        island = ((1000, 1000), [(400, 0), (0, 400), (-400, 0), (0, -400)])
        self.assertIsNone(swfmodel._polygon(self.shape(self.SQUARE, island)))

    def test_a_shape_whose_first_record_has_no_move_starts_at_the_origin(self):
        # the first style change of a shape does not always carry a move: the pen is then at (0, 0)
        records = '<item type="StyleChangeRecord" stateMoveTo="false" fillStyle1="1"/>'
        for dx, dy in ((400, 0), (0, 300), (-400, 0), (0, -300)):
            records += '<item type="StraightEdgeRecord" deltaX="%d" deltaY="%d"/>' % (dx, dy)
        shape = ET.fromstring("<shapes><shapeRecords>%s</shapeRecords></shapes>" % records)
        self.assertEqual(swfmodel._polygon(shape), [(0, 0), (20, 0), (20, 15), (0, 15)])

    def test_the_pen_goes_on_from_the_end_of_a_closed_contour_without_a_move(self):
        records = '<item type="StyleChangeRecord" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"/>'
        for dx, dy in ((400, 0), (0, 400), (-400, 0), (0, -400), (800, 0), (0, 400), (-800, 0), (0, -400)):
            records += '<item type="StraightEdgeRecord" deltaX="%d" deltaY="%d"/>' % (dx, dy)
        shape = ET.fromstring("<shapes><shapeRecords>%s</shapeRecords></shapes>" % records)
        self.assertIsNone(swfmodel._polygon(shape))  # two contours of real size
        self.assertEqual(len(swfmodel._mask_polygons(shape)), 2)


class MaskPolygonTest(unittest.TestCase):
    """_mask_polygon: the outline of a shape that serves as a clip layer, where curves are cut into straight pieces."""

    @staticmethod
    def disc(radius=400):
        # four quarter arcs, each one a quadratic curve through a corner of the bounding square (control point there)
        r = radius
        records = '<item type="StyleChangeRecord" stateMoveTo="true" moveDeltaX="%d" moveDeltaY="0"/>' % r
        for cx, cy, ax, ay in ((0, r, -r, r), (-r, 0, -r, -r), (0, -r, r, -r), (r, 0, r, r)):
            records += ('<item type="CurvedEdgeRecord" controlDeltaX="%d" controlDeltaY="%d" anchorDeltaX="%d" anchorDeltaY="%d"/>'
                        % (cx, cy, ax - cx, ay - cy))
        return ET.fromstring("<shapes><shapeRecords>%s</shapeRecords></shapes>" % records)

    def test_a_curved_shape_has_no_strict_polygon_but_has_a_mask_polygon(self):
        shape = self.disc()
        self.assertIsNone(swfmodel._polygon(shape))
        polygon = swfmodel._mask_polygon(shape)
        self.assertGreaterEqual(len(polygon), 12)
        for x, y in polygon:
            # inside the square of the arcs, never beyond it
            self.assertTrue(-20.0 <= x <= 20.0 and -20.0 <= y <= 20.0)

    def test_the_cut_follows_the_curve_closer_than_a_quarter_pixel(self):
        # each quarter arc is a parabola from (r, 0) towards the corner (0, r): the middle of the curve is at 1/4 of
        # the way from the chord to the control point
        polygon = swfmodel._mask_polygon(self.disc(20 * 20))
        middle = min(polygon, key=lambda p: abs(p[0] + 20) + abs(p[1] - 0))
        self.assertLess(abs(middle[0] + 20) + abs(middle[1]), 0.6)

    def test_morph_ends_keep_the_same_number_of_points(self):
        self.assertEqual(len(swfmodel._mask_polygon(self.disc(400), simplify=False)),
                         len(swfmodel._mask_polygon(self.disc(100), simplify=False)))

    def test_a_straight_shape_gives_its_polygon(self):
        square = PolygonContoursTest.shape(PolygonContoursTest.SQUARE)
        self.assertEqual(swfmodel._mask_polygon(square), [(0, 0), (20, 0), (20, 20), (0, 20)])

    def test_several_contours_give_no_single_polygon(self):
        island = ((1000, 1000), [(400, 0), (0, 400), (-400, 0), (0, -400)])
        shape = PolygonContoursTest.shape(PolygonContoursTest.SQUARE, island)
        self.assertIsNone(swfmodel._mask_polygon(shape))
        self.assertEqual(len(swfmodel._mask_polygons(shape)), 2)


class SeveralContoursReadTest(unittest.TestCase):
    """_read_character keeps every contour of a shape or a morph (no FFDec needed)."""

    @staticmethod
    def records(*contours):
        return PolygonContoursTest.shape(*contours).find("shapeRecords")

    BAR = ((0, 0), [(200, 0), (0, 400), (-200, 0), (0, -400)])
    BAR2 = ((600, 0), [(200, 0), (0, 400), (-200, 0), (0, -400)])
    BAR_END = ((0, 0), [(100, 0), (0, 400), (-100, 0), (0, -400)])
    BAR2_END = ((700, 0), [(100, 0), (0, 400), (-100, 0), (0, -400)])
    BOUNDS = '<%s Xmin="0" Ymin="0" Xmax="800" Ymax="400"/>'

    def shape(self, *contours):
        xml = ('<item type="DefineShapeTag" shapeId="7">' + self.BOUNDS % "shapeBounds" + "<shapes>%s</shapes></item>"
               % ET.tostring(self.records(*contours), encoding="unicode"))
        movie = swfmodel.Movie()
        swfmodel._read_character(ET.fromstring(xml), movie)
        return movie.characters[7]

    def morph(self, start, end):
        edges = lambda tag, contours: "<%s>%s</%s>" % (tag, ET.tostring(self.records(*contours), encoding="unicode"), tag)
        xml = ('<item type="DefineMorphShapeTag" characterId="8">' + self.BOUNDS % "startBounds" + self.BOUNDS % "endBounds"
               + edges("startEdges", start) + edges("endEdges", end) + "</item>")
        movie = swfmodel.Movie()
        swfmodel._read_character(ET.fromstring(xml), movie)
        return movie.characters[8]

    def test_a_shape_of_two_contours_has_both_as_mask_polygons_and_no_strict_polygon(self):
        shape = self.shape(self.BAR, self.BAR2)
        self.assertIsNone(shape.polygon)
        self.assertEqual(len(shape.mask_polygons), 2)
        self.assertEqual(shape.mask_polygons[1], [(30, 0), (40, 0), (40, 20), (30, 20)])

    def test_a_shape_of_one_contour_has_one_mask_polygon(self):
        self.assertEqual(self.shape(self.BAR).mask_polygons, [[(0, 0), (10, 0), (10, 20), (0, 20)]])

    def test_a_morph_of_two_contours_has_both_ends_with_the_same_point_counts(self):
        morph = self.morph([self.BAR, self.BAR2], [self.BAR_END, self.BAR2_END])
        self.assertEqual((len(morph.mask_polygons), len(morph.end_mask_polygons)), (2, 2))
        self.assertEqual([len(p) for p in morph.mask_polygons], [len(p) for p in morph.end_mask_polygons])
        self.assertEqual(morph.end_mask_polygons[1][0], (35, 0))


class MorphMaskPolygonsTest(unittest.TestCase):
    """_morph_mask_polygons: the two ends of a morph clip layer, cut so that their contours and points match one by
    one, even where an edge is straight at one end and curved at the other (no FFDec needed)."""

    @staticmethod
    def records(*contours):
        """contours: (start, [edge...]); an edge is (dx, dy) straight, or (cdx, cdy, adx, ady) curved."""
        out = ""
        for start, edges in contours:
            out += '<item type="StyleChangeRecord" stateMoveTo="true" moveDeltaX="%d" moveDeltaY="%d"/>' % start
            for edge in edges:
                if len(edge) == 2:
                    out += '<item type="StraightEdgeRecord" deltaX="%d" deltaY="%d"/>' % edge
                else:
                    out += ('<item type="CurvedEdgeRecord" controlDeltaX="%d" controlDeltaY="%d" anchorDeltaX="%d" '
                            'anchorDeltaY="%d"/>' % edge)
        return ET.fromstring("<edges><shapeRecords>%s</shapeRecords></edges>" % out)

    SQUARE = ((0, 0), [(400, 0), (0, 400), (-400, 0), (0, -400)])
    # the same square whose bottom edge (from (400, 400) to (0, 400)) is a curve bulging down
    BULGE = ((0, 0), [(400, 0), (0, 400), (-200, 100, -200, -100), (0, -400)])

    def test_matching_edges_give_matching_polygons(self):
        starts, ends = swfmodel._morph_mask_polygons(self.records(self.SQUARE), self.records(self.SQUARE))
        self.assertEqual(starts, [[(0, 0), (20, 0), (20, 20), (0, 20)]])
        self.assertEqual(ends, starts)

    def test_an_edge_straight_at_one_end_and_curved_at_the_other_is_cut_at_both(self):
        starts, ends = swfmodel._morph_mask_polygons(self.records(self.SQUARE), self.records(self.BULGE))
        self.assertEqual(len(starts), 1)
        self.assertEqual(len(starts[0]), len(ends[0]))
        self.assertGreater(len(starts[0]), 4)
        # the straight edge from (20, 20) to (0, 20) is cut into equal steps along itself
        along = [p for p in starts[0] if p[1] == 20 and 0 < p[0] < 20]
        self.assertEqual(len(along), swfmodel.CURVE_STEPS - 1)
        self.assertEqual(sorted(p[0] for p in along), [20 - 20 * i / swfmodel.CURVE_STEPS for i in range(1, swfmodel.CURVE_STEPS)][::-1])
        # the other end bulges below the square
        self.assertTrue(any(p[1] > 20 for p in ends[0]))

    def test_the_contours_keep_their_order_at_both_ends(self):
        other = ((1000, 0), [(400, 0), (0, 400), (-400, 0), (0, -400)])
        starts, ends = swfmodel._morph_mask_polygons(self.records(self.SQUARE, other), self.records(self.BULGE, other))
        self.assertEqual([len(p) for p in starts], [len(p) for p in ends])
        self.assertEqual(starts[1][0], (50, 0))
        self.assertEqual(ends[1][0], (50, 0))

    def test_a_speck_is_dropped_at_both_ends(self):
        speck = ((2000, 2000), [(0, -1), (-7, 3), (7, -2)])
        starts, ends = swfmodel._morph_mask_polygons(self.records(self.SQUARE, speck), self.records(self.BULGE, speck))
        self.assertEqual((len(starts), len(ends)), (1, 1))

    def test_ends_that_do_not_pair_up_give_nothing(self):
        other = ((1000, 0), [(400, 0), (0, 400), (-400, 0), (0, -400)])
        self.assertEqual(swfmodel._morph_mask_polygons(self.records(self.SQUARE, other), self.records(self.SQUARE)), ([], []))
        triangle = ((0, 0), [(400, 0), (0, 400), (-400, -400)])
        self.assertEqual(swfmodel._morph_mask_polygons(self.records(self.SQUARE), self.records(triangle)), ([], []))

    def test_a_morph_character_is_read_through_it(self):
        bounds = '<%s Xmin="0" Ymin="0" Xmax="800" Ymax="400"/>'
        xml = ('<item type="DefineMorphShapeTag" characterId="8">' + bounds % "startBounds" + bounds % "endBounds"
               + "<startEdges>%s</startEdges><endEdges>%s</endEdges></item>"
               % (ET.tostring(self.records(self.SQUARE).find("shapeRecords"), encoding="unicode"),
                  ET.tostring(self.records(self.BULGE).find("shapeRecords"), encoding="unicode")))
        movie = swfmodel.Movie()
        swfmodel._read_character(ET.fromstring(xml), movie)
        morph = movie.characters[8]
        self.assertEqual(len(morph.mask_polygons), 1)
        self.assertEqual(len(morph.mask_polygons[0]), len(morph.end_mask_polygons[0]))
        self.assertGreater(len(morph.mask_polygons[0]), 4)


class MorphLayersTest(unittest.TestCase):
    """_morph_layers: the visible parts of a morph shape (fills, strokes) with their colours (no FFDec needed)."""

    @staticmethod
    def records(start, *edges, moves=()):
        """A shape: (style words of the first record) then edges, an edge being (dx, dy), and `moves` a list of
        (edge number, x, y) records put before the edge with that number."""
        out = '<item type="StyleChangeRecord" %s/>' % start
        for number, (dx, dy) in enumerate(edges):
            for at, x, y in moves:
                if at == number:
                    out += '<item type="StyleChangeRecord" stateMoveTo="true" moveDeltaX="%d" moveDeltaY="%d"/>' % (x, y)
            out += '<item type="StraightEdgeRecord" deltaX="%d" deltaY="%d"/>' % (dx, dy)
        return "<shapeRecords>%s</shapeRecords>" % out

    @staticmethod
    def fill(start, end):
        return ('<morphFillStyles><fillStyles><item type="MORPHFILLSTYLE" fillStyleType="0"><startColor red="%d" green="%d" blue="%d" alpha="%d"/>'
                '<endColor red="%d" green="%d" blue="%d" alpha="%d"/></item></fillStyles></morphFillStyles>' % (start + end))

    @staticmethod
    def line(width, end_width, color=(255, 255, 255, 255), cap=2):
        return ('<morphLineStyles><lineStyles2><item type="MORPHLINESTYLE2" startWidth="%d" endWidth="%d" startCapStyle="%d" joinStyle="2">'
                '<startColor red="%d" green="%d" blue="%d" alpha="%d"/><endColor red="%d" green="%d" blue="%d" alpha="%d"/></item></lineStyles2></morphLineStyles>'
                % ((width, end_width, cap) + color + color))

    NO_LINE = '<morphLineStyles><lineStyles><item type="MORPHLINESTYLE" startWidth="0" endWidth="0"><startColor red="0" green="0" blue="0" alpha="0"/><endColor red="0" green="0" blue="0" alpha="0"/></item></lineStyles></morphLineStyles>'
    SQUARE = [(400, 0), (0, 400), (-400, 0), (0, -400)]  # 20 pixels

    def layers(self, fills, lines, start, end):
        xml = ET.fromstring("<morph>%s%s<startEdges>%s</startEdges><endEdges>%s</endEdges></morph>" % (fills, lines, start, end))
        return swfmodel._morph_layers(xml)

    def test_a_fill_gives_one_layer_with_its_two_colours_and_outlines(self):
        start = self.records('fillStyle0="1" lineStyle="1" stateFillStyle0="true" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', *self.SQUARE)
        end = self.records('stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (800, 0), (0, 400), (-800, 0), (0, -400))
        layers = self.layers(self.fill((0, 0, 0, 115), (10, 20, 30, 255)), self.NO_LINE, start, end)
        self.assertEqual(len(layers), 1)
        self.assertEqual((layers[0]["color"], layers[0]["end_color"]), ((0, 0, 0, 115), (10, 20, 30, 255)))
        self.assertEqual(layers[0]["starts"], [[(0, 0), (20, 0), (20, 20), (0, 20)]])
        self.assertEqual(layers[0]["ends"], [[(0, 0), (40, 0), (40, 20), (0, 20)]])

    def test_a_line_gives_one_rectangle_per_segment_with_square_ends(self):
        # a horizontal line of 20 pixels, 2 pixels thick, becoming 40 pixels and 4 thick
        start = self.records('lineStyle="1" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0))
        end = self.records('stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (800, 0))
        layers = self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(40, 80), start, end)
        self.assertEqual(len(layers), 1)
        self.assertEqual(layers[0]["starts"], [[(-1.0, 1.0), (21.0, 1.0), (21.0, -1.0), (-1.0, -1.0)]])
        self.assertEqual(layers[0]["ends"], [[(-2.0, 2.0), (42.0, 2.0), (42.0, -2.0), (-2.0, -2.0)]])

    def test_a_cap_of_none_does_not_run_past_the_ends(self):
        start = self.records('lineStyle="1" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0))
        layers = self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(40, 40, cap=1), start, start)
        self.assertEqual(layers[0]["starts"], [[(0.0, 1.0), (20.0, 1.0), (20.0, -1.0), (0.0, -1.0)]])

    def test_a_right_angle_corner_is_filled_by_the_two_rectangles(self):
        start = self.records('lineStyle="1" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0), (0, 400))
        layers = self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(40, 40), start, start)
        first, second = layers[0]["starts"]
        # the first runs 1 pixel past the corner (20, 0), the second starts 1 pixel before it
        self.assertEqual(max(x for x, _ in first), 21.0)
        self.assertEqual(min(y for _, y in second), -1.0)

    def test_a_stroke_with_no_width_or_no_alpha_gives_no_layer(self):
        start = self.records('lineStyle="1" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0))
        self.assertEqual(self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(0, 0), start, start), [])
        self.assertEqual(self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(40, 40, (255, 255, 255, 0)), start, start), [])

    def test_a_segment_with_no_length_at_one_end_still_pairs(self):
        start = self.records('lineStyle="1" stateLineStyle="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (0, 0))
        end = self.records('stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0))
        layers = self.layers("<morphFillStyles><fillStyles/></morphFillStyles>", self.line(40, 40), start, end)
        self.assertEqual((len(layers[0]["starts"]), len(layers[0]["ends"])), (1, 1))
        # the start has a direction (that of the end): a rectangle 2 pixels thick and 2 long (the ends past the point)
        xs = sorted(x for x, _ in layers[0]["starts"][0])
        self.assertEqual((xs[0], xs[-1]), (-1.0, 1.0))

    def test_the_end_of_a_shape_that_collapsed_has_no_moves_and_still_pairs(self):
        # two contours at the start (two moves), the end keeps one move: the edges pair up
        start = self.records('fillStyle0="1" stateFillStyle0="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', *self.SQUARE,
                             (400, 0), (0, 400), (-400, 0), (0, -400), moves=[(4, 2000, 0)])
        end = self.records('stateMoveTo="true" moveDeltaX="500" moveDeltaY="500"', *([(20, 0), (0, 20), (-20, 0), (0, -20)] * 2))
        layers = self.layers(self.fill((0, 0, 0, 255), (0, 0, 0, 255)), self.NO_LINE, start, end)
        self.assertEqual(len(layers), 1)
        self.assertEqual(len(layers[0]["starts"]), 2)
        self.assertEqual(layers[0]["ends"][1][0], (25.0, 25.0))  # the second contour starts where the pen is

    def test_ends_that_do_not_pair_up_give_nothing(self):
        start = self.records('fillStyle0="1" stateFillStyle0="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', *self.SQUARE)
        end = self.records('stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', (400, 0), (0, 400), (-400, 0))
        self.assertEqual(self.layers(self.fill((0, 0, 0, 255), (0, 0, 0, 255)), self.NO_LINE, start, end), [])

    def test_a_fully_transparent_fill_gives_no_layer(self):
        start = self.records('fillStyle0="1" stateFillStyle0="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', *self.SQUARE)
        self.assertEqual(self.layers(self.fill((0, 0, 0, 0), (9, 9, 9, 0)), self.NO_LINE, start, start), [])

    def test_a_morph_character_carries_its_layers(self):
        bounds = '<%s Xmin="0" Ymin="0" Xmax="800" Ymax="400"/>'
        start = self.records('fillStyle0="1" stateFillStyle0="true" stateMoveTo="true" moveDeltaX="0" moveDeltaY="0"', *self.SQUARE)
        xml = ('<item type="DefineMorphShapeTag" characterId="8">' + bounds % "startBounds" + bounds % "endBounds"
               + self.fill((1, 2, 3, 255), (1, 2, 3, 255)) + self.NO_LINE
               + "<startEdges>%s</startEdges><endEdges>%s</endEdges></item>" % (start, start))
        movie = swfmodel.Movie()
        swfmodel._read_character(ET.fromstring(xml), movie)
        self.assertEqual(len(movie.characters[8].layers), 1)


if __name__ == "__main__":
    unittest.main()
