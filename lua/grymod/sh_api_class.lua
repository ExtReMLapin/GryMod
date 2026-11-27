-- Two small questions about an entity that other addons answer in their own way (docs/api.md). Shared: both realms ask them.
--
--   GryMod.API.ClassOf(ent): the REAL class of the entity. An addon may replace Entity:GetClass (ZBase makes its NPCs answer the class of their base) and every
--   per-class lookup of GryMod (the registry of tracked entities, the radar's icon, the heavy and shock rules, the use prompt) would then see the wrong name. An adapter
--   adds a class provider that knows the real one: GryMod.API.AddClassProvider("my_addon", function(ent) return "npc_real_class" or nil end).
--
--   GryMod.API.IsCreature(ent): "this entity is a living creature for GryMod": Entity:IsNPC(), or a creature provider says so (a DrGBase nextbot is not an NPC for the
--   engine but is one for the friendly cross, the hologram and the silhouette): GryMod.API.AddCreatureProvider("my_addon", function(ent) return true or false end).
--
-- Providers run under GryMod.API.SafeCall (an error counts as no answer; the fifth in a row switches the provider off). They are asked in the order of registration.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local classProviders = API._classProviders or {}
API._classProviders = classProviders

local creatureProviders = API._creatureProviders or {}
API._creatureProviders = creatureProviders

local function add(list, prefix, key, fn)
	if not isstring(key) or key == "" then
		return false, "invalid key"
	end

	if not isfunction(fn) then
		return false, "invalid function"
	end

	local id = prefix .. ":" .. key

	API.SafeCallReset(id)

	for i = 1, #list do
		if list[i].key == key then
			list[i] = {key = key, fn = fn, id = id}

			return true
		end
	end

	list[#list + 1] = {key = key, fn = fn, id = id}

	return true
end

local function remove(list, key)
	for i = 1, #list do
		if list[i].key == key then
			table.remove(list, i)

			return true
		end
	end

	return false
end

-- Adds (or replaces, with the same key) a class provider: fn(ent) -> a class name, or nil for no opinion. Returns true, or false and why not.
function API.AddClassProvider(key, fn)
	return add(classProviders, "class", key, fn)
end

function API.RemoveClassProvider(key)
	return remove(classProviders, key)
end

-- The class of the entity: the first provider that answers a non-empty string, else Entity:GetClass. nil for something that is not a valid entity. With no provider
-- registered this is Entity:GetClass and nothing more (it is asked for many entities at every tick).
function API.ClassOf(ent)
	if not isentity(ent) and not istable(ent) then
		return nil
	end

	if not IsValid(ent) then
		return nil
	end

	for i = 1, #classProviders do
		local provider = classProviders[i]
		local ok, class = API.SafeCall(provider.id, provider.fn, ent)

		if ok and isstring(class) and class ~= "" then
			return class
		end
	end

	if isfunction(ent.GetClass) then
		return ent:GetClass()
	end

	return nil
end

-- Adds (or replaces, with the same key) a creature provider: fn(ent) -> true when the entity is a living creature for GryMod. Returns true, or false and why not.
function API.AddCreatureProvider(key, fn)
	return add(creatureProviders, "creature", key, fn)
end

function API.RemoveCreatureProvider(key)
	return remove(creatureProviders, key)
end

-- Whether the entity is a living creature for GryMod: an NPC for the engine, or a provider says yes. False for something that is not a valid entity.
function API.IsCreature(ent)
	if not isentity(ent) and not istable(ent) then
		return false
	end

	if not IsValid(ent) then
		return false
	end

	if isfunction(ent.IsNPC) and ent:IsNPC() then
		return true
	end

	for i = 1, #creatureProviders do
		local provider = creatureProviders[i]
		local ok, answer = API.SafeCall(provider.id, provider.fn, ent)

		if ok and answer == true then
			return true
		end
	end

	return false
end

API.AddFeature("class")
API.AddFeature("creature")
