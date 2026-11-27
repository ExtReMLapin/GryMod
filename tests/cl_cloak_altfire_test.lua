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
local timers
local savedConVar

-- a player in the given suit mode holding a weapon: class, magazine, reserve of the primary and secondary ammo; extra (all
-- optional): nextPrimary / nextSecondary (seconds from now when the weapon may fire again, default -1: it may fire),
-- noAmmoType (a weapon with no ammo of its own, like the crowbar), held (the attack key is still down), noSnapshot (the
-- numbers of the weapon were not read at the last command without attack: a weapon that came in the last command)
local function fakePlayer(mode, class, clip1, primary, secondary, extra)
	extra = extra or {}

	local ply = {NanosuitMode = mode, modeSet = {}, extra = extra}
	local weapon = {}

	function weapon:IsValid() return true end
	function weapon:GetClass() return class end
	function weapon:Clip1() return clip1 end
	function weapon:GetPrimaryAmmoType() return extra.noAmmoType and -1 or 1 end
	function weapon:GetSecondaryAmmoType() return 2 end
	function weapon:GetNextPrimaryFire() return CurTime() + (extra.nextPrimary or -1) end
	function weapon:GetNextSecondaryFire() return CurTime() + (extra.nextSecondary or -1) end

	function ply:GetActiveWeapon() return ply.weapon or weapon end
	function ply:KeyDown(key) return key == IN_ATTACK and extra.held == true end
	function ply:GetAmmoCount(kind) return kind == 1 and primary or secondary end
	function ply:SetNanosuitMode(newMode, networked)
		self.modeSet[#self.modeSet + 1] = {newMode, networked}
		self.NanosuitMode = newMode
	end

	if not extra.noSnapshot then
		GryMod.CloakSnapshot(ply)
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
		timers = {}

		-- a stub must never stay when this step fails half way
		local ok, err = pcall(function()
			stub(net, "Start", function(name) sent[#sent + 1] = name end)
			stub(net, "SendToServer", function() end)
			stub(timer, "Simple", function(delay, func) timers[#timers + 1] = {delay = delay, func = func} end)
			GetConVar("gry_cloak_altfire"):SetString("1")
		end)

		if not ok then
			restore()
			error(err, 0)
		end
	end,
	afterEach = function(state)
		pcall(function() GryMod.API.UnregisterWeapon("t_alt_gun") end)
		pcall(restore)
		pcall(function() GetConVar("gry_cloak_altfire"):SetString(savedConVar) end)
	end,
	cases = {
		{
			name = "the shotgun's right click shoots with any shell in the magazine: both barrels with two or more, a single shot with the last one (the engine's own rule), nothing with none",
			func = function(state)
				local shoots = GryMod.AltFireShoots
				expect(shoots("weapon_shotgun", 6, 0, 0)).to.beTrue()
				expect(shoots("weapon_shotgun", 2, 0, 0)).to.beTrue()
				-- with one shell left the right click fires a single shot (measured by the owner: a shot goes off, the camouflage must end)
				expect(shoots("weapon_shotgun", 1, 30, 0)).to.beTrue()
				expect(shoots("weapon_shotgun", 1, 0, 0)).to.beTrue()
				-- an empty magazine reloads (or dry fires): no shot
				expect(shoots("weapon_shotgun", 0, 30, 0)).to.beFalse()
				expect(shoots("weapon_shotgun", 0, 0, 0)).to.beFalse()
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
			-- the table of the stock weapons is gone: the registry says what each secondary is, for an addon's weapon as well
			name = "a weapon registered through RegisterWeapon counts like the stock ones, by what its secondary is",
			func = function(state)
				local shoots = GryMod.AltFireShoots
				local API = GryMod.API

				API.RegisterWeapon("t_alt_gun", {alt = "grenade", altAmmo = "SMG1_Grenade"})
				expect(shoots("t_alt_gun", 30, 90, 2)).to.beTrue()
				expect(shoots("t_alt_gun", 30, 90, 0)).to.beFalse()

				API.RegisterWeapon("t_alt_gun", {alt = "energy", altAmmo = "AR2AltFire"})
				expect(shoots("t_alt_gun", 30, 90, 1)).to.beTrue()
				expect(shoots("t_alt_gun", 30, 90, 0)).to.beFalse()

				API.RegisterWeapon("t_alt_gun", {alt = "doublebarrel"})
				expect(shoots("t_alt_gun", 2, 0, 0)).to.beTrue()
				expect(shoots("t_alt_gun", 1, 30, 0)).to.beTrue() -- the last shell is a single shot
				expect(shoots("t_alt_gun", 0, 30, 0)).to.beFalse()

				API.RegisterWeapon("t_alt_gun", {alt = "throwlow"})
				expect(shoots("t_alt_gun", -1, 1, 0)).to.beTrue()
				expect(shoots("t_alt_gun", -1, 0, 0)).to.beFalse()

				-- a secondary that fires a shot with its own ammo, or with none
				API.RegisterWeapon("t_alt_gun", {alt = "shoot", altAmmo = "Gauss"})
				expect(shoots("t_alt_gun", 30, 90, 1)).to.beTrue()
				expect(shoots("t_alt_gun", 30, 90, 0)).to.beFalse()
				API.RegisterWeapon("t_alt_gun", {alt = "shoot"})
				expect(shoots("t_alt_gun", 0, 0, 0)).to.beTrue()

				-- a zoom, nothing: no shot; a swing counts only when the weapon says altShoots = true (a blow is an attack); altShoots = false turns a shooting secondary off
				for _, alt in ipairs({"zoom", "melee", "none"}) do
					API.RegisterWeapon("t_alt_gun", {alt = alt})
					expect(shoots("t_alt_gun", 30, 90, 90)).to.beFalse()
				end

				API.RegisterWeapon("t_alt_gun", {alt = "melee", altShoots = true})
				expect(shoots("t_alt_gun", -1, 0, 0)).to.beTrue()
				API.RegisterWeapon("t_alt_gun", {alt = "melee", altShoots = false})
				expect(shoots("t_alt_gun", -1, 0, 0)).to.beFalse()

				API.RegisterWeapon("t_alt_gun", {alt = "grenade", altAmmo = "SMG1_Grenade", altShoots = false})
				expect(shoots("t_alt_gun", 30, 90, 3)).to.beFalse()
			end
		},
		{
			-- fails when the fists do not declare their right click as a blow in the registry (alt "melee", altShoots true), when AltFireShoots does not count a declared swing (the
			-- owner's report: the right click of the fists did not end the camouflage), or when the crowbar's or the stun baton's right click counts (measured: it does nothing in the
			-- game, no swing, no cooldown: a click that does nothing must not end the camouflage)
			name = "the right click of the fists is a blow and counts as a shot; the crowbar's and the stun baton's does nothing in the game and does not",
			func = function(state)
				expect(GryMod.AltFireShoots("weapon_fists", -1, 0, 0)).to.beTrue()
				expect(GryMod.AltFireShoots("weapon_fists", -1, 0, nil)).to.beTrue() -- no ammo of any kind, nothing to count

				for _, class in ipairs({"weapon_crowbar", "weapon_stunstick", "weapon_physcannon", "weapon_crossbow"}) do
					expect(GryMod.AltFireShoots(class, -1, 0, 0)).to.beFalse()
				end
			end
		},
		{
			name = "a right click with the fists ends the camouflage and empties the energy, like the left click; with the crowbar or the stun baton only the left click does",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_fists", -1, 0, 0, {noAmmoType = true})

				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)

				for _, class in ipairs({"weapon_fists", "weapon_crowbar", "weapon_stunstick"}) do
					local left = fakePlayer(GryMod.Modes.CLOAK, class, -1, 0, 0, {noAmmoType = true})

					GryMod.CloackAttack(left, IN_ATTACK)
					expect(#left.modeSet).to.equal(1)
				end

				for _, class in ipairs({"weapon_crowbar", "weapon_stunstick"}) do
					local right = fakePlayer(GryMod.Modes.CLOAK, class, -1, 0, 0, {noAmmoType = true})

					GryMod.CloackAttack(right, IN_ATTACK2)
					expect(#right.modeSet).to.equal(0)
				end
			end
		},
		{
			-- fails when the swing of the right click ignores the weapon being drawn or the player's own switch (gry_cloak_altfire 0)
			name = "the right click of the fists keeps the camouflage while the weapon is drawn, and with gry_cloak_altfire at 0",
			func = function(state)
				local drawing = fakePlayer(GryMod.Modes.CLOAK, "weapon_fists", -1, 0, 0, {noAmmoType = true, nextSecondary = 0.5})

				GryMod.CloackAttack(drawing, IN_ATTACK2)
				expect(#drawing.modeSet).to.equal(0)

				GetConVar("gry_cloak_altfire"):SetString("0")

				local off = fakePlayer(GryMod.Modes.CLOAK, "weapon_fists", -1, 0, 0, {noAmmoType = true})

				GryMod.CloackAttack(off, IN_ATTACK2)
				expect(#off.modeSet).to.equal(0)
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
			name = "a right click that cannot shoot keeps the camouflage: shotgun with no shell, no grenade, crossbow, other addon",
			func = function(state)
				local cases = {
					{"weapon_shotgun", 0, 30, 0},
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
			name = "the left click still ends the camouflage with any weapon that is ready and has a round",
			func = function(state)
				for _, class in ipairs({"weapon_crossbow", "weapon_shotgun", "some_other_addon_swep"}) do
					local ply = fakePlayer(GryMod.Modes.CLOAK, class, 1, 0, 0)
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
			name = "AttackShoots: a press counts only when the weapon may fire and has a round (pure)",
			func = function(state)
				local shoots = GryMod.AttackShoots
				local now = 100
				expect(shoots(99, now, 17, 1, 50)).to.beTrue() -- ready, rounds in the magazine
				expect(shoots(100, now, 1, 1, 0)).to.beTrue() -- ready at this very tick, last round
				expect(shoots(100.2, now, 17, 1, 50)).to.beFalse() -- the weapon is being drawn or cooling down
				expect(shoots(99, now, 0, 1, 50)).to.beFalse() -- empty magazine: the weapon reloads, nothing is fired
				expect(shoots(99, now, -1, 1, 0)).to.beFalse() -- no magazine and no grenade left
				expect(shoots(99, now, -1, 1, 2)).to.beTrue() -- the frag grenade
				expect(shoots(99, now, -1, -1, 0)).to.beTrue() -- the crowbar: no ammo of its own
				expect(shoots(0, now, -1, -1, 0)).to.beTrue() -- a weapon that never sets a next fire time
				expect(shoots(nil, now, nil, nil, nil)).to.beTrue() -- unknown numbers: as before, the press counts
			end
		},
		{
			name = "Issue: a click while the new weapon is drawn does not end the camouflage (it fires nothing)",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0, {nextPrimary = 0.1})
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(0)
				expect(ply.NanosuitMode).to.equal(GryMod.Modes.CLOAK)
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "a click with an empty magazine, or a grenade weapon with no grenade, or no weapon in hand, keeps the camouflage",
			func = function(state)
				local empty = fakePlayer(GryMod.Modes.CLOAK, "weapon_pistol", 0, 50, 0)
				GryMod.CloackAttack(empty, IN_ATTACK)
				expect(#empty.modeSet).to.equal(0)

				local noGrenade = fakePlayer(GryMod.Modes.CLOAK, "weapon_frag", -1, 0, 0)
				GryMod.CloackAttack(noGrenade, IN_ATTACK)
				expect(#noGrenade.modeSet).to.equal(0)

				local bare = fakePlayer(GryMod.Modes.CLOAK, "weapon_pistol", 1, 0, 0)
				bare.GetActiveWeapon = function() return NULL end
				GryMod.CloackAttack(bare, IN_ATTACK)
				expect(#bare.modeSet).to.equal(0)
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "a click with a ready weapon still ends the camouflage: the crowbar, the frag grenade, a pistol",
			func = function(state)
				local cases = {
					{fakePlayer(GryMod.Modes.CLOAK, "weapon_crowbar", -1, 0, 0, {noAmmoType = true})},
					{fakePlayer(GryMod.Modes.CLOAK, "weapon_frag", -1, 3, 0)},
					{fakePlayer(GryMod.Modes.CLOAK, "weapon_pistol", 17, 100, 0)}
				}

				for _, c in ipairs(cases) do
					GryMod.CloackAttack(c[1], IN_ATTACK)
					expect(#c[1].modeSet).to.equal(1)
				end

				expect(#sent).to.equal(3)
			end
		},
		{
			name = "ShotSince: a shot moves the next fire time on or lowers the magazine (pure)",
			func = function(state)
				local since = GryMod.ShotSince
				expect(since(100, 17, 100.7, 17)).to.beTrue() -- the time moved on
				expect(since(100, 17, 100, 16)).to.beTrue() -- the magazine dropped
				expect(since(100, -1, 100.5, -1)).to.beTrue() -- no magazine: the time
				expect(since(100, 17, 100, 17)).to.beFalse() -- nothing moved
				expect(since(100, -1, 100, -1)).to.beFalse()
				expect(since(100, 0, 100, 0)).to.beFalse()
			end
		},
		{
			name = "the press is judged by the weapon before it ran the press: the weapon already fired when KeyPress comes (measured)",
			func = function(state)
				-- the snapshot of the start of the command: ready, with rounds
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0)
				GryMod.CloakSnapshot(ply)

				-- then the weapon fired: its next fire time is ahead and the magazine is one lower
				ply.extra.nextPrimary = 0.75
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)
				expect(sent[1]).to.equal("gry_empty_energy")
			end
		},
		{
			name = "a click during the draw, seen by its snapshot, keeps the camouflage",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0, {nextPrimary = 0.1})
				GryMod.CloakSnapshot(ply)
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(0)
			end
		},
		{
			name = "the shotgun's double barrel with two shells ends the camouflage although the magazine is empty when KeyPress comes",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 2, 30, 0)
				GryMod.CloakSnapshot(ply)
				ply.extra.nextSecondary = 1 -- the weapon fired both barrels
				ply.weapon = nil
				local weapon = ply:GetActiveWeapon()
				weapon.Clip1 = function() return 0 end
				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(1)
			end
		},
		{
			name = "a press during the draw that is still held ends the camouflage when the weapon fires, with a timer and no polling",
			func = function(state)
				local now = 100
				stub(_G, "CurTime", function() return now end)

				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0, {nextPrimary = 0.1, held = true})
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(0)
				expect(#timers).to.equal(1)
				expect(timers[1].delay).to.beGreaterThan(0.09)
				expect(timers[1].delay).to.beLessThan(0.5)

				-- the weapon became ready at 100.1, fired at once (the key is held): its next fire time is ahead
				now = 100.14
				ply.extra.nextPrimary = 0.8
				timers[1].func()
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)
				expect(sent[1]).to.equal("gry_empty_energy")
			end
		},
		{
			name = "the late check keeps the camouflage when the key was let go, the suit left it, the weapon changed or nothing was fired",
			func = function(state)
				local now = 100
				stub(_G, "CurTime", function() return now end)
				local function press(extra)
					local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0, extra)
					GryMod.CloackAttack(ply, IN_ATTACK)

					return ply
				end

				local released = press({nextPrimary = 0.1, held = false})
				local left = press({nextPrimary = 0.1, held = true})
				local swapped = press({nextPrimary = 0.1, held = true})
				local dry = press({nextPrimary = 0.1, held = true}) -- ready later, but nothing is fired (the weapon does not move on)

				now = 100.5
				for _, ply in ipairs({released, left, swapped, dry}) do
					ply.extra.nextPrimary = -0.4 -- still the old ready time: nothing was fired
				end

				left.extra.nextPrimary = 0.8
				left.NanosuitMode = GryMod.Modes.SPEED
				swapped.extra.nextPrimary = 0.8
				swapped.weapon = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1", 30, 90, 0, {nextPrimary = 0.5, held = true}):GetActiveWeapon()
				released.extra.nextPrimary = 0.8

				for i = 1, 4 do
					timers[i].func()
				end

				expect(#released.modeSet).to.equal(0)
				expect(#left.modeSet).to.equal(0)
				expect(#swapped.modeSet).to.equal(0)
				expect(#dry.modeSet).to.equal(0)
				expect(#sent).to.equal(0)
				expect(#timers).to.equal(4) -- the late check does not set another timer once the weapon is ready
			end
		},
		{
			name = "a right click during the draw keeps the camouflage even when the weapon would fire with it",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 6, 30, 0, {nextSecondary = 0.3})
				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(0)

				local ready = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 6, 30, 0)
				GryMod.CloackAttack(ready, IN_ATTACK2)
				expect(#ready.modeSet).to.equal(1)
			end
		},
		{
			name = "a weapon with no snapshot (it came in the last command): the press counts as it always did",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_357", 6, 20, 0, {nextPrimary = 0.1, noSnapshot = true})
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(1)
			end
		},
		{
			name = "the snapshot hook is on and only works in the camouflage",
			func = function(state)
				local fn = hook.GetTable().StartCommand["GryCloakSnapshot"]
				expect(isfunction(fn)).to.beTrue()

				local function counted(mode)
					local called = 0
					local ply = fakePlayer(mode, "weapon_pistol", 17, 0, 0, {noSnapshot = true})
					local original = ply.GetActiveWeapon
					ply.GetActiveWeapon = function(...) called = called + 1 return original(...) end

					return ply, function() return called end
				end

				local function cmdWith(attack, attack2)
					return {KeyDown = function(_, key) return (key == IN_ATTACK and attack) or (key == IN_ATTACK2 and attack2) or false end}
				end

				local armor, armorCalls = counted(GryMod.Modes.ARMOR)
				fn(armor, cmdWith(false, false))
				expect(armorCalls()).to.equal(0) -- not in the camouflage: nothing is read

				local idle, idleCalls = counted(GryMod.Modes.CLOAK)
				fn(idle, cmdWith(false, false))
				expect(idleCalls()).to.equal(1)

				-- a command that presses an attack key does not replace the numbers read before the press
				local pressing, pressingCalls = counted(GryMod.Modes.CLOAK)
				fn(pressing, cmdWith(true, false))
				fn(pressing, cmdWith(false, true))
				expect(pressingCalls()).to.equal(0)
			end
		},
		{
			name = "firing out of the camouflage plays the glitch at 15 % energy as at 40 %, once (the old rule: only the 40)",
			func = function(state)
				local FX = GryMod.DamageFx
				local realShake = FX.Shake
				local saved = GetConVar("gry_decloak_glitch"):GetString()
				local shakes = 0

				local ok, err = pcall(function()
					GetConVar("gry_decloak_glitch"):SetString("1")
					FX.Shake = function() shakes = shakes + 1 end

					for _, energy in ipairs({15, 40}) do
						shakes = 0
						FX.Reset(FX.State)

						-- the HUD has seen the player at that energy, in the camouflage (not armor mode: no hit possible)
						local sample = {health = 100, max = 100, energy = energy, armor = false}
						FX.Observe(FX.State, sample, 0, FX.Options())

						-- the shot: the suit goes back to armor mode at once, the server empties the bar a little later
						local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_pistol", 17, 100, 0)
						GryMod.CloackAttack(ply, IN_ATTACK)
						expect(#ply.modeSet).to.equal(1)

						sample.armor = true
						FX.Observe(FX.State, sample, 0.02, FX.Options())
						sample.energy = 0
						FX.Observe(FX.State, sample, 0.1, FX.Options())

						expect(shakes).to.equal(1)
						expect(FX.State.armorAt ~= nil).to.beTrue()
					end
				end)

				FX.Shake = realShake
				pcall(function() GetConVar("gry_decloak_glitch"):SetString(saved) end)
				pcall(FX.Reset, FX.State)

				if not ok then
					error(err, 0)
				end
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
		},
		{
			name = "a right click with the shotgun's last shell ends the camouflage and empties the energy, like any shot (the owner's bug)",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 1, 30, 0)
				GryMod.CloackAttack(ply, IN_ATTACK2)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)
				expect(sent[1]).to.equal("gry_empty_energy")
			end
		},
		{
			name = "CloakShot: a real shot reported by the server ends the camouflage, once, whatever the weapon's rules say",
			func = function(state)
				expect(GryMod.CloakShot).to.exist()

				-- a weapon no rule knows, a magazine the rules call empty: the server saw bullets leave
				local ply = fakePlayer(GryMod.Modes.CLOAK, "some_other_addon_swep", 0, 0, 0)
				GryMod.CloakShot(ply, false)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.NanosuitMode).to.equal(GryMod.Modes.ARMOR)
				expect(sent[1]).to.equal("gry_empty_energy")

				-- the key press and the server both saw it: the second one finds the suit out of the camouflage already
				GryMod.CloakShot(ply, false)
				expect(#ply.modeSet).to.equal(1)
				expect(#sent).to.equal(1)
			end
		},
		{
			name = "CloakShot: a right click shot keeps the camouflage when the player turned gry_cloak_altfire off; a left click shot never does",
			func = function(state)
				GetConVar("gry_cloak_altfire"):SetString("0")

				local right = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 2, 0, 0)
				GryMod.CloakShot(right, true)
				expect(#right.modeSet).to.equal(0)

				local left = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 2, 0, 0)
				GryMod.CloakShot(left, false)
				expect(#left.modeSet).to.equal(1)

				GetConVar("gry_cloak_altfire"):SetString("1")
				local again = fakePlayer(GryMod.Modes.CLOAK, "weapon_shotgun", 2, 0, 0)
				GryMod.CloakShot(again, true)
				expect(#again.modeSet).to.equal(1)
			end
		},
		{
			name = "CloakShot: outside the camouflage nothing happens",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_shotgun", 6, 0, 0)
				GryMod.CloakShot(ply, false)
				expect(#ply.modeSet).to.equal(0)
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "the server's shot notice is received",
			func = function(state)
				expect(net.Receivers["gry_cloak_shot"] ~= nil).to.beTrue()
			end
		}
	}
}
