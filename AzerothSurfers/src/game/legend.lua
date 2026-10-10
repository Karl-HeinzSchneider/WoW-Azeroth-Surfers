---@type string, AzerothSurfers
local _, app = ...
-- The hotkey legend, built like the client's input legend: a dialog panel per run state (only
-- the current one shown), rows of key caps and what they do. The keys are the player's own
-- movement bindings.
local overlay = app.overlay

local ROW_HEIGHT = 24
local INDENT = 20
-- Room between a header row and the rows under it, for the trim.
local HEADER_EXTRA = 10
-- A key cap's height, its smallest width, and the room around its text.
local KEY_HEIGHT, KEY_WIDTH, KEY_PAD = 20, 22, 6
-- Between two keys of a row, and between the keys and the text.
local KEY_GAP, LABEL_GAP = 16, 8
local SIDE_SCALE = 0.75
local KEY_CAP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local TRIM = "Interface\\Common\\UI-TooltipDivider"

-- `bindings`: the WoW bindings whose keys the row shows (at most two; `firsts`: only each
-- binding's first); `keys`: the game's own instead; `header`: a title row with trim;
-- `observed`: only while `profile.capture` is off.
local LEFT = { "TURNLEFT", "STRAFELEFT" }
local RIGHT = { "TURNRIGHT", "STRAFERIGHT" }
local JUMP = { "JUMP" }
local GROUPS = {
    running = {
        { bindings = { "MOVEFORWARD" }, text = "Run (hold)", observed = true },
        { bindings = LEFT, text = "Lane left" },
        { bindings = RIGHT, text = "Lane right" },
        { bindings = JUMP, text = "Jump" },
        { bindings = { "MOVEBACKWARD" }, text = "Duck / drop" },
        { keys = "pause", text = "Pause" },
        { keys = "restart", text = "Start over (hold)" },
    },
}

local function keyCap(parent)
    local cap = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    cap:SetBackdrop(KEY_CAP)
    cap:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    cap:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
    cap:SetHeight(KEY_HEIGHT)
    cap.text = cap:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cap.text:SetPoint("CENTER", 0, 0)
    return cap
end

-- Returns the cap's width: the same for every one-character name, wider for longer ones.
local function setKey(cap, key, text)
    text = text or GetBindingText(key) or key
    cap.text:SetText(text)
    -- Characters, not bytes: UTF-8 continuation bytes are not counted.
    local single = #text:gsub("[\128-\191]", "") == 1
    local w = single and KEY_WIDTH or math.max(KEY_WIDTH, cap.text:GetStringWidth() + 2 * KEY_PAD)
    cap:SetWidth(w)
    return w
end
overlay.KeyCap, overlay.SetKeyCap = keyCap, setKey

local function entry(parent, spec)
    local e = { spec = spec, caps = { keyCap(parent), keyCap(parent) } }
    e.slash = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    e.slash:SetText("/")
    e.label = parent:CreateFontString(nil, "OVERLAY", spec.header and "GameFontHighlight" or "GameFontNormal")
    e.label:SetJustifyH("LEFT")
    e.label:SetText(spec.text)
    return e
end

function overlay:CreateLegend(f)
    local legend = CreateFrame("Frame", nil, f)
    self:Stack(legend, "legend")
    legend:SetSize(1, 1)
    self.legend = legend
    self.legendGroups = {}
    for state, specs in pairs(GROUPS) do
        local panel = CreateFrame("Frame", nil, legend, "DialogBorderTemplate")
        -- The template fills its parent (setAllPoints); the panel is sized by its rows instead.
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT")
        panel:Hide()
        local group = { panel = panel, entries = {} }
        for i, spec in ipairs(specs) do
            group.entries[i] = entry(panel, spec)
            if spec.header then
                group.trim = panel:CreateTexture(nil, "ARTWORK")
                group.trim:SetTexture(TRIM)
                group.trim:SetHeight(8)
            end
        end
        self.legendGroups[state] = group
    end
    legend:RegisterEvent("UPDATE_BINDINGS")
    legend:SetScript("OnEvent", function()
        self.legendState = nil
    end)
end

-- Into `keys` (reused), without the game's own keys (they do something else here) or repeats.
local function bindingKeys(keys, spec)
    local game = overlay.GAME_KEYS
    for i = #keys, 1, -1 do
        keys[i] = nil
    end
    for _, binding in ipairs(spec.bindings) do
        for pass = 1, spec.firsts and 1 or 2 do
            local key = select(pass, GetBindingKey(binding))
            if key and #keys < 2 and key ~= game.pause and key ~= game.restart then
                local seen = false
                for _, k in ipairs(keys) do
                    seen = seen or k == key
                end
                if not seen then
                    keys[#keys + 1] = key
                end
            end
        end
    end
    return keys
end

-- Returns their width.
local function placeKeys(e, keys, x, y)
    local width = 0
    for i, cap in ipairs(e.caps) do
        local key = keys[i]
        cap:SetShown(key ~= nil)
        if key then
            local w = setKey(cap, key)
            if i > 1 then
                width = width + KEY_GAP
            end
            cap:ClearAllPoints()
            cap:SetPoint("TOPLEFT", x + width, y)
            width = width + w
        end
    end
    e.slash:SetShown(keys[2] ~= nil)
    if keys[2] then
        e.slash:ClearAllPoints()
        e.slash:SetPoint("CENTER", e.caps[2], "LEFT", -KEY_GAP / 2, 0)
    end
    -- An action without a key shows that it has none.
    if not keys[1] then
        local cap = e.caps[1]
        cap:Show()
        width = setKey(cap, nil, NOT_BOUND or "Not bound")
        cap:ClearAllPoints()
        cap:SetPoint("TOPLEFT", x, y)
    end
    return width
end

local keys = {}

-- The texts in one column after the widest keys, the panel sized around them.
function overlay:LayoutLegend(group)
    local game = self.GAME_KEYS
    local row, keysWidth, textWidth, headerWidth, header = 0, 0, 0, 0, false
    for _, e in ipairs(group.entries) do
        local spec = e.spec
        e.shown = not (spec.observed and self.capture)
        e.label:SetShown(e.shown)
        if not e.shown or spec.header then
            for _, cap in ipairs(e.caps) do
                cap:Hide()
            end
            e.slash:Hide()
        end
        if e.shown then
            local y = -INDENT - ROW_HEIGHT * row - (header and HEADER_EXTRA or 0)
            e.y = y
            if spec.header then
                header = true
                e.label:ClearAllPoints()
                e.label:SetPoint("TOPLEFT", INDENT, y - 3)
                headerWidth = math.max(headerWidth, e.label:GetStringWidth())
            else
                if spec.keys then
                    keys[1], keys[2] = game[spec.keys], nil
                else
                    bindingKeys(keys, spec)
                end
                keysWidth = math.max(keysWidth, placeKeys(e, keys, INDENT, y))
                textWidth = math.max(textWidth, e.label:GetStringWidth())
            end
            row = row + 1
        end
    end
    for _, e in ipairs(group.entries) do
        if e.shown and not e.spec.header then
            e.label:ClearAllPoints()
            e.label:SetPoint("LEFT", group.panel, "TOPLEFT", INDENT + keysWidth + LABEL_GAP, e.y - KEY_HEIGHT / 2)
        end
    end
    local width = 2 * INDENT + math.max(headerWidth, keysWidth + LABEL_GAP + textWidth)
    -- Without the last row's extra room, so the bottom margin matches the top.
    local height = ROW_HEIGHT * row + 2 * INDENT - (ROW_HEIGHT - KEY_HEIGHT) + (header and HEADER_EXTRA or 0)
    group.panel:SetSize(width, height)
    if group.trim then
        group.trim:ClearAllPoints()
        group.trim:SetPoint("TOPLEFT", INDENT, -INDENT - ROW_HEIGHT + 2)
        group.trim:SetPoint("TOPRIGHT", -INDENT, -INDENT - ROW_HEIGHT + 2)
    end
end

function overlay:PlaceLegend(side, top)
    local legend, scale = self.legend, side and SIDE_SCALE or 1
    legend:ClearAllPoints()
    legend:SetScale(scale)
    -- Clear of the window frame's border, and under a narrow side window's buttons. Offsets
    -- count in the legend's own scale.
    local x, y = 5, top - 5
    if self.framed then
        x, y = 12, top - 10
    elseif side then
        y = top - 40
    end
    legend:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x / scale, y / scale)
end

-- Laid out again only when the state, bindings or mode changed. None in auto mode, on the title
-- and the menu (screens.lua), and on the way into a run.
function overlay:ShowLegend()
    local state = app.db.profile.legend and not self.auto and (self.screen or self.state.status) or "off"
    if self.legendState == state then
        return
    end
    self.legendState = state
    for name, group in pairs(self.legendGroups) do
        if name == state then
            self:LayoutLegend(group)
            group.panel:Show()
        else
            group.panel:Hide()
        end
    end
end
