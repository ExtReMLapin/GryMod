 function ScaleFormGFx_Proxy(address, x, y, time)
	HTMLTest = vgui.Create( "HTML" )
	HTMLTest:SetPos( ((ScrW()-x)/2),((ScrH()-y)/2) )
	HTMLTest:SetSize( x+500 , y+500  ) -- +500 To prevent the Scrollbar, tell me if you have a way to bypass this ;) And not 5000 to prevent Lag , lel
	HTMLTest:OpenURL( address )
		timer.Create( "ScaleFormTimer", time, 1, function()
			HTMLTest:Remove()
		end)
 end


 function GryMod.ZoomScaleform()
 	GryBinoCulars = vgui.Create( "HTML" )
 	GryBinoCulars:SetPos( 0, 0 )
	GryBinoCulars:SetSize( ScrW() , ScrH()  ) //
	GryBinoCulars:OpenURL( "http://extrem-team.com/bino.html" )
 end

 function GryMod.DeZoomScaleform()
if !IsValid(GryBinoCulars) then return end
	GryBinoCulars:Clear() // Maybe useless ... who know ? :V
	GryBinoCulars:Stop()
	GryBinoCulars:Remove()
end
