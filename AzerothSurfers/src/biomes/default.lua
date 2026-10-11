---@type string, AzerothSurfers
local appName, app = ...
-- The look every other biome starts from, and the reference for writing one. Distances are in
-- yards; colors { r, g, b } from 0 to 1; textures and models are classic-era game file ids.

-- Our own sounds (AzerothSurfers/assets/sounds/).
local SOUNDS = "Interface\\AddOns\\" .. appName .. "\\assets\\sounds\\"
app.biomes.Register("default", {
    name = "Plain",

    -- Runner contact sounds: classic sound/character/footsteps/mFootSmallDirtA-E
    -- and mFootSmallWoodA-E. Cycled without touching the track's random streams.
    -- Takeoff, landing and the start of a roll use the same surface contact sound.
    -- Platforms and ramps are wooden in every current biome.
    footsteps = {
        ground = { 540227, 540136, 540099, 540201, 540128 },
        wood = { 540189, 540144, 540105, 540100, 540111 },
        stride = 2.5, -- yards between running contacts
    },

    -- The ground: surfaces (what a stretch of ground is made of) laid out in bands.
    ground = {
        -- A surface's `texture` repeats every `tile` yards (the game terrain's: 8 per chunk);
        -- `color` stands in without one, or until it loads.
        tile = 4.1667,
        surfaces = {
            road = { color = { 0.55, 0.53, 0.45 } },
            dirt = { color = { 0.45, 0.33, 0.18 } },
            grass = { color = { 0.4, 0.5, 0.1 } },
        },
        -- Bands from the road's middle outward, mirrored to both sides (the middle lane ends at
        -- 1.2 yards, the outer ones at 3.6):
        --   surface   which surface it shows
        --   layer     draw order from -8 to 7: higher draws over lower
        --   segments  1, 2 or 4: yards deep its pieces are near the runner. Shorter keeps a
        --             texture's perspective, longer costs less; the road needs 1.
        --   from, to  yards off the middle
        --   opacity   { at from, at to }, linear: a soft edge is a band of its own
        bands = {
            { surface = "grass", layer = -2, segments = 2, from = 3.3, to = 7.9, opacity = { 1, 1 } },
            { surface = "grass", layer = -2, segments = 2, from = 7.9, to = 10.9, opacity = { 1, 0 } },
            { surface = "dirt", layer = -1, segments = 2, from = 3.3, to = 5.3, opacity = { 1, 0 } },
            { surface = "road", layer = 0, segments = 1, from = 0, to = 3.3, opacity = { 1, 1 } },
            { surface = "road", layer = 0, segments = 1, from = 3.3, to = 4.3, opacity = { 1, 0 } },
            { surface = "dirt", layer = 1, segments = 4, from = 0.95, to = 1.45, opacity = { 0.3, 0.3 } },
        },
        -- Where everything far ahead fades out; `to` must stay short of simulation.VIEW.
        fade = { from = 95, to = 135 },
        -- The ground drops `curve` times the distance ahead squared (0.0005: 1.25 yards at 50,
        -- 9.1 at 135); 0 is flat. Everything on the road follows it.
        curve = 0.0005,
    },

    -- 3D models along both sides of the road. Along each side a group, picked by `weight`,
    -- follows the last one after `spacing` yards and takes `length` yards (no items: an empty
    -- stretch). A group's `items`:
    --   model     a file id, or a list to pick one from
    --   x         yards from the road's middle to the model's origin (the road's edge is at 4.3,
    --             the grass solid to 7.9); pushed out if the model reaches in past `clear`
    --   overhang  true: may reach over the road (a lamp's arm), `clear` does not apply
    --   lift      true: stands on its lowest point instead of its origin (a rock built to sink
    --             into the terrain would show its buried part)
    --   d, z      yards along the road from the group's start, and up; 0 if left out
    --   yaw       degrees, 0 if left out
    --   roll      degrees to tip sideways; nonzero centers the model and rests it on the ground
    --   scale     1 if left out
    --   chance    0 to 1: how often it is placed with its group (always if left out)
    -- Groups are written for the right side (yaw 0 faces the road for a model built facing +y);
    -- the left side's are turned round about their middle, `d` counted back from `length`.
    -- A group with `mirror = false` keeps its yaw and along-road offsets on both sides
    -- (for asymmetric fence assemblies); only its lateral position changes sides.
    -- Any number may instead be a { min, max } range, rolled for each one placed. `ambient` and
    -- `diffuse` light them by day.
    decorations = {
        clear = 4.4,
        spacing = { 1, 6 },
        groups = {},
        ambient = { 0.75, 0.75, 0.75 },
        diffuse = { 0.6, 0.6, 0.6 },
    },

    -- The track's boxes as 3D models, by kind: obstacle (1, 2 or 4 layers of 0.6 yards, 1.3
    -- wide), enemy (2 or 4 layers, 1.2 wide), barrier (a bar 2.2 wide, on layer 3: 1.8 to 2.4
    -- yards up, run under it; or a low one on layer 2: 1.2 to 1.8, duck under it) and platform
    -- (1 to 5 layers, 2.1 wide, 12 to 60 long, maybe a ramp). A box may stand on a platform.
    -- Each kind is a list of variants; a box picks one by `weight` among those whose `layers` is
    -- its own (any if left out), and whose `layer` (bottom) is its own: without one for its
    -- layer, among those without `layer`. A variant's `items`:
    --   model   a file id, or a list to pick one from at random
    --   x       yards to the screen's right of the lane's middle, 0 if left out
    --   d       yards along the box from its start, its middle if left out
    --   every   instead of `d`: repeated along the box (past its ramp) about every that many
    --           yards
    --   z       yards up from the box's bottom, 0 if left out
    --   ground  true: `z` counts from the road instead (a barrier's posts)
    --   height  yards the model's top above its origin is scaled to, the box's height if left
    --           out (one of two stacked models: half of it)
    --   scale   its size instead of `height`
    --   yaw     degrees it turns, 0 if left out (180 faces the runner)
    --   creature  instead of `model`: a creature display id (or a list), the creature with its
    --           skin, playing animation `animation` (0, standing, if left out) and `attack` once
    --           the runner is close
    --   sound   played once the runner is close: a file id, a list, or a table of them by
    --           display id; silent if left out
    -- Any number may instead be a { min, max } range. A platform variant's `ramp` items cover
    -- its ramp (4 yards per layer): each model is scaled to the slope's length, laid on it, and
    -- repeated `across` times over the platform's width (or `width` yards); with `segment`
    -- (yards), as many models end to end as make each about that long. A kind without variants
    -- stays a flat box in `shapes`' colors, as does a ramp without `ramp` items.
    obstacles = {},

    -- Wildlife, only for the eye: never in the runner's way or the simulation. One comes every
    -- `every` yards, picked by `weight` among `creatures`, from either side:
    --   creature   a display id, or a list
    --   move       "cross": across the road at the nearest spot ahead clear of every box and
    --              coin, off it before the runner comes (none in sight: skipped); "fly": `z`
    --              yards above the road, `ahead` yards ahead, anywhere
    --   speed      yards per second, 10 if left out; a slow crosser at a fast run may find no spot
    --   from       yards off the middle it starts from and runs to, 9 if left out
    --   animation  5 (run) if left out
    --   pace       yards per second the animation is made for at its own size (7 if left out);
    --              it plays at `speed` / `pace`. Feet sliding forward: lower it; running on the
    --              spot: raise it. `rate` multiplies on top.
    --   height     yards its top is scaled to; or `scale` (1 if left out)
    --   z, ahead   a flyer's height (10) and starting distance ahead (90)
    --   group      several at once, for both ground and flying creatures (ground lines must be clear):
    --     count      a whole number or a { min, max } range
    --     gap        yards of its way each starts after the one before (2)
    --                use 0 with a nonzero offset for side-by-side flights
    --     offset     yards along the road off the first one's line, either side (0)
    --     opposite   0 to 1: how often one crosses the other way (0)
    --   voice      a sound file id or a list, said once as the runner passes ("Creature sounds")
    --   talks      0 to 1: how often one says its `voice` (1)
    -- Any number may instead be a { min, max } range.
    ambient = {
        every = { 80, 200 },
        creatures = {},
    },

    -- The transition of the gates into this biome's zones (biomes.RegisterTransition).
    entrance = "dream",

    -- The side window's backdrop: sky from `top` to `horizon`, land below it hazing toward
    -- `horizon` by `haze`. Lit like the ground; `land` should match the outer ground's texture.
    sky = {
        top = { 0.42, 0.56, 0.74 },
        horizon = { 0.74, 0.78, 0.8 },
        land = { 0.3, 0.3, 0.24 },
        haze = 0.4,
    },

    -- The light at midnight; day is white.
    light = {
        night = { 0.45, 0.5, 0.7 },
    },

    -- The coins. `models`: entries tried in order until one loads; flat coins until then.
    --   model   a file id. One the client lacks shows as its error cube, which counts as loaded.
    --   size    yards its largest side is scaled to (0.5 if left out); larger than a layer, it
    --           rests on the layer's floor.
    --   sound   played on collecting one: a game sound file id or one of ours (SOUNDS), or a
    --           list of them, one per step of a streak (scoring.lua's `streak`), the last from there on.
    --           Left out: lootcoinsmall (567428), as for the flat coins. A new file of ours is
    --           only found after restarting the game, not on /reload.
    --   finale  with a list: played once instead, on the coin that goes past its last step.
    coin = {
        models = {
            {
                model = 201054, -- g_jewelblue
                size = 2.6,
                sound = {
                    SOUNDS .. "pickup_gem_streak_01.ogg",
                    SOUNDS .. "pickup_gem_streak_02.ogg",
                    SOUNDS .. "pickup_gem_streak_03.ogg",
                    SOUNDS .. "pickup_gem_streak_04.ogg",
                    SOUNDS .. "pickup_gem_streak_05.ogg",
                    SOUNDS .. "pickup_gem_streak_06.ogg",
                    SOUNDS .. "pickup_gem_streak_07.ogg",
                    SOUNDS .. "pickup_gem_streak_08.ogg",
                },
            },
        },
    },

    -- The flat boxes' colors by kind and face (a barrier's posts apart).
    shapes = {
        obstacle = { front = { 0.9, 0.29, 0.17 }, top = { 1, 0.48, 0.25 }, side = { 0.68, 0.2, 0.12 } },
        barrier = { front = { 0.95, 0.72, 0.18 }, top = { 1, 0.85, 0.4 }, side = { 0.7, 0.5, 0.1 } },
        post = { front = { 0.55, 0.58, 0.6 } },
        platform = { front = { 0.2, 0.42, 0.72 }, top = { 0.32, 0.58, 0.88 }, side = { 0.14, 0.32, 0.58 } },
        enemy = { front = { 0.62, 0.15, 0.4 }, top = { 0.8, 0.25, 0.55 }, side = { 0.45, 0.1, 0.3 } },
        coin = { front = { 1, 0.77, 0.2 } },
    },
})
