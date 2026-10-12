---@type string, AzerothSurfers
local appName, app = ...

local addon = app.addon

-- The addon's options as one AceConfig table, shown in the game's Settings panel (AddOns tab) and
-- in a standalone window (`/surfers options`), so an option is added here once. One tab per
-- topic: each tab's content scrolls on its own, so nothing runs past the window.
---@class AzerothSurfers.Options : AceModule
local module = {}
app.options = addon:NewModule("Options", module) --[[@as AzerothSurfers.Options]]

-- The standalone window's size: room for the longest tab without scrolling on most screens.
local WIDTH, HEIGHT = 720, 560

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

-- Settings of `profile.overlay`: compact sliders and full-width toggles. The road
-- reprojects on its own when a value changes.
local function overlaySetting(order, key, name, desc, min, max, step)
    return {
        type = "range",
        order = order,
        width = 1.25,
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

-- An open game places the scorecard anew at once.
local function placeHud()
    if app.overlay.frame then
        app.overlay:Layout()
    end
end

-- A pixel offset of `profile.hud`.
local function hudOffset(order, key, name, desc)
    return {
        type = "range",
        order = order,
        name = name,
        desc = desc,
        min = -1000,
        max = 1000,
        softMin = -400,
        softMax = 400,
        step = 1,
        get = function()
            return app.db.profile.hud[key]
        end,
        set = function(_, value)
            app.db.profile.hud[key] = value
            placeHud()
        end,
    }
end

local function header(order, name)
    return { type = "header", order = order, name = name }
end

local function text(order, name)
    return { type = "description", order = order, fontSize = "medium", name = name .. "\n" }
end

-- The Keybindings tab: a row per action of keys.lua, its name, then its two keys and its two gamepad
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
    return { type = "group", order = 4, name = "Keybindings", args = args }
end

local general = {
    type = "group",
    order = 1,
    name = "General",
    args = {
        capture = toggle(
            21,
            "capture",
            "Capture movement keys",
            "While the game is open it keeps the game's keys and your move, strafe, turn and jump keys from WoW, on every screen and menu: your character stays where it is and the runner runs on its own. Steering with the mouse buttons still moves your character.",
            applyMode
        ),
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
        challengeReminder = toggle(
            32,
            "challengeReminder",
            "Challenge reminder at login",
            "At login, one chat line says whether today's daily, this week's and this month's challenge are new, beaten or not finished yet."
        ),
        sharing = toggle(
            33,
            "sharing",
            "Enable sharing",
            "Show Share on run results and exchange challenge scores with your guild and group leaderboard. Turn off to remove Share and stop sending and receiving sharing messages."
        ),
        distanceUnit = {
            type = "select",
            order = 34,
            width = 0.9,
            name = "Distance units",
            desc = "Use the WoW client's spell-range unit, yards, or meters for distances and speed. Like WoW, this changes the unit label while keeping the same numbers.",
            values = { client = "Same as client", yards = "Yards (yd)", meters = "Meters (m)" },
            sorting = { "client", "yards", "meters" },
            get = function()
                return app.db.profile.distanceUnit
            end,
            set = function(_, value)
                app.db.profile.distanceUnit = value
                app.options:Refresh()
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
            width = 0.85,
            name = "Display mode",
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
            disabled = function()
                return app.db.profile.mode ~= "full"
            end,
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
            disabled = function()
                return app.db.profile.mode ~= "side"
            end,
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
        drawStrata = {
            type = "select",
            order = 5,
            width = 0.85,
            name = "Window priority",
            desc = "Choose whether the game appears above or below other WoW windows. Higher priorities draw on top.",
            values = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High" },
            sorting = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" },
            get = function()
                return app.db.profile.drawStrata
            end,
            set = function(_, value)
                app.db.profile.drawStrata = value
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
        cameraHeader = header(20, "Camera"),
        cameraHelp = text(
            21,
            "Scroll the mouse wheel over the game to zoom. These settings affect only the game camera."
        ),
        distance = overlaySetting(22, "distance", "Camera distance", function()
            return "The game's zoom in "
                .. app.distance.Name()
                .. ", also adjusted with the mouse wheel. 2 is a close shoulder view; 12 is the default; 24 is a wide overview."
        end, 2, 24, 0.5),
        fov = overlaySetting(
            23,
            "fov",
            "Field of view",
            "The game's vertical field of view in degrees. Changes how wide the road looks.",
            30,
            100,
            1
        ),
    },
}

display.args.opacity.disabled = function()
    return app.db.profile.mode ~= "full"
end

local hud = {
    type = "group",
    order = 3,
    name = "HUD",
    args = {
        hudPosition = {
            type = "select",
            order = 21,
            width = 0.95,
            name = "Position",
            desc = "Where the score sits. Beside the menu: right of the pause menu, on its top line, in full screen; top right in the side window.",
            values = { menu = "Beside the menu", topright = "Top right", top = "Top centre", topleft = "Top left" },
            sorting = { "menu", "topright", "top", "topleft" },
            get = function()
                return app.db.profile.hud.position
            end,
            set = function(_, value)
                app.db.profile.hud.position = value
                placeHud()
            end,
        },
        hudX = hudOffset(22, "x", "Move right", "Pixels to move the score right of its position (left when negative)."),
        hudY = hudOffset(23, "y", "Move up", "Pixels to move the score up from its position (down when negative)."),
        hudReset = {
            type = "execute",
            order = 24,
            name = "Reset position",
            desc = "Put the score back beside the menu, unmoved.",
            func = function()
                local saved, default = app.db.profile.hud, app.dbDefaults.profile.hud
                for key, value in pairs(default) do
                    saved[key] = value
                end
                placeHud()
            end,
        },
        hudCoinShare = toggle(
            25,
            "hudCoinShare",
            "Coin percentage beside counter",
            "Show the share of the coins that came past that you collected beside the coin counter, as in 156 (60%)."
        ),
        hintsHeader = header(45, "Hotkey hints"),
        legend = toggle(
            46,
            "legend",
            "Show hotkeys",
            "List the game's keys beside the road (set under the Keybindings tab)."
        ),
        inputHudHeader = header(50, "Input window"),
        inputHud = {
            type = "select",
            order = 51,
            width = 0.9,
            name = "Show pressed keys",
            desc = "Show a draggable input window during gameplay, useful for streaming or seeing your inputs. Simplified: arrows, P and R without captions, in a compact window. Normal: bound keys with action captions. Hidden in menus and the lobby.",
            values = { none = "Off", simplified = "Simplified", normal = "Normal" },
            sorting = { "none", "simplified", "normal" },
            get = function()
                if not app.db.profile.inputHud then
                    return "none"
                end
                return app.db.profile.inputHudSimplified and "simplified" or "normal"
            end,
            set = function(_, value)
                app.db.profile.inputHud = value ~= "none"
                app.db.profile.inputHudSimplified = value == "simplified"
                app.overlay:RefreshInputHud()
            end,
        },
        inputHudReset = {
            type = "execute",
            order = 52,
            name = "Reset input window position",
            disabled = function()
                return not app.db.profile.inputHud
            end,
            func = function()
                local position = app.db.profile.mode == "side" and "inputHudSidePosition" or "inputHudPosition"
                local saved = app.db.profile[position]
                for key, value in pairs(app.dbDefaults.profile[position]) do
                    saved[key] = value
                end
                app.overlay:RefreshInputHud()
            end,
        },
    },
}

local sound = {
    type = "group",
    order = 5,
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
            "Play a teleport sound when you go through a portal between zones, and a fanfare at a challenge's last portal."
        ),
        music = toggle(
            5,
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

local options = {
    type = "group",
    name = app.TITLE,
    childGroups = "tab",
    args = {
        general = general,
        display = display,
        sound = sound,
        hud = hud,
    },
}

-- The scorecard's extra info under its position: a toggle per row of hud.lua's HUD_INFO. Built
-- in OnInitialize: hud.lua loads after this file.
local function addHudInfo(args)
    args.hudInfoHeader = header(30, "Extra information")
    args.hudInfoHelp = text(31, "Choose the details shown below your score.")
    for i, stat in ipairs(app.overlay.HUD_INFO) do
        args["hudInfo_" .. stat.id] = {
            type = "toggle",
            order = 31 + i,
            name = stat.name,
            desc = stat.desc,
            get = function()
                return app.db.profile.hudInfo[stat.id]
            end,
            set = function(_, value)
                app.db.profile.hudInfo[stat.id] = value
                placeHud()
            end,
        }
    end
end

-- The development addon supplies its own settings; released builds have no Debug tab.
function module:RegisterDebugOptions(group)
    options.args.debug = group
    self:Refresh()
end

function module:OnInitialize()
    registerGamepadKey()
    addHudInfo(hud.args)
    options.args.keybindings = keysTab()
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
