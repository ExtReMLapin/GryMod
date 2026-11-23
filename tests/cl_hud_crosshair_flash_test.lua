-- Tests of the crosshair drawn from the original Scaleform movie (GryMod.FlashCrosshair), GLuaTest format, client
-- realm. Needs the converted movie lua/grymod/flash/hud_crosshair.lua. The rules are those of the movie's
-- ActionScript (setCrossHair, setRecoil, setUsable, indicateHit, setDamageDirection), see research-ui/NOTES.md.

local function newCrosshair()
	return GryMod.FlashCrosshair.New(GryMod.Flash.Load("hud_crosshair"))
end

local function run(c, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		c:Update(1 / 30)
	end
end

local function near(a, b)
	return math.abs(a - b) < 0.001
end

-- the x or y of the placement of the clip at this path of the current crosshair
local function posOf(c, path)
	local clip = c.current:Find(path)

	return clip.entry.m[5], clip.entry.m[6]
end

-- Runs fn with the replicated variable sv_ladder_useonly set to `value` ("0" or "1"), and puts the game's GetConVar back whatever happens: the stock ladder
-- entry of the usable registry reads it at each question, and the real value (0) means "no prompt: walking into a ladder climbs it".
local function withLadderUseOnly(value, fn)
	local saved = GetConVar

	GetConVar = function(name)
		if name == "sv_ladder_useonly" then
			return {GetBool = function() return value == "1" end, GetInt = function() return tonumber(value) end}
		end

		return saved(name)
	end

	local ok, err = pcall(fn)

	GetConVar = saved

	if not ok then
		error(err, 0)
	end
end

local function scaleOf(c, path)
	local clip = c.current:Find(path)
	local m = clip.entry.m

	return math.sqrt(m[1] * m[1] + m[2] * m[2]) * 100
end

return {
	groupName = "GryMod crosshair (Flash)",
	beforeEach = function(state)
		-- the player's own saved settings must not leak into these tests (they are saved in cfg/client.vdf, which every client reads):
		-- no own zoom key, so that the tests see the game's zoom
		local key = GetConVar("gry_zoom_key")
		state.savedZoomKey = key and key:GetString()

		if key then
			key:SetString("0")
		end
	end,
	afterEach = function(state)
		for _, class in ipairs({"doc_test_nocross_gun", "doc_test_cross_gun"}) do
			GryMod.API.UnregisterWeapon(class)
		end

		local key = GetConVar("gry_zoom_key")

		if key and state.savedZoomKey then
			key:SetString(state.savedZoomKey)
		end
	end,
	cases = {
		{
			name = "a missing movie gives no crosshair instead of an error",
			func = function(state)
				expect(GryMod.FlashCrosshair.New(nil)).to.equal(nil)
			end
		},
		{
			name = "the crosshair starts on the original's default, number 10",
			func = function(state)
				local c = newCrosshair()
				expect(c.index).to.equal(10)
				expect(c.current).to.exist()
				expect(c.current:Find("Line")).to.exist()
				expect(c.current:Find("Line2")).to.exist()
			end
		},
		{
			name = "choosing a number shows that crosshair, 0 shows none, an unknown number changes nothing",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				expect(c.index).to.equal(1)
				expect(c.current:Find("LineL")).to.exist()
				c:SetCrosshair(4)
				expect(c.current:Find("LineU")).to.exist()
				c:SetCrosshair(0)
				expect(c.index).to.equal(0)
				expect(c.current).to.beNil()
				expect(c.root:Child("Root"):CurrentLabel()).to.equal("empty")
				c:SetCrosshair(99)
				expect(c.index).to.equal(0)
				c:SetCrosshair(nil)
				expect(c.index).to.equal(0)
				c:SetCrosshair(3)
				expect(c.index).to.equal(3)
			end
		},
		{
			name = "the recoil spreads the four lines of crosshair 1: 9.5 plus 42 a unit",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetRecoil(0)
				expect(near(posOf(c, "LineL"), -9.5)).to.beTrue()
				expect(near(posOf(c, "LineR"), 9.5)).to.beTrue()
				local _, y = posOf(c, "LineD")
				expect(near(y, 9.5)).to.beTrue()
				c:SetRecoil(0.5)
				expect(near(posOf(c, "LineL"), -(9.5 + 21))).to.beTrue()
				expect(near(posOf(c, "LineR"), 9.5 + 21)).to.beTrue()
			end
		},
		{
			name = "the recoil of the other crosshairs follows each one's own formula",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(2)
				c:SetRecoil(0.5)
				expect(near(scaleOf(c, "Line"), 200)).to.beTrue()
				c:SetCrosshair(3)
				c:SetRecoil(0.5)
				local x, y = posOf(c, "LineTR")
				expect(near(x, 11 + 21)).to.beTrue()
				expect(near(y, -11 - 21)).to.beTrue()
				c:SetCrosshair(4)
				c:SetRecoil(0.5)
				local _, up = posOf(c, "LineU")
				expect(near(up, -(8 + 26))).to.beTrue()
				c:SetCrosshair(5)
				c:SetRecoil(0.5)
				expect(near(scaleOf(c, "Line2"), 50 + 2.5 * (20 + 16))).to.beTrue()
				c:SetCrosshair(6)
				c:SetRecoil(0.5)
				local bx, by = posOf(c, "LineBL")
				expect(near(bx, -(10 + 24))).to.beTrue()
				expect(near(by, 10 + 24)).to.beTrue()
				c:SetCrosshair(7)
				c:SetRecoil(0.5)
				expect(near(posOf(c, "LineR"), 9.5 + 28)).to.beTrue()
			end
		},
		{
			name = "crosshairs 11, 12 and 13 take their spread in pixels, never under their own minimum",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(11)
				c:SetRecoil(30)
				local x, y = posOf(c, "Lines.Colorset.Line1")
				expect(near(x, -30)).to.beTrue()
				expect(near(y, -25)).to.beTrue()
				c:SetRecoil(3)
				x = posOf(c, "Lines.Colorset.Line2")
				expect(near(x, 22)).to.beTrue()
				c:SetCrosshair(12)
				c:SetRecoil(1)
				local _, top = posOf(c, "Lines.Colorset.LineTop")
				expect(near(top, -10)).to.beTrue()
				c:SetCrosshair(13)
				c:SetRecoil(40)
				expect(near(posOf(c, "Lines.Colorset.Line2"), 40)).to.beTrue()
			end
		},
		{
			name = "the recoil is applied again when the crosshair rebuilds its clips, and after a change of number",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetRecoil(0.5)
				c:SetUsable(1)
				run(c, 1)
				expect(near(posOf(c, "LineR"), 9.5 + 21)).to.beTrue()
				c:SetCrosshair(4)
				expect(near(select(1, posOf(c, "LineR")), 8 + 26)).to.beTrue()
			end
		},
		{
			name = "a hit plays the hit animation of the lines of the shown crosshair",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:Hit()
				expect(c.current:Find("LineL"):CurrentLabel()).to.equal("hit")
				expect(c.current:Find("Pointer"):CurrentLabel()).to.equal("hit")
				c:SetCrosshair(11)
				c:Hit()
				expect(c.current:Find("Lines.Colorset.Line3"):CurrentLabel()).to.equal("hit")
				c:SetCrosshair(0)
				c:Hit() -- nothing shown: no error
			end
		},
		{
			name = "usable: 1 opens the crosshair on frame 2, 0 closes it by the way back, 2 plays the second animation",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetUsable(1)
				expect(c.current:CurrentFrame()).to.equal(2)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(12)
				c:SetCrosshair(3)
				expect(c.current:CurrentFrame()).to.equal(1)
				c:SetUsable(2)
				expect(c.current:CurrentFrame()).to.equal(14)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(20)
			end
		},
		{
			name = "usable keeps the same mode as it was, in the middle of an animation, the original's way",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(1)
				c:SetUsable(1)
				c.current:GotoAndStop(4)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(10)
				c.current:GotoAndStop(7)
				c:SetUsable(0)
				expect(c.current:CurrentFrame()).to.equal(8)
			end
		},
		{
			name = "the damage arcs: each plays from its own start and a clear stops all four",
			func = function(state)
				local c = newCrosshair()
				local dd = c.root:Child("DamageDirection")
				c:SetDamageDirection(2)
				expect(dd:Child("Damage2"):CurrentLabel()).to.equal("play")
				expect(dd:Child("Damage1"):CurrentLabel()).to.equal("stop")
				c:SetDamageDirection(4)
				expect(dd:Child("Damage4"):CurrentLabel()).to.equal("play")
				c:ClearDamageDirection()

				for i = 1, 4 do
					expect(dd:Child("Damage" .. i):CurrentLabel()).to.equal("stop")
				end

				c:SetDamageDirection(7) -- not an arc: nothing happens, no error
			end
		},
		{
			name = "an arc plays for 1.2 seconds and goes back to rest on its own",
			func = function(state)
				local c = newCrosshair()
				c:SetDamageDirection(1)
				run(c, 0.5)
				expect(c.root:Child("DamageDirection"):Child("Damage1"):CurrentLabel()).to.equal(nil)
				run(c, 1.5)
				expect(c.root:Child("DamageDirection"):Child("Damage1"):CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "a hit on the player gives the arcs of the original's rule: 0.35 of each world axis, two arcs for a diagonal, all four for none",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function arcs(shooter)
					local list = C.ArcsFor(Vector(0, 0, 0), shooter)
					table.sort(list)

					return table.concat(list, ",")
				end

				-- the world is turned so that the +X of the game is the original's north (arc 1 is the north-south axis)
				expect(arcs(Vector(-100, 0, 0))).to.equal("1") -- the shooter is behind the north-facing player: south
				expect(arcs(Vector(100, 0, 0))).to.equal("3")
				expect(arcs(Vector(0, -100, 0))).to.equal("4") -- east of the player: the original's x is -Y here
				expect(arcs(Vector(0, 100, 0))).to.equal("2")
				expect(arcs(Vector(-100, -100, 0))).to.equal("1,4")
				expect(arcs(Vector(100, 100, 0))).to.equal("2,3")
				-- under 0.35 of an axis it is a single arc: 20 degrees off the axis
				expect(arcs(Vector(-100, -30, 0))).to.equal("1")
				expect(arcs(Vector(0, 0, 0))).to.equal("1,2,3,4")
				expect(arcs(Vector(0, 0, 500))).to.equal("1,2,3,4") -- straight above: no horizontal offset
			end
		},
		{
			name = "the arcs turn with the view: the player's yaw plus 180 degrees, kept inside a turn",
			func = function(state)
				local C = GryMod.FlashCrosshair
				expect(C.ArcRotation(0)).to.equal(180)
				expect(C.ArcRotation(90)).to.equal(270)
				expect(C.ArcRotation(-90)).to.equal(90)
				expect(C.ArcRotation(180)).to.equal(0)
				expect(C.ArcRotation(-180)).to.equal(0)
			end
		},
		{
			name = "a damage report starts its arcs and turns them with the view for 2 seconds, then leaves them alone",
			func = function(state)
				local c = newCrosshair()
				local dd = c.root:Child("DamageDirection")
				c:OnDamage(Vector(0, 0, 0), Vector(-100, 0, 0), 0, 10)
				expect(dd:Child("Damage1"):CurrentLabel()).to.equal("play")
				c:SetViewYaw(90, 10.5)
				expect(near(dd.entry.m[1], math.cos(math.rad(270)))).to.beTrue()
				c:SetViewYaw(0, 11.9)
				expect(near(dd.entry.m[1], math.cos(math.rad(180)))).to.beTrue()
				c:SetViewYaw(90, 12.5) -- past 2 seconds: no more updates
				expect(near(dd.entry.m[1], math.cos(math.rad(180)))).to.beTrue()
			end
		},
		{
			name = "the crosshair number: the chosen style, none for a weapon that hides it or when zooming or without a weapon",
			func = function(state)
				local C = GryMod.FlashCrosshair
				expect(C.IndexFor(6, "weapon_smg1", true, false)).to.equal(6)
				expect(C.IndexFor(3, "weapon_pistol", true, false)).to.equal(3)
				expect(C.IndexFor(6, "weapon_fists", true, false)).to.equal(0)
				expect(C.IndexFor(6, "weapon_rpg", true, false)).to.equal(0)
				expect(C.IndexFor(6, "weapon_smg1", false, false)).to.equal(0) -- the weapon draws its own
				expect(C.IndexFor(6, "weapon_smg1", true, true)).to.equal(0) -- zoomed
				expect(C.IndexFor(6, nil, true, false)).to.equal(0) -- no weapon
				expect(C.IndexFor(99, "weapon_smg1", true, false)).to.equal(C.DEFAULT_STYLE) -- not a style
				expect(C.IndexFor(0, "weapon_smg1", true, false)).to.equal(C.DEFAULT_STYLE)
			end
		},
		{
			name = "a third-party weapon registered through the API with crosshair = false shows no crosshair; one with crosshair = true or no field does; no private list of classes",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local API = GryMod.API

				-- (rouge before the migration: the private list knew only the fists and the RPG)
				expect(C.IndexFor(6, "doc_test_nocross_gun", true, false)).to.equal(6)

				expect((API.RegisterWeapon("doc_test_nocross_gun", {fire = "auto", crosshair = false}))).to.beTrue()
				expect((API.RegisterWeapon("doc_test_cross_gun", {fire = "auto", crosshair = true}))).to.beTrue()

				expect(C.IndexFor(6, "doc_test_nocross_gun", true, false)).to.equal(0)
				expect(C.IndexFor(6, "doc_test_cross_gun", true, false)).to.equal(6)
				expect(C.IndexFor(6, "doc_test_unregistered_gun", true, false)).to.equal(6)

				-- the stock fists and RPG are data of the same registry
				expect(API.WeaponValue("weapon_fists", "crosshair", true)).to.beFalse()
				expect(API.WeaponValue("weapon_rpg", "crosshair", true)).to.beFalse()

				-- unregistered: the crosshair is back
				API.UnregisterWeapon("doc_test_nocross_gun")
				expect(C.IndexFor(6, "doc_test_nocross_gun", true, false)).to.equal(6)
			end
		},
		{
			-- Fails without the weapon style in Cross.IndexFor: a number in the registry's `crosshair` was never read (the user's style won)
			name = "a weapon that declares a crosshair number (11 to 13 have no stock weapon) shows that one, unless the player turned the weapon styles off; hiding and zoom still win",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local API = GryMod.API
				expect((API.RegisterWeapon("doc_test_cross_gun", {fire = "auto", crosshair = 12}))).to.beTrue()

				expect(C.IndexFor(6, "doc_test_cross_gun", true, false)).to.equal(12)
				expect(C.IndexFor(6, "doc_test_cross_gun", true, false, true)).to.equal(12)
				-- the player does not want the weapons to choose: his own style
				expect(C.IndexFor(6, "doc_test_cross_gun", true, false, false)).to.equal(6)
				-- the weapon that draws its own, the zoom and no weapon still give none
				expect(C.IndexFor(6, "doc_test_cross_gun", false, false)).to.equal(0)
				expect(C.IndexFor(6, "doc_test_cross_gun", true, true)).to.equal(0)
				expect(C.IndexFor(6, nil, true, false)).to.equal(0)

				-- the three that the original forces by weapon
				for _, style in ipairs({11, 12, 13}) do
					API.RegisterWeapon("doc_test_cross_gun", {crosshair = style})
					expect(C.IndexFor(3, "doc_test_cross_gun", true, false)).to.equal(style)
				end

				-- `true` keeps the player's style
				API.RegisterWeapon("doc_test_cross_gun", {crosshair = true})
				expect(C.IndexFor(3, "doc_test_cross_gun", true, false)).to.equal(3)
			end
		},
		{
			name = "gry_hud_crosshair_weapon: saved, on by default, with a check box in the HUD menu",
			func = function(state)
				local convar = GetConVar("gry_hud_crosshair_weapon")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				expect(GryMod.FlashCrosshair.WeaponStyles()).to.equal(convar:GetBool())
				local saved = convar:GetString()
				convar:SetString("0")
				local ok, err = pcall(function() expect(GryMod.FlashCrosshair.WeaponStyles()).to.beFalse() end)
				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the spread grows with speed, in the air and while firing, and shrinks when crouching; it eases at 20 a second",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local still = C.SpreadTarget(0, true, false, 0)
				local walking = C.SpreadTarget(0.5, true, false, 0)
				local running = C.SpreadTarget(1, true, false, 0)
				expect(still).to.equal(0)
				expect(walking > still and running > walking).to.beTrue()
				expect(C.SpreadTarget(0, false, false, 0) > still).to.beTrue()
				expect(C.SpreadTarget(1, true, true, 0) < running).to.beTrue()
				expect(C.SpreadTarget(0, true, false, 0.5) > still).to.beTrue()
				expect(C.SpreadTarget(1, false, false, 1)).to.equal(1) -- never over 1
				-- easing: a frame of 1/30 s covers most of the way, a long frame lands on the target
				local v = C.Ease(0, 1, 1 / 30)
				expect(v > 0.4 and v < 0.6).to.beTrue()
				expect(near(C.Ease(0, 1, 5), 1)).to.beTrue()
				expect(C.Ease(0.7, 0.7, 0.1)).to.equal(0.7)
			end
		},
		{
			name = "usable: what needs the key (a button, a door, a ladder, a prop when the group is on) can be used; what is taken by walking over (a weapon, an item) and a wall cannot",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function fake(class, weapon)
					return {IsValid = function() return true end, GetClass = function() return class end, IsWeapon = function() return weapon or false end}
				end

				local saved = GetConVar("gry_usehint_props"):GetString()
				local ok, err = pcall(function()
					GetConVar("gry_usehint_props"):SetString("1")

					local player = {HasWeapon = function(_, class) return class == "weapon_pistol" end}

					-- touch pickups: no key, no prompt (the weapon the player has too)
					expect(C.UsableFor(fake("weapon_smg1", true), player)).to.equal(0)
					expect(C.UsableFor(fake("weapon_pistol", true), player)).to.equal(0)
					expect(C.UsableFor(fake("item_healthkit"), player)).to.equal(0)
					expect(C.UsableFor(fake("item_battery"), player)).to.equal(0)

					expect(C.UsableFor(fake("func_button"), player)).to.equal(1)
					expect(C.UsableFor(fake("prop_door_rotating"), player)).to.equal(1)
					expect(C.UsableFor(fake("prop_physics"), player)).to.equal(1)
					-- the ladder is climbed by walking into it (sv_ladder_useonly 0, the game's default): no prompt; with 1 there is
					expect(C.UsableFor(fake("func_useableladder"), player)).to.equal(0)
					withLadderUseOnly("1", function() expect(C.UsableFor(fake("func_useableladder"), player)).to.equal(1) end)
					expect(C.UsableFor(fake("item_healthcharger"), player)).to.equal(1)
					expect(C.UsableFor(fake("func_brush"), player)).to.equal(0)
					expect(C.UsableFor(nil, player)).to.equal(0)
					expect(C.UsableFor({IsValid = function() return false end}, player)).to.equal(0)
				end)

				GetConVar("gry_usehint_props"):SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without the group switch (gry_usehint_props, off by default) in UsableFor
			name = "the props are a group the player switches (gry_usehint_props, off by default): off, a liftable prop is not usable and the crosshair stays closed; the other groups stay on",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function fake(class)
					return {IsValid = function() return true end, GetClass = function() return class end, IsWeapon = function() return false end}
				end

				local convar = GetConVar("gry_usehint_props")

				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0")

				local saved = convar:GetString()
				local ok, err = pcall(function()
					convar:SetString("0")
					expect(C.UsableFor(fake("prop_physics"), {})).to.equal(0)
					expect(C.UsableFor(fake("func_physbox"), {})).to.equal(0)
					expect(C.UsableFor(fake("npc_turret_floor"), {})).to.equal(0)
					expect(C.UsableFor(fake("func_button"), {})).to.equal(1)
					expect(C.UsableFor(fake("npc_grenade_frag"), {})).to.equal(1)
					withLadderUseOnly("1", function() expect(C.UsableFor(fake("func_useableladder"), {})).to.equal(1) end)

					convar:SetString("1")
					expect(C.UsableFor(fake("prop_physics"), {})).to.equal(1)

					-- a group nobody made a switch for is on
					expect(C.GroupEnabled("no_such_group_switch")).to.beTrue()
					expect(C.GroupEnabled(nil)).to.beTrue()
				end)

				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without the busy check in UsableFor: a ladder the player is climbing kept its CLIMB
			name = "a thing the registry says is busy (a ladder while the player climbs it) is not usable",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local ladder = {IsValid = function() return true end, GetClass = function() return "func_useableladder" end, IsWeapon = function() return false end}

				withLadderUseOnly("1", function()
					expect(C.UsableFor(ladder, {GetMoveType = function() return MOVETYPE_WALK end})).to.equal(1)
					expect(C.UsableFor(ladder, {GetMoveType = function() return MOVETYPE_LADDER end})).to.equal(0)
				end)
			end
		},
		{
			-- fails without Cross.NonSolidAimed: a ladder is not solid, so the eye trace never hits it and the prompt CLIMB never showed
			name = "usable, non-solid things (a ladder): found by the aim ray against their box, only within reach, not behind a wall, only for the classes the registry marks nonsolid",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local savedFind = ents.FindByClass

				-- a ladder box in front of the player: x -16..16, y -40..-8 of its origin (0, 0, 0), z 0..160 (the stock ladder's shape)
				local ladder = {
					IsValid = function() return true end, GetClass = function() return "func_useableladder" end,
					GetPos = function() return Vector(0, 0, 0) end, GetAngles = function() return Angle(0, 0, 0) end,
					OBBMins = function() return Vector(-16, -40, 0) end, OBBMaxs = function() return Vector(16, -8, 160) end,
					WorldSpaceCenter = function() return Vector(0, -24, 80) end
				}
				local other = {
					IsValid = function() return true end, GetClass = function() return "func_brush" end,
					GetPos = function() return Vector(0, 0, 0) end, GetAngles = function() return Angle(0, 0, 0) end,
					OBBMins = function() return Vector(-16, -40, 0) end, OBBMaxs = function() return Vector(16, -8, 160) end,
					WorldSpaceCenter = function() return Vector(0, -24, 80) end
				}
				local function player(eye, aim)
					return {EyePos = function() return eye end, GetAimVector = function() return aim end}
				end

				local ok, err = pcall(withLadderUseOnly, "1", function()
					ents.FindByClass = function(class)
						if class == "func_useableladder" then return {ladder} end
						if class == "func_brush" then return {other} end

						return {}
					end

					expect(isfunction(C.NonSolidAimed)).to.beTrue()

					-- looking at it from 50 units away, level with its middle: found
					expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(0, -1, 0)), 110) == ladder).to.beTrue()
					-- looking beside it: nothing
					expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(1, 0, 0)), 110)).to.beNil()
					-- too far (the reach is the use range)
					expect(C.NonSolidAimed(player(Vector(0, 300, 80), Vector(0, -1, 0)), 110)).to.beNil()
					-- a wall nearer than the ladder (the trace hit it at 30 units): the ladder is behind it
					expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(0, -1, 0)), 30)).to.beNil()
					-- a class the registry does not mark nonsolid is never looked for
					expect(GryMod.API.UsableNonSolidClasses()[1] ~= "func_brush").to.beTrue()
					-- a wheel (momentary_rot_button) is not solid either and the client calls it "class C_BaseToggle": found through the real class the server gave, and
					-- only when its flags say the key turns it (1024); a toggle that is no usable thing (a func_movelinear) is skipped, never returned
					local function toggle(class, flags)
						return {
							IsValid = function() return true end, GetClass = function() return "class C_BaseToggle" end, GetSpawnFlags = function() return flags end,
							GetPos = function() return Vector(0, 0, 0) end, GetAngles = function() return Angle(0, 0, 0) end,
							OBBMins = function() return Vector(-16, -40, 0) end, OBBMaxs = function() return Vector(16, -8, 160) end,
							EntIndex = function() return 9000 end, realClass = class
						}
					end

					local wheel, mover = toggle("momentary_rot_button", 1153), toggle("func_movelinear", 1153)
					local listed, ladders = {wheel}, {}
					local savedResolver = GryMod.API.UsableClassResolver

					GryMod.API.UsableClassResolver = function(ent) return ent.realClass end
					ents.FindByClass = function(class)
						if class == "class C_BaseToggle" then return listed end
						if class == "func_useableladder" then return ladders end

						return {}
						end

						local pok, perr = pcall(function()
						expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(0, -1, 0)), 110) == wheel).to.beTrue()
						-- the flags say the key does not turn it
						wheel.GetSpawnFlags = function() return 65 end
						expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(0, -1, 0)), 110)).to.beNil()
						-- a toggle that is not a usable thing is never returned, and does not hide the ladder behind it in the list
						listed, ladders = {mover}, {ladder}
						expect(C.NonSolidAimed(player(Vector(0, 50, 80), Vector(0, -1, 0)), 110) == ladder).to.beTrue()
						end)

						listed, ladders = {}, {ladder}

					GryMod.API.UsableClassResolver = savedResolver

					if not pok then
						error(perr, 0)
					end

					-- the ladder's own range is 64 units, not the 110 the scan may look: 82 units from its box is out of the key's reach
					expect(C.NonSolidAimed(player(Vector(0, 84, 80), Vector(0, -1, 0)), 110)).to.beNil()
					expect(C.NonSolidAimed(player(Vector(0, 60, 80), Vector(0, -1, 0)), 110) == ladder).to.beTrue()
				end)

				ents.FindByClass = savedFind

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without the distance test of UsableFor: the HUD tested 110 units, the key reaches 80
			name = "a thing is usable only within the reach of the key: 80 units, an entry's own range (the ladder 64) when it has one; no distance given means no test",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function fake(class, flags)
					return {IsValid = function() return true end, GetClass = function() return class end, IsWeapon = function() return false end,
						GetSpawnFlags = function() return flags or 0 end}
				end

				expect(isfunction(GryMod.API.UsableMaxRange)).to.beTrue()
				expect(C.UsableFor(fake("item_ammo_crate"), {}, 79)).to.equal(1)
				expect(C.UsableFor(fake("item_ammo_crate"), {}, 80)).to.equal(1)
				expect(C.UsableFor(fake("item_ammo_crate"), {}, 81)).to.equal(0)
				expect(C.UsableFor(fake("item_ammo_crate"), {}, 109)).to.equal(0)
				expect(C.UsableFor(fake("item_ammo_crate"), {})).to.equal(1)
				expect(C.UsableFor(fake("prop_door_rotating"), {}, 100)).to.equal(0)

				withLadderUseOnly("1", function()
					expect(C.UsableFor(fake("func_useableladder"), {}, 63)).to.equal(1)
					expect(C.UsableFor(fake("func_useableladder"), {}, 70)).to.equal(0)
				end)

				-- how far the scan looks is what the registry says (the greatest range, 80 for the stock entries)
				expect(C.UseTraceLength()).to.equal(GryMod.API.UsableMaxRange())
			end
		},
		{
			-- fails without the spawnflags rule being applied by the crosshair's own test
			name = "the crosshair's test follows the spawnflags: a door that ignores +use, a touch-only button, a func_door without Use opens give no prompt",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function fake(class, flags)
					return {IsValid = function() return true end, GetClass = function() return class end, IsWeapon = function() return false end,
						GetSpawnFlags = function() return flags end}
				end

				expect(C.UsableFor(fake("prop_door_rotating", 34817), {})).to.equal(0)
				expect(C.UsableFor(fake("prop_door_rotating", 8192), {})).to.equal(1)
				expect(C.UsableFor(fake("func_door", 0), {})).to.equal(0)
				expect(C.UsableFor(fake("func_door", 2312), {})).to.equal(1)
				expect(C.UsableFor(fake("func_button", 513), {})).to.equal(0)
				expect(C.UsableFor(fake("func_button", 1025), {})).to.equal(1)
				expect(C.UsableFor(fake("func_tank", 5120), {})).to.equal(0)
				expect(C.UsableFor(fake("func_tank", 1312), {})).to.equal(1)
			end
		},
		{
			-- fails without the mass the server tells: the client has no physics object for a prop, so a 90 kg drum was offered "PICK UP"
			name = "a prop is offered for lifting only when the server says its mass is 35 kg or less: unknown means no prompt (and one question), heavy means none",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local savedAsk = C.AskMass
				local asked = {}
				local function prop(index, size)
					return {
						IsValid = function() return true end, EntIndex = function() return index end,
						OBBMins = function() return Vector(0, 0, 0) end, OBBMaxs = function() return size or Vector(30, 30, 45) end,
						GetPhysicsObject = function() return NULL end
					}
				end

				local ok, err = pcall(function()
					C.AskMass = function(index) asked[#asked + 1] = index end
					C.ForgetMasses()

					expect(isfunction(C.OnMassAnswer)).to.beTrue()

					-- unknown: refused, the server is asked, and not again at once
					expect(C.Grabbable(prop(701), 10)).to.beFalse()
					expect(C.Grabbable(prop(701), 10.1)).to.beFalse()
					expect(#asked).to.equal(1)
					expect(asked[1]).to.equal(701)

					-- the server says 30 kg: a light prop
					C.OnMassAnswer(701, 30, 10.2)
					expect(C.Grabbable(prop(701), 10.3)).to.beTrue()

					-- the server says 90 kg: too heavy, whatever the size
					C.OnMassAnswer(702, 90, 10.2)
					expect(C.Grabbable(prop(702), 10.3)).to.beFalse()

					-- exactly 35 is still liftable (the game's rule is "more than 35 refuses")
					C.OnMassAnswer(703, 35, 10.2)
					expect(C.Grabbable(prop(703), 10.3)).to.beTrue()

					-- too big whatever the mass
					C.OnMassAnswer(704, 5, 10.2)
					expect(C.Grabbable(prop(704, Vector(200, 20, 20)), 10.3)).to.beFalse()

					-- an answer is asked again after a few seconds, and is trusted meanwhile
					asked = {}
					expect(C.Grabbable(prop(701), 11)).to.beTrue()
					expect(#asked).to.equal(0)
					expect(C.Grabbable(prop(701), 14)).to.beTrue() -- the old answer still counts while the new one is on its way
					expect(#asked).to.equal(1)
				end)

				C.AskMass = savedAsk
				C.ForgetMasses()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "friendly: a player of the same team (when there are teams), an NPC only when the server confirmed it likes the player (never by its class), never the player itself",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local me = {Team = function() return 1 end, IsPlayer = function() return true end}
				local function fake(class, player, team)
					return {
						IsValid = function() return true end, GetClass = function() return class end,
						IsPlayer = function() return player or false end, IsNPC = function() return not player end,
						Team = function() return team or 1001 end
					}
				end

				expect(C.IsFriendly(fake("player", true, 1), me)).to.beTrue()
				expect(C.IsFriendly(fake("player", true, 2), me)).to.beFalse()
				expect(C.IsFriendly(fake("player", true, 1001), {Team = function() return 1001 end})).to.beFalse() -- no teams: nobody is friendly
				expect(C.IsFriendly(fake("player", true, 1), me, false)).to.beTrue() -- a player is decided by its team, not by the server's answer
				-- an NPC: the server's answer decides, the class does not
				expect(C.IsFriendly(fake("npc_citizen"), me, true)).to.beTrue()
				expect(C.IsFriendly(fake("npc_zombie"), me, true)).to.beTrue() -- made friendly by something else
				expect(C.IsFriendly(fake("npc_citizen"), me, false)).to.beFalse() -- the Enemy Rebel of the NPC menu
				expect(C.IsFriendly(fake("npc_citizen"), me, nil)).to.beFalse() -- not answered yet: no cross
				expect(C.IsFriendly(fake("npc_citizen"), me)).to.beFalse()
				expect(C.IsFriendly(fake("npc_alyx"), me)).to.beFalse()
				expect(C.IsFriendly(fake("npc_combine_s"), me, false)).to.beFalse()
				expect(C.IsFriendly(nil, me, true)).to.beFalse()
			end
		},
		{
			name = "the relation of an NPC is asked to the server once, kept for a second, asked again after, and an answer too old is not trusted",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local npc = {IsValid = function() return true end, EntIndex = function() return 77 end}
				local realAsk, asked = C.AskServer, {}
				C.AskServer = function(index) asked[#asked + 1] = index end
				C.ForgetRelations()
				local ok, err = pcall(function()
					local r0 = C.Relation(npc, 10)
					assert(r0 == nil, "unknown before the answer")
					assert(#asked == 1 and asked[1] == 77, "asked once")
					C.Relation(npc, 10.5)
					assert(#asked == 1, "not asked again within a second")
					C.OnAnswer(77, true, 10.6)
					assert(C.Relation(npc, 10.7) == true, "answered friendly")
					assert(#asked == 1, "an answer is kept")
					-- after a second it is asked again, the old answer still holds until the new one comes
					assert(C.Relation(npc, 11.7) == true, "the old answer holds while the new one is on its way")
					assert(#asked == 2, "asked again after a second")
					C.OnAnswer(77, false, 11.8)
					assert(C.Relation(npc, 11.9) == false, "the NPC turned hostile")
					-- no answer for more than two seconds: not trusted any more
					C.OnAnswer(77, true, 12)
					assert(C.Relation(npc, 14.5) == nil, "an answer older than two seconds is dropped")
				end)
				C.AskServer = realAsk
				C.ForgetRelations()
				expect(err).to.beNil()
				expect(ok).to.beTrue()
			end
		},
		{
			name = "the questions to the server are spaced by a fifth of a second, whatever NPC the player sweeps over",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function npc(i)
					return {IsValid = function() return true end, EntIndex = function() return i end}
				end

				local realAsk, asked = C.AskServer, {}
				C.AskServer = function(index) asked[#asked + 1] = index end
				C.ForgetRelations()
				local ok, err = pcall(function()
					for i = 1, 10 do
						C.Relation(npc(i), 50 + i * 0.1) -- ten different NPCs in a second
					end

					assert(#asked <= 5, "at most 5 questions a second, asked " .. #asked)
					assert(#asked >= 4, "but the sweep is served, asked " .. #asked)
				end)
				C.AskServer = realAsk
				C.ForgetRelations()
				expect(err).to.beNil()
				expect(ok).to.beTrue()
			end
		},
		{
			name = "in the game: the crosshair is drawn every frame, the vanilla one is hidden while ours is on, and shown again when it is off",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local hud = GetConVar("gry_hud"):GetString()
				local option = GetConVar("gry_hud_crosshair")
				GetConVar("gry_hud"):SetString("1")
				option:SetString("1")
				local realDraw, drawn = GryMod.Flash.Draw, 0
				GryMod.Flash.Draw = function() drawn = drawn + 1 end
				C.Reset()
				C.Paint()
				C.Paint()
				local hider = hook.GetTable().HUDShouldDraw["GRYCROSSHAIRHIDE"]
				local hidden = hider and hider("CHudCrosshair")
				local other = hider and hider("CHudHealth")
				option:SetString("0")
				local shownAgain = hider and hider("CHudCrosshair")
				local drawnOff = drawn
				C.Paint()
				local stillOff = drawn == drawnOff
				GryMod.Flash.Draw = realDraw
				option:SetString("1")
				GetConVar("gry_hud"):SetString(hud)
				C.Reset()

				expect(drawnOff >= 2).to.beTrue()
				expect(stillOff).to.beTrue()
				expect(hidden).to.equal(false)
				expect(other).to.beNil()
				expect(shownAgain).to.beNil()
			end
		},
		{
			name = "the server's hit message blinks the crosshair and its damage message starts the arcs, each only while its switch is on",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local realDraw = GryMod.Flash.Draw
				GryMod.Flash.Draw = function() end
				GetConVar("gry_hud"):SetString("1")
				C.Reset()
				C.Paint()
				local inst = C.Current()
				expect(inst).to.exist()
				inst:SetCrosshair(1)

				local function receive(name, ...)
					local receiver = net.Receivers[name]
					expect(receiver).to.exist()
					receiver(0, ply, ...)
				end

				local hit, damage = GetConVar("gry_hud_hit"), GetConVar("gry_hud_damage")
				hit:SetString("0")
				receive("gry_hit")
				local offBlink = inst.current:Find("LineL"):CurrentLabel()
				hit:SetString("1")
				receive("gry_hit")
				local onBlink = inst.current:Find("LineL"):CurrentLabel()

				local dd = inst.root:Child("DamageDirection")
				damage:SetString("0")
				C.NotifyDamage(Vector(-1, 0, 0))
				local offArc = dd:Child("Damage1"):CurrentLabel()
				damage:SetString("1")
				C.NotifyDamage(Vector(-1, 0, 0))
				local onArc = dd:Child("Damage1"):CurrentLabel()

				GryMod.Flash.Draw = realDraw
				C.Reset()
				expect(offBlink ~= "hit").to.beTrue()
				expect(onBlink).to.equal("hit")
				expect(offArc).to.equal("stop")
				expect(onArc).to.equal("play")
			end
		},
		{
			name = "aiming at a rebel: no cross until the server says it is an ally, the cross while it does, none when it turns hostile; the crosshair keeps being drawn",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				-- an npc_citizen: its class used to be enough to open the cross
				local rebel = {
					IsValid = function() return true end, GetClass = function() return "npc_citizen" end,
					IsWeapon = function() return false end, IsPlayer = function() return false end,
					IsNPC = function() return true end, Team = function() return 1001 end, EntIndex = function() return 4242 end
				}
				local realTrace, realDraw, realAsk, realTime, drawn, asked = util.TraceLine, GryMod.Flash.Draw, C.AskServer, RealTime, 0, {}
				local clock = 1000
				GryMod.Flash.Draw = function() drawn = drawn + 1 end
				util.TraceLine = function() return {Entity = rebel} end
				C.AskServer = function(index) asked[#asked + 1] = index end
				RealTime = function() return clock end
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_crosshair"):SetString("1")
				C.Reset()
				C.ForgetRelations()
				-- the stubs are put back whatever happens, so that a failing check cannot leave them in the game
				local ok, err = pcall(function()
					local function frame(advance)
						clock = clock + advance
						assert(pcall(C.Paint))

						return C.FriendlyShown()
					end

					assert(frame(0.2) == false, "no cross before the answer")
					assert(frame(0.2) == false, "still none while the server has not answered")
					assert(asked[1] == 4242, "the server was asked about the NPC")
					C.OnAnswer(4242, false, clock) -- an enemy rebel
					assert(frame(0.2) == false, "no cross for an enemy rebel, class or not")
					C.OnAnswer(4242, true, clock) -- a rebel of the resistance
					assert(frame(0.2) == true, "the cross for an ally")
					C.OnAnswer(4242, false, clock) -- it turned hostile
					assert(frame(0.2) == false, "the cross closes when the NPC turns hostile")
				end)
				util.TraceLine, GryMod.Flash.Draw, C.AskServer, RealTime = realTrace, realDraw, realAsk, realTime
				C.Reset()
				C.ForgetRelations()

				expect(err).to.beNil()
				expect(ok).to.beTrue()
				expect(drawn >= 5).to.beTrue() -- the crosshair on every frame, the cross on the ally's
			end
		},
		{
			name = "zooming counts only while the binoculars are on",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local B = GryMod.FlashBinoculars
				local realWanted, realEnabled = B.Wanted, B.Enabled
				B.Wanted = function() return true end
				B.Enabled = function() return false end
				local _, off = pcall(C.Zooming, LocalPlayer())
				B.Enabled = function() return true end
				local _, on = pcall(C.Zooming, LocalPlayer())
				B.Wanted, B.Enabled = realWanted, realEnabled
				expect(off).to.beFalse()
				expect(on).to.beTrue()
			end
		},
		{
			name = "a weapon that draws its own crosshair (DoDrawCrosshair) keeps the vanilla crosshair, and we draw none for it",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function weapon(fields)
					fields.IsValid = function() return true end

					return fields
				end

				expect(C.WeaponDraws(weapon({}))).to.beTrue()
				expect(C.WeaponDraws(weapon({DrawCrosshair = false}))).to.beFalse()
				expect(C.WeaponDraws(weapon({DoDrawCrosshair = function() end}))).to.beFalse()
				expect(C.WeaponDraws(nil)).to.beTrue()
				expect(C.VanillaHiddenFor(weapon({}))).to.beTrue()
				expect(C.VanillaHiddenFor(weapon({DoDrawCrosshair = function() end}))).to.beFalse()
				expect(C.VanillaHiddenFor(weapon({DrawCrosshair = false}))).to.beTrue()
				expect(C.VanillaHiddenFor(nil)).to.beTrue()
			end
		},
		{
			name = "the crosshair does not redo its spread every frame when nothing moved the clips",
			func = function(state)
				local c = newCrosshair()
				c:SetCrosshair(11)
				c:SetRecoil(30)
				local calls, real = 0, c.current.Find
				c.current.Find = function(...) calls = calls + 1 return real(...) end
				c:Update(1 / 30)
				c:Update(1 / 30)
				expect(calls).to.equal(0)
			end
		},
		{
			name = "the visibility and the opacity of the whole crosshair",
			func = function(state)
				local c = newCrosshair()
				c:SetVisible(false)
				expect(c:IsShown()).to.beFalse()
				c:SetVisible(true)
				expect(c:IsShown()).to.beTrue()
				c:SetOpacity(0.5)
				expect(near(c.root:Child("Root").entry.cx[4], 0.5)).to.beTrue()
			end
		},
		{
			-- fails without Cross.DwellStep: the prompt would show at the first scan that finds the thing
			name = "the dwell: the same thing for the delay shows it, a different thing starts the wait again, nothing shows nothing at once",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local s = {ent = nil, since = 0}
				local a, b = {}, {}

				expect(C.DwellStep(s, nil, 0, 0.2)).to.beNil()
				expect(C.DwellStep(s, a, 1, 0.2)).to.beNil()
				expect(C.DwellStep(s, a, 1.1, 0.2)).to.beNil()
				expect(C.DwellStep(s, a, 1.2, 0.2)).to.equal(a)
				expect(C.DwellStep(s, a, 3, 0.2)).to.equal(a)

				-- another thing: the wait starts again, and the first one is gone at once
				expect(C.DwellStep(s, b, 3.1, 0.2)).to.beNil()
				expect(C.DwellStep(s, b, 3.2, 0.2)).to.beNil()
				expect(C.DwellStep(s, b, 3.3, 0.2)).to.equal(b)

				-- looking away: gone at once, and back on it the wait starts over
				expect(C.DwellStep(s, nil, 3.4, 0.2)).to.beNil()
				expect(C.DwellStep(s, b, 3.5, 0.2)).to.beNil()
				expect(C.DwellStep(s, b, 3.7, 0.2)).to.equal(b)

				-- no delay: at once
				local z = {ent = nil, since = 0}
				expect(C.DwellStep(z, a, 10, 0)).to.equal(a)
			end
		},
		{
			-- fails without the convar gry_usehint_delay (default 0.2) and Cross.DwellDelay
			name = "gry_usehint_delay is saved, 0.2 s by default, held between 0 and 2",
			func = function(state)
				local convar = GetConVar("gry_usehint_delay")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0.2")
				expect(bit.band(convar:GetFlags(), FCVAR_ARCHIVE)).to.equal(FCVAR_ARCHIVE)

				local saved = convar:GetString()
				local ok, err = pcall(function()
					convar:SetString("0.5")
					expect(GryMod.FlashCrosshair.DwellDelay()).to.aboutEqual(0.5, 1e-6)
					convar:SetString("0")
					expect(GryMod.FlashCrosshair.DwellDelay()).to.equal(0)
					convar:SetString("99")
					expect(GryMod.FlashCrosshair.DwellDelay()).to.equal(2)
				end)

				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without Cross.ReportDwelled in the scan: the hook would run at the first scan, or at every one
			name = "the scan's report: nothing before the delay, the hook once when the thing has been under the crosshair for the delay, once when it goes; with the delay at 0 it is at once",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local convar = GetConVar("gry_usehint_delay")
				local saved = convar:GetString()
				local realReport = C.ReportUsable
				local told = {}
				local ent = {}

				C.ResetDwell()
				C.ReportUsable = function(e, mode) told[#told + 1] = {e, mode} end

				local ok, err = pcall(function()
					convar:SetString("0.2")
					C.ReportDwelled(ent, 1, nil, 10)
					C.ReportDwelled(ent, 1, nil, 10.1)
					expect(#told).to.equal(0)
					C.ReportDwelled(ent, 1, nil, 10.2)
					expect(#told).to.equal(1)
					expect(told[1][1]).to.equal(ent)
					expect(told[1][2]).to.equal(1)
					C.ReportDwelled(ent, 1, nil, 10.3)
					expect(#told).to.equal(1)

					C.ReportDwelled(nil, 0, nil, 10.4)
					expect(#told).to.equal(2)
					expect(told[2][1]).to.beNil()
					expect(told[2][2]).to.equal(0)

					-- a thing passed over for less than the delay is never reported, neither its coming nor its going
					C.ReportDwelled(ent, 1, nil, 11)
					C.ReportDwelled(nil, 0, nil, 11.1)
					expect(#told).to.equal(2)

					convar:SetString("0")
					C.ReportDwelled(ent, 1, nil, 12)
					expect(#told).to.equal(3)
					expect(told[3][1]).to.equal(ent)
				end)

				C.ReportUsable = realReport
				convar:SetString(saved)
				C.ResetDwell()

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
