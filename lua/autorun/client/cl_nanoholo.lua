hook.Add( "PreDrawHalos", "hueheu", function()
if LocalPlayer().ZSing then
halo.Add( ents.FindByClass( "weapon_*" ), Color( 25, 50, 250 ), 0.75, 0.75, 0 )
end
end)