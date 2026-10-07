---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit, arc = track.Add, track.Coins, track.Fit, track.Arc

-- An enemy up on a platform. Either a wolf or boar to jump on top (coins in an arc over it),
-- or a tall one near the end that the runner must leave the platform for, coins on the top
-- before it.
track.Register({
    name = "guard",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 150,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), r(1, 3)
        local ramp = (layers == 3 or r(0, 1) == 1) and layers * 4 or nil
        local length = r(28, 40)
        add(s, "platform", lane, at, length, 0, layers, ramp)
        local top = at + (ramp or 0)
        local guard = top + r(8, 12)
        if r(0, 1) == 1 then
            add(s, "enemy", lane, guard, 1.2, layers, 2)
            arc(s, lane, guard + 0.6, layers)
            -- The arc may reach past the platform's end.
            return math.max(length, guard + 8.1 - at)
        end
        add(s, "enemy", lane, guard, 0.8, layers, 4)
        local first = top + 2
        coins(s, lane, first, fit(first, guard - 4, 5), layers)
        return length
    end,
})
