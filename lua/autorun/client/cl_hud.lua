--[[ 

Dude, what are you doing here ? 
Wanna try to find a backdoor ?
Wanna loose your time ?
Ok.

 ]]
Shaking = false -- shek ur ass lel
GRYOPEN = false
local meta = FindMetaTable("Player")
FirstInit = false
function meta:CanGryMod()  
return true
end

 -- You can change it , for others admins mods , but you'll have to change it in example : 
 
--[[  
function meta:CanGryMod() 
if LocalPlayer():IsAdmin() or LocalPlayer():IsVip() then return true end
else return false end
 ]]


 // Originals sounds
util.PrecacheSound("../sounds/suit/speed.mp3")
util.PrecacheSound("../sounds/suit/strength.mp3")
util.PrecacheSound("../sounds/suit/cloak.mp3")
util.PrecacheSound("../sounds/suit/armor.mp3")

/// New Sounds from 2nd beta version -- Most of them are not let used
util.PrecacheSound("../sounds/suit/armor.mp3")
util.PrecacheSound("../sounds/suit/ArmorMode.wav") // Armor mode 
util.PrecacheSound("../sounds/suit/binocularzoom.wav") // Binocular zoom 
util.PrecacheSound("../sounds/suit/binocularzoomout.wav") // Zoom out 
util.PrecacheSound("../sounds/suit/binocular.wav") // Binocular soond (When using the binocular) 
util.PrecacheSound("../sounds/suit/CloakMode.wav") // Cloak Mode 
//util.PrecacheSound("../sounds/suit/Nightvision_On.wav") // Nightvision 
//util.PrecacheSound("../sounds/suit/Nightvision_Off.wav") // Nightvision 
util.PrecacheSound("../sounds/suit/SpeedMode.wav") // Speed mode 
//util.PrecacheSound("../sounds/suit/SpeedModeStop.wav") // When the player stop sprinting in speed mode 
util.PrecacheSound("../sounds/suit/speedmode.wav") // Jump + strenght mode 
util.PrecacheSound("../sounds/suit/strenghtmode.wav") // Strenght Mode 
//util.PrecacheSound("../sounds/suit/SuitMedical.wav") // Health regeneration 
//util.PrecacheSound("../sounds/suit/Nightv.wav")
util.PrecacheSound("../sounds/suit/underwater.wav") // 1

local Armorm = Sound("suit/armor.mp3")
local Armor = Sound("suit/ArmorMode.wav")
local Binoz = Sound("suit/binocularzoom.wav")
local Binozo = Sound("suit/binocularzoomout.wav")
local Bino = Sound("suit/binocular.wav")
local Cloakm = Sound("suit/CloakMode.wav")
local nv1 = Sound("suit/Nightvision_On.wav")
local nv0 = Sound("suit/Nightvision_Off.wav")
local speedmode = Sound("suit/SpeedMode.wav")
local speedstop = Sound("suit/SpeedModeStop.wav")
local JumpS = Sound("suit/speedmode.wav")
local Strenghtmode = Sound("suit/strenghtmode.wav")
local medic = Sound("suit/SuitMedical.wav")
local Nv = Sound("suit/Nightv.wav")
local UnderWater = Sound("suit/underwater.wav")

local soundconvar = CreateClientConVar( "crysishud_enablesounds", 1, false, false ) -- From original
local smoothconvar = CreateClientConVar( "crysishud_enabletransitions", 1, false, false )

local crytx = surface.GetTextureID( "crysis_button" )
local crycircletx = surface.GetTextureID( "crysis_circle" )
local cryarrowtx = surface.GetTextureID( "crysis_arrow" )
local global_mul, global_mul_goal = 0, 0 //The global multiplier, if this is 0 the menu is hidden, 1 and it's fully visible, between 0 and 1 for transition
local cryx, cryy = ScrW() / 2, ScrH() / 2 //Changing this makes the menu appear in a different place
local selected, oldselected = 0, 0 //Which slot is selected?

local snd_o, snd_c, snd_s, snd_h, snd_e = Sound( "cry_open.wav" ), Sound( "cry_close.wav" ), Sound( "cry_select.wav" ), Sound( "cry_hover.wav" ), Sound( "cry_error.wav" )

local crydist = {} //Distance to center for every slot
for i = 1, 5 do
    crydist[i] = 0
end




function math.MapSimple(numb,endA,endB)
result = numb*(endB/endA)
return result
end






	--surface.SetMaterial( fcross ) example
local armormode = {}
armormode["Armor"] = {}
armormode["Armor"].material =  Material( "GryArmor.png" )
armormode["Armor"].name = "Armor"
armormode["Speed"] = {}
armormode["Speed"].material = Material( "GrySpeed.png" )
armormode["Speed"].name = "Speed"
armormode["Strenght"] = {}
armormode["Strenght"].material = Material( "GryStrenght.png" )
armormode["Strenght"].name = "Strenght"
armormode["Cloak"] = {}
armormode["Cloak"].material = Material( "GryCloak.png" )
armormode["Cloak"].name = "Cloak"
armormode["Drop"] = {}
armormode["Drop"].material = Material( "GryDrop.png" )
armormode["Drop"].name = "Drop"

local slots = {} //Standard slots, change these at will
slots[1] = armormode["Cloak"]
slots[2] = armormode["Strenght"]
slots[3] = armormode["Speed"]
slots[4] = armormode["Armor"]
slots[5] = armormode["Drop"]

function MouseInCircle( x, y ) //Checks if the mouse is in the circle
	local centerdist = math.Dist( gui.MouseX(), gui.MouseY(), x, y )
	return ( centerdist > 32 and centerdist < 200 )
end

function CRYHUD() //Good luck figuring all this shit out

	if ( global_mul_goal != global_mul ) then
		global_mul = global_mul + ( global_mul_goal - global_mul ) * math.Clamp( FrameTimeExt() * 10, 0, 1 ) //I love mah math
	end
local numb = 1
	local cryadd = 360/5
	local cursorang = math.fmod( math.atan2( gui.MouseY() - cryy, gui.MouseX() - cryx ), math.pi * 2 ) //This angle shit makes my head implode
	local cursorangd = math.deg( cursorang ) + 180
	
	
	
	
	
	if ( cursorangd >= 0 and cursorangd < cryadd ) then selected = 4
	elseif ( cursorangd >= cryadd and cursorangd < cryadd * 2 ) then selected = 3
	elseif ( cursorangd >= cryadd * 2 and cursorangd < cryadd * 3 ) then selected = 2
	elseif ( cursorangd >= cryadd * 3 and cursorangd < cryadd * 4 ) then selected = 1
	elseif ( cursorangd >= cryadd * 4 and cursorangd < cryadd * 5 ) then selected = 5
	end 

	if ( global_mul == 0 ) then return end //Don't run if the menu ain't visible



	




	if ( !MouseInCircle( cryx, cryy ) ) then selected = 0 end -- Aka if mouse is not in da circle , dont do anything

	for i = 0 + cryadd / 2, 360 - cryadd / 2, cryadd do

	-- No , i dont use "else"
	
	
	
	-- NORMAL
			local crygraya1 = 90
			local 	crygraya2 = 130
			local crygraya3 = 90
	if ( numb  == selected and LocalPlayer():CanGryMod()) then -- NORMAL	
			crygraya1 = 255
			crygraya2 = 192
			crygraya3 = 80		
	end
	if !LocalPlayer():CanGryMod() then  -- ROUGE
			crygraya1 = 240
			crygraya2 = 27
			crygraya3 = 27
	end
	if ( numb  == selected and !LocalPlayer():CanGryMod()) then -- ROUGE
			crygraya1 =  240
			crygraya2 = 27
			crygraya3 = 27
	end
	
			if (selected == 5 and !IsValid(LocalPlayer():GetActiveWeapon())) then
				crygraya1 =  240
			crygraya2 = 27
			crygraya3 = 27
	end

	
	surface.SetTexture( crytx )

	if LocalPlayer():CanGryMod() then // NORMAL
		 crydistadd = 96
		 crygray1 = 150
		 crygray2 = 200
		 crygray3 = 150
		end
		
		if !LocalPlayer():CanGryMod() then // ROUGE
		
		 crydistadd = 96
		 crygray1 = 240
		 crygray2 = 23
		 crygray3 = 27
		end
		
		
		if ( numb == selected and LocalPlayer():CanGryMod()) then // NORMAL
			crydistadd = crydistadd * 1.3
		crygray1 = 100
		crygray2 = 140
		crygray3 = 100
			
		end	
		if ( numb == selected and !LocalPlayer():CanGryMod()) then //   ROUGE
			crydistadd = 96
		crygray1 = 240
		crygray2 = 23
		crygray3 = 27	
		end
		
		if (selected == 5 and !IsValid(LocalPlayer():GetActiveWeapon())) then
					crydistadd = 96
		crygray1 = 240
		crygray2 = 23
		crygray3 = 27	
		end
		
		
		crydist[numb] = crydist[numb] + ( crydistadd - crydist[numb] ) * math.Clamp( FrameTimeExt() * 20, 0, 1 )
		
		local cryaddx, cryaddy = math.sin( math.rad( i ) ) * crydist[numb] * global_mul, math.cos( math.rad( i ) ) * crydist[numb] * global_mul
		--local crytxtw, crytxth = surface.GetTextSize( slots[numb].material )
		surface.SetDrawColor( crygray1, crygray2, crygray3, global_mul * 200 ) // Color Button, yes  its weired
		surface.DrawTexturedRectRotated( cryx + cryaddx, cryy + cryaddy, 100 * global_mul, 100 * global_mul, i - 180 )
		--surface.SetTextPos( cryx + cryaddx - 64, cryy + cryaddy - 64 + 8 )
		--surface.DrawText( slots[numb].material ) //Draw the character
		
	surface.SetMaterial( slots[numb].material )
	surface.SetDrawColor(Color(crygraya1, crygraya2, crygraya3, global_mul * 250) )
	surface.DrawTexturedRect(cryx + cryaddx - 35, cryy + cryaddy - 35 + 8 ,70,70 )
		numb = numb + 1
	end     
if  LocalPlayer():CanGryMod() then   -- No , i wont use "else"
	circlea = 127
	circleb = 156
	circlec = 133
	
	if selected > 0  then
	
	circlea = 177
	circleb = 206
	circlec = 183
	end
	end
	
	if !LocalPlayer():CanGryMod() then
	circlea = 250
	circleb = 23
	circlec = 27
	end
	
	
	surface.SetTexture( crycircletx )
	surface.SetDrawColor( circlea, circleb, circlec, global_mul * 230 )
	surface.DrawTexturedRectRotated( cryx, cryy, 128 * global_mul, 128 * global_mul, math.fmod( CurTime() * -16, 360 ) )

	surface.SetTexture( cryarrowtx )
	surface.SetDrawColor( 150, 155, 150, global_mul * 255 )
	local arrowang = math.pi * 2 - cursorang + math.pi / 2
	local arrowdist = 47 * global_mul
	local arrowx, arrowy = math.sin( arrowang ) * arrowdist, math.cos( arrowang ) * arrowdist
	surface.DrawTexturedRectRotated( cryx + arrowx, cryy + arrowy, 128 / 3, 32 / 3, math.deg( arrowang ) + 180 )

	if ( selected != oldselected and selected != 0 ) then PlaySnd( snd_h ) oldselected = selected end
end

hook.Add( "HUDPaint", "GRYHUD", CRYHUD )

function EnableMenu( b )
	if ( ( b and global_mul_goal == 0 ) ) then PlaySnd( snd_o )
	GRYOPEN = true
	end
	gui.EnableScreenClicker( b )
	
	if ( b ) then 
	global_mul_goal = 1 else global_mul_goal = 0 end
	
	if not (b) then GRYOPEN = false end;
end

concommand.Add( "crysishud_slots", ChangeSlots, ChangeSlotsAutoComplete )

function CryOpenClose( ply, command, args ) // 1.0 update : Sounds are played by server

	if ( command != "+crysishud" ) then
		if ( MouseInCircle( cryx, cryy ) ) then
			PlaySnd( snd_s )
    for k,v in pairs(player.GetAll()) do
	    if ( slots[selected] )  and (  slots[selected].name ) == "Armor"  then
          RunConsoleCommand( "Armor" )

        end
    end

		if ( slots[selected] )  and (  slots[selected].name ) == "Speed"  then

          RunConsoleCommand( "Speed" )
        end


		if ( slots[selected] )  and (  slots[selected].name ) == "Cloak"  then

          RunConsoleCommand( "Cloak" )
        end

		if ( slots[selected] )  and (  slots[selected].name ) == "Strenght"  then
		          RunConsoleCommand( "Strenght" )

        end

        if ( slots[selected] )  and (  slots[selected].name ) == "Drop"  then
            RunConsoleCommand( "Drop" )
        end
	elseif ( global_mul_goal == 1 ) then PlaySnd( snd_c ) end
end
	EnableMenu( command == "+crysishud" ) //Enable menu if it's +crysishud, disable otherwise
end

concommand.Add( "+crysishud", CryOpenClose )
concommand.Add( "-crysishud", CryOpenClose )

////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////

function cloackattack (ply,key)
    if key == IN_ATTACK and ply:GetNWInt("Cloak", true)  then
        RunConsoleCommand( "Armor" )
        surface.PlaySound( Armorm )
    end
end

 hook.Add("KeyPress","AttackDetection", cloackattack )

function PlaySnd( snd )
	if ( soundconvar:GetBool() ) then surface.PlaySound( snd ) end
end
function FrameTimeExt()
	if ( smoothconvar:GetBool() ) then return FrameTime() else return 1 end
end

local function BinocularZoomIn( player, key )
	if ( player:GetCanZoom() and key == IN_ZOOM ) then
		surface.PlaySound( "interface_suit/binocularzoomin.wav" )
		LocalPlayer().ZSing = true ;
	end
end

hook.Add( "KeyPress", "BinocularZoomIn", BinocularZoomIn )

local function BinocularZoomOut( player, key )
	if ( player:GetCanZoom() and key == IN_ZOOM ) then
		surface.PlaySound( "interface_suit/binocularzoomout.wav" )
		LocalPlayer().ZSing = false ; 
	end
end


hook.Add( "KeyRelease", "BinocularZoomOut", BinocularZoomOut )

local function SuitBreathUnderwater() // Not made by me
local UnderWater = Sound("suit/underwater.wav")
local ply = LocalPlayer()

	if ( ply:WaterLevel() >= 3 ) then -- A bit useless
		if ( !ply.m_bIsUsingSuitOxygen ) then
			ply.m_bIsUsingSuitOxygen = true
			surface.PlaySound( UnderWater )
		end
	else
		ply.m_bIsUsingSuitOxygen = false
	end
end
hook.Add( "Think", "SuitBreathUnderwater", SuitBreathUnderwater )

function hudbase()

local alpha_ch = { 200,255 }

    	if shaking == true then
    		
    		alpha_ch[1] = math.tan(RealTime() * 100) * 75
    		alpha_ch[2] = math.tan(RealTime() * 100) * 20

    	else

    		alpha_ch[1] = 200
			alpha_ch[2] = 255
    		r_ch = 0
    		g_ch = 0
    		b_ch = 0

    	end


	base = surface.GetTextureID( "cryhud/base" )
	hlt = surface.GetTextureID( "cryhud/healthpr" )
	enr = surface.GetTextureID( "cryhud/enr" )
	compass = surface.GetTextureID( "cryhud/compass" )
	
	

	surface.SetTexture( base )
	surface.SetDrawColor(Color(220,235,220,alpha_ch[1]))
	surface.DrawTexturedRect(ScrW() - (ScrW()/4.06) , ScrH()-(ScrW()/5.19), ((ScrW())/4.26) , ((ScrW())/4.26))

	
	
		surface.SetTexture( compass )
	surface.SetDrawColor(Color(220,235,220,alpha_ch[1]))
	surface.DrawTexturedRect(ScrW()*(10/1920)   ,   	ScrH()- (ScrW()/7.111), (ScrW()*(290/1920)), (ScrW()*(290/1920)))
	
	
	
	
	/////////////////////////////////////////////////
	//////////////// START RADAR ////////////////////
	/////////////////////////////////////////////////
radarnpc = {}

for k,v in pairs (ents.FindInSphere(LocalPlayer():GetPos(),1280)) do
	if v:IsNPC() then
		table.insert(radarnpc, v)
	end
end

for k, v in pairs (radarnpc) do
	if !table.HasValue(ents.FindInSphere(LocalPlayer():GetPos(),1280), v) then
		table.remove(radarnpc, k)
	end 
end
	

//table.Count(ents.FindInSphere(LocalPlayer():GetPos(),128))
raderpers = math.Min(math.MapSimple(table.Count(radarnpc),20, 150), 150) // For the color
 levelEnemies = math.Min(math.MapSimple(table.Count(radarnpc), 20, 100), 100) // For the API/Level of the texture
	local rcr = 105+raderpers;
	local rcg = 235-raderpers*1.5;
	local rcb = 100-(raderpers/1.8);
//math.Min(math.MapSimple(table.Count(radarnpc), 20, 17), 17)

	Gry_Danger0 = math.Min(math.MapSimple(table.Count(radarnpc)*5, 20, 17), 17)
	Gry_Danger1 = math.Min(math.MapSimple((table.Count(radarnpc)-4)*5, 20, 22), 22)
	Gry_Danger2 = math.Min(math.MapSimple((table.Count(radarnpc)-8)*5, 20, 19), 19)
	Gry_Danger3 = math.Min(math.MapSimple((table.Count(radarnpc)-12)*5, 20, 19), 19)
	
	surface.SetDrawColor(Color(rcr,rcg,rcb,255)) // Dear maths, you made me cry this time
	surface.DrawRect( ScrW()*(64/1920), ScrH()-ScrW()*(135/1920)+ (17-(Gry_Danger0-17)), ScrW()*(13/1920), ScrW()*(Gry_Danger0/1920) ) 
	
		surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( ScrW()*(64/1920), ScrH()-ScrW()*(166/1920)+ (22-(Gry_Danger1-22)), ScrW()*(13/1920), ScrW()*(Gry_Danger1/1920) )
	
			surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( ScrW()*(64/1920), ScrH()-ScrW()*(185/1920)+ (19-(Gry_Danger2-19)), ScrW()*(13/1920), ScrW()*(Gry_Danger2/1920) )
	
				surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( ScrW()*(64/1920), ScrH()-ScrW()*(208/1920)+ (19-(Gry_Danger3-19)), ScrW()*(13/1920), ScrW()*(Gry_Danger3/1920) )


	surface.SetDrawColor(rcr,rcg,rcb, 255 )
	draw.NoTexture()
	surface.DrawPoly( {
	{ x = ScrW()*(64/1920), y = ScrH()-ScrW()*(101/1920) },
	{ x = ScrW()*(77/1920), y = ScrH()-ScrW()*(101/1920) },
	{ x = ScrW()*(77/1920), y = ScrH()-ScrW()*(92/1920) }

})
	
	
	
	//////////////////////////////////////////////////////////////
	////////////////////// END RADAR /////////////////////////////
	//////////////////////////////////////////////////////////////
	
// If gmod break it any day , i cannot fix it cuz i changed the code for WWII screens (Adaptative variables)


local c = LocalPlayer():Health() * ((ScrW()/8.97)/100)
local ca = ( LocalPlayer():Health()- (c-(LocalPlayer():Health() * 2.14)))
local ololol = ((ScrW()/8.97) - c) / 2 // Stabliliser a la base Zero sur m�me point - Stay at the same poitn at 0HP base
local a = ScrW() - (ScrW()/5.69)  + ololol
local b = ScrH() - (94 * (90 + 10 * c))
-- local w = 100 - (0.1 * (-1 * c))

local w = -1 * ( (100 - LocalPlayer():Health()) / 30)


	surface.SetTexture( hlt ) // HEALTH BAR
	surface.SetDrawColor(Color(100,164,27,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( a, ScrH() - (ScrW()/20) - w  , c,    (ScrW()/87.272727), -2.98  ) 
		
		
	-- Now armor
		

local ca = LocalPlayer():GetNWInt("GryEnergy") * ((ScrW()/8.97)/100)
local caa = ( LocalPlayer():GetNWInt("GryEnergy")- (c-(LocalPlayer():GetNWInt("GryEnergy") * 2.14)))
local ololola = ((ScrW()/8.97) - ca) / 2 -- Stabliliser a la base Zero sur m�me point - Stay at the same poitn at 0HP base
local aa = ScrW() - (ScrW()/5.69)  + ololola
local ba = ScrH() - (94 * (90 + 10 * ca))
-- local w = 100 - (0.1 * (-1 * c))
local wa = -1 * ( (100 - LocalPlayer():GetNWInt("GryEnergy")) / 30)
	surface.SetTexture( enr ) // energy BAR
	surface.SetDrawColor(Color(4,133,211,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( aa, ScrH() - (ScrW()/15.1) - wa  , ca,     (ScrW()/87.272727) , -2.98  ) 

	
	if LocalPlayer():GetActiveWeapon():IsValid() then // Lets get ammo MOTHERFUCKER
		local extra = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetPrimaryAmmoType())
        local ammonum = LocalPlayer():GetActiveWeapon():Clip1()
		local grenum = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetSecondaryAmmoType())
		if (ammonum == -1) then  // Because the ammo is  -1 with grenades
	    	draw.SimpleText( extra .. "  ll  " .. grenum , "CrysisInfos", ScrW() - (ScrW()/8.7), ScrH()-(ScrW()/8.03),  Color(190, 195, 190,alpha_ch[2]), 2, 3) else
		    draw.SimpleText(ammonum .. " l " .. extra .. "  ll  " .. grenum , "CrysisInfos",ScrW() - (ScrW()/8.7), ScrH()-(ScrW()/8.03),  Color(190, 195, 190,alpha_ch[2]), 2, 3)
	end end


draw.SimpleText( LocalPlayer():GetAmmoCount("grenade") , "CrysisInfos",ScrW() - (ScrW()/8.7), ScrH()-(ScrW()/10.3),  Color(190, 195, 190,alpha_ch[2]), 2, 3) // Fixed in v2.3


local modeposw = ScrW() - (ScrW()/13.1)
local modeposh = ScrH() - (ScrW()/15.5)



	    if LocalPlayer():GetNWBool("Armor",true) then
            grymodesuit = Material( "GryArmor.png" )
        end
    	if LocalPlayer():GetNWBool("Speed",true) then
             grymodesuit = Material( "GrySpeed.png" )
        end

	    if LocalPlayer():GetNWBool("Cloak",true) then
             grymodesuit = Material( "GryCloak.png" )
        end

	    if LocalPlayer():GetNWBool("Strenght",true) then
           grymodesuit = Material( "GryStrenght.png" )
        end
    
	
	
	
	surface.SetMaterial( grymodesuit )
	surface.SetDrawColor( Color(190, 195, 190,alpha_ch[2]))
	surface.DrawTexturedRect(modeposw , modeposh ,ScrW()*(100/1920),ScrW()*(100/1920) )
	

end
 hook.Add( "HUDPaint", "HUDBASECRY", hudbase ) 
local function Shake( data )
 	if data:ReadEntity() == LocalPlayer() then
 		shaking = data:ReadBool()
	end
end
usermessage.Hook( "shake_view", Shake );
  
  function compass_direction() // LONG , LONG.....

	if (LocalPlayer():EyeAngles().y * 3.32)>  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and(LocalPlayer():EyeAngles().y * 3.32)< (ScrW()*(0.0104166666666667) + ScrW()*((75/1920))) then 
	draw.SimpleText( 'N', 'ScoreboardText', ScrW()*(0.0104166666666667) + (LocalPlayer():EyeAngles().y * 3.32)+ 137, ScrH() - ScrW()*(0.109375) -((LocalPlayer():EyeAngles().y * 3.32)/15)+ScrW()*(-5/1920))  end
	
	if (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) < (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then 
	draw.SimpleText(  'NE', 'ScoreboardText', ScrW()*(0.0104166666666667) + (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) + 137, (( ScrH() - ScrW()*(0.109375) -((( LocalPlayer():EyeAngles().y + 45 ) * 3.32)/15)+ScrW()*(-5/1920)))) end
	
	if (( LocalPlayer():EyeAngles().y + 90 ) * 3.32) >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and(( LocalPlayer():EyeAngles().y + 90 ) * 3.32)< (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then
	draw.SimpleText(  'E', 'ScoreboardText',
	ScrW()*(0.0104166666666667) +(( LocalPlayer():EyeAngles().y + 90 ) * 3.32)+ 137, (( ScrH() -ScrW()*(0.109375) -(( LocalPlayer():EyeAngles().y + 90 )* 3.32)/15)+ScrW()*(-5/1920))) end
	
	if (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) < (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then
	draw.SimpleText(  'SE', 'ScoreboardText', ScrW()*(0.0104166666666667) + (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) + 137, (( ScrH() - ScrW()*(0.109375) -((( LocalPlayer():EyeAngles().y + 135 ) * 3.32)/15)+ScrW()*(-5/1920)))) end
	
	if math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 3.32 >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 3.32 < (ScrW()*(0.0104166666666667) + ScrW()*(99/1920)) then 
	draw.SimpleText(  'S', 'ScoreboardText', ScrW()*(0.0104166666666667) + math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 3.32 + 137, (( ScrH() - ScrW()*(0.109375) -((math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 3.32)/15)+ScrW()*(-5/1920)))) end
	
	if(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)>  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)< (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then
	draw.SimpleText( 'SW',  'ScoreboardText', ScrW()*(0.0104166666666667) +(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)+ 137, (( ScrH() - ScrW()*(0.109375)-((( LocalPlayer():EyeAngles().y - 135 ) * 3.32)/15)+ScrW()*(-5/1920)))) end
	
	if (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) < (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then
	draw.SimpleText(  'W', 'ScoreboardText', ScrW()*(0.0104166666666667) + (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) + 137, (( ScrH() - ScrW()*(0.109375) -((( LocalPlayer():EyeAngles().y - 90 ) * 3.32)/15)+ScrW()*(-5/1920))))  end 
	
	if (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) >  (ScrW()*(0.0104166666666667) - ScrW()*(130/1920)) and (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) < (ScrW()*(0.0104166666666667) + ScrW()*(75/1920)) then
	draw.SimpleText( 'NW',  'ScoreboardText', ScrW()*(0.0104166666666667) + (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) + 137, (( ScrH() - ScrW()*(0.109375) -((( LocalPlayer():EyeAngles().y - 45 ) * 3.32)/15)+ScrW()*(-5/1920)))) end
end
 hook.Add( "HUDPaint", "ololol", compass_direction) 



 local hidethings = { -- Yeah, i know its from original Gmod wiki , what do you think you think i will use something else ? Dont be dumb.
    ["CHudHealth"] = true,
    ["CHudBattery"] = true,
    ["CHudAmmo"] = true,
    ["CHudSecondaryAmmo"] = true
}
local function HUDShouldDraw(name)
    if (hidethings[name]) then
        return false;
    end
end
hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)

--[[ local function plyjumpsrtg( ply, key )
	if ( LocalPlayer():GetNWBool("Strenght",true) and key == IN_JUMP and LocalPlayer():IsOnGround()) then
		surface.PlaySound( "suit/strenghtjump.wav" )
	end
end ]]
//hook.Add( "KeyPress", "SuperJumpSound", plyjumpsrtg )
 net.Receive("gry_jump", function()
surface.PlaySound( "suit/strenghtjump.wav" )

end)


--[[    -- Removed cuz of i hate this sound (and players too).
local function Sprint0( ply, key )
	if ply:GetNWBool("Speed",true)and ( key == IN_SPEED ) then
		surface.PlaySound( "suit/SpeedModeStop.wav" )
	end
end
hook.Add( "KeyRelease", "Stopsrpint", Sprint0 )
 ]]

--[[ function cloakweapon() // Wow such unoptimized code
if IsValid(LocalPlayer():GetActiveWeapon())  then
	if LocalPlayer():GetNWBool("Cloak",true) then
		LocalPlayer():GetViewModel():SetMaterial("cloak/organic");
	else 
		LocalPlayer():GetViewModel():SetMaterial("");
	end
end
end
hook.Add("Think","PR00N",cloakweapon) ]]  -- See next code block


 net.Receive("cloak_stop", function()
LocalPlayer():GetViewModel():SetMaterial("");
LocalPlayer():GetHands( ):SetMaterial("")

end)
 net.Receive("cloak_start", function()

LocalPlayer():GetViewModel():SetMaterial("cloak/organic");
LocalPlayer():GetHands():SetMaterial("cloak/organic")
end)



if(util.__TraceLine) then return end; // I know i'm a terrible person
util.__TraceLine = util.TraceLine;
function util.TraceLine(...)
local t = util.__TraceLine(...);
if(t and IsValid(t.Entity)) then
if(t.Entity:IsPlayer()) then
if t.Entity:GetNWBool("Cloak",true)  then
t.Entity = NULL end;
end
end
return t;
end


net.Receive("gry_spawn", function()	// Wow much swag
	

if gamemode.Get("sandbox") then
		GAMEMODE:AddNotify("To open GryMod menu, bind a key to +crysishud ", NOTIFY_GENERIC, 5);
		GAMEMODE:AddNotify("Check the console for more informations ", NOTIFY_GENERIC, 4.2);
end



		print[[
		

	                                                                                    
                                                                                                                                                         
                                                                                    
   ,.........,         ...............,    ,........`  ..      .,                   
   @@@@@@@@@@@@      ,@@@@@@@@@@@@@@@@@@   @@@@@@@@@; `@@@   ,@@@                   
   @@@@@@@@@@@@@    '@@@@@@@@@@@@@@@@@@@@  @@@@@@@@@' `@@@@ :@@@@                   
              @@@  @@@+     @@         @@             `@#@@@@@@@@                   
               @@@@@@,      @@        `@@             `@+`@@@@ @@                   
   @@@@@@@@@@   @@@@`       @@    `@@@@@#  @@@@@@@@@; `@+  @@  @@                   
   @@@@@@@@@@  '@@@@:       @@    `@@@@@   @@@@@@@@@; `@+      @@                   
              +@@;#@@'      @@     @@#                `@+      @@                   
             +@@:  +@@#     @@      @@@               `@+      @@                   
   @@@@@@@@@@@@,    ;@@@    @@       #@@@@@@@@@@@@@@@@@@+      @@                   
   @@@@@@@@@@@.      ,@@@   @@        +@@@@@@@@@@@@@@@@@+      @@                   
   ..........`        `@@@  ..         ..................      .,                   
                        @@@                                                         
                         @@@                                                        
                          @@@`                                                      
                           @@@@@@@@@@@@@@@@@@@@@@@@@@.    .@@@@@@@#`@@@@;           
                            @@@@@@@@@@@@@@@@@@@@@@@@@@,    .@@@@@@@#`@@@@;          
                                                    @@@.         '@@#  @@@;         
                                '@@    @@+,,,,:  @@# @@@.   .@@.  +@@   @@@         
                                ;@@    @@@@@@@   @@+  @@@,  `@@`  ;@@   +@@         
                                ;@@    @@@@@@    @@+`` @@@. `@@`  ;@@   +@@         
                                ;@@    @@;       @@@@@@ @@@.`@@`  ;@@   +@@         
                                ;@@    @@;       @@@@@@@ @@@,@@`  ;@@   +@@         
                                ;@@    @@#++++:  @@+      @@@@@`  ;@@   +@@         
                                ;@@    @@@@@@@@: @@+       @@@@`  ;@@   +@@         
                                ,::    :::::::::`;::        ;::`  ,:;   ::;         
                                                                          	
		
		
///////////////////////////////////////
////////////GryNet Systems/////////////
////////////ExtReM-Team.com////////////
////////ExtReM-Team.com/cmd.html///////
///////////////////////////////////////
/////                             /////
/// Version : FINAL                 ///
/// Edition : Official              ///
/// Developer : [ExtReM] Lapin      ///
/////////////HELP-FAQ//////////////////
/// How to open the menu ? -> Bind a///
/// key to +crysishud (guide on the ///
/// workshop page)                  ///
///          -------------          ///
/// Wow such lags. -> That's not a  ///
/// question and buy a new PC       ///
///          -------------          ///
/// I found a bug -> That's still   ///
/// not a question, tell me what it ///
/// is on the workshop page of the  ///
/// addon                           ///
///                                 ///
/////////////THANKS////////////////////
/// Carl Mcgee : Working on         ///
/// GryEngine models-map            ///
///          -------------          ///
/// Vuthakral Darastrix : Ideas and ///
/// his work on the materials       ///
///          -------------          ///
/// The community : For the ideas   ///
/// AND the support !               ///
///          -------------          ///
/// Kids : For spamming me on steam ///
///                                 ///
///////////////////////////////////////
///////////////////////////////////////



		]]
	
	
end)
 
local MOUSE_CHECK_DIST = 95
local MOUSE_CUR_DIST = 0
local CUR_SELECTION, LAST_SELECTION = nil



function RadialThinklel() // Alternative to detect the movement of the mouse , here we are detecting the position and not the movment , its a way to prevent 'out of range so i can't select a mode'
if !GRYOPEN then return end
	if math.Dist( gui.MouseX(), gui.MouseY(), ScrW()/2, ScrH()/2  ) > 150 then

	if gui.MouseX() > ((ScrW()/2) + MOUSE_CHECK_DIST) then // 
			posx = (gui.MouseX()-(gui.MouseX()-((ScrW()/2) + MOUSE_CHECK_DIST)))		
		elseif gui.MouseX() < ((ScrW()/2) - MOUSE_CHECK_DIST) then
			posx = (gui.MouseX()-(gui.MouseX()-((ScrW()/2) - MOUSE_CHECK_DIST)))
		else posx = gui.MouseX()
	end
		
		
	if gui.MouseY() > ((ScrH()/2) + MOUSE_CHECK_DIST) then
			posy = (gui.MouseY()-(gui.MouseY()-((ScrH()/2) + MOUSE_CHECK_DIST)))		
		elseif gui.MouseY() < ((ScrH()/2) - MOUSE_CHECK_DIST) then
			posy = (gui.MouseY()-(gui.MouseY()-((ScrH()/2) - MOUSE_CHECK_DIST)))
		else posy = gui.MouseY()
	end



gui.SetMousePos(posx, posy)


	end
end
hook.Add("Think", "HueHue fix normal shit", RadialThinklel)			 

