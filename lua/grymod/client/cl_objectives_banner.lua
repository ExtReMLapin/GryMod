-- The banner of the objectives: when an objective is added, finished or failed, the top lane of the text line (cl_hud_messages_flash.lua) shows
-- "<NEW OBJECTIVE | OBJECTIVE COMPLETED | OBJECTIVE FAILED>: <title>" and a sound plays with it. In the original game this is the Messages movie, lane 1, in white, and the
-- sound is pda_update for an objective that arrives or fails and objective_completed for one that is finished (FUN_391a97b0 of the demo's CryGame.dll).
--
-- It is ONE HUD event, "objective" (docs/events.md): the data is {kind = "added" | "completed" | "failed", title = the objective's title}, the event builds
-- the line and asks the text line for it with its sound, so that the picture and the sound are never apart and the player's options cut both
-- (gry_msg_objectives for this banner, gry_hud_messages for the text lines, gry_sounds for the sound).
--
-- What starts it: the client hooks GryMod_ObjectiveAdded and GryMod_ObjectiveChanged (cl_objectives.lua), once for each real change. The list the server sends
-- when the player joins (or sends again) comes between BEGIN and END: GryMod.Objectives.Syncing() is true then and the banner is silent for it. Nothing
-- runs between two changes.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local API = GryMod.API
local Obj = GryMod.Objectives
local Messages = GryMod.Messages

if not API or not Obj or not Messages then
	return -- sh_api.lua, sh_objectives.lua and sh_messages.lua are included first (grymod_shared.lua)
end

local Banner = GryMod.ObjectivesBanner or {}
GryMod.ObjectivesBanner = Banner

local SwitchConVar = CreateClientConVar("gry_msg_objectives", "1", true, false,
	"Show a line of text and play a sound when an objective is added, finished or failed (the HUD text lines must be on too)")

-- The prefix of the line of each kind (language keys of the original game, translated by Flash.Localise from hud_boot_strings.lua) and the sound that goes with it.
Banner.KEYS = {added = "@ui_objective_added", completed = "@ui_objective_completed", failed = "@ui_objective_failed"}
Banner.SOUNDS = {
	added = "grymod/hud/pda_updated.wav",
	completed = "grymod/hud/hud_mission_accomplished.wav",
	failed = "grymod/hud/pda_updated.wav"
}

-- Which banner a change of an objective earns, or nil for none. `event` is "added" (a new objective for this client) or "changed" (its fields changed;
-- `oldState` is the state it had). Only a change of the STATE is news: the new state says the kind. `syncing` (GryMod.Objectives.Syncing()) is true while a full
-- list arrives: nothing is said for it.
function Banner.Decide(event, obj, oldState, syncing)
	if syncing or not istable(obj) or not isstring(obj.title) or obj.title == "" then
		return nil
	end

	if event ~= "added" and event ~= "changed" then
		return nil
	end

	if event == "changed" and oldState == obj.state then
		return nil
	end

	if obj.state == Obj.States.DONE then
		return "completed"
	elseif obj.state == Obj.States.FAILED then
		return "failed"
	elseif obj.state == Obj.States.ACTIVE then
		return "added"
	end

	return nil
end

-- The text is cut at a whole character: never in the middle of a multi-byte one.
local function cutAt(text, bytes)
	if #text <= bytes then
		return text
	end

	local cut = bytes

	while cut > 0 do
		local byte = string.byte(text, cut + 1)

		if byte and byte >= 0x80 and byte < 0xC0 then
			cut = cut - 1
		else
			break
		end
	end

	return string.sub(text, 1, cut)
end

-- The line of a kind for a title: the translated prefix, a colon and the title. A title that would make the line longer than the text line accepts is cut and
-- ends with "...". nil for an unknown kind or a title with nothing in it.
function Banner.Text(kind, title)
	local key = Banner.KEYS[kind]
	local clean = Messages.Clean(title)

	if not key or not clean then
		return nil
	end

	local prefix = Flash.Localise(key) .. ": "
	local room = Messages.MAX_TEXT - #prefix

	if #clean > room then
		clean = cutAt(clean, room - 3) .. "..."
	end

	return prefix .. clean
end

-- The handler of the event "objective": the line on the top lane with its sound. Returns whether the text line was asked.
function Banner.Handle(data)
	if not SwitchConVar:GetBool() or not istable(data) then
		return false
	end

	local text = Banner.Text(data.kind, data.title)

	if not text then
		return false
	end

	return API.ShowMessage(text, {lane = "top", sound = Banner.SOUNDS[data.kind]}) == true
end

API.RegisterHUDEvent("objective", Banner.Handle, {
	label = "Objective banner",
	variants = {
		{label = "Objective added", data = {kind = "added", title = "Find the key"}},
		{label = "Objective completed", data = {kind = "completed", title = "Find the key"}},
		{label = "Objective failed", data = {kind = "failed", title = "Find the key"}}
	},
	follows = {{"gry_msg_objectives", "the objective banner"}, {"gry_hud_messages", "the text lines"}, {"gry_hud", "the HUD"}, {"gry_sounds", "the sound of a line"}}
})

local function announce(event, obj, oldState)
	local kind = Banner.Decide(event, obj, oldState, Obj.Syncing())

	if kind then
		API.HUDEvent("objective", {kind = kind, title = obj.title})
	end
end

hook.Add("GryMod_ObjectiveAdded", "GryObjectiveBanner", function(_, obj)
	announce("added", obj)
end)

hook.Add("GryMod_ObjectiveChanged", "GryObjectiveBanner", function(_, obj, oldState)
	announce("changed", obj, oldState)
end)
