---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local bounds = sim.geometry
local LANE = bounds.laneWidth
local EDGES = { -3.7, -1.2, 1.2, 3.7 }
-- Where the road's strips start and end: a yard deep near the runner, then 2 and 4 yards
-- where they are only a few pixels tall. Fewer strips to place on every lane change and jump.
-- Lane lines are thin and need no bands: segments twice as long.
local function edges(scale)
    local list = { -3 }
    while list[#list] < 87 do
        local d = list[#list]
        list[#list + 1] = d + scale * (d < 20 and 1 or d < 44 and 2 or 4)
    end
    return list
end
local STRIP_EDGES, LINE_EDGES = edges(1), edges(2)
-- Coin models from the game files, tried in order until one loads (community listfile ids:
-- 11xp_coin01, 8du_zuldazar_coin01, goldpilesmall01). The flat coin stands in until then.
local COIN_MODELS = { 5737987, 2313815, 200137 }
-- Yards: the model's largest side, the square each coin's scene shows, its camera distance.
local COIN_SIZE, COIN_FRAME, COIN_VIEW = 0.5, 0.8, 3
-- Farther coins are a few pixels tall: drawn flat, without a scene of their own.
local COIN_3D_DISTANCE = 40
-- The twin's animations, and the speeds (yards per second) walking, running and walking
-- backwards are animated for. A normal jump plays JUMP_START throughout; JUMP is the loop of a
-- long fall, after AIR_LOOP seconds in the air (a normal jump lasts about 0.83).
local STAND, WALK, RUN, BACKWARDS, JUMP_START, JUMP, JUMP_END = 0, 4, 5, 13, 37, 38, 39
local WALK_SPEED, RUN_SPEED, BACKWARDS_SPEED = 2.5, 7, 4.5
local AIR_LOOP = 1.1
-- The twin's square scene spans this many character heights, room for arms and turns.
local TWIN_FRAME = 1.6

-- The game, full screen: the road, obstacles and coins are drawn around the real character,
-- and a twin (a copy of the character, seen through the road's camera) runs on top of it.
-- This file draws; controls.lua adds input, movement sampling, the per-frame step and scoring.
local overlay = {}
app.overlay = overlay

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
function overlay:UpdateCamera()
    local settings = app.db.profile.overlay
    local w, h = self.frame:GetSize()
    cam.f = h / 2 / math.tan(math.rad(settings.fov) / 2)
    -- Not in this client's API docs; the distance setting stands in when it is missing, and in
    -- first person, where the twin still needs a camera behind it.
    local zoom = not self.zoomedIn and GetCameraZoom and GetCameraZoom()
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
    same = unchanged(last, "opacity", settings.opacity) and same
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
-- open and back out to the previous zoom after.
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
    self:HideRealCharacter(shown and app.db.profile.overlay.hideReal or false)
end

function overlay:LoadCoinModel(index)
    self.coinModel, self.coinWait, self.coinReady = index, 0, false
    local id = COIN_MODELS[index]
    for _, coin in ipairs(self.coins) do
        if id and not coin.actor:SetModelByFileID(id) then
            return self:LoadCoinModel(index + 1)
        end
    end
end

-- Fits the coin model into COIN_SIZE once it has loaded, or moves on to the next candidate.
function overlay:UpdateCoinModel(elapsed)
    if self.coinReady or not COIN_MODELS[self.coinModel] then
        return
    end
    local minX, minY, minZ, maxX, maxY, maxZ = extents(self.coins[1].actor)
    local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
    if size > 0.001 then
        -- A coin lying flat (as doodads do) is stood up to face the camera, then spun.
        local flat = maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY)
        for _, coin in ipairs(self.coins) do
            coin.actor:SetScale(COIN_SIZE / size)
            coin.actor:SetPitch(flat and math.pi / 2 or 0)
        end
        self.coinReady = true
        app.logger:debug("Coin model %d loaded", COIN_MODELS[self.coinModel])
        return
    end
    self.coinWait = self.coinWait + elapsed
    if self.coinWait > 3 then
        app.logger:debug("Coin model %d did not load", COIN_MODELS[self.coinModel])
        self:LoadCoinModel(self.coinModel + 1)
    end
end

-- Every coin scene looks at its coin the way the game camera looks at the road.
function overlay:AimCoinCameras()
    local pitch = math.rad(app.db.profile.overlay.pitch)
    for _, coin in ipairs(self.coins) do
        coin.scene:SetCameraPosition(-COIN_VIEW * math.cos(pitch), 0, COIN_VIEW * math.sin(pitch))
        coin.scene:SetCameraOrientationByYawPitchRoll(0, pitch, 0)
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
    -- Above the 3D world, below the rest of the UI; clicks go through to the world.
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    -- The road: surface strips, and lane lines just above them; the boxes on it draw on BORDER.
    self.strips, self.lines = {}, {}
    for i = 1, #STRIP_EDGES - 1 do
        local strip = f:CreateTexture(nil, "BACKGROUND", nil, 0)
        strip.near, strip.far = STRIP_EDGES[i], STRIP_EDGES[i + 1]
        self.strips[i] = strip
    end
    for i = 1, #LINE_EDGES - 1 do
        for j = 1, 4 do
            local line = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            line.near, line.far, line.edge = LINE_EDGES[i], LINE_EDGES[i + 1], j
            self.lines[#self.lines + 1] = line
        end
    end
    self.faces = shapes.Pool(f, "BORDER")
    local probe = CreateFrame("ModelScene", nil, f)
    probe:SetSize(1, 1)
    probe:SetPoint("TOPLEFT")
    probe:SetAlpha(0)
    self.probeScene, self.probe = probe, probe:CreateActor()
    -- The twin draws over everything else of the addon, the 3D coins included: a strata above.
    local twin = CreateFrame("ModelScene", nil, f)
    twin:SetSize(1, 1)
    twin:SetPoint("CENTER")
    twin:EnableMouse(false)
    twin:SetFrameStrata("LOW")
    twin:SetCameraNearClip(0.1)
    twin:SetCameraFarClip(200)
    twin:SetLightAmbientColor(0.8, 0.8, 0.8)
    twin:SetLightDiffuseColor(0.6, 0.6, 0.6)
    self.twin = twin
    self.twinActor = twin:CreateActor()
    self.twinActor:SetUseCenterForOrigin(true, true, false)
    self.twinActor:SetYaw(0)
    self:LoadPlayer()
    -- One small scene per coin, placed at its projected position. A scene without a coin is
    -- hidden: every shown scene costs a render pass. The first stays shown while the model loads.
    self.coins = {}
    for i = 1, 24 do
        local scene = CreateFrame("ModelScene", nil, f)
        scene:EnableMouse(false)
        scene:SetSize(1, 1)
        scene:SetPoint("TOPLEFT")
        scene:SetCameraFieldOfView(2 * math.atan(COIN_FRAME / 2 / COIN_VIEW))
        scene:SetCameraNearClip(0.1)
        scene:SetCameraFarClip(10)
        scene:SetLightAmbientColor(0.9, 0.85, 0.7)
        scene:SetLightDiffuseColor(0.8, 0.75, 0.6)
        local actor = scene:CreateActor()
        actor:SetUseCenterForOrigin(true, true, true)
        self.coins[i] = { scene = scene, actor = actor }
    end
    self:LoadCoinModel(1)

    self.score = label(f, "GameFontNormalLarge", "TOP", -14)
    self.message = label(f, "GameFontNormalHuge", "CENTER", 220)
    self.hint = label(f, "GameFontHighlight", "CENTER", 175)
    self.hint:SetWidth(700)
    local controls = CreateFrame("Frame", nil, f)
    controls:SetFrameStrata("MEDIUM")
    controls:SetSize(3 * 112, 24)
    controls:SetPoint("TOP", 0, -38)
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
            "Close",
            function()
                f:Hide()
            end,
        },
    }
    for i, spec in ipairs(buttons) do
        local b = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        b:SetSize(108, 24)
        b:SetPoint("LEFT", (i - 1) * 112, 0)
        b:SetText(spec[1])
        b:SetScript("OnClick", spec[2])
    end

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    -- Observe movement bindings without consuming keys or replacing WoW bindings.
    f:SetScript("OnKeyDown", function(_, key)
        self:OnMovementKey(key)
    end)
    f:SetScript("OnHide", function()
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
    f:SetScript("OnUpdate", function(_, elapsed)
        local lap = self.timing and debugprofilestop()
        self:Step(elapsed)
        lap = self:Lap("simulation", lap)
        self:AnimateTwin(elapsed)
        self:Measure()
        self:UpdateCoinModel(elapsed)
        lap = self:Lap("twin animation, models", lap)
        self:Render(lap)
    end)
    self:ApplyHideReal()
    self:Render()
end

-- The twin stands where the real character stands and covers it. Its scene is a square around
-- the character's projected body, sized by the road's own projection; its camera sits where
-- the road's camera is and looks at the body from the same angle and distance. A square frame
-- spans the same angle across and up, so how the scene measures its field of view cannot
-- change the twin's size. Half see-through while not running, to line it up.
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
    actor:SetAlpha(s.status == "running" and 1 or 0.5)
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

-- A 3D coin: its scene is centered on the projected coin and sized to COIN_FRAME yards there.
-- The twin's scene is a strata above, so a coin behind the twin is covered by it.
function overlay:PlaceCoin(coin, o)
    local d = o.at + o.length / 2 - self.state.distance
    local cx, cy, scale = project(d, -o.lane * LANE, (o.layer + 0.5) * sim.LAYER + ground(d))
    if not cx then
        shapes.Hide(coin.scene)
        return
    end
    coin.scene:ClearAllPoints()
    coin.scene:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx, cy)
    coin.scene:SetSize(scale * COIN_FRAME, scale * COIN_FRAME)
    -- Each coin spins with its own phase.
    coin.actor:SetYaw(GetTime() * 3 + o.at)
    shapes.Show(coin.scene)
end

function overlay:Render(lap)
    local s = self.state
    local opacity = app.db.profile.overlay.opacity
    if self:UpdateCamera() then
        for _, strip in ipairs(self.strips) do
            local near, far = strip.near, strip.far
            face(strip, EDGES[1], EDGES[4], near, ground(near), far, ground(far))
            strip.shade = nil
        end
        for _, line in ipairs(self.lines) do
            local near, far, x = line.near, line.far, EDGES[line.edge]
            face(line, x - 0.025, x + 0.025, near, ground(near), far, ground(far))
            -- Only the opacity changes their color.
            if line.opacity ~= opacity then
                local edge = line.edge == 1 or line.edge == 4
                line:SetColorTexture(0.35, 0.75, 0.71, opacity * (edge and 1 or 0.55))
                line.opacity = opacity
            end
        end
        self:AimCoinCameras()
    end
    lap = self:Lap("road placement", lap)
    self:PlaceTwin()
    lap = self:Lap("twin", lap)
    -- 4-yard bands scroll past; a strip is recolored only when its band changes.
    for _, strip in ipairs(self.strips) do
        local shade = math.floor((strip.near + s.distance) / 4) % 2 == 0 and 0.19 or 0.22
        if strip.shade ~= shade then
            strip:SetColorTexture(shade, shade + 0.05, shade + 0.065, opacity)
            strip.shade = shade
        end
    end
    -- Boxes and flat coins from the shared faces; near coins become 3D once their model loaded.
    local faces, count = shapes.Collect(s, -cam.offset)
    local coinIndex = 0
    for i = 1, count do
        local f = faces[i]
        local coin = f.kind == "coin" and f.depth < COIN_3D_DISTANCE and self.coinReady and self.coins[coinIndex + 1]
        if coin then
            coinIndex = coinIndex + 1
            self:PlaceCoin(coin, f.object)
        else
            shapes.Draw(shapes.Acquire(self.faces, shapes.Sublevel(f)), project, f)
        end
    end
    self.faceCount, self.coinCount = self.faces.used, coinIndex
    shapes.Release(self.faces)
    for i = coinIndex + 1, #self.coins do
        if self.coinReady or i > 1 then
            shapes.Hide(self.coins[i].scene)
        end
    end
    lap = self:Lap("road colors, boxes, coins", lap)
    self:ShowStatus()
    self:ShowHint()
    self:Lap("texts", lap)
    if self.timing then
        self.timing.frames = self.timing.frames + 1
    end
end

-- The hint under the status message, rebuilt only when something it shows changes.
function overlay:ShowHint()
    local hint, running = self.lastHint or {}, self.state.status == "running"
    self.lastHint = hint
    local distance = math.floor(cam.distance * 10 + 0.5)
    local same = unchanged(hint, "running", running)
    same = unchanged(hint, "zoomRead", cam.zoomRead) and same
    same = unchanged(hint, "distance", distance) and same
    if same then
        return
    end
    self.hint:SetText(
        running and ""
            or "Run forward to start. WoW turn / strafe keys: lanes   |   WoW jump key: jump\n"
                .. "Line the see-through copy up with your character in /surfer options.\n"
                .. string.format(
                    cam.zoomRead and "Camera zoom %.1f, read from the game."
                        or "The game does not report its zoom: Camera distance (%.1f) must match yours.",
                    distance / 10
                )
    )
end

-- /surfer profile: the first call starts timing each part of a frame, the second reports the
-- milliseconds per frame each took. Only the addon's own work: the cost of drawing what it
-- shows lands in the game's frame time, which the report sets beside it.
local PARTS = {
    "simulation",
    "twin animation, models",
    "road placement",
    "twin",
    "road colors, boxes, coins",
    "texts",
}

-- Adds the time since `since` to `part` and starts the next lap; nothing while not profiling.
function overlay:Lap(part, since)
    if not since then
        return nil
    end
    local now = debugprofilestop()
    self.timing[part] = (self.timing[part] or 0) + now - since
    return now
end

function overlay:Profile()
    local log = app.logger
    if not self.frame or not self.frame:IsShown() then
        log:chat("Open the game first (/surfer).")
        return
    end
    local timing = self.timing
    if not timing then
        self.timing = { frames = 0, started = debugprofilestop() }
        log:chat("Profiling: play for a while, then /surfer profile again.")
        return
    end
    self.timing = nil
    local frames = math.max(timing.frames, 1)
    local seconds = (debugprofilestop() - timing.started) / 1000
    local total = 0
    for _, part in ipairs(PARTS) do
        total = total + (timing[part] or 0)
    end
    log:chat(
        "%d frames in %.1f s: %.0f fps, %.2f ms per frame, of which the addon's Lua %.3f ms",
        frames,
        seconds,
        frames / seconds,
        seconds * 1000 / frames,
        total / frames
    )
    for _, part in ipairs(PARTS) do
        log:chat("  %-26s %.3f ms", part, (timing[part] or 0) / frames)
    end
    local scenes = (self.twin:IsShown() and 1 or 0) + (self.probeScene:IsShown() and 1 or 0)
    for _, coin in ipairs(self.coins) do
        scenes = scenes + (coin.scene:IsShown() and 1 or 0)
    end
    log:chat(
        "Last frame: %d faces, %d 3D coins, %d model scenes shown, %d road textures",
        self.faceCount or 0,
        self.coinCount or 0,
        scenes,
        #self.strips + #self.lines
    )
end

-- /surfer debug: what the twin's camera and scene do, to compare with the game's camera.
function overlay:Report()
    local log = app.logger
    if not self.frame or not self.frame:IsShown() then
        log:chat("Open the game first (/surfer).")
        return
    end
    local settings, scene = app.db.profile.overlay, self.twin
    log:chat(
        "zoom %s (used %.2f), cameraFov %s, fov setting %d",
        tostring(GetCameraZoom and GetCameraZoom()),
        cam.distance or -1,
        tostring(GetCVar("cameraFov")),
        settings.fov
    )
    log:chat(
        "UI scale %.3f, scene scale %.3f, screen %.0f x %.0f, scene %.0f x %.0f",
        UIParent:GetEffectiveScale(),
        scene:GetEffectiveScale(),
        self.frame:GetWidth(),
        self.frame:GetHeight(),
        scene:GetWidth(),
        scene:GetHeight()
    )
    local minX, minY, low, maxX, maxY, high = extents(self.twinActor)
    log:chat(
        "twin loaded %s, bounds %s, scale %.2f; measured height %.2f",
        tostring(self.twinActor:IsLoaded()),
        low and string.format("%.2f x %.2f x %.2f", maxX - minX, maxY - minY, high - low) or "none",
        self.twinActor:GetScale(),
        self.height
    )
end
