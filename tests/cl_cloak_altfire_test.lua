-- Tests of the camouflage's right click (GryMod.CloackAttack and GryMod.AltFireShoots, cl_hud.lua), GLuaTest format,
-- client realm. The camouflage ends when the player shoots: the left click always, the right click only when the
-- weapon really fires with it (the shotgun's double barrel, the SMG grenade, the AR2 energy ball, the frag grenade's
-- lob). The crossbow's zoom and the other addons' weapons keep it. Fake players and weapons, the network is a recorder.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

local sent
local savedConVar

-- a player in the given suit mode holding a weapon: class, magazine, reserve of the primary and secondary ammo
local function fakePlayer(mode, class, clip1, primary, secondary)
	local ply = {NanosuitMode = mode, modeSet = {}}
	local weapon = {}

	function weapon:IsValid() return true end
	function weapon:GetClass() return class end
	function weapon:Clip1() return clip1 end
	function weapon:GetPrimaryAmmoType() return 1 end
	function weapon:GetSecondaryAmmoType() return 2 end

	function ply:GetActiveWeapon() return weapon end
	function ply:GetAmmoCount(kind) return kind == 1 and primary or secondary end
	function ply:SetNanosuitMode(newMode, networked)
		self.modeSet[#self.modeSet + 1] = {newMode, networked}
		self.NanosuitMode = newMode
	end

	return ply
end

return {
	groupName = "GryMod camouflage and the right click",
	beforeAll = function(state)
		savedConVar = GetConVar("gry_cloak_altfire"):GetString()
	end,
	beforeEach = function(state)
		sent = {}
		stub(net, "Start", function(name) sent[#sent + 1] = name end)
		stub(net, "SendToServer", function() end)
		GetConVar("gry_cloak_altfire"):SetString("1")
	end,
	afterEach = function(state)
		restore()
		GetConVar("gry_cloak_altfire"):SetString(savedConVar)
	end,
	cases = {
		{
			name = "the shotgun's right click shoots with at least two shells in the magazine",
			func = function(state)
				local shoots = GryMod.AltFireShoots
				expect(shoots("weapon_shotgun", 6, 0, 0)).to.beTrue()
				expect(shoots("weapon_shotgun", 2, 0, 0)).to.beTrue()
				expect(shoots("weapon_shotgun", 1, 30, 0)).to.beFalse()
				expect(shoots("weapon_shotgun", 0, 30, 0)).to.beFalse()
			end
		},
		{
			name = "the SMG grenade and the AR2 energy ball need ammo of the secondary type, whatever the magazine",
			func = function(state)
				local shoots = GryMod.AltFireShoots

				for _, class in ipairs({"weapon_smg1", "weapon_ar2"}) do
					expect(shoots(class, 30, 90, 3)).to.beTrue()
					expect(shoots(class, 0, 0, 1)).to.beTrue()
					expect(shoots(class, 30, 90, 0)).to.beFalse()
					expect(shoots(class, 30, 90, nil)).to.beFalse()
				end
			end
		},
		{
			name = "the frag grenade's lob needs a grenade left",
			func = function(state)
				local shoots = GryMod.AltFireShoots
				expect(shoots("weapon_frag", -1, 3, 0)).to.beTrue()
				expect(shoots("weapon_frag", -1, 1, 0)).to.beTrue()
				expect(shoots("weapon_frag", -1, 0, 0)).to.beFalse()
			end
		},
		{
			name = "the crossbow's zoom, unknown weapons and a missing class never count as a shot, whatever the ammo",
			func = function(state)
				local shoots = GryMod.AltFireShoots
				expect(shoots("weapon_crossbow", 1, 10, 10)).to.beFalse()
				expect(shoots("weapon_pistol", 18, 100, 100)).to.beFalse()
				expect(shoots("weapon_357", 6, 100, 100)).to.beFalse()
				expect(shoots("weapon_rpg", 1, 3, 3)).to.beFalse()
				expect(shoots("some_other_addon_swep", 30, 30, 30)).to.beFalse()
				expect(shoots(nil, 30, 30, 30)).to.beFalse()
			end
		},
		{
			name = "a right click with a shotgun that can fire ends the camouflage and empties the energy, like a left click",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 6, 30, 0)
				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)
				expect(ply.modeSet[1][2]).to.beTrue()
				expect(sent[1]).to.equal("gry_empty_energy")
			end
		},
		{
			name = "a right click that cannot shoot keeps the camouflage: shotgun with one shell, no grenade, crossbow, other addon",
			func = function(state)
				local cases = {
					{"weapon_shotgun", 1, 30, 0},
					{"weapon_smg1", 30, 90, 0},
					{"weapon_ar2", 30, 90, 0},
					{"weapon_frag", -1, 0, 0},
					{"weapon_crossbow", 1, 10, 10},
					{"some_other_addon_swep", 30, 30, 30}
				}

				for _, c in ipairs(cases) do
					local ply = fakePlayer(GryMod.Modes.CLOAK, c[1], c[2], c[3], c[4])
					GryMod.CloackAttack(ply, IN_ATTACK2)
					expect(#ply.modeSet).to.equal(0)
					expect(ply.NanosuitMode).to.equal(GryMod.Modes.CLOAK)
				end

				expect(#sent).to.equal(0)
			end
		},
		{
			name = "the left click still ends the camouflage with any weapon and any ammo",
			func = function(state)
				for _, class in ipairs({"weapon_crossbow", "weapon_shotgun", "some_other_addon_swep"}) do
					local ply = fakePlayer(GryMod.Modes.CLOAK, class, 0, 0, 0)
					GryMod.CloackAttack(ply, IN_ATTACK)
					expect(#ply.modeSet).to.equal(1)
				end

				expect(#sent).to.equal(3)
			end
		},
		{
			name = "outside the camouflage nothing happens, and a player with no weapon does not break the right click",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_shotgun", 6, 0, 0)
				GryMod.CloackAttack(ply, IN_ATTACK2)
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(0)

				local bare = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 6, 0, 0)
				bare.GetActiveWeapon = function() return NULL end
				GryMod.CloackAttack(bare, IN_ATTACK2)
				expect(#bare.modeSet).to.equal(0)
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "with gry_cloak_altfire 0 the right click keeps the camouflage even when the weapon fires, the left click does not",
			func = function(state)
				GetConVar("gry_cloak_altfire"):SetString("0")
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 6, 0, 0)
				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(0)
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(1)
			end
		},
		{
			name = "the key hook is on, and the switch is saved, on by default, with a check box in the options",
			func = function(state)
				expect(hook.GetTable().KeyPress["AttackDetection"]).to.equal(GryMod.CloackAttack)

				local convar = GetConVar("gry_cloak_altfire")
				expect(convar:GetDefault()).to.equal("1")

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_cloak_altfire"]).to.beTrue()
			end
		}
	}
}
