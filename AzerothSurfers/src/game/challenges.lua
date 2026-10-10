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

-- `goal`: yards to the last portal. `stream`: where its seeds start on the generator's cycle.
challenges.KINDS = {
    { id = "daily", name = "Daily", goal = 5000, stream = 1922838371 },
    { id = "weekly", name = "Weekly", goal = 10000, stream = 552808412 },
    { id = "monthly", name = "Monthly", goal = 15000, stream = 1375892117 },
}
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

-- The seed of period `index` of `kind`.
function challenges.Seed(kind, index)
    local r = random.New(SALT + index, kind.stream)
    return r(random.MAX)
end

local function dateText(days)
    local y, m, d = challenges.Date(days)
    return string.format("%d %s %d", d, MONTHS[m], y)
end

-- The period of `kind` (an id) at `now` (seconds since 1970, UTC; challenges.Now() when nil):
--   index   its number: days, weeks or months since 1970
--   key     its id in the saved records ("daily-20371")
--   seed, goal
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
    return {
        kind = kind,
        index = index,
        key = id .. "-" .. index,
        seed = challenges.Seed(kind, index),
        goal = kind.goal,
        starts = first * DAY + reset,
        ends = after * DAY + reset,
        label = label,
    }
end

-- "3d 4h", "4h 12m", "12m": time left until `ends`.
function challenges.Left(period, now)
    local left = math.max(0, period.ends - (now or challenges.Now()))
    local days, hours, minutes = math.floor(left / DAY), math.floor(left % DAY / 3600), math.floor(left % 3600 / 60)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    end
    return string.format("%dm", math.max(1, minutes))
end

-- The saved best of `period` at a difficulty (an id), or nil. In `global.challenges`, by the
-- period's key, then by difficulty:
--   score, coins, coinTotal, distance (yards), finished (reached the last portal),
--   difficulty (its id), at (seconds since 1970, UTC)
function challenges.Best(period, difficulty)
    local saved = app.db.global.challenges[period.key]
    return saved and saved[difficulty]
end

-- Whether `record` beats `best`: reaching the portal first, then the score.
local function beats(record, best)
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
    local saved = all[period.key] or {}
    if not beats(record, saved[record.difficulty]) then
        return false
    end
    saved[record.difficulty] = record
    all[period.key] = saved
    return true
end
