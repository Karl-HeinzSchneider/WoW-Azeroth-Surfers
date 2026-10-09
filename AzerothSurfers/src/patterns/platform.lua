---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, fit, SPACING = track.Add, track.Coins, track.Fit, track.COIN_SPACING

-- Higher ground: a platform (with a ramp when too high to jump onto), coins and maybe an
-- obstacle on top, sometimes a higher platform beside it to jump across to.
track.Register({
    name = "platform",
    weight = 3,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), r(1, 3)
        local ramp = (layers == 3 or r(0, 1) == 1) and layers * 4 or nil
        local length = r(24, 40)
        add(s, "platform", lane, at, length, 0, layers, ramp)
        -- Coins on top, from past the ramp to short of the end.
        local first = at + (ramp or 0) + 2
        local count = fit(first, at + length - 2, 6)
        coins(s, lane, first, count, layers)
        -- Past the coins, with room to land before the platform ends.
        if r(0, 1) == 1 and at + length - 6 > first + (count - 1) * SPACING + 3 then
            add(s, "obstacle", lane, at + length - 6, 0.5, layers, 1)
        end
        if layers < 3 and r(0, 1) == 1 then
            local beside = lane == 0 and (r(0, 1) == 0 and -1 or 1) or 0
            add(s, "platform", beside, at + 10, length - 10, 0, layers + 1)
            coins(s, beside, at + 14, fit(at + 14, at + length - 2, 6), layers + 1)
        end
        return length
    end,
})
