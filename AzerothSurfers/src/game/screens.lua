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
-- Pixels at scale 1: the title screen's name and credit, the menu's, its items.
local TITLE_SIZE, CREDIT_SIZE = 78, 20
local MENU_TITLE_SIZE, MENU_CREDIT_SIZE, ITEM_SIZE = 42, 14, 28
local ITEM_HEIGHT, MENU_WIDTH, MARKER = 42, 360, 30
local VALUE_WIDTH, ARROW_SIZE = 110, 28
-- The side window shows them smaller.
local TITLE_SIDE_SCALE, PROMPT_SIDE_SCALE, MENU_SIDE_SCALE = 0.5, 0.7, 0.6
-- The prompt's flicker: seconds per pulse, and its faintest.
local PULSE, PULSE_LOW = 1.4, 0.2
-- Seconds the title fades out and the menu in.
local FADE = 0.5
local GOLD = { 1, 0.82, 0 }
local CREAM = { 1, 0.9294, 0.7607 }
local WHITE = { 1, 1, 1 }
-- The login screen's arrow in front of the chosen item; the spell book's page arrows beside the
-- difficulty.
local MARKER_ART = "Interface\\Glues\\Common\\Glue-RightArrow-Button-Up"
local ARROWS = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Interface\\Buttons\\UI-SpellbookIcon-NextPage" }
local ITEMS = {
    { act = "play", text = "Play" },
    { act = "difficulty", text = "Difficulty" },
    { act = "watch", text = "Watch" },
    { act = "settings", text = "Settings" },
    { act = "close", text = "Close" },
}
local DIFFICULTY = 2
-- A shot's fields (overlay.lua's RunShot), in a fixed order.
local FIELDS = { "at", "side", "height", "pitch", "fov" }

local function text(parent, size, color)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFontObject(GameFontNormalHuge)
    t:SetFont(FONT, size, "OUTLINE")
    t:SetShadowColor(0, 0, 0, 1)
    t:SetShadowOffset(2, -2)
    t:SetTextColor(color[1], color[2], color[3])
    return t
end

local function arrow(o, parent, art, step)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ARROW_SIZE, ARROW_SIZE)
    button:SetNormalTexture(art .. "-Up")
    button:SetPushedTexture(art .. "-Down")
    button:SetDisabledTexture(art .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        o:StepDifficulty(step)
    end)
    return button
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

    -- The menu: a smaller name and the items under it.
    local menu = CreateFrame("Frame", nil, f)
    self:Stack(menu, "screens")
    menu:SetSize(MENU_WIDTH, 1)
    menu:SetAlpha(0)
    menu:Hide()
    local menuName = text(menu, MENU_TITLE_SIZE, GOLD)
    menuName:SetPoint("TOPLEFT")
    menuName:SetText(app.TITLE)
    local menuCredit = text(menu, MENU_CREDIT_SIZE, CREAM)
    menuCredit:SetPoint("TOPLEFT", menuName, "BOTTOMLEFT", 2, -2)
    menuCredit:SetText(CREDIT)
    local top = -(MENU_TITLE_SIZE + MENU_CREDIT_SIZE + 36)
    local items = {}
    for i, spec in ipairs(ITEMS) do
        local button = CreateFrame("Button", nil, menu)
        button:SetSize(MENU_WIDTH, ITEM_HEIGHT)
        button:SetPoint("TOPLEFT", 0, top - (i - 1) * ITEM_HEIGHT)
        local label = text(button, ITEM_SIZE, GOLD)
        label:SetPoint("LEFT", MARKER + 8, 0)
        label:SetText(spec.text)
        button:SetScript("OnEnter", function()
            self:SelectItem(i)
        end)
        button:SetScript("OnClick", function()
            self:ChooseItem(i)
        end)
        items[i] = { button = button, label = label }
    end
    menu:SetHeight(-top + #ITEMS * ITEM_HEIGHT)
    local marker = menu:CreateTexture(nil, "ARTWORK")
    marker:SetTexture(MARKER_ART)
    marker:SetSize(MARKER, MARKER)
    -- The difficulty's value between its arrows, right of its label.
    local row = items[DIFFICULTY]
    local easier, harder = arrow(self, row.button, ARROWS[1], -1), arrow(self, row.button, ARROWS[2], 1)
    easier:SetPoint("LEFT", row.label, "RIGHT", 12, 0)
    local value = text(row.button, ITEM_SIZE - 4, WHITE)
    value:SetWidth(VALUE_WIDTH)
    value:SetPoint("LEFT", easier, "RIGHT", 2, 0)
    harder:SetPoint("LEFT", value, "RIGHT", 2, 0)

    self.screens = {
        title = title,
        banner = banner,
        prompt = prompt,
        promptText = promptText,
        menu = menu,
        items = items,
        marker = marker,
        easier = easier,
        harder = harder,
        value = value,
        alpha = {},
    }
    self.selected = 1

    -- The character at the fire: an actor of the world scene, so the fire and the models in
    -- front of it cover it. Placed by its origin, at its feet.
    if not self.worldScene then
        return
    end
    local seat = self.worldScene:CreateActor()
    seat:SetUseCenterForOrigin(false, false, false)
    seat:Hide()
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
    self.standUntil, self.watching = nil, nil
    self.selected = self.selected or 1
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
    self:PlayTitleMusic(true)
end

function overlay:ContinueTitle()
    if self.screen == "title" then
        self:OpenMenu()
    end
end

-- The character stands up, then the camera glides behind it and the run starts; `watch`: in
-- auto mode.
function overlay:Play(watch)
    if self.screen ~= "title" and self.screen ~= "menu" then
        return
    end
    local seat = app.lobby.seat
    self.screen, self.watching = "start", watch or nil
    self.seatWant, self.standUntil = seat.standUp, GetTime() + seat.standUpSeconds
    self.legendState = nil
end

function overlay:SelectItem(i)
    self.selected = (i - 1) % #ITEMS + 1
end

function overlay:ChooseItem(i)
    self:SelectItem(i)
    local act = ITEMS[self.selected].act
    if act == "play" then
        self:Play(false)
    elseif act == "watch" then
        self:Play(true)
    elseif act == "difficulty" then
        -- Round from the hardest to the easiest.
        local current = sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
        local other = sim.DIFFICULTIES[current.level % #sim.DIFFICULTIES + 1]
        self:SetDifficulty(other.id)
    elseif act == "settings" then
        app.options:Open()
    elseif act == "close" then
        self.frame:Hide()
    end
end

-- The menu's and the title's keys: the movement keys and Enter, which then do nothing else.
-- True when `key` was one of them.
function overlay:OnScreenKey(key, binding)
    local screen = self.screen
    if screen == "title" then
        if key == "ENTER" or binding == "MOVEFORWARD" or binding == "JUMP" then
            self.frame:SetPropagateKeyboardInput(false)
            self:ContinueTitle()
            return true
        end
    elseif screen == "menu" then
        local up = key == "UP" or binding == "MOVEFORWARD"
        local down = key == "DOWN" or binding == "MOVEBACKWARD"
        local left = key == "LEFT" or binding == "TURNLEFT" or binding == "STRAFELEFT"
        local right = key == "RIGHT" or binding == "TURNRIGHT" or binding == "STRAFERIGHT"
        local choose = key == "ENTER" or binding == "JUMP"
        if not (up or down or left or right or choose) then
            return false
        end
        self.frame:SetPropagateKeyboardInput(false)
        if up or down then
            self:SelectItem(self.selected + (up and -1 or 1))
        elseif left or right then
            if self.selected == DIFFICULTY then
                self:StepDifficulty(left and -1 or 1)
            end
        else
            self:ChooseItem(self.selected)
        end
        return true
    elseif screen == "start" then
        -- On the way into the run: the run starts by itself once the camera is behind the
        -- character, not by a key.
        if binding == "MOVEFORWARD" or binding == "JUMP" then
            self.frame:SetPropagateKeyboardInput(not self.capture)
            return true
        end
    end
    return false
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

-- Of the walk from the fire to the lane, how much goes ahead: the twin turns toward the lane,
-- not quite sideways.
local WALK_AHEAD = 0.3

-- On the way into a run from the lobby, once a step after the movement is sampled: the twin
-- walks from the fire to the run's lane while the camera glides behind it, and walks for its
-- animation (overlay.lua's AnimateTwin).
function overlay:StepWalk()
    local glide, s, from = self.glide, self.state, self.walkFrom
    if not from or not glide then
        return
    end
    local t = math.min(1, (GetTime() - glide.start) / glide.seconds)
    s.lateral = from + (s.lane - from) * t
    -- Positive lanes are on the left, as is positive `left`.
    local speed = (s.lane - from) * LANE / glide.seconds
    local motion = self.motion or {}
    self.motion = motion
    motion.left, motion.forward = speed, math.abs(speed) * WALK_AHEAD
    motion.speed = math.abs(speed) * math.sqrt(1 + WALK_AHEAD * WALK_AHEAD)
end

-- Once a frame: the way into a run, the fades, the prompt's flicker, the menu's choice and the
-- character at the fire.
function overlay:ShowScreens()
    local sc = self.screens
    local now = GetTime()
    local elapsed = now - (sc.time or now)
    sc.time = now
    if self.screen == "start" then
        if self.standUntil then
            if now >= self.standUntil then
                -- The twin takes the character's place, as it stands, and walks over to the run's
                -- lane while the camera goes behind it (StepWalk).
                local seat = app.lobby.seat
                self.standUntil, self.seated = nil, false
                self.walkFrom, self.state.lateral = -seat.x / LANE, -seat.x / LANE
                self.twinYaw = math.rad(seat.yaw)
                self.shotName = nil
                self:StartGlide(app.lobby.glide.run)
                self:PlayTitleMusic(false)
            end
        elseif not self.glide then
            -- In the lane, whatever the last frame's step left.
            local s = self.state
            s.lateral, self.walkFrom = s.lane, nil
            self.screen = nil
            self.legendState = nil
            if self.watching then
                self.watching = nil
                self:SetAuto(true)
            else
                sim.Start(self.state)
            end
        end
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
        self:ShowMenuChoice()
    end
    self:PlaceSeat()
end

-- The chosen item white behind the marker, the others gold; the difficulty's value.
function overlay:ShowMenuChoice()
    local sc = self.screens
    local difficulty = sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
    if sc.shownChoice == self.selected and sc.shownDifficulty == difficulty then
        return
    end
    sc.shownChoice, sc.shownDifficulty = self.selected, difficulty
    for i, item in ipairs(sc.items) do
        local color = i == self.selected and WHITE or GOLD
        item.label:SetTextColor(color[1], color[2], color[3])
    end
    sc.marker:ClearAllPoints()
    sc.marker:SetPoint("LEFT", sc.items[self.selected].button, "LEFT", 0, 0)
    sc.value:SetText(difficulty.name)
    sc.easier:SetEnabled(difficulty.level > 1)
    sc.harder:SetEnabled(difficulty.level < #sim.DIFFICULTIES)
end
