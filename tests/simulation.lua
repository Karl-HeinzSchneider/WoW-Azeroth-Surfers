local app = {}
dofile("tests/load.lua")(
    app,
    { "game/random", "game/simulation", "game/track", "patterns/patterns.xml", "game/autopilot" }
)
local random = app.random
local g = app.simulation
local track = app.track
local L = g.LAYER
local count = 0
local function test(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end
-- A running game with an empty track: tests place their own boxes.
local function fresh(...)
    local s = g.New()
    s.nextRow = math.huge
    s.objects = { ... }
    g.Start(s)
    s.forward = true
    return s
end
local function advance(s, seconds, fps)
    for _ = 1, math.floor(seconds * fps) do
        g.Update(s, 1 / fps)
    end
end
local function obstacle(lane, at, layer, layers)
    return g.Box("obstacle", lane, at, 0.5, layer or 0, layers or 1)
end
local function coin(lane, at, layer)
    return g.Box("coin", lane, at, 0.32, layer or 0, 1)
end
local function platform(lane, at, length, layers, ramp)
    return g.Box("platform", lane, at, length, 0, layers, ramp)
end

test("lane limits and smooth movement", function()
    local s = fresh()
    g.Move(s, -1)
    g.Move(s, -1)
    assert(s.lane == -1 and s.lateral == 0)
    advance(s, 0.3, 60)
    assert(math.abs(s.lateral + 1) < 0.001)
end)
test("a jump peaks past layer 2, lands and cannot double jump", function()
    local s = fresh()
    g.Jump(s)
    advance(s, 0.3, 60)
    assert(s.height > 2 * L)
    local velocity = s.velocity
    g.Jump(s)
    assert(s.velocity == velocity)
    advance(s, 0.6, 60)
    assert(s.height == 0 and s.velocity == 0)
end)
test("pause freezes simulation", function()
    local s = fresh()
    g.Jump(s)
    advance(s, 0.2, 60)
    g.Pause(s)
    local distance, height = s.distance, s.height
    advance(s, 5, 60)
    assert(s.distance == distance and s.height == height)
    g.Pause(s)
    advance(s, 0.1, 60)
    assert(s.distance > distance)
end)
test("obstacle collision ends run", function()
    local s = fresh(obstacle(0, 1))
    advance(s, 0.3, 60)
    assert(s.status == "over")
    local distance = s.distance
    advance(s, 1, 60)
    assert(s.distance == distance)
end)
-- At speed 30 a jump is above two layers from 6 to 18 yards after take-off.
test("a jump clears one and two layer obstacles", function()
    for layers = 1, 2 do
        local s = fresh(obstacle(0, 10, 0, layers))
        g.Jump(s)
        advance(s, 0.9, 60)
        assert(s.status == "running" and s.distance > 11)
    end
end)
test("a three layer wall cannot be jumped", function()
    local s = fresh(obstacle(0, 10, 0, 3))
    g.Jump(s)
    advance(s, 0.9, 60)
    assert(s.status == "over")
end)
test("coins award once, high ones only in a jump", function()
    local s = fresh(coin(0, 1), coin(0, 3, 4))
    advance(s, 0.3, 60)
    assert(s.coins == 1 and g.Score(s) == math.floor(s.distance) + 25)
    s = fresh(coin(0, 4, 4))
    g.Jump(s)
    advance(s, 0.4, 60)
    assert(s.coins == 1)
    -- Every coin passed counts toward the total, collected or not.
    s = fresh(coin(0, 1), coin(1, 2), coin(0, 4, 4))
    advance(s, 0.4, 60)
    assert(s.coins == 1 and s.coinTotal == 3, "one of three")
end)
test("a coin streak survives a coin missed beside it, breaks on too long a gap", function()
    local streak, from = g.STREAK, g.STREAK.from
    streak.from = 3
    -- A row in lane 0 with one in lane 1 beside it, then one far ahead.
    local s = fresh(coin(0, 2), coin(0, 5), coin(1, 8), coin(0, 8), coin(0, 11), coin(0, 40))
    advance(s, 0.45, 60)
    assert(s.coins == 4 and s.streak == 4 and s.coinTotal == 5, "the coin beside does not break it")
    -- 25 a coin, `points` more from the third on.
    assert(s.bonus == 4 * 25 + 2 * streak.points, "scores more from `from` on")
    while s.distance < 11 + g.StreakReach(s) + 0.5 do
        g.Update(s, 1 / 60)
    end
    assert(s.streak == 0 and s.bestStreak == 4, "too far without a coin breaks it")
    advance(s, 0.6, 60)
    assert(s.coins == 5 and s.streak == 1)
    streak.from = from
end)
test("the multiplier scales only what is earned after it is set", function()
    local s = fresh(coin(0, 1))
    advance(s, 0.3, 60)
    local before, distance = g.Score(s), s.distance
    g.SetMultiplier(s, 3)
    advance(s, 0.3, 60)
    assert(s.multiplier == 3)
    assert(math.abs(g.Score(s) - (before + 3 * (s.distance - distance))) <= 1)
    g.SetMultiplier(s, 0)
    assert(s.multiplier == 1, "never below 1")
end)
test("barriers on layer 3 are run under but hit in a jump", function()
    local s = fresh(g.Box("barrier", 0, 3, 0.4, 3, 1))
    advance(s, 0.4, 60)
    assert(s.status == "running")
    s = fresh(g.Box("barrier", 0, 3, 0.4, 3, 1))
    g.Jump(s)
    advance(s, 0.4, 60)
    assert(s.status == "over")
end)
test("running into a platform ends the run, jumping lands on it", function()
    local s = fresh(platform(0, 5, 20, 2))
    advance(s, 0.5, 60)
    assert(s.status == "over")
    s = fresh(platform(0, 5, 20, 2))
    g.Jump(s)
    advance(s, 0.8, 60)
    assert(s.status == "running" and s.height == 2 * L and s.floor == 2 * L)
end)
test("a ramp climbs to a platform too high to jump onto", function()
    local s = fresh(platform(0, 2, 30, 3, 12))
    advance(s, 1, 60)
    assert(s.status == "running" and s.height == 3 * L)
end)
test("the runner jumps from a platform and falls off its end", function()
    local s = fresh(platform(0, -1, 4, 1))
    s.height, s.floor = L, L
    g.Jump(s)
    advance(s, 0.2, 60)
    assert(s.height > 3 * L, "a jump from a platform reaches past layer 3")
    advance(s, 1, 60)
    assert(s.status == "running" and s.height == 0)
end)
test("obstacles on a platform collide at its layer", function()
    local s = fresh(platform(0, -1, 30, 2), obstacle(0, 4, 2, 1))
    s.height, s.floor = 2 * L, 2 * L
    advance(s, 0.4, 60)
    assert(s.status == "over")
end)
test("changing lanes into a platform's side ends the run, jumping across lands on it", function()
    local s = fresh(platform(1, -1, 30, 2))
    g.Move(s, 1)
    advance(s, 0.3, 60)
    assert(s.status == "over")
    s = fresh(platform(1, -1, 30, 2))
    g.Jump(s)
    advance(s, 0.12, 60)
    g.Move(s, 1)
    advance(s, 0.8, 60)
    assert(s.status == "running" and s.height == 2 * L)
end)
test("frame rate independence", function()
    local a, b = fresh(), fresh()
    advance(a, 1, 30)
    advance(b, 1, 120)
    assert(math.abs(a.distance - b.distance) < 0.001)
end)
test("long stalls cannot tunnel through obstacles", function()
    local s = fresh(obstacle(0, 1))
    g.Update(s, 10)
    assert(s.status == "over" and s.distance < 1.5)
end)
test("restart is clean", function()
    local s = g.New()
    assert(s.status == "ready" and #s.objects == 0 and g.Score(s) == 0)
    g.Jump(s)
    g.Move(s, 1)
    assert(s.velocity == 0 and s.lane == 0)
end)

-- The rules of a track (track.lua): boxes on the grid, at every point some lane free of
-- anything a runner on the ground can neither jump nor climb, and coins spaced apart, never
-- inside a solid box, on a platform only over its top. `label` names it in a failure.
local function byAt(a, b)
    return a.at < b.at
end
local function checkTrack(objects, label)
    -- Per lane, sorted along the track: the boxes, and the stretches a runner on the ground
    -- can neither jump nor climb (merged where they overlap).
    local lanes, walls, longest = { [-1] = {}, [0] = {}, [1] = {} }, { [-1] = {}, [0] = {}, [1] = {} }, 0
    for _, o in ipairs(objects) do
        assert(lanes[o.lane] and o.layer >= 0 and o.layers >= 1, label .. ": off the grid")
        local list = lanes[o.lane]
        list[#list + 1] = o
        longest = math.max(longest, o.length)
    end
    for lane, list in pairs(lanes) do
        table.sort(list, byAt)
        local stretches = walls[lane]
        for _, o in ipairs(list) do
            local solid = o.kind == "obstacle" or o.kind == "enemy" or (o.kind == "platform" and not o.ramp)
            -- Taller than a jump from the ground, starting below the body's top (one on layer 3
            -- only touches it: 3 * L is a hair under the body's height).
            if solid and g.Top(o) > 2 * L and o.layer * L < g.geometry.playerHeight - 1e-6 then
                local last = stretches[#stretches]
                if last and o.at <= last[2] then
                    last[2] = math.max(last[2], o.at + o.length)
                else
                    stretches[#stretches + 1] = { o.at, o.at + o.length }
                end
            end
        end
    end
    -- No stretch where all three lanes are walled.
    for _, a in ipairs(walls[-1]) do
        for _, b in ipairs(walls[0]) do
            local from, to = math.max(a[1], b[1]), math.min(a[2], b[2])
            if from <= to then
                for _, c in ipairs(walls[1]) do
                    local inner, outer = math.max(from, c[1]), math.min(to, c[2])
                    assert(inner > outer, string.format("%s blocks every lane at %.2f", label, inner))
                end
            end
        end
    end
    -- Coins against their lane's boxes nearby: every box that can reach a coin starts at most
    -- the longest box's length before it.
    for _, list in pairs(lanes) do
        for i, c in ipairs(list) do
            if c.kind == "coin" then
                local j = i - 1
                while list[j] and list[j].at > c.at - longest - 3 do
                    j = j - 1
                end
                j = j + 1
                while list[j] and list[j].at < c.at + 3 do
                    local o = list[j]
                    if o ~= c and o.kind == "coin" and math.abs(o.at - c.at) < 2.99 then
                        assert(o.layer ~= c.layer, label .. ": coins closer than 3 yards")
                    end
                    local overlaps = c.at < o.at + o.length and c.at + c.length > o.at
                    if overlaps and o.kind ~= "coin" and o.kind ~= "platform" then
                        local apart = c.layer >= o.layer + o.layers or c.layer + c.layers <= o.layer
                        assert(apart, string.format("%s: a coin inside a %s", label, o.kind))
                    end
                    if o.kind == "platform" and c.layer == o.layer + o.layers then
                        local near = c.at > o.at - 2 and c.at < o.at + o.length + 2
                        local over = c.at >= o.at and c.at + c.length <= o.at + o.length
                        assert(not near or over, label .. ": a coin beyond a platform's top")
                    end
                    j = j + 1
                end
            end
        end
    end
end

-- Every pattern on its own, many times: within its length and lead-in, and a way through.
test("every pattern keeps the track's rules", function()
    assert(#track.list > 0, "patterns registered")
    -- At every difficulty's slowest and fastest: some spacings follow the speed.
    local speeds = {}
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        speeds[#speeds + 1] = difficulty.startSpeed
        speeds[#speeds + 1] = difficulty.topSpeed
    end
    for _, pattern in ipairs(track.list) do
        for seed = 1, 100 do
            local s = g.New(seed)
            s.objects = {}
            s.speed = speeds[seed % #speeds + 1]
            local at = 30
            local length = pattern.place(s, at, s.random)
            local label = string.format("pattern %s, seed %d", pattern.name, seed)
            assert(type(length) == "number" and length >= 0, label .. ": returns its length")
            assert(#s.objects > 0, label .. ": places something")
            for _, o in ipairs(s.objects) do
                assert(o.seed, label .. ": a box without a seed (use track.Add)")
                assert(o.at >= at - track.LEAD_IN - 0.5, label .. ": leads in too far")
                assert(o.at <= at + length, label .. ": starts a box past its length")
            end
            checkTrack(s.objects, label)
        end
    end
end)

-- Whether a runner can get through a run's track up to `goal`: a depth-first search over the
-- inputs (nothing, jump, a lane either way, both) every DT seconds, through the simulation
-- itself. Each branch is a copy of the run (its own list of boxes: the simulation drops the
-- passed ones).
local DT = 0.05
local INPUTS = { { 0, false }, { 0, true }, { -1, false }, { 1, false }, { -1, true }, { 1, true } }
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
local function runnable(start, goal)
    local seen = {}
    local function go(s, step)
        if s.status ~= "running" then
            return false
        end
        if s.distance >= goal then
            return true
        end
        local key = string.format(
            "%d %d %d %d %d",
            step,
            s.lane,
            math.floor(s.lateral * 20 + 0.5),
            math.floor(s.height * 20 + 0.5),
            math.floor(s.velocity * 4 + 0.5)
        )
        if seen[key] then
            return false
        end
        seen[key] = true
        for _, input in ipairs(INPUTS) do
            local c = branch(s)
            if input[1] ~= 0 then
                g.Move(c, input[1])
            end
            if input[2] then
                g.Jump(c)
            end
            g.Update(c, DT)
            if go(c, step + 1) then
                return true
            end
        end
        return false
    end
    return go(start, 0)
end

-- Every pattern can be run through at every difficulty's slowest and fastest speed, starting
-- in any lane. Crates and enemies fill their lane for it: the simulation leaves room to
-- squeeze between two of them mid lane change, which no one can time every time.
test("every pattern can be run through", function()
    local widths = g.geometry.halfWidth
    local crateWidth, enemyWidth = widths.obstacle, widths.enemy
    widths.obstacle, widths.enemy = 1, 1
    for _, pattern in ipairs(track.list) do
        for _, difficulty in ipairs(g.DIFFICULTIES) do
            for _, speed in ipairs({ difficulty.startSpeed, difficulty.topSpeed }) do
                for seed = 1, 6 do
                    local s = g.New(seed, difficulty.id)
                    s.objects, s.nextRow, s.speed = {}, math.huge, speed
                    local at = 30
                    local length = pattern.place(s, at, s.random)
                    -- The speed held for the whole pattern.
                    s.difficulty = { startSpeed = speed, topSpeed = speed, speedUp = math.huge, gap = difficulty.gap }
                    g.Start(s)
                    s.forward = true
                    local through = false
                    for lane = -1, 1 do
                        local c = branch(s)
                        c.lane, c.lateral = lane, lane
                        through = through or runnable(c, at + length + 2)
                    end
                    assert(
                        through,
                        string.format(
                            "pattern %s, seed %d: no way through at %s's %d",
                            pattern.name,
                            seed,
                            difficulty.id,
                            speed
                        )
                    )
                end
            end
        end
    end
    widths.obstacle, widths.enemy = crateWidth, enemyWidth
end)

-- Generated tracks, at every difficulty: the stream stays bounded, the rules hold where
-- patterns meet.
test("generated tracks always leave a way through", function()
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        for seed = 1, difficulty.id == "normal" and 200 or 40 do
            -- Jump ahead pattern by pattern, keeping every box before the track drops it.
            local s, objects, seen = g.New(seed, difficulty.id), {}, {}
            g.Start(s)
            for _ = 1, 40 do
                -- High above the track, so nothing ends the run before the next pattern spawns.
                s.distance, s.height = s.nextRow - 80, 100
                g.Update(s, 1 / 120)
                s.status = "running"
                for _, o in ipairs(s.objects) do
                    if not seen[o] then
                        seen[o] = true
                        objects[#objects + 1] = o
                    end
                end
            end
            assert(#s.objects < 120, "the live stream stays bounded")
            assert(#objects > 150, "the track was generated")
            checkTrack(objects, string.format("%s seed %d", difficulty.id, seed))
        end
    end
end)

-- A run through zones lays out a gate where each zone ends, about every ZONE_LENGTH yards,
-- none at its start; the track keeps its rules there. Without zones, none.
test("a run through zones has a gate between each two", function()
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        for seed = 1, 10 do
            local s, objects, seen = g.New(seed, difficulty.id, true), {}, {}
            g.Start(s)
            for _ = 1, 120 do
                s.distance, s.height = s.nextRow - 80, 100
                g.Update(s, 1 / 120)
                s.status = "running"
                for _, o in ipairs(s.objects) do
                    if not seen[o] then
                        seen[o] = true
                        objects[#objects + 1] = o
                    end
                end
            end
            local label = string.format("%s seed %d with zones", difficulty.id, seed)
            assert(#s.gates >= 2, label .. ": gates")
            assert(s.gates[1] >= g.ZONE_LENGTH[1], label .. ": none at the start")
            for k = 2, #s.gates do
                local apart = s.gates[k] - s.gates[k - 1]
                assert(apart >= g.ZONE_LENGTH[1] and apart <= g.ZONE_LENGTH[2] + 200, label .. ": zone lengths")
            end
            -- Each gate's ramp: a platform with its ramp in every lane, up to the rim and past it.
            local gate = track.GATE
            local lanes = {}
            for _, o in ipairs(objects) do
                if o.gate then
                    assert(o.kind == "platform" and o.ramp and o.layers == gate.ramp.layers, label .. ": a gate's ramp")
                    assert(o.at < o.rim and o.at + o.length > o.rim, label .. ": the ramp reaches the rim")
                    lanes[o.rim] = (lanes[o.rim] or 0) + 1
                end
            end
            for _, rim in ipairs(s.gates) do
                assert(lanes[rim] == 3, label .. ": a ramp in every lane at each gate")
            end
            -- Empty road to each rim and away from it in every lane, but for the gate's own ramp:
            -- the strip and `lead` yards of the zone's road beyond it, and at least `clear` seconds
            -- at the difficulty's slowest (the speed only rises): nothing to die on at the gate,
            -- time to see the next zone after it, and none of the zone's boxes at the strip's edge.
            local before = math.max(gate.before + gate.lead, difficulty.startSpeed * gate.clear[1])
            local after = math.max(gate.after + gate.lead, difficulty.startSpeed * gate.clear[2])
            for _, o in ipairs(objects) do
                if o.kind ~= "coin" and not o.gate then
                    for _, rim in ipairs(s.gates) do
                        local inside = o.at + o.length > rim - before and o.at < rim + after
                        assert(not inside, label .. ": a box on the empty road around a gate")
                    end
                end
            end
            checkTrack(objects, label)
        end
    end
    assert(g.New(1).gates == nil, "without zones, no gates")
end)

-- A run from the lobby starts in its lane with its coins, its gate at its rim and the patterns
-- past it; with zones the next gate a zone's length on. It can be run through, from the start
-- to past its first patterns, at every difficulty.
test("a run from the lobby starts in front of its gate", function()
    local lobby = {
        rim = 50,
        lane = -1,
        coins = { { lane = -1, from = 7, count = 4 }, { lane = 0, from = 18, count = 4 } },
    }
    local gate = track.GATE
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        for _, zones in ipairs({ false, true }) do
            local label = string.format("%s%s", difficulty.id, zones and " with zones" or "")
            local s = g.New(3, difficulty.id, zones, lobby)
            assert(s.lane == -1 and s.lateral == -1, label .. ": in the lobby's lane")
            assert(s.gates[1] == lobby.rim and #s.gates == 1, label .. ": its gate first")
            assert((s.zones or false) == zones, label .. ": zones as asked")
            local first = math.huge
            for _, o in ipairs(s.objects) do
                if not o.gate and o.kind ~= "coin" then
                    first = math.min(first, o.at)
                end
            end
            g.Start(s)
            s.forward = true
            -- The first patterns come in as the run goes.
            local probe = branch(s)
            probe.distance, probe.height = s.nextRow - 80, 100
            g.Update(probe, 1 / 120)
            for _, o in ipairs(probe.objects) do
                if not o.gate and o.kind ~= "coin" then
                    first = math.min(first, o.at)
                end
            end
            assert(first >= lobby.rim + gate.after + gate.lead, label .. ": no box before the gate's empty road ends")
            if zones then
                assert(s.nextGate >= lobby.rim + g.ZONE_LENGTH[1], label .. ": the next gate a zone on")
            end
            local coins = 0
            for _, o in ipairs(s.objects) do
                coins = coins + (o.kind == "coin" and o.at < lobby.rim - gate.before and 1 or 0)
            end
            assert(coins == 8, label .. ": the lobby's coins")
            assert(runnable(s, lobby.rim + 80), label .. ": runnable from the start")
        end
    end
end)

-- The pick honors a pattern's weight by difficulty and its `from`; a run's speed follows its
-- difficulty.
test("difficulties pick their patterns and set the speed", function()
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        local s = g.New(1, difficulty.id)
        assert(s.difficulty == difficulty and s.speed == difficulty.startSpeed)
        for _, at in ipairs({ 0, 300, 3000 }) do
            for _ = 1, 200 do
                local pattern = track.Pick(s, at)
                local weight = pattern and pattern.weight
                if type(weight) == "table" then
                    weight = weight[difficulty.id]
                end
                assert(
                    not pattern or (pattern.from <= at and weight and weight > 0),
                    difficulty.id .. " picks a pattern it has"
                )
            end
        end
    end
    assert(g.New(1, "nowhere").difficulty == g.DIFFICULTIES.normal, "an unknown difficulty is normal")
    local easy, expert = g.New(1, "easy"), g.New(1, "expert")
    easy.objects, expert.objects, easy.nextRow, expert.nextRow = {}, {}, math.huge, math.huge
    for _, s in ipairs({ easy, expert }) do
        g.Start(s)
        s.forward = true
        advance(s, 30, 60)
    end
    assert(easy.distance < expert.distance and easy.speed < expert.speed, "harder is faster")
    assert(expert.speed <= g.DIFFICULTIES.expert.topSpeed, "up to the top speed")
end)
-- Seeds: Park and Miller's own check, and one seed always lays out the same track.
test("the generator is the minimal standard", function()
    local x = 1
    for _ = 1, 10000 do
        x = random.Step(x)
    end
    assert(x == 1043618065, x)
    assert(random.Normalize(0) == random.MAX and random.Normalize(random.MAX + 1) == 1)
    local r = random.New(7)
    for _ = 1, 1000 do
        local u, n = r(), r(-1, 1)
        assert(u >= 0 and u < 1 and (n == -1 or n == 0 or n == 1))
    end
end)
local function layout(seed)
    local s, objects = g.New(seed), {}
    g.Start(s)
    for _ = 1, 40 do
        s.distance, s.height = s.nextRow - 80, 100
        g.Update(s, 1 / 120)
        s.status = "running"
        for _, o in ipairs(s.objects) do
            local line =
                table.concat({ o.kind, o.lane, o.at, o.length, o.layer, o.layers, tostring(o.ramp), o.seed }, " ")
            objects[line] = true
        end
    end
    local lines = {}
    for line in pairs(objects) do
        lines[#lines + 1] = line
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end
test("a seed always lays out the same track", function()
    assert(layout(1234) == layout(1234))
    assert(layout(1234) ~= layout(1235))
    assert(g.New(99).seed == 99 and g.New().seed >= 1)
end)
-- Auto mode's autopilot gets through generated tracks at every difficulty, at an uneven frame
-- rate, collecting coins on the way; its runs save no best score.
test("the autopilot plays generated tracks", function()
    for _, difficulty in ipairs(g.DIFFICULTIES) do
        local s, frame = g.New(7, difficulty.id), 0
        while s.status ~= "over" and s.distance < 1000 do
            s.forward = s.status == "running"
            frame = frame + 1
            app.autopilot.Play(s, frame % 3 == 0 and 1 / 30 or 1 / 90)
        end
        assert(s.status == "running", difficulty.id .. ": the autopilot got through")
        assert(s.coins > 0 and s.piloted, difficulty.id .. ": collects coins, marks the run")
    end
end)
print(string.format("%d simulation tests passed", count))

-- Near misses use the same box dimensions the views draw.
local s = fresh()
assert(not g.Overlaps(s, obstacle(0, 0.2)))
assert(g.Overlaps(s, obstacle(0, -0.2)))
s.lateral = 0.4
assert(not g.Overlaps(s, obstacle(0, -0.2)))
s.lateral = 0
s.height = L + 0.01
assert(not g.Overlaps(s, obstacle(0, -0.2)))
assert(g.Overlaps(s, coin(0, -0.1, 1)))
s.height = 2 * L + 0.01
assert(not g.Overlaps(s, coin(0, -0.1, 1)))
s.height = 0
s.lateral = 0.2
assert(not g.Overlaps(s, coin(0, -0.1, 0)))
print("PASS box depth, lateral near misses, jump clearance and coin layers")

local stopped = fresh()
stopped.forward = false
g.Jump(stopped)
advance(stopped, 0.9, 60)
assert(stopped.distance == 0 and stopped.height == 0)
stopped.forward = true
advance(stopped, 0.2, 60)
assert(stopped.distance > 0)
local distance = stopped.distance
stopped.forward = false
advance(stopped, 0.2, 60)
assert(stopped.distance == distance)
print("PASS track advances only with forward movement; jumps still land while stopped")
