---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, SPACING = track.Add, track.Coins, track.COIN_SPACING

-- Overhead barriers on layer 3 over one to three lanes side by side: run under them, do not
-- jump.
track.Register({
    name = "barriers",
    weight = 3,
    place = function(s, at, r)
        local first = r(-1, 1)
        local last = r(first, 1)
        for lane = first, last do
            add(s, "barrier", lane, at, 0.4, 3, 1)
        end
        coins(s, first, at - 2, 3, 0)
        return 2 * SPACING - 2
    end,
})
