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
        log:chat("/surfer light day | dusk | night | auto")
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
        log:chat("/surfer multiplier <n>")
        return
    end
    local o = dev.Overlay()
    if not o then
        return
    end
    app.simulation.SetMultiplier(o.state, n)
    log:chat("Multiplier: x%d", o.state.multiplier)
end)

-- sim.STREAK's fields, in the order the command lists them.
local STREAK_FIELDS = { "gap", "seconds", "from", "points" }

dev.Command(
    "streak",
    "streak [gap <yards>] [seconds <s>] [from <coins>] [points <n>]: what keeps a coin streak and what it scores (streak alone: the settings)",
    function(rest)
        local streak, words = app.simulation.STREAK, dev.Words(rest)
        for i = 1, #words, 2 do
            local field, value = words[i], words[i + 1]
            if streak[field] == nil or type(value) ~= "number" or value < 0 then
                log:chat("/surfer streak [gap <yards>] [seconds <s>] [from <coins>] [points <n>]")
                return
            end
            streak[field] = value
        end
        local parts = {}
        for i, field in ipairs(STREAK_FIELDS) do
            parts[i] = field .. " " .. tostring(streak[field])
        end
        log:chat("Streak: %s", table.concat(parts, ", "))
        local o = app.overlay
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
            log:chat("/surfer zonelength <yards> [<max yards>], at least 50")
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
        log:chat("/surfer spawn %s", patternNames())
        return
    end
    local s = o.state
    pattern.place(s, s.distance + 30, s.random)
end)
