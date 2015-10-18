local DrawMotionBlur = DrawMotionBlur; -- About 20% performance boost, for all the following vars
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


--Warning : The second part of the code (the non-quick-menu-part) is 60% brain fuck because of all the fucking retards with their WW2 Monitor which only support 800x600
--Yeah, fuck you, the guys with shitty monitors.
local color_white = Color(255,255,255,255)
local GryModXDistance = CreateClientConVar( "gry_xadd", "0", false, false )
local GryModXDistance2 = CreateClientConVar( "gry_xdist", "0", false, false )
local GryModXDistance_int = GryModXDistance:GetInt()
local GryModXDistance2_int = GryModXDistance2:GetInt()
local EyeFinity = CreateClientConVar( "cl_Eyefinity", "0", false, false )
local Shaking = false -- shek ur ass lel -- better make it local next time
local GRYOPEN = false
local meta = FindMetaTable("Player")

cvars.AddChangeCallback( "gry_xadd", function( convar_name, value_old, value_new )
	GryModXDistance_int = value_new
	end )

cvars.AddChangeCallback( "gry_xdist", function( convar_name, value_old, value_new )
	GryModXDistance2_int = value_new
	end )


local gry_icons = { Material( "gryarmor.png" ), Material( "gryspeed.png" ), Material( "grystrenght.png" ), Material( "grycloak.png"), Material( "grydrop.png")}


local tempscrw = ScrW()
local tempscrh = ScrH()

local base = surface.GetTextureID( "cryhud/base" )
local compass = surface.GetTextureID( "cryhud/compass" )

function meta:CanGryMod() 
	return true -- return meta:Alive() ????
end


-- You can change it , for others admins mods , but you'll have to change it in example : 

--[[  
function meta:CanGryMod() 
	if LocalPlayer():IsAdmin() or LocalPlayer():IsVip() then 
		return true 
	else 
		return false 
	end
end
]]

function GryMod.EyeFinityScrW()
	if tempscrw/tempscrh == 16/3 and EyeFinity:GetInt() > 0 then
		return tempscrw/3
	else
		return tempscrw
	end
end

local color_1 = Color(255,255,255,200)

//072 215
//273 227
//292 209
//061 194
//060 204


function draw.TextRotated( text,font, x, y, color, ang ) -- Just drawing lib, used one time or less, not really used
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


function draw.BoxRotated(x, y, scalex, scaley, color, ang ) 
	render.PushFilterMag( TEXFILTER.ANISOTROPIC )
	render.PushFilterMin( TEXFILTER.ANISOTROPIC )
	local rad = -math.rad( ang )
	local halvedPi = math.pi / 2
	local m = Matrix()
	m:SetAngles( Angle( 0, ang, 0 ) )
	m:SetTranslation( Vector( x, y, 0 ) )
	cam.PushModelMatrix( m )
	surface.SetDrawColor(color)
	surface.DrawRect(0,0, scalex, scaley)
	cam.PopModelMatrix()
	render.PopFilterMag()
	render.PopFilterMin()
end


local grymodesuit = gry_icons[1] -- Init mode, you better not reload this files, else there will be a de-sync
GryMod.Cloaked = false

net.Receive( "cloak_start", function( length, client ) -- First network optimizations are here 
	grymodesuit = gry_icons[4]
	GryMod.Cloaked = true
	LocalPlayer():GetViewModel():SetMaterial("cloak/organic")
	LocalPlayer():GetHands():SetMaterial("cloak/organic") -- ask someone to fix that
	PlaySnd(Sound("suit/cloak.mp3"))
	end)

net.Receive("gry_jump", function() // hotfix
	surface.PlaySound( "suit/strenghtjump.wav" )
	end)

net.Receive("cloak_stop", function()
	LocalPlayer():GetViewModel():SetMaterial("")
	LocalPlayer():GetHands():SetMaterial("")
end)


net.Receive( "armor_start", function( length, client )
	grymodesuit = gry_icons[1]
	GryMod.Cloaked = false
	PlaySnd(Sound("suit/armor.mp3"))
	end)

net.Receive( "speed_start", function( length, client )
	grymodesuit = gry_icons[2]
	GryMod.Cloaked = false
	PlaySnd(Sound("suit/speed.mp3"))
	end)

net.Receive( "strenght_start", function( length, client )
	grymodesuit = gry_icons[3]
	GryMod.Cloaked = false
	PlaySnd(Sound("suit/strength.mp3"))
	end)


 -- Originals sounds
util.PrecacheSound("suit/speed.mp3") --I don't really know if it's changing something or not, i don't really care anyway
util.PrecacheSound("suit/strength.mp3")
util.PrecacheSound("suit/cloak.mp3")
util.PrecacheSound("suit/armor.mp3")
util.PrecacheSound("suit/armor.mp3")
util.PrecacheSound("suit/ArmorMode.wav") -- Armor mode 
util.PrecacheSound("suit/binocularzoom.wav") -- Binocular zoom 
util.PrecacheSound("suit/binocularzoomout.wav") -- Zoom out 
util.PrecacheSound("suit/binocular.wav") -- Binocular soond (When using the binocular) 
util.PrecacheSound("suit/CloakMode.wav") -- Cloak Mode 
util.PrecacheSound("suit/SpeedMode.wav") -- Speed mode 
util.PrecacheSound("suit/speedmode.wav") -- Jump + strenght mode 
util.PrecacheSound("suit/strenghtmode.wav") -- Strenght Mode 
util.PrecacheSound("suit/underwater.wav") -- 1

local Armorm = Sound("suit/armor.mp3")
local Armor = Sound("suit/ArmorMode.wav") -- i know, i know but's it's local so it's okay, right ?
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
local global_mul, global_mul_goal = 0, 0 --The global multiplier, if this is 0 the menu is hidden, 1 and it's fully visible, between 0 and 1 for transition
local cryx, cryy = GryMod.EyeFinityScrW() / 2, tempscrh / 2 --Changing this makes the menu appear in a different place
local selected, oldselected = 0, 0 --Which slot is selected?

local snd_o, snd_c, snd_s, snd_h, snd_e = Sound( "cry_open.wav" ), Sound( "cry_close.wav" ), Sound( "cry_select.wav" ), Sound( "cry_hover.wav" ), Sound( "cry_error.wav" )

local crydist = {} --Distance to center for every slot
for i = 1, 5 do
	crydist[i] = 0
end

local nilweps = {"weapon_physgun", "weapon_physcannon", "weapon_crowbar", "mod_tool"} -- Weapons with *infinite* ammo

local armormode = {}
armormode["Armor"] = {}
armormode["Armor"].material =  gry_icons[1]
armormode["Armor"].name = "Armor"
armormode["Speed"] = {}
armormode["Speed"].material = gry_icons[2]
armormode["Speed"].name = "Speed"
armormode["Strenght"] = {}
armormode["Strenght"].material = gry_icons[3]
armormode["Strenght"].name = "Strenght"
armormode["Cloak"] = {}
armormode["Cloak"].material = gry_icons[4]
armormode["Cloak"].name = "Cloak"
armormode["Drop"] = {}
armormode["Drop"].material = gry_icons[5]
armormode["Drop"].name = "Drop"

local slots = {} --Standard slots, change these at will
slots[1] = armormode["Cloak"]
slots[2] = armormode["Strenght"]
slots[3] = armormode["Speed"]
slots[4] = armormode["Armor"]
slots[5] = armormode["Drop"]

function GryMod.MouseInCircle( x, y ) --Checks if the mouse is in the circle
	local centerdist = math.Dist( gui.MouseX(), gui.MouseY(), x, y )
	return ( centerdist > 32 and centerdist < 200 )
end

function GryMod.CRYHUD() --Good luck figuring all this shit out

	if ( global_mul_goal != global_mul ) then
		global_mul = global_mul + ( global_mul_goal - global_mul ) * math.Clamp( FrameTimeExt() * 10, 0, 1 ) --I love mah math
	end

	local numb = 1
	local cryadd = 360/5
	local cursorang = math.fmod( math.atan2( gui.MouseY() - cryy, gui.MouseX() - cryx ), math.pi * 2 ) --This angle shit makes my head implode
	local cursorangd = math.deg( cursorang ) + 180

	if ( cursorangd >= 0 and cursorangd < cryadd ) then selected = 4
	elseif ( cursorangd >= cryadd and cursorangd < cryadd * 2 ) then selected = 3
	elseif ( cursorangd >= cryadd * 2 and cursorangd < cryadd * 3 ) then selected = 2
	elseif ( cursorangd >= cryadd * 3 and cursorangd < cryadd * 4 ) then selected = 1
	elseif ( cursorangd >= cryadd * 4 and cursorangd < cryadd * 5 ) then selected = 5
	end 

	if ( global_mul == 0 ) then return end --Don't run if the menu ain't visible
	if ( !GryMod.MouseInCircle( cryx, cryy ) ) then selected = 0 end -- Aka if mouse is not in da circle , dont do anything

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
		crygraya1 = 240
		crygraya2 = 27
		crygraya3 = 27
	end

	if (selected == 5 and !IsValid(LocalPlayer():GetActiveWeapon())) then
		crygraya1 =  240
		crygraya2 = 27
		crygraya3 = 27
	end


	surface.SetTexture( crytx )

	if LocalPlayer():CanGryMod() then -- NORMAL
		crydistadd = 96
		crygray1 = 150
		crygray2 = 200
		crygray3 = 150
	end

	if !LocalPlayer():CanGryMod() then -- ROUGE
		crydistadd = 96
		crygray1 = 240
		crygray2 = 23
		crygray3 = 27
	end


	if ( numb == selected and LocalPlayer():CanGryMod()) then -- NORMAL
		crydistadd = crydistadd * 1.3
		crygray1 = 100
		crygray2 = 140
		crygray3 = 100
	end	

	if ( numb == selected and !LocalPlayer():CanGryMod()) then --   ROUGE
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
		surface.SetDrawColor( crygray1, crygray2, crygray3, global_mul * 200 ) -- Color Button, yes  its weired
		surface.DrawTexturedRectRotated( cryx + cryaddx, cryy + cryaddy, 100 * global_mul, 100 * global_mul, i - 180 )

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

function GryMod.EnableMenu( b )
	if ( ( b and global_mul_goal == 0 ) ) then PlaySnd( snd_o )
		GRYOPEN = true
	end
	gui.EnableScreenClicker( b )
	
	if ( b ) then 
		global_mul_goal = 1 else global_mul_goal = 0 end

		if not (b) then GRYOPEN = false end;
	end


function GryMod.CryOpenClose( ply, command, args ) -- 1.0 update : Sounds are played by server -- Message to me in 2014 : Played by the server ? WHY THE DUCK DID I DO THAT ?! 

	if ( command != "+crysishud" ) then
		if ( GryMod.MouseInCircle( cryx, cryy ) ) then
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
	GryMod.EnableMenu( command == "+crysishud" ) --Enable menu if it's +crysishud, disable otherwise
end

concommand.Add( "+crysishud", GryMod.CryOpenClose )
concommand.Add( "-crysishud", GryMod.CryOpenClose )



----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------
----------------------------------------------------------------------------


function GryMod.CloackAttack (ply,key)
	if key == IN_ATTACK and GryMod.Cloaked  then
		RunConsoleCommand( "Armor" )
		RunConsoleCommand( "ArmorFUUUUU" )
		surface.PlaySound( Armorm )
	end
end


function PlaySnd( snd )
	if ( soundconvar:GetBool() ) then surface.PlaySound( snd ) end
end

function FrameTimeExt()
	if ( smoothconvar:GetBool() ) then return FrameTime() else return 1 end
end

function GryMod.BinocularZoomIn( player, key )
	if ( player:GetCanZoom() and key == IN_ZOOM ) then
		surface.PlaySound( "interface_suit/binocularzoomin.wav" )
		LocalPlayer().ZSing = true ;
		--ZoomScaleform()
	end
end

function GryMod.BinocularZoomOut( player, key )
	if ( player:GetCanZoom() and key == IN_ZOOM ) then
		surface.PlaySound( "interface_suit/binocularzoomout.wav" )
		LocalPlayer().ZSing = false ; 
		--DeZoomScaleform()
	end
end

function SuitBreathUnderwater() -- Not made by me
	local UnderWater = Sound("suit/underwater.wav")

	if ( LocalPlayer():WaterLevel() >= 3 ) then -- A bit useless
		if ( !LocalPlayer().m_bIsUsingSuitOxygen ) then
			LocalPlayer().m_bIsUsingSuitOxygen = true
			surface.PlaySound( UnderWater )
		end
	else
		LocalPlayer().m_bIsUsingSuitOxygen = false
	end
end


function GryMod.mathradar()

	radarnpc = {}
	if IsValid(LocalPlayer()) then

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
		raderpers = math.Min(math.MapSimple(table.Count(radarnpc),20, 150), 150) -- For the color
		levelEnemies = math.Min(math.MapSimple(table.Count(radarnpc), 20, 100), 100) -- For the API/Level of the texture
		GryMod.rcr = 105+raderpers;
		GryMod.rcg = 235-raderpers*1.5;
		GryMod.rcb = 100-(raderpers/1.8);
		Gry_Danger0 = math.Min(math.MapSimple(table.Count(radarnpc)*5, 20, 17), 17)
		Gry_Danger1 = math.Min(math.MapSimple((table.Count(radarnpc)-4)*5, 20, 22), 22)
		Gry_Danger2 = math.Min(math.MapSimple((table.Count(radarnpc)-8)*5, 20, 19), 19)
		Gry_Danger3 = math.Min(math.MapSimple((table.Count(radarnpc)-12)*5, 20, 19), 19)
	end
	timer.Simple(0.1, GryMod.mathradar)
end

GryMod.mathradar()


local alpha_ch = { 200,255 }

function GryMod.hudbase() -- WARNING : No-one i know understand my maths
-- Feel free to send me a "readable" version of that if you wants :V


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


surface.SetTexture( base )
surface.SetDrawColor(Color(220,235,220,alpha_ch[1]))
surface.DrawTexturedRect(GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/4.06)+ GryModXDistance_int + GryModXDistance2_int , tempscrh-(GryMod.EyeFinityScrW()/5.19), ((GryMod.EyeFinityScrW())/4.26) , ((GryMod.EyeFinityScrW())/4.26))


surface.SetTexture( compass )
surface.SetDrawColor(Color(220,235,220,alpha_ch[1]))
surface.DrawTexturedRect(GryMod.EyeFinityScrW()*(10/1920) - GryModXDistance_int + GryModXDistance2_int  ,   	tempscrh- (GryMod.EyeFinityScrW()/7.111), (GryMod.EyeFinityScrW()*(290/1920)), (GryMod.EyeFinityScrW()*(290/1920)))


	------------------------------------------------/
	---------------- START RADAR --------------------
	------------------------------------------------/

	
	surface.SetDrawColor(Color(GryMod.rcr,GryMod.rcg,GryMod.rcb,255)) -- Dear maths, you made me cry this time
	surface.DrawRect( GryMod.EyeFinityScrW()*(64/1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh-GryMod.EyeFinityScrW()*(135/1920)+ (17-(Gry_Danger0-17)), GryMod.EyeFinityScrW()*(13/1920), GryMod.EyeFinityScrW()*(Gry_Danger0/1920) ) 
	
	surface.SetDrawColor(Color(GryMod.rcr,GryMod.rcg,GryMod.rcb,255))
	surface.DrawRect( GryMod.EyeFinityScrW()*(64/1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh-GryMod.EyeFinityScrW()*(166/1920)+ (22-(Gry_Danger1-22)), GryMod.EyeFinityScrW()*(13/1920), GryMod.EyeFinityScrW()*(Gry_Danger1/1920) )
	
	surface.SetDrawColor(Color(GryMod.rcr,GryMod.rcg,GryMod.rcb,255))
	surface.DrawRect( GryMod.EyeFinityScrW()*(64/1920) - GryModXDistance_int + GryModXDistance2_int, tempscrh-GryMod.EyeFinityScrW()*(185/1920)+ (19-(Gry_Danger2-19)), GryMod.EyeFinityScrW()*(13/1920), GryMod.EyeFinityScrW()*(Gry_Danger2/1920) )
	
	surface.SetDrawColor(Color(GryMod.rcr,GryMod.rcg,GryMod.rcb,255))
	surface.DrawRect( GryMod.EyeFinityScrW()*(64/1920)- GryModXDistance_int + GryModXDistance2_int, tempscrh-GryMod.EyeFinityScrW()*(208/1920)+ (19-(Gry_Danger3-19)), GryMod.EyeFinityScrW()*(13/1920), GryMod.EyeFinityScrW()*(Gry_Danger3/1920) )

	surface.SetDrawColor(GryMod.rcr,GryMod.rcg,GryMod.rcb, 255 )
	draw.NoTexture()
	surface.DrawPoly( {
		{ x = GryMod.EyeFinityScrW()*(64/1920)- GryModXDistance_int + GryModXDistance2_int, y = tempscrh-GryMod.EyeFinityScrW()*(101/1920) },
		{ x = GryMod.EyeFinityScrW()*(77/1920)- GryModXDistance_int + GryModXDistance2_int, y = tempscrh-GryMod.EyeFinityScrW()*(101/1920) },
		{ x = GryMod.EyeFinityScrW()*(77/1920)- GryModXDistance_int + GryModXDistance2_int, y = tempscrh-GryMod.EyeFinityScrW()*(91/1920) }

		})
	
	--------------------------------------------------------------
	---------------------- END RADAR -----------------------------
	--------------------------------------------------------------







	draw.TextRotated( LocalPlayer():GetAmmoCount("grenade") , "CrysisInfos",GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/9) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/11),  Color(190, 195, 190,alpha_ch[2]), 1) -- Fixed in v2.3
	draw.TextRotated( LocalPlayer():Health() , "CrysisInfos",GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/10) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/22),  Color(190, 195, 190,alpha_ch[2]), 1) -- Fixed in v2.3
	draw.TextRotated( math.Round(LocalPlayer():GetNWInt("GryEnergy")) , "CrysisInfos",GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/10) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/16),  Color(190, 195, 190,alpha_ch[2]), 1) -- Fixed in v2.3


	local modeposw = GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/13.1)
	local modeposh = tempscrh - (GryMod.EyeFinityScrW()/15.5)


	surface.SetMaterial( grymodesuit )
	surface.SetDrawColor( Color(150, 195, 150,alpha_ch[2] - 100))
	surface.DrawTexturedRect(modeposw + GryModXDistance_int + GryModXDistance2_int , modeposh ,GryMod.EyeFinityScrW()*(100/1920),GryMod.EyeFinityScrW()*(100/1920) )

	if LocalPlayer():GetActiveWeapon():IsValid() then -- Lets get ammo MOTHERFUCKER
		if table.HasValue(nilweps, LocalPlayer():GetActiveWeapon():GetClass()) then 
			draw.TextRotated("∞", "CrysisInfos",GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/8) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3)
			return end

			local extra = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetPrimaryAmmoType())
			local ammonum = LocalPlayer():GetActiveWeapon():Clip1()
			local grenum = LocalPlayer():GetAmmoCount(LocalPlayer():GetActiveWeapon():GetSecondaryAmmoType())
		if (ammonum == -1) then  -- Because the ammo is  -1 with grenades
			draw.TextRotated( extra .. "  ||  " .. grenum , "CrysisInfos", GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/7.5) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3) else
			draw.TextRotated(ammonum .. " | " .. extra .. "  ||  " .. grenum , "CrysisInfos",GryMod.EyeFinityScrW() - (GryMod.EyeFinityScrW()/7.5) + GryModXDistance_int + GryModXDistance2_int, tempscrh-(GryMod.EyeFinityScrW()/8.4),  Color(190, 195, 190,alpha_ch[2]), 3)
		end 
	end


end


local function Shake( data )
	if data:ReadEntity() == LocalPlayer() then
		shaking = data:ReadBool()
	end
end

usermessage.Hook( "shake_view", Shake );






function GryMod.Stencils1()
		local compassmask = { -- if we want to support eyefinity, we have to update the table each frames
		{ x = -1*GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()*(072/1920), y = ScrH()-GryMod.EyeFinityScrW()*(215/1920) },
		{ x = -1*GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()*(273/1920), y = ScrH()-GryMod.EyeFinityScrW()*(227/1920) },
		{ x = -1*GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()*(294/1920), y = ScrH()-GryMod.EyeFinityScrW()*(207/1920) },
		{ x = -1*GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()*(061/1920), y = ScrH()-GryMod.EyeFinityScrW()*(194/1920) },
		{ x = -1*GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()*(060/1920), y = ScrH()-GryMod.EyeFinityScrW()*(204/1920) }
	}




	local nbener 	= LocalPlayer():GetNWInt("GryEnergy")
	local nbhlt 	= LocalPlayer():Health()

	render.ClearStencil()
	render.SetStencilEnable( true )
	render.SetStencilWriteMask( 255 )
	render.SetStencilTestMask( 255 )
	render.SetStencilReferenceValue( 15 )

	render.SetStencilFailOperation( STENCILOPERATION_ZERO )
	render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
	render.SetStencilZFailOperation( STENCILOPERATION_KEEP )

	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
	surface.SetDrawColor( Color(255,255,255,255) ) 
	render.SetBlend(0)
	surface.DrawPoly( compassmask )
	render.SetBlend(1)

	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
	LocalPlayer_y = LocalPlayer():EyeAngles().y +6.256798
	
	draw.SimpleText( 'N', 'ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int + (LocalPlayer_y * 3.32)+ GryMod.EyeFinityScrW()*(134/1920), tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((LocalPlayer_y * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920),color_white)
	draw.SimpleText( 'NE','ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  + (( LocalPlayer_y + 45 ) * 3.32) + GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((( LocalPlayer_y + 45 ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	draw.SimpleText( 'E', 'ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  +(( LocalPlayer_y + 90 ) * 3.32)+ GryMod.EyeFinityScrW()*(134/1920), (( tempscrh -GryMod.EyeFinityScrW()*(218/1920) -(( LocalPlayer_y + 90 )* 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920)),color_white)
	draw.SimpleText( 'SE','ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  + (( LocalPlayer_y + 135 ) * 3.32) + GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((( LocalPlayer_y + 135 ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	draw.SimpleText( 'S', 'ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  +math.max( math.NormalizeAngle( LocalPlayer_y + 180 ), math.NormalizeAngle( LocalPlayer_y - 180 ) ) * 5 + GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((math.max( math.NormalizeAngle( LocalPlayer_y + 180 ), math.NormalizeAngle( LocalPlayer_y - 180 ) ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	draw.SimpleText( 'SW','ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  +(( LocalPlayer_y - 135 ) * 3.32)+ GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920)-((( LocalPlayer_y - 135 ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	draw.SimpleText( 'W', 'ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  + (( LocalPlayer_y - 90 ) * 3.32) + GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((( LocalPlayer_y - 90 ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	draw.SimpleText( 'NW','ScoreboardText',  GryMod.EyeFinityScrW()*(20/1920)- GryModXDistance_int + GryModXDistance2_int  + (( LocalPlayer_y - 45 ) * 3.32) + GryMod.EyeFinityScrW()*(134/1920), (( tempscrh - GryMod.EyeFinityScrW()*(218/1920) -((( LocalPlayer_y - 45 ) * 3.32)/15)+GryMod.EyeFinityScrW()*(-5/1920))),color_white)
	render.SetStencilEnable( false )
end

function GryMod.Stencils2()

	local nbener 	= LocalPlayer():GetNWInt("GryEnergy")
	local energybarpoly1 = { -- if we want to support eyefinity, we have to update the table each frames
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920), y = ScrH()-GryMod.EyeFinityScrW()*(136/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(436/1920), y = ScrH()-GryMod.EyeFinityScrW()*(144/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(277/1920), y = ScrH()-GryMod.EyeFinityScrW()*(136/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(277/1920), y = ScrH()-GryMod.EyeFinityScrW()*(113.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920), y = ScrH()-GryMod.EyeFinityScrW()*(122/1920) }
	}
		render.ClearStencil()

		------------------------------------------------------------------------------------------------------------------------------------------------------------

		render.SetStencilEnable( true )
		render.SetStencilWriteMask( 255 )
		render.SetStencilTestMask( 255 )
		render.SetStencilReferenceValue( 15 )

		render.SetStencilFailOperation( STENCILOPERATION_ZERO )
		render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
		render.SetStencilZFailOperation( STENCILOPERATION_KEEP )

		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
		surface.SetDrawColor( Color(255,255,255,255) )
		render.SetBlend(0)
		surface.DrawPoly( energybarpoly1 )
		render.SetBlend(1)

		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
		

		surface.SetDrawColor(Color(20,150,230,alpha_ch[1]))
		local hltoffset = math.Remap(nbener, 0, 100,0, GryMod.EyeFinityScrW()*(219/1920))
		surface.DrawRect( 
			GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920)+(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
			ScrH()-GryMod.EyeFinityScrW()*(144/1920) ,
			GryMod.EyeFinityScrW()*(219/1920)-(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
			GryMod.EyeFinityScrW()*(37/1920))

		render.SetStencilEnable( false )
end

function GryMod.Stencils3()

	local nbhlt 	= LocalPlayer():Health()

		local healthbarpoly1 = { -- if we want to support eyefinity, we have to update the table each frames
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920), y = ScrH()-GryMod.EyeFinityScrW()*(112/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(277/1920), y = ScrH()-GryMod.EyeFinityScrW()*(102.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(277/1920), y = ScrH()-GryMod.EyeFinityScrW()*(81.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(436/1920), y = ScrH()-GryMod.EyeFinityScrW()*(91/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920), y = ScrH()-GryMod.EyeFinityScrW()*(97/1920) }
	}

		render.ClearStencil()
		render.SetStencilEnable( true )
		render.SetStencilWriteMask( 255 )
		render.SetStencilTestMask( 255 )
		render.SetStencilReferenceValue( 15 )

		render.SetStencilFailOperation( STENCILOPERATION_ZERO )
		render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
		render.SetStencilZFailOperation( STENCILOPERATION_KEEP )

		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
		surface.SetDrawColor( Color(255,255,255,255) ) 
		render.SetBlend(0)
		surface.DrawPoly( healthbarpoly1 )
		render.SetBlend(1)
		render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
		

		surface.SetDrawColor(Color(116,194,27,alpha_ch[1]))
		local hltoffset = math.Remap(nbhlt, 0, 100,0, GryMod.EyeFinityScrW()*(219/1920))
		surface.DrawRect( 
			GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920)+(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
			ScrH()-GryMod.EyeFinityScrW()*(113/1920) ,
			GryMod.EyeFinityScrW()*(219/1920)-(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
			GryMod.EyeFinityScrW()*(37/1920))

		render.SetStencilEnable( false )
end
---------------------------------------------------------------------------------------------------------------------------------------------------------

function GryMod.Stencils4()

		//270 103
		//228 100
		//228 78
		//270 80

		//+32 for ener

	local nbhlt 	= LocalPlayer():Health()
		local healthbarpoly2 = { -- cut the bars
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(270/1920), y = ScrH()-GryMod.EyeFinityScrW()*(102/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(228/1920), y = ScrH()-GryMod.EyeFinityScrW()*(99.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(228/1920), y = ScrH()-GryMod.EyeFinityScrW()*(78.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(270/1920), y = ScrH()-GryMod.EyeFinityScrW()*(81/1920) }
	}



	render.ClearStencil()
	render.SetStencilEnable( true )
	render.SetStencilWriteMask( 255 )
	render.SetStencilTestMask( 255 )
	render.SetStencilReferenceValue( 15 )

	render.SetStencilFailOperation( STENCILOPERATION_ZERO )
	render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
	render.SetStencilZFailOperation( STENCILOPERATION_KEEP )

	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
	surface.SetDrawColor( Color(255,255,255,255) ) 

	render.SetBlend(0)
	surface.DrawPoly( healthbarpoly2 )
	render.SetBlend(1)

	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
	

	if nbhlt > 20 then 
		surface.SetDrawColor(Color(116,194,27,alpha_ch[1]))
	else
		surface.SetDrawColor(Color(240,23,27,alpha_ch[1]))
	end
	local hltoffset = math.Remap(nbhlt, 0, 100,0, GryMod.EyeFinityScrW()*(219/1920))
	surface.DrawRect( 
		GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920)+(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
		ScrH()-GryMod.EyeFinityScrW()*(113/1920) ,
		GryMod.EyeFinityScrW()*(219/1920)-(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
		GryMod.EyeFinityScrW()*(37/1920))

	render.SetStencilEnable( false )
end
	------------------------------------------


function GryMod.Stencils5()

		local energybarpoly2 = { -- cut the bars
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(270/1920), y = ScrH()-GryMod.EyeFinityScrW()*(135.5/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(228/1920), y = ScrH()-GryMod.EyeFinityScrW()*(133/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(228/1920), y = ScrH()-GryMod.EyeFinityScrW()*(111/1920) },
		{ x = GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(270/1920), y = ScrH()-GryMod.EyeFinityScrW()*(113.5/1920) }
	}

	local nbener 	= LocalPlayer():GetNWInt("GryEnergy")


	render.ClearStencil()
	render.SetStencilEnable( true )
	render.SetStencilWriteMask( 1 )
	render.SetStencilTestMask( 1 )
	render.SetStencilReferenceValue( 1 )

	render.SetStencilFailOperation( STENCILOPERATION_ZERO )
	render.SetStencilPassOperation( STENCILOPERATION_REPLACE )
	render.SetStencilZFailOperation( STENCILOPERATION_KEEP )

	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_ALWAYS )
	surface.SetDrawColor( Color(255,255,255,255) ) 
	render.SetBlend(0)
	surface.DrawPoly( energybarpoly2 )
	render.SetBlend(1)
	render.SetStencilCompareFunction( STENCILCOMPARISONFUNCTION_EQUAL )
	

	if nbener >20 then 
		surface.SetDrawColor(Color(20,150,230,alpha_ch[1]))
	else
		surface.SetDrawColor(Color(240,23,27,alpha_ch[1]))
	end
	local hltoffset = math.Remap(nbener, 0, 100,0, GryMod.EyeFinityScrW()*(219/1920))
	surface.DrawRect( 
		GryModXDistance_int + GryModXDistance2_int + GryMod.EyeFinityScrW()-GryMod.EyeFinityScrW()*(446/1920)+(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
		ScrH()-GryMod.EyeFinityScrW()*(144/1920) ,
		GryMod.EyeFinityScrW()*(219/1920)-(GryMod.EyeFinityScrW()*(219/1920)-hltoffset),
		GryMod.EyeFinityScrW()*(37/1920))

	render.SetStencilEnable( false )
end









net.Receive("gry_spawn", function()	-- Wow much swag
	ScaleFormGFx_Proxy("http://extrem-team.com/init.html", 1000, 700, 5) -- Rip cheap monitors
	if gamemode.Get("sandbox") and jesus != 4646434346 then -- I know...
		GAMEMODE:AddNotify("To open GryMod menu, bind a key to +crysishud ", NOTIFY_GENERIC, 15);
		GAMEMODE:AddNotify("Check the console for more informations ", NOTIFY_GENERIC, 13);
		if not file.Exists("resource/fonts/Agency FB.ttf", "GAME") then 
			GAMEMODE:AddNotify("You don't have the required Font fix, check console to get the download link!", NOTIFY_GENERIC, 20);
		else
			GAMEMODE:AddNotify("Font fix installed ( ͡° ͜ʖ ͡°)", NOTIFY_GENERIC, 10);
		end
		jesus = 4646434346 -- MAGIC




		print[[



	MMMMMMMMMMM        MMMMMMMMMMMMMMMM,  MMMMMMMMMM  MM     MM:                  
	MMMMMMMMMMMMM    MMMMMMMMMMMMMMMMMMM  MMMMMMMMMM  MMMM MMMM:                  
	           MMM MMM      MM         MM             MMMMMMM M:                  
	MMMMMMMMM    MMM        MM    DMMMMM  MMMMMMMMMM  MM  N   M:                  
	           MMM MMM      MM     MM=                MM      M:                  
	7IIIIIIII8MM:   MMMM    MM      +MM7IIIIIIIIIIIIIIMM      M:                  
	MMMMMMMMMMM       MMM   MM        MMMMMMMMMMMMMMMMMM      M:                  
	                    MMM                                                       
	                     IMMM                                                     
	                       MMMMMMMMMMMMMMMMMMMMMMMMMZ    ,MMMMMMM MMMMM           
	                                               MMM    ,     MMM  MMM          
	                            MMM   ?MMMMMMM  MMM DMMM   MMM   MMM  ,MM         
	     ExtReM-Team.com        MMM   ?MMMMMN   MMM   MMM  MMM   MMM   MM         
	    By [ExtReM] Lapin       MMM   ?MM       MMMMMMM MMMMMM   MMM   MM         
	                            MMM   ?MMMMMMM  MMM      NMMMM   MMM   MM         
	                            MMN   ?MMMMMMMMOMMM        MMM   MMM   MM         




		///////////////////////////////////////
		////////////GryNet Systems/////////////
		////////////ExtReM-Team.com////////////
		////////ExtReM-Team.com/cmd.html///////
		///////////////////////////////////////
		/////                             /////
		/// Version : FINAL (More or less)  ///
		/// Edition : Official              ///
		/// Dev : [ExtReM] Lapin            ///
		/////////////HELP-FAQ//////////////////
		/// How to open the menu ? -> Bind a///
		/// key to +crysishud (guide on the ///
		/// workshop page)                  ///
		///          -------------          ///
		/// Wow such lags. -> That's not a  ///
		/// question and buy a new PC       ///
		///          -------------          ///
		/// I found a bug -> That's still   ///
		/// not a question, make an issue   ///
		/// ion github/tell me the bugs in  ///
		/// the comments m8                 ///
		///                                 ///
		//////////////FONT FIX/////////////////
		///  The font fix will really       ///
		///  improve how the hud looks, you ///
		///  can downloadit here :          ///
		///    https://goo.gl/n7u0zS        ///
		///                                 ///
		///   Then put it in :              ///
		///   garrysmod/resource/fonts/     ///
		///                                 ///
		/////////////THANKS////////////////////
		/// Carl Mcgee : Working on         ///
		/// GryEngine models/map            ///
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
end

end)


----------------FIX----------------


local MOUSE_CHECK_DIST = 95
local MOUSE_CUR_DIST = 0
function GryMod.RadialThinklel() -- Alternative to detect the movement of the mouse , here we are detecting the position and not the movment , its a way to prevent 'out of range so i can't select a mode'
	if !GRYOPEN then return end
	if math.Dist( gui.MouseX(), gui.MouseY(), GryMod.EyeFinityScrW()/2, tempscrh/2  ) > 150 then
		if gui.MouseX() > ((GryMod.EyeFinityScrW()/2) + MOUSE_CHECK_DIST) then -- 
			posx = (gui.MouseX()-(gui.MouseX()-((GryMod.EyeFinityScrW()/2) + MOUSE_CHECK_DIST)))		
		elseif gui.MouseX() < ((GryMod.EyeFinityScrW()/2) - MOUSE_CHECK_DIST) then
			posx = (gui.MouseX()-(gui.MouseX()-((GryMod.EyeFinityScrW()/2) - MOUSE_CHECK_DIST)))
			else posx = gui.MouseX()
			end


			if gui.MouseY() > ((tempscrh/2) + MOUSE_CHECK_DIST) then
				posy = (gui.MouseY()-(gui.MouseY()-((tempscrh/2) + MOUSE_CHECK_DIST)))		
			elseif gui.MouseY() < ((tempscrh/2) - MOUSE_CHECK_DIST) then
				posy = (gui.MouseY()-(gui.MouseY()-((tempscrh/2) - MOUSE_CHECK_DIST)))
				else posy = gui.MouseY()
				end
				gui.SetMousePos(posx, posy)
			end
		end


 local hidethings = { -- Yeah, i know its from original Gmod wiki , what do you think you think i will use something else ? Dont be dumb.
 ["CHudHealth"] = true,
 ["CHudBattery"] = true,
 ["CHudAmmo"] = true,
 ["CHudSecondaryAmmo"] = true
}
function HUDShouldDraw(name)
	if (hidethings[name]) then
		return false;
	end
end

--[[if(util.__TraceLine) then return end -- I know i'm a terrible person
util.__TraceLine = util.TraceLine;

function util.TraceLine(...) -- Aka, if i'm looking at you and you're cloaked, then i can't see your name, ikr this is dangerous to do that, i'll fix it later
	local t = util.__TraceLine(...);
	if(t and IsValid(t.Entity)) then
		if(t.Entity:IsPlayer()) then
			if t.Entity:GetMaterial() == "cloak/organic" then
				t.Entity = NULL
				end;
			end
		end
		return t;
end--]]

	hook.Add( "HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
	hook.Add( "HUDPaint", "GRYHUD", 				GryMod.CRYHUD )
	hook.Add( "KeyPress","AttackDetection", 		GryMod.CloackAttack )
	hook.Add( "KeyPress", "BinocularZoomIn", 		GryMod.BinocularZoomIn )
	hook.Add( "KeyRelease", "BinocularZoomOut",	 	GryMod.BinocularZoomOut )
	hook.Add( "Think", "SuitBreathUnderwater", 		GryMod.SuitBreathUnderwater )
	hook.Add( "HUDPaint", "HUDBASECRY", 			GryMod.hudbase ) 
	hook.Add( "Think", "HueHue fix normal shit", 	GryMod.RadialThinklel)

	hook.Add( "HUDPaint", "GryMod stencils1", 		GryMod.Stencils1)
	hook.Add( "HUDPaint", "GryMod stencils2", 		GryMod.Stencils2)
	hook.Add( "HUDPaint", "GryMod stencils3", 		GryMod.Stencils3)
	hook.Add( "HUDPaint", "GryMod stencils4", 		GryMod.Stencils4)
	hook.Add( "HUDPaint", "GryMod stencils5", 		GryMod.Stencils5)
