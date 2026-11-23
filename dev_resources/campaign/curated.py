"""The maps whose objectives are written by hand (our own words), with the PROOFS of what they say. Every objective carries `proof` entries; build_campaign.py
reads the map again and FAILS if one is false. A curated map replaces the generated baseline of the same map completely.
proof keys: class, name (targetname), pos (x,y,z within 1.5 units of origin or brush centre), kv {key: value}, out [output, target, input]
The meaning of each step (what the player does when the event fires) is DEDUCED from the entity names and the chain of outputs: it has to be walked once in the game."""

MAPS = {}

# ---------------------------------------------------------------- d1_trainstation_01 (story chain made of doors, relays and scenes)
MAPS[('hl2', 'd1_trainstation_01')] = {
 'note': 'Arrival and checkpoint chain. Semantics DEDUCED from entity names and outputs; objective texts are ours.',
 'objectives': [
  dict(id='hl2c.d1_trainstation_01.checkpoint', title='Go through the checkpoint', primary=True, pos=(-4211, -492, 28),
       description='Follow the arrivals to the guards at the end of the hall.',
       complete=dict(kind='input', entity='gordon_cop_template', input='ForceSpawn'),
       proof=[dict(**{'class': 'trigger_once', 'pos': (-4211, -492, 28), 'out': ['OnTrigger', 'gordon_cop_template', 'ForceSpawn']}),
              dict(**{'class': 'point_template', 'name': 'gordon_cop_template'})]),
  dict(id='hl2c.d1_trainstation_01.back_room', title='Get out of the back room', primary=True, pos=(-3497, -460, 22), after='hl2c.d1_trainstation_01.checkpoint',
       description='You are locked in. Wait until a way out opens and leave through the door.',
       complete=dict(kind='input', entity='barney_door_2', input='Open'),
       proof=[dict(**{'class': 'prop_door_rotating', 'name': 'barney_door_2', 'pos': (-3497, -460, 22)}),
              dict(**{'class': 'logic_choreographed_scene', 'name': 'security_intro_01', 'out': ['OnTrigger1', 'barney_door_2', 'Open']})]),
  dict(id='hl2c.d1_trainstation_01.storage_room', title='Leave through the storage room', primary=True, pos=(-3337, -132, 22), after='hl2c.d1_trainstation_01.back_room',
       description='Go through the storage room door and out of the building.',
       complete=dict(kind='input', entity='storage_room_door', input='Open'),
       proof=[dict(**{'class': 'prop_door_rotating', 'name': 'storage_room_door', 'pos': (-3337, -132, 22)}),
              dict(**{'class': 'logic_choreographed_scene', 'name': 'security_03', 'out': ['OnTrigger3', 'storage_room_door', 'Open']})]),
  dict(id='hl2c.d1_trainstation_01.exit', title='Reach the exit', primary=True, pos=(-3104, -152, 0), after='hl2c.d1_trainstation_01.storage_room', via=[(-3497, -460, 22), (-3337, -132, 22)],
       description='Leave this area to continue to the next map.',
       complete=dict(kind='changelevel', target='d1_trainstation_02'),
       proof=[dict(**{'class': 'trigger_changelevel', 'pos': (-3104, -152, 0), 'kv': {'map': 'd1_trainstation_02', 'landmark': 'trainstation_01_to_02'}})]),
  dict(id='hl2c.d1_trainstation_01.soda', title='Try the soda machine', primary=False, pos=(-4117.13, -1127.13, 21),
       description='A drinks machine stands against the wall. Press its button.',
       complete=dict(kind='use', entity='soda_machine_1'),
       proof=[dict(**{'class': 'func_button', 'name': 'soda_machine_1', 'pos': (-4117.13, -1127.13, 21), 'out': ['OnPressed', 'soda_machine_1_branch', 'Test']})]),
 ],
 'fail_events': [],
}

# ---------------------------------------------------------------- d1_canals_01 (open level: one trigger-driven step, a charger, the exit)
MAPS[('hl2', 'd1_canals_01')] = {
 'note': 'Long linear level. Few scripted steps: the boxcar scene is the only named progress event. Charger objective uses the use hook.',
 'objectives': [
  dict(id='hl2c.d1_canals_01.charger', title='Recharge at the health station', primary=False, pos=(576, -7776, -74.065),
       description='A wall charger heals you while you hold the use key.',
       complete=dict(kind='use', at=(576, -7776, -74.065), **{'class': 'item_healthcharger'}),  # no name: found by its class and its place
       proof=[dict(**{'class': 'item_healthcharger', 'pos': (576, -7776, -74.065), 'kv': {'hammerid': '3082385'}})]),
  dict(id='hl2c.d1_canals_01.boxcar', title='Reach the boxcar', primary=True, pos=(736, 2158, -56),
       description='Two allies are waiting in a rail car at the far end.',
       complete=dict(kind='input', entity='boxcar_human', input='StartScripting'),
       proof=[dict(**{'class': 'trigger_once', 'pos': (736, 2158, -55.99), 'out': ['OnTrigger', 'boxcar_human', 'StartScripting']}),
              dict(**{'class': 'npc_citizen', 'name': 'boxcar_human', 'pos': (684, 2668, -41)})]),
  dict(id='hl2c.d1_canals_01.exit', title='Reach the exit', primary=True, pos=(768, 3024, 0), after='hl2c.d1_canals_01.boxcar', via=[(736, 2158, -56)],
       description='Leave this area to continue to the next map.',
       complete=dict(kind='changelevel', target='d1_canals_01a'),
       proof=[dict(**{'class': 'trigger_changelevel', 'pos': (768, 3024, 0), 'kv': {'map': 'd1_canals_01a', 'landmark': 'canals_trans_0101a'}})]),
 ],
 'fail_events': [],
}

# ---------------------------------------------------------------- d2_coast_03 (vehicle, ally, set-piece fight, fail events)
MAPS[('hl2', 'd2_coast_03')] = {
 'note': 'Vehicle, outpost, rocket launcher, gunship. Two ways to fail are defined by the map itself (env_message GAMEOVER_*).',
 'objectives': [
  dict(id='hl2c.d2_coast_03.buggy', title='Get in the buggy', primary=True, pos=(-6913.57, -13638.2, 1026),
       description='The buggy is parked by the start. Drive it along the coast.',
       complete=dict(kind='enter_vehicle', entity='jeep', **{'class': 'prop_vehicle_jeep'}),
       fail=dict(kind='input', entity='jeep_lost_in_water', input='ShowMessage', why='the buggy was lost in the water'),
       proof=[dict(**{'class': 'prop_vehicle_jeep', 'name': 'jeep', 'pos': (-6913.57, -13638.2, 1026), 'out': ['PlayerOn', 'antlion_spawner_injeep_relay', 'Trigger']}),
              dict(**{'class': 'trigger_once', 'pos': (992, -2176, -160), 'out': ['OnTrigger', 'jeep_lost_in_water', 'ShowMessage']}),
              dict(**{'class': 'env_message', 'name': 'jeep_lost_in_water', 'kv': {'message': 'GAMEOVER_OBJECT'}})]),
  dict(id='hl2c.d2_coast_03.basement', title='Go down to the basement', primary=True, pos=(8894, 4064, 310), after='hl2c.d2_coast_03.buggy',
       description='Find the man in the outpost basement.',
       complete=dict(kind='input', entity='basement_gordon_first_entered', input='Trigger'),
       fail=dict(kind='input', entity='killed_critical_npc', input='ShowMessage', why='an ally died'),
       proof=[dict(**{'class': 'trigger_once', 'name': 'trigger_gordoninbasement', 'pos': (8894, 4064, 310), 'out': ['OnTrigger', 'basement_gordon_first_entered', 'Trigger']}),
              dict(**{'class': 'npc_citizen', 'name': 'rocketman', 'out': ['OnDeath', 'killed_critical_npc', 'ShowMessage']}),
              dict(**{'class': 'env_message', 'name': 'killed_critical_npc', 'kv': {'message': 'GAMEOVER_ALLY'}})]),
  dict(id='hl2c.d2_coast_03.rpg', title='Take the rocket launcher', primary=True, pos=(8515.57, 4303.08, 285), after='hl2c.d2_coast_03.basement', via=[(8894, 4064, 310)],
       description='A launcher is lying in the outpost. You will need it against what is coming.',
       complete=dict(kind='pickup', **{'class': 'weapon_rpg'}, entity='rpg_weapon'),
       proof=[dict(**{'class': 'weapon_rpg', 'name': 'rpg_weapon', 'pos': (8515.57, 4303.08, 285), 'out': ['OnPlayerPickup', 'first_train_rl', 'Trigger']})]),
  dict(id='hl2c.d2_coast_03.gunship', title='Destroy the gunship', primary=True, pos=(8247, 4387.3, 465), after='hl2c.d2_coast_03.rpg', via=[(8894, 4064, 310), (8515.57, 4303.08, 285)],
       description='A gunship is attacking the outpost. Bring it down.',
       complete=dict(kind='removed', entity='gunship1', also=dict(kind='input', entity='achievement_gunship', input='FireEvent')),
       proof=[dict(**{'class': 'npc_combinegunship', 'name': 'gunship1', 'out': ['OnDeath', 'achievement_gunship', 'FireEvent']}),
              dict(**{'class': 'logic_achievement', 'name': 'achievement_gunship', 'pos': (8247, 4387.3, 464.984), 'kv': {'AchievementEvent': 'ACHIEVEMENT_EVENT_HL2_KILL_ODESSAGUNSHIP'}})]),
  dict(id='hl2c.d2_coast_03.exit', title='Reach the exit', primary=True, pos=(6660, 13408, 240), after='hl2c.d2_coast_03.gunship', via=[(8894, 4064, 310), (8515.57, 4303.08, 285), (8247, 4387.3, 465)],
       description='Leave this area to continue to the next map.',
       complete=dict(kind='changelevel', target='d2_coast_04'),
       proof=[dict(**{'class': 'trigger_changelevel', 'pos': (6660, 13408, 240), 'kv': {'map': 'd2_coast_04', 'landmark': 'landmark_d2_coast_03-04'}})]),
 ],
 'fail_events': [dict(entity='killed_critical_npc', input='ShowMessage', why='an ally died'), dict(entity='jeep_lost_in_water', input='ShowMessage', why='the buggy was lost')],
}

# ---------------------------------------------------------------- ep2_outland_01 (Episode 2 intro: gravity-gun prop, cut-scene driven)
MAPS[('ep2', 'ep2_outland_01')] = {
 'note': 'Episode 2 opening. Mostly cut scenes; only the crowbar prop and the elevator exit are mechanical. DEDUCED semantics.',
 'objectives': [
  dict(id='hl2c.ep2_outland_01.crowbar', title='Lift the crowbar', primary=True, pos=(-6283.02, 3853, -245.55),
       description='A crowbar lies on the machine room floor. Pick it up with the gravity gun.',
       complete=dict(kind='input', entity='relay_crowbar_grabbed', input='Trigger'),
       proof=[dict(**{'class': 'prop_physics_override', 'name': 'crowbar', 'pos': (-6283.02, 3853, -245.55), 'out': ['OnPhysGunOnlyPickup', 'relay_crowbar_grabbed', 'Trigger']})]),
  dict(id='hl2c.ep2_outland_01.exit', title='Reach the exit', primary=True, pos=(-6048, 3502, -1312), after='hl2c.ep2_outland_01.crowbar', via=[(-6283.02, 3853, -245.55)],
       description='Leave this area to continue to the next map.',
       complete=dict(kind='changelevel', target='ep2_outland_01a', entity='trigger_ep2_outland_01-01a'),
       proof=[dict(**{'class': 'trigger_changelevel', 'name': 'trigger_ep2_outland_01-01a', 'pos': (-6048, 3502, -1312), 'kv': {'map': 'ep2_outland_01a', 'landmark': 'landmark_ep2_outland_01-01a'}})]),
 ],
 'fail_events': [],
}
