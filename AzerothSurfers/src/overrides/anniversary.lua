---@type string, AzerothSurfers
local _, app = ...
-- Anniversary reported interface 20506. Select its 2.5.x client family only.
local interface = select(4, GetBuildInfo())
if interface < 20500 or interface >= 20600 then
    return
end

-- Independent of retail. Rabbit and player fallback need an Anniversary audit/preview.
app.biomes.ApplyAssetOverrides({
    creatures = { [139885] = 328 }, -- Rabbit (working retail replacement).
    models = {}, -- M2 file IDs.
    sounds = {}, -- Sound file IDs or paths.
    textures = {}, -- Texture file IDs or paths.
    animations = { [25] = 0 }, -- ReadyUnarmed -> Stand (604 and 6798 lack ready).
    playerAnimations = { [666] = 119 }, -- Roll -> StealthWalk for crouching.
})
