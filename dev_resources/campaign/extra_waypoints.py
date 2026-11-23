"""Waypoints added by hand to the baseline, as PROOFS about the game's own maps: {map: [proof, ...]} (proofs.py keys: class, pos, out). Each one is a trigger of the
map that the map's own logic uses to set a door, a scene, a relay or a spawner going, chosen where a hand check of the route said a step was missed. They are merged
with the waypoints the rules find, filtered like them, and every proof is checked against the map by build_campaign.py. At most three for a map."""
EXTRA = {
    'd1_canals_01a': [
        {'class': 'trigger_once', 'pos': (-2808.0, 7328.0, 4.0), 'out': ['OnTrigger', 'barnacle_bowling_barnacles_template', 'ForceSpawn']},
        {'class': 'trigger_once', 'pos': (-1608.0, 6066.0, 34.0), 'out': ['OnTrigger', 'ss_mary_getinposition', 'BeginSequence']},
    ],
    'd1_canals_02': [
        {'class': 'trigger_multiple', 'pos': (56.0, -1360.0, -728.0), 'out': ['OnTrigger', 'underground_spawner_cscanner02', 'Spawn']},
    ],
    'd1_canals_03': [
        {'class': 'trigger_once', 'pos': (-2146.5, -881.0, -863.0), 'out': ['OnTrigger', 'grate_manhack_maker', 'Enable']},
    ],
    'd1_canals_05': [
        {'class': 'trigger_once', 'pos': (4228.0, 1746.0, -390.5), 'out': ['OnTrigger', 'relay_shanty_incoming', 'Trigger']},
        {'class': 'trigger_once', 'pos': (6678.83, 1405.96, -408.0), 'out': ['OnTrigger', 'ss_arlene_gascan', 'BeginSequence']},
    ],
    'd1_canals_08': [
        {'class': 'trigger_once', 'pos': (-2150.0, -2858.0, -312.0), 'out': ['OnTrigger', 'template_piercops3', 'ForceSpawn']},
        {'class': 'trigger_once', 'pos': (-776.0, -1368.0, -288.0), 'out': ['OnTrigger', 'template_pier_cops2', 'ForceSpawn']},
    ],
    'd1_canals_11': [
        {'class': 'trigger_once', 'pos': (7477.99, 4867.84, -924.0), 'out': ['OnTrigger', 'lcs_guncave_gategreet1', 'Start']},
    ],
    'd1_canals_12': [
        {'class': 'trigger_once', 'pos': (-3552.0, 4352.0, 384.0), 'out': ['OnTrigger', 'relay_pushcop_sequence', 'Trigger']},
        {'class': 'trigger_once', 'pos': (-960.0, -256.0, 352.0), 'out': ['OnTrigger', 'template_2apc_APCs', 'ForceSpawn']},
    ],
    'd1_eli_01': [
        {'class': 'trigger_once', 'pos': (456.0, 1665.99, -1226.0), 'out': ['OnTrigger', 'logic_loungers_start', 'Trigger']},
    ],
    'd1_town_01': [
        {'class': 'func_button', 'pos': (2709.38, -1219.5, -3807.0), 'out': ['OnOut', 'propeller_01_backfire_timer_1', 'Disable']},
        {'class': 'func_button', 'pos': (2277.38, -1251.5, -3743.0), 'out': ['OnOut', 'propeller_03_backfire_timer_1', 'Disable']},
        {'class': 'trigger_once', 'pos': (1691.0, -1668.0, -3712.0), 'out': ['OnTrigger', 'proptrap_2_zombie_ss_1', 'BeginSequence']},
    ],
    'd1_town_02': [
        {'class': 'func_button', 'pos': (-3006.0, 862.0, -3085.0), 'out': ['OnPressed', 'freight_lift_down_relay', 'Trigger']},
    ],
    'd1_trainstation_05': [
        {'class': 'trigger_once', 'pos': (-7220.0, -1312.0, 56.0), 'out': ['OnTrigger', 'BarneyTPnag_Loop_Barney01_lcs', 'Kill']},
        {'class': 'trigger_once', 'pos': (-7186.95, -1166.0, 24.0), 'out': ['OnTrigger', 'kleiner_teleport_player_starter_1', 'Trigger']},
    ],
    'd2_coast_04': [
        {'class': 'trigger_once', 'pos': (2464.0, -2080.0, 320.0), 'out': ['OnTrigger', 'dock_soldier_template', 'ForceSpawn']},
    ],
    'd2_coast_08': [
        {'class': 'trigger_once', 'pos': (3024.0, -3740.0, 1848.0), 'out': ['OnTrigger', 'cable_combine_template', 'ForceSpawn']},
        {'class': 'trigger_once', 'pos': (3260.0, 928.0, 1524.0), 'out': ['OnTrigger', 'spawn_crossbow_fodder', 'ForceSpawn']},
        {'class': 'trigger_once', 'pos': (3328.0, 2560.0, 1840.0), 'out': ['OnTrigger', 'headcrab_1_template', 'ForceSpawn']},
    ],
    'd2_coast_09': [
        {'class': 'trigger_once', 'pos': (802.78, -6653.29, -539.0), 'out': ['OnTrigger', 'house_innards_spawner2', 'ForceSpawn']},
    ],
    'd2_coast_10': [
        {'class': 'trigger_once', 'pos': (4760.0, -230.0, 976.0), 'out': ['OnTrigger', 'greeter_car_nag_timer', 'Kill']},
    ],
    'd2_prison_06': [
        {'class': 'trigger_once', 'pos': (1038.0, -1144.0, 20.0), 'out': ['OnTrigger', 'template_headcrab_vent_1', 'ForceSpawn']},
    ],
    'd2_prison_08': [
        {'class': 'trigger_once', 'pos': (96.0, 240.0, 996.0), 'out': ['OnStartTouch', 'logic_teleport_wheels_start_1', 'Trigger']},
    ],
    'd3_c17_08': [
        {'class': 'trigger_once', 'pos': (942.0, 508.0, 608.5), 'out': ['OnTrigger', 'roof_window_2_soldier_1_maker', 'Spawn']},
    ],
    'ep1_c17_00a': [
        {'class': 'func_button', 'pos': (4503.0, 3660.0, 451.0), 'out': ['OnPressed', 'elev_start', 'Trigger']},
    ],
    'ep1_c17_02a': [
        {'class': 'trigger_once', 'pos': (-450.0, 9649.0, -2728.0), 'out': ['OnTrigger', 'ss05', 'BeginSequence']},
    ],
    'ep1_citadel_00': [
        {'class': 'trigger_once', 'pos': (-7812.0, 5404.0, -48.0), 'out': ['OnTrigger', 'SS_alyx_pathedge_hopdown', 'BeginSequence']},
    ],
    'ep1_citadel_01': [
        {'class': 'trigger_once', 'pos': (-2658.0, 1377.0, 2576.86), 'out': ['OnStartTouch', 'logic_weapon_strip_announce', 'Trigger']},
    ],
    'ep1_citadel_02b': [
        {'class': 'trigger_once', 'pos': (3258.0, 4649.0, 2509.0), 'out': ['OnTrigger', 'alyx_elevator_ss_1', 'BeginSequence']},
    ],
    'ep1_citadel_03': [
        {'class': 'trigger_multiple', 'pos': (1200.0, 11708.0, 5247.96), 'out': ['OnTrigger', 'logic_door_comb_1_close', 'Trigger']},
        {'class': 'trigger_once', 'pos': (1488.0, 12144.0, 5535.91), 'out': ['OnTrigger', 'lcs_alyx_corecomplete', 'Resume']},
        {'class': 'trigger_multiple', 'pos': (1522.0, 11720.0, 5312.0), 'out': ['OnStartTouch', 'lcs_core_control_scene', 'Resume']},
    ],
    'ep1_citadel_04': [
        {'class': 'trigger_once', 'pos': (3576.02, 11714.0, 3728.0), 'out': ['OnTrigger', 'al_citadel_04_rearsoldierslock', 'Start']},
        {'class': 'trigger_once', 'pos': (4558.0, 10744.0, 3566.0), 'out': ['OnTrigger', 'lcs_al_stalkertrain_01', 'Cancel']},
    ],
    'ep2_outland_02': [
        {'class': 'trigger_once', 'pos': (-3115.5, -9477.5, -3040.0), 'out': ['OnTrigger', 'start_the_elevator_rl', 'Trigger']},
    ],
    'ep2_outland_03': [
        {'class': 'trigger_once', 'pos': (3125.49, -7152.0, -1386.0), 'out': ['OnTrigger', 'thumper_arena_ragdoll_template', 'ForceSpawn']},
        {'class': 'trigger_once', 'pos': (5148.88, -5507.28, -615.0), 'out': ['OnTrigger', 'rideable_tracktrain_2_start_rl', 'Trigger']},
    ],
    'ep2_outland_06': [
        {'class': 'trigger_once', 'pos': (256.0, 416.0, 828.0), 'out': ['OnTrigger', 'lcs_vort_workloop', 'Resume']},
        {'class': 'trigger_once', 'pos': (536.0, 2320.0, 848.0), 'out': ['OnTrigger', 'ss_alyx_wait', 'BeginSequence']},
        {'class': 'trigger_once', 'pos': (876.0, 3236.0, 64.0), 'out': ['OnTrigger', 'goo_pit1_template', 'ForceSpawn']},
    ],
    'ep2_outland_06a': [
        {'class': 'trigger_once', 'pos': (-3080.0, -9712.0, -1492.0), 'out': ['OnTrigger', 'ss_alyx_standby', 'BeginSequence']},
    ],
    'ep2_outland_08': [
        {'class': 'trigger_once', 'pos': (-1726.0, 974.0, 127.41), 'out': ['OnTrigger', 'relay_alyx_starthealth', 'Trigger']},
    ],
    'ep2_outland_09': [
        {'class': 'trigger_multiple', 'pos': (-1251.0, -9490.0, 77.0), 'out': ['OnTrigger', 'spawner.alley.zombie', 'Kill']},
        {'class': 'trigger_once', 'pos': (-247.95, -7565.51, 107.09), 'out': ['OnTrigger', 'combine_set_3_template', 'Kill']},
        {'class': 'trigger_once', 'pos': (456.0, -9186.0, 121.0), 'out': ['OnStartTouch', 'timer_nag_door', 'Kill']},
    ],
    'ep2_outland_10': [
        {'class': 'trigger_once', 'pos': (3448.0, -384.0, 0.05), 'out': ['OnTrigger', 'relay_combineshieldwall1_on', 'Trigger']},
    ],
    'ep2_outland_11': [
        {'class': 'trigger_once', 'pos': (443.0, -9936.0, 112.0), 'out': ['OnStartTouch', 'lift_door_1_a', 'Close']},
        {'class': 'func_button', 'pos': (1397.0, -9894.5, -525.0), 'out': ['OnPressed', 'temp_roperguy', 'ForceSpawn']},
    ],
    'ep2_outland_11b': [
        {'class': 'trigger_once', 'pos': (448.0, -8557.0, -254.01), 'out': ['OnStartTouch', 'door_silo_lab_1', 'Close']},
        {'class': 'trigger_multiple', 'pos': (366.0, -8828.0, -254.01), 'out': ['OnStartTouch', 'door_silo_lab_1', 'Open']},
    ],
    'ep2_outland_12': [
        {'class': 'trigger_once', 'pos': (-776.0, -6504.0, -244.11), 'out': ['OnTrigger', 'base_cit_sawmill_lcs', 'Start']},
        {'class': 'trigger_once', 'pos': (-704.0, -8408.0, -240.0), 'out': ['OnTrigger', 'changelevel_to_12a_door', 'Open']},
    ],
    'ep2_outland_12a': [
        {'class': 'trigger_once', 'pos': (-372.0, -2189.01, -1514.0), 'out': ['OnTrigger', 'door_elevator_L', 'Close']},
    ],
}
