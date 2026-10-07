---@type string, Surfer
local _, app = ...
local track = app.track
local add, coins, fit, arc = track.Add, track.Coins, track.Fit, track.Arc

-- Coins up a ramp from `at` (`layers` high, 4 yards a layer), from layer `layer` on: one a yard
-- into each layer's rise, just over the slope.
local function up(s, lane, at, layer, layers)
    for k = 0, layers - 1 do
        add(s, "coin", lane, at + k * 4 + 1 - 0.16, 0.32, layer + k, 1)
    end
end

-- What a lane beside the tower gets, by weight: crates to jump, beams to run under, lumber
-- walling it off, a trap, or nothing. A list: the order of a roll must not change, or a seed
-- would lay out another track.
local BESIDE = { { "hurdles", 2 }, { "beams", 2 }, { "wall", 2 }, { "trap", 1 }, { "open", 1 } }
local BESIDE_TOTAL = 8

-- A lane beside the tower, from `at` to `finish`, the tower's top reached at `top` (from there
-- on, the tower's side is too high to get onto).
--   hurdles  crates to jump, a jump's length and more apart, each under an arc of coins
--   beams    beams to run under, every 8 to 12 yards, coins under the first
--   wall     lumber too high to climb beside the top: the lane ends where the climb tops out
--   trap     a row of coins as bait into a tall enemy waiting a little past the top: a dead
--            end for whoever followed them instead of climbing
local function beside(s, r, lane, at, top, finish)
    local roll, kind = r() * BESIDE_TOTAL, "open"
    for _, entry in ipairs(BESIDE) do
        roll = roll - entry[2]
        if roll < 0 then
            kind = entry[1]
            break
        end
    end
    if kind == "hurdles" then
        local hurdle = at + r(4, 10)
        while hurdle + 8 <= finish do
            add(s, "obstacle", lane, hurdle, 0.5, 0, r(1, 2))
            arc(s, lane, hurdle + 0.25)
            hurdle = hurdle + track.JumpLength(s) + r(3, 6)
        end
    elseif kind == "beams" then
        local beam = at + r(6, 10)
        coins(s, lane, beam - 3, 3, 0)
        while beam + 0.4 <= finish do
            add(s, "barrier", lane, beam, 0.4, 3, 1)
            beam = beam + r(8, 12)
        end
    elseif kind == "wall" then
        add(s, "platform", lane, top, finish - top, 0, r(4, 5))
    elseif kind == "trap" then
        local enemy = top + r(4, 10)
        coins(s, lane, at + 2, fit(at + 2, enemy - 4, 8), 0)
        add(s, "enemy", lane, enemy, 0.8, 0, 4)
    end
end

-- High ground: a platform 4 or 5 layers up (3 yards at most), coins up its ramp and along the
-- top, and something in each lane beside it (`beside`). Either one long ramp, or two shorter
-- ones with a landing between them: a lower platform 2 layers high, and on it the upper one
-- with a ramp of its own.
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
            for other = -1, 1 do
                if other ~= lane then
                    beside(s, r, other, at, at + ramp, at + length)
                end
            end
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
        for other = -1, 1 do
            if other ~= lane then
                beside(s, r, other, at, top, finish)
            end
        end
        return finish - at
    end,
})
