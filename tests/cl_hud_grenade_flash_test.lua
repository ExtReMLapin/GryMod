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
			name = "the stage position of a screen point: the icon's corner is half an icon (18 px) before the point, x is held inside 3 to 97 percent",
			func = function(state)
				local G = GryMod.FlashGrenade
				-- 1920 x 1080: the stage (1366 x 768) is scaled by 1080 / 768 and centred
				local scale = 1080 / 768
				local x, y = G.StagePosition(960, 540, 1920, 1080)
				expect(near(x, (960 - (1920 - 1366 * scale) / 2) / scale - 18 / scale)).to.beTrue()
				expect(near(y, 540 / scale - 18 / scale)).to.beTrue()
				-- off the left edge: held at 3 percent of the screen
				local left = G.StagePosition(-500, 540, 1920, 1080)
				local held = G.StagePosition(0.03 * 1920, 540, 1920, 1080)
				expect(near(left, held)).to.beTrue()
				local right = G.StagePosition(5000, 540, 1920, 1080)
				local heldRight = G.StagePosition(0.97 * 1920, 540, 1920, 1080)
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
