---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- One compact scorecard matching the keybind legend's dialog border. Score and multiplier
-- lead, coins and distance sit below; the streak remains beside the runner. Digit cells keep
-- counters steady and updates avoid allocating strings during a run.
local overlay = app.overlay

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
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
-- The star's pop when the multiplier goes up: seconds, and growth.
local POP, POP_GROW = 0.3, 0.4
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

local function icon(parent, texture)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(texture)
    t:SetSize(ICON, ICON)
    t:SetPoint("CENTER", parent, "LEFT", PAD + ICON / 2, 0)
    return t
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
    card:ClearAllPoints()
    card:SetPoint("TOPRIGHT")
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
    local star = icon(multiplierPanel, STAR)
    local multiplier = text(multiplierPanel, MULTIPLIER_SIZE)
    multiplier:SetPoint("LEFT", PAD + ICON + 4, 0)

    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Common\\UI-TooltipDivider")
    divider:SetPoint("TOPLEFT", INSET - 4, -70)
    divider:SetPoint("TOPRIGHT", -INSET + 4, -70)
    divider:SetHeight(8)

    local coinPanel = panel(card)
    coinPanel:SetHeight(24)
    coinPanel:SetPoint("BOTTOMLEFT", INSET - PAD, 13)
    icon(coinPanel, COIN)
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
        star = star,
        streakPanel = streakPanel,
        streak = streak,
    }
end

-- `top`: where the view's free area starts, under a full-screen frame's title bar.
function overlay:PlaceHud(side, w, h, top)
    local hud = self.hud.frame
    hud:ClearAllPoints()
    if side then
        hud:SetScale(SIDE_SCALE)
        -- Under the buttons' row, if any; offsets count in the display's own scale.
        local y = top - (self.framed and 8 or 40)
        hud:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8 / SIDE_SCALE, y / SIDE_SCALE)
    else
        hud:SetScale(1)
        -- Keep the score in the player's field of view, right of the road above the horizon.
        local x = math.min(0.62 * h, w / 2 - 16)
        local y = math.min(0.36 * h, h / 2 + top - 48)
        hud:SetPoint("TOPRIGHT", self.frame, "CENTER", x, y)
    end
end

-- Once a frame: numbers redrawn only when they change (no strings built), and the star's pop.
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
        -- A new run starts at x1 without a pop.
        if shown.multiplier and s.multiplier > shown.multiplier then
            shown.starPop = now
        end
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
        local multiplierWidth = math.max(MULTIPLIER_WIDTH, (hud.multiplier:GetStringWidth() or 0) + PAD + ICON + 4)
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
    local since = shown.starPop and now - shown.starPop
    if since then
        local size = ICON
        if since < POP then
            size = ICON * (1 + POP_GROW * math.sin(math.pi * since / POP))
        else
            shown.starPop = nil
        end
        hud.star:SetSize(size, size)
    end
end
