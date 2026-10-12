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
    { 104, -76 },
    { 26, -138 },
    { 104, -138 },
    { 182, -138 },
    { 260, -76 },
    { 260, -138 },
}

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
    local saved = app.db.profile.inputHudPosition
    f:SetFrameStrata(app.db.profile.drawStrata)
    f:SetFrameLevel(app.db.profile.drawLevel + 40)
    f:ClearAllPoints()
    f:SetPoint(saved.point, UIParent, saved.relative, saved.x, saved.y)
    self:SyncInputHudVisibility()
end

function overlay:UpdateInputHud()
    local blocked = GetCurrentKeyBoardFocus() or (app.options and app.options:IsOpen()) or (self.auto and self.side)
    if blocked then
        self:ClearInputHud()
    end
    local context = self:InputHudContext()
    local now, slot = GetTime(), self:ShownSlot()
    for i, cap in ipairs(self.inputHudCaps) do
        local id = ACTIONS[i]
        if id then
            local action = overlay.ACTION_BY_ID[id]
            local key = overlay.ActionKey(id, slot) or overlay.ActionKey(id, slot + 1)
            local text = key and overlay.KeyText(key) or "—"
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
                cap.label:SetText(action.name)
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
    f:SetSize(362, 220)
    f:SetFrameStrata("HIGH")
    menu.title:SetText("Input HUD")
    menu:PlaceTrim(menu.trims[1], -58)
    menu.trims[2]:Hide()
    menu.marker:Hide()
    menu.version:Hide()
    window:SetScript("OnDragStop", function()
        window:SetScript("OnUpdate", nil)
        local saved = app.db.profile.inputHudPosition
        saved.x, saved.y = saved.x + menu.dx, saved.y + menu.dy
        menu:PlaceWindow(0, 0)
        self:RefreshInputHud()
    end)
    self.inputHudCaps = {}
    for i, position in ipairs(POSITIONS) do
        local cap = self.KeyCap(window)
        cap:SetSize(76, 36)
        cap.text:SetWidth(70)
        cap:SetPoint("TOPLEFT", position[1], position[2])
        cap.label = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cap.label:SetPoint("TOP", cap, "BOTTOM", 0, -2)
        cap.label:SetWidth(76)
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
