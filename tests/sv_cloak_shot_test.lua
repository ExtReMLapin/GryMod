-- Tests of the real-shot notice (GryMod.CloakShooter and the hook EntityFireBullets, sv_system.lua), GLuaTest format, server realm. The camouflage
-- ends when the player shoots. Judging a key press by the numbers of the weapon (cl_hud.lua) can be wrong for a weapon whose rules are not
-- known, or got wrong (the shotgun's right click with its last shell fires a single shot); bullets leaving the weapon are the shot itself, and
-- the engine tells every addon through EntityFireBullets. The server sees it (the client's weapon code does not run in single player) and
-- tells the client, which ends the camouflage. Fake entities, the network is a recorder; the hook is called directly, never through hook.Run
-- (the other addons' hooks would get an empty bullet).

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

local function fakePlayer(mode, keys)
	local ply = {Nanosuit_mode = mode}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:IsWeapon() return false end
	function ply:KeyDown(key) return keys ~= nil and keys[key] == true end

	return ply
end

local function fakeWeapon(owner)
	local weapon = {}

	function weapon:IsValid() return true end
	function weapon:IsPlayer() return false end
	function weapon:IsWeapon() return true end
	function weapon:GetOwner() return owner end

	return weapon
end

local sent

return {
	groupName = "GryMod camouflage and the real shot (server)",
	beforeEach = function()
		sent = {}

		local ok, err = pcall(function()
			stub(net, "Start", function(name) sent[#sent + 1] = {name = name} end)
			stub(net, "WriteBool", function(value) sent[#sent].alt = value end)
			stub(net, "Send", function(target) sent[#sent].target = target end)
		end)

		if not ok then
			restore()
			error(err, 0)
		end
	end,
	afterEach = function()
		pcall(restore)
	end,
	cases = {
		{
			name = "a camouflaged player's bullets: his shot, from the left click",
			func = function()
				local ply = fakePlayer(GryMod.Modes.CLOAK, {[IN_ATTACK] = true})
				local shooter, alt = GryMod.CloakShooter(ply)
				expect(shooter).to.equal(ply)
				expect(alt).to.beFalse()
			end
		},
		{
			name = "from the right click alone it is an alt fire; with both keys down it is not",
			func = function()
				local _, alt = GryMod.CloakShooter(fakePlayer(GryMod.Modes.CLOAK, {[IN_ATTACK2] = true}))
				expect(alt).to.beTrue()

				_, alt = GryMod.CloakShooter(fakePlayer(GryMod.Modes.CLOAK, {[IN_ATTACK] = true, [IN_ATTACK2] = true}))
				expect(alt).to.beFalse()

				_, alt = GryMod.CloakShooter(fakePlayer(GryMod.Modes.CLOAK, {}))
				expect(alt).to.beFalse()
			end
		},
		{
			name = "a weapon that fires the bullets itself (a scripted weapon's self:FireBullets) counts for its owner",
			func = function()
				local ply = fakePlayer(GryMod.Modes.CLOAK, {[IN_ATTACK] = true})
				local shooter = GryMod.CloakShooter(fakeWeapon(ply))
				expect(shooter).to.equal(ply)
			end
		},
		{
			name = "nothing for a player out of the camouflage, for a weapon with no owner or a non-player owner, or for an entity that is gone",
			func = function()
				expect(GryMod.CloakShooter(fakePlayer(GryMod.Modes.ARMOR, {[IN_ATTACK] = true}))).to.beNil()
				expect(GryMod.CloakShooter(fakePlayer(nil, {}))).to.beNil()
				expect(GryMod.CloakShooter(fakeWeapon(nil))).to.beNil()

				local npc = {}
				function npc:IsValid() return true end
				function npc:IsPlayer() return false end
				function npc:IsWeapon() return false end
				expect(GryMod.CloakShooter(npc)).to.beNil()
				expect(GryMod.CloakShooter(fakeWeapon(npc))).to.beNil()

				local gone = fakePlayer(GryMod.Modes.CLOAK, {})
				function gone:IsValid() return false end
				expect(GryMod.CloakShooter(gone)).to.beNil()
				expect(GryMod.CloakShooter(nil)).to.beNil()
			end
		},
		{
			name = "the hook tells the shooter, with the alt fire flag, and leaves the bullets alone (no return value)",
			func = function()
				local hookFn = hook.GetTable().EntityFireBullets and hook.GetTable().EntityFireBullets.GryCloakShot
				expect(hookFn).to.exist()

				local ply = fakePlayer(GryMod.Modes.CLOAK, {[IN_ATTACK2] = true})
				local data = {Num = 7}
				local result = hookFn(ply, data)

				expect(result).to.beNil()
				expect(data.Num).to.equal(7)
				expect(#sent).to.equal(1)
				expect(sent[1].name).to.equal("gry_cloak_shot")
				expect(sent[1].alt).to.beTrue()
				expect(sent[1].target).to.equal(ply)
			end
		},
		{
			name = "the hook says nothing when nobody camouflaged fired: every bullet of the server goes through it",
			func = function()
				local hookFn = hook.GetTable().EntityFireBullets.GryCloakShot

				hookFn(fakePlayer(GryMod.Modes.ARMOR, {[IN_ATTACK] = true}), {})
				hookFn(fakeWeapon(fakePlayer(GryMod.Modes.SPEED, {})), {})
				hookFn(nil, {})

				expect(#sent).to.equal(0)
			end
		}
	}
}
