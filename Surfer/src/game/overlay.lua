---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local light = app.light
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- Where the ground's pieces start and end, from behind the runner (the bottom of the screen at
-- the usual zoom) to the far fade. A texture is stretched over a piece's two triangles without
-- perspective, so it bends where they meet; the bend stays on the screen while the texture
-- scrolls through it, which shimmers like hot air. It grows with a piece's size on the screen,
-- so pieces are half a yard deep close to the camera, then 1, 2 and 4 yards where they are
-- only a few pixels tall: fewer pieces to place on every lane change and jump.
local function edges(scale)
    local list = { -7 }
    while list[#list] < 87 do
        local d = list[#list]
        list[#list + 1] = d + scale * (d < 6 and 0.5 or d < 20 and 1 or d < 44 and 2 or 4)
    end
    return list
end
-- For the same reason, closer than COLUMN_NEAR yards wide bands are cut into columns at most
-- COLUMN yards wide (about a lane).
local COLUMN, COLUMN_NEAR = 2.4, 12
-- A band's pieces by its `segments` (biomes/default.lua).
local SEGMENTS = { [1] = edges(1), [2] = edges(2), [4] = edges(4) }
-- The addon's draw order by mode, bottom to top. The overlay frame (`view`) draws the ground
-- (its BACKGROUND layer) and the flat boxes and coins (BORDER); above it the world scene's 3D
-- decorations and coins; the twin above all of them, the window frame over its edges
-- (window.lua), and the buttons, the start dialog and the restart bar above that (menu.lua).
-- Full screen, the game lies under the rest of the UI (BACKGROUND, the twin a strata up), but
-- its frame and buttons stay above it, wherever the minimap or a raised panel is. The side
-- window is one window above the UI, all of it in one strata. Levels count from the overlay
-- frame's; all are fixed, so nothing the client or another frame does changes them.
local ORDER = {
    full = {
        view = { "BACKGROUND" },
        world = { "BACKGROUND", 2 },
        twin = { "LOW", 10 },
        window = { "HIGH", 20 },
        controls = { "HIGH", 21 },
        menu = { "HIGH", 25 },
    },
    side = {
        view = { "HIGH" },
        world = { "HIGH", 2 },
        twin = { "HIGH", 10 },
        window = { "HIGH", 20 },
        controls = { "HIGH", 21 },
        menu = { "HIGH", 25 },
    },
}
-- The clip planes of every 3D scene, in yards. The scenes share the depth buffer, so with the
-- same planes and the road's camera position their depths compare as in one scene: the twin
-- covers what is behind it, and what is in front of it (a bar it runs under, once past) covers
-- the twin.
local CLIP_NEAR, CLIP_FAR = 0.2, 250
-- Yards: a coin model's largest side.
local COIN_SIZE = 0.5
-- The twin's animations, and the speeds (yards per second) walking, running and walking
-- backwards are animated for. A normal jump plays JUMP_START throughout; JUMP is the loop of a
-- long fall, after AIR_LOOP seconds in the air (a normal jump lasts about 0.83).
local STAND, WALK, RUN, BACKWARDS, JUMP_START, JUMP, JUMP_END = 0, 4, 5, 13, 37, 38, 39
local WALK_SPEED, RUN_SPEED, BACKWARDS_SPEED = 2.5, 7, 4.5
local AIR_LOOP = 1.1
-- The twin's square scene spans this many character heights, room for arms and turns.
local TWIN_FRAME = 1.6

-- The game: the road, obstacles and coins, and a twin (a copy of the character, seen through
-- the road's camera) running on it. Full screen they are drawn around the real character and
-- the twin covers it; window.lua adds the side window and the window frame. This file draws;
-- controls.lua adds input, movement sampling, the per-frame step and scoring.
local overlay = {}
app.overlay = overlay
overlay.CLIP_NEAR, overlay.CLIP_FAR = CLIP_NEAR, CLIP_FAR

local ground = shapes.Ground

-- WoW's follow camera orbits a focus point on the character and keeps it at the screen's
-- center; zoom, pitch and the focus height decide where the feet land below it.
local cam = {}
overlay.camera = cam
-- Stores `value` under `name` and tells whether it was already there.
local function unchanged(last, name, value)
    if last[name] == value then
        return true
    end
    last[name] = value
    return false
end
overlay.Unchanged = unchanged
function overlay:UpdateCamera()
    local settings = app.db.profile.overlay
    local w, h = self.frame:GetSize()
    cam.f = h / 2 / math.tan(math.rad(settings.fov) / 2)
    -- Not in this client's API docs; the distance setting stands in when it is missing, in
    -- first person, where the twin still needs a camera behind it, and in the side window,
    -- which has a camera of its own.
    local zoom = not self.zoomedIn and not self.side and GetCameraZoom and GetCameraZoom()
    cam.zoomRead = zoom and true or false
    zoom = zoom or settings.distance
    local pitch = math.rad(settings.pitch)
    cam.cos, cam.sin = math.cos(pitch), math.sin(pitch)
    cam.cx, cam.cy = w / 2, h / 2
    cam.distance = zoom
    cam.x = -math.max(zoom, 0.5) * cam.cos
    -- The camera follows the character, so the world shifts by its lane offset and, while it
    -- jumps, drops away beneath it: the character keeps its place on screen.
    cam.feet = self.state.height
    cam.z = cam.feet + settings.focus * self.height + math.max(zoom, 0.5) * cam.sin
    cam.offset = self.state.lateral * LANE
    -- Whether the road has to be projected again: compared value by value, without building a
    -- key, so an unchanged frame allocates nothing.
    local last = self.lastRoad
    local same = unchanged(last, "zoom", zoom)
    same = unchanged(last, "offset", cam.offset) and same
    same = unchanged(last, "feet", cam.feet) and same
    same = unchanged(last, "w", w) and same
    same = unchanged(last, "h", h) and same
    same = unchanged(last, "height", self.height) and same
    same = unchanged(last, "pitch", settings.pitch) and same
    same = unchanged(last, "focus", settings.focus) and same
    same = unchanged(last, "fov", settings.fov) and same
    -- The biome's curve, or the fixed one of the options.
    local curve = settings.fixedCurve and settings.curve or self.biome.ground.curve
    if not unchanged(last, "curve", curve) then
        shapes.SetCurve(curve)
        same = false
    end
    return not same
end

-- Screen point of (distance ahead, screen-right world offset, height) and yards to pixels there.
local function project(d, x, z)
    local vd, vz = d - cam.x, z - cam.z
    local depth = vd * cam.cos - vz * cam.sin
    if depth < 0.2 then
        return nil
    end
    local scale = cam.f / depth
    return cam.cx + (x + cam.offset) * scale, cam.cy + (vd * cam.sin + vz * cam.cos) * scale, scale
end

-- The road's projection of a point, for decorations.lua and tests.
function overlay:Project(d, x, z)
    return project(d, x, z)
end

-- The quad from a bottom edge at (d1, z1) to a top edge at (d2, z2), between left and right.
local function face(t, left, right, d1, z1, d2, z2)
    local bl, by = project(d1, left, z1)
    local tl, ty = project(d2, left, z2)
    if not bl or not tl or ty <= by then
        shapes.Hide(t)
        return
    end
    local br, tr = project(d1, right, z1), project(d2, right, z2)
    t:SetPoint("BOTTOMLEFT", bl, by)
    t:SetSize(math.max(br - bl, 0.01), ty - by)
    t:SetVertexOffset(1, tl - bl, 0)
    t:SetVertexOffset(3, tr - br, 0)
    shapes.Show(t)
end

-- The ground's pieces: textures fixed to a stretch of the ground, `left` to `right` across
-- it and `near` to `far` ahead of the runner, on BACKGROUND under the boxes. Textures are
-- reused when the biome changes; spare ones stay hidden.
function overlay:AddGroundPieces(band, left, right, alphaLeft, alphaRight)
    local look = self.biome.ground
    local surface = look.surfaces[band.surface]
    local segments = SEGMENTS[band.segments]
    assert(surface, "Surfer biome: unknown ground surface " .. tostring(band.surface))
    assert(segments, "Surfer biome: a band's segments are 1, 2 or 4")
    local list, pool = self.ground, self.groundPool
    for i = 1, #segments - 1 do
        local near = segments[i]
        local columns = near < COLUMN_NEAR and math.ceil((right - left) / COLUMN - 1e-9) or 1
        for c = 1, columns do
            local n = #list + 1
            local t = pool[n]
            if not t then
                t = self.groundParent:CreateTexture(nil, "BACKGROUND", nil, band.layer)
                t.groundLayer = band.layer
                pool[n] = t
            end
            if t.groundLayer ~= band.layer then
                t:SetDrawLayer("BACKGROUND", band.layer)
                t.groundLayer = band.layer
            end
            -- A column's share of the band, and of its opacity gradient.
            local a, b = (c - 1) / columns, c / columns
            t.kind, t.near, t.far = band.surface, near, segments[i + 1]
            t.left, t.right = left + (right - left) * a, left + (right - left) * b
            t.alphaLeft = alphaLeft + (alphaRight - alphaLeft) * a
            t.alphaRight = alphaLeft + (alphaRight - alphaLeft) * b
            if surface.texture and t:SetTexture(surface.texture, "REPEAT", "REPEAT", "TRILINEAR") then
                t.tile = surface.tile or look.tile
            else
                local color = surface.color
                t:SetColorTexture(color[1], color[2], color[3], 1)
                t.tile = false
            end
            list[n] = t
        end
    end
end

-- The biome's bands, mirrored to both sides of the road.
function overlay:BuildGround()
    local list = self.ground
    for i = #list, 1, -1 do
        list[i] = nil
    end
    for _, band in ipairs(self.biome.ground.bands) do
        local from, to, inner, outer = band.from, band.to, band.opacity[1], band.opacity[2]
        if from == 0 then
            self:AddGroundPieces(band, -to, to, outer, outer)
        else
            self:AddGroundPieces(band, -to, -from, outer, inner)
            self:AddGroundPieces(band, from, to, inner, outer)
        end
    end
    for i = #list + 1, #self.groundPool do
        shapes.Hide(self.groundPool[i])
    end
end

function overlay:CreateGround(f)
    self.groundParent, self.groundPool, self.ground = f, {}, {}
    -- Reused for the gradients: colors are only read during the call.
    self.groundColors = { CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1) }
    if self.biome then
        self:BuildGround()
    end
end

-- The ground's light: the world's (light.lua) times the brightness setting. Tells whether it,
-- or the opacity, changed since the last call. The side window has nothing to see through to.
function overlay:UpdateGroundLight()
    local settings = app.db.profile.overlay
    local last = self.groundLight or {}
    self.groundLight = last
    local same = unchanged(last, "day", light.day)
    same = unchanged(last, "brightness", settings.brightness) and same
    same = unchanged(last, "opacity", self.side and 1 or settings.opacity) and same
    return not same
end

-- The pieces' light and see-through: the opacity setting, the far fade and the soft edges.
function overlay:ShadeGround()
    local left, right = self.groundColors[1], self.groundColors[2]
    local brightness, opacity = self.groundLight.brightness, self.groundLight.opacity
    local r, g, b = light.r * brightness, light.g * brightness, light.b * brightness
    local fade = self.biome.ground.fade
    for _, t in ipairs(self.ground) do
        local alpha = opacity * math.min(1, math.max(0, (fade.to - t.near) / (fade.to - fade.from)))
        if t.alphaLeft == t.alphaRight then
            t:SetVertexColor(r, g, b, alpha * t.alphaLeft)
        else
            left:SetRGBA(r, g, b, alpha * t.alphaLeft)
            right:SetRGBA(r, g, b, alpha * t.alphaRight)
            t:SetGradient("HORIZONTAL", left, right)
        end
    end
end

-- The textures slide toward the runner as it runs; their place across the road is fixed, so
-- they move with the road on lane changes. Offsets wrap at a tile, which looks the same.
function overlay:ScrollGround()
    local distance = self.state.distance
    if self.scrolled == distance then
        return
    end
    self.scrolled = distance
    for _, t in ipairs(self.ground) do
        local tile = t.tile
        if tile then
            local base = distance % tile
            t:SetTexCoord(t.left / tile, t.right / tile, -(t.far + base) / tile, -(t.near + base) / tile)
        end
    end
end

-- Puts `frame` at its place in ORDER for the current mode, and again whenever it changes.
function overlay:Stack(frame, place)
    self.stacked = self.stacked or {}
    self.stacked[frame] = place
    local strata, level = ORDER[self.side and "side" or "full"][place][1], ORDER.full[place][2]
    frame:SetFixedFrameStrata(false)
    frame:SetFixedFrameLevel(false)
    frame:SetFrameStrata(strata)
    frame:SetFixedFrameStrata(true)
    frame:SetFrameLevel(self.frame:GetFrameLevel() + level)
    frame:SetFixedFrameLevel(true)
end

-- Every stacked frame at its place for the mode, after the view's own strata.
function overlay:Restack()
    self.frame:SetFrameStrata(ORDER[self.side and "side" or "full"].view[1])
    for frame, place in pairs(self.stacked) do
        self:Stack(frame, place)
    end
end

-- Forever returns six scalars; the API docs describe two vectors. Accepts both.
local function extents(actor)
    if not actor:IsLoaded() then
        return nil
    end
    local a, b, c, d, e, f = actor:GetActiveBoundingBox()
    if type(a) == "table" and type(b) == "table" then
        a, b, c, d, e, f = a.x, a.y, a.z, b.x, b.y, b.z
    end
    if type(a) ~= "number" or type(f) ~= "number" then
        return nil
    end
    return a, b, c, d, e, f
end
overlay.Extents = extents

-- Character height in yards from a copy without weapons; a human-sized guess until it loads.
function overlay:Measure()
    if self.measured then
        return
    end
    local _, _, low, _, _, high = extents(self.probe)
    if not low or high - low < 0.1 then
        return
    end
    self.height = math.min(math.max(high - low, 0.8), 4)
    self.measured = true
    -- Every shown scene costs a render pass, even an empty one.
    shapes.Hide(self.probeScene)
end

function overlay:LoadPlayer()
    self.measured = false
    shapes.Show(self.probeScene)
    self.probe:SetModelByUnit("player", true, true, true, true)
    self.twinActor:SetModelByUnit("player", true, true, false, true)
    self.twinLow, self.twinAnimation = nil, nil
end

-- The game does not draw the character in first person: zoom all the way in while the view is
-- open full screen and back out to the previous zoom after.
function overlay:HideRealCharacter(hide)
    if hide == (self.zoomedIn or false) then
        return
    end
    if hide then
        self.savedZoom = GetCameraZoom and GetCameraZoom() or nil
        CameraZoomIn(50)
    else
        CameraZoomOut(self.savedZoom or app.db.profile.overlay.distance)
    end
    self.zoomedIn = hide
end

function overlay:ApplyHideReal()
    local shown = self.frame and self.frame:IsShown()
    self:HideRealCharacter(shown and not self.side and app.db.profile.overlay.hideReal or false)
end

-- The biome's look: ground, coins, box colors and night light. On a change while playing,
-- everything is redrawn with the new one.
function overlay:ApplyBiome()
    local biome = app.biomes.Current()
    self.biome = biome
    shapes.colors = biome.shapes
    light.SetNight(biome.light.night)
    if self.groundParent then
        self:BuildGround()
    end
    if self.worldScene then
        self:LoadCoinModel(1)
        self:ApplyDecorations(biome)
        self:ResetObstacles()
    end
    self.lastRoad, self.groundLight, self.scrolled = {}, nil, nil
end

-- A coin actor more in the world scene, with the current coin model, out of sight until placed.
function overlay:NewCoinActor()
    local actor = self.worldScene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(-1000, 0, 0)
    actor.surferAlpha = false
    local id = self.biome.coin.models[self.coinModel]
    if id then
        actor:SetModelByFileID(id)
    end
    if self.coinReady then
        actor:SetScale(self.coinScale)
        actor:SetPitch(self.coinPitch)
    end
    self.coinActors[#self.coinActors + 1] = actor
    return actor
end

-- Loads the biome's coin models, tried in order until one loads, on every coin actor; the first
-- actor is where it is measured.
function overlay:LoadCoinModel(index)
    self.coinModel, self.coinWait, self.coinReady = index, 0, false
    if #self.coinActors == 0 then
        self:NewCoinActor()
    end
    local id = self.biome.coin.models[index]
    for _, actor in ipairs(self.coinActors) do
        if id and not actor:SetModelByFileID(id) then
            return self:LoadCoinModel(index + 1)
        end
    end
end

-- Fits the coin model into COIN_SIZE once it has loaded, or moves on to the next candidate.
function overlay:UpdateCoinModel(elapsed)
    local models = self.biome.coin.models
    if self.coinReady or not self.worldScene or not models[self.coinModel] then
        return
    end
    local minX, minY, minZ, maxX, maxY, maxZ = extents(self.coinActors[1])
    local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
    if size > 0.001 then
        -- A coin lying flat (as doodads do) is stood up to face the camera, then spun.
        local flat = maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY)
        self.coinScale, self.coinPitch = COIN_SIZE / size, flat and math.pi / 2 or 0
        for _, actor in ipairs(self.coinActors) do
            actor:SetScale(self.coinScale)
            actor:SetPitch(self.coinPitch)
        end
        self.coinReady = true
        app.logger:debug("Coin model %d loaded", models[self.coinModel])
        return
    end
    self.coinWait = self.coinWait + elapsed
    if self.coinWait > 3 then
        app.logger:debug("Coin model %d did not load", models[self.coinModel])
        self:LoadCoinModel(self.coinModel + 1)
    end
end

local function label(parent, font, point, y)
    local f = parent:CreateFontString(nil, "OVERLAY", font)
    f:SetPoint(point, 0, y)
    return f
end

function overlay:Create()
    self.state = sim.New()
    self.height, self.lastRoad = 2, {}
    local f = CreateFrame("Frame", "SurferOverlay", UIParent)
    self.frame = f
    f:SetAllPoints(UIParent)
    -- Above the 3D world, below the rest of the UI (full screen, ORDER); clicks go through to
    -- the world.
    f:SetFrameStrata(ORDER.full.view[1])
    f:EnableMouse(false)
    -- The ground; the boxes on it draw on BORDER.
    self:CreateGround(f)
    self.faces = shapes.Pool(f, "BORDER")
    local probe = CreateFrame("ModelScene", nil, f)
    probe:SetSize(1, 1)
    probe:SetPoint("TOPLEFT")
    probe:SetAlpha(0)
    self.probeScene, self.probe = probe, probe:CreateActor()
    -- The twin draws over everything else of the addon (ORDER), its model on the scene's top
    -- layer.
    local twin = CreateFrame("ModelScene", nil, f)
    twin:SetSize(1, 1)
    twin:SetPoint("CENTER")
    twin:EnableMouse(false)
    self:Stack(twin, "twin")
    twin:SetDrawLayer("OVERLAY")
    twin:SetCameraNearClip(CLIP_NEAR)
    twin:SetCameraFarClip(CLIP_FAR)
    light.AddScene(twin, { 0.8, 0.8, 0.8 }, { 0.6, 0.6, 0.6 })
    self.twin = twin
    self.twinActor = twin:CreateActor()
    self.twinActor:SetUseCenterForOrigin(true, true, false)
    self.twinActor:SetYaw(0)
    self:LoadPlayer()
    -- The world scene: 3D decorations and coins, one render pass for all of them.
    self:CreateDecorations(f)
    self.coinActors, self.modelled = {}, {}
    self:ApplyBiome()

    self.score = label(f, "GameFontNormalLarge", "TOP", -14)
    self.message = label(f, "GameFontNormalHuge", "CENTER", 220)
    self.hint = label(f, "GameFontHighlight", "CENTER", 175)
    self.hint:SetWidth(700)
    local controls = CreateFrame("Frame", nil, f)
    self.controls = controls
    self:Stack(controls, "controls")
    controls:SetHeight(24)
    -- Minimize and Close show only without the window frame, which has its own (window.lua
    -- lays the row out).
    local buttons = {
        {
            "Restart",
            function()
                if not InCombatLockdown() then
                    self:Restart()
                end
            end,
        },
        {
            "Pause",
            function()
                self:Action("P")
            end,
        },
        {
            "Minimize",
            function()
                self:SetMode(self.side and "full" or "side")
            end,
        },
        {
            "Close",
            function()
                f:Hide()
            end,
        },
    }
    self.controlButtons = {}
    for i, spec in ipairs(buttons) do
        local b = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        b:SetSize(84, 24)
        b:SetText(spec[1])
        b:SetScript("OnClick", spec[2])
        self.controlButtons[i] = b
    end
    self:CreateMenu(f)

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    -- Keys pass on to WoW, except the restart key and, while captured, the movement keys.
    f:SetScript("OnKeyDown", function(_, key)
        self:OnKey(key)
    end)
    f:SetScript("OnKeyUp", function(_, key)
        self:OnKeyRelease(key)
    end)
    f:SetScript("OnHide", function()
        self.holding = nil
        self:ForgetPosition()
        self.state.forward = false
        if self.state.status == "running" then
            sim.Pause(self.state)
        end
        self:SaveBest()
        self:ApplyHideReal()
    end)
    f:SetScript("OnShow", function()
        if not InCombatLockdown() then
            f:SetPropagateKeyboardInput(true)
        end
        -- After a finished run the game opens on the start dialog again.
        if self.state.status == "over" then
            self.state = sim.New()
        end
        self:LoadPlayer()
        self:ApplyHideReal()
        self.lastRoad = {}
    end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            f:Hide()
        elseif event == "PLAYER_LOGOUT" then
            self:SaveBest()
        else
            self:LoadPlayer()
        end
    end)
    self:CreateWindow(f)
    f:SetScript("OnUpdate", function(_, elapsed)
        local lap = self.timing and debugprofilestop()
        self:Step(elapsed)
        self:UpdateHold(elapsed)
        lap = self:Lap("simulation", lap)
        self:AnimateTwin(elapsed)
        self:Measure()
        self:UpdateCoinModel(elapsed)
        lap = self:Lap("twin animation, models", lap)
        self:Render(lap)
    end)
    self:ApplyMode()
    self:Render()
end

-- The twin stands where the real character stands and covers it. Its scene is a square around
-- the character's projected body, sized by the road's own projection; its camera sits where
-- the road's camera is and looks at the body from the same angle and distance. A square frame
-- spans the same angle across and up, so how the scene measures its field of view cannot
-- change the twin's size. Half see-through while not running full screen, to line it up.
function overlay:PlaceTwin()
    local s, settings = self.state, app.db.profile.overlay
    local scene, actor = self.twin, self.twinActor
    if not actor:IsLoaded() then
        actor:Hide()
        return
    end
    if not self.twinLow then
        local _, _, low = extents(actor)
        if not low then
            actor:Hide()
            return
        end
        self.twinLow = low
    end
    local middle = cam.feet + self.height / 2
    local x, y, scale = project(0, -cam.offset, middle)
    if not x then
        actor:Hide()
        return
    end
    local side = TWIN_FRAME * self.height
    scene:ClearAllPoints()
    scene:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
    scene:SetSize(side * scale, side * scale)
    -- From the road's camera to the middle of the body.
    local ahead, down = -cam.x, cam.z - middle
    local distance = math.sqrt(ahead * ahead + down * down)
    scene:SetCameraPosition(cam.x, 0, cam.z)
    scene:SetCameraOrientationByYawPitchRoll(0, math.atan2(down, ahead), 0)
    scene:SetCameraFieldOfView(2 * math.atan(side / 2 / distance))
    actor:SetScale(settings.twinScale)
    actor:SetPosition(0, 0, cam.feet / settings.twinScale - self.twinLow)
    actor:SetAlpha((s.status == "running" or self.side) and 1 or 0.5)
    actor:Show()
end

-- The real character's animation cannot be read, so the twin mirrors how it moves: walking or
-- running at its speed, its body turned toward a strafe or diagonal as WoW turns it,
-- backpedalling, and a jump's start, air and landing while it (or the twin on the track) is in
-- the air.
function overlay:AnimateTwin(elapsed)
    local actor, s, motion = self.twinActor, self.state, self.motion or {}
    local airborne = IsFalling("player") or s.height > s.floor
    self.airTime = airborne and (self.airTime or 0) + elapsed or 0
    if self.wasAirborne and not airborne then
        self.landTime = 0
    elseif self.landTime then
        self.landTime = self.landTime + elapsed
    end
    self.wasAirborne = airborne
    -- The direction comes from one frame's step, which is noisy: smooth it.
    local k = math.min(1, elapsed * 12)
    self.towardForward = (self.towardForward or 0) + ((motion.forward or 0) - (self.towardForward or 0)) * k
    self.towardLeft = (self.towardLeft or 0) + ((motion.left or 0) - (self.towardLeft or 0)) * k
    local speed = motion.speed or 0
    local animation, rate, yaw = STAND, 1, self.twinYaw or 0
    if airborne then
        animation = self.airTime < AIR_LOOP and JUMP_START or JUMP
    elseif speed > 0 then
        -- 0 straight ahead, positive to the left; pushing against a wall runs on the spot.
        local direction = math.atan2(self.towardLeft, self.towardForward)
        if self.towardForward < -0.1 and math.abs(direction) > math.pi * 0.6 then
            animation, rate = BACKWARDS, speed / BACKWARDS_SPEED
            yaw = direction - (direction > 0 and math.pi or -math.pi)
        else
            animation = speed < 4 and WALK or RUN
            rate, yaw = speed / (animation == WALK and WALK_SPEED or RUN_SPEED), direction
        end
    elseif self.landTime and self.landTime < 0.3 then
        animation = JUMP_END
    else
        yaw = 0
    end
    -- Turn the body smoothly, the short way round.
    local turn = (yaw - (self.twinYaw or 0) + math.pi) % (2 * math.pi) - math.pi
    self.twinYaw = (self.twinYaw or 0) + turn * math.min(1, elapsed * 10)
    actor:SetYaw(self.twinYaw)
    -- Setting an animation restarts it: only when it or its speed really changes.
    if animation ~= self.twinAnimation or math.abs(rate - (self.twinRate or 1)) > 0.1 then
        actor:SetAnimation(animation, 0, rate, 0)
        self.twinAnimation, self.twinRate = animation, rate
    end
end

-- The `i`th coin in view, an actor of the world scene: at the coin's place on the road, spinning
-- with its own phase, fading in far ahead like the ground.
function overlay:PlaceCoin(i, o)
    local actor = self.coinActors[i] or self:NewCoinActor()
    local d = o.at + o.length / 2 - self.state.distance
    -- The scene's y points left; an actor's position is scaled with it.
    local scale = self.coinScale
    actor:SetPosition(d / scale, o.lane * LANE / scale, ((o.layer + 0.5) * sim.LAYER + ground(d)) / scale)
    actor:SetYaw(GetTime() * 3 + o.at)
    local fade = self.biome.ground.fade
    local alpha = math.min(1, math.max(0, (fade.to - d) / (fade.to - fade.from)))
    if not actor.surferAlpha or math.abs(alpha - actor.surferAlpha) > 0.02 then
        actor:SetAlpha(alpha)
        actor.surferAlpha = alpha
    end
    shapes.Show(actor)
end

function overlay:Render(lap)
    local s = self.state
    if self:UpdateCamera() then
        for _, t in ipairs(self.ground) do
            local near, far = t.near, t.far
            face(t, t.left, t.right, near, ground(near), far, ground(far))
        end
        if self.worldScene then
            self:AimDecorations()
        end
        if self.side then
            self:PlaceBackdrop()
        end
    end
    light.Update()
    if self:UpdateGroundLight() then
        self:ShadeGround()
        if self.side then
            self:ShadeBackdrop()
        end
    end
    lap = self:Lap("road placement", lap)
    self:PlaceTwin()
    lap = self:Lap("twin", lap)
    self:ScrollGround()
    if self.worldScene then
        self:UpdateDecorations()
        self:UpdateObstacles()
    end
    lap = self:Lap("ground scroll, decorations, obstacles", lap)
    -- Boxes and flat coins from the shared faces; coins are 3D models in the world scene once
    -- their model has loaded, flat until then.
    local faces, count = shapes.Collect(s, -cam.offset)
    local coins = 0
    local real = self.worldScene and self.coinReady
    for i = 1, count do
        local f = faces[i]
        if f.kind == "coin" and real then
            coins = coins + 1
            self:PlaceCoin(coins, f.object)
        elseif not (self.worldScene and self:Modelled(f)) then
            shapes.Draw(shapes.Acquire(self.faces, shapes.Sublevel(f)), project, f)
        end
    end
    self.faceCount, self.coinCount = self.faces.used, coins
    shapes.Release(self.faces)
    if self.worldScene then
        -- The first coin stays out of sight but shown while the model loads.
        for i = coins + 1, #self.coinActors do
            if self.coinReady or i > 1 then
                shapes.Hide(self.coinActors[i])
            end
        end
        -- Every shown scene costs a render pass, even an empty one.
        if #self.decor > 0 or coins > 0 or not self.coinReady or self.keepWorldScene then
            shapes.Show(self.worldScene)
        else
            shapes.Hide(self.worldScene)
        end
    end
    lap = self:Lap("boxes, coins", lap)
    self:ShowStatus()
    self:ShowHint()
    self:ShowMenu()
    self:Lap("texts", lap)
    if self.timing then
        self.timing.frames = self.timing.frames + 1
    end
end

-- How to play: in the start dialog while a run is ready, under the status message what to do
-- while it is paused or over; rebuilt only when something it shows changes.
function overlay:ShowHint()
    local hint, status = self.lastHint or {}, self.state.status
    self.lastHint = hint
    local distance = math.floor(cam.distance * 10 + 0.5)
    local same = unchanged(hint, "status", status)
    same = unchanged(hint, "zoomRead", cam.zoomRead) and same
    same = unchanged(hint, "distance", distance) and same
    if same then
        return
    end
    if status == "paused" then
        self.hint:SetText("Press Q to go on. Hold R to start over.")
    elseif status == "over" then
        self.hint:SetText("Press R to run again.")
    else
        self.hint:SetText("")
    end
    if status ~= "ready" then
        return
    end
    local text = self.capture
            and "Forward or jump key: start\nTurn or strafe keys: change lanes\nJump key: jump\nQ: pause\nHold R: start over\nYour character stays where it is."
        or "Run forward: start\nTurn or strafe keys: change lanes\nJump key: jump\nQ: pause\nHold R: start over"
    if not self.side then
        text = text
            .. "\n\nLine the see-through copy up with your character in /surfer options. "
            .. string.format(
                cam.zoomRead and "Camera zoom %.1f, read from the game."
                    or "The game does not report its zoom: Camera distance (%.1f) must match yours.",
                distance / 10
            )
    end
    self.menuHelp:SetText(text)
    self:FitMenu()
end

-- Adds the time since `since` to `part` of a frame and starts the next lap, into `timing` while
-- Surfer_Dev's /surfer profile runs; nothing otherwise.
function overlay:Lap(part, since)
    if not since then
        return nil
    end
    local now = debugprofilestop()
    self.timing[part] = (self.timing[part] or 0) + now - since
    return now
end
