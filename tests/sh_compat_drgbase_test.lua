-- Tests of the DrGBase adapter (lua/grymod/compat/npc/sh_drgbase.lua), GLuaTest format, runs in the server AND in the client realm. DrGBase's nextbots are not NPCs for the engine (no
-- IsNPC, no NPC state, no conditions) and keep their own relations (GetRelationship) and awareness (GetEnemy, HasSpotted, IsInSight): the adapter says to GryMod what they are, through the public API
-- (AddCreatureProvider, RegisterTracked with relation, awareness and dead, a danger for the grenades). DrGBase is stood in for by tables that answer like a nextbot, so the cases run without it; each
-- stand-in checks its arguments. Each case names the production change whose absence makes it fail.

local API

local D_LI_, D_HT_, D_FR_, D_NU_ = D_LI, D_HT, D_FR, D_NU

local function player(extra)
	local p = {IsValid = function() return true end, IsPlayer = function() return true end}

	for k, v in pairs(extra or {}) do
		p[k] = v
	end

	return p
end

-- a nextbot stand-in. `disposition` is what GetRelationship answers (and the call must pass the player and `true`: the absolute relation, without the "ignored" rule)
local function nextbot(fields)
	local nb = {IsDrGNextbot = true, Base = "drgbase_nextbot"}

	function nb:IsValid() return true end
	function nb:GetClass() return "npc_test_drg" end

	for k, v in pairs(fields or {}) do
		nb[k] = v
	end

	return nb
end

return {
	groupName = "GryMod compat: DrGBase nextbots (shared)",
	beforeEach = function()
		API = GryMod.API
	end,
	cases = {
		{
			-- fails when no creature provider is added (a nextbot is no creature: the radar, the crosshair and the hologram skip it) or when it answers for what is not a DrGBase nextbot
			name = "a DrGBase nextbot is a creature for GryMod, anything else that is not an NPC is not",
			func = function()
				expect(API.IsCreature(nextbot())).to.beTrue()
				expect(API.IsCreature(nextbot({IsDrGNextbot = false}))).to.beFalse()

				local plain = {IsValid = function() return true end, GetClass = function() return "prop_physics" end}

				expect(API.IsCreature(plain)).to.beFalse()
			end
		},
		{
			-- fails when the base is not registered (the entry is not found), or is registered with another key than the adapter's
			name = "a nextbot of a DrGBase pack has a tracked entry found by its base",
			func = function()
				local entry = API.GetTracked(nextbot())

				expect(entry).toNot.beNil()
				expect(entry.key).to.equal("compat.drgbase")
				-- (another class name: the registry keeps what it found for a class)
				expect(API.GetTracked(nextbot({Base = "base_nextbot", GetClass = function() return "npc_test_other" end}))).to.beNil()
			end
		},
		{
			-- fails when the relation is read without the `true` (a camouflaged player is "ignored" by DrGBase and every nextbot would turn neutral: the radar would drop it), when a
			-- disposition is mapped to the wrong word, or when a thing that has no GetRelationship is not left to the next rule
			name = "the relation is DrGBase's own, asked as an absolute one: like is an ally, hate is hostile, fear and neutral are neutral",
			func = function()
				local entry = API.GetTracked(nextbot())
				local ply = player()
				local asked = {}

				local function relationOf(disposition)
					return entry.relation(ply, nextbot({
						GetRelationship = function(self, other, absolute)
							asked[#asked + 1] = {other, absolute}

							return disposition
						end
					}))
				end

				expect(relationOf(D_LI_)).to.equal("ally")
				expect(relationOf(D_HT_)).to.equal("hostile")
				expect(relationOf(D_FR_)).to.equal("neutral")
				expect(relationOf(D_NU_)).to.equal("neutral")

				for _, call in ipairs(asked) do
					expect(call[1]).to.equal(ply)
					expect(call[2]).to.equal(true)
				end

				expect(#asked).to.equal(4)
				expect(entry.relation(ply, nextbot())).to.beNil()
			end
		},
		{
			-- fails when the awareness field is not there, when the enemy is not the fight level (2), when a nextbot that only spotted the player is not alerted (1), or when seeing is not read
			name = "the awareness: fighting when the player is its enemy, alerted when it has spotted him, calm otherwise; it says what it sees",
			func = function()
				local entry = API.GetTracked(nextbot())
				local ply = player()
				local other = player()

				local function aware(fields)
					local nb = nextbot({
						GetEnemy = function() return fields.enemy end,
						HasSpotted = function(self, who) return who == ply and fields.spotted == true end,
						IsInSight = function(self, who) return who == ply and fields.sight == true end
					})

					return {entry.awareness(nb, ply)}
				end

				local fight = aware({enemy = ply, spotted = true, sight = true})

				expect(fight[1]).to.equal(2)
				expect(fight[2]).to.equal(1)
				expect(fight[3]).to.beTrue()

				local alert = aware({enemy = other, spotted = true, sight = false})

				expect(alert[1]).to.equal(1)
				expect(alert[2] > 0 and alert[2] < 1).to.beTrue()
				expect(alert[3]).to.beFalse()

				local calm = aware({enemy = other, spotted = false, sight = false})

				expect(calm[1]).to.equal(0)
				expect(calm[2]).to.equal(0)
				expect(calm[4]).to.beFalse()

				-- the enemy is NULL-like: a nextbot with no enemy is calm
				expect(aware({enemy = nil, spotted = false, sight = false})[1]).to.equal(0)
			end
		},
		{
			-- fails when a nextbot that is dying or dead stays a contact
			name = "a nextbot that is dead (IsDead) is not a contact",
			func = function()
				local entry = API.GetTracked(nextbot())

				expect(entry.dead(nextbot({IsDead = function() return true end}))).to.beTrue()
				expect(entry.dead(nextbot({IsDead = function() return false end}))).to.beFalse()
				expect(entry.dead(nextbot())).to.beFalse()
			end
		},
		{
			-- fails when a thrown DrGBase grenade has no danger entry, when the smoke grenade is one (a smoke is no danger), or when the entry is found by class name only
			name = "the grenades of DrGBase are dangers, the smoke grenade is not, and a pack's own grenade class (built on the base) is found",
			func = function()
				local realIsBasedOn = scripted_ents.IsBasedOn

				scripted_ents.IsBasedOn = function(class, base)
					return base == "proj_drg_grenade" and (class == "proj_drg_flashbang" or class == "proj_drg_smoke_grenade" or class == "drg_pack_nade")
				end

				local ok, err = pcall(function()
					local frag = API.GetDanger({IsValid = function() return true end, GetClass = function() return "proj_drg_grenade" end, IsDrGGrenade = true})
					local pack = API.GetDanger({IsValid = function() return true end, GetClass = function() return "drg_pack_nade" end, IsDrGGrenade = true})
					local flash = API.GetDanger({IsValid = function() return true end, GetClass = function() return "proj_drg_flashbang" end, IsDrGGrenade = true})
					local smoke = API.GetDanger({IsValid = function() return true end, GetClass = function() return "proj_drg_smoke_grenade" end, IsDrGGrenade = true})
					local plasma = API.GetDanger({IsValid = function() return true end, GetClass = function() return "proj_drg_plasma" end})

					expect(frag).toNot.beNil()
					expect(pack).to.equal(frag)
					expect(frag.danger.label).to.equal("GRENADE")
					expect(flash).toNot.beNil()
					expect(flash.danger.label).to.equal("FLASHBANG")
					expect(smoke).to.beNil()
					expect(plasma).to.beNil()
				end)

				scripted_ents.IsBasedOn = realIsBasedOn

				if not ok then error(err, 0) end
			end
		},
		{
			-- fails when the grenade is "armed" before the pin is out (every grenade lying around would warn) or after it exploded
			name = "a DrGBase grenade is armed from the pin out (DrGBaseUnpined) until it detonated",
			func = function()
				local entry = API.GetDanger({IsValid = function() return true end, GetClass = function() return "proj_drg_grenade" end, IsDrGGrenade = true})

				local function grenade(unpined, detonated)
					return {
						GetNW2Bool = function(self, key)
							expect(key == "DrGBaseUnpined" or key == "DrGBaseDetonated").to.beTrue()

							if key == "DrGBaseUnpined" then return unpined end

							return detonated
						end
					}
				end

				expect(entry.danger.armed(grenade(false, false))).to.beFalse()
				expect(entry.danger.armed(grenade(true, false))).to.beTrue()
				expect(entry.danger.armed(grenade(true, true))).to.beFalse()
			end
		}
	}
}
