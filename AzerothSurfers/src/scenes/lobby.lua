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

-- Elwynn Forest with more grass beside the road: the default's bands (default.lua), the grass
-- 8 yards wider and fading out 9 further. Only the lobby's: never a zone of a run, nor offered
-- in the options.
app.biomes.Derive("lobby", "elwynn", {
    tier = false,
    hidden = true,
    ground = {
        bands = {
            { surface = "grass", layer = -2, segments = 2, from = 3.3, to = 15.9, opacity = { 1, 1 } },
            { surface = "grass", layer = -2, segments = 2, from = 15.9, to = 19.9, opacity = { 1, 0 } },
            { surface = "dirt", layer = -1, segments = 2, from = 3.3, to = 5.3, opacity = { 1, 0 } },
            { surface = "road", layer = 0, segments = 1, from = 0, to = 3.3, opacity = { 1, 1 } },
            { surface = "road", layer = 0, segments = 1, from = 3.3, to = 4.3, opacity = { 1, 0 } },
            { surface = "dirt", layer = 1, segments = 4, from = 0.95, to = 1.45, opacity = { 0.3, 0.3 } },
        },
    },
})

app.lobby = {
    -- How the stretch before the portal looks.
    biome = "lobby",
    -- The portal's rim. The gate's strip (track.GATE) around it is dressed by its transition;
    -- the lobby's own models stand before it.
    rim = 50,
    -- The lane the run starts in (-1: the right one); the character walks over to it from the
    -- fire.
    lane = -1,
    -- Coin rows in front of the portal: `lane`, the first coin's `from`, `count` (3 yards
    -- apart), `layer` (0 if left out). The gate adds its arc over the middle lane.
    coins = {
        { lane = -1, from = 10, count = 3 },
        { lane = 0, from = 24, count = 4 },
    },
    -- The run up to the portal plays itself (autopilot.Intro), through every coin: into `lane`
    -- from `at` yards on, then a jump whose top is at the rim, through the gate's arc. The
    -- player takes over past the gate's strip.
    intro = { { at = 17.5, lane = 0 } },

    -- Models, placed like a transition's `items` (biomes.lua): `model` (a file id or a list),
    -- `x`, `d`, `z`, `yaw` (degrees), `scale` or `height` (yards its top is scaled to), `lift`;
    -- any number may be a { min, max } range.
    items = {
        -- The camp, ahead of the character and to its right, where the menu's camera sees it. Flat
        -- props built a little into the ground are `lift`ed: the ground is only drawn, so a buried
        -- part would show over it.
        -- The fire (elwynn/passivedoodads/campfire/elwynncampfire) with a boar roasting over it on
        -- its own spit (generic/orc/passive doodads/roasts/roastboar).
        { model = 189705, x = FIRE_X, d = FIRE_D, height = 1.02 },
        { model = 199231, x = FIRE_X, d = FIRE_D, scale = 0.55, yaw = 30 },
        -- Across the fire from the character, turned toward it: tree/elwynnlog01 as a bench with
        -- a mug on it (human/passive doodads/mugs/mug01). By the fire a firewood pile (human/
        -- passive doodads/firewood/firewoodpile01) and a bucket (buckets/bucket).
        { model = 189915, x = 9.4, d = 2.7, height = 0.5, yaw = 35, lift = true },
        { model = 198360, x = 9.3, d = 2.8, z = 0.5, height = 0.15, yaw = 40 },
        { model = 198197, x = 9.2, d = 0.2, height = 0.45, yaw = 70, lift = true },
        { model = 198068, x = 7, d = 2.5, height = 0.35, yaw = { 0, 360 } },
        -- A tent behind the fire (generic/buildings/humantentmedium, a small one), a bearskin rug
        -- before its door (human/passive doodads/rugs/generalbearskinrug01) and a shovel
        -- against its side (elwynn/passivedoodads/shovel).
        { model = 197109, x = 11.8, d = 8, height = 2.4, yaw = 200, lift = true },
        { model = 198426, x = 10.8, d = 5.8, scale = 0.6, yaw = 110, lift = true },
        { model = 189854, x = 13.8, d = 7, height = 1.1, yaw = 30 },
        -- Supplies beside the tent: a crate with a smaller one and a lantern on it (human/
        -- passive doodads/crates/replacecrate01, 03, lanterns/generallantern01) and a barrel
        -- (westfall/passivedoodads/barrel/westfallbarrel01).
        { model = 198165, x = 9.6, d = 6.6, height = 0.6, yaw = 15 },
        { model = 198167, x = 9.6, d = 6.6, z = 0.6, height = 0.4, yaw = 50 },
        { model = 198327, x = 9.4, d = 6.4, z = 1, height = 0.35 },
        { model = 190535, x = 9.2, d = 7.8, height = 1, yaw = { 0, 360 } },
        -- Big trees around the camp and along the road: trees/elwynntreecanopy01 to 04,
        -- canopylesstree01 to 04, elwynntree01/elwynnpine01, 02.
        { model = 189927, x = 12, d = -4, height = 16, yaw = { 0, 360 } },
        { model = 189928, x = 17, d = 14, height = 18, yaw = { 0, 360 } },
        { model = 189929, x = -13, d = 2, height = 17, yaw = { 0, 360 } },
        { model = 189930, x = -16, d = 16, height = 19, yaw = { 0, 360 } },
        { model = 189919, x = 9, d = 18, height = 12, yaw = { 0, 360 } },
        { model = 189921, x = -10, d = 24, height = 13, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { 14, 16 }, d = { 11, 14 }, height = { 9, 11 }, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { -9, -7 }, d = { 9, 13 }, height = { 9, 11 }, yaw = { 0, 360 } },
        { model = { 189924, 189925 }, x = { 11, 13 }, d = { 25, 28 }, height = { 10, 12 }, yaw = { 0, 360 } },
        -- bush/elwynnbush06 to 09 and detail/elwynnthornbush01, 02 by the road.
        {
            model = { 189697, 189698, 189699, 189700 },
            x = { 14, 15.5 },
            d = { -3, -1 },
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
    -- degrees (0 faces the portal, positive to the left), sitting (`sit`: SitGround), standing
    -- up (`standUp`: SitGroundUp) once Play is chosen, until the animation ends (`standUpMost`
    -- seconds at most). Then it turns toward `lane` over `turnSeconds` and moves there at
    -- `launch.speed`, `walk` yards ahead on the way, while the camera glides behind it.
    seat = { x = SEAT_X, yaw = -55, sit = 97, standUp = 98, standUpMost = 2, turnSeconds = 0.5, walk = 3 },
    -- In the lane the run starts at `speed` (yards per second: WoW's normal movement speed) and
    -- speeds up to the difficulty's over `seconds`.
    launch = { speed = 7, seconds = 1.2 },

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
    -- Seconds the camera glides from the title to the menu, and from the menu behind the runner
    -- (while it moves to its lane and speeds up).
    glide = { menu = 2, run = 1.6 },

    -- sound/music/gluescreenmusic/wow_main_theme.mp3: the classic login screen's theme, on the
    -- title and in the menu ("Title music").
    music = 53223,
}
