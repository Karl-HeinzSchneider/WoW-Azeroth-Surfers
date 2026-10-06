---@type string, Surfer
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
local bounds = sim.geometry
local LANE = bounds.laneWidth
-- Opaque except for a soft capsule; CLAMP stretches the opaque border over the whole screen.
local CUTOUT = "Interface\\AddOns\\Surfer\\assets\\game\\cutout"
-- Share of the cutout texture the capsule fills: 4 opaque texels on each side of 64 x 128.
local CUTOUT_WIDTH, CUTOUT_HEIGHT, CUTOUT_BOTTOM = 56 / 64, 120 / 128, 4 / 128
-- The character seen from behind as head, torso and legs: bottom and top as shares of its
-- height; width as a share of its cutout width, or of its height for the head. Parts overlap
-- so no seam shows between them. Strides per second of the run cycle the cutout follows.
local HEAD, TORSO, LEGS = { 0.8, 1.04 }, { 0.42, 0.88 }, { 0, 0.5 }
local HEAD_WIDTH, LEGS_WIDTH, RUN_CYCLE = 0.16, 0.55, 1.5
local EDGES = { -3.7, -1.2, 1.2, 3.7 }
-- Coin models from the game files, tried in order until one loads (community listfile ids:
-- 11xp_coin01, 8du_zuldazar_coin01, goldpilesmall01). The flat coin stands in until then.
local COIN_MODELS = { 5737987, 2313815, 200137 }
-- Yards: the model's largest side, the square each coin's scene shows, its camera distance.
local COIN_SIZE, COIN_FRAME, COIN_VIEW = 0.5, 0.8, 3

-- Full-screen view: the real character is the runner, and the road, obstacles and coins are
-- drawn around it. Everything behind the character is masked by capsules over its head, torso
-- and legs, so the character appears in front of the UI.
local overlay = {}
app.overlay = overlay
-- Input, movement sampling, scoring and toggling only need `state`, `frame` and `Create`.
for _, name in ipairs({ "SaveBest", "Restart", "Action", "IsMovingForward", "OnMovementKey", "Toggle" }) do
    overlay[name] = app.runner[name]
end

local ground = shapes.Ground

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
        for _, mask in ipairs(self.cutouts) do
            if behind then
                t:AddMaskTexture(mask)
            else
                t:RemoveMaskTexture(mask)
            end
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
    self.cutouts, self.holes = {}, {}
    for i = 1, 3 do
        self.cutouts[i] = f:CreateMaskTexture()
        self.cutouts[i]:SetTexture(CUTOUT, "CLAMP", "CLAMP")
    end
    self.strips = {}
    for i = 90, 1, -1 do
        local strip = {}
        for j = 1, 5 do
            -- Lane lines just above the road; the boxes on it draw on BORDER.
            strip[j] = f:CreateTexture(nil, "BACKGROUND", nil, j == 1 and 0 or 1)
            strip[j]:SetColorTexture(1, 1, 1)
            self:SetBehind(strip[j], i >= 4)
        end
        self.strips[i] = strip
    end
    self.faces = shapes.Pool(f, "BORDER")
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
        self.clock = (self.clock or 0) + elapsed
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

-- Cutout part i spans `bottom` to `top` yards above the feet, `width` yards wide, `x` yards to
-- the right of the character's center. Its screen box is kept for the 3D coins.
function overlay:PlacePart(i, x, bottom, top, width)
    local mask = self.cutouts[i]
    local sx, y1, scale = project(0, x - cam.offset, cam.feet + bottom)
    local _, y2 = project(0, x - cam.offset, cam.feet + top)
    if not sx or not y2 or y2 <= y1 then
        self.holes[i] = nil
        mask:SetSize(0.01, 0.01)
        return
    end
    local half = width * scale / 2
    self.holes[i] = { left = sx - half, right = sx + half, bottom = y1, top = y2 }
    local w, h = 2 * half / CUTOUT_WIDTH, (y2 - y1) / CUTOUT_HEIGHT
    mask:ClearAllPoints()
    mask:SetPoint("BOTTOMLEFT", sx - w / 2, y1 - h * CUTOUT_BOTTOM)
    mask:SetSize(w, h)
end

-- Head, torso and legs follow a generic run cycle: the body bobs and sways with each stride,
-- and a jump tucks the legs in. The real animation's phase is unknown, so this only
-- approximates it.
function overlay:PlaceCutout()
    local s = self.state
    local h, w = self.height, self.width * app.db.profile.overlay.cutout
    local airborne = s.height - s.floor
    local running = s.status == "running" and s.forward and airborne == 0
    local phase = running and (self.clock or 0) * RUN_CYCLE * 2 * math.pi or 0
    local bob = 0.03 * h * math.abs(math.sin(phase))
    local sway = 0.06 * w * math.sin(phase)
    local tuck = 0.12 * h * math.min(1, airborne / 0.3)
    self:PlacePart(1, sway / 2, HEAD[1] * h + bob, HEAD[2] * h + bob, HEAD_WIDTH * h)
    self:PlacePart(2, sway / 2, TORSO[1] * h + bob, TORSO[2] * h + bob, w)
    self:PlacePart(3, sway, LEGS[1] * h + tuck, LEGS[2] * h + bob, LEGS_WIDTH * w)
    local x, feet, scale = project(0, -cam.offset, cam.feet)
    if x then
        self.feet:ClearAllPoints()
        self.feet:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, feet)
        self.feet:SetSize(self.width * scale * 1.6, 3)
    end
end

-- A 3D coin: its scene is centered on the projected coin and sized to COIN_FRAME yards there.
function overlay:PlaceCoin(coin, o)
    local d = o.at + o.length / 2 - self.state.distance
    local cx, cy, scale = project(d, -o.lane * LANE, (o.layer + 0.5) * sim.LAYER + ground(d))
    local hidden = not cx
    if cx and d - o.length / 2 > 0 then
        -- 3D coins cannot be masked; one behind the body hides while its center is inside a part.
        for i = 1, #self.cutouts do
            local hole = self.holes[i]
            if hole and cx > hole.left and cx < hole.right and cy > hole.bottom and cy < hole.top then
                hidden = true
            end
        end
    end
    if hidden then
        coin.actor:Hide()
        return
    end
    coin.scene:ClearAllPoints()
    coin.scene:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx, cy)
    coin.scene:SetSize(scale * COIN_FRAME, scale * COIN_FRAME)
    -- Each coin spins with its own phase.
    coin.actor:SetYaw(GetTime() * 3 + o.at)
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
        self:AimCoinCameras()
    end
    self:PlaceCutout()
    local opacity = settings.opacity
    for i, strip in ipairs(self.strips) do
        local shade = math.floor((i - 4 + s.distance) / 4) % 2 == 0 and 0.19 or 0.22
        strip[1]:SetColorTexture(shade, shade + 0.05, shade + 0.065, opacity)
        for j = 1, 4 do
            strip[j + 1]:SetColorTexture(0.35, 0.75, 0.71, opacity * ((j == 1 or j == 4) and 1 or 0.55))
        end
    end
    -- Boxes and flat coins from the shared faces; coins become 3D once their model loaded.
    local faces, count = shapes.Collect(s, -cam.offset)
    local coinIndex = 0
    for i = 1, count do
        local f = faces[i]
        local coin = f.kind == "coin" and self.coinReady and self.coins[coinIndex + 1]
        if coin then
            coinIndex = coinIndex + 1
            self:PlaceCoin(coin, f.object)
        else
            local t = shapes.Acquire(self.faces, shapes.Sublevel(f))
            shapes.Draw(t, project, f)
            self:SetBehind(t, f.behind)
        end
    end
    shapes.Release(self.faces)
    for i = coinIndex + 1, #self.coins do
        self.coins[i].actor:Hide()
    end
    self.feet:SetShown(s.status ~= "running")
    self.score:SetText(
        string.format(
            "SCORE  %06d     COINS  %d     BEST  %06d     SPEED  %.0f     LAYER  %d",
            sim.Score(s),
            s.coins,
            app.db.global.bestScore,
            s.speed,
            math.floor(s.height / sim.LAYER + 0.01)
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
