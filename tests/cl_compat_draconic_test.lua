-- Tests of the Draconic Base patches, client side (lua/grymod/compat/weapons/cl_draconic.lua), GLuaTest format, client realm. Draconic is a weapon base that keeps its fire mode in a networked
-- integer (CurFireMode: 1 semi-automatic, 2 automatic, 3 burst) and has melee weapons (the fists, IsMelee).
-- The cases use stand-ins for the weapon (the real weapons are tried in the game, see the report). Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a Draconic weapon stand-in; the call must ask the networked integer by its name
local function draconic(mode, fields)
	local w = {Draconic = true}

	function w:IsValid() return true end
	function w:GetClass() return "test_draconic_gun" end
	function w:GetNW2Int(key, default)
		expect(key).to.equal("CurFireMode")

		return mode
	end

	for k, v in pairs(fields or {}) do
		w[k] = v
	end

	return w
end

return {
	groupName = "GryMod compat: Draconic Base (client)",
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when no resolver is added (the burst gun shows the icon of its Primary.Automatic, which Draconic clears in burst), or when a mode is mapped to the wrong icon
			name = "the fire mode icon follows Draconic's CurFireMode: 1 single, 2 auto, 3 burst",
			func = function()
				local M = GryMod.FlashHUD

				expect(M.FireModeFor(draconic(1))).to.equal("Single")
				expect(M.FireModeFor(draconic(2))).to.equal("Auto")
				expect(M.FireModeFor(draconic(3))).to.equal("Burst")
			end
		},
		{
			-- fails when a melee weapon (the fists) shows a gun
			name = "a Draconic melee weapon shows no gun",
			func = function()
				expect(GryMod.FlashHUD.FireModeFor(draconic(1, {IsMelee = true}))).to.equal("NoGun")
			end
		},
		{
			-- fails when the resolver answers for a weapon that is not Draconic's (its own icon would be changed), or a Draconic stand-in without the integer raises an error
			name = "a weapon that is not Draconic's keeps its own icon",
			func = function()
				local other = {IsValid = function() return true end, GetClass = function() return "test_other_gun" end, Primary = {Automatic = true}}

				function other:GetNW2Int() error("asked") end

				expect(GryMod.FlashHUD.FireModeFor(other)).to.equal("Auto")
			end
		}
	}
}
