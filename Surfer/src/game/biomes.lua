---@type string, Surfer
local _, app = ...
-- Biomes: how the game looks in one region of the world, one file each in src/biomes/. A biome
-- lists only what it changes; everything else comes from the default biome (default.lua, which
-- documents every field). Tables merge field by field, so `ground.surfaces.road.texture`
-- alone replaces just the road's texture; lists (a color, the bands, the coin models) are
-- replaced whole.
local biomes = { list = {}, merged = {} }
app.biomes = biomes

-- A list: a table with a first element. Colors and lists are replaced whole, never merged.
local function isList(t)
    return type(t) == "table" and t[1] ~= nil
end

-- `over` laid over `base`, without changing either.
local function merge(base, over)
    if type(base) ~= "table" or type(over) ~= "table" or isList(base) or isList(over) then
        return over
    end
    local out = {}
    for k, v in pairs(base) do
        out[k] = v
    end
    for k, v in pairs(over) do
        out[k] = merge(base[k], v)
    end
    return out
end

-- Called by each biome file: `id` is what the profile stores, `biome.name` what players see.
function biomes.Register(id, biome)
    biomes.list[id] = biome
    biomes.merged = {}
end

-- The biome `id` with the default's fields filled in; the default for an unknown id.
function biomes.Get(id)
    if not biomes.list[id] then
        id = "default"
    end
    local merged = biomes.merged[id]
    if not merged then
        merged = id == "default" and biomes.list.default or merge(biomes.list.default, biomes.list[id])
        biomes.merged[id] = merged
    end
    return merged
end

-- The biome the profile picked.
function biomes.Current()
    return biomes.Get(app.db.profile.biome)
end

-- Every biome's name by id, for the options' select.
function biomes.Names()
    local names = {}
    for id, biome in pairs(biomes.list) do
        names[id] = biome.name or id
    end
    return names
end
