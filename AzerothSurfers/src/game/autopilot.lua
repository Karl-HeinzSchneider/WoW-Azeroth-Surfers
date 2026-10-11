---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
local L = sim.LAYER
-- Auto mode's player: a depth-first search on copies of the run, an input every DT seconds,
-- STEPS ahead. It plays the run in `simulation.Update`'s stead, splitting each frame at its
-- input times, so the run follows the plan to the tick. A plan heads for one lane and drops the
-- lane changes, jumps and ducks it can do without while keeping as many coins.
--
-- Copies leave out the run's coins (they would collect them) and never lay out track (it would
-- draw from the run's generator). Every table is reused, so a search allocates nothing. A replan
-- is worked out ahead, a share each frame, from where the plan in play will have the run (see
-- `foresee`), so auto mode has no long frames.
local autopilot = {}
app.autopilot = autopilot

-- 1.4 seconds ahead: within simulation.AHEAD even at the top speed.
local DT, STEPS = 0.05, 28
-- Inputs played from a plan before the next one, as long as it found a way through.
local REPLAN = 5
local BUDGET = 20000
-- How many yards ahead a coin draws the runner to its lane.
local REACH = 25

-- { lane change, action ("jump", "duck" or false) }; `ORDERS[i]` tries input i first, then the
-- rest as listed.
local INPUTS = {
    { 0, false },
    { 0, "jump" },
    { -1, false },
    { 1, false },
    { -1, "jump" },
    { 1, "jump" },
    { 0, "duck" },
}
local ORDERS = {}
for first = 1, #INPUTS do
    local order = { first }
    for i = 1, #INPUTS do
        if i ~= first then
            order[#order + 1] = i
        end
    end
    ORDERS[first] = order
end
local function inputOf(move, action)
    for i, input in ipairs(INPUTS) do
        if input[1] == move and input[2] == action then
            return i
        end
    end
end
local function apply(s, i)
    local input = INPUTS[i]
    if input[1] ~= 0 then
        sim.Move(s, input[1])
    end
    if input[2] == "jump" then
        sim.Jump(s)
    elseif input[2] == "duck" then
        sim.Duck(s)
    end
end

-- The run's coins still to collect, nearest first (`coinCount` of them), and their copies for
-- replays.
local coins, coinCount, coinCopies = {}, 0, {}
local function byAt(a, b)
    if a.at ~= b.at then
        return a.at < b.at
    end
    return a.lane < b.lane
end
local function collectCoins(s)
    for i = #coins, 1, -1 do
        coins[i] = nil
    end
    for _, o in ipairs(s.objects) do
        if o.kind == "coin" and not o.hit and o.at + o.length > s.distance then
            coins[#coins + 1] = o
        end
    end
    table.sort(coins, byAt)
    coinCount = #coins
end

-- The boxes within the plan's reach (`boxes`, `boxCount` of them) and, for replays, copies of
-- the run's coins within it (`coinCopies`, `copyCount`).
local boxes, boxCount, copyCount = {}, 0, 0
-- A copy stepped for DT seconds only meets boxes alongside it on the way (simulation.lua's
-- `alongside`): those it gets, so that each tick tests a few boxes, not every one within reach.
local NEAR = sim.geometry.playerHalfDepth + 0.01
local function nearby(objects, n, list, count, from, to)
    for i = 1, count do
        local o = list[i]
        if o.at < to and o.at + o.length > from then
            n = n + 1
            objects[n] = o
        end
    end
    return n
end
-- Copies the run `s` into `c`, with the boxes (and coin copies, `withCoins`) it meets in the
-- next DT seconds.
local function copy(c, s, withCoins)
    local objects = c.objects
    for k, v in pairs(s) do
        c[k] = v
    end
    c.objects = objects
    local from, to = s.distance - NEAR, s.distance + s.difficulty.topSpeed * (DT + 1 / 60) + NEAR
    local n = nearby(objects, 0, boxes, boxCount, from, to)
    if withCoins then
        n = nearby(objects, n, coinCopies, copyCount, from, to)
    end
    for i = #objects, n + 1, -1 do
        objects[i] = nil
    end
    return c
end
-- The boxes within the plan's reach of the run `s`, `extra` inputs on, for its searches and
-- replays.
local function gather(s, extra)
    local reach = s.distance + s.difficulty.topSpeed * (STEPS + extra) * DT + 2
    boxCount = 0
    for _, o in ipairs(s.objects) do
        if o.kind ~= "coin" and o.at < reach then
            boxCount = boxCount + 1
            boxes[boxCount] = o
        end
    end
    for i = #boxes, boxCount + 1, -1 do
        boxes[i] = nil
    end
end
-- A copy of the run `s` to search or replay from, with fresh copies of the coins within reach
-- (`withCoins`).
local function start(c, s, withCoins)
    copyCount = 0
    if withCoins then
        local reach = s.distance + s.difficulty.topSpeed * STEPS * DT + 2
        for i = 1, coinCount do
            local o = coins[i]
            if o.at >= reach then
                break
            end
            local k = coinCopies[i]
            if not k then
                k = {}
                coinCopies[i] = k
            end
            k.kind, k.lane, k.at, k.length, k.layer, k.layers, k.hit =
                "coin", o.lane, o.at, o.length, o.layer, o.layers, nil
            copyCount = i
        end
    end
    copy(c, s, withCoins)
    c.nextRow = math.huge
    c.coins = 0
    return c
end
-- The search's start, a replay's start, and one branch per depth below it: the search
-- explores one child of a branch at a time.
local root, replayed, branches = { objects = {} }, { objects = {} }, {}
for depth = 1, STEPS do
    branches[depth] = { objects = {} }
end

-- The plan being played: `plan[1..planLength]`, its next input `nextInput`, whether it found a
-- way through all STEPS (`found`), the lane it heads for (`lane`); the run it is for, and the
-- seconds to its next input time (`due`).
local plan, planLength, nextInput, found, lane = {}, 0, 1, false, 0
local current, due = nil, 0
-- The search: the states it has seen (by `key`), the inputs of the branch it is on (`path`),
-- of the one that got furthest (`best`, `deepest` inputs; `spare` keeps another), the states
-- searched (`nodes`), and what it heads for (`aim`).
local seen, path, best, spare = {}, {}, {}, {}
local nodes, deepest = 0, -1
local aim = { lane = 0, prior = false, offset = 0 }

-- The lane a plan heads for: the runner's own (the one it is changing to) while a coin in it is
-- near, else the nearest coin's, else its own again.
local function targetLane(s)
    local nearest
    for i = 1, coinCount do
        local o = coins[i]
        if o.at > s.distance + REACH then
            break
        end
        if o.lane == s.lane then
            return s.lane
        end
        nearest = nearest or o
    end
    return nearest and nearest.lane or s.lane
end

-- The input to try first: the previous plan's at this point while it heads for the same lane,
-- else toward the target lane, with a jump just before a coin in the lane too high to reach
-- from the floor.
local function preferred(c, step)
    local k = aim.offset + step + 1
    if aim.prior and k <= planLength then
        return plan[k]
    end
    local jump = false
    for i = 1, coinCount do
        local o = coins[i]
        if o.at > c.distance + c.speed * 0.15 then
            break
        end
        if o.lane == c.lane and o.at + o.length > c.distance then
            jump = o.layer * L >= c.floor + sim.geometry.playerHeight - 0.01
            break
        end
    end
    return inputOf(aim.lane > c.lane and 1 or aim.lane < c.lane and -1 or 0, jump and "jump" or false)
end

-- A state as a number: the step, lane, lateral place, height, vertical speed and ducking time
-- left, rounded.
local floor = math.floor
local function key(c, step)
    local lateral = floor(c.lateral * 20 + 0.5) + 32
    local height = floor(c.height * 20 + 0.5)
    local velocity = floor(c.velocity * 4 + 0.5) + 128
    return ((((step * 3 + c.lane + 1) * 64 + lateral) * 1024 + height) * 256 + velocity) * 16 + floor(c.duck * 20 + 0.5)
end

-- Replans run in a coroutine (see `think` below), up to `quota` sim.Update calls on copies a
-- frame (`spent` so far). Crates and enemies made narrower for a search (`narrow`) are only so
-- while it runs, never for the run itself.
local spent, quota = 0, math.huge
local widths, crate, enemy = sim.geometry.halfWidth, nil, nil
local narrowed = false
local function narrow(on)
    if on and not narrowed then
        crate, enemy = widths.obstacle, widths.enemy
        widths.obstacle, widths.enemy = 1, 1
    elseif not on and narrowed then
        widths.obstacle, widths.enemy = crate, enemy
    end
    narrowed = on
end
local function work()
    spent = spent + 1
    if spent >= quota then
        local was = narrowed
        narrow(false)
        coroutine.yield(false)
        narrow(was)
    end
end

-- Depth first from branch `c` at `step`: whether it gets through all STEPS.
local function go(c, step)
    if c.status ~= "running" then
        return false
    end
    if step > deepest then
        deepest = step
        for i = 1, step do
            best[i] = path[i]
        end
    end
    if step >= STEPS then
        return true
    end
    nodes = nodes + 1
    if nodes > BUDGET then
        return false
    end
    local k = key(c, step)
    if seen[k] then
        return false
    end
    seen[k] = true
    -- Inputs that change nothing are left out: a jump in the air, a lane past the edge. It only
    -- ducks on the ground (never drops from a jump).
    local grounded = c.velocity == 0 and c.height <= c.floor
    for _, i in ipairs(ORDERS[preferred(c, step)]) do
        local move, action = INPUTS[i][1], INPUTS[i][2]
        if (grounded or not action) and (move == 0 or math.abs(c.lane + move) <= 1) then
            local child = copy(branches[step + 1], c)
            apply(child, i)
            sim.Update(child, DT)
            work()
            path[step + 1] = i
            if go(child, step + 1) then
                return true
            end
        end
    end
    return false
end

-- Searches from the run `s`: whether it found a way through; `best[1..deepest]` holds it, or
-- the way that got furthest.
local function search(s)
    for k in pairs(seen) do
        seen[k] = nil
    end
    nodes, deepest = 0, -1
    return go(start(root, s, false), 0)
end

-- Plays `line[1..length]` on a copy of the run with copies of its coins: how many inputs it
-- lives through and how many coins it collects.
local function replay(s, line, length)
    local c = start(replayed, s, true)
    for k = 1, length do
        if k > 1 then
            copy(c, c, true)
        end
        apply(c, line[k])
        sim.Update(c, DT)
        work()
        if c.status ~= "running" then
            return k - 1, c.coins
        end
    end
    return length, c.coins
end

-- Takes the lane change (`move`) or the jump or duck (`action`) out of input `k`; returns what
-- it was.
local function strip(line, k, move, action)
    local old = line[k]
    local input = INPUTS[old]
    line[k] = inputOf(move and 0 or input[1], not action and input[2] or false)
    return old
end

-- Whether `line` still gets through with at least `most` coins, and how many it collects.
local function keeps(s, line, length, most)
    local lived, collected = replay(s, line, length)
    return lived == length and collected >= most, collected
end

-- A found way without what it does not need: each lane change that the next one undoes, then
-- each lane change and each jump or duck on its own, left out where the way still gets through and
-- collects as many coins.
local function smooth(s, line, length)
    local _, most = replay(s, line, length)
    for k = 1, length do
        local move = INPUTS[line[k]][1]
        if move ~= 0 then
            local back = k + 1
            while back <= length and INPUTS[line[back]][1] == 0 do
                back = back + 1
            end
            if back <= length and INPUTS[line[back]][1] == -move then
                local a, b = strip(line, k, true), strip(line, back, true)
                local ok, collected = keeps(s, line, length, most)
                if ok then
                    most = collected
                else
                    line[k], line[back] = a, b
                end
            end
        end
    end
    for k = 1, length do
        if INPUTS[line[k]][1] ~= 0 then
            local old = strip(line, k, true)
            local ok, collected = keeps(s, line, length, most)
            if ok then
                most = collected
            else
                line[k] = old
            end
        end
        if INPUTS[line[k]][2] then
            local old = strip(line, k, false, true)
            local ok, collected = keeps(s, line, length, most)
            if ok then
                most = collected
            else
                line[k] = old
            end
        end
    end
end

local function adopt(line, length)
    for i = 1, length do
        plan[i] = line[i]
    end
    for i = planLength, length + 1, -1 do
        plan[i] = nil
    end
    planLength, nextInput = length, 1
end

-- A new plan for the run `s` (as it is, or as the plan in play will have it `offset` inputs
-- on), `coins` collected for it: whether it found a way, `best[1..deepest]` (`thought`). Crates
-- and enemies fill their lane for it, so it does not squeeze between two mid lane change; only
-- when that finds no way, at their real widths.
local thought = { found = false, lane = 0 }
local function think(s, offset)
    aim.lane = targetLane(s)
    -- The previous plan goes on while it heads for the same lane.
    aim.prior, aim.offset = found and lane == aim.lane, offset
    narrow(true)
    local through = search(s)
    if through then
        smooth(s, best, deepest)
    end
    narrow(false)
    if not through then
        local wide = deepest
        best, spare = spare, best
        through = search(s)
        if through then
            smooth(s, best, deepest)
        elseif wide >= deepest then
            best, spare, deepest = spare, best, wide
        end
    end
    thought.found, thought.lane = through, aim.lane
end

-- Replans are thought out ahead, in a coroutine given a share each frame: from where the plan in
-- play will have the run by the time it is due (`ahead`, `jobAt` inputs on), so that its
-- searches are spread over the frames before that rather than all in one. `thinking`: a job in
-- hand, `ready`: done.
local ahead = { objects = {} }
local thinker, job, jobAt, thinking, ready = nil, nil, 0, false, false
-- What a replan may take in sim.Update calls on copies, spread over the frames before it is due
-- (at least MIN a frame); the few that take more finish when due.
local SPREAD, MIN = 2000, 50
local function body()
    while true do
        think(job, jobAt)
        coroutine.yield(true)
    end
end
-- Thinks on, up to `limit` more sim.Update calls.
local function resume(limit)
    quota = spent + limit
    local ok, done = coroutine.resume(thinker)
    if not ok then
        narrow(false)
        thinker, thinking = nil, false
        error(done)
    end
    ready = done == true
end
-- A job: replan for the run `s`, `at` inputs into the plan in play. One left half done (for
-- another state, or another run) is dropped with its coroutine.
local function begin(s, at)
    if not ready then
        thinker = nil
    end
    thinker = thinker or coroutine.create(body)
    job, jobAt, spent, thinking, ready = s, at, 0, true, false
end

-- Whether the run is where the job foresaw it (its time to the next tick but for rounding).
local function foreseen(s)
    return thinking
        and jobAt == nextInput - 1
        and s.distance == ahead.distance
        and s.lane == ahead.lane
        and s.lateral == ahead.lateral
        and s.height == ahead.height
        and s.velocity == ahead.velocity
        and s.floor == ahead.floor
        and s.duck == ahead.duck
        and s.diving == ahead.diving
        and s.speed == ahead.speed
        and s.launch == ahead.launch
        and math.abs(s.accumulator - ahead.accumulator) < 1e-9
end

-- Starts thinking about the next replan, from where the plan just adopted will have the run:
-- after REPLAN inputs, or after one if it found no way through.
local function foresee(s)
    local at = found and REPLAN or 1
    if planLength < at then
        return
    end
    collectCoins(s)
    gather(s, at)
    local c = start(ahead, s, true)
    for k = 1, at do
        if k > 1 then
            copy(c, c, true)
        end
        apply(c, plan[k])
        sim.Update(c, DT)
    end
    if c.status ~= "running" then
        return
    end
    -- The coins it collects or passes by then are not ahead of it any more.
    local n = 0
    for i = 1, coinCount do
        local o = coins[i]
        if not (i <= copyCount and coinCopies[i].hit) and o.at + o.length > c.distance then
            n = n + 1
            coins[n] = o
        end
    end
    for i = coinCount, n + 1, -1 do
        coins[i] = nil
    end
    coinCount = n
    begin(c, at)
end

-- The next input, at an input time: from the plan, or from a new one (thought out ahead if the
-- run is where that foresaw it, else now).
local function decide(s)
    if not found or nextInput > REPLAN or nextInput > planLength then
        if not foreseen(s) then
            collectCoins(s)
            gather(s, 0)
            begin(s, nextInput - 1)
        end
        if not ready then
            resume(math.huge)
        end
        thinking = false
        found, lane = thought.found, thought.lane
        adopt(best, math.max(0, deepest))
        -- Where it first saw no way through (or none within its budget).
        if not found and not autopilot.lost then
            autopilot.lost = s.distance
        end
        foresee(s)
    end
    local i = plan[nextInput]
    nextInput = nextInput + 1
    if i then
        apply(s, i)
    end
end

-- Marks the run `piloted` (it saves no best score). `lost`: where it first found no way through.
function autopilot.Play(s, elapsed)
    if s.status == "ready" then
        sim.Start(s)
    end
    s.piloted = true
    if s.status ~= "running" then
        return
    end
    if current ~= s then
        current, due, found, planLength, nextInput, lane = s, 0, false, 0, 1, s.lane
        thinking = false
        autopilot.lost = nil
    end
    -- Like the simulation, a stall loses time.
    elapsed = math.min(elapsed, 0.1)
    local frame = elapsed
    while elapsed > 1e-9 and s.status == "running" do
        if due <= 1e-9 then
            decide(s)
            due = DT
        end
        local part = math.min(elapsed, due)
        sim.Update(s, part)
        due, elapsed = due - part, elapsed - part
    end
    -- This frame's share of the job: what is left of SPREAD over the frames before it is due.
    if thinking and not ready and s.status == "running" then
        local frames = math.max(1, math.floor((due + (jobAt + 1 - nextInput) * DT) / math.max(frame, 1e-3)))
        resume(math.max(MIN, math.ceil((SPREAD - spent) / frames)))
    end
end

-- Whether a run from the lobby still plays itself: up to past its gate's strip, where it starts
-- counting (`start`).
function autopilot.InIntro(s)
    return s.lobby ~= nil and s.status == "running" and s.distance < s.start
end

-- A run from the lobby plays itself up to past its gate (`lobby.intro`, src/scenes/lobby.lua):
-- its lane changes, then a jump whose top is at the rim, through the gate's arc of coins. The
-- frame is split at the takeoff, so the jump starts where it should at any frame rate. False
-- once the player is to take over.
function autopilot.Intro(s, elapsed)
    if not autopilot.InIntro(s) then
        return false
    end
    local lobby = s.lobby
    s.forward = true
    local lane = lobby.lane
    for _, step in ipairs(lobby.intro) do
        if s.distance >= step.at then
            lane = step.lane
        end
    end
    if lane ~= s.lane then
        sim.Move(s, lane > s.lane and 1 or -1)
    end
    elapsed = math.min(elapsed, 0.1)
    local takeoff = lobby.rim - app.track.JumpLength(s) / 2
    if not s.introJumped and s.distance + s.speed * elapsed >= takeoff then
        local before = math.max(0, (takeoff - s.distance) / s.speed)
        sim.Update(s, before)
        elapsed = elapsed - before
        s.introJumped = true
        sim.Jump(s)
    end
    sim.Update(s, elapsed)
    return true
end
