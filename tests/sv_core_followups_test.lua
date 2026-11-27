-- Tests of the follow-ups of the ecosystem work in the core (server realm, GLuaTest format): GryMod.API.ReportShot (an attack that makes the shot's noise too), the rule of whose shot a
-- vehicle's bullet is (a turret that its creator is not sitting in does not end his camouflage), the ring of util.BlastDamageInfo (Glide's explosions), a provider that says "nobody
-- drives" (driver = false: no fall back to the entity's own GetDriver) and the `heavy` field as a function. The stand-ins are put back in afterEach inside a pcall; each case names the
-- change whose absence makes it fail.

local API, Mech, R
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function ply()
	return player.GetAll()[1]
end

-- Runs fn with the network recorded: returns what fn returned and the messages {name, bool}.
local function recorded(fn)
	local sent = {}
	local realStart, realSend, realWriteBool = net.Start, net.Send, net.WriteBool

	net.Start = function(name)
		sent[#sent + 1] = {name = name}

		return true
	end
	net.WriteBool = function(value)
		if sent[#sent] then
			sent[#sent].bool = value
		end
	end
	net.Send = function(to)
		if sent[#sent] then
			sent[#sent].to = to
		end
	end

	local ok, a = pcall(fn)

	net.Start, net.Send, net.WriteBool = realStart, realSend, realWriteBool
	assert(ok, a)

	return a, sent
end

local function shotMessages(sent)
	local list = {}

	for _, m in ipairs(sent) do
		if m.name == "gry_cloak_shot" then
			list[#list + 1] = m
		end
	end

	return list
end

-- a stand-in entity: not a player, not a weapon
local function thing(class, parent)
	local e = {}

	function e:IsValid() return true end
	function e:IsWeapon() return false end
	function e:IsPlayer() return false end
	function e:GetClass() return class or "t_thing" end
	function e:GetParent() return parent or NULL end

	return e
end

local function camouflaged(on)
	local p = ply()

	saved[#saved + 1] = {p, "Nanosuit_mode", p.Nanosuit_mode}
	p.Nanosuit_mode = on and GryMod.Modes.CLOAK or GryMod.Modes.ARMOR
end

return {
	groupName = "GryMod core follow-ups: ReportShot, shots of vehicles, blast info, driver nobody, heavy function (server)",
	beforeAll = function()
		API, Mech, R = GryMod.API, GryMod.Mech, GryMod.Radar
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			pcall(function() saved[i][1][saved[i][2]] = saved[i][3] end)
		end

		saved = {}
		pcall(API.RemoveVehicleProvider, "t_core_nobody")
		pcall(API.UnregisterTracked, "t_core_heavy")
		pcall(API.SafeCallReset, "tracked:t_core_heavy/heavy")
	end,
	cases = {
		{
			-- fails when the function does not exist, when it does not tell the client to end the camouflage, when the shot's noise is not made as well, or when a player who is not
			-- camouflaged is told or heard
			name = "ReportShot: a camouflaged player is told to end the camouflage and the shot's noise is made; a player who is not camouflaged: nothing",
			func = function()
				expect(isfunction(API.ReportShot)).to.beTrue()

				local noises = {}

				GryMod.SuitNoiseReset()
				stub(GryMod, "EmitSuitNoise", function(p, kind) noises[#noises + 1] = kind end)
				stub(API, "CloakLevel", function() return 1 end)

				camouflaged(true)

				local ok, sent = recorded(function() return API.ReportShot(ply(), false) end)

				expect(ok).to.beTrue()
				expect(#shotMessages(sent)).to.equal(1)
				expect(#noises).to.equal(1)
				expect(noises[1]).to.equal("cloak_fire")

				camouflaged(false)
				noises = {}

				local ok2, sent2 = recorded(function() return API.ReportShot(ply(), false) end)

				expect(ok2).to.beFalse()
				expect(#shotMessages(sent2)).to.equal(0)
				expect(#noises).to.equal(0)
			end
		},
		{
			-- fails when a burst of shots in a moment makes a noise for each (the same gap as the bullets' own noise), or when the call raises for what is not a player
			name = "ReportShot: the noise is made once for a burst, and nothing is raised for what is not a player",
			func = function()
				local noises = 0

				GryMod.SuitNoiseReset()
				stub(GryMod, "EmitSuitNoise", function() noises = noises + 1 end)
				stub(API, "CloakLevel", function() return 1 end)

				camouflaged(true)

				recorded(function()
					API.ReportShot(ply(), false)
					API.ReportShot(ply(), false)
					API.ReportShot(ply(), false)
				end)

				expect(noises).to.equal(1)

				local ok = pcall(API.ReportShot, nil)
				expect(ok).to.beTrue()
				ok = pcall(API.ReportShot, "no")
				expect(ok).to.beTrue()
			end
		},
		{
			-- fails when a bullet fired by a turret that the player placed (the attacker is its creator, who may be elsewhere) ends the camouflage of its creator, or when the shot of the
			-- vehicle the player sits in (or of a part of it) stops counting
			name = "CloakShooter: the attacker of a vehicle's bullet counts only when the player sits in that vehicle (or the shooter is a part of it)",
			func = function()
				camouflaged(true)

				local p = ply()
				local car = thing("t_car")
				local gun = thing("t_gun", car)
				local turret = thing("t_turret")

				stub(API, "GetVehicleOf", function(who) if who == p then return car end end)

				expect(GryMod.CloakShooter(car, {Attacker = p})).to.equal(p) -- his vehicle
				expect(GryMod.CloakShooter(gun, {Attacker = p})).to.equal(p) -- a gun of his vehicle
				expect(GryMod.CloakShooter(turret, {Attacker = p})).to.beNil() -- a turret that is not his vehicle

				stub(API, "GetVehicleOf", function() return nil end)

				expect(GryMod.CloakShooter(car, {Attacker = p})).to.beNil() -- he is not in any vehicle
			end
		},
		{
			-- fails when the noise of the suit counts the turret's bullet as the player's shot (the same rule as the camouflage's)
			name = "the suit's shot noise follows the same rule: a turret's bullet is not the player's shot",
			func = function()
				local hookFn = hook.GetTable().EntityFireBullets and hook.GetTable().EntityFireBullets["GryMod suit noise"]

				expect(isfunction(hookFn)).to.beTrue()

				camouflaged(true)

				local p = ply()
				local car = thing("t_car")
				local turret = thing("t_turret")
				local noises = 0

				GryMod.SuitNoiseReset()
				stub(GryMod, "EmitSuitNoise", function() noises = noises + 1 end)
				stub(API, "CloakLevel", function() return 1 end)
				stub(API, "GetVehicleOf", function(who) if who == p then return car end end)

				hookFn(turret, {Attacker = p})
				expect(noises).to.equal(0)

				hookFn(car, {Attacker = p})
				expect(noises).to.equal(1)
			end
		},
		{
			-- fails when util.BlastDamageInfo (what Glide's explosions use) is not wrapped, when the radar is not told, or when the original's results are not given back
			name = "util.BlastDamageInfo is wrapped once: the explosion hook is told with the inflictor and the attacker of the damage info, and the original's results are returned",
			func = function()
				expect(isfunction(R.InstallBlastInfo)).to.beTrue()

				local told = {}
				local TAG = "t_core_blastinfo"

				hook.Add("GryMod_Explosion", TAG, function(pos, radius, inflictor, attacker) told[#told + 1] = {pos = pos, radius = radius, inflictor = inflictor, attacker = attacker} end)

				local a1, a2 = thing("t_inflictor"), thing("t_attacker")
				local info = {GetInflictor = function() return a1 end, GetAttacker = function() return a2 end}

				R.UninstallBlastInfo()

				local savedFn = util.BlastDamageInfo

				util.BlastDamageInfo = function() return "original", 7 end
				R.InstallBlastInfo()

				local r1, r2
				local ok, err = pcall(function() r1, r2 = util.BlastDamageInfo(info, Vector(15000, -15000, 5000), 300) end)

				R.UninstallBlastInfo()
				util.BlastDamageInfo = savedFn
				R.InstallBlastInfo()
				hook.Remove("GryMod_Explosion", TAG)

				assert(ok, err)
				expect(r1).to.equal("original")
				expect(r2).to.equal(7)
				expect(#told).to.equal(1)
				expect(told[1].radius).to.equal(300)
				expect(told[1].inflictor).to.equal(a1)
				expect(told[1].attacker).to.equal(a2)
			end
		},
		{
			-- fails when a provider that answers `false` (nobody drives: simfphys with a remote driver and no one at the wheel) is still given the entity's own GetDriver (the remote
			-- driver, who does not sit in it)
			name = "GetVehicleDriver: a provider that answers false means nobody, with no fall back to the entity's GetDriver",
			func = function()
				local remote = thing("t_remote")
				local car = thing("t_nobody_car")

				function car:GetDriver() return remote end

				expect(API.GetVehicleDriver(car)).to.equal(remote) -- no provider yet: the entity's own answer

				API.AddVehicleProvider("t_core_nobody", {
					ofPlayer = function() return nil end,
					driver = function(vehicle) if vehicle == car then return false end end,
					kind = "ground"
				})

				expect(API.GetVehicleDriver(car)).to.beNil()
			end
		},
		{
			-- fails when `heavy` as a function is refused, not asked, asked with a class name (it takes an entity), or when a function that raises or answers no is taken for a yes
			name = "heavy as a function: asked for an entity, true only when it answers true, nothing raised for an error or for a class name",
			func = function()
				local yes, no = thing("t_core_heavy_c"), thing("t_core_heavy_c")

				yes.isHeavy = true

				local ok, why = API.RegisterTracked("t_core_heavy", {class = "t_core_heavy_c", heavy = function(ent) return ent.isHeavy == true end})

				expect(ok).to.beTrue()
				expect(Mech.IsHeavyMachine(yes)).to.beTrue()
				expect(Mech.IsHeavyMachine(no)).to.beFalse()
				expect(Mech.IsHeavyMachine("t_core_heavy_c")).to.beFalse()

				API.RegisterTracked("t_core_heavy", {class = "t_core_heavy_c", heavy = function() error("broken") end})
				expect(Mech.IsHeavyMachine(yes)).to.beFalse()

				-- a boolean is still what it was
				API.RegisterTracked("t_core_heavy", {class = "t_core_heavy_c", heavy = true})
				expect(Mech.IsHeavyMachine("t_core_heavy_c")).to.beTrue()
			end
		}
	}
}
