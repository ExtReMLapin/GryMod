-- Tests of the suit of a player who sits in a vehicle (server realm, GLuaTest format). The owner's decision: the suit works in a vehicle as on foot, but a seated player counts as
-- STILL for the camouflage's drain (Crysis does not use more energy in a vehicle: the vehicle's speed is not the player's), for "is he moving" (the recharge and the health
-- regeneration), for the speed sprint and for the jumps; and a bullet that a vehicle fires with the player as ATTACKER (EntityFireBullets: data.Attacker) is the player's shot: it ends the
-- camouflage and makes the noise of a shot. Stand-in players (tables that answer like players) are used wherever the real one cannot be put in a vehicle at a speed. Each case names the
-- production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

-- a player stand-in: seated or not, moving at `speed` units a second
local function fakePlayer(seated, speed, fields)
	local p = {Nanosuit_mode = GryMod.Modes.ARMOR, energy = 100}

	function p:IsValid() return true end
	function p:IsPlayer() return true end
	function p:IsWeapon() return false end
	function p:InVehicle() return seated end
	function p:GetVelocity() return Vector(speed, 0, 0) end
	function p:IsSprinting() return true end
	function p:IsOnGround() return true end
	function p:OnGround() return true end
	function p:WaterLevel() return 0 end
	function p:Alive() return true end
	function p:KeyDown() return false end
	function p:GetNW2Float() return self.energy end
	function p:SetNW2Float(_, value) self.energy = value end
	function p:SetJumpPower() end

	for k, v in pairs(fields or {}) do
		p[k] = v
	end

	return p
end

local savedConfig, realMechSpeed

local function mute(fn)
	local sent = {}
	local realStart, realSend, realRun = net.Start, net.Send, hook.Run

	net.Start = function(name) sent[#sent + 1] = name return true end
	net.Send = function() end
	hook.Run = function() end

	local ok, err = pcall(fn)

	net.Start, net.Send, hook.Run = realStart, realSend, realRun
	assert(ok, err)

	return sent
end

-- A vehicle's bullet is the attacker's shot only when he sits in that vehicle (GryMod.ShotPlayer): who sits in which vehicle, for GetVehicleOf; the function it returns puts the real one back
local function seats(map)
	local API = GryMod.API
	local real = API.GetVehicleOf

	API.GetVehicleOf = function(who) return map[who] end

	return function() API.GetVehicleOf = real end
end

return {
	groupName = "GryMod suit of a player in a vehicle (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
		realMechSpeed = GryMod.Mech.CloakSpeed
	end,
	beforeEach = function()
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "crysis"

		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNW2Float("GryEnergy", 100)
		p:SetNW2Float("GryCloakLvl0", 0)
		p:SetNW2Float("GryCloakT0", 0)

		if GryMod.SuitNoiseReset then
			GryMod.SuitNoiseReset()
		end
	end,
	afterEach = function()
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Mech.CloakSpeed = realMechSpeed

		local p = ply()

		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNW2Float("GryEnergy", 100)
		end
	end,
	cases = {
		{
			-- fails when a seated player's speed is the vehicle's: the camouflage would drain with the car's speed
			name = "Mech.CloakSpeed: a seated player counts as speed 0, a player on foot as his own speed",
			func = function()
				expect(GryMod.Mech.CloakSpeed(fakePlayer(true, 900))).to.equal(0)
				expect(GryMod.Mech.CloakSpeed(fakePlayer(false, 300))).to.equal(300)
			end
		},
		{
			-- fails when the camouflage's drain callers (the energy rate told to the client, sv_health.lua, and the Think of the camouflage, sv_system.lua) read the raw velocity
			name = "the camouflage's drain, in the rate told to the client and in its Think, is worked out from Mech.CloakSpeed",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				GryMod.Mech.CloakSpeed = function() return 123 end

				expect(GryMod.EnergyRate(p)).to.equal(-GryMod.Mech.CloakDrain(123))

				p:SetNW2Float("GryEnergy", 100)
				mute(function()
					hook.GetTable().Think["GryCloakThink"]()
				end)

				local paid = 100 - p:GetNW2Float("GryEnergy")

				-- (the energy is a float of 32 bits: a few millionths of rounding)
				expect(math.abs(paid - GryMod.Mech.CloakDrain(123) * FrameTime()) < 1e-4).to.beTrue()
			end
		},
		{
			-- fails when a seated player counts as moving (the recharge and the health regeneration would be the slow ones, as on foot)
			name = "Mech.IsMoving: a seated player is not moving, whatever the vehicle's speed; on foot he is",
			func = function()
				expect(GryMod.Mech.IsMoving(fakePlayer(true, 900))).to.beFalse()
				expect(GryMod.Mech.IsMoving(fakePlayer(false, 900))).to.beTrue()
				expect(GryMod.Mech.IsMoving(fakePlayer(false, 0))).to.beFalse()
			end
		},
		{
			-- fails when the speed sprint is paid (and its run speed climbs) at the speed of a vehicle
			name = "the speed sprint: a fast seated player is not sprinting, a fast one on foot is; the sprint key's climb does not count a seated player",
			func = function()
				local fast = GryMod.Movement.SprintSpeedSqr() ^ 0.5 + 500

				expect(GryMod.IsSpeedSprinting(fakePlayer(false, fast, {Nanosuit_mode = GryMod.Modes.SPEED}))).to.beTrue()
				expect(GryMod.IsSpeedSprinting(fakePlayer(true, fast, {Nanosuit_mode = GryMod.Modes.SPEED}))).to.beFalse()

				local held = {KeyDown = function() return true end}

				expect(GryMod.Mech.SprintHeld(fakePlayer(false, fast, held))).to.beTrue()
				expect(GryMod.Mech.SprintHeld(fakePlayer(true, fast, held))).to.beFalse()
			end
		},
		{
			-- fails when the jump of the strength mode (energy, message, report) is granted to a seated player (the jump key in a vehicle is not a jump)
			name = "the strength jump: not granted to a seated player (no energy, no message, no report), granted on foot",
			func = function()
				local jumped = 0
				local realRun = hook.Run

				hook.Run = function(name) if name == "GryMod_StrengthJump" then jumped = jumped + 1 end end

				local seated = fakePlayer(true, 0, {Nanosuit_mode = GryMod.Modes.STRENGTH})
				local walker = fakePlayer(false, 0, {Nanosuit_mode = GryMod.Modes.STRENGTH})
				local sentSeated, sentWalker

				local ok, err = pcall(function()
					local realStart, realSend = net.Start, net.Send
					local names = {}

					net.Start = function(name) names[#names + 1] = name return true end
					net.Send = function() end

					local ok2, err2 = pcall(function()
						GryMod.SuperJump(seated, IN_JUMP)
						sentSeated = #names
						GryMod.SuperJump(walker, IN_JUMP)
						sentWalker = #names - sentSeated
					end)

					net.Start, net.Send = realStart, realSend
					assert(ok2, err2)
				end)

				hook.Run = realRun
				assert(ok, err)

				expect(seated.energy).to.equal(100)
				expect(sentSeated).to.equal(0)
				expect(walker.energy < 100).to.beTrue()
				expect(sentWalker).to.equal(1)
				expect(jumped).to.equal(1)
			end
		},
		{
			-- fails when a bullet fired by a vehicle with the player as attacker does not end the camouflage (the vehicle is not a player and not a weapon: only data.Attacker names him)
			name = "CloakShooter: a vehicle's bullet with the cloaked player as attacker is his shot; without an attacker, with another or with a player who is not cloaked it is not",
			func = function()
				local cloaked = fakePlayer(false, 0, {Nanosuit_mode = GryMod.Modes.CLOAK})
				local armor = fakePlayer(false, 0)
				local car = {IsValid = function() return true end, IsWeapon = function() return false end, IsPlayer = function() return false end}

				local restore = seats({[cloaked] = car, [armor] = car})
				local ok, err = pcall(function()
					expect(GryMod.CloakShooter(car)).to.beNil()
					expect(GryMod.CloakShooter(car, {})).to.beNil()
					expect(GryMod.CloakShooter(car, {Attacker = car})).to.beNil()
					expect(GryMod.CloakShooter(car, {Attacker = armor})).to.beNil()
					expect(GryMod.CloakShooter(car, {Attacker = cloaked})).to.equal(cloaked)
				end)

				restore()
				assert(ok, err)
			end
		},
		{
			-- fails when the weapon of the player is counted twice (its owner, then the attacker of the same bullet), or when its owner is no longer the shooter
			name = "CloakShooter: a player's own weapon is one shot, whether the attacker is told or not; the player himself too",
			func = function()
				local cloaked = fakePlayer(false, 0, {Nanosuit_mode = GryMod.Modes.CLOAK})
				local weapon = {IsValid = function() return true end, IsWeapon = function() return true end, IsPlayer = function() return false end, GetOwner = function() return cloaked end}

				expect(GryMod.CloakShooter(weapon, {Attacker = cloaked})).to.equal(cloaked)
				expect(GryMod.CloakShooter(weapon)).to.equal(cloaked)
				expect(GryMod.CloakShooter(cloaked, {Attacker = cloaked})).to.equal(cloaked)

				local sent = mute(function()
					hook.GetTable().EntityFireBullets["GryCloakShot"](weapon, {Attacker = cloaked})
				end)

				expect(#sent).to.equal(1)
			end
		},
		{
			-- fails when the real hook does not tell the player's client about a bullet of a vehicle
			name = "the hook EntityFireBullets tells the client once for a vehicle's bullet with the player as attacker",
			func = function()
				local p = ply()
				local car = {IsValid = function() return true end, IsWeapon = function() return false end, IsPlayer = function() return false end}

				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)

				local restore = seats({[p] = car})
				local sent
				local ok, err = pcall(function()
					sent = mute(function()
						hook.GetTable().EntityFireBullets["GryCloakShot"](car, {Attacker = p})
					end)
				end)

				restore()
				assert(ok, err)
				expect(#sent).to.equal(1)
				expect(sent[1]).to.equal("gry_cloak_shot")
			end
		},
		{
			-- fails when the suit's noise of a shot (cloak_fire, for the AI's hearing) ignores a vehicle's bullet, or makes it twice for the weapon of the player
			name = "the noise of a shot (cloak_fire) is made for a vehicle's bullet with the cloaked player as attacker, once a quarter second",
			func = function()
				local p = ply()
				local car = {IsValid = function() return true end, IsWeapon = function() return false end, IsPlayer = function() return false end}
				local calls = {}

				hook.Add("GryMod_SuitNoise", "gry_test_vehicle", function(_, _, _, kind) calls[#calls + 1] = kind end)
				p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
				p:SetNW2Float("GryCloakT0", CurTime() - 3)
				calls = {}

				local fn = hook.GetTable().EntityFireBullets["GryMod suit noise"]
				local restore = seats({[p] = car})
				local ok, err = pcall(function()
					fn(car, {Attacker = p})
					fn(car, {Attacker = p})
				end)

				restore()
				hook.Remove("GryMod_SuitNoise", "gry_test_vehicle")
				assert(ok, err)
				expect(#calls).to.equal(1)
				expect(calls[1]).to.equal("cloak_fire")
			end
		}
	}
}
