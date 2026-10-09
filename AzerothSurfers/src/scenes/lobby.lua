---@type string, AzerothSurfers
local _, app = ...
-- The lobby: where a run started from the menu begins. The character sits at a cooking fire
-- in Elwynn Forest beside a bit of track; the track runs through the portal of the first gate
-- into the run's first zone. The title screen and the main menu (screens.lua) look at it.
-- Distances are yards along the track from the start (d) and to the screen's right of the
-- road's middle (x); models are classic-era game file ids.

-- The camp on the grass right of the road: where the character sits, and the fire in front of
-- it to its right.
local SEAT_X = 6.5
local FIRE_X, FIRE_D = 7.9, 1.3

app.lobby = {
    -- How the stretch before the portal looks.
    biome = "elwynn",
    -- The portal's rim. The gate's strip (track.GATE) around it is dressed by its transition;
    -- the lobby's own models stand before it.
    rim = 50,
    -- The lane the run starts in (-1: the right one); the character walks over to it from the
    -- fire.
    lane = -1,
    -- Coin rows in front of the portal: `lane`, the first coin's `from`, `count` (3 yards
    -- apart), `layer` (0 if left out). The gate adds its arc over the middle lane.
    coins = {
        { lane = -1, from = 7, count = 4 },
        { lane = 0, from = 18, count = 4 },
    },

    -- Models, placed like a transition's `items` (biomes.lua): `model` (a file id or a list),
    -- `x`, `d`, `z`, `yaw` (degrees), `scale` or `height` (yards its top is scaled to), `lift`;
    -- any number may be a { min, max } range.
    items = {
        -- passivedoodads/campfire/elwynncampfire, with tree/elwynnlog01 beyond it as a bench.
        { model = 189705, x = FIRE_X, d = FIRE_D, height = 0.9 },
        { model = 189915, x = FIRE_X + 1.4, d = FIRE_D + 0.6, height = 0.5, yaw = 60 },
        -- trees/stumps/elwynntreestump01 behind the character.
        { model = 189939, x = SEAT_X + 1.9, d = -1.2, height = 0.6, yaw = { 0, 360 } },
        -- Big trees around the camp and along the road: trees/elwynntreecanopy01 to 04,
        -- canopylesstree01 to 04, elwynntree01/elwynnpine01, 02.
        { model = 189927, x = 12, d = -4, height = 16, yaw = { 0, 360 } },
        { model = 189928, x = 15, d = 9, height = 18, yaw = { 0, 360 } },
        { model = 189929, x = -13, d = 2, height = 17, yaw = { 0, 360 } },
        { model = 189930, x = -16, d = 16, height = 19, yaw = { 0, 360 } },
        { model = 189919, x = 9, d = 18, height = 12, yaw = { 0, 360 } },
        { model = 189921, x = -10, d = 24, height = 13, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { 8, 10 }, d = { 4, 7 }, height = { 9, 11 }, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { -9, -7 }, d = { 9, 13 }, height = { 9, 11 }, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { 11, 13 }, d = { 25, 28 }, height = { 10, 12 }, yaw = { 0, 360 } },
        -- bush/elwynnbush06 to 09 and detail/elwynnthornbush01, 02 by the road.
        {
            model = { 189697, 189698, 189699, 189700 },
            x = { 9.5, 11 },
            d = { -1, 1 },
            scale = { 0.5, 0.8 },
            yaw = { 0, 360 },
        },
        {
            model = { 189697, 189698, 189699, 189700 },
            x = { -7.5, -6 },
            d = { 3, 6 },
            scale = { 0.5, 0.8 },
            yaw = { 0, 360 },
        },
        { model = { 189777, 189778 }, x = { 5, 6 }, d = { 12, 15 }, scale = { 0.8, 1.1 }, yaw = { 0, 360 } },
        { model = { 189777, 189778 }, x = { -6, -5 }, d = { 19, 23 }, scale = { 0.8, 1.1 }, yaw = { 0, 360 } },
        -- A stretch of fence on the left (elwynnwoodfence01, turned round: its rails reach
        -- 4.16 yards ahead to the next post; elwynnwoodpost01 closes it), a lamppost at its end.
        { model = 189795, x = -5.2, d = -6, yaw = 180 },
        { model = 189795, x = -5.2, d = -1.84, yaw = 180 },
        { model = 189795, x = -5.2, d = 2.32, yaw = 180 },
        { model = 189796, x = -5.2, d = 6.48, yaw = 180 },
        { model = 189825, x = -6.8, d = 6.48, yaw = 180 },
    },

    -- The character at the fire, `x` yards right of the road's middle at d 0: turned `yaw`
    -- degrees (0 faces the portal, positive to the left), sitting (`sit`: SitGround), standing up (`standUp`: SitGroundUp)
    -- for `standUpSeconds` once Play is chosen; then it walks over to `lane` while the camera
    -- glides behind it.
    seat = { x = SEAT_X, yaw = -55, sit = 97, standUp = 98, standUpSeconds = 0.7 },

    -- The camera of each screen: `at` yards along the track, `side` yards to the screen's right,
    -- `height` yards up, `pitch` degrees down (negative: up), `fov` the vertical field of view in
    -- degrees. `sideWindow`: what differs in the side window. AzerothSurfers_Dev's /surfers shot tunes
    -- them live.
    shots = {
        -- Straight down the track at the portal, 42 yards on: its top just under the title, the
        -- coins on the track below it.
        title = { at = 8, side = 0, height = 3.4, pitch = 0, fov = 55 },
        -- Low behind the camp, in line with the character, well right of the road: the whole road
        -- lies to the left and runs diagonally from the lower left to the portal.
        menu = { at = -5, side = 6.5, height = 1.3, pitch = 5, fov = 55, sideWindow = { at = -5, height = 1.9 } },
    },
    -- Seconds the camera glides from the title to the menu, and from the menu into a run.
    glide = { menu = 2, run = 1.8 },

    -- sound/music/gluescreenmusic/wow_main_theme.mp3: the classic login screen's theme, on the
    -- title and in the menu ("Title music").
    music = 53223,
}
