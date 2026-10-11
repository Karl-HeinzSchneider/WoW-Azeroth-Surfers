---@type string, AzerothSurfers
local appName, app = ...

local log = app.logger
local addon = app.addon

-- Same texture as the TOC's `## IconTexture`.
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

---@class AzerothSurfers.MinimapButton : AceModule
---@field ldb LibDataBroker.QuickLauncher
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
    log:debug("Minimap button registered")
end

-- The addon's first OnProfileRefresh runs before module:OnInitialize, hence the guard.
function module:OnProfileRefresh()
    local icon = LibStub("LibDBIcon-1.0")
    if icon:IsRegistered(appName) then
        icon:Refresh(appName, app.db.profile.minimap)
    end
end

---@param button string "LeftButton", "RightButton", ...
function module:OnClick(button)
    if button == "LeftButton" then
        app.overlay:Toggle()
    else
        log:debug("Minimap button clicked (%s)", button)
    end
end
