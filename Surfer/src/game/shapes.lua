---@type string, Surfer
local _, app = ...
local sim = app.simulation
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- The visible faces of the track's boxes, shared by both views. A face is four corners
-- (upper left, lower left, upper right, lower right), each (d, x, z): yards ahead of the
-- runner, yards to the screen's right of the track's center, yards up including the curve.
local shapes = {}
app.shapes = shapes
-- Faces closer than this are not drawn; farther than DRAW_DISTANCE neither.
local NEAR, DRAW_DISTANCE = -3, 85

-- The track curves down and away toward the horizon.
function shapes.Ground(d)
    return -0.0005 * math.max(d, 0) ^ 2
end
local ground = shapes.Ground

-- Colors by kind and part.
shapes.colors = {
    obstacle = { front = { 0.9, 0.29, 0.17 }, top = { 1, 0.48, 0.25 }, side = { 0.68, 0.2, 0.12 } },
    barrier = { front = { 0.95, 0.72, 0.18 }, top = { 1, 0.85, 0.4 }, side = { 0.7, 0.5, 0.1 } },
    post = { front = { 0.55, 0.58, 0.6 } },
    platform = { front = { 0.2, 0.42, 0.72 }, top = { 0.32, 0.58, 0.88 }, side = { 0.14, 0.32, 0.58 } },
    coin = { front = { 1, 0.77, 0.2 } },
}

local out, count = {}, 0
local function add(object, kind, part, behind, depth, ...)
    count = count + 1
    local f = out[count] or {}
    out[count] = f
    f.object, f.kind, f.part, f.behind, f.depth = object, kind, part, behind, depth
    f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12] = ...
end

-- Box faces between d = a and b: its top and the side the camera sees.
local function segment(o, s, viewX, x1, x2, a, b)
    local bottom = o.layer * sim.LAYER
    local ta, tb = sim.Top(o, a + s.distance) + ground(a), sim.Top(o, b + s.distance) + ground(b)
    local ba, bb = bottom + ground(a), bottom + ground(b)
    local behind = a >= 0
    add(o, o.kind, "top", behind, a, b, x1, tb, a, x1, ta, b, x2, tb, a, x2, ta)
    -- On the screen, a side's near edge lies farther out than its far edge.
    if viewX < x1 then
        add(o, o.kind, "side", behind, a, b, x1, tb, b, x1, bb, a, x1, ta, a, x1, ba)
    elseif viewX > x2 then
        add(o, o.kind, "side", behind, a, a, x2, ta, a, x2, ba, b, x2, tb, b, x2, bb)
    end
end

-- A barrier's post at `left`, from the ground up to the bar's bottom `z`.
local POST = 0.08
local function post(o, near, left, z)
    local floor, right = ground(near), left + POST
    add(o, "post", "front", near > 0, near, near, left, z, near, left, floor, near, right, z, near, right, floor)
end

-- Reused by every box: the points where its faces split.
local cuts = {}

local function box(o, s, viewX)
    local near, far = o.at - s.distance, o.at + o.length - s.distance
    if far < NEAR or near > DRAW_DISTANCE then
        return
    end
    local x = -o.lane * LANE
    local half = bounds.halfWidth[o.kind]
    local x1, x2 = x - half, x + half
    local bottom = o.layer * sim.LAYER
    if near >= NEAR then
        local z, top = bottom + ground(near), sim.Top(o, o.at) + ground(near)
        if top - z > 0.01 then
            add(o, o.kind, "front", near > 0, near, near, x1, top, near, x1, z, near, x2, top, near, x2, z)
        end
        if o.kind == "barrier" then
            -- Posts from the ground to the bar, for looks only.
            post(o, near, x1, z)
            post(o, near, x2 - POST, z)
        end
    end
    -- Split where a ramp ends and at the runner, so the part behind it can be masked.
    local a, b = math.max(near, NEAR), math.min(far, DRAW_DISTANCE)
    local n = 2
    cuts[1], cuts[2] = a, b
    local rampEnd = o.ramp and near + o.ramp
    if rampEnd and rampEnd > a and rampEnd < b then
        n = n + 1
        cuts[n] = rampEnd
    end
    if a < 0 and b > 0 then
        n = n + 1
        cuts[n] = 0
    end
    -- At most four values: an insertion sort, without a comparison closure.
    for i = 2, n do
        local value, j = cuts[i], i - 1
        while j >= 1 and cuts[j] > value do
            cuts[j + 1] = cuts[j]
            j = j - 1
        end
        cuts[j + 1] = value
    end
    for i = 1, n - 1 do
        segment(o, s, viewX, x1, x2, cuts[i], cuts[i + 1])
    end
end

local function coin(o, s)
    local d = o.at + o.length / 2 - s.distance
    if d < NEAR or d > DRAW_DISTANCE then
        return
    end
    local x, z = -o.lane * LANE, (o.layer + 0.5) * sim.LAYER + ground(d)
    local left, right = x - bounds.halfWidth.coin, x + bounds.halfWidth.coin
    local bottom, top = z - bounds.coinSize / 2, z + bounds.coinSize / 2
    add(o, "coin", "front", d - o.length / 2 > 0, d, d, left, top, d, left, bottom, d, right, top, d, right, bottom)
end

-- The faces of every box and coin in view, reusing the same tables every frame. `viewX` is
-- the camera's position to the screen's right, which decides the sides it sees.
function shapes.Collect(s, viewX)
    count = 0
    for _, o in ipairs(s.objects) do
        if not o.hit then
            if o.kind == "coin" then
                coin(o, s)
            else
                box(o, s, viewX)
            end
        end
    end
    return out, count
end

-- Platform tops lie under everything else; other faces draw nearer over farther.
function shapes.Sublevel(f)
    if f.kind == "platform" and f.part == "top" then
        return -8
    end
    return 7 - math.min(14, math.floor(math.max(f.depth, 0) / 6))
end

-- Show and hide only on a change: every call into the client costs, even one that changes
-- nothing. Textures shown and hidden here keep their state in `surferShown`.
function shapes.Show(t)
    if not t.surferShown then
        t:Show()
        t.surferShown = true
    end
end

function shapes.Hide(t)
    if t.surferShown ~= false then
        t:Hide()
        t.surferShown = false
    end
end

-- Fits texture `t` to the face's projected corners; hidden when a corner cannot be projected.
-- Its only anchor is BOTTOMLEFT, which SetPoint replaces, so no ClearAllPoints.
-- `project(d, x, z)` returns screen x, y in the texture parent's coordinates.
function shapes.Draw(t, project, f)
    local x1, y1 = project(f[1], f[2], f[3])
    local x2, y2 = project(f[4], f[5], f[6])
    local x3, y3 = project(f[7], f[8], f[9])
    local x4, y4 = project(f[10], f[11], f[12])
    if not (x1 and x2 and x3 and x4) then
        shapes.Hide(t)
        return false
    end
    local left, right = math.min(x1, x2, x3, x4), math.max(x1, x2, x3, x4)
    local bottom, top = math.min(y1, y2, y3, y4), math.max(y1, y2, y3, y4)
    t:SetPoint("BOTTOMLEFT", left, bottom)
    t:SetSize(math.max(right - left, 0.01), math.max(top - bottom, 0.01))
    t:SetVertexOffset(1, x1 - left, y1 - top)
    t:SetVertexOffset(2, x2 - left, y2 - bottom)
    t:SetVertexOffset(3, x3 - right, y3 - top)
    t:SetVertexOffset(4, x4 - right, y4 - bottom)
    local color = shapes.colors[f.kind][f.part]
    if t.surferColor ~= color then
        t:SetColorTexture(color[1], color[2], color[3], 0.95)
        t.surferColor = color
    end
    shapes.Show(t)
    return true
end

-- Textures handed out in order each frame; Release hides the ones this frame did not use.
function shapes.Pool(parent, layer)
    return { parent = parent, layer = layer, used = 0 }
end

function shapes.Acquire(pool, sublevel)
    pool.used = pool.used + 1
    local t = pool[pool.used]
    if not t then
        t = pool.parent:CreateTexture(nil, pool.layer)
        pool[pool.used] = t
    end
    if t.surferSublevel ~= sublevel then
        t:SetDrawLayer(pool.layer, sublevel)
        t.surferSublevel = sublevel
    end
    return t
end

function shapes.Release(pool)
    for i = pool.used + 1, #pool do
        shapes.Hide(pool[i])
    end
    pool.used = 0
end
