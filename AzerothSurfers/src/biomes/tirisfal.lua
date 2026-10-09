---@type string, AzerothSurfers
local _, app = ...
-- Tirisfal Glades: a weathered road through graveyards and Forsaken settlements.
-- Classic M2 and terrain IDs verified in the listfile. Keep Elwynn's tested lumber
-- platforms and plank ramps; the graveyard has its own obstacles and wildlife.
local ZOMBIE = { 565178, 565179, 565185, 565176 } -- Zombie/ZombieAttackA to D
local DARKHOUND = { 546876, 546881, 546874, 546885 } -- DarkHound/mDarkHoundAttackA to D
local SPIDER = { 549870, 549872, 549869, 549868 } -- GiantSpider/GiantSpiderAttackA to D
local GRAVES = { 190633, 190634, 190635, 190636 } -- Westfall/PassiveDoodads/Tombstones
-- Duskwood/tombs: TombStone05 to 08 and WoodCross01/02, for roadside plots only.
local MARKERS = { 190633, 190634, 190635, 190636, 189530, 189532, 189534, 189535, 189540, 189541 }
-- Native classic Tirisfal canopy trees (02 and 04 to 07).
local TREES = { 204129, 204131, 204132, 204133, 204134 }

-- Build paired graves at load time. Fixed offsets keep each headstone with its mound;
-- the decoration system mirrors the complete plot onto the other side of the road.
-- TirisfalGlade/PassiveDoodads/Graves/TirisfallGraveDirtMound01/02.
local function graveGroup(weight, length, plots, groundModel, framed, markers)
    local items = {}
    for _, plot in ipairs(plots) do
        local x, d = plot[1], plot[2]
        items[#items + 1] = { model = groundModel or { 204112, 204113 }, x = x, d = d, scale = 0.65 }
        items[#items + 1] = { model = markers or MARKERS, x = x, d = d + 1.2, yaw = 180, scale = 0.7 }
        if framed then
            -- Duskwood/PassiveDoodads/GraveFrame/DuskWoodGraveFrame.
            items[#items + 1] = { model = 189485, x = x, d = d, scale = 0.65 }
        end
    end
    return { weight = weight, length = length, items = items }
end

-- Keep spacing in the same units as the scaled models. The original 4.16-yard
-- spacing was unscaled, leaving large gaps at scale 0.65. Native length still
-- needs verification with /surfers preview model 189469 in this client.
local FENCE_SCALE = 0.65
local FENCE_SECTION = 4.16 * FENCE_SCALE
local function fenceGroup(count, damaged, style)
    local start = FENCE_SECTION / 2
    local items = { { model = 189467, x = 5.5, d = start, yaw = 90, scale = 0.65 } }
    local gap = damaged and math.floor(count / 2)
    local i = 1
    while i <= count do
        local along = start + i * FENCE_SECTION
        if i == gap then
            -- Keep a post at the gap's far edge and lay the missing panel outside the fence.
            items[#items + 1] = { model = 189467, x = 5.5, d = along, yaw = 90, scale = 0.65 }
            items[#items + 1] = {
                model = 189469,
                x = 7,
                d = along - FENCE_SECTION / 2,
                yaw = 90,
                roll = 90,
                scale = 0.65,
            }
            i = i + 1
        else
            local broken = damaged and i == gap + 1
            -- A double section spans two bays. Never let it bridge the deliberate gap.
            local double = not broken and i < count and i + 1 ~= gap
            local span = double and 2 or 1
            items[#items + 1] = {
                model = broken and 189466 or double and 189470 or 189469,
                x = 5.5,
                d = start + (i + span - 1) * FENCE_SECTION,
                yaw = 90,
                scale = 0.65,
            }
            i = i + span
        end
    end
    -- Dress the same group behind its fence so independent roadside groups cannot
    -- land between the railings and graves. Leave the damaged entrance free of props.
    for bay = 2, count - 1, 3 do
        if not gap or math.abs(bay - gap) > 1 then
            local d = start + bay * FENCE_SECTION
            local x = bay % 2 == 0 and 8.5 or 10
            local plots = graveGroup(
                1,
                0,
                { { x, d } },
                nil,
                style == "framed",
                style == "memorial" and { 189536, 189538 } or nil
            )
            for _, item in ipairs(plots.items) do
                items[#items + 1] = item
            end
            items[#items + 1] = {
                model = { 204097, 204098, 204099 },
                x = x + 1,
                d = d - 2,
                scale = { 0.35, 0.5 },
                yaw = { 0, 360 },
                chance = style == "overgrown" and 1 or 0.55,
            }
        end
    end
    items[#items + 1] = {
        model = { 204135, 204136 },
        x = 9,
        d = start + FENCE_SECTION,
        scale = { 0.4, 0.55 },
        yaw = { 0, 360 },
        chance = 0.7,
    }
    items[#items + 1] = {
        model = TREES,
        x = 8,
        d = start + (count - 2) * FENCE_SECTION,
        scale = { 0.25, 0.36 },
        yaw = { 0, 360 },
        chance = 0.85,
    }
    if style == "memorial" then
        items[#items + 1] = { model = 198318, x = 7.5, d = start + FENCE_SECTION, scale = 0.65 }
    end
    -- Keep the tested panel/post direction on both verges, including the closing post
    -- and the damaged gap. Only the lateral position changes on the left.
    return { weight = 0.8, length = (count + 1) * FENCE_SECTION, mirror = false, items = items }
end

app.biomes.Register("tirisfal", {
    name = "Tirisfal Glades",
    tier = 1,
    ground = {
        curve = 0.0002,
        surfaces = {
            -- tileset/TirisFall: StoneRoad01, DirtRock02 and grass01.
            road = { texture = 188963, color = { 0.34, 0.36, 0.3 } },
            dirt = { texture = 188950, color = { 0.28, 0.27, 0.2 } },
            grass = { texture = 188954, color = { 0.24, 0.29, 0.18 } },
        },
    },
    sky = {
        top = { 0.17, 0.23, 0.22 },
        horizon = { 0.46, 0.52, 0.36 },
        land = { 0.24, 0.29, 0.18 },
        haze = 0.65,
    },
    light = { night = { 0.44, 0.55, 0.5 } },
    obstacles = {
        -- Share only the proven platforms; all roadside scenery is Tirisfal's own.
        platform = app.biomes.Get("elwynn").obstacles.platform,
        obstacle = {
            -- DuskwoodFootLocker01; cap each at one yard tall to keep its broad model compact.
            { layers = 1, items = { { model = 198238, height = 0.85, yaw = { -10, 10 } } } },
            { layers = 2, items = { { model = 198238, height = 1, yaw = { -8, 8 } } } },
            { layers = 2, items = { { model = GRAVES, height = 1.24, yaw = { 170, 190 } } } },
            { layers = 4, items = { { model = GRAVES, height = 2.4, yaw = { 170, 190 } } } },
            {
                layers = 4,
                items = {
                    { model = 198238, height = 1 },
                    { model = 198238, height = 1, z = 1, yaw = { -10, 10 } },
                },
            },
        },
        -- UndeadFencePost supports the same readable overhead timber as Elwynn.
        barrier = {
            {
                items = {
                    { model = 200758, x = -1, ground = true, height = 2.15 },
                    { model = 200758, x = 1, ground = true, height = 2.15 },
                    { model = 198340, yaw = 90, z = 0.1, scale = 0.65 },
                },
            },
        },
        enemy = {
            -- Decrepit Darkhound (NPC 1547) and Night Web Spider (1505).
            { layers = 2, items = { { creature = 9021, yaw = 180, attack = 16, sound = DARKHOUND } } },
            { layers = 2, items = { { creature = 30, yaw = 180, attack = 16, sound = SPIDER } } },
            -- Mindless Zombie (1501) and Wretched Zombie (1502), using skinned displays.
            {
                layers = 4,
                items = {
                    {
                        creature = { 10973, 10979 },
                        height = 2.1,
                        yaw = 180,
                        animation = 25,
                        attack = 16,
                        sound = ZOMBIE,
                    },
                },
            },
        },
    },
    ambient = {
        every = { 90, 180 },
        creatures = {
            -- Duskbat (NPC 1512), flying above the track.
            { creature = 4732, move = "fly", speed = { 8, 11 }, z = { 5, 8 }, ahead = { 35, 55 }, scale = 0.7 },
        },
    },
    decorations = {
        spacing = { 3, 7 },
        ambient = { 0.6, 0.68, 0.57 },
        diffuse = { 0.45, 0.5, 0.4 },
        groups = {
            { weight = 2, length = { 5, 10 }, items = {} },
            -- TirisfalGlade/PassiveDoodads/Bushes: low vegetation near the road.
            {
                weight = 3,
                length = { 3, 6 },
                items = {
                    { model = { 204097, 204098, 204099 }, x = { 5.5, 7.5 }, yaw = { 0, 360 }, scale = { 0.45, 0.7 } },
                    { model = 204097, x = { 6, 8 }, d = 3, scale = 0.5, chance = 0.5 },
                },
            },
            -- TirisfalGladeTree01, kept small and close to the verge.
            {
                weight = 1.5,
                length = { 6, 9 },
                items = {
                    { model = 204124, x = { 6.5, 8 }, yaw = { 0, 360 }, scale = { 0.18, 0.25 } },
                    { model = 204098, x = 6, d = 3, scale = 0.5, chance = 0.6 },
                },
            },
            -- More frequent, taller canopies with occasional smaller trees between them.
            {
                weight = 3,
                length = { 6, 9 },
                items = {
                    { model = TREES, x = { 7, 8.5 }, yaw = { 0, 360 }, scale = { 0.28, 0.4 } },
                    { model = TREES, x = { 7, 8.5 }, d = 4, yaw = { 0, 360 }, scale = { 0.18, 0.25 }, chance = 0.5 },
                },
            },
            -- TirisfallTreeStump01/02, sometimes with a second stump and undergrowth.
            {
                weight = 2,
                length = { 4, 7 },
                items = {
                    { model = { 204135, 204136 }, x = { 5.5, 7.5 }, yaw = { 0, 360 }, scale = { 0.45, 0.7 } },
                    { model = 204136, x = 8, d = 3, yaw = { 0, 360 }, scale = 0.4, chance = 0.4 },
                    { model = 204097, x = 6, d = 2, scale = 0.4, chance = 0.5 },
                },
            },
            -- TirisfallFallenTree01 to 04: occasional dead trunks off the road.
            {
                weight = 0.75,
                length = { 7, 10 },
                items = {
                    {
                        model = { 204125, 204126, 204127, 204128 },
                        x = { 6.5, 8 },
                        yaw = { -15, 15 },
                        scale = { 0.18, 0.25 },
                    },
                },
            },
            -- A lone burial, two graves in a row, or a staggered cluster of three.
            -- Each mound always has a headstone or wooden cross.
            graveGroup(1.2, 5, { { 6.5, 1.5 } }),
            graveGroup(1, 9, { { 6.5, 1.5 }, { 6.5, 5.5 } }),
            graveGroup(0.8, 10, { { 6.5, 1.5 }, { 9, 3.5 }, { 6.5, 6.5 } }),
            -- The open grave includes a broad grassy surround: one complete piece,
            -- centered in a longer group with no added headstone or neighbouring grave.
            {
                weight = 0.8,
                length = 16,
                items = { { model = 204114, x = 8, d = 8, scale = 0.65 } },
            },
            -- Framed earth plots and a pair beside larger monuments.
            graveGroup(1, 9, { { 6.5, 1.5 }, { 9, 5 } }, 189528, true),
            graveGroup(0.4, 9, { { 7, 1.5 }, { 9.5, 5 } }, 189528, true, { 189536, 189538 }),
            -- Frequent graveyards, 10-18 bays long, with their own scenery behind the fence.
            fenceGroup(10, false, "framed"),
            fenceGroup(12, true, "overgrown"),
            fenceGroup(14, false, "memorial"),
            fenceGroup(15, true, "framed"),
            fenceGroup(16, false, "overgrown"),
            fenceGroup(18, true, "memorial"),
            -- TirisfallStreetLamp01 and a grave marker along the road.
            {
                weight = 2,
                length = 7,
                items = {
                    { model = 198318, x = 6, scale = 0.8 },
                    { model = 190634, x = 7, d = 3, scale = 0.7, chance = 0.5 },
                },
            },
            -- Lordaeron's banner appears only occasionally among the vegetation.
            { weight = 0.25, length = 6, items = { { model = 200673, x = 7, scale = 0.65 } } },
            { weight = 1, length = 5, items = { { model = 200655, x = 6.5, scale = 0.65 } } },
            {
                weight = 0.5,
                length = 10,
                items = {
                    { model = 198253, x = 8, scale = 0.45 }, -- TirisfallFountain
                    { model = 200652, x = 6.5, d = 4, scale = 0.65 }, -- Lordaeron_Bench_01
                },
            },
            -- An apothecary's roadside workstation: undead_alchemy_table.
            { weight = 0.15, length = 7, items = { { model = 200767, x = 7, scale = 0.6 } } },
        },
    },
})
