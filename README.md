# Azeroth Surfers

A Subway Surfers-inspired, three-lane runner for WoW Forever (interface 16001).
Built from the shared addon template with Ace3, checks, formatting, packaging and release workflows.

## Play

Install the **AzerothSurfers** subfolder in Interface/AddOns, reload, and type **/surfers** (or **/azerothsurfers**) or click the minimap icon.

The game opens on its title screen, at a portal in Elwynn Forest with the title music playing.
Press **E** to enter the main menu, where your character sits
at a campfire beside the track: **Play** (then **Play**, **Difficulty**, **Seed**, **Auto
mode**, **Cancel**), **Stats**, **Options** and **Close**. **W** / **S** (or the arrow keys, or
the D-pad) choose, **A** / **D** change the difficulty, **E** accepts and **Q** goes back; the
mouse works too, and every other key goes on to WoW (Enter still opens the chat).
The seed starts random: **R** rolls a new one, or type one into its box (**E** or a click, then
Enter). On Play
your character stands up, walks over to the track and runs through the portal into the first
zone. Portals along the track lead from zone to zone: Elwynn Forest, Durotar, Teldrassil and
Tirisfal Glades, each with its own road, obstacles, enemies and wildlife (**/surfers options**
can fix one instead). Paused or after a run, the same kind of menu shows the run's numbers: **Go on** (or
Q), **Start over** / **Run again** (or R), **Difficulty** for the next run, **Auto mode** and
**Main menu**, which goes back to the fire.

| While running   | Keys                      | Arrow keys | Gamepad                 |
| --------------- | ------------------------- | ---------- | ----------------------- |
| Lane left/right | **A**/**D**               | ←/→        | Left stick or D-pad ←/→ |
| Jump            | **Space**                 | ↑          | A                       |
| Duck / drop     | **S**                     | ↓          | X                       |
| Pause           | **Q**                     | **P**      | Start                   |
| Start over      | **R** (hold during a run) |            | Y                       |

Duck is a short roll, two layers tall; in the air it drops you fast and rolls on landing. Every
key is the game's own while it is open, whatever it is bound to in WoW: change any of them, two
keys and two gamepad buttons each, on the **Keys** tab of **/surfers options**. A key may do one
thing in a run and another in the menus. Use the buttons at the top to restart, pause/resume, or
close.

Footsteps follow the biome's ground, with wooden contacts on platforms and ramps. Jumping
sounds on takeoff and landing; rolling makes a contact sound when it begins, with no running
steps in the air or during the roll. Toggle **Footsteps** on the options' **Sound** tab.

All keyboard inputs pass through to WoW, so your real character moves and jumps too.
Custom movement bindings and modifier keys are respected. Typing in an edit box does not
control the runner. Forward movement no longer triggers a jump. The track advances only while your character actually moves forward relative to its facing. Stopping, moving backward, pure strafing, and pushing against a wall do not advance it. Autorun and mouse movement work too. Jumping and lane transitions still update while stopped.
**/surfers options** opens addon settings. The game closes and pauses on combat entry
and pauses when hidden. The addon never moves your character or changes WoW's camera.

The track is a grid: three lanes side by side and layers stacked 0.6 yards high. You run on
layer 0; a jump (WoW's own arc) reaches a little past layer 2, and your body is three layers tall.

- **Red obstacles**: one or two layers high can be jumped; four-layer walls must be dodged.
- **Amber barriers** float on layer 3: run under them, a jump hits them. **Low barriers** on layer
  2 are too low to run under and too high to jump: duck under them. Some guard a crawlway of
  coins beside the open road.
- **Blue platforms** are higher ground on layers 1 to 3: jump onto them or take their ramp (always
  there for layer 3), run along the top with its coins and obstacles, jump across to a higher
  platform beside it, and fall back down at its end. Running or changing lanes into a platform's
  side ends the run.
- **Gold coins** sit on a layer and award 25 points; high arcs over hurdles need a jump.

Distance adds points, speed increases gradually, and your best score is saved account-wide. A
run from the lobby counts from where you take over past the portal, as a restart counts from its
start: the coins and yards on the way there do not count. In **Auto: zone to zone**, every portal
into the next zone raises the score multiplier by one (the lobby's portal does not).
Every pattern leaves a lane that can be run, jumped or climbed through; `tests/simulation.lua`
checks that on generated tracks.

## How it looks

The game is drawn full screen around your character: the road, obstacles and coins sit under the
rest of the UI, and changing lanes slides the road under your character, which the camera keeps
centered. A twin (a copy of your character with your gear) runs exactly where your real character
stands and covers it, in front of the road. It mirrors how you move (running, walking, strafing,
backpedalling, jumping), and jumping or running on a platform lifts it with the road dropping
away beneath it. Coins near you are spinning 3D models from the game files.

The road imitates WoW's follow camera and has to be calibrated once: on the **Calibration** tab
of **/surfers options**, adjust camera pitch, focus height, field of view and twin size until the
see-through twin (shown before a run starts) covers your character. Zooming or tilting the camera mid-run changes the fit, unless
the client reports the zoom. Calibration adjusts the addon's view only; it never changes WoW's camera.

### Modes

In **/surfers options**, on the **Display** tab (**Capture movement keys** is on the **Game** tab):

- **Full screen** (the default) is the game as described above, part of the world. **Window frame
  in full screen** adds a border, title bar and close button around the screen.
- **Side window** puts the game in a window of its own, out of the way: drag it by its title, size
  it from its corner. It has its own camera (the calibration's pitch, focus, distance and field of
  view) and a sky behind the road. Its frame can be turned off too, which fixes it in place.
- **Capture movement keys** (on by default) works in both: while the game is open it keeps the
  game's keys and your move, strafe, turn and jump keys from WoW, on every screen and menu, so
  your character stays where it is and the runner runs on its own. Steering with the mouse
  buttons still moves your character. While the options are open the game takes no keys at all,
  so binding one there steers nothing.

The window frame's minimize button switches from full screen to the side window, its maximize
button back. The game opens on a start dialog with your best score. **R** starts over: press it
once after a run, or hold it for a moment during one. **Q** pauses and goes on.

Every run comes from a **seed**: the same seed always lays out the same track, obstacles and
roadside. The start dialog shows this run's seed; type a number into its Seed box to play that one
on every run (empty: a new seed each run). `/surfers seed <number>` and `/surfers seed random` do
the same, and the paused and finished screens show the seed of the run.

The `AzerothSurfers_Dev` addon in this repository (never released) adds development tools to `/surfers`:
`/surfers help` lists them.

## Development

- npm install
- npm run format
- npm run check (TypeScript, addon manifest, Lua syntax, XML, formatting)
- npm run dev:link -- "<WoW>/Interface/AddOns", then /reload
- npm run package:addons produces a local distributable ZIP.

Release workflows are inherited from the template.
Configure project IDs and upload secrets only when publishing; none are required to play locally.
