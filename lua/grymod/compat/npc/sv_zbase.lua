-- ZBase (server): a player who controls a ZBase NPC cannot be hurt (ZBase's controller cancels that damage in an EntityTakeDamage hook of its own): the suit ignores those hits, so that the bar
-- does not pay for damage that never comes (GryMod.API.AddHitFilter). Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing happens when ZBase is not installed (no
-- player has the field). Read from ZBase's source (zbase/controller/sv.lua: ply.ZBASE_ControlledNPC), not tried: ZBase needs a library that is not available.

local API = GryMod.API

if not API or not API.AddHitFilter then
	return -- sv_api.lua is included first (grymod_shared.lua)
end

API.AddHitFilter("GryMod compat zbase", function(ply)
	if IsValid(ply.ZBASE_ControlledNPC) then
		return "ignore"
	end

	return nil
end)
