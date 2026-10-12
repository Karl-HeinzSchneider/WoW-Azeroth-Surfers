-- The challenges' leaderboard: what goes out, what is kept, what is ignored, the ranking.
local app = {}
dofile("tests/load.lua")(app, {
    "game/random",
    "game/scoring",
    "game/simulation",
    "game/challenges",
    "game/leaderboard",
})
local c, board = app.challenges, app.leaderboard
app.db = { profile = {}, global = { challenges = {}, leaderboard = {} } }
local now = 20736 * 86400 + 12 * 3600
function GetServerTime()
    return now
end
-- WoW Forever: the first name and the surname apart; senders and NameUtil have both.
function UnitName()
    return "Me", "Meier"
end
NameUtil = {
    GetUnmodifiedUnitFullName = function()
        return "Me Meier"
    end,
}
local guild, group = true, false
function IsInGuild()
    return guild
end
function IsInRaid()
    return false
end
function IsInGroup()
    return group
end
local daily, weekly = c.Period("daily"), c.Period("weekly")
local function best(score, finished, distance)
    return { score = score, distance = distance or 100, finished = finished, coins = 3, coinTotal = 10 }
end
local function sent()
    local all = board.sent
    board.sent = {}
    return all
end
local count = 0
local function test(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end

test("a best goes out to the guild and the group and comes back the same", function()
    group = true
    board:Share(daily, best(1234, true, daily.goal))
    local out = sent()
    assert(#out == 2 and out[1].channel == "GUILD" and out[2].channel == "PARTY", "both channels")
    assert(out[1].text == "2 B " .. daily.key .. " 1234 " .. daily.goal .. " 1 3 10", out[1].text)
    assert(#out[1].text <= 255, "one message")
    board:Receive(out[1].text, "GUILD", "Ann")
    local kept = app.db.global.leaderboard[daily.key].Ann
    assert(kept and kept.score == 1234 and kept.finished and kept.distance == daily.goal and kept.coins == 3)
    group = false
end)

test("disabled sharing blocks bests, requests and replies", function()
    app.db.global.challenges[weekly.key] = best(100, true)
    app.db.profile.sharing = false
    board:Share(daily, best(1234, true, daily.goal))
    board:Ask(weekly)
    board:Receive("2 Q " .. weekly.key, "GUILD", "Ann")
    board:Receive(board.Encode(weekly.key, best(200, true)), "GUILD", "Disabled")
    assert(#sent() == 0, "no outgoing messages while sharing is disabled")
    assert(not app.db.global.leaderboard[weekly.key], "disabled sharing does not receive scores")
    app.db.profile.sharing = true
    board:Ask(weekly)
    assert(#sent() > 0, "sharing can be enabled again")
    board.asked = {}
    app.db.global.challenges[weekly.key] = nil
end)

test("a best is kept only if it beats the one before", function()
    board:Receive(board.Encode(daily.key, best(900, true)), "GUILD", "Ann")
    assert(app.db.global.leaderboard[daily.key].Ann.score == 1234, "a lower score")
    board:Receive(board.Encode(daily.key, best(5000, false)), "GUILD", "Ann")
    assert(app.db.global.leaderboard[daily.key].Ann.finished, "not reaching the portal")
    board:Receive(board.Encode(daily.key, best(2000, true)), "GUILD", "Ann")
    assert(app.db.global.leaderboard[daily.key].Ann.score == 2000, "a higher one")
end)

test("anything malformed, out of period, from elsewhere or from oneself is ignored", function()
    local key = daily.key
    local bad = {
        "2 B " .. key .. " 50 100 1 3", -- a word short
        "2 B " .. key .. " 50 100 1 3 10 7", -- a word too many
        "2 B " .. key .. " -5 100 1 3 10",
        "2 B " .. key .. " 5.5 100 1 3 10",
        "2 B " .. key .. " 1e12 100 1 3 10",
        "2 B " .. key .. " " .. (board.MOST_SCORE + 1) .. " 100 1 3 10", -- more than the columns hold
        "2 B " .. key .. " 50 100 1 3 " .. (board.MOST_COINS + 1),
        "2 B " .. key .. " 50 abc 1 3 10",
        "2 B " .. key .. " 50 " .. (daily.goal + 1000) .. " 1 3 10", -- further than the challenge
        "2 B " .. key .. " 50 100 2 3 10",
        "2 B " .. key .. " 50 100 1 11 10", -- more coins than there were
        "2 B daily-" .. (daily.index - 1) .. " 50 100 1 3 10", -- yesterday's
        "2 B daily-" .. (daily.index + 1) .. " 50 100 1 3 10",
        "1 B " .. key .. " 50 100 1 3 10", -- another version
        "2 X " .. key,
        "",
        "2 B",
    }
    for _, text in ipairs(bad) do
        board:Receive(text, "GUILD", "Bob")
    end
    assert(app.db.global.leaderboard[key].Bob == nil, "nothing from Bob kept")
    assert(app.db.global.leaderboard["daily-" .. (daily.index - 1)] == nil)
    local good = board.Encode(key, best(50, true))
    board:Receive(good, "WHISPER", "Bob")
    board:Receive(good, "SAY", "Bob")
    board:Receive(good, "GUILD", "Me Meier")
    assert(app.db.global.leaderboard[key].Bob == nil and app.db.global.leaderboard[key]["Me Meier"] == nil, "oneself")
    board:Receive(good, "GUILD", "Me Schulz")
    assert(app.db.global.leaderboard[key]["Me Schulz"].score == 50, "another player of the same first name")
    board:Receive(board.Encode(key, best(board.MOST_SCORE, true)), "GUILD", "Max")
    assert(app.db.global.leaderboard[key].Max.score == board.MOST_SCORE, "the most a column holds")
    app.db.global.leaderboard[key].Max = nil
    board:Receive(good, "RAID", "Bob-Firemaw")
    assert(app.db.global.leaderboard[key]["Bob-Firemaw"].score == 50, "another realm's player")
    assert(#sent() == 0, "nothing answered")
end)

test("asking: once per channel and period a while, answered with the bests one has", function()
    group = true
    board:Ask(daily)
    local out = sent()
    assert(#out == 2 and out[1].text == "2 Q " .. daily.key, out[1] and out[1].text)
    board:Ask(daily)
    assert(#sent() == 0, "not again so soon")
    board:Ask(weekly)
    out = sent()
    assert(#out == 2 and out[1].text == "2 Q " .. weekly.key, "another challenge without waiting")
    local monthly = c.Period("monthly")
    board:Ask(monthly)
    out = sent()
    assert(#out == 2 and out[1].text == "2 Q " .. monthly.key, "monthly without waiting")
    board:Ask(weekly)
    board:Ask(monthly)
    assert(#sent() == 0, "each challenge keeps its own cooldown")
    now = now + board.ASK_EVERY
    board:Ask(daily)
    assert(#sent() == 2, "same challenge again after a while")
    group = false
    -- Answers: only with a best of the period, once a while per channel and period.
    board:Receive("2 Q " .. daily.key, "GUILD", "Ann")
    assert(#sent() == 0, "no best of its own yet")
    c.Save(daily, best(777, true))
    board:Receive("2 Q " .. daily.key .. " " .. weekly.key, "GUILD", "Ann")
    out = sent()
    assert(#out == 1 and out[1].channel == "GUILD" and out[1].text:find(" 777 "), "its daily best")
    board:Receive("2 Q " .. daily.key, "GUILD", "Cid")
    assert(#sent() == 0, "not again so soon")
    board:Receive("2 Q " .. daily.key, "PARTY", "Cid")
    assert(#sent() == 1, "another channel")
    board:Receive("2 Q daily-" .. (daily.index - 1), "RAID", "Cid")
    assert(#sent() == 0, "not for another period")
end)

test("the ranking: the portal first, then the score, and oneself in it", function()
    board:Receive(board.Encode(daily.key, best(9000, false)), "GUILD", "Dan")
    local ranked = board:Ranked(daily)
    local names = {}
    for i, e in ipairs(ranked) do
        names[i] = e.name
    end
    assert(table.concat(names, ", ") == "Ann, Me Meier, Bob-Firemaw, Me Schulz, Dan", table.concat(names, ", "))
    assert(ranked[2].me and ranked[2].record.score == 777)
    assert(board:Ranked(daily) == ranked, "built once while nothing changes")
    c.Save(daily, best(3000, true))
    assert(board:Ranked(daily)[1].me, "its own new best")
    assert(#board:Ranked(weekly) == 0, "nobody's weekly yet")
end)

test("without NameUtil, the first name", function()
    local util = NameUtil
    NameUtil = nil
    assert(board.Me() == "Me", board.Me())
    NameUtil = util
end)

test("a player's list per period is bounded, and ended periods are dropped", function()
    local most = board.MOST_PLAYERS
    board.MOST_PLAYERS = 4
    for i = 1, 6 do
        board:Receive(board.Encode(weekly.key, best(i, true)), "GUILD", "P" .. i)
    end
    local n = 0
    for _ in pairs(app.db.global.leaderboard[weekly.key]) do
        n = n + 1
    end
    assert(n == 4, "no more than the most")
    board.MOST_PLAYERS = most
    board:Prune(daily.ends)
    assert(app.db.global.leaderboard[daily.key] == nil, "yesterday's gone")
    assert(app.db.global.leaderboard[weekly.key], "the week goes on")
    board:Share(daily, best(1, true), daily.ends)
    assert(#sent() == 0, "an ended period is not shared")
end)

print(string.format("%d leaderboard tests passed", count))
