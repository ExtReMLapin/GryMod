if SERVER then
	AddCSLuaFile("shared.lua")
	SWEP.HoldType = "ar2"
end

if CLIENT then

	SWEP.DrawAmmo			= true
	SWEP.DrawCrosshair		= true
	SWEP.ViewModelFlip		= true
	SWEP.PrintName			= "SCAR by [ExtReM] Lapin"			
	SWEP.Author			= "Lapin"
	SWEP.Slot			= 2
	SWEP.SlotPos			= 5

	killicon.AddFont( "weapon_glock", "CSKillIcons", SWEP.IconLetter, Color( 255, 80, 0, 255 ) )
	
	SWEP.SupportsLaser		= true
	SWEP.LaserAttachment 		= 1	
	SWEP.LaserOffset 		= Angle( 0, 0, 90 )
	SWEP.LaserScale 		= 50
	SWEP.LaserBeamOffset 		= Vector( 999, 9999, 090 )
end

SWEP.Category	= "Crysis Sweps"
SWEP.Base	= "weapon_grymod_base"
SWEP.BobScale 	= 1.5
SWEP.SwayScale 	= 1
SWEP.PrintName	= "Crysis Scar"	
SWEP.Author	= "[ExtReM] Lapin"
SWEP.Contact	= "Add ExtReMLapin on steam"
SWEP.Instructions	= "Shoot First, then ask Questions Later"
SWEP.Spawnable	= true
SWEP.AdminSpawnable	= false
SWEP.Weight	= 2
SWEP.AutoSwitchTo	= true
SWEP.AutoSwitchFrom	= true
SWEP.Primary.Sound	= Sound("Weapons/crym4a1/m4a1_unsil-1.wav")
SWEP.Primary.Damage	= 20
SWEP.Primary.NumShots	= 1
SWEP.Primary.ClipSize	= 40
SWEP.Primary.Delay	= 0.1
SWEP.Primary.DefaultCli	= 120
SWEP.Primary.Automatic	= true
SWEP.Primary.Ammo	= "smg1"
SWEP.Primary.Automatic	= true

SWEP.Secondary.ClipSize	= -1
SWEP.Secondary.DefaultClip	= -1
SWEP.Secondary.Automati	= false
SWEP.Secondary.Ammo	= "none"
SWEP.IdleDelay		= 0
SWEP.IdleApply		= false
SWEP.AllowIdleAnimation	= true
SWEP.AllowPlaybackRate	= true

SWEP.IronSightsPos = Vector (4.076, -7.3, 1.1002)
SWEP.IronSightsAng = Vector (-0.37, 0.2, 0.0)
SWEP.ViewModel			= "models/weapons/v_cry_m4a1.mdl"
SWEP.WorldModel			= "models/weapons/w_rif_m4a1.mdl"

SWEP.ShellEjectAttachment	= "2"
SWEP.ShellEffect		= "rg_shelleject_rifle"
SWEP.CrouchModifier		= 0.6
SWEP.IronSightModifier 		= 0.6
SWEP.AvailableFireModes		= {"Auto"}
SWEP.AutoRPM			= 500
SWEP.DrawFireModes		= true

SWEP.ScopeZooms			= {2}
SWEP.RedDot			= true
SWEP.RedDot			= true
