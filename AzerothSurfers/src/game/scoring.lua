---@type string, AzerothSurfers
local _, app = ...
-- How a run scores, as data. DEFAULTS are the rules of every run; a game mode passes its own
-- `scoring` to simulation.New, any of DEFAULTS' fields at any depth, and the run plays by those
-- over the defaults (`s.scoring`, Rules). Game code reads a run's rules, never a constant of its
-- own, so a mode may change anything here.
local scoring = {}
app.scoring = scoring

scoring.DEFAULTS = {
    -- Points a yard run scores, at multiplier 1.
    yardPoints = 1,
    -- Points a coin scores, at multiplier 1.
    coinPoints = 25,
    -- A streak: coins collected one right after another. A coin missed beside it (a parallel
    -- row) does not break it, running on too far without one does:
    --   gap      yards from one collected coin to the next that keep a streak (6: one empty
    --            spot in a row)
    --   seconds  or that long at the speed of the moment, if further (a change of lanes or two)
    --   from     the streak's length from which every coin scores `points` more, at the
    --            multiplier
    -- AzerothSurfers_Dev's /surfers streak changes them while playing.
    streak = { gap = 7, seconds = 0.35, from = 7, points = 25 },
    -- The multiplier scales what is earned at its moment:
    --   start    what a run starts at
    --   perGate  what each gate into the next zone adds (simulation.lua's passGates)
    --   most     the highest it goes
    multiplier = { start = 1, perGate = 1, most = math.huge },
    -- The score is everything earned times its difficulty's factor (by difficulty id, 1 for one
    -- not listed): a harder run's yards and coins are worth more.
    difficulty = { easy = 0.75, normal = 1, hard = 1.25, expert = 1.5 },
}

local function merge(into, from)
    for key, value in pairs(from) do
        if type(value) == "table" and type(into[key]) == "table" then
            merge(into[key], value)
        elseif type(value) == "table" then
            into[key] = merge({}, value)
        else
            into[key] = value
        end
    end
    return into
end

-- A run's own rules: a copy of DEFAULTS with `overrides` (nil: none) over it, field by field. A
-- run may change its copy without changing any other's.
function scoring.Rules(overrides)
    local rules = merge({}, scoring.DEFAULTS)
    return overrides and merge(rules, overrides) or rules
end

-- What `rules` scale a run at `difficulty` (simulation.lua's DIFFICULTIES entry) by.
function scoring.Factor(rules, difficulty)
    return rules.difficulty[difficulty.id] or 1
end
