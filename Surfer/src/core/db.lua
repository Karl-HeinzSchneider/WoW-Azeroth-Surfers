---@type string, Surfer
local _, app = ...

-- AceDB-3.0 defaults. Missing keys in the SavedVariables fall back to these values,
-- and values equal to the default are not written to disk.

-- User settings, switchable per character via AceDBOptions.
---@class Surfer.DB.Profile
local profile = {
    logLevel = "INFO",
    minimap = {
        hide = false,
        -- Degrees around the minimap (0 = east, counter-clockwise), written by LibDBIcon on drag.
        -- LibDBIcon puts every button at 225 when it has none, so buttons nobody has dragged yet
        -- all stack on one spot; start somewhere else instead.
        minimapPos = 200,
    },
    coinSound = true,
    biome = "elwynn", -- how the game looks: a file in src/biomes/
    -- "full": the game covers the screen around the real character; "side": a window of its own.
    mode = "full",
    -- The game takes the movement keys from WoW: the character stays put, the runner runs alone.
    capture = true,
    -- The window frame (border, title bar, close button) in each mode.
    frame = { full = false, side = true },
    -- The side window's place and size, set by dragging and sizing it.
    side = { point = "RIGHT", relative = "RIGHT", x = -40, y = 0, width = 400, height = 480 },
    -- Calibration: the follow camera that the road's projection imitates, and the twin.
    overlay = {
        hideReal = false, -- first-person camera while the view is open, so only the twin shows
        twinScale = 1,
        pitch = 20, -- degrees the camera looks down
        focus = 0.9, -- camera focus height, as a share of the character's height
        distance = 12, -- camera distance in yards, when the client cannot report its zoom
        fov = 55, -- vertical field of view in degrees
        opacity = 1,
        brightness = 0.75, -- the ground's light by day
        dayNight = true, -- the ground darkens at night, by the game's clock
        fixedCurve = false, -- `curve` instead of the biome's ground curve
        curve = 0.0005, -- the ground's drop: this times the distance ahead squared, in yards
    },
}

-- Data tied to one character.
---@class Surfer.DB.Char
local char = {}

-- Account-wide data shared by every character.
---@class Surfer.DB.Global
local global = {
    dbVersion = 1,
    bestScore = 0,
}

---@class Surfer.DBDefaults : AceDB.Schema
app.dbDefaults = {
    profile = profile,
    char = char,
    global = global,
}
