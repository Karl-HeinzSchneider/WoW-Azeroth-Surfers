---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit, arc = track.Add, track.Coins, track.Fit, track.Arc

-- A bridge: one lane climbs a ramp to a long platform 3 layers up, the other two walled off by
-- lumber too high to climb from the ramp's top to the bridge's end. On it one or two wolves (or
-- boars) to jump, a jump's length and more apart, each under an arc of coins; coins along the
-- stretch before them.
track.Register({
    name = "bridge",
    weight = { easy = 1, normal = 1, hard = 2, expert = 2 },
    from = 150,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), 3
        local top = at + layers * 4
        local beasts = { top + r(14, 20) }
        if r(0, 1) == 1 then
            beasts[2] = beasts[1] + track.JumpLength(s) + r(4, 6)
        end
        -- Room to land on the bridge past the last one.
        local finish = beasts[#beasts] + r(12, 18)
        add(s, "platform", lane, at, finish - at, 0, layers, layers * 4)
        for other = -1, 1 do
            if other ~= lane then
                add(s, "platform", other, top, finish - top, 0, r(4, 5))
            end
        end
        local first = top + 2
        coins(s, lane, first, fit(first, beasts[1] - 9, 4), layers)
        for _, beast in ipairs(beasts) do
            add(s, "enemy", lane, beast, 1.2, layers, 2)
            arc(s, lane, beast + 0.6, layers)
        end
        -- The jump over the last one may land past the bridge's end.
        return math.max(finish, beasts[#beasts] + track.Landing(s, layers)) - at
    end,
})
