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
local GEM, GEM_FOV, GEM_MARGIN = 30, 0.5, 1.15
-- The multiplier's gold, and its orange above 1.
local GOLD = { 1, 0.82, 0 }
local BOOST = { 1, 0.55, 0.1 }
-- The streak (sim.STREAK) beside the character: shown from STREAK_EARLY coins before it scores
-- more on, gold, orange once it does. Its bottom left corner STREAK_OFFSET pixels off the right
-- of the twin's square on the screen (overlay.lua's twinAnchor), centred on the character and a
-- little larger than it.
local STREAK_EARLY, STREAK_SIZE = 1, 20
local STREAK_HEIGHT = 32
local STREAK_OFFSET = { -10, 6 }
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

-- Its camera looks along +x at the model in the middle. Lit evenly, day or night.
local function gem(parent)
    local scene = CreateFrame("ModelScene", nil, parent)
    scene:EnableMouse(false)
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
    streakPanel:SetHeight(STREAK_HEIGHT)
    streakPanel:SetPoint("BOTTOMLEFT", self.twinAnchor, "RIGHT", STREAK_OFFSET[1], STREAK_OFFSET[2])
    streakPanel:Hide()
    local streak = text(streakPanel, STREAK_SIZE)
    streak:SetPoint("CENTER")

    self.hud = {
        frame = hud,
        card = card,
        distance = distance,
        multiplierPanel = multiplierPanel,
        score = counter(scorePanel, SCORE_SIZE, SCORE_DIGITS, 0),
        coins = counter(coinPanel, COINS_SIZE, COINS_DIGITS, ICON + 8),
        multiplier = multiplier,
        gem = coin,
        streakPanel = streakPanel,
        streak = streak,
    }
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
        hud.distance:SetFormattedText("%d yd", distance)
    end
    if shown.layoutScore ~= hud.score.shown or shown.layoutMultiplier ~= s.multiplier then
        shown.layoutScore, shown.layoutMultiplier = hud.score.shown, s.multiplier
        local multiplierWidth = math.max(MULTIPLIER_WIDTH, (hud.multiplier:GetStringWidth() or 0) + PAD)
        hud.multiplierPanel:SetWidth(multiplierWidth)
        hud.card:SetWidth(math.max(CARD_WIDTH, hud.score.panel:GetWidth() + multiplierWidth + 2 * INSET + 12))
    end
    local shownFrom = math.max(1, sim.STREAK.from - STREAK_EARLY)
    local streak = s.status == "running" and s.streak >= shownFrom and s.streak or 0
    if shown.streak ~= streak then
        shown.streak = streak
        hud.streakPanel:SetShown(streak > 0)
        if streak > 0 then
            hud.streak:SetFormattedText("Streak %d", streak)
            local color = streak >= sim.STREAK.from and BOOST or GOLD
            hud.streak:SetTextColor(color[1], color[2], color[3])
            hud.streakPanel:SetWidth((hud.streak:GetStringWidth() or 0) + 2 * PAD)
        end
    end
    self:ShowHudCoin(shown, now)
end

-- The run's coin model once overlay.lua has fitted it (LoadCoinModel), the camera as far as the
-- coin's size fills the scene. The near clip just short of the coin keeps its depth below the
-- world scene's (the 3D scenes share the depth buffer): nothing of the road hides it.
function overlay:ShowHudCoin(shown, now)
    local coin = self.hud.gem
    local entry = self.coinReady and self.biome.coin.models[self.coinModel]
    local model = entry and entry.model or false
    if shown.coinModel ~= model or shown.coinScale ~= self.coinScale then
        shown.coinModel, shown.coinScale = model, self.coinScale
        -- Actors have Show and Hide, no SetShown.
        if not model then
            coin.actor:Hide()
        else
            coin.actor:Show()
            coin.actor:SetModelByFileID(model)
            coin.actor:SetScale(self.coinScale)
            coin.actor:SetPitch(self.coinPitch)
            local size = self.coinSize
            local distance = size / 2 / math.tan(GEM_FOV / 2) * GEM_MARGIN
            coin.scene:SetCameraPosition(-distance, 0, 0)
            coin.scene:SetCameraNearClip(math.max(0.01, distance - size))
            coin.scene:SetCameraFarClip(overlay.CLIP_FAR)
        end
    end
    if model then
        coin.actor:SetYaw(now * 3)
    end
end
