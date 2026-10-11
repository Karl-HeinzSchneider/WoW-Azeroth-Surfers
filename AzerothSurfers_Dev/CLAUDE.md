# AzerothSurfers_Dev

Development tools for Azeroth Surfers, never released (`## X-AzerothSurfers-Dev: 1`, ignored by
`.pkgmeta`). Debugging, playtesting and biome-building tools go here, not into `AzerothSurfers/`.

It reaches the addon's private table through
`LibStub("AceAddon-3.0"):GetAddon("AzerothSurfers"):DevApp()` (`dev.app`) and adds `/surfers`
subcommands with `dev.Command(name, usage, run)`; `/surfers help` lists them. The addon keeps
only the hooks the tools use: `overlay:Lap`, `light.override`, `simulation.invincible`,
`track.list`/`track.byName`, `overlay.referenceHeight`, `simulation.ZONE_LENGTH`,
`simulation.STREAK`, `lobby.shots` with `overlay.shotName`,
`lobby.items` with `overlay.decorState`, `overlay.OCCLUDER_SINK`, `overlay.occluderOff` and
`overlay.occluder` with `overlay:PlaceOccluder`.

- `dev.lua` — the hand-off, `dev.Command`, `dev.Overlay()`, `dev.Words`, `dev.ANIMATIONS`, `dev.CROUCH`
  (duck/slide candidates).
- `diagnostics.lua` — `/surfers profile`, `/surfers debug`, `/surfers twinsize` (the twin's size
  on the screen against the road's projection of its body).
  `/surfers minimap` reports hover enablement, button/scene visibility, model request result,
  loaded file, fitting state, accumulated load wait and failure reason without changing them.
  Includes the native hover-entry count and last reason scene startup was blocked.
  `/surfers layers` reports existing unit frames, action bars, bags, chat and game frames sorted
  by strata and level, with visibility and parent names. `/surfers layers FrameName` inspects
  one named frame and its direct children. It never changes their layers or opens UI panels.
- `preview.lua` — `/surfers preview creature|model|player|turn|off` (`player`: your own character,
  cycling through `dev.CROUCH`).
- `icon.lua` — `/surfers icon`: isolated, evenly lit gameplay gem on a solid background,
  without opening the game. Buttons adjust yaw, pitch, zoom, rotation and background.
  `icon turn <degrees>`, `pitch <degrees>`, `zoom <0.1-10>`, `background black|white|green`,
  `spin on|off`, `clean`, `controls`, `off` provide the same controls through chat.
  Clean view stops rotation and hides controls; Escape closes. Capture the central square
  with WoW's screenshot key, crop outside WoW, and edit alpha externally (screenshots are
  opaque; black preserves the blue glow better than chroma key). Keep PNG for external use;
  convert to BLP or uncompressed 32-bit TGA for the TOC and minimap texture. The model's
  built-in idle animation is frozen at time zero; `spin` only turns the actor's yaw.
  The selected gem capture has wider `AzerothSurfers/assets/core/icon-gem.tga` and tighter
  `icon-gem-zoomed.tga` variants; the TOC and minimap launcher use the tighter one.
  This tool never writes image files.
- `animations.lua` — `/surfers animations [display id | player]` (`player`: which of `dev.CROUCH`
  your own character has).
- `assets.lua` — `/surfers assets [all|models|animations|sounds] [all|biome]`: audits registered
  biome assets, transitions, lobby, and the current player's used animations. Deduplicates IDs
  and records every usage path. Loads models asynchronously (5-second timeout), compares loaded
  file IDs, checks requested animation IDs, and briefly probes sounds on SFX. Failed sounds and
  model timeouts need review, not automatic removal. `/surfers assets report [all]` opens a
  copyable report; `listen <report number>` auditions a sound; `stop` cancels scanning/playback.
  A loaded model can still be invisible or an error model; use `preview` to inspect it. Animation
  variations need visual checks. Keep the small code-local asset list in sync with game code.
  Offline regression test: `lua tests/assets.lua`.
- `playtest.lua` — `/surfers light`, `god`, `multiplier`, `streak`, `spawn`, `zonelength`,
  `reference`, `shot` (tunes the lobby's camera shots, prints them as Lua), `camp` (moves, turns
  and sizes the lobby's models live, prints them as Lua).
- `occluder.lua` — `/surfers occluder on|off|show|sink lobby|run <yards>`: the ground's depth
  (AzerothSurfers' `occluder.lua`) on and off, its tiles over the ground, how far under it.
