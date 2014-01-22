

function surface.ScreenScale( size )
	return size * ( ScrH() / 480.0 )
end

local function grenadetetect()
	local player = LocalPlayer()

detectable = {} // Feel Free to customize that, that's why i used a table system.
detectable[1] = {}
detectable[1].realname = "gmod_button"
detectable[1].drawname = "Button"
detectable[1].drawimage = "gui/arrow"
detectable[1].distance = 130
detectable[1].distancecolor = Color(255, 255, 255, 255)
detectable[2] = {}
detectable[2].realname = "npc_grenade_frag"
detectable[2].drawname = "Frag Grenade"
detectable[2].drawimage = "cryhud/cadre"
detectable[2].distance = 750
detectable[2].distancecolor = Color(220, 5, 5, 255)
	

	

	for k, Entity in pairs( ents.GetAll() ) do
		if ( Entity and IsValid(Entity) ) then
			for l, projectile in pairs( detectable) do
				if (Entity:GetClass() == projectile.realname ) then
					local pos		= Entity:LocalToWorld( Entity:OBBCenter() ):ToScreen()
					local text_xpos	= pos.x
					local text_ypos	= pos.y - surface.ScreenScale( 32 )
					if ( pos.visible ) then
							local DISTANCE	= math.Round( player:GetPos():Distance( Entity:GetPos() )  )
							if DISTANCE < projectile.distance then
								surface.SetTexture( surface.GetTextureID( projectile.drawimage )  )
								surface.SetDrawColor(Color(255,255,255,255))
								surface.DrawTexturedRect(pos.x-(25)  , pos.y-(25) ,  50, 50)	
								draw.SimpleText( projectile.drawname, "CrysisInfos",pos.x + 150, pos.y + 25, projectile.distancecolor, 2, 3)			
							end
					end

				end

			end

		end

	end

end

hook.Add( "HUDPaint", "Nade detection", grenadetetect )




