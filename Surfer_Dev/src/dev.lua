---@type string, table
local _, dev = ...
-- Surfer_Dev: tools for developing Surfer and its biomes, never released. Surfer hands its
-- private table over through its Ace addon object; the tools add `/surfer` subcommands.
---@type Surfer
local app = LibStub("AceAddon-3.0"):GetAddon("Surfer"):DevApp()
dev.app = app
dev.log = app.logger

-- Adds `/surfer <name> ...`: `run(rest)` gets the text after the name; `usage` lists it in
-- `/surfer help`.
function dev.Command(name, usage, run)
    app.devCommands[name] = { usage = usage, run = run }
end

-- The game's view while it is open; nothing, with a hint, while it is closed.
function dev.Overlay()
    local overlay = app.overlay
    if not overlay.frame or not overlay.frame:IsShown() then
        dev.log:chat("Open the game first (/surfer).")
        return nil
    end
    return overlay
end

-- The words of `text`, numbers as numbers.
function dev.Words(text)
    local words = {}
    for word in (text or ""):gmatch("%S+") do
        words[#words + 1] = tonumber(word) or word:lower()
    end
    return words
end

-- Animations worth checking on a creature, by id (the client's AnimationData).
dev.ANIMATIONS = {
    { 0, "stand" },
    { 16, "attack unarmed" },
    { 17, "attack one-handed" },
    { 18, "attack two-handed" },
    { 19, "attack two-handed polearm" },
    { 25, "ready unarmed" },
    { 26, "ready one-handed" },
    { 4, "walk" },
    { 5, "run" },
    { 1, "death" },
}
