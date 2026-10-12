---@type string, AzerothSurfers
local _, app = ...
-- Classic Era 1.15.9 reports interface 11509. Select its 1.15.x client family only.
local interface = select(4, GetBuildInfo())
if interface < 11500 or interface >= 11600 then
    return
end

-- Era's asset audit rejects the baseline rabbit, ready stance and player roll.
app.biomes.ApplyAssetOverrides({
    creatures = { [139885] = 328 }, -- Rabbit; same fallback as retail and Anniversary.
    models = {}, -- M2 file IDs.
    sounds = {}, -- Sound file IDs or paths.
    textures = {}, -- Texture file IDs or paths.
    animations = { [25] = 0 }, -- ReadyUnarmed -> Stand (604 lacks ready).
    playerAnimations = { [666] = 42 }, -- Roll -> Swim.
    playerAnimationOffsets = { [42] = -0.5 }, -- Lower the swimming duck visually, as on Anniversary.
})
