-- What the server tells the client for the crosshair of the Crysis HUD: where the damage came from (the arcs around
-- the crosshair, the original's ClDamageIndicator: who shot, not how much) and a hit on a living target (the
-- original's ClHitIndicator). The client draws them (cl_hud_crosshair_flash.lua).

util.AddNetworkString("gry_hit")
util.AddNetworkString("gry_damage_dir")

GryMod = GryMod or {}
GryMod.Feedback = GryMod.Feedback or {}

local function living(ent)
	return IsValid(ent) and (ent:IsNPC() or ent:IsPlayer() or ent:IsNextBot())
end

hook.Add("EntityTakeDamage", "GryMod feedback", function(victim, dmg)
	if not IsValid(victim) or dmg:GetDamage() <= 0 then
		return
	end

	local attacker = dmg:GetAttacker()

	if not IsValid(attacker) or attacker == victim or attacker:IsWorld() then
		return
	end

	-- the player is hurt by something: the arcs show the side. Only the direction is sent (the arcs need no more
	-- and a position would show where a hidden player is), at most ten times a second (a shotgun fires many pellets).
	if victim:IsPlayer() and victim:Alive() and CurTime() >= (victim.gryNextDamageDir or 0) then
		victim.gryNextDamageDir = CurTime() + 0.1

		net.Start("gry_damage_dir")
		net.WriteNormal((attacker:GetPos() - victim:GetPos()):GetNormalized())
		net.Send(victim)
	end

	-- the player hurts something alive: the crosshair blinks
	if attacker:IsPlayer() and living(victim) then
		net.Start("gry_hit")
		net.Send(attacker)
	end
end)
