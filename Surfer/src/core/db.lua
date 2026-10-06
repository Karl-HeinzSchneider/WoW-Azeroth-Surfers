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
    -- "overlay": your character runs on a full-screen road; "window": a model copy in a window.
    view = "overlay",
    -- Full-screen calibration: the follow camera that the road's projection imitates.
    overlay = {
        pitch = 20, -- degrees the camera looks down
        focus = 0.9, -- camera focus height, as a share of the character's height
        distance = 12, -- camera distance in yards, when the client cannot report its zoom
        fov = 55, -- vertical field of view in degrees
        opacity = 0.85,
        cutout = 0.8, -- width of the hole behind the character, as a share of its width
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
