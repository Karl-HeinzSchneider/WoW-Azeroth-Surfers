---@type string, AzerothSurfers
local appName, app = ...

local log = app.logger
local addon = app.addon

-- Same texture as the TOC's `## IconTexture`.
local ICON = "Interface\\AddOns\\AzerothSurfers\\assets\\core\\icon-gem-zoomed"
local HOVER_FOV, HOVER_ZOOM, LOAD_TIMEOUT = 0.5, 3.5, 5

---@class AzerothSurfers.MinimapButton : AceModule
---@field ldb LibDataBroker.QuickLauncher
---@field button table  # LibDBIcon's button and icon region; library scripts remain untouched
---@field hover table?  # one lazily created ModelScene and actor, reused across hovers
---@field hoverEnabled boolean?
---@field dragging boolean?
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

    local icon = LibStub("LibDBIcon-1.0")
    icon:Register(appName, self.ldb, app.db.profile.minimap)
    self.button = icon:GetMinimapButton(appName)
    -- LDB's OnEnter is skipped when OnTooltipShow exists. Hooks preserve the tooltip,
    -- click handlers and drag scripts (including replacements on LibDBIcon:Refresh).
    self.button:HookScript("OnEnter", function()
        self:StartHover()
    end)
    self.button:HookScript("OnLeave", function()
        self:StopHover()
    end)
    self.button:HookScript("OnHide", function()
        self:StopHover()
    end)
    self.button:HookScript("OnMouseDown", function()
        self:StopHover()
    end)
    self.button:HookScript("OnMouseUp", function()
        self:StartHover()
    end)
    self.button:HookScript("OnDragStart", function()
        self.dragging = true
        self:StopHover()
    end)
    self.button:HookScript("OnDragStop", function()
        self.dragging = false
        self:StartHover()
    end)
    log:debug("Minimap button registered")
end

function module:OnEnable()
    self.hoverEnabled = true
end

function module:OnDisable()
    self.hoverEnabled, self.dragging = false, false
    self:StopHover()
end

function module:StopHover()
    local hover = self.hover
    if hover then
        hover.scene:SetScript("OnUpdate", nil)
        hover.scene:Hide()
        hover.actor:Hide()
        if hover.iconAlpha then
            self.button.icon:SetAlpha(hover.iconAlpha)
            hover.iconAlpha = nil
        end
    end
end

function module:ShowHover()
    local hover = self.hover
    hover.scene:SetAlpha(1)
    if not hover.iconAlpha then
        hover.iconAlpha = self.button.icon:GetAlpha()
    end
    self.button.icon:SetAlpha(0)
    -- Rotation comes from the gem's idle animation, with no per-frame Lua yaw calls.
    hover.actor:SetAnimation(0, 0, 1, 0)
    hover.scene:SetScript("OnUpdate", nil)
end

function module:StartHover()
    local button = self.button
    if
        not self.hoverEnabled
        or self.dragging
        or button.isMouseDown
        or not button:IsShown()
        or not button:IsMouseOver()
    then
        return
    end
    if not self.hover then
        local entry = app.biomes.Get("default").coin.models[1]
        if not entry then
            return
        end
        local scene = CreateFrame("ModelScene", nil, button)
        scene:Hide()
        -- Follow the library's icon region, including Classic's offset and skin sizing.
        -- Mouse-disabled child: the original button keeps all pointer input.
        scene:SetAllPoints(button.icon)
        scene:EnableMouse(false)
        scene:SetFrameLevel(button:GetFrameLevel())
        scene:SetDrawLayer("ARTWORK")
        scene:SetCameraNearClip(app.overlay.CLIP_NEAR)
        scene:SetCameraFarClip(app.overlay.CLIP_FAR)
        scene:SetCameraOrientationByYawPitchRoll(0, 0, 0)
        scene:SetCameraFieldOfView(HOVER_FOV)
        scene:SetCameraPosition(-0.5 / math.tan(HOVER_FOV / 2) * 1.15, 0, 0)
        scene:SetLightAmbientColor(0.8, 0.8, 0.8)
        scene:SetLightDiffuseColor(0.8, 0.8, 0.8)
        local actor = scene:CreateActor()
        actor:SetUseCenterForOrigin(true, true, true)
        actor:SetPosition(0, 0, 0)
        actor:SetScale(1)
        actor:SetYaw(0)
        actor:SetPitch(0)
        self.hover = { scene = scene, actor = actor, model = entry.model, wait = 0 }
        if not actor:SetModelByFileID(entry.model) then
            self.hover.failed = true
        end
    end
    local hover = self.hover
    if hover.failed then
        return
    end
    hover.actor:Show()
    hover.scene:Show()
    if hover.ready then
        self:ShowHover()
        return
    end
    -- Keep the texture visible while loading. Poll only during hover, with a bounded
    -- timeout; missing or mismatched assets retain the static fallback.
    hover.scene:SetAlpha(0)
    hover.scene:SetScript("OnUpdate", function(_, elapsed)
        hover.wait = hover.wait + elapsed
        local minX, minY, minZ, maxX, maxY, maxZ = app.overlay.Extents(hover.actor)
        local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
        if size > 0.001 and hover.actor:GetModelFileID() == hover.model then
            hover.actor:SetScale(HOVER_ZOOM / size)
            hover.actor:SetPitch(maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY) and math.pi / 2 or 0)
            hover.ready = true
            self:ShowHover()
        elseif hover.wait > LOAD_TIMEOUT then
            hover.failed = true
            self:StopHover()
            log:debug("Minimap gem model %d did not load; retaining texture", hover.model)
        end
    end)
end

-- The addon's first OnProfileRefresh runs before module:OnInitialize, hence the guard.
function module:OnProfileRefresh()
    self:StopHover()
    local icon = LibStub("LibDBIcon-1.0")
    if icon:IsRegistered(appName) then
        icon:Refresh(appName, app.db.profile.minimap)
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
