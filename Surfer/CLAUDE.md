# Surfer (the addon)

The distributable addon: everything in this folder ships; the packager copies it to the top of the
zip (`.pkgmeta`). User settings live in `SurferDB` (AceDB).

## Load order (`Surfer.toc`)

The TOC is the manifest and the source of truth for the load order; **every new Lua/XML file must
be listed**. The order follows these rules:

1. `embeds.xml` first: every vendored library in dependency order (LibStub â†’ CallbackHandler â†’
   Ace\* â†’ LibDataBroker â†’ LibDBIcon).
2. `src\core\`: `logger.lua` first (everything logs), `db.lua` (the defaults `ace.lua` needs),
   `ace.lua` (creates `app.addon`), then the Ace modules that hang off it (`options.lua`,
   `minimapbutton.lua`).
3. Feature code after the core: `src\<feature>\*.lua`, or `modules\<name>\` with a loader XML
   per module listed in a `modules\modules.xml`. In UI code, each Lua mixin comes before the XML
   that names it.
4. `Surfer.lua` last; it only logs.

## Files

### `src/core/`

- `logger.lua` â€” `app.logger`: leveled, colored chat logging; `log("x")` is `log:info("x")`,
  `log:debug("Looted %s x%d", link, count)` formats, `log:chat(...)` is unfiltered user-facing
  output, `log:dump(tbl)` prints a table at DEBUG. The threshold comes from `profile.logLevel`.
- `db.lua` â€” `app.dbDefaults` for AceDB: `profile` = user settings (`logLevel`, `minimap`;
  `minimapPos` = 200Â° so an undragged button doesn't sit on LibDBIcon's shared 225Â° default),
  `char` = per-character data, `global.dbVersion` for future migrations.
- `ace.lua` â€” `app.addon`, the AceAddon object (AceConsole, AceEvent). `OnInitialize` opens
  `app.db`, wires the profile callbacks to `OnProfileRefresh` (log level, then every module's
  `OnProfileRefresh`) and registers `/surfer`; `OnSlashCommand` opens the runner by default and handles `options`, `loglevel <level>`, `debug` (twin camera report), `profile` (time per frame part, start/stop) and `reset`. Register game events in `OnEnable`.
- `options.lua` â€” `app.options`: the user options as **one** AceConfig table (plus the AceDBOptions
  profiles tab), registered in the game's Settings panel (`AddToBlizOptions`) and opened in a
  standalone AceConfigDialog window by `Open()`. A new option goes only here. `Refresh()` redraws
  them after a setting changed elsewhere.
- `minimapbutton.lua` â€” `app.minimapButton`, a LibDataBroker launcher + LibDBIcon that opens the
  runner and honors `profile.minimap`. Optional: to drop it, delete the file, its TOC line, the
  `minimap` option and `profile.minimap`.

### Annotations (not in the TOC)

- `src/types.lua` â€” the private-table class `Surfer` (`app.*` fields) and
  `Surfer.DB`. When a file adds a member to `app`, add a matching `---@field` here.

### Other

- `lib/` â€” vendored Ace3, LibStub, CallbackHandler, LibDBIcon (+ LibDataBroker). Excluded from
  LuaLS, StyLua and Prettier; update by replacing the folder, don't patch. `embeds.xml` loads all
  of them; drop a line there (not the folder) to skip a library the addon doesn't use.
- `assets/` â€” textures the game files cannot provide (`assets/core/coffee.tga` is the TOC notes'
  donation icon).

## Conventions

- Prototype-style Ace modules: define methods on a local `module` table and pass it to
  `addon:NewModule("Name", module, â€¦)`; state lives on the object Ace returns (see
  `minimapbutton.lua`). A module that depends on profile settings defines `OnProfileRefresh`.
- New user settings get a default in `db.lua` and an entry in `options.lua`.

## The game

- `src/game/simulation.lua` — the pure fixed-step simulation on a lane/layer grid: every object is
  a box (`Box(kind, lane, at, length, layer, layers, ramp)`), platforms set the floor, the rest
  collide or are collected.
- `src/game/biomes.lua` — `app.biomes`, the registry of looks: `Register(id, biome)`,
  `Get(id)` (merged over the default), `Current()` (`profile.biome`). `src/biomes/*.lua` hold one
  biome each and override only what they change; `default.lua` holds every field, documented, and
  is the reference for writing one. Tables merge field by field, lists (colors, bands, models)
  are replaced whole. **Anything visual a region could change (ground, obstacles, coins,
  decorations, light) belongs in the biome, not as a constant in the game code**: add the field
  with its current value to `default.lua`, read it from `overlay.biome`, and re-apply it in
  `overlay:ApplyBiome()` (called on Create and when the setting changes). New biome files go in
  the TOC after `default.lua`. Only classic-era game files.
- `src/game/light.lua` — `app.light`, the day/night light by the game's clock (`GetGameTime`; the
  world's own light cannot be read). Every 3D model's ModelScene registers with
  `light.AddScene(scene, ambient, diffuse)` (its colors by day) instead of setting its lights;
  the ground multiplies its vertex colors by `light.r/g/b`.
- `src/game/shapes.lua` — turns boxes and coins into the faces to draw, and pools their textures
  (show, color and draw layer only set on a change).
- `src/game/overlay.lua` — `app.overlay`, the full-screen view: road, boxes and coins as UI
  textures at BACKGROUND strata, projected with a model of the follow camera (focus point at
  screen center; pitch, focus height, FOV and, without `GetCameraZoom`, distance from
  `profile.overlay`). A twin covers the real character: a square ModelScene (LOW strata) around
  the projected body, sized by the road's projection, its camera at the road's camera (a square
  frame makes the scene's field-of-view axis irrelevant). The real character's animation cannot be
  read, so the twin mirrors its movement (`motion` from position sampling, `GetUnitSpeed`,
  `IsFalling`). `hideReal` zooms into first person (`CameraZoomIn`) while the game is open. Coins
  within 40 yards are 3D models (`COIN_MODELS`, file ids tried in order), one small ModelScene
  each; every shown ModelScene costs a render pass, so unused ones are hidden. A running frame
  allocates nothing (`tests/overlay.lua` checks it).
- `src/game/decorations.lua` — the biome's roadside models (`decorations.groups`, weighted
  groups of items, any number a `{ min, max }` range): all actors of one full-screen square
  ModelScene whose camera is the road's camera (one render pass for all; the square makes the FOV
  axis irrelevant). Placed up to the ground's far fade, moved every frame, dropped behind the
  camera; actors are pooled by model and instance tables reused. Models are placed by their own
  origin (never `SetUseCenterForOrigin`: animated bounds make them drift) and pushed out past the
  biome's `clear` by their measured, turned bounds unless an item is `overhang`.
- `src/game/controls.lua` — input (observed movement bindings), movement sampling, the per-frame
  `Step`, score texts and `Toggle`, added to `app.overlay`.

global.bestScore stores the account high score. tests/\*.lua run without the client through
npm run test:game; `npm run bench:overlay` counts WoW API calls per frame.
