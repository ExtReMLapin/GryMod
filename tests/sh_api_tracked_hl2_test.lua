-- Tests of the stock Half-Life 2 entries of the registry of tracked entities (lua/grymod/sh_api_tracked_hl2.lua), GLuaTest format,
-- runs in the server AND in the client realm. They are plain data registered through the public API (RegisterTracked), exactly as an
-- addon would: the radar's icon classes (flying, machines, big ones) and the dangers of the grenade warning (labels, which
-- projectiles are the player's own missiles, how the server reads that one is armed). Design: docs/superpowers/specs/2026-11-21-extension-api-design.md,
-- the addendum and wave B3.

local API

local function ent(class)
	return {IsValid = function() return true end, GetClass = function() return class end}
end

return {
	groupName = "GryMod extension API: stock Half-Life 2 entries of the tracked registry (shared)",
	beforeEach = function()
		API = GryMod.API
	end,
	cases = {
		{
			name = "the radar's icons: flying, machines and the big ones are registered entries (human for the rest)",
			func = function()
				for _, class in ipairs({"npc_combinegunship", "npc_helicopter", "npc_combinedropship", "npc_cscanner", "npc_clawscanner", "npc_manhack"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry).toNot.beNil()
					expect(entry.type).to.equal(2)
					expect(entry.size).to.beNil()
				end

				for _, class in ipairs({"npc_strider", "npc_hunter"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.type).to.equal(3)
					expect(entry.size).to.equal("big")
				end

				for _, class in ipairs({"npc_turret_floor", "npc_turret_ceiling", "npc_turret_ground", "npc_rollermine", "npc_combine_camera"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.type).to.equal(3)
					expect(entry.size).to.beNil()
				end

				for _, class in ipairs({"npc_antlionguard", "npc_antlionguardian"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.size).to.equal("big")
					expect(entry.type).to.beNil() -- the icon of a ground unit
				end

				expect(API.GetTracked(ent("npc_combine_s"))).to.beNil()
				expect(API.GetTracked(ent("npc_zombie"))).to.beNil()
			end
		},
		{
			name = "the stock entries change nothing else of an NPC: scan allowed, relation auto, no radar rule",
			func = function()
				for _, class in ipairs({"npc_manhack", "npc_strider", "npc_turret_floor", "npc_antlionguard"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.scan).to.beTrue()
					expect(entry.relation).to.equal("auto")
					expect(entry.radar).to.beNil()
					expect(entry.danger).to.beNil()
				end
			end
		},
		{
			name = "the stock entries have a low priority: an entry registered later for the same class beats them, and goes away cleanly",
			func = function()
				local stock = API.GetTracked(ent("npc_strider"))
				expect(stock.priority < 0).to.beTrue()

				expect(API.RegisterTracked("t_hl2_override", {class = "npc_strider", relation = "ally", type = "human"})).to.beTrue()
				local ok, err = pcall(function()
					expect(API.GetTracked(ent("npc_strider")).key).to.equal("t_hl2_override")
					expect(API.GetTrackedByClass("npc_strider").type).to.equal(1)
				end)
				API.UnregisterTracked("t_hl2_override")
				if not ok then error(err, 0) end

				expect(API.GetTracked(ent("npc_strider")).key).to.equal(stock.key)
			end
		},
		{
			name = "the dangers: the six projectiles are registered with their label and the warning indicator",
			func = function()
				local labels = {
					npc_grenade_frag = "FRAG GRENADE", grenade_ar2 = "RIFLE GRENADE", rpg_missile = "MISSILE",
					grenade_helicopter = "BOMB", combine_mine = "MINE", prop_combine_ball = "ENERGY BALL"
				}

				for class, label in pairs(labels) do
					local entry = API.GetDanger(class)
					expect(entry).toNot.beNil()
					expect(entry.danger.label).to.equal(label)
					expect(entry.indicator).to.equal("warning")
					expect(isstring(entry.danger.type)).to.beTrue()
					expect(isfunction(entry.danger.armed)).to.beTrue()
				end

				expect(API.GetDanger("prop_physics")).to.beNil()
			end
		},
		{
			name = "the projectiles a player FIRES are the own missiles (they never warn their shooter): the rifle grenade, the missile and the energy ball; the thrown ones are not",
			func = function()
				expect(API.GetDanger("rpg_missile").danger.ownMissile).to.beTrue()
				expect(API.GetDanger("grenade_ar2").danger.ownMissile).to.beTrue()
				expect(API.GetDanger("prop_combine_ball").danger.ownMissile).to.beTrue()
				expect(API.GetDanger("npc_grenade_frag").danger.ownMissile).to.beFalse()
				expect(API.GetDanger("grenade_helicopter").danger.ownMissile).to.beFalse()
				expect(API.GetDanger("combine_mine").danger.ownMissile).to.beFalse()
			end
		}
	}
}
