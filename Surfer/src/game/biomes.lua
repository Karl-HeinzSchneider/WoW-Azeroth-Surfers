---@type string, Surfer
local _, app = ...
-- Biomes: how the game looks in one region, one file each in src/biomes/, listing only what
-- differs from default.lua (which documents every field). Tables merge field by field; lists
-- (a color, the bands, the coin models) are replaced whole.
local biomes = { list = {}, merged = {} }
app.biomes = biomes

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

-- `id` is what the profile stores, `biome.name` what players see. A biome with a `tier` (1 for
-- starter zones, 2 and up for later ones) is a zone auto mode goes through, picked by `weight`
-- (1 if left out) among its tier's.
function biomes.Register(id, biome)
    biomes.list[id] = biome
    biomes.merged = {}
    biomes.zones = nil
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

function biomes.Names()
    local names = {}
    for id, biome in pairs(biomes.list) do
        names[id] = biome.name or id
    end
    return names
end

biomes.transitions = {}

-- Transitions (src/biomes/transitions/): what a gate between two zones looks like, named by the
-- next biome's `entrance`. They dress the strip of track.GATE around the rim; past it nothing
-- shows until the runner jumps through. `def`:
--   name
--   ground    optional: `surfaces` as a biome's; a surface left out, or no ground at all, is
--             the zones' (the one before up to the rim, the next one past it)
--   items     the models at the gate, placed like decorations from the rim: `model` (a file id
--             or a list), `x` (yards to the screen's right of the road's middle; write an item
--             for each side), `d` (yards along the road from the rim), `z`, `yaw`, `scale` or
--             `height`, `lift`; any number may be a { min, max } range
--   obstacles the looks of the gate's boxes, as a biome's `obstacles`
--   flash     optional: a color the screen flashes in going through
--   vortex    optional: the portal's pull (messages.lua's ShowVortex): its opening's `center`
--             yards up, `radius`, `color`
--   sounds    optional, with a `vortex` (the "Portal sounds" option): `approach` during the
--             pull, `through` as the camera goes through
function biomes.RegisterTransition(id, def)
    biomes.transitions[id] = def
end

-- The transition `id`, or the first registered one for an unknown id.
function biomes.Transition(id)
    return biomes.transitions[id] or biomes.transitions.dream
end

-- `profile.biome` for auto. Where a zone ends is the simulation's; which biome it is, here.
biomes.AUTO = "auto"
-- How much likelier the next tier up is than staying or going back to a lower one.
local CLIMB = 3

-- Every biome with a tier, by tier then id (a fixed order, so a seed always goes the same way).
local function zoneList()
    if biomes.zones then
        return biomes.zones
    end
    local list, tiers, seen = {}, {}, {}
    for id, biome in pairs(biomes.list) do
        if biome.tier then
            list[#list + 1] = { id = id, tier = biome.tier, weight = biome.weight or 1 }
            if not seen[biome.tier] then
                seen[biome.tier] = true
                tiers[#tiers + 1] = biome.tier
            end
        end
    end
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then
            return a.tier < b.tier
        end
        return a.id < b.id
    end)
    table.sort(tiers)
    biomes.zones = { list = list, tiers = tiers }
    return biomes.zones
end

local function pick(r, entries)
    local total = 0
    for _, entry in ipairs(entries) do
        total = total + entry.weight
    end
    local roll = r() * total
    for _, entry in ipairs(entries) do
        roll = roll - entry.weight
        if roll < 0 then
            return entry
        end
    end
    return entries[#entries]
end

-- The next zone of a route: its biome. Its tier: the lowest one to start with; then the next
-- one up (CLIMB times as likely), the same one, or any lower one, never skipping one on the way
-- up. Its biome: one of the tier's not visited yet, by weight; once all were, all of them again,
-- but never the one just left while there is another.
local function addZone(route)
    local r, zones, visited = route.random, route.zones, route.visited
    local last = zones[#zones]
    local all = zoneList()
    if #all.list == 0 then
        zones[#zones + 1] = { id = "default" }
        return
    end
    local tier = all.tiers[1]
    if last then
        local choices, at = {}, 1
        for k, t in ipairs(all.tiers) do
            if t == last.tier then
                at = k
            end
        end
        for k = 1, math.min(at + 1, #all.tiers) do
            choices[#choices + 1] = { tier = all.tiers[k], weight = k == at + 1 and CLIMB or 1 }
        end
        tier = pick(r, choices).tier
    end
    local pool = {}
    for pass = 1, 2 do
        for _, entry in ipairs(all.list) do
            if entry.tier == tier and not visited[entry.id] and not (last and entry.id == last.id) then
                pool[#pool + 1] = entry
            end
        end
        if #pool > 0 or pass == 2 then
            break
        end
        -- Every one of the tier visited: all of them again.
        for _, entry in ipairs(all.list) do
            if entry.tier == tier then
                visited[entry.id] = nil
            end
        end
    end
    -- The tier's only biome, just left: again.
    if #pool == 0 then
        for _, entry in ipairs(all.list) do
            if entry.tier == tier then
                pool[#pool + 1] = entry
            end
        end
    end
    local entry = pick(r, pool)
    visited[entry.id] = true
    zones[#zones + 1] = { id = entry.id, tier = tier }
end

-- `gates`: the run's `gates`, growing with its track.
function biomes.Route(seed, gates)
    return { random = app.random.New(seed, app.random.ZONES), zones = {}, visited = {}, gates = gates, at = 1 }
end

-- `id`, its biome; `from` and `to`, its gates (+-math.huge where there is none yet).
function biomes.Zone(route, distance)
    local gates, k = route.gates, route.at
    while gates[k] and gates[k] <= distance do
        k = k + 1
    end
    while k > 1 and gates[k - 1] > distance do
        k = k - 1
    end
    route.at = k
    local zones = route.zones
    while #zones < k do
        addZone(route)
    end
    local zone = zones[k]
    zone.from, zone.to = gates[k - 1] or -math.huge, gates[k] or math.huge
    return zone
end

function biomes.ZoneAt(route, distance)
    return biomes.Zone(route, distance).id
end
