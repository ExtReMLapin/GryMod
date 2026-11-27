-- Tests of the VJ Base adapter, client side (lua/grymod/compat/npc/sh_vjbase.lua), GLuaTest format, client realm. The camera of the NPC controller owns the view, and
-- the use prompt "FOLLOW" shows for an ally that VJ marked as a follower; stand-ins only (VJ writes no network variable of its own on the client).

return {
	groupName = "GryMod VJ Base adapter (client)",
	cases = {
		{
			name = "the NPC controller of VJ Base is a camera owner: the view is the NPC's while ply.VJ_Controlling is true (VJ sets it on the client itself)",
			func = function()
				local API = GryMod.API
				local me = LocalPlayer()
				local before = me.VJ_Controlling

				-- (the answer is kept for the frame: `true` asks the owners again)
				me.VJ_Controlling = true
				local owned = API.IsCameraOwned(me, true)
				me.VJ_Controlling = before

				expect(owned).to.beTrue()
			end
		},
		{
			name = "the follow prompt is for a VJ NPC that follows when used (the server marks it) and that is an ally to the player; never for the others",
			func = function()
				local V = GryMod.VJBase
				local function npc(fields)
					local e = {IsVJBaseSNPC = true, flag = true, health = 50}
					e.GetNW2Bool = function(self) return self.flag end
					e.Health = function(self) return self.health end
					for k, v in pairs(fields or {}) do e[k] = v end

					return e
				end

				expect(isfunction(V.IsFollowCandidate)).to.beTrue()
				expect(V.IsFollowCandidate(npc(), "ally")).to.beTrue()
				expect(V.IsFollowCandidate(npc(), "hostile")).to.beFalse()
				expect(V.IsFollowCandidate(npc(), "neutral")).to.beFalse()
				expect(V.IsFollowCandidate(npc(), nil)).to.beFalse() -- the server did not answer yet
				expect(V.IsFollowCandidate(npc({flag = false}), "ally")).to.beFalse() -- a tank: FollowPlayer is false
				expect(V.IsFollowCandidate(npc({health = 0}), "ally")).to.beFalse()
				expect(V.IsFollowCandidate(npc({IsVJBaseSNPC = false}), "ally")).to.beFalse()
			end
		},
		{
			name = "the prompt entry exists in the usable registry and asks ClientRelation (nothing else on the client knows the camp of a VJ NPC)",
			when = VJ ~= nil,
			func = function()
				expect(GryMod.API.Has("clientrelation")).to.beTrue()
				expect(GryMod.API.Has("usable")).to.beTrue()
				expect(GryMod.API.GetUsable ~= nil).to.beTrue()
			end
		}
	}
}
