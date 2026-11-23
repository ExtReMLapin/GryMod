-- d1_canals_01 (hl2). Written by hand (dev_resources/campaign/curated.py). Every proof line below was checked against the map when this file was made.
-- Long linear level. Few scripted steps: the boxcar scene is the only named progress event. Charger objective uses the use hook.
-- Texts are ours; the meaning of each step is deduced from the names and outputs and has to be walked once in the game.
return {
	objectives = {
		-- proof true: {'class': 'item_healthcharger', 'pos': (576, -7776, -74.065), 'kv': {'hammerid': '3082385'}}
		{
			id = "hl2c.d1_canals_01.charger", title = "Recharge at the health station", description = "A wall charger heals you while you hold the use key.", primary = false,
			pos = Vector(576, -7776, -74.065),
			complete = {kind = "use", at = Vector(576, -7776, -74.065), class = "item_healthcharger"},
		},
		-- proof true: {'class': 'trigger_once', 'pos': (736, 2158, -55.99), 'out': ['OnTrigger', 'boxcar_human', 'StartScripting']}
		-- proof true: {'class': 'npc_citizen', 'name': 'boxcar_human', 'pos': (684, 2668, -41)}
		{
			id = "hl2c.d1_canals_01.boxcar", title = "Reach the boxcar", description = "Two allies are waiting in a rail car at the far end.", primary = true,
			pos = Vector(736, 2158, -56),
			complete = {kind = "input", entity = "boxcar_human", input = "StartScripting"},
		},
		-- proof true: {'class': 'trigger_changelevel', 'pos': (768, 3024, 0), 'kv': {'map': 'd1_canals_01a', 'landmark': 'canals_trans_0101a'}}
		{
			id = "hl2c.d1_canals_01.exit", title = "Reach the exit", description = "Leave this area to continue to the next map.", primary = true,
			pos = Vector(768, 3024, 0),
			via = {Vector(736, 2158, -56)},
			after = "hl2c.d1_canals_01.boxcar",
			complete = {kind = "changelevel", target = "d1_canals_01a"},
		},
		-- [hl2/d1_canals_01 #1235] classname=logic_achievement targetname=achievement_gman_sighting_1 origin=710.448 2636.44 81.9076 AchievementEvent=ACHIEVEMENT_EVENT_HL2_GMAN_TRAINCAR hammerid=3148787
		-- fired by logic_relay "relay_achievement_gman_sighting_1" OnTrigger -> FireEvent
		{
			id = "hl2c.d1_canals_01.secret.hl2_gman_traincar", title = "Sighting", description = "", primary = false, secret = true,
			pos = Vector(710.448, 2636.44, 81.908),
			complete = {kind = "input", entity = "achievement_gman_sighting_1", input = "FireEvent"},
		},
		-- [hl2/d1_canals_01 #1239] classname=logic_achievement targetname=achievement_cache_1 origin=723.211 -6156 561.035 AchievementEvent=ACHIEVEMENT_EVENT_HL2_LAMDACACHE_CANALSSTATION hammerid=3151979
		-- fired by logic_relay "relay_achievement_cache_1" OnTrigger -> FireEvent
		{
			id = "hl2c.d1_canals_01.secret.hl2_lamdacache_canalsstation", title = "Hidden item", description = "", primary = false, secret = true,
			pos = Vector(723.211, -6156, 561.035),
			complete = {kind = "input", entity = "achievement_cache_1", input = "FireEvent"},
		},
		-- [hl2/d1_canals_01 #1241] classname=logic_achievement targetname=achievement_cache_2 origin=557.2 -5176 544.276 AchievementEvent=ACHIEVEMENT_EVENT_HL2_LAMDACACHE_VENTCRAWL hammerid=3152003
		-- fired by logic_relay "relay_achievement_cache_2" OnTrigger -> FireEvent
		{
			id = "hl2c.d1_canals_01.secret.hl2_lamdacache_ventcrawl", title = "Hidden item", description = "", primary = false, secret = true,
			pos = Vector(557.2, -5176, 544.276),
			complete = {kind = "input", entity = "achievement_cache_2", input = "FireEvent"},
		},
	},
	fail_events = {
	},
}
