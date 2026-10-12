---@type string, AzerothSurfers
local _, app = ...
local overlay = app.overlay

-- Actions rather than physical keyboard positions: remapped keys and gamepad buttons share
-- the same indicators. Short taps stay visible for 120 ms so a stream can show them.
local ACTIONS = {
    "jump",
    "left",
    "duck",
    "right",
    "pause",
    "restart",
}
local POSITIONS = {
    { 2, -30 },
    { 1, -78 },
    { 2, -78 },
    { 3, -78 },
    { 4, -30 },
    { 4, -78 },
}
local CAP_WIDTH, CAP_GAP = 56, 6
-- This atlas crops the up arrow from Interface/Housing/HousingLayoutEditor2x.
local ARROW = "housing-floor-arrow-up"
local ROTATION = { jump = 0, left = math.pi / 2, duck = math.pi, right = -math.pi / 2 }

function overlay:InputHudContext()
    return (self.screen == "title" or self.screen == "menu" or self.statusOpen) and "menu" or "run"
end

function overlay:ClearInputHud()
    self.inputHudHeld = nil
    self.inputHudUntil = nil
end

function overlay:InputHudIsPlaying()
    return self.screen == nil
        and not self.statusOpen
        and self.state ~= nil
        and self.state.status == "running"
        and not app.autopilot.InIntro(self.state)
end

function overlay:SyncInputHudVisibility()
    if self.inputHud then
        -- Follow scorecard growth and its side-window scale, keeping the visible widths equal.
        if self.hud then
            local width = math.max(280, self.hud.card:GetWidth())
            local scale = self.hud.frame:GetScale()
            if width ~= self.inputHudWidth then
                self.inputHudWidth = width
                self.inputHud:SetWidth(width)
            end
            if scale ~= self.inputHudScale then
                self.inputHudScale = scale
                self.inputHud:SetScale(scale)
            end
        end
        self.inputHud:SetShown(app.db.profile.inputHud and self.frame:IsShown() and self:InputHudIsPlaying())
    end
end

function overlay:InputHudPress(key, chord)
    if not (self.inputHud and self.inputHud:IsShown() and app.db.profile.inputHud and self:InputHudIsPlaying()) then
        return
    end
    local action = overlay.KeyAction("run", chord)
    if not action then
        return
    end
    self.inputHudHeld = self.inputHudHeld or {}
    self.inputHudUntil = self.inputHudUntil or {}
    self.inputHudHeld[key] = action
    self.inputHudUntil[action] = GetTime() + 0.12
end

function overlay:InputHudRelease(key)
    if self.inputHudHeld then
        self.inputHudHeld[key] = nil
    end
end

function overlay:RefreshInputHud()
    local f = self.inputHud
    if not f then
        return
    end
    self:ClearInputHud()
    local side = app.db.profile.mode == "side"
    local saved = side and app.db.profile.inputHudSidePosition or app.db.profile.inputHudPosition
    f:SetFrameStrata(app.db.profile.drawStrata)
    f:SetFrameLevel(app.db.profile.drawLevel + 40)
    f:ClearAllPoints()
    f:SetPoint(saved.point, side and self.hud.card or UIParent, saved.relative, saved.x, saved.y)
    self:SyncInputHudVisibility()
end

function overlay:UpdateInputHud()
    local blocked = GetCurrentKeyBoardFocus() or (app.options and app.options:IsOpen()) or (self.auto and self.side)
    if blocked then
        self:ClearInputHud()
    end
    local context = self:InputHudContext()
    local now, slot = GetTime(), self:ShownSlot()
    local simplified = app.db.profile.inputHudSimplified == true
    if self.inputHudMenu and self.inputHudLayoutSimplified ~= simplified then
        self.inputHudLayoutSimplified = simplified
        self.inputHud:SetHeight(simplified and 122 or 140)
        for i, cap in ipairs(self.inputHudCaps) do
            local position = POSITIONS[i]
            local y = simplified and position[2] == -78 and -64 or position[2]
            cap:ClearAllPoints()
            cap:SetPoint("TOP", self.inputHudMenu.window, "TOP", (position[1] - 2.5) * (CAP_WIDTH + CAP_GAP), y)
        end
    end
    for i, cap in ipairs(self.inputHudCaps) do
        local id = ACTIONS[i]
        if id then
            local action = overlay.ACTION_BY_ID[id]
            local key = overlay.ActionKey(id, slot) or overlay.ActionKey(id, slot + 1)
            local text = key and overlay.KeyText(key) or "—"
            if simplified then
                text = id == "pause" and "P" or id == "restart" and "R" or ""
            end
            if cap.simplified ~= simplified then
                cap.simplified = simplified
                cap.label:SetShown(not simplified)
                local rotation = ROTATION[id]
                cap.icon:SetShown(simplified and rotation ~= nil)
                if simplified and rotation then
                    cap.icon:SetSize(15, 15)
                    cap.icon:SetAtlas(ARROW)
                    cap.icon:SetRotation(rotation)
                end
            end
            local enabled = key ~= nil and not blocked
            do
                enabled = enabled and overlay.SameContext(action.context, context)
                if self.screen == "title" then
                    enabled = enabled and id == "accept"
                elseif self.screen == "start" or (self.auto and context == "run") then
                    enabled = enabled and (id == "pause" or id == "restart")
                end
            end
            if cap.enabled ~= enabled then
                cap.enabled = enabled
                cap:SetAlpha(enabled and 1 or 0.3)
            end
            if cap.keyText ~= text then
                cap.keyText = text
                cap.text:SetText(text)
            end
            if cap.action ~= id then
                cap.action = id
                cap.label:SetText(id == "restart" and "Start over" or action.name)
            end
            local active = self.inputHudUntil and (self.inputHudUntil[id] or 0) > now or false
            if self.inputHudHeld then
                for _, held in pairs(self.inputHudHeld) do
                    active = active or held == id
                end
            end
            active = active and enabled
            if cap.active ~= active then
                cap.active = active
                if active then
                    cap:SetBackdropColor(0.1, 0.65, 0.85, 1)
                    cap:SetBackdropBorderColor(0.65, 0.95, 1, 1)
                else
                    cap:SetBackdropColor(0.08, 0.08, 0.1, 0.95)
                    cap:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)
                end
            end
        end
    end
end

function overlay:CreateInputHud()
    -- Use the menu's actual window, title, trim and drag implementation. The panel owns
    -- the saved position; its window holds input caps in place of selectable option rows.
    local menu = self:CreateMenu(UIParent)
    local f, window = menu.panel, menu.window
    self.inputHud = f
    self.inputHudMenu = menu
    f:SetSize(280, 140)
    f:SetFrameStrata("HIGH")
    menu.title:Hide()
    local label = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 18, -14)
    label:SetText("Input")
    label:SetTextColor(0.72, 0.68, 0.58)
    menu.trims[1]:Hide()
    menu.trims[2]:Hide()
    menu.marker:Hide()
    menu.version:Hide()
    window:SetScript("OnDragStop", function()
        window:SetScript("OnUpdate", nil)
        local saved = app.db.profile.mode == "side" and app.db.profile.inputHudSidePosition
            or app.db.profile.inputHudPosition
        saved.x, saved.y = saved.x + menu.dx, saved.y + menu.dy
        menu:PlaceWindow(0, 0)
        self:RefreshInputHud()
    end)
    self.inputHudCaps = {}
    for i, position in ipairs(POSITIONS) do
        local cap = self.KeyCap(window)
        cap:SetSize(CAP_WIDTH, 28)
        cap.text:SetWidth(50)
        -- Four equally spaced columns around the window's centre. Symmetric margins remain
        -- exact when the scorecard widens; the upper keys align with their lower columns.
        local x = (position[1] - 2.5) * (CAP_WIDTH + CAP_GAP)
        cap:SetPoint("TOP", window, "TOP", x, position[2])
        cap.label = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap.label:SetPoint("TOP", cap, "BOTTOM", 0, -2)
        cap.label:SetWidth(56)
        self.inputHudCaps[i] = cap
    end
    f:SetScript("OnUpdate", function()
        self:UpdateInputHud()
    end)
    f:SetScript("OnHide", function()
        self:ClearInputHud()
    end)
    self.frame:HookScript("OnHide", function()
        f:Hide()
    end)
    self.frame:HookScript("OnShow", function()
        self:RefreshInputHud()
    end)
    self:RefreshInputHud()
end
