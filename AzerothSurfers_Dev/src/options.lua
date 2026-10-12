---@type string, table
local _, dev = ...
local app = dev.app
local log = app.logger

-- The log levels for the select, quietest first, shown as "Info" for "INFO".
local levelNames, levelOrder = {}, {}
for name in pairs(log.level) do
    levelNames[name] = name:sub(1, 1) .. name:sub(2):lower()
    levelOrder[#levelOrder + 1] = name
end
table.sort(levelOrder, function(a, b)
    return log.level[a] < log.level[b]
end)

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

-- An open game places the scorecard anew at once.
local function placeHud()
    if app.overlay.frame then
        app.overlay:Layout()
    end
end

local function header(order, name)
    return { type = "header", order = order, name = name }
end

local function text(order, name)
    return { type = "description", order = order, fontSize = "medium", name = name .. "\n" }
end

local runs = {
    type = "group",
    order = 1,
    name = "Run overrides",
    args = {
        help = text(
            0,
            "Difficulty and biome overrides for playtesting. Seed and distance settings apply to Custom runs; Play draws a new seed."
        ),
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
        seedHeader = header(10, "Custom game"),
        fixedSeed = {
            type = "toggle",
            order = 11,
            width = "full",
            name = "Fixed seed",
            desc = "Every custom game run (the main menu's Custom) lays out the same track, from the seed below. Off: a new seed every run. Play always draws a new one.",
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
            desc = "The seed every custom game run starts from: a whole number. Checked first: the current run's.",
            hidden = function()
                return app.db.profile.seed == false
            end,
            get = function()
                return tostring(app.db.profile.seed)
            end,
            validate = function(_, value)
                local number = tonumber(value)
                return (number and number == math.floor(number) and number > -math.huge and number < math.huge)
                    or "Enter a finite whole number."
            end,
            set = function(_, value)
                app.overlay:SetSeed(tonumber(value))
            end,
        },
        startAt = {
            type = "input",
            order = 13,
            name = function()
                return "Start at (" .. app.distance.Unit() .. ")"
            end,
            desc = "Distance into the seed every custom game run begins: on empty road up to its next obstacles, the same track the seed lays out from the camp. 0: from the camp, a restart just past the portal. Custom game runs save no best score.",
            get = function()
                return tostring(app.db.profile.startAt or 0)
            end,
            validate = function(_, value)
                local yards = tonumber(value)
                return (yards and yards >= 0 and yards <= app.simulation.MAX_START)
                    or ("Enter a distance from 0 to " .. app.distance.Text(app.simulation.MAX_START) .. ".")
            end,
            set = function(_, value)
                app.overlay:SetStartAt(tonumber(value))
            end,
        },
        endAt = {
            type = "input",
            order = 14,
            name = function()
                return "Ends at (" .. app.distance.Unit() .. ")"
            end,
            desc = "Distance into the seed every custom game run ends, at a last portal as a challenge's run does; past Start at. 0: never.",
            get = function()
                return tostring(app.db.profile.endAt or 0)
            end,
            validate = function(_, value)
                local yards = tonumber(value)
                return (yards and yards >= 0 and yards <= app.simulation.MAX_START)
                    or ("Enter a distance from 0 to " .. app.distance.Text(app.simulation.MAX_START) .. ".")
            end,
            set = function(_, value)
                app.overlay:SetEndAt(tonumber(value))
            end,
        },
    },
}

local rendering = {
    type = "group",
    order = 2,
    name = "Rendering",
    args = {
        drawLevel = {
            type = "range",
            order = 6,
            name = "Base frame level",
            desc = "Draw order within the selected layer. The scene is 2 levels above this base; controls and menus are up to 25 levels above it. Default: 1.",
            min = 1,
            max = 1000,
            step = 1,
            get = function()
                return app.db.profile.drawLevel
            end,
            set = function(_, value)
                app.db.profile.drawLevel = value
                applyMode()
            end,
        },
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
            desc = function()
                return string.format(
                    "How many %s the ground drops %s ahead. 0 is flat.",
                    app.distance.Name(),
                    app.distance.Text(50)
                )
            end,
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
        cameraHeader = header(20, "Camera calibration"),
        pitch = overlaySetting(
            21,
            "pitch",
            "Camera pitch",
            "How far your camera looks down, in degrees. Moves the horizon.",
            -10,
            80,
            1
        ),
        focus = overlaySetting(
            22,
            "focus",
            "Focus height",
            "Where on your character the camera points, as a share of its height. Moves the road up and down.",
            0.2,
            1.5,
            0.01
        ),
        twinHeader = header(30, "Character calibration"),
        twinScale = overlaySetting(
            31,
            "twinScale",
            "Twin size",
            "Size of the twin compared to your real character.",
            0.5,
            1.5,
            0.01
        ),
    },
}

local diagnostics = {
    type = "group",
    order = 3,
    name = "Diagnostics",
    args = {
        logLevel = {
            type = "select",
            order = 34,
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

for i, stat in ipairs(app.overlay.HUD_INFO) do
    if stat.id == "seed" or stat.id == "fps" then
        diagnostics.args["hudInfo_" .. stat.id] = {
            type = "toggle",
            order = 40 + i,
            width = "full",
            name = "Show " .. stat.name .. " on scorecard",
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

app.options:RegisterDebugOptions({
    type = "group",
    order = 90,
    name = "Debug",
    childGroups = "tab",
    args = { runs = runs, rendering = rendering, diagnostics = diagnostics },
})
