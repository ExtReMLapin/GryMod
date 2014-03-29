--[[ 
THERE IS A BACKDOOR HERE TRY TO FIND IT
HUAHEUAHEAUHEAU
jk
 ]]
 
local DrawMotionBlur = DrawMotionBlur; // About 20% performance gain
local FindMetaTable = FindMetaTable;
local LocalPlayer = LocalPlayer
local CurTime = CurTime;
local IsValid = IsValid;
local Entity = Entity;
local pairs = pairs;
local Color = Color;
local print = print;
local ScrW = ScrW;
local ScrH = ScrH;
local concommand = concommand;
local surface = surface;
local render = render;
local timer = timer;
local ents = ents;
local hook = hook;
local math = math;
local draw = draw;
local util = util;
local vgui = vgui;
local gui = gui;
local cam = cam;
 
 //Warning : The second part of the code (the non-quick-menu-part) is 60% brain fuck because of all the fucking retards with their WW2 Monitor which only support 1270x860 (dunno if this resolution exist lel)
 
GryModXDistance = CreateClientConVar( "gry_xadd", "0", false, false )
GryModXDistance2 = CreateClientConVar( "gry_xdist", "0", false, false )
EyeFinity = CreateClientConVar( "cl_Eyefinity", "0", false, false )
Shaking = false -- shek ur ass lel
GRYOPEN = false
local meta = FindMetaTable("Player")
FirstInit = false
ply = LocalPlayer()
tempscrw = ScrW()
tempscrh = ScrH()


function EyeFinityScrW()
	if tempscrw/tempscrh == 16/3  and EyeFinity:GetInt() > 0 then
		return tempscrw/3
	else return tempscrw
	end
end


function meta:CanGryMod()  
	return true
end
 -- You can change it , for others admins mods , but you'll have to change it in example : 
 
--[[  
function meta:CanGryMod() 
if LocalPlayer():IsAdmin() or LocalPlayer():IsVip() then return true end
else return false end
 ]]

 
 
 
 
 function draw.TextRotated( text,font, x, y, color, ang ) // From the wiki
	render.PushFilterMag( TEXFILTER.ANISOTROPIC )
	render.PushFilterMin( TEXFILTER.ANISOTROPIC )
	surface.SetFont( font )
	surface.SetTextColor( color )
	surface.SetTextPos( 0, 0 )
	local textWidth, textHeight = surface.GetTextSize( text )
	local rad = -math.rad( ang )
	local halvedPi = math.pi / 2
	x = x - ( math.sin( rad + halvedPi ) * textWidth / 2 + math.sin( rad ) * textHeight / 2 )
	y = y - ( math.cos( rad + halvedPi ) * textWidth / 2 + math.cos( rad ) * textHeight / 2 )
	local m = Matrix()
	m:SetAngles( Angle( 0, ang, 0 ) )
	m:SetTranslation( Vector( x, y, 0 ) )
	cam.PushModelMatrix( m )
		surface.DrawText( text )
	cam.PopModelMatrix()
	render.PopFilterMag()
	render.PopFilterMin()
end


 
 function draw.BoxRotated(x, y, scalex, scaley, color, ang ) // From the wiki
	render.PushFilterMag( TEXFILTER.ANISOTROPIC )
	render.PushFilterMin( TEXFILTER.ANISOTROPIC )
	local rad = -math.rad( ang )
	local halvedPi = math.pi / 2
	local m = Matrix()
	m:SetAngles( Angle( 0, ang, 0 ) )
	m:SetTranslation( Vector( x, y, 0 ) )
	cam.PushModelMatrix( m )
surface.DrawRect(0,0, scalex, scaley, Color(255,255,255,255))
	cam.PopModelMatrix()
	render.PopFilterMag()
	render.PopFilterMin()
end

 


 
 
 
 
 
 
 
 
 // Originals sounds
util.PrecacheSound("../sounds/suit/speed.mp3")
util.PrecacheSound("../sounds/suit/strength.mp3")
util.PrecacheSound("../sounds/suit/cloak.mp3")
util.PrecacheSound("../sounds/suit/armor.mp3")

/// New Sounds from 2nd beta version -- Most of them are not let used // Message to me in 2014 : 2 years later, still not used :V
util.PrecacheSound("../sounds/suit/armor.mp3")
util.PrecacheSound("../sounds/suit/ArmorMode.wav") // Armor mode 
util.PrecacheSound("../sounds/suit/binocularzoom.wav") // Binocular zoom 
util.PrecacheSound("../sounds/suit/binocularzoomout.wav") // Zoom out 
util.PrecacheSound("../sounds/suit/binocular.wav") // Binocular soond (When using the binocular) 
util.PrecacheSound("../sounds/suit/CloakMode.wav") // Cloak Mode 

util.PrecacheSound("../sounds/suit/SpeedMode.wav") // Speed mode 
util.PrecacheSound("../sounds/suit/speedmode.wav") // Jump + strenght mode 
util.PrecacheSound("../sounds/suit/strenghtmode.wav") // Strenght Mode 
util.PrecacheSound("../sounds/suit/underwater.wav") // 1

local Armorm = Sound("suit/armor.mp3")
local Armor = Sound("suit/ArmorMode.wav")
local Binoz = Sound("suit/binocularzoom.wav")
local Binozo = Sound("suit/binocularzoomout.wav")
local Bino = Sound("suit/binocular.wav")
local Cloakm = Sound("suit/CloakMode.wav")
local speedmode = Sound("suit/SpeedMode.wav")
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
local cryx, cryy = EyeFinityScrW() / 2, ScrH() / 2 //Changing this makes the menu appear in a different place
local selected, oldselected = 0, 0 //Which slot is selected?

local snd_o, snd_c, snd_s, snd_h, snd_e = Sound( "cry_open.wav" ), Sound( "cry_close.wav" ), Sound( "cry_select.wav" ), Sound( "cry_hover.wav" ), Sound( "cry_error.wav" )

local crydist = {} //Distance to center for every slot
for i = 1, 5 do
    crydist[i] = 0
end


local enemytype = {}
enemytype["npc"] = {}
enemytype["npc"].material =  Material( "cryhud/gry_BadGuys.png" )
enemytype["npc"].color = Color(255,255,255,200)
enemytype["npcf"] = {}
enemytype["npcf"].material = Material( "cryhud/gry_Friendly.png" )
enemytype["npcf"].color = Color(255,255,255,200)
enemytype["player"] = {}
enemytype["player"].material = Material( "cryhud/gry_WhoAreU.png" )
enemytype["player"].color = Color(255,255,255,200)


 nilweps = {"weapon_physgun", "weapon_physcannon", "weapon_crowbar", "mod_tool"}



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

function CryOpenClose( ply, command, args ) // 1.0 update : Sounds are played by server // Message to me in 2014 : Played by the server ? WHY THE DUCK DID I DO THAT ?! 

	if ( command != "+crysishud" ) then
		if ( MouseInCircle( cryx, cryy ) ) then
			PlaySnd( snd_s )

	    if ( slots[selected] )  and (  slots[selected].name ) == "Armor"  then
          RunConsoleCommand( "Armor" )

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
		 RunConsoleCommand( "ArmorFUUUUU" )
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
		//ZoomScaleform()
	end
end

hook.Add( "KeyPress", "BinocularZoomIn", BinocularZoomIn )

local function BinocularZoomOut( player, key )
	if ( player:GetCanZoom() and key == IN_ZOOM ) then
		surface.PlaySound( "interface_suit/binocularzoomout.wav" )
		LocalPlayer().ZSing = false ; 
		//DeZoomScaleform()
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

function hudbase() // WARNING : No-one i know understand my maths
				// Feel free to send me a "readable" version of that if you wants :V

local alpha_ch = { 200,255 }
    	if shaking == true then
    		alpha_ch[1] = math.tan(RealTime() * 100) * 20
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
	surface.DrawTexturedRect(EyeFinityScrW() - (EyeFinityScrW()/4.06)+ GryModXDistance:GetInt() + GryModXDistance2:GetInt() , ScrH()-(EyeFinityScrW()/5.19), ((EyeFinityScrW())/4.26) , ((EyeFinityScrW())/4.26))

	
	surface.SetTexture( compass )
	surface.SetDrawColor(Color(220,235,220,alpha_ch[1]))
	surface.DrawTexturedRect(EyeFinityScrW()*(10/1920) - GryModXDistance:GetInt() + GryModXDistance2:GetInt()  ,   	ScrH()- (EyeFinityScrW()/7.111), (EyeFinityScrW()*(290/1920)), (EyeFinityScrW()*(290/1920)))
	
	
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
	surface.DrawRect( EyeFinityScrW()*(64/1920) - GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-EyeFinityScrW()*(135/1920)+ (17-(Gry_Danger0-17)), EyeFinityScrW()*(13/1920), EyeFinityScrW()*(Gry_Danger0/1920) ) 
	
		surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( EyeFinityScrW()*(64/1920) - GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-EyeFinityScrW()*(166/1920)+ (22-(Gry_Danger1-22)), EyeFinityScrW()*(13/1920), EyeFinityScrW()*(Gry_Danger1/1920) )
	
			surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( EyeFinityScrW()*(64/1920) - GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-EyeFinityScrW()*(185/1920)+ (19-(Gry_Danger2-19)), EyeFinityScrW()*(13/1920), EyeFinityScrW()*(Gry_Danger2/1920) )
	
				surface.SetDrawColor(Color(rcr,rcg,rcb,255))
	surface.DrawRect( EyeFinityScrW()*(64/1920)- GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-EyeFinityScrW()*(208/1920)+ (19-(Gry_Danger3-19)), EyeFinityScrW()*(13/1920), EyeFinityScrW()*(Gry_Danger3/1920) )

	surface.SetDrawColor(rcr,rcg,rcb, 255 )
	draw.NoTexture()
	surface.DrawPoly( {
	{ x = EyeFinityScrW()*(64/1920)- GryModXDistance:GetInt() + GryModXDistance2:GetInt(), y = ScrH()-EyeFinityScrW()*(101/1920) },
	{ x = EyeFinityScrW()*(77/1920)- GryModXDistance:GetInt() + GryModXDistance2:GetInt(), y = ScrH()-EyeFinityScrW()*(101/1920) },
	{ x = EyeFinityScrW()*(77/1920)- GryModXDistance:GetInt() + GryModXDistance2:GetInt(), y = ScrH()-EyeFinityScrW()*(92/1920) }

})
	
	
	
	//////////////////////////////////////////////////////////////
	////////////////////// END RADAR /////////////////////////////
	//////////////////////////////////////////////////////////////
	
	
	
	//////////////////////////////////////////////////////////////
	////////////////////// MAP START /////////////////////////////
	/////////////////////////HERE/////////////////////////////////
	//////////////////////////////////////////////////////////////
	
	
	
	
// TO DO : Fix that
	
	
	//////////////////////////////////////////////////////////////
	////////////////////// MAP ENDS  /////////////////////////////
	/////////////////////////HERE/////////////////////////////////
	//////////////////////////////////////////////////////////////
	

	
// If gmod break it any day , i cannot fix it cuz i changed the code for WWII screens (Adaptative variables


--[[ 
	surface.SetMaterial( Material("cryhud/bluebar.png" , "noclamp"))
	surface.SetDrawColor(Color(255,255,255,alpha_ch[1]))
	surface.DrawTexturedRectUV(1475, 936, 217, 33, 1 , 1, 2 ,2)
	

	
	
	surface.SetMaterial( Material("cryhud/greenbar.png" ))
	surface.SetDrawColor(Color(255,255,255,alpha_ch[1]))
	surface.DrawTexturedRect(1475, 969, 217, 33)
 ]]
 --[[ local c = LocalPlayer():Health() * ((EyeFinityScrW()/8.97)/100)
local ca = ( LocalPlayer():Health()- (c-(LocalPlayer():Health() * 2.14)))
local ololol = ((EyeFinityScrW()/8.97) - c) / 2 
local a = EyeFinityScrW() - (EyeFinityScrW()/5.69)  + ololol
local b = ScrH() - (94 * (90 + 10 * c))
-- local w = 100 - (0.1 * (-1 * c))

local w = -1 * ( (100 - LocalPlayer():Health()) / 30)


	surface.SetTexture( hlt ) // HEALTH BAR
	surface.SetDrawColor(Color(100,164,27,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( a + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH() - (EyeFinityScrW()/20) - w  , c,    (EyeFinityScrW()/87.272727), -2.98  ) 
		
		
	-- Now armor
		

local ca = LocalPlayer():GetNWInt("GryEnergy") * ((EyeFinityScrW()/8.97)/100)
local caa = ( LocalPlayer():GetNWInt("GryEnergy")- (c-(LocalPlayer():GetNWInt("GryEnergy") * 2.14)))
local ololola = ((EyeFinityScrW()/8.97) - ca) / 2
local aa = EyeFinityScrW() - (EyeFinityScrW()/5.69)  + ololola
local ba = ScrH() - (94 * (90 + 10 * ca))
-- local w = 100 - (0.1 * (-1 * c))
local wa = -1 * ( (100 - LocalPlayer():GetNWInt("GryEnergy")) / 30)
	surface.SetTexture( enr ) // energy BAR
	surface.SetDrawColor(Color(4,133,211,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( aa + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH() - (EyeFinityScrW()/15.1) - wa  , ca,     (EyeFinityScrW()/87.272727) , -2.98  )  

	 ]]
	 
	 
	 //// BRRRRAAAAAAAAAAAAIIIIIIINNNNNNNNNNNN FFUUUUUUUUUCCCCCCKKKKKK
// My brain literaly exploded, REALLY, i mean i'm resious, i can't understand my code anymore, all this fucking map.Simple, which dynamicaly change the range of a variable, and all the other shit, for WW2 monitor, multiple formats, scale, rezs...
	surface.SetTexture( hlt ) // HEALTH BAR
	surface.SetDrawColor(Color(200,164,27,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( (EyeFinityScrW()-EyeFinityScrW()*(362/1920)) - math.MapSimple(LocalPlayer():Health()-20,80, EyeFinityScrW()*(167/1920))/2 + EyeFinityScrW()*(167/1920)/2 + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()- EyeFinityScrW()*(95/1920)- (-1*(200-LocalPlayer():Health()))/120 , math.MapSimple(LocalPlayer():Health()-20,80, EyeFinityScrW()*(167/1920)), (EyeFinityScrW()/84), -3.5  ) 
	
	 
	surface.SetTexture( enr ) // ENERGY THIS TIME
	surface.SetDrawColor(Color(4,133,211,alpha_ch[1])) 
	surface.DrawTexturedRectRotated( (EyeFinityScrW()-EyeFinityScrW()*(362/1920)) - math.MapSimple(LocalPlayer():GetNWInt("GryEnergy")-20,80,EyeFinityScrW()*(167/1920))/2 + EyeFinityScrW()*(167/1920)/2 +  GryModXDistance:GetInt() + GryModXDistance2:GetInt() ,
	ScrH()- EyeFinityScrW()*(130/1920)- (-1*(200-LocalPlayer():GetNWInt("GryEnergy")))/38 , math.MapSimple(LocalPlayer():GetNWInt("GryEnergy")-20,80, EyeFinityScrW()*(167/1920)), (EyeFinityScrW()/84), -3.5  ) 
	 
	 
		surface.SetDrawColor(Color(4,133,211,alpha_ch[1])) 
		draw.BoxRotated(EyeFinityScrW()-(EyeFinityScrW()*(269/1920))+   ((EyeFinityScrW()*(40/1920))-(math.MapSimple(math.Min(LocalPlayer():GetNWInt("GryEnergy"),20 ), 20, (EyeFinityScrW()*(40/1920)))))+  GryModXDistance:GetInt() + GryModXDistance2:GetInt(),
		ScrH()-(EyeFinityScrW()*(133/1920)), // Small bar energy
		math.MapSimple(math.Min(LocalPlayer():GetNWInt("GryEnergy"),20 ), 20, (EyeFinityScrW()*(40/1920))),
		(EyeFinityScrW()/84), Color(4,133,211,alpha_ch[1]), 3.5)
	 
	 
	 
	 	surface.SetDrawColor(Color(200,164,2,alpha_ch[1])) 
	 	 draw.BoxRotated(EyeFinityScrW()-(EyeFinityScrW()*(269/1920))+   ((EyeFinityScrW()*(40/1920))-(math.MapSimple(math.Min(LocalPlayer():Health(),20 ), 20, (EyeFinityScrW()*(40/1920)))))  + GryModXDistance:GetInt() + GryModXDistance2:GetInt(),
	 ScrH()-(EyeFinityScrW()*(100/1920)), // Small bar health
	math.MapSimple(math.Min(LocalPlayer():Health(),20 ), 20, (EyeFinityScrW()*(40/1920))),
	 (EyeFinityScrW()/84), Color(200,164,2,alpha_ch[1]), 3.5)

draw.TextRotated( LocalPlayer():GetAmmoCount("grenade") , "CrysisInfos",EyeFinityScrW() - (EyeFinityScrW()/9) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/11),  Color(190, 195, 190,alpha_ch[2]), 1) // Fixed in v2.3
draw.TextRotated( LocalPlayer():Health() , "CrysisInfos",EyeFinityScrW() - (EyeFinityScrW()/10) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/22),  Color(190, 195, 190,alpha_ch[2]), 1) // Fixed in v2.3
draw.TextRotated( math.Round(LocalPlayer():GetNWInt("GryEnergy")) , "CrysisInfos",EyeFinityScrW() - (EyeFinityScrW()/10) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/16),  Color(190, 195, 190,alpha_ch[2]), 1) // Fixed in v2.3




local modeposw = EyeFinityScrW() - (EyeFinityScrW()/13.1)
local modeposh = ScrH() - (EyeFinityScrW()/15.5)
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
	surface.DrawTexturedRect(modeposw + GryModXDistance:GetInt() + GryModXDistance2:GetInt() , modeposh ,EyeFinityScrW()*(100/1920),EyeFinityScrW()*(100/1920) )
	
	
	
	
		if LocalPlayer():GetActiveWeapon():IsValid() then // Lets get ammo MOTHERFUCKER
	if table.HasValue(nilweps, LocalPlayer():GetActiveWeapon():GetClass()) then 
	
		    draw.TextRotated("∞", "CrysisInfos",EyeFinityScrW() - (EyeFinityScrW()/8) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3)
	
	return end

		local extra = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetPrimaryAmmoType())
        local ammonum = LocalPlayer():GetActiveWeapon():Clip1()
		local grenum = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetSecondaryAmmoType())
		if (ammonum == -1) then  // Because the ammo is  -1 with grenades
	    	draw.TextRotated( extra .. "  ll  " .. grenum , "CrysisInfos", EyeFinityScrW() - (EyeFinityScrW()/7.5) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3) else
		    draw.TextRotated(ammonum .. " l " .. extra .. "  ll  " .. grenum , "CrysisInfos",EyeFinityScrW() - (EyeFinityScrW()/7.5) + GryModXDistance:GetInt() + GryModXDistance2:GetInt(), ScrH()-(EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3)
	end end


end
 hook.Add( "HUDPaint", "HUDBASECRY", hudbase ) 
local function Shake( data )
 	if data:ReadEntity() == LocalPlayer() then
 		shaking = data:ReadBool()
	end
end
usermessage.Hook( "shake_view", Shake );
  
  function compass_direction() // LONG , LONG.....   lik my dik lel

	if (LocalPlayer():EyeAngles().y * 3.32)>  (EyeFinityScrW()*(0.0104166666666667) - ScrW()*(115/1920)) and(LocalPlayer():EyeAngles().y * 3.32)< (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*((75/1920))) then 
	draw.SimpleText( 'N', 'ScoreboardText', EyeFinityScrW()*(0.0104166666666667) - GryModXDistance:GetInt() + GryModXDistance2:GetInt() + (LocalPlayer():EyeAngles().y * 3.32)+ EyeFinityScrW()*(134/1920), ScrH() - EyeFinityScrW()*(218/1920) -((LocalPlayer():EyeAngles().y * 3.32)/15)+EyeFinityScrW()*(-5/1920))  end
	
	if (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) < (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then 
	draw.SimpleText(  'NE', 'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  + (( LocalPlayer():EyeAngles().y + 45 ) * 3.32) + EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920) -((( LocalPlayer():EyeAngles().y + 45 ) * 3.32)/15)+EyeFinityScrW()*(-5/1920)))) end
	
	if (( LocalPlayer():EyeAngles().y + 90 ) * 3.32) >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and(( LocalPlayer():EyeAngles().y + 90 ) * 3.32)< (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then 
	draw.SimpleText(  'E', 'ScoreboardText',EyeFinityScrW()*(0.0104166666666667) - GryModXDistance:GetInt() + GryModXDistance2:GetInt()  +(( LocalPlayer():EyeAngles().y + 90 ) * 3.32)+ EyeFinityScrW()*(134/1920), (( ScrH() -EyeFinityScrW()*(218/1920) -(( LocalPlayer():EyeAngles().y + 90 )* 3.32)/15)+EyeFinityScrW()*(-5/1920))) end
	
	if (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) < (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then
	draw.SimpleText(  'SE', 'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  + (( LocalPlayer():EyeAngles().y + 135 ) * 3.32) + EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920) -((( LocalPlayer():EyeAngles().y + 135 ) * 3.32)/15)+EyeFinityScrW()*(-5/1920)))) end
	
	if math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 5 >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 5 < (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(99/1920)) then 
	draw.SimpleText(  'S', 'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  + math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 5 + EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920) -((math.max( math.NormalizeAngle( LocalPlayer():EyeAngles().y + 180 ), math.NormalizeAngle( LocalPlayer():EyeAngles().y - 180 ) ) * 3.32)/15)+EyeFinityScrW()*(-5/1920)))) end
	
	if(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)>  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)< (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then
	draw.SimpleText( 'SW',  'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  +(( LocalPlayer():EyeAngles().y - 135 ) * 3.32)+ EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920)-((( LocalPlayer():EyeAngles().y - 135 ) * 3.32)/15)+EyeFinityScrW()*(-5/1920)))) end
	
	if (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) < (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then
	draw.SimpleText(  'W', 'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  + (( LocalPlayer():EyeAngles().y - 90 ) * 3.32) + EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920) -((( LocalPlayer():EyeAngles().y - 90 ) * 3.32)/15)+EyeFinityScrW()*(-5/1920))))  end 
	
	if (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) >  (EyeFinityScrW()*(0.0104166666666667) - EyeFinityScrW()*(115/1920)) and (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) < (EyeFinityScrW()*(0.0104166666666667) + EyeFinityScrW()*(75/1920)) then
	draw.SimpleText( 'NW',  'ScoreboardText', EyeFinityScrW()*(0.0104166666666667)- GryModXDistance:GetInt() + GryModXDistance2:GetInt()  + (( LocalPlayer():EyeAngles().y - 45 ) * 3.32) + EyeFinityScrW()*(134/1920), (( ScrH() - EyeFinityScrW()*(218/1920) -((( LocalPlayer():EyeAngles().y - 45 ) * 3.32)/15)+EyeFinityScrW()*(-5/1920)))) end
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

 net.Receive("gry_jump", function()
	surface.PlaySound( "suit/strenghtjump.wav" )
end)

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
				t.Entity = NULL
			end;
		end
	end
return t;
end

net.Receive("gry_spawn", function()	// Wow much swag
	

if gamemode.Get("sandbox") and jesus != 4646434346 then
		GAMEMODE:AddNotify("To open GryMod menu, bind a key to +crysishud ", NOTIFY_GENERIC, 5);
		GAMEMODE:AddNotify("Check the console for more informations ", NOTIFY_GENERIC, 4.2);
		jesus = 4646434346 // MAGIC
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
function RadialThinklel() // Alternative to detect the movement of the mouse , here we are detecting the position and not the movment , its a way to prevent 'out of range so i can't select a mode'
if !GRYOPEN then return end
	if math.Dist( gui.MouseX(), gui.MouseY(), EyeFinityScrW()/2, ScrH()/2  ) > 150 then

	if gui.MouseX() > ((EyeFinityScrW()/2) + MOUSE_CHECK_DIST) then // 
			posx = (gui.MouseX()-(gui.MouseX()-((EyeFinityScrW()/2) + MOUSE_CHECK_DIST)))		
		elseif gui.MouseX() < ((EyeFinityScrW()/2) - MOUSE_CHECK_DIST) then
			posx = (gui.MouseX()-(gui.MouseX()-((EyeFinityScrW()/2) - MOUSE_CHECK_DIST)))
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