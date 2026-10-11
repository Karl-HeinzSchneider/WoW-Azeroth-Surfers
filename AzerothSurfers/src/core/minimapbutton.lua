---@type string, AzerothSurfers
local appName, app = ...

local log = app.logger
local addon = app.addon

-- Custom minimap/LDB texture; the addon-list icon is set separately in the TOC.
local ICON = "Interface\\AddOns\\AzerothSurfers\\assets\\core\\gem128"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

---@class AzerothSurfers.MinimapButton : AceModule
---@field ldb LibDataBroker.QuickLauncher
---@field backdrop table?  # opaque circular backing under the supplied icon
local module = {}
app.minimapButton = addon:NewModule("MinimapButton", module) --[[@as AzerothSurfers.MinimapButton]]

function module:OnInitialize()
    ---@type LibDataBroker.QuickLauncher
    local launcher = {
        type = "launcher",
        text = app.TITLE,
        icon = ICON,
        OnClick = function(_, button)
            self:OnClick(button)
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(app.TITLE)
            tooltip:AddLine("Left-click: play", 1, 1, 1)
            tooltip:AddLine("Right-click: options", 1, 1, 1)
            tooltip:AddLine(" ")
            local challenges = app.challenges
            for _, kind in ipairs(challenges.KINDS) do
                local period = challenges.Period(kind.id)
                tooltip:AddDoubleLine(
                    kind.name .. " challenge",
                    challenges.StatusText(kind.id) .. " |cffbbbbbb(" .. challenges.Left(period) .. " left)|r",
                    1,
                    1,
                    1
                )
            end
        end,
    }
    self.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(appName, launcher) --[[@as LibDataBroker.QuickLauncher]]

    LibStub("LibDBIcon-1.0"):Register(appName, self.ldb, app.db.profile.minimap)
    self:PositionIcon()
    log:debug("Minimap button registered")
end

function module:PositionIcon()
    local icon = LibStub("LibDBIcon-1.0")
    -- Start from the library's client-specific anchor so refreshes cannot accumulate
    -- the offset. Move only the image, keeping the rim and button hit area in place.
    icon:ResetButtonIcon(appName)
    local button = icon:GetMinimapButton(appName)
    local texture = button.icon
    local point, relativeTo, relativePoint, x, y = texture:GetPoint()
    texture:SetPoint(point, relativeTo, relativePoint, x, y - 2)
    self:PositionBackdrop(button)
end

function module:PositionBackdrop(button)
    if not self.backdrop then
        local fill = button:CreateTexture(nil, "BACKGROUND", nil, 1)
        fill:SetColorTexture(0, 0, 0, 1)
        local mask = button:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(fill)
        fill:AddMaskTexture(mask)
        self.backdrop = { fill = fill, mask = mask }
    end
    -- Cover the icon's fading alpha with a solid interior. The extra diameter sits
    -- under the gold rim, avoiding an exposed seam along the stock background edge.
    local fill = self.backdrop.fill
    local size = math.max(26, button.background:GetWidth() + 2, button.background:GetHeight() + 2)
    fill:SetSize(size, size)
    fill:ClearAllPoints()
    fill:SetPoint("CENTER", button.background, "CENTER", 1, -2)
end

-- The addon's first OnProfileRefresh runs before module:OnInitialize, hence the guard.
function module:OnProfileRefresh()
    local icon = LibStub("LibDBIcon-1.0")
    if icon:IsRegistered(appName) then
        icon:Refresh(appName, app.db.profile.minimap)
        self:PositionIcon()
    end
end

---@param button string "LeftButton", "RightButton", ...
function module:OnClick(button)
    if button == "LeftButton" then
        app.overlay:Toggle()
    elseif button == "RightButton" then
        app.options:Open()
    else
        log:debug("Minimap button clicked (%s)", button)
    end
end
