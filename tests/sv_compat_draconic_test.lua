-- Tests of the Draconic Base patches, server side (lua/grymod/compat/weapons/sv_draconic.lua), GLuaTest format, server realm. Four things: a projectile of the base that a camouflaged player
-- throws or fires, and a melee blow, end the camouflage (the server only sees bullets: Draconic's projectiles and its melee are not); the EMP of Draconic (DRC:EMP) puts the suit of a player down
-- (it only sets a flag on the target, GryMod never read it); and the base's own habit of putting the field of view back every 0.4 s (ShouldFixFOV) must not fight the suit's zoom. Draconic is
-- stood in for. Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function player_()
	return player.GetAll()[1]
end

local function entHook(name)
	return hook.GetTable()[name]["GryMod compat draconic"]
end

return {
	groupName = "GryMod compat: Draconic Base (server)",
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
		hook.Run("GryMod_Zoom", player_(), 0)
	end,
	cases = {
		{
			-- fails when a melee blow of a Draconic weapon by a camouflaged player does not end the camouflage, or when the blow of another weapon (no marker) does
			name = "a melee blow of a Draconic weapon is an attack (not a right click) that is reported; the damage of something else is not",
			func = function()
				local told = {}

				stub(GryMod.API, "ReportAttack", function(ply, right) told[#told + 1] = {ply, right} return true end)

				local function blow(inflictor, custom)
					local d = DamageInfo()

					d:SetAttacker(player_())
					d:SetInflictor(inflictor)
					d:SetDamageCustom(custom)
					d:SetDamage(25)

					return d
				end

				-- (the inflictor of a DamageInfo must be a real entity: a prop that wears the marker of Draconic's weapons)
				local weapon, plain = ents.Create("prop_physics"), ents.Create("prop_physics")

				weapon.Draconic = true

				local ok, err = pcall(function()
					entHook("EntityTakeDamage")({}, blow(weapon, 2221208))
					expect(#told).to.equal(1)
					expect(told[1][1]).to.equal(player_())
					expect(told[1][2]).to.equal(false)

					entHook("EntityTakeDamage")({}, blow(weapon, 0)) -- a bullet of the same weapon: the server saw it
					entHook("EntityTakeDamage")({}, blow(plain, 2221208))
					entHook("EntityTakeDamage")({}, blow(game.GetWorld(), 2221208))
					expect(#told).to.equal(1)
				end)

				weapon:Remove()
				plain:Remove()

				if not ok then error(err, 0) end
			end
		},
		{
			-- fails when a projectile of the base made by a player is not reported (a thrown grenade or a launcher shot would keep the camouflage), when a dropped magazine is, or when the
			-- projectile of a non-player is
			name = "a projectile of Draconic's base made by a player ends the camouflage; a dropped magazine and a projectile of a non-player do not",
			func = function()
				local told = {}
				local ply = player_()

				stub(GryMod.API, "ReportAttack", function(p, right) told[#told + 1] = {p, right} return true end)

				local function projectile(kind, owner)
					return {
						IsValid = function() return true end,
						GetOwner = function() return owner end,
						ProjectileType = kind
					}
				end

				local report = GryMod.DraconicSV.ReportProjectile

				report(projectile("grenade", ply))
				report(projectile("point", ply))
				expect(#told).to.equal(2)
				expect(told[1][2]).to.equal(false)

				report(projectile("magazine", ply))
				report(projectile("grenade", game.GetWorld()))
				report(projectile("grenade", nil))
				expect(#told).to.equal(2)
			end
		},
		{
			-- fails when the creation hook is not there, or reports at once (the owner is set after the creation: the player is not yet known), or reports a class that is not built on the base
			name = "the creation hook only looks at classes built on draconic_projectile_base, and looks at the owner one frame later",
			func = function()
				local S = GryMod.DraconicSV
				local realIsBasedOn = scripted_ents.IsBasedOn

				scripted_ents.IsBasedOn = function(class, base) return class == "t_drc_nade" and base == "draconic_projectile_base" end
				S.ClassCache = {}

				local ok, err = pcall(function()
					expect(S.IsProjectileClass("t_drc_nade")).to.beTrue()
					expect(S.IsProjectileClass("prop_physics")).to.beFalse()
					expect(S.IsProjectileClass(nil)).to.beFalse()
				end)

				scripted_ents.IsBasedOn = realIsBasedOn
				S.ClassCache = {}

				if not ok then error(err, 0) end
			end
		},
		{
			-- fails when the EMP of Draconic does nothing to the suit of a player, when the malfunction lasts another time than the EMP, when something that is not a player gets one, or when the
			-- original EMP is not run
			name = "an EMP of Draconic puts the suit of a player down for the same time, whatever the target, and runs the original",
			func = function()
				local ran, down = {}, {}
				local DRC_ = {EMP = function(self, src, tgt, thyme) ran[#ran + 1] = {src, tgt, thyme} end}

				stub(_G, "DRC", DRC_)
				stub(GryMod.API, "StartMalfunction", function(ply, seconds, reason) down[#down + 1] = {ply, seconds, reason} return true end)

				local H = GryMod.DraconicSV

				H.original = nil
				expect(H.InstallEMP()).to.beTrue()
				expect(H.InstallEMP()).to.beTrue() -- idempotent: the wrapper is not wrapped

				local ply = player_()

				DRC_:EMP("source", ply, 5)
				expect(#ran).to.equal(1)
				expect(#down).to.equal(1)
				expect(down[1][1]).to.equal(ply)
				expect(down[1][2]).to.equal(5)
				expect(down[1][3]).to.equal("emp")

				DRC_:EMP("source", game.GetWorld(), 5)
				DRC_:EMP("source", nil, 5)
				expect(#ran).to.equal(3)
				expect(#down).to.equal(1)

				H.original = nil
			end
		},
		{
			-- fails when Draconic is not installed and the install raises an error or says it is there
			name = "without Draconic the EMP install does nothing and says so",
			func = function()
				stub(_G, "DRC", nil)

				local ok, result = pcall(GryMod.DraconicSV.InstallEMP)

				expect(ok).to.beTrue()
				expect(result).to.beFalse()
			end
		},
		{
			-- fails when the weapon still asks to put the field of view back while the suit's zoom is held (the zoom is undone within 0.4 s), when it never asks again after the zoom, or when
			-- the weapon's own answer is changed in any other case
			name = "the weapon does not put the field of view back while the suit's zoom is up, and does as before otherwise",
			func = function()
				local ply = player_()
				local answers = 0
				local weapon = {Draconic = true, IsValid = function() return true end}

				function weapon:GetOwner() return ply end
				function weapon:ShouldFixFOV() answers = answers + 1 return true end

				local S = GryMod.DraconicSV

				S.PatchWeapon(weapon)
				expect(weapon:ShouldFixFOV()).to.beTrue()

				hook.Run("GryMod_Zoom", ply, 30)
				expect(weapon:ShouldFixFOV()).to.equal(false)

				hook.Run("GryMod_Zoom", ply, 0)
				expect(weapon:ShouldFixFOV()).to.beTrue()
			end
		},
		{
			-- fails when patching twice wraps the wrapper (the original would be asked twice, and a weapon patched many times by the equip hook would slow down), or when a weapon that is not
			-- Draconic's is touched
			name = "a weapon is patched once, and only a Draconic weapon",
			func = function()
				local calls = 0
				local weapon = {Draconic = true, IsValid = function() return true end}

				function weapon:GetOwner() return player_() end
				function weapon:ShouldFixFOV() calls = calls + 1 return true end

				local S = GryMod.DraconicSV

				S.PatchWeapon(weapon)

				local first = weapon.ShouldFixFOV

				S.PatchWeapon(weapon)
				expect(weapon.ShouldFixFOV).to.equal(first)
				weapon:ShouldFixFOV()
				expect(calls).to.equal(1)

				local other = {IsValid = function() return true end}

				function other:ShouldFixFOV() return true end

				local original = other.ShouldFixFOV

				S.PatchWeapon(other)
				S.PatchWeapon({})
				S.PatchWeapon(nil)
				expect(other.ShouldFixFOV).to.equal(original)
			end
		}
	}
}
