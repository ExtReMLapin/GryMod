if not GryMod then
	GryMod = {}
end

GryMod.WSID = 153963150
GryMod.Workshop = false

GryMod.Modes = {
	ARMOR = 0,
	SPEED = 1,
	CLOAK = 2,
	STRENGTH = 3,
	DROP = 4
}

function math.MapSimple(numb, endA, endB)
	return numb * (endB / endA)
end


if SERVER then
	AddCSLuaFile()
	AddCSLuaFile("grymod/client/cl_hud.lua")
	AddCSLuaFile("grymod/client/cl_sounds.lua")
	AddCSLuaFile("grymod/client/cl_fonts.lua")
	AddCSLuaFile("grymod/client/cl_options.lua")
	include("grymod/server/sv_health.lua")
	include("grymod/server/sv_system.lua")

	if GryMod.Workshop == false then
	resource.AddFile("materials/gryarmor.png")
	resource.AddFile("materials/grycloak.png")
	resource.AddFile("materials/grydrop.png")
	resource.AddFile("materials/gryspeed.png")
	resource.AddFile("materials/grystrength.png")
	resource.AddFile( "materials/cloak/cloak.vmt" )
	resource.AddFile( "materials/cloak/organic.vmt" )
	resource.AddFile( "materials/cloak/organic.vtf" )
	resource.AddFile( "materials/cloak/organic_ddn.vtf" )
	resource.AddFile( "materials/cloak/organic_ddndif.vtf" )
	resource.AddFile( "materials/cryhud/base.vmt" )
	resource.AddFile( "materials/cryhud/base.vtf" )
	resource.AddFile( "materials/cryhud/cadre.vmt" )
	resource.AddFile( "materials/cryhud/cadre.vtf" )
	resource.AddFile( "materials/cryhud/compass.vmt" )
	resource.AddFile( "materials/cryhud/compass.vtf" )
	resource.AddFile( "materials/crysis_arrow.vmt" )
	resource.AddFile( "materials/crysis_arrow.vtf" )
	resource.AddFile( "materials/crysis_button.vmt" )
	resource.AddFile( "materials/crysis_button.vtf" )
	resource.AddFile( "materials/crysis_button_grid.vmt" )
	resource.AddFile( "materials/crysis_button_grid.vtf" )
	resource.AddFile( "materials/crysis_circle.vmt" )
	resource.AddFile( "materials/crysis_circle.vtf" )
	resource.AddFile( "materials/models/crysis_pack/base.vtf" )
	resource.AddFile( "materials/models/crysis_pack/Material__25.vmt" )
	resource.AddFile( "materials/models/crysis_pack/normalmap.vtf" )
	resource.AddFile( "materials/models/crysis_pack/parachute.vmt" )
	resource.AddFile( "materials/models/crysis_pack/para_texture.vtf" )
	resource.AddFile( "models/models/crysis_pack/parachute_attachement.mdl" )
	resource.AddFile( "models/models/crysis_pack/parachute_backpack.mdl" )
	resource.AddFile( "sound/cry_close.wav" )
	resource.AddFile( "sound/cry_error.wav" )
	resource.AddFile( "sound/cry_hover.wav" )
	resource.AddFile( "sound/cry_open.wav" )
	resource.AddFile( "sound/cry_select.wav" )
	resource.AddFile( "sound/suit/cloak_chameleon_activate_12.wa.mp3" )
	resource.AddFile( "sound/suit/servo_speed_loop_01c.mp3" )
	resource.AddFile( "sound/suit/servo_speed_loop_01_underwater.mp3" )
	resource.AddFile( "sound/suit/servo_speed_stop_01_underwater.mp3" )
	resource.AddFile( "sound/suit/servo_speed_stop_fp_2.mp3" )
	resource.AddFile( "sound/suit/strengthjump.mp3" )
	resource.AddFile( "sound/suit/strengthmode.mp3" )
	resource.AddFile( "sound/suit/suit_armor_108.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_01.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_02.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_03.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_05.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_06.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_07.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_09.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_10.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_11.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_13.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_14.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_15.mp3" )
	resource.AddFile( "sound/suit/suit_bullet_impact_16.mp3" )
	resource.AddFile( "sound/suit/suit_cloak_chameleon_101_r.mp3" )
	resource.AddFile( "sound/suit/suit_energy_critical.mp3" )
	resource.AddFile( "sound/suit/suit_maximum_armor.mp3" )
	resource.AddFile( "sound/suit/suit_maximum_speed.mp3" )
	resource.AddFile( "sound/suit/suit_maximum_strength.mp3" )
	resource.AddFile( "sound/suit/suit_medical_use_new.mp3" )
	resource.AddFile( "sound/suit/suit_modification_engaged.mp3" )
	resource.AddFile( "sound/suit/suit_speed_activate_07_good.wa.mp3" )
	resource.AddFile( "sound/suit/suit_strength_101_r.mp3" )
	resource.AddFile( "sound/suit/suit_usage_error.mp3" )
	else
		resource.AddWorkshop(tostring(GryMod.WSID))
	end
end

if CLIENT then
	include("grymod/client/cl_hud.lua")
	include("grymod/client/cl_sounds.lua")
	include("grymod/client/cl_fonts.lua")
	include("grymod/client/cl_options.lua")
end