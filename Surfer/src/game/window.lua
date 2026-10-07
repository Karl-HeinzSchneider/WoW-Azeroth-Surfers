---@type string, Surfer
local appName, app = ...
local light = app.light
-- The game's modes and its window, added to the view that overlay.lua creates. Full screen
-- (`profile.mode` "full"), the view covers the screen and imitates the real camera, so the road
-- lies around the real character. In the side window ("side") it is a window of its own,
-- dragged by its title and sized from its corner: its camera is the calibration's (not the real
-- zoom), with a sky and land behind the road, as there is no world to show through. Either mode
-- can have a window frame (`profile.frame`): the classic portrait frame (as the spell book's)
-- without its portrait, with a title bar, close and minimize / maximize buttons.
local overlay = app.overlay
local cam = overlay.camera

-- The frame's border and title bar around the view, in pixels: PortraitFrameTemplate's content
-- area.
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = 2, 21, 2, 2
-- How far the frame's corners reach out of it: the top left and bottom corners, and the close
-- button above the top right one. Full screen, the frame sits this far inside the screen's
-- edges; the side window keeps them on the screen when clamped. Fitted by eye in the game, not
-- the textures' own offsets.
local OUT_LEFT, OUT_TOP, OUT_RIGHT, OUT_BOTTOM = -1, 5, 3, 5
-- The smallest side window: room for the score display and the legend.
local MIN_WIDTH, MIN_HEIGHT = 360, 300
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
-- The buttons' row at the top (without the window frame): its buttons' width and spacing.
local BUTTON_STEP = 88

-- The frame (a sibling of the view, so the side window's clipping does not cut it off), its
-- drag handle and size grip, and the backdrop. Shown and hidden with the view.
function overlay:CreateWindow(f)
    self.sky = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.sky:SetColorTexture(1, 1, 1, 1)
    self.sky:SetPoint("TOPLEFT")
    self.sky:SetPoint("TOPRIGHT")
    self.land = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.land:SetColorTexture(1, 1, 1, 1)
    self.land:SetPoint("BOTTOMLEFT")
    self.land:SetPoint("BOTTOMRIGHT")

    -- Built like the spell book's frame: the portrait frame with its close button, and the
    -- maximize / minimize buttons left of it. Its background and portrait are left out: the
    -- game shows through, and the client's own helper turns the portrait into a plain corner.
    local chrome = CreateFrame("Frame", nil, UIParent, "PortraitFrameTemplate")
    self:Stack(chrome, "window")
    chrome:EnableMouse(false)
    chrome:Hide()
    self.chrome = chrome
    chrome.Bg:Hide()
    chrome.TopTileStreaks:Hide()
    ButtonFrameTemplate_HidePortrait(chrome)
    chrome:GetTitleText():SetText(appName)
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

-- The side window's place and size, after it was dragged or sized.
function overlay:SaveWindow()
    local f, saved = self.frame, app.db.profile.side
    -- Kept here, not in the client's layout cache.
    f:SetUserPlaced(false)
    local point, _, relative, x, y = f:GetPoint(1)
    saved.point, saved.relative, saved.x, saved.y = point, relative, x, y
    saved.width, saved.height = f:GetSize()
end

-- Switches to full screen ("full") or the side window ("side").
function overlay:SetMode(mode)
    app.db.profile.mode = mode
    self:ApplyMode()
    app.options:Refresh()
end

-- Puts the view where the mode wants it, with its frame and capture setting; on Create and when
-- a mode setting or the profile changes.
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
        -- Over the screen's edges (the road must stay centered on the real character), the
        -- parts reaching out of it on the screen.
        chrome:SetPoint("TOPLEFT", f, "TOPLEFT", OUT_LEFT, -OUT_TOP)
        chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -OUT_RIGHT, OUT_BOTTOM)
    end
    f:SetMovable(side)
    f:SetResizable(side)
    f:SetClampedToScreen(side)
    -- The side window takes clicks inside it; full screen, they go through to the world.
    f:EnableMouse(side)
    -- The road's pieces reach past the window's edges.
    f:SetClipsChildren(side)
    self.sky:SetShown(side)
    self.land:SetShown(side)
    self.dragHandle:EnableMouse(side)
    self.grip:SetShown(side)
    -- Minimized to the side window, it offers to maximize, and the other way round.
    if side then
        self.resizeButton:SetMaximizedLook()
    else
        self.resizeButton:SetMinimizedLook()
    end
    chrome:SetShown(self.framed and f:IsShown())
    -- Everything is placed, shaded and written again.
    self.lastRoad, self.groundLight, self.lastHint, self.shown, self.hudShown = {}, nil, nil, nil, nil
    self.legendState = nil
    self:Layout()
    self:ApplyHideReal()
end

-- The texts and buttons for the view's mode and size.
function overlay:Layout()
    local side, w, h = self.side, self.frame:GetSize()
    -- Full screen, a frame's title bar covers the top of the screen.
    local top = (not side and self.framed) and -(OUT_TOP + INSET_TOP) or 0
    self:PlaceHud(side, w, h, top)
    self:PlaceLegend(side, top)
    self.controls:ClearAllPoints()
    self.controls:SetPoint("TOP", 0, top - (side and 8 or 14))
    -- Minimize (or Maximize) and Close, unless the frame has its own.
    local buttons, count = self.controlButtons, self.framed and 0 or 2
    buttons[1]:SetText(side and "Maximize" or "Minimize")
    for i, b in ipairs(buttons) do
        b:SetShown(i <= count)
        b:ClearAllPoints()
        b:SetPoint("LEFT", (i - 1) * BUTTON_STEP, 0)
    end
    self.controls:SetWidth(math.max(1, count * BUTTON_STEP - 4))
    self.holdBar:ClearAllPoints()
    self.holdBar:SetPoint("TOP", self.controls, "BOTTOM", 0, -12)
    self.message:ClearAllPoints()
    self.hint:ClearAllPoints()
    if side then
        self.message:SetFontObject(GameFontNormalLarge)
        self.message:SetPoint("TOP", 0, -h * 0.22)
        self.hint:SetFontObject(GameFontHighlightSmall)
        self.hint:SetPoint("TOP", self.message, "BOTTOM", 0, -8)
        self.hint:SetWidth(w - 24)
    else
        self.message:SetFontObject(GameFontNormalHuge)
        self.message:SetPoint("CENTER", 0, 220)
        self.hint:SetFontObject(GameFontHighlight)
        self.hint:SetPoint("CENTER", 0, 175)
        self.hint:SetWidth(700)
    end
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
