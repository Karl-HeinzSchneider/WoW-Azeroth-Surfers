# Surfer

A Subway Surfers-inspired, three-lane runner for WoW Forever (interface 16001).
Built from the shared addon template with Ace3, checks, formatting, packaging and release workflows.

## Play

Install the **Surfer** subfolder in Interface/AddOns, reload, and type **/surfer** or click the minimap icon.

- Your WoW turn-left / strafe-left binding: left lane.
- Your WoW turn-right / strafe-right binding: right lane.
- Your WoW jump binding: jump (also starts the first run).
- Your WoW move-forward binding: start the first run.
- Use the window buttons to restart, pause/resume, or close.

All keyboard inputs pass through to WoW, so your real character moves and jumps too.
Custom movement bindings and modifier keys are respected. Typing in an edit box does not
control the runner. Forward movement no longer triggers a jump. The track advances only while your character actually moves forward relative to its facing. Stopping, moving backward, pure strafing, and pushing against a wall do not advance it. Autorun and mouse movement work too. Jumping and lane transitions still update while stopped.
**/surfer options** opens addon settings. The game closes and pauses on combat entry
and pauses when hidden. No real-player movement or camera commands are issued by the addon.

Dodge or jump over red obstacles; gold pickups award 25 points. Distance adds points,
speed increases gradually, and your best score is saved account-wide.
Each obstacle row leaves two lanes clear. Obstacle faces and collision checks share world-space dimensions; the red obstacle volume is the collision reference. Decorative models are fitted inside it. Coin pickup uses its own smaller bounds and vertical overlap with the runner.

## Full-screen view (default)

Your real character is the runner. The road, obstacles and coins are drawn full screen around it,
under the rest of the UI; changing lanes slides the road under your character, which the camera
keeps centered. Everything behind your character is cut out over its body with a capsule mask, so
your character appears in front of the road and obstacles.

The road imitates WoW's follow camera and has to be calibrated once: in **/surfer options**, adjust
camera pitch and focus height until the gold bar sits under your feet. Zooming or tilting the camera
mid-run changes the fit (unless the client reports the zoom). The window view below is still
available under **View**.

## Window view

A native ModelScene copies your current character and equipment and plays run/jump animations.
The fixed camera projects a segmented track that curves away toward the horizon. Native scene projection keeps the track aligned with actors; an analytic projection is the fallback.
Ground is colored UI geometry, not imported terrain. Coins and obstacle silhouettes remain readable
without scenery assets. Obstacles also use the wrapped-present creature display (71933), referenced
by the client's shared UI; availability still needs in-game verification.
There are no bundled custom models, tree assets, or dependency on Spyglass.

Model origin, race size, animation appearance, and native camera projection need visual verification
in the Forever client. The same jump input reaches both WoW and Surfer; their jump physics remain independent.
Projected ground does not write to the ModelScene depth buffer.

## Development

- npm install
- npm run format
- npm run check (TypeScript, addon manifest, Lua syntax, XML, formatting, simulation tests)
- npm run dev:link -- "<WoW>/Interface/AddOns", then /reload
- npm run package:addons produces a local distributable ZIP.

Release workflows are inherited from the template.
Configure project IDs and upload secrets only when publishing; none are required to play locally.
