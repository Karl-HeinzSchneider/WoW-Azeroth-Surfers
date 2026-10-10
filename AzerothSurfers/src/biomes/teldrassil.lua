---@type string, AzerothSurfers
local _, app = ...
-- Teldrassil: a violet woodland road between kaldorei lamps and ancient trees.
-- Classic assets verified in the listfile: tileset/Kalidar, world/Kalimdor/Kalidar/
-- PassiveDoodads and world/Generic/NightElf/Passive Doodads. Keep Elwynn's proven
-- lumber platforms and ramps (inherited through Derive); everything else is replaced.

-- The enemies' attack sounds: sound/creature/furbolg/mFurbolgAttack1 to 3.
local FURBOLG = { 549397, 549401, 549404 }
-- sound/creature/tiger/mTigerAttackA to D, shared by the classic saber cats.
local NIGHTSABER = { 562394, 562385, 562393, 562386 }
-- sound/creature/grell/GrellAttackA to C.
local GRELL = { 551169, 551174, 551167 }

app.biomes.Derive("teldrassil", "elwynn", {
    name = "Teldrassil",
    tier = 1,

    ground = {
        -- Gentle slope: half a yard down at 50 yards ahead (the default: 1.25).
        curve = 0.0002,
        surfaces = {
            road = { texture = 188597, color = { 0.38, 0.32, 0.43 } }, -- KalidarRoad
            dirt = { texture = 188595, color = { 0.28, 0.24, 0.35 } }, -- KalidarLeaf
            grass = { texture = 188589, color = { 0.24, 0.3, 0.36 } }, -- KalidarFerns
        },
    },
    sky = {
        top = { 0.22, 0.19, 0.4 },
        horizon = { 0.57, 0.43, 0.66 },
        land = { 0.24, 0.28, 0.35 },
        haze = 0.55,
    },
    light = { night = { 0.52, 0.56, 0.8 } },

    obstacles = {
        -- world/Generic/NightElf/Passive Doodads/Gates/KalidarMoonGate.m2.
        -- The entire arch stands on the road, rather than at the overhead box's bottom.
        -- Initial fit; check the opening against the barrier in-game.
        barrier = {
            { items = { { model = 198761, ground = true, height = 4, yaw = 180 } } },
            -- The low one to duck under: the same arch, a wooden beam (deadminelumberpilesmall,
            -- as Elwynn's bar) across its opening 1.3 yards up. Initial fit; check in-game.
            {
                layer = 2,
                items = {
                    { model = 198761, ground = true, height = 4, yaw = 180 },
                    { model = 198340, yaw = 90, z = 0.1, scale = 0.65 },
                },
            },
        },
        obstacle = {
            -- ElfCrate01 and ElfBarrel01: the same readable heights as other starter zones.
            { layers = 1, items = { { model = 198748, height = 0.85, yaw = { -12, 12 } } } },
            { layers = 1, items = { { model = 198733, height = 0.85, yaw = { 0, 360 } } } },
            { layers = 2, items = { { model = 198748, height = 1.24, yaw = { -8, 8 } } } },
            { layers = 2, items = { { model = 198733, height = 1.24, yaw = { 0, 360 } } } },
            {
                layers = 4,
                items = {
                    { model = 198748, height = 1.2, yaw = { -5, 5 } },
                    { model = 198748, z = 1.2, height = 1.2, yaw = { -15, 15 } },
                },
            },
            -- FurbolgTotem01/02 mark the forest's less welcoming stretches.
            { layers = 4, items = { { model = { 202018, 202019 }, height = 2.4, yaw = { 170, 190 } } } },
        },
        enemy = {
            -- Young Nightsaber (classic NPC 2031, display 11454).
            { layers = 2, items = { { creature = 11454, yaw = 180, attack = 16, sound = NIGHTSABER } } },
            -- Grell (classic NPC 1988, display 6806), small enough to jump over.
            { layers = 2, items = { { creature = 6806, yaw = 180, attack = 16, sound = GRELL } } },
            -- Gnarlpine Ursa (classic NPC 2006, display 6798). The display supplies its skin;
            -- loading the raw Furbolg.M2 file leaves its replaceable textures white.
            {
                layers = 4,
                items = { { creature = 6798, height = 2.2, yaw = 180, animation = 25, attack = 16, sound = FURBOLG } },
            },
        },
    },

    ambient = {
        every = { 70, 160 },
        creatures = {
            -- Deer (NPC 883, display 347) bounding across, as in Elwynn.
            {
                creature = 347,
                move = "cross",
                speed = { 11, 14 },
                pace = 9,
                group = { count = { 1, 3 }, gap = { 2, 4 }, offset = { 0, 3 }, opposite = 0.2 },
            },
        },
    },

    decorations = {
        spacing = { 2, 5 },
        ambient = { 0.65, 0.66, 0.82 },
        diffuse = { 0.5, 0.55, 0.7 },
        groups = {
            -- Nothing for a while.
            { weight = 1, length = { 4, 8 }, items = {} },
            -- KalidarBush01 to 04: purple undergrowth beside the fern-covered verge.
            {
                weight = 3,
                length = { 3, 6 },
                items = {
                    {
                        model = { 202021, 202022, 202023, 202024 },
                        x = { 5.5, 8 },
                        yaw = { 0, 360 },
                        scale = { 0.4, 0.65 },
                    },
                    { model = 202024, x = { 7, 9 }, d = 3, yaw = { 0, 360 }, scale = 0.45, chance = 0.5 },
                },
            },
            -- Open stretches with occasional undergrowth near the road.
            {
                weight = 3,
                length = { 6, 10 },
                items = {
                    { model = 202021, x = { 6, 8 }, d = 2, scale = 0.5, chance = 0.6 },
                },
            },
            -- Kalidar tree stumps and roots, safely off the running surface.
            {
                weight = 1.5,
                length = { 4, 7 },
                items = {
                    { model = { 202059, 202060 }, x = { 7, 10 }, yaw = { 0, 360 }, scale = { 0.35, 0.55 } },
                    { model = 202038, x = { 9, 12 }, d = 3, yaw = { 0, 360 }, scale = 0.35, chance = 0.4 },
                },
            },
            -- KalidarStreetLamp01/02 with a KalidarBush03 beside it.
            {
                weight = 2,
                length = 7,
                items = {
                    { model = { 198776, 198777 }, x = 6.5, scale = 0.7 },
                    { model = 202023, x = 7.5, d = 3, scale = 0.4 },
                },
            },
            -- NightElfOwlBanner01/02.
            {
                weight = 1,
                length = 6,
                items = { { model = { 198725, 198726 }, x = { 7, 9 }, yaw = { -15, 15 }, scale = 0.65 } },
            },
            -- An elven fountain and candle at a small roadside shrine.
            {
                weight = 0.5,
                length = 10,
                items = {
                    { model = 198754, x = 10, scale = 0.5 },
                    { model = 198743, x = 7, d = 2, scale = 0.8 },
                },
            },
        },
    },
})
