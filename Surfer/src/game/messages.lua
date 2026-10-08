---@type string, Surfer
local appName, app = ...
local sim = app.simulation
-- What the game says in the middle of the view, added to the view that overlay.lua creates,
-- drawn over everything else of the game (and full screen, over the rest of the UI too):
--
-- * The status panel while a run is ready to start (the start screen: the best score, Start
--   game, Auto mode, Options, Close), paused or over: a classic dialog (framed like the hotkey legend)
--   with the run's numbers (score, coins, distance, best; "New best!" after one), the
--   difficulty between page arrows (as in the addon options; while paused, for the next run),
--   its seed in a box and the seed option ("Fixed seed", as in the addon options; checked, the box
--   can be edited, otherwise only copied), and a button for each thing to do next, with the
--   key cap of the key that does the same in front of it. Trims like the legend's under the
--   title and under the numbers.
-- * Announcements: a line of big text that fades in, stays a while and fades out, like the
--   game's own zone text. `overlay:Announce(text, seconds, small)` shows one (a newer one
--   replaces it). A run's start announces its biome ("Welcome to Elwynn Forest"), as does
--   changing the biome while a run is on.
local overlay = app.overlay

local WIDTH, PAD, ROW = 300, 28, 22
-- The action rows: the button centered, the key's cap against its left end ("Hold" before a
-- held one's).
local BUTTON_WIDTH, BUTTON_HEIGHT, ACTION_ROW = 130, 22, 28
-- The seed option's rows: the checkbox, and the seed's box (as wide as the start dialog's).
local OPTION_ROW, CHECK_SIZE, INPUT_WIDTH = 26, 24, 110
-- The difficulty's row: its name between the spell book's page arrows.
local ARROW_SIZE, DIFFICULTY_WIDTH = 26, 72
local ARROWS = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Interface\\Buttons\\UI-SpellbookIcon-NextPage" }
-- The legend's header trim, as far in from the panel's sides.
local TRIM, TRIM_HEIGHT, TRIM_INDENT = "Interface\\Common\\UI-TooltipDivider", 8, 20
local SIDE_SCALE = 0.8
-- Seconds an announcement shows by default (not counting its fades), and its fades.
local ANNOUNCE_SECONDS, FADE_IN, FADE_OUT = 2, 0.3, 0.7
local BANNER_SIDE_SCALE = 0.5
-- Jumping through a gate: the screen flashes this strong in the transition's color, fading out
-- over this many seconds.
local FLASH_ALPHA, FLASH_SECONDS = 0.85, 0.7
-- The zone text's colors: the zone's cream, a subzone's gold.
local CREAM = { 1, 0.9294, 0.7607 }
local GOLD = { 1, 0.82, 0 }

local TITLES = { ready = appName, paused = "Paused", over = "Run complete" }
-- The numbers' rows (Score, Coins, Distance, Best) each state shows.
local ROWS = { ready = { false, false, false, true } }
-- What to do next, by state: what the button does (`DoAction`), the key that does the same (a
-- game key, `overlay.GAME_KEYS`, or the first bound key of `bindings`; none: no key cap),
-- whether the key is held for it, and the button's text. Auto mode (the game plays itself,
-- controls.lua) is in every one; while it is on, a paused run offers to go on (no key: the
-- keys all go to WoW) and to stop it, a finished run only to stop it.
local START = { "MOVEFORWARD", "JUMP" }
local AUTO = { act = "auto", text = "Auto mode" }
local ACTIONS = {
    ready = {
        { act = "start", bindings = START, text = "Start game" },
        AUTO,
        { act = "options", text = "Options" },
        { act = "close", text = "Close" },
    },
    paused = {
        { act = "pause", key = "pause", text = "Go on" },
        { act = "restart", key = "restart", hold = true, text = "Start over" },
        AUTO,
    },
    over = { { act = "restart", key = "restart", text = "Run again" }, AUTO },
}
local STOP = { act = "manual", text = "Stop auto mode" }
local AUTO_ACTIONS = { paused = { { act = "pause", text = "Go on" }, STOP }, over = { STOP } }

-- A row of the status panel: a name on the left, its value on the right.
local function row(panel, name)
    local r = {}
    r.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetText(name)
    r.value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    r.value:SetJustifyH("RIGHT")
    return r
end

-- An action row: "Hold" (for a held key), the key's cap and the button.
local function actionRow(o, panel)
    local r = {}
    r.hold = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.hold:SetText("Hold")
    r.cap = o.KeyCap(panel)
    r.button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    r.button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    r.button:SetScript("OnClick", function()
        o:DoAction(r.act)
    end)
    return r
end

-- A button's action: start the run, go on with it (pause again toggles), start a new one, turn
-- auto mode on or off, open the addon options, or close the game.
function overlay:DoAction(act)
    if act == "start" then
        sim.Start(self.state)
    elseif act == "pause" then
        self:Action("P")
    elseif act == "restart" and not InCombatLockdown() then
        self:Restart()
    elseif act == "auto" or act == "manual" then
        self:SetAuto(act == "auto")
    elseif act == "options" then
        app.options:Open()
    elseif act == "close" then
        self.frame:Hide()
    end
end

-- A page arrow that steps the difficulty by `step`.
local function arrow(o, panel, art, step)
    local button = CreateFrame("Button", nil, panel)
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

-- The key a button's action has, if any: a game key, or the first bound key of its bindings.
local function actionKey(o, action)
    if action.key then
        return o.GAME_KEYS[action.key]
    end
    for _, binding in ipairs(action.bindings or {}) do
        local key = GetBindingKey(binding)
        if key then
            return key
        end
    end
end

function overlay:CreateMessages(f)
    -- The panel's place; the panel, the client's dialog border template, is sized by its
    -- lines. The template fills its parent (setAllPoints), so it is anchored anew.
    local holder = CreateFrame("Frame", nil, f)
    self:Stack(holder, "messages")
    holder:SetSize(1, 1)
    holder:Hide()
    local panel = CreateFrame("Frame", nil, holder, "DialogBorderTemplate")
    panel:ClearAllPoints()
    panel:SetPoint("CENTER")
    panel:SetWidth(WIDTH)
    -- Clicks on the panel stay on it.
    panel:EnableMouse(true)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -22)
    local best = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    best:SetTextColor(0.1, 1, 0.1)
    best:SetText("New best!")
    local rows = { row(panel, "Score"), row(panel, "Coins"), row(panel, "Distance"), row(panel, "Best") }
    local trims = {}
    for i = 1, 2 do
        trims[i] = panel:CreateTexture(nil, "ARTWORK")
        trims[i]:SetTexture(TRIM)
        trims[i]:SetHeight(TRIM_HEIGHT)
    end
    local actions = {}
    for i = 1, 4 do
        actions[i] = actionRow(self, panel)
    end

    -- The difficulty, the setting `profile.difficulty` (SetDifficulty shows a change here).
    local difficultyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    difficultyLabel:SetText("Difficulty")
    local easier, harder = arrow(self, panel, ARROWS[1], -1), arrow(self, panel, ARROWS[2], 1)
    local difficulty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    difficulty:SetWidth(DIFFICULTY_WIDTH)
    difficulty:SetPoint("LEFT", easier, "RIGHT")
    harder:SetPoint("LEFT", difficulty, "RIGHT")
    -- While paused, a change waits for the next run.
    local nextRun = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nextRun:SetText("From the next run on")

    -- The seed option, the setting `profile.seed` (SetSeed shows a change here).
    local fixed = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    fixed:SetSize(CHECK_SIZE, CHECK_SIZE)
    fixed:SetScript("OnClick", function(button)
        self:SetFixedSeed(button:GetChecked())
    end)
    local fixedLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fixedLabel:SetPoint("LEFT", fixed, "RIGHT", 2, 0)
    fixedLabel:SetText("Fixed seed")
    local seedLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    seedLabel:SetText("Seed")
    -- The seed's box always shows the seed: the kept one, or this run's. Only a fixed seed can
    -- be edited; otherwise the box is read-only (typing is undone), but its text can still be
    -- selected and copied.
    local seedBox = self.NumberBox(panel)
    local function restore()
        seedBox:SetText(tostring(app.db.profile.seed or self.state.seed))
    end
    seedBox:SetScript("OnEnterPressed", seedBox.ClearFocus)
    seedBox:SetScript("OnEscapePressed", function()
        restore()
        seedBox:ClearFocus()
    end)
    seedBox:SetScript("OnTextChanged", function(_, typed)
        if typed and not app.db.profile.seed then
            restore()
        end
    end)
    -- Read-only, a click selects the seed, ready to copy.
    seedBox:SetScript("OnEditFocusGained", function()
        if not app.db.profile.seed then
            seedBox:HighlightText()
        end
    end)
    -- Taken when the box loses focus; an empty box keeps the seed.
    seedBox:SetScript("OnEditFocusLost", function()
        seedBox:HighlightText(0, 0)
        local value = tonumber(seedBox:GetText())
        if app.db.profile.seed and value and app.random.Normalize(value) ~= app.db.profile.seed then
            self:SetSeed(value)
        else
            restore()
        end
    end)
    self.status = {
        holder = holder,
        panel = panel,
        title = title,
        best = best,
        rows = rows,
        trims = trims,
        actions = actions,
        fixed = fixed,
        fixedLabel = fixedLabel,
        seedLabel = seedLabel,
        seedBox = seedBox,
        difficultyLabel = difficultyLabel,
        difficulty = difficulty,
        easier = easier,
        harder = harder,
        nextRun = nextRun,
    }

    local banner = CreateFrame("Frame", nil, f)
    self:Stack(banner, "messages")
    banner:SetSize(1, 1)
    banner:Hide()
    local small = banner:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    small:SetPoint("BOTTOM", banner, "CENTER", 0, 4)
    small:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local text = banner:CreateFontString(nil, "OVERLAY", "ZoneTextFont")
    text:SetPoint("TOP", banner, "CENTER", 0, 0)
    text:SetTextColor(CREAM[1], CREAM[2], CREAM[3])
    self.banner = { frame = banner, text = text, small = small }

    -- The flash of jumping through a gate, over the world and the twin, under the score.
    local flash = CreateFrame("Frame", nil, f)
    self:Stack(flash, "flash")
    flash:SetAllPoints(f)
    flash:Hide()
    local glow = flash:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(flash)
    glow:SetColorTexture(1, 1, 1, 1)
    self.flash = { frame = flash, texture = glow }
end

-- Where the panel and announcements stand for the view's mode and size (window.lua's Layout).
function overlay:PlaceMessages(side, h)
    local panel, banner = self.status.holder, self.banner.frame
    -- A point's offsets count in the frame's own scale.
    local scale = side and SIDE_SCALE or 1
    panel:SetScale(scale)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.05 or 0.12) * h / scale)
    scale = side and BANNER_SIDE_SCALE or 1
    banner:SetScale(scale)
    banner:ClearAllPoints()
    banner:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.25 or 0.3) * h / scale)
end

-- A trim across the panel at `y`; returns where the next line starts.
function overlay:PlaceTrim(trim, y)
    local panel = self.status.panel
    trim:ClearAllPoints()
    trim:SetPoint("TOPLEFT", panel, "TOPLEFT", TRIM_INDENT, y)
    trim:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -TRIM_INDENT, y)
    return y - TRIM_HEIGHT - 6
end

-- Fills the status panel for `status` and stacks its lines from the top.
function overlay:FillStatus(status)
    local s, st = self.state, self.status
    local panel = st.panel
    st.title:SetText(TITLES[status])
    local y = -22 - st.title:GetStringHeight() - 4
    y = self:PlaceTrim(st.trims[1], y)
    st.best:SetShown(status == "over" and s.newBest == true)
    if st.best:IsShown() then
        st.best:ClearAllPoints()
        st.best:SetPoint("TOP", 0, y)
        y = y - st.best:GetStringHeight() - 8
    end
    local values = { sim.Score(s), s.coins, math.floor(s.distance), app.db.global.bestScore }
    local rows = ROWS[status]
    for i, r in ipairs(st.rows) do
        local shown = not rows or rows[i]
        r.name:SetShown(shown)
        r.value:SetShown(shown)
        if shown then
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", panel, "TOPLEFT", PAD, y - ROW / 2)
            r.value:ClearAllPoints()
            r.value:SetPoint("RIGHT", panel, "TOPRIGHT", -PAD, y - ROW / 2)
            if i == 2 and s.coinTotal > 0 then
                -- Of the coins it came past; 100% only with every one.
                r.value:SetFormattedText(
                    "%d / %d  |cffaaaaaa%d%%|r",
                    s.coins,
                    s.coinTotal,
                    math.floor(100 * s.coins / s.coinTotal)
                )
            else
                r.value:SetText(i == 3 and string.format("%d yd", values[i]) or tostring(values[i]))
            end
            y = y - ROW
        end
    end
    -- A multiplier above 1 shows next to the score.
    if s.multiplier > 1 then
        st.rows[1].name:SetFormattedText("Score  |cffff8c1ax%d|r", s.multiplier)
    else
        st.rows[1].name:SetText("Score")
    end
    y = self:PlaceTrim(st.trims[2], y - 4)
    -- The difficulty, centered: its name between the arrows (each off at its end). While
    -- paused, a different one than the run's is for the next run, and says so.
    local chosen = sim.DIFFICULTIES[app.db.profile.difficulty] or sim.DIFFICULTIES.normal
    st.difficulty:SetText(chosen.name)
    st.easier:SetEnabled(chosen.level > 1)
    st.harder:SetEnabled(chosen.level < #sim.DIFFICULTIES)
    local labelWidth = st.difficultyLabel:GetStringWidth()
    local x = (WIDTH - labelWidth - 8 - 2 * ARROW_SIZE - DIFFICULTY_WIDTH) / 2
    st.difficultyLabel:ClearAllPoints()
    st.difficultyLabel:SetPoint("LEFT", panel, "TOPLEFT", x, y - OPTION_ROW / 2)
    st.easier:ClearAllPoints()
    st.easier:SetPoint("LEFT", panel, "TOPLEFT", x + labelWidth + 8, y - OPTION_ROW / 2)
    y = y - OPTION_ROW
    st.nextRun:SetShown(status == "paused" and chosen ~= s.difficulty)
    if st.nextRun:IsShown() then
        st.nextRun:ClearAllPoints()
        st.nextRun:SetPoint("TOP", panel, "TOP", 0, y)
        y = y - st.nextRun:GetStringHeight() - 4
    end
    -- The seed, centered: its box (white while it can be edited, gray while read-only), and the
    -- checkbox under it.
    local kept = app.db.profile.seed
    if not st.seedBox:HasFocus() then
        st.seedBox:SetText(tostring(kept or s.seed))
    end
    if kept then
        st.seedBox:SetTextColor(1, 1, 1)
    else
        st.seedBox:SetTextColor(0.6, 0.6, 0.6)
    end
    labelWidth = st.seedLabel:GetStringWidth()
    x = (WIDTH - labelWidth - 12 - INPUT_WIDTH) / 2
    st.seedLabel:ClearAllPoints()
    st.seedLabel:SetPoint("LEFT", panel, "TOPLEFT", x, y - OPTION_ROW / 2)
    st.seedBox:ClearAllPoints()
    st.seedBox:SetPoint("LEFT", panel, "TOPLEFT", x + labelWidth + 12, y - OPTION_ROW / 2)
    y = y - OPTION_ROW
    st.fixed:SetChecked(kept ~= false)
    local width = CHECK_SIZE + 2 + st.fixedLabel:GetStringWidth()
    st.fixed:ClearAllPoints()
    st.fixed:SetPoint("LEFT", panel, "TOPLEFT", (WIDTH - width) / 2, y - OPTION_ROW / 2)
    y = y - OPTION_ROW - 8
    -- Each action row: the button centered, ["Hold"] [key] against it.
    local actions = self.auto and AUTO_ACTIONS[status] or ACTIONS[status]
    for i, r in ipairs(st.actions) do
        local action = actions[i]
        local key = action and actionKey(self, action)
        r.hold:SetShown(action ~= nil and action.hold == true)
        r.cap:SetShown(key ~= nil)
        r.button:SetShown(action ~= nil)
        if action then
            r.act = action.act
            r.button:SetText(action.text)
            if key then
                self.SetKeyCap(r.cap, key)
            end
            r.button:ClearAllPoints()
            r.button:SetPoint("CENTER", panel, "TOP", 0, y - ACTION_ROW / 2)
            r.cap:ClearAllPoints()
            r.cap:SetPoint("RIGHT", r.button, "LEFT", 0, 0)
            r.hold:ClearAllPoints()
            r.hold:SetPoint("RIGHT", r.cap, "LEFT", -6, 0)
            y = y - ACTION_ROW
        end
    end
    panel:SetHeight(-y + 18)
end

-- Once a frame: the status panel for the run's state, filled again only when the state or the
-- run changes; announces a run's biome once it starts.
function overlay:ShowStatus()
    local s, st = self.state, self.status
    if s.status == "running" and self.announced ~= s then
        self.announced = s
        self:WelcomeBiome()
    end
    if st.shownStatus == s.status and st.shownState == s then
        return
    end
    st.shownStatus, st.shownState = s.status, s
    -- Auto mode's pause button (the top row's third, window.lua; SetAuto shows it anew): Go on
    -- while paused, nothing to pause between two runs.
    if self.auto then
        local pause = self.controlButtons[3]
        pause:SetText(s.status == "paused" and "Go on" or "Pause")
        pause:SetEnabled(s.status == "running" or s.status == "paused")
    end
    local shown = TITLES[s.status] ~= nil
    if shown then
        self:FillStatus(s.status)
    end
    st.holder:SetShown(shown)
end

-- Shows `text` in big letters for `seconds` (ANNOUNCE_SECONDS when left out), with an optional
-- `small` line over it; replaces an announcement still showing.
function overlay:Announce(text, seconds, small)
    local b = self.banner
    if not b then
        return
    end
    b.text:SetText(text)
    b.small:SetText(small or "")
    b.start, b.hold = GetTime(), seconds or ANNOUNCE_SECONDS
    b.frame:SetAlpha(0)
    b.frame:Show()
end

-- Flashes the screen in `color` ({ red, green, blue }, white when left out), fading out: the
-- runner jumped through a gate (UpdateZone).
function overlay:Flash(color)
    local flash = self.flash
    if not flash then
        return
    end
    color = color or { 1, 1, 1 }
    flash.texture:SetColorTexture(color[1], color[2], color[3], 1)
    flash.start = GetTime()
    flash.frame:SetAlpha(FLASH_ALPHA)
    flash.frame:Show()
end

-- Once a frame: a flash fading out.
function overlay:ShowFlash()
    local flash = self.flash
    if not flash or not flash.start then
        return
    end
    local t = GetTime() - flash.start
    if t >= FLASH_SECONDS then
        flash.start = nil
        flash.frame:Hide()
        return
    end
    flash.frame:SetAlpha(FLASH_ALPHA * (1 - t / FLASH_SECONDS))
end

-- The current biome's name, as the game names a zone you enter.
function overlay:WelcomeBiome()
    self:Announce(self.biome.name, nil, "Welcome to")
end

-- Once a frame: an announcement's fade in, hold and fade out.
function overlay:ShowBanner()
    local b = self.banner
    if not b.start then
        return
    end
    -- GetTime() is the frame's time: an announcement made this frame starts at 0, invisible.
    local t = GetTime() - b.start
    if t >= FADE_IN + b.hold + FADE_OUT then
        b.start = nil
        b.frame:Hide()
        return
    end
    local alpha
    if t < FADE_IN then
        alpha = t / FADE_IN
    elseif t < FADE_IN + b.hold then
        alpha = 1
    else
        alpha = 1 - (t - FADE_IN - b.hold) / FADE_OUT
    end
    b.frame:SetAlpha(alpha)
end
