---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
local sim = app.simulation
local L = sim.LAYER
-- /surfer bot: the game plays itself while you watch, to see the patterns run through at
-- every difficulty. It searches the simulation itself, like tests/simulation.lua's check that a
-- pattern can be run through: an input every DT seconds (nothing, jump, a lane either way,
-- both), depth first, STEPS inputs ahead on copies of the run. It plays the run in
-- `simulation.Update`'s stead (Surfer's `overlay.pilot`), splitting each frame at its input
-- times, so the run follows the plan to the tick. The runner runs by itself (the movement keys
-- neither move nor steer it), heads for coins when it safely can, changes lanes only when an
-- obstacle or a coin asks for it (no needless out and back), a piloted run never counts as a
-- best score, and a finished run starts over after a moment.

local bot = {}
dev.bot = bot

-- Seconds between two inputs, and how many a plan looks ahead (1.4 seconds: up to 76 yards at
-- the top speed, short of the 85 yards the track is laid out ahead).
local DT, STEPS = 0.05, 28
-- Inputs played from a plan before the next one, as long as it found a way through.
local REPLAN = 5
-- Searched states per plan, at most.
local BUDGET = 20000
-- Seconds a finished run stays on screen before the next.
local RESTART_DELAY = 3
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

-- A copy of a branch to play on; its own list of boxes, since the simulation drops passed ones.
local function branch(s)
    local c = {}
    for k, v in pairs(s) do
        c[k] = v
    end
    c.objects = {}
    for i, o in ipairs(s.objects) do
        c.objects[i] = o
    end
    return c
end
-- The search's start: the run without its coins, which a branch would collect for the run,
-- without laying out more track, which would draw from the run's generator, and without the
-- boxes beyond the plan's reach.
local function root(s)
    local c = branch(s)
    local reach = s.distance + s.difficulty.topSpeed * STEPS * DT + 2
    c.objects = {}
    for _, o in ipairs(s.objects) do
        if o.kind ~= "coin" and o.at < reach then
            c.objects[#c.objects + 1] = o
        end
    end
    c.nextRow = math.huge
    return c
end

local function byAt(a, b)
    if a.at ~= b.at then
        return a.at < b.at
    end
    return a.lane < b.lane
end
-- The run's coins still to collect, nearest first.
local function coinsAhead(s)
    local coins = {}
    for _, o in ipairs(s.objects) do
        if o.kind == "coin" and not o.hit and o.at + o.length > s.distance then
            coins[#coins + 1] = o
        end
    end
    table.sort(coins, byAt)
    return coins
end

-- The lane a plan heads for: the runner's own (the one it is changing to) while a coin in it is
-- near, else the nearest coin's, else its own again.
local function targetLane(s, coins)
    local nearest
    for _, o in ipairs(coins) do
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
local function preferred(c, step, aim)
    local prior = aim.prior and aim.prior[aim.offset + step + 1]
    if prior then
        return prior
    end
    local jump = false
    for _, o in ipairs(aim.coins) do
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

-- Depth first through the inputs from `start`: whether it found a way through all STEPS, and
-- the inputs of the way (or of the one that got furthest).
local function search(start, aim)
    local seen, nodes, path, best, depth = {}, 0, {}, {}, -1
    local function go(c, step)
        if c.status ~= "running" then
            return false
        end
        if step > depth then
            depth = step
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
        local key = string.format(
            "%d %d %d %d %d",
            step,
            c.lane,
            math.floor(c.lateral * 20 + 0.5),
            math.floor(c.height * 20 + 0.5),
            math.floor(c.velocity * 4 + 0.5)
        )
        if seen[key] then
            return false
        end
        seen[key] = true
        -- Inputs that change nothing are left out: a jump in the air, a lane past the edge.
        local grounded = c.velocity == 0 and c.height <= c.floor
        for _, i in ipairs(ORDERS[preferred(c, step, aim)]) do
            local move, jump = INPUTS[i][1], INPUTS[i][2]
            if (grounded or not jump) and (move == 0 or math.abs(c.lane + move) <= 1) then
                local child = branch(c)
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
    return go(start, 0), best
end

-- Plays `path` on a copy of the run, with copies of its coins: how many inputs it lives
-- through and how many coins it collects.
local function replay(s, path, coins)
    local c = root(s)
    for _, o in ipairs(coins) do
        c.objects[#c.objects + 1] = sim.Box("coin", o.lane, o.at, o.length, o.layer, o.layers)
    end
    c.coins = 0
    for k, i in ipairs(path) do
        apply(c, i)
        sim.Update(c, DT)
        if c.status ~= "running" then
            return k - 1, c.coins
        end
    end
    return #path, c.coins
end

-- `path` without the lane change and the jump at `k` where `move`/`jump` say so.
local function without(path, k, move, jump)
    local copy = {}
    for i, input in ipairs(path) do
        copy[i] = input
    end
    local input = INPUTS[path[k]]
    copy[k] = inputOf(move and 0 or input[1], input[2] and not jump)
    return copy
end

-- A found way without what it does not need: each lane change that the next one undoes, then
-- each lane change and each jump on its own, left out where the way still gets through and
-- collects as many coins.
local function smooth(s, path, coins)
    local _, most = replay(s, path, coins)
    local function try(candidate)
        local lived, collected = replay(s, candidate, coins)
        if lived == #candidate and collected >= most then
            path, most = candidate, collected
        end
    end
    for k = 1, #path do
        local move = INPUTS[path[k]][1]
        if move ~= 0 then
            local back = k + 1
            while path[back] and INPUTS[path[back]][1] == 0 do
                back = back + 1
            end
            if path[back] and INPUTS[path[back]][1] == -move then
                local candidate = without(path, k, true)
                try(without(candidate, back, true))
            end
        end
    end
    for k = 1, #path do
        if INPUTS[path[k]][1] ~= 0 then
            try(without(path, k, true))
        end
        if INPUTS[path[k]][2] then
            try(without(path, k, false, true))
        end
    end
    return path
end

-- A plan from the run as it is. Crates and enemies fill their lane for it, so it does not
-- squeeze between two mid lane change; only when that finds no way, at their real widths.
local function plan(s)
    local coins, widths = coinsAhead(s), sim.geometry.halfWidth
    local aim = { coins = coins, lane = targetLane(s, coins) }
    -- The previous plan goes on while it heads for the same lane.
    if bot.found and bot.lane == aim.lane then
        aim.prior, aim.offset = bot.path, bot.next - 1
    end
    bot.lane = aim.lane
    local crate, enemy = widths.obstacle, widths.enemy
    widths.obstacle, widths.enemy = 1, 1
    local found, path = search(root(s), aim)
    if found then
        path = smooth(s, path, coins)
    end
    widths.obstacle, widths.enemy = crate, enemy
    if not found then
        local tight, tightPath = search(root(s), aim)
        if tight then
            tightPath = smooth(s, tightPath, coins)
        end
        if tight or #tightPath > #path then
            found, path = tight, tightPath
        end
    end
    return found, path
end

-- The next input, at an input time: from the plan, or from a new one.
local function decide(s)
    if bot.state ~= s then
        bot.state, bot.path, bot.lost = s, nil, nil
    end
    if not bot.path or not bot.found or bot.next > REPLAN then
        bot.found, bot.path = plan(s)
        bot.next = 1
        -- Where it first saw no way through: a track the search cannot get through (or not
        -- within its budget).
        if not bot.found and not bot.lost then
            bot.lost = s.distance
        end
    end
    local i = bot.path[bot.next]
    bot.next = bot.next + 1
    if i then
        apply(s, i)
    end
end

-- Plays `elapsed` seconds of the run, `simulation.Update`'s stand-in: starts it, and splits the
-- time at the input times.
function bot.Play(s, elapsed)
    if s.status == "ready" then
        sim.Start(s)
    end
    s.piloted = true
    if s.status ~= "running" then
        return
    end
    if bot.state ~= s then
        bot.due = 0
    end
    -- Like the simulation, a stall loses time.
    elapsed = math.min(elapsed, 0.1)
    while elapsed > 1e-9 and s.status == "running" do
        if bot.due <= 1e-9 then
            decide(s)
            bot.due = DT
        end
        local part = math.min(elapsed, bot.due)
        sim.Update(s, part)
        bot.due, elapsed = bot.due - part, elapsed - part
    end
end

local function report(s)
    local lost = bot.state == s and bot.lost
    log:chat(
        "Bot: over at %d yards, score %d, %d coins (%s, seed %d)%s",
        math.floor(s.distance),
        sim.Score(s),
        s.coins,
        s.difficulty.name,
        s.seed,
        lost and string.format("; found no way through from %d yards on", lost) or ""
    )
end

-- `overlay.pilot`: plays the run, and after a finished one reports it and starts the next.
local function pilot(s, elapsed)
    if s.status ~= "over" then
        bot.Play(s, elapsed)
        return
    end
    if bot.ended ~= s then
        bot.ended, bot.wait = s, 0
        if s.piloted then
            report(s)
        end
    end
    bot.wait = bot.wait + elapsed
    if bot.wait >= RESTART_DELAY then
        app.overlay:Restart()
    end
end

dev.Command("bot", "bot: the game plays itself while you watch (toggles)", function()
    local overlay = app.overlay
    if overlay.pilot then
        overlay.pilot = nil
        log:chat("Bot: off")
        return
    end
    overlay.pilot = pilot
    if not overlay.frame or not overlay.frame:IsShown() then
        overlay:Toggle()
    end
    log:chat("Bot: on. Its runs count for no best score; /surfer bot again stops it.")
end)
