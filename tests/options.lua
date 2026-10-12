-- Options must work independently of the development addon, which adds its own controls.
local load = dofile("tests/load.lua")
local registered, changes
local registry = {
    NotifyChange = function()
        changes = (changes or 0) + 1
    end,
}
local libraries = {
    ["AceGUI-3.0"] = { WidgetRegistry = { AzerothSurfersGamepadKey = true } },
    ["AceConfigRegistry-3.0"] = registry,
    ["AceConfig-3.0"] = {
        RegisterOptionsTable = function(_, _, options)
            registered = options
        end,
    },
    ["AceConfigDialog-3.0"] = {
        AddToBlizOptions = function()
            return {}
        end,
        SetDefaultSize = function() end,
    },
    ["AceDBOptions-3.0"] = {
        GetOptionsTable = function()
            return { type = "group", args = {} }
        end,
    },
}
function LibStub(name)
    return assert(libraries[name], name)
end

local layouts, modes, inputs = 0, 0, 0
local app = {
    TITLE = "Azeroth Surfers",
    logger = { level = { INFO = 2, DEBUG = 3 } },
    overlay = {
        frame = {},
        ACTIONS = {},
        HUD_INFO = {
            { id = "seed", name = "Seed", desc = "Seed" },
            { id = "time", name = "Time", desc = "Elapsed time" },
            { id = "fps", name = "FPS", desc = "Frame rate" },
        },
        Layout = function()
            layouts = layouts + 1
        end,
        ApplyMode = function()
            modes = modes + 1
        end,
        RefreshInputHud = function()
            inputs = inputs + 1
        end,
    },
}
-- Define callbacks after app so they close over the local table.
app.overlay.SetSeed = function(_, value)
    app.db.profile.seed = value
end
load(app, { "core/db", "core/options" })
app.db = { profile = app.dbDefaults.profile }
app.options:OnInitialize()
assert(registered.args.general and registered.args.display and registered.args.scorecard)
assert(registered.args.keybindings and registered.args.sound and registered.args.profiles)
assert(not registered.args.debug, "Released addon must not expose debug controls")
assert(not registered.args.display.args.pitch and not registered.args.display.args.fixedCurve)
assert(
    registered.args.scorecard.args.hudInfo_seed and registered.args.scorecard.args.hudInfo_fps,
    "All extra scorecard rows remain together without the development addon"
)
assert(registered.args.scorecard.args.hudInfo_time, "Run time remains player-facing")

local display = registered.args.display.args
assert(display.opacity.disabled() == false)
display.mode.set(nil, "side")
assert(modes == 1 and display.opacity.disabled(), "Display changes apply immediately")
assert(display.frameFull.disabled() and not display.frameSide.disabled())
registered.args.scorecard.args.hudInfo_time.set(nil, true)
assert(app.db.profile.hudInfo.time and layouts == 1)
local input = display
input.inputHud.set(nil, "simplified")
assert(app.db.profile.inputHud and app.db.profile.inputHudSimplified and inputs == 1)
input.inputHud.set(nil, "none")
assert(not app.db.profile.inputHud and input.inputHudReset.disabled())
assert(registered.args.keybindings.name == "Keybindings" and registered.args.keybindings.args.reset)
assert(not registered.args.keybindings.childGroups and not registered.args.controls, "Bindings have no nested tabs")
assert(not registered.args.general.args.help, "General starts with settings")
registered.args.general.args.capture.set(nil, false)
assert(not app.db.profile.capture and modes == 2, "Capture remains functional in General")
display.legend.set(nil, false)
assert(not app.db.profile.legend, "Hotkey display remains functional in Display")
print("PASS player settings without the development addon")

assert(loadfile("AzerothSurfers_Dev/src/options.lua"))("AzerothSurfers_Dev", { app = app })
local debug = registered.args.debug.args
assert(debug.runs.args.seed and debug.runs.args.difficulty and debug.runs.args.biome)
assert(debug.rendering.args.pitch and debug.rendering.args.focus and debug.rendering.args.twinScale)
assert(debug.rendering.args.fixedCurve and debug.rendering.args.drawLevel)
assert(debug.diagnostics.args.logLevel)
assert(
    not debug.diagnostics.args.hudInfo_seed and not debug.diagnostics.args.hudInfo_fps,
    "Debug must not duplicate scorecard display preferences"
)
debug.runs.args.seed.set(nil, "123")
assert(app.db.profile.seed == 123, "Relocated seed option writes the same profile setting")
assert(debug.runs.args.seed.validate(nil, "1.5") ~= true)
assert(debug.runs.args.seed.validate(nil, "inf") ~= true)
assert(debug.runs.args.seed.validate(nil, "123") == true)
registered.args.scorecard.args.hudInfo_seed.set(nil, true)
assert(app.db.profile.hudInfo.seed and layouts == 2)
registered.args.scorecard.args.hudInfo_fps.set(nil, true)
assert(app.db.profile.hudInfo.fps and layouts == 3)
assert(changes > 0, "Debug registration refreshes existing settings panels")
print("PASS development settings extend the same options table")
