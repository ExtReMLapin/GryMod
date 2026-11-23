-- gry_objective: a point entity for mapmakers. It gives GryMod an objective with no Lua: place it in Hammer, set the keyvalues, and drive it with inputs
-- (docs/api.md, "Objectives"). It goes through the same GryMod.API as an addon (RegisterObjective, SetObjectiveState...), so the displays and the hooks see no
-- difference.
--
-- Keyvalues: id (the objective's id; the name of the entity when empty, else "gry_objective_" and the entity index), title, description, primary (1),
--   radar (1), marker (1), startactive (0: the objective exists from the start of the map; else it waits for Activate), follow (the name of an entity to
--   follow, else the objective sits where this entity is), removeaction (remove | complete | fail: what happens when the entity it follows is removed).
-- Inputs: Activate (register it, active), Complete, Fail (register it first if needed), Remove, SetMain.
-- Outputs: OnActivated, OnCompleted, OnFailed, OnRemoved (triggered by the inputs above).
-- Nothing runs by itself: no Think, one timer at the start of the map when startactive is on.

ENT.Type = "point"
ENT.Base = "base_point"
ENT.Spawnable = false

if CLIENT then
	return
end

local OUTPUTS = {onactivated = true, oncompleted = true, onfailed = true, onremoved = true}

-- a keyvalue of Hammer is a text: "0" is off, anything else is on
local function isOn(value)
	return value ~= "0" and value ~= ""
end

function ENT:KeyValue(key, value)
	local name = string.lower(key)

	if OUTPUTS[name] then
		self:StoreOutput(key, value)

		return
	end

	if name == "id" or name == "objectiveid" then
		self.gryId = value
	elseif name == "title" then
		self.gryTitle = value
	elseif name == "description" then
		self.gryDescription = value
	elseif name == "primary" then
		self.gryPrimary = isOn(value)
	elseif name == "radar" then
		self.gryRadar = isOn(value)
	elseif name == "marker" then
		self.gryMarker = isOn(value)
	elseif name == "startactive" then
		self.gryStartActive = isOn(value)
	elseif name == "follow" then
		self.gryFollow = value
	elseif name == "removeaction" then
		self.gryRemoveAction = value
	end
end

function ENT:Initialize()
	if self.gryStartActive then
		-- not now: the entities the objective may follow are not all made yet
		timer.Simple(0, function()
			if IsValid(self) then
				self:OnStart()
			end
		end)
	end
end

-- The map has started: an objective that is active from the start is registered.
function ENT:OnStart()
	if self.gryStartActive then
		self:Define("active")
	end
end

-- The id of the objective this entity drives.
function ENT:ObjectiveId()
	if self.gryId and self.gryId ~= "" then
		return self.gryId
	end

	local name = self:GetName()

	if name and name ~= "" then
		return name
	end

	return "gry_objective_" .. self:EntIndex()
end

-- The entity to follow: the first one with the name of `follow`, if any.
function ENT:FollowTarget()
	if not self.gryFollow or self.gryFollow == "" then
		return nil
	end

	for _, found in ipairs(ents.FindByName(self.gryFollow)) do
		if IsValid(found) and found ~= self then
			return found
		end
	end

	return nil
end

-- Registers (or updates) the objective with the keyvalues, in the state asked. Returns what RegisterObjective returns.
function ENT:Define(state)
	local id = self:ObjectiveId()
	local def = {
		title = (self.gryTitle and self.gryTitle ~= "") and self.gryTitle or id,
		description = self.gryDescription or "",
		primary = self.gryPrimary ~= false,
		radar = self.gryRadar ~= false,
		marker = self.gryMarker ~= false,
		state = state,
		onRemove = self.gryRemoveAction ~= "" and self.gryRemoveAction or nil
	}

	local target = self:FollowTarget()

	if target then
		def.ent = target
	else
		def.pos = self:GetPos()
	end

	local ok, reason = GryMod.API.RegisterObjective(id, def)

	if not ok then
		MsgN("GryMod: the objective '" .. id .. "' of " .. tostring(self) .. " was refused: " .. tostring(reason))
	end

	return ok
end

-- Puts the objective in the state; it is registered first when it does not exist yet (a Complete that comes before any Activate).
function ENT:Settle(state)
	local id = self:ObjectiveId()

	if GryMod.API.GetObjective(id) then
		GryMod.API.SetObjectiveState(id, state)
	else
		self:Define(state)
	end
end

function ENT:AcceptInput(name, activator)
	if not GryMod or not GryMod.API or not GryMod.API.RegisterObjective then
		return false
	end

	name = string.lower(name)

	if name == "activate" then
		self:Define("active")
		self:TriggerOutput("OnActivated", activator)
	elseif name == "complete" then
		self:Settle("done")
		self:TriggerOutput("OnCompleted", activator)
	elseif name == "fail" then
		self:Settle("failed")
		self:TriggerOutput("OnFailed", activator)
	elseif name == "remove" then
		GryMod.API.RemoveObjective(self:ObjectiveId())
		self:TriggerOutput("OnRemoved", activator)
	elseif name == "setmain" then
		GryMod.API.SetMainObjective(self:ObjectiveId())
	else
		return false
	end

	return true
end
