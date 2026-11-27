-- Tests of the Draconic Base patches, client side (lua/grymod/compat/weapons/cl_draconic.lua), GLuaTest format, client realm. Draconic is a weapon base that keeps its fire mode in a networked
-- integer (CurFireMode: 1 semi-automatic, 2 automatic, 3 burst), has melee weapons (the fists, IsMelee) and draws a crosshair of its own (the hook HUDPaint "drc_crosshair") over the one of GryMod.
-- The cases use stand-ins for the weapon and for Draconic's hook (the real weapons are tried in the game, see the report). Each case names the change that makes it fail.

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
		},
		{
			-- fails when the option does not exist, is not saved, is off by default (two crosshairs one over the other) or has no check box on the Draconic tab of the Compatibility page
			name = "gry_draconic_hide_crosshair: a saved client setting, on by default",
			func = function()
				local cvar = GetConVar("gry_draconic_hide_crosshair")

				expect(cvar ~= nil).to.beTrue()
				expect(cvar:GetDefault()).to.equal("1")
				expect(cvar:GetFlags()).to.equal(GetConVar("gry_binoculars_no_fire"):GetFlags())
			end
		},
		{
			-- fails when Draconic's crosshair is still drawn with the option on and GryMod's crosshair up, when it is hidden with the option off, with GryMod's HUD off, with the crosshair
			-- element switched off by the player (no crosshair at all), or when the wrapper is put on the wrapper at a second install
			name = "Draconic's crosshair is not drawn with the option on and GryMod's crosshair up, and is drawn in every other case",
			func = function()
				local H = GryMod.DraconicHUD
				local drawn = 0
				local table_ = hook.GetTable().HUDPaint
				local before = table_ and table_["drc_crosshair"]
				local before_original = H.original

				hook.Add("HUDPaint", "drc_crosshair", function() drawn = drawn + 1 end)
				H.original = nil
				expect(H.Install()).to.beTrue()
				expect(H.Install()).to.beTrue() -- idempotent

				local hudUp, crosshairOn = true, true

				stub(GryMod.FlashHUD, "Enabled", function() return hudUp end)
				stub(GryMod.HUDOptions, "Enabled", function(name) return name ~= "crosshair" or crosshairOn end)

				local cvar = GetConVar("gry_draconic_hide_crosshair")
				local was = cvar:GetString()
				local ok, err = pcall(function()
					local function draw()
						drawn = 0
						hook.GetTable().HUDPaint["drc_crosshair"]()

						return drawn
					end

					cvar:SetString("1")
					expect(draw()).to.equal(0)

					cvar:SetString("0")
					expect(draw()).to.equal(1)

					cvar:SetString("1")
					hudUp = false
					expect(draw()).to.equal(1)

					hudUp, crosshairOn = true, false
					expect(draw()).to.equal(1)
				end)

				cvar:SetString(was)
				hook.Add("HUDPaint", "drc_crosshair", before)
				H.original = before_original

				if not before then hook.Remove("HUDPaint", "drc_crosshair") end
				if not ok then error(err, 0) end
			end
		},
		{
			-- fails when Install raises an error or does something when Draconic is not installed (no hook of that name)
			name = "without Draconic's hook the install does nothing and says so",
			func = function()
				local H = GryMod.DraconicHUD
				local table_ = hook.GetTable().HUDPaint
				local before = table_ and table_["drc_crosshair"]

				hook.Remove("HUDPaint", "drc_crosshair")

				local ok, result = pcall(H.Install)

				if before then hook.Add("HUDPaint", "drc_crosshair", before) end

				expect(ok).to.beTrue()
				expect(result).to.beFalse()
			end
		}
	}
}
