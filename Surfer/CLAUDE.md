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

- `src/game/random.lua` — `app.random`, seeded random numbers (WoW's `math.random` cannot be
  seeded): Park–Miller's minimal standard, exact in Lua's doubles. `random.New(seed, stream)` is
  a generator called like `math.random` (`r()`, `r(n)`, `r(m, n)`), `r:Seed(seed, stream)`
  restarts it without allocating. Each system draws from its own `stream` (`TRACK`, `LEFT`,
  `RIGHT`, `LOOK`), a far-away point of the cycle, so they do not repeat one another. **Nothing
  in a run may use `math.random`**: everything a seed should replay draws from a generator of
  the run's seed.
- `src/game/simulation.lua` — the pure fixed-step simulation on a lane/layer grid: every object is
  a box (`Box(kind, lane, at, length, layer, layers, ramp)`), platforms set the floor, the rest
  collide or are collected. `New(seed)` starts a run from `seed` (a new one when left out,
  `s.seed`); the track follows only from it. Every generated box gets `o.seed` for its looks.
  The score adds up as the run goes (`s.points` per yard, `s.bonus` per coin), each at the
  multiplier of its moment: `SetMultiplier(s, n)` (whole, at least 1; events raise it) scales
  only what is earned from then on. `Score(s)` is the total.
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
- `src/game/overlay.lua` — `app.overlay`, the view (full screen or the side window, see
  `window.lua`): road, boxes and coins as UI textures at BACKGROUND strata, projected with a
  model of the follow camera (focus point at the view's center; pitch, focus height, FOV and, without `GetCameraZoom`, distance from
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
  biome's `clear` by their measured, turned bounds unless an item is `overhang`. Each side draws
  from its own stream of the run's seed in road order, and an obstacle's look from its box's
  `o.seed` (obstacles.lua), so a seed decorates the same at any frame rate.
- `src/game/window.lua` — the modes (`profile.mode`): `ApplyMode()` puts the view full screen
  or in the side window (a movable, resizable, clipped frame whose place `profile.side` saves;
  its camera uses the calibration distance, not the real zoom, and a sky/land backdrop from the
  biome's `sky` fills it). The window frame (`profile.frame.full/side`) is a
  PortraitFrameTemplate (built like the spell book's: its CloseButton, a
  MaximizeMinimizeButtonFrameTemplate left of it, no background, no portrait) sibling of the view, so the clipping does not cut it; full screen it
  covers the screen's edges, since the road must stay centered on the real character.
  The frame's minimize/maximize button (and, without the frame, the Minimize/Close buttons in a
  row at the top middle) switch modes through `SetMode(mode)`. `Layout()` places texts and buttons for the
  mode and size. Call `ApplyMode()` after any mode
  setting changes (the options and `OnProfileRefresh` do).
- `src/game/menu.lua` — the start dialog (classic dialog box: best score, how to play, Start game
  and Close; options go between the buttons: the Seed box) shown while a run is `ready`, and the
  restart bar shown while the restart key is held. `profile.seed` is a fixed seed (or false: a
  new one every run); `overlay:NewState()` starts every run from it and `SetSeed(n|false)`
  changes it (also `/surfer seed`); `SetFixedSeed(on)` keeps the current run's seed or lets
  every run draw one (the "Fixed seed" option and checkbox). `SetSeed` updates every place that
  shows the setting: the start dialog, the status panel and the addon options.
- `src/game/hud.lua` — the score display: dark, see-through panels (the tooltip's art, tinted)
  with bright outlined numbers (the UI font, Friz Quadrata): the score, the multiplier (a star
  and `x1`, orange above 1; the star pops when it rises) in front of it, the coins under it. It
  holds still to be read while running: one fixed-width cell per digit, panels widen only for a
  digit more, the running score is redrawn 20 times a second.
  Full screen it stands right of the road's far end, above the horizon (placed in proportion to
  the screen's height); in the side window in its top right corner under the buttons, scaled
  down. Hidden on the start dialog. Its own place in the draw order (`hud`, above the twin).
- `src/game/legend.lua` — the hotkey legend, remade after the client's persistent input
  legend: one group of rows per run state (ready, running, paused, over), only the current one
  shown; each group a `DialogBorderTemplate` panel sized from its rows, a header row with a
  classic divider as trim, rows of key caps (tooltip-bordered plates; `overlay.KeyCap` / `SetKeyCap` for others) and gold texts in one
  column. The keys are the player's movement bindings (`GetBindingKey`, again on
  `UPDATE_BINDINGS`; Q and R left out of them) and the game's own (`overlay.GAME_KEYS`,
  controls.lua). In the view's top left corner (scaled down in the side window), clear of the
  window frame's border; full screen in MEDIUM strata, over the player frame (LOW), which would
  otherwise draw between its background and border.
  `profile.legend` (option "Show hotkeys").
- `src/game/messages.lua` — what the game says in the middle of the view, over everything else
  (`messages` in the draw order, HIGH strata in both modes): the status panel while a run is
  paused or over (a `DialogBorderTemplate` panel like the legend's: score with its
  multiplier, coins, distance, best, "New best!" when `SaveBest` set `state.newBest`, trims like the legend's under the title and the numbers, the seed in a box (editable only
  with the "Fixed seed" checkbox under it checked, otherwise read-only but copyable),
  and a button per next action, Go on / Start over / Run again, each behind the legend's key
  cap of the game key that does the same, `DoAction(key)`), and announcements:
  `overlay:Announce(text, seconds, small)` shows big zone-text-style letters (`ZoneTextFont`,
  `small` in `SubZoneTextFont` above) that fade in, stay `seconds` (2 by default) and fade
  out; a newer one replaces it. `WelcomeBiome()` announces the biome ("Welcome to" /
  "Elwynn Forest") when a run starts and when the biome option changes during one.
- `src/game/controls.lua` — input (observed movement bindings), movement sampling, the per-frame
  `Step`, best score (`SaveBest`) and `Toggle`, added to `app.overlay`. With `profile.capture` the movement
  bindings' keys stop at the view (`SetPropagateKeyboardInput(false)` per key) and the runner
  runs by itself (`AutoRun`) instead of following the sampled movement. R (without modifiers)
  is always the game's: one press restarts a finished run, holding it `RESTART_HOLD` seconds
  restarts a running or paused one. Q (without modifiers) pauses and goes on.

global.bestScore stores the account high score. tests/\*.lua run without the client through
npm run test:game; `npm run bench:overlay` counts WoW API calls per frame.

Development tools (previews, animation checks, `/surfer profile` and `/surfer debug`) live in
the separate `Surfer_Dev` addon ([../Surfer_Dev/CLAUDE.md](../Surfer_Dev/CLAUDE.md)); this addon
only keeps the hooks they use.
