-- Exercise the full-screen projection and cutout rules without creating client UI frames.
local app = {}
assert(loadfile("Surfer/src/game/simulation.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/shapes.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/window.lua"))("Surfer", app)
assert(loadfile("Surfer/src/game/overlay.lua"))("Surfer", app)
app.db = {
    global = { bestScore = 0 },
    profile = {
        overlay = {
            character = "cutout",
            twinScale = 1,
            pitch = 20,
            focus = 0.9,
            distance = 12,
            fov = 55,
            opacity = 0.85,
            cutout = 0.8,
        },
    },
}
local o, g = app.overlay, app.simulation
local W, H = 1600, 900
local function texture()
    return {
        ClearAllPoints = function() end,
        SetPoint = function(self, _, a, b, c, d)
            self.x, self.y = c or a, d or b
        end,
        SetSize = function(self, w, h)
            self.w, self.h = w, h
        end,
        Show = function(self)
            self.shown = true
        end,
        Hide = function(self)
            self.shown = false
        end,
        SetShown = function(self, shown)
            self.shown = shown
        end,
        SetColorTexture = function() end,
        SetVertexOffset = function() end,
        AddMaskTexture = function() end,
        RemoveMaskTexture = function() end,
        SetText = function() end,
        SetDrawLayer = function() end,
    }
end
o.frame = {
    GetSize = function()
        return W, H
    end,
}
o.height, o.width = 2, 0.8
o.strips = { { texture(), texture(), texture(), texture(), texture() } }
o.faces = app.shapes.Pool({ CreateTexture = texture }, "BORDER")
-- The first face drawn: a box's front, or a flat coin.
local function first()
    return o.faces[1]
end
local function obstacle(lane, at, layer)
    return g.Box("obstacle", lane, at, 0.5, layer or 0, 1)
end
local function coin(lane, center, layer)
    return g.Box("coin", lane, center - 0.16, 0.32, layer or 1, 1)
end
o.cutouts, o.holes, o.feet = { texture(), texture(), texture() }, { {}, {}, {} }, texture()
o.lastRoad = {}
o.coins = {}
o.score, o.message, o.hint = texture(), texture(), texture()

o.state = g.New()
g.Start(o.state)
o:Render()
assert(o.feet.x == W / 2, "the character stays at the screen's horizontal center")
assert(o.feet.y < H / 2, "the feet sit below the camera's focus at the screen center")
-- The boxes are reused every frame: keep copies to compare with later frames.
local function copy(hole)
    return { left = hole.left, right = hole.right, bottom = hole.bottom, top = hole.top }
end
local head, torso, legs = copy(o.holes[1]), copy(o.holes[2]), copy(o.holes[3])
assert(o.cutouts[3].y < o.feet.y and legs.bottom == o.feet.y, "the legs cutout reaches the feet")
assert(legs.top > torso.bottom and torso.top > head.bottom, "the parts overlap without seams")
assert(head.right - head.left < torso.right - torso.left, "the head is narrower than the shoulders")
print("PASS character anchor and body cutout placement")

-- Running bobs and sways the cutout; a jump tucks the legs in.
o.state.forward, o.clock = true, 0.1
o:Render()
assert(o.holes[2].bottom > torso.bottom and o.holes[2].left ~= torso.left, "running bobs and sways")
o.state.forward, o.state.height = false, 0.5
o:Render()
assert(o.holes[3].bottom > o.feet.y, "a jump tucks the legs in")
o.state.height = 0
print("PASS run cycle and jump tuck")

for _, lane in ipairs({ -1, 1 }) do
    o.state.objects = { obstacle(lane, 10) }
    o:Render()
    local x = first().x + first().w / 2
    -- Positive simulation lanes are on the screen's left, as in the window view.
    assert((lane == 1 and x < W / 2) or (lane == -1 and x > W / 2), "obstacle lane follows the controls")
    assert(first().surferBehind, "an obstacle ahead is behind the character")
end
o.state.objects = { obstacle(0, -1) }
o:Render()
assert(not first().surferBehind, "a passed obstacle is drawn over the character")
print("PASS lane sides and behind/in-front masking")

-- Changing lanes moves the road under the character, which stays centered.
o.state.objects = { coin(0, 10) }
o:Render()
local centered = first().x
o.state.lateral = 1
o:Render()
assert(first().x > centered, "moving left slides the world to the right")
assert(o.feet.x == W / 2, "the character stays centered while changing lanes")
print("PASS road follows the character's lane")

-- 3D coins cannot be masked: one behind the body hides, one beside it or passed stays visible.
function GetTime()
    return 0
end
local function stub()
    local t = texture()
    t.SetYaw = function() end
    t.SetCameraPosition = function() end
    t.SetCameraOrientationByYawPitchRoll = function() end
    return t
end
o.coins = { { scene = stub(), actor = stub() } }
o.coinReady = true
o.state.lateral = 0
for _, case in ipairs({
    { lane = 0, at = 1, shown = false },
    { lane = 1, at = 1, shown = true },
    { lane = 0, at = -1, shown = true },
}) do
    o.state.objects = { coin(case.lane, case.at) }
    o:Render()
    assert(o.coins[1].actor.shown == case.shown, "3D coin visibility around the character")
    assert(not first().shown, "a loaded coin model replaces the flat coin")
end
o.state.objects = {}
o:Render()
assert(not o.coins[1].actor.shown, "unused coin scenes hide their model")
print("PASS 3D coins hide behind the character and replace flat coins")

-- Jumping: the camera rises with the character, so it keeps its place and the road drops.
o.coinReady = false
o.state.objects = { coin(1, 10) }
o.state.height = 0
o:Render()
local feetY, coinY = o.feet.y, first().y
o.state.height = 1.5
o:Render()
assert(math.abs(o.feet.y - feetY) < 0.001, "the character keeps its place on screen")
assert(first().y < coinY, "the road and its objects drop while jumping")
print("PASS jumping drops the road beneath the character")

-- A platform under the runner: its top in front of the feet is drawn over the character, the
-- part behind them is masked; the side facing the runner shows.
o.state.height, o.state.floor = 2 * g.LAYER, 2 * g.LAYER
o.state.objects = { g.Box("platform", 0, -5, 30, 0, 2), g.Box("platform", 1, 5, 20, 0, 1) }
o:Render()
local before, after, sides = 0, 0, 0
for i = 1, #o.faces do
    local t = o.faces[i]
    if t.shown then
        before = before + ((t.surferBehind == false) and 1 or 0)
        after = after + (t.surferBehind and 1 or 0)
    end
end
local faces, count = app.shapes.Collect(o.state, -o.state.lateral * g.geometry.laneWidth)
for i = 1, count do
    sides = sides + (faces[i].part == "side" and 1 or 0)
end
assert(before > 0 and after > 0, "the platform splits at the runner")
assert(sides > 0, "the neighbouring platform shows the side facing the runner")
print("PASS platforms split at the runner and show their sides")

-- The twin: a copy in a full-screen scene with the road's camera, standing on the real feet.
local settings = app.db.profile.overlay
settings.character = "twin"
local scene, actor = texture(), { loaded = true, shown = false }
-- Stubs reuse their tables, so the allocation check below measures the addon only.
scene.camera = {}
function scene:SetCameraPosition(x, y, z)
    self.camera[1], self.camera[2], self.camera[3] = x, y, z
end
function scene:SetCameraOrientationByYawPitchRoll() end
function scene:SetCameraFieldOfView(fov)
    self.fov = fov
end
function actor:IsLoaded()
    return self.loaded
end
function actor:GetActiveBoundingBox()
    return -0.3, -0.4, -0.05, 0.3, 0.4, 1.9
end
function actor:SetScale(scale)
    self.scale = scale
end
actor.position = {}
function actor:SetPosition(x, y, z)
    self.position[1], self.position[2], self.position[3] = x, y, z
end
function actor:SetAnimation(animation, _, rate)
    self.animation, self.rate = animation, rate
end
function actor:SetYaw(yaw)
    self.yaw = yaw
end
function actor:SetAlpha(alpha)
    self.alpha = alpha
end
function actor:Show()
    self.shown = true
end
function actor:Hide()
    self.shown = false
end
o.twin, o.twinActor = scene, actor
o.coins = {}
o.state = g.New()
o.state.objects = {}
o:Render()
assert(actor.shown and actor.alpha == 0.5, "a see-through twin before the run")
assert(math.abs(actor.position[3] - 0.05) < 1e-9, "the twin's feet stand on the real feet")
assert(scene.camera[2] == 0 and scene.camera[1] < 0 and scene.camera[3] > 0, "the twin's camera follows behind")
assert(scene.x == W / 2 and scene.w == scene.h, "a square scene centred on the character")
-- Seen from above at angle a, the twin spans height * cos(a) / side of its square frame; on
-- the road's projection the body spans about twice the distance from its feet to its middle.
local side = 1.6 * o.height
local a = math.atan2(scene.camera[3] - 1, -scene.camera[1])
local twinHeight = scene.h * o.height * math.cos(a) / side
local roadHeight = 2 * (scene.y - o.feet.y)
assert(math.abs(twinHeight / roadHeight - 1) < 0.03, "the twin is exactly as tall as the road's projection")
assert(
    math.abs(math.tan(scene.fov / 2) * 2 * math.sqrt(scene.camera[1] ^ 2 + (scene.camera[3] - 1) ^ 2) - side) < 1e-6,
    "the scene's lens spans its frame"
)
g.Start(o.state)
o:Render()
assert(actor.alpha == 1, "the twin is fully drawn while running")
o.state.height = 0.5
o:Render()
assert(math.abs(actor.position[3] - 0.55) < 1e-9, "the twin rises on the sim's arc")
o.state.height = 0
o.state.objects = { obstacle(0, 10) }
o:Render()
assert(not first().surferBehind, "with the twin the road needs no cutout")
settings.character = "cutout"
o:Render()
assert(not actor.shown, "the cutout mode hides the twin")
print("PASS twin stands on the real character, on the sim's arc, and replaces the cutout")

-- The twin mirrors how the real character moves, as a player holds the keys.
local falling = false
function IsFalling()
    return falling
end
local function hold(forward, left, speed, seconds)
    o.motion = { forward = forward, left = left, speed = speed }
    for _ = 1, seconds * 20 do
        o:AnimateTwin(0.05)
    end
end
hold(0, 0, 0, 0.5)
assert(actor.animation == 0 and math.abs(actor.yaw) < 1e-6, "standing still, facing ahead")
hold(7, 0, 7, 1)
assert(actor.animation == 5 and math.abs(actor.rate - 1) < 1e-9 and math.abs(actor.yaw) < 0.01, "running ahead")
hold(0, 7, 7, 1)
assert(actor.animation == 5 and math.abs(actor.yaw - math.pi / 2) < 0.05, "strafing left turns the body left")
hold(4.95, -4.95, 7, 1)
assert(math.abs(actor.yaw + math.pi / 4) < 0.05, "a forward-right diagonal turns it halfway right")
hold(-4.5, 0, 4.5, 1)
assert(actor.animation == 13 and math.abs(actor.yaw) < 0.05, "backpedalling faces ahead")
hold(2.5, 0, 2.5, 1)
assert(actor.animation == 4 and math.abs(actor.rate - 1) < 1e-9, "walking at walking speed")
hold(7, 0, 7, 1)
falling = true
hold(7, 0, 7, 0.1)
assert(actor.animation == 37, "a jump starts")
hold(7, 0, 7, 0.7)
assert(actor.animation == 37, "a normal jump keeps its own animation, rising and falling")
hold(7, 0, 7, 0.5)
assert(actor.animation == 38, "a long fall loops in the air")
falling = false
hold(0, 0, 0, 0.1)
assert(actor.animation == 39, "and lands")
hold(0, 0, 0, 0.5)
assert(actor.animation == 0, "then stands")
hold(7, 0, 7, 0.5)
local rate = actor.rate
hold(7, 0, 7.2, 0.5)
assert(actor.rate == rate, "small speed changes do not restart the animation")
print("PASS twin mirrors standing, running, strafing, backpedalling, walking and jumping")

-- Hiding the real character zooms into first person while the view is open, and back out.
local zoom, calls = 9, {}
function GetCameraZoom()
    return zoom
end
function CameraZoomIn(n)
    calls[#calls + 1] = "in " .. n
    zoom = 0
end
function CameraZoomOut(n)
    calls[#calls + 1] = "out " .. n
    zoom = n
end
local shown = true
o.frame.IsShown = function()
    return shown
end
settings.character, settings.hideReal = "twin", true
o:ApplyHideReal()
assert(calls[1] == "in 50" and o.zoomedIn, "zoomed into first person")
o:UpdateCamera()
assert(o.camera.distance == 12, "in first person the twin's camera uses the distance setting")
shown = false
o:ApplyHideReal()
assert(calls[2] == "out 9" and zoom == 9 and not o.zoomedIn, "zoomed back out to the previous zoom")
print("PASS hiding the real character zooms into first person and back")

-- A running frame allocates nothing: no new tables or strings, so no garbage piles up.
settings.character, settings.hideReal = "twin", false
o.state = g.New()
o.state.nextRow = math.huge
o.state.objects = {
    obstacle(0, 10),
    coin(1, 12),
    g.Box("platform", -1, 5, 30, 0, 2, 8),
    g.Box("barrier", 0, 20, 0.4, 3, 1),
}
g.Start(o.state)
o.state.forward, o.state.distance = true, 0.5
o.motion = { forward = 7, left = 0, speed = 7 }
local function frame()
    o.state.distance = o.state.distance + 0.001
    o.state.lateral = (o.state.lateral + 0.01) % 1
    o:AnimateTwin(0.016)
    o:Render()
end
-- One full sideways cycle first: the face and texture pools grow once to the most faces seen.
for _ = 1, 150 do
    frame()
end
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 300 do
    frame()
end
local grown = collectgarbage("count") - before
collectgarbage("restart")
assert(grown < 0.5, string.format("300 frames allocated %.2f KB", grown))
print(string.format("PASS 300 running frames allocate nothing (%.2f KB)", grown))
