GryMod

[Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=153963150)

----------

Crysis for Garry's Mod
----------
           
**YOU ARE NOT ALLOWED TO RE-UPLOAD IT**
**YOU ARE NOT ALLOWED TO MAKE MONEY USING THIS MOD**


The code is kindda garbage because it's the very first project i worked on
           
           
> **Features:**

> - The Crysis 1 HUD, quick menu, binoculars and grenade warning, drawn from the original Scaleform movies
> - Crysis 1 suit modes (Strength, Speed, Armor, Cloak and shit)
> - Crysis 1 energy and health rules (a setting gives the earlier GryMod ones back)
> - Auto resizing support (Different monitors format and different sizes, so it will not look like shit)

           
How it Works 
-------------
         
Download and Put this in GarrysMod/garrysmod/addons

Pick a key for the quick menu: when none is set, a small window asks for one every time you spawn (click the
box, press the key). Or choose it in Options > GryMod, or in the console:

              bind mouse3 +crysishud          

Hold the key, point at a mode with the mouse (the view stays where it is), release to switch. The binoculars are
the Half-Life 2 suit zoom (the zoom key). A grenade coming at you gets the red warning of the original game.
    
         
         
Developers      
-------------

##
>Here is the only NW Var used (it's a float)

* GryEnergy (0-100)




         
         
         
         
  
		
		
Settings
-------------

All of them are saved between sessions (Options > GryMod in the spawn menu, or the console):

* `gry_hud 0` : hide the HUD (health, energy, ammo, radar, compass). The quick menu and the suit abilities keep working.
* `gry_sounds 0` : mute the suit sounds.
* `gry_hud_theme` : the colours of the HUD: `blue` (the original's "Ice blue"), `default` ("Military green"), `orange` ("Amber"), `white`, the four sets the original game offers, or `custom`, which uses the three colours `gry_hud_color_line` (outlines and icons), `gry_hud_color_over` (active indicators) and `gry_hud_color_text` (digits and letters), each written `r g b` (0 to 255). The options panel has a colour mixer for each.
* One switch for each element of the interface, all on by default (`gry_hud_reset` puts them back): `gry_hud_status` (health, energy and ammo panel), `gry_hud_radar` (compass and radar panel), `gry_hud_crosshair`, `gry_hud_damage` (damage direction arcs), `gry_hud_hit` (hit marker), `gry_hud_grenade` (grenade warning), `gry_hud_binoculars`, `gry_hud_quickmenu`, `gry_hud_boot` (start-up log, shutdown animation and reboot sequence, with their sounds). The original game has no such switches, only the four colour sets and a crosshair style.
* `gry_hud_prewarm` : when the pictures of the interface are loaded. Each big one takes 0.6 to 1.3 s to decode, so the first use of the quick menu or the binoculars used to freeze the game. `1` (default): at the loading screen, for the elements that are switched on (the map takes about ten seconds longer to open); `2`: the panels of the spawn at the loading screen, the rest in short steps over the first seconds of play; `0`: when first used.
* `gry_hud_crosshair_style` : the crosshair, 1 to 13 (the original's profile uses 6).
* `gry_menu_key` : the button code of the quick menu key (the engine does not let an addon run `bind`; set it with the key picker of the options or of the prompt).
* `gry_mechanics` (server) : `crysis` (default, the original game's numbers: energy recharge 8/6/7 s after a 1 s delay, sprint, cloak and jump costs, 30 % minimum armor absorption, health back in 1 s steps after 2.5 s) or `classic` (GryMod's earlier numbers).
* `gry_xadd`, `gry_xdist` : HUD position.
* Admins: `gry_Health` toggles the health regeneration, `gry_Armor` toggles the infinite armor (also usable from the server console).


The Crysis interface
-------------

The interface is drawn from the Crysis Scaleform movies (`HUD_AmmoHealthEnergySuit`, `HUD_RadarCompassStealth`,
`HUD_QuickMenu`, `HUD_Binoculars`, `HUD_GrenadeDetect`, `HUD_Crosshair`, `HUD_FriendlyCross`, `HUD_Initialize`,
`HUD_Lost`, `HUD_Reboot`), with their own animations and the original ActionScript rules for the digits, the bars,
the suit icon, the ammo colours, the malfunction (the HUD turns red when the energy is empty, the shutdown animation
plays, then the reboot sequence when the suit comes back), the quick menu's selection, the crosshair (13 styles that
spread with what you do, open on something you can use, blink on a hit; the damage arcs show where a hit came from;
a cross on an ally) and the start-up log at every spawn. The sounds of the start-up, malfunction and reboot are the
demo's own interface sounds. How it works:

* `dev_resources/flash2lua/` converts the movies once, offline (Python, [FFDec](https://github.com/jindrapetrik/jpexs-decompiler)
  and the Crysis SP demo's `GameData.pak`): every shape becomes a picture in an atlas
  (`materials/grymod/flash/*.png`) and every timeline becomes Lua data (`lua/grymod/flash/*.lua`).
  `dev_resources/flash2lua/README.md` says how to run it. The generated files are committed: the game does not need
  the converter or the demo.
* `lua/grymod/client/cl_flash.lua` plays the timelines (30 images per second, any frame rate),
  `cl_flash_draw.lua` draws them; `cl_hud_flash.lua`, `cl_hud_radar_flash.lua`, `cl_hud_quickmenu_flash.lua`,
  `cl_hud_binoculars_flash.lua`, `cl_hud_grenade_flash.lua`, `cl_hud_crosshair_flash.lua` and
  `cl_hud_boot_flash.lua` are the hand-ported ActionScript and the link with GryMod's values;
  `lua/grymod/server/sv_feedback.lua` tells the client where damage came from and when the player hit something.
* The compass panel has no minimap picture and no enemy icons yet; its stealth bar shows how many NPCs are near.
  Not ported: the binoculars' horizon ladder and target locks, pickups, use icons, mission markers (a survey of every
  movie is in the research notes of the branch's author). The crosshair's spread is estimated from what the player
  does (speed, air, crouch, shots) because Garry's Mod weapons have no common spread value, and "friendly" means a
  teammate or one of the Half-Life 2 rebels' NPC classes.

Tests
-------------

`tests/` holds GLuaTest-format tests for the server and the client. They run in a real game with
[gmod-mcp](https://github.com/ExtReMLapin/gmod-mcp): load a map in singleplayer, then
`tests_run` with `realm=server` on `tests/sv_grymod_test.lua` and `realm=client` on `tests/cl_grymod_test.lua`.


Releases
-------------

Publishing a GitHub release (tag `4.3` or `v4.3`) attaches a zip of the addon to it and uploads the addon to the
Steam Workshop (`.github/workflows/release.yml`; the secrets it needs are listed at the top of that file).
The release notes become the Workshop change note: no double quote (`"`) in them.

Before anything is published a `verify` job checks the Lua, the compiled shaders, the package (file types, names, size,
version) and that the Workshop id of the `WORKSHOP_ID` secret is the `GryMod.WSID` of the code. A rehearsal that publishes
nothing: Actions > Release > Run workflow. The same checks run locally:

    python tools/prepare_release.py --version 4.3 --out dist/workshop --workshop --expect-wsid <the item id>
    python tools/check_lua_syntax.py            # needs: pip install lupa
    python dev_resources/shaders/check_compiled.py

The compiled shaders (`shaders/fxc/*.vcs`) are committed: after changing a `.hlsl`, recompile it
(`dev_resources/shaders/README.md`) and run `check_compiled.py --update`.

Credits    
----------

Lapin : Lua code, HUD materials and some others stuff

The Crysis-style HUD uses graphics and fonts taken from the Crysis Scaleform HUD files (Crytek / Electronic Arts).

Carl Mcgee : Working on GryEngine models-map 

Vuthakral Darastrix : Ideas and his work on the scar materials (now unused)

Dlaor : The original quick-menu

Sven Dixon :  Designed the original crysis interface suite
