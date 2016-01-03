local function detectcible( player, key )
	if key == IN_ATTACK then
	local eyetrace = LocalPlayer():GetEyeTrace();
		if eyetrace.Entity:IsPlayer() then
			if eyetrace.Entity:Team() == LocalPlayer():Team() then
				AllyCrossDraw = true
			end 
		end
	end

end

hook.Add( "KeyPress", "HueHueHueHue", detectcible )


local function detectcible_release( player, key )
	if key == IN_ATTACK then
		AllyCrossDraw = false
	end 
end

hook.Add( "KeyRelease", "Hehehehe", detectcible_release )

local tx = surface.GetTextureID( "cryhud/fcross" ) 
function GryMod.cross()
	if AllyCrossDraw == true then
		surface.SetTexture( tx )
		surface.SetDrawColor(Color(255,255,255,255))
		surface.DrawTexturedRect(ScrW()/2-15, ScrH()/2-15, 30, 30)
	end
end

hook.Add("HUDPaint", "GryCross", GryMod.cross) 
