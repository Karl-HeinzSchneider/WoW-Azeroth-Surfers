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
  `OnProfileRefresh`) and registers `/surfer`; `OnSlashCommand` opens the runner by default and handles `options`, `loglevel <level>` and `reset`. Register game events in `OnEnable`.
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

## Runner prototype

src/game/simulation.lua is the pure fixed-step simulation on a lane/layer grid: every object is a
box (`Box(kind, lane, at, length, layer, layers, ramp)`), platforms set the floor, the rest
collide or are collected. src/game/shapes.lua turns boxes into the faces both views draw (split at
the runner for the overlay's mask) and pools their textures. Two views render it, chosen by `profile.view`;
`app.ToggleGame()` (/surfer, minimap button) opens the chosen one and closes the other.

- src/game/window.lua: `app.runner`, a window with a ModelScene copy of the character, a projected
  curved road and buttons. It also owns the shared input, movement sampling and scoring methods.
- src/game/overlay.lua: `app.overlay`, the full-screen view. The real character is the runner; the
  road, obstacles and coins are UI textures at BACKGROUND strata, projected with a model of the
  follow camera (focus point at screen center; pitch, focus height, FOV and, without
  `GetCameraZoom`, distance from `profile.overlay`). Everything behind the character gets the
  `assets/game/cutout.tga` mask (opaque, transparent capsule, CLAMP-wrapped) three times: head,
  torso and legs, sized from the model's bounds and moved with a generic run cycle and jump tuck.
  Coins are 3D models (`COIN_MODELS`, file ids tried in order), one small ModelScene each at the
  projected position; models cannot be masked, so a coin hides while behind the body.

global.bestScore stores the account high score. tests/\*.lua run without the client through
npm run test:game. See the root README for controls and rendering limitations.
