# Player settings

Settings describe preferences that persist across runs. Choose difficulty in Play and
configure seeds, start/end distances and scoring in Custom from the game menu.

| Category                  | Settings                                                                                                                         | Player purpose                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| General                   | Minimap button, login challenge reminder, sharing, distance units                                                                | Access, notifications, privacy and familiar units.                                        |
| Display: Window           | Display mode, borders, reset side window, window priority                                                                        | Fit the game around the player's WoW UI. Priority chooses whether other windows cover it. |
| Display: Road and ground  | Opacity, brightness, darker at night                                                                                             | Readability and appearance. Opacity applies only to full screen.                          |
| Display: Camera           | Distance, field of view                                                                                                          | Comfortable framing; distance can also be adjusted with the mouse wheel.                  |
| Scorecard: Position       | Anchor, horizontal/vertical offsets, reset position                                                                              | Keep the score visible without covering other UI.                                         |
| Scorecard: Information    | Coin percentage beside the counter; extra rows for time, speed, region, next portal, coin percentage, best streak and best score | Choose useful run information. The extra coin percentage is a separate row.               |
| Controls: Input and hints | Capture movement keys, hotkey legend, pressed-key window style and reset position                                                | Prevent accidental WoW movement, learn controls and display inputs while streaming.       |
| Controls: Key bindings    | Two keyboard and two gamepad bindings per action, reset bindings                                                                 | Customize running and menu controls.                                                      |
| Sound                     | Coins, creatures, portals, footsteps, title music                                                                                | Choose which sounds play.                                                                 |
| Profiles                  | AceDB profile selection, copy, reset and deletion                                                                                | Reuse settings across characters or maintain different setups.                            |

The development addon adds **Debug**, with Run overrides, Rendering and Diagnostics pages:

| Debug settings                                           | Why outside player preferences                                                            |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Difficulty, biome, fixed seed, seed, start/end distances | Run setup already belongs in the game menus; biome overrides are for playtesting.         |
| Base frame level                                         | Fine tuning UI stacking; window priority covers the normal player need.                   |
| Fixed ground curve and curve amount                      | Override biome geometry for rendering development.                                        |
| Camera pitch, focus height, twin size                    | Calibrate projection and character rendering. Player framing uses zoom and field of view. |
| Log level, seed and FPS scorecard rows                   | Troubleshooting and reproducibility.                                                      |

Moving a setting does not change its saved value. Existing profiles, custom games and slash
commands retain their behavior. Debug settings are supplied by `AzerothSurfers_Dev`, which
is excluded from releases.
