---@type string, Surfer
local appName, app = ...
local sim = app.simulation
-- The start dialog and the restart bar, added to the view that overlay.lua creates. The dialog
-- (the classic dialog box) stands in the middle of the view while a run is ready to start: the
-- best score, how to play, a start button and a close button. The bar fills while the restart
-- key is held during a run (controls.lua).
local overlay = app.overlay

local DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local WIDTH, BUTTON_WIDTH, BUTTON_HEIGHT = 300, 160, 24

local function button(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

function overlay:CreateMenu(f)
    local menu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    self:Stack(menu, "menu")
    menu:SetBackdrop(DIALOG)
    menu:SetWidth(WIDTH)
    menu:SetPoint("CENTER", 0, 20)
    -- Clicks on the dialog stay on it.
    menu:EnableMouse(true)
    menu:Hide()
    self.menu = menu

    local header = menu:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(256, 64)
    header:SetPoint("TOP", 0, 12)
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText(appName)

    local best = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    best:SetPoint("TOP", 0, -34)
    self.menuBest = best
    local help = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOP", best, "BOTTOM", 0, -10)
    help:SetWidth(WIDTH - 40)
    help:SetSpacing(2)
    self.menuHelp = help

    local start = button(menu, "Start game", function()
        sim.Start(self.state)
    end)
    start:SetPoint("TOP", help, "BOTTOM", 0, -16)
    -- Room for options between the two buttons, later.
    local close = button(menu, "Close", function()
        f:Hide()
    end)
    close:SetPoint("TOP", start, "BOTTOM", 0, -8)
    self.menuButtons = { start, close }

    local bar = CreateFrame("StatusBar", nil, f)
    self:Stack(bar, "menu")
    bar:SetSize(220, 14)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0.82, 0)
    bar:SetMinMaxValues(0, 1)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.6)
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("Restarting...")
    bar:Hide()
    self.holdBar = bar
end

-- Once a frame: the dialog while a run is ready to start, with the best score of the moment.
function overlay:ShowMenu()
    local ready = self.state.status == "ready"
    if ready == self.menuShown then
        return
    end
    self.menuShown = ready
    if ready then
        self.menuBest:SetText(string.format("Best score  %06d", app.db.global.bestScore))
        self:FitMenu()
    end
    self.menu:SetShown(ready)
end

-- The dialog's height around its texts and buttons.
function overlay:FitMenu()
    local height = 34 + self.menuBest:GetStringHeight() + 10 + self.menuHelp:GetStringHeight()
    self.menu:SetHeight(height + 16 + 2 * BUTTON_HEIGHT + 8 + 20)
end

-- The restart bar: how far the restart key has been held, nothing while it is not.
function overlay:ShowHold(share)
    if share then
        self.holdBar:SetValue(share)
        if not self.holdShown then
            self.holdShown = true
            self.holdBar:Show()
        end
    elseif self.holdShown then
        self.holdShown = false
        self.holdBar:Hide()
    end
end
