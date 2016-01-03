	local hook =  hook;
	local umsg = umsg;
	local player = player;
	hook.Add("EntityTakeDamage","Sahek",function( target, dmginfo )
		if ( target:IsPlayer() ) then
			if target:GetNWBool("Armor", true) then return end
			umsg.Start( "shake_view" ); umsg.Entity(target) umsg.Bool(true) umsg.End();
			timer.Simple(0.75,function() if target:IsValid() then
				umsg.Start( "shake_view" );
				umsg.Entity(target)
				umsg.Bool(false)
				umsg.End();
				end end)
		end
		end)


	Regen_Status = true
	Regen_HealRamps = false
	Regen_PerSect = false 

	local function Regen_PlayerHasSpawned(ply)
		ply.RD = CurTime() + 0.1
		ply.HRA = 1
		ply.HRT = 0
	end
	hook.Add("PlayerSpawn", "Player spawnadads AR", Regen_PlayerHasSpawned)
	local function Regen_PlayerTakesDamage(ent, inflictor, attacker, _, dmginfo)
		if (!ent:IsPlayer())then return end
		if ent:GetNWBool("Armor", true) then return end
		ent.RD = CurTime() + (ent.RD * 0 + 5) // ent.RD * 0 + (CurTime() + 5)
		ent.HRA = 1
		ent.HRT = 0
	end
	hook.Add("EntityTakeDamage", "Regen Time Penalty After Daadadamage", Regen_PlayerTakesDamage)

	GryMod.plytbl = GryMod.plytbl or player.GetAll()

	local function Regen_Do()
		if gry_Should_Regen then
			for _, ply in pairs (GryMod.plytbl) do
				if not IsValid(ply) then return end
				if ply:Alive() then
					if Regen_Status == true then
						if Regen_PerSect == true then
							local block
							if ply:Health() > 100 * 0.75 then
								block = 100
								elseif ply:Health() > 100 * 0.5 then
									block = 100 * 0.75
									elseif ply:Health() > 25 then
										block = 100 * 0.5
									else
										block = 25
									end

									if Regen_HealRamps == true then
										if CurTime() >= ply.RD then
											if (ply:Health() + ply.HRA) > block then
												ply:SetHealth(block)
											else
												ply:SetHealth(math.min(ply:Health() + ply.HRA, block))
												ply.RD = CurTime() + 0.1
												ply.HRT = ply.HRT + 1
											end
										end
										if ply.HRT >= 3 then
											ply.HRA = ply.HRA + 1
											ply.HRT = 0
										end
									else
										if CurTime() >= ply.RD then
											ply:SetHealth(math.min(ply:Health() + 1, block))
											ply.RD = CurTime() + 0.1
										end
									end
								else
									if Regen_HealRamps == true then
										if ply:Health() < 100 then
											if CurTime() >= ply.RD then
												if (ply:Health() + ply.HRA) > 100 then
													ply:SetHealth(100)
												else
													ply:SetHealth(ply:Health() + ply.HRA)
													ply.RD = CurTime() + 0.1
													ply.HRT = ply.HRT + 1
												end
											end
										end
										if ply.HRT >= 3  then
											ply.HRA = ply.HRA + 1
											ply.HRT = 0
										end
									else
										if ply:Health() < 100 then
											if CurTime() >= ply.RD then
												ply:SetHealth(ply:Health() + 1)
												ply.RD = CurTime() + 0.1
											end
										end
									end
								end
							end
						end
					end
				end
			end
hook.Add("Tick", "Player gets his health regeneratedadazda", Regen_Do)

