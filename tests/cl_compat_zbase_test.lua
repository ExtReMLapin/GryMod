-- Tests of the ZBase adapter, client side (lua/grymod/compat/npc/cl_zbase.lua), GLuaTest format, client realm. The player who controls a ZBase NPC sees through the NPC's camera (another camera has the
-- view); the use key on an ally NPC of ZBase makes it follow him, which GryMod's prompt says (FOLLOW, or STOP FOLLOWING while it does). ZBase is stood in for. Each case names the change that makes it
-- fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function npc(fields)
	local e = {}

	function e:IsValid() return true end
	function e:GetClass() return "zb_human_rebel" end
	function e:GetNWBool(key) return key == "IsZBaseNPC" end
	function e:GetNWString(key) if key == "ZBASE_CustomClass" then return "zb_human_rebel" end return "" end

	for k, v in pairs(fields or {}) do
		e[k] = v
	end

	return e
end

return {
	groupName = "GryMod compat: ZBase NPCs (client)",
	beforeEach = function()
		saved = {}
		stub(_G, "ZBaseInstalled", true)
		stub(_G, "ZBaseNPCs", {zb_human_rebel = {CanFollowPlayers = true}, zb_zombie = {CanFollowPlayers = false}})
		stub(GryMod.API, "ClientRelation", function(ent) return ent.relation end)
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when no camera owner is registered, or when it says yes for a player who controls nothing
			name = "the player who controls a ZBase NPC has another camera, the player who does not has not",
			func = function()
				local ply = LocalPlayer()

				stub(ply, "GetNWEntity", function(self, key) if key == "ZBASE_ControllerCamEnt" then return game.GetWorld() end return NULL end)
				expect(GryMod.API.IsCameraOwned(ply)).to.beTrue()

				ply.GetNWEntity = function() return NULL end
				expect(GryMod.API.IsCameraOwned(ply)).to.beFalse()
			end
		},
		{
			-- fails when an ally ZBase NPC that can follow has no prompt, or the prompt is not FOLLOW
			name = "an allied ZBase NPC that can follow has the prompt FOLLOW",
			func = function()
				local ply = LocalPlayer()

				stub(ply, "ZBaseFollowHaloEnts", {})

				local entry = GryMod.API.GetUsable(npc({relation = "ally"}))

				expect(entry).toNot.beNil()
				expect(entry.key).to.equal("compat.zbase.follow")
				expect(GryMod.API.UsableText(npc({relation = "ally"}), ply, entry)).to.equal("FOLLOW")
			end
		},
		{
			-- fails when the prompt does not change while the NPC follows (ZBase's own list of followers is on the player on the client)
			name = "the prompt says STOP FOLLOWING while the NPC follows the player",
			func = function()
				local ply = LocalPlayer()
				local following = npc({relation = "ally"})

				stub(ply, "ZBaseFollowHaloEnts", {following})
				expect(GryMod.API.UsableText(following, ply)).to.equal("STOP FOLLOWING")
			end
		},
		{
			-- fails when an enemy, a neutral or an unanswered relation gets the prompt (a FOLLOW on a zombie), or an NPC that cannot follow
			name = "no prompt for a hostile or neutral NPC, one whose relation is not known yet, one that cannot follow, or one that is not ZBase's",
			func = function()
				expect(GryMod.API.GetUsable(npc({relation = "hostile"}))).to.beNil()
				expect(GryMod.API.GetUsable(npc({relation = "neutral"}))).to.beNil()
				expect(GryMod.API.GetUsable(npc({relation = nil}))).to.beNil()

				local zombie = npc({relation = "ally", GetClass = function() return "zb_zombie" end, GetNWString = function(self, key) if key == "ZBASE_CustomClass" then return "zb_zombie" end return "" end})

				expect(GryMod.API.GetUsable(zombie)).to.beNil()

				local other = npc({relation = "ally", GetNWBool = function() return false end})

				expect(GryMod.API.GetUsable(other)).to.beNil()
			end
		}
	}
}
