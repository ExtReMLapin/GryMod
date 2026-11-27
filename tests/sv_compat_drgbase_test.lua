-- Tests of the DrGBase adapter, server side (lua/grymod/compat/npc/sv_drgbase.lua), GLuaTest format, server realm. Two things: the noises of the suit are passed on to the nextbots that
-- can hear them (DrGBase's hearing only knows the sounds a player emits; the suit's noises are not sounds, GryMod_SuitNoise tells them), and the hits on a player that is possessing a
-- nextbot are ignored by the suit (DrGBase cancels that damage itself, so the bar must not pay for it). DrGBase is stood in for. Each case names the change that makes it fail.

local API
local realDrG

local function damage(amount)
	local d = DamageInfo()

	d:SetDamage(amount)
	d:SetDamageType(DMG_BULLET)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())

	return d
end

-- a nextbot that hears: it records what it is told, and answers the questions of DrGBase's own hearing code
local function listener(fields)
	local nb = {told = {}, deaf = false, disabled = false, ignored = false, coefficient = 1, distance2 = 0}

	function nb:IsValid() return true end
	function nb:IsDeaf() return self.deaf end
	function nb:IsAIDisabled() return self.disabled end
	function nb:GetHearingCoefficient() return self.coefficient end
	function nb:IsIgnored(ply) expect(ply).toNot.beNil() return self.ignored end
	function nb:GetRangeSquaredTo(pos) expect(isvector(pos)).to.beTrue() return self.distance2 end
	function nb:OnSound(ply, sound)
		expect(sound.Pos).toNot.beNil()
		self.told[#self.told + 1] = {ply, sound}
	end

	for k, v in pairs(fields or {}) do
		nb[k] = v
	end

	return nb
end

return {
	groupName = "GryMod compat: DrGBase nextbots (server)",
	beforeEach = function()
		API = GryMod.API
		realDrG = _G.DrGBase
	end,
	afterEach = function()
		_G.DrGBase = realDrG
		API.RemoveHitFilter("t_drg_probe")
	end,
	cases = {
		{
			-- fails when the hook is not listened to (the nextbots never hear a strength jump), or when the nextbot is not told the player as the one who made it
			name = "a noise of the suit is told to a nextbot within its reach, as a sound of the player",
			func = function()
				local ply = player.GetAll()[1]
				local near = listener({distance2 = 500 * 500})

				_G.DrGBase = {GetNextbots = function() return {near} end}
				hook.Run("GryMod_SuitNoise", ply, Vector(0, 0, 0), 800, "speed_sprint")

				expect(#near.told).to.equal(1)
				expect(near.told[1][1]).to.equal(ply)
				expect(near.told[1][2].Pos).to.equal(Vector(0, 0, 0))
			end
		},
		{
			-- fails when the radius of the noise is not read (a nextbot at 2000 units hears a footstep-sized noise), or when the hearing coefficient of the nextbot is ignored
			name = "a nextbot too far for the noise does not hear it; a sharp ear (coefficient) hears farther",
			func = function()
				local ply = player.GetAll()[1]
				local far = listener({distance2 = 1000 * 1000})
				local sharp = listener({distance2 = 1000 * 1000, coefficient = 2})

				_G.DrGBase = {GetNextbots = function() return {far, sharp} end}
				hook.Run("GryMod_SuitNoise", ply, Vector(0, 0, 0), 800, "speed_sprint")

				expect(#far.told).to.equal(0)
				expect(#sharp.told).to.equal(1)
			end
		},
		{
			-- fails when a deaf nextbot, one whose AI is off, or one that ignores this player (a camouflaged one: FL_NOTARGET makes DrGBase ignore him) is told
			name = "a deaf nextbot, a nextbot with its AI off and a nextbot that ignores the player are not told",
			func = function()
				local ply = player.GetAll()[1]
				local deaf, off, ignoring = listener({deaf = true}), listener({disabled = true}), listener({ignored = true})

				_G.DrGBase = {GetNextbots = function() return {deaf, off, ignoring} end}
				hook.Run("GryMod_SuitNoise", ply, Vector(0, 0, 0), 800, "strength_jump")

				expect(#deaf.told).to.equal(0)
				expect(#off.told).to.equal(0)
				expect(#ignoring.told).to.equal(0)
			end
		},
		{
			-- fails when the hook raises an error without DrGBase, or when a broken nextbot stops the others from being told
			name = "without DrGBase nothing happens, and a nextbot that raises an error does not stop the others",
			func = function()
				local ply = player.GetAll()[1]
				local good = listener()

				_G.DrGBase = nil
				hook.Run("GryMod_SuitNoise", ply, Vector(0, 0, 0), 800, "speed_sprint")

				_G.DrGBase = {GetNextbots = function() return {{IsValid = function() error("broken nextbot") end}, good} end}
				local ok = pcall(hook.Run, "GryMod_SuitNoise", ply, Vector(0, 0, 0), 800, "speed_sprint")

				expect(ok).to.beTrue()
				expect(#good.told).to.equal(1)
			end
		},
		{
			-- fails when the possession is not a hit filter (the bar pays for damage DrGBase cancels), or when the filter ignores a player that does not possess
			name = "the suit ignores the hits on a player who is possessing a nextbot, and only on him",
			func = function()
				local possessing = {DrG_IsPossessing = function() return true end}
				local free = {DrG_IsPossessing = function() return false end}
				local plain = {}

				expect(API.AddHitFilter("t_drg_probe", function() end, -1000)).to.beTrue() -- makes sure a filter exists even when ours is gone: the verdict below is ours

				expect(API.HitVerdict(possessing, damage(10))).to.equal("ignore")
				expect(API.HitVerdict(free, damage(10))).to.beNil()
				expect(API.HitVerdict(plain, damage(10))).to.beNil()
			end
		}
	}
}
