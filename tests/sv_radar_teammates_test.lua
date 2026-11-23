-- Tests of the team mates on the radar (the original's icon type 7, server/sv_radar.lua: Radar.TeamsInUse, Radar.Mates and their place in the list of contacts the
-- server sends), GLuaTest format, server realm. Fake players are used: the rules only read Team, Alive, IsValid, EntIndex, GetPos and GetAngles.

local R -- GryMod.Radar, set in beforeAll

local TEAM_RED, TEAM_BLUE = 1, 2

local nextIndex = 0

-- a stand-in for a player of `team`, at x units ahead of the origin
local function fake(team, x, extra)
	nextIndex = nextIndex + 1
	local p = {index = nextIndex, team = team, alive = true, x = x or 0}

	for k, v in pairs(extra or {}) do
		p[k] = v
	end

	p.IsValid = function() return true end
	p.Team = function() return p.team end
	p.Alive = function() return p.alive end
	p.EntIndex = function() return p.index end
	p.GetPos = function() return Vector(p.x, 0, 0) end
	p.GetAngles = function() return Angle(0, 90, 0) end
	p.IsPlayer = function() return true end
	p.GetObserverMode = function() return p.observer or OBS_MODE_NONE end

	return p
end

return {
	groupName = "GryMod radar team mates (server)",
	beforeAll = function(state)
		R = GryMod.Radar
	end,
	beforeEach = function(state)
		state.value = GetConVar("gry_radar_teammates") and GetConVar("gry_radar_teammates"):GetString()
	end,
	afterEach = function(state)
		if state.value and GetConVar("gry_radar_teammates") then
			GetConVar("gry_radar_teammates"):SetString(state.value)
		end
	end,
	cases = {
		-- fails without the convar in sv_radar.lua
		{
			name = "the switch gry_radar_teammates exists, on by default",
			func = function(state)
				expect(GetConVar("gry_radar_teammates")).toNot.beNil()
				expect(GetConVar("gry_radar_teammates"):GetDefault()).to.equal("1")
			end
		},
		-- fails without TeamsInUse
		{
			name = "teams are in use when at least two real teams have a player: one team, or only the unassigned and spectator teams, is not a team game (Sandbox)",
			func = function(state)
				expect(R.TeamsInUse({fake(TEAM_RED), fake(TEAM_RED)})).to.beFalse()
				expect(R.TeamsInUse({fake(TEAM_UNASSIGNED), fake(TEAM_UNASSIGNED), fake(TEAM_SPECTATOR)})).to.beFalse()
				expect(R.TeamsInUse({})).to.beFalse()
				expect(R.TeamsInUse({fake(TEAM_RED), fake(TEAM_BLUE)})).to.beTrue()
				-- a team with players and one that has none: not in use
				expect(R.TeamsInUse({fake(TEAM_RED), fake(TEAM_UNASSIGNED)})).to.beFalse()
			end
		},
		-- fails without Mates
		{
			name = "the mates of a player are the OTHER living players of his team, as contacts of type 7 and subtype 0 at their place; the enemy team, the dead, the spectators and himself are not",
			func = function(state)
				local me = fake(TEAM_RED, 0)
				local mate = fake(TEAM_RED, 500)
				local enemy = fake(TEAM_BLUE, 100)
				local dead = fake(TEAM_RED, 200, {alive = false})
				local watching = fake(TEAM_RED, 300, {observer = OBS_MODE_CHASE})
				local mates = R.Mates(me, {me, mate, enemy, dead, watching})
				expect(#mates).to.equal(1)
				expect(mates[1].id).to.equal(mate.index)
				expect(mates[1].type).to.equal(7)
				expect(mates[1].sub).to.equal(0)
				expect(mates[1].x).to.equal(500)
				expect(mates[1].marker).to.beFalse()
				expect(mates[1].yaw).to.equal(90)
			end
		},
		{
			name = "no mates when the teams are not in use (Sandbox), and none when the switch is off",
			func = function(state)
				local me = fake(TEAM_RED)
				local friend = fake(TEAM_RED, 10)
				expect(#R.Mates(me, {me, friend})).to.equal(0) -- one team only

				local enemy = fake(TEAM_BLUE)
				expect(#R.Mates(me, {me, friend, enemy})).to.equal(1)
				GetConVar("gry_radar_teammates"):SetString("0")
				expect(#R.Mates(me, {me, friend, enemy})).to.equal(0)
			end
		},
		-- fails without AddMates
		{
			name = "the mates join the list of contacts and take their places before the others when the list is full (48): the nearest hostiles give way, never a mate",
			func = function(state)
				local S = GryMod.RadarShared
				local list = {}

				for i = 1, S.MAX_CONTACTS do
					list[i] = {id = 1000 + i, x = i, y = 0, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false}
				end

				local mates = {{id = 1, x = 0, y = 0, z = 0, yaw = 0, type = 7, sub = 0, marker = false, big = false}, {id = 2, x = 0, y = 0, z = 0, yaw = 0, type = 7, sub = 0, marker = false, big = false}}
				local joined = R.AddMates(list, mates)
				expect(#joined).to.equal(S.MAX_CONTACTS)
				expect(joined[S.MAX_CONTACTS].id).to.equal(2)
				expect(joined[S.MAX_CONTACTS - 1].id).to.equal(1)
				expect(joined[S.MAX_CONTACTS - 2].id).to.equal(1000 + S.MAX_CONTACTS - 2)
				-- nothing to add: the list is the same
				expect(R.AddMates({{id = 5}}, {})[1].id).to.equal(5)
			end
		}
	}
}
