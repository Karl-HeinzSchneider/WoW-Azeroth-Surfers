# AzerothSurfers_Dev

Development tools for Azeroth Surfers, never released (`## X-AzerothSurfers-Dev: 1`, ignored by `.pkgmeta`).
Debugging, playtesting and biome-building tools go here, not into `AzerothSurfers/`.

It reaches the addon's private table through `LibStub("AceAddon-3.0"):GetAddon("AzerothSurfers"):DevApp()`
(`dev.app`) and adds `/surfers` subcommands with `dev.Command(name, usage, run)`; `/surfers help`
lists them. The addon keeps only the hooks the tools use: `overlay:Lap`, `light.override`,
`simulation.invincible`, `track.list`/`track.byName`, `overlay.keepWorldScene`,
`overlay.referenceHeight`, `simulation.ZONE_LENGTH`, `simulation.STREAK`, `lobby.shots` with
`overlay.shotName`, `lobby.items` with `overlay.decorState`.

- `dev.lua` — the hand-off, `dev.Command`, `dev.Overlay()`, `dev.Words`, `dev.ANIMATIONS`.
- `diagnostics.lua` — `/surfers profile`, `/surfers debug`.
- `preview.lua` — `/surfers preview creature|model|turn|off`.
- `animations.lua` — `/surfers animations [display id]`.
- `playtest.lua` — `/surfers light`, `god`, `multiplier`, `streak`, `spawn`, `zonelength`,
  `reference`, `shot` (tunes the lobby's camera shots, prints them as Lua), `camp` (moves, turns
  and sizes the lobby's models live, prints them as Lua).
