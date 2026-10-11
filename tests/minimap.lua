-- Run the real vendored LibDBIcon scripts with WoW frame stand-ins. Verify that the
-- persistent model coexists with tooltip/click/drag behavior and profile visibility.
local methods, sceneCount, actorCount = {}, 0, 0
local function noop() end
local function frame(kind, parent)
    local f = setmetatable({
        kind = kind,
        parent = parent or false,
        shown = true,
        alpha = 1,
        scripts = {},
        hooks = {},
        owner = false,
        name = false,
        children = {},
    }, {
        __index = function(_, key)
            return methods[key] or noop
        end,
    })
    if parent then
        table.insert(parent.children, f)
    end
    return f
end
function methods:SetScript(event, fn)
    self.scripts[event] = fn
end
function methods:HookScript(event, fn)
    self.hooks[event] = self.hooks[event] or {}
    table.insert(self.hooks[event], fn)
end
function methods:Run(event, ...)
    if self.scripts[event] then
        self.scripts[event](self, ...)
    end
    for _, hook in ipairs(self.hooks[event] or {}) do
        hook(self, ...)
    end
end
local function visibilityEvent(f, event)
    f:Run(event)
    for _, child in ipairs(f.children) do
        if child.shown then
            visibilityEvent(child, event)
        end
    end
end
function methods:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function methods:Show()
    local wasVisible = self:IsVisible()
    self.shown = true
    if not wasVisible and self:IsVisible() then
        visibilityEvent(self, "OnShow")
    end
end
function methods:Hide()
    local wasVisible = self:IsVisible()
    self.shown = false
    if wasVisible then
        visibilityEvent(self, "OnHide")
    end
end
function methods:IsShown()
    return self.shown
end
function methods:IsMouseOver()
    return self.mouseOver == true
end
function methods:SetAlpha(alpha)
    self.alpha = alpha
end
function methods:GetAlpha()
    return self.alpha
end
function methods:SetFrameLevel(level)
    self.level = level
end
function methods:GetFrameLevel()
    return self.level
end
function methods:EnableMouse(enabled)
    self.mouseEnabled = enabled
end
function methods:SetAllPoints(target)
    self.target = target
end
function methods:GetParent()
    return self.parent
end
function methods:SetOwner(owner)
    self.owner = owner
end
function methods:GetOwner()
    return self.owner
end
function methods:GetName()
    return self.name or nil
end
function methods:GetVertexColor()
    return 1, 1, 1
end
function methods:SetTexture(texture)
    self.texture = texture
end
function methods:GetTexture()
    return self.texture
end
function methods:GetCenter()
    return 100, 100
end
function methods:GetWidth()
    return 200
end
methods.GetHeight = methods.GetWidth
function methods:CreateTexture()
    return frame("Texture", self)
end
function methods:CreateMaskTexture()
    return frame("MaskTexture", self)
end
function methods:CreateAnimationGroup()
    return frame("AnimationGroup", self)
end
function methods:CreateAnimation()
    return frame("Animation", self)
end
function methods:CreateActor()
    actorCount = actorCount + 1
    local actor = frame("Actor", self)
    actor.loaded, actor.model, actor.returnedModel = false, 0, false
    actor.boundsQueries = 0
    return actor
end
function methods:SetModelByFileID(id)
    self.model = id
    if id == 998 then
        return nil -- Legacy client success without a boolean result.
    end
    return id ~= 999
end
function methods:GetModelFileID()
    return self.returnedModel or self.model
end
function methods:SetAnimation(_, _, speed)
    self.speed = speed
end
function methods:SetScale(scale)
    self.scale = scale
end
function CreateFrame(kind, name, parent)
    if kind == "ModelScene" then
        sceneCount = sceneCount + 1
    end
    local f = frame(kind, parent)
    f.name = name or false
    if name then
        _G[name] = f
    end
    return f
end
UIParent = frame("Frame")
Minimap = frame("Frame", UIParent)
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
local libraries = {
    ["LibDataBroker-1.1"] = {
        RegisterCallback = noop,
        NewDataObject = function(_, _, object)
            return object
        end,
    },
    ["CallbackHandler-1.0"] = {
        New = function()
            return { Fire = noop }
        end,
    },
    ["LibDBIcon-1.0"] = { loggedIn = true },
}
LibStub = setmetatable({
    NewLibrary = function(_, name)
        return libraries[name]
    end,
}, {
    __call = function(_, name)
        return assert(libraries[name], name)
    end,
})
dofile("AzerothSurfers/lib/LibDBIcon-1.0/LibDBIcon-1.0/LibDBIcon-1.0.lua")
local icon = libraries["LibDBIcon-1.0"]
local index = 0
local function new(model, hidden)
    index = index + 1
    local app = {
        TITLE = "Azeroth Surfers",
        logger = { debug = noop },
        db = { profile = { minimap = { minimapPos = 200, hide = hidden } } },
        biomes = {
            Get = function()
                return { coin = { models = { { model = model or 201054 } } } }
            end,
        },
        overlay = {
            CLIP_NEAR = 0.2,
            CLIP_FAR = 250,
            Extents = function(actor)
                actor.boundsQueries = actor.boundsQueries + 1
                if actor.loaded then
                    return -1, -1, -1, 1, 1, 1
                end
            end,
        },
        challenges = { KINDS = {} },
    }
    app.overlay.Toggle = function()
        app.clicked = "play"
    end
    app.options = {
        Open = function()
            app.clicked = "options"
        end,
    }
    local name = "AzerothSurfersModelTest" .. index
    dofile("tests/load.lua")(app, {}) -- Supply the common Ace module stand-in.
    -- Give failure cases distinct identities in the real library's button registry.
    assert(loadfile("AzerothSurfers/src/core/minimapbutton.lua"))(name, app)
    app.minimapButton:OnProfileRefresh() -- Safe before registration.
    app.minimapButton:OnInitialize()
    app.minimapButton:OnEnable()
    return app, app.minimapButton, name
end
local app, module, name = new()
local button, gem = module.button, module.gem
local enter, dragStart, click = button.scripts.OnEnter, button.scripts.OnDragStart, button.scripts.OnClick
assert(sceneCount == 1 and actorCount == 1, "enable creates one scene without waiting for hover")
assert(gem.scene:IsVisible() and gem.scene.scripts.OnUpdate, "visible button starts asynchronous loading immediately")
assert(
    gem.scene.target == button.icon and not gem.scene.mouseEnabled,
    "model follows icon region without taking pointer input"
)
assert(gem.scene:GetFrameLevel() > button:GetFrameLevel(), "model renders above the button background")
assert(button.icon:GetAlpha() == 1 and gem.scene:GetAlpha() > 0, "static fallback remains visible while model loads")
gem.actor.loaded = true
gem.scene:Run("OnUpdate", 0.1)
assert(
    gem.ready and gem.scene:GetAlpha() == 1 and button.icon:GetAlpha() == 0,
    "loaded model replaces texture without hover"
)
assert(
    gem.actor.speed == 1 and not gem.scene.scripts.OnUpdate,
    "native animation runs without a steady Lua update handler"
)
assert(
    button.icon:GetTexture() == module.ldb.icon and module.ldb.icon:find("icon-gem-zoomed", 1, true),
    "real icon texture remains accessible to other addons"
)
button.mouseOver = true
button:Run("OnEnter")
assert(icon.tooltip:IsShown() and gem.scene:IsVisible(), "library tooltip coexists with the persistent model")
button.mouseOver = false
button:Run("OnLeave")
assert(
    not icon.tooltip:IsShown() and gem.scene:IsVisible() and button.icon:GetAlpha() == 0,
    "leaving preserves the model"
)
button:Run("OnClick", "LeftButton")
assert(app.clicked == "play", "left click still opens game")
button:Run("OnClick", "RightButton")
assert(app.clicked == "options", "right click still opens options")
button:Run("OnMouseDown")
assert(button.isMouseDown and gem.scene:IsVisible(), "model persists while pressed")
button:Run("OnDragStart")
assert(
    button.scripts.OnUpdate and gem.scene:IsVisible(),
    "library drag update remains intact while model follows its anchor"
)
button:Run("OnMouseUp")
button:Run("OnDragStop")
assert(not button.scripts.OnUpdate and gem.scene:IsVisible(), "drag stop leaves model visible")
assert(
    button.scripts.OnEnter == enter and button.scripts.OnDragStart == dragStart and button.scripts.OnClick == click,
    "button input scripts are untouched"
)
assert(not button.hooks.OnEnter and not button.hooks.OnLeave, "no hover hooks are installed")
module:OnProfileRefresh()
assert(gem.scene:IsVisible() and button.icon:GetAlpha() == 0, "visible profile refresh keeps model active")
app.db.profile.minimap.hide = true
module:OnProfileRefresh()
assert(
    not gem.scene:IsVisible() and not gem.actor:IsShown() and button.icon:GetAlpha() == 1,
    "hidden profile stops rendering and restores fallback"
)
app.db.profile.minimap.hide, app.db.profile.minimap.lock = false, true
module:OnProfileRefresh()
assert(
    gem.scene:IsVisible() and button.icon:GetAlpha() == 0 and not button.scripts.OnDragStart,
    "profile show resumes cached model with lock preserved"
)
module:OnDisable()
assert(not gem.scene:IsVisible() and button.icon:GetAlpha() == 1, "disable restores static icon")
module:OnEnable()
assert(gem.scene:IsVisible() and sceneCount == 1 and actorCount == 1, "reenable reuses scene and actor")
icon:Hide(name)
assert(not gem.scene:IsVisible() and not gem.actor:IsShown(), "direct library hide stops model rendering")
icon:Show(name)
assert(gem.scene:IsVisible() and button.icon:GetAlpha() == 0, "direct library show restores the model")
Minimap:Hide()
assert(not gem.scene:IsVisible() and not gem.actor:IsShown(), "ancestor hide propagates to scene lifecycle")
Minimap:Show()
assert(
    gem.scene:IsVisible() and not gem.scene.scripts.OnUpdate,
    "ancestor show resumes native animation without polling"
)
local prior = sceneCount
icon.tooltip:SetOwner(frame("Button"))
module.ldb.OnTooltipShow(icon.tooltip)
assert(
    sceneCount == prior and module.ldb.icon == button.icon:GetTexture(),
    "broker/compartment tooltips retain the static icon and do not create scenes"
)
print(
    "PASS persistent gem, retained LDB texture, real LibDBIcon input/tooltip/drag/lock behavior, visibility, disable and reuse"
)

local _, missing = new(999)
assert(missing.gem.failed and missing.button.icon:GetAlpha() == 1, "rejected model retains static fallback")
local _, legacy = new(998)
assert(not legacy.gem.failed, "nil model request result is accepted")
legacy.gem.actor.loaded = true
legacy.gem.scene:Run("OnUpdate", 0.1)
assert(legacy.gem.ready and legacy.button.icon:GetAlpha() == 0, "legacy model becomes visible without hover")
local _, timeout, timeoutName = new()
timeout.gem.scene:Run("OnUpdate", 5.1)
assert(
    timeout.gem.failed and not timeout.gem.scene.scripts.OnUpdate and timeout.button.icon:GetAlpha() == 1,
    "timeout ends polling and restores texture"
)
icon:Hide(timeoutName)
icon:Show(timeoutName)
assert(not timeout.gem.failed and timeout.gem.scene.scripts.OnUpdate, "show retries a cold-cache timeout")
timeout.gem.actor.loaded = true
timeout.gem.scene:Run("OnUpdate", 0.1)
assert(timeout.gem.ready, "timed-out model recovers after visibility cycle")
local _, wrong = new()
wrong.gem.actor.loaded, wrong.gem.actor.returnedModel = true, 123
wrong.gem.scene:Run("OnUpdate", 5.1)
assert(wrong.gem.failed and wrong.button.icon:GetAlpha() == 1, "incorrect model cannot replace fallback texture")
print("PASS nil, rejected, timed-out and mismatched model requests with static fallback and visibility retry")

local _, initiallyHidden, hiddenName = new(nil, true)
assert(
    not initiallyHidden.gem.scene:IsVisible() and not initiallyHidden.gem.scene.scripts.OnUpdate,
    "initially hidden button does not poll or render"
)
icon:Show(hiddenName)
assert(
    initiallyHidden.gem.scene:IsVisible() and initiallyHidden.gem.scene.scripts.OnUpdate,
    "first show starts loading even without pointer events"
)
icon:Hide(hiddenName)
assert(
    not initiallyHidden.gem.scene.scripts.OnUpdate and not initiallyHidden.gem.actor:IsShown(),
    "hiding during loading cancels polling"
)
icon:Show(hiddenName)
initiallyHidden.gem.actor.loaded = true
initiallyHidden.gem.scene:Run("OnUpdate", 0.1)
assert(
    initiallyHidden.gem.ready and not initiallyHidden.gem.scene.scripts.OnUpdate,
    "loading resumes and finishes after a visibility cycle"
)
print("PASS initially hidden model defers polling and resumes on visibility changes")
