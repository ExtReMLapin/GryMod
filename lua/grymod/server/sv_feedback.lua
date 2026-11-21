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

-- What a hit of this amount tells the client. The amount is the one the hit had when it came, before the suit's armor
-- took any of it: a hit of no amount at all tells nothing (a prop that grazes, a damage with no amount).
function GryMod.Feedback.OnHit(victim, attacker, amount)
	if not IsValid(victim) or not amount or amount <= 0 then
		return
	end

	if not IsValid(attacker) or attacker == victim or attacker:IsWorld() then
		return
	end

	-- the player is hurt by something: the arrows show the side. Only the direction is sent (the arrows need no more
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
end

-- The suit's armor (sv_health.lua) can take all of a hit and set its damage to 0, and the EntityTakeDamage hooks run in
-- no fixed order, so a hook of this file would read 0 or the real amount by chance. The hits on a player are therefore
-- reported by the suit's own hook, with the amount it found before changing it; this hook takes the other victims
-- (NPCs, nothing of GryMod touches their damage).
hook.Add("EntityTakeDamage", "GryMod feedback", function(victim, dmg)
	if not IsValid(victim) or victim:IsPlayer() then
		return
	end

	GryMod.Feedback.OnHit(victim, dmg:GetAttacker(), dmg:GetDamage())
end)
