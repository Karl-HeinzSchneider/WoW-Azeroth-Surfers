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
})
