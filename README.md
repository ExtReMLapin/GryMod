GryMod

[Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=153963150)

----------

Crysis for Garry's Mod
----------
           
**YOU ARE NOT ALLOWED TO RE-UPLOAD IT**
**YOU ARE NOT ALLOWED TO MAKE MONEY USING THIS MOD**


The code is kindda garbage because it's the very first project i worked on
           
           
> **Features:**

> - Crysis 1/Warhead like hud
> - Crysis 1 suit modes (Strength, Speed, Armor, Cloak and shit)
> - Crysis 1 energy system
> - Auto resizing support (Different monitors format and different sizes, so it will not look like shit)
> - Pseudo-Vectorized textures

           
How it Works 
-------------
         
Download and Put this in GarrysMod/garrysmod/addons

Open the console and bind a key to "+crysishud"  (Without quotes, don't be stupid)

Like this command
        
              bind mouse3 +crysishud          

Here, when you'll press the middle button of your mouse the QuickMenu (AKA the menu for the modes&shitz) will open
if your head spine as hell, you're running it on a non-allowed mouse gamemode
If it says "Unknow command : +crysishud", reinstall it.
    
         
         
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
* `gry_hud_style` : `classic` (default) or `crysis`, the HUD redrawn from the original Crysis Scaleform movies (see below).
* `gry_xadd`, `gry_xdist` : HUD position.
* Admins: `gry_Health` toggles the health regeneration, `gry_Armor` toggles the infinite armor (also usable from the server console).


The Crysis HUD
-------------

`gry_hud_style crysis` draws the ammo / health / energy / suit block and the compass panel from the Crysis
Scaleform movies (`HUD_AmmoHealthEnergySuit`, `HUD_RadarCompassStealth`), with their own animations and the
original ActionScript rules for the digits, the bars, the suit icon and the ammo colours. How it works:

* `tools/flash2lua/` converts the movies once, offline (Python, [FFDec](https://github.com/jindrapetrik/jpexs-decompiler)
  and the Crysis SP demo's `GameData.pak`): every shape becomes a picture in an atlas
  (`materials/grymod/flash/*.png`) and every timeline becomes Lua data (`lua/grymod/flash/*.lua`).
  `tools/flash2lua/README.md` says how to run it. The generated files are committed: the game does not need
  the converter or the demo.
* `lua/grymod/client/cl_flash.lua` plays the timelines (30 images per second, any frame rate),
  `cl_flash_draw.lua` draws them, `cl_hud_flash.lua` and `cl_hud_radar_flash.lua` are the hand-ported
  ActionScript and the link with GryMod's values.
* The compass panel has no minimap picture and no enemy icons yet; its stealth bar shows how many NPCs are near.

Tests
-------------

`tests/` holds GLuaTest-format tests for the server and the client. They run in a real game with
[gmod-mcp](https://github.com/ExtReMLapin/gmod-mcp): load a map in singleplayer, then
`tests_run` with `realm=server` on `tests/sv_grymod_test.lua` and `realm=client` on `tests/cl_grymod_test.lua`.


Releases
-------------

Publishing a GitHub release (tag `vX.Y.Z`) attaches a zip of the addon to it and uploads the addon to the
Steam Workshop (`.github/workflows/release.yml`; the secrets it needs are listed at the top of that file).
The release notes become the Workshop change note: no double quote (`"`) in them.

Credits    
----------

Lapin : Lua code, HUD materials and some others stuff

The Crysis-style HUD uses graphics and fonts taken from the Crysis Scaleform HUD files (Crytek / Electronic Arts).

Carl Mcgee : Working on GryEngine models-map 

Vuthakral Darastrix : Ideas and his work on the scar materials (now unused)

Dlaor : The original quick-menu

Sven Dixon :  Designed the original crysis interface suite
