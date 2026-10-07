---@type string, Surfer
local _, app = ...
local track = app.track
local add, SPACING = track.Add, track.COIN_SPACING

-- The coins' layers over the hurdle, an arc only a jump collects.
local ARC = { 3, 4, 5, 5, 4, 3 }

-- A hurdle under an arc of coins.
track.Register({
    name = "hurdle",
    weight = 3,
    place = function(s, at, r)
        local lane = r(-1, 1)
        add(s, "obstacle", lane, at, 0.5, 0, 1)
        -- Centred over the hurdle.
        for i, layer in ipairs(ARC) do
            add(s, "coin", lane, at + 0.25 + (i - 3.5) * SPACING - 0.16, 0.32, layer, 1)
        end
        return 8
    end,
})
