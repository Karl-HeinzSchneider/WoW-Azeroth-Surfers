---@type string, AzerothSurfers
local _, app = ...
local sim = app.simulation
-- What the game shows in the middle of the view, over everything else:
-- * the status panel while a run is paused or over: the run's numbers, the difficulty, the seed
--   and a button per next action, each behind its key's cap (before a run: screens.lua);
-- * announcements in zone-text style (`Announce`);
-- * a gate's flash and its portal's pull (the vortex: wind into the portal, edges closing in).
local overlay = app.overlay

local WIDTH, PAD, ROW = 300, 28, 22
local BUTTON_WIDTH, BUTTON_HEIGHT, ACTION_ROW = 130, 22, 28
local OPTION_ROW, CHECK_SIZE, INPUT_WIDTH = 26, 24, 110
local ARROW_SIZE, DIFFICULTY_WIDTH = 26, 72
local ARROWS = { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", "Interface\\Buttons\\UI-SpellbookIcon-NextPage" }
local TRIM, TRIM_HEIGHT, TRIM_INDENT = "Interface\\Common\\UI-TooltipDivider", 8, 20
local SIDE_SCALE = 0.8
local ANNOUNCE_SECONDS, FADE_IN, FADE_OUT = 2, 0.3, 0.7
local BANNER_SIDE_SCALE = 0.5
local FLASH_ALPHA, FLASH_SECONDS = 0.85, 0.7
-- The pull, by the portal's distance from the camera (which goes through last): it builds from
-- VORTEX_FROM yards and fades over VORTEX_THROUGH after; in the last VORTEX_AROUND yards the
-- opening grows past the screen's edges.
local VORTEX_FROM, VORTEX_THROUGH, VORTEX_AROUND = 50, 14, 8
-- In screen sizes.
local VORTEX_AROUND_SIZE = 1.2
-- `approach` fades out over HUM_FADE milliseconds; `through` plays THROUGH_LEAD seconds early
-- (the teleport's whoosh builds up into it).
local HUM_FADE, THROUGH_LEAD = 1000, 0.4
local VORTEX_EDGES, VORTEX_EDGES_ALPHA = "Interface\\FullScreenTextures\\OutOfControl", 0.8
-- Radians a second, without pull and at the full pull.
local VORTEX_SPIN = { 1, 9 }
-- The wind's lines: count; from and to, length (at no and full pull) in opening sizes; head width
-- in pixels; trips a second (at no and full pull); the share of the spin they turn.
local WIND_LINES, WIND_FROM, WIND_TO = 28, 2.2, 0.15
local WIND_LENGTH, WIND_WIDTH, WIND_TRIPS, WIND_TWIST = { 0.25, 0.8 }, 3, { 0.5, 2.2 }, 0.12
-- Reused for the gradients (read only during the call).
local windTail, windHead
-- The zone text's colors: the zone's cream, a subzone's gold.
local CREAM = { 1, 0.9294, 0.7607 }
local GOLD = { 1, 0.82, 0 }

local TITLES = { paused = "Paused", over = "Run complete" }
-- By state: the action (`DoAction`), its key (a game key or the first bound key of `bindings`;
-- none: no cap), whether the key is held, and the button's text. In auto mode no key does
-- anything.
local AUTO = { act = "auto", text = "Auto mode" }
local MENU = { act = "menu", text = "Main menu" }
local ACTIONS = {
    paused = {
        { act = "pause", key = "pause", text = "Go on" },
        { act = "restart", key = "restart", hold = true, text = "Start over" },
        AUTO,
        MENU,
    },
    over = { { act = "restart", key = "restart", text = "Run again" }, AUTO, MENU },
}
local STOP = { act = "manual", text = "Stop auto mode" }
local AUTO_ACTIONS = { paused = { { act = "pause", text = "Go on" }, STOP }, over = { STOP } }

local function row(panel, name)
    local r = {}
    r.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetText(name)
    r.value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    r.value:SetJustifyH("RIGHT")
    return r
end

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

function overlay:DoAction(act)
    if act == "pause" then
        self:Action("P")
    elseif act == "restart" and not InCombatLockdown() then
        self:Restart()
    elseif act == "auto" or act == "manual" then
        self:SetAuto(act == "auto")
    elseif act == "menu" then
        self:OpenMenu()
    end
end

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
    -- The template fills its parent (setAllPoints): the panel is anchored anew and sized by its lines.
    local holder = CreateFrame("Frame", nil, f)
    self:Stack(holder, "messages")
    holder:SetSize(1, 1)
    holder:Hide()
    local panel = CreateFrame("Frame", nil, holder, "DialogBorderTemplate")
    panel:ClearAllPoints()
    panel:SetPoint("CENTER")
    panel:SetWidth(WIDTH)
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

    local difficultyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    difficultyLabel:SetText("Difficulty")
    local easier, harder = arrow(self, panel, ARROWS[1], -1), arrow(self, panel, ARROWS[2], 1)
    local difficulty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    difficulty:SetWidth(DIFFICULTY_WIDTH)
    difficulty:SetPoint("LEFT", easier, "RIGHT")
    harder:SetPoint("LEFT", difficulty, "RIGHT")
    local nextRun = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nextRun:SetText("From the next run on")

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
    -- Only a fixed seed can be edited; otherwise typing is undone, but the seed can be copied.
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

    local flash = CreateFrame("Frame", nil, f)
    self:Stack(flash, "flash")
    flash:SetAllPoints(f)
    flash:Hide()
    local glow = flash:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(flash)
    glow:SetColorTexture(1, 1, 1, 1)
    self.flash = { frame = flash, texture = glow }

    local vortex = CreateFrame("Frame", nil, f)
    self:Stack(vortex, "flash")
    vortex:SetAllPoints(f)
    vortex:Hide()
    local edges = vortex:CreateTexture(nil, "BACKGROUND")
    edges:SetAllPoints(vortex)
    edges:SetTexture(VORTEX_EDGES)
    -- Quads drawn by their corners (SetVertexOffset) from a point at the view's corner, so they
    -- can point any way.
    local lines, phases = {}, {}
    for i = 1, WIND_LINES do
        -- Scattered by a hash: a phase growing with the number would line them up in a spiral.
        local hash = math.sin(i * 12.9898) * 43758.5453
        phases[i] = hash - math.floor(hash)
        local line = vortex:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 1)
        line:SetBlendMode("ADD")
        line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        line:SetSize(1, 1)
        lines[i] = line
    end
    windTail, windHead = CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)
    self.vortex = {
        frame = vortex,
        parent = f,
        edges = edges,
        lines = lines,
        phases = phases,
        angle = 0,
        flow = 0,
    }
end

function overlay:PlaceMessages(side, h)
    local panel, banner = self.status.holder, self.banner.frame
    -- Offsets count in the frame's own scale.
    local scale = side and SIDE_SCALE or 1
    panel:SetScale(scale)
    panel:ClearAllPoints()
    panel:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.05 or 0.12) * h / scale)
    scale = side and BANNER_SIDE_SCALE or 1
    banner:SetScale(scale)
    banner:ClearAllPoints()
    banner:SetPoint("CENTER", self.frame, "CENTER", 0, (side and 0.25 or 0.3) * h / scale)
end

-- Returns where the next line starts.
function overlay:PlaceTrim(trim, y)
    local panel = self.status.panel
    trim:ClearAllPoints()
    trim:SetPoint("TOPLEFT", panel, "TOPLEFT", TRIM_INDENT, y)
    trim:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -TRIM_INDENT, y)
    return y - TRIM_HEIGHT - 6
end

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
    for i, r in ipairs(st.rows) do
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", panel, "TOPLEFT", PAD, y - ROW / 2)
        r.value:ClearAllPoints()
        r.value:SetPoint("RIGHT", panel, "TOPRIGHT", -PAD, y - ROW / 2)
        if i == 2 and s.coinTotal > 0 then
            -- 100% only with every one.
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
    if s.multiplier > 1 then
        st.rows[1].name:SetFormattedText("Score  |cffff8c1ax%d|r", s.multiplier)
    else
        st.rows[1].name:SetText("Score")
    end
    y = self:PlaceTrim(st.trims[2], y - 4)
    -- While paused, a different one than the run's is for the next run, and says so.
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
    -- White while it can be edited, gray while read-only.
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

-- Once a frame: filled again only when the state or the run changes.
function overlay:ShowStatus()
    local s, st = self.state, self.status
    if s.status == "running" and self.announced ~= s then
        self.announced = s
        -- A run from the lobby is welcomed through its portal.
        if not s.lobby then
            self:WelcomeBiome()
        end
    end
    if st.shownStatus == s.status and st.shownState == s then
        return
    end
    st.shownStatus, st.shownState = s.status, s
    -- Auto mode's pause button: Go on while paused, nothing to pause between two runs.
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

-- `small`: an optional line over it. Replaces an announcement still showing.
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

-- White when `color` is nil.
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

-- Once a frame, when the next gate (or the one just gone through) has a `vortex`: the wind
-- rushes into the opening, stronger as it nears, then spreads over the screen and fades.
function overlay:ShowVortex()
    local vortex = self.vortex
    if not vortex then
        return
    end
    local s = self.state
    local strips, looks = self.strips, self.stripLooks
    local look, ahead, transition, rim
    for i = 1, strips and #strips or 0 do
        local d = strips[i] - s.distance
        if d - self.camera.x < VORTEX_FROM and d - self.camera.x > -VORTEX_THROUGH and looks[i].vortex then
            look, ahead, transition, rim = looks[i].vortex, d, looks[i], strips[i]
            break
        end
    end
    self:PortalSounds(transition, rim, ahead and ahead - self.camera.x)
    local now = GetTime()
    local elapsed = now - (vortex.time or now)
    vortex.time = now
    if not look then
        if vortex.shown then
            vortex.frame:Hide()
            vortex.shown = false
        end
        return
    end
    if not vortex.shown then
        vortex.frame:Show()
        vortex.shown = true
    end

    local camera = self.camera.x
    local before = ahead - camera
    local pull = math.max(0, math.min(1, 1 - before / VORTEX_FROM)) ^ 1.4
    local past = math.max(0, math.min(1, -before / VORTEX_THROUGH))
    local fade = past * past * (3 - 2 * past)
    local around = math.max(0, math.min(1, 1 - before / VORTEX_AROUND))
    around = around * around * (3 - 2 * around)
    -- Also on the title, where the camera looks at the portal.
    if s.status == "running" or self.screen then
        vortex.angle = vortex.angle + elapsed * (VORTEX_SPIN[1] + (VORTEX_SPIN[2] - VORTEX_SPIN[1]) * pull)
        vortex.flow = vortex.flow + elapsed * (WIND_TRIPS[1] + (WIND_TRIPS[2] - WIND_TRIPS[1]) * pull)
    end
    -- Held where it still projects once the camera is nearly at it.
    local at = math.max(ahead, camera + VORTEX_AROUND / 2)
    local x, y, scale = self:Project(at, 0, app.shapes.Ground(at) + look.center)
    if not x then
        vortex.frame:Hide()
        vortex.shown = false
        return
    end
    local w, h = vortex.parent:GetSize()
    local size = 2 * look.radius * scale * (1 + 0.2 * pull)
    size = size + (VORTEX_AROUND_SIZE * math.max(w, h) - size) * around
    x, y = x + (w / 2 - x) * around, y + (h / 2 - y) * around
    local strength = pull * (1 - fade)
    -- Not on a screen: they would darken the whole view.
    vortex.edges:SetAlpha(self.screen and 0 or strength * VORTEX_EDGES_ALPHA)
    self:ShowWind(x, y, size, pull, strength, look.color)
end

-- Each once a gate and only while running; `through` when the portal is `before` yards ahead.
function overlay:PortalSounds(transition, rim, before)
    local vortex, s = self.vortex, self.state
    local sounds = transition and transition.sounds
    if not sounds or s.status ~= "running" then
        if vortex.hum then
            StopSound(vortex.hum, HUM_FADE)
            vortex.hum = nil
        end
        return
    end
    if vortex.soundState ~= s or vortex.soundRim ~= rim then
        vortex.soundState, vortex.soundRim, vortex.hummed, vortex.through = s, rim, false, false
    end
    local on = app.db.profile.portalSound
    if sounds.approach and not vortex.hummed then
        vortex.hummed = true
        if on then
            local _, handle = PlaySoundFile(sounds.approach, "SFX")
            vortex.hum = handle
        end
    end
    if sounds.through and not vortex.through and before < s.speed * THROUGH_LEAD then
        vortex.through = true
        if on then
            PlaySoundFile(sounds.through, "SFX")
        end
    end
end

-- The lines into the opening at (`x`, `y`), `size` across, the golden angle apart.
function overlay:ShowWind(x, y, size, pull, strength, color)
    local vortex = self.vortex
    local length = size * (WIND_LENGTH[1] + (WIND_LENGTH[2] - WIND_LENGTH[1]) * pull)
    local half = WIND_WIDTH / 2
    local r, g, b = (color[1] + 1) / 2, (color[2] + 1) / 2, (color[3] + 1) / 2
    for i, line in ipairs(vortex.lines) do
        local trip = (vortex.flow + vortex.phases[i]) % 1
        local angle = i * 2.399963 + vortex.angle * WIND_TWIST
        local ux, uy = math.cos(angle), math.sin(angle)
        local head = size * (WIND_FROM - (WIND_FROM - WIND_TO) * trip)
        local tail = head + length
        -- The tail (left of the texture) is a point.
        local tx, ty = x + ux * tail, y + uy * tail
        local hx, hy = x + ux * head, y + uy * head
        local nx, ny = -uy * half, ux * half
        -- From the 1 by 1 square at the view's corner: upper left, lower left, upper right,
        -- lower right.
        line:SetVertexOffset(1, tx, ty - 1)
        line:SetVertexOffset(2, tx, ty)
        line:SetVertexOffset(3, hx + nx - 1, hy + ny - 1)
        line:SetVertexOffset(4, hx - nx - 1, hy - ny)
        local alpha = strength * math.sin(math.pi * trip)
        windTail:SetRGBA(r, g, b, 0)
        windHead:SetRGBA(r, g, b, alpha)
        line:SetGradient("HORIZONTAL", windTail, windHead)
    end
end

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

function overlay:WelcomeBiome()
    self:Announce(self.biome.name, nil, "Welcome to")
end

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
