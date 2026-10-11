---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
-- /surfers animations: which of dev.ANIMATIONS each enemy of the biome (or one creature) has, or
-- which of dev.CROUCH your own character has. A model scene cannot tell, a character model frame
-- can (HasAnimation): an invisible one loads each creature in turn.

local TIMEOUT = 3
-- Display ids, or "player".
local queue, current, waited = {}, nil, 0
local loaded = false
local function label()
    return current == "player" and "your character" or "creature " .. current
end

local model = CreateFrame("PlayerModel", nil, UIParent)
model:SetSize(1, 1)
model:SetPoint("BOTTOMLEFT")
model:SetAlpha(0)
model:Hide()
model:SetScript("OnModelLoaded", function()
    loaded = true
end)

local function nextCreature()
    current, waited = table.remove(queue, 1), 0
    if not current then
        model:Hide()
        return
    end
    model:Show()
    model:ClearModel()
    loaded = false
    if current == "player" then
        model:SetUnit("player")
    else
        model:SetDisplayInfo(current)
    end
end

model:SetScript("OnUpdate", function(_, elapsed)
    if not current then
        return
    end
    waited = waited + elapsed
    if not loaded then
        if waited > TIMEOUT then
            log:chat("%s: did not load within %ds; retry to rule out slow loading", label(), TIMEOUT)
            nextCreature()
        end
        return
    end
    local has, lacks = {}, {}
    for _, animation in ipairs(current == "player" and dev.CROUCH or dev.ANIMATIONS) do
        local list = model:HasAnimation(animation[1]) and has or lacks
        list[#list + 1] = animation[1] .. " " .. animation[2]
    end
    log:chat("%s has: %s", label(), #has > 0 and table.concat(has, ", ") or "none")
    log:chat("    lacks: %s", #lacks > 0 and table.concat(lacks, ", ") or "none")
    nextCreature()
end)

-- The creature display ids of the biome's enemies.
local function enemies()
    local ids, seen = {}, {}
    for _, variant in ipairs(app.biomes.Get(app.overlay:BiomeId()).obstacles.enemy or {}) do
        for _, item in ipairs(variant.items) do
            local list = type(item.creature) == "table" and item.creature or { item.creature }
            for _, id in ipairs(list) do
                if not seen[id] then
                    seen[id] = true
                    ids[#ids + 1] = id
                end
            end
        end
    end
    return ids
end

dev.Command("animations", "animations [display id | player]: which animations the biome's enemies have", function(rest)
    local id = dev.Words(rest)[1]
    local ids = (type(id) == "number" or id == "player") and { id } or enemies()
    if #ids == 0 then
        log:chat("The biome has no enemies.")
        return
    end
    for _, each in ipairs(ids) do
        queue[#queue + 1] = each
    end
    if not current then
        nextCreature()
    end
end)
