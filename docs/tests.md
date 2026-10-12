# Tests

Plain Lua scripts in `tests/` that load the addon's files outside the client and assert on
them. No framework, no client, no build.

```sh
npm run test:game       # simulation.lua, controls.lua, overlay.lua, leaderboard.lua, options.lua (stops at the first failure)
npm run bench:overlay   # WoW API calls per frame; not part of test:game or check
npm run test:assets     # dev asset audit: asynchronous loading, missing animations, audio and reports
lua tests/simulation.lua  # one file on its own, from the repo root
```

Needs `lua` on PATH. Run from the repo root: paths are relative to it.

## The files

| File                | Covers                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `load.lua`          | Not a test. Loads addon files into an `app` table the way the TOC does: `"game/simulation"` is `AzerothSurfers/src/game/simulation.lua`, an `.xml` entry loads each of its `<Script>`s and `<Include>`s in order.                                                                                                                                                                                                                    |
| `simulation.lua`    | The pure game: physics, collisions, coins and streaks, scoring, difficulties, seeds. Every pattern keeps the track's rules and can be run through (a search over inputs). The autopilot. A new run's empty road; a run from the lobby: its gate in front, and its intro collects every coin at every difficulty. Challenges: periods and their reset, draws, status and reminder, the live target's checkpoints, history and streak. |
| `controls.lua`      | Input and movement sampling, coin sound, with the few WoW functions it needs defined as globals. A challenge's runs (its seed to its goal, restarts, its best) and its finish at the last portal.                                                                                                                                                                                                                                    |
| `overlay.lua`       | The view with stubbed frames: projection, twin, ground, biomes, light, HUD texts. The title, the main menu and the way into a run from the lobby, the menus' keys (E, Q, R, every other key on to WoW), a new seed leaving the lobby's look alone, the pause and end menus, the challenge card's live target. And that **a running frame allocates nothing**.                                                                        |
| `leaderboard.lua`   | The challenges' leaderboard: the messages a best and an ask make, what is kept and what ignored (malformed, out of period, other channels, oneself), how often it asks and answers, the ranking, the bound per period and dropping ended periods.                                                                                                                                                                                    |
| `bench-overlay.lua` | Counts API calls per frame on a generated track (the average, and the median, 90th percentile and worst frame: jumps and lane changes move the camera). Every frame method is an auto-stub returning nil.                                                                                                                                                                                                                            |

## How a test looks

`simulation.lua` has a tiny helper: `test(name, fn)` runs `fn` and prints `PASS name`. The other
files are top to bottom blocks that end in `print("PASS ...")`. A failing `assert` stops the
file, so put a message on every assert that says what broke:

```lua
test("a coin streak survives a coin missed beside it", function()
    local s = fresh(coin(0, 2), coin(1, 2), coin(0, 5)) -- a run with only these boxes
    advance(s, 0.3, 60) -- 0.3 seconds at 60 fps
    assert(s.streak == 2, "the coin beside does not break it")
end)
```

`simulation.lua` helpers: `fresh(...)` (a started run, empty track plus the given boxes),
`advance(s, seconds, fps)`, `obstacle`, `coin`, `platform` (box builders), `branch` and
`runnable` (the input search).

## Writing a new one

- Add it to the file for its layer: game rules in `simulation.lua`, input in `controls.lua`,
  anything drawn in `overlay.lua`. A new file must also go into `test:game` in `package.json`.
- Loading a file the tested code now needs: add it to that test's `load.lua` list, in TOC order.
- Test behaviour through the real functions (`g.Update`, `pattern.place`, `o:Render`), not by
  copying their logic into the test.
- Change a shared setting (`g.STREAK`, `g.geometry.halfWidth`, a `db` value) only for the test,
  and set it back at its end.
- Visual changes (a model, a size, a color) need no new test: they are checked in-game.

## Common pitfalls

- **Gameplay revisions.** Challenge fixtures saved as competitive bests must include
  `gameplayRevision` and use `challenges.Save` or `challenges.RecordKey(period)`. Unversioned
  fixtures are legacy history. Revision regression tests check that old scores survive in
  history without affecting current targets, ranking or daily streak counts, and that peers
  exchange bests and queries only with matching gameplay rules.
- **Floating point.** `3 * 0.6` is `1.7999999999999998`, not `1.8`, so a box on layer 3 is
  "below" a 1.8-yard body. Compare heights with a small epsilon (the simulation uses `1e-6`).
- **Allocation.** The allocation test fails on any table or string built per frame:
  `string.format`, `..`, `{}` in a running path. Use `SetFormattedText`, cached tables, and
  compare values instead of building keys (`overlay.Unchanged`).
- **Data on a stub.** The stubbed frames and actors in `overlay.lua` and `bench-overlay.lua`
  answer every unknown field with a function, so a field the addon stores on a frame or an
  actor (`frame.surferAlpha`, `actor.surferScale`) reads as a function in the tests and breaks
  them. Keep such data in tables of your own (the menu's `sc.alpha`, the occluder's `occ.scale`).
  `shapes.Show`'s flag is stored the same way, so in the benchmark a scene shown that way never
  shows.
- **Stubs fall behind.** A new WoW API call in drawing code needs a stub in `overlay.lua`
  (and returns a number in `bench-overlay.lua` if the code does arithmetic with it).
  `bench-overlay.lua` is not in `test:game`, so it breaks unnoticed: run it after changing the
  overlay.
- **Too short to catch it.** The autopilot test runs one seed for 1000 yards; a new pattern may
  never come up there. For a new pattern, also run the autopilot over many seeds and longer
  distances once (a throwaway script in your scratch folder, not in `tests/`).
- **A pattern's length.** A pattern returns how far it reaches; if it ends with a jump, that
  includes the landing (`track.Landing`), or the next pattern starts under the runner in the air.
  The per-pattern tests check each pattern alone, so only a full run shows this.
- **Seeds change.** Any new or changed pattern changes what every seed lays out. Tests compare
  a seed with itself, never with a stored layout; keep it that way.
- **`app.addon` in tests.** `load.lua` gives a stand-in when a test has none: a module is its
  prototype's instance, and its AceComm messages land in `module.sent`.
- **Lua version.** The addon is Lua 5.1, but the `lua` on PATH may be newer and accept what 5.1
  does not (`//`, `goto`, integer formatting). Passing tests do not prove 5.1 syntax:
  `npm run check:lua` does, with a Lua 5.1 `luac`.
- **Globals between files.** Each test file runs in its own `lua` process, but within a file a
  global defined by one block (`PlaySoundFile`, `GetTime`) stays for the blocks after it.

`options.lua` checks the player settings without the development addon, live display and input
updates, then development-only registration and relocated settings using the same profile.
