# Surfer

A Subway Surfers-inspired, three-lane runner for WoW Forever (interface 16001).
Built from the shared addon template with Ace3, checks, formatting, packaging and release workflows.

## Play

Install the **Surfer** subfolder in Interface/AddOns, reload, and type **/surfer** or click the minimap icon.

- Your WoW turn-left / strafe-left binding: left lane.
- Your WoW turn-right / strafe-right binding: right lane.
- Your WoW jump binding: jump (also starts the first run).
- Your WoW move-forward binding: start the first run.
- Use the buttons at the top to restart, pause/resume, or close.

All keyboard inputs pass through to WoW, so your real character moves and jumps too.
Custom movement bindings and modifier keys are respected. Typing in an edit box does not
control the runner. Forward movement no longer triggers a jump. The track advances only while your character actually moves forward relative to its facing. Stopping, moving backward, pure strafing, and pushing against a wall do not advance it. Autorun and mouse movement work too. Jumping and lane transitions still update while stopped.
**/surfer options** opens addon settings. The game closes and pauses on combat entry
and pauses when hidden. The addon never moves your character; it only changes the camera when
**Hide your real character** is on.

The track is a grid: three lanes side by side and layers stacked 0.6 yards high. You run on
layer 0; a jump (WoW's own arc) reaches a little past layer 2, and your body is three layers tall.

- **Red obstacles**: one or two layers high can be jumped; four-layer walls must be dodged.
- **Amber barriers** float on layer 3: run under them, a jump hits them.
- **Blue platforms** are higher ground on layers 1 to 3: jump onto them or take their ramp (always
  there for layer 3), run along the top with its coins and obstacles, jump across to a higher
  platform beside it, and fall back down at its end. Running or changing lanes into a platform's
  side ends the run.
- **Gold coins** sit on a layer and award 25 points; high arcs over hurdles need a jump.

Distance adds points, speed increases gradually, and your best score is saved account-wide.
Every pattern leaves a lane that can be run, jumped or climbed through; `tests/simulation.lua`
checks that on generated tracks.

## How it looks

The game is drawn full screen around your character: the road, obstacles and coins sit under the
rest of the UI, and changing lanes slides the road under your character, which the camera keeps
centered. A twin (a copy of your character with your gear) runs exactly where your real character
stands and covers it, in front of the road. It mirrors how you move (running, walking, strafing,
backpedalling, jumping), and jumping or running on a platform lifts it with the road dropping
away beneath it. Coins near you are spinning 3D models from the game files.

The road imitates WoW's follow camera and has to be calibrated once: in **/surfer options**, adjust
camera pitch, focus height, field of view and twin size until the see-through twin (shown before
a run starts) covers your character. Zooming or tilting the camera mid-run changes the fit, unless
the client reports the zoom. **Hide your real character** zooms into first person while the game is
open, where WoW does not draw your character, and back out after.

`/surfer profile` (twice) reports the addon's milliseconds per frame; `/surfer debug` prints the
twin's camera.

## Development

- npm install
- npm run format
- npm run check (TypeScript, addon manifest, Lua syntax, XML, formatting, simulation tests)
- npm run dev:link -- "<WoW>/Interface/AddOns", then /reload
- npm run package:addons produces a local distributable ZIP.

Release workflows are inherited from the template.
Configure project IDs and upload secrets only when publishing; none are required to play locally.
