-- The administrators' switch of the night vision (client side: cl_nightvision.lua). The night vision itself is a client feature (its own energy, key
-- and screen effect); the server only says whether it is allowed at all. Replicated, so every client reads it, and in the white list of
-- sh_server_options.lua so that an administrator changes it from the options panel. 0 forbids it for everybody: a client that has it on
-- switches it off the moment the value arrives, and cannot switch it on.
-- Cost: nothing runs.

local flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

CreateConVar("gry_sv_nightvision", "1", flags, "The night vision is allowed for the players (the suit's own light amplifier, key N by default); 0 forbids it for everybody", 0, 1)
