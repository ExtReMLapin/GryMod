-- Tests of the grenade warning drawn from the original Scaleform movie (GryMod.FlashGrenade), GLuaTest format,
-- client realm. Needs the converted movie lua/grymod/flash/hud_grenadedetect.lua. The rules come from the movie's
-- ActionScript and from the game's code (research notes: research-ui/NOTES.md).

local function newWarning()
	return GryMod.FlashGrenade.New(GryMod.Flash.Load("hud_grenadedetect"))
end

local function run(w, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		w:Update(1 / 30)
	end
end

local function near(a, b)
	return math.abs(a - b) < 0.001
end

-- Stubs (saved first, put back in afterEach inside a pcall, even when a case fails halfway) and the fake entities of the
-- following tests. The real entities are never touched: the warning is fed by fakes, the world search is a recorder.
local saved = {}
local fakes = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

local function fakeEntity(class)
	local ent = {class = class, valid = true}

	function ent:IsValid() return self.valid end
	function ent:GetClass() return self.class end
	function ent:GetOwner() return NULL end
	function ent:GetNW2Entity() return NULL end
	function ent:GetNW2Bool() return false end
	function ent:GetPos() return Vector(100, 0, 0) end
	function ent:WorldSpaceCenter() return Vector(100, 0, 0) end

	fakes[#fakes + 1] = ent

	return ent
end

local function fakePlayer()
	return {EyePos = function() return Vector(0, 0, 0) end, IsValid = function() return true end}
end

-- The hooks the module follows the projectiles with, called directly (never through hook.Run: the other addons would get a fake).
local function created(ent)
	hook.GetTable()["OnEntityCreated"]["GRYGRENADEFOLLOW"](ent)
end

local function removed(ent)
	hook.GetTable()["EntityRemoved"]["GRYGRENADEFOLLOW"](ent, false)
end

-- Replaces the world search by a recorder: `found[class]` is what it answers, `calls` the classes asked, in order.
local function recordSearch(found)
	local calls = {}

	stub(ents, "FindByClass", function(class)
		calls[#calls + 1] = class

		return found and found[class] or {}
	end)

	return calls
end

local function entitiesOf(list)
	local out = {}

	for i, candidate in ipairs(list) do
		out[i] = candidate.ent
	end

	return out
end

-- The candidates that are fakes of these tests (a real projectile standing in the world is none of their business).
local function mine(list)
	local out = {}

	for _, candidate in ipairs(list) do
		for _, fake in ipairs(fakes) do
			if candidate.ent == fake then out[#out + 1] = candidate end
		end
	end

	return out
end

local function has(list, ent)
	for _, e in ipairs(entitiesOf(list)) do
		if e == ent then return true end
	end

	return false
end

return {
	groupName = "GryMod grenade warning (Flash)",
	afterEach = function(state)
		pcall(restore)

		for _, ent in ipairs(fakes) do
			ent.valid = false
			pcall(GryMod.FlashGrenade.Forget, ent)
		end

		fakes = {}

		if GryMod.API and GryMod.API.UnregisterTracked then
			GryMod.API.UnregisterTracked("t_cl_trap")
		end
	end,
	cases = {
		{
			name = "the warning is hidden until shown, then plays its opening and stays on the last frame of it",
			func = function(state)
				local w = newWarning()
				expect(w:IsShown()).to.beFalse()
				w:Show()
				expect(w:IsShown()).to.beTrue()
				run(w, 1.2)
				expect(w.icon:CurrentFrame()).to.equal(27)
				expect(w.icon.playing).to.beFalse()
			end
		},
		{
			name = "the distance is written with its M and shrinks the icon by 1.5 percent a metre, down to 45 percent",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)
				w:SetDistance(34.06)
				expect(w.icon:Find("Distance"):CurrentFrame() >= 1).to.beTrue()
				local entry = w.icon:Find("Distance").names.TargetDistance
				expect(entry.text).to.equal("34.06M")
				expect(near(w.icon.entry.m[1], 0.4891)).to.beTrue()
				w:SetDistance(5)
				expect(near(w.icon.entry.m[1], 0.925)).to.beTrue()
				w:SetDistance(80)
				expect(near(w.icon.entry.m[1], 0.45)).to.beTrue()
				expect(near(w.icon.entry.m[4], 0.45)).to.beTrue()
			end
		},
		{
			name = "the distance animation restarts only when the shown distance changes, not every frame",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)
				w:SetDistance(10)
				run(w, 0.2)
				local frame = w.icon:Find("Distance"):CurrentFrame()
				w:SetDistance(10)
				expect(w.icon:Find("Distance"):CurrentFrame()).to.equal(frame)
				w:SetDistance(10.004) -- the same text (10.00M)
				expect(w.icon:Find("Distance"):CurrentFrame()).to.equal(frame)
			end
		},
		{
			name = "the distance field carries the current distance at every frame of a moving player, never the movie's initial 34.06M (the update animation recreates the field)",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)

				for i = 1, 90 do
					local metres = 40 - i * 0.31 -- the distance changes at every frame
					local text = string.format("%.2fM", metres)
					w:SetType("FRAG GRENADE")
					w:SetDistance(metres)
					-- right after the call (the clip went through its "update" frame and back to the first)
					expect(w.icon:Find("Distance").names.TargetDistance.text).to.equal(text)
					w:SetPosition(300 + i, 200)
					w:Update(1 / 30)
					-- and after the frame has advanced (the image after the "update" one)
					expect(w.icon:Find("Distance").names.TargetDistance.text).to.equal(text)
					expect(w.icon:Find("Text").names.GrenadeText.text).to.equal("FRAG GRENADE")
				end
			end
		},
		{
			name = "the distance and type fields are written again when the clips are recreated behind the warning's back",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)
				w:SetDistance(12.5)
				w:SetType("MISSILE")
				-- the movie's own scripts rebuild the two clips
				w.icon:Find("Distance"):GotoAndPlay("update")
				w.icon:Find("Text"):GotoAndStop(1)
				w:Update(1 / 30)
				expect(w.icon:Find("Distance").names.TargetDistance.text).to.equal("12.50M")
				expect(w.icon:Find("Text").names.GrenadeText.text).to.equal("MISSILE")
			end
		},
		{
			name = "the grenade type is written in the text field",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)
				w:SetType("FRAG GRENADE")
				expect(w.icon:Find("Text").names.GrenadeText.text).to.equal("FRAG GRENADE")
			end
		},
		{
			name = "the position moves the icon and keeps its scale, even while the opening rebuilds the clips",
			func = function(state)
				local w = newWarning()
				w:Show()
				w:SetDistance(10)
				w:SetPosition(300, 200)
				run(w, 1.2)
				expect(w.icon.entry.m[5]).to.equal(300)
				expect(w.icon.entry.m[6]).to.equal(200)
				expect(near(w.icon.entry.m[1], 0.85)).to.beTrue()
				w:SetType("FRAG GRENADE")
				expect(w.icon:Find("Text").names.GrenadeText.text).to.equal("FRAG GRENADE")
			end
		},
		{
			name = "hiding stops drawing, showing again replays the opening",
			func = function(state)
				local w = newWarning()
				w:Show()
				run(w, 1.2)
				w:Hide()
				expect(w:IsShown()).to.beFalse()
				w:Show()
				expect(w.icon:CurrentFrame() < 27).to.beTrue()
			end
		},
		{
			name = "the stage position of a screen point: the centre of the hexagon, whatever its size and the screen's, is on the point, x is held inside 3 to 97 percent",
			func = function(state)
				local G = GryMod.FlashGrenade
				-- the icon hangs from its corner and its hexagon is 18 stage pixels from it at full size: after the
				-- shrinking of the distance its centre is 18 * size from the corner, and that centre is the projected point,
				-- on every screen size
				for _, size in ipairs({{1920, 1080}, {640, 360}, {2560, 1440}, {1024, 768}}) do
					local w, h = size[1], size[2]
					local scale = h / 768
					for _, metres in ipairs({0, 10, 30, 60}) do
						local x, y = G.StagePosition(w * 0.6, h * 0.4, w, h, metres)
						local s = math.max(45, 100 - metres * 1.5) / 100
						local centreX = (w - 1366 * scale) / 2 + (x + 18 * s) * scale
						local centreY = (y + 18 * s) * scale
						expect(near(centreX, w * 0.6)).to.beTrue()
						expect(near(centreY, h * 0.4)).to.beTrue()
					end
				end
				-- off the left edge: held at 3 percent of the screen
				local left = G.StagePosition(-500, 540, 1920, 1080, 20)
				local held = G.StagePosition(0.03 * 1920, 540, 1920, 1080, 20)
				expect(near(left, held)).to.beTrue()
				local right = G.StagePosition(5000, 540, 1920, 1080, 20)
				local heldRight = G.StagePosition(0.97 * 1920, 540, 1920, 1080, 20)
				expect(near(right, heldRight)).to.beTrue()
			end
		},
		-- the alert at the edge of the screen (gry_hud_grenade_edge): the original keeps the icon on the screen while the grenade is in front of the player
		{
			-- needs: Grenade.EdgePoint (new)
			name = "a point inside the screen stays where it is; one outside goes to the edge in its direction, 3 percent in, the corner for a diagonal one",
			func = function(state)
				local G = GryMod.FlashGrenade
				local w, h = 1920, 1080
				local x, y, moved = G.EdgePoint(900, 500, w, h)
				expect(x).to.equal(900)
				expect(y).to.equal(500)
				expect(moved).to.beFalse()

				-- far to the right at mid height: the right edge, same height
				x, y, moved = G.EdgePoint(9000, h / 2, w, h)
				expect(near(x, 0.97 * w)).to.beTrue()
				expect(near(y, h / 2)).to.beTrue()
				expect(moved).to.beTrue()

				-- above the screen, over the left half: the top edge, to the left of the middle
				x, y = G.EdgePoint(400, -3000, w, h)
				expect(near(y, 0.03 * h)).to.beTrue()
				expect(x < w / 2).to.beTrue()
				expect(x > 0.03 * w).to.beTrue()

				-- the corner: a point far down to the right
				x, y = G.EdgePoint(w * 3, h * 3, w, h)
				expect(near(x, 0.97 * w)).to.beTrue()
				expect(near(y, 0.97 * h)).to.beTrue()

				-- the direction from the centre is kept
				local px, py = 2500, 1700
				x, y = G.EdgePoint(px, py, w, h)
				expect(near((x - w / 2) * (py - h / 2), (y - h / 2) * (px - w / 2))).to.beTrue()
			end
		},
		{
			-- needs: Grenade.StagePosition taking the edge flag (the hexagon's centre lands on the point held at the edge, y included)
			name = "the stage position with the edge on holds a grenade above the screen at the top edge; with it off, y is not held",
			func = function(state)
				local G = GryMod.FlashGrenade
				local w, h, metres = 1920, 1080, 20
				local scale = h / 768
				local s = math.max(45, 100 - metres * 1.5) / 100
				local x, y = G.StagePosition(w / 2, -800, w, h, metres, true)
				expect(near((y + 18 * s) * scale, 0.03 * h)).to.beTrue()
				expect(near((w - 1366 * scale) / 2 + (x + 18 * s) * scale, w / 2)).to.beTrue()
				local _, yOff = G.StagePosition(w / 2, -800, w, h, metres)
				expect(near((yOff + 18 * s) * scale, -800)).to.beTrue()
			end
		},
		{
			-- needs: Warns reading opts.edge and c.front
			name = "with the edge on a grenade in front of the player warns even when it is off the screen; one behind never does; with it off, off the screen is silent as before",
			func = function(state)
				local G = GryMod.FlashGrenade
				local function grenade(onScreen, front) return {class = "npc_grenade_frag", metres = 10, onScreen = onScreen, front = front, own = false, armed = true} end

				expect(G.Warns(grenade(false, true), true, {edge = true})).to.beTrue()
				expect(G.Warns(grenade(false, false), true, {edge = true})).to.beFalse()
				expect(G.Warns(grenade(true, true), true, {edge = true})).to.beTrue()
				-- a candidate made without the side (nil): the screen says it, as before
				expect(G.Warns(grenade(false, nil), true, {edge = true})).to.beFalse()
				expect(G.Warns(grenade(true, nil), true, {edge = true})).to.beTrue()
				-- the setting off: only what is on the screen
				expect(G.Warns(grenade(false, true), true, {edge = false})).to.beFalse()
				expect(G.Warns(grenade(false, true), true, {})).to.beFalse()
				expect(G.Warns(grenade(true, false), true, {})).to.beTrue()
				-- the other rules still apply at the edge: range and armed
				expect(G.Warns({class = "npc_grenade_frag", metres = 300, onScreen = false, front = true, own = false, armed = true}, true, {edge = true})).to.beFalse()
				expect(G.Warns({class = "npc_grenade_frag", metres = 10, onScreen = false, front = true, own = false, armed = false}, true, {edge = true})).to.beFalse()
			end
		},
		{
			-- needs: Candidate carrying the `front` it is given, Candidates computing it from the eye direction
			name = "a candidate carries whether the grenade is in front of the eye, read from the direction the player looks (not from the screen point)",
			func = function(state)
				local G = GryMod.FlashGrenade
				local ent = fakeEntity("npc_grenade_frag")
				local ply = {EyePos = function() return Vector(0, 0, 0) end, IsValid = function() return true end}
				expect(G.Candidate(ent, ply, {x = 0, y = 0, visible = false}, nil, true).front).to.beTrue()
				expect(G.Candidate(ent, ply, {x = 0, y = 0, visible = false}, nil, false).front).to.beFalse()
				expect(G.Candidate(ent, ply, {x = 0, y = 0, visible = false}).front).to.beNil()

				-- the grenade is at (100, 0, 0): in front of an eye that looks along +x, behind one that looks along -x
				stub(ents, "FindByClass", function() return {} end)
				stub(_G, "EyeVector", function() return Vector(1, 0, 0) end)
				created(ent)
				local list = mine(G.Candidates(ply, {}))
				expect(#list).to.equal(1)
				expect(list[1].front).to.beTrue()
				_G.EyeVector = function() return Vector(-1, 0, 0) end
				list = mine(G.Candidates(ply, {}))
				expect(list[1].front).to.beFalse()
			end
		},
		{
			-- needs: the setting gry_hud_grenade_edge (1 by default) read by Options
			name = "gry_hud_grenade_edge exists (1 by default), Options reads it, and it has its check box in the options",
			func = function(state)
				local G = GryMod.FlashGrenade
				local convar = GetConVar("gry_hud_grenade_edge")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				local saved = convar:GetString()
				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					convar:SetString("0")
					expect(G.Options().edge).to.beFalse()
					convar:SetString("1")
					expect(G.Options().edge).to.beTrue()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				pcall(function() convar:SetString(saved) end)
				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_hud_grenade_edge"]).to.beTrue()
			end
		},
		{
			name = "the grenade classes have their names, an unknown one has none",
			func = function(state)
				local G = GryMod.FlashGrenade
				expect(G.TypeFor("npc_grenade_frag")).to.equal("FRAG GRENADE")
				expect(G.TypeFor("grenade_ar2")).to.equal("RIFLE GRENADE")
				expect(G.TypeFor("rpg_missile")).to.equal("MISSILE")
				expect(G.TypeFor("grenade_helicopter")).to.equal("BOMB")
				expect(G.TypeFor("combine_mine")).to.equal("MINE")
				expect(G.TypeFor("prop_combine_ball")).to.equal("ENERGY BALL")
				expect(G.TypeFor("prop_physics")).to.equal(nil)
				expect(G.TypeFor(nil)).to.equal(nil)
			end
		},
		{
			name = "the warning picks the nearest dangerous projectile in front of the player, within range",
			func = function(state)
				local G = GryMod.FlashGrenade
				local picked = G.Pick({
					{class = "npc_grenade_frag", metres = 20, onScreen = true, own = false, armed = true},
					{class = "npc_grenade_frag", metres = 8, onScreen = false, own = false, armed = true}, -- behind the camera
					{class = "prop_physics", metres = 3, onScreen = true, own = false, armed = true}, -- not a grenade
					{class = "grenade_ar2", metres = 12, onScreen = true, own = false, armed = true},
					{class = "npc_grenade_frag", metres = G.DEFAULT_RANGE + 1, onScreen = true, own = false, armed = true} -- too far
				})
				expect(picked.metres).to.equal(12)
				expect(G.Pick({})).to.equal(nil)
				expect(G.Pick(nil)).to.equal(nil)
			end
		},
		{
			name = "a grenade the player threw NEVER warns, hand grenade included, at any distance (owner's decision); nothing is warned about within 1 m of the eye either",
			func = function(state)
				local G = GryMod.FlashGrenade
				expect(G.MIN_OWN).to.equal(1)
				expect(G.OWN_RANGE).to.beNil() -- the 15 m rule of the old default is gone
				local function own(metres, class) return {class = class or "npc_grenade_frag", metres = metres, onScreen = true, own = true, armed = true} end

				for _, class in ipairs({"npc_grenade_frag", "grenade_helicopter", "combine_mine", "grenade_ar2", "rpg_missile", "prop_combine_ball"}) do
					for _, metres in ipairs({1.5, 5, 8, 14.9, 15, 20, 39}) do
						expect(G.Pick({own(metres, class)})).to.equal(nil)
						expect(G.Pick({own(metres, class)}, false)).to.equal(nil)
						expect(G.Pick({own(metres, class)}, true, {range = 100})).to.equal(nil)
					end
				end

				-- a grenade the player let go of after picking it up with the gravity gun is recognised as theirs by the server
				-- (the thrower), so it arrives here with own = true: same; an enemy's one with no thrower at the hand does not blink
				expect(G.Pick({{class = "npc_grenade_frag", metres = 0.9, onScreen = true, own = false, armed = true}})).to.equal(nil)
				expect(G.Pick({{class = "npc_grenade_frag", metres = 1.1, onScreen = true, own = false, armed = true}}) ~= nil).to.beTrue()

				-- the player's own one never hides an enemy's behind it: the nearest of the two is the enemy's
				expect(G.Pick({
					own(6),
					{class = "grenade_ar2", metres = 9, onScreen = true, own = false, armed = true}
				}).metres).to.equal(9)
				expect(G.Pick({own(2), {class = "npc_grenade_frag", metres = 35, onScreen = true, own = false, armed = true}}).metres).to.equal(35)
			end
		},
		{
			name = "an inert projectile is not warned about, unless the switch asks for every one (the second argument false)",
			func = function(state)
				local G = GryMod.FlashGrenade
				local list = {
					{class = "npc_grenade_frag", metres = 4, onScreen = true, own = false, armed = false}, -- lying there, not armed
					{class = "combine_mine", metres = 9, onScreen = true, own = false, armed = false}, -- on the ground
					{class = "npc_grenade_frag", metres = 15, onScreen = true, own = false, armed = true}
				}
				expect(G.Pick(list).metres).to.equal(15) -- armed only is the default
				expect(G.Pick(list, true).metres).to.equal(15)
				expect(G.Pick(list, false).metres).to.equal(4) -- the old behaviour
				expect(G.Pick({{class = "combine_mine", metres = 9, onScreen = true, own = false, armed = false}})).to.equal(nil)
			end
		},
		{
			name = "the range is a setting: 40 m by default (the original has none, see docs/superpowers/plans/2026-11-21-grenade-range.md), held between 5 and 200 m, and Pick obeys the one it is given",
			func = function(state)
				local G = GryMod.FlashGrenade
				expect(G.DEFAULT_RANGE).to.equal(40)
				expect(G.ClampRange(nil)).to.equal(40)
				expect(G.ClampRange(1)).to.equal(5)
				expect(G.ClampRange(500)).to.equal(200)
				expect(G.ClampRange(75)).to.equal(75)
				local far = {class = "npc_grenade_frag", metres = 30, onScreen = true, own = false, armed = true}
				expect(G.Pick({far}, true, {range = 25})).to.equal(nil)
				expect(G.Pick({far}, true, {range = 30}) ~= nil).to.beTrue()
				expect(G.Pick({far}, true, {range = 100}) ~= nil).to.beTrue()
				expect(G.Pick({{class = "npc_grenade_frag", metres = 41, onScreen = true, own = false, armed = true}})).to.equal(nil)
				expect(G.Pick({{class = "npc_grenade_frag", metres = 39, onScreen = true, own = false, armed = true}}) ~= nil).to.beTrue()
			end
		},
		{
			name = "a projectile the player FIRED (missile, rifle grenade, energy ball) never warns, even with the old own-grenade rule on, and an enemy's does",
			func = function(state)
				local G = GryMod.FlashGrenade
				for _, class in ipairs({"rpg_missile", "grenade_ar2", "prop_combine_ball"}) do
					expect(G.Pick({{class = class, metres = 12, onScreen = true, own = true, armed = true}})).to.equal(nil)
					expect(G.Pick({{class = class, metres = 12, onScreen = true, own = true, armed = true}}, true, {ownWarn = true})).to.equal(nil)
					expect(G.Pick({{class = class, metres = 12, onScreen = true, own = false, armed = true}}) ~= nil).to.beTrue()
				end
				-- the nearest is not the player's own missile but the enemy's behind it
				local picked = G.Pick({
					{class = "rpg_missile", metres = 5, onScreen = true, own = true, armed = true},
					{class = "rpg_missile", metres = 20, onScreen = true, own = false, armed = true}
				})
				expect(picked.metres).to.equal(20)
				-- which ones are fired is the registry's `ownMissile`, no table of this module
				expect(G.FIRED).to.beNil()
				expect(GryMod.API.GetDanger("rpg_missile").danger.ownMissile).to.beTrue()
				expect(GryMod.API.GetDanger("npc_grenade_frag").danger.ownMissile).to.beFalse()
			end
		},
		{
			name = "a third-party danger registered with RegisterTracked (invented class) warns by the same path as the stock ones: its label, the options (armed only, range, line of sight, own grenades) apply to it",
			func = function(state)
				local G, API = GryMod.FlashGrenade, GryMod.API
				expect(API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP", type = "mine"}})).to.beTrue()
				local ok, err = pcall(function()
					expect(G.TypeFor("t_cl_trap")).to.equal("TRAP")
					local function c(fields)
						local base = {class = "t_cl_trap", metres = 12, onScreen = true, own = false, armed = true}
						for k, v in pairs(fields or {}) do base[k] = v end
						return base
					end

					expect(G.Pick({c()}) ~= nil).to.beTrue()
					expect(G.Pick({c({armed = false})})).to.equal(nil) -- gry_grenade_armed_only
					expect(G.Pick({c({armed = false})}, false) ~= nil).to.beTrue()
					expect(G.Pick({c({onScreen = false})})).to.equal(nil)
					expect(G.Pick({c({metres = 41})})).to.equal(nil) -- the player's range
					expect(G.Pick({c({metres = 0.5})})).to.equal(nil)
					expect(G.Pick({c({visible = false})}, true, {los = true})).to.equal(nil)
					expect(G.Pick({c({visible = false})}, true, {los = false}) ~= nil).to.beTrue()
					-- its own, thrown by the player: never, unless the old rule is on, and then within 15 m (it is not a fired missile)
					expect(G.Pick({c({own = true})})).to.equal(nil)
					expect(G.Pick({c({own = true})}, true, {ownWarn = true}) ~= nil).to.beTrue()
					expect(G.Pick({c({own = true, metres = 20})}, true, {ownWarn = true})).to.equal(nil)
				end)
				API.UnregisterTracked("t_cl_trap")
				if not ok then error(err, 0) end
				expect(G.TypeFor("t_cl_trap")).to.beNil()
				expect(G.Pick({{class = "t_cl_trap", metres = 12, onScreen = true, own = false, armed = true}})).to.equal(nil)
			end
		},
		{
			name = "danger.ownMissile makes a third-party projectile one the player fires (never warns their own, even with the old rule); danger.range caps the player's range for that entry only",
			func = function(state)
				local G, API = GryMod.FlashGrenade, GryMod.API
				API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "ROCKET", ownMissile = true, range = 20}})
				local ok, err = pcall(function()
					local mine = {class = "t_cl_trap", metres = 12, onScreen = true, own = true, armed = true}
					expect(G.Pick({mine}, true, {ownWarn = true})).to.equal(nil)
					expect(G.Pick({{class = "t_cl_trap", metres = 12, onScreen = true, own = false, armed = true}}) ~= nil).to.beTrue()
					-- the entry's range of 20 m: nearer than the player's 100 m
					local far = {class = "t_cl_trap", metres = 25, onScreen = true, own = false, armed = true}
					expect(G.Pick({far}, true, {range = 100})).to.equal(nil)
					expect(G.Pick({{class = "t_cl_trap", metres = 15, onScreen = true, own = false, armed = true}}, true, {range = 10})).to.equal(nil) -- the player's range still applies
					-- the stock ones keep the player's range alone
					expect(G.Pick({{class = "npc_grenade_frag", metres = 25, onScreen = true, own = false, armed = true}}, true, {range = 100}) ~= nil).to.beTrue()
				end)
				API.UnregisterTracked("t_cl_trap")
				if not ok then error(err, 0) end
			end
		},
		{
			name = "indicator marker or none: the entry has no warning (accepted and stored, drawn by no part of the HUD yet); the stock ones warn",
			func = function(state)
				local G, API = GryMod.FlashGrenade, GryMod.API
				local candidate = {class = "t_cl_trap", metres = 12, onScreen = true, own = false, armed = true}

				for _, indicator in ipairs({"marker", "none"}) do
					API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP"}, indicator = indicator})
					expect(G.Pick({candidate})).to.equal(nil)
					expect(G.TypeFor("t_cl_trap")).to.equal("TRAP")
				end

				API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP"}, indicator = "warning"})
				expect(G.Pick({candidate}) ~= nil).to.beTrue()
				API.UnregisterTracked("t_cl_trap")
				expect(GryMod.API.GetDanger("combine_mine").indicator).to.equal("warning")
			end
		},
		{
			name = "gry_grenade_own_warn (off by default) brings back the old rule: the player's own hand grenade warns within 15 m, never what the player fired",
			func = function(state)
				local G = GryMod.FlashGrenade
				expect(G.OWN_WARN_RANGE).to.equal(15)
				local function own(metres, class) return {class = class or "npc_grenade_frag", metres = metres, onScreen = true, own = true, armed = true} end
				local on = {ownWarn = true}
				expect(G.Pick({own(8)}, true, on) ~= nil).to.beTrue()
				expect(G.Pick({own(8)}, true, {ownWarn = false})).to.equal(nil)
				expect(G.Pick({own(8)}, true, {})).to.equal(nil)
				expect(G.Pick({own(8)})).to.equal(nil) -- off when no option is given
				expect(G.Pick({own(15)}, true, on) ~= nil).to.beTrue()
				expect(G.Pick({own(15.5)}, true, on)).to.equal(nil)
				expect(G.Pick({own(30)}, true, {ownWarn = true, range = 100})).to.equal(nil)
				expect(G.Pick({own(9, "grenade_helicopter")}, true, on) ~= nil).to.beTrue()
				expect(G.Pick({own(20, "grenade_helicopter")}, true, on)).to.equal(nil)
				expect(G.Pick({own(0.9)}, true, on)).to.equal(nil) -- still nothing at the hand
				-- an enemy's frag at 30 m warns whatever the option says, and the own one beyond 15 m does not hide it
				local enemy = {class = "npc_grenade_frag", metres = 30, onScreen = true, own = false, armed = true}
				expect(G.Pick({enemy}, true, on) ~= nil).to.beTrue()
				expect(G.Pick({own(16), {class = "npc_grenade_frag", metres = 35, onScreen = true, own = false, armed = true}}, true, on).metres).to.equal(35)
			end
		},
		{
			name = "line of sight (off by default, as in the original: the warning goes through walls): when on, a projectile that is not seen does not warn",
			func = function(state)
				local G = GryMod.FlashGrenade
				local hidden = {class = "npc_grenade_frag", metres = 10, onScreen = true, own = false, armed = true, visible = false}
				local seen = {class = "npc_grenade_frag", metres = 20, onScreen = true, own = false, armed = true, visible = true}
				expect(G.Pick({hidden, seen}).metres).to.equal(10) -- los off: through the wall
				expect(G.Pick({hidden, seen}, true, {los = false}).metres).to.equal(10)
				expect(G.Pick({hidden, seen}, true, {los = true}).metres).to.equal(20)
				expect(G.Pick({hidden}, true, {los = true})).to.equal(nil)
				-- no reading yet (nil): not held back
				expect(G.Pick({{class = "npc_grenade_frag", metres = 10, onScreen = true, own = false, armed = true}}, true, {los = true}) ~= nil).to.beTrue()
			end
		},
		{
			name = "the line of sight is probed at most 5 times a second per projectile, and a view lost is kept for half a second (hysteresis)",
			func = function(state)
				local G = GryMod.FlashGrenade
				local probes, clear = 0, true
				local function probe() probes = probes + 1 return clear end
				local entry = {}
				expect(G.LosStep(entry, 0, probe)).to.beTrue()
				expect(probes).to.equal(1)
				-- every frame for a second: 5 probes more at most
				for i = 1, 60 do
					G.LosStep(entry, i / 60, probe)
				end
				expect(probes <= 6).to.beTrue()
				expect(probes >= 5).to.beTrue()
				-- a wall comes: seen for half a second more, then not
				clear = false
				local t = entry.seen -- the last time it was seen
				expect(G.LosStep(entry, t + 0.21, probe)).to.beTrue() -- probed: blocked, but seen 0.21 s ago
				expect(G.LosStep(entry, t + 0.42, probe)).to.beTrue() -- seen 0.42 s ago
				expect(G.LosStep(entry, t + 0.63, probe)).to.beFalse() -- more than half a second
				-- it is seen again at once
				clear = true
				expect(G.LosStep(entry, t + 0.84, probe)).to.beTrue()
				-- a first probe that fails is not seen
				clear = false
				expect(G.LosStep({}, 5, probe)).to.beFalse()
			end
		},
		{
			name = "the settings exist: gry_grenade_range (40, 5 to 200), gry_grenade_own_warn (0), gry_grenade_los (0)",
			func = function(state)
				local r, o, l = GetConVar("gry_grenade_range"), GetConVar("gry_grenade_own_warn"), GetConVar("gry_grenade_los")
				expect(r).toNot.beNil()
				expect(o).toNot.beNil()
				expect(l).toNot.beNil()
				expect(r:GetMin()).to.equal(5)
				expect(r:GetMax()).to.equal(200)
				expect(r:GetDefault()).to.equal("40")
				expect(o:GetDefault()).to.equal("0")
				expect(l:GetDefault()).to.equal("0")
			end
		},
		{
			name = "an old saved gry_grenade_own 1 does not bring the old rule back: only gry_grenade_own_warn does, and it is read by Options",
			func = function(state)
				local G = GryMod.FlashGrenade
				local warn = GetConVar("gry_grenade_own_warn")
				local old = GetConVar("gry_grenade_own") -- it only exists when an earlier version of the module created it in this session
				local savedWarn, savedOld = warn:GetString(), old and old:GetString()

				local ok, err = pcall(function()
					if old then
						old:SetString("1")
					end

					warn:SetString("0")
					expect(G.Options().ownWarn).to.beFalse()
					local own = {class = "npc_grenade_frag", metres = 8, onScreen = true, own = true, armed = true}
					expect(G.Pick({own}, true, G.Options())).to.equal(nil)

					warn:SetString("1")
					expect(G.Options().ownWarn).to.beTrue()
					expect(G.Pick({own}, true, G.Options()) ~= nil).to.beTrue()
				end)

				pcall(function() warn:SetString(savedWarn) end)
				pcall(function() if old then old:SetString(savedOld) end end)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "gry_grenade_own_warn has its check box in the options, and the old gry_grenade_own has none",
			func = function(state)
				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_grenade_own_warn"]).to.beTrue()
				expect(found["gry_grenade_own"]).to.beNil()
			end
		},
		{
			name = "a candidate is built from the entity: its class, its distance in metres, the server's mark and whether the player owns it",
			func = function(state)
				local G = GryMod.FlashGrenade
				local eye = Vector(0, 0, 0)
				local me = {}
				local function stub(owner, armed, thrown)
					return {
						IsValid = function() return true end,
						GetClass = function() return "npc_grenade_frag" end,
						GetPos = function() return Vector(524.9, 0, 0) end,
						WorldSpaceCenter = function() return Vector(524.9, 0, 0) end,
						GetOwner = function() return owner end,
						GetNW2Bool = function(_, name) return name == "GryArmed" and armed end,
						GetNW2Entity = function(_, name) return name == "GryThrower" and thrown or NULL end
					}
				end
				local ply = {EyePos = function() return eye end, IsValid = function() return true end}
				local c = G.Candidate(stub(NULL, true), ply, {x = 100, y = 50, visible = true})
				expect(c.class).to.equal("npc_grenade_frag")
				expect(near(c.metres, 10)).to.beTrue()
				expect(c.armed).to.beTrue()
				expect(c.own).to.beFalse()
				expect(c.onScreen).to.beTrue()
				expect(G.Candidate(stub(NULL, false), ply, {x = 0, y = 0, visible = false}).armed).to.beFalse()
				expect(G.Candidate(stub(NULL, false), ply, {x = 0, y = 0, visible = false}).onScreen).to.beFalse()
					-- the thrower the server writes (GryThrower) counts as much as the engine's owner
					expect(G.Candidate(stub(NULL, true, ply), ply, {x = 0, y = 0, visible = true}).own).to.beTrue()
					expect(G.Candidate(stub(NULL, true, {}), ply, {x = 0, y = 0, visible = true}).own).to.beFalse()
					expect(G.Candidate(stub(ply, true), ply, {x = 0, y = 0, visible = true}).own).to.beTrue()
					-- another player (a bot, a team mate) threw it: it is not the player's own, so it warns
					local bot = {IsValid = function() return true end}
					expect(G.Candidate(stub(bot, true, bot), ply, {x = 0, y = 0, visible = true}).own).to.beFalse()
					-- third person (ShouldDrawLocalPlayer) changes the camera, not who threw: the eye of the player still gives the distance
					local third = {EyePos = function() return eye end, IsValid = function() return true end, ShouldDrawLocalPlayer = function() return true end}
					expect(G.Candidate(stub(third, true), third, {x = 0, y = 0, visible = true}).own).to.beTrue()
					-- the line of sight reading is carried when given
					expect(G.Candidate(stub(NULL, true), ply, {x = 0, y = 0, visible = true}, false).visible).to.beFalse()
			end
		},
		{
			name = "no search of the world: once the registry is settled, thirty frames of candidates never call ents.FindByClass (fails if a periodic scan comes back)",
			func = function(state)
				local G = GryMod.FlashGrenade
				local ply = fakePlayer()
				G.Candidates(ply, {}) -- settles the registry once, with the real search
				local calls = recordSearch()
				local now = RealTime()
				stub(_G, "RealTime", function() now = now + 0.25 return now end) -- far more than the old 0.2 s between two scans

				for _ = 1, 30 do
					G.Candidates(ply, {})
				end

				expect(#calls).to.equal(0)
			end
		},
		{
			name = "a projectile made after the load is followed from the hook OnEntityCreated alone (the search answers nothing); fails if the hook is not there or does not follow",
			func = function(state)
				local G = GryMod.FlashGrenade
				local ply = fakePlayer()
				G.Candidates(ply, {})
				recordSearch() -- finds nothing: only the event can have told the warning about it
				local ent = fakeEntity("npc_grenade_frag")
				expect(has(G.Candidates(ply, {}), ent)).to.beFalse()
				created(ent)
				local list = G.Candidates(ply, {})
				list = mine(list)
				expect(#list).to.equal(1)
				expect(list[1].ent).to.equal(ent)
				expect(list[1].class).to.equal("npc_grenade_frag")
			end
		},
		{
			name = "a projectile that is removed is forgotten at once, even while its entity still answers IsValid (the hook EntityRemoved is called before the end); fails if EntityRemoved does not forget it",
			func = function(state)
				local G = GryMod.FlashGrenade
				local ply = fakePlayer()
				G.Candidates(ply, {})
				recordSearch()
				local ent, other = fakeEntity("npc_grenade_frag"), fakeEntity("combine_mine")
				created(ent)
				created(other)
				expect(#mine(G.Candidates(ply, {}))).to.equal(2)
				removed(ent)
				local list = G.Candidates(ply, {})
				expect(has(list, ent)).to.beFalse()
				expect(has(list, other)).to.beTrue()
				-- a projectile that goes without the hook (invalid) is not kept either
				other.valid = false
				expect(#mine(G.Candidates(ply, {}))).to.equal(0)
			end
		},
		{
			name = "a class registered later: the entities that stand already are looked for ONCE, per class of the registry, then the events alone follow; fails if no catch-up is made, or if it is made every frame",
			func = function(state)
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()
				G.Candidates(ply, {})
				local ent = fakeEntity("t_cl_trap")
				local calls = recordSearch({t_cl_trap = {ent}})
				created(ent) -- no entry yet: not a projectile
				expect(has(G.Candidates(ply, {}), ent)).to.beFalse()
				expect(#calls).to.equal(0)

				expect(API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP"}})).to.beTrue()
				expect(has(G.Candidates(ply, {}), ent)).to.beTrue()
				local asked = 0

				for _, class in ipairs(calls) do
					if class == "t_cl_trap" then asked = asked + 1 end
				end

				expect(asked).to.equal(1)
				expect(#calls).to.equal(#API.DangerClasses())
				local total = #calls

				for _ = 1, 10 do
					G.Candidates(ply, {})
				end

				expect(#calls).to.equal(total)
			end
		},
		{
			name = "a projectile that has no class yet when it is made is looked at again one frame on (one timer for all the ones of the frame); fails if it is judged at creation only, or one timer is made for each",
			func = function(state)
				local G = GryMod.FlashGrenade
				local ply = fakePlayer()
				G.Candidates(ply, {})
				recordSearch()
				local timers = {}
				stub(timer, "Simple", function(delay, fn) timers[#timers + 1] = {delay = delay, fn = fn} end)
				local ent, other = fakeEntity("class C_BaseEntity"), fakeEntity("class C_BaseEntity")
				created(ent)
				created(other)
				expect(has(G.Candidates(ply, {}), ent)).to.beFalse()
				expect(#timers).to.equal(1)
				expect(timers[1].delay).to.equal(0)
				-- the class arrives with the first update of the entity
				ent.class = "npc_grenade_frag"
				timers[1].fn()
				expect(has(G.Candidates(ply, {}), ent)).to.beTrue()
				expect(has(G.Candidates(ply, {}), other)).to.beFalse() -- a prop of the client stays out
			end
		},
		{
			name = "the candidates are what the old search gave: only the projectiles whose entry draws a warning (the indicator), valid ones, with their class, distance and server mark",
			func = function(state)
				local G, API = GryMod.FlashGrenade, GryMod.API
				local ply = fakePlayer()
				G.Candidates(ply, {})
				recordSearch()
				local frag, trap, prop = fakeEntity("npc_grenade_frag"), fakeEntity("t_cl_trap"), fakeEntity("prop_physics")
				API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP"}, indicator = "marker"})
				created(frag)
				created(trap)
				created(prop)
				local list = mine(G.Candidates(ply, {}))
				expect(has(list, frag)).to.beTrue()
				expect(has(list, trap)).to.beFalse() -- followed, but its entry has no warning
				expect(has(list, prop)).to.beFalse() -- no entry
				expect(#list).to.equal(1)
				expect(list[1].class).to.equal("npc_grenade_frag")
				expect(near(list[1].metres, 100 / 52.49)).to.beTrue()
				expect(list[1].armed).to.beFalse()
				-- the entry of the trap is given a warning: the same entity warns, nothing else was needed
				API.RegisterTracked("t_cl_trap", {class = "t_cl_trap", danger = {label = "TRAP"}, indicator = "warning"})
				expect(has(G.Candidates(ply, {}), trap)).to.beTrue()
				-- and when the entry goes, so does the warning
				API.UnregisterTracked("t_cl_trap")
				expect(has(G.Candidates(ply, {}), trap)).to.beFalse()
			end
		},
		{
			name = "the projectiles that stand when the file is loaded (a hot reload) are looked for once at the load; fails if the load makes no catch-up",
			func = function(state)
				local ent = fakeEntity("npc_grenade_frag")
				local calls = recordSearch({npc_grenade_frag = {ent}})
				local old = GryMod.FlashGrenade
				old.Reset()
				local ok, err = pcall(include, "grymod/client/cl_hud_grenade_flash.lua")
				local G = GryMod.FlashGrenade
				pcall(restore) -- the search is the real one again before anything else runs
				saved = {}
				expect(ok).to.beTrue()
				expect(err).to.beNil()
				expect(#calls >= 1).to.beTrue()
				recordSearch()
				expect(has(G.Candidates(fakePlayer(), {}), ent)).to.beTrue()
			end
		},
		{
			name = "the module listens to the creation and the removal of entities (the hooks OnEntityCreated and EntityRemoved)",
			func = function(state)
				local hooks = hook.GetTable()
				expect(isfunction(hooks["OnEntityCreated"]["GRYGRENADEFOLLOW"])).to.beTrue()
				expect(isfunction(hooks["EntityRemoved"]["GRYGRENADEFOLLOW"])).to.beTrue()
			end
		},
		{
			name = "a missing movie gives no warning instead of an error",
			func = function(state)
				expect(GryMod.FlashGrenade.New(nil)).to.equal(nil)
			end
		}
	}
}
