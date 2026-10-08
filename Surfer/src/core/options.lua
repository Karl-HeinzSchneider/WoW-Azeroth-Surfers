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

-- A mode setting; an open game takes it on at once.
local function modeSetting(order, name, desc, get, set)
    return {
        type = "toggle",
        order = order,
        width = "full",
        name = name,
        desc = desc,
        get = get,
        set = function(_, value)
            set(value)
            if app.overlay.frame then
                app.overlay:ApplyMode()
            end
        end,
    }
end

local options = {
    type = "group",
    name = appName,
    args = {
        mode = {
            type = "group",
            order = 1,
            inline = true,
            name = "Mode",
            args = {
                mode = {
                    type = "select",
                    order = 1,
                    name = "Mode",
                    desc = "Full screen: the road lies in the world around your character. Side window: the game runs in a window of its own, out of the way; drag it by its title and size it from its corner.",
                    values = { full = "Full screen", side = "Side window" },
                    sorting = { "full", "side" },
                    get = function()
                        return app.db.profile.mode
                    end,
                    set = function(_, value)
                        app.db.profile.mode = value
                        if app.overlay.frame then
                            app.overlay:ApplyMode()
                        end
                    end,
                },
                capture = modeSetting(
                    2,
                    "Capture movement keys",
                    "While the game is open it takes your move, strafe, turn and jump keys: your character stays where it is and the runner runs on its own. Steering with the mouse buttons still moves your character.",
                    function()
                        return app.db.profile.capture
                    end,
                    function(value)
                        app.db.profile.capture = value
                    end
                ),
                frameFull = modeSetting(
                    3,
                    "Window frame in full screen",
                    "A border, title bar and close button around the screen. Without it, the game looks like part of the world.",
                    function()
                        return app.db.profile.frame.full
                    end,
                    function(value)
                        app.db.profile.frame.full = value
                    end
                ),
                frameSide = modeSetting(
                    4,
                    "Window frame in the side window",
                    "A border, title bar and close button around the side window. Without it, the window can't be dragged or sized.",
                    function()
                        return app.db.profile.frame.side
                    end,
                    function(value)
                        app.db.profile.frame.side = value
                    end
                ),
                resetSide = {
                    type = "execute",
                    order = 5,
                    name = "Reset side window",
                    desc = "Put the side window back at the right edge of the screen, at its first size.",
                    func = function()
                        local saved, default = app.db.profile.side, app.dbDefaults.profile.side
                        for key, value in pairs(default) do
                            saved[key] = value
                        end
                        if app.overlay.frame then
                            app.overlay:ApplyMode()
                        end
                    end,
                },
            },
        },
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
        enemySound = {
            type = "toggle",
            order = 6.1,
            width = "full",
            name = "Creature sounds",
            desc = "Play an enemy's attack sound when you run past it, and what a creature crossing the road says.",
            get = function()
                return app.db.profile.enemySound
            end,
            set = function(_, value)
                app.db.profile.enemySound = value
            end,
        },
        portalSound = {
            type = "toggle",
            order = 6.2,
            width = "full",
            name = "Portal sounds",
            desc = "Play a teleport sound when you go through a portal between zones.",
            get = function()
                return app.db.profile.portalSound
            end,
            set = function(_, value)
                app.db.profile.portalSound = value
            end,
        },
        legend = {
            type = "toggle",
            order = 6.5,
            width = "full",
            name = "Show hotkeys",
            desc = "List the game's keys beside the road: your own movement keys, and Q and R.",
            get = function()
                return app.db.profile.legend
            end,
            set = function(_, value)
                app.db.profile.legend = value
            end,
        },
        difficulty = {
            type = "select",
            order = 6.55,
            name = "Difficulty",
            desc = "How fast the run goes and speeds up, how much room there is between obstacles, and which come up. During a run: from the next one on.",
            values = function()
                local names = {}
                for _, difficulty in ipairs(app.simulation.DIFFICULTIES) do
                    names[difficulty.id] = difficulty.name
                end
                return names
            end,
            sorting = function()
                local ids = {}
                for i, difficulty in ipairs(app.simulation.DIFFICULTIES) do
                    ids[i] = difficulty.id
                end
                return ids
            end,
            get = function()
                return app.db.profile.difficulty
            end,
            set = function(_, value)
                app.overlay:SetDifficulty(value)
            end,
        },
        fixedSeed = {
            type = "toggle",
            order = 6.6,
            width = "full",
            name = "Fixed seed",
            desc = "Every run lays out the same track, from the seed below. Off: a new seed every run.",
            get = function()
                return app.db.profile.seed ~= false
            end,
            set = function(_, value)
                app.overlay:SetFixedSeed(value)
            end,
        },
        seed = {
            type = "input",
            order = 6.7,
            name = "Seed",
            desc = "The seed every run starts from: a whole number. Checked first: the current run's.",
            hidden = function()
                return app.db.profile.seed == false
            end,
            get = function()
                return tostring(app.db.profile.seed)
            end,
            validate = function(_, value)
                return tonumber(value) ~= nil or "Enter a whole number."
            end,
            set = function(_, value)
                app.overlay:SetSeed(tonumber(value))
            end,
        },
        biome = {
            type = "select",
            order = 7,
            name = "Biome",
            desc = "How the game looks: its ground, obstacles and coins. Auto goes from zone to zone as you run, starter zones first, the way set by the seed.",
            values = function()
                local names = app.biomes.Names()
                names[app.biomes.AUTO] = "Auto: zone to zone"
                return names
            end,
            get = function()
                return app.db.profile.biome
            end,
            set = function(_, value)
                app.db.profile.biome = value
                if app.overlay.frame then
                    app.overlay:ApplyBiome()
                    -- During a run, as when entering a zone.
                    if app.overlay.state.status ~= "ready" then
                        app.overlay:WelcomeBiome()
                    end
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
                    name = "Full screen: open the game and stand still, then adjust until the see-through copy covers your character and the road lies flat on the ground. Zooming or tilting the camera changes the fit. In the side window, pitch, focus, distance and field of view set the window's own camera.",
                },
                hideReal = {
                    type = "toggle",
                    order = 3,
                    width = "full",
                    name = "Hide your real character (first-person camera)",
                    desc = "Full screen only. The game does not draw your character in first person, so only the twin shows. Zooms all the way in while the game is open and back out after; the world is then seen from eye height.",
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
                opacity = calibration(
                    60,
                    "opacity",
                    "Road opacity",
                    "Full screen only: how much of the world shows through the road.",
                    0.1,
                    1,
                    0.05
                ),
                brightness = calibration(
                    70,
                    "brightness",
                    "Ground brightness",
                    "How bright the road and grass are by day.",
                    0.2,
                    1,
                    0.05
                ),
                fixedCurve = {
                    type = "toggle",
                    order = 80,
                    name = "Fixed ground curve",
                    desc = "Use the curve below instead of the biome's: how the ground bends down toward the horizon.",
                    get = function()
                        return app.db.profile.overlay.fixedCurve
                    end,
                    set = function(_, value)
                        app.db.profile.overlay.fixedCurve = value
                    end,
                },
                curve = {
                    type = "range",
                    order = 81,
                    name = "Ground curve",
                    desc = "How many yards the ground drops 50 yards ahead. 0 is flat.",
                    min = 0,
                    max = 6,
                    step = 0.05,
                    disabled = function()
                        return not app.db.profile.overlay.fixedCurve
                    end,
                    -- Stored as the drop per yard squared.
                    get = function()
                        return app.db.profile.overlay.curve * 2500
                    end,
                    set = function(_, value)
                        app.db.profile.overlay.curve = value / 2500
                    end,
                },
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
