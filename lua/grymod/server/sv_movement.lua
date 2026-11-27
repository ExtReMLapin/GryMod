-- The base speeds of the suit modes (server): the rules and the convars are in sh_movement.lua; this file gives the speeds to the players. OFF by default
-- (gry_movement 0): the walk and run speeds are GryMod's own (200 / 400, and 400 / 600 in the speed mode). A change of mode gives a player the speeds of
-- his mode (SetNanosuitMode in sv_system.lua), a change of a setting reaches everybody at once.

GryMod = GryMod or {}

local Movement = GryMod.Movement

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

-- The take-off of a jump: the jump key pressed on the ground brings a faster horizontal speed down to the limit (sh_movement.lua: gry_jump_speed_cap). One event, no Think.
hook.Add("KeyPress", "GryMod jump speed limit", function(ply, key)
	if key ~= IN_JUMP or not IsValid(ply) or not ply:Alive() then
		return
	end

	local delta = Movement.JumpDelta(ply:GetVelocity(), ply:OnGround())

	if delta then
		ply:SetVelocity(delta)
	end
end)
