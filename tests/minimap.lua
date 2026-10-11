-- Run the real vendored LibDBIcon scripts with WoW frame stand-ins. Verify that the
-- model hover coexists with tooltip/click/drag behavior and library profile refreshes.
local methods, sceneCount, actorCount = {}, 0, 0
local function noop() end
local function frame(kind, parent)
    return setmetatable({ kind = kind, parent = parent, shown = true, alpha = 1, scripts = {}, hooks = {} }, {
        __index = function(_, key)
            return methods[key] or noop
        end,
    })
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
function methods:Show()
    self.shown = true
end
function methods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown then
        self:Run("OnHide")
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
function methods:GetVertexColor()
    return 1, 1, 1
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
    return actor
end
function methods:SetModelByFileID(id)
    self.model = id
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
local function new(model)
    index = index + 1
    local app = {
        TITLE = "Azeroth Surfers",
        logger = { debug = noop },
        db = { profile = { minimap = { minimapPos = 200 } } },
        biomes = {
            Get = function()
                return { coin = { models = { { model = model or 201054 } } } }
            end,
        },
        overlay = {
            CLIP_NEAR = 0.2,
            CLIP_FAR = 250,
            Extents = function(actor)
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
    local name = "AzerothSurfersHoverTest" .. index
    dofile("tests/load.lua")(app, {}) -- Supply the common Ace module stand-in.
    -- Give failure cases distinct identities in the real library's button registry.
    assert(loadfile("AzerothSurfers/src/core/minimapbutton.lua"))(name, app)
    app.minimapButton:OnProfileRefresh() -- Safe before registration.
    app.minimapButton:OnInitialize()
    app.minimapButton:OnEnable()
    return app, app.minimapButton, name
end
local app, module, name = new()
local button = module.button
assert(sceneCount == 0, "initialization must not allocate a model scene")
local enter, dragStart, click = button.scripts.OnEnter, button.scripts.OnDragStart, button.scripts.OnClick
button.mouseOver = true
button:Run("OnEnter")
assert(icon.tooltip:IsShown(), "library tooltip must still open")
assert(sceneCount == 1 and actorCount == 1, "first hover creates exactly one scene and actor")
local hover = module.hover
assert(hover.scene.target == button.icon and not hover.scene.mouseEnabled, "scene follows icon without taking input")
assert(button.icon:GetAlpha() == 1 and hover.scene:GetAlpha() == 0, "texture stays visible during loading")
hover.scene:Run("OnUpdate", 0.1)
assert(not hover.ready, "loading is asynchronous")
button.mouseOver = false
button:Run("OnLeave")
assert(not hover.scene.scripts.OnUpdate and button.icon:GetAlpha() == 1, "leaving while loading cancels polling")
button:Run("OnMouseUp")
assert(not hover.scene:IsShown(), "mouse up outside the button cannot start a model")
button.mouseOver = true
button:Run("OnEnter")
assert(sceneCount == 1, "unfinished loading resumes in the same scene")
hover.actor.loaded = true
hover.scene:Run("OnUpdate", 0.1)
assert(hover.ready and button.icon:GetAlpha() == 0 and hover.scene:GetAlpha() == 1, "loaded model replaces texture")
assert(hover.actor.speed == 1 and not hover.scene.scripts.OnUpdate, "native animation needs no steady Lua update")
button:Run("OnClick", "LeftButton")
assert(app.clicked == "play", "left click still opens game")
button:Run("OnClick", "RightButton")
assert(app.clicked == "options", "right click still opens options")
button.mouseOver = false
button:Run("OnLeave")
assert(
    not icon.tooltip:IsShown() and not hover.scene:IsShown() and button.icon:GetAlpha() == 1,
    "leave restores texture and tooltip"
)
button.mouseOver = true
button:Run("OnEnter")
assert(sceneCount == 1 and actorCount == 1, "subsequent hover reuses scene and actor")
button:Run("OnMouseDown")
assert(button.isMouseDown and not hover.scene:IsShown(), "press keeps library pressed-icon behavior")
button:Run("OnDragStart")
assert(
    module.dragging and button.scripts.OnUpdate and not hover.scene:IsShown(),
    "library dragging owns button update script"
)
button:Run("OnMouseUp")
assert(not hover.scene:IsShown(), "mouse up during drag does not restart hover")
button:Run("OnDragStop")
assert(
    not module.dragging and not button.scripts.OnUpdate and hover.scene:IsShown(),
    "drag stop resumes hover without replacing drag scripts"
)
module:OnProfileRefresh()
assert(not hover.scene:IsShown() and button.icon:GetAlpha() == 1, "profile refresh cleans up hover")
assert(
    button.scripts.OnEnter == enter and button.scripts.OnDragStart == dragStart and button.scripts.OnClick == click,
    "library scripts are preserved"
)
button:Run("OnEnter")
assert(hover.scene:IsShown(), "hooks survive library Refresh replacing scripts")
app.db.profile.minimap.hide = true
module:OnProfileRefresh()
assert(not button:IsShown() and not hover.scene:IsShown() and button.icon:GetAlpha() == 1, "hidden profile stops model")
app.db.profile.minimap.hide, app.db.profile.minimap.lock = false, true
module:OnProfileRefresh()
assert(not button.scripts.OnDragStart, "library lock remains effective")
button:Run("OnEnter")
assert(hover.scene:IsShown(), "hover works while drag is locked")
module:OnDisable()
button:Run("OnEnter")
assert(not hover.scene:IsShown() and button.icon:GetAlpha() == 1, "disabled module does not restart hover")
module:OnEnable()
button:Run("OnEnter")
icon:Hide(name)
assert(not hover.scene:IsShown() and not hover.actor:IsShown(), "direct library hide stops rendering")
print(
    "PASS real LibDBIcon tooltip, clicks, pressed state, dragging, refresh, lock, hide and disable with lazy native-animation hover"
)

local _, missing = new(999)
missing.button.mouseOver = true
missing.button:Run("OnEnter")
assert(missing.hover.failed and missing.button.icon:GetAlpha() == 1, "rejected model retains static icon")
local _, timeout = new()
timeout.button.mouseOver = true
timeout.button:Run("OnEnter")
timeout.hover.scene:Run("OnUpdate", 5.1)
assert(
    timeout.hover.failed and not timeout.hover.scene:IsShown() and not timeout.hover.scene.scripts.OnUpdate,
    "timeout stops polling and rendering"
)
local _, wrong = new()
wrong.button.mouseOver = true
wrong.button:Run("OnEnter")
wrong.hover.actor.loaded, wrong.hover.actor.returnedModel = true, 123
wrong.hover.scene:Run("OnUpdate", 5.1)
assert(wrong.hover.failed and wrong.button.icon:GetAlpha() == 1, "error model with valid bounds cannot replace icon")
print("PASS rejected, timed-out and incorrect models retain static fallback")
