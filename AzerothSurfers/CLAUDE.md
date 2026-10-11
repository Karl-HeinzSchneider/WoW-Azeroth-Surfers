# Azeroth Surfers (the addon)

Everything in this folder ships. Settings live in `AzerothSurfersDB` (AceDB).

## Load order (`AzerothSurfers.toc`)

The TOC is the source of truth; **every new Lua/XML file must be listed**, in it or in a loader
XML it lists (`biomes.xml`, `game.xml`, `patterns.xml`, `overlay.xml`).

1. `embeds.xml`: the vendored libraries in dependency order.
2. `src\core\`: `logger.lua` (everything logs), `db.lua` (the defaults), `ace.lua` (creates
   `app.addon`), then the modules that hang off it (`options.lua`, `minimapbutton.lua`).
3. `src\biomes\biomes.xml`: `src\game\biomes.lua`, then the biome files (`default.lua` first, new
   ones after it; one that derives from or borrows another's, as Teldrassil and Tirisfal do
   Elwynn's, after that one) and the transitions; **a new biome is a new file plus a line in
   `biomes.xml`**. Then `src\scenes\lobby.lua` (it derives a biome from Elwynn's) and the
   client overrides.
4. `src\game\game.xml`, the run without its view: `random` → `scoring` → `simulation` →
   `challenges` → `leaderboard` → `track` → `..\patterns\patterns.xml` → `autopilot`.
5. `light` and `shapes`, then `src\game\overlay.xml`, the view: `overlay.lua` and the files
   that extend `app.overlay` after it. A Lua mixin comes before the XML that names it.
6. `AzerothSurfers.lua` last; it only logs.

`src/types.lua` is LuaLS annotations only (not in the TOC): the `AzerothSurfers` class (`app.*`)
and `AzerothSurfers.DB`. `lib/` is vendored: update by replacing the folder, never patch it.

## Client asset overrides

Biome, transition and lobby definitions are the Forever baseline. `src/overrides/retail.lua`
loads immediately after the lobby and before game consumers. It returns without changes on
Forever (interface 16001, even if its project is Mainline) and Classic; on retail it calls
`biomes.ApplyAssetOverrides` with mappings from baseline IDs to replacement IDs. Add all retail
replacements there, never conditionals inside individual biomes.

`src/overrides/anniversary.lua` targets the 2.5.x Anniversary client family (manifest
20506), separately from vanilla Era. It replaces the rabbit, ready stance and player roll.
`playerAnimations` maps player animation IDs through `biomes.PlayerAnimation`, shared by
rendering and the asset audit. New replacements still need in-client verification.
Anniversary maps roll to Swim (42). `playerAnimationOffsets = { [42] = -0.5 }` lowers
only the rendered character during grounded ducks, scaled with its body size. Collision,
movement and camera positions are unchanged; the normal height returns when ducking ends.

Mappings cover `creatures`, `models`, `sounds`, `textures` and explicit biome `animations`.
The application step copies definitions and clears merged caches, so the dev asset audit sees
the same resolved data as gameplay. It handles asset lists, display-keyed enemy sounds,
footsteps, transitions and lobby music; it preserves gameplay numbers and list lengths/weights.
Targets are final IDs (no chained remapping). If creature sound keys collide, the target
display's existing voice wins. Other local constants in rendering/control code are not remapped by this system. `npm run test:assets` also tests overrides.

## Core

- `logger.lua` — `app.logger`: `log("x")` is `log:info("x")`, `log:debug(fmt, ...)` formats,
  `log:chat(...)` is unfiltered user output, `log:dump(tbl)` at DEBUG.
- `db.lua` — `app.dbDefaults`: `profile` (user settings), `char`, `global` (`dbVersion`,
  `bestScore`, `challenges`, `leaderboard`).
- `ace.lua` — `app.addon`. `OnProfileRefresh` calls every module's `OnProfileRefresh`.
  `/surfers` (or `/azerothsurfers`) opens the game; also `options`, `loglevel`, `seed`, `auto`,
  `reset`, and the commands AzerothSurfers_Dev registers in `app.devCommands`. `app.TITLE`
  (`logger.lua`) is the name players see.
- `options.lua` — `app.options`: **one** AceConfig table, in tabs (Game, Display, Sound, Keys,
  Calibration, Profiles), for the Settings panel and a standalone window. `Refresh()` after a
  setting changed elsewhere.
- `minimapbutton.lua` — LibDataBroker launcher + LibDBIcon; its tooltip lists each challenge's
  status (`challenges.StatusText`).

Prototype-style Ace modules: methods on a local `module` table passed to
`addon:NewModule("Name", module)`; state on the object Ace returns. A new user setting gets a
default in `db.lua` and an entry in `options.lua`.

## The game

- `random.lua` — seeded generators (`random.New(seed, stream)`, called like `math.random`).
  **Nothing in a run may use `math.random`**: everything a seed should replay draws from a
  generator of the run's seed, each system from its own stream.
- `scoring.lua` — `app.scoring`: how a run scores, as data. `DEFAULTS` holds every value (points
  per yard and per coin, the streak, the multiplier's start, step per gate and most, a factor per
  difficulty the score is multiplied by); `Rules(overrides)` copies them with a game mode's
  overrides over them, field by field. **Game code reads a run's rules (`s.scoring`), never a
  scoring constant of its own**, so a mode can change any of it.
- `simulation.lua` — the pure fixed-step simulation: every object is a box on a lane/layer grid.
  `New(seed, difficulty, zones, lobby, goal, scoring)` (`goal`: a challenge's, see below;
  `scoring`: a mode's overrides of scoring.lua's rules); `DIFFICULTIES`; `VIEW` (how far the views show),
  `AHEAD` (how far the track is laid out), `CLEAR` (seconds of empty road at a run's start).
  Nothing scores before a run's `start` (a run from the lobby: where the player takes over past
  the portal); `Run(s)` is the yards counted. Each gate past `start` adds the rules'
  `multiplier.perGate`; `Score(s)` is everything earned times the difficulty's factor.
  `Skip(s, yards)` begins a run from the lobby that far into its seed, past its portal at the
  least: the track is laid out step by step as running it from the menu lays it out, so from the
  first pattern past the empty road on it is the seed's own. Every restart is one, so a seed
  lays out one track, from the menu or a restart. Play's runs draw a new seed each and begin
  at the camp; a custom game (the main menu's Custom, `overlay.custom`, cleared by the menu or
  the title; `s.custom`) takes `CUSTOM`'s settings (messages.lua: `profile.seed`, fixed or new
  each run, "Start at", `profile.startAt`, from the menu and every restart, and "Ends at",
  `profile.endAt`, a last portal as a challenge's `finish`, yards from the camp as "Start at";
  its Scoring page, `profile.customScoring`, only what differs from scoring.lua's `DEFAULTS`,
  passed to `New` as its `scoring`) and saves no best score.
- `challenges.lua` — `app.challenges`: daily, weekly and monthly challenges.
  - Periods: one begins at `RESET_HOUR` UTC (a week on Monday, a month on the 1st), counted
    from the realm's clock (`Now`). `Period(id, now)` gives its `key` ("daily-20371", the key
    of everything saved for it), seed, difficulty and goal in yards (`Draw`: from its number
    alone, by `random`, the same for everyone; the goal its kind's in `KINDS`, up to
    `VARIATION` more or less); `ByIndex(id, index)` the same by its number.
  - The run: `overlay.challenge` (set by the main menu's Challenges, cleared by the menu or the
    title) always runs through zones from the lobby at its own difficulty, never "Start at";
    `simulation.New(..., goal)` gives it a `finish`, where track.lua lays out a last portal and
    nothing after it, and the run ends `FINISH_PAST` yards through it (`s.finished`). Going
    through that portal shows "Finish!" with the level-up fanfare (messages.lua's `Finish`, the
    fanfare with the portal sounds).
  - Bests: one per period in `global.challenges` (`Best`, `Save`, `Beats`: reaching the portal
    first, then the score; controls.lua's `SaveChallenge`, only for a run that is over); it
    never counts as the endless best score. The end menu says how much the run beat or missed
    the best before it by (`s.lastBest`).
  - Live target: a challenge's run keeps its score every `TRACE_EVERY` yards (`NewTrace`,
    `Trace`), saved with its best (`SavedTrace`); `Target` reads the best's score at a distance.
  - History: every period's best stays (`History`, `ShortLabel`; past ones lose their trace at
    login and reload, `Compact`), and the streak counts days in a row with a daily challenge
    run (`Streak`): the Challenges page's History in screens.lua.
  - Login and reload: `ace.lua`'s first `PLAYER_ENTERING_WORLD`, once the realm's clock is
    known, runs `Compact` and the leaderboard's `Prune`; never earlier, as the periods follow
    that clock.
  - `Status` (new, beaten or tried), `StatusText`, and `Reminder`, the chat line `ace.lua`
    prints at login (`profile.challengeReminder`).
- `leaderboard.lua` — `app.leaderboard` (an Ace module with AceComm): the challenges' bests of
  the guild and the group, no server. A new best goes out on GUILD and PARTY or RAID (`Share`);
  opening a challenge's leaderboard (screens.lua) asks them for theirs (`Ask`, once per channel
  every `ASK_EVERY`), and whoever has one answers on that channel (once every `ANSWER_EVERY`).
  The message format is at the top of the file. Only the current periods' bests are kept, in
  `global.leaderboard` by key then sender (ended periods dropped at login and reload, `Prune`);
  anything malformed, from another period, another channel or another protocol version is
  ignored. `Ranked(period)` sorts them with the player's own as challenges.lua does (`Beats`).
- `track.lua` — the stream of patterns. The rules every pattern keeps are at the top of the
  file; `tests/simulation.lua` checks them and that each pattern can be run through.
- `src/patterns/*.lua` — one pattern each. **A new pattern is a new file plus a line in
  `patterns.xml`**, nothing else. A new or changed pattern changes what a seed lays out.
- `biomes.lua` — `app.biomes`: biome registry (`Register`, `Get` merges over the default,
  `Derive` registers one biome as another with changes; a `hidden` one is not offered in the
  options), transitions (`RegisterTransition`, documented there) and auto mode's zone route.
  `src/biomes/default.lua` documents every biome field and is the reference for writing one.
  **Anything visual a region could change belongs in the biome, not as a constant in game
  code**: add the field to `default.lua`, read it from `overlay.biome`, re-apply it in
  `overlay:ApplyBiome()`. Only classic-era game files.
- `src/scenes/lobby.lua` — `app.lobby`: where a run started from the menu begins (its lane,
  coins and the gate at its `rim`, laid out by `track.Lobby`; up to the portal the run plays
  itself, `autopilot.Intro`, starting slow from `launch`), its biome (`lobby`, Elwynn with more
  grass, hidden), the camp's models, the title's and the menu's camera shots, the seated
  character and the title music. Up to its portal the title and the menu look the same whatever
  the run's seed. A restart during play is that run skipped past its portal.
- `autopilot.lua` — `app.autopilot`: auto mode's player (a search on copies of the run, each
  replan worked out over the frames before it is due), and `Intro`, which plays a run from the
  lobby up to its portal.
- `light.lua` — `app.light`: day and night by the game's clock, for the ground and every scene.
- `shapes.lua` — `app.shapes`: the boxes' and flat coins' faces, their texture pool, the
  ground's curve (`Ground`).
- `overlay.lua` — `app.overlay`, the view: road, boxes and coins projected through a camera
  shot (`RunShot` uses the game's own zoom, never WoW's; screens.lua's `ViewShot` swaps in a screen's or
  glides between them), and the twin over the real character: an actor of the world scene, so it
  shares its camera and depth with every model, drawn `TWIN_SIZE` (√2) times as big as the real
  character (the size it had in a scene of its own). **A running frame allocates nothing**
  (`tests/overlay.lua` checks it). The ground's pieces are small so their textures don't
  shimmer; one off the screen, past the horizon or faded out is hidden and costs no calls
  (`face`, `SkinPiece`), and a call that would change nothing is skipped.
  Mouse wheel changes the game's camera distance (2 to 24 yards, default 12). The foreground ground strip
  extends at least 32 UI pixels below the viewport as needed, including while jumping.
- Files that extend `app.overlay`, in `overlay.xml`'s order:
  - `decorations.lua` — the world ModelScene (one render pass for every model, the twin's too,
    with the road's camera; its lens measured against the road) and the roadside's and the
    lobby's models in it. Its actors are pooled by model (`AcquireActor`); the roadside and the
    boxes load up to `LOADS_PER_FRAME` new ones a frame, and an actor is moved only once it
    would show off its place (`MoveActor`).
  - `occluder.lua` — the ground's depth: a scene of flat tiles under the 2D ground hides what
    models have below it (the 3D scenes share the depth buffer). How deep under the ground and
    from where (`SINK`, `BEHIND`) switches at the lobby's portal.
  - `obstacles.lua` (box models), `ambient.lua` (wildlife), `window.lua` (full screen / side
    window, window frame), `keys.lua` (the game's controls: `ACTIONS` of a run and of the menus,
    two keys and two gamepad buttons each, `profile.keys` over their defaults; `KeyAction`,
    `ActionKey`, `Chord`; what shows keys shows Key 1, or Gamepad 1 since a gamepad was used:
    `ShownSlot`, `NoteDevice`, `ShownKeys`), `menu.lua` (restart bar, number box), `hud.lua`
    (score; where it sits, `profile.hud`: beside the pause menu, a top corner or the top
    centre; its extra info, `HUD_INFO` rows turned on in `profile.hudInfo`, a section under a
    divider that makes the card taller, redrawn every `INFO_EVERY`; under it during a
    challenge the challenge card: its period, goal, difficulty, time to the reset, best and the
    live target, ahead or behind the best at this distance),
    `legend.lua` (the running keys, below the scorecard and the challenge card).
  - `messages.lua` — the pause and end menus (difficulty, and in a custom game its settings,
    `CUSTOM`, a page per category such as Seed options: **a new custom setting is an item on
    its category's page** over a profile setting `NewState` reads; full screen, they hang from
    one top line); a challenge's own pause and end pages (its best, the difference to the one
    before); announcements (the challenge's or a custom game's "Finish!", `Finish`), the gate's
    flash and vortex.
  - `menus.lua` — the menu window: pages of items (actions, choices, info lines, notes, number
    boxes, grayed out while they cannot be typed in) steered by directions, accept, back and a
    page's extra action; a page may set its own `width`, or be a table (`columns`: sized from
    samples of its longest label and values, as the leaderboard is). The window can be dragged
    away from where its owner placed it (`menu.panel`, what the scorecard is anchored to); each
    `Open` puts it back, and nothing is saved.
    `MenuAction` maps a key (keyboard or gamepad) to them through keys.lua's menu actions.
  - `screens.lua` — the title screen and the main menu over the lobby, camera shots and glides,
    the seated character, the way into a run, title music; the main menu's pages: Play (a new
    seed, difficulty, auto mode), Challenges (each challenge's page, its leaderboard, the
    history and streak; `PlayChallenge`), Custom (Play's items and `CUSTOM`; `PlayCustom`);
    the keys of every screen and menu (`OnScreenKey`).
  - `controls.lua` — input, per-frame `Step` (a challenge's finish and trace), best score (a
    challenge's: `SaveChallenge`, shared with `leaderboard:Share`), auto mode.

Tests: `npm run test:game` runs `tests/*.lua` without the client; `npm run bench:overlay`
counts WoW API calls per frame. Development tools live in `AzerothSurfers_Dev`
([../AzerothSurfers_Dev/CLAUDE.md](../AzerothSurfers_Dev/CLAUDE.md)); this addon only keeps the
hooks they use.
