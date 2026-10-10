---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, arc = track.Add, track.Coins, track.Arc

-- A row across the road with a different way through each lane: a beam on layer 3 to run under,
-- a low beam on layer 2 to duck under, a crate to jump. Coins under the low beam, or in an arc
-- over the crate.
track.Register({
    name = "choice",
    weight = { easy = 1, normal = 1, hard = 2, expert = 2 },
    from = 100,
    place = function(s, at, r)
        -- The lanes in a random order: high beam, low beam, crate.
        local high = r(-1, 1)
        local low = high == 0 and (r(0, 1) == 0 and -1 or 1) or (r(0, 1) == 0 and 0 or -high)
        local crate = -high - low
        add(s, "barrier", high, at, 0.4, 3, 1)
        add(s, "barrier", low, at, 0.4, 2, 1)
        add(s, "obstacle", crate, at, 0.5, 0, r(1, 2))
        if r(0, 1) == 0 then
            coins(s, low, at - 2, 3, 0)
        else
            arc(s, crate, at + 0.25)
        end
        return 8
    end,
})
