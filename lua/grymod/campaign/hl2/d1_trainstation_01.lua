-- d1_trainstation_01 (hl2). Written by hand (dev_resources/campaign/curated.py). Every proof line below was checked against the map when this file was made.
-- Arrival and checkpoint chain. Semantics DEDUCED from entity names and outputs; objective texts are ours.
-- Texts are ours; the meaning of each step is deduced from the names and outputs and has to be walked once in the game.
return {
	objectives = {
		-- proof true: {'class': 'trigger_once', 'pos': (-4211, -492, 28), 'out': ['OnTrigger', 'gordon_cop_template', 'ForceSpawn']}
		-- proof true: {'class': 'point_template', 'name': 'gordon_cop_template'}
		{
			id = "hl2c.d1_trainstation_01.checkpoint", title = "Go through the checkpoint", description = "Follow the arrivals to the guards at the end of the hall.", primary = true,
			pos = Vector(-4211, -492, 28),
			complete = {kind = "input", entity = "gordon_cop_template", input = "ForceSpawn"},
		},
		-- proof true: {'class': 'prop_door_rotating', 'name': 'barney_door_2', 'pos': (-3497, -460, 22)}
		-- proof true: {'class': 'logic_choreographed_scene', 'name': 'security_intro_01', 'out': ['OnTrigger1', 'barney_door_2', 'Open']}
		{
			id = "hl2c.d1_trainstation_01.back_room", title = "Get out of the back room", description = "You are locked in. Wait until a way out opens and leave through the door.", primary = true,
			pos = Vector(-3497, -460, 22),
			after = "hl2c.d1_trainstation_01.checkpoint",
			complete = {kind = "input", entity = "barney_door_2", input = "Open"},
		},
		-- proof true: {'class': 'prop_door_rotating', 'name': 'storage_room_door', 'pos': (-3337, -132, 22)}
		-- proof true: {'class': 'logic_choreographed_scene', 'name': 'security_03', 'out': ['OnTrigger3', 'storage_room_door', 'Open']}
		{
			id = "hl2c.d1_trainstation_01.storage_room", title = "Leave through the storage room", description = "Go through the storage room door and out of the building.", primary = true,
			pos = Vector(-3337, -132, 22),
			after = "hl2c.d1_trainstation_01.back_room",
			complete = {kind = "input", entity = "storage_room_door", input = "Open"},
		},
		-- proof true: {'class': 'trigger_changelevel', 'pos': (-3104, -152, 0), 'kv': {'map': 'd1_trainstation_02', 'landmark': 'trainstation_01_to_02'}}
		{
			id = "hl2c.d1_trainstation_01.exit", title = "Reach the exit", description = "Leave this area to continue to the next map.", primary = true,
			pos = Vector(-3104, -152, 0),
			via = {Vector(-3497, -460, 22), Vector(-3337, -132, 22)},
			after = "hl2c.d1_trainstation_01.storage_room",
			complete = {kind = "changelevel", target = "d1_trainstation_02"},
		},
		-- proof true: {'class': 'func_button', 'name': 'soda_machine_1', 'pos': (-4117.13, -1127.13, 21), 'out': ['OnPressed', 'soda_machine_1_branch', 'Test']}
		{
			id = "hl2c.d1_trainstation_01.soda", title = "Try the soda machine", description = "A drinks machine stands against the wall. Press its button.", primary = false,
			pos = Vector(-4117.13, -1127.13, 21),
			complete = {kind = "use", entity = "soda_machine_1"},
		},
	},
	fail_events = {
	},
}
