---@type string, Surfer
local _, app = ...
-- The Emerald Dream: the dragon groves' tree portal in an overgrown night elf shrine in Feralas'
-- forest, a touch of the Nightmare about it. A stone path leads to the step up to the portal's
-- platform (3.45 yards to either side); ruins on the left, forest on the right.

-- Flat slabs (generic/nightelf/passive doodads/steppingstones/steppingstone01, 02; kalimdor/
-- diremaul/passivedoodads/rubble/diremaulfloorrubble01), low enough to read as the ground.
-- Scattered first, then a row across before the step.
local SLABS = { 198947, 198948, 201699 }
local path = {}
local SPOTS = { { -1.7, -0.8 }, { 0.8, 1.7 }, { -4.3, -3.3 }, { 3.3, 4.3 }, { -0.4, 0.4 } }
for k = 0, 9 do
    path[#path + 1] = {
        model = SLABS,
        x = SPOTS[k % #SPOTS + 1],
        d = { -19.5 + k * 1.2, -18.5 + k * 1.2 },
        height = { 0.12, 0.2 },
        yaw = { 0, 360 },
    }
end
for _, x in ipairs({ -3, -1.5, 0, 1.5, 3 }) do
    path[#path + 1] = { model = SLABS, x = { x - 0.2, x + 0.2 }, d = { -8.2, -7.6 }, height = 0.15, yaw = { 0, 360 } }
end

local shrine = {
    -- generic/activedoodads/worldtreeportals/worldtreeportal01 on the platform.
    { model = 197068, x = 0, z = 0.6, height = 14 },
    -- Two curved roots framing it (kalimdor/felwood/passivedoodads/roots/felwoodroots03).
    { model = 201883, x = -8.5, d = -1, height = 11 },
    { model = 201883, x = 8.8, d = 0.5, height = 10, yaw = 180 },
    -- kalimdor/mauradon/passivedoodads/bridgebraziers/bridgebraziergreen01.
    { model = 202081, x = -4.3, d = -6.8, height = 1.3 },
    { model = 202081, x = 4.3, d = -6.5, height = 1.3 },
    { model = 202081, x = -4.1, d = -1.5, height = 1.1 },
    { model = 202081, x = 4.1, d = -1, height = 1.1 },
    -- The Nightmare: generic/passivedoodads/particleemitters/purplegroundfog, felwoodroots01,
    -- felwoodmushrooms/felwoodmushroom01, 02.
    { model = 199967, x = 0, d = 1, z = 0.6, scale = 0.35 },
    { model = 201881, x = -5.6, d = 2, height = 2.6, yaw = 20 },
    { model = { 201859, 201860 }, x = 4.9, d = -5.2, height = 0.7, yaw = { 0, 360 } },
    { model = { 201859, 201860 }, x = -5.2, d = -3.6, height = 0.6, yaw = { 0, 360 } },
}

-- Ruins, in order: kalimdor/darkshore/passivedoodads/ruins/darkshoreruinpillar01, kalimdor/
-- ashenvale/passivedoodads/ashenvaleroots/ashenvaleroots02, azeroth/duskwood/passivedoodads/
-- detail/duskwoodvine01, darkshoreruinwall02, generic/nightelf/passive doodads/ruins/
-- nightelfruins07, darkshoreruinwall01, kalimdor/feralas/passivedoodads/fern/feralasferns01,
-- darkshorerock01, 02, kalimdor/kalidar/passivedoodads/kalidarbushes/kalidarbush02,
-- dreaming/passivedoodads/flowers/dnrdreampurpleflower02.
local left = {
    { model = 201553, x = -11.5, d = -3, height = 9, yaw = { 0, 360 } },
    { model = 201202, x = -10.6, d = -2.2, height = 2.4, yaw = 60 },
    { model = 189440, x = -10.9, d = -3.9, height = 5.5, yaw = 10 },
    { model = 201559, x = -12.8, d = 2.5, height = 3, yaw = 150 },
    { model = 198839, x = -10.5, d = -10.5, height = 6, yaw = 90 },
    { model = 201558, x = -6.6, d = -13.5, height = 1.1, yaw = 35 },
    { model = 201930, x = -6, d = -8.5, height = 1.3, yaw = { 0, 360 } },
    { model = 201930, x = -8, d = -15.5, height = 1.1, yaw = { 0, 360 } },
    { model = 201551, x = -6.4, d = -18.5, height = 1.4, yaw = { 0, 360 } },
    { model = 201552, x = -8.6, d = -17.5, height = 1.8, yaw = { 0, 360 } },
    { model = 202022, x = -7.6, d = -19.5, height = 3, yaw = { 0, 360 } },
    { model = 190773, x = -5.3, d = -18, height = 1.1, yaw = { 0, 360 } },
}

-- Forest: kalimdor/kalidar/passivedoodads/kalidarroots/kalidargiantroot02, darkshoreruinpillar03,
-- duskwoodvine02, ferns, kalidarbush01, 03, a rock, darkshoreruinpillar04, kalidarroots03,
-- kalidarbush04, a mushroom, dnrdreampurpleflower01, 03.
local right = {
    { model = 202035, x = 14, d = 1, height = 13, yaw = 90 },
    { model = 201555, x = 10.4, d = -4.5, height = 6, yaw = { 0, 360 } },
    { model = 189442, x = 10, d = -5.2, height = 5, yaw = 200 },
    { model = 201930, x = 5.6, d = -11, height = 1.4, yaw = { 0, 360 } },
    { model = 201930, x = 7.2, d = -8.5, height = 1.2, yaw = { 0, 360 } },
    { model = 201930, x = 6.4, d = -14.5, height = 1.5, yaw = { 0, 360 } },
    { model = 202021, x = 8.4, d = -10, height = 2, yaw = { 0, 360 } },
    { model = 202023, x = 9.5, d = -13, height = 2.2, yaw = { 0, 360 } },
    { model = 201551, x = 6, d = -16.5, height = 1.2, yaw = { 0, 360 } },
    { model = 201556, x = 5.6, d = -7.8, height = 1.4, yaw = { 0, 360 } },
    { model = 202040, x = 6.8, d = -12.5, height = 3, yaw = 200 },
    { model = 202024, x = 6.6, d = -19, height = 1.6, yaw = { 0, 360 } },
    { model = 201859, x = 5.2, d = -18.5, height = 0.8, yaw = { 0, 360 } },
    { model = { 190772, 190774 }, x = 5.8, d = -20, height = 1.5, yaw = { 0, 360 } },
}

-- Past the gate: diremaultrimrubble01 to 03, feralas/passivedoodads/stones/feralasstone01, 02.
local after = {
    { model = { 201715, 201716, 201717 }, x = { -6.5, -4.6 }, d = { 6, 10 }, yaw = { 0, 360 } },
    { model = { 201715, 201716, 201717 }, x = { 4.6, 6.5 }, d = { 6, 10 }, yaw = { 0, 360 } },
    { model = { 201933, 201934 }, x = -7.5, d = { 12, 16 }, height = { 3, 5 }, yaw = { 0, 360 } },
    { model = { 201933, 201934 }, x = 7.5, d = { 12, 16 }, height = { 3, 5 }, yaw = { 0, 360 } },
}

local items = {}
for _, list in ipairs({ shrine, left, right, path, after }) do
    for _, item in ipairs(list) do
        items[#items + 1] = item
    end
end

app.biomes.RegisterTransition("dream", {
    name = "Emerald Dream",
    -- No ground of its own. The step and platform of stepping stones and Dire Maul's flat rubble.
    obstacles = {
        platform = {
            {
                layers = 1,
                items = { { model = { 201699, 198947, 198948 }, every = 1.8, yaw = { 0, 360 } } },
                ramp = { { model = { 198947, 198948 } } },
            },
        },
    },
    items = items,
    -- The portal's opening.
    vortex = { center = 6, radius = 5.7, color = { 0.45, 1, 0.6 } },
    -- sound/doodad/portalparticles.ogg, sound/spells/teleport.ogg.
    sounds = { approach = 566073, through = 569735 },
})
