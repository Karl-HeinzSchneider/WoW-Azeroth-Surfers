---@type string, Surfer
local _, app = ...
-- The restart bar (fills while the restart key is held, controls.lua) and the number box of the
-- status panel's seed (messages.lua).
local overlay = app.overlay

local INPUT = "Interface\\Common\\Common-Input-Border"
local INPUT_WIDTH, INPUT_HEIGHT = 110, 20

-- A box for whole numbers, framed like the game's own number boxes.
local function numberBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(INPUT_WIDTH, INPUT_HEIGHT)
    box:SetFontObject(ChatFontNormal)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(10)
    box:SetTextInsets(0, 4, 0, 0)
    local left = box:CreateTexture(nil, "BACKGROUND")
    left:SetTexture(INPUT)
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    left:SetSize(8, INPUT_HEIGHT)
    left:SetPoint("LEFT", -5, 0)
    local right = box:CreateTexture(nil, "BACKGROUND")
    right:SetTexture(INPUT)
    right:SetTexCoord(0.9375, 1, 0, 0.625)
    right:SetSize(8, INPUT_HEIGHT)
    right:SetPoint("RIGHT")
    local middle = box:CreateTexture(nil, "BACKGROUND")
    middle:SetTexture(INPUT)
    middle:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    middle:SetHeight(INPUT_HEIGHT)
    middle:SetPoint("LEFT", left, "RIGHT")
    middle:SetPoint("RIGHT", right, "LEFT")
    return box
end

overlay.NumberBox = numberBox

function overlay:CreateHoldBar(f)
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

-- `share`: how far the restart key has been held; nil hides the bar.
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
