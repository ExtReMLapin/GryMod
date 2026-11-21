-- Tests of the recovery from a graphics restore, GLuaTest format, client realm. When the engine frees and rebuilds its graphics
-- (another Garry's Mod starting: Facepunch garrysmod-issues #7137, an alt-tab, a video change), the render targets lose what was drawn
-- in them, and the interface cached in them would stay empty. The interface notices the long gap (the main thread is blocked
-- for seconds by the restore) and rebuilds itself.

local H

return {
	groupName = "GryMod graphics restore",
	beforeAll = function(state)
		H = GryMod.FlashHUD
	end,
	afterEach = function(state)
		H.ForgetPaintTime()
	end,
	cases = {
		{
			name = "a gap of two seconds or more between two paints is a graphics restore, a shorter one (a hitch) is not",
			func = function(state)
				expect(H.RESTORE_GAP).to.equal(2)
				expect(H.IsRestoreGap(0.05)).to.beFalse()
				expect(H.IsRestoreGap(1.9)).to.beFalse()
				expect(H.IsRestoreGap(2)).to.beTrue()
				expect(H.IsRestoreGap(10.2)).to.beTrue()
				expect(H.IsRestoreGap(nil)).to.beFalse()
				expect(H.IsRestoreGap(0 / 0)).to.beFalse()
			end
		},
		{
			name = "the first paint of a level never counts, the next ones count from the one before",
			func = function(state)
				local rebuilt = 0
				local real = H.ResetAll
				H.ResetAll = function() rebuilt = rebuilt + 1 end
				local results = {}
				local ok, err = pcall(function()
					results[1] = H.CheckRestore(100) -- first paint
					results[2] = H.CheckRestore(100.03)
					results[3] = H.CheckRestore(110.5) -- a 10 second block
					results[4] = H.CheckRestore(110.55)
				end)
				H.ResetAll = real
				assert(ok, err)
				expect(results[1]).to.beFalse()
				expect(results[2]).to.beFalse()
				expect(results[3]).to.beTrue()
				expect(results[4]).to.beFalse()
				expect(rebuilt).to.equal(1)
			end
		},
		{
			name = "forgetting the paint time (a new level, the HUD off) makes the next paint a first one again",
			func = function(state)
				local rebuilt = 0
				local real = H.ResetAll
				H.ResetAll = function() rebuilt = rebuilt + 1 end
				local ok, err = pcall(function()
					H.CheckRestore(50)
					H.ForgetPaintTime()
					expect(H.CheckRestore(80)).to.beFalse()
				end)
				H.ResetAll = real
				assert(ok, err)
				expect(rebuilt).to.equal(0)
			end
		},
		{
			name = "the HUD paint checks for a restore, so that a real block of the main thread rebuilds the interface",
			func = function(state)
				local seen = {}
				local real = H.CheckRestore
				H.CheckRestore = function(now) seen[#seen + 1] = now return false end
				local realDraw = GryMod.Flash.Draw
				GryMod.Flash.Draw = function() end
				local ok, err = pcall(function()
					H.Paint()
				end)
				H.CheckRestore = real
				GryMod.Flash.Draw = realDraw
				assert(ok, err)

				local ply = LocalPlayer()

				if IsValid(ply) and ply:Alive() and H.Enabled() then
					expect(#seen).to.equal(1)
					expect(isnumber(seen[1])).to.beTrue()
				end
			end
		}
	}
}
