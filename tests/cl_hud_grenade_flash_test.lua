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

return {
	groupName = "GryMod grenade warning (Flash)",
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
		{
			name = "the grenade classes have their names, an unknown one has none",
			func = function(state)
				local G = GryMod.FlashGrenade
				expect(G.TypeFor("npc_grenade_frag")).to.equal("FRAG GRENADE")
				expect(G.TypeFor("grenade_ar2")).to.equal("RIFLE GRENADE")
				expect(G.TypeFor("rpg_missile")).to.equal("MISSILE")
				expect(G.TypeFor("prop_physics")).to.equal(nil)
				expect(G.TypeFor(nil)).to.equal(nil)
			end
		},
		{
			name = "the warning picks the nearest dangerous projectile in front of the player, not the player's own, within range",
			func = function(state)
				local G = GryMod.FlashGrenade
				local picked = G.Pick({
					{class = "npc_grenade_frag", metres = 20, onScreen = true, own = false},
					{class = "npc_grenade_frag", metres = 8, onScreen = false, own = false}, -- behind the camera
					{class = "npc_grenade_frag", metres = 5, onScreen = true, own = true}, -- thrown by the player
					{class = "prop_physics", metres = 3, onScreen = true, own = false}, -- not a grenade
					{class = "grenade_ar2", metres = 12, onScreen = true, own = false},
					{class = "npc_grenade_frag", metres = G.RANGE + 1, onScreen = true, own = false} -- too far
				})
				expect(picked.metres).to.equal(12)
				expect(G.Pick({})).to.equal(nil)
				expect(G.Pick(nil)).to.equal(nil)
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
