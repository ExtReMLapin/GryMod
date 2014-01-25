 function menu()

	GryOptions = vgui.Create("DFrame")
	GryOptions:SetSize(300, 220)
	GryOptions:SetPos(ScrW() / 3, ScrH() / 3)
	GryOptions:SetTitle( "GryMod Options" )
	GryOptions:SetVisible( true )
	GryOptions:SetDraggable( true )
	GryOptions:ShowCloseButton( true )
	GryOptions:MakePopup()

	enabled1 = vgui.Create( "DButton", GryOptions )
	enabled1:SetPos( 25, 30 )
	enabled1:SetSize( 250, 50 )
	enabled1:SetText( "ON" )
	
	enabled1.DoClick = function()
		 hook.Add( "HUDPaint", "HUDBASECRY", hudbase )
		  hook.Add( "HUDPaint", "ololol", compass_direction) 
		  hook.Add("HUDShouldDraw", "How to: HUD Example HUD hider", HUDShouldDraw)
	end

	disabled1 = vgui.Create( "DButton", GryOptions )
	disabled1:SetPos( 25, 90 )
	disabled1:SetSize( 250, 50 )
	disabled1:SetText( "OFF" )
	
	disabled1.DoClick = function()
			hook.Remove( "HUDPaint", "HUDBASECRY")
			hook.Remove( "HUDPaint", "ololol") 
			hook.Remove("HUDShouldDraw", "How to: HUD Example HUD hider")
	end


	local NumSliderThingy = vgui.Create( "DNumSlider", GryOptions )
NumSliderThingy:SetPos( 25,150)
NumSliderThingy:SetSize( 250, 10 ) -- Keep the second number at 100
NumSliderThingy:SetText( "Mirror Distance" )
NumSliderThingy:SetMin( -5000 ) -- Minimum number of the slider
NumSliderThingy:SetMax( 5000 ) -- Maximum number of the slider
NumSliderThingy:SetDecimals( 0 ) -- Sets a decimal. Zero means it's a whole number
NumSliderThingy:SetConVar( "gry_xadd" ) -- Set the convar
 
	local NumSliderThingy1 = vgui.Create( "DNumSlider", GryOptions )
NumSliderThingy1:SetPos( 25,180)
NumSliderThingy1:SetSize( 250, 10 ) -- Keep the second number at 100
NumSliderThingy1:SetText( "X Posision" )
NumSliderThingy1:SetMin( -5000 ) -- Minimum number of the slider
NumSliderThingy1:SetMax( 5000 ) -- Maximum number of the slider
NumSliderThingy1:SetDecimals( 0 ) -- Sets a decimal. Zero means it's a whole number
NumSliderThingy1:SetConVar( "gry_xdist" ) -- Set the convar
 
 
 local CheckBoxThing = vgui.Create( "DCheckBoxLabel", GryOptions )
CheckBoxThing:SetPos( 25,195 )
CheckBoxThing:SetText( "Eyefinity" )
CheckBoxThing:SetConVar( "cl_Eyefinity" ) -- ConCommand must be a 1 or 0 value
CheckBoxThing:SetValue( 0 )
CheckBoxThing:SizeToContents() -- Make its size to the contents. Duh?
 
 
end

concommand.Add("GryOptions_menu", menu)


function GryOptionschute (Panel)
Panel:AddControl("Label", {Text = "HUD Parts"})

Panel:AddControl("Button", {Label = "Menu", Text = "...", Command = "GryOptions_menu"})



end

function GryOptionschuteOptionmenu()
spawnmenu.AddToolMenuOption( "Options", "GryMod", "Hud Parts", "HUD Parts", "test1", "test23", GryOptionschute )
end
hook.Add("PopulateToolMenu", "PopulateToolMenu", GryOptionschuteOptionmenu)

