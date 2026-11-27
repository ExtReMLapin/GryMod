-- Tests of the camouflage's energy loop (the Think hook "GryCloakThink", sv_system.lua) for a player who is dead, GLuaTest format, server realm.
-- The loop walked every player in the camouflage whether he was alive or not: the body of a player who died camouflaged kept paying for the
-- camouflage (the bar of a dead player went down, DrawWorldModel was called on a body at every tick) and, once the bar was under the limit,
-- asked for a change of mode to armor with the cause ENERGY at every tick, which the suit refuses for a dead player ("dead"). The message
-- "Temperature Camo: Disabled!" is the answer to that cause (cl_hud_messages_flash.lua), so the cause must only ever be asked for a player who is
-- alive: the camouflage stops for lack of energy, never because of a death. Fake players (the list of the loop is stubbed), no network.

local saved = {}

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

-- A player in the camouflage with `energy`, alive or not. `calls` records what the loop did to him.
local function fakePlayer(alive, energy)
	local ply = {Nanosuit_mode = GryMod.Modes.CLOAK, energy = energy, alive = alive, calls = {}}

	function ply:IsValid() return true end
	function ply:Alive() return self.alive end
	function ply:InVehicle() return false end
	function ply:GetMoveType() return MOVETYPE_WALK end
	function ply:GetVelocity() return Vector(0, 0, 0) end
	function ply:GetNW2Float(name, default) if name == "GryEnergy" then return self.energy end return default end
	function ply:SetNW2Float(name, value) if name == "GryEnergy" then self.energy = value end end
	function ply:DrawWorldModel(on) self.calls[#self.calls + 1] = "DrawWorldModel" end

	function ply:SetNanosuitMode(mode, networked, reason)
		self.calls[#self.calls + 1] = {"SetNanosuitMode", mode, reason}

		return false, "dead"
	end

	return ply
end

local function runLoop(ply)
	stub(GryMod.Players, "All", function() return {ply} end)
	stub(GryMod.Config, "InfiniteArmor", false)
	stub(GryMod.Config, "Mechanics", "crysis")

	-- the report of an energy use goes to other addons' listeners, which expect a real player: not told here
	local realRun = hook.Run
	stub(hook, "Run", function(name, ...)
		if name == "GryUseEnergy" then
			return nil
		end

		return realRun(name, ...)
	end)

	hook.GetTable().Think["GryCloakThink"]()
end

return {
	groupName = "GryMod camouflage energy loop and a dead player (server)",
	afterEach = function()
		pcall(restore)
	end,
	cases = {
		{
			name = "a dead player in the camouflage is left alone: his bar does not go down (the loop walks living players only)",
			func = function()
				local body = fakePlayer(false, 50)
				runLoop(body)

				expect(body.energy).to.equal(50)
			end
		},
		{
			name = "no change of mode is asked for a dead player, whatever his bar (the cause ENERGY is for a living player only), and his body is not touched",
			func = function()
				for _, energy in ipairs({50, 9, 0}) do
					local body = fakePlayer(false, energy)
					runLoop(body)
					restore()

					expect(#body.calls).to.equal(0)
				end
			end
		},
		{
			name = "a living player whose bar is empty still falls back to armor with the cause ENERGY (the rule the message is for)",
			func = function()
				local ply = fakePlayer(true, 0)
				runLoop(ply)

				local asked = nil

				for _, call in ipairs(ply.calls) do
					if istable(call) and call[1] == "SetNanosuitMode" then
						asked = call
					end
				end

				expect(asked).to.exist()
				expect(asked[2]).to.equal(GryMod.Modes.ARMOR)
				expect(asked[3]).to.equal(GryMod.ModeReasons.ENERGY)
			end
		},
		{
			name = "a living player in the camouflage with energy to spare still pays for it (the loop was not switched off for everybody)",
			func = function()
				local ply = fakePlayer(true, 50)
				runLoop(ply)

				expect(ply.energy < 50).to.beTrue()
			end
		}
	}
}
