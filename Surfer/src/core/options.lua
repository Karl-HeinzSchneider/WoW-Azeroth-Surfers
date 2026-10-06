---@type string, Surfer
local appName, app = ...

local log = app.logger
local addon = app.addon

-- The addon's options as one AceConfig table, shown in the game's Settings panel (AddOns tab) and
-- in a standalone window (`/surfer`), so an option is added here once.
---@class Surfer.Options : AceModule
local module = {}
app.options = addon:NewModule("Options", module) --[[@as Surfer.Options]]

-- The log levels for the select, quietest first, shown as "Info" for "INFO".
local levelNames, levelOrder = {}, {}
for name in pairs(log.level) do
    levelNames[name] = name:sub(1, 1) .. name:sub(2):lower()
    levelOrder[#levelOrder + 1] = name
end
table.sort(levelOrder, function(a, b)
    return log.level[a] < log.level[b]
end)

-- A calibration slider; the road reprojects on its own when a value changes.
local function calibration(order, key, name, desc, min, max, step)
    return {
        type = "range",
        order = order,
        name = name,
        desc = desc,
        min = min,
        max = max,
        step = step,
        get = function()
            return app.db.profile.overlay[key]
        end,
        set = function(_, value)
            app.db.profile.overlay[key] = value
        end,
    }
end

local options = {
    type = "group",
    name = appName,
    args = {
        coinSound = {
            type = "toggle",
            order = 6,
            width = "full",
            name = "Coin sound",
            desc = "Play the money loot sound when you collect a coin.",
            get = function()
                return app.db.profile.coinSound
            end,
            set = function(_, value)
                app.db.profile.coinSound = value
            end,
        },
        biome = {
            type = "select",
            order = 7,
            name = "Biome",
            desc = "How the game looks: its ground, obstacles and coins.",
            values = function()
                return app.biomes.Names()
            end,
            get = function()
                return app.db.profile.biome
            end,
            set = function(_, value)
                app.db.profile.biome = value
                if app.overlay.frame then
                    app.overlay:ApplyBiome()
                end
            end,
        },
        overlay = {
            type = "group",
            order = 30,
            inline = true,
            name = "Calibration",
            args = {
                help = {
                    type = "description",
                    order = 1,
                    name = "Open the game and stand still, then adjust until the see-through copy covers your character and the road lies flat on the ground. Zooming or tilting the camera changes the fit.",
                },
                hideReal = {
                    type = "toggle",
                    order = 3,
                    width = "full",
                    name = "Hide your real character (first-person camera)",
                    desc = "The game does not draw your character in first person, so only the twin shows. Zooms all the way in while the game is open and back out after; the world is then seen from eye height.",
                    get = function()
                        return app.db.profile.overlay.hideReal
                    end,
                    set = function(_, value)
                        app.db.profile.overlay.hideReal = value
                        app.overlay:ApplyHideReal()
                    end,
                },
                pitch = calibration(
                    10,
                    "pitch",
                    "Camera pitch",
                    "How far your camera looks down, in degrees. Moves the horizon.",
                    -10,
                    80,
                    1
                ),
                focus = calibration(
                    20,
                    "focus",
                    "Focus height",
                    "Where on your character the camera points, as a share of its height. Moves the road up and down.",
                    0.2,
                    1.5,
                    0.01
                ),
                distance = calibration(
                    30,
                    "distance",
                    "Camera distance",
                    "Your camera zoom in yards. Only used when the client cannot report the zoom itself.",
                    1,
                    40,
                    0.5
                ),
                fov = calibration(
                    40,
                    "fov",
                    "Field of view",
                    "The game's vertical field of view in degrees. Changes how wide the road looks.",
                    30,
                    100,
                    1
                ),
                twinScale = calibration(
                    45,
                    "twinScale",
                    "Twin size",
                    "Size of the twin compared to your real character.",
                    0.5,
                    1.5,
                    0.01
                ),
                opacity = calibration(60, "opacity", "Road opacity", nil, 0.1, 1, 0.05),
                brightness = calibration(
                    70,
                    "brightness",
                    "Ground brightness",
                    "How bright the road and grass are by day.",
                    0.2,
                    1,
                    0.05
                ),
                dayNight = {
                    type = "toggle",
                    order = 75,
                    name = "Darker at night",
                    desc = "The ground, your twin and the coins follow the game's clock: dimmed and moonlit blue at night, brightening at dawn (5 to 7) and darkening at dusk (19 to 21).",
                    get = function()
                        return app.db.profile.overlay.dayNight
                    end,
                    set = function(_, value)
                        app.db.profile.overlay.dayNight = value
                    end,
                },
            },
        },
        minimap = {
            type = "toggle",
            order = 10,
            width = "full",
            name = "Show minimap button",
            desc = "The minimap button opens these options.",
            get = function()
                return not app.db.profile.minimap.hide
            end,
            set = function(_, value)
                app.db.profile.minimap.hide = not value
                app.minimapButton:OnProfileRefresh()
            end,
        },
        logLevel = {
            type = "select",
            order = 20,
            name = "Log level",
            desc = "How much " .. appName .. " writes to the chat window. Same as /surfer loglevel <level>.",
            values = levelNames,
            sorting = levelOrder,
            get = function()
                return app.db.profile.logLevel
            end,
            set = function(_, value)
                if log:setLevel(value) then
                    app.db.profile.logLevel = log:getLevelName()
                end
            end,
        },
    },
}

-- Runs after addon:OnInitialize, so app.db is available.
function module:OnInitialize()
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(app.db)
    options.args.profiles.order = 100

    LibStub("AceConfig-3.0"):RegisterOptionsTable(appName, options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(appName)
end

-- Toggles the options in a standalone window.
function module:Open()
    local dialog = LibStub("AceConfigDialog-3.0")
    if dialog.OpenFrames[appName] then
        dialog:Close(appName)
    else
        dialog:Open(appName)
    end
end

-- Redraws the options wherever they are shown, after a setting changed outside of them.
function module:Refresh()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(appName)
end

-- A profile switch, copy or reset changes every value.
function module:OnProfileRefresh()
    self:Refresh()
end
