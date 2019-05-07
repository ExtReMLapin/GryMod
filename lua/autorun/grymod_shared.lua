if not GryMod then
	GryMod = {}
end

GryMod.WSID = 153963150
GryMod.Workshop = false
GryMod.Modes = {ARMOR = 0, SPEED = 1, CLOAK = 2, STRENGTH = 3, DROP = 4}



function math.MapSimple(numb, endA, endB)
	return numb * (endB / endA)
end -- i used the map() function in processing, i have no idea if there somthing similar here

if SERVER then
	AddCSLuaFile("grymod/client/cl_hud.lua")
	AddCSLuaFile("grymod/client/cl_fonts.lua")
	AddCSLuaFile("grymod/client/cl_grenade.lua")
	AddCSLuaFile("grymod/client/cl_allycross.lua")
	AddCSLuaFile("grymod/client/cl_nanoholo.lua")
	AddCSLuaFile("grymod/client/cl_options.lua")
	AddCSLuaFile("grymod/sh_crashlogo.lua")
	AddCSLuaFile()
	include("grymod/server/sv_health.lua")
	include("grymod/server/sv_system.lua")
	include("grymod/sh_crashlogo.lua")

	if GryMod.Workshop == false then
		resource.AddFile("sound/cry_close.wav")
		resource.AddFile("sound/cry_error.wav")
		resource.AddFile("sound/cry_hover.wav")
		resource.AddFile("sound/cry_open.wav")
		resource.AddFile("sound/cry_select.wav")
		resource.AddFile("sound/suit/armor.mp3")
		resource.AddFile("sound/suit/binocular.wav")
		resource.AddFile("sound/suit/binocularzoom.wav")
		resource.AddFile("sound/suit/binocularzoomout.wav")
		resource.AddFile("sound/suit/cloak.mp3")
		resource.AddFile("sound/suit/nightv.wav")
		resource.AddFile("sound/suit/speed.mp3")
		resource.AddFile("sound/suit/speedmode.wav")
		resource.AddFile("sound/suit/strenghtjump.wav")
		resource.AddFile("sound/suit/strenghtmode.wav")
		resource.AddFile("sound/suit/strength.mp3")
		resource.AddFile("sound/suit/underwater.wav")
		resource.AddFile("sound/interface_suit/binocularzoomin.wav")
		resource.AddFile("sound/interface_suit/binocularzoomout.wav")
		resource.AddFile("resource/fonts/Agency FB.ttf")
		resource.AddFile("models/models/crysis_pack/parachute_attachement.mdl")
		resource.AddFile("models/models/crysis_pack/parachute_backpack.mdl")
		resource.AddFile("materials/crysis_arrow.vmt")
		resource.AddFile("materials/crysis_arrow.vtf")
		resource.AddFile("materials/crysis_button.vmt")
		resource.AddFile("materials/crysis_button.vtf")
		resource.AddFile("materials/crysis_circle.vmt")
		resource.AddFile("materials/crysis_circle.vtf")
		resource.AddFile("materials/gryarmor.png")
		resource.AddFile("materials/grycloak.png")
		resource.AddFile("materials/grydrop.png")
		resource.AddFile("materials/gryspeed.png")
		resource.AddFile("materials/grystrenght.png")
		resource.AddFile("materials/models/crysis_pack/base.vtf")
		resource.AddFile("materials/models/crysis_pack/Material__25.vmt")
		resource.AddFile("materials/models/crysis_pack/normalmap.vtf")
		resource.AddFile("materials/models/crysis_pack/parachute.vmt")
		resource.AddFile("materials/models/crysis_pack/para_texture.vtf")
		resource.AddFile("materials/cryhud/base.vmt")
		resource.AddFile("materials/cryhud/base.vtf")
		resource.AddFile("materials/cryhud/cadre.vmt")
		resource.AddFile("materials/cryhud/cadre.vtf")
		resource.AddFile("materials/cryhud/compass.vmt")
		resource.AddFile("materials/cryhud/compass.vtf")
		resource.AddFile("materials/cryhud/crash.vmt")
		resource.AddFile("materials/cryhud/crash.vtf")
		resource.AddFile("materials/cryhud/enr.vmt")
		resource.AddFile("materials/cryhud/enr.vtf")
		resource.AddFile("materials/cryhud/fcross.vmt")
		resource.AddFile("materials/cryhud/fcross.vtf")
		resource.AddFile("materials/cryhud/healthpr.vmt")
		resource.AddFile("materials/cryhud/healthpr.vtf")
		resource.AddFile("materials/cloak/cloak.vmt")
		resource.AddFile("materials/cloak/organic.vmt")
		resource.AddFile("materials/cloak/organic.vtf")
		resource.AddFile("materials/cloak/organic_ddn.vtf")
		resource.AddFile("materials/cloak/organic_ddndif.vtf")
	else
		resource.AddWorkshop(tostring(GryMod.WSID))
	end
end

if CLIENT then
	include("grymod/client/cl_hud.lua")
	include("grymod/client/cl_fonts.lua")
	include("grymod/client/cl_grenade.lua")
	include("grymod/client/cl_allycross.lua")
	include("grymod/client/cl_nanoholo.lua")
	include("grymod/client/cl_options.lua")
	include("grymod/sh_crashlogo.lua")
end