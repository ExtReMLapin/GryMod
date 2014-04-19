// 22/02/2014 NOTE : IIII FEEEEEEELLLLL THE POWER OF THE POTATOOOOOOOO
--[[ 
 
 omg srsly, 2 years to code this SHIT
 TWO FUCKING YEARS ?
 
 
 TWO ?
 
 
 
 OH MY FUCKING GOD IM SOOOOO LAZY]]

 
 function ScaleFormGFx_Proxy(address, x, y, time)
HTMLTest = vgui.Create( "HTML" )
HTMLTest:SetPos( ((ScrW()-x)/2),((ScrH()-y)/2) )
HTMLTest:SetSize( x+500 , y+500  ) // +500 To prevent the Scrollbar, tell me if you have a way to bypass this ;) And not 5000 to prevent Lag , lel
HTMLTest:OpenURL( address )


timer.Create( "ScaleFormTimer", time, 1, function()
	HTMLTest:Remove()
end)

 end
 
 
 
 function ZoomScaleform()
 GryBinoCulars = vgui.Create( "HTML" )
 GryBinoCulars:SetPos( 0, 0 )
 GryBinoCulars:SetSize( ScrW() , ScrH()  ) //
 GryBinoCulars:OpenURL( "http://extrem-team.com/bino.html" )
 end
 
 function DeZoomScaleform()
 if !IsValid(GryBinoCulars) then return end
GryBinoCulars:Clear() // Maybe useless ... who know ? :V
GryBinoCulars:Stop()
GryBinoCulars:Remove()
 end
 
 
 net.Receive("gry_spawn", function()
ScaleFormGFx_Proxy("http://extrem-team.com/init.html", 1000, 700, 5) // Rip cheap monitors
 end)
 
 
 
 
 hook.Add("PlayerStartVoice", "GrySclVoiceStart", function()
 GryVoice = vgui.Create( "HTML" )
 GryVoice:SetPos( (ScrW()-200), ((ScrH()/2)-150) )
 GryVoice:SetSize( 165+75 , 250+75  ) //
 GryVoice:OpenURL( "http://extrem-team.com/voice.html" )
 end)
 
  hook.Add("PlayerEndVoice", "GrySclVoiceStop", function()
  if !IsValid(GryVoice) then return end
 GryVoice:Clear() // Maybe useless ... who know ? :V
 GryVoice:Stop()
 GryVoice:Remove()
 end)
 
 
 
 
