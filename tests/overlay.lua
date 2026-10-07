-- Exercise the full-screen projection, the twin and the coins without creating client UI frames.
local app = {}
for _, file in ipairs({
    "game/biomes",
    "biomes/default",
    "biomes/elwynn",
    "game/random",
    "game/simulation",
    "game/light",
    "game/shapes",
    "game/overlay",
    "game/decorations",
    "game/window",
    "game/menu",
    "game/hud",
    "game/legend",
    "game/controls",
}) do
    assert(loadfile("Surfer/src/" .. file .. ".lua"))("Surfer", app)
end
app.db = {
    global = { bestScore = 0 },
    profile = {
        biome = "elwynn",
        mode = "full",
        capture = false,
        frame = { full = false, side = true },
        side = { point = "RIGHT", relative = "RIGHT", x = -40, y = 0, width = 400, height = 480 },
        overlay = {
            twinScale = 1,
            pitch = 20,
            focus = 0.9,
            distance = 12,
            fov = 55,
            opacity = 0.85,
            brightness = 0.75,
            dayNight = true,
        },
    },
}
local settings = app.db.profile.overlay
local o, g = app.overlay, app.simulation
local W, H = 1600, 900
-- A texture the client does not have: SetTexture fails for it.
local missing = 187113
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
        SetColorTexture = function() end,
        SetVertexOffset = function() end,
        SetText = function() end,
        SetDrawLayer = function() end,
        SetTexture = function(self, id)
            self.texture = id
            return id ~= missing
        end,
        SetTexCoord = function(self, left, right, top, bottom)
            self.coords = self.coords or {}
            self.coords[1], self.coords[2], self.coords[3], self.coords[4] = left, right, top, bottom
        end,
        SetVertexColor = function(self, r, _, b, a)
            self.red, self.blue, self.alpha = r, b, a
        end,
        SetGradient = function(self, _, min, max)
            self.gradient = { min.a, max.a }
        end,
    }
end
function GetTime()
    return 0
end
local function noop() end
function CreateColor(r, g, b, a)
    return {
        r = r,
        g = g,
        b = b,
        a = a,
        SetRGBA = function(self, ...)
            self.r, self.g, self.b, self.a = ...
        end,
    }
end

-- The twin's scene and actor. Stubs reuse their tables, so the allocation check at the end
-- measures the addon only.
local scene, actor = texture(), { loaded = true, shown = false, position = {} }
scene.camera = {}
function scene:SetCameraPosition(x, y, z)
    self.camera[1], self.camera[2], self.camera[3] = x, y, z
end
function scene:SetCameraOrientationByYawPitchRoll() end
function scene:SetCameraNearClip() end
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
local function coinScene()
    local t = texture()
    t.SetYaw = function() end
    t.SetCameraPosition = function() end
    t.SetCameraOrientationByYawPitchRoll = function() end
    t.SetLightAmbientColor = function() end
    t.SetLightDiffuseColor = function() end
    t.SetModelByFileID = function()
        return true
    end
    return t
end

o.frame = {
    GetSize = function()
        return W, H
    end,
}
o.height, o.lastRoad = 2, {}
o:ApplyBiome()
o:CreateGround({ CreateTexture = texture })
o.faces = app.shapes.Pool({ CreateTexture = texture }, "BORDER")
o.twin, o.twinActor = scene, actor
o.message, o.hint = texture(), texture()
-- The score display, the start dialog and the restart bar: a widget's Create* methods make
-- another widget, its Get* methods answer 0, the rest do nothing.
local function zero()
    return 0
end
local function nothing() end
local widgetMeta = {}
local function widget()
    return setmetatable({}, widgetMeta)
end
widgetMeta.__index = function(_, name)
    if name:find("^Create") then
        return widget
    end
    return name:find("^Get") and zero or nothing
end
function CreateFrame()
    return widget()
end
o.frame.GetFrameLevel = zero
o:CreateHud(widget())
-- The hotkey legend, with the default movement bindings.
local BINDINGS = { MOVEFORWARD = { "W", "UP" }, TURNLEFT = { "A", "LEFT" }, STRAFELEFT = { "Q" }, JUMP = { "SPACE" } }
function GetBindingKey(binding)
    local keys = BINDINGS[binding]
    if keys then
        return keys[1], keys[2]
    end
end
function GetBindingText(key)
    return key
end
app.db.profile.legend = true
o:CreateLegend(widget())
o.menu, o.menuBest, o.menuHelp, o.runSeed, o.seedBox, o.holdBar =
    widget(), widget(), widget(), widget(), widget(), widget()
o.menuButtons = { widget(), widget() }
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

-- The twin: a copy in a square scene around the character, seen through the road's camera.
o.state = g.New()
o.state.objects = { obstacle(0, 0) }
o:Render()
local feetY = first().y
assert(actor.shown and actor.alpha == 0.5, "a see-through twin before the run")
assert(math.abs(actor.position[3] - 0.05) < 1e-9, "the twin's feet stand on the real feet")
assert(scene.camera[2] == 0 and scene.camera[1] < 0 and scene.camera[3] > 0, "the twin's camera follows behind")
assert(scene.x == W / 2 and scene.w == scene.h, "a square scene centred on the character")
assert(feetY < scene.y and scene.y < H / 2, "the body's middle between its feet and the camera's focus")
-- Seen from above at angle a, the twin spans height * cos(a) / side of its square frame; on
-- the road's projection the body spans about twice the distance from its feet to its middle.
local side = 1.6 * o.height
local a = math.atan2(scene.camera[3] - 1, -scene.camera[1])
local twinHeight = scene.h * o.height * math.cos(a) / side
local roadHeight = 2 * (scene.y - feetY)
assert(math.abs(twinHeight / roadHeight - 1) < 0.03, "the twin is exactly as tall as the road's projection")
assert(
    math.abs(math.tan(scene.fov / 2) * 2 * math.sqrt(scene.camera[1] ^ 2 + (scene.camera[3] - 1) ^ 2) - side) < 1e-6,
    "the scene's lens spans its frame"
)
g.Start(o.state)
o:Render()
assert(actor.alpha == 1, "the twin is fully drawn while running")
print("PASS twin stands on the real character, as tall as the road's projection")

for _, lane in ipairs({ -1, 1 }) do
    o.state.objects = { obstacle(lane, 10) }
    o:Render()
    local x = first().x + first().w / 2
    -- Positive simulation lanes are on the screen's left.
    assert((lane == 1 and x < W / 2) or (lane == -1 and x > W / 2), "obstacle lane follows the controls")
end
print("PASS lane sides")

-- Changing lanes moves the road under the character, which stays centered.
o.state.objects = { coin(0, 10) }
o:Render()
local centered = first().x
o.state.lateral = 1
o:Render()
assert(first().x > centered, "moving left slides the world to the right")
assert(scene.x == W / 2, "the character stays centered while changing lanes")
o.state.lateral = 0
print("PASS road follows the character's lane")

-- Jumping: the camera rises with the character, so it keeps its place and the road drops.
o.state.objects = { coin(1, 10) }
o:Render()
local twinY, coinY = scene.y, first().y
o.state.height = 1.5
o:Render()
assert(math.abs(scene.y - twinY) < 0.001, "the character keeps its place on screen")
assert(first().y < coinY, "the road and its objects drop while jumping")
assert(math.abs(actor.position[3] - 1.55) < 1e-9, "the twin rises on the sim's arc")
o.state.height = 0
print("PASS jumping drops the road beneath the character")

-- A platform beside the runner shows the side facing it.
o.state.objects = { g.Box("platform", 0, -5, 30, 0, 2), g.Box("platform", 1, 5, 20, 0, 1) }
local faces, count = app.shapes.Collect(o.state, 0)
local sides = 0
for i = 1, count do
    sides = sides + (faces[i].part == "side" and faces[i].object.lane == 1 and 1 or 0)
end
assert(sides > 0, "the neighbouring platform shows the side facing the runner")
print("PASS platforms show the side facing the runner")

-- The ground: Elwynn's textures, sliding toward the runner.
local function piece(kind, x, near)
    for _, t in ipairs(o.ground) do
        if t.kind == kind and t.left <= x and x < t.right and t.near <= near and near < t.far then
            return t
        end
    end
end
local road = piece("road", 0, 5)
assert(road.texture == 187099 and road.tile, "cobbles")
assert(piece("grass", 6, 5).texture == 187126 and piece("dirt", 4, 5).texture == 187114, "grass and dirt")
assert(piece("dirt", 1.2, 5) and piece("dirt", -1.2, 5), "ruts between the lanes")
o.state.distance = 0
o:Render()
local top, bottom = road.coords[3], road.coords[4]
assert(top < bottom, "the texture's top is ahead")
o.state.distance = 1
o:Render()
assert(math.abs(road.coords[4] - (bottom - 1 / road.tile)) < 1e-9, "running a yard slides the texture a yard closer")
o.state.distance = 1000 * road.tile + 0.25
o:Render()
assert(road.coords[4] > -2, "far runs keep the coordinates small")
assert(road.alpha == settings.opacity and piece("road", 0, 85).alpha < 0.2 * settings.opacity, "the far road fades out")
local cobbleEdge, grassLeft = piece("road", 4, 5), piece("grass", -8.4, 5)
assert(cobbleEdge.gradient[1] > 0 and cobbleEdge.gradient[2] == 0, "the cobbles fade out toward the side")
assert(grassLeft.gradient[1] == 0 and grassLeft.gradient[2] > 0, "the grass fades into the world on the left")
assert(
    road.gradient == nil and math.abs(piece("dirt", 1.2, 5).alpha - 0.3 * settings.opacity) < 1e-9,
    "solid road, faint ruts"
)
o.state.distance = 0
print("PASS ground textures scroll toward the runner and fade out at their edges and far ahead")

-- The ground's light follows the game's clock: bright by day, dim and blue at night.
local hour = 12
function GetGameTime()
    return hour, 0
end
o:Render()
assert(math.abs(road.red - 0.75) < 1e-9 and road.red == road.blue, "by day: the brightness setting, white")
local model = {
    SetLightAmbientColor = function(self, r, _, b)
        self.ambient = { r, b }
    end,
    SetLightDiffuseColor = function(self, r)
        self.diffuse = r
    end,
}
app.light.AddScene(model, { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 })
assert(model.ambient[1] == 0.8 and model.diffuse == 0.6, "a model scene by day: its own colors")
hour = 23
o:Render()
assert(road.red < 0.4 and road.blue > road.red, "at night: dimmer and moonlit blue")
assert(model.ambient[1] < 0.4 and model.ambient[2] > model.ambient[1], "models are relit at night")
assert(math.abs(model.ambient[1] / 0.8 - road.red / 0.75) < 1e-9, "models and ground share one light")
hour = 6
o:Render()
assert(road.red > 0.45 and road.red < 0.7, "at dawn: in between")
settings.dayNight = false
o:Render()
assert(math.abs(road.red - 0.75) < 1e-9, "without the clock: always day")
settings.dayNight, GetGameTime = true, nil
o:Render()
print("PASS the ground and 3D models share a light that follows the game's clock")

-- A texture that does not load leaves a plain color.
local fallback = {}
o.ground, missing = nil, 187099
o:CreateGround({
    CreateTexture = function()
        local t = texture()
        t.SetColorTexture = function()
            fallback[#fallback + 1] = t
        end
        return t
    end,
})
assert(#fallback > 0 and not fallback[1].tile, "a missing texture is drawn as a plain color")
missing = 187113
o:CreateGround({ CreateTexture = texture })
o.groundLight, o.lastRoad = nil, {}
print("PASS a missing ground texture falls back to a color")

-- Biomes override the default field by field; lists are replaced whole.
local biomes = app.biomes
local elwynn, plain = biomes.Get("elwynn"), biomes.Get("default")
assert(elwynn.ground.surfaces.road.texture == 187099, "a biome's own field")
assert(elwynn.ground.surfaces.road.color == plain.ground.surfaces.road.color, "the default's field beside it")
assert(elwynn.ground.bands == plain.ground.bands and elwynn.coin == plain.coin, "untouched parts are the default's")
assert(plain.ground.surfaces.road.texture == nil, "the default is not changed by a biome")
assert(biomes.Get("nowhere") == plain, "an unknown biome is the default")
biomes.Register(
    "test",
    { name = "Test", ground = { bands = { plain.ground.bands[4] } }, light = { night = { 0, 0, 0 } } }
)
local test = biomes.Get("test")
assert(#test.ground.bands == 1 and test.light.night[3] == 0 and test.coin == plain.coin, "lists are replaced whole")
assert(biomes.Names().elwynn == "Elwynn Forest" and biomes.Names().test == "Test", "names for the options")
-- Every biome builds its ground.
for id in pairs(biomes.list) do
    app.db.profile.biome = id
    o:ApplyBiome()
    assert(#o.ground > 0, id .. " builds its ground")
end
-- Switching while playing re-skins the same textures: spare ones are hidden.
app.db.profile.biome = "test"
o:ApplyBiome()
o:Render()
local used = #o.ground
assert(o.groundPool[used + 1].shown == false, "a band fewer hides its pieces")
app.db.profile.biome = "default"
o:ApplyBiome()
o:Render()
assert(piece("road", 0, 5).tile == false and app.shapes.colors == plain.shapes, "the plain biome: colors")
biomes.list.test, biomes.merged = nil, {}
app.db.profile.biome = "elwynn"
o:ApplyBiome()
assert(piece("road", 0, 5).texture == 187099, "back to Elwynn's cobbles")
print("PASS biomes override the default, and switching re-skins the running game")

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
settings.hideReal = true
o:ApplyHideReal()
assert(calls[1] == "in 50" and o.zoomedIn, "zoomed into first person")
o:UpdateCamera()
assert(o.camera.distance == 12, "in first person the twin's camera uses the distance setting")
shown = false
o:ApplyHideReal()
assert(calls[2] == "out 9" and zoom == 9 and not o.zoomedIn, "zoomed back out to the previous zoom")
settings.hideReal = false
print("PASS hiding the real character zooms into first person and back")

-- A running frame allocates nothing: no new tables or strings, so no garbage piles up.
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
