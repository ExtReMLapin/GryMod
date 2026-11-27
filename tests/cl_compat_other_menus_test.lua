-- Tests of the weapon menu providers of ARC9, ArcCW, CW 2.0 and FA:S 2 (lua/grymod/compat/weapons/cl_arc9_menu.lua, cl_arccw_menu.lua, cl_cw2_menu.lua, cl_fas2_menu.lua),
-- GLuaTest format, client realm. The way each base opens its customization menu was READ in its source code (the research of 2026-11-27: none of these bases is installed on
-- the machine, so none was tried in a game): ARC9 is opened by the weapon's ToggleCustomize(true), ArcCW by the console command arccw_toggle_inv, CW 2.0 by the weapon's
-- attemptToggleInteractionMenu (after canOpenInteractionMenu), FA:S 2 by the command fas2_togglegunpimper after the weapon's ShowStats is set the way its key sets it. The bases
-- are stood in for, so these cases pin what the providers answer to the bases' markers and what they call. Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function weapon(fields)
	local wep = {}

	function wep:IsValid() return true end

	for k, v in pairs(fields or {}) do
		wep[k] = v
	end

	return wep
end

local function console()
	local sent = {}

	stub(_G, "RunConsoleCommand", function(...) sent[#sent + 1] = table.concat({...}, " ") end)

	return sent
end

return {
	groupName = "GryMod compat: weapon menus of ARC9, ArcCW, CW 2.0 and FA:S 2",
	beforeEach = function()
		saved = {}
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the ARC9 provider answers for a weapon that is not ARC9's, or the opener does not call ToggleCustomize(true) (ARC9 has no console command: its key is a bind)
			name = "ARC9: an ARC9 weapon opens with ToggleCustomize(true); a weapon without the marker or without the function gets none",
			func = function()
				local API = GryMod.API
				local calls = {}
				local wep = weapon({ARC9 = true, ToggleCustomize = function(_, open) calls[#calls + 1] = open end})

				expect(API.GetWeaponMenu(wep)).to.beA("function")
				expect(API.OpenWeaponMenu(wep)).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1]).to.beTrue()

				expect(API.GetWeaponMenu(weapon({ToggleCustomize = function() end}))).to.beNil()
				expect(API.GetWeaponMenu(weapon({ARC9 = true}))).to.beNil()
			end
		},
		{
			-- fails when a knife, a machete or a grenade (the base gives them an empty Attachments table: nothing to customize) gets the customization menu, which would open an empty screen;
			-- a weapon with at least one slot, or one that does not declare the table at all, keeps it
			name = "ARC9: a weapon with no attachment slot (knife, grenade) gets no weapon menu; one with a slot, or with no table, keeps it",
			func = function()
				local API = GryMod.API
				local function arc9(attachments)
					return weapon({ARC9 = true, Attachments = attachments, ToggleCustomize = function() end})
				end

				expect(API.GetWeaponMenu(arc9({}))).to.beNil()
				expect(API.GetWeaponMenu(arc9({{PrintName = "Optic"}}))).to.beA("function")
				expect(API.GetWeaponMenu(arc9(nil))).to.beA("function")
			end
		},
		{
			-- fails when ArcCW's menu is offered while the server disables the customization (arccw_enable_customization -1), or the command sent is not arccw_toggle_inv
			name = "ArcCW: an ArcCW weapon opens with arccw_toggle_inv, unless arccw_enable_customization is -1",
			func = function()
				local API = GryMod.API
				local sent = console()
				local setting = {GetInt = function() return 1 end}
				local real = GetConVar

				stub(_G, "GetConVar", function(name) if name == "arccw_enable_customization" then return setting end return real(name) end)

				local wep = weapon({ArcCW = true})

				expect(API.OpenWeaponMenu(wep)).to.beTrue()
				expect(sent[1]).to.equal("arccw_toggle_inv")

				setting.GetInt = function() return -1 end
				expect(API.GetWeaponMenu(wep)).to.beNil()
				expect(API.GetWeaponMenu(weapon())).to.beNil()
			end
		},
		{
			-- fails when CW 2.0's own test of whether the menu can open is ignored (it refuses a weapon with no attachment, while reloading or running), or the opener does not use
			-- the weapon's own function
			name = "CW 2.0: a CW 2.0 weapon opens with attemptToggleInteractionMenu when canOpenInteractionMenu agrees; the command cw_customize is the fallback",
			func = function()
				local API = GryMod.API
				local opened = 0
				local can = true
				local wep = weapon({
					CW20Weapon = true,
					canOpenInteractionMenu = function() return can end,
					attemptToggleInteractionMenu = function() opened = opened + 1 end
				})

				expect(API.OpenWeaponMenu(wep)).to.beTrue()
				expect(opened).to.equal(1)

				can = false
				expect(API.GetWeaponMenu(wep)).to.beNil()

				local sent = console()
				local bare = weapon({CW20Weapon = true})

				expect(API.OpenWeaponMenu(bare)).to.beTrue()
				expect(sent[1]).to.equal("cw_customize")
				expect(API.GetWeaponMenu(weapon())).to.beNil()
			end
		},
		{
			-- fails when ShowStats is not set before the command (the menu opens on the wrong page, like the key's own code avoids), when the weapon that forbids the menu is offered
			-- one, or when a weapon of another base is
			name = "FA:S 2: an FA:S 2 weapon sets ShowStats then sends fas2_togglegunpimper; NoAttachmentMenu forbids it",
			func = function()
				local API = GryMod.API
				local sent = console()
				local plain = weapon({IsFAS2Weapon = true})
				local withAttachments = weapon({IsFAS2Weapon = true, Attachments = {}})

				expect(API.OpenWeaponMenu(plain)).to.beTrue()
				expect(plain.ShowStats).to.beTrue() -- no attachments: the page of the statistics
				expect(sent[1]).to.equal("fas2_togglegunpimper")

				expect(API.OpenWeaponMenu(withAttachments)).to.beTrue()
				expect(withAttachments.ShowStats).to.beFalse()

				expect(API.GetWeaponMenu(weapon({IsFAS2Weapon = true, NoAttachmentMenu = true}))).to.beNil()
				expect(API.GetWeaponMenu(weapon())).to.beNil()
			end
		}
	}
}
