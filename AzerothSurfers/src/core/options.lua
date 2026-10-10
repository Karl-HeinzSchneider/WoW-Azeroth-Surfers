---@type string, AzerothSurfers
local appName, app = ...

local log = app.logger
local addon = app.addon

-- The addon's options as one AceConfig table, shown in the game's Settings panel (AddOns tab) and
-- in a standalone window (`/surfers options`), so an option is added here once. One tab per
-- topic: each tab's content scrolls on its own, so nothing runs past the window.
---@class AzerothSurfers.Options : AceModule
local module = {}
app.options = addon:NewModule("Options", module) --[[@as AzerothSurfers.Options]]

-- The standalone window's size: room for the longest tab without scrolling on most screens.
local WIDTH, HEIGHT = 720, 560

-- The log levels for the select, quietest first, shown as "Info" for "INFO".
local levelNames, levelOrder = {}, {}
for name in pairs(log.level) do
    levelNames[name] = name:sub(1, 1) .. name:sub(2):lower()
    levelOrder[#levelOrder + 1] = name
end
table.sort(levelOrder, function(a, b)
    return log.level[a] < log.level[b]
end)

-- A setting of the profile at `key`, a toggle across the whole width; `after(value)` runs once
-- it is set.
local function toggle(order, key, name, desc, after)
    return {
        type = "toggle",
        order = order,
        width = "full",
        name = name,
        desc = desc,
        get = function()
            return app.db.profile[key]
        end,
        set = function(_, value)
            app.db.profile[key] = value
            if after then
                after(value)
            end
        end,
    }
end

-- Settings of `profile.overlay`, a slider and a toggle across the whole width. The road
-- reprojects on its own when a value changes.
local function overlaySetting(order, key, name, desc, min, max, step)
    return {
        type = "range",
        order = order,
        width = "full",
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

local function overlayToggle(order, key, name, desc)
    return {
        type = "toggle",
        order = order,
        width = "full",
        name = name,
        desc = desc,
        get = function()
            return app.db.profile.overlay[key]
        end,
        set = function(_, value)
            app.db.profile.overlay[key] = value
        end,
    }
end

-- An open game takes a new mode or frame setting on at once.
local function applyMode()
    if app.overlay.frame then
        app.overlay:ApplyMode()
    end
end

local function header(order, name)
    return { type = "header", order = order, name = name }
end

local function text(order, name)
    return { type = "description", order = order, fontSize = "medium", name = name .. "\n" }
end

-- The Keys tab: a row per action of keys.lua, its name, then its two keys and its two gamepad
-- buttons. Built in OnInitialize: keys.lua loads after this file.
local SLOT_NAMES = { "Key 1", "Key 2", "Gamepad 1", "Gamepad 2" }
local CONTEXT_NAMES = { run = "Running", menu = "Menus", both = "Running and menus" }
-- Widths in AceConfig's units (170 pixels): the five of a row fit the Settings panel.
local NAME_WIDTH, KEY_WIDTH = 0.8, 0.68
local GOLD = "|cffffd100%s|r"

-- The gamepad slot's button: AceGUI's own key binding button that, while it waits for a key,
-- also takes a push of a stick (the sticks send no button presses: overlay.StickButton).
local GAMEPAD_KEY = "AzerothSurfersGamepadKey"
local function registerGamepadKey()
    local AceGUI = LibStub("AceGUI-3.0")
    if AceGUI.WidgetRegistry[GAMEPAD_KEY] then
        return
    end
    AceGUI:RegisterWidgetType(GAMEPAD_KEY, function()
        local widget = AceGUI.WidgetRegistry.Keybinding()
        widget.type = GAMEPAD_KEY
        local button = widget.button
        if not button.EnableGamePadStick then
            return widget
        end
        local press = button:GetScript("OnGamePadButtonDown")
        -- The sticks only while it waits: its own scripts start and end the waiting.
        local function listen()
            button:EnableGamePadStick(widget.waitingForKey == true)
        end
        for _, script in ipairs({ "OnClick", "OnKeyDown", "OnGamePadButtonDown", "OnMouseDown", "OnMouseWheel" }) do
            button:HookScript(script, listen)
        end
        button:SetScript("OnGamePadStick", function(frame, stick, x, y)
            local name = widget.waitingForKey and app.overlay.StickButton(stick, x, y)
            if name then
                press(frame, name)
                listen()
            end
        end)
        local acquire = widget.OnAcquire
        widget.OnAcquire = function(self)
            acquire(self)
            button:EnableGamePadStick(false)
        end
        return widget
    end, 1)
end

local function keyButton(order, action, slot)
    local overlay = app.overlay
    return {
        type = "keybinding",
        dialogControl = app.overlay.GAMEPAD_SLOTS[slot] and GAMEPAD_KEY or nil,
        order = order,
        width = KEY_WIDTH,
        name = "",
        desc = SLOT_NAMES[slot] .. " for " .. action.name .. ". Escape leaves it unbound.",
        get = function()
            return overlay.ActionKey(action.id, slot) or ""
        end,
        -- Within a run, or within the menus, a key does one thing.
        validate = function(_, value)
            if value == "" then
                return true
            end
            for _, other in ipairs(overlay.ACTIONS) do
                if app.overlay.SameContext(other.context, action.context) then
                    for s = 1, overlay.KEY_SLOTS do
                        local same = other ~= action or s ~= slot
                        if same and overlay.ActionKey(other.id, s) == value then
                            return value .. " is already " .. other.name .. "."
                        end
                    end
                end
            end
            return true
        end,
        set = function(_, value)
            local saved = app.db.profile.keys
            if type(saved[action.id]) ~= "table" then
                saved[action.id] = {}
            end
            saved[action.id][slot] = value ~= "" and value or false
            overlay.legendState = nil
        end,
    }
end

local function keysTab()
    local args = {
        help = text(
            1,
            "The game's keys work only while it is open, whatever they are bound to in WoW; with Capture movement keys on, WoW does not get them. Two keys and two gamepad buttons for each: by default WASD, the arrow keys, and the gamepad with its left stick and D-pad mirroring each other. A key may do one thing in a run and another in the menus."
        ),
        reset = {
            type = "execute",
            order = 2,
            name = "Reset all keys",
            desc = "Back to WASD, the arrow keys and the gamepad's defaults.",
            confirm = true,
            confirmText = "Reset every key to its default?",
            func = function()
                wipe(app.db.profile.keys)
                app.overlay.legendState = nil
            end,
        },
    }
    local order, context = 10, nil
    for _, action in ipairs(app.overlay.ACTIONS) do
        if action.context ~= context then
            context = action.context
            args["header_" .. context] = header(order, CONTEXT_NAMES[context])
            args["columns_" .. context] = { type = "description", order = order + 1, width = NAME_WIDTH, name = "" }
            for slot, name in ipairs(SLOT_NAMES) do
                args["column_" .. context .. slot] = {
                    type = "description",
                    order = order + 1 + slot / 10,
                    width = KEY_WIDTH,
                    name = GOLD:format(name),
                }
            end
            order = order + 2
        end
        args["name_" .. action.id] = {
            type = "description",
            order = order,
            width = NAME_WIDTH,
            fontSize = "medium",
            name = action.name,
        }
        for slot = 1, app.overlay.KEY_SLOTS do
            args["key_" .. action.id .. slot] = keyButton(order + slot / 10, action, slot)
        end
        order = order + 1
    end
    return { type = "group", order = 4, name = "Keys", args = args }
end

local game = {
    type = "group",
    order = 1,
    name = "Game",
    args = {
        difficulty = {
            type = "select",
            order = 1,
            width = "double",
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
        biome = {
            type = "select",
            order = 2,
            width = "double",
            name = "Biome",
            desc = "How the game looks: its ground, obstacles and coins. Auto goes from zone to zone as you run, starter zones first, the way set by the seed; each portal raises the score multiplier.",
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
        seedHeader = header(10, "Seed"),
        fixedSeed = {
            type = "toggle",
            order = 11,
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
            order = 12,
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
        controlsHeader = header(20, "Controls"),
        capture = toggle(
            21,
            "capture",
            "Capture movement keys",
            "While the game is open it keeps the game's keys and your move, strafe, turn and jump keys from WoW, on every screen and menu: your character stays where it is and the runner runs on its own. Steering with the mouse buttons still moves your character.",
            applyMode
        ),
        legend = toggle(22, "legend", "Show hotkeys", "List the game's keys beside the road (set on the Keys tab)."),
        otherHeader = header(30, "Other"),
        minimap = {
            type = "toggle",
            order = 31,
            width = "full",
            name = "Show minimap button",
            desc = "The minimap button opens the game.",
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
            order = 32,
            name = "Log level",
            desc = "How much " .. app.TITLE .. " writes to the chat window. Same as /surfers loglevel <level>.",
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

local display = {
    type = "group",
    order = 2,
    name = "Display",
    args = {
        mode = {
            type = "select",
            order = 1,
            width = "double",
            name = "Mode",
            desc = "Full screen: the road lies in the world around your character. Side window: the game runs in a window of its own, out of the way; drag it by its title and size it from its corner.",
            values = { full = "Full screen", side = "Side window" },
            sorting = { "full", "side" },
            get = function()
                return app.db.profile.mode
            end,
            set = function(_, value)
                app.db.profile.mode = value
                applyMode()
            end,
        },
        frameFull = {
            type = "toggle",
            order = 2,
            width = "full",
            name = "Window frame in full screen",
            desc = "A border, title bar and close button around the screen. Without it, the game looks like part of the world.",
            get = function()
                return app.db.profile.frame.full
            end,
            set = function(_, value)
                app.db.profile.frame.full = value
                applyMode()
            end,
        },
        frameSide = {
            type = "toggle",
            order = 3,
            width = "full",
            name = "Window frame in the side window",
            desc = "A border, title bar and close button around the side window. Without it, the window can't be dragged or sized.",
            get = function()
                return app.db.profile.frame.side
            end,
            set = function(_, value)
                app.db.profile.frame.side = value
                applyMode()
            end,
        },
        resetSide = {
            type = "execute",
            order = 4,
            name = "Reset side window",
            desc = "Put the side window back at the right edge of the screen, at its first size.",
            func = function()
                local saved, default = app.db.profile.side, app.dbDefaults.profile.side
                for key, value in pairs(default) do
                    saved[key] = value
                end
                applyMode()
            end,
        },
        lookHeader = header(10, "Road and ground"),
        opacity = overlaySetting(
            11,
            "opacity",
            "Road opacity",
            "Full screen only: how much of the world shows through the road.",
            0.1,
            1,
            0.05
        ),
        brightness = overlaySetting(
            12,
            "brightness",
            "Ground brightness",
            "How bright the road and grass are by day.",
            0.2,
            1,
            0.05
        ),
        dayNight = overlayToggle(
            13,
            "dayNight",
            "Darker at night",
            "The ground, your twin and the coins follow the game's clock: dimmed and moonlit blue at night, brightening at dawn (5 to 7) and darkening at dusk (19 to 21)."
        ),
        fixedCurve = overlayToggle(
            14,
            "fixedCurve",
            "Fixed ground curve",
            "Use the curve below instead of the biome's: how the ground bends down toward the horizon."
        ),
        curve = {
            type = "range",
            order = 15,
            width = "full",
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
    },
}

local sound = {
    type = "group",
    order = 3,
    name = "Sound",
    args = {
        coinSound = toggle(1, "coinSound", "Coin sound", "Play the money loot sound when you collect a coin."),
        footstepSound = toggle(
            4,
            "footstepSound",
            "Footsteps",
            "Play surface sounds while running, jumping, landing and rolling."
        ),
        enemySound = toggle(
            2,
            "enemySound",
            "Creature sounds",
            "Play an enemy's attack sound when you run past it, and what a creature crossing the road says."
        ),
        portalSound = toggle(
            3,
            "portalSound",
            "Portal sounds",
            "Play a teleport sound when you go through a portal between zones."
        ),
        music = toggle(
            4,
            "music",
            "Title music",
            "Play the classic login theme on the title screen and in the main menu (with the game's music on).",
            function(value)
                if app.overlay.frame then
                    app.overlay:PlayTitleMusic(value and app.overlay.screen ~= nil and app.overlay.screen ~= "start")
                end
            end
        ),
    },
}

local calibration = {
    type = "group",
    order = 5,
    name = "Calibration",
    args = {
        help = text(
            1,
            "Full screen: open the game and stand still, then adjust until the see-through copy covers your character and the road lies flat on the ground. Zooming or tilting the camera changes the fit. In the side window, pitch, focus, distance and field of view set the window's own camera."
        ),
        hideReal = {
            type = "toggle",
            order = 2,
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
        cameraHeader = header(10, "Camera"),
        pitch = overlaySetting(
            11,
            "pitch",
            "Camera pitch",
            "How far your camera looks down, in degrees. Moves the horizon.",
            -10,
            80,
            1
        ),
        focus = overlaySetting(
            12,
            "focus",
            "Focus height",
            "Where on your character the camera points, as a share of its height. Moves the road up and down.",
            0.2,
            1.5,
            0.01
        ),
        distance = overlaySetting(
            13,
            "distance",
            "Camera distance",
            "Your camera zoom in yards. Only used when the client cannot report the zoom itself.",
            1,
            40,
            0.5
        ),
        fov = overlaySetting(
            14,
            "fov",
            "Field of view",
            "The game's vertical field of view in degrees. Changes how wide the road looks.",
            30,
            100,
            1
        ),
        twinHeader = header(20, "Twin"),
        twinScale = overlaySetting(
            21,
            "twinScale",
            "Twin size",
            "Size of the twin compared to your real character.",
            0.5,
            1.5,
            0.01
        ),
    },
}

local options = {
    type = "group",
    name = app.TITLE,
    childGroups = "tab",
    args = {
        game = game,
        display = display,
        sound = sound,
        calibration = calibration,
    },
}

function module:OnInitialize()
    registerGamepadKey()
    options.args.keys = keysTab()
    options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(app.db)
    options.args.profiles.order = 100

    LibStub("AceConfig-3.0"):RegisterOptionsTable(appName, options)
    local dialog = LibStub("AceConfigDialog-3.0")
    -- Our panel in the game's Settings, to tell when it shows.
    self.panel = dialog:AddToBlizOptions(appName, app.TITLE)
    dialog:SetDefaultSize(appName, WIDTH, HEIGHT)
end

-- Whether the options show, in their own window or in the game's Settings: the game then leaves
-- every key alone (rebinding one must not steer it).
function module:IsOpen()
    if LibStub("AceConfigDialog-3.0").OpenFrames[appName] then
        return true
    end
    return self.panel ~= nil and self.panel:IsVisible()
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
