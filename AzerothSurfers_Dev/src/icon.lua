---@type string, table
local _, dev = ...
local app, log = dev.app, dev.log
-- A separate, evenly lit scene for capturing the gameplay gem without opening a run.
-- This prepares a screenshot, not a texture export: WoW cannot write an image with alpha.
local FOV, MARGIN = 0.5, 1.15
local backgrounds = { black = { 0, 0, 0 }, white = { 1, 1, 1 }, green = { 0, 1, 0 } }
local view
local state = { yaw = 0, pitch = 0, zoom = 2.5, spin = false, background = "black" }

local function pose()
    view.actor:SetYaw(math.rad(state.yaw))
    view.actor:SetPitch(math.rad(state.pitch))
    if state.size then
        view.actor:SetScale(state.zoom / state.size)
    end
end

local function update(_, elapsed)
    if not state.size and not state.failed then
        state.wait = state.wait + elapsed
        local minX, minY, minZ, maxX, maxY, maxZ = app.overlay.Extents(view.actor)
        local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
        if size > 0.001 then
            state.size = size
            -- Loading can restart the model's own idle loop; freeze it once ready too.
            view.actor:SetAnimation(0, 0, 0, 0)
            -- Match gameplay's upright pose for models whose native geometry lies flat.
            if not state.pitchManual then
                state.pitch = maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY) and 90 or 0
            end
            pose()
            log:chat(
                "Icon gem loaded (model %d). Use Clean view, move the cursor away, then take a screenshot.",
                state.model
            )
        elseif state.wait > 5 then
            state.failed = true
            log:chat("Icon gem model %d did not load. Close and reopen /surfers icon to retry.", state.model)
        end
    end
    if state.spin and state.size then
        state.yaw = (state.yaw + elapsed * 90) % 360
        view.actor:SetYaw(math.rad(state.yaw))
    elseif state.size or state.failed then
        view.frame:SetScript("OnUpdate", nil)
    end
end

local function refresh()
    pose()
    local color = backgrounds[state.background]
    view.background:SetColorTexture(color[1], color[2], color[3], 1)
    view.status:SetFormattedText(
        "Model %d | yaw %.0f | pitch %.0f | zoom %.2f | %s | %s",
        state.model,
        state.yaw,
        state.pitch,
        state.zoom,
        state.background,
        state.spin and "rotating" or "rotation stopped"
    )
    if view.frame:IsShown() then
        view.frame:SetScript("OnUpdate", update)
    end
end

local function button(parent, label, x, y, run)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", run)
end

local function create()
    local frame = CreateFrame("Frame", "AzerothSurfersIconCapture", UIParent)
    frame:Hide()
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    tinsert(UISpecialFrames, "AzerothSurfersIconCapture")
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()

    local scene = CreateFrame("ModelScene", nil, frame)
    scene:SetPoint("CENTER")
    scene:EnableMouse(false)
    scene:SetDrawLayer("OVERLAY")
    scene:SetCameraNearClip(app.overlay.CLIP_NEAR)
    scene:SetCameraFarClip(app.overlay.CLIP_FAR)
    scene:SetCameraOrientationByYawPitchRoll(0, 0, 0)
    scene:SetCameraFieldOfView(FOV)
    scene:SetCameraPosition(-0.5 / math.tan(FOV / 2) * MARGIN, 0, 0)
    scene:SetLightAmbientColor(0.8, 0.8, 0.8)
    scene:SetLightDiffuseColor(0.8, 0.8, 0.8)
    local actor = scene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(0, 0, 0)

    local controls = CreateFrame("Frame", nil, frame)
    controls:SetSize(590, 86)
    controls:SetPoint("BOTTOM", 0, 12)
    local status = controls:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOP", 0, 0)
    view =
        { frame = frame, scene = scene, actor = actor, background = background, controls = controls, status = status }
    local function adjust(key, amount)
        if key == "pitch" then
            state.pitchManual = true
        end
        state[key] = state[key] + amount
        state.zoom = math.max(0.1, math.min(10, state.zoom))
        refresh()
    end
    button(controls, "Turn -15", 0, -22, function()
        adjust("yaw", -15)
    end)
    button(controls, "Turn +15", 120, -22, function()
        adjust("yaw", 15)
    end)
    button(controls, "Tilt -15", 240, -22, function()
        adjust("pitch", -15)
    end)
    button(controls, "Tilt +15", 360, -22, function()
        adjust("pitch", 15)
    end)
    button(controls, "Rotate / stop", 480, -22, function()
        state.spin = not state.spin
        refresh()
    end)
    button(controls, "Zoom -", 0, -52, function()
        adjust("zoom", -0.25)
    end)
    button(controls, "Zoom +", 120, -52, function()
        adjust("zoom", 0.25)
    end)
    button(controls, "Background", 240, -52, function()
        state.background = state.background == "black" and "white" or state.background == "white" and "green" or "black"
        refresh()
    end)
    button(controls, "Clean view", 360, -52, function()
        state.spin = false
        refresh()
        controls:Hide()
    end)
    button(controls, "Close (Esc)", 480, -52, function()
        frame:Hide()
    end)
    frame:SetScript("OnHide", function()
        frame:SetScript("OnUpdate", nil)
    end)
end

local USAGE = "icon [turn <degrees> | pitch <degrees> | zoom <0.1-10> | background black|white|green"
    .. " | spin on|off | clean | controls | off]"

dev.Command("icon", USAGE, function(rest)
    local words = dev.Words(rest)
    local what, value = words[1], words[2]
    if what == "off" then
        if view then
            view.frame:Hide()
        end
        return
    end
    if
        what
        and not (
            ((what == "turn" or what == "pitch") and type(value) == "number")
            or (what == "zoom" and type(value) == "number" and value >= 0.1 and value <= 10)
            or (what == "background" and backgrounds[value])
            or (what == "spin" and (value == "on" or value == "off"))
            or what == "clean"
            or what == "controls"
        )
    then
        log:chat("/surfers " .. USAGE)
        return
    end
    if not view then
        create()
    end
    if not view.frame:IsShown() then
        -- Read resolved biome data, including the client's asset overrides.
        local biome = app.overlay.biome or app.biomes.Get("default")
        local models = biome.coin.models
        local entry = models[app.overlay.coinReady and app.overlay.coinModel or 1] or models[1]
        if not entry then
            log:chat("This biome has no coin model to capture.")
            return
        end
        state.model, state.size, state.wait, state.failed = entry.model, nil, 0, false
        view.actor:SetScale(1)
        view.actor:SetModelByFileID(state.model)
        -- Stop the gem's built-in rotation, independently of our optional yaw spin.
        view.actor:SetAnimation(0, 0, 0, 0)
        view.actor:Show()
        local size = math.min(512, UIParent:GetWidth() - 40, UIParent:GetHeight() - 220)
        view.scene:SetSize(size, size)
        view.controls:Show()
        view.frame:Show()
        log:chat(
            "Gem capture: central %.0f UI-unit square. Clean view hides controls; Escape closes. Screenshots need cropping and alpha editing outside WoW.",
            size
        )
    end
    if what == "turn" then
        state.yaw = value % 360
    elseif what == "pitch" then
        state.pitch = value % 360
        state.pitchManual = true
    elseif what == "zoom" then
        state.zoom = value
    elseif what == "background" then
        state.background = value
    elseif what == "spin" then
        state.spin = value == "on"
    elseif what == "clean" then
        state.spin = false
        view.controls:Hide()
    elseif what == "controls" or not what then
        view.controls:Show()
    end
    refresh()
end)
