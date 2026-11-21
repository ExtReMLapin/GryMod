-- What the NPCs do about a camouflaged player. The cloak sets FL_NOTARGET (sv_system.lua), which keeps most NPCs from
-- picking the player as an enemy, but not all of them. Measured in game: an NPC that already had the player as an
-- enemy when he cloaked keeps him for good (and keeps shooting) if it is a strider, a hunter or a manhack; the
-- soldiers, police and antlions let him go after about seven seconds, the gunship, zombies, helicopter and rollermines at once.
-- While a player is camouflaged, the three are made neutral to him and forget him; when the cloak ends (mode
-- change, suit failure, death, disconnect) they get their old attitude back. Only what was changed is given back: an
-- NPC that was not hostile, or that another addon made friendly or neutral, is never touched.
--
-- Cost: nothing while nobody is camouflaged (no timer). Otherwise one timer every half second that searches the
-- listed classes only (ents.FindByClass, never every entity).

GryMod = GryMod or {}

local CloakAI = {}
GryMod.CloakAI = CloakAI

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)
local enabled = CreateConVar("gry_cloak_ai", "1", flags,
	"A camouflaged player is forgotten by the NPCs that ignore the cloak badly (strider, hunter, manhack); 0 leaves them alone")

local TIMER = "GryCloakAI"
local INTERVAL = 0.5

-- The classes that keep a player who cloaked in the middle of a fight for good (see above). More can be added by other code.
CloakAI.Classes = {
	"npc_strider",
	"npc_hunter",
	"npc_manhack"
}

-- [npc] = {[player] = the disposition it had before we made it neutral}; weak so that a removed NPC or player goes away
local changed = setmetatable({}, {__mode = "k"})

local function isCloaked(ply)
	return IsValid(ply) and ply:Alive() and ply.Nanosuit_mode == GryMod.Modes.CLOAK
end

local function anyCloaked()
	for _, ply in ipairs(player.GetAll()) do
		if isCloaked(ply) then
			return true
		end
	end

	return false
end

-- Gives back what was taken from the NPCs for this player (every player when ply is nil)
local function release(ply)
	for npc, perPlayer in pairs(changed) do
		if not IsValid(npc) then
			changed[npc] = nil
		else
			for p, old in pairs(perPlayer) do
				if ply == nil or p == ply then
					perPlayer[p] = nil

					if IsValid(p) then
						npc:AddEntityRelationship(p, old, 99)
					end
				end
			end

			if next(perPlayer) == nil then
				changed[npc] = nil
			end
		end
	end
end

local function hide(npc, ply)
	local mine = changed[npc]

	-- hostile NPCs only: a friendly, neutral or frightened one is not ours to change
	if not (mine and mine[ply]) and npc:Disposition(ply) == D_HT then
		mine = mine or {}
		mine[ply] = D_HT
		changed[npc] = mine
		npc:AddEntityRelationship(ply, D_NU, 99)
	end

	if npc:GetEnemy() == ply then
		npc:ClearEnemyMemory(ply)
		npc:SetEnemy(NULL)
	end
end

local function stopTimer()
	timer.Remove(TIMER)
end

function CloakAI.Tick()
	if not enabled:GetBool() then
		release()
		stopTimer()

		return
	end

	local hidden = {}

	for _, ply in ipairs(player.GetAll()) do
		if isCloaked(ply) then
			hidden[#hidden + 1] = ply
		else
			release(ply)
		end
	end

	if #hidden == 0 then
		stopTimer()

		return
	end

	for _, class in ipairs(CloakAI.Classes) do
		for _, npc in ipairs(ents.FindByClass(class)) do
			for _, ply in ipairs(hidden) do
				hide(npc, ply)
			end
		end
	end
end

-- Starts the timer for as long as somebody is camouflaged, and acts at once (the NPCs do not wait half a second)
local function refresh()
	if enabled:GetBool() and anyCloaked() then
		if not timer.Exists(TIMER) then
			timer.Create(TIMER, INTERVAL, 0, CloakAI.Tick)
		end
	end

	CloakAI.Tick()
end

hook.Add("GryNanosuitMode", "GryCloakAI", function()
	refresh()
end)

-- A dead player keeps his mode until he respawns: he is not hidden any more
hook.Add("PostPlayerDeath", "GryCloakAI", function(ply)
	release(ply)

	if not anyCloaked() then
		stopTimer()
	end
end)

hook.Add("PlayerDisconnected", "GryCloakAI", function(ply)
	release(ply)

	if not anyCloaked() then
		stopTimer()
	end
end)

cvars.AddChangeCallback("gry_cloak_ai", function()
	refresh()
end, "GryCloakAI")
