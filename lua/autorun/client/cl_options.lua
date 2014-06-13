

concommand.Add("GryCredits", function()
local GryPopup = vgui.Create( "DFrame" )
GryPopup:SetSize( 1366+4, 768+27 )
GryPopup:Center()
GryPopup:SetBackgroundBlur( true )
GryPopup:MakePopup()
GryPopup:SetPaintShadow(true)
 
local CryDrawFrame = vgui.Create( "HTML", GryPopup )
CryDrawFrame:SetPos( 2, 25 )
CryDrawFrame:SetSize( 1366, 768 )
CryDrawFrame:OpenURL( "http://extrem-team.com/Credits.html" )
 

end)


function GryMod.GryOptionschute (Panel)
Panel:AddControl("Label", {Text = "GryMod Config"})

	enabled1 = vgui.Create( "DButton", Panel )
	enabled1:SetSize( 250, 25 )
	enabled1:SetText( "Enable Base HUD" )
	
	enabled1.DoClick = function()
		 hook.Add( "HUDPaint", "HUDBASECRY", hudbase )
		 hook.Add( "HUDPaint", "ololol", compass_direction) 
		 hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
	end
	
	
	disabled1 = vgui.Create( "DButton", Panel )
	disabled1:SetSize( 250, 25 )
	disabled1:SetText( "Disable Base HUD" )
	
	disabled1.DoClick = function()
			hook.Remove( "HUDPaint", "HUDBASECRY")
			hook.Remove( "HUDPaint", "ololol") 
			hook.Remove("HUDShouldDraw", "How to: HUD Example HUD hider")
	end
 
 	
	togglehealth = vgui.Create( "DButton", Panel )
	//togglehealth:SetPos( 25, 220 )
	togglehealth:SetSize( 250, 20 )
	togglehealth:SetText( "[ADMIN] Toggle Health Regen" )
	
	togglehealth.DoClick = function()
		RunConsoleCommand( "gry_Health" )
	end
	
	
	togglearmor = vgui.Create( "DButton", Panel )
	//togglearmor:SetPos( 25, 280 )
	togglearmor:SetSize( 250, 20 )
	togglearmor:SetText( "[ADMIN] Toggle Infinite Armor" )
	
	togglearmor.DoClick = function()
		RunConsoleCommand( "gry_Armor" )
	end
	
	
 
	local NumSliderThingy = vgui.Create( "DNumSlider", Panel )
NumSliderThingy:SetPos( 25,150)
NumSliderThingy:SetSize( 250, 10 ) -- Keep the second number at 100
NumSliderThingy:SetText( "Mirror Distance" )
NumSliderThingy:SetMin( -5000 ) -- Minimum number of the slider
NumSliderThingy:SetMax( 5000 ) -- Maximum number of the slider
NumSliderThingy:SetDecimals( 0 ) -- Sets a decimal. Zero means it's a whole number
NumSliderThingy:SetConVar( "gry_xadd" ) -- Set the convar
 
	local NumSliderThingy1 = vgui.Create( "DNumSlider", Panel )
NumSliderThingy1:SetPos( 25,180)
NumSliderThingy1:SetSize( 250, 10 ) -- Keep the second number at 100
NumSliderThingy1:SetText( "X Posision" )
NumSliderThingy1:SetMin( -5000 ) -- Minimum number of the slider
NumSliderThingy1:SetMax( 5000 ) -- Maximum number of the slider
NumSliderThingy1:SetDecimals( 0 ) -- Sets a decimal. Zero means it's a whole number
NumSliderThingy1:SetConVar( "gry_xdist" ) -- Set the convar
 
 
 local CheckBoxThing = vgui.Create( "DCheckBoxLabel", Panel )
CheckBoxThing:SetPos( 25,195 )
CheckBoxThing:SetText( "Eyefinity" )
CheckBoxThing:SetConVar( "cl_Eyefinity" ) -- ConCommand must be a 1 or 0 value
CheckBoxThing:SetValue( 0 )
CheckBoxThing:SizeToContents() -- Make its size to the contents. Duh?
 
Panel:AddItem(disabled1)
Panel:AddItem(enabled1)
Panel:AddItem(togglehealth)
Panel:AddItem(togglearmor)
Panel:AddItem(NumSliderThingy)
Panel:AddItem(NumSliderThingy1)
Panel:AddItem(CheckBoxThing)

Panel:AddControl("Button", {Label = "Credits", Text = "tel me who med dis mod plz", Command = "GryCredits"})
end

function GryMod.GryOptionschuteOptionmenu()
spawnmenu.AddToolMenuOption( "Options", "GryMod", "Config", "Config it !", "test1", "test23", GryMod.GryOptionschute )
end
hook.Add("PopulateToolMenu", "PopulateToolMenu", GryMod.GryOptionschuteOptionmenu)

