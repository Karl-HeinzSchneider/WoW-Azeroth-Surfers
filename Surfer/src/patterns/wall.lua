---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, SPACING = track.Add, track.Coins, track.COIN_SPACING

-- A tall wall to dodge beside a hurdle to jump; coins in the third lane, which is clear.
track.Register({
    name = "wall",
    weight = 3,
    place = function(s, at, r)
        local tall = r(-1, 1)
        local low = (tall + 1 + r(1, 2)) % 3 - 1
        add(s, "obstacle", tall, at, 0.8, 0, 4)
        add(s, "obstacle", low, at, 0.5, 0, 1)
        coins(s, -tall - low, at - 4, 4, 0)
        return 3 * SPACING - 4
    end,
})
