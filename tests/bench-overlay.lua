-- Counts the WoW API calls the full-screen view makes per frame, on a generated track with lane
-- changes and jumps. Not part of `npm run check`; run with `lua tests/bench-overlay.lua`.
local counts, frames = {}, 0
local methods = {}
local special = {}
local proto = setmetatable({}, {
    __index = function(_, name)
        local f = special[name]
        if not f then
            f = methods[name]
            if not f then
                f = function()
                    counts[name] = (counts[name] or 0) + 1
                end
                methods[name] = f
            end
        end
        return f
    end,
})
local meta = { __index = proto }
local shownScenes = {}
local function stub(kind)
    return setmetatable({ kind = kind, shown = true, scripts = {} }, meta)
end
local function count(name)
    counts[name] = (counts[name] or 0) + 1
end
function special.GetStringHeight()
    count("GetStringHeight")
    return 12
end
function special.GetStringWidth()
    count("GetStringWidth")
    return 60
end
function special.GetSize()
    count("GetSize")
    return 1920, 1080
end
function special.GetWidth()
    return 1920
end
function special.GetHeight()
    return 1080
end
function special.GetFrameLevel()
    return 1
end
function special.IsShown(self)
    return self.shown
end
function special.Show(self)
    count("Show")
    self.shown = true
end
function special.Hide(self)
    count("Hide")
    self.shown = false
end
function special.SetShown(self, shown)
    count("SetShown")
    self.shown = shown
end
function special.SetScript(self, name, f)
    self.scripts[name] = f
end
function special.CreateTexture()
    count("CreateTexture")
    return stub("Texture")
end
function special.CreateMaskTexture()
    return stub("MaskTexture")
end
function special.CreateFontString()
    return stub("FontString")
end
function special.CreateActor(self)
    local actor = stub("Actor")
    actor.scene = self
    return actor
end
function special.IsLoaded()
    return true
end
function special.GetActiveBoundingBox()
    return -0.3, -0.4, 0, 0.3, 0.4, 2
end
local projected = 0
function special.Project3DPointTo2D()
    projected = projected + 1
    return 960, 540 + projected % 2 * 100, 10
end
function special.SetTexture()
    count("SetTexture")
    return true
end
function special.SetModelByFileID()
    return true
end
function special.SetModelByUnit()
    return true
end
function special.GetScale()
    return 1
end
function special.GetEffectiveScale()
    return 1
end

function CreateFrame(kind, _, _, template)
    local frame = stub(kind)
    if kind == "ModelScene" then
        shownScenes[#shownScenes + 1] = frame
    end
    if template == "PortraitFrameTemplate" then
        frame.Bg, frame.TopTileStreaks = stub("Texture"), stub("Texture")
        frame.CloseButton = stub("Button")
        local title = stub("FontString")
        function frame.GetTitleText()
            return title
        end
    end
    return frame
end
UIParent = stub("Frame")
function ButtonFrameTemplate_HidePortrait() end
function GetBindingKey() end
function GetBindingText(key)
    return key
end
function CreateColor()
    return stub("Color")
end
local x = 0
function UnitPosition()
    return x, 0, 0, 1
end
function GetPlayerFacing()
    return 0
end
function GetUnitSpeed()
    return 7
end
function GetCameraZoom()
    return 12
end
function GetCVar()
    return "90"
end
function IsFalling()
    return false
end
function GetTime()
    return frames / 140
end
function InCombatLockdown()
    return false
end
function PlaySoundFile() end
function PlaySound() end
function debugprofilestop()
    return os.clock() * 1000
end

local app = {
    logger = {
        debug = function() end,
        chat = function(_, fmt, ...)
            print("  /surfer profile | " .. fmt:format(...))
        end,
    },
}
for _, file in ipairs({
    "core/db",
    "game/biomes",
    "biomes/default",
    "biomes/elwynn",
    "game/random",
    "game/simulation",
    "game/light",
    "game/shapes",
    "game/overlay",
    "game/decorations",
    "game/obstacles",
    "game/window",
    "game/menu",
    "game/hud",
    "game/legend",
    "game/messages",
    "game/controls",
}) do
    assert(loadfile("Surfer/src/" .. file .. ".lua"))("Surfer", app)
end
local profile = app.dbDefaults.profile
-- The runner follows the character's sampled movement, as without capturing the keys.
profile.capture = false
app.db = { profile = profile, global = { bestScore = 0 } }
math.randomseed(1)

local o, g = app.overlay, app.simulation
o:Create()
local update = o.frame.scripts.OnUpdate
-- Play 30 seconds at 140 fps: a lane change every 2 s, a jump every 3 s.
local seconds, fps = 30, 140
local clock = os.clock()
o.timing = { frames = 0 }
for i = 1, seconds * fps do
    frames = i
    x = x + 7 / fps
    if i % (2 * fps) == 0 then
        g.Move(o.state, (i / (2 * fps)) % 2 == 0 and 1 or -1)
    end
    if i % (3 * fps) == 0 then
        g.Jump(o.state)
    end
    update(o.frame, 1 / fps)
    -- Run through obstacles: the benchmark measures drawing, not playing.
    if o.state.status == "over" then
        o.state.status = "running"
    end
end
local lua = (os.clock() - clock) / (seconds * fps) * 1000
-- The parts' milliseconds per frame, as Surfer_Dev's /surfer profile reports them.
local parts = {}
for part, ms in pairs(o.timing) do
    if part ~= "frames" then
        parts[#parts + 1] = part
    end
end
table.sort(parts)
for _, part in ipairs(parts) do
    print(string.format("  %-38s %.3f ms", part, o.timing[part] / o.timing.frames))
end
o.timing = nil

local rows, total = {}, 0
for name, n in pairs(counts) do
    rows[#rows + 1] = { name, n / (seconds * fps) }
    total = total + n / (seconds * fps)
end
table.sort(rows, function(a, b)
    return a[2] > b[2]
end)
print(string.format("%s, %.0f yards, %d boxes on the track", o.state.status, o.state.distance, #o.state.objects))
print(string.format("API calls per frame: %.0f   Lua time per frame (stubbed API): %.3f ms", total, lua))
for i = 1, math.min(14, #rows) do
    print(string.format("  %-28s %8.1f", rows[i][1], rows[i][2]))
end
local shown = 0
for _, scene in ipairs(shownScenes) do
    shown = shown + (scene.shown and 1 or 0)
end
print(string.format("ModelScenes shown: %d of %d", shown, #shownScenes))
