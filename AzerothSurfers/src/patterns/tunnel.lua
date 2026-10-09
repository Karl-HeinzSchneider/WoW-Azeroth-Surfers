---@type string, AzerothSurfers
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- A tunnel: one lane covered by beams to run under, every 4 to 6 yards over 20 to 30 yards,
-- coins under them all the way; a jump in there hits one. Somewhere along it a tall wall in
-- both other lanes, one of them sometimes lumber from there to the tunnel's end: past that
-- point the tunnel is the only way.
track.Register({
    name = "tunnel",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 100,
    place = function(s, at, r)
        local lane = r(-1, 1)
        local finish, beam, last = at + r(20, 30), at, at
        while beam <= finish do
            add(s, "barrier", lane, beam, 0.4, 3, 1)
            last = beam
            beam = beam + r(4, 6)
        end
        coins(s, lane, at - 2, fit(at - 2, last, 10), 0)
        local wall = at + r(6, last - at - 4)
        local lumber = r(0, 1) == 1 and (lane == 0 and (r(0, 1) == 0 and -1 or 1) or 0) or nil
        for other = -1, 1 do
            if other == lumber then
                add(s, "platform", other, wall, last + 0.4 - wall, 0, r(4, 5))
            elseif other ~= lane then
                add(s, "obstacle", other, wall, 0.8, 0, 4)
            end
        end
        return last + 0.4 - at
    end,
})
