-- Exercise the full-screen projection, the twin and the coins without creating client UI frames.
local app = {}
dofile("tests/load.lua")(app, {
    "game/biomes",
    "biomes/default",
    "biomes/elwynn",
    "scenes/lobby",
    "biomes/durotar",
    "biomes/teldrassil",
    "biomes/tirisfal",
    "biomes/transitions/dream",
    "game/random",
    "game/scoring",
    "game/simulation",
    "game/challenges",
    "game/leaderboard",
    "game/track",
    "patterns/patterns.xml",
    "game/autopilot",
    "game/light",
    "game/shapes",
    "game/overlay",
    "game/decorations",
    "game/occluder",
    "game/window",
    "game/keys",
    "game/menu",
    "game/hud",
    "game/legend",
    "game/messages",
    "game/menus",
    "game/screens",
    "game/controls",
})
app.db = {
    global = { bestScore = 0, challenges = {}, leaderboard = {} },
    profile = {
        biome = "elwynn",
        mode = "full",
        capture = false,
        frame = { full = false, side = true },
        hud = { position = "menu", x = 0, y = 0 },
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
function actor:SetAnimation(animation, variation, rate)
    self.variation = variation
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
o.height, o.body, o.bodyScale, o.lastRoad = 2, 2, 1, {}
o:ApplyBiome()
o:CreateGround({ CreateTexture = texture })
o.faces = app.shapes.Pool({ CreateTexture = texture }, "BORDER")
-- The twin: an actor of the world scene; `scene` stands in for its square on the screen.
o.twinAnchor, o.twinActor = scene, actor
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
do
    local function frame()
        return {
            SetFixedFrameStrata = function() end,
            SetFixedFrameLevel = function() end,
            SetFrameStrata = function(self, value)
                self.strata = value
            end,
            SetFrameLevel = function(self, value)
                self.level = value
            end,
            GetFrameLevel = function(self)
                return self.level
            end,
        }
    end
    local root, world, menu = frame(), frame(), frame()
    local view = setmetatable({ frame = root, stacked = { [world] = "world", [menu] = "menu" } }, { __index = o })
    local strata, level = app.db.profile.drawStrata, app.db.profile.drawLevel
    for _, side in ipairs({ false, true }) do
        view.side = side
        for _, layer in ipairs({ "LOW", "MEDIUM", "HIGH" }) do
            app.db.profile.drawStrata, app.db.profile.drawLevel = layer, 100
            view:Restack()
            assert(root.strata == layer and world.strata == layer and menu.strata == layer)
            assert(root.level == 100 and world.level == 102 and menu.level == 125, "relative levels survive restacking")
        end
    end
    app.db.profile.drawStrata, app.db.profile.drawLevel = strata, level
end
print("PASS configurable draw strata and base level in both display modes")
o:CreateLegend(widget())
-- Legend and menu hints reuse caps when the input device changes.
do
    local cap = o.KeyCap(widget())
    local iconShown, label
    cap.icon.SetShown = function(_, shown)
        iconShown = shown
    end
    cap.text.SetText = function(_, text)
        label = text
    end
    for _ = 1, 2 do
        o.SetKeyCap(cap, nil, "A")
        assert(iconShown == false and label == "A", "keyboard hint hides the controller icon")
        o.SetKeyCap(cap, nil, "|A:Gamepad_Face_Down:22:22|a")
        assert(iconShown == true and label == "", "controller hint clears the keyboard label")
        o.SetKeyCap(cap, nil, "D")
        assert(iconShown == false and label == "D", "switching back hides the old controller icon")
    end
end
print("PASS reused key caps switch between keyboard and controller without overlap")
o:CreateMessages(widget())
o:CreateScreens(widget())
-- The portal's wind measures the view.
o.vortex.parent = o.frame
o:CreateHoldBar(widget())
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

-- The twin: a copy of the character in the world scene at the runner, its square on the screen
-- around the body.
o.state = g.New()
o.state.objects = { obstacle(0, 0) }
o:Render()
local feetY = first().y
assert(actor.shown and actor.alpha == 0.5, "a see-through twin before the run")
assert(math.abs(actor.position[3] - 0.05) < 1e-9, "the twin's feet stand on the real feet")
assert(actor.position[1] == 0 and actor.position[2] == 0, "at the runner, in the middle lane")
assert(scene.x == W / 2 and scene.w == scene.h, "a square centred on the character")
assert(feetY < scene.y and scene.y < H / 2, "the body's middle between its feet and the camera's focus")
o.state.lateral = 1
o:Render()
assert(math.abs(actor.position[2] * actor.scale - 2.4) < 1e-9, "in the left lane: the scene's y points left")
o.state.lateral = 0
o:Render()
g.Start(o.state)
o:Render()
assert(actor.alpha == 1, "the twin is fully drawn while running")
print("PASS twin stands on the real character, in the world scene at the runner")

do
    local objects, distance, zoom = o.state.objects, o.state.distance, settings.distance
    local missed = coin(1, -5)
    o.state.objects, o.state.distance, settings.distance = { missed }, 0, 24
    o:Render()
    assert(o.faceCount > 0, "a missed coin behind the runner still renders at wide zoom")
    missed.hit = true
    o:Render()
    assert(o.faceCount == 0, "collected coins disappear immediately")
    missed.hit, missed.at = false, -30
    o:Render()
    assert(o.faceCount == 0, "coins behind the camera are culled")
    o.state.objects, o.state.distance, settings.distance = objects, distance, zoom
    o:Render()
end
print("PASS missed coins remain visible behind the runner until past the camera")

do
    local objects, distance, zoom = o.state.objects, o.state.distance, settings.distance
    local passed = obstacle(1, -6)
    o.state.objects, o.state.distance, settings.distance = { passed }, 0, 24
    o:Render()
    assert(o.faceCount > 0, "a passed obstacle behind the runner still renders at wide zoom")
    passed.at = -30
    o:Render()
    assert(o.faceCount == 0, "obstacles behind the camera are culled")
    o.state.objects, o.state.distance, settings.distance = objects, distance, zoom
    o:Render()
end
print("PASS passed obstacles remain visible behind the runner until past the camera")

-- A tall character (2.5 yards) is drawn at a human's height in the track's world, the camera
-- nearer by as much: on the screen it covers the real one just as before, and the track around
-- it is bigger.
o.height, o.body, o.bodyScale, o.lastRoad = 2.5, 2.5, 1, {}
o:Render()
local realX, realY, realSize, realWidth = scene.x, scene.y, scene.h, first().w
o.body, o.bodyScale, o.lastRoad = 2, 1.25, {}
o:Render()
assert(math.abs(scene.h / realSize - 1) < 1e-9, "the twin is as big on the screen as the real character")
assert(math.abs(scene.x - realX) < 1e-6 and math.abs(scene.y - realY) < 1e-6, "and where it stands")
assert(
    math.abs(actor.scale - math.sqrt(2) / 1.25) < 1e-9,
    "the twin itself is smaller (its size, overlay.lua's TWIN_SIZE)"
)
assert(first().w > realWidth * 1.15, "the track is drawn bigger around it")
o.height, o.body, o.bodyScale, o.lastRoad = 2, 2, 1, {}
o:Render()
print("PASS a tall character keeps its size on the screen, the track grows around it")

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
assert(math.abs(actor.position[3] - (1.5 / actor.scale + 0.05)) < 1e-9, "the twin rises on the sim's arc")
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
local farRoad = piece("road", 0, 133)
assert(
    road.alpha == settings.opacity and (not farRoad.shown or farRoad.alpha < 0.2 * settings.opacity),
    "the far road fades out"
)
local cobbleEdge, grassLeft = piece("road", 4, 5), piece("grass", -10.8, 5)
assert(cobbleEdge.gradient[1] > 0 and cobbleEdge.gradient[2] == 0, "the cobbles fade out toward the side")
assert(grassLeft.gradient[1] == 0 and grassLeft.gradient[2] > 0, "the grass fades into the world on the left")
assert(
    road.gradient == nil and math.abs(piece("dirt", 1.2, 5).alpha - 0.3 * settings.opacity) < 1e-9,
    "solid road, faint ruts"
)
o.state.distance = 0
print("PASS ground textures scroll toward the runner and fade out at their edges and far ahead")

-- Pieces nobody sees cost no calls: behind a close camera, then shown again once it backs off.
do
    local distance = settings.distance
    local behind = piece("road", 0, -4)
    settings.distance = 2
    o:Render()
    assert(behind.shown == false, "a piece behind the camera is hidden")
    local coords = behind.coords[4]
    o.state.distance = 1.5
    o:Render()
    assert(behind.coords[4] == coords, "a hidden piece's texture does not scroll")
    settings.distance = 24
    o:Render()
    assert(behind.shown, "it shows once the camera backs off")
    assert(math.abs(behind.coords[4] + (behind.near + 1.5) / behind.tile) < 1e-9, "with the texture where it belongs")
    settings.distance, o.state.distance = distance, 0
    o:Render()
end
print("PASS ground pieces off the screen are hidden and not updated")

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
-- Menu scenery must not prepopulate the first zone with the lobby's wooden fences.
do
    local probe = setmetatable({
        state = { seed = 17, distance = 0, status = "ready", lobby = { rim = 50, items = {} } },
        biome = app.biomes.Get("lobby"),
        decorLens = { calibrated = true },
        decor = {},
        decorNext = {},
        decorRandom = { [-1] = app.random.New(1), [1] = app.random.New(1) },
        gateRandom = app.random.New(1),
    }, { __index = app.overlay })
    local queries = 0
    function probe:BiomeAt(at)
        assert(self.state.status == "running", "no procedural lobby scenery beyond the portal before launch")
        assert(at >= self.state.lobby.rim, "the first zone starts beyond the lobby")
        queries = queries + 1
        return { decorations = { groups = {} } }
    end
    function probe:StripEnd()
        return nil
    end
    probe:UpdateDecorations()
    local left, right = probe.decorNext[-1], probe.decorNext[1]
    probe:UpdateDecorations()
    assert(
        queries == 0 and probe.decorNext[-1] == left and probe.decorNext[1] == right,
        "menu keeps zone scenery pending"
    )
    probe.state.status = "running"
    probe:UpdateDecorations()
    assert(
        queries > 0 and probe.decorNext[-1] > left and probe.decorNext[1] > right,
        "launch generates pending zone scenery"
    )
end

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

-- Auto: a run goes from zone to zone, its way set by its seed. Two zones more per tier here.
for _, extra in ipairs({ { "hills", 2 }, { "marsh", 2 }, { "peaks", 3 }, { "wastes", 3 } }) do
    biomes.Register(extra[1], { name = extra[1], tier = extra[2] })
end
local tierOf = { elwynn = 1, durotar = 1, teldrassil = 1, tirisfal = 1, hills = 2, marsh = 2, peaks = 3, wastes = 3 }
-- Gates every 1000 yards, as a run through zones lays them out (simulation.lua).
local gates = {}
for k = 1, 40 do
    gates[k] = k * 1000
end
local function route(seed, count)
    local r, ids = biomes.Route(seed, gates), {}
    for k = 1, count do
        ids[k] = biomes.ZoneAt(r, k * 1000 - 500)
    end
    return ids, r
end
for seed = 1, 200 do
    local ids, r = route(seed, 30)
    assert(tierOf[ids[1]] == 1, "a run starts in a starter zone")
    local since = {}
    for k = 2, #ids do
        assert(ids[k] ~= ids[k - 1], "never the zone just left again")
        assert(tierOf[ids[k]] <= tierOf[ids[k - 1]] + 1, "no tier skipped on the way up")
    end
    -- Within a tier, both zones before either one a third time.
    for _, id in ipairs(ids) do
        since[id] = (since[id] or 0) + 1
        for other, tier in pairs(tierOf) do
            if tier == tierOf[id] and other ~= id then
                assert(since[id] - (since[other] or 0) <= 1, "unvisited zones of a tier first")
            end
        end
    end
    local zone = biomes.Zone(r, 2500)
    assert(
        zone.id == ids[3] and zone.from == 2000 and zone.to == 3000,
        "a zone runs from gate to gate, also going back"
    )
    assert(biomes.Zone(r, -5).from == -math.huge, "the first zone has no gate")
end
local a, b = route(7, 20), route(7, 20)
assert(table.concat(a, " ") == table.concat(b, " "), "a seed always goes the same way")
local climbed = 0
for seed = 1, 200 do
    local ids = route(seed, 3)
    climbed = climbed + (tierOf[ids[2]] == 2 and 1 or 0)
end
assert(climbed > 120, "mostly up a tier after the first zone")
for _, id in ipairs({ "hills", "marsh", "peaks", "wastes" }) do
    biomes.list[id] = nil
end
biomes.merged, biomes.zones = {}, nil
print("PASS auto: starter zones first, up the tiers, unvisited zones first, the seed's way")

-- The twin mirrors how the real character moves, as a player holds the keys.
local falling = false
local playerRace = "Human"
local playerSex = 2
function UnitSex()
    return playerSex
end
function UnitRace()
    return playerRace, playerRace
end
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

playerRace = "NightElf"
local seen = {}
for i = 1, 30 do
    falling = true
    hold(0, 0, 0, 0.1)
    local variation = actor.variation
    assert(actor.animation == 37 and (variation == 0 or variation == 1), "night elf jump variation")
    seen[variation] = true
    hold(0, 0, 0, 0.6)
    assert(actor.variation == variation, "jump choice stays fixed in the air")
    hold(0, 0, 0, 0.5)
    assert(actor.animation == 38 and actor.variation == 0, "long fall uses the standard loop")
    falling = false
    hold(0, 0, 0, 0.1)
    assert(actor.animation == 39 and actor.variation == 0, "landing clears the jump variation")
end
assert(seen[0] and seen[1], "night elves use both jump variants")
for _, race in ipairs({ "NightElf", "BloodElf", "VoidElf", "Worgen", "Vulpera", "Human" }) do
    for _, sex in ipairs({ 2, 3 }) do
        playerRace, playerSex = race, sex
        local variants = {}
        for i = 1, 30 do
            falling = true
            hold(0, 0, 0, 0.1)
            variants[actor.variation] = true
            falling = false
            hold(0, 0, 0, 0.1)
        end
        local alternate = race == "NightElf"
            or race == "Worgen"
            or race == "Vulpera"
            or (race == "BloodElf" or race == "VoidElf") and sex == 3
        assert(variants[0], "every race and sex can use the normal jump")
        assert(not not variants[1] == alternate, "alternate jump is restricted by race and sex")
    end
end
playerRace = "Human"
falling = true
hold(0, 0, 0, 0.1)
assert(actor.animation == 37 and actor.variation == 0, "other races keep the normal jump")
falling = false
hold(0, 0, 0, 0.5)
print("PASS race-specific jump variants persist until landing or a long fall")

-- The runner's camera neither reads nor changes WoW's zoom.
function GetCameraZoom()
    error("the game camera must be independent of WoW's zoom")
end
function CameraZoomIn()
    error("the addon must not change WoW's camera")
end
CameraZoomOut = CameraZoomIn
local shown = false
o.frame.IsShown = function()
    return shown
end
o:UpdateCamera()
assert(o.camera.distance == settings.distance, "the game uses its own zoom")
do
    local width, height = W, H
    local distance, playerHeight, bodyScale = settings.distance, o.state.height, o.bodyScale
    local pitch, fov = settings.pitch, settings.fov
    settings.pitch, settings.fov = 20, 55
    for _, aspect in ipairs({ 16 / 9, 21 / 9, 32 / 9 }) do
        W, H = 1080 * aspect, 1080
        for _, scale in ipairs({ 0.7, 1, 1.5 }) do
            o.bodyScale = scale
            for _, zoom in ipairs({ 2, 6, 12, 18, 24 }) do
                settings.distance = zoom
                for _, rise in ipairs({ 0, 1.64, 3.44 }) do
                    o.state.height = rise
                    o:Render()
                    local covered = false
                    for _, t in ipairs(o.ground) do
                        if t.kind == "road" and t.left <= 0 and t.right > 0 and t.shown then
                            if t.y <= -32 + 1e-6 and t.y + t.h >= -32 - 1e-6 then
                                covered = true
                            end
                        end
                    end
                    assert(
                        covered,
                        string.format(
                            "foreground coverage: aspect %.2f, scale %.2f, zoom %.2f, rise %.2f",
                            aspect,
                            scale,
                            zoom,
                            rise
                        )
                    )
                end
            end
        end
    end
    o.state.height, o.bodyScale = 0, 1
    settings.distance = 12
    o:Render()
    local size = scene.h
    o:Zoom(1)
    o:Render()
    assert(settings.distance == 11 and scene.h > size, "wheel up enlarges the character by one yard")
    o:Zoom(100)
    assert(settings.distance == 2, "zoom stops at shoulder view")
    o:Zoom(-100)
    assert(settings.distance == 24, "zoom out stops at the wide overview")
    W, H = width, height
    settings.distance, o.state.height, o.bodyScale = distance, playerHeight, bodyScale
    settings.pitch, settings.fov = pitch, fov
    o:Render()
end
print("PASS independent zoom and foreground coverage at 16:9, 21:9 and 32:9 during jumps")

-- An announcement lives through its first frame (made and shown at the same time), its fades
-- and its hold, and no longer.
local now = 100
function GetTime()
    return now
end
o:Announce("Elwynn Forest", 2)
o:ShowBanner()
assert(o.banner.start, "an announcement survives the frame it was made in")
now = 100 + 0.3 + 2 + 0.6
o:ShowBanner()
assert(o.banner.start, "still fading out")
now = 100 + 0.3 + 2 + 0.7
o:ShowBanner()
assert(not o.banner.start, "gone after its fade out")
-- A challenge's last portal: its banner, and the fanfare unless portal sounds are off.
local fanfares, said = 0, {}
local banner = o.banner
local setText, setSmall, setAlpha = banner.text.SetText, banner.small.SetText, banner.frame.SetAlpha
function banner.text:SetText(text)
    said.text = text
end
function banner.small:SetText(text)
    said.small = text
end
function banner.frame:SetAlpha(alpha)
    said.alpha = alpha
end
local playSound = PlaySoundFile
function PlaySoundFile(file, channel)
    assert(file == 567431 and channel == "SFX")
    fanfares = fanfares + 1
end
local portalSound = app.db.profile.portalSound
app.db.profile.portalSound = true
o:Finish({ challenge = { kind = { name = "Daily" } } })
assert(said.text == "Finish!" and said.small == "Daily challenge" and fanfares == 1)
app.db.profile.portalSound = false
o:Finish({})
assert(said.small == "" and fanfares == 1, "silent without portal sounds")
o:Finish({ custom = true })
assert(said.small == "Custom game", "a custom game's end")
app.db.profile.portalSound, PlaySoundFile = portalSound, playSound
-- Ended early (a menu over it): it fades out from then on, from where its fade in got to.
now = 200
o:Announce("Finish!", 1.5)
now = 201
o:EndAnnouncement()
o:ShowBanner()
assert(o.banner.start and said.alpha == 1, "fading out from full")
now = 201 + 0.71
o:ShowBanner()
assert(not o.banner.start, "gone after its fade out")
o:Announce("Finish!", 1.5)
now = now + 0.15
o:EndAnnouncement()
o:ShowBanner()
assert(math.abs(said.alpha - 0.5) < 1e-6, "from halfway in")
now = now + 0.36
o:ShowBanner()
assert(not o.banner.start)
banner.text.SetText, banner.small.SetText, banner.frame.SetAlpha = setText, setSmall, setAlpha
function GetTime()
    return 0
end
print("PASS announcements fade in, stay their time and fade out")

-- The title, the menu and the way into a run from the lobby: each screen's camera, the glide
-- between them, the menu's keys, the character standing up, the run starting in the lobby's
-- lane; the lobby's biome up to its gate.
local lobby, music = app.lobby, {}
now = 50
function GetTime()
    return now
end
function PlayMusic(id)
    music[#music + 1] = id
end
function StopMusic()
    music[#music + 1] = "stop"
end
shown = true
o.frame.SetPropagateKeyboardInput = function() end
app.db.profile.music = true
local difficulty = app.db.profile.difficulty
o:OpenTitle()
assert(o.screen == "title" and o.state.lobby == lobby and o.state.status == "ready", "the title shows the lobby")
assert(music[1] == lobby.music, "the title music plays")
o:Render()
local title, menu = lobby.shots.title, lobby.shots.menu
assert(math.abs(o.camera.x - title.at) < 1e-9 and math.abs(o.camera.offset + title.side) < 1e-9, "the title's shot")
app.db.profile.biome = "durotar"
assert(o:BiomeIdAt(lobby.rim + 1) == lobby.biome, "the lobby's biome everywhere before its run")
o.state.status = "running"
assert(o:BiomeIdAt(lobby.rim - 1) == lobby.biome and o:BiomeIdAt(lobby.rim + 1) == "durotar", "the lobby's biome")
o.state.status = "ready"
app.db.profile.biome = "elwynn"
for _, name in ipairs({ "IsAltKeyDown", "IsControlKeyDown", "IsShiftKeyDown" }) do
    _G[name] = _G[name] or function()
        return false
    end
end
for _, key in ipairs({ { "ENTER" }, { "W", "MOVEFORWARD" }, { "SPACE", "JUMP" } }) do
    o:OnScreenKey(key[1], key[2])
end
assert(o.screen == "title", "only E goes on from the title")
o:OnScreenKey("E", "STRAFERIGHT")
assert(o.screen == "menu" and o.glide, "E goes on to the menu")
now = now + lobby.glide.menu / 2
o:Render()
assert(o.camera.x < title.at and o.camera.x > menu.at, "on the way to the menu's shot")
now = now + lobby.glide.menu
o:Render()
assert(math.abs(o.camera.x - menu.at) < 1e-9 and not o.glide, "at the menu's shot")
-- The menu (menus.lua): directions by the movement bindings, E accepts, Q goes back; every
-- other key goes on to WoW.
local passed
o.frame.SetPropagateKeyboardInput = function(_, on)
    passed = on
end
local function press(key, binding)
    assert(o:OnScreenKey(key, binding), "a screen's key: " .. key)
    return passed
end
local main = o.mainMenu
assert(press("ENTER") and press("SPACE", "JUMP"), "Enter and jump go on to WoW")
assert(main:Page().title == nil and main.stack[1].selected == 1, "on the main page, at Play")
assert(press("S", "MOVEBACKWARD") == false and main.stack[1].selected == 2, "down to Challenges")
assert(press("E", "STRAFERIGHT") == false and main:Page().title == "Challenges", "E accepts, whatever E is bound to")
-- A challenge's page: its period at the realm's time, no best yet, a run to play.
function GetServerTime()
    return 20736 * 86400 + 12 * 3600
end
assert(main.stack[2].selected == 2, "the note above Daily cannot be chosen")
press("E")
local daily = main:Page()
assert(daily.title == "Daily challenge" and daily.items[1].text == "10 October 2026", daily.items[1].text)
for _, item in ipairs(daily.items) do
    if item.info then
        assert(type(item.info(o)) == "string")
    end
end
assert(daily.items[#daily.items - 2].text(o) == "Play", "no best yet")
-- Its leaderboard: nobody's yet, then a best shared in the guild.
function UnitName()
    return "Me"
end
local panelWidth
main.panel.SetWidth = function(_, w)
    panelWidth = w
end
-- Every letter 10 pixels wide.
local measured
main.measure.SetText = function(_, t)
    measured = t
end
main.measure.GetStringWidth = function()
    return 10 * #measured
end
daily.items[#daily.items - 1].run(o, main)
local board = main:Page()
assert(board.title == "Daily leaderboard" and board.extra, board.title)
-- The longest name, then the longest score, distance and coins, apart, inside the borders.
local need = 10 * #board.columns.label * (1 + board.columns.spare)
for k, sample in ipairs(board.columns.values) do
    need = need + 20 + 10 * math.max(#sample, #board.columns.heads[k])
end
assert(panelWidth > 400 and panelWidth >= need + 52, "as wide as the longest name and values need")
main:Show()
assert(select(2, board.items[2].info(o)) == "Distance", "the header")
assert(board.items[3].text(o) == "No bests shared yet" and board.items[3].info(o) == "")
local period = app.challenges.Period("daily")
app.leaderboard:Receive(
    app.leaderboard.Encode(period.key, {
        score = 4321,
        distance = period.goal,
        finished = true,
        coins = 1,
        coinTotal = 2,
    }),
    "GUILD",
    "Ann"
)
main:Show()
assert(board.items[3].text(o) == "1. Ann", board.items[3].text(o))
local score, distance, coins = board.items[3].info(o)
assert(score == "4321" and distance == period.goal .. " yd" and coins == "1/2 (50%)", coins)
assert(board.items[4].text(o) == "", "one player")
press("Q", "STRAFELEFT")
assert(main:Page() == daily, "back to the challenge")
assert(panelWidth == 400, "the menu's own width again")
-- The history under the challenges: the streak, and a kind's past bests a page at a time.
press("Q", "STRAFELEFT")
press("S")
press("S")
press("S")
press("E")
local history = main:Page()
assert(history.title == "History" and history.items[1].info(o) == "0 days", "no streak yet")
assert(main.stack[3].selected == 4, "the streak's lines cannot be chosen")
local past = app.challenges.Period("daily").index - 1
app.db.global.challenges["daily-" .. past] =
    { score = 1200, coins = 30, coinTotal = 80, distance = 2500, finished = false, at = 0 }
press("E")
local list = main:Page()
assert(list.title == "Daily history" and list.items[1].choice.get(o) == "1 / 1", "one page")
assert(list.items[2].text(o) == "9 Oct", list.items[2].text(o))
assert(list.items[2].info(o) == "1200  |cffaaaaaa2500 yd|r  30/80", list.items[2].info(o))
assert(list.items[3].text(o) == "" and list.items[3].info(o) == "", "the rows below it empty")
press("Q", "STRAFELEFT")
press("Q", "STRAFELEFT")
press("Q", "STRAFELEFT")
app.db.global.challenges["daily-" .. past] = nil
assert(main:Page().title == nil and main.stack[1].selected == 2, "Q goes back to where it was")
assert(press("R") == true, "R goes on to WoW on a page without an extra action")
press("Q", "STRAFELEFT")
assert(o.screen == "title" and o.glide, "Q on the main page goes back to the title")
press("E")
assert(o.screen == "menu" and main:Page().title == nil and main.stack[1].selected == 1, "and on to the menu again")
-- Custom: Play's items and its own settings, the seed among them.
press("S")
press("S")
press("E")
local custom = main:Page()
assert(custom.title == "Custom" and main.stack[2].selected == 2, "Custom opens its page, at Play past its note")
assert(custom.items[3].text == "Difficulty" and custom.items[4].text == "Seed options")
press("S")
press("S")
press("E")
local seedPage = main:Page()
assert(seedPage.title == "Seed options", "its seed options on a page of their own")
assert(press("R") == false and app.db.profile.seed, "R fixes a new seed")
local function item(page, label)
    for _, it in ipairs(page.items) do
        if it.text == label then
            return it
        end
    end
end
item(seedPage, "Seed").input.set(o, "12345")
assert(app.db.profile.seed == 12345 and item(seedPage, "Seed").input.get(o) == "12345", "a seed typed in")
assert(item(seedPage, "Ends at").input.get(o) == "Never", "no end at first")
item(seedPage, "Ends at").input.set(o, "3000")
assert(app.db.profile.endAt == 3000 and item(seedPage, "Ends at").input.get(o) == "3000", "an end typed in")
app.db.profile.endAt = 0
press("Q", "STRAFELEFT")
assert(main:Page() == custom, "back to Custom")
press("Q", "STRAFELEFT")
assert(main:Page().title == nil and main.stack[1].selected == 3, "back at Custom")
press("UP")
press("UP")
press("E")
assert(main:Page().title == "Play", "Play opens its page")
assert(press("R") == true and o.state.seed ~= 12345, "Play has no seed of its own: R goes on to WoW")
-- Whatever the seed, and so the first zone: the same ground, the same look behind the portal,
-- the same boxes.
app.db.profile.biome = "auto"
local curve, looks = o:GroundCurve(), {}
for i, box in ipairs(o.state.objects) do
    looks[i] = box.seed
end
for _ = 1, 8 do
    o.state = o:NewState(lobby, app.random.Seed())
    assert(o:GroundCurve() == curve, "the same ground curve with a new seed")
    assert(o:BiomeIdAt(lobby.rim + 5) == lobby.biome, "the lobby's ground behind the portal until the run")
    for i, box in ipairs(o.state.objects) do
        assert(box.seed == looks[i], "the lobby's boxes look the same with a new seed")
    end
end
app.db.profile.biome = "elwynn"
press("DOWN")
press("D", "TURNRIGHT")
assert(
    app.db.profile.difficulty == "hard" and o.state.lobby and o.state.status == "ready",
    "harder, still in the lobby"
)
press("A", "TURNLEFT")
press("A", "TURNLEFT")
press("A", "TURNLEFT")
assert(app.db.profile.difficulty == "easy", "no easier than the easiest")
press("E")
assert(app.db.profile.difficulty == "easy", "accept leaves it alone")
press("D", "TURNRIGHT")
assert(app.db.profile.difficulty == "normal", "only left and right change it")
o.frame.SetPropagateKeyboardInput = function() end
press("UP")
press("E")
assert(o.screen == "start" and o.seated, "Play: the character stands up")
o:OnScreenKey("SPACE", "JUMP")
assert(o.state.status == "ready", "no key starts the run on the way into it")
now = now + 0.1
-- The model scene's actor, which plays it, is not in this test.
o.seatAnimation = lobby.seat.standUp
o:OnSeatAnimFinished()
o:Render()
assert(o.seated, "an animation ending right away is not the stand-up's")
now = now + 0.5
o:OnSeatAnimFinished()
o:Render()
assert(not o.seated and o.startPhase == "turn", "once the stand-up ends, the twin takes over and turns")
assert(o.state.status == "ready" and math.abs(o.camera.x - menu.at) < 1e-9, "still at the menu's shot")
now = now + lobby.seat.turnSeconds
o:Render()
assert(o.startPhase == "walk" and o.glide and o.state.status == "ready", "it walks to the lane, the camera glides")
assert(music[#music] == "stop", "the title music ends with the menu")
o:StepApproach(0.1)
local walked = o.state.distance
assert(o.state.lateral < -1 and walked > 0 and o.motion.speed == lobby.launch.speed, "toward the lane, at a walk")
for _ = 1, 20 do
    o:StepApproach(0.1)
end
assert(o.screen == nil and o.state.status == "running", "in the lane the run starts")
assert(not o.state.custom and o.state.seed ~= 12345, "Play's run: a new seed, not Custom's")
assert(o.state.lateral == lobby.lane and o.state.distance == lobby.seat.walk, "in the lane, its walk ahead")
assert(o.state.speed == lobby.launch.speed, "slow at first")
o:OnScreenKey("A", "STRAFELEFT")
assert(o.state.lane == lobby.lane, "the run plays itself up to the portal")
-- The pause and end menus (messages.lua) on the same menu system: Q goes on, R starts over.
InCombatLockdown = InCombatLockdown or function()
    return false
end
o.frame.SetPropagateKeyboardInput = function(_, on)
    passed = on
end
local status = o.statusMenu
o:Action("P")
o:Render()
assert(o.statusOpen and status:Page().title == "Paused", "paused: its menu")
assert(status:Page().items[status.stack[1].selected].text == "Go on", "at Go on, past the run's numbers")
assert(press("Q") == false and o.state.status == "running", "Q goes on")
o:Render()
assert(not o.statusOpen, "no menu while running")
o.state.status, o.state.newBest = "over", true
o:Render()
assert(status:Page().title == "Run complete" and status:Page().items[1].note, "the end, with a new best")
-- The page is built at each end: a run that ended again.
local function ended()
    o.state.status = "running"
    o:Render()
    o.state.status = "over"
    o:Render()
end
local function labels()
    local list = {}
    for _, it in ipairs(status:Page().items) do
        list[#list + 1] = type(it.text) == "string" and it.text or "?"
    end
    return table.concat(list, ",")
end
assert(not labels():find("Seed options", 1, true), "Play's end: no custom settings")
o.state.newBest, o.state.custom = nil, true
ended()
assert(status:Page().items[1].text == "Custom game: no best score", "a custom run says it saves none")
assert(labels():find("Seed options", 1, true), "and its settings' pages")
o.state.custom = nil
ended()
assert(not status:Page().items[1].note, "a plain run without a new best: no note")
-- A challenge's end: how much it beat or missed the best before it by, when both reached the
-- last portal or neither did.
-- (The scorecard's challenge card shows its label, goal, difficulty and reset too.)
o.state.challenge, o.state.finished =
    {
        kind = { name = "Daily" },
        key = "daily-1",
        label = "2 January 1970",
        goal = 5000,
        difficulty = "normal",
        ends = 2 * 86400,
    }, true
o.state.lastBest = { score = g.Score(o.state) + 120, finished = true }
ended()
assert(status:Page().title == "Challenge complete" and status:Page().items[1].text == "120 short of your best")
o.state.newBest, o.state.lastBest.score = true, g.Score(o.state) - 80
ended()
assert(status:Page().items[1].text == "New best!" and status:Page().items[2].text == "80 more than your best")
o.state.newBest, o.state.lastBest.score = nil, g.Score(o.state)
ended()
assert(status:Page().items[1].text == "Level with your best")
o.state.finished = false
ended()
local items = status:Page().items
assert(items[1].text == "The last portal not reached" and not items[2].note, "only one through it: no difference")
o.state.challenge, o.state.finished, o.state.lastBest = nil, nil, nil
assert(press("SPACE", "JUMP") == true and o.state.status == "over", "jump goes on to WoW")
-- Captured, a key the menu leaves unused stays with the game: the character does not jump.
o.capture = true
assert(press("SPACE", "JUMP") == false and o.state.status == "over", "captured, jump stays")
assert(press("W", "MOVEFORWARD") == false, "and WoW's movement keys")
assert(press("ENTER") == true, "other keys go on")
o.capture = false
press("R")
assert(o.state.status == "running" and not o.state.lobby, "R runs again, a plain run")
o:Render()
o.state.status = "over"
o:Render()
press("Q")
assert(o.screen == "menu" and o.state.lobby, "Q goes to the main menu")
app.db.profile.difficulty = difficulty
function GetTime()
    return 0
end
print("PASS the title, the menu and the way into a run from the lobby, the pause and end menus")

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

-- Flying groups start in the background at their configured speed.
assert(loadfile("AzerothSurfers/src/game/ambient.lua"))("AzerothSurfers", app)
do
    local noop = function() end
    local bounds = { -0.5, -0.5, 0, 0.5, 0.5, 1 }
    local function flight(seed, gap, count, runSpeed)
        local item = {
            creature = 4732,
            move = "fly",
            speed = 8,
            ahead = 90,
            from = 18,
            z = 6,
            group = { count = count, gap = gap, offset = 4 },
        }
        local biome = { ground = { fade = { from = 95, to = 135 } }, ambient = { every = 100, creatures = { item } } }
        local p = setmetatable({
            state = {
                seed = seed,
                distance = 0,
                speed = runSpeed,
                status = "running",
                difficulty = { topSpeed = runSpeed },
            },
            biome = biome,
            sceneRunner = 0,
        }, { __index = app.overlay })
        function p:BiomeAt()
            return biome
        end
        function p:AcquireActor()
            return {
                SetAlpha = noop,
                SetUseCenterForOrigin = noop,
                SetPitch = noop,
                SetYaw = noop,
                SetScale = noop,
                SetPosition = noop,
                SetAnimation = noop,
            }
        end
        p.ReleaseActor, p.FadeAlpha = noop, function()
            return 1
        end
        function p:ModelBounds()
            return bounds
        end
        p:CreateAmbient()
        p:UpdateAmbient()
        p.state.distance = 100
        p:UpdateAmbient()
        assert(#p.critters == count, "all flying group members spawn")
        local signature = {}
        for k, c in ipairs(p.critters) do
            assert(math.abs(c.start) == 18, "flyers start at the configured lateral distance")
            assert(c.at - 100 >= 85 and c.at - 100 <= 95, "flock starts in the background before the fade")
            assert((gap == 0 and c.delay == 0) or (gap > 0 and (k == 1 or c.delay > 0)), "pair or trailing formation")
            assert(c.speed == 8, "flight speed is not increased to outrun the camera")
            signature[k] = string.format("%.6f/%.6f/%.6f", c.at, c.delay, c.step)
        end
        assert(p.critters[1].at ~= p.critters[2].at, "neighbouring flight paths have depth separation")
        p.ambientNext = math.huge
        for step = 1, 600 do
            if #p.critters == 0 then
                break
            end
            p.state.distance = p.state.distance + runSpeed * 0.02
            p:UpdateAmbient()
        end
        assert(#p.critters == 0, "flyers are released after crossing or passing the camera")
        return table.concat(signature, ",")
    end
    for _, speed in ipairs({ 26, 54 }) do
        assert(flight(7, 3, 4, speed) == flight(7, 3, 4, speed), "flocks replay from the seed")
        flight(12, 0, 2, speed)
    end
end
print("PASS flying flocks and pairs spawn in the background at their configured speed")

do
    dofile("tests/load.lua")(app, { "game/obstacles" })
    local oldSound, enabled = PlaySoundFile, app.db.profile.enemySound
    local heard = 0
    PlaySoundFile = function()
        heard = heard + 1
    end
    app.db.profile.enemySound = true
    local function pass(lateral, height, start)
        local entry = {
            actor = widget(),
            item = { attack = 16 },
            sound = 123,
            along = 10,
            scale = 1,
            shiftX = 0,
            shiftY = 0,
            x = 0,
            z = 0,
        }
        local mob = g.Box("obstacle", 1, 9, 2, 0, 2)
        mob.surferActors = { entry }
        local state =
            { objects = { mob }, distance = start or 8, lateral = lateral, height = height, status = "running" }
        local view = setmetatable({
            state = state,
            obstacleState = state,
            modelled = {},
            sceneRunner = 0,
            biome = { ground = { fade = { to = 100 } } },
            ObstacleLook = function()
                return true
            end,
            FadeAlpha = function()
                return 1
            end,
        }, { __index = o })
        local before = heard
        view:UpdateObstacles()
        assert(heard == before, "approaching or newly loaded behind: no sound")
        state.distance = 10.1
        view:UpdateObstacles()
        view:UpdateObstacles()
        state.distance = 11
        view:UpdateObstacles()
        return heard - before
    end
    assert(pass(1, 1.64) == 1, "jumping over the mob sounds once at the pass")
    assert(pass(0, 0) == 1, "passing an adjacent lane sounds once")
    assert(pass(-1, 0) == 0, "opposite outer lanes stay silent")
    assert(pass(-0.5, 0) == 0, "distance uses the runner's actual lateral position")
    assert(pass(1, 0, 10.1) == 0, "loading a mob behind does not sound")
    app.db.profile.enemySound = false
    assert(pass(0, 0) == 0, "the sound option is respected")
    PlaySoundFile, app.db.profile.enemySound = oldSound, enabled
end
print("PASS hostile sounds at the pass in the same or adjacent lane only")

-- The challenge card under the scorecard: the live target against the best's checkpoints, and
-- a running frame of a challenge allocates nothing either.
function GetServerTime()
    return 20736 * 86400 + 12 * 3600
end
local period = app.challenges.Period("daily")
local run = g.New(period.seed, period.difficulty, true, nil, period.goal)
run.challenge = period
run.target = { score = 2000, distance = 1000, trace = { 100, 300 }, traceEvery = 100 }
app.challenges.NewTrace(run)
run.nextRow, run.objects = math.huge, {}
g.Start(run)
run.forward = true
o.state = run
o.hudShown = nil
local shown
local function challengeFrame(yards, points)
    run.distance, run.points = yards, points
    app.challenges.Trace(run)
    o:Render()
    shown = o.hudShown
end
challengeFrame(150, 250)
assert(shown.challenge == period, "the card shows the run's challenge")
assert(shown.challengeTarget == 2 * 50 + 4, "ahead by 50 at 150 yards")
function GetTime()
    return 1
end
challengeFrame(150, 150)
assert(shown.challengeTarget == 2 * 50 + 5, "behind by 50")
function GetTime()
    return 2
end
challengeFrame(1200, 5000)
assert(shown.challengeTarget == -3, "past where the best ended")
local t = 2
local function later()
    t = t + 1
    return t
end
GetTime = later
for i = 1, 50 do
    challengeFrame(300 + i, 1000 + 3 * i)
end
collectgarbage("collect")
collectgarbage("stop")
before = collectgarbage("count")
for i = 1, 300 do
    challengeFrame(300 + i, 1000 + 3 * i)
end
assert(shown.challengeTarget > 0, "a gap to the best")
grown = collectgarbage("count") - before
collectgarbage("restart")
assert(grown < 0.5, string.format("300 challenge frames allocated %.2f KB", grown))
print(string.format("PASS the challenge card's live target, and its frames allocate nothing (%.2f KB)", grown))

-- The scorecard's extra info: off by default; once on, a row each under the score, redrawn every
-- INFO_EVERY seconds, written only when changed, and its frames allocate nothing either.
function GetFramerate()
    return 59.6
end
o:LayoutHudInfo()
assert(o:HudInfoRoom() == 0 and o.hud.info.count == 0, "no extra info by default")
app.db.profile.hudInfo = {}
for _, stat in ipairs(o.HUD_INFO) do
    app.db.profile.hudInfo[stat.id] = true
end
o:LayoutHudInfo()
local info = o.hud.info
assert(info.count == #o.HUD_INFO and o:HudInfoRoom() > 0, "every row turned on is shown")
-- What each row writes, read through a recorder.
local written = {}
local function row(id)
    for i, r in ipairs(info.shown) do
        if r.stat.id == id then
            return written[i]
        end
    end
end
run.time = 125.4
for i, r in ipairs(info.shown) do
    r.stat.write({
        SetText = function(_, value)
            written[i] = value
        end,
        SetFormattedText = function(_, format, ...)
            written[i] = string.format(format, ...)
        end,
    }, r.stat.value(o, run))
end
assert(row("time") == "2m 05s", "the run's time: " .. tostring(row("time")))
assert(row("fps") == "60", "frames per second, rounded")
assert(row("seed") == string.format("%.0f", run.seed), "the seed")
assert(row("biome") == o.biome.name, "the biome")
for i = 1, 50 do
    run.time = i
    challengeFrame(400 + i, 2000 + 3 * i)
end
local timeRow
for _, r in ipairs(info.shown) do
    if r.stat.id == "time" then
        timeRow = r
    end
end
assert(timeRow.written == 50, "the time row follows the run")
collectgarbage("collect")
collectgarbage("stop")
before = collectgarbage("count")
for i = 1, 300 do
    run.time, run.speed = 50 + i, 30 + i / 10
    challengeFrame(450 + i, 2200 + 3 * i)
end
grown = collectgarbage("count") - before
collectgarbage("restart")
assert(timeRow.written == 350, "the time row still follows the run")
assert(grown < 0.5, string.format("300 frames with every extra info allocated %.2f KB", grown))
app.db.profile.hudInfo = nil
o:LayoutHudInfo()
assert(o:HudInfoRoom() == 0, "turned off, the section goes")
print(string.format("PASS the scorecard's extra info, and its frames allocate nothing (%.2f KB)", grown))
