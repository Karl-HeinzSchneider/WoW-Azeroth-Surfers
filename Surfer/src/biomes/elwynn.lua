---@type string, Surfer
local _, app = ...
-- Elwynn Forest: the old road through the forest. Everything not listed is the default's
-- (default.lua documents every field). Models from world/azeroth/elwynn/passivedoodads/.

-- A fence is always three sections: elwynnwoodfence01 is a post at its origin and two rails
-- reaching 4.16 yards ahead (on this side of the road), ending at the next section's post;
-- elwynnwoodpost01, a post alone, closes the last one.
local FENCE_LENGTH = 12.6
local fence = {
    { model = 189795, x = 5.2, d = 0 },
    { model = 189795, x = 5.2, d = 4.2 },
    { model = 189795, x = 5.2, d = 8.4 },
    { model = 189796, x = 5.2, d = 12.56 },
}
-- lamppost/lamppost behind the closing post, its arm reaching over the road's edge.
local lantern = { model = 189825, x = 6.8, d = 12.56, overhang = true }
-- A small bush (bush/elwynnbush06 or 08) growing in the fence.
local bush = { model = { 189697, 189699 }, x = 5.3, d = { 1.5, 11 }, yaw = { 0, 360 }, scale = { 0.45, 0.65 } }

-- A fence group with `...` added to it, picked by `weight`.
local function fenceWith(weight, ...)
    local items = { unpack(fence) }
    for _, extra in ipairs({ ... }) do
        items[#items + 1] = extra
    end
    return { weight = weight, length = FENCE_LENGTH, items = items }
end

app.biomes.Register("elwynn", {
    name = "Elwynn Forest",

    ground = {
        surfaces = {
            road = { texture = 187099 }, -- tileset/elwynn/elwynncobblestonebase.blp
            dirt = { texture = 187114 }, -- tileset/elwynn/elwynndirtbase2.blp
            grass = { texture = 187126 }, -- tileset/elwynn/elwynngrassbase.blp
        },
    },

    -- The roadside: fences in four variants, bushes, thorn bushes by the road and pines farther
    -- back.
    decorations = {
        spacing = { 1, 6 },
        groups = {
            fenceWith(3),
            fenceWith(1.5, bush),
            fenceWith(1, lantern),
            fenceWith(0.5, bush, lantern),
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
