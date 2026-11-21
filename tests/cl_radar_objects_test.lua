-- Tests of what the binoculars may scan on the client side for the radar's vehicles and mines (Bino.IsObject, Bino.Scannable, Bino.Aimable in
-- cl_hud_binoculars_flash.lua), GLuaTest format, client realm. The server decides in the end (sv_radar.lua, Radar.Scan); the client only
-- spares the sound of a lock the server would refuse. The entities are fakes: only what the rules ask for.

local SWITCH = "gry_radar_objects"

local function fake(class, props)
	local e = {class = class, vehicle = false}

	for k, v in pairs(props or {}) do
		e[k] = v
	end

	function e:IsValid() return true end
	function e:GetClass() return self.class end
	function e:IsNPC() return false end
	function e:IsNextBot() return false end
	function e:IsPlayer() return false end
	function e:IsWorld() return false end
	function e:IsVehicle() return self.vehicle end
	function e:Health() return 0 end
	function e:GetMaxHealth() return 0 end

	return e
end

return {
	groupName = "GryMod binoculars: vehicles and mines (client)",
	beforeEach = function(state)
		local c = GetConVar(SWITCH)
		state.switch = c and c:GetString()
		state.realLocalPlayer = LocalPlayer
	end,
	afterEach = function(state)
		LocalPlayer = state.realLocalPlayer

		-- (the switch is the server's, replicated: the client cannot write it, the cases only read it)
	end,
	cases = {
		{
			name = "the switch is replicated to the client, on by default",
			func = function()
				local c = GetConVar(SWITCH)

				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
			end
		},
		{
			name = "a registered vehicle and the mine are objects the binoculars may scan; a seat, a prop and anything unregistered are not",
			func = function()
				local Bino = GryMod.FlashBinoculars

				expect(Bino.IsObject(fake("prop_vehicle_jeep", {vehicle = true}))).to.beTrue()
				expect(Bino.IsObject(fake("prop_vehicle_airboat", {vehicle = true}))).to.beTrue()
				expect(Bino.IsObject(fake("prop_vehicle_apc", {vehicle = true}))).to.beTrue()
				expect(Bino.IsObject(fake("combine_mine"))).to.beTrue()

				expect(Bino.IsObject(fake("prop_vehicle_prisoner_pod", {vehicle = true}))).to.beFalse()
				expect(Bino.IsObject(fake("prop_physics"))).to.beFalse()
				expect(Bino.IsObject(fake("npc_grenade_frag"))).to.beFalse()
			end
		},
		{
			name = "Scannable: a vehicle or a mine that is not tagged yet; not a tagged one, and not the vehicle the player sits in",
			func = function()
				local Bino = GryMod.FlashBinoculars
				local jeep = fake("prop_vehicle_jeep", {vehicle = true})
				local mine = fake("combine_mine")

				expect(Bino.Scannable(jeep, false)).to.beTrue()
				expect(Bino.Scannable(mine, false)).to.beTrue()
				expect(Bino.Scannable(jeep, true)).to.beFalse()
				expect(Bino.Scannable(fake("prop_physics"), false)).to.beFalse()

				-- the player sits in it
				LocalPlayer = function()
					return {IsValid = function() return true end, GetVehicle = function() return jeep end}
				end

				expect(Bino.Scannable(jeep, false)).to.beFalse()
				expect(Bino.Scannable(mine, false)).to.beTrue()
			end
		},
		{
			name = "Aimable: the vehicles and the mines read as a distance like the NPCs, a plain prop does not",
			func = function()
				local Bino = GryMod.FlashBinoculars

				expect(Bino.Aimable(fake("combine_mine"))).to.beTrue()
				expect(Bino.Aimable(fake("prop_vehicle_jeep", {vehicle = true}))).to.beTrue()
				expect(Bino.Aimable(fake("prop_physics"))).to.beFalse()
			end
		}
	}
}
