---@type string, AzerothSurfers
local _, app = ...
local random = app.random
-- Fixed-step rules on a grid of three lanes and layers LAYER yards high. Everything on the track
-- is a box on that grid, so one overlap test serves every kind. A run's track follows only from
-- its seed.
local game = {}
app.simulation = game

-- A jump (about 1.64 yards) reaches a little past layer 2.
game.LAYER = 0.6
game.geometry = {
    laneWidth = 2.4,
    playerHalfWidth = 0.22,
    playerHalfDepth = 0.15,
    playerHeight = 1.8, -- three layers: a barrier on layer 3 can be run under
    halfWidth = { obstacle = 0.65, enemy = 0.6, barrier = 1.1, platform = 1.05, coin = 0.16 },
    coinSize = 0.5, -- drawn; it collects anywhere in its layer
}
local bounds = game.geometry
local L = game.LAYER

-- `at` (near end) and `length` in yards; `layer` (bottom) and `layers` (height) in layers.
-- "obstacle", "enemy" and "barrier" end the run on contact, a "coin" is collected, a "platform"
-- is walked on and a wall below its top; its first `ramp` yards rise to its top.
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

-- Boxes that only touch (a body three layers tall under a barrier on layer 3) do not overlap.
local EPSILON = 1e-6
function game.Overlaps(s, o)
    return sideBySide(s, o)
        and alongside(s, o)
        and s.height < game.Top(o) - EPSILON
        and s.height + bounds.playerHeight > o.layer * L + EPSILON
end

local STEP = 1 / 120
-- Yards ahead the views show anything. The track is laid out further, so nothing comes into
-- sight before it exists, nor before a gate that a roadside group placed there could reach.
game.VIEW = 140
game.AHEAD = game.VIEW + 20
-- WoW's own jump (yards, seconds), so the road drops in step with the real character.
local JUMP_VELOCITY, GRAVITY = 7.955716, 19.291105
-- Seconds a jump from a floor to the same height lasts.
game.JUMP_TIME = 2 * JUMP_VELOCITY / GRAVITY
-- How high the runner steps up without jumping: ramps, and landings just short of a top.
local STEP_UP = 0.25
-- Seconds of empty road, at the difficulty's start speed, from where the player takes over to
-- the first pattern: a new run's start, and past the lobby's gate.
game.CLEAR = 2

-- Easiest first. Speeds in yards per second; `speedUp`: yards run per yard per second more;
-- `gap`: seconds of free road between patterns (track.lua). A pattern's `weight` may differ by
-- difficulty id.
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
-- The speed the twin's run animation is paced for (overlay.lua).
game.RUN_PACE = game.DIFFICULTIES.normal.startSpeed

-- With `zones` (auto biome), a zone ends at a gate (patterns/gate.lua) every ZONE_LENGTH yards
-- (a range, from random.GATES). `s.gates` lists where the zones after the first start; a run
-- from the lobby has its gate first, with zones or without.
game.ZONE_LENGTH = { 1500, 2500 }

function game.ZoneLength(s)
    local from, to = game.ZONE_LENGTH[1], game.ZONE_LENGTH[2]
    return from + s.gateRandom() * (to - from)
end

-- `seed`: any whole number, a new one when nil; `difficulty`: an id, normal when nil or unknown.
-- `lobby` (src/scenes/lobby.lua): the run starts in its lane, with a gate at its `rim`.
function game.New(seed, difficulty, zones, lobby)
    seed = random.Normalize(seed or random.Seed())
    difficulty = game.DIFFICULTIES[difficulty] or game.DIFFICULTIES.normal
    local s = {
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
        coinTotal = 0, -- coins come past, collected or missed
        -- Coins collected one right after another (game.STREAK), and where the last one was.
        streak = 0,
        streakAt = 0,
        bestStreak = 0,
        -- Distance points (fractional) and coin points, each at the multiplier of its moment.
        points = 0,
        bonus = 0,
        multiplier = 1,
        speed = difficulty.startSpeed,
        accumulator = 0,
        nextRow = difficulty.startSpeed * game.CLEAR,
        objects = {},
        random = random.New(seed, random.TRACK),
    }
    if zones then
        s.zones, s.gates, s.gateRandom = true, {}, random.New(seed, random.GATES)
        s.nextGate = game.ZoneLength(s)
    end
    if lobby then
        s.lobby, s.gates = lobby, s.gates or {}
        s.lane, s.lateral = lobby.lane, lobby.lane
        -- It starts at `launch.speed` and speeds up to the difficulty's (tick).
        local launch = lobby.launch
        if launch then
            s.speed, s.launch = launch.speed, launch.speed
            s.launchRate = (difficulty.startSpeed - launch.speed) / launch.seconds
        end
        app.track.Lobby(s, lobby)
    end
    return s
end

-- At multiplier 1; a yard run is one point.
local COIN_POINTS = 25

-- A streak: coins collected one right after another. A coin missed beside it (a parallel row)
-- does not break it, running on too far without one does:
--   gap      yards from one collected coin to the next that keep a streak (6: one empty spot
--            in a row)
--   seconds  or that long at the speed of the moment, if further (a change of lanes or two)
--   from     the streak's length from which every coin scores `points` more, at the multiplier
-- AzerothSurfers_Dev's /surfers streak changes them while playing.
game.STREAK = { gap = 7, seconds = 0.35, from = 7, points = 25 }

-- Yards past the last collected coin a streak holds at the speed of the moment.
function game.StreakReach(s)
    local streak = game.STREAK
    return math.max(streak.gap, streak.seconds * s.speed)
end

function game.Score(s)
    return math.floor(s.points) + s.bonus
end

-- Scales only what is earned from now on.
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
    -- A run from the lobby speeds up from its launch speed first.
    if s.launch then
        if s.launch < s.speed then
            s.speed, s.launch = s.launch, s.launch + s.launchRate * STEP
        else
            s.launch = nil
        end
    end
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
    while s.nextRow < s.distance + game.AHEAD do
        game.Spawn(s)
    end
    if s.streak > 0 and s.distance > s.streakAt + game.StreakReach(s) then
        s.streak = 0
    end
    for i = #s.objects, 1, -1 do
        local o = s.objects[i]
        if not o.hit and o.kind ~= "platform" and game.Overlaps(s, o) then
            if o.kind == "coin" then
                o.hit = true
                s.coins = s.coins + 1
                s.streak, s.streakAt = s.streak + 1, s.distance
                s.bestStreak = math.max(s.bestStreak, s.streak)
                local points = COIN_POINTS
                if s.streak >= game.STREAK.from then
                    points = points + game.STREAK.points
                end
                s.bonus = s.bonus + points * s.multiplier
            elseif not game.invincible then -- AzerothSurfers_Dev's /surfers god
                s.status = "over"
                return
            end
        end
        -- A coin counts once collected, or once the runner is past it.
        if o.kind == "coin" and not o.passed and (o.hit or o.at + o.length < s.distance - bounds.playerHalfDepth) then
            o.passed = true
            s.coinTotal = s.coinTotal + 1
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
