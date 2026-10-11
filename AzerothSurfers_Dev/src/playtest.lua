---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
-- Playtest helpers: a fixed time of day for the light, invincibility, and patterns on demand.

local LIGHTS = { day = 1, dusk = 0.5, night = 0 }

dev.Command("light", "light day | dusk | night | auto: fix the time of day for the light", function(rest)
    local word = dev.Words(rest)[1]
    if word == "auto" then
        app.light.override = nil
    elseif LIGHTS[word] then
        app.light.override = LIGHTS[word]
    else
        log:chat("/surfers light day | dusk | night | auto")
        return
    end
    -- Relit on the next frame.
    app.light.day = nil
    log:chat("Light: %s", word)
end)

dev.Command("god", "god: run through everything (toggles)", function()
    app.simulation.invincible = not app.simulation.invincible or nil
    log:chat("Invincible: %s", app.simulation.invincible and "on" or "off")
end)

dev.Command("multiplier", "multiplier <n>: score n times from now on (the HUD's star)", function(rest)
    local n = dev.Words(rest)[1]
    if type(n) ~= "number" then
        log:chat("/surfers multiplier <n>")
        return
    end
    local o = dev.Overlay()
    if not o then
        return
    end
    app.simulation.SetMultiplier(o.state, n)
    log:chat("Multiplier: x%d", o.state.multiplier)
end)

-- The scoring rules' `streak` fields (scoring.lua), in the order the command lists them.
local STREAK_FIELDS = { "gap", "seconds", "from", "points" }

dev.Command(
    "streak",
    "streak [gap <yards>] [seconds <s>] [from <coins>] [points <n>]: what keeps a coin streak and what it scores (streak alone: the settings)",
    function(rest)
        -- The defaults, for runs from now on, and the running one's own rules.
        local streak, words = app.scoring.DEFAULTS.streak, dev.Words(rest)
        local o = app.overlay
        for i = 1, #words, 2 do
            local field, value = words[i], words[i + 1]
            if streak[field] == nil or type(value) ~= "number" or value < 0 then
                log:chat("/surfers streak [gap <yards>] [seconds <s>] [from <coins>] [points <n>]")
                return
            end
            streak[field] = value
            if o.state then
                o.state.scoring.streak[field] = value
            end
        end
        local parts = {}
        for i, field in ipairs(STREAK_FIELDS) do
            parts[i] = field .. " " .. tostring(streak[field])
        end
        log:chat("Streak: %s", table.concat(parts, ", "))
        if o.state then
            log:chat(
                "Holds %.1f yards at %d yards a second; this run's best %d",
                app.simulation.StreakReach(o.state),
                o.state.speed,
                o.state.bestStreak
            )
        end
    end
)

dev.Command(
    "reference",
    "reference <yards>: the height a taller character is drawn at in the track's world (the track grows around it)",
    function(rest)
        local o = dev.Overlay()
        if not o then
            return
        end
        local yards = dev.Words(rest)[1]
        if type(yards) == "number" and yards > 0.5 then
            o.referenceHeight = yards
            o:ApplyBodyScale()
        end
        log:chat(
            "Character %.2f yards tall (measured), reference %.2f: drawn at %.2f, the track %.2f times as big",
            o.height,
            o.referenceHeight,
            o.body,
            o.bodyScale
        )
    end
)

dev.Command(
    "zonelength",
    "zonelength <yards> [<max yards>]: how long auto's zones last (zonelength alone: the zones so far)",
    function(rest)
        local sim, words, o = app.simulation, dev.Words(rest), app.overlay
        local low, high = words[1], words[2] or words[1]
        if type(low) == "number" and type(high) == "number" and low >= 50 and high >= low then
            sim.ZONE_LENGTH = { low, high }
            -- The next gate at most that far, from the end of the track laid out so far.
            local s = o.state
            if s and s.nextGate then
                s.nextGate = math.min(s.nextGate, s.nextRow + low)
            end
            log:chat("Zones last %d to %d yards", low, high)
        elseif rest ~= "" then
            log:chat("/surfers zonelength <yards> [<max yards>], at least 50")
            return
        end
        log:chat("Zone length %d to %d yards", sim.ZONE_LENGTH[1], sim.ZONE_LENGTH[2])
        local s = o.state
        if not s or not s.gates then
            log:chat("This run has no zones: the biome option is not Auto (or was not when it began).")
            return
        end
        o:BiomeIdAt(s.distance)
        log:chat("At %d yards; next gate laid out at %d:", math.floor(s.distance), math.floor(s.nextGate))
        for k, zone in ipairs(o.route.zones) do
            local from, to = s.gates[k - 1] or 0, s.gates[k]
            log:chat(
                "  %d. %s (tier %d) from %d to %s",
                k,
                zone.id,
                zone.tier or 0,
                from,
                to and tostring(math.floor(to)) or "..."
            )
        end
    end
)

-- The registered patterns' names (src/patterns/), in their order.
local function patternNames()
    local names = {}
    for i, pattern in ipairs(app.track.list) do
        names[i] = pattern.name
    end
    return table.concat(names, " | ")
end

dev.Command("spawn", "spawn <pattern>: that pattern 30 yards ahead (spawn alone lists them)", function(rest)
    local o = dev.Overlay()
    if not o then
        return
    end
    local word = dev.Words(rest)[1]
    local pattern = type(word) == "number" and app.track.list[word] or app.track.byName[word]
    if not pattern then
        log:chat("/surfers spawn %s", patternNames())
        return
    end
    local s = o.state
    pattern.place(s, s.distance + 30, s.random)
end)

-- A lobby shot's fields, in the order lobby.lua writes them.
local SHOT_FIELDS = { "at", "side", "height", "pitch", "fov" }

-- The shot as a line of Lua, to paste into src/scenes/lobby.lua.
local function shotLine(name, shot)
    local parts = {}
    for _, field in ipairs(SHOT_FIELDS) do
        parts[#parts + 1] = string.format("%s = %g", field, shot[field])
    end
    return string.format("%s = { %s }", name, table.concat(parts, ", "))
end

dev.Command(
    "shot",
    "shot [title | menu] [window] [at|side|height|pitch|fov <n> ...]: look through a lobby shot and change it (window: the side window's values; shot alone: both, as Lua)",
    function(rest)
        local shots, words = app.lobby.shots, dev.Words(rest)
        local name = words[1]
        if not shots[name] then
            for _, which in ipairs({ "title", "menu" }) do
                log:chat(shotLine(which, shots[which]))
                if shots[which].sideWindow then
                    log:chat("  sideWindow: %s", shotLine(which, shots[which].sideWindow))
                end
            end
            return
        end
        local shot, first = shots[name], 2
        if words[2] == "window" then
            shot.sideWindow = shot.sideWindow or {}
            -- Filled with the full screen's values, then changed.
            for _, field in ipairs(SHOT_FIELDS) do
                shot.sideWindow[field] = shot.sideWindow[field] or shot[field]
            end
            shot, first = shot.sideWindow, 3
        end
        for i = first, #words, 2 do
            local field, value = words[i], words[i + 1]
            if shot[field] == nil or type(value) ~= "number" then
                log:chat("/surfers shot [title | menu] [window] [at|side|height|pitch|fov <n> ...]")
                return
            end
            shot[field] = value
        end
        log:chat(shotLine(name, shot))
        -- The camera goes there at once while the title or the menu shows.
        local o = app.overlay
        if o.frame and o.frame:IsShown() and (o.screen == "title" or o.screen == "menu") then
            o.shotName, o.glide, o.lastRoad = name, nil, {}
        end
    end
)

-- A camp item's fields, in the order lobby.lua writes them.
local ITEM_FIELDS = { "model", "x", "d", "z", "height", "scale", "yaw", "lift" }

local function luaValue(v)
    if type(v) == "table" then
        local parts = {}
        for i, part in ipairs(v) do
            parts[i] = luaValue(part)
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    elseif type(v) == "number" then
        return string.format("%g", v)
    end
    return tostring(v)
end

-- The item as a line of Lua, to paste into src/scenes/lobby.lua.
local function itemLine(item)
    local parts = {}
    for _, field in ipairs(ITEM_FIELDS) do
        if item[field] ~= nil then
            parts[#parts + 1] = field .. " = " .. luaValue(item[field])
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " },"
end

dev.Command(
    "camp",
    "camp [<n> [x|d|z|yaw|height|scale <number>] [lift on|off] ...]: the lobby's items (camp alone: all, numbered); changes one live",
    function(rest)
        local items, words = app.lobby.items, dev.Words(rest)
        local item = items[words[1]]
        if not item then
            for i, each in ipairs(items) do
                log:chat("%d: %s", i, itemLine(each))
            end
            return
        end
        for i = 2, #words, 2 do
            local field, value = words[i], words[i + 1]
            if field == "lift" and (value == "on" or value == "off") then
                item.lift = value == "on" or nil
            elseif (field == "x" or field == "d" or field == "z" or field == "yaw") and type(value) == "number" then
                item[field] = value
            elseif (field == "height" or field == "scale") and type(value) == "number" then
                -- One or the other sizes it.
                item.height, item.scale = nil, nil
                item[field] = value
            else
                log:chat("/surfers camp <n> [x|d|z|yaw|height|scale <number>] [lift on|off] ...")
                return
            end
        end
        log:chat("%d: %s", words[1], itemLine(item))
        -- Placed anew on the next frame.
        app.overlay.decorState = nil
    end
)
