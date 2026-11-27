-- Tests of the speed limit at the take-off of a jump (GryMod.Movement.CapSpeed / JumpCapSpeed / JumpDelta in lua/grymod/sh_movement.lua and the KeyPress hook of
-- lua/grymod/server/sv_movement.lua), GLuaTest format, server realm (the setting is replicated: only the server changes it). The jump keeps the whole horizontal speed of the run
-- in the Source engine, so a jump in the speed mode (sprint 600) threw the player forward much faster than any other mode ("a leap completely crazy", the owner). The engine's
-- own rule against bunny hops is relative to the mode's own top speed, which does nothing here. The limit is relative to the PLAIN sprint of the movement setting (400 by default,
-- 266 with the original game's speeds): 1.2 times it by default, 0 turns it off. Each case names the change that makes it fail.

local Movement
local convar

local function near(a, b)
	return math.abs(a - b) < 0.001
end

local function withSetting(name, value, fn)
	local c = GetConVar(name)
	local before = c:GetString()

	c:SetString(value)

	local ok, err = pcall(fn)

	c:SetString(before)

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod movement: the speed limit at a jump",
	beforeEach = function()
		Movement = GryMod.Movement
		convar = GetConVar("gry_jump_speed_cap")
	end,
	cases = {
		{
			-- fails when the module has no such function, or a speed under the limit is changed, or the direction is lost, or the height is touched
			name = "CapSpeed keeps a slower speed as it is and brings a faster one down to the limit in the same direction",
			func = function()
				expect(isfunction(Movement.CapSpeed)).to.beTrue()

				local x, y = Movement.CapSpeed(300, 0, 480)

				expect(x).to.equal(300)
				expect(y).to.equal(0)

				x, y = Movement.CapSpeed(600, 0, 480)
				expect(near(x, 480) and near(y, 0)).to.beTrue()

				-- the direction stays: a 3-4-5 triangle at 750 brought to 480
				x, y = Movement.CapSpeed(450, 600, 480)
				expect(near(math.sqrt(x * x + y * y), 480)).to.beTrue()
				expect(near(x / y, 450 / 600)).to.beTrue()

				x, y = Movement.CapSpeed(0, 0, 480)
				expect(x == 0 and y == 0).to.beTrue()
			end
		},
		{
			-- fails when the default is not 1.2 times the plain sprint (480), when 0 does not turn it off, or when it ignores the movement setting (the original's speeds sprint at 266)
			name = "JumpCapSpeed: 1.2 times the plain sprint of the movement setting, nil when the setting is 0",
			func = function()
				expect(convar ~= nil).to.beTrue()

				withSetting("gry_movement", "0", function()
					withSetting("gry_jump_speed_cap", "1.2", function()
						expect(near(Movement.JumpCapSpeed(), 480)).to.beTrue()
					end)

					withSetting("gry_jump_speed_cap", "0", function()
						expect(Movement.JumpCapSpeed()).to.beNil()
					end)
				end)

				withSetting("gry_movement", "1", function()
					withSetting("gry_jump_speed_cap", "1.2", function()
						expect(near(Movement.JumpCapSpeed(), 266 * 1.2)).to.beTrue()
					end)
				end)
			end
		},
		{
			-- fails when a player in the air or slower than the limit is touched, when the push is not exactly what brings the speed down to the limit (the engine adds it to the
			-- velocity), or when the height changes
			name = "JumpDelta: the push that brings a fast take-off down to the limit; nothing in the air, under the limit or with the limit off",
			func = function()
				withSetting("gry_jump_speed_cap", "1.2", function()
					local v = Vector(600, 0, 0)
					local d = Movement.JumpDelta(v, true)

					expect(d ~= nil).to.beTrue()
					expect(near(v.x + d.x, 480) and near(v.y + d.y, 0) and d.z == 0).to.beTrue()

					expect(Movement.JumpDelta(Vector(300, 0, 0), true)).to.beNil()
					expect(Movement.JumpDelta(Vector(600, 0, 0), false)).to.beNil()
				end)

				withSetting("gry_jump_speed_cap", "0", function()
					expect(Movement.JumpDelta(Vector(600, 0, 0), true)).to.beNil()
				end)
			end
		},
		{
			-- fails when the take-off of a jump (the jump key pressed on the ground) does not push the player's velocity down to the limit through the hook, or does it in the air
			name = "the jump key on the ground brings a fast take-off down to the limit; in the air or when slow nothing happens",
			func = function()
				local hookFn = hook.GetTable().KeyPress and hook.GetTable().KeyPress["GryMod jump speed limit"]

				expect(isfunction(hookFn)).to.beTrue()

				local pushes = {}

				local function player(velocity, ground)
					local ply = {pushes = pushes}

					function ply:IsValid() return true end
					function ply:IsPlayer() return true end
					function ply:Alive() return true end
					function ply:OnGround() return ground end
					function ply:GetVelocity() return velocity end
					function ply:SetVelocity(v) pushes[#pushes + 1] = v end

					return ply
				end

				withSetting("gry_jump_speed_cap", "1.2", function()
					hookFn(player(Vector(600, 0, 0), true), IN_JUMP)
					expect(#pushes).to.equal(1)
					expect(near(600 + pushes[1].x, 480)).to.beTrue()

					hookFn(player(Vector(600, 0, 0), false), IN_JUMP)
					hookFn(player(Vector(300, 0, 0), true), IN_JUMP)
					hookFn(player(Vector(600, 0, 0), true), IN_ATTACK)
					expect(#pushes).to.equal(1)
				end)
			end
		}
	}
}
