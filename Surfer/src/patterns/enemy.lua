---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, SPACING = track.Add, track.Coins, track.COIN_SPACING

-- An enemy standing in one lane, low enough to jump (2 layers) or too tall (4), coins in
-- another. Rare.
track.Register({
    name = "enemy",
    weight = 1,
    place = function(s, at, r)
        local lane, tall = r(-1, 1), r(0, 1) == 1
        add(s, "enemy", lane, at, tall and 0.8 or 1.2, 0, tall and 4 or 2)
        coins(s, (lane + 2) % 3 - 1, at - 4, 5, 0)
        return 4 * SPACING - 4
    end,
})
