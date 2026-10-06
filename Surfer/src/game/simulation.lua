---@type string, Surfer
local _, app = ...
-- Fixed-step rules are independent of the curved render coordinates.
local game = {}
app.simulation = game
-- Shared world-space dimensions for collision and the visible obstacle faces.
game.geometry = {
    laneWidth = 2.4,
    playerHalfWidth = 0.22,
    playerHalfDepth = 0.15,
    playerHeight = 2,
    obstacleHalfWidth = 0.65,
    obstacleHalfDepth = 0.25,
    obstacleHeight = 0.95,
    coinHalfWidth = 0.16,
    coinHalfDepth = 0.16,
    coinBottom = 0.9,
    coinHeight = 0.5,
}
local bounds = game.geometry
function game.Overlaps(s, o)
    local obstacle = o.kind == "obstacle"
    local halfWidth = obstacle and bounds.obstacleHalfWidth or bounds.coinHalfWidth
    local halfDepth = obstacle and bounds.obstacleHalfDepth or bounds.coinHalfDepth
    local bottom = obstacle and 0 or bounds.coinBottom
    local top = obstacle and bounds.obstacleHeight or (bottom + bounds.coinHeight)
    return math.abs(o.at - s.distance) < bounds.playerHalfDepth + halfDepth
        and math.abs(o.lane - s.lateral) * bounds.laneWidth < bounds.playerHalfWidth + halfWidth
        and s.height < top
        and s.height + bounds.playerHeight > bottom
end
local STEP = 1 / 120
function game.New(random)
    return {
        status = "ready",
        lane = 0,
        lateral = 0,
        height = 0,
        velocity = 0,
        distance = 0,
        forward = false,
        coins = 0,
        speed = 12,
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
function game.Jump(s)
    if s.status == "running" and s.height == 0 then
        s.velocity = 9
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
    s.speed = math.min(24, 12 + s.distance / 180)
    if s.forward then
        s.distance = s.distance + s.speed * STEP
    end
    local delta = s.lane - s.lateral
    s.lateral = s.lateral + math.max(-STEP * 7, math.min(STEP * 7, delta))
    if s.velocity ~= 0 or s.height > 0 then
        s.height = math.max(0, s.height + s.velocity * STEP - 12 * STEP * STEP)
        s.velocity = s.velocity - 24 * STEP
        if s.height == 0 then
            s.velocity = 0
        end
    end
    while s.nextRow < s.distance + 85 do
        local blocked = s.random(-1, 1)
        s.objects[#s.objects + 1] = { kind = "obstacle", lane = blocked, at = s.nextRow }
        -- One blocked lane per row; the other two always offer an escape.
        s.objects[#s.objects + 1] = { kind = "coin", lane = (blocked + 2) % 3 - 1, at = s.nextRow + 3 }
        s.nextRow = s.nextRow + 13
    end
    for i = #s.objects, 1, -1 do
        local o = s.objects[i]
        local d = o.at - s.distance
        if not o.hit and game.Overlaps(s, o) then
            if o.kind == "coin" then
                o.hit = true
                s.coins = s.coins + 1
            elseif o.kind == "obstacle" then
                s.status = "over"
                return
            end
        end
        if d < -4 then
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
