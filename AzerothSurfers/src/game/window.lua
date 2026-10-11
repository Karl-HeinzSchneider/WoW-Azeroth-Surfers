---@type string, AzerothSurfers
local _, app = ...
local light = app.light
-- The modes (`profile.mode`): "full" covers the screen; "side" is
-- a window of its own with the calibration's camera and a sky and land backdrop. Either can
-- have the window frame (`profile.frame`).
local overlay = app.overlay
local cam = overlay.camera

-- The frame's border and title bar around the view, in pixels: PortraitFrameTemplate's content
-- area.
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = 2, 21, 2, 2
-- How far the frame's corners and close button reach out of it, fitted by eye: full screen the
-- frame sits this far inside the screen's edges, the side window clamps them on screen.
local OUT_LEFT, OUT_TOP, OUT_RIGHT, OUT_BOTTOM = -1, 5, 3, 5
-- The smallest side window: room for the score display and the legend.
local MIN_WIDTH, MIN_HEIGHT = 360, 300
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
local BUTTON_GAP = 4

-- The frame is a sibling of the view, so the side window's clipping does not cut it.
function overlay:CreateWindow(f)
    f:SetScript("OnMouseWheel", function(_, delta)
        self:Zoom(delta)
    end)
    self.sky = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.sky:SetColorTexture(1, 1, 1, 1)
    self.sky:SetPoint("TOPLEFT")
    self.sky:SetPoint("TOPRIGHT")
    self.land = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.land:SetColorTexture(1, 1, 1, 1)
    self.land:SetPoint("BOTTOMLEFT")
    self.land:SetPoint("BOTTOMRIGHT")

    -- Built like the spell book's frame, without background (the game shows through) or portrait.
    local chrome = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplate")
    self:Stack(chrome, "window")
    chrome:EnableMouse(false)
    chrome:Hide()
    self.chrome = chrome
    chrome.Bg:Hide()
    chrome.TopTileStreaks:Hide()
    ButtonFrameTemplate_HidePortrait(chrome)
    chrome:GetTitleText():SetText(app.TITLE)
    local close = chrome.CloseButton
    close:SetScript("OnClick", function()
        f:Hide()
    end)
    local resize = CreateFrame("Frame", nil, chrome, "MaximizeMinimizeButtonFrameTemplate")
    resize:SetPoint("RIGHT", close, "LEFT")
    resize:SetFrameLevel(close:GetFrameLevel())
    resize:SetOnMinimizedCallback(function()
        self:SetMode("side")
    end)
    resize:SetOnMaximizedCallback(function()
        self:SetMode("full")
    end)
    self.resizeButton = resize

    local handle = CreateFrame("Frame", nil, chrome)
    handle:SetPoint("TOPLEFT")
    -- The title bar, up to the minimize / maximize and close buttons.
    handle:SetPoint("BOTTOMRIGHT", chrome, "TOPRIGHT", -60, -INSET_TOP)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        self:SaveWindow()
    end)
    self.dragHandle = handle

    local grip = CreateFrame("Button", nil, chrome)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture(GRIP .. "Up")
    grip:SetPushedTexture(GRIP .. "Down")
    grip:SetHighlightTexture(GRIP .. "Highlight")
    grip:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        self:SaveWindow()
    end)
    grip:SetFrameLevel(close:GetFrameLevel())
    self.grip = grip

    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    else
        f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
    end
    f:HookScript("OnShow", function()
        chrome:SetShown(self.framed)
    end)
    f:HookScript("OnHide", function()
        chrome:Hide()
    end)
    f:SetScript("OnSizeChanged", function()
        self:Layout()
    end)
end

function overlay:SaveWindow()
    local f, saved = self.frame, app.db.profile.side
    -- Kept here, not in the client's layout cache.
    f:SetUserPlaced(false)
    local point, _, relative, x, y = f:GetPoint(1)
    saved.point, saved.relative, saved.x, saved.y = point, relative, x, y
    saved.width, saved.height = f:GetSize()
end

function overlay:SetMode(mode)
    app.db.profile.mode = mode
    self:ApplyMode()
    app.options:Refresh()
end

-- On Create and whenever a mode setting or the profile changes.
function overlay:ApplyMode()
    local profile, f = app.db.profile, self.frame
    local side = profile.mode == "side"
    self.side, self.capture = side, profile.capture
    self:Restack()
    self.framed = profile.frame[side and "side" or "full"]
    f:ClearAllPoints()
    local chrome = self.chrome
    chrome:ClearAllPoints()
    if side then
        local saved = profile.side
        f:SetPoint(saved.point, UIParent, saved.relative, saved.x, saved.y)
        f:SetSize(saved.width, saved.height)
        chrome:SetPoint("TOPLEFT", f, "TOPLEFT", -INSET_LEFT, INSET_TOP)
        chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", INSET_RIGHT, -INSET_BOTTOM)
        if self.framed then
            f:SetClampRectInsets(
                -INSET_LEFT - OUT_LEFT,
                INSET_RIGHT + OUT_RIGHT,
                INSET_TOP + OUT_TOP,
                -INSET_BOTTOM - OUT_BOTTOM
            )
        else
            f:SetClampRectInsets(0, 0, 0, 0)
        end
    else
        f:SetAllPoints(UIParent)
        -- Over the screen's edges: the road must stay centered on the real character.
        chrome:SetPoint("TOPLEFT", f, "TOPLEFT", OUT_LEFT, -OUT_TOP)
        chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -OUT_RIGHT, OUT_BOTTOM)
    end
    f:SetMovable(side)
    f:SetResizable(side)
    f:SetClampedToScreen(side)
    -- Both modes block world hover and targeting inside the game's viewport.
    f:EnableMouse(true)
    -- Wheel input belongs to the game's camera in both modes.
    f:EnableMouseWheel(true)
    f:SetClipsChildren(side)
    self.sky:SetShown(side)
    self.land:SetShown(side)
    self.dragHandle:EnableMouse(side)
    self.grip:SetShown(side)
    if side then
        self.resizeButton:SetMaximizedLook()
    else
        self.resizeButton:SetMinimizedLook()
    end
    chrome:SetShown(self.framed and f:IsShown())
    -- Everything is placed, shaded and written again.
    self.lastRoad, self.groundLight, self.shown, self.hudShown = {}, nil, nil, nil
    self.legendState = nil
    self:Layout()
end

function overlay:Layout()
    local side, w, h = self.side, self.frame:GetSize()
    -- Full screen, a frame's title bar covers the top of the screen.
    local top = (not side and self.framed) and -(OUT_TOP + INSET_TOP) or 0
    self:PlaceHud(side, top)
    self:PlaceLegend(side, top)
    self.controls:ClearAllPoints()
    self.controls:SetPoint("TOP", 0, top - (side and 8 or 14))
    local buttons, x = self.controlButtons, 0
    buttons[1]:SetText(side and "Maximize" or "Minimize")
    for i, b in ipairs(buttons) do
        local shown = (i <= 2 and not self.framed) or (i >= 3 and self.auto == true)
        b:SetShown(shown)
        if shown then
            b:ClearAllPoints()
            b:SetPoint("LEFT", x, 0)
            x = x + b:GetWidth() + BUTTON_GAP
        end
    end
    self.controls:SetWidth(math.max(1, x - BUTTON_GAP))
    self.holdBar:ClearAllPoints()
    self.holdBar:SetPoint("TOP", self.controls, "BOTTOM", 0, -12)
    self:PlaceMessages(side, h, top)
    self:PlaceScreens(side, w, h)
end

-- The horizon between the sky and the land: where a point straight ahead, endlessly far,
-- projects. On every change of the road's camera, in the side window only.
function overlay:PlaceBackdrop()
    local _, h = self.frame:GetSize()
    local horizon = math.min(h, math.max(0, cam.cy + cam.f * cam.sin / cam.cos))
    self.land:SetHeight(math.max(horizon, 0.01))
    self.sky:SetHeight(math.max(h - horizon, 0.01))
end

-- The backdrop in the world's light: the sky as is, the land like the ground.
function overlay:ShadeBackdrop()
    local sky, lower, upper = self.biome.sky, self.groundColors[1], self.groundColors[2]
    local r, g, b = light.r, light.g, light.b
    local top, horizon, land, haze = sky.top, sky.horizon, sky.land, sky.haze
    lower:SetRGBA(horizon[1] * r, horizon[2] * g, horizon[3] * b, 1)
    upper:SetRGBA(top[1] * r, top[2] * g, top[3] * b, 1)
    self.sky:SetGradient("VERTICAL", lower, upper)
    local lit = self.groundLight.brightness
    local lr, lg, lb = land[1] * lit, land[2] * lit, land[3] * lit
    lower:SetRGBA(lr * r, lg * g, lb * b, 1)
    upper:SetRGBA(
        (lr + (horizon[1] - lr) * haze) * r,
        (lg + (horizon[2] - lg) * haze) * g,
        (lb + (horizon[3] - lb) * haze) * b,
        1
    )
    self.land:SetGradient("VERTICAL", lower, upper)
end
