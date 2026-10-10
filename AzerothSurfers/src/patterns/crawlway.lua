---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- A crawlway: two or three low beams 3 to 4 yards apart in one lane (a duck or two gets under
-- them all), coins under them all the way. Beside it lumber too high to climb, the third lane
-- open: the crawlway is the way to the coins, not the only way through.
track.Register({
    name = "crawlway",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 150,
    place = function(s, at, r)
        local lane = r(-1, 1)
        local wall = lane == 0 and (r(0, 1) == 0 and -1 or 1) or (r(0, 1) == 0 and 0 or -lane)
        local beam, last = at, at
        for _ = 1, r(2, 3) do
            add(s, "barrier", lane, beam, 0.4, 2, 1)
            last = beam
            beam = beam + r(3, 4)
        end
        local finish = last + 3
        coins(s, lane, at - 2, fit(at - 2, finish, 6), 0)
        add(s, "platform", wall, at, finish - at, 0, r(4, 5))
        return finish - at
    end,
})
