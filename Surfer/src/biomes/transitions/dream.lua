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
    -- An old, overgrown grove of the highborne around the gate:
    -- generic/activedoodads/worldtreeportals/worldtreeportal01 over the road (about 17 yards
    -- wide at this height); a ruined highborne statue on each side before it, turned toward the
    -- runner (kalimdor/diremaul/passivedoodads/rubble/diremaulstonestatue01 to 04); a tall
    -- Teldrassil tree close behind each side of its frame, its crown reaching over the portal's
    -- edge (kalimdor/kalidar/passivedoodads/kalidartrees/kalidartree02 or 04); Dire Maul's broken stone
    -- (diremaulwallrubble01 to 03, diremaultrimrubble01 to 03) along the road, and Feralas'
    -- standing stones (feralas/passivedoodads/stones/feralasstone01, 02) past the gate.
    items = {
        { model = 197068, x = 0, height = 14 },
        { model = { 201705, 201706, 201707, 201708 }, x = -6.8, d = -8, height = 9, yaw = { 215, 235 } },
        { model = { 201705, 201706, 201707, 201708 }, x = 6.8, d = -8, height = 9, yaw = { 125, 145 } },
        { model = { 202051, 202053 }, x = -11, d = { 0, 2 }, height = { 24, 28 }, yaw = { 0, 360 } },
        { model = { 202051, 202053 }, x = 11, d = { 0, 2 }, height = { 24, 28 }, yaw = { 0, 360 } },
        { model = { 201718, 201719, 201720 }, x = { -6, -4.6 }, d = { -10, -4 }, yaw = { 0, 360 } },
        { model = { 201718, 201719, 201720 }, x = { 4.6, 6 }, d = { -10, -4 }, yaw = { 0, 360 } },
        { model = { 201715, 201716, 201717 }, x = { -6.5, -4.6 }, d = { 5, 10 }, yaw = { 0, 360 } },
        { model = { 201715, 201716, 201717 }, x = { 4.6, 6.5 }, d = { 5, 10 }, yaw = { 0, 360 } },
        { model = { 201933, 201934 }, x = -7.5, d = { 12, 16 }, height = { 3, 5 }, yaw = { 0, 360 } },
        { model = { 201933, 201934 }, x = 7.5, d = { 12, 16 }, height = { 3, 5 }, yaw = { 0, 360 } },
    },
    flash = { 0.55, 1, 0.65 },
})
