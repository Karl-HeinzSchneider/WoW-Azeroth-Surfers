---@type string, AzerothSurfers
local appName, app = ...
local log, addon = app.logger, app.addon

-- Keep a real texture in LDB and on the library's icon region for other displays.
-- Only our minimap region's alpha changes once the model is ready.
local ICON = "Interface\\AddOns\\AzerothSurfers\\assets\\core\\icon-gem-zoomed"
local FOV, ZOOM, LOAD_TIMEOUT, LOAD_ALPHA = 0.5, 3.5, 5, 0.01
-- About one UI pixel lower within the 17/18-pixel viewport. Raising the camera
-- offsets the visible model without depending on its native bounds or actor scale.
local CAMERA_Z = 0.06
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

---@class AzerothSurfers.MinimapButton : AceModule
---@field ldb LibDataBroker.QuickLauncher
---@field button table  # LibDBIcon's button and retained static icon region
---@field gem table?  # one persistent ModelScene and actor
---@field modelEnabled boolean?
---@field backdrop table  # opaque black disk and Blizzard's circular mask
local module = {}
app.minimapButton = addon:NewModule("MinimapButton", module) --[[@as AzerothSurfers.MinimapButton]]

function module:OnInitialize()
    self.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(appName, {
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
    }) --[[@as LibDataBroker.QuickLauncher]]
    local icon = LibStub("LibDBIcon-1.0")
    icon:Register(appName, self.ldb, app.db.profile.minimap)
    self.button = icon:GetMinimapButton(appName)
    -- Follow the library's circular background footprint, including Classic offsets.
    -- A separate opaque fill removes the stock art's translucent interior.
    local backdrop = self.button:CreateTexture(nil, "BACKGROUND", nil, 1)
    backdrop:SetAllPoints(self.button.background)
    backdrop:SetColorTexture(0, 0, 0, 1)
    local mask = self.button:CreateMaskTexture()
    mask:SetAllPoints(backdrop)
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    backdrop:AddMaskTexture(mask)
    self.backdrop = { texture = backdrop, mask = mask }
    log:debug("Minimap button registered")
end

function module:CreateGem()
    if self.gem then
        return
    end
    local entry = app.biomes.Get("default").coin.models[1]
    if not entry then
        return
    end
    local scene = CreateFrame("ModelScene", nil, self.button)
    scene:Hide()
    scene:SetAllPoints(self.button.icon)
    scene:EnableMouse(false)
    scene:SetFrameLevel(self.button:GetFrameLevel() + 1)
    scene:SetDrawLayer("OVERLAY")
    scene:SetCameraNearClip(app.overlay.CLIP_NEAR)
    scene:SetCameraFarClip(app.overlay.CLIP_FAR)
    scene:SetCameraOrientationByYawPitchRoll(0, 0, 0)
    scene:SetCameraFieldOfView(FOV)
    scene:SetCameraPosition(-0.5 / math.tan(FOV / 2) * 1.15, 0, CAMERA_Z)
    scene:SetLightAmbientColor(0.8, 0.8, 0.8)
    scene:SetLightDiffuseColor(0.8, 0.8, 0.8)
    local actor = scene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(0, 0, 0)
    actor:SetScale(1)
    actor:SetYaw(0)
    actor:SetPitch(0)
    actor:Hide()
    self.gem = { scene = scene, actor = actor, model = entry.model, wait = 0 }
    local accepted = actor:SetModelByFileID(entry.model)
    self.gem.requestResult = tostring(accepted)
    if accepted == false then
        self.gem.failed, self.gem.failure = true, "request rejected"
    end
    -- Own scene scripts follow effective parent visibility. No minimap hover hooks,
    -- tooltip ownership checks, or changes to the library's input scripts are needed.
    scene:SetScript("OnShow", function()
        self:ResumeGem()
    end)
    scene:SetScript("OnHide", function()
        self:PauseGem()
    end)
end

function module:PauseGem()
    local gem = self.gem
    if gem then
        gem.scene:SetScript("OnUpdate", nil)
        gem.actor:Hide()
        if gem.iconAlpha then
            self.button.icon:SetAlpha(gem.iconAlpha)
            gem.iconAlpha = nil
        end
    end
end

function module:ShowGem()
    local gem = self.gem
    gem.scene:SetAlpha(1)
    if not gem.iconAlpha then
        gem.iconAlpha = self.button.icon:GetAlpha()
    end
    self.button.icon:SetAlpha(0)
    gem.actor:Show()
    gem.actor:SetAnimation(0, 0, 1, 0)
    gem.scene:SetScript("OnUpdate", nil)
end

function module:ResumeGem()
    local gem = self.gem
    if not self.modelEnabled or not gem or not gem.scene:IsVisible() then
        return
    end
    if gem.failed then
        if gem.failure ~= "load timed out" then
            return
        end
        gem.failed, gem.failure, gem.wait = false, nil, 0
    end
    if gem.ready then
        self:ShowGem()
        return
    end
    -- Nonzero opacity allows native loading to advance; the texture stays visible
    -- until the requested model has usable bounds. Polling ends after fitting/failure.
    gem.scene:SetAlpha(LOAD_ALPHA)
    gem.actor:Show()
    gem.scene:SetScript("OnUpdate", function(_, elapsed)
        gem.wait = gem.wait + elapsed
        local minX, minY, minZ, maxX, maxY, maxZ = app.overlay.Extents(gem.actor)
        local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
        if size > 0.001 and gem.actor:GetModelFileID() == gem.model then
            gem.actor:SetScale(ZOOM / size)
            gem.actor:SetPitch(maxZ - minZ < 0.3 * math.max(maxX - minX, maxY - minY) and math.pi / 2 or 0)
            gem.ready = true
            self:ShowGem()
        elseif gem.wait > LOAD_TIMEOUT then
            gem.failed, gem.failure = true, "load timed out"
            self:PauseGem()
            gem.scene:SetAlpha(0)
            log:debug("Minimap gem model %d did not load; retaining texture", gem.model)
        end
    end)
end

function module:OnEnable()
    self.modelEnabled = true
    self:CreateGem()
    if self.gem then
        self.gem.scene:Show()
        self:ResumeGem()
    end
end

function module:OnDisable()
    self.modelEnabled = false
    self:PauseGem()
    if self.gem then
        self.gem.scene:Hide()
    end
end

-- The first profile refresh precedes initialization; the registration guard covers it.
function module:OnProfileRefresh()
    local icon = LibStub("LibDBIcon-1.0")
    if icon:IsRegistered(appName) then
        self:PauseGem()
        icon:Refresh(appName, app.db.profile.minimap)
        self:ResumeGem()
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
