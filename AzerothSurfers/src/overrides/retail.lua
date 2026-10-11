---@type string, AzerothSurfers
local _, app = ...
-- Forever can identify as Mainline too. Its interface number must take precedence.
-- Listed in the shared TOC, but does nothing on Forever or any Classic client.
local interface = select(4, GetBuildInfo())
if interface == 16001 or not WOW_PROJECT_MAINLINE or WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
    return
end

-- All retail substitutions belong here, using Forever's IDs on the left. Targets are final
-- IDs, not chains of replacements. Applied once after the lobby, before game consumers load.
-- Retail creature display replacements supplied by the user.
app.biomes.ApplyAssetOverrides({
    creatures = {
        [1252] = 1967, -- Razormane Scout
        [6088] = 6096, -- Razormane Dustrunner
        [30] = 418, -- Night Web Spider
        [139885] = 328, -- Rabbit
    },
    models = {}, -- M2 file IDs in model fields (including lists).
    sounds = {}, -- Sound file IDs or paths, including footsteps, voices and lobby music.
    textures = {}, -- Texture file IDs or paths in texture fields.
    animations = {}, -- Explicit animation/attack IDs in biome definitions.
})
