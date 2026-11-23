-- d2_coast_03 (hl2). Written by hand (dev_resources/campaign/curated.py). Every proof line below was checked against the map when this file was made.
-- Vehicle, outpost, rocket launcher, gunship. Two ways to fail are defined by the map itself (env_message GAMEOVER_*).
-- Texts are ours; the meaning of each step is deduced from the names and outputs and has to be walked once in the game.
return {
	objectives = {
		-- proof true: {'class': 'prop_vehicle_jeep', 'name': 'jeep', 'pos': (-6913.57, -13638.2, 1026), 'out': ['PlayerOn', 'antlion_spawner_injeep_relay', 'Trigger']}
		-- proof true: {'class': 'trigger_once', 'pos': (992, -2176, -160), 'out': ['OnTrigger', 'jeep_lost_in_water', 'ShowMessage']}
		-- proof true: {'class': 'env_message', 'name': 'jeep_lost_in_water', 'kv': {'message': 'GAMEOVER_OBJECT'}}
		-- fails when: the buggy was lost in the water
		{
			id = "hl2c.d2_coast_03.buggy", title = "Get in the buggy", description = "The buggy is parked by the start. Drive it along the coast.", primary = true,
			pos = Vector(-6913.57, -13638.2, 1026),
			complete = {kind = "enter_vehicle", entity = "jeep", class = "prop_vehicle_jeep"},
			fail = {kind = "input", entity = "jeep_lost_in_water", input = "ShowMessage"},
		},
		-- proof true: {'class': 'trigger_once', 'name': 'trigger_gordoninbasement', 'pos': (8894, 4064, 310), 'out': ['OnTrigger', 'basement_gordon_first_entered', 'Trigger']}
		-- proof true: {'class': 'npc_citizen', 'name': 'rocketman', 'out': ['OnDeath', 'killed_critical_npc', 'ShowMessage']}
		-- proof true: {'class': 'env_message', 'name': 'killed_critical_npc', 'kv': {'message': 'GAMEOVER_ALLY'}}
		-- fails when: an ally died
		{
			id = "hl2c.d2_coast_03.basement", title = "Go down to the basement", description = "Find the man in the outpost basement.", primary = true,
			pos = Vector(8894, 4064, 310),
			after = "hl2c.d2_coast_03.buggy",
			complete = {kind = "input", entity = "basement_gordon_first_entered", input = "Trigger"},
			fail = {kind = "input", entity = "killed_critical_npc", input = "ShowMessage"},
		},
		-- proof true: {'class': 'weapon_rpg', 'name': 'rpg_weapon', 'pos': (8515.57, 4303.08, 285), 'out': ['OnPlayerPickup', 'first_train_rl', 'Trigger']}
		{
			id = "hl2c.d2_coast_03.rpg", title = "Take the rocket launcher", description = "A launcher is lying in the outpost. You will need it against what is coming.", primary = true,
			pos = Vector(8515.57, 4303.08, 285),
			via = {Vector(8894, 4064, 310)},
			after = "hl2c.d2_coast_03.basement",
			complete = {kind = "pickup", class = "weapon_rpg", entity = "rpg_weapon"},
		},
		-- proof true: {'class': 'npc_combinegunship', 'name': 'gunship1', 'out': ['OnDeath', 'achievement_gunship', 'FireEvent']}
		-- proof true: {'class': 'logic_achievement', 'name': 'achievement_gunship', 'pos': (8247, 4387.3, 464.984), 'kv': {'AchievementEvent': 'ACHIEVEMENT_EVENT_HL2_KILL_ODESSAGUNSHIP'}}
		{
			id = "hl2c.d2_coast_03.gunship", title = "Destroy the gunship", description = "A gunship is attacking the outpost. Bring it down.", primary = true,
			pos = Vector(8247, 4387.3, 465),
			via = {Vector(8894, 4064, 310), Vector(8515.57, 4303.08, 285)},
			after = "hl2c.d2_coast_03.rpg",
			complete = {kind = "removed", entity = "gunship1", also = {kind = "input", entity = "achievement_gunship", input = "FireEvent"}},
		},
		-- proof true: {'class': 'trigger_changelevel', 'pos': (6660, 13408, 240), 'kv': {'map': 'd2_coast_04', 'landmark': 'landmark_d2_coast_03-04'}}
		{
			id = "hl2c.d2_coast_03.exit", title = "Reach the exit", description = "Leave this area to continue to the next map.", primary = true,
			pos = Vector(6660, 13408, 240),
			via = {Vector(8894, 4064, 310), Vector(8515.57, 4303.08, 285), Vector(8247, 4387.3, 465)},
			after = "hl2c.d2_coast_03.gunship",
			complete = {kind = "changelevel", target = "d2_coast_04"},
		},
		-- [hl2/d2_coast_03 #1791] classname=logic_achievement targetname=achievement_cache origin=-3608 -5960 616 AchievementEvent=ACHIEVEMENT_EVENT_HL2_LAMDACACHE_POISONSHACK hammerid=1083828
		-- fired by logic_relay "relay_cache" OnTrigger -> FireEvent
		{
			id = "hl2c.d2_coast_03.secret.hl2_lamdacache_poisonshack", title = "Hidden item", description = "", primary = false, secret = true,
			pos = Vector(-3608, -5960, 616),
			complete = {kind = "input", entity = "achievement_cache", input = "FireEvent"},
		},
		-- [hl2/d2_coast_03 #1793] classname=logic_achievement targetname=achievement_gman_sighting origin=-3702.21 3794.65 493 AchievementEvent=ACHIEVEMENT_EVENT_HL2_GMAN_ODESSA hammerid=1087705
		-- fired by logic_relay "relay_gman_sighting" OnTrigger -> FireEvent
		{
			id = "hl2c.d2_coast_03.secret.hl2_gman_odessa", title = "Sighting", description = "", primary = false, secret = true,
			pos = Vector(-3702.21, 3794.65, 493),
			complete = {kind = "input", entity = "achievement_gman_sighting", input = "FireEvent"},
		},
	},
	fail_events = {
		{entity = "killed_critical_npc", input = "ShowMessage"},  -- an ally died
		{entity = "jeep_lost_in_water", input = "ShowMessage"},  -- the buggy was lost
	},
}
