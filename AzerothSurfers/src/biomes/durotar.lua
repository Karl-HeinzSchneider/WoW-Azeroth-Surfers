---@type string, AzerothSurfers
local _, app = ...
-- Durotar: the dusty Horde road through the red canyons. Models from world/kalimdor/durotar/
-- passivedoodads/ and world/generic/orc/passive doodads/.

-- A ramp's planks, as Elwynn's (redridgedocksplank01), until Durotar has its own.
local RAMP = { { model = 190091, across = 3, segment = 3, width = 1.5 } }

-- The enemies' attack sounds, the files of their classic sound kits (one picked at random):
-- sound/creature/boar/mwildboarattack1 to 3 (kit 380), silithidwasp/msilithidwaspattacka to c
-- (715), tiger/mtigerattacka to d (643), quillboar/quillboarattacka to d (1176), centaur/
-- centaurattacka to d (1040), and an orc's, sound/character/orc/orcmalenpc/orcmalenpc1/
-- orcwarriormale1attacka to c (1341).
local BOAR = { 545136, 545135, 545129 }
local SCORPID = { 560307, 560304, 560313 }
local TIGER = { 562394, 562385, 562393, 562386 }
local QUILBOAR = { 558709, 558714, 558716, 558717 }
local ORC = { 541311, 541309, 541314 }
local CENTAUR = { 546042, 546048, 546051, 546046 }

app.biomes.Register("durotar", {
    name = "Durotar",
    tier = 1,

    ground = {
        surfaces = {
            road = { texture = 187034 }, -- tileset/durotar/durotarroad.blp
            dirt = { texture = 187019 }, -- tileset/durotar/durotardirtsmooth.blp
            grass = { texture = 187021 }, -- tileset/durotar/durotargrass.blp
        },
        -- Flatter open land: 0.7 yards down at 50 ahead (the default: 1.25).
        curve = 0.00028,
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
            { layers = 2, items = { { creature = 503, yaw = 180, attack = 16, sound = BOAR } } },
            { layers = 2, items = { { creature = { 2732, 2487, 2486 }, yaw = 180, attack = 16, sound = SCORPID } } },
            { layers = 2, weight = 0.5, items = { { creature = 598, yaw = 180, attack = 16, sound = TIGER } } },
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
                        sound = QUILBOAR,
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
                        sound = ORC,
                    },
                },
            },
            -- A Kolkar Drudge (9442), a centaur: bigger and rarer.
            {
                layers = 4,
                weight = 0.5,
                items = { { creature = 9442, height = 2.5, yaw = 180, animation = 25, attack = 16, sound = CENTAUR } },
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
            -- The low one to duck under: the same, with a second beam a layer lower (`z` counts
            -- from the low box's bottom, a layer under the high one's).
            {
                layer = 2,
                items = {
                    { model = 199210, x = -1, ground = true, height = 2.15 },
                    { model = 199210, x = 1, ground = true, height = 2.15 },
                    { model = 198340, yaw = 90, z = 0.7, scale = 0.65 },
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

    -- A snake (NPC 2914, display 1206), and the Lazy Peon (10556, display 10038) with its lines
    -- (sound/creature/peon/peonyes1 to 4, peonready1).
    ambient = {
        every = { 70, 180 },
        creatures = {
            {
                creature = 1206,
                move = "cross",
                speed = { 6, 8 },
                -- Small and low: its slither covers little ground.
                pace = 3,
                from = 6.5,
                weight = 1.5,
                group = { count = { 1, 2 }, gap = { 2, 4 }, offset = { 1.5, 3 }, opposite = 0.3 },
            },
            {
                creature = 10038,
                move = "cross",
                speed = { 7, 9 },
                group = { count = { 1, 2 }, gap = { 1.5, 3 }, offset = { 0, 2 } },
                voice = { 558136, 558139, 558147, 558140, 558137 },
                talks = 0.8,
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
                        -- Built half buried in the terrain: on the ground instead.
                        lift = true,
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
