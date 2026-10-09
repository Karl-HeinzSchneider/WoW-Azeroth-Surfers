---@type string, table
local _, dev = ...
local log = dev.log
-- /surfers occluder: the ground's depth (AzerothSurfers' occluder.lua) on and off, its tiles
-- shown over the ground to see where they lie, and how far under it they lie.

local function report(o)
    local sink = o.OCCLUDER_SINK
    log:chat(
        "Occluder: %s, %d tiles, %.2f yards under the ground before a run from the lobby, %.2f in a run",
        o.occluderOff and "off" or o.occluderShown and "shown" or "on",
        o.occluder and o.occluder.count or 0,
        sink.lobby,
        sink.run
    )
end

dev.Command(
    "occluder",
    "occluder on | off | show | sink lobby|run <yards>: the ground's depth (show: its tiles over the ground)",
    function(rest)
        local o = dev.Overlay()
        if not o or not o.occluder then
            return
        end
        local words = dev.Words(rest)
        if words[1] == "on" or words[1] == "off" or words[1] == "show" then
            o.occluderOff = words[1] == "off" or nil
            o.occluderShown = words[1] == "show" or nil
            o:PlaceOccluder()
            if o.occluderShown then
                -- Over the view's own textures (the ground), under the world scene.
                o.occluder.scene:SetFrameLevel(o.frame:GetFrameLevel() + 1)
            end
        elseif words[1] == "sink" and o.OCCLUDER_SINK[words[2]] and type(words[3]) == "number" then
            o.OCCLUDER_SINK[words[2]] = words[3]
        else
            report(o)
            return
        end
        -- Placed anew on the next frame.
        o.occluder.last.placed = nil
        report(o)
    end
)
