---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- High ground: a platform 4 or 5 layers up (3 yards at most), its long ramp lined with coins
-- one layer apart, and a row of coins along the top.
track.Register({
    name = "tower",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 200,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), r(4, 5)
        local ramp = layers * 4
        local length = ramp + r(16, 26)
        add(s, "platform", lane, at, length, 0, layers, ramp)
        -- Up the ramp, a coin a yard into each layer's rise: just over the slope.
        for layer = 0, layers - 1 do
            add(s, "coin", lane, at + layer * 4 + 1 - 0.16, 0.32, layer, 1)
        end
        local first = at + ramp + 2
        coins(s, lane, first, fit(first, at + length - 2, 6), layers)
        return length
    end,
})
