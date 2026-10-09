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
local PAGES = {}
PAGES.play = {
    title = "Play",
    items = {
        {
            text = "Play",
            run = function(o)
                o:Play(false)
            end,
        },
        {
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
                -- From the hardest round to the easiest.
                wrap = function(o)
                    o:SetDifficulty(sim.DIFFICULTIES[1].id)
                end,
            },
        },
        -- The run's seed: a new random one with each new run from the lobby, R for another, or
        -- typed in.
        {
            text = "Seed",
            input = {
                get = function(o)
                    return tostring(o.state.seed)
                end,
                set = function(o, typed)
                    local seed = tonumber(typed)
                    if seed then
                        o:SetRunSeed(seed)
                    end
                end,
            },
        },
        {
            text = "Auto mode",
            run = function(o)
                o:Play(true)
            end,
        },
        { text = "Cancel", back = true },
    },
    extra = {
        text = "New seed",
        run = function(o)
            o:SetRunSeed(app.random.Seed())
        end,
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

-- The lobby's run, not started yet; a new one unless it is shown already.
function overlay:EnterLobby()
    local s = self.state
    if s.status ~= "ready" or not s.lobby then
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

-- The seed of the run about to start from the lobby. With a fixed seed (the options), it is the
-- fixed one too.
function overlay:SetRunSeed(seed)
    seed = app.random.Normalize(seed)
    if app.db.profile.seed then
        self:SetSeed(seed)
    else
        self.state = self:NewState(app.lobby, seed)
    end
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
-- The title goes on with the move-forward key, Enter or jump; the main menu and the pause and end
-- menu (messages.lua) take their actions' keys (menus.lua's MenuAction). Every other key goes on
-- to WoW untouched.
function overlay:OnScreenKey(key, binding)
    local screen = self.screen
    if screen == "title" then
        local go = key == "ENTER" or binding == "MOVEFORWARD" or binding == "JUMP"
        self.frame:SetPropagateKeyboardInput(not go)
        if go then
            self:ContinueTitle()
        end
        return true
    elseif screen == "menu" then
        return self:MenuKey(self.mainMenu, key, binding)
    elseif not screen and self.statusOpen then
        return self:MenuKey(self.statusMenu, key, binding)
    elseif screen == "start" or app.autopilot.InIntro(self.state) then
        -- On the way into the run and up to the portal, the run plays itself: the movement keys
        -- do nothing here.
        if MOVES[binding] then
            self.frame:SetPropagateKeyboardInput(not self.capture)
            return true
        end
    end
    return false
end

-- `menu` takes `key` if it is one of its actions; every other key goes on to WoW.
function overlay:MenuKey(menu, key, binding)
    local action = overlay.MenuAction(key, binding)
    if action and not menu:Takes(action) then
        action = nil
    end
    self.frame:SetPropagateKeyboardInput(action == nil)
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
    local scale = app.db.profile.overlay.twinScale / self.bodyScale
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
        local key = GetBindingKey("MOVEFORWARD")
        if self.screenPrompt ~= (key or false) then
            self.screenPrompt = key or false
            sc.promptText:SetText(
                key and string.format("Press %s / Enter to continue", GetBindingText(key) or key)
                    or "Press Enter to continue"
            )
            sc.prompt:SetSize(sc.promptText:GetStringWidth() + 20, sc.promptText:GetStringHeight() + 10)
        end
        local pulse = (math.cos(2 * math.pi * now / PULSE) + 1) / 2
        sc.promptText:SetAlpha(PULSE_LOW + (1 - PULSE_LOW) * pulse)
    elseif self.screen == "menu" then
        self.mainMenu:Show()
    end
    self:PlaceSeat()
end
