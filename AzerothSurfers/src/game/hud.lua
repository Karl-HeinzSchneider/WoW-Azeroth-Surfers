---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- One compact scorecard matching the keybind legend's dialog border. Score and multiplier
-- lead, coins and distance sit below; the streak remains beside the runner. Digit cells keep
-- counters steady and updates avoid allocating strings during a run.
local overlay = app.overlay

-- At scale 1 (full screen); the side window scales by SIDE_SCALE.
local HEIGHT, PAD, ICON = 32, 10, 18
local CARD_WIDTH, CARD_HEIGHT, INSET = 280, 116, 18
local SCORE_SIZE, MULTIPLIER_SIZE, COINS_SIZE = 28, 22, 18
-- Digits a panel always has room for: it widens only past them.
local SCORE_DIGITS, COINS_DIGITS = 6, 3
local MULTIPLIER_WIDTH = 70
local SIDE_SCALE = 0.75
-- Seconds between redraws of the running score.
local SCORE_EVERY = 0.05
-- The coin beside the coins: the run's coin model in a scene of its own, GEM pixels square,
-- spinning as the coins on the road do. Its camera's field of view (radians) and the room around
-- the model.
local GEM, GEM_FOV, GEM_MARGIN = 32, 0.5, 1.15
-- The gem fills a small part of its model's bounds (its glow reaches further): drawn this many
-- times as big as the bounds fitted to the scene.
local GEM_ZOOM = 2.5
-- The multiplier's gold, and its orange above 1.
local GOLD = { 1, 0.82, 0 }
local BOOST = { 1, 0.55, 0.1 }
-- The streak (the run's `scoring.streak`) beside the character: shown from STREAK_EARLY coins before it scores
-- more on, gold, orange once it does. Its bottom left corner STREAK_OFFSET pixels off the right
-- of the twin's square on the screen (overlay.lua's twinAnchor), centred on the character and a
-- little larger than it.
local STREAK_EARLY, STREAK_SIZE = 1, 20
local STREAK_OFFSET = { -10, 6 }
-- Its border is the dialog's (DialogBorderTemplate), whose corners are STREAK_CORNER pixels
-- square: the panel is never less than two corners high or wide, or they overlap. Drawn at
-- STREAK_SCALE, so the badge stays small with its border whole; STREAK_PAD (at that scale)
-- keeps the text clear of the corners' studs.
local STREAK_CORNER, STREAK_SCALE, STREAK_PAD = 32, 0.75, 20
local DIGITS = {}
for d = 0, 9 do
    DIGITS[d] = tostring(d)
end

local function panel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetHeight(HEIGHT)
    return p
end

local function text(parent, size)
    local t = parent:CreateFontString(nil, "OVERLAY")
    local path = GameFontNormalHuge and GameFontNormalHuge:GetFont()
    if path then
        t:SetFont(path, size, "OUTLINE")
    else
        t:SetFontObject(GameFontNormalHuge)
    end
    t:SetShadowColor(0, 0, 0, 0.9)
    t:SetShadowOffset(2, -2)
    t:SetTextColor(1, 1, 1)
    return t
end

-- Its camera looks along +x at the model in the middle. Lit evenly, day or night. Set up as the
-- twin's own scene was before it joined the world scene: its model on the scene's top layer, the
-- road's clip planes.
local function gem(parent)
    local scene = CreateFrame("ModelScene", nil, parent)
    scene:EnableMouse(false)
    scene:SetDrawLayer("OVERLAY")
    scene:SetCameraNearClip(overlay.CLIP_NEAR)
    scene:SetCameraFarClip(overlay.CLIP_FAR)
    scene:SetSize(GEM, GEM)
    scene:SetPoint("CENTER", parent, "LEFT", PAD + ICON / 2, 0)
    scene:SetCameraOrientationByYawPitchRoll(0, 0, 0)
    scene:SetCameraFieldOfView(GEM_FOV)
    scene:SetLightAmbientColor(0.8, 0.8, 0.8)
    scene:SetLightDiffuseColor(0.8, 0.8, 0.8)
    local actor = scene:CreateActor()
    actor:SetUseCenterForOrigin(true, true, true)
    actor:SetPosition(0, 0, 0)
    actor:Hide()
    return { scene = scene, actor = actor }
end

-- Right-aligned, one cell as wide as the widest digit per digit. `extra`: room left of the
-- digits (an icon).
local function counter(p, size, digits, extra)
    local c = { panel = p, size = size, digits = digits, extra = extra, cells = {}, shown = 0 }
    local probe = text(p, size)
    local width = 0
    for d = 0, 9 do
        probe:SetText(DIGITS[d])
        width = math.max(width, probe:GetStringWidth() or 0)
    end
    probe:Hide()
    c.width = math.ceil(width > 0 and width or size * 0.65) + 1
    return c
end

-- Creates cells only when `value` has more digits than ever.
local function show(c, value)
    local count = 0
    repeat
        count = count + 1
        local cell = c.cells[count]
        if not cell then
            cell = text(c.panel, c.size)
            -- Placed by its center and given no width: a text narrower than its glyph turns
            -- into "...", as a digit measured at one scale may be when drawn at another.
            cell:SetPoint("CENTER", c.panel, "RIGHT", -PAD - (count - 0.5) * c.width, 0)
            c.cells[count] = cell
        end
        cell:SetText(DIGITS[value % 10])
        cell:Show()
        value = math.floor(value / 10)
    until value == 0
    for i = count + 1, c.shown do
        c.cells[i]:Hide()
    end
    if count ~= c.shown then
        c.shown = count
        c.panel:SetWidth(math.max(count, c.digits) * c.width + 2 * PAD + c.extra)
    end
end

function overlay:CreateHud(f)
    local hud = CreateFrame("Frame", nil, f)
    self:Stack(hud, "hud")
    hud:SetSize(1, 1)
    hud:Hide()

    local card = CreateFrame("Frame", nil, hud, "DialogBorderTemplate")
    -- Anchored by its position's corner (PlaceHud).
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", INSET, -14)
    label:SetText("SCORE")
    label:SetTextColor(0.72, 0.68, 0.58)

    local scorePanel = panel(card)
    scorePanel:SetPoint("TOPLEFT", INSET - PAD, -31)

    local multiplierPanel = panel(card)
    multiplierPanel:SetPoint("TOPRIGHT", -INSET, -31)
    multiplierPanel:SetWidth(MULTIPLIER_WIDTH)
    local multiplier = text(multiplierPanel, MULTIPLIER_SIZE)
    multiplier:SetPoint("RIGHT", 0, 0)

    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Common\\UI-TooltipDivider")
    divider:SetPoint("TOPLEFT", INSET - 4, -70)
    divider:SetPoint("TOPRIGHT", -INSET + 4, -70)
    divider:SetHeight(8)

    local coinPanel = panel(card)
    coinPanel:SetHeight(24)
    coinPanel:SetPoint("BOTTOMLEFT", INSET - PAD, 13)
    local coin = gem(coinPanel)
    local distance = text(card, 15)
    distance:SetPoint("BOTTOMRIGHT", -INSET, 18)
    distance:SetTextColor(0.78, 0.78, 0.78)

    -- Follows the twin's square, which follows the character on screen.
    local streakPanel = CreateFrame("Frame", nil, hud, "DialogBorderTemplate")
    streakPanel:ClearAllPoints()
    streakPanel:SetScale(STREAK_SCALE)
    streakPanel:SetSize(2 * STREAK_CORNER, 2 * STREAK_CORNER)
    -- Its offsets are in its own scale.
    streakPanel:SetPoint(
        "BOTTOMLEFT",
        self.twinAnchor,
        "RIGHT",
        STREAK_OFFSET[1] / STREAK_SCALE,
        STREAK_OFFSET[2] / STREAK_SCALE
    )
    streakPanel:Hide()
    local streak = text(streakPanel, STREAK_SIZE / STREAK_SCALE)
    streak:SetPoint("CENTER")

    self.hud = {
        frame = hud,
        card = card,
        distance = distance,
        multiplierPanel = multiplierPanel,
        score = counter(scorePanel, SCORE_SIZE, SCORE_DIGITS, 0),
        coins = counter(coinPanel, COINS_SIZE, COINS_DIGITS, ICON + 14),
        multiplier = multiplier,
        gem = coin,
        streakPanel = streakPanel,
        streak = streak,
    }
    self:CreateChallengeCard(card)
end

-- Where the scorecard may sit (profile.hud.position), each by its corner that stays put as the
-- card widens. "menu" is full screen only: the card's top left beside the pause and end menus'
-- top right, MENU_GAP pixels apart; in the side window it is "topright".
local POSITIONS = { menu = "TOPLEFT", topright = "TOPRIGHT", top = "TOP", topleft = "TOPLEFT" }
local MENU_GAP = 12
-- From the view's edges; "top" under the buttons' row (window.lua's controls) at the centre.
local EDGE, UNDER_BUTTONS = 16, 48

-- `top`: where the view's free area starts, under a full-screen frame's title bar. Sets
-- `hudPosition`, the position used (PlaceLegend keeps clear of it).
function overlay:PlaceHud(side, top)
    local hud, saved = self.hud.frame, app.db.profile.hud
    local position = POSITIONS[saved.position] and saved.position or "menu"
    if side and position == "menu" then
        position = "topright"
    end
    self.hudPosition = position
    local point, scale = POSITIONS[position], side and SIDE_SCALE or 1
    hud:SetScale(scale)
    hud:ClearAllPoints()
    self.hud.card:ClearAllPoints()
    self.hud.card:SetPoint(point)
    -- Offsets count in the display's own scale.
    local x, y = saved.x / scale, saved.y / scale
    if position == "menu" then
        hud:SetPoint(point, self.statusMenu.panel, "TOPRIGHT", MENU_GAP + x, y)
        return
    end
    -- Under the buttons' row, if any.
    local edge = side and 8 or EDGE
    local below = top - (side and (self.framed and 8 or 40) or (position == "top" and UNDER_BUTTONS or EDGE))
    if position == "top" then
        edge = 0
    elseif position == "topright" then
        edge = -edge
    end
    hud:SetPoint(point, self.frame, point, edge / scale + x, below / scale + y)
end

-- Once a frame: numbers redrawn only when they change (no strings built), and the coin's spin.
function overlay:ShowHud()
    local s, hud = self.state, self.hud
    local shown = self.hudShown or {}
    self.hudShown = shown
    local visible = s.status ~= "ready"
    if shown.visible ~= visible then
        shown.visible = visible
        hud.frame:SetShown(visible)
    end
    if not visible then
        return
    end
    local now = GetTime()
    local score = sim.Score(s)
    if shown.score ~= score and (s.status ~= "running" or not shown.scoreAt or now - shown.scoreAt >= SCORE_EVERY) then
        shown.score, shown.scoreAt = score, now
        show(hud.score, score)
    end
    if shown.coins ~= s.coins then
        shown.coins = s.coins
        show(hud.coins, s.coins)
    end
    if shown.multiplier ~= s.multiplier then
        shown.multiplier = s.multiplier
        hud.multiplier:SetFormattedText("x%d", s.multiplier)
        local color = s.multiplier > 1 and BOOST or GOLD
        hud.multiplier:SetTextColor(color[1], color[2], color[3])
    end
    local distance = math.floor(sim.Run(s))
    if shown.distance ~= distance then
        shown.distance = distance
        -- A challenge's: and the yards to its last portal.
        if s.finish then
            hud.distance:SetFormattedText("%d / %d yd", distance, s.finish - s.start)
        else
            hud.distance:SetFormattedText("%d yd", distance)
        end
    end
    if shown.layoutScore ~= hud.score.shown or shown.layoutMultiplier ~= s.multiplier then
        shown.layoutScore, shown.layoutMultiplier = hud.score.shown, s.multiplier
        local multiplierWidth = math.max(MULTIPLIER_WIDTH, (hud.multiplier:GetStringWidth() or 0) + PAD)
        hud.multiplierPanel:SetWidth(multiplierWidth)
        hud.card:SetWidth(math.max(CARD_WIDTH, hud.score.panel:GetWidth() + multiplierWidth + 2 * INSET + 12))
    end
    local shownFrom = math.max(1, s.scoring.streak.from - STREAK_EARLY)
    local streak = s.status == "running" and s.streak >= shownFrom and s.streak or 0
    if shown.streak ~= streak then
        shown.streak = streak
        hud.streakPanel:SetShown(streak > 0)
        if streak > 0 then
            hud.streak:SetFormattedText("Streak %d", streak)
            local color = streak >= s.scoring.streak.from and BOOST or GOLD
            hud.streak:SetTextColor(color[1], color[2], color[3])
            local width = (hud.streak:GetStringWidth() or 0) + 2 * STREAK_PAD
            hud.streakPanel:SetWidth(math.max(2 * STREAK_CORNER, width))
        end
    end
    self:ShowChallengeCard(shown, now)
    self:ShowHudCoin(shown, now)
end

-- The run's coin model (overlay.lua's LoadCoinModel), measured in its own actor once loaded:
-- scaled to GEM_ZOOM, the camera as far as a side of 1 fills the scene.
function overlay:ShowHudCoin(shown, now)
    local coin = self.hud.gem
    local entry = self.coinReady and self.biome.coin.models[self.coinModel]
    local model = entry and entry.model or false
    local actor = coin.actor
    if shown.coinModel ~= model then
        shown.coinModel, shown.coinFitted, shown.coinSince = model, false, now
        -- Actors have Show and Hide, no SetShown.
        if not model then
            actor:Hide()
            return
        end
        actor:Show()
        actor:SetScale(1)
        actor:SetPitch(self.coinPitch or 0)
        actor:SetModelByFileID(model)
        local distance = 0.5 / math.tan(GEM_FOV / 2) * GEM_MARGIN
        coin.scene:SetCameraPosition(-distance, 0, 0)
        app.logger:debug("Scorecard coin: model %d", model)
    end
    if not model then
        return
    end
    if not shown.coinFitted then
        local minX, minY, minZ, maxX, maxY, maxZ = overlay.Extents(actor)
        local size = minX and math.max(maxX - minX, maxY - minY, maxZ - minZ) or 0
        if size > 0.001 then
            shown.coinFitted = true
            actor:SetScale(GEM_ZOOM / size)
            app.logger:debug("Scorecard coin: loaded, size %.3f", size)
        elseif now - shown.coinSince > 3 then
            shown.coinFitted = true
            app.logger:debug("Scorecard coin: model %d did not load", model)
        end
    end
    actor:SetYaw(now * 3)
end

-- The challenge card: under the scorecard while a challenge runs (challenges.lua), as wide as
-- it, CHALLENGE_GAP pixels below. Its period, goal, difficulty and time to the reset, its best
-- and the live target: ahead or behind the best's score at the same distance
-- (challenges.Target, from the checkpoints saved with the best).
local CHALLENGE_HEIGHT, CHALLENGE_GAP, ROW = 174, 6, 21
local LABEL = { 0.72, 0.68, 0.58 }
local AHEAD = { 0.25, 1, 0.35 }
local BEHIND = { 1, 0.3, 0.25 }
local QUIET = { 0.78, 0.78, 0.78 }
local DAY = 86400

-- A label on the left and its value on the right, centred `y` pixels under the card's top.
local function row(card, y, name, size)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", card, "TOPLEFT", INSET, -y)
    label:SetText(name)
    label:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    local value = text(card, size or 15)
    value:SetPoint("RIGHT", card, "TOPRIGHT", -INSET, -y)
    return value
end

function overlay:CreateChallengeCard(scorecard)
    local card = CreateFrame("Frame", nil, self.hud.frame, "DialogBorderTemplate")
    -- The template fills its parent: only under the scorecard.
    card:ClearAllPoints()
    card:SetHeight(CHALLENGE_HEIGHT)
    card:SetPoint("TOPLEFT", scorecard, "BOTTOMLEFT", 0, -CHALLENGE_GAP)
    card:SetPoint("TOPRIGHT", scorecard, "BOTTOMRIGHT", 0, -CHALLENGE_GAP)
    card:Hide()
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", INSET, -14)
    title:SetTextColor(LABEL[1], LABEL[2], LABEL[3])
    local period = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    period:SetPoint("TOPRIGHT", -INSET, -14)
    period:SetTextColor(QUIET[1], QUIET[2], QUIET[3])

    local first = 42
    local goal = row(card, first, "Goal")
    local difficulty = row(card, first + ROW, "Difficulty")
    local resets = row(card, first + 2 * ROW, "Resets in")
    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Common\\UI-TooltipDivider")
    divider:SetPoint("TOPLEFT", INSET - 4, -(first + 2.5 * ROW + 2))
    divider:SetPoint("TOPRIGHT", -INSET + 4, -(first + 2.5 * ROW + 2))
    divider:SetHeight(8)
    local best = row(card, first + 3.5 * ROW + 4, "Best")
    best:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local target = row(card, first + 4.5 * ROW + 10, "Target", 18)

    self.hud.challenge = {
        card = card,
        title = title,
        period = period,
        goal = goal,
        difficulty = difficulty,
        resets = resets,
        best = best,
        target = target,
    }
end

-- Room the challenge card takes under the scorecard, at the scorecard's scale: none without it.
-- PlaceLegend keeps clear of it.
function overlay:ChallengeCardRoom()
    return self.hud.challenge.card:IsShown() and CHALLENGE_HEIGHT + CHALLENGE_GAP or 0
end

local function color(t, c)
    t:SetTextColor(c[1], c[2], c[3])
end

-- Once a frame from ShowHud: what a run keeps written once when it begins, the time left once a
-- minute, the target as often as the score.
function overlay:ShowChallengeCard(shown, now)
    local s, c = self.state, self.hud.challenge
    local period = s.challenge
    if shown.challenge ~= period then
        shown.challenge, shown.challengeBest = period, nil
        c.card:SetShown(period ~= nil)
        -- The legend under the scorecard moves down or back up.
        self:PlaceLegend()
        if period then
            c.title:SetText(string.upper(period.kind.name .. " challenge"))
            c.period:SetText(period.label)
            c.goal:SetFormattedText("%d yd", period.goal)
            local difficulty = sim.DIFFICULTIES[period.difficulty]
            c.difficulty:SetText(difficulty and difficulty.name or period.difficulty)
            shown.challengeLeft, shown.challengeTarget, shown.challengeAt = nil, nil, nil
        end
    end
    if not period then
        return
    end
    -- Before the run begins: the best it chases; past it, no change until a restart.
    if shown.challengeBest ~= s.target then
        shown.challengeBest, shown.challengeTarget = s.target, nil
        if s.target then
            c.best:SetFormattedText("%d", s.target.score)
        else
            c.best:SetText("None yet")
        end
    end
    local left = math.max(0, period.ends - app.challenges.Now())
    local minutes = math.floor(left / 60)
    if shown.challengeLeft ~= minutes then
        shown.challengeLeft = minutes
        local days, hours = math.floor(left / DAY), math.floor(left % DAY / 3600)
        if left <= 0 then
            c.resets:SetText("Now")
        elseif days > 0 then
            c.resets:SetFormattedText("%dd %dh", days, hours)
        elseif hours > 0 then
            c.resets:SetFormattedText("%dh %dm", hours, minutes % 60)
        else
            c.resets:SetFormattedText("%dm", math.max(1, minutes))
        end
    end
    if shown.challengeAt and s.status == "running" and now - shown.challengeAt < SCORE_EVERY then
        return
    end
    shown.challengeAt = now
    self:ShowChallengeTarget(s, shown, c.target)
end

-- Ahead or behind the best's score at this distance; "+0" while even.
function overlay:ShowChallengeTarget(s, shown, target)
    local best = s.target
    -- A number for each state, so nothing is written again while it holds: -1 none yet, -2 no
    -- checkpoints saved with the best, -3 past where the best ended, else the gap's sign and
    -- size (2 * |gap| + 4, + 1 behind).
    local key, gap
    if not best then
        key = -1
    elseif not best.trace then
        key = -2
    else
        local at = app.challenges.Target(best, sim.Run(s))
        if not at then
            key = -3
        else
            gap = sim.Score(s) - at
            key = 2 * math.abs(gap) + 4 + (gap < 0 and 1 or 0)
        end
    end
    if shown.challengeTarget == key then
        return
    end
    shown.challengeTarget = key
    if key == -1 then
        target:SetText("Set one")
        color(target, QUIET)
    elseif key == -2 then
        target:SetFormattedText("Beat %d", best.score)
        color(target, QUIET)
    elseif key == -3 then
        target:SetText("Past your best")
        color(target, AHEAD)
    elseif gap < 0 then
        target:SetFormattedText("Behind %d", -gap)
        color(target, BEHIND)
    else
        target:SetFormattedText("Ahead +%d", gap)
        color(target, AHEAD)
    end
end
