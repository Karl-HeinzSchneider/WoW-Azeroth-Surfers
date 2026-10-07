---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit = track.Add, track.Coins, track.Fit

-- Coins up a ramp from `at` (`layers` high, 4 yards a layer), from layer `layer` on: one a yard
-- into each layer's rise, just over the slope.
local function up(s, lane, at, layer, layers)
    for k = 0, layers - 1 do
        add(s, "coin", lane, at + k * 4 + 1 - 0.16, 0.32, layer + k, 1)
    end
end

-- High ground: a platform 4 or 5 layers up (3 yards at most), coins up its ramp and along the
-- top. Either one long ramp, or two shorter ones with a landing between them: a lower
-- platform 2 layers high, and on it the upper one with a ramp of its own.
track.Register({
    name = "tower",
    weight = { easy = 1, normal = 2, hard = 2, expert = 2 },
    from = 200,
    place = function(s, at, r)
        local lane, layers = r(-1, 1), r(4, 5)
        if r(0, 1) == 1 then
            local ramp = layers * 4
            local length = ramp + r(16, 26)
            add(s, "platform", lane, at, length, 0, layers, ramp)
            up(s, lane, at, 0, layers)
            local first = at + ramp + 2
            coins(s, lane, first, fit(first, at + length - 2, 6), layers)
            return length
        end
        local low, high = 2, layers - 2
        local landing = at + low * 4
        local upper = landing + r(8, 12)
        local top = upper + high * 4
        local finish = top + r(14, 22)
        add(s, "platform", lane, at, finish - at, 0, low, low * 4)
        add(s, "platform", lane, upper, finish - upper, low, high, high * 4)
        up(s, lane, at, 0, low)
        coins(s, lane, landing + 2, fit(landing + 2, upper - 2, 3), low)
        up(s, lane, upper, low, high)
        coins(s, lane, top + 2, fit(top + 2, finish - 2, 6), layers)
        return finish - at
    end,
})
