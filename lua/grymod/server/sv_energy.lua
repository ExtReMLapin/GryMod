local hook =  hook;
local umsg = umsg;
local player = player;
Regen_Status = true
Regen_HealRamps = false
Regen_PerSect = false 
local function Regen_PlayerHasSpawneda(ply)
	ply.RDW = CurTime() + 0.1
	ply.HRAW = 1
	ply.HRTW = 0
end
hook.Add("PlayerSpawn", "Player spawns AR", Regen_PlayerHasSpawneda)
local function Regen_PlayerTakesDamagea(ply)
	if (!ply:IsPlayer()) then return end
	ply.RDW = CurTime() + (ply.RDW * 0 + 2.5) // ent.RDW * 0 + (CurTime() + 5)
	ply.HRAW = 1
	ply.HRTW = 0
end
hook.Add("GryUseEnergy", "Regen Time Penalty After Damage", Regen_PlayerTakesDamagea)

local function Regen_Doa()
	for _, ply in pairs(player.GetAll()) do
			if not IsValid(ply) then return end
			if ply:Alive() then
				if Regen_PerSect == true then
					local block
					if ply:GetNWInt("GryEnergy") > 100 * 0.75 then
						block = 100
						elseif ply:GetNWInt("GryEnergy") > 100 * 0.5 then
							block = 100 * 0.75
							elseif ply:GetNWInt("GryEnergy") > 25 then
								block = 100 * 0.5
							else
								block = 25
							end

							if Regen_HealRamps == true then
								if CurTime() >= ply.RDW then
									if (ply:GetNWInt("GryEnergy") + ply.HRAW) > block then
										ply:SetNWInt("GryEnergy",block)
									else
										ply:SetNWInt("GryEnergy",math.min(ply:GetNWInt("GryEnergy") + ply.HRAW, block))
										ply.RDW = CurTime() + 0.1
										ply.HRTW = ply.HRTW + 1
									end
								end
								if ply.HRTW >= 3 then
									ply.HRAW = ply.HRAW + 1
									ply.HRTW = 0
								end
							else
								if CurTime() >= ply.RDW then
									ply:SetNWInt("GryEnergy",math.min(ply:GetNWInt("GryEnergy") + 1, block))
									ply.RDW = CurTime() + 0.1
								end
							end
						else
							if Regen_HealRamps == true then
								if ply:GetNWInt("GryEnergy") < 100 then
									if CurTime() >= ply.RDW then
										if (ply:GetNWInt("GryEnergy") + ply.HRAW) > 100 then
											ply:SetNWInt("GryEnergy",100)
										else
											ply:SetNWInt("GryEnergy",ply:GetNWInt("GryEnergy") + ply.HRAW)
											ply.RDW = CurTime() + 0.1
											ply.HRTW = ply.HRTW + 1
										end
									end
								end
								if ply.HRTW >= 3  then
									ply.HRAW = ply.HRAW + 1
									ply.HRTW = 0
								end
							else
								if ply:GetNWInt("GryEnergy") < 100 then
									if CurTime() >= ply.RDW then
										ply:SetNWInt("GryEnergy",ply:GetNWInt("GryEnergy") + 1)
										ply.RDW = CurTime() + 0.1
									end
								end
							end
						end
					end
				end
			end
hook.Add("Tick", "Player gets his Armor regenerated", Regen_Doa)
