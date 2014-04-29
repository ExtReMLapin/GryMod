hook.Add( "PreDrawHalos", "hueheu", function() // Yes, a file only for that
if LocalPlayer().ZSing then
halo.Add( ents.FindByClass( "weapon_*" ), Color( 25, 50, 250 ), 0.75, 0.75, 0 )
end
end)