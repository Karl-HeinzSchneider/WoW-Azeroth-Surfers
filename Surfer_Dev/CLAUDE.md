# Surfer_Dev

Development tools for Surfer, never released (`## X-Surfer-Dev: 1`, ignored by `.pkgmeta`).
Debugging, playtesting and biome-building tools go here, not into `Surfer/`.

It reaches Surfer's private table through `LibStub("AceAddon-3.0"):GetAddon("Surfer"):DevApp()`
(`dev.app`) and adds `/surfer` subcommands with `dev.Command(name, usage, run)`; `/surfer help`
lists them. Surfer keeps only the hooks the tools use: `overlay:Lap`, `light.override`,
`simulation.invincible`, `track.list`/`track.byName`, `overlay.keepWorldScene`,
`overlay.referenceHeight`, `simulation.ZONE_LENGTH`, `simulation.STREAK`.

- `dev.lua` — the hand-off, `dev.Command`, `dev.Overlay()`, `dev.Words`, `dev.ANIMATIONS`.
- `diagnostics.lua` — `/surfer profile`, `/surfer debug`.
- `preview.lua` — `/surfer preview creature|model|turn|off`.
- `animations.lua` — `/surfer animations [display id]`.
- `playtest.lua` — `/surfer light`, `god`, `multiplier`, `streak`, `spawn`, `zonelength`,
  `reference`.
