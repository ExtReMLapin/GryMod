-- Tests of the VJ Base adapter, shared part (lua/grymod/compat/npc/sh_vjbase.lua), GLuaTest format, both realms (the same declarations run on the server and on the
-- client). The rule that picks the dangerous projectiles is tried on stand-ins (a function that says what a class declares); the cases marked `when = VJ ~= nil`
-- read the real classes of VJ Base and of Half-Life Resurgence and are skipped where they are not installed.

local function realClass(class)
	return scripted_ents.Get(class) ~= nil
end

return {
	groupName = "GryMod VJ Base adapter (shared)",
	cases = {
		{
			name = "the adapter exists",
			func = function()
				expect(GryMod.VJBase ~= nil).to.beTrue()
				expect(isfunction(GryMod.VJBase.ProjectileKind)).to.beTrue()
				expect(isfunction(GryMod.VJBase.Setup)).to.beTrue()
			end
		},
		{
			name = "a projectile VJ tags as a grenade is a grenade; a tagged danger is a missile or a bomb by its name; anything else is nothing",
			func = function()
				local V = GryMod.VJBase

				local function member(tags)
					return function(class, key) return tags[key] end
				end

				expect(V.ProjectileKind("obj_vj_grenade", member({VJ_ID_Grenade = true}))).to.equal("grenade")
				expect(V.ProjectileKind("obj_vj_thing", member({VJ_ID_Grenade = true, VJ_ID_Danger = true}))).to.equal("grenade")
				expect(V.ProjectileKind("obj_vj_rocket", member({VJ_ID_Danger = true}))).to.equal("missile")
				expect(V.ProjectileKind("obj_vj_hlr1_rocket", member({VJ_ID_Danger = true}))).to.equal("missile")
				expect(V.ProjectileKind("obj_vj_hlr1_grenade_40mm", member({VJ_ID_Danger = true}))).to.equal("grenade")
				expect(V.ProjectileKind("obj_vj_l4d_pipebomb", member({VJ_ID_Danger = true}))).to.equal("bomb")
				expect(V.ProjectileKind("obj_vj_combineball", member({VJ_ID_Danger = true}))).to.equal("energy")
				-- tagged as danger but no explosive: a hornet, an orb, a stomp
				expect(V.ProjectileKind("obj_vj_hlr1_hornet", member({VJ_ID_Danger = true}))).to.beNil()
				expect(V.ProjectileKind("obj_vj_hlr1_kingpin_orb", member({VJ_ID_Danger = true}))).to.beNil()
				expect(V.ProjectileKind("obj_vj_hlr1_garg_stomp", member({VJ_ID_Danger = true}))).to.beNil()
				-- no tag at all, or an NPC
				expect(V.ProjectileKind("obj_vj_crossbowbolt", member({}))).to.beNil()
				expect(V.ProjectileKind("npc_vj_rocket_guy", member({VJ_ID_Danger = true, Type = "ai"}))).to.beNil()
			end
		},
		{
			name = "REAL VJ: the default grenade, the rocket and the Half-Life Resurgence rockets are dangers of the grenade warning, a hornet is not",
			when = VJ ~= nil,
			func = function()
				local API = GryMod.API
				local V = GryMod.VJBase

				V.Setup()
				expect(API.GetDanger("obj_vj_grenade") ~= nil).to.beTrue()
				expect(API.GetDanger("obj_vj_grenade").danger.label).to.equal("GRENADE")
				expect(API.GetDanger("obj_vj_rocket") ~= nil).to.beTrue()
				expect(API.GetDanger("obj_vj_rocket").danger.label).to.equal("MISSILE")
				expect(API.GetDanger("obj_vj_rocket").danger.ownMissile).to.beTrue()
				expect(API.GetDanger("obj_vj_grenade_rifle") ~= nil).to.beTrue()

				if realClass("obj_vj_hlr1_rocket") then
					expect(API.GetDanger("obj_vj_hlr1_rocket") ~= nil).to.beTrue()
					expect(API.GetDanger("obj_vj_hlr1_hornet")).to.beNil()
					expect(API.GetDanger("obj_vj_hlr1_kingpin_orb")).to.beNil()
				end
			end
		},
		{
			name = "REAL VJ: a VJ projectile is followed as a danger from its creation, without any armed reader (the fuse and the flight start at once)",
			when = VJ ~= nil and SERVER,
			func = function()
				local grenade = ents.Create("obj_vj_grenade")
				grenade:SetPos(player.GetAll()[1]:GetPos() + Vector(300, 0, 50))
				grenade:Spawn()

				local entry = GryMod.API.GetDanger(grenade)
				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed).to.beNil()
				grenade:Remove()
			end
		},
		{
			name = "REAL VJ: the tanks are machines, the aircraft flying units, the bullseye is never on the radar and cannot be scanned",
			when = VJ ~= nil and SERVER,
			func = function()
				local API = GryMod.API
				local made = {}

				local function make(class)
					local e = ents.Create(class)
					e:SetPos(player.GetAll()[1]:GetPos() + Vector(600, 0, 30))
					e:Spawn()
					made[#made + 1] = e

					return e
				end

				local ok, err = pcall(function()
					local tank = make("npc_vj_milifri_m1a1abrams")
					local bull = make("obj_vj_bullseye")

					local tankEntry = API.GetTracked(tank)
					expect(tankEntry ~= nil).to.beTrue()
					expect(tankEntry.type).to.equal(3) -- "machine"
					expect(tankEntry.size).to.equal("big")

					local bullEntry = API.GetTracked(bull)
					expect(bullEntry ~= nil).to.beTrue()
					expect(bullEntry.radar).to.equal("never")
					expect(bullEntry.scan).to.equal(false)

					if realClass("npc_vj_hlr1_apache") then
						local heli = make("npc_vj_hlr1_apache")
						local heliEntry = API.GetTracked(heli)
						expect(heliEntry ~= nil).to.beTrue()
						expect(heliEntry.type).to.equal(2) -- "flying"
					end

					-- a plain VJ soldier is no machine: the default icon
					expect(API.GetTracked(make("npc_vj_milifri_ranger"))).to.beNil()
				end)

				for _, e in ipairs(made) do
					if IsValid(e) then e:Remove() end
				end

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the stock entries of Half-Life 2 keep their icon (the adapter's entries come after them)",
			func = function()
				expect(GryMod.API.GetTrackedByClass("npc_strider").size).to.equal("big")
				expect(GryMod.API.GetTrackedByClass("npc_manhack").type).to.equal(2) -- "flying"
			end
		},
		{
			name = "a VJ melee weapon is described with no gun icon, a gun with its Primary.Automatic",
			-- the adapter registers its entries only when VJ Base is in the game
			when = VJ ~= nil,
			func = function()
				local API = GryMod.API
				local entry = API.GetWeapon("weapon_vj_base")

				expect(entry ~= nil).to.beTrue()
				expect(isfunction(entry.fire)).to.beTrue()
				expect(entry.fire({IsMeleeWeapon = true, Primary = {Automatic = true}})).to.equal("none")
				expect(entry.fire({IsMeleeWeapon = false, Primary = {Automatic = true}})).to.equal("auto")
				expect(entry.fire({IsMeleeWeapon = false, Primary = {Automatic = false}})).to.equal("semi")
				expect(entry.fire({})).to.equal("semi")
			end
		},
		{
			name = "the usable entries: a VJ weapon on the floor is taken with the use key (VJ asks for it), an owned one is not",
			func = function()
				local API = GryMod.API
				local floor = {IsVJBaseWeapon = true, GetOwner = function() return NULL end}
				local held = {IsVJBaseWeapon = true, GetOwner = function() return player.GetAll()[1] end}

				expect(isfunction(API.RegisterUsable)).to.beTrue()
				expect(GryMod.VJBase.IsFloorWeapon(floor)).to.beTrue()
				expect(GryMod.VJBase.IsFloorWeapon(held)).to.beFalse()
				expect(GryMod.VJBase.IsFloorWeapon({})).to.beFalse()
			end
		}
	}
}
