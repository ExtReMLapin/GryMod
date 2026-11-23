"""Tests of the campaign data tools and of the data they ship.
Run:  python -m unittest discover -s dev_resources/campaign        (needs `pip install lupa`; the game's maps are NOT needed except by the last class,
which is skipped without them).

Each test says which change makes it fail."""
import itertools
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import emit_lua  # noqa: E402
import proofs  # noqa: E402
import waypoints as W  # noqa: E402
import build_campaign as BC  # noqa: E402
import bsp_ents as B  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
DATA = os.path.join(REPO, 'lua', 'grymod', 'campaign')


def ent(cls, name=None, origin=None, model=None, outs=(), **kv):
    d = {'classname': cls}
    if name:
        d['targetname'] = name
    if origin:
        d['origin'] = origin
    if model is not None:
        d['model'] = model
    d.update(kv)
    return {'kv': d, 'outs': [tuple(o) for o in outs]}


# models: index N -> (mins, maxs)
MODELS = [((0, 0, 0), (0, 0, 0)), ((-50, -50, 0), (50, 50, 100)), ((-5000, -5000, 0), (5000, 5000, 100)), ((-50, -50, 0), (50, 50, 100))]


class Emit(unittest.TestCase):
    def test_vector_string_escaping_and_field_order(self):
        # fails if: a Vector is written as a table, a quote is not escaped, or `via` comes after `complete`
        o = {'fields': {'id': 'a"b', 'title': 'T', 'description': '', 'primary': True, 'pos': (1.0, 2.5, -3), 'via': [(4, 5, 6)],
                        'complete': {'kind': 'input', 'entity': 'e', 'input': 'Open'}}, 'notes': ['why']}
        text = '\n'.join(emit_lua.emit_objective(o))
        self.assertIn('id = "a\\"b"', text)
        self.assertIn('pos = Vector(1, 2.5, -3)', text)
        self.assertIn('via = {Vector(4, 5, 6)}', text)
        self.assertLess(text.index('via ='), text.index('complete ='))
        self.assertIn('-- why', text)

    def test_non_ascii_is_refused(self):
        # fails if: a character that the data files must not hold goes through
        with self.assertRaises(ValueError):
            emit_lua.lua_string('café')


class Proofs(unittest.TestCase):
    ENTS = [ent('trigger_once', 'trig', model='*1', outs=[('OnTrigger', 'relay', 'Trigger', '', 0.0, 1)]), ent('logic_relay', 'relay')]

    def test_true_proofs_pass_and_false_ones_fail(self):
        # fails if: the checker accepts a wrong class, name, place, key value or output (a false fact would be shipped)
        def n(**p):
            return len(proofs.check(p, self.ENTS, MODELS))
        self.assertEqual(n(**{'class': 'trigger_once', 'name': 'trig'}), 1)
        self.assertEqual(n(**{'class': 'trigger_once', 'pos': (0, 0, 50)}), 1)
        self.assertEqual(n(**{'class': 'trigger_once', 'out': ['OnTrigger', 'relay', 'Trigger']}), 1)
        self.assertEqual(n(**{'class': 'trigger_multiple'}), 0)
        self.assertEqual(n(**{'name': 'nope'}), 0)
        self.assertEqual(n(**{'class': 'trigger_once', 'pos': (9, 9, 9)}), 0)
        self.assertEqual(n(**{'class': 'trigger_once', 'out': ['OnTrigger', 'relay', 'Kill']}), 0)
        self.assertEqual(n(**{'class': 'logic_relay', 'kv': {'targetname': 'other'}}), 0)


class Ways(unittest.TestCase):
    def test_shortest_way_matches_brute_force(self):
        # fails if: the search returns an order that is not the shortest (the display would send the player back and forth)
        pts = [(0, 0, 0), (1000, 0, 0), (200, 50, 0), (600, -40, 0), (900, 300, 0)]
        start, goal = (-100, 0, 0), (1200, 100, 0)

        def length(order):
            path = [start] + [pts[i] for i in order] + [goal]
            return sum(W.dist(a, b) for a, b in zip(path, path[1:]))
        best = min(itertools.permutations(range(len(pts))), key=length)
        got = W.shortest_way(pts, start, goal)
        self.assertAlmostEqual(length(got), length(best), places=6)
        self.assertEqual(sorted(got), list(range(len(pts))))

    def test_shortest_way_without_a_start_ends_at_the_goal(self):
        # fails if: a missing start breaks the search or the last waypoint is not the one nearest the goal on the way
        pts = [(0, 0, 0), (100, 0, 0), (200, 0, 0)]
        self.assertEqual(W.shortest_way(pts, None, (300, 0, 0)), [0, 1, 2])
        self.assertEqual(W.shortest_way([], None, (0, 0, 0)), [])

    def logic(self):
        return [
            ent('info_player_start', origin='-2000 0 0'),
            ent('trigger_once', 'gate_a', model='*1', outs=[('OnTrigger', 'relay_a', 'Trigger', '', 0.0, 1)]),                   # 0: a gate, 1 relay away
            ent('logic_relay', 'relay_a', outs=[('OnTrigger', 'achv', 'FireEvent', '', 0.0, 1)]),
            ent('logic_achievement', 'achv', origin='0 0 0', AchievementEvent='ACHIEVEMENT_EVENT_HL2_BEAT_CEMETERY'),
            ent('trigger_multiple', 'huge', model='*2', outs=[('OnTrigger', 'achv', 'FireEvent', '', 0.0, 1)]),                  # too big: no centre
            ent('trigger_once', 'unrelated', model='*3', outs=[('OnTrigger', 'other', 'Kill', '', 0.0, 1)]),                      # reaches no story step
        ]

    def test_find_gates_follows_relays_and_ignores_the_rest(self):
        # fails if: a trigger that reaches the story step through a relay is missed, a trigger the size of the level is kept, or an unrelated trigger is taken
        ents = self.logic()
        # the models: *1 and *3 are small; give them different places through origin offsets
        models = [((0, 0, 0), (0, 0, 0)), ((950, -50, 0), (1050, 50, 100)), ((-5000, -5000, 0), (5000, 5000, 100)), ((3000, 0, 0), (3100, 100, 100))]
        gates = W.find_gates(ents, models, ['achv'])
        self.assertEqual([(g['class'], g['pos']) for g in gates], [('trigger_once', (1000.0, 0.0, 50.0))])
        self.assertEqual(gates[0]['out'], ['OnTrigger', 'relay_a', 'Trigger'])
        self.assertEqual(gates[0]['depth'], 1)

    def test_depth_limit(self):
        # fails if: a chain of relays longer than the limit is followed (guessing)
        ents = [ent('trigger_once', 'g', model='*1', outs=[('OnTrigger', 'r1', 'Trigger', '', 0, 1)])]
        for i in range(1, 6):
            ents.append(ent('logic_relay', 'r%d' % i, outs=[('OnTrigger', 'r%d' % (i + 1) if i < 5 else 'sink', 'Trigger', '', 0, 1)]))
        ents.append(ent('logic_achievement', 'sink'))
        self.assertEqual(W.find_gates(ents, MODELS, ['sink']), [])

    def test_exit_waypoints_filtering_and_order(self):
        # fails if: a waypoint on the exit or the start is kept, the arrival is not the landmark of the way back, or the order is not the shortest way
        models = [((0, 0, 0), (0, 0, 0)), ((950, -50, 0), (1050, 50, 100)), ((-5000, -5000, 0), (5000, 5000, 100)), ((1900, -50, 0), (2000, 50, 100)), ((-1990, -50, 0), (-1900, 50, 100)), ((2950, -50, 0), (3050, 50, 100))]
        ents = [
            ent('trigger_changelevel', map='prev_map', landmark='back'), ent('info_landmark', 'back', origin='-2000 0 0'),
            ent('trigger_once', 'g1', model='*3', outs=[('OnTrigger', 'achv2', 'FireEvent', '', 0, 1)]),     # at x=1950
            ent('trigger_once', 'g2', model='*1', outs=[('OnTrigger', 'achv', 'FireEvent', '', 0, 1)]),      # at x=1000
            ent('trigger_once', 'near_start', model='*4', outs=[('OnTrigger', 'achv', 'FireEvent', '', 0, 1)]),  # at x=-1945: within 150 of the landmark
            ent('trigger_once', 'near_exit', model='*5', outs=[('OnTrigger', 'achv', 'FireEvent', '', 0, 1)]),   # at x=3000: on the exit
            ent('logic_achievement', 'achv'), ent('logic_achievement', 'achv2'),
        ]
        objs = [{'rule': 'R4_milestone', 'complete': {'kind': 'input', 'entity': 'achv'}, 'pos': (0, 0, 0)},
                {'rule': 'R4_milestone', 'complete': {'kind': 'input', 'entity': 'achv2'}, 'pos': (0, 0, 0)}]
        exit_obj = {'rule': 'R1_exit', 'complete': {'kind': 'changelevel', 'target': 'next'}, 'pos': (3000.0, 0.0, 50.0)}
        out = W.waypoints_for_exit('hl2', 'm', ents, models, objs + [exit_obj], exit_obj, {'next'})
        self.assertEqual([w['pos'][0] for w in out], [1000.0, 1950.0])
        for w in out:
            self.assertTrue(proofs.check(w['proof'], ents, models))
        # extras are merged, checked like the others, and filtered
        extra = {'class': 'trigger_once', 'pos': (1500.0, 0.0, 50.0), 'out': ['OnTrigger', 'x', 'Kill']}
        out2 = W.waypoints_for_exit('hl2', 'm', ents, models, objs + [exit_obj], exit_obj, {'next'}, [extra])
        self.assertEqual([w['pos'][0] for w in out2], [1000.0, 1500.0, 1950.0])

    def test_no_gate_no_waypoint(self):
        # fails if: a map without a certain waypoint gets a guessed one
        exit_obj = {'rule': 'R1_exit', 'complete': {'kind': 'changelevel', 'target': 'next'}, 'pos': (3000.0, 0.0, 50.0)}
        self.assertEqual(W.waypoints_for_exit('hl2', 'm', [ent('info_player_start', origin='0 0 0')], MODELS, [exit_obj], exit_obj, {'next'}), [])

    def test_at_most_twelve_waypoints(self):
        # fails if: the cap that keeps the exact search fast and the data short is gone
        ents = [ent('logic_achievement', 'achv')]
        models = [((0, 0, 0), (0, 0, 0))]
        for i in range(20):
            models.append(((500 * i, 0, 0), (500 * i + 50, 50, 50)))
            ents.append(ent('trigger_once', 'g%d' % i, model='*%d' % (i + 1), outs=[('OnTrigger', 'achv', 'FireEvent', '', 0, 1)]))
        objs = [{'rule': 'R4_milestone', 'complete': {'kind': 'input', 'entity': 'achv'}, 'pos': (0, 0, 0)}]
        exit_obj = {'rule': 'R1_exit', 'complete': {'kind': 'changelevel', 'target': 'next'}, 'pos': (20000.0, 0.0, 0.0)}
        # MAX_PER_SINK limits one step to 3 gates; many steps give many gates
        objs = [{'rule': 'R4_milestone', 'complete': {'kind': 'input', 'entity': 'achv'}, 'pos': (0, 0, 0)}]
        out = W.waypoints_for_exit('hl2', 'm', ents, models, objs + [exit_obj], exit_obj, {'next'})
        self.assertLessEqual(len(out), W.MAX_GATES)


class Build(unittest.TestCase):
    def test_baseline_and_curated_maps_are_written_with_their_comments(self):
        # fails if: a curated map does not replace its baseline, a false proof is not reported, or the proof comments are not in the file
        ents = [ent('trigger_changelevel', map='m2', landmark='lm', model='*1'), ent('weapon_rpg', 'rpg', origin='10 20 30')]
        models = [((0, 0, 0), (0, 0, 0)), ((100, 100, 0), (200, 200, 50))]
        derived = {('hl2', 'm1'): ([{'id': 'hl2c.m1.exit', 'rule': 'R1_exit', 'primary': True, 'title': 'Reach the exit', 'description': 'd', 'pos': [150, 150, 25],
                                     'complete': {'kind': 'changelevel', 'target': 'm2', 'mapid': 5}, 'evidence': ['[hl2/m1 #0] classname=trigger_changelevel']}], [], [])}
        curated = {('hl2', 'm1'): {'note': 'a note', 'objectives': [
            dict(id='c.rpg', title='Take it', description='d', primary=True, pos=(10, 20, 30), complete=dict(kind='pickup', **{'class': 'weapon_rpg'}),
                 proof=[{'class': 'weapon_rpg', 'name': 'rpg'}, {'class': 'weapon_rpg', 'name': 'wrong'}])], 'fail_events': []}}
        texts, report = BC.build({('hl2', 'm1'): (ents, models)}, derived, curated)
        text = texts[('hl2', 'm1')]
        self.assertIn('c.rpg', text)
        self.assertNotIn('hl2c.m1.exit', text)
        self.assertIn('proof true', text)
        self.assertIn('proof FALSE', text)
        self.assertEqual(len(report['false_proofs']), 1)
        self.assertEqual(report['curated'], 1)


class ShippedData(unittest.TestCase):
    """The files in lua/grymod/campaign are checked by the REAL validator of the addon (sv_campaign_core.lua), run in LuaJIT."""

    @classmethod
    def setUpClass(cls):
        from lupa.luajit21 import LuaRuntime
        cls.lua = LuaRuntime(unpack_returned_tuples=True)
        cls.lua.execute('''
            local VMT = {}
            VMT.__index = VMT
            function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VMT) end
            function isvector(v) return type(v) == "table" and getmetatable(v) == VMT end
            function isstring(v) return type(v) == "string" end
            function isnumber(v) return type(v) == "number" end
            function istable(v) return type(v) == "table" end
            function isfunction(v) return type(v) == "function" end
            function isbool(v) return type(v) == "boolean" end
            GryMod = {}
            assert(loadfile(...))()
            C = GryMod.Campaign
            function check(path)
                local chunk, err = loadfile(path)
                if not chunk then return "does not parse: " .. tostring(err) end
                local data = chunk()
                if type(data) ~= "table" then return "does not return a table" end
                local list, why = C.CheckList(data.objectives)
                if not list then return why end
                local _, problems = C.Resolve(list)
                if problems[1] then return problems[1] end
                for i, f in ipairs(data.fail_events or {}) do
                    local clean, w = C.CheckCompletion({kind = "input", entity = f.entity, input = f.input}, C.FailKinds)
                    if not clean then return "fail_events #" .. i .. ": " .. w end
                end
                local primary = false
                for _, d in ipairs(list) do if d.primary and not d.secret then primary = true end end
                return nil, #list
            end
        ''', os.path.join(REPO, 'lua', 'grymod', 'server', 'sv_campaign_core.lua').replace('\\', '/'))

    def files(self):
        out = []
        for game in sorted(os.listdir(DATA)):
            for f in sorted(os.listdir(os.path.join(DATA, game))):
                out.append((game, f[:-4], os.path.join(DATA, game, f).replace('\\', '/')))
        return out

    def test_every_file_passes_the_addons_own_check(self):
        # fails if: a generated or hand-written file has a bad field, a duplicate id, a chain that cannot start, or a waypoint list that is too long
        files = self.files()
        self.assertGreater(len(files), 90)
        for game, name, path in files:
            err, _ = self.lua.globals().check(path)
            self.assertIsNone(err, '%s/%s: %s' % (game, name, err))

    def test_file_name_is_the_map_and_the_folder_is_the_game(self):
        # fails if: a file sits in the wrong game folder or its name is not lower case (the Workshop refuses it; the runtime looks it up by map name)
        for game, name, _ in self.files():
            self.assertIn(game, ('hl2', 'ep1', 'ep2'))
            self.assertEqual(name, name.lower())
            self.assertTrue(name.startswith({'hl2': 'd', 'ep1': 'ep1_', 'ep2': 'ep2_'}[game]), name)

    def test_curated_maps_keep_their_proofs_and_waypoints(self):
        # fails if: a curated file is overwritten by the baseline, or loses its proof comments or its waypoints
        with open(os.path.join(DATA, 'hl2', 'd2_coast_03.lua'), encoding='utf-8') as f:
            text = f.read()
        self.assertIn('Written by hand', text)
        self.assertIn('proof true', text)
        self.assertNotIn('proof FALSE', text)
        self.assertIn('via = {', text)

    def test_no_data_file_holds_a_non_ascii_character(self):
        # fails if: a file would not be safe to ship
        for _, name, path in self.files():
            with open(path, encoding='ascii') as f:
                f.read()


@unittest.skipUnless(all(os.path.isdir(r) for r in B.ROOTS.values()), 'the game\'s maps are not here')
class AgainstTheMaps(unittest.TestCase):
    def test_every_proof_is_true_and_the_files_are_what_the_maps_give(self):
        # fails if: a proof is false, or a shipped file is not what build_campaign.py makes now (someone edited a generated file, or the rules changed without a rebuild)
        maps = BC.read_maps()
        texts, report = BC.build(maps)
        self.assertEqual(report['false_proofs'], [])
        for (game, name), text in texts.items():
            path = os.path.join(DATA, game, name + '.lua')
            self.assertTrue(os.path.exists(path), path)
            with open(path, encoding='utf-8', newline='') as f:
                self.assertEqual(f.read(), text, name)

    def test_extra_waypoints_are_facts_of_the_maps(self):
        # fails if: a hand-added waypoint does not exist in the map
        from extra_waypoints import EXTRA
        maps = BC.read_maps()
        for name, plist in EXTRA.items():
            for (g, n), (ents, models) in maps.items():
                if n == name:
                    for pr in plist:
                        self.assertTrue(proofs.check(pr, ents, models), (name, pr))


if __name__ == '__main__':
    unittest.main()
