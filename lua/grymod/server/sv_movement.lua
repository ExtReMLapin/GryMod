-- The base speeds of the suit modes (server). OFF by default: the walk and run speeds are GryMod's own (200 / 400, and 400 / 600 in the speed
-- mode). ON (gry_movement 1): the original game's, read from its code (research-mech/SPEEDS.md; 1 metre = 52.49 units):
--   walk 177 and sprint 266 in every mode (3.4 and 5.1 m/s), the speed mode's walk stays 177 (its multiplier only works with the sprint key),
--   and its sprint is the top 757 (x2.85 of 266; under a fifth of the bar and empty it follows the same multipliers, x1.4 and x1.3, see
--   Mech.SpeedRunSpeed in sv_mechanics.lua).
-- It is only the speeds: the energy, its drain and its recharge are not touched. The four values are convars an administrator can change
-- (gry_move_walk, gry_move_run, gry_move_speed_walk, gry_move_speed_run), cut to the range the engine copes with; a change reaches the
-- players at once. The mode change gives a player the speeds of his mode (SetNanosuitMode in sv_system.lua).

GryMod = GryMod or {}

local Movement = GryMod.Movement or {}
GryMod.Movement = Movement

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local enabled = CreateConVar("gry_movement", "0", flags,
	"1: the walk and run speeds are the original game's (177 and 266 units a second, the speed mode's sprint 757); 0: GryMod's own (200 / 400, speed mode 400 / 600)", 0, 1)
local walk = CreateConVar("gry_move_walk", "177", flags, "Walk speed in the armor, strength and cloak modes, with gry_movement 1 (units a second)")
local run = CreateConVar("gry_move_run", "266", flags, "Sprint speed in the armor, strength and cloak modes, with gry_movement 1 (units a second)")
local speedWalk = CreateConVar("gry_move_speed_walk", "177", flags, "Walk speed in the speed mode, with gry_movement 1 (units a second)")
local speedRun = CreateConVar("gry_move_speed_run", "757", flags, "Sprint speed in the speed mode with energy, with gry_movement 1 (units a second)")

-- A speed under or over these is not a speed (a player at 5000 units a second leaves the map).
Movement.MIN_SPEED = 50
Movement.MAX_SPEED = 2000

function Movement.Enabled()
	return enabled:GetBool()
end

local function value(convar)
	local v = convar:GetFloat()

	if v ~= v then
		v = tonumber(convar:GetDefault())
	end

	return math.Clamp(v, Movement.MIN_SPEED, Movement.MAX_SPEED)
end

-- The walk and run speeds of a mode.
function Movement.Speeds(mode)
	if not enabled:GetBool() then
		if mode == GryMod.Modes.SPEED then
			return 400, 600
		end

		return 200, 400
	end

	if mode == GryMod.Modes.SPEED then
		return value(speedWalk), value(speedRun)
	end

	return value(walk), value(run)
end

-- The plain sprint and the speed mode's top sprint: the line the speed mode's multipliers are put on (Mech.SpeedRunSpeed).
function Movement.Bounds()
	local _, plain = Movement.Speeds(GryMod.Modes.ARMOR)
	local _, top = Movement.Speeds(GryMod.Modes.SPEED)

	return plain, top
end

function Movement.Apply(ply, mode)
	local w, r = Movement.Speeds(mode or ply.Nanosuit_mode or GryMod.Modes.ARMOR)

	ply:SetWalkSpeed(w)
	ply:SetRunSpeed(r)
end

function Movement.ApplyAll()
	for _, ply in ipairs(player.GetAll()) do
		Movement.Apply(ply)
	end
end

for _, name in ipairs({"gry_movement", "gry_move_walk", "gry_move_run", "gry_move_speed_walk", "gry_move_speed_run"}) do
	cvars.AddChangeCallback(name, function()
		Movement.ApplyAll()
	end, "GryMovement")
end
