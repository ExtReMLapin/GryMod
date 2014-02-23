// 22/02/2014 NOTE : IIII FEEEEEEELLLLL THE POWER OF THE POTATOOOOOOOO
--[[ 
No srsly, if someone read that, i just checked back old GryMod comments, dat feel,
 i was felling bad in Jully2k13 ans some peoples were still here to say GryMod was a good addon :),  
 so i'm here to finish my job. 
 
 
 Thanks to all peoples who supported me and this project since 2 years
 
 
 
 
 omg srsly, 2 years to code this SHIT
 TWO FUCKING YEARS ?
 
 
 TWO ?
 
 
 
 OH MY FUCKING GOD IM SOOOOO LAZY]]

 
 function ScaleFormGFx_Proxy(address, x, y)
HTMLTest = vgui.Create( "HTML" )
HTMLTest:SetPos( ((ScrW()-x)/2),((ScrH()-y)/2) )
HTMLTest:SetSize( x+500 , y+500  ) // +500 To prevent the Scrollbar, tell me if you have a way to bypass this ;) And not 5000 to prevent Lag , lel
HTMLTest:OpenURL( address )
 end
 
 
 
 
 
 net.Receive("gry_spawn", function()
ScaleFormGFx_Proxy("http://extrem-team.com/init.html", 1000, 700) // Rip cheap monitors
 end)
 
 
 
 
 hook.Add("PlayerStartVoice", "GrySclVoiceStart", function()
 GryVoice = vgui.Create( "HTML" )
 GryVoice:SetPos( (ScrW()-200), (ScrH()/2) )
 GryVoice:SetSize( 165+75 , 250+75  ) //
 GryVoice:OpenURL( "http://extrem-team.com/voice.html" )
 end)
 
  hook.Add("PlayerEndVoice", "GrySclVoiceStop", function()
 GryVoice:Clear()
 GryVoice:Stop()
 GryVoice:Close()
 end)
 