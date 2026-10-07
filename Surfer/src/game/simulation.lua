---@type string, Surfer
local _, app = ...
local random = app.random
-- Fixed-step rules on a grid: three lanes side by side and layers stacked LAYER yards high.
-- Everything on the track is a box on that grid, so one overlap test serves every kind, and
-- the rules are independent of how the views draw them. A run's track follows only from its
-- seed: the same seed lays out the same track.
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
    halfWidth = { obstacle = 0.65, enemy = 0.6, barrier = 1.1, platform = 1.05, coin = 0.16 },
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
-- Seconds a jump from a floor to the same height lasts.
game.JUMP_TIME = 2 * JUMP_VELOCITY / GRAVITY
-- How high the runner steps up without jumping: ramps, and landings just short of a top.
local STEP_UP = 0.25

-- The difficulties, easiest first; `profile.difficulty` picks one by `id`. Each sets the
-- track's speed (yards per second) at the start and at most, the yards run for each yard per
-- second more (`speedUp`), the seconds of free road between two patterns (`gap`, a range,
-- in yards at the speed of the moment; track.lua), and which patterns come up how often (a
-- pattern's `weight` may differ by difficulty id; src/patterns/).
game.DIFFICULTIES = {
    { id = "easy", name = "Easy", startSpeed = 26, topSpeed = 36, speedUp = 240, gap = { 0.45, 0.7 } },
    { id = "normal", name = "Normal", startSpeed = 30, topSpeed = 42, speedUp = 180, gap = { 1 / 3, 0.53 } },
    { id = "hard", name = "Hard", startSpeed = 34, topSpeed = 48, speedUp = 150, gap = { 0.3, 0.46 } },
    { id = "expert", name = "Expert", startSpeed = 38, topSpeed = 54, speedUp = 120, gap = { 0.27, 0.4 } },
}
for level, difficulty in ipairs(game.DIFFICULTIES) do
    difficulty.level = level
    game.DIFFICULTIES[difficulty.id] = difficulty
end
-- The track speed the twin's run animation is paced for (overlay.lua): faster legs above it.
game.RUN_PACE = game.DIFFICULTIES.normal.startSpeed

-- A run from `seed` (any whole number), or from a new one when left out, at difficulty
-- `difficulty` (an id; normal when left out or unknown).
function game.New(seed, difficulty)
    seed = random.Normalize(seed or random.Seed())
    difficulty = game.DIFFICULTIES[difficulty] or game.DIFFICULTIES.normal
    return {
        difficulty = difficulty,
        seed = seed,
        status = "ready",
        lane = 0,
        lateral = 0,
        height = 0,
        floor = 0,
        velocity = 0,
        distance = 0,
        forward = false,
        coins = 0,
        -- The score so far: distance points (fractional) and coin points, each earned at the
        -- multiplier of its moment.
        points = 0,
        bonus = 0,
        multiplier = 1,
        speed = difficulty.startSpeed,
        accumulator = 0,
        nextRow = 22,
        objects = {},
        random = random.New(seed, random.TRACK),
    }
end

-- Points for a coin, at multiplier 1; a yard run is one point.
local COIN_POINTS = 25

function game.Score(s)
    return math.floor(s.points) + s.bonus
end

-- Scores everything from now on `multiplier` times (a whole number, at least 1), e.g. for a
-- special event; the score earned so far stays.
function game.SetMultiplier(s, multiplier)
    s.multiplier = math.max(1, math.floor(multiplier))
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

local function tick(s)
    local difficulty = s.difficulty
    s.speed = math.min(difficulty.topSpeed, difficulty.startSpeed + s.distance / difficulty.speedUp)
    if s.forward then
        local step = s.speed * STEP
        s.distance = s.distance + step
        s.points = s.points + step * s.multiplier
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
    -- The track ahead: patterns (track.lua) up to this far.
    while s.nextRow < s.distance + 85 do
        game.Spawn(s)
    end
    for i = #s.objects, 1, -1 do
        local o = s.objects[i]
        if not o.hit and o.kind ~= "platform" and game.Overlaps(s, o) then
            if o.kind == "coin" then
                o.hit = true
                s.coins = s.coins + 1
                s.bonus = s.bonus + COIN_POINTS * s.multiplier
            elseif not game.invincible then
                -- `invincible`: Surfer_Dev's /surfer god.
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
