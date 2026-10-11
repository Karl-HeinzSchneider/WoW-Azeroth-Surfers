-- Exercise the dev audit against delayed loads, fallback files and audio failures.
local frames, messages, played, stopped, loaded = {}, {}, {}, {}, {}
local reportText, command
local function noop() end
local methods = {
    SetSize = noop,
    SetPoint = noop,
    SetAlpha = noop,
    SetTitle = noop,
    SetLayout = noop,
    SetWidth = noop,
    SetHeight = noop,
    SetLabel = noop,
    DisableButton = noop,
    AddChild = noop,
    SetCallback = noop,
    Release = noop,
}
function methods:Show()
    self.shown = true
end
function methods:Hide()
    self.shown = false
end
function methods:SetScript(event, fn)
    self[event] = fn
end
function methods:SetText(value)
    reportText = value
end
function methods:ClearModel()
    self.id, self.age = nil, 0
end
function methods:SetModelByFileID(id)
    self.id, self.age = id, 0
    loaded[id] = (loaded[id] or 0) + 1
    return id ~= 901
end
function methods:SetModelByCreatureDisplayID(id)
    return self:SetModelByFileID(id)
end
function methods:SetModelByUnit()
    return self:SetModelByFileID(800)
end
function methods:IsLoaded()
    return self.id and self.id ~= 902 and self.age >= 0.2
end
function methods:GetModelFileID()
    return self.id == 903 and 999 or self.id
end
function methods:SetDisplayInfo(id)
    self:SetModelByFileID(id)
end
function methods:SetUnit()
    self:SetModelByFileID(800)
end
function methods:HasAnimation(id)
    return not (self.id == 700 and id == 17)
end
function CreateFrame(kind)
    local frame = setmetatable({ kind = kind, age = 0 }, { __index = methods })
    frames[#frames + 1] = frame
    return frame
end
function methods:CreateActor()
    return CreateFrame("Actor")
end
function PlaySoundFile(id)
    played[id] = (played[id] or 0) + 1
    if id == 904 then
        return false
    end
    return true, id
end
function StopSound(id)
    stopped[id] = true
end
function GetBuildInfo()
    return "12.1.0", "test", "", 120100
end
function LibStub()
    return {
        Create = function(_, kind)
            return CreateFrame(kind)
        end,
    }
end

local app = {}
dofile("tests/load.lua")(app, { "game/biomes" })
app.biomes.Register("default", {
    obstacles = {
        obstacle = {
            {
                items = {
                    { model = { 900, 901, 902, 903 } },
                    { creature = { 700, 701 }, animation = 0, attack = 17, sound = { [700] = { 904, 905 } } },
                },
            },
        },
    },
    ambient = { creatures = { { creature = 702, voice = 906 } } },
    footsteps = { ground = { 907 }, wood = { 908 }, stride = 2.5 },
    coin = { models = { { model = 900, sound = { "addon.ogg" }, finale = 909 } } },
    entrance = "dream",
})
app.biomes.Register("forest", { name = "Forest" })
app.biomes.RegisterTransition("dream", { items = { { model = 910 } }, sounds = { approach = 911, through = 912 } })
app.lobby = { items = { { model = 913 } }, music = 914, seat = { sit = 97, standUp = 98 } }
local dev = {
    app = app,
    log = {
        chat = function(_, fmt, ...)
            messages[#messages + 1] = string.format(fmt, ...)
        end,
    },
}
function dev.Command(_, _, run)
    command = run
end
function dev.Words(text)
    local out = {}
    for word in text:gmatch("%S+") do
        out[#out + 1] = tonumber(word) or word
    end
    return out
end
assert(loadfile("AzerothSurfers_Dev/src/assets.lua"))("AzerothSurfers_Dev", dev)
local function tick(count)
    for _ = 1, count do
        for _, frame in ipairs(frames) do
            frame.age = frame.age + 0.1
            if frame.kind == "PlayerModel" and frame.id and frame.age >= 0.2 and frame.OnModelLoaded then
                frame:OnModelLoaded()
            end
            if frame.shown and frame.OnUpdate then
                frame:OnUpdate(0.1)
            end
        end
    end
end
command("all")
tick(1000)
command("report all")
assert(reportText:find("901 %[review%]: Model request rejected"), "rejected file reported")
assert(reportText:find("902 %[review%]: Model load timed out"), "timeout reported, not accepted from previous load")
assert(reportText:find("903 %[review%]: Requested file differs"), "fallback identity reported")
assert(reportText:find("700 %[review%]: Missing animation IDs: 17"), "requested attack checked")
assert(reportText:find("701 %[ok%]"), "next creature does not inherit prior animation result")
assert(reportText:find("904 %[review%]: Playback failed"), "failed audio remains inconclusive")
assert(played[905] == 1 and stopped[905], "deduplicated sound probe stopped")
assert(played["addon.ogg"] and played[914] and played[911], "custom sounds, music and transitions included")
assert(not played[2.5] and not played[700], "stride and display-map keys are not sounds")
assert(loaded[900] == 1 and loaded[913], "models deduplicated and lobby included")
assert(
    reportText:find("biomes.forest.obstacles") and reportText:find("biomes.default.obstacles"),
    "all usage paths retained"
)
local before = played[905]
command("models forest")
tick(1000)
assert(played[905] == before, "model scan does not play audio")
command("report")
assert(not reportText:find("%[skipped%]"), "issue report excludes category skips")
command("all")
tick(1)
command("stop")
local loads = loaded[700]
tick(100)
assert(loaded[700] == loads, "cancel prevents further work")
command("report")
assert(reportText:find("cancelled"), "partial report identifies cancellation")
print("PASS asset catalog, delayed loads, animation failures, sounds, filtering and cancellation")
