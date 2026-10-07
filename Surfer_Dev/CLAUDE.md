# Surfer_Dev

Development tools for Surfer, never released: `## X-Surfer-Dev: 1` in the TOC keeps it out of
`npm run package:addons`, and `.pkgmeta` ignores the folder. `npm run dev:link` links it into the
client with Surfer. Put debugging, playtesting and biome-building tools here, not in `Surfer/`.

It reaches Surfer's private table through `LibStub("AceAddon-3.0"):GetAddon("Surfer"):DevApp()`
(`dev.app` in every file) and adds `/surfer` subcommands with `dev.Command(name, usage, run)`;
`/surfer help` lists them. Surfer keeps only the hooks the tools need: `overlay:Lap` (timing),
`light.override` (a fixed time of day), `simulation.invincible`, `track.list`/`track.byName`,
`overlay.keepWorldScene` (keeps the 3D scene shown for a preview), `overlay.pilot` (plays the run
in `simulation.Update`'s stead; the runner runs by itself, movement keys do not steer, and a run
marked `piloted` saves no best score).

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
  registered patterns).
- `src/bot.lua` — `/surfer bot` (toggles; opens the game): the game plays itself. A depth-first
  search through copies of the simulation, like the "can be run through" test's, plans an input
  every 0.05 s for 1.4 s ahead (crates and enemies lane-wide, toward one target lane per plan:
  its own while a coin in it is near, else the nearest coin's) and replans every 0.25 s, going on
  with the previous plan while the target stays. A found plan is smoothed: lane changes (an out
  and back first) and jumps are dropped where it still gets through with as many coins. It splits
  each frame at its input times, so the run follows the plan to the tick. Branches leave out coins (they would collect the run's) and
  never lay out track (it would draw from the run's generator). A finished run is reported in
  chat (seed, difficulty, where it found no way through) and restarts after 3 seconds.
