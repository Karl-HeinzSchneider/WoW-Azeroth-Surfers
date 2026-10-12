---@type string, AzerothSurfers
local _, app = ...
-- Classic 5.5.4 reports interface 50504. Select its 5.5.x client family only.
local interface = select(4, GetBuildInfo())
if interface < 50500 or interface >= 50600 then
    return
end

-- Classic's asset audit rejects the baseline rabbit and ready stance.
app.biomes.ApplyAssetOverrides({
    creatures = { [139885] = 328 }, -- Rabbit; same fallback as the other clients.
    models = {}, -- M2 file IDs.
    sounds = {}, -- Sound file IDs or paths.
    textures = {}, -- Texture file IDs or paths.
    animations = { [25] = 0 }, -- ReadyUnarmed -> Stand (604 lacks ready).
    playerAnimations = {}, -- Player animation IDs.
    playerAnimationOffsets = {}, -- Visual height adjustments in yards.
})
