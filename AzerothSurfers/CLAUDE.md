# Azeroth Surfers (the addon)

Everything in this folder ships. Settings live in `AzerothSurfersDB` (AceDB).

## Load order (`AzerothSurfers.toc`)

The TOC is the source of truth; **every new Lua/XML file must be listed**.

1. `embeds.xml`: the vendored libraries in dependency order.
2. `src\core\`: `logger.lua` (everything logs), `db.lua` (the defaults), `ace.lua` (creates
   `app.addon`), then the modules that hang off it (`options.lua`, `minimapbutton.lua`).
3. `src\game\biomes.lua`, then the biome files (`default.lua` first, new ones after it), the
   transitions and `src\scenes\lobby.lua`, then `random` → `simulation` → `track` →
   `patterns\patterns.xml`, then `overlay.lua` and the files that extend `app.overlay` after it.
   A Lua mixin comes before the XML that names it.
4. `AzerothSurfers.lua` last; it only logs.

`src/types.lua` is LuaLS annotations only (not in the TOC): the `AzerothSurfers` class (`app.*`) and
`AzerothSurfers.DB`. `lib/` is vendored: update by replacing the folder, never patch it.

## Core

- `logger.lua` — `app.logger`: `log("x")` is `log:info("x")`, `log:debug(fmt, ...)` formats,
  `log:chat(...)` is unfiltered user output, `log:dump(tbl)` at DEBUG.
- `db.lua` — `app.dbDefaults`: `profile` (user settings), `char`, `global` (`dbVersion`,
  `bestScore`).
- `ace.lua` — `app.addon`. `OnProfileRefresh` calls every module's `OnProfileRefresh`.
  `/surfers` (or `/azerothsurfers`) opens the game; also `options`, `loglevel`, `seed`, `auto`, `reset`, and the
  commands AzerothSurfers_Dev registers in `app.devCommands`.
- `options.lua` — `app.options`: **one** AceConfig table for the Settings panel and a standalone
  window. `Refresh()` after a setting changed elsewhere.
- `minimapbutton.lua` — LibDataBroker launcher + LibDBIcon.

Prototype-style Ace modules: methods on a local `module` table passed to
`addon:NewModule("Name", module)`; state on the object Ace returns. A new user setting gets a
default in `db.lua` and an entry in `options.lua`.

## The game

- `random.lua` — seeded generators (`random.New(seed, stream)`, called like `math.random`).
  **Nothing in a run may use `math.random`**: everything a seed should replay draws from a
  generator of the run's seed, each system from its own stream.
- `simulation.lua` — the pure fixed-step simulation: every object is a box on a lane/layer grid.
  `New(seed, difficulty, zones, lobby)`; `DIFFICULTIES`; `VIEW` (how far the views show) and `AHEAD`
  (how far the track is laid out).
- `track.lua` — the stream of patterns. The rules every pattern keeps are at the top of the
  file; `tests/simulation.lua` checks them and that each pattern can be run through.
- `src/patterns/*.lua` — one pattern each. **A new pattern is a new file plus a line in
  `patterns.xml`**, nothing else. A new or changed pattern changes what a seed lays out.
- `biomes.lua` — `app.biomes`: biome registry (`Register`, `Get` merges over the default),
  transitions (`RegisterTransition`, documented there) and auto mode's zone route.
  `src/biomes/default.lua` documents every biome field and is the reference for writing one.
  **Anything visual a region could change belongs in the biome, not as a constant in game
  code**: add the field to `default.lua`, read it from `overlay.biome`, re-apply it in
  `overlay:ApplyBiome()`. Only classic-era game files.
- `src/scenes/lobby.lua` — `app.lobby`: where a run started from the menu begins (its lane,
  coins and the gate at its `rim`, laid out by `track.Lobby`; up to the portal the run plays
  itself, `autopilot.Intro`), the camp's models, the title's and the menu's camera shots, the
  seated character and the title music. A restart during play has no lobby.
- `overlay.lua` — `app.overlay`, the view: road, boxes and coins projected through a camera
  shot (`RunShot` imitates the follow camera; screens.lua's `ViewShot` swaps in a screen's or
  glides between them), and the twin covering the real character. **A running frame allocates
  nothing** (`tests/overlay.lua` checks it).
- Files that extend `app.overlay`: `shapes.lua` (faces and texture pool), `decorations.lua`
  (roadside models in one world ModelScene), `obstacles.lua` (box models), `ambient.lua`
  (wildlife), `light.lua` (day/night by the game clock), `window.lua` (full screen / side window,
  window frame), `menu.lua` (restart bar, seed box), `hud.lua` (score), `legend.lua` (hotkeys),
  `messages.lua` (pause and end panels, announcements, gate flash and vortex), `menus.lua`
  (the menu window: pages of items steered by directions, accept and back; `MenuAction` maps
  keys to them, a gamepad would map to the same), `screens.lua`
  (title screen, main menu, the seated character, the way into a run, title music),
  `controls.lua` (input, per-frame `Step`, best score, auto mode), `autopilot.lua` (auto
  mode's player).

Tests: `npm run test:game` runs `tests/*.lua` without the client; `npm run bench:overlay`
counts WoW API calls per frame. Development tools live in `AzerothSurfers_Dev`
([../AzerothSurfers_Dev/CLAUDE.md](../AzerothSurfers_Dev/CLAUDE.md)); this addon only keeps the hooks they use.
