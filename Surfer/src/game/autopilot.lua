---@type string, Surfer
local _, app = ...
local sim = app.simulation
local L = sim.LAYER
-- The autopilot of auto mode (controls.lua): the game plays itself while you watch. It
-- searches the simulation itself, like tests/simulation.lua's check that a pattern can be run
-- through: an input every DT seconds (nothing, jump, a lane either way, both), depth first,
-- STEPS inputs ahead on copies of the run. It plays the run in `simulation.Update`'s stead,
-- splitting each frame at its input times, so the run follows the plan to the tick.
--
-- It heads for one lane per plan (its own while a coin in it is near, else the nearest
-- coin's), goes on with the previous plan while that lane stays, and leaves out of a plan what
-- it does not need (a lane change and its way back, a lane change, a jump) as long as the plan
-- still gets through with as many coins: no needless left and right.
--
-- Copies of the run leave out its coins (they would collect the run's) and never lay out more
-- track (it would draw from the run's generator). Every table is reused: a search allocates
-- nothing once its tables have grown.
local autopilot = {}
app.autopilot = autopilot

-- Seconds between two inputs, and how many a plan looks ahead (1.4 seconds: up to 76 yards at
-- the top speed, short of the 85 yards the track is laid out ahead).
local DT, STEPS = 0.05, 28
-- Inputs played from a plan before the next one, as long as it found a way through.
local REPLAN = 5
-- Searched states per search, at most.
local BUDGET = 20000
-- How many yards ahead a coin draws the runner to its lane.
local REACH = 25

-- { lane change, jump }; `ORDERS[i]` tries input i first, then the rest as listed.
local INPUTS = { { 0, false }, { 0, true }, { -1, false }, { 1, false }, { -1, true }, { 1, true } }
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
local function inputOf(move, jump)
    if move == 0 then
        return jump and 2 or 1
    end
    return (jump and 5 or 3) + (move > 0 and 1 or 0)
end
local function apply(s, i)
    local input = INPUTS[i]
    if input[1] ~= 0 then
        sim.Move(s, input[1])
    end
    if input[2] then
        sim.Jump(s)
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

-- `c` made a copy of `s` with its own list of boxes (the simulation drops passed ones).
local function copy(c, s)
    local objects = c.objects
    for k, v in pairs(s) do
        c[k] = v
    end
    c.objects = objects
    local source = s.objects
    for i = 1, #source do
        objects[i] = source[i]
    end
    for i = #objects, #source + 1, -1 do
        objects[i] = nil
    end
    return c
end
-- `c` made the start of a search or a replay from the run `s`: its boxes within the plan's
-- reach, without its coins, or with copies of them (`withCoins`, for a replay), and no more
-- track laid out.
local function start(c, s, withCoins)
    local objects = c.objects
    for k, v in pairs(s) do
        c[k] = v
    end
    c.objects = objects
    for i = #objects, 1, -1 do
        objects[i] = nil
    end
    local reach = s.distance + s.difficulty.topSpeed * STEPS * DT + 2
    for _, o in ipairs(s.objects) do
        if o.kind ~= "coin" and o.at < reach then
            objects[#objects + 1] = o
        end
    end
    if withCoins then
        for i = 1, coinCount do
            local o, k = coins[i], coinCopies[i]
            if not k then
                k = {}
                coinCopies[i] = k
            end
            k.kind, k.lane, k.at, k.length, k.layer, k.layers, k.hit =
                "coin", o.lane, o.at, o.length, o.layer, o.layers, nil
            objects[#objects + 1] = k
        end
    end
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
    return inputOf(aim.lane > c.lane and 1 or aim.lane < c.lane and -1 or 0, jump)
end

-- A state as a number: the step, lane, lateral place, height and vertical speed, rounded.
local floor = math.floor
local function key(c, step)
    local lateral = floor(c.lateral * 20 + 0.5) + 32
    local height = floor(c.height * 20 + 0.5)
    return (((step * 3 + c.lane + 1) * 64 + lateral) * 1024 + height) * 256 + floor(c.velocity * 4 + 0.5) + 128
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
    -- Inputs that change nothing are left out: a jump in the air, a lane past the edge.
    local grounded = c.velocity == 0 and c.height <= c.floor
    for _, i in ipairs(ORDERS[preferred(c, step)]) do
        local move, jump = INPUTS[i][1], INPUTS[i][2]
        if (grounded or not jump) and (move == 0 or math.abs(c.lane + move) <= 1) then
            local child = copy(branches[step + 1], c)
            apply(child, i)
            sim.Update(child, DT)
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
    return go(start(root, s), 0)
end

-- Plays `line[1..length]` on a copy of the run with copies of its coins: how many inputs it
-- lives through and how many coins it collects.
local function replay(s, line, length)
    local c = start(replayed, s, true)
    for k = 1, length do
        apply(c, line[k])
        sim.Update(c, DT)
        if c.status ~= "running" then
            return k - 1, c.coins
        end
    end
    return length, c.coins
end

-- Takes the lane change (`move`) or the jump (`jump`) out of input `k`; returns what it was.
local function strip(line, k, move, jump)
    local old = line[k]
    local input = INPUTS[old]
    line[k] = inputOf(move and 0 or input[1], input[2] and not jump)
    return old
end

-- Whether `line` still gets through with at least `most` coins, and how many it collects.
local function keeps(s, line, length, most)
    local lived, collected = replay(s, line, length)
    return lived == length and collected >= most, collected
end

-- A found way without what it does not need: each lane change that the next one undoes, then
-- each lane change and each jump on its own, left out where the way still gets through and
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

-- Makes `line[1..length]` the plan.
local function adopt(line, length)
    for i = 1, length do
        plan[i] = line[i]
    end
    for i = planLength, length + 1, -1 do
        plan[i] = nil
    end
    planLength, nextInput = length, 1
end

-- A new plan from the run as it is. Crates and enemies fill their lane for it, so it does not
-- squeeze between two mid lane change; only when that finds no way, at their real widths.
local function replan(s)
    collectCoins(s)
    aim.lane = targetLane(s)
    -- The previous plan goes on while it heads for the same lane.
    aim.prior, aim.offset = found and lane == aim.lane, nextInput - 1
    lane = aim.lane
    local widths = sim.geometry.halfWidth
    local crate, enemy = widths.obstacle, widths.enemy
    widths.obstacle, widths.enemy = 1, 1
    found = search(s)
    if found then
        smooth(s, best, deepest)
    end
    widths.obstacle, widths.enemy = crate, enemy
    if not found then
        local wide = deepest
        best, spare = spare, best
        found = search(s)
        if found then
            smooth(s, best, deepest)
        elseif wide >= deepest then
            best, spare, deepest = spare, best, wide
        end
    end
    adopt(best, math.max(0, deepest))
    -- Where it first saw no way through (or none within its budget).
    if not found and not autopilot.lost then
        autopilot.lost = s.distance
    end
end

-- The next input, at an input time: from the plan, or from a new one.
local function decide(s)
    if not found or nextInput > REPLAN or nextInput > planLength then
        replan(s)
    end
    local i = plan[nextInput]
    nextInput = nextInput + 1
    if i then
        apply(s, i)
    end
end

-- Plays `elapsed` seconds of the run `s` (in `simulation.Update`'s stead): starts it, splits the
-- time at the input times and marks the run `piloted` (it saves no best score). `lost` is where
-- it first found no way through in this run, if it did.
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
        autopilot.lost = nil
    end
    -- Like the simulation, a stall loses time.
    elapsed = math.min(elapsed, 0.1)
    while elapsed > 1e-9 and s.status == "running" do
        if due <= 1e-9 then
            decide(s)
            due = DT
        end
        local part = math.min(elapsed, due)
        sim.Update(s, part)
        due, elapsed = due - part, elapsed - part
    end
end
