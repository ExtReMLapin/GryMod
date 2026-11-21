-- Tests of the vehicles and the mines on the radar (GryMod.Radar, sv_radar.lua; the stock entries are in sh_api_tracked_hl2.lua), GLuaTest
-- format, server realm. In the original radar the vehicles are the rectangle icons of the movie (type 3: grey for a vehicle with
-- nobody or a driver that is neither friend nor foe, blue for a friend, red for a hostile driver, the colour of its DRIVER) and they
-- are on the radar once tagged, which the binoculars' scan does. The mine uses the movie's type 4, a rectangle with a disc, an icon the
-- original's HUD code never produces. Only the stock classes are tracked (the Buggy and the Jalopy are prop_vehicle_jeep, the airboat,
-- the Combine APC, the crane): a seat of the spawn menu (prop_vehicle_prisoner_pod) is not. Another addon's vehicle is registered by
-- the API. One switch for all of it: gry_radar_objects (the administrators' option).

local function ply()
	return player.GetAll()[1]
end

local R, S

local spawned = {}

local function remember(e)
	spawned[#spawned + 1] = e

	return e
end

-- A real Buggy, `ahead` units in front of the player.
local function spawnJeep(ahead)
	local p = ply()
	local e = ents.Create("prop_vehicle_jeep")
	e:SetModel("models/buggy.mdl")
	e:SetKeyValue("vehiclescript", "scripts/vehicles/jeep_test.txt")
	e:SetPos(p:GetPos() + Vector(ahead or 300, 0, 40))
	e:Spawn()
	e:Activate()

	return remember(e)
end

local function spawnMine(ahead)
	local p = ply()
	local e = ents.Create("combine_mine")
	e:SetPos(p:GetPos() + Vector(ahead or 300, 100, 10))
	e:Spawn()

	return remember(e)
end

local function spawnNPC(class, ahead)
	local p = ply()
	local e = ents.Create(class)
	e:SetPos(p:GetPos() + Vector(ahead or 300, -200, 10))
	e:Spawn()

	return remember(e)
end

-- the list a tick sends, without sending it to the player's real client
local real = {}
local stubbed = false

local function stubNet()
	if stubbed then return end

	stubbed = true
	real.Start, real.Send = net.Start, net.Send
	net.Start = function() return true end
	net.Send = function() end
end

local function restoreNet()
	if not stubbed then return end

	stubbed = false
	net.Start, net.Send = real.Start, real.Send
end

local function contactOf(list, ent)
	for _, c in ipairs(list or {}) do
		if c.id == ent:EntIndex() then
			return c
		end
	end
end

-- the tick of a player that asked for the radar
local function tick()
	local p = ply()
	p.GryRadarWant = true
	R.Tick(p, CurTime())

	return R.State(p).sent
end

return {
	groupName = "GryMod radar: vehicles and mines (server)",
	beforeAll = function()
		R = GryMod.Radar
		S = GryMod.RadarShared
	end,
	beforeEach = function(state)
		local c = GetConVar("gry_radar_objects")
		state.objects = c and c:GetString()

		if c then
			c:SetString("1")
		end

		local a = GetConVar("gry_radar_allies_always")
		state.alliesAlways = a and a:GetString()

		if a then
			a:SetString("0")
		end

		stubNet()
	end,
	afterEach = function(state)
		pcall(restoreNet)

		local c = GetConVar("gry_radar_objects")

		if c and state.objects then
			c:SetString(state.objects)
		end

		local a = GetConVar("gry_radar_allies_always")

		if a and state.alliesAlways then
			a:SetString(state.alliesAlways)
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:SetPos(Vector(0, 0, -30000))
				e:Remove()
			end
		end

		spawned = {}
		local p = ply()

		if IsValid(p) and R then
			R.Reset(p)
			p.GryRadarWant = nil
		end
	end,
	cases = {
		{
			name = "the switch exists, on by default, replicated, and is in the administrators' white list",
			func = function()
				local c = GetConVar("gry_radar_objects")

				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("1")
				expect(c:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				expect(GryMod.ServerSettings.Find("gry_radar_objects") ~= nil).to.beTrue()
			end
		},
		{
			name = "the stock registry knows the vehicles (type 3, listed only once scanned) and the Combine mine (type 4, hostile, listed only once scanned); a seat is not one",
			func = function()
				local API = GryMod.API

				for _, class in ipairs({"prop_vehicle_jeep", "prop_vehicle_airboat", "prop_vehicle_apc", "prop_vehicle_crane"}) do
					local entry = API.GetTrackedByClass(class)

					expect(entry ~= nil).to.beTrue()
					expect(entry.type).to.equal(3)
					expect(entry.radar).to.equal("scan")
				end

				local mine = API.GetTrackedByClass("combine_mine")
				expect(mine ~= nil).to.beTrue()
				expect(mine.type).to.equal(4)
				expect(mine.radar).to.equal("scan")
				expect(isfunction(mine.relation)).to.beTrue()

				expect(API.GetTrackedByClass("prop_vehicle_prisoner_pod")).to.beNil()
				expect(API.GetTrackedByClass("prop_physics")).to.beNil()
			end
		},
		{
			name = "type 4 goes through the message: three bits for the icon, so that the mine's icon is not cut",
			func = function()
				local calls = {}
				local saved = {write = net.WriteUInt}

				local ok, err = pcall(function()
					net.WriteUInt = function(v, bits) calls[#calls + 1] = {v, bits} end
					S.Write({{id = 5, type = 4, sub = 2, x = 0, y = 0, z = 0, yaw = 0}})
				end)

				net.WriteUInt = saved.write

				if not ok then error(err, 0) end

				-- count, then id, type, sub...
				expect(calls[2][2]).to.equal(13)
				expect(calls[3][1]).to.equal(4)
				expect(calls[3][2]).to.equal(3)
			end
		},
		{
			name = "Step: a vehicle is not listed before it is scanned; scanned, it shows in the colour of its driver (nobody or a neutral: 0, a friend: blue, a hostile: red)",
			func = function()
				local st = {tagged = setmetatable({}, {__mode = "k"}), markers = setmetatable({}, {__mode = "k"})}
				local key = {}
				local d = {key = key, id = 700, class = "prop_vehicle_jeep", hostile = false, ally = false, state = NPC_STATE_NONE, enemyIsPlayer = false,
					health = 0, maxHealth = 0, x = 800, y = 0, z = 0, yaw = 0, type = 3, radar = "scan"}

				expect(#R.Step(Vector(0, 0, 0), {d}, st, 0, false)).to.equal(0)

				st.tagged[key] = true
				local list = R.Step(Vector(0, 0, 0), {d}, st, 0, false)
				expect(#list).to.equal(1)
				expect(list[1].type).to.equal(3)
				expect(list[1].sub).to.equal(0)

				d.ally = true
				list = R.Step(Vector(0, 0, 0), {d}, st, 0, false)
				expect(list[1].sub).to.equal(S.SUB_ALLY)

				d.ally, d.hostile = false, true
				list = R.Step(Vector(0, 0, 0), {d}, st, 0, false)
				expect(list[1].sub).to.equal(2)
			end
		},
		{
			name = "a real Buggy: Describe gives its icon and the rule 'only once scanned'; with nobody in it the relation is neutral",
			func = function()
				local jeep = spawnJeep()
				local d = R.Describe(jeep, ply())

				expect(d.type).to.equal(3)
				expect(d.radar).to.equal("scan")
				expect(d.hostile).to.beFalse()
				expect(d.ally).to.beFalse()
				expect(d.class).to.equal("prop_vehicle_jeep")
			end
		},
		{
			name = "a vehicle's heading is the way it FACES (measured: the Buggy and the airboat face along the entity's right, 90 degrees from its yaw), so the rectangle points the right way on the radar; a mine keeps its own yaw",
			func = function()
				local jeep = spawnJeep()
				jeep:SetAngles(Angle(0, 30, 0))

				local f = jeep:GetForward()
				local facing = math.deg(math.atan2(f.y, f.x))
				local d = R.Describe(jeep, ply())

				-- the facing is 120, not the 30 of the entity's own yaw
				expect(math.abs(math.AngleDifference(d.yaw, facing)) < 0.5).to.beTrue()
				expect(math.abs(math.AngleDifference(d.yaw, 120)) < 1).to.beTrue()

				local mine = spawnMine()
				mine:SetAngles(Angle(0, 30, 0))
				expect(math.abs(math.AngleDifference(R.Describe(mine, ply()).yaw, 30)) < 0.5).to.beTrue()
			end
		},
		{
			name = "the colour of a vehicle is its driver's: a friendly citizen at the wheel is blue, a Combine soldier red",
			func = function()
				local jeep = spawnJeep()
				local friend = spawnNPC("npc_citizen")
				local foe = spawnNPC("npc_combine_s")

				-- (the methods of a real entity cannot be replaced on the instance: the radar asks Radar.DriverOf)
				local realDriver = R.DriverOf
				local ok, err = pcall(function()
					R.DriverOf = function() return friend end
					local d = R.Describe(jeep, ply())
					expect(d.ally).to.beTrue()
					expect(d.hostile).to.beFalse()

					R.DriverOf = function() return foe end
					d = R.Describe(jeep, ply())
					expect(d.hostile).to.beTrue()
					expect(d.ally).to.beFalse()
				end)

				R.DriverOf = realDriver

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the binoculars' scan tags a vehicle in range, and not one out of range, a prop, the player's own vehicle, or with the switch off",
			func = function()
				local p = ply()
				local jeep = spawnJeep(300)
				local far = spawnJeep(300)
				far:SetPos(p:GetPos() + Vector(30000, 0, 40))
				local prop = remember(ents.Create("prop_physics"))
				prop:SetModel("models/props_c17/oildrum001.mdl")
				prop:SetPos(p:GetPos() + Vector(300, 200, 40))
				prop:Spawn()

				expect(R.Scan(p, jeep)).to.beTrue()
				expect(R.State(p).tagged[jeep]).to.beTrue()
				expect(R.Scan(p, far)).to.beFalse()
				expect(R.Scan(p, prop)).to.beFalse()

				-- the vehicle the player sits in is never a contact
				local own = spawnJeep(500)
				local realSits = R.Sits
				local ok, err = pcall(function()
					R.Sits = function(_, ent) return ent == own end
					expect(R.Scan(p, own)).to.beFalse()
				end)

				R.Sits = realSits

				if not ok then error(err, 0) end

				GetConVar("gry_radar_objects"):SetString("0")
				local other = spawnJeep(400)
				expect(R.Scan(p, other)).to.beFalse()
			end
		},
		{
			name = "the radar lists a vehicle only after the scan, with the icon of the rectangle, and drops it when it is gone; the player's own vehicle never shows",
			func = function()
				local p = ply()
				local jeep = spawnJeep(300)

				expect(contactOf(tick(), jeep)).to.beNil()

				expect(R.Scan(p, jeep)).to.beTrue()
				local c = contactOf(tick(), jeep)
				expect(c ~= nil).to.beTrue()
				expect(c.type).to.equal(3)
				expect(c.sub).to.equal(0)

				-- the one the player drives is not listed even if it was scanned
				local realSits = R.Sits
				local ok, err = pcall(function()
					R.Sits = function(_, ent) return ent == jeep end
					expect(contactOf(tick(), jeep)).to.beNil()
				end)

				R.Sits = realSits

				if not ok then error(err, 0) end

				-- gone (a removed entity lives to the end of the frame, and a run is one frame: it is sent far away instead)
				jeep:SetPos(Vector(0, 0, -30000))
				expect(contactOf(tick(), jeep)).to.beNil()
			end
		},
		{
			name = "a mine is hostile, and an ally once the player took it with the gravity gun and put it down (m_bPlacedByPlayer): blue on the radar",
			func = function()
				local p = ply()
				local mine = spawnMine(300)

				expect(GryMod.Friendly.Relation(p, mine)).to.equal("hostile")
				expect(R.Describe(mine, p).hostile).to.beTrue()

				mine:SetSaveValue("m_bPlacedByPlayer", true)
				expect(mine:GetInternalVariable("m_bPlacedByPlayer")).to.equal(true)
				expect(GryMod.Friendly.Relation(p, mine)).to.equal("ally")

				expect(R.Scan(p, mine)).to.beTrue()
				local c = contactOf(tick(), mine)
				expect(c ~= nil).to.beTrue()
				expect(c.type).to.equal(4)
				expect(c.sub).to.equal(S.SUB_ALLY)
			end
		},
		{
			name = "a Combine mine: scanned, it is on the radar with the type 4 icon in red; the switch off takes it (and the vehicles) off",
			func = function()
				local p = ply()
				local mine = spawnMine(300)
				local jeep = spawnJeep(400)

				expect(contactOf(tick(), mine)).to.beNil()
				expect(R.Scan(p, mine)).to.beTrue()
				expect(R.Scan(p, jeep)).to.beTrue()

				local list = tick()
				local m = contactOf(list, mine)
				expect(m ~= nil).to.beTrue()
				expect(m.type).to.equal(4)
				expect(m.sub).to.equal(2)
				expect(contactOf(list, jeep) ~= nil).to.beTrue()

				GetConVar("gry_radar_objects"):SetString("0")
				list = tick()
				expect(contactOf(list, mine)).to.beNil()
				expect(contactOf(list, jeep)).to.beNil()
			end
		}
	}
}
