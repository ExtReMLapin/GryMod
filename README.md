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
> - Eyefinity support
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
* `cl_Eyefinity`, `gry_xadd`, `gry_xdist` : Eyefinity and HUD position.
* Admins: `gry_Health` toggles the health regeneration, `gry_Armor` toggles the infinite armor (also usable from the server console).


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

Carl Mcgee : Working on GryEngine models-map 

Vuthakral Darastrix : Ideas and his work on the scar materials (now unused)

Dlaor : The original quick-menu

Sven Dixon :  Designed the original crysis interface suite
