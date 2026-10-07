---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins = track.Add, track.Coins

-- A slalom: rows of tall walls in two lanes each, the gap moving to a neighbouring lane every
-- row, half a second apart at the speed of the moment. A coin in every gap.
track.Register({
    name = "slalom",
    weight = { easy = 1, normal = 2, hard = 3, expert = 3 },
    from = 100,
    place = function(s, at, r)
        local rows = r(3, 4)
        local spacing = math.max(9, s.speed * 0.5)
        local gap = r(-1, 1)
        for i = 0, rows - 1 do
            local row = at + i * spacing
            for lane = -1, 1 do
                if lane ~= gap then
                    add(s, "obstacle", lane, row, 0.8, 0, 4)
                end
            end
            coins(s, gap, row + 0.4, 1, 0)
            gap = gap == 0 and (r(0, 1) == 0 and -1 or 1) or 0
        end
        return (rows - 1) * spacing + 1
    end,
})
