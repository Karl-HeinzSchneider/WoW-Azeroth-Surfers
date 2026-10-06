---@type string, Surfer
local _, app = ...
-- Elwynn Forest: the old road through the forest. Everything not listed is the default's
-- (default.lua documents every field).
app.biomes.Register("elwynn", {
    name = "Elwynn Forest",

    ground = {
        surfaces = {
            road = { texture = 187099 }, -- tileset/elwynn/elwynncobblestonebase.blp
            dirt = { texture = 187114 }, -- tileset/elwynn/elwynndirtbase2.blp
            grass = { texture = 187126 }, -- tileset/elwynn/elwynngrassbase.blp
        },
    },

    -- The roadside: wooden fences, now and then with a road lamp hanging over the road, bushes,
    -- thorn bushes by the road and pines farther back. Models from
    -- world/azeroth/elwynn/passivedoodads/.
    decorations = {
        spacing = { 1, 6 },
        groups = {
            -- elwynnwoodfence01: a 4.2-yard rail between three posts.
            { weight = 4, length = 4.4, items = { { model = 189795, x = 5.2 } } },
            -- The fence with lamppost/lamppost behind its end post, the arm reaching over the
            -- road's edge.
            {
                weight = 1,
                length = 4.4,
                items = {
                    { model = 189795, x = 5.2 },
                    { model = 189825, x = 6.8, overhang = true },
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
