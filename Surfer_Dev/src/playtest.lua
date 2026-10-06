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

-- The simulation's patterns in their order (simulation.lua).
local PATTERNS = { "jump", "hurdle", "wall", "barriers", "platform", "enemy" }

dev.Command(
    "spawn",
    "spawn jump | hurdle | wall | barriers | platform | enemy: that pattern 30 yards ahead",
    function(rest)
        local o = dev.Overlay()
        if not o then
            return
        end
        local word = dev.Words(rest)[1]
        local index = type(word) == "number" and word or nil
        for i, name in ipairs(PATTERNS) do
            if name == word then
                index = i
            end
        end
        local pattern = index and app.simulation.patterns[index]
        if not pattern then
            log:chat("/surfer spawn %s", table.concat(PATTERNS, " | "))
            return
        end
        local s = o.state
        pattern(s, s.distance + 30, s.random)
    end
)
