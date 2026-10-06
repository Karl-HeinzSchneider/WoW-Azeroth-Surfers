local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
local g = app.simulation
local count = 0
local function test(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end
local function fresh()
    local s = g.New(function()
        return -1
    end)
    g.Start(s)
    s.forward = true
    return s
end
local function advance(s, seconds, fps)
    for _ = 1, math.floor(seconds * fps) do
        g.Update(s, 1 / fps)
    end
end
test("lane limits and smooth movement", function()
    local s = fresh()
    g.Move(s, -1)
    g.Move(s, -1)
    assert(s.lane == -1 and s.lateral == 0)
    advance(s, 0.3, 60)
    assert(math.abs(s.lateral + 1) < 0.001)
end)
test("jump arc lands and cannot double jump", function()
    local s = fresh()
    g.Jump(s)
    advance(s, 0.3, 60)
    assert(s.height > 1.4)
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
    local s = fresh()
    s.objects = { { kind = "obstacle", lane = 0, at = 1 } }
    advance(s, 0.3, 60)
    assert(s.status == "over")
    local distance = s.distance
    advance(s, 1, 60)
    assert(s.distance == distance)
end)
test("jump clears obstacle", function()
    local s = fresh()
    s.objects = { { kind = "obstacle", lane = 0, at = 4 } }
    g.Jump(s)
    advance(s, 0.6, 60)
    assert(s.status == "running" and s.distance > 5)
end)
test("coins award once", function()
    local s = fresh()
    s.objects = { { kind = "coin", lane = 0, at = 1 } }
    advance(s, 0.3, 60)
    assert(s.coins == 1 and g.Score(s) == math.floor(s.distance) + 25)
end)
test("frame rate independence", function()
    local a, b = fresh(), fresh()
    advance(a, 1, 30)
    advance(b, 1, 120)
    assert(math.abs(a.distance - b.distance) < 0.001)
end)
test("long stalls cannot tunnel through obstacles", function()
    local s = fresh()
    s.objects = { { kind = "obstacle", lane = 0, at = 1 } }
    g.Update(s, 10)
    assert(s.status == "over" and s.distance < 1)
end)
test("spawn stream remains bounded on long runs", function()
    local s = fresh()
    advance(s, 120, 60)
    assert(s.status == "running")
    assert(#s.objects < 20 and s.speed <= 24)
    for _, o in ipairs(s.objects) do
        assert(o.lane >= -1 and o.lane <= 1)
        if o.kind == "obstacle" then
            assert(o.lane == -1)
        end
    end
end)
test("restart is clean", function()
    local s = g.New()
    assert(s.status == "ready" and #s.objects == 0 and g.Score(s) == 0)
    g.Jump(s)
    g.Move(s, 1)
    assert(s.velocity == 0 and s.lane == 0)
end)
print(string.format("%d simulation tests passed", count))

-- Near misses must use the same dimensions as the obstacle/coin visuals.
local s = fresh()
s.distance = 0
assert(not g.Overlaps(s, { kind = "obstacle", lane = 0, at = 0.6 }))
assert(g.Overlaps(s, { kind = "obstacle", lane = 0, at = 0.2 }))
s.lateral = 0.4
assert(not g.Overlaps(s, { kind = "obstacle", lane = 0, at = 0 }))
s.lateral = 0
s.height = 0.96
assert(not g.Overlaps(s, { kind = "obstacle", lane = 0, at = 0 }))
assert(g.Overlaps(s, { kind = "coin", lane = 0, at = 0 }))
s.height = 1.41
assert(not g.Overlaps(s, { kind = "coin", lane = 0, at = 0 }))
s.height = 0
s.lateral = 0.2
assert(not g.Overlaps(s, { kind = "coin", lane = 0, at = 0 }))
print("PASS visible obstacle depth, lateral near misses, jump clearance and coin bounds")

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
