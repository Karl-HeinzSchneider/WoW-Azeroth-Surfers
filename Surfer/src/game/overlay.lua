---@type string, Surfer
local _, app = ...
local sim = app.simulation
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- Opaque except for a soft capsule; CLAMP stretches the opaque border over the whole screen.
local CUTOUT = "Interface\\AddOns\\Surfer\\assets\\game\\cutout"
-- Share of the cutout texture the capsule fills: 4 opaque texels on each side of 64 x 128.
local CUTOUT_WIDTH, CUTOUT_HEIGHT, CUTOUT_BOTTOM = 56 / 64, 120 / 128, 4 / 128
local EDGES = { -3.7, -1.2, 1.2, 3.7 }
-- Coin models from the game files, tried in order until one loads (community listfile ids:
-- 11xp_coin01, 8du_zuldazar_coin01, goldpilesmall01). The flat coin stands in until then.
local COIN_MODELS = { 5737987, 2313815, 200137 }
-- Yards: the model's largest side, the square each coin's scene shows, its camera distance.
local COIN_SIZE, COIN_FRAME, COIN_VIEW = 0.5, 0.8, 3

-- Full-screen view: the real character is the runner, and the road, obstacles and coins are
-- drawn around it. Everything behind the character is masked by a capsule over its body, so
-- the character appears in front of the UI.
local overlay = {}
app.overlay = overlay
-- Input, movement sampling, scoring and toggling only need `state`, `frame` and `Create`.
for _, name in ipairs({ "SaveBest", "Restart", "Action", "IsMovingForward", "OnMovementKey", "Toggle" }) do
    overlay[name] = app.runner[name]
end

local function ground(d)
    return -0.0005 * math.max(d, 0) ^ 2
end

-- WoW's follow camera orbits a focus point on the character and keeps it at the screen's
-- center; zoom, pitch and the focus height decide where the feet land below it.
local cam = {}
function overlay:UpdateCamera()
    local settings = app.db.profile.overlay
    local w, h = self.frame:GetSize()
    cam.f = h / 2 / math.tan(math.rad(settings.fov) / 2)
    -- Not in this client's API docs; the distance setting stands in when it is missing.
    local zoom = GetCameraZoom and GetCameraZoom() or settings.distance
    local pitch = math.rad(settings.pitch)
    cam.cos, cam.sin = math.cos(pitch), math.sin(pitch)
    cam.cx, cam.cy = w / 2, h / 2
    cam.x = -math.max(zoom, 0.5) * cam.cos
    -- The camera follows the character, so the world shifts by its lane offset and, while it
    -- jumps, drops away beneath it: the character keeps its place on screen.
    cam.feet = self.state.height
    cam.z = cam.feet + settings.focus * self.height + math.max(zoom, 0.5) * cam.sin
    cam.offset = self.state.lateral * LANE
    return string.format(
        "%.2f %.3f %.3f %.0f %.0f %.2f %.2f %g %g %g %g",
        zoom,
        cam.offset,
        cam.feet,
        w,
        h,
        self.height,
        self.width,
        settings.pitch,
        settings.focus,
        settings.fov,
        settings.cutout
    )
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
        t:Hide()
        return
    end
    local br, tr = project(d1, right, z1), project(d2, right, z2)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", bl, by)
    t:SetSize(math.max(br - bl, 0.01), ty - by)
    t:SetVertexOffset(1, tl - bl, 0)
    t:SetVertexOffset(3, tr - br, 0)
    t:Show()
end

-- Only what lies behind the character gets the cutout; what passed it stays in front.
function overlay:SetBehind(t, behind)
    if t.surferBehind ~= behind then
        if behind then
            t:AddMaskTexture(self.cutout)
        else
            t:RemoveMaskTexture(self.cutout)
        end
        t.surferBehind = behind
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

-- Character size in yards from a model copy; a human-sized guess until it has loaded.
function overlay:Measure()
    if self.measured then
        return
    end
    local _, minY, low, _, maxY, high = extents(self.probe)
    if not low or high - low < 0.1 then
        return
    end
    self.height = math.min(math.max(high - low, 0.8), 4)
    self.width = math.min(math.max(maxY - minY, 0.4), 1.5)
    self.measured = true
end

function overlay:LoadPlayer()
    self.measured = false
    self.probe:SetModelByUnit("player", true, true, true, true)
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
    self.height, self.width = 2, 0.8
    local f = CreateFrame("Frame", "SurferOverlay", UIParent)
    self.frame = f
    f:SetAllPoints(UIParent)
    -- Above the 3D world, below the rest of the UI; clicks go through to the world.
    f:SetFrameStrata("BACKGROUND")
    f:EnableMouse(false)
    self.cutout = f:CreateMaskTexture()
    self.cutout:SetTexture(CUTOUT, "CLAMP", "CLAMP")
    self.strips = {}
    for i = 90, 1, -1 do
        local strip = {}
        for j = 1, 5 do
            strip[j] = f:CreateTexture(nil, j == 1 and "BACKGROUND" or "BORDER")
            strip[j]:SetColorTexture(1, 1, 1)
            self:SetBehind(strip[j], i >= 4)
        end
        self.strips[i] = strip
    end
    self.markers = {}
    for i = 1, 32 do
        self.markers[i] = { top = f:CreateTexture(nil, "ARTWORK"), texture = f:CreateTexture(nil, "ARTWORK") }
    end
    self.feet = f:CreateTexture(nil, "OVERLAY")
    self.feet:SetColorTexture(1, 0.82, 0.2, 0.9)
    local probe = CreateFrame("ModelScene", nil, f)
    probe:SetSize(1, 1)
    probe:SetPoint("TOPLEFT")
    probe:SetAlpha(0)
    self.probe = probe:CreateActor()
    self:LoadPlayer()
    -- One small scene per coin, placed at its projected position. The scenes stay shown so
    -- models load; unused ones only hide their actor.
    self.coins = {}
    for i = 1, 12 do
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
        actor:Hide()
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
        self.previousPosition = nil
        self.state.forward = false
        if self.state.status == "running" then
            sim.Pause(self.state)
        end
        self:SaveBest()
    end)
    f:SetScript("OnShow", function()
        if not InCombatLockdown() then
            f:SetPropagateKeyboardInput(true)
        end
        self:LoadPlayer()
        self.roadKey = nil
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
        self.state.forward = self:IsMovingForward(elapsed)
        if self.state.forward and self.state.status == "ready" then
            sim.Start(self.state)
        end
        local before = self.state.status
        sim.Update(self.state, elapsed)
        if before == "running" and self.state.status == "over" then
            self:SaveBest()
        end
        self:Measure()
        self:UpdateCoinModel(elapsed)
        self:Render()
    end)
    self:Render()
end

-- The capsule covers the character from the feet to just above the head.
function overlay:PlaceCutout()
    local settings = app.db.profile.overlay
    local x, feet, scale = project(0, -cam.offset, cam.feet)
    local _, head = project(0, -cam.offset, cam.feet + self.height * 1.05)
    if not x or not head or head <= feet then
        self.hole = nil
        self.cutout:SetSize(0.01, 0.01)
        self.feet:Hide()
        return
    end
    local half = self.width * settings.cutout * scale / 2
    -- 3D coins cannot be masked; they hide while their center is inside this box.
    self.hole = { left = x - half, right = x + half, bottom = feet, top = head }
    local width = 2 * half / CUTOUT_WIDTH
    local height = (head - feet) / CUTOUT_HEIGHT
    self.cutout:ClearAllPoints()
    self.cutout:SetPoint("BOTTOMLEFT", x - width / 2, feet - height * CUTOUT_BOTTOM)
    self.cutout:SetSize(width, height)
    self.feet:ClearAllPoints()
    self.feet:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, feet)
    self.feet:SetSize(self.width * scale * 1.6, 3)
end

-- A 3D coin: its scene is centered on the projected coin and sized to COIN_FRAME yards there.
function overlay:PlaceCoin(coin, d, x, at)
    local cx, cy, scale = project(d, x, ground(d) + bounds.coinBottom + bounds.coinHeight / 2)
    local hole = self.hole
    local hidden = not cx
        or d - bounds.coinHalfDepth > 0
            and hole
            and cx > hole.left
            and cx < hole.right
            and cy > hole.bottom
            and cy < hole.top
    if hidden then
        coin.actor:Hide()
        return
    end
    coin.scene:ClearAllPoints()
    coin.scene:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx, cy)
    coin.scene:SetSize(scale * COIN_FRAME, scale * COIN_FRAME)
    -- Each coin spins with its own phase.
    coin.actor:SetYaw(GetTime() * 3 + at)
    coin.actor:Show()
end

function overlay:Render()
    local s = self.state
    local settings = app.db.profile.overlay
    local key = self:UpdateCamera()
    if key ~= self.roadKey then
        self.roadKey = key
        for i, strip in ipairs(self.strips) do
            local near, far = i - 4, i - 3
            face(strip[1], EDGES[1], EDGES[4], near, ground(near), far, ground(far))
            for j = 1, 4 do
                face(strip[j + 1], EDGES[j] - 0.025, EDGES[j] + 0.025, near, ground(near), far, ground(far))
            end
        end
        self:PlaceCutout()
        self:AimCoinCameras()
    end
    local opacity = settings.opacity
    for i, strip in ipairs(self.strips) do
        local shade = math.floor((i - 4 + s.distance) / 4) % 2 == 0 and 0.19 or 0.22
        strip[1]:SetColorTexture(shade, shade + 0.05, shade + 0.065, opacity)
        for j = 1, 4 do
            strip[j + 1]:SetColorTexture(0.35, 0.75, 0.71, opacity * ((j == 1 or j == 4) and 1 or 0.55))
        end
    end
    local index, coinIndex = 0, 0
    for _, o in ipairs(s.objects) do
        local d = o.at - s.distance
        local marker = self.markers[index + 1]
        -- Simulation lanes are positive to the left of the character.
        local x = -o.lane * LANE
        local coin = self.coinReady and o.kind == "coin" and self.coins[coinIndex + 1]
        if coin and not o.hit and d > -3 and d < 85 then
            coinIndex = coinIndex + 1
            self:PlaceCoin(coin, d, x, o.at)
        elseif marker and not o.hit and d > -3 and d < 85 then
            index = index + 1
            if o.kind == "coin" then
                local bottom = ground(d) + bounds.coinBottom
                local half = bounds.coinHalfWidth
                face(marker.texture, x - half, x + half, d, bottom, d, bottom + bounds.coinHeight)
                marker.texture:SetColorTexture(1, 0.77, 0.2, 1)
                self:SetBehind(marker.texture, d - bounds.coinHalfDepth > 0)
                marker.top:Hide()
            else
                local half, height = bounds.obstacleHalfWidth, bounds.obstacleHeight
                local front, back = d - bounds.obstacleHalfDepth, d + bounds.obstacleHalfDepth
                face(marker.texture, x - half, x + half, front, ground(front), front, ground(front) + height)
                face(marker.top, x - half, x + half, front, ground(front) + height, back, ground(back) + height)
                marker.texture:SetColorTexture(0.9, 0.29, 0.17, 0.95)
                marker.top:SetColorTexture(1, 0.48, 0.25, 0.95)
                self:SetBehind(marker.texture, front > 0)
                self:SetBehind(marker.top, front > 0)
            end
        end
    end
    for i = index + 1, #self.markers do
        self.markers[i].texture:Hide()
        self.markers[i].top:Hide()
    end
    for i = coinIndex + 1, #self.coins do
        self.coins[i].actor:Hide()
    end
    self.feet:SetShown(s.status ~= "running")
    self.score:SetText(
        string.format(
            "SCORE  %06d     COINS  %d     BEST  %06d     SPEED  %.0f",
            sim.Score(s),
            s.coins,
            app.db.global.bestScore,
            s.speed
        )
    )
    local messages = { ready = "READY TO RUN?", paused = "PAUSED", over = "RUN COMPLETE" }
    self.message:SetText(messages[s.status] or "")
    self.hint:SetText(
        s.status == "running" and ""
            or "Run forward to start. WoW turn / strafe keys: lanes   |   WoW jump key: jump\n"
                .. "The gold bar should sit under your feet; adjust it in /surfer options."
    )
end

-- /surfer and the minimap button open the view chosen in the options and close the other one.
function app.ToggleGame()
    local view = app.db.profile.view == "window" and app.runner or overlay
    local other = view == overlay and app.runner or overlay
    if other.frame and other.frame:IsShown() then
        other.frame:Hide()
    end
    view:Toggle()
end
