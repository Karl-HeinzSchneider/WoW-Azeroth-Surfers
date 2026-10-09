---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- A fork: the middle lane walled off by lumber too high to climb, the road splitting around it.
-- On one side the high road, a ramp up to a platform 2 or 3 layers high, coins along its top;
-- on the other the low road, beams to run under every 6 to 9 yards, coins under them. Both end
-- with the lumber.
track.Register({
    name = "fork",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 150,
    place = function(s, at, r)
        local length = r(36, 48)
        local finish = at + length
        local high, layers = r(0, 1) == 1 and 1 or -1, r(2, 3)
        local ramp = layers * 4
        add(s, "platform", 0, at, length, 0, r(4, 5))
        add(s, "platform", high, at, length, 0, layers, ramp)
        local first = at + ramp + 2
        coins(s, high, first, fit(first, finish - 2, 10), layers)
        local beam = at + r(4, 8)
        coins(s, -high, beam - 2, fit(beam - 2, finish - 2, 12), 0)
        while beam + 0.4 <= finish do
            add(s, "barrier", -high, beam, 0.4, 3, 1)
            beam = beam + r(6, 9)
        end
        return length
    end,
})
