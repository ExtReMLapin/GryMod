"""What the notes and the code say about the elements that the static analysis (unused_elements.py) cannot judge alone.

HIDDEN[film]: placements (dotted path of instance names from the root; an unnamed clip is `#<char id>`) that our module hides on
    purpose, with the file:line that does it. The placements the film itself puts off the stage are found by the tool.
VERDICTS: (film, kind, name) -> dict. kind is "function", "label" or "clip"; a label can be given as "name@clip id" to
    judge one clip's label. Keys of the dict:
      cls      used (ported), a (nothing to do), b (possibly missing feature), c (orphan in the original), d (undecided)
      what     what it is on the screen
      game     what the original does with it (the C++ side, from the research notes)
      source   where that is said (file:line of the notes, the ActionScript dump, our module)
      effort   S / M / L
      missed   the row of 2026-11-21-missed-behaviours-audit.md that already lists it, if any
      priority how much a player would see it: high / medium / low / none

Paths: `research-*` are the notes and `research-ui/scripts/HUD_*` the ActionScript dump, all under D:/dev/crysis-hud-research (not in
this repository); `docs/...` and `lua/...` are in this repository.
"""

NOTES = "research-ui2/crosshair-reboot.md"
UI = "research-ui/NOTES.md"
QM = "research-qm/NOTES.md"
AUDIT = "docs/superpowers/plans/2026-11-21-missed-behaviours-audit.md"
RADAR = "docs/superpowers/plans/2026-11-21-radar-research.md"
MAPS = "docs/superpowers/plans/2026-11-21-map-zoom-research.md"
BINO = "docs/superpowers/plans/2026-11-21-binoculars-features.md"
TRIAGE = "docs/superpowers/plans/2026-11-21-film-audit-triage.md"
AS = "research-ui/scripts/HUD_%s/scripts/frame_1/DoAction.as"

AMMO = "hud_ammohealthenergysuit"
QUICK = "hud_quickmenu"
RADAR_FILM = "hud_radarcompassstealth"
CROSS = "hud_crosshair"
BINOC = "hud_binoculars"
GREN = "hud_grenadedetect"
INIT = "hud_initialize"
REBOOT = "hud_reboot"
LOST = "hud_lost"

HIDDEN = {
    AMMO: {
        "Root.Tank": "lua/grymod/client/cl_hud_flash.lua:112-118 (the vehicle layouts are never shown)",
        "Root.VTOL": "lua/grymod/client/cl_hud_flash.lua:112-118",
        "Root.EmptyHUD": "lua/grymod/client/cl_hud_flash.lua:112-118",
        "Root.Player.OverheatBar": "lua/grymod/client/cl_hud_flash.lua:123-127",
    },
    QUICK: {
        "Root.CriticalArea": "lua/grymod/client/cl_hud_quickmenu_flash.lua:246-249 (the legacy critical gauge)",
    },
    RADAR_FILM: {
        "Root.RadarCompassStealth.Indicator": "lua/grymod/client/cl_hud_radar_flash.lua:85-89 (the ring is hidden; Panel:SetDamage, :191-208, is never called)",
    },
    BINOC: {
        "Root.Binoculars.TargetIconTL": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390 (_hideTargets)",
        "Root.Binoculars.TargetIconTR": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconBL": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconBR": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconLockTL": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconLockTR": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconLockBL": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.TargetIconLockBR": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390",
        "Root.Binoculars.#51": "lua/grymod/client/cl_hud_binoculars_flash.lua:383-390 (LOCK_SYMBOL: the lock symbol has no instance name)",
    },
}


def _ported(what, source):
    return {"cls": "used", "what": what, "source": source}


THEME = "the theme colour reaches the colour-set clips through the converter's `color` actions (Clip:_colorChild)"
THEME_SRC = "lua/grymod/client/cl_hud_flash.lua:14-36 (Themes), lua/grymod/client/cl_flash.lua:415-427"
RESET = "ported as a rebuild of every piece on a theme change"
RESET_SRC = "lua/grymod/client/cl_hud_flash.lua:1098-1111 (Module.ResetAll)"

VERDICTS = {
    # ---------------------------------------------------------------- AmmoHealthEnergySuit
    (AMMO, "function", "setLineColor"): _ported(THEME, THEME_SRC),
    (AMMO, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (AMMO, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (AMMO, "function", "resetColor"): _ported(RESET, RESET_SRC),
    (AMMO, "function", "setFireMode"): _ported("the fire-mode icon of the weapon slot", "lua/grymod/client/cl_hud_flash.lua:234-266 (HUD:SetAmmo carries the mode), :395-410 (fillSlot AmmoMode)"),
    (AMMO, "function", "reboot"): {
        "cls": "used", "what": "RebootHUD's reboot(): the suit icon of the current mode plays its reboot animation",
        "source": "lua/grymod/client/cl_hud_flash.lua:413, :440-447 (HUD:Destroy(0) then GotoAndPlay('reboot'), switch gry_icon_reboot)",
        "game": "the film's own reboot() also plays Root/Player 'normal', which Destroy(0) does too"},
    (AMMO, "function", "updateAmmoMode"): {
        "cls": "a", "what": "internal: shows the layout (Player / Tank / VTOL / Empty) chosen by setAmmoMode",
        "source": "lua/grymod/client/cl_hud_flash.lua:104-131 (_resolve: always the Player layout)"},
    (AMMO, "function", "setAmmoMode"): {
        "cls": "b", "what": "the HUD layout of a vehicle (tank, VTOL, AAA, helicopter, boat, APC, hover, truck, LTV, gunner, empty): own icons, own bars",
        "game": "setAmmoMode(0..20) picks the layout; 0 and 5 are the player's", "effort": "L", "missed": "B6", "priority": "low",
        "source": AUDIT + ":74 and :251-252; " + AS % "AmmoHealthEnergySuit" + " (setAmmoMode)"},
    (AMMO, "function", "setTankIcons"): {
        "cls": "b", "what": "the two weapon icons (PriIcon, SecIcon) of the tank / VTOL layout",
        "game": "called by setAmmoMode for the vehicle layouts", "effort": "L (with B6)", "missed": "B6", "priority": "low",
        "source": AUDIT + ":93"},
    (AMMO, "function", "setTankName"): {
        "cls": "c", "what": "the vehicle's name", "game": "the function body is empty in this build",
        "source": AS % "AmmoHealthEnergySuit" + ": setTankName = function(_strName) { };"},
    (AMMO, "function", "setReloadDuration"): {
        "cls": "b", "what": "the reload bar of the vehicle layouts (ReloadBar)", "game": "vehicle layouts only: the Player clip has no ReloadBar",
        "effort": "L (with B6)", "missed": "B6", "priority": "low", "source": AUDIT + ":93"},
    (AMMO, "function", "setReloadDuration2"): {
        "cls": "b", "what": "the second reload bar of the vehicle layouts (ReloadBar2)", "game": "vehicle layouts only",
        "effort": "L (with B6)", "missed": "B6", "priority": "low", "source": AUDIT + ":93"},
    (AMMO, "function", "showReloadDuration2"): {
        "cls": "b", "what": "shows ReloadBar2 of the current vehicle layout", "game": "vehicle layouts only", "effort": "L (with B6)",
        "missed": "B6", "priority": "low", "source": AUDIT + ":93"},
    (AMMO, "function", "hideReloadDuration2"): {
        "cls": "b", "what": "hides ReloadBar2 of the current vehicle layout", "game": "vehicle layouts only", "effort": "L (with B6)",
        "missed": "B6", "priority": "low", "source": AUDIT + ":93"},
    (AMMO, "function", "setOverheatBar"): {
        "cls": "b", "what": "a bar under the ammo digits that fills while a weapon overheats (Player.OverheatBar, 100 frames)",
        "game": "sent only when the current weapon says it has a heat value; crosshair ids 12 and 13 are tied to the same modes",
        "effort": "S (needs a heat value: ARC9 / TFA heat)", "missed": "B7", "priority": "medium",
        "source": AUDIT + ":75 and :253; our module hides the bar: lua/grymod/client/cl_hud_flash.lua:123-127"},
    (AMMO, "function", "setOverheatBar2"): {
        "cls": "b", "what": "the same bar of the tank / VTOL layouts", "game": "vehicle layouts", "effort": "L (with B6)", "missed": "B7",
        "priority": "low", "source": AUDIT + ":75"},
    (AMMO, "label", "restart@241"): _ported("resetColor() -> Root.gotoAndPlay('restart'): the colours were changed", RESET_SRC),
    (AMMO, "label", "restart"): {
        "cls": "c", "what": "the per-clip restart frame", "game": "nothing in the film jumps to it (only the root's `restart` is reached, by resetColor)",
        "source": "data: hud_ammohealthenergysuit.lua (sprites 62, 73, 227, 239, 240); AS: no gotoAndPlay('restart') but in resetColor"},
    (AMMO, "label", "end@223"): {
        "cls": "c", "what": "last frame of the overheat bar", "game": "the bar is set by frame number (1..100): `end` (101) is not a state",
        "source": AS % "AmmoHealthEnergySuit" + " setOverheatBar: OverheatBar.gotoAndStop(_Value)"},
    (AMMO, "label", "end@238"): {
        "cls": "b", "what": "last frame of the vehicle's second reload bar", "game": "vehicle layouts", "effort": "L (with B6)", "missed": "B6",
        "priority": "low", "source": AS % "AmmoHealthEnergySuit" + " (showReloadDuration2, setAmmoMode)"},
    (AMMO, "label", "mounted"): {
        "cls": "c", "what": "the 'mounted' picture of the tank's secondary weapon icon", "game": "no function of the film jumps to it",
        "source": "data: hud_ammohealthenergysuit.lua:1555; AS: setTankIcons names other labels"},
    (AMMO, "label", "flashbang"): {
        "cls": "b", "what": "hand grenade icon: flash grenade", "game": "setAmmo carries the grenade kind: explosivegrenade, flashbang, smokegrenade, empgrenade",
        "effort": "S (map the GMod grenade weapon / ammo to a kind)", "priority": "low",
        "source": "lua/grymod/client/cl_hud_flash.lua:936 (the feed always passes 'explosivegrenade'); " + UI + " (GrenadeDetect: the kinds)"},
    (AMMO, "label", "smokegrenade"): {
        "cls": "b", "what": "hand grenade icon: smoke grenade", "game": "same as flashbang", "effort": "S", "priority": "low",
        "source": "lua/grymod/client/cl_hud_flash.lua:936"},
    (AMMO, "label", "empgrenade"): {
        "cls": "b", "what": "hand grenade icon: EMP / nano disruptor grenade", "game": "same as flashbang", "effort": "S", "priority": "low",
        "source": "lua/grymod/client/cl_hud_flash.lua:936"},
    (AMMO, "clip", "PriIcon"): {"cls": "b", "what": "tank layout: primary weapon icon", "game": "setTankIcons", "effort": "L (with B6)", "missed": "B6",
                                "priority": "low", "source": "lua/grymod/client/cl_hud_flash.lua:112-118 hides Root.Tank"},
    (AMMO, "clip", "SecIcon"): {"cls": "b", "what": "tank layout: secondary weapon icon", "game": "setTankIcons", "effort": "L (with B6)", "missed": "B6",
                                "priority": "low", "source": "lua/grymod/client/cl_hud_flash.lua:112-118 hides Root.Tank"},
    (AMMO, "clip", "ReloadBar"): {"cls": "b", "what": "tank / VTOL layout: reload bar", "game": "setReloadDuration", "effort": "L (with B6)", "missed": "B6",
                                  "priority": "low", "source": "lua/grymod/client/cl_hud_flash.lua:112-118"},
    (AMMO, "clip", "ReloadBar2"): {"cls": "b", "what": "tank layout: second reload bar", "game": "setReloadDuration2", "effort": "L (with B6)", "missed": "B6",
                                   "priority": "low", "source": "lua/grymod/client/cl_hud_flash.lua:112-118"},

    # ---------------------------------------------------------------- QuickMenu
    (QUICK, "function", "setLineColor"): _ported(THEME, THEME_SRC + "; lua/grymod/client/cl_hud_quickmenu_flash.lua:225-232 (Menu.New takes the theme)"),
    (QUICK, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (QUICK, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (QUICK, "function", "resetColor"): _ported(RESET, "lua/grymod/client/cl_hud_flash.lua:1098-1111, lua/grymod/client/cl_hud_quickmenu_flash.lua:690-696 (Menu.Reset)"),
    (QUICK, "function", "setAlpha"): {
        "cls": "a", "what": "Root._alpha = a * 100", "game": "the C++ only sets _alpha = 100 when the menu opens (the film's default)",
        "source": QM + ":10 (PRESS: Invoke showQuickMenu; _alpha=100)"},
    (QUICK, "function", "showQuickMenu"): _ported("opens the menu", "lua/grymod/client/cl_hud_quickmenu_flash.lua:270-281 (Instance:Open)"),
    (QUICK, "function", "hideQuickMenu"): _ported("closes the menu", "lua/grymod/client/cl_hud_quickmenu_flash.lua:283-291 (Instance:Close)"),
    (QUICK, "function", "setActive"): _ported("which modes can be chosen", "lua/grymod/client/cl_hud_quickmenu_flash.lua:294-297 (SetStates), :491-500 (feedStates)"),
    (QUICK, "function", "setDefect"): _ported("which modes are defective", "lua/grymod/client/cl_hud_quickmenu_flash.lua:294-297 (SetStates)"),
    (QUICK, "function", "makeBlink"): {
        "cls": "c", "what": "would make a mode icon blink (frame 5 of each mode clip, with its Blink clip)",
        "game": "the function body is empty: nothing can reach frame 5",
        "source": "research-ui/scripts/HUD_QuickMenu/scripts/frame_1/DoAction.as:165-167; " + AUDIT + ":97; " + QM + " (Pitfalls: frames 5 and Default unused)"},
    (QUICK, "label", "restart"): _ported("resetColor(): the colours were changed", RESET_SRC),
    (QUICK, "label", "bothOpen"): {
        "cls": "c", "what": "the 'critical area' gauge (OVERLOAD / STABLE, SUIT ENERGY and CLOAK bars) opening",
        "game": "the C++ drives only Root.QuickMenu (SetVariable ...Circle.Indicator._rotation, Invoke ...setAutosnapItem, showQuickMenu, hideQuickMenu)",
        "source": QM + " (C++ paragraphs); our module hides the gauge: lua/grymod/client/cl_hud_quickmenu_flash.lua:246-249"},
    (QUICK, "label", "bothClose"): {"cls": "c", "what": "the same gauge closing", "game": "see bothOpen", "source": QM},
    (QUICK, "label", "CloakOpen"): {"cls": "c", "what": "the same gauge, cloak part", "game": "see bothOpen", "source": QM},
    (QUICK, "label", "CloakClose"): {"cls": "c", "what": "the same gauge, cloak part", "game": "see bothOpen", "source": QM},
    (QUICK, "label", "EnergyOpen"): {"cls": "c", "what": "the same gauge, energy part", "game": "see bothOpen", "source": QM},
    (QUICK, "label", "EnergyClose"): {"cls": "c", "what": "the same gauge, energy part", "game": "see bothOpen", "source": QM},
    (QUICK, "clip", "Blink"): {
        "cls": "c", "what": "the blink of a mode icon", "game": "reached only through makeBlink, which is empty",
        "source": "research-ui/scripts/HUD_QuickMenu/scripts/frame_1/DoAction.as:165-167"},

    # ---------------------------------------------------------------- RadarCompassStealth
    (RADAR_FILM, "function", "setLineColor"): _ported(THEME, THEME_SRC + "; lua/grymod/client/cl_hud_radar_flash.lua:26-44"),
    (RADAR_FILM, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (RADAR_FILM, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (RADAR_FILM, "function", "setNoiseValue"): _ported("the noise over the units while the suit malfunctions (Noise, Units alpha)", "lua/grymod/client/cl_hud_radar_flash.lua:70-92, :99-110"),
    (RADAR_FILM, "function", "Noise"): {"cls": "a", "what": "internal: starts the noise loop", "source": "lua/grymod/client/cl_hud_radar_flash.lua:103-108 (noise:GotoAndPlay('loop'))"},
    (RADAR_FILM, "function", "setCompassRotation"): _ported("the heading strip", "lua/grymod/client/cl_hud_radar_flash.lua:137-147 (Panel:SetHeading), lua/grymod/client/cl_hud_flash.lua:1043"),
    (RADAR_FILM, "function", "setView"): {
        "cls": "a", "what": "rotates the view cone clip", "game": "the C++ resets it to 0 (the cone points up)", "source": AUDIT + ":94"},
    (RADAR_FILM, "function", "setObjectArray"): _ported("the contacts (Units / ObjectIcon)", "lua/grymod/client/cl_hud_radar_units.lua:176-243 (Panel:SetObjects), :369 (Radar.Feed)"),
    (RADAR_FILM, "function", "reboot"): _ported("plays the film's reboot label", "lua/grymod/client/cl_hud_radar_flash.lua:99-123 (Destroy(0): to_normal, whose frames run into reboot)"),
    (RADAR_FILM, "function", "QuickLoaded"): {
        "cls": "a", "what": "resets NoisePlaying after a quick load", "game": "internal flag of the film", "source": AS % "RadarCompassStealth" + " (QuickLoaded)"},
    (RADAR_FILM, "function", "setDamage"): {
        "cls": "c", "what": "the red ring around the radar (Indicator, frame = value * 100 + 1)",
        "game": "the radar's scan progress for a vehicle with a 'radar' parameter (AAA), not on foot",
        "source": RADAR + ":166-167; the port defines Panel:SetDamage (lua/grymod/client/cl_hud_radar_flash.lua:191-208) and nothing calls it"},
    (RADAR_FILM, "function", "setScanningEffect"): {
        "cls": "c", "what": "shows the same ring while a scan runs", "game": "the same vehicle case; not called on foot",
        "source": RADAR + ":166-167; " + AUDIT + ":94"},
    (RADAR_FILM, "function", "setPlayer"): {
        "cls": "b", "what": "places the map picture under the units (the player's position and rotation)", "game": "setObjectArray calls it every frame",
        "effort": "L (a picture per map)", "priority": "medium", "missed": "A1 (the minimap is named there as not needed for the dots)",
        "source": MAPS + ":62, :75-86; " + AUDIT + ":134-136"},
    (RADAR_FILM, "function", "setMapBackground"): {
        "cls": "b", "what": "the level's mini map picture behind the radar units (cvar hud_radarBackground, default 1)",
        "game": "one picture per level, world rectangle written by the designers",
        "effort": "S (no picture) / M (trace grid) / L (render)", "priority": "medium", "missed": "A1",
        "source": MAPS + ":62 and :75-86 (options 1 to 3)"},
    (RADAR_FILM, "function", "setMapScale"): {
        "cls": "b", "what": "the scale of that picture", "game": "with the picture", "effort": "with setMapBackground", "priority": "medium", "missed": "A1",
        "source": MAPS + ":62"},
    (RADAR_FILM, "label", "restart"): {
        "cls": "c", "what": "the film's restart frame", "game": "frame 27: nothing in the film or in resetColor of this movie jumps to it",
        "source": TRIAGE + ":169 (RebootState, dead code)"},
    (RADAR_FILM, "label", "reboot@196"): {
        "cls": "c", "what": "the boot-up animation of the cone clip", "game": "the root's `reboot` plays on into it only through frames our Destroy(0) already runs",
        "source": "data: hud_radarcompassstealth.lua:1200"},
    (RADAR_FILM, "label", "play"): {
        "cls": "c", "what": "the second frame of an icon (play after stop)", "game": "no script jumps to it", "source": "data: hud_radarcompassstealth.lua:742"},
    (RADAR_FILM, "label", "Sound"): {
        "cls": "c", "what": "the arrow icon of type 6 (a sound)", "game": "the HUD code produces types 1 to 4 only", "source": RADAR + ":152"},
    (RADAR_FILM, "label", "Waypont"): {
        "cls": "c", "what": "the arrow icon of a waypoint", "game": "the HUD code produces types 1 to 4 only", "source": RADAR + ":152"},
    (RADAR_FILM, "clip", "MapArea"): {
        "cls": "b", "what": "the map picture area (Map holds the loaded picture)", "game": "setPlayer / setMapBackground", "effort": "L", "priority": "medium",
        "missed": "A1", "source": MAPS + ":62"},
    (RADAR_FILM, "clip", "Map"): {
        "cls": "b", "what": "the clip that loads the map picture", "game": "loadMovie('img://' + m_MapBackground)", "effort": "L", "priority": "medium",
        "source": "research-ui/scripts/HUD_RadarCompassStealth/scripts/DefineSprite_12/frame_1/DoAction.as"},
    (RADAR_FILM, "clip", "Line2"): {"cls": "c", "what": "an extra line of the damage ring", "game": "inside the Indicator ring", "source": "data: hud_radarcompassstealth.lua:905"},

    # ---------------------------------------------------------------- Crosshair
    (CROSS, "function", "setLineColor"): _ported(THEME, THEME_SRC),
    (CROSS, "function", "setVisible"): {
        "cls": "c", "what": "_visible = b", "game": "never called by the demo's C++ (hiding is crosshair id 0)",
        "source": NOTES + ":16 and :68; the port keeps Instance:SetVisible (lua/grymod/client/cl_hud_crosshair_flash.lua:359)"},
    (CROSS, "function", "setOpacity"): {
        "cls": "d", "what": "Root._alpha = a * 100: the timed fade of the whole crosshair",
        "game": "sent by CPlayer::Update from a player field (a linear fade); who starts the fade is not resolved (probably cinematics)",
        "effort": "S", "priority": "none",
        "source": NOTES + ":68; the port keeps Instance:SetOpacity (lua/grymod/client/cl_hud_crosshair_flash.lua:364), nothing calls it"},
    (CROSS, "function", "setHit"): {
        "cls": "c", "what": "sets the blink flags g_bBlinking / g_fHitTime", "game": "declared and never read by any script: a no-op",
        "source": AUDIT + ":96; " + NOTES + ":21 and :66"},
    (CROSS, "function", "indicateHit"): _ported("the lines blink ('hit' label)", "lua/grymod/client/cl_hud_crosshair_flash.lua:412-427 (Instance:Hit), :535-539 (Cross.NotifyHit)"),
    (CROSS, "function", "setUsable"): _ported("the use prompt (frames 2..8 / 14..20 by number)", "lua/grymod/client/cl_hud_crosshair_flash.lua:140-144 (USABLE), :429-436 (SetUsable)"),
    (CROSS, "function", "clearDamageDirection"): {
        "cls": "b", "what": "stops the four damage arcs at once", "game": "called by the HUD hide path when the HUD is destroyed (FUN_391b42a0)",
        "effort": "S", "priority": "low",
        "source": NOTES + ":68 and :89; the port defines Instance:ClearDamageDirection (lua/grymod/client/cl_hud_crosshair_flash.lua:449-461) and nothing calls it"},
    (CROSS, "label", "useOn"): _ported("setUsable(1): the use prompt fades in", "lua/grymod/client/cl_hud_crosshair_flash.lua:140-144 (USABLE: frames 2, 8, 14, 20 by number)"),
    (CROSS, "label", "useOff"): _ported("setUsable(0)", "lua/grymod/client/cl_hud_crosshair_flash.lua:140-144"),
    (CROSS, "label", "useOn2"): _ported("setUsable(2): the 'blocked' variant", "lua/grymod/client/cl_hud_crosshair_flash.lua:140-144"),
    (CROSS, "label", "useOff2"): _ported("setUsable(0) from the blocked variant", "lua/grymod/client/cl_hud_crosshair_flash.lua:140-144"),
    (CROSS, "clip", "Tagg"): {
        "cls": "d", "what": "a tag mark inside crosshair 9", "game": "crosshair 9 is reachable only through the cvar hud_crosshair; no script of the film touches Tagg",
        "source": NOTES + ":55; data: hud_crosshair.lua:840"},
    (CROSS, "clip", "Colorset2"): {"cls": "c", "what": "a colour holder of crosshair 2", "game": "no script touches it", "source": "data: hud_crosshair.lua:88"},

    # ---------------------------------------------------------------- Binoculars
    (BINOC, "function", "setLineColor"): _ported(THEME, THEME_SRC),
    (BINOC, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (BINOC, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (BINOC, "function", "setVisible"): _ported("opens the movie (frame 1 play)", "lua/grymod/client/cl_hud_binoculars_flash.lua:219-233 (Instance:Show), :255-259 (Hide)"),
    (BINOC, "function", "closeBinoculars"): _ported("plays the close animation and the vignette's fade", "lua/grymod/client/cl_hud_binoculars_flash.lua:239-252 (Instance:Close)"),
    (BINOC, "function", "setAlpha"): {
        "cls": "d", "what": "Root._alpha = a * 100 (a fade of the whole movie)", "game": "no caller found in the notes (the movie lists it)",
        "effort": "S", "priority": "none", "source": UI + " (Binoculars functions); " + BINO + ":93 (F20)"},
    (BINOC, "function", "destroy"): {
        "cls": "b", "what": "the binoculars' own malfunction look (Root: malfunction / malfunctionOn / flickering frames, then normal)",
        "game": "the HUD's destroy path calls destroy(1) on every movie; whether it reaches the binoculars was not traced",
        "effort": "S", "priority": "low", "source": NOTES + ":139; " + BINO + ":93 (F20: not done)"},
    (BINOC, "label", "malfunction"): {
        "cls": "b", "what": "the red malfunction animation of the binoculars", "game": "destroy(1)", "effort": "S", "priority": "low",
        "source": BINO + ":93 (F20)"},
    (BINOC, "label", "malfunctionOn"): {"cls": "b", "what": "its steady malfunction frame", "game": "destroy(1)", "effort": "S", "priority": "low", "source": BINO + ":93"},
    (BINOC, "label", "flickering"): {"cls": "b", "what": "the flicker animation", "game": "destroy(2)", "effort": "S", "priority": "low", "source": BINO + ":93"},
    (BINOC, "label", "reboot"): {
        "cls": "c", "what": "the binoculars' boot-up animation",
        "game": "RebootHUD calls reboot() on AmmoHealthEnergySuit, Ammo, HealthEnergy, RadarCompassStealth and PDA_Map only", "source": NOTES + ":130"},
    (BINOC, "label", "restart"): {
        "cls": "c", "what": "restart frame", "game": "this movie has no resetColor",
        "source": "research-ui/scripts/HUD_Binoculars/scripts/frame_1/DoAction.as (functions: no resetColor)"},
    (BINOC, "label", "TargetLock"): {
        "cls": "c", "what": "the lock state of the target brackets", "game": "the TargetIcon* clips are placed by code the demo never calls for the binoculars",
        "source": BINO + ":74 (F19)"},

    # ---------------------------------------------------------------- GrenadeDetect
    (GREN, "function", "showGrenadeDetector"): _ported("shows the warning", "lua/grymod/client/cl_hud_grenade_flash.lua:178-186 (Instance:Show)"),
    (GREN, "function", "hideGrenadeDetector"): _ported("hides it", "lua/grymod/client/cl_hud_grenade_flash.lua:189-192 (Instance:Hide)"),
    (GREN, "function", "setGrenadeType"): _ported("the kind of grenade (text)", "lua/grymod/client/cl_hud_grenade_flash.lua:201-204 (SetType), :75 (Grenade.TypeFor)"),
    (GREN, "function", "setAlpha"): {
        "cls": "d", "what": "Root._alpha = a * 100", "game": "no caller found in the notes (the C++ writes _x and _y of GrenadeDetect every frame)",
        "effort": "S", "priority": "none", "source": UI + " (GrenadeDetect)"},
    (GREN, "function", "morphLeft"): {"cls": "c", "what": "(empty function)", "game": "empty", "source": UI + " (GrenadeDetect: morphLeft/Right/None EMPTY (dead))"},
    (GREN, "function", "morphRight"): {"cls": "c", "what": "(empty function)", "game": "empty", "source": UI + " (GrenadeDetect)"},
    (GREN, "function", "morphNone"): {"cls": "c", "what": "(empty function)", "game": "empty", "source": UI + " (GrenadeDetect)"},
    (GREN, "label", "morphLeft"): {"cls": "c", "what": "a hexagon morph to the left", "game": "morphLeft() is empty", "source": UI + " (GrenadeDetect)"},
    (GREN, "label", "morphRight"): {"cls": "c", "what": "a hexagon morph to the right", "game": "morphRight() is empty", "source": UI + " (GrenadeDetect)"},

    # ---------------------------------------------------------------- Initialize, Reboot, Lost
    (INIT, "function", "setLineColor"): _ported(THEME, THEME_SRC + "; lua/grymod/client/cl_hud_boot_flash.lua:44 (Boot.New takes the theme)"),
    (INIT, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (INIT, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (INIT, "function", "resetColor"): _ported("Root.gotoAndPlay('restart')", "lua/grymod/client/cl_hud_boot_flash.lua:94-101 (Sequence:Start)"),
    (REBOOT, "function", "setLineColor"): _ported(THEME, THEME_SRC),
    (REBOOT, "function", "setOverColor"): _ported(THEME, THEME_SRC),
    (REBOOT, "function", "setTextColor"): _ported(THEME, THEME_SRC),
    (REBOOT, "function", "setStatus"): _ported("the four load bars stop on their second frame", "lua/grymod/client/cl_hud_boot_flash.lua:73-83"),
    (REBOOT, "function", "showProgressBar"): _ported("opens / closes the six clips", "lua/grymod/client/cl_hud_boot_flash.lua:58-86 (Sequence:_showProgressBar)"),
    (REBOOT, "function", "reboot"): _ported("showProgressBar(true)", "lua/grymod/client/cl_hud_boot_flash.lua:102-104"),
    (REBOOT, "clip", "Bar01"): {"cls": "c", "what": "an outline bar", "game": "no script touches it", "source": "data: hud_reboot.lua:315"},
    (LOST, "function", "resetColor"): {"cls": "a", "what": "empty in this movie", "game": "the Lost movie has no colour sets", "source": NOTES + ":137"},
    (LOST, "label", "update"): {
        "cls": "a", "what": "the last frame, where the loop restarts", "game": "its own script jumps back to frame 1",
        "source": NOTES + ":137 (frame 138: gotoAndPlay(1))"},
}

# the weapon icons of the AmmoMode clip that GryMod's own weapon table never selects (they are listed as valid, so a fire-mode resolver
# of another addon can return them)
_ICON_SRC = "lua/grymod/client/cl_hud_flash.lua:574-576 (FIRE_MODE_ICONS lists it), :582-586 (STOCK_WEAPON_ICON never maps to it)"
for _label, _what in (
        ("Incendiary", "incendiary ammo icon"), ("Tranquilizer", "tranquilizer ammo icon"), ("infinity", "infinite-ammo icon"),
        ("Narrow", "narrow-spread (shotgun) icon"), ("Moac", "MOAC alien weapon icon"), ("Moar", "MOAR alien weapon icon"),
        ("TACCannon", "TAC cannon icon"), ("C4", "C4 icon"), ("Gauss", "Gauss rifle icon"), ("Gunner", "gunner (turret) icon"),
        ("Mounted", "mounted weapon icon"), ("Claymore", "claymore mine icon")):
    VERDICTS[(AMMO, "label", _label)] = {
        "cls": "b", "what": "weapon-slot icon: " + _what,
        "game": "setFireMode(name) picks the icon from the weapon's fire-mode name; the demo's weapons use them",
        "effort": "S (add the GMod weapon classes to the table, or a resolver)", "priority": "low", "source": _ICON_SRC}

# the placements our module hides: what the film means by them
for _name in ("TargetIconTL", "TargetIconTR", "TargetIconBL", "TargetIconBR", "TargetIconLockTL", "TargetIconLockTR", "TargetIconLockBL",
              "TargetIconLockBR", "LockIcon_M"):
    VERDICTS[(BINOC, "clip", _name)] = {
        "cls": "c", "what": "target bracket / lock bracket / lock symbol of the binoculars",
        "game": "placed by code that the demo never calls for the binoculars (the TargetLock and Binoculars_EnemyIndicator movies are orphans)",
        "source": BINO + ":74 (F19); hidden by lua/grymod/client/cl_hud_binoculars_flash.lua:383-390"}

VERDICTS[(BINOC, "clip", "TargetText")] = {
    "cls": "c", "what": "the blinking 'TARGET LOCKED' banner with its underline (sprite 127, placed at frame 56, label TargetLock)",
    "game": "reached only through the TargetLock state, which nothing drives in the demo", "source": BINO + ":74 (F19); data: hud_binoculars.lua:491"}
VERDICTS[(RADAR_FILM, "clip", "Indicator")] = {
    "cls": "c", "what": "the red ring around the radar", "game": "setDamage / setScanningEffect only, for a vehicle's radar scan",
    "source": RADAR + ":166-167"}
VERDICTS[(QUICK, "clip", "CriticalArea")] = {
    "cls": "c", "what": "the legacy energy / cloak critical gauge", "game": "no function of the film and no call of the C++ reaches it",
    "source": QM + " (C++ paragraphs); hidden by lua/grymod/client/cl_hud_quickmenu_flash.lua:246-249"}
VERDICTS[(AMMO, "clip", "Tank")] = {
    "cls": "b", "what": "the tank HUD layout (icons, reload bars, name)", "game": "setAmmoMode picks it for tanks", "effort": "L", "missed": "B6",
    "priority": "low", "source": AUDIT + ":74; hidden by lua/grymod/client/cl_hud_flash.lua:112-118"}
VERDICTS[(AMMO, "clip", "VTOL")] = {
    "cls": "b", "what": "the VTOL HUD layout", "game": "setAmmoMode picks it for the VTOL", "effort": "L", "missed": "B6", "priority": "low",
    "source": AUDIT + ":74; hidden by lua/grymod/client/cl_hud_flash.lua:112-118"}
VERDICTS[(AMMO, "clip", "EmptyHUD")] = {
    "cls": "b", "what": "the empty layout (a vehicle without weapon HUD)", "game": "setAmmoMode(20)", "effort": "L", "missed": "B6", "priority": "low",
    "source": AUDIT + ":251-252; hidden by lua/grymod/client/cl_hud_flash.lua:112-118"}
for _name, _what in (("GunAmmo", "the vehicle's gun ammo digits"), ("MisAmmo", "the vehicle's missile ammo digits")):
    VERDICTS[(AMMO, "clip", _name)] = {
        "cls": "b", "what": "tank layout: " + _what, "game": "setAmmo of the Tank clip, with the vehicle layouts", "effort": "L (with B6)", "missed": "B6",
        "priority": "low", "source": AUDIT + ":74; inside Root.Tank, hidden by lua/grymod/client/cl_hud_flash.lua:112-118"}
VERDICTS[(AMMO, "clip", "OverheatBar")] = {
    "cls": "b", "what": "the overheat bar under the ammo digits", "game": "setOverheatBar(value) for weapons with a heat value", "effort": "S",
    "missed": "B7", "priority": "medium", "source": AUDIT + ":75; hidden by lua/grymod/client/cl_hud_flash.lua:123-127"}


# the features the class b rows add up to (one line each in the report)
_FEATURES = {
    "Vehicle HUD layouts (tank, VTOL, empty): own icons, names and reload bars": (
        AMMO, ("setAmmoMode", "setTankIcons", "setReloadDuration", "setReloadDuration2", "showReloadDuration2", "hideReloadDuration2",
               "setOverheatBar2", "end@238", "PriIcon", "SecIcon", "ReloadBar", "ReloadBar2", "Tank", "VTOL", "EmptyHUD",
               "GunAmmo", "MisAmmo")),
    "Overheat bar under the ammo digits": (AMMO, ("setOverheatBar", "OverheatBar")),
    "Icons of the other hand grenades (flash, smoke, EMP)": (AMMO, ("flashbang", "smokegrenade", "empgrenade")),
    "Weapon-slot icons that no GMod weapon selects": (AMMO, ("Incendiary", "Tranquilizer", "infinity", "Narrow", "Moac", "Moar", "TACCannon",
                                                              "C4", "Gauss", "Gunner", "Mounted", "Claymore")),
    "Radar minimap picture under the units": (RADAR_FILM, ("setPlayer", "setMapBackground", "setMapScale", "Map", "MapArea")),
    "Binoculars malfunction / flicker look (destroy)": (BINOC, ("destroy", "malfunction", "malfunctionOn", "flickering")),
    "Clear the damage arcs when the HUD is destroyed": (CROSS, ("clearDamageDirection",)),
}

for (_film, _kind, _name), _verdict in VERDICTS.items():
    if _verdict["cls"] != "b":
        continue

    for _feature, (_where, _names) in _FEATURES.items():
        if _film == _where and _name in _names:
            _verdict["feature"] = _feature


# the orphans that belong together (one line each in the report)
_GAUGE = "Legacy critical gauge of the quick menu film (CriticalArea): OVERLOAD / STABLE, SUIT ENERGY and CLOAK bars"

for _name in ("CloakBar", "CloakBarLabel", "EnergyBar", "EnergyBarLabel", "EnergyLabel", "Overload", "Stable", "SuitEnergyBar",
              "TemperatureBar", "Critical"):
    VERDICTS[(QUICK, "clip", _name)] = {
        "cls": "c", "what": "part of the critical gauge", "game": "no function of the film and no call of the C++ reaches it",
        "source": QM + " (C++ paragraphs); hidden by lua/grymod/client/cl_hud_quickmenu_flash.lua:246-249"}

for (_film, _kind, _name), _verdict in list(VERDICTS.items()):
    if _film == QUICK and (_name in ("CriticalArea", "CloakOpen", "CloakClose", "EnergyOpen", "EnergyClose", "bothOpen", "bothClose") or
                           (_kind == "clip" and _verdict["what"] == "part of the critical gauge")):
        _verdict["feature"] = _GAUGE
    elif _film == BINOC and _name.startswith(("TargetIcon", "LockIcon", "TargetLock", "TargetText")):
        _verdict["feature"] = "Target brackets, lock brackets and lock symbol of the binoculars (never driven by the demo)"
