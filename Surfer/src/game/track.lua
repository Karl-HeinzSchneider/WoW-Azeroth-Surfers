---@type string, Surfer
local _, app = ...
local random = app.random
local game = app.simulation
-- The track ahead: a stream of patterns (src/patterns/, listed in patterns.xml), each a weighted
-- roll among those the difficulty allows at its distance, followed by free road measured in
-- seconds at the speed of the moment. Everything draws from the run's generator.
--
-- Spacings that depend on reaction time follow the speed (`s.speed`, `JumpLength`). The rules
-- every pattern keeps (tests/simulation.lua checks them, and that a search gets through at every
-- difficulty's slowest and fastest speed):
-- * boxes from `at` on, coins leading in at most LEAD_IN yards before it; it returns its
--   length, how far past `at` it reaches (no box starts beyond it), and the next pattern
--   starts past that;
-- * at every point one lane can be run, jumped or climbed through;
-- * coins COIN_SPACING apart in a lane, never inside a box, on a platform only over its top.
local track = { list = {}, byName = {}, choices = {} }
app.track = track

track.COIN_SPACING = 3
track.LEAD_IN = 8
-- At least LEAD_IN, so the next pattern's coins never reach back into the previous one.
local MIN_GAP = 10

-- A box with a seed of its own for its looks.
function track.Add(s, kind, lane, at, length, layer, layers, ramp)
    local o = game.Box(kind, lane, at, length, layer, layers, ramp)
    o.seed = s.random(random.MAX)
    s.objects[#s.objects + 1] = o
    return o
end
local add, SPACING = track.Add, track.COIN_SPACING

-- `count` coins from `at` (their middles).
function track.Coins(s, lane, at, count, layer)
    for i = 0, count - 1 do
        add(s, "coin", lane, at + i * SPACING - 0.16, 0.32, layer, 1)
    end
end

-- How many coins fit in a row from `from` to `to`, at most `most`.
function track.Fit(from, to, most)
    return math.max(0, math.min(most, math.floor((to - from) / SPACING) + 1))
end

-- Layers over the floor: only a jump collects them.
local ARC = { 3, 4, 5, 5, 4, 3 }
-- Centred on `middle`, over a floor `layer` layers up (0 when nil); 7.5 yards to each side.
function track.Arc(s, lane, middle, layer)
    for i, up in ipairs(ARC) do
        add(s, "coin", lane, middle + (i - 3.5) * SPACING - 0.16, 0.32, (layer or 0) + up, 1)
    end
end

-- Yards a jump carries the runner at the speed of the moment.
function track.JumpLength(s)
    return s.speed * game.JUMP_TIME
end

-- Yards past a takeoff from a floor `layer` layers up (0 when nil) by which the runner is down
-- on the road again, with room to spare (a layer's fall adds under 4 yards at any speed). A
-- pattern ending in a jump reaches at least that far, so the next one never starts under it.
function track.Landing(s, layer)
    return track.JumpLength(s) + (layer or 0) * 4 + 4
end

-- Called by each pattern file, once:
--   name    its id (`/surfer spawn <name>` in Surfer_Dev)
--   weight  how often it comes up: a number, or a table of them by difficulty id (a
--           difficulty left out never has it)
--   from    yards into a run before it comes up, 0 if left out
--   place   function(s, at, r): places its boxes at track distance `at` on, rolling with `r`
--           (the run's generator), and returns its length
function track.Register(pattern)
    assert(type(pattern.name) == "string" and type(pattern.place) == "function", "a pattern needs name and place")
    assert(not track.byName[pattern.name], "two patterns named " .. pattern.name)
    pattern.from = pattern.from or 0
    track.list[#track.list + 1] = pattern
    track.byName[pattern.name] = pattern
    track.choices = {}
end

-- Built once per difficulty: its patterns sorted by `from`, with running sums of weights, so
-- the patterns allowed at a distance are the first ones.
local function choicesFor(difficulty)
    local entries = {}
    for i, pattern in ipairs(track.list) do
        local weight = pattern.weight
        if type(weight) == "table" then
            weight = weight[difficulty.id]
        end
        if weight and weight > 0 then
            entries[#entries + 1] = { pattern = pattern, weight = weight, order = i }
        end
    end
    -- In registration order among equals, so the order cannot change what a seed lays out.
    table.sort(entries, function(a, b)
        if a.pattern.from ~= b.pattern.from then
            return a.pattern.from < b.pattern.from
        end
        return a.order < b.order
    end)
    local choices, sum = { patterns = {}, from = {}, sums = {} }, 0
    for k, entry in ipairs(entries) do
        sum = sum + entry.weight
        choices.patterns[k], choices.from[k], choices.sums[k] = entry.pattern, entry.pattern.from, sum
    end
    return choices
end

-- nil when the difficulty allows none at `at`.
function track.Pick(s, at)
    local difficulty = s.difficulty
    local choices = track.choices[difficulty]
    if not choices then
        choices = choicesFor(difficulty)
        track.choices[difficulty] = choices
    end
    local from, sums = choices.from, choices.sums
    local allowed = 0
    while allowed < #from and from[allowed + 1] <= at do
        allowed = allowed + 1
    end
    if allowed == 0 then
        return nil
    end
    local roll, k = s.random() * sums[allowed], 1
    while sums[k] <= roll do
        k = k + 1
    end
    return choices.patterns[k]
end

-- The next pattern at `s.nextRow`, and the free road after it.
function game.Spawn(s)
    local r, at = s.random, s.nextRow
    local pattern
    if s.nextGate and at >= s.nextGate then
        pattern = track.byName.gate
    else
        pattern = track.Pick(s, at)
    end
    local length = pattern and pattern.place(s, at, r) or 0
    if pattern == track.byName.gate and s.gates then
        s.nextGate = s.gates[#s.gates] + game.ZoneLength(s)
    end
    local gap = s.difficulty.gap
    s.nextRow = at + length + math.max(MIN_GAP, s.speed * (gap[1] + (gap[2] - gap[1]) * r()))
end
