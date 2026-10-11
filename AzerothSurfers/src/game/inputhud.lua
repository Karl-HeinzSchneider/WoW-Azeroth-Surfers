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
    "forward",
    "up",
    "menuLeft",
    "down",
    "menuRight",
    "accept",
    "back",
}
local POSITIONS = {
    { 96, -36 },
    { 18, -94 },
    { 96, -94 },
    { 174, -94 },
    { 252, -36 },
    { 252, -94 },
    { 330, -94 },
    { 96, -176 },
    { 18, -234 },
    { 96, -234 },
    { 174, -234 },
    { 252, -176 },
    { 252, -234 },
}

function overlay:InputHudContext()
    return (self.screen == "title" or self.screen == "menu" or self.statusOpen) and "menu" or "run"
end

function overlay:ClearInputHud()
    self.inputHudHeld = nil
    self.inputHudUntil = nil
end

function overlay:InputHudPress(key, chord)
    if not (self.inputHud and self.inputHud:IsShown() and app.db.profile.inputHud) then
        return
    end
    local context = self:InputHudContext()
    local action = overlay.KeyAction(context, chord)
    if not action and context == "run" and not self.capture and GetBindingAction(chord, true) == "MOVEFORWARD" then
        action = "forward"
    end
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
    f:SetShown(app.db.profile.inputHud and self.frame:IsShown())
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
            local key
            if id == "forward" then
                key = GetBindingKey("MOVEFORWARD")
            else
                key = overlay.ActionKey(id, slot) or overlay.ActionKey(id, slot + 1)
            end
            local text = key and overlay.KeyText(key) or "—"
            local enabled = key ~= nil and not blocked
            if id == "forward" then
                enabled = enabled and context == "run" and not self.capture and not self.auto
            else
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
                cap.label:SetText(action and action.name or "Run (hold)")
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
    local f = CreateFrame("Frame", nil, UIParent, "DialogBorderTemplate")
    self.inputHud = f
    f:ClearAllPoints()
    f:SetSize(430, 310)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText("INPUT HUD")
    title:SetTextColor(0.72, 0.68, 0.58)
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Common\\UI-TooltipDivider")
    divider:SetPoint("TOPLEFT", 14, -152)
    divider:SetPoint("TOPRIGHT", -14, -152)
    divider:SetHeight(8)
    local menuLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menuLabel:SetPoint("TOPLEFT", 18, -160)
    menuLabel:SetText("MENU")
    menuLabel:SetTextColor(0.72, 0.68, 0.58)
    f:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relative, x, y = f:GetPoint()
        local saved = app.db.profile.inputHudPosition
        saved.point, saved.relative, saved.x, saved.y = point, relative, x, y
    end)
    self.inputHudCaps = {}
    for i, position in ipairs(POSITIONS) do
        local cap = self.KeyCap(f)
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
        f:StopMovingOrSizing()
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
