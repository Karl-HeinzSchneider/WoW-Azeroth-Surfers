---@type string, Surfer
local _, app = ...
-- Durotar: the dusty Horde road through the red canyons. Everything not listed is the
-- default's (default.lua documents every field). Models from world/kalimdor/durotar/
-- passivedoodads/ and world/generic/orc/passive doodads/; creatures by the display ids of
-- Durotar's NPCs. A first pass: sizes and turns are fitted by eye in the game.

-- A ramp's planks, as Elwynn's (redridgedocksplank01), until Durotar has its own.
local RAMP = { { model = 190091, across = 3, segment = 3, width = 1.5 } }

app.biomes.Register("durotar", {
    name = "Durotar",

    ground = {
        surfaces = {
            road = { texture = 187034 }, -- tileset/durotar/durotarroad.blp
            dirt = { texture = 187019 }, -- tileset/durotar/durotardirtsmooth.blp
            grass = { texture = 187021 }, -- tileset/durotar/durotargrass.blp
        },
    },

    -- A hot, hazy sky over red earth.
    sky = {
        top = { 0.42, 0.6, 0.85 },
        horizon = { 0.93, 0.8, 0.62 },
        land = { 0.5, 0.33, 0.2 },
        haze = 0.5,
    },

    -- The track: orc crates and barrels to jump, a beam on orc fence posts to run under, and
    -- for now Elwynn's lumber piles to run on.
    obstacles = {
        obstacle = {
            -- barrelsandcrates/orccrate01 or 02, or orcbarrel01.
            {
                layers = 1,
                weight = 2,
                items = { { model = { 199094, 199095 }, height = 0.85, yaw = { -12, 12 } } },
            },
            { layers = 1, items = { { model = 199090, height = 0.85, yaw = { 0, 360 } } } },
            -- orccrate03, or orcbarrel03.
            { layers = 2, weight = 2, items = { { model = 199096, height = 1.24, yaw = { -8, 8 } } } },
            { layers = 2, items = { { model = 199091, height = 1.24, yaw = { 0, 360 } } } },
            -- The tall wall, too high to jump: two orc crates stacked, the one with the Horde's
            -- mark on top smaller (it looked too big at the same size), or a tall brazier
            -- (braziers/tallbrazier01). The wall's box stays its full height.
            {
                layers = 4,
                items = {
                    { model = 199096, height = 1.2, yaw = { -5, 5 } },
                    { model = { 199094, 199095 }, z = 1.2, height = 0.77, yaw = { -15, 15 } },
                },
            },
            { layers = 4, items = { { model = 199141, height = 2.3, yaw = { 0, 360 } } } },
        },
        -- Durotar's creatures facing the runner; all attack (16) when the runner comes close,
        -- the tall ones from their ready stance (25).
        enemy = {
            -- Low enough to jump: a Mottled Boar (503), a Venomtail, Armored or Clattering
            -- Scorpid (2732, 2487, 2486), or a Durotar Tiger (598), each with its kind's attack.
            { layers = 2, items = { { creature = 503, yaw = 180, attack = 16, sound = 380 } } },
            { layers = 2, items = { { creature = { 2732, 2487, 2486 }, yaw = 180, attack = 16, sound = 715 } } },
            { layers = 2, weight = 0.5, items = { { creature = 598, yaw = 180, attack = 16, sound = 643 } } },
            -- Too tall: the Razormane quilboar (Quilboar 1218, Scout 1252, Dustrunner 6088,
            -- Battleguard 1964), all with the quilboar's attack.
            {
                layers = 4,
                weight = 2,
                items = {
                    {
                        creature = { 1218, 1252, 6088, 1964 },
                        height = 2,
                        yaw = 180,
                        animation = 25,
                        attack = 16,
                        sound = 1176,
                    },
                },
            },
            -- The Burning Blade (Cultist 4194, Thug 4188, Fanatic 4192), with an orc's attack.
            {
                layers = 4,
                items = {
                    {
                        creature = { 4194, 4188, 4192 },
                        height = 2,
                        yaw = 180,
                        animation = 25,
                        attack = 16,
                        sound = 1341,
                    },
                },
            },
            -- A Kolkar Drudge (9442), a centaur: bigger and rarer.
            {
                layers = 4,
                weight = 0.5,
                items = { { creature = 9442, height = 2.5, yaw = 180, animation = 25, attack = 16, sound = 1040 } },
            },
        },
        -- deadminelumberpilesmall across two orcfence/orcfencepost posts.
        barrier = {
            {
                items = {
                    { model = 199210, x = -1, ground = true, height = 2.15 },
                    { model = 199210, x = 1, ground = true, height = 2.15 },
                    { model = 198340, yaw = 90, z = 0.1, scale = 0.65 },
                },
            },
        },
        -- Elwynn's lumber piles for now: deadminelumberpilesmall for one layer,
        -- deadminelumberpilelarge for two and three, stacked for four and five.
        platform = {
            { layers = 1, items = { { model = 198340, every = 3.4 } }, ramp = RAMP },
            { layers = 2, items = { { model = 198339, every = 2.3 } }, ramp = RAMP },
            { layers = 3, items = { { model = 198339, every = 3.4 } }, ramp = RAMP },
            {
                layers = 4,
                items = {
                    { model = 198339, every = 2.3, height = 1.2 },
                    { model = 198339, every = 2.3, z = 1.2, height = 1.2 },
                },
                ramp = RAMP,
            },
            {
                layers = 5,
                items = {
                    { model = 198339, every = 2.9, height = 1.5 },
                    { model = 198339, every = 2.9, z = 1.5, height = 1.5 },
                },
                ramp = RAMP,
            },
        },
    },

    -- The roadside: dry bushes and cactus by the road, rocks, an orc brazier lamp or a Horde
    -- banner now and then. Durotar's twisted trees (trees/durotartree01 to 06: 201803 to
    -- 201808) are left out for now: too big beside the road.
    decorations = {
        spacing = { 1, 6 },
        groups = {
            -- Nothing for a while.
            { weight = 2, length = { 4, 12 }, items = {} },
            -- bushes/durotarbush01 to 04, one or two, by the road.
            {
                weight = 3,
                length = { 3, 6 },
                items = {
                    {
                        model = { 201768, 201769, 201770, 201771 },
                        x = { 5, 7 },
                        yaw = { 0, 360 },
                        scale = { 0.6, 0.9 },
                    },
                    {
                        model = { 201768, 201769, 201770, 201771 },
                        x = { 6, 8 },
                        d = { 1.5, 3 },
                        yaw = { 0, 360 },
                        scale = { 0.6, 0.9 },
                        chance = 0.5,
                    },
                },
            },
            -- bushes/cactusapple01.
            {
                weight = 1,
                length = 3,
                items = { { model = 201766, x = { 5.5, 8 }, yaw = { 0, 360 }, scale = { 0.7, 1 } } },
            },
            -- rocks/durotarrock01 to 08, small, by the road.
            {
                weight = 2,
                length = 3,
                items = {
                    {
                        model = { 201783, 201785, 201786, 201788, 201789, 201790, 201791, 201792 },
                        x = { 5, 8 },
                        yaw = { 0, 360 },
                        scale = { 0.3, 0.6 },
                    },
                },
            },
            -- lampposts/orcbrazierlamppost01, its fire by the road.
            { weight = 1, length = 4, items = { { model = 199197, x = 5.5, yaw = { -10, 10 } } } },
            -- hordebanners/hordebanner01 to 04.
            {
                weight = 1,
                length = 4,
                items = { { model = { 199173, 199174, 199175, 199176 }, x = { 6, 7 }, yaw = { -20, 20 } } },
            },
        },
    },
})
