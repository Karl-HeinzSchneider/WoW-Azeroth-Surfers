---@type string, Surfer
local _, app = ...
-- The Emerald Dream: the gate is the great tree portal of the dragon groves (Seradane, Twilight
-- Grove, Dream Bough, Bough Shadow), on Ashenvale's mossy ground; jumping through flashes green.
app.biomes.RegisterTransition("dream", {
    name = "Emerald Dream",
    ground = {
        surfaces = {
            road = { texture = 186838 }, -- tileset/ashenvale/ashenvaleroad.blp
            dirt = { texture = 186836 }, -- tileset/ashenvale/ashenvalemossbase.blp
            grass = { texture = 186830 }, -- tileset/ashenvale/ashenvaleferns.blp
        },
    },
    -- generic/activedoodads/worldtreeportals/worldtreeportal01, over the road.
    items = {
        { model = 197068, x = 0, height = 14 },
    },
    flash = { 0.55, 1, 0.65 },
})
