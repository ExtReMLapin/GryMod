-- Tests of the DrGBase adapter, client side (lua/grymod/compat/npc/cl_drgbase.lua), GLuaTest format, client realm. A player who possesses a nextbot sees through the nextbot's camera
-- (DrGBase's CalcView, in the third person): another camera has the view, so GryMod's own zoom and the binoculars must not take it (GryMod.API.AddCameraOwner). Each case names the change that
-- makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

return {
	groupName = "GryMod compat: DrGBase nextbots (client)",
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when no camera owner is registered, or when it says yes for a player who does not possess (the binoculars would never open)
			name = "the player possessing a nextbot has another camera, the player who is not does not",
			func = function()
				local ply = LocalPlayer()
				local meta = FindMetaTable("Player") -- (DrGBase puts its function on the player's metatable, which an entity's own field does not hide)

				stub(meta, "DrG_IsPossessing", function() return true end)
				expect(GryMod.API.IsCameraOwned(ply, true)).to.beTrue()

				meta.DrG_IsPossessing = function() return false end
				expect(GryMod.API.IsCameraOwned(ply, true)).to.beFalse()
			end
		},
		{
			-- fails when the owner raises an error without DrGBase (a player has no DrG_IsPossessing then)
			name = "without DrGBase the owner answers no and raises nothing",
			func = function()
				local ply = LocalPlayer()

				stub(FindMetaTable("Player"), "DrG_IsPossessing", nil)
				expect(GryMod.API.IsCameraOwned(ply, true)).to.beFalse()
			end
		}
	}
}
