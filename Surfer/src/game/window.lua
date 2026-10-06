---@type string, Surfer
local appName, app = ...
local light = app.light
-- The game's modes and its window, added to the view that overlay.lua creates. Full screen
-- (`profile.mode` "full"), the view covers the screen and imitates the real camera, so the road
-- lies around the real character. In the side window ("side") it is a window of its own,
-- dragged by its title and sized from its corner: its camera is the calibration's (not the real
-- zoom), with a sky and land behind the road, as there is no world to show through. Either mode
-- can have a window frame (`profile.frame`): border, title bar and close button.
local overlay = app.overlay
local cam = overlay.camera

-- The frame's border and title bar around the view, in pixels: DefaultPanelBaseTemplate's
-- content area.
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = 6, 21, 2, 2
-- The smallest side window: room for the buttons and the score line.
local MIN_WIDTH, MIN_HEIGHT = 360, 300
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

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

    local chrome = CreateFrame("Frame", nil, UIParent, "DefaultPanelBaseTemplate")
    self:Stack(chrome, "window")
    chrome:EnableMouse(false)
    chrome:Hide()
    self.chrome = chrome
    local title = chrome.TitleContainer and chrome.TitleContainer.TitleText
    if title then
        title:SetText(appName)
    end
    local close = CreateFrame("Button", nil, chrome, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 4, 4)
    if chrome.TitleContainer then
        close:SetFrameLevel(chrome.TitleContainer:GetFrameLevel() + 1)
    end
    close:SetScript("OnClick", function()
        f:Hide()
    end)

    local handle = CreateFrame("Frame", nil, chrome)
    handle:SetPoint("TOPLEFT")
    handle:SetPoint("BOTTOMRIGHT", chrome, "TOPRIGHT", -28, -INSET_TOP)
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
    if chrome.TitleContainer then
        grip:SetFrameLevel(chrome.TitleContainer:GetFrameLevel() + 1)
    end
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

-- Puts the view where the mode wants it, with its frame and capture setting; on Create and when
-- a mode setting or the profile changes.
function overlay:ApplyMode()
    local profile, f = app.db.profile, self.frame
    local side = profile.mode == "side"
    self.side, self.capture = side, profile.capture
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
            f:SetClampRectInsets(-INSET_LEFT, INSET_RIGHT, INSET_TOP, -INSET_BOTTOM)
        else
            f:SetClampRectInsets(0, 0, 0, 0)
        end
    else
        f:SetAllPoints(UIParent)
        -- Over the screen's edges: the road must stay centered on the real character.
        chrome:SetAllPoints(f)
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
    chrome:SetShown(self.framed and f:IsShown())
    -- Everything is placed, shaded and written again.
    self.lastRoad, self.groundLight, self.lastHint, self.shown = {}, nil, nil, nil
    self:Layout()
    self:ApplyHideReal()
end

-- The texts and buttons for the view's mode and size.
function overlay:Layout()
    local side, w, h = self.side, self.frame:GetSize()
    -- Full screen, a frame's title bar covers the top of the screen.
    local top = (not side and self.framed) and -INSET_TOP or 0
    self.score:SetFontObject(side and GameFontNormal or GameFontNormalLarge)
    self.score:ClearAllPoints()
    self.score:SetPoint("TOP", 0, top - (side and 8 or 14))
    self.controls:ClearAllPoints()
    self.controls:SetPoint("TOP", 0, top - (side and 26 or 38))
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
    -- A narrow view gets the short score line.
    self.narrow = w < 560
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
