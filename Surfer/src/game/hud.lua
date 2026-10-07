---@type string, Surfer
local _, app = ...
local sim = app.simulation
-- The heads-up display, added to the view that overlay.lua creates: bright numbers on dark,
-- see-through panels next to the road. The score panel with the multiplier's panel (a star and
-- "x1") in front of it, the coins under it. Full screen it stands right of the road's far end,
-- above the horizon; in the side window in its top right corner, under the buttons. Shown
-- while a run is on (running, paused, over), not on the start dialog.
--
-- It is meant to be read at a glance while running, so it holds still: every digit has a cell
-- of the same width (no number shifts when a digit changes), a panel only widens when its
-- number gets a digit more, and the score is redrawn a few times a second, not every frame.
local overlay = app.overlay

-- The classic tooltip's background and border, tinted dark: a soft, rounded panel.
local PANEL = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local PANEL_ALPHA = 0.55
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
-- Sizes at scale 1 (full screen); the side window scales the whole display (SIDE_SCALE).
local HEIGHT, GAP, PAD, ICON = 40, 5, 10, 24
local SCORE_SIZE, MULTIPLIER_SIZE, COINS_SIZE = 26, 22, 22
-- Digits a panel always has room for: it widens only past them.
local SCORE_DIGITS, COINS_DIGITS = 6, 3
local MULTIPLIER_WIDTH = 70
local SIDE_SCALE = 0.75
-- Seconds between redraws of the running score; a finished or paused one is exact at once.
local SCORE_EVERY = 0.125
-- Seconds the star pops (grows and shrinks back) when the multiplier goes up, and by how much.
local POP, POP_GROW = 0.3, 0.4
-- The multiplier's gold, and the brighter orange it turns while above 1.
local GOLD = { 1, 0.82, 0 }
local BOOST = { 1, 0.55, 0.1 }
local DIGITS = {}
for d = 0, 9 do
    DIGITS[d] = tostring(d)
end

local function panel(parent)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetBackdrop(PANEL)
    p:SetBackdropColor(0, 0, 0, PANEL_ALPHA)
    p:SetBackdropBorderColor(0, 0, 0, PANEL_ALPHA)
    p:SetHeight(HEIGHT)
    return p
end

-- Bright text in the game's UI font (Friz Quadrata), outlined, with a shadow.
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

-- A whole number in `p`, right-aligned, one digit per cell; the cell is as wide as the widest
-- digit, so no digit moves when another changes. `extra` is the room left of the digits (an
-- icon).
local function counter(p, size, digits, extra)
    local c = { panel = p, size = size, digits = digits, extra = extra, cells = {}, shown = 0 }
    local probe = text(p, size)
    local width = 0
    for d = 0, 9 do
        probe:SetText(DIGITS[d])
        width = math.max(width, probe:GetStringWidth() or 0)
    end
    probe:Hide()
    -- A pixel of room between digits.
    c.width = math.ceil(width > 0 and width or size * 0.65) + 1
    return c
end

-- Shows `value` (no leading zeros), creating cells only when it has more digits than ever.
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

    local scorePanel = panel(hud)
    scorePanel:SetPoint("TOPRIGHT")

    local multiplierPanel = panel(hud)
    multiplierPanel:SetPoint("RIGHT", scorePanel, "LEFT", -GAP, 0)
    multiplierPanel:SetWidth(MULTIPLIER_WIDTH)
    local star = icon(multiplierPanel, STAR)
    local multiplier = text(multiplierPanel, MULTIPLIER_SIZE)
    multiplier:SetPoint("LEFT", PAD + ICON + 4, 0)

    local coinPanel = panel(hud)
    coinPanel:SetPoint("TOPRIGHT", scorePanel, "BOTTOMRIGHT", 0, -GAP)
    icon(coinPanel, COIN)

    self.hud = {
        frame = hud,
        score = counter(scorePanel, SCORE_SIZE, SCORE_DIGITS, 0),
        coins = counter(coinPanel, COINS_SIZE, COINS_DIGITS, ICON + 8),
        multiplier = multiplier,
        star = star,
    }
end

-- Where the display stands for the view's mode and size (window.lua's Layout); `top` is where
-- the view's free area starts, under a full-screen frame's title bar.
function overlay:PlaceHud(side, w, h, top)
    local hud = self.hud.frame
    hud:ClearAllPoints()
    if side then
        hud:SetScale(SIDE_SCALE)
        -- Under the buttons' row, if any; a point's offsets count in the display's own scale.
        local y = top - (self.framed and 8 or 40)
        hud:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8 / SIDE_SCALE, y / SIDE_SCALE)
    else
        hud:SetScale(1)
        -- Beside the road's far end, above the horizon, but always on the screen and under
        -- the buttons.
        local x = math.min(0.62 * h, w / 2 - 16)
        local y = math.min(0.36 * h, h / 2 + top - 48)
        hud:SetPoint("TOPRIGHT", self.frame, "CENTER", x, y)
    end
end

-- Once a frame: the numbers, redrawn only when they change (no Lua strings are built), and the
-- star's pop.
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
