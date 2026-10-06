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

    -- The roadside: wooden fences, some with a road lamp hanging over the road or a bush growing
    -- in them, bushes, thorn bushes by the road and pines farther back. Models from
    -- world/azeroth/elwynn/passivedoodads/.
    decorations = {
        spacing = { 1, 6 },
        groups = {
            -- A fence of three sections: elwynnwoodfence01 is a post at its origin and two rails
            -- reaching 4.16 yards ahead (on this side of the road), ending at the next section's
            -- post; elwynnwoodpost01, a post alone, closes the last one. Sometimes
            -- lamppost/lamppost stands behind the closing post, the arm reaching over the road's
            -- edge, and sometimes a small bush (bush/elwynnbush06 or 08) grows in the fence.
            {
                weight = 3,
                length = 12.6,
                items = {
                    { model = 189795, x = 5.2, d = 0 },
                    { model = 189795, x = 5.2, d = 4.2 },
                    { model = 189795, x = 5.2, d = 8.4 },
                    { model = 189796, x = 5.2, d = 12.56 },
                    { model = 189825, x = 6.8, d = 12.56, overhang = true, chance = 0.35 },
                    {
                        model = { 189697, 189699 },
                        x = 5.3,
                        d = { 1.5, 11 },
                        yaw = { 0, 360 },
                        scale = { 0.45, 0.65 },
                        chance = 0.4,
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
