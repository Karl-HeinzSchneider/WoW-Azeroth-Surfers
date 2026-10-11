---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
local shapes = app.shapes
-- The title screen and the main menu. Both look at the lobby (src/scenes/lobby.lua) through its
-- `shots`, where the character sits at a cooking fire; the camera glides from one to the next
-- and, on Play, behind the character into the run. `screen`: "title", "menu", "start" (standing
-- up and on the way into a run) or nil (a run, its pause and its end).
local overlay = app.overlay
local cam = overlay.camera
local LANE = sim.geometry.laneWidth
local ground = shapes.Ground

local FONT = "Fonts\\MORPHEUS.ttf"
local CREDIT = "made by Karl-Heinz Schneider"
-- Pixels at scale 1: the title screen's name and credit, and the menu's over its window.
local TITLE_SIZE, CREDIT_SIZE = 78, 20
local MENU_TITLE_SIZE, MENU_CREDIT_SIZE = 42, 14
-- The side window shows them smaller.
local TITLE_SIDE_SCALE, PROMPT_SIDE_SCALE, MENU_SIDE_SCALE = 0.5, 0.7, 0.6
-- The prompt's flicker: seconds per pulse, and its faintest.
local PULSE, PULSE_LOW = 1.4, 0.2
-- Seconds the title fades out and the menu in.
local FADE = 0.5
local GOLD = { 1, 0.82, 0 }
local CREAM = { 1, 0.9294, 0.7607 }
local WHITE = { 1, 1, 1 }
-- The bindings that steer a run.
local MOVES = {
    MOVEFORWARD = true,
    TURNLEFT = true,
    TURNRIGHT = true,
    STRAFELEFT = true,
    STRAFERIGHT = true,
    JUMP = true,
}
-- A shot's fields (overlay.lua's RunShot), in a fixed order.
local FIELDS = { "at", "side", "height", "pitch", "fov" }

-- The main menu's pages (menus.lua describes pages and items).
local function difficulty()
    return sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
end
local DIFFICULTY = {
    text = "Difficulty",
    choice = {
        get = function()
            return difficulty().name
        end,
        can = function(_, dir)
            return sim.DIFFICULTIES[difficulty().level + dir] ~= nil
        end,
        step = function(o, dir)
            o:StepDifficulty(dir)
        end,
    },
}
local GRAY = { 0.7, 0.7, 0.7 }
local PAGES = {}
-- The normal game: a new seed each run, from the camp; its best is the best score.
PAGES.play = {
    title = "Play",
    items = {
        {
            text = "Play",
            run = function(o)
                o:Play(false)
            end,
        },
        DIFFICULTY,
        {
            text = "Auto mode",
            run = function(o)
                o:Play(true)
            end,
        },
        { text = "Cancel", back = true },
    },
}
-- A custom game: Play's items and every setting of messages.lua's CUSTOM (seed, start at, ...);
-- its runs save no best score.
do
    local items = {
        { text = "Your own settings, no best score", note = GRAY },
        {
            text = "Play",
            run = function(o)
                o:PlayCustom(false)
            end,
        },
        DIFFICULTY,
    }
    for _, item in ipairs(overlay.CUSTOM) do
        items[#items + 1] = item
    end
    items[#items + 1] = {
        text = "Auto mode",
        run = function(o)
            o:PlayCustom(true)
        end,
    }
    items[#items + 1] = { text = "Cancel", back = true }
    PAGES.custom = {
        title = "Custom",
        items = items,
        extra = {
            text = "New seed",
            run = function(o)
                o:SetSeed(app.random.Seed())
            end,
        },
    }
end
-- A challenge's best (challenges.lua's Best): its score, and how far it got if it did not reach
-- the portal.
local function scoreText(record)
    return record.finished and tostring(record.score)
        or string.format("%d  |cffaaaaaa%d yd|r", record.score, record.distance)
end
-- Rows of a leaderboard; this player's place below them when it is further down.
local RANKS = 8
-- A full name as long as names get: a first name and a surname of 12 letters each (WoW's
-- limit; other clients have no surname), of letters as wide as names have on average.
local LONG_NAME = "Zimtschnecke Zimtschnecke"
-- A leaderboard is a table (menus.lua): its name column as wide as a place and LONG_NAME and a
-- quarter more, for wider letters (a name wider still, or another realm's "-Realm", is cut),
-- then score, distance and coins, as wide as the most leaderboard.lua takes of each.
local BOARD = {
    size = 20,
    label = "99. " .. LONG_NAME,
    spare = 0.25,
    values = {
        tostring(app.leaderboard.MOST_SCORE),
        "9999 yd",
        string.format("%d/%d (100%%)", app.leaderboard.MOST_COINS, app.leaderboard.MOST_COINS),
    },
    heads = { "Score", "Distance", "Coins" },
}
-- A leaderboard row's columns: the score, the distance (gray: the run did not reach the
-- portal), the coins and their share of the run's, in whole percent down.
local function boardColumns(record)
    if not record then
        return "", "", ""
    end
    local far = string.format(record.finished and "%d yd" or "|cffaaaaaa%d yd|r", record.distance)
    local share = record.coinTotal > 0 and math.floor(100 * record.coins / record.coinTotal) or 0
    return tostring(record.score), far, string.format("%d/%d (%d%%)", record.coins, record.coinTotal, share)
end
-- A challenge's leaderboard (leaderboard.lua): the bests of the guild and the group, asked for
-- when it opens and again by its extra action, and shown as they arrive.
local function leaderboardPage(period)
    local board = app.leaderboard
    board:Ask(period)
    local function entry(i)
        return board:Ranked(period)[i]
    end
    local function name(e, i)
        local shown = string.format("%d. %s", i, e.name)
        return e.me and "|cffffffff" .. shown .. "|r" or shown
    end
    local items = {
        { text = period.label, note = GRAY },
        {
            text = "Player",
            info = function()
                return unpack(BOARD.heads)
            end,
        },
    }
    for i = 1, RANKS do
        items[#items + 1] = {
            text = function()
                local e = entry(i)
                if e then
                    return name(e, i)
                end
                return i == 1 and "No bests shared yet" or ""
            end,
            info = function()
                local e = entry(i)
                return boardColumns(e and e.record)
            end,
        }
    end
    -- This player's place, should it be below the rows.
    local function own()
        local ranked = board:Ranked(period)
        for i = RANKS + 1, #ranked do
            if ranked[i].me then
                return ranked[i], i
            end
        end
    end
    items[#items + 1] = {
        text = function()
            local e, i = own()
            return e and name(e, i) or ""
        end,
        info = function()
            local e = own()
            return boardColumns(e and e.record)
        end,
    }
    items[#items + 1] = { text = "Back", back = true }
    return {
        title = period.kind.name .. " leaderboard",
        items = items,
        columns = BOARD,
        extra = {
            text = "Ask again",
            run = function()
                board:Ask(period)
            end,
        },
    }
end
-- A challenge's page (challenges.lua): its period as it is when opened (seed, difficulty and
-- distance all its own), its best, and a run to beat it.
local challengePage
function challengePage(id)
    local challenges = app.challenges
    local period = challenges.Period(id)
    local function best()
        return challenges.Best(period)
    end
    return {
        title = period.kind.name .. " challenge",
        items = {
            { text = period.label, note = GRAY },
            {
                text = "Distance",
                info = function()
                    return string.format("%d yd", period.goal)
                end,
            },
            {
                text = "Difficulty",
                info = function()
                    return sim.DIFFICULTIES[period.difficulty].name
                end,
            },
            {
                text = "Seed",
                info = function()
                    return tostring(period.seed)
                end,
            },
            {
                text = "New one in",
                info = function()
                    return challenges.Left(period)
                end,
            },
            {
                text = "Best",
                info = function()
                    local record = best()
                    return record and scoreText(record) or "0"
                end,
            },
            {
                text = "Coins",
                info = function()
                    local record = best()
                    return record and string.format("%d / %d", record.coins, record.coinTotal) or "0"
                end,
            },
            {
                text = function()
                    return best() and "Beat it" or "Play"
                end,
                -- Left open past its end: the new one's page instead.
                run = function(o, menu)
                    if challenges.Now() >= period.ends then
                        menu:Back()
                        menu:Push(challengePage(id))
                    else
                        o:PlayChallenge(period)
                    end
                end,
            },
            -- The guild's and the group's bests.
            {
                text = "Leaderboard",
                run = function(_, menu)
                    menu:Push(leaderboardPage(period))
                end,
            },
            { text = "Back", back = true },
        },
    }
end
local function challengeItem(id)
    return {
        text = app.challenges.KINDS[id].name,
        run = function(_, menu)
            menu:Push(challengePage(id))
        end,
    }
end
-- Past challenges of a kind (challenges.lua's History), newest first, HISTORY_ROWS a page: the
-- date, the best's score, how far it got if it did not reach the portal, and its coins.
local HISTORY_ROWS = 7
local function historyPage(id)
    local challenges = app.challenges
    local list = challenges.History(id)
    local pages = math.max(1, math.ceil(#list / HISTORY_ROWS))
    local shown = 1
    local function entry(row)
        return list[(shown - 1) * HISTORY_ROWS + row]
    end
    local items = {
        {
            text = "Page",
            choice = {
                get = function()
                    return string.format("%d / %d", shown, pages)
                end,
                can = function(_, dir)
                    return shown + dir >= 1 and shown + dir <= pages
                end,
                step = function(_, dir)
                    shown = shown + dir
                end,
            },
        },
    }
    for row = 1, HISTORY_ROWS do
        items[#items + 1] = {
            text = function()
                local e = entry(row)
                if e then
                    return challenges.ShortLabel(challenges.ByIndex(id, e.index))
                end
                return row == 1 and "None played yet" or ""
            end,
            info = function()
                local e = entry(row)
                if not e then
                    return ""
                end
                local record = e.record
                local far = record.finished and "" or string.format("|cffaaaaaa%d yd|r  ", record.distance)
                return string.format("%d  %s%d/%d", record.score, far, record.coins, record.coinTotal)
            end,
        }
    end
    items[#items + 1] = { text = "Back", back = true }
    return { title = challenges.KINDS[id].name .. " history", items = items }
end
local function historyItem(id)
    return {
        text = app.challenges.KINDS[id].name,
        run = function(_, menu)
            menu:Push(historyPage(id))
        end,
    }
end
-- The streak of days played (a daily challenge each) and the lists of past challenges; counted
-- when opened.
local function streakText(days)
    return days == 1 and "1 day" or string.format("%d days", days)
end
local function historyOverview()
    local current, longest = app.challenges.Streak()
    return {
        title = "History",
        items = {
            {
                text = "Streak",
                info = function()
                    return streakText(current)
                end,
            },
            {
                text = "Longest",
                info = function()
                    return streakText(longest)
                end,
            },
            { text = "Days with a daily challenge run", note = GRAY },
            historyItem("daily"),
            historyItem("weekly"),
            historyItem("monthly"),
            { text = "Back", back = true },
        },
    }
end
PAGES.challenges = {
    title = "Challenges",
    items = {
        { text = "The same seed for everyone", note = GRAY },
        challengeItem("daily"),
        challengeItem("weekly"),
        challengeItem("monthly"),
        {
            text = "History",
            run = function(_, menu)
                menu:Push(historyOverview())
            end,
        },
        { text = "Back", back = true },
    },
}
PAGES.stats = {
    title = "Stats",
    items = {
        {
            text = "Best score",
            info = function()
                return tostring(app.db.global.bestScore)
            end,
        },
        { text = "Back", back = true },
    },
}
PAGES.main = {
    items = {
        {
            text = "Play",
            run = function(_, menu)
                menu:Push(PAGES.play)
            end,
        },
        {
            text = "Challenges",
            run = function(_, menu)
                menu:Push(PAGES.challenges)
            end,
        },
        {
            text = "Custom",
            run = function(_, menu)
                menu:Push(PAGES.custom)
            end,
        },
        {
            text = "Stats",
            run = function(_, menu)
                menu:Push(PAGES.stats)
            end,
        },
        {
            text = "Options",
            run = function()
                app.options:Open()
            end,
        },
        {
            text = "Close",
            run = function(o)
                o.frame:Hide()
            end,
        },
    },
    -- Back from the first page: to the title.
    back = function(o)
        o:BackToTitle()
    end,
}

local function text(parent, size, color)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFontObject(GameFontNormalHuge)
    t:SetFont(FONT, size, "OUTLINE")
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(2, -2)
    t:SetTextColor(color[1], color[2], color[3])
    return t
end

function overlay:CreateScreens(f)
    -- The title screen: the name over the portal, the credit under it, the prompt in the middle.
    local title = CreateFrame("Frame", nil, f)
    self:Stack(title, "screens")
    title:SetAllPoints(f)
    title:SetAlpha(0)
    title:Hide()
    local banner = CreateFrame("Frame", nil, title)
    banner:SetSize(1, 1)
    local name = text(banner, TITLE_SIZE, GOLD)
    name:SetPoint("TOP")
    name:SetText(app.TITLE)
    local credit = text(banner, CREDIT_SIZE, CREAM)
    credit:SetPoint("TOP", name, "BOTTOM", 0, -4)
    credit:SetText(CREDIT)
    local prompt = CreateFrame("Button", nil, title)
    prompt:SetScript("OnClick", function()
        self:ContinueTitle()
    end)
    local promptText = text(prompt, 24, WHITE)
    promptText:SetPoint("CENTER")

    -- The menu: a smaller name, and the menu window (menus.lua) under it.
    local menu = CreateFrame("Frame", nil, f)
    self:Stack(menu, "screens")
    menu:SetSize(1, 1)
    menu:SetAlpha(0)
    menu:Hide()
    local menuName = text(menu, MENU_TITLE_SIZE, GOLD)
    menuName:SetPoint("TOPLEFT")
    menuName:SetText(app.TITLE)
    local menuCredit = text(menu, MENU_CREDIT_SIZE, CREAM)
    menuCredit:SetPoint("TOPLEFT", menuName, "BOTTOMLEFT", 2, -2)
    menuCredit:SetText(CREDIT)
    self.mainMenu = self:CreateMenu(menu)
    self.mainMenu.panel:SetPoint("TOPLEFT", menuCredit, "BOTTOMLEFT", -14, -12)

    self.screens = {
        title = title,
        banner = banner,
        prompt = prompt,
        promptText = promptText,
        menu = menu,
        alpha = {},
    }
    -- The character at the fire: an actor of the world scene, so the fire and the models in
    -- front of it cover it. Placed by its origin, at its feet.
    if not self.worldScene then
        return
    end
    local seat = self.worldScene:CreateActor()
    seat:SetUseCenterForOrigin(false, false, false)
    seat:Hide()
    -- Without the handler (an older client), standing up takes `standUpMost` seconds.
    pcall(seat.SetScript, seat, "OnAnimFinished", function()
        self:OnSeatAnimFinished()
    end)
    self.seat = seat
    self:LoadSeat()
end

function overlay:LoadSeat()
    self.seat:SetModelByUnit("player", true, true, false, true)
    self.seatAnimation = nil
end

function overlay:PlaceScreens(side, w, h)
    local sc = self.screens
    -- Offsets count in each frame's own scale.
    local scale = side and TITLE_SIDE_SCALE or 1
    sc.banner:SetScale(scale)
    sc.banner:ClearAllPoints()
    sc.banner:SetPoint("TOP", self.frame, "TOP", 0, -(side and 0.1 or 0.09) * h / scale)
    scale = side and PROMPT_SIDE_SCALE or 1
    sc.prompt:SetScale(scale)
    sc.prompt:ClearAllPoints()
    sc.prompt:SetPoint("CENTER", self.frame, "CENTER", 0, -0.04 * h / scale)
    scale = side and MENU_SIDE_SCALE or 1
    sc.menu:SetScale(scale)
    sc.menu:ClearAllPoints()
    local x = side and 16 or math.max(40, 0.07 * w)
    local y = side and 44 or 0.12 * h
    sc.menu:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x / scale, -y / scale)
    self.screenPrompt = nil
end

-- The lobby's shot `name` into `out`, with its side window values in the side window.
local function lobbyShot(self, name, out)
    local shot = app.lobby.shots[name]
    local over = self.side and shot.sideWindow
    for _, k in ipairs(FIELDS) do
        out[k] = over and over[k] or shot[k]
    end
    return out
end

local screenShot, glideShot = {}, {}

-- The camera's shot this frame: the run's (`run`), a screen's, or on the way between them.
function overlay:ViewShot(run)
    local target = self.shotName and lobbyShot(self, self.shotName, screenShot) or run
    local glide = self.glide
    if not glide then
        return target
    end
    local t = (GetTime() - glide.start) / glide.seconds
    if t >= 1 then
        self.glide = nil
        return target
    end
    t = t * t * (3 - 2 * t)
    local from = glide.from
    for _, k in ipairs(FIELDS) do
        glideShot[k] = from[k] + (target[k] - from[k]) * t
    end
    return glideShot
end

-- From where the camera is now to the next shot, over `seconds`.
function overlay:StartGlide(seconds)
    if not cam.f then
        self.glide = nil
        return
    end
    local _, h = self.frame:GetSize()
    local from = { at = cam.x, side = -cam.offset, height = cam.z, pitch = math.deg(cam.pitch) }
    from.fov = math.deg(2 * math.atan(h / 2 / cam.f))
    self.glide = { from = from, start = GetTime(), seconds = seconds }
end

-- The lobby's run, not started yet; a new one unless it is shown already. It ends a challenge
-- and a custom game.
function overlay:EnterLobby()
    local s = self.state
    self.challenge, self.custom = nil, nil
    if s.status ~= "ready" or not s.lobby or s.challenge or s.custom then
        self:SaveBest()
        self.state = self:NewState(app.lobby)
    end
    self.startPhase, self.watching, self.twinFace = nil, nil, nil
    self.seated, self.seatWant = true, app.lobby.seat.sit
    self.legendState = nil
end

function overlay:OpenTitle()
    self:EnterLobby()
    self.screen, self.shotName, self.glide = "title", "title", nil
    self.lastRoad = {}
    self:PlayTitleMusic(true)
end

-- From the title, or back from a run (its pause or end, or auto mode): the camera glides to
-- the menu's shot.
function overlay:OpenMenu()
    self:StartGlide(app.lobby.glide.menu)
    self:EnterLobby()
    self.screen, self.shotName = "menu", "menu"
    self.mainMenu:Open(PAGES.main)
    self:PlayTitleMusic(true)
end

-- A challenge (challenges.lua's Period) from the menu: its run from the lobby, and every
-- restart, until the menu or the title shows again.
function overlay:PlayChallenge(period)
    if self.screen ~= "menu" then
        return
    end
    self.challenge = period
    self.state = self:NewState(app.lobby)
    self:Play(false)
end

-- A custom game from the menu: its run from the lobby with the custom settings, and every
-- restart, until the menu or the title shows again. `watch`: in auto mode.
function overlay:PlayCustom(watch)
    if self.screen ~= "menu" then
        return
    end
    self.custom = true
    self.state = self:NewState(app.lobby)
    self:Play(watch)
end

-- Back from the main menu's first page: the camera glides to the title's shot.
function overlay:BackToTitle()
    self:StartGlide(app.lobby.glide.menu)
    self.screen, self.shotName = "title", "title"
end

function overlay:ContinueTitle()
    if self.screen == "title" then
        self:OpenMenu()
    end
end

-- The character stands up, turns to the road, and the run starts (ShowScreens); `watch`: in
-- auto mode.
function overlay:Play(watch)
    if self.screen ~= "title" and self.screen ~= "menu" then
        return
    end
    local seat, now = app.lobby.seat, GetTime()
    self.screen, self.watching = "start", watch or nil
    self.startPhase, self.seatWant, self.standDone = "stand", seat.standUp, false
    self.standFrom, self.standUntil = now, now + seat.standUpMost
    self.legendState = nil
end

-- The keys while a screen or a menu shows; true when the run's own handling is not to see `key`.
-- The title goes on with the menus' accept (keys.lua); the main menu and the pause and end
-- menu (messages.lua) take their actions' keys (menus.lua's MenuAction). Captured, every other key
-- of the game's and WoW's movement keys stay here too (controls.lua's Captures), so nothing the
-- screen leaves unused moves the character; every other key goes on to WoW untouched.
function overlay:OnScreenKey(key, binding, chord)
    chord = chord or overlay.Chord(key)
    local screen = self.screen
    if screen == "title" then
        -- The menus' accept, and nothing else.
        local go = overlay.MenuAction(key) == "accept"
        self.frame:SetPropagateKeyboardInput(not (go or self:Captures(chord, binding)))
        if go then
            self:ContinueTitle()
        end
        return true
    elseif screen == "menu" then
        return self:MenuKey(self.mainMenu, key, binding, chord)
    elseif not screen and self.statusOpen then
        return self:MenuKey(self.statusMenu, key, binding, chord)
    elseif screen == "start" or app.autopilot.InIntro(self.state) then
        -- On the way into the run and up to the portal, the run plays itself: the run's moves
        -- (keys.lua) and WoW's movement keys do nothing here.
        local move = overlay.KeyAction("run", chord)
        if MOVES[binding] or (move and move ~= "pause" and move ~= "restart") then
            self.frame:SetPropagateKeyboardInput(not self:Captures(chord, binding))
            return true
        end
    end
    return false
end

-- `menu` takes `key` if it is one of its actions; captured, the game's other keys stay too.
function overlay:MenuKey(menu, key, binding, chord)
    local action = overlay.MenuAction(key)
    if action and not menu:Takes(action) then
        action = nil
    end
    self.frame:SetPropagateKeyboardInput(not (action or self:Captures(chord or overlay.Chord(key), binding)))
    if action then
        menu:Input(action)
    end
    return true
end

-- The lobby's music while the title or the menu shows ("Title music"), if the client has it.
function overlay:PlayTitleMusic(on)
    on = (on and app.db.profile.music and PlayMusic and self.frame and self.frame:IsShown()) and true or false
    if on == (self.musicOn or false) then
        return
    end
    self.musicOn = on
    if on then
        PlayMusic(app.lobby.music)
    elseif StopMusic then
        StopMusic()
    end
end

-- Fades `sc[name]` toward shown or hidden by `step`; its alpha is kept in `sc.alpha`.
local function fade(sc, name, visible, step)
    local frame, alpha = sc[name], sc.alpha[name] or 0
    local target = visible and 1 or 0
    if alpha == target then
        return
    end
    alpha = target > alpha and math.min(target, alpha + step) or math.max(target, alpha - step)
    sc.alpha[name] = alpha
    frame:SetAlpha(alpha)
    frame:SetShown(alpha > 0)
end

-- The character at the lobby's fire, `seat.x` yards right of the road's middle at its start.
function overlay:PlaceSeat()
    local actor = self.seat
    if not actor then
        return
    elseif not self.seated then
        shapes.Hide(actor)
        return
    end
    if not actor:IsLoaded() then
        return
    end
    local lobby = app.lobby
    if self.seatAnimation ~= self.seatWant then
        actor:SetAnimation(self.seatWant, 0, 1, 0)
        self.seatAnimation = self.seatWant
    end
    local scale = self:TwinScale()
    local d = -self.state.distance
    actor:SetScale(scale)
    actor:SetYaw(math.rad(lobby.seat.yaw))
    -- The scene's y points left; an actor's position is scaled with it.
    actor:SetPosition((d + self.sceneRunner) / scale, -lobby.seat.x / scale, ground(d) / scale)
    shapes.Show(actor)
end

-- The way from the fire to the run's lane: `left` yards to the left, `ahead` yards ahead, and
-- how long it is.
local function approach(s)
    local seat = app.lobby.seat
    local left = (s.lane + seat.x / LANE) * LANE
    return left, seat.walk, math.sqrt(left * left + seat.walk * seat.walk)
end

-- The way into a run from the lobby, once a frame: the character stands up until its animation
-- ends; the twin takes its place, standing, and turns toward the run's lane; then it moves there
-- (StepApproach) while the camera glides behind it.
function overlay:StepStart(now)
    local seat, s = app.lobby.seat, self.state
    if self.startPhase == "stand" then
        if self.standDone or now >= self.standUntil then
            self.seated = false
            s.lateral = -seat.x / LANE
            local left, ahead = approach(s)
            self.twinYaw, self.twinFace = math.rad(seat.yaw), math.atan2(left, ahead)
            self.startPhase, self.turnUntil = "turn", now + seat.turnSeconds
        end
    elseif self.startPhase == "turn" and now >= self.turnUntil then
        self.startPhase, self.twinFace, self.walked = "walk", nil, 0
        self.shotName = nil
        self:StartGlide(app.lobby.glide.run)
        self:PlayTitleMusic(false)
    end
end

-- Once a step, after the movement is sampled: the twin moves from the fire to the run's lane at
-- the lobby's launch speed, running for its animation (overlay.lua's AnimateTwin). In the lane
-- the run starts, slow, and speeds up (simulation.lua's `launch`); up to the portal it plays
-- itself (autopilot.Intro).
function overlay:StepApproach(elapsed)
    if self.startPhase ~= "walk" then
        return
    end
    local s, speed = self.state, app.lobby.launch.speed
    local left, ahead, length = approach(s)
    local from = -app.lobby.seat.x / LANE
    self.walked = math.min(length, self.walked + speed * elapsed)
    local t = self.walked / length
    s.distance, s.lateral = ahead * t, from + (s.lane - from) * t
    local motion = self.motion or {}
    self.motion = motion
    motion.forward, motion.left, motion.speed = speed * ahead / length, speed * left / length, speed
    if t < 1 then
        return
    end
    self.screen, self.startPhase = nil, nil
    self.legendState = nil
    -- A custom game begun further into the seed ("Start at"): there at once, as a restart is.
    local at = app.db.profile.startAt or 0
    if at > 0 and s.custom then
        s = self:NewState(nil, s.seed, at)
        self.state = s
    end
    sim.Start(s)
    if self.watching then
        self.watching = nil
        self:SetAuto(true)
    end
end

-- The stand-up's end. The actor reports the end of every animation: only the stand-up's,
-- once it has played a moment, counts.
function overlay:OnSeatAnimFinished()
    if self.startPhase == "stand" and self.seatAnimation == app.lobby.seat.standUp then
        if GetTime() - self.standFrom > 0.2 then
            self.standDone = true
        end
    end
end

-- Once a frame: the way into a run, the fades, the prompt's flicker, the menu's choice and the
-- character at the fire.
function overlay:ShowScreens()
    local sc = self.screens
    local now = GetTime()
    local elapsed = now - (sc.time or now)
    sc.time = now
    if self.screen == "start" then
        self:StepStart(now)
    end
    local step = elapsed / FADE
    fade(sc, "title", self.screen == "title", step)
    fade(sc, "menu", self.screen == "menu", step)
    if self.screen == "title" then
        if not self.screenPrompt then
            self.screenPrompt = true
            -- The shown accept key (keys.lua: Key 1, or Gamepad 1 since a gamepad was used).
            local accept = overlay.ActionKey("accept", self:ShownSlot())
            sc.promptText:SetText(accept and ("Press " .. overlay.KeyText(accept) .. " to enter") or "Click to enter")
            sc.prompt:SetSize(sc.promptText:GetStringWidth() + 20, sc.promptText:GetStringHeight() + 10)
        end
        local pulse = (math.cos(2 * math.pi * now / PULSE) + 1) / 2
        sc.promptText:SetAlpha(PULSE_LOW + (1 - PULSE_LOW) * pulse)
    elseif self.screen == "menu" then
        self.mainMenu:Show()
    end
    self:PlaceSeat()
end
