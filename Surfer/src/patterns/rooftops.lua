---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- Rooftops: two or three platforms in one lane with gaps between them, each a layer higher
-- than the one before (up to 4), the first with a ramp; jump each gap. Coins along every top.
track.Register({
    name = "rooftops",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 200,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), r(1, 2)
        local ramp = layers * 4
        local from, last = at, at
        for i = 1, r(2, 3) do
            local up = i == 1 and ramp or 0
            local length = up + r(12, 18)
            add(s, "platform", lane, from, length, 0, layers, i == 1 and ramp or nil)
            local first = from + up + 2
            coins(s, lane, first, fit(first, from + length - 2, 4), layers)
            last = from + length
            from = last + r(4, 7)
            layers = layers + 1
        end
        return last - at
    end,
})
