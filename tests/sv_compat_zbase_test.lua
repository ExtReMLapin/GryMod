-- Tests of the ZBase adapter, server side (lua/grymod/compat/npc/sv_zbase.lua), GLuaTest format, server realm. A player who controls a ZBase NPC cannot be hurt (ZBase cancels the damage itself):
-- the suit ignores those hits, so that the bar does not pay for damage that never comes. ZBase is stood in for. Each case names the change that makes it fail.

local API

local function damage(amount)
	local d = DamageInfo()

	d:SetDamage(amount)
	d:SetDamageType(DMG_BULLET)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())

	return d
end

return {
	groupName = "GryMod compat: ZBase NPCs (server)",
	beforeEach = function()
		API = GryMod.API
	end,
	cases = {
		{
			-- fails when the control is not a hit filter, or when a player that controls nobody is ignored
			name = "the suit ignores the hits on a player who is controlling a ZBase NPC, and only on him",
			func = function()
				local npc = {IsValid = function() return true end}
				local controlling = {ZBASE_ControlledNPC = npc}
				local free = {}
				local stale = {ZBASE_ControlledNPC = {IsValid = function() return false end}}

				expect(API.HitVerdict(controlling, damage(10))).to.equal("ignore")
				expect(API.HitVerdict(free, damage(10))).to.beNil()
				expect(API.HitVerdict(stale, damage(10))).to.beNil()
			end
		}
	}
}
