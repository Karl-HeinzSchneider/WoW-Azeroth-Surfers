---@type string, Surfer
local _, app = ...
-- Fixed-step rules on a grid: three lanes side by side and layers stacked LAYER yards high.
-- Everything on the track is a box on that grid, so one overlap test serves every kind, and
-- the rules are independent of how the views draw them.
local game = {}
app.simulation = game

-- A jump (about 1.64 yards) reaches a little past layer 2.
game.LAYER = 0.6
game.geometry = {
    laneWidth = 2.4,
    playerHalfWidth = 0.22,
    playerHalfDepth = 0.15,
    -- The runner's body is three layers tall: a barrier on layer 3 can be run under.
    playerHeight = 1.8,
    -- Half widths by kind: obstacles leave room to squeeze past, platforms fill their lane.
    halfWidth = { obstacle = 0.65, barrier = 1.1, platform = 1.05, coin = 0.16 },
    -- The drawn size of a coin; it collects anywhere in its layer.
    coinSize = 0.5,
}
local bounds = game.geometry
local L = game.LAYER

-- A box: `lane`; `at`, its near end, and `length` in yards along the track; `layer`, its
-- bottom, and `layers`, its height, in layers. Kinds: "obstacle" and "barrier" end the run on
-- contact, a "coin" is collected, a "platform" can be walked on and is a wall below its top;
-- its first `ramp` yards rise from its bottom to its top.
function game.Box(kind, lane, at, length, layer, layers, ramp)
    return { kind = kind, lane = lane, at = at, length = length, layer = layer, layers = layers, ramp = ramp }
end

-- The box's top in yards; along a ramp, its height at track distance `at`.
function game.Top(o, at)
    local bottom, top = o.layer * L, (o.layer + o.layers) * L
    if o.ramp and at and at < o.at + o.ramp then
        return bottom + (top - bottom) * math.max(0, at - o.at) / o.ramp
    end
    return top
end

local function sideBySide(s, o)
    return math.abs(o.lane - s.lateral) * bounds.laneWidth < bounds.playerHalfWidth + bounds.halfWidth[o.kind]
end

local function alongside(s, o)
    return s.distance + bounds.playerHalfDepth > o.at and s.distance - bounds.playerHalfDepth < o.at + o.length
end

-- Whether the runner's body overlaps the box (for platforms, its full height). Boxes that only
-- touch, like a body three layers tall under a barrier on layer 3, do not overlap.
local EPSILON = 1e-6
function game.Overlaps(s, o)
    return sideBySide(s, o)
        and alongside(s, o)
        and s.height < game.Top(o) - EPSILON
        and s.height + bounds.playerHeight > o.layer * L + EPSILON
end

local STEP = 1 / 120
-- WoW's own jump (yards, seconds), so the road drops in step with the real character.
local JUMP_VELOCITY, GRAVITY = 7.955716, 19.291105
-- How high the runner steps up without jumping: ramps, and landings just short of a top.
local STEP_UP = 0.25

function game.New(random)
    return {
        status = "ready",
        lane = 0,
        lateral = 0,
        height = 0,
        floor = 0,
        velocity = 0,
        distance = 0,
        forward = false,
        coins = 0,
        speed = 30,
        accumulator = 0,
        nextRow = 22,
        objects = {},
        random = random or math.random,
    }
end

function game.Score(s)
    return math.floor(s.distance) + s.coins * 25
end

function game.Start(s)
    if s.status == "ready" then
        s.status = "running"
    end
end

function game.Move(s, delta)
    if s.status == "running" then
        s.lane = math.max(-1, math.min(1, s.lane + delta))
    end
end

-- Only from a floor: the ground or a platform's top.
function game.Jump(s)
    if s.status == "running" and s.velocity == 0 and s.height <= s.floor then
        s.velocity = JUMP_VELOCITY
    end
end

function game.Pause(s)
    if s.status == "running" then
        s.status = "paused"
    elseif s.status == "paused" then
        s.status = "running"
    end
    s.accumulator = 0
end

local function add(s, kind, lane, at, length, layer, layers, ramp)
    s.objects[#s.objects + 1] = game.Box(kind, lane, at, length, layer, layers, ramp)
end

-- Yards between coins in a row: close enough to read as a trail, far enough apart that
-- distant coins do not merge.
local COIN_SPACING = 3

-- `count` coins in `lane` on `layer`, one every COIN_SPACING yards from `at`.
local function coins(s, lane, at, count, layer)
    for i = 0, count - 1 do
        add(s, "coin", lane, at + i * COIN_SPACING - 0.16, 0.32, layer, 1)
    end
end

-- How many coins fit in a row from `from` to `to`, at most `most`.
local function fit(from, to, most)
    return math.max(0, math.min(most, math.floor((to - from) / COIN_SPACING) + 1))
end

-- Each pattern places its boxes around `at` and returns where its last box ends, relative to
-- `at`; coins may lead in up to 8 yards before it, less than the gap between patterns. Every
-- pattern leaves a lane that can be run, jumped or climbed through.
local patterns = {
    -- One lane blocked low enough to jump, coins in another.
    function(s, at, r)
        local blocked = r(-1, 1)
        add(s, "obstacle", blocked, at, 0.5, 0, r(1, 2))
        coins(s, (blocked + 2) % 3 - 1, at - 4, 5, 0)
        return 4 * COIN_SPACING - 4
    end,
    -- A hurdle under an arc of coins that only a jump collects.
    function(s, at, r)
        local lane = r(-1, 1)
        add(s, "obstacle", lane, at, 0.5, 0, 1)
        -- Centred over the hurdle.
        for i, layer in ipairs({ 3, 4, 5, 5, 4, 3 }) do
            add(s, "coin", lane, at + 0.25 + (i - 3.5) * COIN_SPACING - 0.16, 0.32, layer, 1)
        end
        return 8
    end,
    -- A tall wall to dodge beside a hurdle to jump; the third lane is clear.
    function(s, at, r)
        local tall = r(-1, 1)
        local low = (tall + 1 + r(1, 2)) % 3 - 1
        add(s, "obstacle", tall, at, 0.8, 0, 4)
        add(s, "obstacle", low, at, 0.5, 0, 1)
        coins(s, -tall - low, at - 4, 4, 0)
        return 3 * COIN_SPACING - 4
    end,
    -- Overhead barriers on layer 3: run under them, do not jump.
    function(s, at, r)
        local first = r(-1, 1)
        local last = r(first, 1)
        for lane = first, last do
            add(s, "barrier", lane, at, 0.4, 3, 1)
        end
        coins(s, first, at - 2, 3, 0)
        return 2 * COIN_SPACING - 2
    end,
    -- Higher ground: a platform (with a ramp when too high to jump onto), coins and maybe an
    -- obstacle on top, sometimes a higher platform beside it to jump across to.
    function(s, at, r)
        local lane, layers = r(-1, 1), r(1, 3)
        local ramp = (layers == 3 or r(0, 1) == 1) and layers * 4 or nil
        local length = r(24, 40)
        add(s, "platform", lane, at, length, 0, layers, ramp)
        -- Coins on top, from past the ramp to short of the end.
        local first = at + (ramp or 0) + 2
        local count = fit(first, at + length - 2, 6)
        coins(s, lane, first, count, layers)
        -- Past the coins, with room to land before the platform ends.
        if r(0, 1) == 1 and at + length - 6 > first + (count - 1) * COIN_SPACING + 3 then
            add(s, "obstacle", lane, at + length - 6, 0.5, layers, 1)
        end
        if layers < 3 and r(0, 1) == 1 then
            local beside = lane == 0 and (r(0, 1) == 0 and -1 or 1) or 0
            add(s, "platform", beside, at + 10, length - 10, 0, layers + 1)
            coins(s, beside, at + 14, fit(at + 14, at + length - 2, 6), layers + 1)
        end
        return length
    end,
}

local function spawn(s)
    local r = s.random
    s.nextRow = s.nextRow + patterns[r(1, #patterns)](s, s.nextRow, r) + r(10, 16)
end

local function tick(s)
    s.speed = math.min(42, 30 + s.distance / 180)
    if s.forward then
        s.distance = s.distance + s.speed * STEP
    end
    local delta = s.lane - s.lateral
    s.lateral = s.lateral + math.max(-STEP * 7, math.min(STEP * 7, delta))
    -- The floor is the highest top under the runner it can step onto; a higher one is a wall.
    local floor = 0
    for _, o in ipairs(s.objects) do
        if o.kind == "platform" and sideBySide(s, o) and alongside(s, o) then
            local top = game.Top(o, s.distance + bounds.playerHalfDepth)
            if top > s.height + STEP_UP then
                s.status = "over"
                return
            end
            floor = math.max(floor, top)
        end
    end
    s.floor = floor
    if s.velocity > 0 or s.height > floor then
        s.height = s.height + s.velocity * STEP - GRAVITY / 2 * STEP * STEP
        s.velocity = s.velocity - GRAVITY * STEP
        if s.height <= floor then
            s.height, s.velocity = floor, 0
        end
    else
        s.height, s.velocity = floor, 0
    end
    while s.nextRow < s.distance + 85 do
        spawn(s)
    end
    for i = #s.objects, 1, -1 do
        local o = s.objects[i]
        if not o.hit and o.kind ~= "platform" and game.Overlaps(s, o) then
            if o.kind == "coin" then
                o.hit = true
                s.coins = s.coins + 1
            else
                s.status = "over"
                return
            end
        end
        if o.at + o.length < s.distance - 4 then
            table.remove(s.objects, i)
        end
    end
end

function game.Update(s, elapsed)
    if s.status ~= "running" then
        return
    end
    -- Client stalls lose time rather than teleporting the runner into obstacles.
    s.accumulator = s.accumulator + math.min(elapsed, 0.1)
    while s.accumulator >= STEP and s.status == "running" do
        s.accumulator = s.accumulator - STEP
        tick(s)
    end
end
