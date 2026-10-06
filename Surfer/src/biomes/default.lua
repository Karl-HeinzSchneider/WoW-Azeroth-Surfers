---@type string, Surfer
local _, app = ...
-- The default biome: the look every other biome starts from. Each field below is documented,
-- so this file is also the reference for writing a biome. Distances are in yards; colors are
-- { red, green, blue } from 0 to 1. Textures and models are game file ids (from the community
-- listfile); only the original, classic-era files.
app.biomes.Register("default", {
    name = "Plain",

    -- The ground: surfaces (what a stretch of ground is made of) laid out in bands.
    ground = {
        -- Each surface's `texture` (a file id; none here) repeats every `tile` yards, as on the
        -- game's own terrain (4.1667 yards: 8 times per terrain chunk). `color` stands in
        -- without a texture, or when it does not load.
        tile = 4.1667,
        surfaces = {
            road = { color = { 0.55, 0.53, 0.45 } },
            dirt = { color = { 0.45, 0.33, 0.18 } },
            grass = { color = { 0.4, 0.5, 0.1 } },
        },
        -- Bands from the road's middle outward, mirrored to both sides; a band `from` 0 is one
        -- band across the middle. The lanes are 2.4 yards wide: the middle one ends at 1.2, the
        -- outer ones at 3.6.
        --   surface   which surface it shows
        --   layer     draw order from -8 to 7: higher draws over lower
        --   segments  1, 2 or 4: how deep its pieces are near the runner, in yards. Shorter
        --             keeps a texture's perspective, longer costs less. The road needs 1: a seam
        --             next to it would show.
        --   from, to  yards off the middle
        --   opacity   { at from, at to }. Gradients are linear across a band, so a soft edge is
        --             a band of its own.
        -- Here: a road fading into a dirt shoulder, the dirt into grass, the grass into the
        -- world, and worn dirt ruts marking the lanes.
        bands = {
            { surface = "grass", layer = -2, segments = 2, from = 3.3, to = 5.5, opacity = { 1, 1 } },
            { surface = "grass", layer = -2, segments = 2, from = 5.5, to = 8.5, opacity = { 1, 0 } },
            { surface = "dirt", layer = -1, segments = 2, from = 3.3, to = 5.3, opacity = { 1, 0 } },
            { surface = "road", layer = 0, segments = 1, from = 0, to = 3.3, opacity = { 1, 1 } },
            { surface = "road", layer = 0, segments = 1, from = 3.3, to = 4.3, opacity = { 1, 0 } },
            { surface = "dirt", layer = 1, segments = 4, from = 0.95, to = 1.45, opacity = { 0.3, 0.3 } },
        },
        -- The far ground fades out between these distances ahead instead of ending at a hard
        -- edge.
        fade = { from = 60, to = 88 },
    },

    -- 3D models along both sides of the road, as actors of one scene. Along each side a group
    -- follows the last one after `spacing` yards; groups are picked at random by `weight`, and
    -- each takes `length` yards of the roadside (a group without items leaves that stretch
    -- empty). A group's `items` are placed together:
    --   model  a file id, or a list to pick one from at random
    --   x      yards from the road's middle to the model's origin, the point it stands on in the
    --          world (the road's edge is at 4.3, the grass ends at 8.5). Moved farther out if
    --          the model would reach closer to the middle than `clear`.
    --   overhang  true: may reach over the road (a lamp's arm), `clear` does not apply
    --   d      yards along the road from the group's start, 0 if left out
    --   yaw    degrees the model turns (0 if left out)
    -- Groups are written for the right side of the road (models face the road at yaw 0 when
    -- built facing the model's +y). The left side's are the same group turned round about its
    -- middle: every model turned round to face the road too, and `d` counted back from the
    -- group's `length`, so parts that join up (a fence and the post closing it) still do.
    --   scale  its size, 1 if left out
    --   chance from 0 to 1: how often it is placed with its group, always if left out. Optional
    --          parts make variants: a fence that sometimes has a lamp, sometimes a bush, or both.
    -- Any number may instead be a { min, max } range, picked at random for each one placed.
    -- `ambient` and `diffuse` light them by day. None by default.
    decorations = {
        clear = 4.4,
        spacing = { 1, 6 },
        groups = {},
        ambient = { 0.75, 0.75, 0.75 },
        diffuse = { 0.6, 0.6, 0.6 },
    },

    -- The light at midnight; day is white. light.lua blends between them by the game's clock.
    light = {
        night = { 0.45, 0.5, 0.7 },
    },

    -- Coins are 3D models in the same scene as the decorations, lit like them: `models` are tried
    -- in order until one loads (11xp_coin01, 8du_zuldazar_coin01, goldpilesmall01); flat coins
    -- stand in until then.
    coin = {
        models = { 5737987, 2313815, 200137 },
    },

    -- The flat boxes' colors by kind and face: obstacles to jump over, barriers to run under
    -- (their posts drawn apart), platforms to run on, and distant flat coins.
    shapes = {
        obstacle = { front = { 0.9, 0.29, 0.17 }, top = { 1, 0.48, 0.25 }, side = { 0.68, 0.2, 0.12 } },
        barrier = { front = { 0.95, 0.72, 0.18 }, top = { 1, 0.85, 0.4 }, side = { 0.7, 0.5, 0.1 } },
        post = { front = { 0.55, 0.58, 0.6 } },
        platform = { front = { 0.2, 0.42, 0.72 }, top = { 0.32, 0.58, 0.88 }, side = { 0.14, 0.32, 0.58 } },
        coin = { front = { 1, 0.77, 0.2 } },
    },
})
