---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- Stairs across the lanes: three platforms side by side, each a layer higher than the one
-- before and starting later, all ending together; climbed by jumping across from step to
-- step. The first is low enough to jump onto, the higher ones are walls from the ground.
-- Coins on each step, and sometimes a wolf near the top step's end to jump.
track.Register({
    name = "stairs",
    weight = { easy = 1, normal = 2, hard = 3, expert = 3 },
    from = 100,
    place = function(s, at, r)
        local side = r(0, 1) == 1 and 1 or -1
        local base = r(1, 2)
        -- Time to land on a step and jump across to the next.
        local step = math.max(10, s.speed * 0.5)
        local finish = at + 2 * step + r(14, 22)
        local guarded = r(0, 1) == 1
        for k = 0, 2 do
            local lane, from, layers = (k - 1) * side, at + k * step, base + k
            add(s, "platform", lane, from, finish - from, 0, layers)
            -- On a step's own stretch, before the next one starts; the top step's to its end,
            -- or to short of its wolf.
            local first = from + 2
            local last = k < 2 and from + step - 2 or finish - (guarded and 10 or 2)
            coins(s, lane, first, fit(first, last, 6), layers)
        end
        if guarded then
            add(s, "enemy", side, finish - 6, 1.2, base + 2, 2)
        end
        return finish - at
    end,
})
