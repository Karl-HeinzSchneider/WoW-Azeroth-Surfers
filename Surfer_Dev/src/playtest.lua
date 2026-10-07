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
