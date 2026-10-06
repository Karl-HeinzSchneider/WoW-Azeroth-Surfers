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

src/game/simulation.lua is the pure fixed-step simulation; src/game/window.lua owns the window, ModelScene, projected curved road and controls. Both load after the core. /surfer and the minimap button toggle the game; /surfer options opens settings. global.bestScore stores the account high score. tests/simulation.lua runs without the client through npm run test:game. See the root README for controls and rendering limitations.
