---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
-- /surfers animations: which of dev.ANIMATIONS each enemy of the biome (or one creature) has. A
-- model scene cannot tell, a character model frame can (HasAnimation): an invisible one loads
-- each creature in turn.

local TIMEOUT = 3
local queue, current, waited = {}, nil, 0

local model = CreateFrame("PlayerModel", nil, UIParent)
model:SetSize(1, 1)
model:SetPoint("BOTTOMLEFT")
model:SetAlpha(0)
model:Hide()

local function nextCreature()
    current, waited = table.remove(queue, 1), 0
    if not current then
        model:Hide()
        return
    end
    model:Show()
    model:SetDisplayInfo(current)
end

model:SetScript("OnUpdate", function(_, elapsed)
    if not current then
        return
    end
    waited = waited + elapsed
    -- Every creature has a stand animation once its model has loaded.
    if not model:HasAnimation(0) then
        if waited > TIMEOUT then
            log:chat("creature %d: did not load", current)
            nextCreature()
        end
        return
    end
    local has, lacks = {}, {}
    for _, animation in ipairs(dev.ANIMATIONS) do
        local list = model:HasAnimation(animation[1]) and has or lacks
        list[#list + 1] = animation[1] .. " " .. animation[2]
    end
    log:chat("creature %d has: %s", current, table.concat(has, ", "))
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

dev.Command("animations", "animations [display id]: which animations the biome's enemies have", function(rest)
    local id = dev.Words(rest)[1]
    local ids = type(id) == "number" and { id } or enemies()
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
