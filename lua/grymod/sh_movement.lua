-- The rules of the base speeds (shared: the server sets the speeds, the client's servo sound counts a sprint with the same threshold). gry_movement has three
-- positions:
--   0 (default)  GryMod's own speeds: walk 200 and sprint 400, and 400 / 600 in the speed mode.
--   1  "Crysis vanilla speed": the original game's speeds, read from its code (research-mech/SPEEDS.md; 1 metre = 52.49 units): walk 177 and sprint 266 in
--      every mode; the speed mode's walk gry_move_speed_walk and its sprint a climb from x1.3 to x2.85 of the plain sprint in one second
--      (gry_move_speed_run is the top, 757), x1.4 under a fifth of the bar and x1.3 empty (Mech.SpeedRunSpeed in sv_mechanics.lua).
--      The speed mode's walk is 221.25 (177 x 1.25) BY THE OWNER'S CHOICE: the demo's code gives no bonus to the walk in the speed mode (research-mech/
--      SPEEDS_WALK_BONUS.md: x1.0, so 177), but he remembers the full game faster there. Set gry_move_speed_walk to 177 for the demo's own value.
--   2  "Crysis ratios": GMod's own walk and sprint (200 / 400) with the same RATIOS: the speed mode's walk is x(gry_move_speed_walk / gry_move_walk) and its
--      sprint climbs to x(gry_move_speed_run / gry_move_run) of 400.
-- On 1 and 2 the energy rules are the original's too (Mech.IsCrysis in sv_mechanics.lua). The values are convars an administrator can change, cut to the
-- range the engine copes with; a change reaches the players at once (sv_movement.lua).

GryMod = GryMod or {}

local Movement = GryMod.Movement or {}
GryMod.Movement = Movement

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local enabled = CreateConVar("gry_movement", "0", flags,
	"Base speeds: 0 GMod's own (200 / 400, speed mode 400 / 600), 1 the original Crysis speeds, 2 GMod's walk and sprint with the original's ratios; on 1 and 2 the energy rules are the original's too", 0, 2)
local walk = CreateConVar("gry_move_walk", "177", flags, "Walk speed in the armor, strength and cloak modes, with gry_movement 1 (units a second); the reference of the ratios with 2")
local run = CreateConVar("gry_move_run", "266", flags, "Sprint speed in the armor, strength and cloak modes, with gry_movement 1 (units a second); the reference of the ratios with 2")
local speedWalk = CreateConVar("gry_move_speed_walk", "221.25", flags, "Walk speed in the speed mode, with gry_movement 1 (units a second; 221.25 = 177 x 1.25, the owner's choice, the demo's code says 177); with 2 its ratio to gry_move_walk")
local speedRun = CreateConVar("gry_move_speed_run", "757", flags, "Top sprint speed in the speed mode with energy, with gry_movement 1 (units a second); with 2 its ratio to gry_move_run")

Movement.MODE_OFF = 0
Movement.MODE_EXACT = 1
Movement.MODE_RATIOS = 2

-- The walk and sprint of the game GryMod runs in (the Sandbox gamemode: player_sandbox.lua) and the line the speed mode's multipliers are put on.
Movement.GMOD_WALK = 200
Movement.GMOD_RUN = 400
Movement.TOP_MULTIPLIER = 2.85

-- A speed under or over these is not a speed (a player at 5000 units a second leaves the map).
Movement.MIN_SPEED = 50
Movement.MAX_SPEED = 2000

-- 0, 1 or 2.
function Movement.Mode()
	local mode = math.floor(enabled:GetFloat())

	if mode ~= mode then
		return 0
	end

	return math.Clamp(mode, 0, 2)
end

function Movement.Enabled()
	return Movement.Mode() > 0
end

local function value(convar)
	local v = convar:GetFloat()

	if v ~= v then
		v = tonumber(convar:GetDefault())
	end

	return math.Clamp(v, Movement.MIN_SPEED, Movement.MAX_SPEED)
end

local function clampSpeed(v)
	return math.Clamp(v, Movement.MIN_SPEED, Movement.MAX_SPEED)
end

-- The limit of the horizontal speed at the take-off of a jump. The engine keeps the whole speed of the run in a jump, so a jump in the speed mode (sprint 600) threw the player forward
-- much faster than in any other mode. The limit is a multiple of the PLAIN sprint of the movement setting (400 by default, 266 with the original game's speeds): gry_jump_speed_cap, 1.2 by
-- default, 0 = no limit. Not relative to the mode's own top speed: the engine's rule against bunny hops is, and it does nothing here.
local jumpCap = CreateConVar("gry_jump_speed_cap", "1.2", flags, "Limit of the horizontal speed at the take-off of a jump, as a multiple of the plain sprint (the speed mode's sprint is faster and a jump kept all of it: a huge leap). 0 = no limit", 0, 4)

-- The walk and run speeds of a mode of the suit.
function Movement.Speeds(mode)
	local setting = Movement.Mode()

	if setting == 0 then
		if mode == GryMod.Modes.SPEED then
			return 400, 600
		end

		return 200, 400
	end

	if setting == 1 then
		if mode == GryMod.Modes.SPEED then
			return value(speedWalk), value(speedRun)
		end

		return value(walk), value(run)
	end

	if mode == GryMod.Modes.SPEED then
		return clampSpeed(Movement.GMOD_WALK * value(speedWalk) / value(walk)), clampSpeed(Movement.GMOD_RUN * value(speedRun) / value(run))
	end

	return Movement.GMOD_WALK, Movement.GMOD_RUN
end

-- The speed (units a second) that a take-off is brought down to, or nil when the limit is off.
function Movement.JumpCapSpeed()
	local factor = jumpCap:GetFloat()

	if factor ~= factor or factor <= 0 then
		return nil
	end

	local _, run = Movement.Speeds(GryMod.Modes.ARMOR)

	return run * factor
end

-- The horizontal speed (vx, vy) brought down to `limit` in the same direction; a slower one is kept as it is.
function Movement.CapSpeed(vx, vy, limit)
	local speed = math.sqrt(vx * vx + vy * vy)

	if speed <= limit or speed == 0 then
		return vx, vy
	end

	local scale = limit / speed

	return vx * scale, vy * scale
end

-- The push (a Vector to ADD to the velocity: Player:SetVelocity adds) that brings the take-off of a jump down to the limit, or nil when nothing is to be done (in the air, under the
-- limit, the limit off). The height is not touched.
function Movement.JumpDelta(velocity, onGround)
	local limit = Movement.JumpCapSpeed()

	if not limit or not onGround then
		return nil
	end

	local x, y = Movement.CapSpeed(velocity.x, velocity.y, limit)

	if x == velocity.x and y == velocity.y then
		return nil
	end

	return Vector(x - velocity.x, y - velocity.y, 0)
end

-- The plain sprint and the speed mode's top sprint: the line the speed mode's multipliers are put on (Mech.SpeedRunSpeed).
function Movement.Bounds()
	local _, plain = Movement.Speeds(GryMod.Modes.ARMOR)
	local _, top = Movement.Speeds(GryMod.Modes.SPEED)

	return plain, top
end

-- The multiplier of the speed mode's sprint above a fifth of the bar, from the seconds the sprint has lasted (the original's code: 1 + max(0.3, 1.85 x
-- min(1, seconds)): x1.3 for the first 0.16 s, then straight up to x2.85 at one second).
function Movement.SprintMultiplier(seconds)
	seconds = tonumber(seconds) or 0

	if seconds < 0 then
		seconds = 0
	elseif seconds > 1 then
		seconds = 1
	end

	return 1 + math.max(0.3, 1.85 * seconds)
end

-- Under this speed (squared, units a second) a player is not counted as sprinting, for the drain and the servo sound: the old rule's 412 off; on 1 and 2
-- a little over the speed mode's walk (its sprint begins at x1.3 of the plain sprint, which the old 412 would not see).
function Movement.SprintSpeedSqr()
	if Movement.Mode() == 0 then
		return 170000
	end

	local jog = Movement.Speeds(GryMod.Modes.SPEED)

	return (jog * 1.15) ^ 2
end
