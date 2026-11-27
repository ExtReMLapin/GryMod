-- Tests of the TFA weapon menu provider (lua/grymod/compat/weapons/cl_tfa_menu.lua), GLuaTest format, client realm. TFA's inspection menu (the attachments, the ammunition) is
-- opened by the impulse TFA.INSPECTION_IMPULSE (TFA's own key does exactly that, tfa_hooks.lua). The provider answers an opener only for a TFA weapon that has the
-- menu (ToggleInspect) while the server allows it (sv_tfa_cmenu), and the opener sends that impulse. A weapon of another base gets nothing. TFA is stood in for, so the
-- cases run without it. Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function weapon(fields)
	local wep = {IsTFAWeapon = true, ToggleInspect = function() end}

	function wep:IsValid() return true end

	for k, v in pairs(fields or {}) do
		wep[k] = v
	end

	return wep
end

return {
	groupName = "GryMod compat: TFA weapon menu",
	beforeEach = function()
		saved = {}
		stub(_G, "TFA", {INSPECTION_IMPULSE = 205})
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the provider is not registered, or answers for a weapon that is not TFA's (the quick menu would send a TFA impulse to another base's weapon)
			name = "a TFA weapon gets an opener, a weapon of another base or a stand-in without the menu gets none",
			func = function()
				local API = GryMod.API

				expect(API.GetWeaponMenu(weapon())).to.beA("function")
				expect(API.GetWeaponMenu(weapon({IsTFAWeapon = false}))).to.beNil()
				local plain = weapon()

				plain.IsTFAWeapon = nil -- a weapon of another base has no marker (a nil field cannot be passed through the constructor)
				expect(API.GetWeaponMenu(plain)).to.beNil()
				expect(API.GetWeaponMenu(weapon({ToggleInspect = false}))).to.beNil()
			end
		},
		{
			-- fails when the opener does not send TFA's own impulse (the menu would not open), or sends it with the wrong number
			name = "the opener sends TFA's inspection impulse",
			func = function()
				local sent = {}

				stub(_G, "RunConsoleCommand", function(...) sent[#sent + 1] = {...} end)

				local wep = weapon()

				expect(GryMod.API.OpenWeaponMenu(wep)).to.beTrue()
				expect(#sent).to.equal(1)
				expect(sent[1][1]).to.equal("impulse")
				expect(sent[1][2]).to.equal("205")
			end
		},
		{
			-- fails when the server's setting that forbids the menu (sv_tfa_cmenu 0) is not respected: the quick menu would show an icon that does nothing
			name = "no opener while the server forbids TFA's menu (sv_tfa_cmenu 0), and none when TFA's impulse is not known",
			func = function()
				local cmenu = {GetBool = function() return false end}
				local real = GetConVar

				stub(_G, "GetConVar", function(name) if name == "sv_tfa_cmenu" then return cmenu end return real(name) end)
				expect(GryMod.API.GetWeaponMenu(weapon())).to.beNil()

				cmenu.GetBool = function() return true end
				expect(GryMod.API.GetWeaponMenu(weapon())).to.beA("function")

				stub(_G, "TFA", {})
				expect(GryMod.API.GetWeaponMenu(weapon())).to.beNil()

				stub(_G, "TFA", nil)
				expect(GryMod.API.GetWeaponMenu(weapon())).to.beNil()
			end
		}
	}
}
