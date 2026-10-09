---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, fit, arc = track.Add, track.Coins, track.Fit, track.Arc

-- A terrace: the road steps up one or two layers in every lane, low enough to jump onto (one
-- lane sometimes has a ramp), and drops back at its end. On top a crate to jump in one lane
-- (coins in an arc over it), a tall enemy in another (leave its lane), coins along the third.
track.Register({
    name = "terrace",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 100,
    place = function(s, at, r)
        local layers, length = r(1, 2), r(30, 40)
        local ramp = layers * 4
        local ramped = r(0, 1) == 1 and r(-1, 1) or nil
        for lane = -1, 1 do
            add(s, "platform", lane, at, length, 0, layers, lane == ramped and ramp or nil)
        end
        local crate = r(-1, 1)
        local tall = (crate + 1 + r(1, 2)) % 3 - 1
        local free = -crate - tall
        -- Both past the longest ramp.
        local hurdle = at + r(12, length - 14)
        add(s, "obstacle", crate, hurdle, 0.5, layers, r(1, 2))
        arc(s, crate, hurdle + 0.25, layers)
        add(s, "enemy", tall, at + r(14, length - 6), 0.8, layers, 4)
        local first = at + (free == ramped and ramp or 0) + 2
        coins(s, free, first, fit(first, at + length - 2, 8), layers)
        -- The jump over the crate may land past the terrace's end.
        return math.max(length, hurdle + track.Landing(s, layers) - at)
    end,
})
