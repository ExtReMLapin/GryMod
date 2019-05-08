

function surface.ScreenScale(size)
	return size * (ScrH() / 480.0)
end

GryMod.detectable = {} -- Feel Free to customize this
GryMod.detectable[1] = {}
GryMod.detectable[1].realname = "gmod_button"
GryMod.detectable[1].drawname = "Button"
GryMod.detectable[1].drawimage = surface.GetTextureID("gui/arrow")
GryMod.detectable[1].distance = 130
GryMod.detectable[1].distancecolor = color_white
GryMod.detectable[2] = {}
GryMod.detectable[2].realname = "npc_grenade_frag"
GryMod.detectable[2].drawname = "Frag Grenade"
GryMod.detectable[2].drawimage = surface.GetTextureID("cryhud/cadre")
GryMod.detectable[2].distance = 750
GryMod.detectable[2].distancecolor = Color(220, 5, 5, 255)

function GryMod.grenadetetect()
	for k, Entity in pairs(ents.GetAll()) do
		if (Entity and IsValid(Entity)) then
			for l, projectile in pairs(GryMod.detectable) do
				if (Entity:GetClass() == projectile.realname) then
					local pos = Entity:LocalToWorld(Entity:OBBCenter()):ToScreen()

					if (pos.visible) then
						local DISTANCE = math.Round(LocalPlayer():GetPos():Distance(Entity:GetPos()))

						if DISTANCE < projectile.distance then
							surface.SetTexture(projectile.drawimage)
							surface.SetDrawColor(color_white)
							surface.DrawTexturedRect(pos.x - (25) + (DISTANCE / 80), pos.y - (25) + (DISTANCE / 80), 50 - (DISTANCE / 40), 50 - (DISTANCE / 40))
							draw.SimpleText(projectile.drawname, "CrysisInfos", pos.x + 150, pos.y + 25, projectile.distancecolor, 2, 3)
						end
					end
				end
			end
		end
	end
end

hook.Add("HUDPaint", "Nade detection", GryMod.grenadetetect)