-- Energy probe, server realm: records the energy every server tick and drives a scenario.
-- Measurement probes of docs/superpowers/plans/2026-11-21-energy-smooth.md (gmod-mcp lua_exec_file / lua_job on a TEST client,
-- never the owner's game). P.yaw: a direction with a long straight path (found with traces); P.home: where to start.
GRY_PROBE = GRY_PROBE or {}
local P = GRY_PROBE
P.rows = {}
P.scn = nil

local function ply() return Entity(1) end

hook.Remove("Think", "gryprobe_sv")
hook.Remove("StartCommand", "gryprobe_cmd")
hook.Remove("EntityTakeDamage", "gryprobe_dmg")

hook.Add("Think", "gryprobe_sv", function()
	local p = ply()
	if not IsValid(p) then return end
	local t = SysTime()
	P.rows[#P.rows + 1] = {t, p:GetNWFloat("GryEnergy"), FrameTime(), CurTime(), p:GetVelocity():Length()}
	local s = P.scn
	if s and s.step then s.step(p, t - s.t0) end
end)

hook.Add("StartCommand", "gryprobe_cmd", function(p, cmd)
	local s = P.scn
	if s and s.move then
		cmd:SetViewAngles(Angle(0, P.yaw or 0, 0))
		cmd:SetForwardMove(10000)
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD, IN_SPEED))
	end
end)

-- name: sprint | recharge | cloak | armor
function P.start(name)
	local p = ply()
	P.rows = {}
	p:SetMoveType(MOVETYPE_WALK)
	p:SetHealth(100)
	local s = {t0 = SysTime(), name = name}
	P.scn = s
	if name == "sprint" then
		p:SetNanosuitMode(GryMod.Modes.SPEED, false)
		p:SetNWFloat("GryEnergy", 100)
		s.move = true
	elseif name == "recharge" then
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNWFloat("GryEnergy", 10)
		hook.Run("GryUseEnergy", p)
	elseif name == "cloak" then
		p:SetNanosuitMode(GryMod.Modes.CLOAK, false)
		p:SetNWFloat("GryEnergy", 100)
		s.move = true
	elseif name == "armor" then
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNWFloat("GryEnergy", 100)
		s.step = function(pp, dt)
			if not s.hit and dt > 0.5 then
				s.hit = true
				local d = DamageInfo()
				d:SetDamage(30)
				d:SetDamageType(DMG_BULLET)
				d:SetAttacker(game.GetWorld())
				d:SetInflictor(game.GetWorld())
				pp:TakeDamageInfo(d)
			end
		end
	end
	return name
end

function P.stop()
	P.scn = nil
end

function P.get() return P.rows end
return "ok " .. tostring(engine.TickInterval())
