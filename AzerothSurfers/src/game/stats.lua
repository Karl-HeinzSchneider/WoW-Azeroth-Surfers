---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- The Stats page's numbers (screens.lua), kept in `global.stats`: every run the player played
-- themselves (Play, a challenge, a custom game; never auto mode) adds its yards, coins, time and
-- portals, and counts once it has run a yard past its `start`. Records only from runs that keep a
-- best: the longest coin streak from Play's and the challenges', the best per difficulty from
-- Play's alone (a challenge's best is its own, challenges.lua).
local stats = {}
app.stats = stats

-- `global.stats` as db.lua's defaults have it, filled in where it lacks a field.
local DEFAULTS = { runs = 0, yards = 0, coins = 0, time = 0, portals = 0, longestStreak = 0 }
function stats.Saved()
    local global = app.db.global
    local saved = global.stats or {}
    global.stats = saved
    for k, v in pairs(DEFAULTS) do
        saved[k] = saved[k] or v
    end
    saved.best = saved.best or {}
    return saved
end

-- The zones' portals the runner went through past `start`, as the multiplier counts them: not
-- the lobby's, nor a challenge's last one.
function stats.Portals(s)
    local count = 0
    for i = 1, s.gatesPassed do
        local at = s.gates[i]
        if at > s.start and at ~= s.finish then
            count = count + 1
        end
    end
    return count
end

-- Adds what `s` ran since the last call for it (`s.recorded`), so it may be called whenever
-- the run is saved (controls.lua's SaveBest: at its end, a restart, the game closed while it
-- is paused) and counts each yard once.
function stats.Record(s)
    if s.piloted or sim.Run(s) <= 0 then
        return
    end
    local saved, done = stats.Saved(), s.recorded
    if not done then
        done = { yards = 0, coins = 0, time = 0, portals = 0 }
        s.recorded = done
        saved.runs = saved.runs + 1
    end
    local now = { yards = math.floor(sim.Run(s)), coins = s.coins, time = s.time, portals = stats.Portals(s) }
    for k, v in pairs(now) do
        saved[k] = saved[k] + v - done[k]
        done[k] = v
    end
    if s.custom or s.practice then
        return
    end
    saved.longestStreak = math.max(saved.longestStreak, s.bestStreak)
    if s.challenge then
        return
    end
    local id, score = s.difficulty.id, sim.Score(s)
    local best = saved.best[id]
    if not best or score > best.score then
        saved.best[id] = { score = score, distance = now.yards, coins = s.coins }
    end
end

-- Seconds as hours and minutes, or minutes and seconds under an hour.
function stats.TimeText(seconds)
    seconds = math.floor(seconds)
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm %ds", minutes, seconds % 60)
end
