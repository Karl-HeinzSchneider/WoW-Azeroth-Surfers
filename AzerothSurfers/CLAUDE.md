# Azeroth Surfers (the addon)

Everything in this folder ships. Settings live in `AzerothSurfersDB` (AceDB).

## Load order (`AzerothSurfers.toc`)

The TOC is the source of truth; **every new Lua/XML file must be listed**.

1. `embeds.xml`: the vendored libraries in dependency order.
2. `src\core\`: `logger.lua` (everything logs), `db.lua` (the defaults), `ace.lua` (creates
   `app.addon`), then the modules that hang off it (`options.lua`, `minimapbutton.lua`).
3. `src\game\biomes.lua`, then the biome files (`default.lua` first, new ones after it; one that
   derives from or borrows another's, as Teldrassil and Tirisfal do Elwynn's, after that one), the
   transitions and `src\scenes\lobby.lua` (it derives a biome from Elwynn's), then `random` →
   `simulation` → `track` → `patterns\patterns.xml` → `autopilot`, then `light` and `shapes`,
   then `overlay.lua` and the files that extend `app.overlay` after it. A Lua mixin comes before
   the XML that names it.
4. `AzerothSurfers.lua` last; it only logs.

`src/types.lua` is LuaLS annotations only (not in the TOC): the `AzerothSurfers` class (`app.*`)
and `AzerothSurfers.DB`. `lib/` is vendored: update by replacing the folder, never patch it.

## Core

- `logger.lua` — `app.logger`: `log("x")` is `log:info("x")`, `log:debug(fmt, ...)` formats,
  `log:chat(...)` is unfiltered user output, `log:dump(tbl)` at DEBUG.
- `db.lua` — `app.dbDefaults`: `profile` (user settings), `char`, `global` (`dbVersion`,
  `bestScore`).
- `ace.lua` — `app.addon`. `OnProfileRefresh` calls every module's `OnProfileRefresh`.
  `/surfers` (or `/azerothsurfers`) opens the game; also `options`, `loglevel`, `seed`, `auto`,
  `reset`, and the commands AzerothSurfers_Dev registers in `app.devCommands`. `app.TITLE`
  (`logger.lua`) is the name players see.
- `options.lua` — `app.options`: **one** AceConfig table, in tabs (Game, Display, Sound, Keys,
  Calibration, Profiles), for the Settings panel and a standalone window. `Refresh()` after a
  setting changed elsewhere.
- `minimapbutton.lua` — LibDataBroker launcher + LibDBIcon.

Prototype-style Ace modules: methods on a local `module` table passed to
`addon:NewModule("Name", module)`; state on the object Ace returns. A new user setting gets a
default in `db.lua` and an entry in `options.lua`.

## The game

- `random.lua` — seeded generators (`random.New(seed, stream)`, called like `math.random`).
  **Nothing in a run may use `math.random`**: everything a seed should replay draws from a
  generator of the run's seed, each system from its own stream.
- `simulation.lua` — the pure fixed-step simulation: every object is a box on a lane/layer grid.
  `New(seed, difficulty, zones, lobby)`; `DIFFICULTIES`; `VIEW` (how far the views show),
  `AHEAD` (how far the track is laid out), `CLEAR` (seconds of empty road at a run's start).
  Nothing scores before a run's `start` (a run from the lobby: where the player takes over past
  the portal); `Run(s)` is the yards counted. Each gate past `start` adds `GATE_MULTIPLIER` to
  the multiplier.
  `Skip(s, yards)` starts a run that far into its seed (the options' "Start at", with a fixed
  seed; never a run from the lobby): the track is laid out step by step as running lays it out,
  so from the first pattern past the empty road on it is the seed's own.
- `track.lua` — the stream of patterns. The rules every pattern keeps are at the top of the
  file; `tests/simulation.lua` checks them and that each pattern can be run through.
- `src/patterns/*.lua` — one pattern each. **A new pattern is a new file plus a line in
  `patterns.xml`**, nothing else. A new or changed pattern changes what a seed lays out.
- `biomes.lua` — `app.biomes`: biome registry (`Register`, `Get` merges over the default,
  `Derive` registers one biome as another with changes; a `hidden` one is not offered in the
  options), transitions (`RegisterTransition`, documented there) and auto mode's zone route.
  `src/biomes/default.lua` documents every biome field and is the reference for writing one.
  **Anything visual a region could change belongs in the biome, not as a constant in game
  code**: add the field to `default.lua`, read it from `overlay.biome`, re-apply it in
  `overlay:ApplyBiome()`. Only classic-era game files.
- `src/scenes/lobby.lua` — `app.lobby`: where a run started from the menu begins (its lane,
  coins and the gate at its `rim`, laid out by `track.Lobby`; up to the portal the run plays
  itself, `autopilot.Intro`, starting slow from `launch`), its biome (`lobby`, Elwynn with more
  grass, hidden), the camp's models, the title's and the menu's camera shots, the seated
  character and the title music. Up to its portal the title and the menu look the same whatever
  the run's seed. A restart during play has no lobby.
- `autopilot.lua` — `app.autopilot`: auto mode's player (a search on copies of the run), and
  `Intro`, which plays a run from the lobby up to its portal.
- `light.lua` — `app.light`: day and night by the game's clock, for the ground and every scene.
- `shapes.lua` — `app.shapes`: the boxes' and flat coins' faces, their texture pool, the
  ground's curve (`Ground`).
- `overlay.lua` — `app.overlay`, the view: road, boxes and coins projected through a camera
  shot (`RunShot` uses the game's own zoom, never WoW's; screens.lua's `ViewShot` swaps in a screen's or
  glides between them), and the twin over the real character: an actor of the world scene, so it
  shares its camera and depth with every model, drawn `TWIN_SIZE` (√2) times as big as the real
  character (the size it had in a scene of its own). **A running frame allocates nothing**
  (`tests/overlay.lua` checks it).
  Mouse wheel changes the game's camera distance (2 to 24 yards, default 12). The foreground ground strip
  extends at least 32 UI pixels below the viewport as needed, including while jumping.
- Files that extend `app.overlay`, in TOC order:
  - `decorations.lua` — the world ModelScene (one render pass for every model, the twin's too,
    with the road's camera; its lens measured against the road) and the roadside's and the
    lobby's models in it.
  - `occluder.lua` — the ground's depth: a scene of flat tiles under the 2D ground hides what
    models have below it (the 3D scenes share the depth buffer). How deep under the ground and
    from where (`SINK`, `BEHIND`) switches at the lobby's portal.
  - `obstacles.lua` (box models), `ambient.lua` (wildlife), `window.lua` (full screen / side
    window, window frame), `keys.lua` (the game's controls: `ACTIONS` of a run and of the menus,
    two keys and two gamepad buttons each, `profile.keys` over their defaults; `KeyAction`,
    `ActionKey`, `Chord`; what shows keys shows Key 1, or Gamepad 1 since a gamepad was used:
    `ShownSlot`, `NoteDevice`, `ShownKeys`), `menu.lua` (restart bar, number box), `hud.lua`
    (score), `legend.lua` (the running keys).
  - `messages.lua` — the pause and end menus, announcements, the gate's flash and vortex.
  - `menus.lua` — the menu window: pages of items (actions, choices, info lines, notes, number
    boxes) steered by directions, accept, back and a page's extra action. `MenuAction` maps a key
    (keyboard or gamepad) to them through keys.lua's menu actions.
  - `screens.lua` — the title screen and the main menu over the lobby, camera shots and glides,
    the seated character, the way into a run, title music; the keys of every screen and menu
    (`OnScreenKey`).
  - `controls.lua` — input, per-frame `Step`, best score, auto mode.

Tests: `npm run test:game` runs `tests/*.lua` without the client; `npm run bench:overlay`
counts WoW API calls per frame. Development tools live in `AzerothSurfers_Dev`
([../AzerothSurfers_Dev/CLAUDE.md](../AzerothSurfers_Dev/CLAUDE.md)); this addon only keeps the
hooks they use.
