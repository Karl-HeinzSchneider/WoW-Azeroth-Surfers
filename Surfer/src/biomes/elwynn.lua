---@type string, Surfer
local _, app = ...
-- Elwynn Forest: the old road through the forest. Everything not listed is the default's
-- (default.lua documents every field). Models from world/azeroth/elwynn/passivedoodads/.

-- A fence is always three sections: elwynnwoodfence01 is a post at its origin and two rails
-- reaching 4.16 yards back toward the runner (on this side of the road), ending at the previous
-- section's post; elwynnwoodpost01, a post alone, closes the first section's open end. Half a
-- section of open grass before and after it keeps the next fence one section away.
local SECTION = 4.16
local START = SECTION / 2
local FENCE_LENGTH = START + 3 * SECTION + START
local fence = {
    { model = 189796, x = 5.2, d = START },
    { model = 189795, x = 5.2, d = START + SECTION },
    { model = 189795, x = 5.2, d = START + 2 * SECTION },
    { model = 189795, x = 5.2, d = START + 3 * SECTION },
}
-- lamppost/lamppost behind the single post, its arm reaching over the road's edge.
local lantern = { model = 189825, x = 6.8, d = START, overhang = true }
-- A small bush (bush/elwynnbush06 or 08) growing in the fence.
local bush = {
    model = { 189697, 189699 },
    x = 5.3,
    d = { START + 1.5, START + 11 },
    yaw = { 0, 360 },
    scale = { 0.45, 0.65 },
}

-- A ramp's planks: world/azeroth/redridge/passivedoodads/dockpieces/redridgedocksplank01 (21.6
-- yards long) scaled down to pieces of about 3 yards of slope (narrow and thin: a model scales
-- the same every way), three side by side over a ramp narrower than its platform, as many
-- pieces end to end as the slope is long; a long ramp has more planks, not bigger ones.
local RAMP = { { model = 190091, across = 3, segment = 3, width = 1.5 } }

-- A fence group with `...` added to it, picked by `weight`.
local function fenceWith(weight, ...)
    local items = {}
    for _, item in ipairs(fence) do
        items[#items + 1] = item
    end
    for _, extra in ipairs({ ... }) do
        items[#items + 1] = extra
    end
    return { weight = weight, length = FENCE_LENGTH, items = items }
end

app.biomes.Register("elwynn", {
    name = "Elwynn Forest",
    -- A starter zone.
    tier = 1,

    ground = {
        surfaces = {
            road = { texture = 187099 }, -- tileset/elwynn/elwynncobblestonebase.blp
            dirt = { texture = 187114 }, -- tileset/elwynn/elwynndirtbase2.blp
            grass = { texture = 187126 }, -- tileset/elwynn/elwynngrassbase.blp
        },
    },

    -- A clear summer sky over the forest's dark grass.
    sky = {
        top = { 0.36, 0.55, 0.8 },
        horizon = { 0.72, 0.8, 0.85 },
        land = { 0.26, 0.32, 0.13 },
        haze = 0.45,
    },

    -- The track: crates, kegs and hay to jump, a beam of lumber on two fence posts to run under,
    -- long piles of lumber to run on. Models from world/generic/human/passive doodads/
    -- (crates, beerkegs, lumberpiles) and world/azeroth/elwynn/passivedoodads/.
    obstacles = {
        obstacle = {
            -- crates/replacecrate01 or 03 (0.63 yards tall), haystacks/haystack01 (0.7).
            -- Drawn taller than their 0.6-yard box, which looks tiny beside a character: any jump
            -- clears them by far.
            {
                layers = 1,
                weight = 2,
                items = { { model = { 198165, 198167 }, height = 0.85, yaw = { -12, 12 } } },
            },
            -- The haystack a little bigger still (10 to 20 percent over the crates): it reads
            -- better. Its box stays one layer.
            { layers = 1, items = { { model = 189810, height = { 0.94, 1.02 }, yaw = { -12, 12 } } } },
            -- crates/stormwindcrate01 (1.24), or two small crates.
            { layers = 2, weight = 2, items = { { model = 198168, yaw = { -8, 8 } } } },
            {
                layers = 2,
                items = {
                    { model = 198165, height = 0.6, yaw = { -6, 6 } },
                    { model = { 198165, 198167 }, z = 0.6, height = 0.6, yaw = { -25, 25 } },
                },
            },
            -- The tall wall, too high to jump: two big crates stacked.
            {
                layers = 4,
                items = {
                    { model = 198168, height = 1.2, yaw = { -5, 5 } },
                    { model = 198168, z = 1.2, height = 1.2, yaw = { -15, 15 } },
                },
            },
            -- Or one big beerkegs/beerkeg01, scaled to the wall's height.
            { layers = 4, items = { { model = 198004, yaw = { 0, 360 } } } },
            -- Or Goldshire's training grounds: a target dummy (woodendummies/
            -- stormwindwoodendummy01 or generalwoodendummy02), or an archery target
            -- (archerytargets/stormwindarcherytarget01), turned toward the runner.
            { layers = 4, items = { { model = { 198666, 198665 }, height = 2.2, yaw = { 165, 195 } } } },
            { layers = 4, items = { { model = 197849, height = 2.1, yaw = { 170, 190 } } } },
        },
        -- Elwynn's creatures facing the runner, display ids of the NPCs. Those that have it wait
        -- in their ready stance (animation 25), and all attack (16) when the runner comes close
        -- (/surfer animations in Surfer_Dev lists what each has), with their classic attack
        -- sound.
        enemy = {
            -- Low enough to jump: a Timber Wolf (604) or a Stonetusk Boar (503, no ready stance).
            { layers = 2, items = { { creature = 604, yaw = 180, animation = 25, attack = 16, sound = 391 } } },
            { layers = 2, items = { { creature = 503, yaw = 180, attack = 16, sound = 380 } } },
            -- Too tall: the Defias Thug (5035), Bandit (2357), Footpad (2333) and Cutpurse
            -- (2361), and Morgaine the Sly (3320); the men and the women sound different.
            {
                layers = 4,
                weight = 2,
                items = {
                    {
                        creature = { 5035, 2357, 2333, 2361, 3320 },
                        height = 2,
                        yaw = 180,
                        animation = 25,
                        attack = 16,
                        sound = { [5035] = 2941, [2357] = 2941, [2361] = 2941, [2333] = 2937, [3320] = 2937 },
                    },
                },
            },
            -- Riverpaw gnolls: the Outrunner (512), Taskmaster (376) and Runt (10791).
            {
                layers = 4,
                items = {
                    {
                        creature = { 512, 376, 10791 },
                        height = 2.1,
                        yaw = 180,
                        animation = 25,
                        attack = 16,
                        sound = 306,
                    },
                },
            },
            -- Hogger (384), bigger and rarer.
            {
                layers = 4,
                weight = 0.4,
                items = { { creature = 384, height = 2.6, yaw = 180, animation = 25, attack = 16, sound = 306 } },
            },
            -- A cow (1060), just standing there, mooing as the runner passes (its classic
            -- wound sound, the only moo it has).
            {
                layers = 4,
                weight = 0.6,
                items = { { creature = 1060, height = 1.9, yaw = { 150, 210 }, sound = 1467 } },
            },
        },
        -- lumberpiles/deadminelumberpilesmall across two elwynnwoodpost01 posts (1.9 tall).
        barrier = {
            {
                items = {
                    { model = 189796, x = -1, ground = true, scale = 1 },
                    { model = 189796, x = 1, ground = true, scale = 1 },
                    { model = 198340, yaw = 90, z = 0.1, scale = 0.65 },
                },
            },
        },
        -- Rows of lumber piles: deadminelumberpilesmall (0.56 tall) for one layer,
        -- deadminelumberpilelarge (1.67 tall) scaled for two and three, stacked for four and
        -- five. Every ramp is laid with the same short planks, end to end up the slope (RAMP).
        platform = {
            {
                layers = 1,
                items = { { model = 198340, every = 3.4 } },
                ramp = RAMP,
            },
            {
                layers = 2,
                items = { { model = 198339, every = 2.3 } },
                ramp = RAMP,
            },
            {
                layers = 3,
                items = { { model = 198339, every = 3.4 } },
                ramp = RAMP,
            },
            -- Higher ground (towers, corridor walls, the top of stairs and rooftops): two
            -- large piles stacked, each half the height.
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

    -- Elwynn's wildlife: now and then deer (347) bounding across the road, one to three, one
    -- after another or side by side, now and then one the other way; more often rabbits
    -- (139885) darting over from closer by, one or two, often crossing each other. Both at their
    -- own size; /surfer preview in Surfer_Dev shows a creature on the road with its size.
    ambient = {
        every = { 70, 180 },
        creatures = {
            {
                creature = 347,
                move = "cross",
                speed = { 11, 14 },
                -- Long bounds: its run covers more ground than a character's.
                pace = 9,
                group = { count = { 1, 3 }, gap = { 2, 4 }, offset = { 0, 3 }, opposite = 0.2 },
            },
            {
                creature = 139885,
                move = "cross",
                speed = { 8, 10 },
                -- Short hops: its run covers little ground, so it plays fast.
                pace = 3.5,
                from = 7,
                weight = 1.5,
                group = { count = { 1, 2 }, gap = { 1, 3 }, offset = { 1.5, 3 }, opposite = 0.5 },
            },
        },
    },

    -- The roadside: fences in four variants with open stretches between them, bushes, thorn
    -- bushes by the road and pines farther back.
    decorations = {
        spacing = { 1, 6 },
        groups = {
            fenceWith(1.5),
            fenceWith(0.75, bush),
            fenceWith(0.5, lantern),
            fenceWith(0.25, bush, lantern),
            -- Nothing for a while.
            { weight = 2, length = { 4, 12 }, items = {} },
            -- One or two small bushes (bush/elwynnbush08, detail/elwynnthornbush01) by the road.
            {
                weight = 2,
                length = { 3, 6 },
                items = {
                    { model = { 189699, 189777 }, x = { 5, 6.5 }, yaw = { 0, 360 }, scale = { 0.4, 0.6 } },
                    {
                        model = { 189699, 189777 },
                        x = { 5, 7 },
                        d = { 1.5, 3 },
                        yaw = { 0, 360 },
                        scale = { 0.4, 0.6 },
                        chance = 0.5,
                    },
                },
            },
            -- bush/elwynnbush06 to 09, turned and sized at random.
            {
                weight = 3,
                length = 3,
                items = {
                    {
                        model = { 189697, 189698, 189699, 189700 },
                        x = { 6.5, 9 },
                        yaw = { 0, 360 },
                        scale = { 0.5, 0.8 },
                    },
                },
            },
            -- detail/elwynnthornbush01 and 02, close to the road.
            {
                weight = 2,
                length = 2,
                items = { { model = { 189777, 189778 }, x = { 4.8, 6 }, yaw = { 0, 360 }, scale = { 0.8, 1.1 } } },
            },
            -- trees/elwynntree01/elwynnpine01 and 02, trees/elwynntreemid01, farther back.
            {
                weight = 2,
                length = 4,
                items = {
                    { model = { 189924, 189925, 189932 }, x = { 9, 14 }, yaw = { 0, 360 }, scale = { 0.8, 1.1 } },
                },
            },
        },
    },
})
