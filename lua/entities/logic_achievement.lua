-- Half-Life 2's achievement relay. Garry's Mod does not make it: a map that fires it finds no target, and the signal is lost. Many story steps of the campaigns
-- (the can in the bin, the gravity gun...) are marked by it, and GryMod's campaign objectives listen to its inputs (GM:AcceptInput). This stand-in only has to exist
-- on the map, so that the input has somewhere to go: it does nothing itself.
ENT.Type = "point"

function ENT:Initialize()
end

function ENT:KeyValue(key, value)
	if key == "AchievementEvent" then
		self.AchievementEvent = value
	end
end
