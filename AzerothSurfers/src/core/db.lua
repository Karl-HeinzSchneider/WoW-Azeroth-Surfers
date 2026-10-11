---@type string, AzerothSurfers
local _, app = ...

---@class AzerothSurfers.DB.Profile
local profile = {
    logLevel = "INFO",
    minimap = {
        hide = false,
        -- LibDBIcon puts every undragged button at 225 degrees; start elsewhere.
        minimapPos = 200,
    },
    coinSound = true,
    footstepSound = false,
    enemySound = true, -- enemies passed and wildlife
    portalSound = true,
    music = true, -- the title music on the title screen and in the menu
    challengeReminder = true, -- a chat line at login: each challenge new, beaten or not finished
    legend = true,
    distanceUnit = "client", -- "client", "yards" or "meters"; WoW's localized units, same numbers
    -- A biome id, or "auto": zone to zone as the run goes.
    biome = "auto",
    -- "full": the game covers the screen around the real character; "side": a window of its own.
    mode = "full",
    drawStrata = "HIGH", -- the game's draw layer in both display modes
    drawLevel = 1, -- base frame level; scene and controls retain their relative offsets
    -- The game takes the movement keys from WoW: the character stays put, the runner runs alone.
    capture = true,
    -- The game's keys by action (keys.lua's ACTIONS): { key 1, key 2, gamepad button }, false
    -- for unbound; where an action or slot is not set, its default. Set on the Keys tab.
    keys = {},
    difficulty = "normal", -- an id of simulation.DIFFICULTIES
    -- The custom game's settings (the main menu's Custom, messages.lua's CUSTOM); Play ignores
    -- them.
    seed = false, -- a fixed seed for every custom run, or false: a new one each run
    startAt = 0, -- yards into its seed every custom run begins (simulation.Skip); 0: from the camp
    endAt = 0, -- yards into its seed every custom run ends, at a last portal; 0: never
    customScoring = {}, -- its scoring rules where they differ from scoring.lua's DEFAULTS
    frame = { full = false, side = true }, -- the window frame in each mode
    -- The scorecard: "menu" (full screen: right of the pause and end menus, its top on theirs;
    -- the side window: top right), "topright", "top" or "topleft"; x and y move it that many
    -- pixels (right and up).
    hud = { position = "menu", x = 0, y = 0 },
    hudCoinShare = true, -- the share of coins collected beside the scorecard's coin counter
    -- The scorecard's extra info (hud.lua's HUD_INFO), each by its id: true to show it.
    hudInfo = {
        seed = false,
        time = false,
        fps = false,
        speed = false,
        biome = false,
        portal = false,
        coinRate = false,
        bestStreak = false,
        best = false,
    },
    side = { point = "RIGHT", relative = "RIGHT", x = -40, y = 0, width = 400, height = 480 },
    -- The game's independent follow camera and the twin.
    overlay = {
        twinScale = 1,
        pitch = 20, -- degrees the camera looks down
        focus = 0.9, -- camera focus height, as a share of the character's height
        distance = 12, -- game's camera distance; mouse wheel adjusts it independently of WoW
        fov = 55, -- vertical field of view in degrees
        opacity = 1,
        brightness = 0.75, -- the ground's light by day
        dayNight = true, -- the ground darkens at night, by the game's clock
        fixedCurve = false, -- `curve` instead of the biome's ground curve
        curve = 0.0005, -- the ground's drop: this times the distance ahead squared, in yards
    },
}

---@class AzerothSurfers.DB.Char
local char = {}

---@class AzerothSurfers.DB.Global
local global = {
    dbVersion = 1,
    bestScore = 0,
    -- The main menu has shown How to play (screens.lua) once, on its first opening.
    tipsShown = false,
    -- The Stats page's numbers (stats.lua): runs played and what they add up to, the longest
    -- coin streak, and Play's best of each difficulty by its id ({ score, distance, coins }).
    stats = { runs = 0, yards = 0, coins = 0, time = 0, portals = 0, longestStreak = 0, best = {} },
    -- The best run of each challenge (challenges.lua's Best), by its period's key.
    challenges = {},
    -- The bests the guild and the group shared (leaderboard.lua), by the period's key, then by
    -- the player's name; only the current periods'.
    leaderboard = {},
}

---@class AzerothSurfers.DBDefaults : AceDB.Schema
app.dbDefaults = {
    profile = profile,
    char = char,
    global = global,
}
