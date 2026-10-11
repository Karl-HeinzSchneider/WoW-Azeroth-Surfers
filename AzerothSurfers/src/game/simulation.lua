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
-- Passed boxes and missed coins remain available beyond the maximum 24-yard camera distance.
game.VIEW_BEHIND = 32
game.geometry = {
    laneWidth = 2.4,
    playerHalfWidth = 0.22,
    playerHalfDepth = 0.15,
    playerHeight = 1.8, -- three layers: a barrier on layer 3 can be run under
    duckHeight = 1.2, -- two layers, while ducking (game.Duck)
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

-- The runner's height in yards: shorter while ducking.
function game.BodyHeight(s)
    return s.duck > 0 and bounds.duckHeight or bounds.playerHeight
end

-- Boxes that only touch (a body three layers tall under a barrier on layer 3) do not overlap.
local EPSILON = 1e-6
function game.Overlaps(s, o)
    return sideBySide(s, o)
        and alongside(s, o)
        and s.height < game.Top(o) - EPSILON
        and s.height + game.BodyHeight(s) > o.layer * L + EPSILON
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
-- Seconds a duck lasts, and how fast (yards per second) ducking in the air pulls the runner down.
game.DUCK_TIME = 0.6
local DIVE_VELOCITY = 2 * JUMP_VELOCITY
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

-- A run with a `finish` (a challenge's) ends FINISH_PAST yards past the last portal's rim: the
-- runner goes through it, and a camera close behind too. Its yards and points count up to the
-- rim.
game.FINISH_PAST = 18

-- `seed`: any whole number, a new one when nil; `difficulty`: an id, normal when nil or unknown.
-- `lobby` (src/scenes/lobby.lua): the run starts in its lane, with a gate at its `rim`.
-- `goal`: yards from where the run starts counting to its last portal (`finish`, a track
-- distance; track.lua lays nothing out past it), none when nil.
-- `scoring`: a game mode's scoring rules over scoring.lua's DEFAULTS (`s.scoring`), none when nil.
function game.New(seed, difficulty, zones, lobby, goal, scoring)
    seed = random.Normalize(seed or random.Seed())
    difficulty = game.DIFFICULTIES[difficulty] or game.DIFFICULTIES.normal
    scoring = app.scoring.Rules(scoring)
    local s = {
        difficulty = difficulty,
        seed = seed,
        scoring = scoring,
        -- What the score is everything earned times (scoring.lua's `difficulty`).
        scoreFactor = app.scoring.Factor(scoring, difficulty),
        status = "ready",
        lane = 0,
        lateral = 0,
        height = 0,
        floor = 0,
        velocity = 0,
        contacts = 0, -- takeoffs, landings and grounded rolls; consumed by the view
        -- Seconds of ducking left; `diving`: ducked in the air, ducks on landing.
        duck = 0,
        diving = false,
        distance = 0,
        forward = false,
        -- Where the run starts counting: nothing before it scores (a run from the lobby: where
        -- the player takes over, track.Lobby). `Run` is how far from there.
        start = 0,
        coins = 0,
        coinTotal = 0, -- coins come past, collected or missed
        collected = 0, -- coins picked up, before `start` too (their sound)
        -- Coins collected one right after another (the rules' `streak`), and where the last was.
        streak = 0,
        streakAt = 0,
        bestStreak = 0,
        -- Distance points (fractional) and coin points, each at the multiplier of its moment,
        -- before the difficulty's factor (Score).
        points = 0,
        bonus = 0,
        -- More for every gate gone through past `start` (the rules' `multiplier`).
        multiplier = scoring.multiplier.start,
        gatesPassed = 0, -- of `gates`, those the runner is past
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
    if goal then
        s.finish = s.start + goal
    end
    return s
end

-- Yards past the last collected coin a streak holds at the speed of the moment.
function game.StreakReach(s)
    local streak = s.scoring.streak
    return math.max(streak.gap, streak.seconds * s.speed)
end

-- Everything earned, times the difficulty's factor (scoring.lua).
function game.Score(s)
    return math.floor((s.points + s.bonus) * s.scoreFactor)
end

-- Yards run since the run started counting (`start`), up to its `finish` at most.
function game.Run(s)
    return math.max(0, math.min(s.distance, s.finish or math.huge) - s.start)
end

-- Scales only what is earned from now on; from 1 up to the rules' `most`.
function game.SetMultiplier(s, multiplier)
    s.multiplier = math.max(1, math.min(s.scoring.multiplier.most, math.floor(multiplier)))
end

-- Each gate into the next zone adds the rules' `perGate` to the multiplier. A gate before
-- `start` (the lobby's) adds nothing: a run from the lobby counts as a restart does; nor does
-- the last portal, `finish`.
local function passGates(s)
    local gates, k = s.gates, s.gatesPassed + 1
    while gates[k] and gates[k] <= s.distance do
        if gates[k] > s.start and gates[k] ~= s.finish then
            game.SetMultiplier(s, s.multiplier + s.scoring.multiplier.perGate)
        end
        s.gatesPassed, k = k, k + 1
    end
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

-- Remember the surface at contact, even if this frame then moves beyond it.
local function contact(s)
    s.contacts = s.contacts + 1
    s.contactFloor, s.contactAt = s.floor, s.distance
end

-- Only from a floor: the ground or a platform's top. It ends a duck.
function game.Jump(s)
    if s.status == "running" and s.velocity == 0 and s.height <= s.floor then
        contact(s)
        s.velocity = JUMP_VELOCITY
        s.duck, s.diving = 0, false
    end
end

-- On a floor, the runner ducks for DUCK_TIME (again from the start while ducking); in the air
-- it drops fast and ducks on landing.
function game.Duck(s)
    if s.status ~= "running" then
        return
    end
    if s.velocity == 0 and s.height <= s.floor then
        if s.duck == 0 then
            contact(s)
        end
        s.duck = game.DUCK_TIME
    else
        s.velocity = math.min(s.velocity, -DIVE_VELOCITY)
        s.diving = true
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

-- One step's speed and distance. The track ahead is laid out at the speed of the moment, so
-- game.Skip takes the very same steps.
local function move(s)
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
        local counted = math.min(step, s.distance - s.start)
        if s.finish then
            counted = math.min(counted, s.finish - s.distance + step)
        end
        if counted > 0 then
            s.points = s.points + counted * s.scoring.yardPoints * s.multiplier
        end
        if s.gates then
            passGates(s)
        end
    end
end

local function tick(s)
    move(s)
    if s.finish and s.distance >= s.finish + game.FINISH_PAST then
        s.status, s.finished = "over", true
        return
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
    if s.duck > 0 then
        s.duck = math.max(0, s.duck - STEP)
    end
    if s.velocity > 0 or s.height > floor then
        s.height = s.height + s.velocity * STEP - GRAVITY / 2 * STEP * STEP
        s.velocity = s.velocity - GRAVITY * STEP
        if s.height <= floor then
            s.height, s.velocity = floor, 0
            contact(s)
            if s.diving then
                s.duck, s.diving = game.DUCK_TIME, false
            end
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
                s.collected = s.collected + 1
                if s.distance >= s.start then
                    s.coins = s.coins + 1
                    s.streak, s.streakAt = s.streak + 1, s.distance
                    s.bestStreak = math.max(s.bestStreak, s.streak)
                    local rules = s.scoring
                    local points = rules.coinPoints
                    if s.streak >= rules.streak.from then
                        points = points + rules.streak.points
                    end
                    s.bonus = s.bonus + points * s.multiplier
                end
            elseif not game.invincible then -- AzerothSurfers_Dev's /surfers god
                s.status = "over"
                return
            end
        end
        -- A coin counts once collected, or once the runner is past it; none before `start`.
        if o.kind == "coin" and not o.passed and (o.hit or o.at + o.length < s.distance - bounds.playerHalfDepth) then
            o.passed = true
            if s.distance >= s.start then
                s.coinTotal = s.coinTotal + 1
            end
        end
        local behind = (o.kind ~= "coin" or not o.hit) and game.VIEW_BEHIND or 4
        if o.at + o.length < s.distance - behind then
            table.remove(s.objects, i)
        end
    end
end

-- A seed's run from the lobby (game.New with `lobby`, not started yet) begun `to` yards into
-- it instead, past the lobby's portal at the least: the track up to there is laid out as
-- running it from the menu lays it out (its launch and gate too), then dropped up to the first
-- pattern game.CLEAR seconds (at the difficulty's start speed) past `to`; the runner starts
-- there on empty road, in the middle lane. From that pattern on the track is the seed's own, the
-- same as from the menu. A gate in the dropped stretch is still a zone's end, without its step.
-- It scores from there on, at the multiplier its gates gave; past the portal it saves no best
-- score (`practice`). `fromLobby`: the lobby it no longer has, for the route of its zones.
-- The furthest a run starts (yards): every yard up to it is stepped through at once.
game.MAX_START = 100000
function game.Skip(s, to)
    local lobby = s.lobby
    if s.status ~= "ready" or not lobby then
        return
    end
    local practice = to and to > s.start and to or nil
    to = math.max(to or 0, s.start)
    local starts = {}
    s.forward = true
    while s.distance < to do
        move(s)
        while s.nextRow < s.distance + game.AHEAD do
            starts[#starts + 1] = s.nextRow
            game.Spawn(s)
        end
    end
    s.forward = false
    -- The first pattern far enough ahead (the next one to be laid out, if none is yet). Past the
    -- portal, the lobby's own first one: track.Lobby puts it just that far on.
    local clear, first = to + s.difficulty.startSpeed * game.CLEAR, s.nextRow
    for i = #starts, 1, -1 do
        if starts[i] < clear then
            break
        end
        first = starts[i]
    end
    -- Patterns are MIN_GAP apart, more than coins lead in (track.lua): this cuts between two.
    local kept = {}
    for _, o in ipairs(s.objects) do
        if o.at >= first - app.track.LEAD_IN then
            kept[#kept + 1] = o
        end
    end
    s.objects = kept
    s.lobby, s.fromLobby, s.launch = nil, lobby, nil
    s.lane, s.lateral = 0, 0
    s.start, s.points, s.practice = s.distance, 0, practice
    -- With a `finish`, the yards to it stay its goal: counted from `to`, as from the menu.
    if s.finish then
        s.start, s.points = to, (s.distance - to) * s.scoring.yardPoints
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
