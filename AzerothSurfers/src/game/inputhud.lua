---@type string, AzerothSurfers
local _, app = ...
local overlay = app.overlay

-- Actions rather than physical keyboard positions: remapped keys and gamepad buttons share
-- the same indicators. Short taps stay visible for 120 ms so a stream can show them.
local RUN = { "jump", "left", "duck", "right", "pause", "restart", "forward" }
local MENU = { "up", "menuLeft", "down", "menuRight", "accept", "back", "restart" }
local POSITIONS = { { 90, -32 }, { 12, -90 }, { 90, -90 }, { 168, -90 }, { 246, -32 }, { 246, -90 }, { 324, -90 } }

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
    if GetCurrentKeyBoardFocus() or (app.options and app.options:IsOpen()) or (self.auto and self.side) then
        self:ClearInputHud()
    end
    local actions = self:InputHudContext() == "menu" and MENU or RUN
    local now, slot = GetTime(), self:ShownSlot()
    for i, cap in ipairs(self.inputHudCaps) do
        local id = actions[i]
        if id == "forward" and self.capture then
            id = nil
        end
        cap:SetShown(id ~= nil)
        if id then
            local action = overlay.ACTION_BY_ID[id]
            local key
            if id == "forward" then
                key = GetBindingKey("MOVEFORWARD")
            else
                key = overlay.ActionKey(id, slot) or overlay.ActionKey(id, slot + 1)
            end
            local text = key and overlay.KeyText(key) or "—"
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
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    self.inputHud = f
    f:SetSize(412, 160)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.85)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Input HUD")
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
