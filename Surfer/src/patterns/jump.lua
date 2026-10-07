---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, SPACING = track.Add, track.Coins, track.COIN_SPACING

-- One lane blocked low enough to jump, coins in another.
track.Register({
    name = "jump",
    weight = 3,
    place = function(s, at, r)
        local blocked = r(-1, 1)
        add(s, "obstacle", blocked, at, 0.5, 0, r(1, 2))
        coins(s, (blocked + 2) % 3 - 1, at - 4, 5, 0)
        return 4 * SPACING - 4
    end,
})
