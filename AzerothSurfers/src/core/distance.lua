---@type string, AzerothSurfers
local _, app = ...

-- WoW localizes the unit of spell ranges without converting the number. Keep the same
-- convention: simulation, saved records, scoring and shared leaderboard data stay in yards.
local distance = {}
app.distance = distance

-- SPELL_RANGE is the client's localized spell-tooltip format. Chinese uses yards too.
-- Fall back to the locale only when the format is unavailable (older clients/test harnesses).
local locale = GetLocale and GetLocale() or "enUS"
local clientYards = locale == "enUS" or locale == "enGB" or locale == "zhCN" or locale == "zhTW"
if type(SPELL_RANGE) == "string" and SPELL_RANGE ~= "" then
    local range = SPELL_RANGE:lower()
    clientYards = range:find("%f[%a]yd%f[%A]") ~= nil
        or range:find("yard", 1, true) ~= nil
        or range:find("码", 1, true) ~= nil
        or range:find("碼", 1, true) ~= nil
end
local clientUnit = clientYards and "yd" or "m"

function distance.Unit()
    local setting = app.db and app.db.profile.distanceUnit
    if setting == "yards" then
        return "yd"
    elseif setting == "meters" then
        return "m"
    end
    return clientUnit
end

function distance.Name()
    return distance.Unit() == "yd" and "yards" or "meters"
end

function distance.Text(value, goal)
    if goal then
        return string.format("%d / %d %s", value, goal, distance.Unit())
    end
    return string.format("%d %s", value, distance.Unit())
end
