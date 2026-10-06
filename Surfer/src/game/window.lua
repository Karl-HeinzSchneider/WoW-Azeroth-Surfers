---@type string, Surfer
local _, app = ...
local sim = app.simulation
local runner = {}
app.runner = runner
local W, H = 900, 500
local FOV = math.rad(55)
local F = H / (2 * math.tan(FOV / 2))
local CAMERA_PITCH = 0.18
local C, S = math.cos(CAMERA_PITCH), math.sin(CAMERA_PITCH)
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- The current yaw/pitch actor view renders positive simulation lanes on the left.
-- Keep collision lanes unchanged; convert to screen-right coordinates only for UI art.
local function screenSide(lane)
    return -lane * LANE
end
-- Positive logical lanes must always move to the screen's right.
local function laneY(side)
    return side * (runner.laneSign or 1)
end
function runner:CalibrateLanes()
    local scene = self.scene
    if scene.Transform3DPointTo2D then
        local center = scene:Transform3DPointTo2D(0, 0, 0)
        local positiveY = scene:Transform3DPointTo2D(0, 1, 0)
        if center and positiveY and math.abs(positiveY - center) > 0.0001 then
            self.laneSign = positiveY > center and 1 or -1
        end
    end
end
local function ground(d)
    return -0.0005 * math.max(d, 0) ^ 2
end
-- Native actors and the projected track share this camera basis.
local function project(d, side, z)
    local scene = runner.scene
    if scene and scene.Transform3DPointTo2D then
        local px, py = scene:Transform3DPointTo2D(d, laneY(side), z)
        local right = scene:Transform3DPointTo2D(d, laneY(side + 1), z)
        if px and py and right and right > px + 0.0001 then
            local uiScale = scene:GetEffectiveScale()
            return px / uiScale, py / uiScale, math.abs(right - px) / uiScale
        end
    end
    local x, height = d + 10, z - 5
    local depth = C * x - S * height
    return W / 2 + F * side / depth, H / 2 + F * (S * x + C * height) / depth, F / depth
end
local function label(parent, size, x, y, text)
    local f = parent:CreateFontString(nil, "OVERLAY", size)
    f:SetPoint("TOPLEFT", x, y)
    f:SetText(text)
    return f
end
local function rect(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end
local function box(t, x, y, w, h)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", x, y)
    t:SetSize(math.max(w, 0.01), math.max(h, 0.01))
    t:Show()
end
local function quad(t, left, right, near, far, elevation)
    elevation = elevation or 0
    local xl, yl = project(near, left, ground(near) + elevation)
    local xr = project(near, right, ground(near) + elevation)
    local fl, fy = project(far, left, ground(far) + elevation)
    local fr = project(far, right, ground(far) + elevation)
    box(t, xl, yl, xr - xl, math.max(0.01, fy - yl))
    t:SetVertexOffset(1, fl - xl, 0)
    t:SetVertexOffset(3, fr - xr, 0)
end
local function button(parent, text, x, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(140, 28)
    b:SetPoint("BOTTOMLEFT", x, 13)
    b:SetText(text)
    b:SetScript("OnClick", callback)
    return b
end
function runner:SaveBest()
    app.db.global.bestScore = math.max(app.db.global.bestScore, sim.Score(self.state))
end
function runner:Restart()
    self:SaveBest()
    self.state = sim.New()
    sim.Start(self.state)
end
function runner:Action(key)
    local s = self.state
    -- Match the observed screen direction with Forever's yaw/pitch camera.
    if key == "LEFT" or key == "A" then
        sim.Move(s, 1)
    elseif key == "RIGHT" or key == "D" then
        sim.Move(s, -1)
    elseif key == "SPACE" then
        if s.status == "ready" then
            sim.Start(s)
        else
            sim.Jump(s)
        end
    elseif key == "P" then
        sim.Pause(s)
    elseif key == "ENTER" then
        if s.status == "ready" or s.status == "over" then
            self:Restart()
        else
            sim.Pause(s)
        end
    elseif key == "ESCAPE" then
        if s.status == "running" then
            sim.Pause(s)
        else
            self.frame:Hide()
        end
    end
end
function runner:OnMovementKey(key)
    if InCombatLockdown() or GetCurrentKeyBoardFocus() then
        return
    end
    local chord = (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
    local binding = GetBindingAction(chord, true)
    if binding == "TURNLEFT" or binding == "STRAFELEFT" then
        self:Action("LEFT")
    elseif binding == "TURNRIGHT" or binding == "STRAFERIGHT" then
        self:Action("RIGHT")
    elseif binding == "JUMP" then
        self:Action("SPACE")
    elseif binding == "MOVEFORWARD" and self.state.status == "ready" then
        sim.Start(self.state)
    end
end
local function normalize(actor, height, halfWidth, halfDepth)
    if not actor:IsLoaded() then
        return nil
    end
    -- Forever returns six scalars: minX, minY, minZ, maxX, maxY, maxZ.
    -- The exported API docs describe vectors, but that is not this client's runtime contract.
    local minX, minY, low, maxX, maxY, high = actor:GetActiveBoundingBox()
    if type(low) ~= "number" or type(high) ~= "number" or high - low < 0.01 then
        return nil
    end
    local scale = height / (high - low)
    if halfWidth and maxY > minY then
        scale = math.min(scale, 2 * halfWidth / (maxY - minY))
    end
    if halfDepth and maxX > minX then
        scale = math.min(scale, 2 * halfDepth / (maxX - minX))
    end
    actor:SetScale(scale)
    return -low * scale
end
local function position(actor, x, y, z)
    local scale = actor:GetScale()
    actor:SetPosition(x / scale, y / scale, z / scale)
end
function runner:LoadPlayer()
    self.playerReady = self.player:SetModelByUnit("player", true, true, false, true)
    self.player:SetUseCenterForOrigin(true, true, false)
    self.playerOffset = nil
    self.player:SetYaw(0)
    self.player:SetScale(1)
    self.animation = nil
end
function runner:Create()
    self.state = sim.New()
    local f = CreateFrame("Frame", "SurferWindow", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(W + 24, H + 112)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    f:SetBackdropColor(0.025, 0.045, 0.065, 1)
    f:SetBackdropBorderColor(0.15, 0.65, 0.65)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT")
    drag:SetHeight(53)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
    end)
    label(f, "GameFontNormalLarge", 18, -13, "SURFER  |cff64d8cb/  ENDLESS RUN|r")
    self.score = label(f, "GameFontHighlightSmall", 18, -35, "")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local canvas = CreateFrame("Frame", nil, f)
    self.canvas = canvas
    canvas:SetSize(W, H)
    canvas:SetPoint("TOPLEFT", 12, -55)
    canvas:SetClipsChildren(true)
    local sky = rect(canvas, "BACKGROUND", 0.04, 0.10, 0.16)
    sky:SetAllPoints()
    local land = rect(canvas, "BACKGROUND", 0.045, 0.16, 0.16)
    box(land, 0, 0, W, H * 0.56)
    local scene = CreateFrame("ModelScene", nil, canvas)
    self.scene = scene
    scene:SetAllPoints()
    scene:EnableMouse(false)
    scene:SetCameraPosition(-10, 0, 5)
    -- Let the engine build a proper rotation, as OrbitCameraMixin does.
    -- Manually supplied axes can reflect the view and invert surface culling.
    scene:SetCameraOrientationByYawPitchRoll(0, CAMERA_PITCH, 0)
    scene:SetCameraFieldOfView(FOV)
    scene:SetCameraNearClip(0.1)
    scene:SetCameraFarClip(140)
    scene:SetLightAmbientColor(0.85, 0.85, 0.85)
    scene:SetLightDiffuseColor(0.6, 0.6, 0.6)
    self.player = scene:CreateActor()
    self:LoadPlayer()
    self.props = {}
    for i = 1, 12 do
        local actor = scene:CreateActor()
        -- Display used by the client's shared wrapped-present model scene.
        local loaded = actor:SetModelByCreatureDisplayID(71933)
        actor:SetUseCenterForOrigin(true, true, false)
        actor:SetScale(0.6)
        actor:Hide()
        self.props[i] = { actor = actor, loaded = loaded }
    end
    self.strips = {}
    -- Short trapezoids approximate a curved surface without external art.
    for i = 90, 1, -1 do
        local strip = {}
        for j = 1, 5 do
            strip[j] = rect(canvas, "ARTWORK", 1, 1, 1)
        end
        local near, far = -3 + (i - 1), -3 + i
        quad(strip[1], -3.7, 3.7, near, far)
        local edges = { -3.7, -1.2, 1.2, 3.7 }
        for j = 1, 4 do
            quad(strip[j + 1], edges[j] - 0.025, edges[j] + 0.025, near, far)
            strip[j + 1]:SetColorTexture(0.35, 0.75, 0.71, (j == 1 or j == 4) and 1 or 0.55)
        end
        self.strips[i] = strip
    end
    self.markers = {}
    for i = 1, 32 do
        self.markers[i] =
            { top = rect(canvas, "OVERLAY", 1, 0.48, 0.25), texture = rect(canvas, "OVERLAY", 1, 0.7, 0.2) }
    end
    local overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(scene:GetFrameLevel() + 5)
    self.message = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    self.message:SetPoint("CENTER", 0, 70)
    self.message:SetWidth(W - 80)
    self.hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.hint:SetPoint("CENTER", 0, 15)
    self.hint:SetWidth(W - 80)
    button(f, "Start / Restart", 14, function()
        if not InCombatLockdown() then
            self:Restart()
        end
    end)
    button(f, "Left", 166, function()
        self:Action("LEFT")
    end)
    button(f, "Jump", 318, function()
        self:Action("SPACE")
    end)
    button(f, "Right", 470, function()
        self:Action("RIGHT")
    end)
    button(f, "Pause / Resume", 622, function()
        if not InCombatLockdown() then
            self:Action("P")
        end
    end)
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    -- Observe movement bindings without consuming keys or replacing WoW bindings.
    f:SetScript("OnKeyDown", function(_, key)
        self:OnMovementKey(key)
    end)
    f:SetScript("OnHide", function()
        if self.state.status == "running" then
            sim.Pause(self.state)
        end
        self:SaveBest()
        f:StopMovingOrSizing()
    end)
    f:SetScript("OnShow", function()
        if not InCombatLockdown() then
            f:SetPropagateKeyboardInput(true)
        end
        self:LoadPlayer()
        self.roadDirty = true
    end)
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    f:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            f:Hide()
        elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            self.roadDirty = true
        elseif event == "PLAYER_LOGOUT" then
            self:SaveBest()
        else
            self:LoadPlayer()
        end
    end)
    f:SetScript("OnUpdate", function(_, elapsed)
        local before = self.state.status
        sim.Update(self.state, elapsed)
        if before == "running" and self.state.status == "over" then
            self:SaveBest()
        end
        self:Render()
    end)
    self.roadDirty = true
    self:Render()
end
function runner:Render()
    local s = self.state
    if self.roadDirty then
        self:CalibrateLanes()
        local edges = { -3.7, -1.2, 1.2, 3.7 }
        for i, strip in ipairs(self.strips) do
            quad(strip[1], -3.7, 3.7, i - 4, i - 3)
            for j = 1, 4 do
                quad(strip[j + 1], edges[j] - 0.025, edges[j] + 0.025, i - 4, i - 3)
            end
        end
        self.roadDirty = false
    end
    for i, strip in ipairs(self.strips) do
        local shade = math.floor((i - 4 + s.distance) / 4) % 2 == 0 and 0.19 or 0.22
        strip[1]:SetColorTexture(shade, shade + 0.05, shade + 0.065)
    end
    local index, propIndex = 0, 0

    for _, o in ipairs(s.objects) do
        local d = o.at - s.distance
        if not o.hit and d > -2 and d < 85 then
            index = index + 1
            local marker = self.markers[index]
            local x, y, scale =
                project(d, screenSide(o.lane), ground(d) + (o.kind == "coin" and bounds.coinBottom or 0))
            if marker then
                if o.kind == "coin" then
                    marker.top:Hide()
                    box(
                        marker.texture,
                        x - scale * bounds.coinHalfWidth,
                        y,
                        scale * bounds.coinHalfWidth * 2,
                        scale * bounds.coinHeight
                    )
                    marker.texture:SetColorTexture(1, 0.77, 0.2, 1)
                else
                    -- Visible collision silhouette even if this client's display is missing.
                    local side = screenSide(o.lane)
                    local front = d - bounds.obstacleHalfDepth
                    local left, bottom = project(front, side - bounds.obstacleHalfWidth, ground(front))
                    local right, top =
                        project(front, side + bounds.obstacleHalfWidth, ground(front) + bounds.obstacleHeight)
                    box(marker.texture, left, bottom, right - left, top - bottom)
                    quad(
                        marker.top,
                        side - bounds.obstacleHalfWidth,
                        side + bounds.obstacleHalfWidth,
                        front,
                        d + bounds.obstacleHalfDepth,
                        bounds.obstacleHeight
                    )
                    marker.texture:SetColorTexture(0.9, 0.29, 0.17, 0.85)
                    propIndex = propIndex + 1
                    local entry = self.props[propIndex]
                    if entry and entry.loaded then
                        entry.offset = entry.offset
                            or normalize(
                                entry.actor,
                                bounds.obstacleHeight,
                                bounds.obstacleHalfWidth,
                                bounds.obstacleHalfDepth
                            )
                        position(entry.actor, d, laneY(o.lane * LANE), ground(d) + (entry.offset or 0))
                        entry.actor:SetYaw(0)
                        entry.actor:Show()
                    end
                end
            end
        end
    end
    for i = index + 1, #self.markers do
        self.markers[i].texture:Hide()
        self.markers[i].top:Hide()
    end
    for i = propIndex + 1, #self.props do
        self.props[i].actor:Hide()
    end
    if not self.playerOffset then
        self.playerOffset = normalize(self.player, bounds.playerHeight)
        if self.playerOffset then
            self.animation = nil
        end
    end
    position(self.player, 0, laneY(s.lateral * LANE), s.height + (self.playerOffset or 0))
    -- Keep the impact pose visible rather than snapping to standing on a crash.
    local animation = (s.status == "running" or s.status == "over") and (s.height > 0 and 38 or 5) or 0
    if animation ~= self.animation then
        self.player:SetAnimation(animation, 0, 1, 0)
        self.animation = animation
    end
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
            or "WoW turn / strafe keys: lanes   |   WoW jump key: jump\nAll inputs pass through. Use the buttons to restart or pause."
    )
end
function runner:Toggle()
    if InCombatLockdown() then
        app.logger:chat("Surfer is available outside combat.")
        return
    end
    if not self.frame then
        self:Create()
    else
        self.frame:SetShown(not self.frame:IsShown())
    end
end
