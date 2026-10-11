---@type string, AzerothSurfers
local _, app = ...
-- The challenges' leaderboard: players in the same guild or group share their best of each
-- current challenge (challenges.lua) as addon messages (AceComm), no server. A new best goes out
-- when it is saved; opening a leaderboard asks the others for theirs, and every answer reaches
-- everyone on that channel. What arrives is kept in `global.leaderboard`, by the period's key,
-- then by the sender's name as AceComm gives it, only while its period lasts: "Name" on this
-- realm, "Name-Realm" from another, and on clients with surnames (WoW Forever) the full
-- "Name Surname", so two players of one first name stay apart.
--
-- A message is words split by spaces, the protocol's VERSION first (another version's are left
-- alone):
--   "1 B <key> <score> <distance> <finished 0|1> <coins> <coinTotal>"   a best
--   "1 Q <key> ..."                                                       asking for bests
local challenges = app.challenges

---@class AzerothSurfers.Leaderboard : AceModule, AceComm-3.0
local module = {}
local leaderboard = app.addon:NewModule("Leaderboard", module, "AceComm-3.0") --[[@as AzerothSurfers.Leaderboard]]
app.leaderboard = leaderboard
-- When each channel was asked; when each was answered, by "<channel> <key>"; Ranked's lists by
-- key; how often what arrived changed.
leaderboard.asked, leaderboard.answered, leaderboard.ranked, leaderboard.changes = {}, {}, {}, 0

local PREFIX = "AzSurfers"
local VERSION = "1"
-- The channels it is shared on; any other's messages are ignored.
local CHANNELS = { GUILD = true, PARTY = true, RAID = true }
-- Seconds before asking a channel again, and before answering it again for a period.
module.ASK_EVERY, module.ANSWER_EVERY = 30, 30
-- What a best may hold at most; a message past it is ignored.
local MOST_SCORE, MOST_COINS = 100000000, 100000
-- The most players kept per period.
module.MOST_PLAYERS = 200

function module:OnEnable()
    self:Prune()
    self:RegisterComm(PREFIX)
end

-- The challenges now, by key.
local function current(now)
    local periods = {}
    for _, kind in ipairs(challenges.KINDS) do
        local period = challenges.Period(kind.id, now)
        periods[period.key] = period
    end
    return periods
end

-- Drops what arrived for a period that is over.
function module:Prune(now)
    local periods, saved = current(now), app.db.global.leaderboard
    for key in pairs(saved) do
        if not periods[key] then
            saved[key] = nil
        end
    end
end

-- The channels this player can share on now.
function module.Channels()
    local channels = {}
    if IsInGuild and IsInGuild() then
        channels[#channels + 1] = "GUILD"
    end
    if IsInRaid and IsInRaid() then
        channels[#channels + 1] = "RAID"
    elseif IsInGroup and IsInGroup() then
        channels[#channels + 1] = "PARTY"
    end
    return channels
end

function module.Encode(key, record)
    return string.format(
        "%s B %s %d %d %d %d %d",
        VERSION,
        key,
        record.score,
        record.distance,
        record.finished and 1 or 0,
        record.coins,
        record.coinTotal
    )
end

-- This player's name as the others receive it. WoW Forever's UnitName gives the first name and
-- the surname apart (where the realm would be); its NameUtil joins them as senders arrive, the
-- other clients' gives the plain name. A client without NameUtil: UnitName's first.
function module.Me()
    if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
        return NameUtil.GetUnmodifiedUnitFullName("player")
    end
    return (UnitName("player"))
end

local function count(text, most)
    local n = tonumber(text)
    if n and n >= 0 and n <= most and n == math.floor(n) then
        return n
    end
end

-- The best in `words` (a "B" message's, after its key) for `period`, or nil if it is not one
-- that period could have.
local function decodeBest(period, words)
    local score = count(words[4], MOST_SCORE)
    local distance = count(words[5], period.goal + app.simulation.FINISH_PAST)
    local finished = words[6] == "1" or words[6] ~= "0" and nil
    local coinTotal = count(words[8], MOST_COINS)
    local coins = coinTotal and count(words[7], coinTotal)
    if score and distance and finished ~= nil and coins and not words[9] then
        return { score = score, distance = distance, finished = finished, coins = coins, coinTotal = coinTotal }
    end
end

local function send(self, text, channel)
    self:SendCommMessage(PREFIX, text, channel, nil, "BULK")
end

-- Keeps `record` as `name`'s best of `period` if it beats the one kept; true then.
function module:Store(period, name, record)
    local saved = app.db.global.leaderboard
    local players = saved[period.key]
    if not players then
        players = {}
        saved[period.key] = players
    end
    local kept = players[name]
    if not kept then
        local n = 0
        for _ in pairs(players) do
            n = n + 1
        end
        if n >= self.MOST_PLAYERS then
            return false
        end
    end
    if not challenges.Beats(record, kept) then
        return false
    end
    players[name] = record
    self.changes = self.changes + 1
    return true
end

-- A message from `sender` on `channel`: a best is kept, an ask answered with this player's
-- bests of the periods it names, once per ANSWER_EVERY each.
function module:Receive(message, channel, sender, now)
    if not CHANNELS[channel] or sender == self.Me() then
        return
    end
    local words = {}
    for word in message:gmatch("%S+") do
        words[#words + 1] = word
        if #words > 9 then
            return
        end
    end
    if words[1] ~= VERSION then
        return
    end
    now = now or challenges.Now()
    local periods = current(now)
    if words[2] == "B" then
        local period = periods[words[3] or ""]
        local record = period and decodeBest(period, words)
        if record then
            self:Store(period, sender, record)
        end
    elseif words[2] == "Q" then
        for i = 3, #words do
            local period = periods[words[i]]
            local best = period and challenges.Best(period)
            local id = channel .. " " .. words[i]
            if best and (self.answered[id] or -math.huge) + self.ANSWER_EVERY <= now then
                self.answered[id] = now
                send(self, self.Encode(period.key, best), channel)
            end
        end
    end
end

function module:OnCommReceived(_, message, channel, sender)
    self:Receive(message, channel, sender)
end

-- This player's new best of `period` (challenges.Save kept it), to every channel.
function module:Share(period, record, now)
    if not current(now)[period.key] then
        return
    end
    self.changes = self.changes + 1
    for _, channel in ipairs(self.Channels()) do
        send(self, self.Encode(period.key, record), channel)
    end
end

-- Asks every channel for its bests of `period`, at most once per ASK_EVERY each.
function module:Ask(period, now)
    now = now or challenges.Now()
    if not current(now)[period.key] then
        return
    end
    for _, channel in ipairs(self.Channels()) do
        if (self.asked[channel] or -math.huge) + self.ASK_EVERY <= now then
            self.asked[channel] = now
            send(self, string.format("%s Q %s", VERSION, period.key), channel)
        end
    end
end

local function before(a, b)
    if a.record.finished ~= b.record.finished then
        return a.record.finished
    elseif a.record.score ~= b.record.score then
        return a.record.score > b.record.score
    end
    return a.name < b.name
end

-- `period`'s players, best first: { name, record, me (this player) }; this player's own best
-- from challenges.Best. Built anew only once something changed.
function module:Ranked(period)
    local own = challenges.Best(period)
    local ranked = self.ranked[period.key]
    if ranked and ranked.changes == self.changes and ranked.own == own then
        return ranked
    end
    ranked = { changes = self.changes, own = own }
    local me = self.Me()
    for name, record in pairs(app.db.global.leaderboard[period.key] or {}) do
        if name ~= me then
            ranked[#ranked + 1] = { name = name, record = record }
        end
    end
    if own then
        ranked[#ranked + 1] = { name = me, record = own, me = true }
    end
    table.sort(ranked, before)
    self.ranked[period.key] = ranked
    return ranked
end
