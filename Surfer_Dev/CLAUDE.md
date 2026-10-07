# Surfer_Dev

Development tools for Surfer, never released: `## X-Surfer-Dev: 1` in the TOC keeps it out of
`npm run package:addons`, and `.pkgmeta` ignores the folder. `npm run dev:link` links it into the
client with Surfer. Put debugging, playtesting and biome-building tools here, not in `Surfer/`.

It reaches Surfer's private table through `LibStub("AceAddon-3.0"):GetAddon("Surfer"):DevApp()`
(`dev.app` in every file) and adds `/surfer` subcommands with `dev.Command(name, usage, run)`;
`/surfer help` lists them. Surfer keeps only the hooks the tools need: `overlay:Lap` (timing),
`light.override` (a fixed time of day), `simulation.invincible`, `track.list`/`track.byName`,
`overlay.keepWorldScene` (keeps the 3D scene shown for a preview), `overlay.referenceHeight`.

Files (load order in the TOC):

- `src/dev.lua` — the hand-off, `dev.Command`, `dev.Overlay()` (the open game or a hint),
  `dev.Words`, `dev.ANIMATIONS` (animation ids worth checking).
- `src/diagnostics.lua` — `/surfer profile` (milliseconds per frame by part) and `/surfer debug`
  (cameras, the world scene's lens calibration, every model's measured bounds).
- `src/preview.lua` — `/surfer preview creature <display id> [animation] | model <file id>
[animation] | turn <degrees> | off`: one model at its own size in the middle lane 8 yards
  ahead, its size in chat; a creature cycles through `dev.ANIMATIONS` without an animation.
- `src/animations.lua` — `/surfer animations [display id]`: which of `dev.ANIMATIONS` the
  biome's enemies (or one creature) have, from an invisible PlayerModel (`HasAnimation`; model
  scenes cannot tell).
- `src/playtest.lua` — `/surfer light day|dusk|night|auto`, `/surfer god` (invincible), `/surfer multiplier <n>` (the score multiplier),
  `/surfer spawn <pattern>` (30 yards ahead; by name or number, `/surfer spawn` lists the
  registered patterns), `/surfer reference <yards>` (the height a taller character is drawn at
  in the track's world; alone, the measured height and the scale in use).
