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

local function scaleOf(c, path)
	local clip = c.current:Find(path)
	local m = clip.entry.m

	return math.sqrt(m[1] * m[1] + m[2] * m[2]) * 100
end

return {
	groupName = "GryMod crosshair (Flash)",
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
			name = "usable: a weapon not owned can be taken (1), one already owned is blocked (2), items, buttons and props can be used, a wall cannot",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local function fake(class, weapon)
					return {IsValid = function() return true end, GetClass = function() return class end, IsWeapon = function() return weapon or false end}
				end

				local player = {HasWeapon = function(_, class) return class == "weapon_pistol" end}
				expect(C.UsableFor(fake("weapon_smg1", true), player)).to.equal(1)
				expect(C.UsableFor(fake("weapon_pistol", true), player)).to.equal(2)
				expect(C.UsableFor(fake("item_healthkit"), player)).to.equal(1)
				expect(C.UsableFor(fake("func_button"), player)).to.equal(1)
				expect(C.UsableFor(fake("prop_door_rotating"), player)).to.equal(1)
				expect(C.UsableFor(fake("prop_physics"), player)).to.equal(1)
				expect(C.UsableFor(fake("func_useableladder"), player)).to.equal(1)
				expect(C.UsableFor(fake("func_brush"), player)).to.equal(0)
				expect(C.UsableFor(nil, player)).to.equal(0)
				expect(C.UsableFor({IsValid = function() return false end}, player)).to.equal(0)
			end
		},
		{
			name = "friendly: a player of the same team (when there are teams) and the rebels' NPC classes, never the player itself",
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
				expect(C.IsFriendly(fake("npc_citizen"), me)).to.beTrue()
				expect(C.IsFriendly(fake("npc_alyx"), me)).to.beTrue()
				expect(C.IsFriendly(fake("npc_combine_s"), me)).to.beFalse()
				expect(C.IsFriendly(nil, me)).to.beFalse()
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
			name = "aiming at an ally opens the friendly cross without an error, and the crosshair keeps being drawn",
			func = function(state)
				local C = GryMod.FlashCrosshair
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local ally = {
					IsValid = function() return true end, GetClass = function() return "npc_citizen" end,
					IsWeapon = function() return false end, IsPlayer = function() return false end,
					IsNPC = function() return true end, Team = function() return 1001 end
				}
				local realTrace, realDraw, drawn = util.TraceLine, GryMod.Flash.Draw, 0
				GryMod.Flash.Draw = function() drawn = drawn + 1 end
				util.TraceLine = function() return {Entity = ally} end
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_crosshair"):SetString("1")
				C.Reset()
				-- the stubs are put back whatever happens, so that a failing check cannot leave them in the game
				local ok, shown = pcall(function()
					assert(pcall(C.Paint))
					assert(pcall(C.Paint))

					return C.FriendlyShown()
				end)
				util.TraceLine, GryMod.Flash.Draw = realTrace, realDraw
				C.Reset()

				expect(ok).to.beTrue()
				expect(shown).to.beTrue()
				expect(drawn >= 3).to.beTrue() -- the crosshair twice and the cross at least once
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
		}
	}
}
