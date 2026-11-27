# lua/grymod/campaign

The objectives of the Half-Life 2, Episode One and Episode Two maps, one file for each map that has something to say (`hl2/d1_canals_01.lua`, `ep1/...`, `ep2/...`). **Generated; do not edit by hand.**

`lua/grymod/server/sv_campaign.lua` reads only the file of the map being played, registers its objectives with `GryMod.API.RegisterObjective` and follows the map's own events to complete them. The files are not listed in the loader (`tools/test_loader_coverage.py` skips this folder): the runtime compiles the file of the current map by name.

The files are built by `dev_resources/campaign/build_campaign.py`: rules applied to the entity lump of each map, read from the game's own `.bsp` files, plus hand-curated maps whose claims are checked against the map. The maps are only read, never copied. Run it with `--check` to verify that the committed files are what the maps give. Other addons add or change objectives with `GryMod.API.RegisterCampaignMap` and `GryMod.API.OverrideCampaignObjective` ([`docs/reference/objectives.md`](../../../docs/reference/objectives.md)).
