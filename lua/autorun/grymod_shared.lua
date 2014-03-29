GITHUB = 1
WORKSHOP = 2

GRY_VERSION = GITHUB

if SERVER then
AddCSLuaFile( "client/cl_hud.lua" )
AddCSLuaFile( "client/cl_fonts.lua" )
AddCSLuaFile( "client/cl_grenade.lua" )
AddCSLuaFile( "client/cl_allycross.lua" )
AddCSLuaFile( "client/cl_nanoholo.lua" )
AddCSLuaFile( "client/cl_options.lua" )
AddCSLuaFile( "client/cl_Scaleform_GFx.lua" )
AddCSLuaFile( "sh_crashlogo.lua" )
AddCSLuaFile( "sh_math.lua" )
end



if (SERVER) then
	resource.AddWorkshop(209535414)
	resource.AddFile( "resource/fonts/Agency FB.ttf" ) // PLEASE PUT IT IN YOUR FASTDL PLEEEEASSSEEEEE
end	