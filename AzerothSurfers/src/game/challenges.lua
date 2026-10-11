---@type string, AzerothSurfers
local _, app = ...
local random = app.random
-- Daily, weekly and monthly challenges: one seed each, the same for every player at any moment,
-- run to a fixed distance (simulation.lua's `finish`) for the highest score. A period begins at
-- RESET_HOUR UTC (a week on Monday, a month on its first day), so the clock of the player's
-- computer, its time zone and daylight saving change nothing; its seed follows from its number
-- alone, by the game's own generator (random.lua), never `math.random`.
local challenges = {}
app.challenges = challenges

-- 11:00 UTC: midday in Europe (12:00 CET, 13:00 CEST), early morning in North America (07:00
-- EDT, 04:00 PDT).
challenges.RESET_HOUR = 11
local DAY = 86400

-- `goal`: yards to the last portal before its VARIATION. `stream`: where its draws start on the
-- generator's cycle.
challenges.KINDS = {
    { id = "daily", name = "Daily", goal = 5000, stream = 1922838371 },
    { id = "weekly", name = "Weekly", goal = 6250, stream = 552808412 },
    { id = "monthly", name = "Monthly", goal = 7500, stream = 1375892117 },
}
-- Each period's goal is its kind's, up to this share more or less, in whole ROUND yards.
challenges.VARIATION = 0.15
local ROUND = 50
for _, kind in ipairs(challenges.KINDS) do
    challenges.KINDS[kind.id] = kind
end
-- Every seed starts from it: changing it changes every challenge.
local SALT = 1000003

local MONTHS = {
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
}

-- The date of `days` since 1970-01-01 (Howard Hinnant's civil_from_days): year, month, day.
function challenges.Date(days)
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400 + (m <= 2 and 1 or 0)
    return y, m, d
end

-- Days since 1970-01-01 of a date (days_from_civil).
function challenges.Days(y, m, d)
    if m <= 2 then
        y = y - 1
    end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

-- Seconds since 1970 (UTC): the realm's clock where the client has it, else the computer's.
function challenges.Now()
    return GetServerTime and GetServerTime() or time()
end

-- What period `index` of `kind` is played with, drawn in this order: its seed, its difficulty
-- (an id of simulation.DIFFICULTIES) and its goal in yards.
function challenges.Draw(kind, index)
    local r = random.New(SALT + index, kind.stream)
    local seed = r(random.MAX)
    local difficulties = app.simulation.DIFFICULTIES
    local difficulty = difficulties[r(#difficulties)].id
    local goal = kind.goal * (1 + challenges.VARIATION * (2 * r() - 1))
    -- Rounded toward the kind's own, so it stays within the variation.
    local steps = (goal - kind.goal) / ROUND
    steps = steps < 0 and math.ceil(steps) or math.floor(steps)
    return seed, difficulty, kind.goal + steps * ROUND
end

local function dateText(days)
    local y, m, d = challenges.Date(days)
    return string.format("%d %s %d", d, MONTHS[m], y)
end

-- The period of `kind` (an id) at `now` (seconds since 1970, UTC; challenges.Now() when nil):
--   index   its number: days, weeks or months since 1970
--   key     its id in the saved records ("daily-20371")
--   seed, difficulty (an id), goal (challenges.Draw)
--   starts, ends   seconds since 1970 of its first moment and of the next period's
--   label   its date, as players see it
function challenges.Period(id, now)
    local kind = challenges.KINDS[id]
    now = now or challenges.Now()
    -- A challenge's day starts at the reset.
    local day = math.floor((now - challenges.RESET_HOUR * 3600) / DAY)
    local index, first, after, label
    if id == "daily" then
        index, first, after = day, day, day + 1
        label = dateText(day)
    elseif id == "weekly" then
        -- 1970-01-01 was a Thursday: day 4 the first Monday.
        index = math.floor((day + 3) / 7)
        first = index * 7 - 3
        after = first + 7
        label = "Week of " .. dateText(first)
    else
        local y, m = challenges.Date(day)
        index = (y - 1970) * 12 + m - 1
        first = challenges.Days(y, m, 1)
        after = m == 12 and challenges.Days(y + 1, 1, 1) or challenges.Days(y, m + 1, 1)
        label = MONTHS[m] .. " " .. y
    end
    local reset = challenges.RESET_HOUR * 3600
    local seed, difficulty, goal = challenges.Draw(kind, index)
    return {
        kind = kind,
        index = index,
        key = id .. "-" .. index,
        seed = seed,
        difficulty = difficulty,
        goal = goal,
        starts = first * DAY + reset,
        ends = after * DAY + reset,
        label = label,
    }
end

-- "3d 4h", "4h 12m", "12m": time left until `ends`; "now" once it has come.
function challenges.Left(period, now)
    local left = period.ends - (now or challenges.Now())
    if left <= 0 then
        return "now"
    end
    local days, hours, minutes = math.floor(left / DAY), math.floor(left % DAY / 3600), math.floor(left % 3600 / 60)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", math.max(1, minutes))
end

-- The saved best of `period`, or nil. In `global.challenges`, by the period's key:
--   score, coins, coinTotal, distance (yards), finished (reached the last portal),
--   difficulty (its id), goal (yards), at (seconds since 1970, UTC),
--   trace, traceEvery (the live target's checkpoints, challenges.Trace; none in older records)
function challenges.Best(period)
    local record = app.db.global.challenges[period.key]
    -- Anything else under the key (an earlier version's records by difficulty) is no best.
    if type(record) == "table" and type(record.score) == "number" then
        return record
    end
end

-- Whether `record` beats `best` (nil: none yet): reaching the portal first, then the score.
function challenges.Beats(record, best)
    if not best then
        return true
    elseif record.finished ~= best.finished then
        return record.finished
    end
    return record.score > best.score
end

-- Keeps `record` (fields as in Best) if it beats the saved one; true then.
function challenges.Save(period, record)
    local all = app.db.global.challenges
    if not challenges.Beats(record, challenges.Best(period)) then
        return false
    end
    all[period.key] = record
    return true
end

-- The live target: a challenge's run keeps its score every TRACE_EVERY yards (`s.trace`, the
-- score at TRACE_EVERY * i yards in `[i]`), saved with its record (`trace`, `traceEvery`), so
-- a later run can tell how far ahead or behind the best it is at the same distance.
challenges.TRACE_EVERY = 100

-- Room for the whole run, made when it begins: a running frame adds nothing to a table.
function challenges.NewTrace(s)
    local trace = {}
    for i = 1, math.ceil((s.finish - s.start) / challenges.TRACE_EVERY) do
        trace[i] = 0
    end
    s.trace, s.traced = trace, 0
end

-- Once a step or a frame: the score at every checkpoint the run passed since.
function challenges.Trace(s)
    local trace = s.trace
    if not trace then
        return
    end
    local passed = math.min(#trace, math.floor(app.simulation.Run(s) / challenges.TRACE_EVERY))
    while s.traced < passed do
        s.traced = s.traced + 1
        trace[s.traced] = app.simulation.Score(s)
    end
end

-- The run's trace as saved: its checkpoints passed only.
function challenges.SavedTrace(s)
    local saved = {}
    for i = 1, s.traced or 0 do
        saved[i] = s.trace[i]
    end
    return saved
end

-- What `best` (a record of Best) had scored `yards` in: between its checkpoints, and from the
-- last one to where it ended, in a straight line. Nil past where it ended, or without a trace
-- (a record from before traces).
function challenges.Target(best, yards)
    local trace = best and best.trace
    if not trace or yards > best.distance then
        return nil
    end
    local every = best.traceEvery or challenges.TRACE_EVERY
    local i = math.floor(yards / every)
    local fromYards, from = i * every, trace[i] or 0
    local toYards, to = (i + 1) * every, trace[i + 1]
    if not to then
        toYards, to = best.distance, best.score
    end
    if toYards <= fromYards then
        return to
    end
    return math.floor(from + (to - from) * (yards - fromYards) / (toYards - fromYards))
end

-- How this player stands in the current period of `id` (`now` as in Period): "new" (no run
-- yet), "beaten" (a run reached its finish) or "tried" (none did yet); then its best (Best)
-- and the period.
function challenges.Status(id, now)
    local period = challenges.Period(id, now)
    local best = challenges.Best(period)
    return (not best and "new") or (best.finished and "beaten") or "tried", best, period
end

-- The status as players read it: "new", "beaten (1234)", "not finished (800)", in its color.
local STATUS = {
    new = "|cff20ff20new|r",
    beaten = "|cffffd100beaten (%d)|r",
    tried = "|cffff8040not finished (%d)|r",
}
function challenges.StatusText(id, now)
    local status, best = challenges.Status(id, now)
    return string.format(STATUS[status], best and best.score or 0)
end

-- The login reminder: one chat line with every kind's status.
function challenges.Reminder(now)
    local parts = {}
    for i, kind in ipairs(challenges.KINDS) do
        parts[i] = kind.name .. " " .. challenges.StatusText(kind.id, now)
    end
    return "Challenges: " .. table.concat(parts, ", ")
end
