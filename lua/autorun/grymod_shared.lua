if not GryMod then GryMod = {} end

function math.LengthSqVector(a)
	return (a.x * a.x + a.y * a.y + a.z * a.z);
end

function math.LengthVector(a)
	return math.sqrt(LengthSqVector(a));
end

function math.DistanceSqVectors(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	local z = a.z-b.z;
	return x*x + y*y + z*z;
end

function math.DistanceSqVectors2d(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	return x*x + y*y;
end

function math.DistanceVectors(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	local z = a.z-b.z;
	return math.sqrt(x*x + y*y + z*z);
end

function math.Delta(actual,goal)
return goal - actual;
end

function GryMod.EyeFinityScrW()
	if tempscrw/tempscrh == 16/3  and EyeFinity:GetInt() > 0 then
		return tempscrw/3
	else
		return tempscrw
	end
end

function constrain(val, minv, maxv)
	return math.min(math.max(val, minv), maxv)
 end
 
 function math.MapSimple(numb,endA,endB) -- i used the map() function in processing, i have no idea if there smthng similar here
	return numb*(endB/endA)
end

if SERVER then
AddCSLuaFile( "client/cl_hud.lua" )
AddCSLuaFile( "client/cl_fonts.lua" )
AddCSLuaFile( "client/cl_grenade.lua" )
AddCSLuaFile( "client/cl_allycross.lua" )
AddCSLuaFile( "client/cl_nanoholo.lua" )
AddCSLuaFile( "client/cl_options.lua" )
AddCSLuaFile( "client/cl_Scaleform_GFx.lua" )
AddCSLuaFile( "sh_crashlogo.lua" )
end

if (SERVER) then
	resource.AddFile( "sound/cry_close.wav" )
	resource.AddFile( "sound/cry_error.wav" )
	resource.AddFile( "sound/cry_hover.wav" )
	resource.AddFile( "sound/cry_open.wav" )
	resource.AddFile( "sound/cry_select.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_boltpull.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_boltrelease.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_clipin.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_clipout.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_silencer_click.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_silencer_release.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_silencer_twist.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_unsil-1.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_unsil-2.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_unsil-3.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_unsil-4.wav" )
	resource.AddFile( "sound/weapons/crym4a1/m4a1_unsil-5.wav" )
	resource.AddFile( "sound/suit/armor.mp3" )
	resource.AddFile( "sound/suit/binocular.wav" )
	resource.AddFile( "sound/suit/binocularzoom.wav" )
	resource.AddFile( "sound/suit/binocularzoomout.wav" )
	resource.AddFile( "sound/suit/cloak.mp3" )
	resource.AddFile( "sound/suit/nightv.wav" )
	resource.AddFile( "sound/suit/speed.mp3" )
	resource.AddFile( "sound/suit/speedmode.wav" )
	resource.AddFile( "sound/suit/strenghtjump.wav" )
	resource.AddFile( "sound/suit/strenghtmode.wav" )
	resource.AddFile( "sound/suit/strength.mp3" )
	resource.AddFile( "sound/suit/underwater.wav" )
	resource.AddFile( "sound/interface_suit/binocularzoomin.wav" )
	resource.AddFile( "sound/interface_suit/binocularzoomout.wav" )
	resource.AddFile( "resource/fonts/Agency FB.ttf" )
	resource.AddFile( "models/weapons/v_cry_m4a1.mdl" )
	resource.AddFile( "models/models/crysis_pack/parachute_attachement.mdl" )
	resource.AddFile( "models/models/crysis_pack/parachute_backpack.mdl" )
	resource.AddFile( "materials/crysis_arrow.vmt" )
	resource.AddFile( "materials/crysis_arrow.vtf" )
	resource.AddFile( "materials/crysis_button.vmt" )
	resource.AddFile( "materials/crysis_button.vtf" )
	resource.AddFile( "materials/crysis_circle.vmt" )
	resource.AddFile( "materials/crysis_circle.vtf" )
	resource.AddFile( "materials/gryarmor.png" )
	resource.AddFile( "materials/grycloak.png" )
	resource.AddFile( "materials/grydrop.png" )
	resource.AddFile( "materials/gryspeed.png" )
	resource.AddFile( "materials/grystrenght.png" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/assault_scope.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/assault_scope.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/assault_scope_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/assault_scope_normal.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/back_rail.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/back_rail.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/back_rail_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/back_rail_normal.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/crosshair.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/crosshair.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lam_rifle.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lam_rifle.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lam_rifle_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lam_rifle_normal.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/laser_beam.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/laser_beam.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lense.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/lense.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/mag.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/mag.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/mag_bump.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/railing.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/railing.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/railing_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/railing_normal.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/scar.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/scar.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/scar_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/scar_normal.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/silencer.vmt" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/silencer.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/silencer_exp.vtf" )
	resource.AddFile( "materials/models/weapons/v_models/cry_scar/silencer_normal.vtf" )
	resource.AddFile( "materials/models/crysis_pack/base.vtf" )
	resource.AddFile( "materials/models/crysis_pack/Material__25.vmt" )
	resource.AddFile( "materials/models/crysis_pack/normalmap.vtf" )
	resource.AddFile( "materials/models/crysis_pack/parachute.vmt" )
	resource.AddFile( "materials/models/crysis_pack/para_texture.vtf" )
	resource.AddFile( "materials/lightwarps/lw1.vtf" )
	resource.AddFile( "materials/detail/weapon_metal.vtf" )
	resource.AddFile( "materials/Cubemap/hdr.vtf" )
	resource.AddFile( "materials/cryhud/base.vmt" )
	resource.AddFile( "materials/cryhud/base.vtf" )
	resource.AddFile( "materials/cryhud/bluebar.png" )
	resource.AddFile( "materials/cryhud/cadre.vmt" )
	resource.AddFile( "materials/cryhud/cadre.vtf" )
	resource.AddFile( "materials/cryhud/compass.vmt" )
	resource.AddFile( "materials/cryhud/compass.vtf" )
	resource.AddFile( "materials/cryhud/crash.vmt" )
	resource.AddFile( "materials/cryhud/crash.vtf" )
	resource.AddFile( "materials/cryhud/enr.vmt" )
	resource.AddFile( "materials/cryhud/enr.vtf" )
	resource.AddFile( "materials/cryhud/fcross.vmt" )
	resource.AddFile( "materials/cryhud/fcross.vtf" )
	resource.AddFile( "materials/cryhud/greenbar.png" )
	resource.AddFile( "materials/cryhud/gry_badguys.png" )
	resource.AddFile( "materials/cryhud/gry_friendly.png" )
	resource.AddFile( "materials/cryhud/gry_whoAreu.png" )
	resource.AddFile( "materials/cryhud/healthpr.vmt" )
	resource.AddFile( "materials/cryhud/healthpr.vtf" )
	resource.AddFile( "materials/cryhud/scarprofil1.png" )
	resource.AddFile( "materials/cloak/cloak.vmt" )
	resource.AddFile( "materials/cloak/organic.vmt" )
	resource.AddFile( "materials/cloak/organic.vtf" )
	resource.AddFile( "materials/cloak/organic_ddn.vtf" )
	resource.AddFile( "materials/cloak/organic_ddndif.vtf" )
end
