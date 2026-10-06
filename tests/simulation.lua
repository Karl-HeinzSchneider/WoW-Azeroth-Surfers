local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
local g = app.simulation
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
test("a jump clears one and two layer obstacles", function()
    for layers = 1, 2 do
        local s = fresh(obstacle(0, 5, 0, layers))
        g.Jump(s)
        advance(s, 0.9, 60)
        assert(s.status == "running" and s.distance > 6)
    end
end)
test("a three layer wall cannot be jumped", function()
    local s = fresh(obstacle(0, 5, 0, 3))
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

-- Generated tracks: boxes stay on the grid, the stream stays bounded, and at every point some
-- lane is free of anything a runner on the ground can neither jump nor climb.
test("generated patterns always leave a way through", function()
    for seed = 1, 200 do
        math.randomseed(seed)
        -- Jump ahead pattern by pattern, keeping every box before the track drops it.
        local s, objects, seen = g.New(), {}, {}
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
        local far = 0
        for _, o in ipairs(objects) do
            assert(o.lane >= -1 and o.lane <= 1 and o.layer >= 0 and o.layers >= 1)
            far = math.max(far, o.at + o.length)
        end
        for at = 0, far, 0.25 do
            local open = 0
            for lane = -1, 1 do
                local blocked = false
                for _, o in ipairs(objects) do
                    local solid = o.kind == "obstacle" or (o.kind == "platform" and not o.ramp)
                    if solid and o.lane == lane and at >= o.at and at <= o.at + o.length then
                        -- Taller than a jump from the ground, starting below the body's top.
                        if g.Top(o) > 2 * L and o.layer * L < g.geometry.playerHeight then
                            blocked = true
                        end
                    end
                end
                open = open + (blocked and 0 or 1)
            end
            assert(open > 0, string.format("seed %d blocks every lane at %.2f", seed, at))
        end
        -- Coins: spaced apart, never inside a solid box, and on a platform only over its top.
        for _, c in ipairs(objects) do
            if c.kind == "coin" then
                for _, o in ipairs(objects) do
                    if o ~= c and o.lane == c.lane and math.abs(o.at - c.at) < 2.99 and o.kind == "coin" then
                        assert(o.layer ~= c.layer, string.format("seed %d: coins closer than 3 yards", seed))
                    end
                    local overlaps = o.lane == c.lane and c.at < o.at + o.length and c.at + c.length > o.at
                    if overlaps and o.kind ~= "coin" and o.kind ~= "platform" then
                        local apart = c.layer >= o.layer + o.layers or c.layer + c.layers <= o.layer
                        assert(apart, string.format("seed %d: a coin inside a %s", seed, o.kind))
                    end
                    if o.kind == "platform" and o.lane == c.lane and c.layer == o.layer + o.layers then
                        local near = c.at > o.at - 2 and c.at < o.at + o.length + 2
                        local over = c.at >= o.at and c.at + c.length <= o.at + o.length
                        assert(not near or over, string.format("seed %d: a coin beyond a platform's top", seed))
                    end
                end
            end
        end
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
