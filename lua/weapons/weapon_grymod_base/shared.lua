if (SERVER) then
	AddCSLuaFile( "shared.lua" )
	SWEP.Weight				= 5
	SWEP.AutoSwitchTo		= false
	SWEP.AutoSwitchFrom		= false

end

if ( CLIENT ) then
	SWEP.DrawAmmo			= true
	SWEP.DrawCrosshair		= true
	SWEP.ViewModelFOV		= 86
	SWEP.ViewModelFlip		= true
	SWEP.CSMuzzleFlashes	= true
end

SWEP.Author			= "ExtReM Lapin"
SWEP.Contact		= ""
SWEP.Purpose		= ""
SWEP.Instructions	= ""

SWEP.Spawnable			= false
SWEP.AdminSpawnable		= false

SWEP.Primary.Sound			= Sound("Scar.Single")
SWEP.Primary.Damage			= 40
SWEP.Primary.NumShots		= 1
SWEP.Primary.Delay			= 0.15
SWEP.Silenced = false
SWEP.UseSilencer = true
SWEP.SilencerAnim = true
SWEP.Primary.ClipSize		= -1
SWEP.Primary.DefaultClip	= -1
SWEP.Primary.Automatic		= false
SWEP.Primary.Ammo			= "none"
SWEP.IsAiming 				= false
SWEP.Secondary.ClipSize		= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Automatic	= false
SWEP.Secondary.Ammo			= "none"
SWEP.RunArmOffset 			= Vector (-3, -1, -8)
SWEP.RunArmAngle 			= Angle(-25, 60, 5)
SWEP.Rifle					= true
SWEP.HoldType			= "smg"
SWEP.DeployDelay		= 0.2
SWEP.IsAiming			= false

/*---------------------------------------------------------
---------------------------------------------------------*/
function SWEP:Initialize()

	if ( SERVER ) then
		self:SetNPCMinBurst( 30 )
		self:SetNPCMaxBurst( 30 )
		self:SetNPCFireRate( 0.01 )
	end
	self:SetWeaponHoldType( self.HoldType )
	self.Weapon:SetNetworkedBool( "Ironsights", true )
end
function SWEP:DrawWeaponSelection( x, y, wide, tall, alpha )
 local	fcross = Material( "cryhud/scarprofil1.png" )
	surface.SetMaterial( fcross )
	surface.SetDrawColor(Color(255,255,255,255))
	surface.DrawTexturedRect(x + wide/2-120, y + tall*0.2, 250, 100)
 
end

function SWEP:Reload()

if self.Weapon:Clip1() < 40  and self.Weapon:Clip2()!= 0 then
			if self.Silenced and self.SilencerAnim then
			

		self.Weapon:DefaultReload( ACT_VM_RELOAD_SILENCED )
			
		else
			self.Weapon:DefaultReload( ACT_VM_RELOAD )
		end
	self:SetIronsights( false )
	end
end

function SWEP:SecondThink()
end

/*---------------------------------------------------------
   OLOL
---------------------------------------------------------*/
function SWEP:Think()

	self:SecondThink()

	if self.Weapon:Clip1() > 0 and self.IdleDelay < CurTime() and self.IdleApply then
		local WeaponModel = self.Weapon:GetOwner():GetActiveWeapon():GetClass()

			if self.Silenced and self.SilencerAnim then
					self.Weapon:SendWeaponAnim(ACT_VM_IDLE_SILENCED)
				else
					self.Weapon:SendWeaponAnim(ACT_VM_IDLE)
				end

		self.IdleApply = false
	elseif self.Weapon:Clip1() <= 0 then
		self.IdleApply = false
	end

	if self.Weapon:GetDTBool(1) and self.Owner:KeyDown(IN_SPEED) then
		self:SetIronsights(false)
	end
	
	if self.Owner:KeyDown(IN_SPEED) or self.Weapon:GetDTBool(0) then
		if self.Rifle or self.Sniper or self.Shotgun then
			if (SERVER) then
				self:SetWeaponHoldType("passive")
			end
		elseif self.Pistol then
			if (SERVER) then
				self:SetWeaponHoldType("normal")
			end
		end
	else
		if (SERVER) then
			self:SetWeaponHoldType(self.HoldType)
		end
	end


	if self.Weapon:GetDTBool(3) and self.Type == 3 then
		if self.BurstTimer + self.BurstDelay < CurTime() then
			if self.BurstCounter > 0 then
				self.BurstCounter = self.BurstCounter - 1
				self.BurstTimer = CurTime()
				
				if self:CanPrimaryAttack() then
					self.Weapon:EmitSound(self.Primary.Sound)
					self:ShootBulletInformation()
					self:TakePrimaryAmmo(1)
				end
			end
		end
	end

	self:NextThink(CurTime())
end


function SWEP:PrimaryAttack()

	self.Weapon:SetNextSecondaryFire( CurTime() + self.Primary.Delay )
	self.Weapon:SetNextPrimaryFire( CurTime() + self.Primary.Delay )
	
	if ( !self:CanPrimaryAttack() ) or (self.Owner:KeyDown(IN_SPEED))  then return end
	
	-- Play shoot sound
	self.Weapon:EmitSound( self.Primary.Sound )
	
	
			self.Primary.Recoil		= 0.32
		self.Primary.Cone			= 0.0532 
		
	if self.Owner:GetNWBool("Strenght",true) and self.IsAiming then  -- Aim + Strenght
		self.Primary.Recoil = 0.27
		self.Primary.Cone	= 0.0097
	end
	
	 if self.IsAiming then -- Aim only
		self.Primary.Recoil		= 0.032
		self.Primary.Cone		= 0.012
	end
	
	if self.Owner:GetNWBool("Strenght",true) and !self.IsAiming then -- Strenght only
		self.Primary.Recoil		= 0.32
		self.Primary.Cone		= 0.0532
  end
 


  
  
	
	
	
	
	-- Shoot the bullet
	self:CSShootBullet( self.Primary.Damage, self.Primary.Recoil, self.Primary.NumShots, self.Primary.Cone )
	self:RecoilPower()
	-- Remove 1 bullet from our clip
	self:TakePrimaryAmmo( 1 )
	
	if ( self.Owner:IsNPC() ) then return end
	

	
	-- In singleplayer this function doesn't get called on the client, so we use a networked float
	-- to send the last shoot time. In multiplayer this is predicted clientside so we don't need to 
	-- send the float.
	if ( (game.SinglePlayer() and SERVER) or CLIENT ) then
		self.Weapon:SetNetworkedFloat( "LastShootTime", CurTime() )
	end
	
end



function SWEP:SecondaryAttack()
	if self.Owner:IsNPC() then return end
	if not IsFirstTimePredicted() then return end

 
    if (self.Owner:KeyDown(IN_USE))  then -- Zoom + Use
		if self.Silenced then
			self.Weapon:SendWeaponAnim(ACT_VM_DETACH_SILENCER)
					self.Primary.Sound	= Sound("Weapons/crym4a1/m4a1_unsil-1.wav")
			self.Silenced 			= false
		else
			self.Weapon:SendWeaponAnim(ACT_VM_ATTACH_SILENCER)
				self.Primary.Sound			= Sound("Weapon_USP.SilencedShot") // Yes
 			self.Silenced 			= true
		end
        self:SetIronsights(false)
        self.Weapon:SetNextPrimaryFire(CurTime() + 1.95)
        self.Weapon:SetNextSecondaryFire(CurTime() + 1.95)
        return
    end
	if (!self.IronSightsPos) or (self.Owner:KeyDown(IN_SPEED) or self.Weapon:GetDTBool(0)) then return end
	
	bIronsights = !self.Weapon:GetDTBool(1)
	self:SetIronsights(bIronsights)

	self.Weapon:SetNextPrimaryFire(CurTime() + 0.2)
	self.Weapon:SetNextSecondaryFire(CurTime() + 0.2)
end



function SWEP:RecoilPower()
	if !IsValid(self.Owner) then return end
		if self.Owner:Alive() then

		
		
		if self.IsAiming then
		self.Owner:ViewPunch(Angle(math.Rand(-0.5,-.7)*0.2, math.Rand(-1,1) * 0.5, 0)) -- lol		
		else
			self.Owner:ViewPunch(Angle(math.Rand(-0.5,-.7)*.223456789 , math.Rand(-1,1) * 2, 0)) -- internet
		end	
			
			
	end
end



function SWEP:CSShootBullet( dmg, recoil, numbul, cone )

	numbul 	= numbul 	or 1
	cone 	= cone 		or 0.01

	local bullet = {}
	bullet.Num 		= numbul
	bullet.Src 		= self.Owner:GetShootPos()			-- Source
	bullet.Dir 		= self.Owner:GetAimVector()			-- Dir of bullet
	bullet.Spread 	= Vector( cone, cone, 0 )			-- Aim Cone
	bullet.Tracer	= 1									-- Show a tracer on every x bullets 
	bullet.Force	= 5									-- Amount of force to give to phys objects
	bullet.Damage	= dmg
	
	self.Owner:FireBullets( bullet )
	-- View model animation
	self.Owner:MuzzleFlash()	
	-- Crappy muzzle light
	self.Owner:SetAnimation( PLAYER_ATTACK1 )				-- 3rd Person Animation

		-- self.Weapon:SendWeaponAnim( ACT_VM_PRIMARYATTACK ) 

	----------------------------------------/	
		if  self.IsAiming == false  then
			if self.Silenced and self.SilencerAnim  then
				self.Weapon:SendWeaponAnim( ACT_VM_PRIMARYATTACK_SILENCED )	
			else
				self.Weapon:SendWeaponAnim( ACT_VM_PRIMARYATTACK )
			end
		end
		
	----------------------------------------
	
	if ( self.Owner:IsNPC() ) then return end
	
	-- CUSTOM RECOIL !
	if ( (game.SinglePlayer() and SERVER) or ( !game.SinglePlayer() and CLIENT and IsFirstTimePredicted() ) ) then
	
		local eyeang = self.Owner:EyeAngles()
		eyeang.pitch = eyeang.pitch - recoil
		self.Owner:SetEyeAngles( eyeang )
	
	end

end





local IRONSIGHT_TIME = 0.25

function SWEP:GetViewModelPosition(pos, ang)

	local bIron = self.Weapon:GetDTBool(1)	
	
	local DashDelta = 0
	
	if (self.Owner:KeyDown(IN_SPEED) or self.Weapon:GetDTBool(0)) then
		if (!self.DashStartTime) then
			self.DashStartTime = CurTime()
		end
		
		DashDelta = math.Clamp(((CurTime() - self.DashStartTime) / 0.2) ^ 1.2, 0, 1)
	else
		if (self.DashStartTime) then
			self.DashEndTime = CurTime()
		end
	
		if (self.DashEndTime) then
			DashDelta = math.Clamp(((CurTime() - self.DashEndTime) / 0.2) ^ 1.2, 0, 1)
			DashDelta = 1 - DashDelta
			if (DashDelta == 0) then self.DashEndTime = nil end
		end
	
		self.DashStartTime = nil
	end
	
	if (DashDelta) then
		local Down = ang:Up() * -1
		local Right = ang:Right()
		local Forward = ang:Forward()
	
		local bUseVector = false
		
		if(!self.RunArmAngle.pitch) then
			bUseVector = true
		end
		
		if (bUseVector == true) then
			ang:RotateAroundAxis(ang:Right(), self.RunArmAngle.x * DashDelta)
			ang:RotateAroundAxis(ang:Up(), self.RunArmAngle.y * DashDelta)
			ang:RotateAroundAxis(ang:Forward(), self.RunArmAngle.z * DashDelta)
			
			pos = pos + self.RunArmOffset.x * ang:Right() * DashDelta 
			pos = pos + self.RunArmOffset.y * ang:Forward() * DashDelta 
			pos = pos + self.RunArmOffset.z * ang:Up() * DashDelta 
		else
			ang:RotateAroundAxis(Right, self.RunArmAngle.pitch * DashDelta)
			ang:RotateAroundAxis(Down, self.RunArmAngle.yaw * DashDelta)
			ang:RotateAroundAxis(Forward, self.RunArmAngle.roll * DashDelta)

			pos = pos + (Down * self.RunArmOffset.x + Forward * self.RunArmOffset.y + Right * self.RunArmOffset.z) * DashDelta			
		end
		
		if (self.DashEndTime) then
			return pos, ang
		end
	end

	if (bIron != self.bLastIron) then
		self.bLastIron = bIron 
		self.fIronTime = CurTime()
		
		if (bIron) then 
			self.SwayScale 	= 0.2
			self.BobScale 	= 0.3
		else 
			self.SwayScale 	= 0.2
			self.BobScale 	= 0.3
		end
	
	end
	
	local fIronTime = self.fIronTime or 0

	if (!bIron and fIronTime < CurTime() - IRONSIGHT_TIME) then 
		return pos, ang
	end
	
	local Mul = 1.0
	
	if (fIronTime > CurTime() - IRONSIGHT_TIME) then
		Mul = math.Clamp((CurTime() - fIronTime) / IRONSIGHT_TIME, 0, 1)

		if (!bIron) then Mul = 1 - Mul end
	end

	if (self.IronSightsAng) then
		ang = ang * 1
		ang:RotateAroundAxis(ang:Right(), 	self.IronSightsAng.x * Mul)
		ang:RotateAroundAxis(ang:Up(), 	self.IronSightsAng.y * Mul)
		ang:RotateAroundAxis(ang:Forward(), self.IronSightsAng.z * Mul)
	end
	
	local Right 	= ang:Right()
	local Up 		= ang:Up()
	local Forward 	= ang:Forward()
	
	pos = pos + self.IronSightsPos.x * Right * Mul
	pos = pos + self.IronSightsPos.y * Forward * Mul
	pos = pos + self.IronSightsPos.z * Up * Mul
	
	return pos, ang
end


function SWEP:SetIronsights(b)
	if (self.Owner) then
		if (b) then
			if (SERVER) then
				self.Owner:SetFOV(30, 0.23)
			end

			if self.AllowIdleAnimation then
				if self.Silenced then
					self.Weapon:SendWeaponAnim(ACT_VM_IDLE_SILENCED)
				else
					self.Weapon:SendWeaponAnim(ACT_VM_IDLE)
				end

				self.Owner:GetViewModel():SetPlaybackRate(0)
			end

			self.Weapon:EmitSound("weapons/universal/iron_in.wav")
		else
			if (SERVER) then
				self.Owner:SetFOV(0, 0.23)
			end

			if self.AllowPlaybackRate and self.AllowIdleAnimation then
				self.Owner:GetViewModel():SetPlaybackRate(1)
			end	

			self.Weapon:EmitSound("weapons/universal/iron_out.wav")
		end
	end

	
			if ( b )then

			self.IsAiming 			= true
			self.Owner.IsAiming = true
		else

 			self.IsAiming			= false
			self.Owner.IsAiming = false
		end
			
	
	if (self.Weapon) then
		self.Weapon:SetDTBool(1, b)
	end
end






/*---------------------------------------------------------
	onRestore
	Loaded a saved game (or changelevel)
---------------------------------------------------------*/
function SWEP:OnRestore()

	self.NextSecondaryAttack = 0
	self:SetIronsights( false )
	
end
function SWEP:CanDrawLaser()

	return self.SupportsLaser and ( self.LaserTime or 0 ) < CurTime()

end
function SWEP:Deploy()
	if CLIENT then
	
		self.LaserTime = CurTime() + 0.5
	
	end
	self:DeployAnimation()

	if (IsValid(self.Owner) and self.Owner:GetViewModel()) then
		self:IdleAnimation(self.Owner:GetViewModel():SequenceDuration())
	end

		local vm = self.Owner:GetViewModel()
	
	self:ResetVar()
	
	if !self.Silenced then
	if self.Weapon:Clip1() <= 0 then
		self.Weapon:SendWeaponAnim(ACT_VM_DRAW_EMPTY)
	else
		self.Weapon:SendWeaponAnim(ACT_VM_DRAW)
	end
	elseif self.Silenced and self.SilencerAnim then

	self.Weapon:SendWeaponAnim(ACT_VM_DRAW_SILENCED)

	end
	
	self.Weapon:SetNextPrimaryFire(CurTime() + self.DeployDelay + 0.05)
	self.Weapon:SetNextSecondaryFire(CurTime() + self.DeployDelay + 0.05)
	self.ActionDelay = (CurTime() + self.DeployDelay + 0.05)

	self:SetIronsights(false)

	return true
end
---------------------------------------------------------*/
function SWEP:DeployAnimation()

	-- Weapon has a suppressor
		if self.Silenced and self.SilencerAnim then
			

		self.Weapon:SendWeaponAnim( ACT_VM_DRAW_SILENCED )
			
		else
			self.Weapon:SendWeaponAnim( ACT_VM_DRAW )
		end
end


function SWEP:IdleAnimation(time)

	if not self.AllowIdleAnimation then return false end

	self.IdleApply = true
	self.ActionDelay = CurTime() + time
	self.IdleDelay = CurTime() + time
end


function SWEP:SetSilencer( b )
	
	self.Silenced = b
	
	if SERVER then
		if self.LastSilBool != b then
			self.LastSilBool = b
			umsg.Start("ClSendSilencer", self.Owner)
				umsg.Bool(b)
			umsg.End()
		end
	end	
	
end
function SWEP:ResetVar()

end

function SWEP:GetSilencer()

    return self.Silenced
	
end



function SWEP:OnRemove()
	self:ResetVar()
end

function SWEP:OnRestore()
	self:ResetVar()
end


function SWEP:OwnerChanged()
	self:ResetVar()
end