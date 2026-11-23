-- ep2_outland_01 (ep2). Written by hand (dev_resources/campaign/curated.py). Every proof line below was checked against the map when this file was made.
-- Episode 2 opening. Mostly cut scenes; only the crowbar prop and the elevator exit are mechanical. DEDUCED semantics.
-- Texts are ours; the meaning of each step is deduced from the names and outputs and has to be walked once in the game.
return {
	objectives = {
		-- proof true: {'class': 'prop_physics_override', 'name': 'crowbar', 'pos': (-6283.02, 3853, -245.55), 'out': ['OnPhysGunOnlyPickup', 'relay_crowbar_grabbed', 'Trigger']}
		{
			id = "hl2c.ep2_outland_01.crowbar", title = "Lift the crowbar", description = "A crowbar lies on the machine room floor. Pick it up with the gravity gun.", primary = true,
			pos = Vector(-6283.02, 3853, -245.55),
			complete = {kind = "input", entity = "relay_crowbar_grabbed", input = "Trigger"},
		},
		-- proof true: {'class': 'trigger_changelevel', 'name': 'trigger_ep2_outland_01-01a', 'pos': (-6048, 3502, -1312), 'kv': {'map': 'ep2_outland_01a', 'landmark': 'landmark_ep2_outland_01-01a'}}
		{
			id = "hl2c.ep2_outland_01.exit", title = "Reach the exit", description = "Leave this area to continue to the next map.", primary = true,
			pos = Vector(-6048, 3502, -1312),
			via = {Vector(-6283.02, 3853, -245.55)},
			after = "hl2c.ep2_outland_01.crowbar",
			complete = {kind = "changelevel", target = "ep2_outland_01a", entity = "trigger_ep2_outland_01-01a"},
		},
	},
	fail_events = {
	},
}
