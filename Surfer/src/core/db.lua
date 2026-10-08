---@type string, Surfer
local _, app = ...

---@class Surfer.DB.Profile
local profile = {
    logLevel = "INFO",
    minimap = {
        hide = false,
        -- LibDBIcon puts every undragged button at 225 degrees; start elsewhere.
        minimapPos = 200,
    },
    coinSound = true,
    enemySound = true, -- enemies passed and wildlife
    portalSound = true,
    legend = true,
    -- A biome id, or "auto": zone to zone as the run goes.
    biome = "auto",
    -- "full": the game covers the screen around the real character; "side": a window of its own.
    mode = "full",
    -- The game takes the movement keys from WoW: the character stays put, the runner runs alone.
    capture = true,
    difficulty = "normal", -- an id of simulation.DIFFICULTIES
    seed = false, -- a fixed seed for every run, or false: a new one each run
    frame = { full = false, side = true }, -- the window frame in each mode
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

---@class Surfer.DB.Char
local char = {}

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
