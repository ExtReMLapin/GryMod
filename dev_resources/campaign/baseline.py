"""The baseline: objectives derived by rules from the entity lump of every campaign map of Half-Life 2, Episode One and Episode Two.
Only facts read from the maps are used (entity names, outputs, origins). The titles and descriptions are written here, in our own words.
`derive_all(maps)` takes {(game, map): (entities, models)} (see bsp_ents.py) and returns {(game, map): (objectives, secrets, fail_events)}.
"""
import re
import bsp_ents as B   # noqa: F401  (the readers are used by build_campaign.py; the constants below are the rules)

MAPID_BASE = 1234   # Entity:MapCreationID() = the entity's number in the lump + 1234 (the wiki says "believed to start at 1234"; to check in the game: one call)

# ---- campaign visit order (facts; cross-checked below against the hl2c NEXT_MAP table when present) ----
def seq(prefix, names): return [prefix + n for n in names]
SEQ = {
 'hl2': seq('d1_trainstation_', ['01','02','03','04','05','06']) + seq('d1_canals_', ['01','01a','02','03','05','06','07','08','09','10','11','12','13'])
        + ['d1_eli_01','d1_eli_02','d1_town_01','d1_town_01a','d1_town_02','d1_town_03','d1_town_02','d1_town_02a','d1_town_04','d1_town_05','d2_coast_01']
        + seq('d2_coast_', ['03','04','05','07','08','07','09','10','11','12']) + seq('d2_prison_', ['01','02','03','04','05','06','07','08'])
        + seq('d3_c17_', ['01','02','03','04','05','06a','06b','07','08','09','10a','10b','11','12','12b','13']) + seq('d3_citadel_', ['01','02','03','04','05']) + ['d3_breen_01'],
 'ep1': ['ep1_citadel_00','ep1_citadel_01','ep1_citadel_02','ep1_citadel_02b','ep1_citadel_03','ep1_citadel_04','ep1_c17_00','ep1_c17_00a','ep1_c17_01','ep1_c17_02','ep1_c17_02b','ep1_c17_02a','ep1_c17_05','ep1_c17_06'],
 'ep2': seq('ep2_outland_', ['01','01a','02','03','04','02','05','06','06a','07','08','09','10','10a','11','11a','11b','12','12a']),
}
def successors(game, m):
    s = SEQ[game]; out = set()
    for i, x in enumerate(s):
        if x == m and i + 1 < len(s): out.add(s[i+1])
    return out

WEAPON_NAME = {'weapon_crowbar':'Crowbar','weapon_pistol':'Pistol','weapon_smg1':'SMG','weapon_shotgun':'Shotgun','weapon_ar2':'Pulse Rifle','weapon_357':'.357 Magnum',
  'weapon_physcannon':'Gravity Gun','weapon_crossbow':'Crossbow','weapon_rpg':'Rocket Launcher','weapon_frag':'Grenade','weapon_bugbait':'Bug Bait',
  'weapon_annabelle':'Annabelle','weapon_stunstick':'Stun Baton','weapon_slam':'SLAM','weapon_striderbuster':'Magnusson Device'}
# classes that are only ammo / loadout noise for objective purposes
LOADOUT_NAMES = re.compile(r'^(global_newgame|player_spawn_items|spawn_?items|start_?items|startobjects|loaditems|new_game_items|player_items|start_item)', re.I)
VEH_SCRIPT = [('airboat','Airboat'),('jeep_test','Buggy'),('jalopy','Jalopy'),('jeep','Buggy')]   # vehiclescript substrings -> name

# achievement events that are story progress (our own words). Others are collectibles (secrets) or challenges.
MILESTONE = {
 'ACHIEVEMENT_EVENT_HL2_GET_CROWBAR':      ('Pick up the crowbar', 'A crowbar is lying here. Take it.', True),
 'ACHIEVEMENT_EVENT_HL2_GET_AIRBOAT':      ('Get the airboat', 'A boat is waiting for you. Climb in.', True),
 'ACHIEVEMENT_EVENT_HL2_GET_AIRBOATGUN':   ('Arm the airboat', 'Have a stronger gun fitted to your boat.', True),
 'ACHIEVEMENT_EVENT_HL2_KILL_CHOPPER':     ('Bring down the chopper', 'The helicopter keeps hunting you. Shoot it down.', True),
 'ACHIEVEMENT_EVENT_HL2_GET_GRAVITYGUN':   ('Get the gravity gun', 'Receive the new tool in the lab.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_CEMETERY':    ('Fight through the cemetery', 'Reach the far end of the graveyard alive.', True),
 'ACHIEVEMENT_EVENT_HL2_KILL_ODESSAGUNSHIP': ('Destroy the gunship', 'A gunship attacks the outpost. Bring it down.', True),
 'ACHIEVEMENT_EVENT_HL2_ENTER_NOVAPROSPEKT': ('Destroy the gunships', 'Take down the gunships guarding the prison.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_TURRETSTANDOFF2': ('Clear the turret room', 'Break the turret ambush.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_TOXICTUNNEL': ('Get through the toxic tunnel', 'Cross the poisoned tunnel.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_PLAZASTANDOFF': ('Win the plaza standoff', 'Hold out in the plaza.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_SUPRESSIONDEVICE': ('Switch off the suppression device', 'Shut the device down at its switches.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_C1713STRIDERSTANDOFF': ('Destroy the striders', 'Beat the strider attack.', True),
 'ACHIEVEMENT_EVENT_HL2_BEAT_GAME':        ('Destroy the dark energy core', 'Finish the fight.', True),
 'ACHIEVEMENT_EVENT_HL2_ESCAPE_APARTMENTRAID': ('Escape the raid', 'Get away from the police.', True),
 'ACHIEVEMENT_EVENT_HL2_PUT_CANINTRASH':   ('Put the can in the bin', 'The cop wants the can in the trash can.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_ANTLIONINVASION': ('Hold off the antlions', 'Survive the antlion attack.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_ANTLIONGUARDS': ('Defeat the antlion guards', 'Beat the big antlions.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_HUNTERAMBUSH': ('Survive the hunter ambush', 'Beat the hunters.', True),
 'ACHIEVEMENT_EVENT_EP2_KILL_COMBINECANNON': ('Cut the cannon power', 'Switch off the cannon.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_WHITEFORESTINN': ('Defend the inn', 'Hold the inn against the attack.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_MISSILESILO2': ('Close the silo doors', 'Seal the silo.', True),
 'ACHIEVEMENT_EVENT_EP2_BEAT_GAME':        ('Stop the Combine strike', 'Hold on until the rocket is launched.', True),
}
# challenges / jokes: no objective. Everything with CACHE (lambda / web / radar) and GMAN / VORTIGAUNTCAVE / HEVFACEPLATE is a secret.
def is_secret(ev):
    return any(k in ev for k in ('LAMDACACHE', 'WEBCACHE', 'RADARCACHE', 'GMAN_', 'VORTIGAUNTCAVE', 'HEVFACEPLATE'))

def centre(models, kv):
    if 'origin' in kv: return [float(v) for v in kv['origin'].split()]
    m = kv.get('model', '')
    if m.startswith('*') and int(m[1:]) < len(models):
        mn, mx = models[int(m[1:])]
        return [round((a + c) / 2, 1) for a, c in zip(mn, mx)]
    return None

def fmt_ent(ep, name, idx, x):
    kv = x['kv']
    keys = ['classname','targetname','origin','map','landmark','spawnflags','AchievementEvent','vehiclescript','message','hammerid']
    return '[%s/%s #%d] ' % (ep, name, idx) + ' '.join('%s=%s' % (k, kv[k]) for k in keys if k in kv)

def firers(ents, tname):
    if not tname: return []
    return [(y['kv'].get('classname'), y['kv'].get('targetname', ''), o[0], o[2]) for y in ents for o in y['outs'] if o[1] == tname]

def derive(game, name, ents, models):
    objs, secrets, fails, seen_ids = [], [], [], set()
    succ = successors(game, name)
    # entities that exist only as members of a point_template that logic_auto fires at map start / new game = the loadout, not a world pickup
    auto_fired = {o[1] for x in ents if x['kv'].get('classname') == 'logic_auto' for o in x['outs'] if o[2] == 'ForceSpawn'}
    templ = set()
    for x in ents:
        if x['kv'].get('classname') == 'point_template' and (x['kv'].get('targetname', '') in auto_fired or LOADOUT_NAMES.match(x['kv'].get('targetname', ''))):
            for k, v in x['kv'].items():
                if k.startswith('Template'): templ.add(v)
    def add(o):
        base = o['id']; n = 2
        while o['id'] in seen_ids: o['id'] = '%s.%d' % (base, n); n += 1
        seen_ids.add(o['id']); objs.append(o)
    for idx, x in enumerate(ents):
        kv = x['kv']; c = kv.get('classname', ''); tn = kv.get('targetname', '')
        mapid = MAPID_BASE + idx
        # R1 exit
        if c == 'trigger_changelevel' and kv.get('map') and kv['map'] != name:
            fwd = kv['map'] in succ   # last map of a game: no forward exit (the game ends)
            if not fwd: continue
            noTouch = int(kv.get('spawnflags', '0') or 0) & 2
            if noTouch and tn: comp = {'kind': 'input', 'entity': tn, 'input': 'ChangeLevel'}
            else: comp = {'kind': 'changelevel', 'target': kv['map'], 'mapid': mapid}
            add({'id': 'hl2c.%s.exit%s' % (name, '' if len(succ) <= 1 else '.' + kv['map']), 'rule': 'R1_exit', 'primary': True,
                 'title': 'Reach the exit', 'description': 'Leave this area to continue to the next map.', 'pos': centre(models, kv), 'pos_quality': 'trigger_brush',
                 'complete': comp, 'next_map': kv['map'], 'ambiguous_exit': len(succ) > 1, 'evidence': [fmt_ent(game, name, idx, x)]})
        # R2 key weapons lying in the world
        elif c.startswith('weapon_') and c in WEAPON_NAME and tn not in templ and not LOADOUT_NAMES.match(tn):
            nopick = int(kv.get('spawnflags', '0') or 0) & 2
            if c not in ('weapon_frag',) and not nopick:
                add({'id': 'hl2c.%s.get_%s' % (name, c[7:]) + ('.' + tn if tn else '.m%d' % mapid), 'rule': 'R2_weapon', 'primary': False,
                     'title': 'Find the %s' % WEAPON_NAME[c], 'description': 'Pick up the %s lying here.' % WEAPON_NAME[c].lower(), 'pos': centre(models, kv), 'pos_quality': 'entity',
                     'complete': {'kind': 'pickup', 'class': c, 'entity': tn or None, 'mapid': mapid}, 'evidence': [fmt_ent(game, name, idx, x)] + ['    output %s -> %s.%s' % (o[0], o[1], o[2]) for o in x['outs'][:3]]})
        elif c == 'item_suit' and tn not in templ and not LOADOUT_NAMES.match(tn):
            add({'id': 'hl2c.%s.get_suit' % name, 'rule': 'R2_weapon', 'primary': False, 'title': 'Find the HEV suit', 'description': 'Pick up the protective suit.', 'pos': centre(models, kv), 'pos_quality': 'entity',
                 'complete': {'kind': 'pickup', 'class': 'item_suit', 'entity': tn or None, 'mapid': mapid}, 'evidence': [fmt_ent(game, name, idx, x)]})
        # R2b weapon handed over by a map command ("give weapon_x")
        for o in x['outs']:
            if o[2] == 'Command' and o[3].startswith('give weapon_') and o[3][5:] in WEAPON_NAME and o[3][5:] not in ('weapon_crowbar', 'weapon_pistol') or (o[2] == 'Command' and o[3] == 'give weapon_physcannon'):
                w = o[3][5:]
                if w in WEAPON_NAME and not LOADOUT_NAMES.match(tn or ''):
                    add({'id': 'hl2c.%s.give_%s' % (name, w[7:]), 'rule': 'R2b_give', 'primary': True, 'title': 'Get the %s' % WEAPON_NAME[w], 'description': 'Receive the %s here.' % WEAPON_NAME[w].lower(), 'pos': centre(models, kv), 'pos_quality': 'trigger_brush',
                         'complete': {'kind': 'pickup', 'class': w, 'entity': None, 'via_input': {'entity': o[1], 'input': 'Command', 'param': o[3]}}, 'evidence': [fmt_ent(game, name, idx, x), '    output %s -> %s.Command "%s"' % (o[0], o[1], o[3])]})
        # R3 vehicles (drivable by the player)
        if c in ('prop_vehicle_jeep', 'prop_vehicle_airboat'):
            vs = kv.get('vehiclescript', '').lower()
            if 'apc' in vs: continue
            vname = None
            for sub, nm in VEH_SCRIPT:
                if sub in vs: vname = nm; break
            if vname is None and c == 'prop_vehicle_airboat': vname = 'Airboat'
            if vname and (tn or True):
                add({'id': 'hl2c.%s.get_%s' % (name, vname.lower()), 'rule': 'R3_vehicle', 'primary': False, 'title': 'Find the %s' % vname, 'description': 'A %s is parked here. Get in.' % vname.lower(), 'pos': centre(models, kv), 'pos_quality': 'entity',
                     'complete': {'kind': 'enter_vehicle', 'class': c, 'entity': tn or None, 'mapid': mapid, 'output_in_map': [o[0] for o in x['outs'] if o[0] in ('PlayerOn', 'PlayerOff')]}, 'evidence': [fmt_ent(game, name, idx, x)]})
        # R4 milestones and secrets from logic_achievement
        if c == 'logic_achievement':
            ev = kv.get('AchievementEvent', '')
            fr = firers(ents, tn)
            comp = {'kind': 'input', 'entity': tn, 'input': 'FireEvent'}
            evid = [fmt_ent(game, name, idx, x)] + ['    fired by %s "%s" %s -> FireEvent' % (f[0], f[1], f[2]) for f in fr[:3]]
            if ev in MILESTONE:
                t, d, p = MILESTONE[ev]
                # the relay's own origin is a spot the mapper left anywhere (a corner of the room): where it happens is the trigger that fires it, when there is one
                at, quality = centre(models, kv), 'approx_logic_origin'
                for y in ents:
                    ky = y['kv']
                    if tn and ky.get('classname', '').startswith('trigger_') and ky.get('model', '').startswith('*') and any(o[1] == tn and o[2] == 'FireEvent' for o in y['outs']):
                        # a brush with an `origin` has its bounds relative to it
                        local = centre(models, {'model': ky['model']})
                        if local:
                            base = [float(v) for v in ky['origin'].split()] if 'origin' in ky else [0.0, 0.0, 0.0]
                            at, quality = [round(a + b, 1) for a, b in zip(base, local)], 'trigger_brush'
                            break
                add({'id': 'hl2c.%s.%s' % (name, ev.replace('ACHIEVEMENT_EVENT_', '').lower()), 'rule': 'R4_milestone', 'primary': p, 'title': t, 'description': d, 'pos': at, 'pos_quality': quality, 'complete': comp, 'evidence': evid})
            elif is_secret(ev):
                secrets.append({'id': 'hl2c.%s.secret.%s' % (name, ev.replace('ACHIEVEMENT_EVENT_', '').lower()), 'title': 'Hidden item' if 'CACHE' in ev else 'Sighting', 'pos': centre(models, kv), 'complete': comp, 'event': ev, 'evidence': evid})
        # R5 failure events: env_message GAMEOVER_*
        if c == 'env_message' and kv.get('message', '').startswith('GAMEOVER_'):
            fails.append({'entity': tn, 'input': 'ShowMessage', 'message': kv['message'], 'fired_by': [f[:2] for f in firers(ents, tn)][:3], 'evidence': [fmt_ent(game, name, idx, x)]})
    # R6: no primary objective? (never happens when an exit exists) -> keep list as is
    return objs, secrets, fails



def derive_all(maps):
    """maps: {(game, name): (ents, models)}. First pass: the rules on each map. Second pass: in campaign order, a weapon or a vehicle already seen is not offered again."""
    derived = {}
    for (game, name), (ents, models) in maps.items():
        derived[(game, name)] = derive(game, name, ents, models)
    for game in ('hl2', 'ep1', 'ep2'):
        order = []
        for m in SEQ[game] + sorted(n for (g, n) in derived if g == game):
            if m not in order and (game, m) in derived:
                order.append(m)
        seen = set()
        for m in order:
            objs, secrets, fails = derived[(game, m)]
            keep = []
            has_airboat_milestone = any(o['id'].endswith('get_airboat') and o['rule'] == 'R4_milestone' for o in objs)
            for o in objs:
                if o['rule'] in ('R2_weapon', 'R3_vehicle'):
                    key = o['complete'].get('class') if o['rule'] == 'R2_weapon' else o['title']
                    if key in seen:
                        continue
                    if o['rule'] == 'R3_vehicle' and o['title'] == 'Find the Airboat' and has_airboat_milestone:
                        seen.add(key)
                        continue
                    seen.add(key)
                if o['rule'] == 'R2b_give':
                    seen.add(o['complete']['class'])
                keep.append(o)
            # a weapon given by a command in this map counts as seen before its lying copy: drop duplicates inside the map
            gives = {o['complete']['class'] for o in keep if o['rule'] == 'R2b_give'}
            keep = [o for o in keep if not (o['rule'] == 'R2_weapon' and o['complete']['class'] in gives)]
            # a milestone that already says "get the crowbar / gravity gun" replaces the generic weapon objective of the same map
            implied = {o['id'].rsplit('.', 1)[-1]: 1 for o in keep if o['rule'] == 'R4_milestone'}
            drop_cls = {c for ev, c in (('get_crowbar', 'weapon_crowbar'), ('get_gravitygun', 'weapon_physcannon')) if any(i.endswith(ev) for i in implied)}   # (the prototype compared whole ids and never matched: the crowbar was listed twice)
            keep = [o for o in keep if not (o['rule'] in ('R2_weapon', 'R2b_give') and o['complete'].get('class') in drop_cls)]
            # order inside the map: gets, vehicles, milestones, exit last
            rank = {'R2_weapon': 0, 'R2b_give': 0, 'R3_vehicle': 1, 'R4_milestone': 2, 'R1_exit': 9}
            keep.sort(key=lambda o: rank[o['rule']])
            derived[(game, m)] = (keep, secrets, fails)
    return derived


# the maps that are not part of the campaign's route (menus, credits, cut content)
SKIP = re.compile(r'^(background|credits|intro|ep1_background|ep2_background)|_demo$|_camera$|^ep1_c17_01a$')
