---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, SPACING = track.Add, track.Coins, track.COIN_SPACING

-- Low beams on layer 2 over one to three lanes side by side: too low to run under, too high to
-- jump over, so duck under them. Coins under one of them.
track.Register({
    name = "lowbeams",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 60,
    place = function(s, at, r)
        local first = r(-1, 1)
        local last = r(first, 1)
        for lane = first, last do
            add(s, "barrier", lane, at, 0.4, 2, 1)
        end
        coins(s, r(first, last), at - 2, 3, 0)
        return 2 * SPACING - 2
    end,
})
